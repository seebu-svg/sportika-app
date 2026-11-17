import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sportika/app/env.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/core/data/profile_directory.dart';
import 'package:sportika/core/data/profile_photo.dart';
import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/features/auth/services/authentication_service.dart';
import 'package:sportika/features/auth/services/supabase_auth_errors.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/profile_setup.dart';

/// The account directory when identity lives in PostgreSQL instead of on the
/// device.
///
/// Only session and profile reads and writes come from here. Games, teams,
/// tournaments, fixtures and scorecards are still served by
/// [LocalSportikaRepository], which is why the two are paired: this class owns
/// one [Account] and delegates everything derived from match data back to the
/// device store.
///
/// Three invariants make the rest of the app work unchanged:
///
/// * `Account.id` is `auth.users.id`, so a verified session names the row it
///   reads without a lookup table.
/// * the client never names the row it writes: `complete_profile_setup` derives
///   the owner from `auth.uid()`, and profile updates are filtered to the
///   signed-in id by row level security.
/// * `accounts` is the signed-in member plus a bounded read of the public
///   profile directory, so an opponent in a scoreboard has a name and a face.
///   It is capped at [ProfileDirectory.rowLimit] rows and never includes private
///   details.
class SupabaseAccountRepository extends ChangeNotifier
    implements AccountRepository {
  SupabaseAccountRepository({
    required SupabaseClient client,
    required LocalSportikaRepository device,
    // A named parameter cannot be a private initializing formal, so both fields
    // are assigned from the matching parameter below.
    // ignore: prefer_initializing_formals
  }) : _client = client,
       // ignore: prefer_initializing_formals
       _device = device,
       // ignore: prefer_initializing_formals
       _directory = ProfileDirectory(client);

  final SupabaseClient _client;

  /// The other members' public cards, read in one bounded query alongside the
  /// profile. Scoreboards, rosters and team invitations all name people who are
  /// not the signed-in member.
  final ProfileDirectory _directory;

  /// The same directory, for the team module: a roster names players, and two
  /// caches would let the two screens disagree about who exists.
  ProfileDirectory get directory => _directory;

  /// Owner of everything that is not identity: fixtures, teams, scorecards and
  /// the device-level onboarding flag.
  final LocalSportikaRepository _device;

  Account? _account;
  bool _disposed = false;

  /// Account settings keys ('reminders', 'invites', 'publicProfile') mapped to
  /// their row columns. Keeping the mapping here means the settings screen does
  /// not have to know the schema.
  static const Map<String, String> _preferenceColumns = <String, String>{
    'reminders': 'reminders',
    'invites': 'invites',
    'publicProfile': 'public_profile',
  };

  final Map<String, bool> _preferences = <String, bool>{};

  /// One round trip per hydrate: the public card, the private details and the
  /// preferred sports. Selecting them separately would let a reload land between
  /// rows and show a profile that never existed as a whole.
  static const String _profileColumns =
      'id, username, display_name, bio, city, avatar_preset, avatar_url, '
      'play_style, profile_setup_complete, '
      'profiles_private(date_of_birth, gender), '
      'profile_sports(sport_key, level, position), '
      'user_preferences(reminders, invites, public_profile)';

  // ── Session ────────────────────────────────────────────────────────────

  /// There is no document to decode before the first frame: the rows arrive with
  /// the session, so the shell is never held behind a disk read.
  @override
  bool get ready => true;

  /// Device-level, exactly as on the local store: it survives signing out.
  @override
  bool get onboardingSeen => _device.onboardingSeen;

  @override
  bool get isSignedIn => _account != null;

  @override
  Account? get currentAccount => _account;

  /// The signed-in member first, then the public directory.
  @override
  List<Account> get accounts {
    final me = _account;
    if (me == null) return const <Account>[];
    return <Account>[me, ..._directory.accounts];
  }

  /// Report the profile the session belongs to, and nothing else.
  ///
  /// Roles are vestigial metadata for local compatibility; the schema has no
  /// role column and permission is expressed by ownership per object, so a
  /// server-backed account holds none.
  @override
  bool hasRole(UserRole role) => false;

  /// Every signed-in member may organize. This is the universal-account rule.
  @override
  bool get canOrganize => isSignedIn;

  /// Own account first, then the directory. An id the directory has not loaded
  /// yet still resolves to null rather than to a wrong player.
  @override
  Account? accountById(String? id) {
    final me = _account;
    if (me != null && me.id == id) return me;
    return _directory.byId(id);
  }

  @override
  Account? accountByEmail(String email) {
    final needle = email.trim().toLowerCase();
    final me = _account;
    if (me == null || me.email.toLowerCase() != needle) return null;
    return me;
  }

  @override
  Future<void> hydrateAccount(String accountId) async {
    final user = _client.auth.currentUser;
    if (user == null || user.id != accountId) {
      _setAccount(null);
      throw const AuthenticationException(
        'Your session could not be verified. Please sign in again.',
      );
    }

    Map<String, dynamic>? row;
    try {
      row = await _client
          .from('profiles')
          .select(_profileColumns)
          .eq('id', accountId)
          .maybeSingle();
    } catch (error) {
      // A missing row is not an error here: the signup trigger creates it, and
      // the message below tells the member what to do if it somehow did not.
      if (error is PostgrestException && error.code == 'PGRST116') {
        row = null;
      } else {
        _setAccount(null);
        throw mapProfileError(error);
      }
    }

    if (row == null) {
      _setAccount(null);
      throw const AuthenticationException(
        'Your account profile could not be loaded. Please try again.',
      );
    }

    final account = _accountFromRow(row, user.email ?? '');
    _adoptPreferences(_firstEmbedded(row['user_preferences']));
    _setAccount(account);

    // The opponents a scoreboard has to name. Read after the own row so a slow
    // or denied directory can never delay or replace the session's profile.
    await _directory.load(exceptAccountId: accountId);

    // A verified session means this device already carried the member through
    // onboarding. The flag only drives the carousel, so it must not replay after
    // a sign-out — the signup trigger creates the row, not this class, so there
    // is no createAccount call to carry the flag for a server-backed build.
    if (!_device.onboardingSeen) {
      try {
        await _device.markOnboardingSeen();
      } catch (_) {
        // A device that cannot record the flag would only replay the carousel
        // later; it must never block a verified sign-in.
      }
    }
  }

  @override
  Future<void> signIn(String accountId) async {
    if (_account?.id != accountId) await hydrateAccount(accountId);
    _setAccount(_account);
  }

  /// Local sign-out only. Clearing the SDK credentials is the authentication
  /// service's job, and it runs before this.
  @override
  Future<void> signOut() async {
    if (_account == null) return;
    _directory.clear();
    _setAccount(null);
  }

  @override
  Future<void> markOnboardingSeen() async {
    await _device.markOnboardingSeen();
    _notify();
  }

  /// The demo world only exists on the device, so resettable data here means
  /// re-reading the member's own rows.
  @override
  Future<void> resetDemoData() => reload();

  /// Wipes this device: the cached document, the onboarding flag and the
  /// picture files. The member's rows on the server are untouched.
  @override
  Future<void> clearLocalData() async {
    await _device.clearLocalData();
    _setAccount(null);
  }

  @override
  String? takeStorageNotice() => _device.takeStorageNotice();

  /// Never reached from the app: the signup trigger creates the profile row, and
  /// `AuthenticationService.register` owns that call.
  @override
  Future<Account> createAccount({
    required String displayName,
    required String email,
    required String city,
    required AccountIntent intent,
  }) {
    throw UnsupportedError(
      'Accounts are created by the authentication service, not the repository.',
    );
  }

  @override
  Future<void> completeProfileSetup({
    required String displayName,
    required String handle,
    required String bio,
    required String city,
    required Set<Sport> sports,
    required Map<String, PlayingLevel> levels,
    required PlayStyle playStyle,
    required String avatar,
    String? email,
    DateTime? dateOfBirth,
    ProfileGender? gender,
    Map<String, String>? playingPositions,
    bool playingPreferencesSkipped = false,
  }) async {
    final current = _account;
    if (current == null) {
      throw const AuthenticationException(
        'Sign in before saving your profile.',
      );
    }

    // The RPC requires a date of birth, and the form already refuses to move on
    // without one; this only catches a draft that lost it.
    final birth = dateOfBirth ?? current.dateOfBirth;
    if (birth == null) {
      throw const AuthenticationException(
        'Enter your date of birth as DD/MM/YYYY.',
        field: 'birthDate',
      );
    }

    // A skipped preference step means "no level, no position" rather than a
    // default, so the member's decline survives the round trip.
    final payload = <Map<String, dynamic>>[
      for (final sport in sports)
        <String, dynamic>{
          'sport_key': sport.key,
          'level': playingPreferencesSkipped ? null : levels[sport.key]?.key,
          'position': playingPreferencesSkipped
              ? null
              : playingPositions?[sport.key],
        },
    ];

    try {
      await _client.rpc(
        'complete_profile_setup',
        params: <String, dynamic>{
          'p_display_name': displayName.trim(),
          'p_username': normalizeProfileHandle(handle),
          'p_city': city.trim(),
          'p_bio': bio.trim(),
          'p_date_of_birth': _dateOnly(birth),
          'p_gender': gender == null ? null : profileGenderColumn(gender),
          'p_play_style': playStyle.key,
          'p_avatar_preset': avatar,
          'p_avatar_url': current.photoUrl,
          'p_terms_version': AppEnv.termsVersion,
          'p_sports': payload,
        },
      );
    } catch (error) {
      throw mapProfileError(error);
    }

    // An address change is an identity change: GoTrue mails the new address and
    // only applies it once it is confirmed, so the profile is already saved and
    // the account keeps its current address until then.
    if (email != null &&
        email.trim().isNotEmpty &&
        email.trim().toLowerCase() != current.email.toLowerCase()) {
      try {
        await _client.auth.updateUser(UserAttributes(email: email.trim()));
      } catch (error) {
        throw mapAuthError(error);
      }
    }

    await hydrateAccount(current.id);
  }

  @override
  Future<void> reload() async {
    final id = _account?.id ?? _client.auth.currentUser?.id;
    if (id == null) return;
    try {
      await hydrateAccount(id);
    } on AuthenticationException {
      // Keep the last good snapshot: the session flow owns signing out, and a
      // failed pull-to-refresh must not empty the screen.
    }
  }

  // ── Profile ────────────────────────────────────────────────────────────

  @override
  Future<void> updateProfile({
    String? displayName,
    String? city,
    String? email,
  }) async {
    // `email` is not writable here: it belongs to `auth.users` and changes only
    // through the confirmation flow in completeProfileSetup.
    //
    // There is deliberately no direct write for display_name/city either. The
    // profiles table grants members SELECT only, and the one write path that
    // exists server-side (update_profile_details) replaces bio, date of birth
    // and gender wholesale, so a name-only call through it would wipe fields
    // this signature cannot carry. Personal-detail edits belong to
    // ProfileModuleRepository.updatePersonalDetails, which is what the
    // personal-information screen uses; the device store keeps its own direct
    // implementation for demo mode.
    throw UnsupportedError(
      'Supabase profile edits go through ProfileModuleRepository '
      '(updatePersonalDetails), not the account repository.',
    );
  }

  /// Uploads the picture the photo flow already cropped and then points the
  /// profile at it.
  ///
  /// The local file the caller wrote stays as the fast path; the public URL is
  /// what a fresh install reads back. If the upload or the write fails the
  /// account is left exactly as it was, so the caller can discard the new file.
  @override
  Future<void> setProfilePhoto(String? path) async {
    final current = _account;
    if (current == null) {
      throw const PhotoException(
        PhotoFailure.notSignedIn,
        'Sign in before changing your profile picture.',
      );
    }

    final wanted = (path == null || path.isEmpty) ? null : path;
    final previousUrl = current.photoUrl;

    String? uploadedUrl;
    String? uploadedPath;
    if (wanted != null) {
      Uint8List bytes;
      try {
        bytes = await File(wanted).readAsBytes();
      } on FileSystemException {
        throw const PhotoException(
          PhotoFailure.unreadable,
          'That picture could not be read back from this device. Try again.',
        );
      }
      try {
        // Owner folder: the storage policy only accepts a write under the
        // member's own id, so this path is also the permission.
        final objectPath =
            '${current.id}/avatar-${DateTime.now().microsecondsSinceEpoch}.png';
        final bucket = _client.storage.from(AppEnv.avatarBucket);
        await bucket.uploadBinary(
          objectPath,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/png'),
        );
        uploadedUrl = bucket.getPublicUrl(objectPath);
        uploadedPath = objectPath;
      } catch (_) {
        throw const PhotoException(
          PhotoFailure.storage,
          'The picture could not be uploaded. Check your connection and try '
          'again.',
        );
      }
    }

    try {
      await _client
          .from('profiles')
          .update(<String, dynamic>{
            'avatar_url': uploadedUrl,
            'avatar_path': uploadedPath,
          })
          .eq('id', current.id);
    } catch (_) {
      // The upload already happened, so it must not outlive the failed write.
      if (uploadedUrl != null) await _removeAvatarObject(uploadedUrl);
      throw const PhotoException(
        PhotoFailure.persistence,
        'Your picture was not saved, so your previous avatar is still in place.',
      );
    }

    current
      ..photoPath = wanted
      ..photoUrl = uploadedUrl;
    _notify();

    if (previousUrl != null && previousUrl != uploadedUrl) {
      await _removeAvatarObject(previousUrl);
    }
  }

  /// Match-derived stats stay on the device store, which is where fixtures and
  /// entries still live.
  @override
  List<Sport> sportsPlayedBy(String accountId) =>
      _device.sportsPlayedBy(accountId);

  @override
  List<Fixture> appearancesOf(String accountId) =>
      _device.appearancesOf(accountId);

  @override
  List<Fixture> officialMatchesPlayed() => _device.officialMatchesPlayed();

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ── Mapping ────────────────────────────────────────────────────────────

  Account _accountFromRow(Map<String, dynamic> row, String email) {
    final priv = _firstEmbedded(row['profiles_private']);
    final sports = <Sport>{};
    final levels = <String, PlayingLevel>{};
    final positions = <String, String>{};

    for (final entry in _embeddedList(row['profile_sports'])) {
      final key = entry['sport_key'] as String?;
      if (key == null) continue;
      final sport = Sport.values.where((s) => s.key == key).firstOrNull;
      // An unknown key means the reference table grew ahead of this build.
      // Ignoring it is better than drawing a wrong sport.
      if (sport == null) continue;
      sports.add(sport);

      final level = entry['level'] as String?;
      if (level != null && level.isNotEmpty) {
        levels[key] = PlayingLevelX.fromKey(level);
      }
      final position = entry['position'] as String?;
      if (position != null && position.isNotEmpty) {
        positions[key] = position;
      }
    }

    final genderColumn = priv?['gender'] as String?;

    return Account(
      id: row['id'] as String,
      displayName: (row['display_name'] as String? ?? '').trim(),
      // The address is identity, so it comes from the session user rather than
      // from a column a later email change would not have updated yet.
      email: email,
      city: row['city'] as String? ?? '',
      roles: const <UserRole>[],
      handle: row['username'] as String? ?? '',
      bio: row['bio'] as String? ?? '',
      dateOfBirth: DateTime.tryParse(priv?['date_of_birth'] as String? ?? ''),
      gender: profileGenderFromColumn(genderColumn),
      playingPositions: positions,
      // No level on any sport is what the skipped step looks like after a round
      // trip, so the review screen can say so again.
      playingPreferencesSkipped: sports.isNotEmpty && levels.isEmpty,
      sports: sports,
      levels: levels,
      playStyle: PlayStyleX.fromKey(row['play_style'] as String?),
      avatar: row['avatar_preset'] as String? ?? 'midnight',
      photoUrl: row['avatar_url'] as String?,
      setupComplete: row['profile_setup_complete'] as bool? ?? false,
    );
  }

  /// PostgREST returns a to-one embed as an object and a to-many embed as an
  /// array depending on which side of the relationship it is reading from, so
  /// both shapes are accepted.
  static Map<String, dynamic>? _firstEmbedded(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty) {
      final first = value.first;
      if (first is Map<String, dynamic>) return first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    return null;
  }

  static Iterable<Map<String, dynamic>> _embeddedList(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value.whereType<Map>().map(Map<String, dynamic>.from);
  }

  /// The enum names the UI uses are camelCase; the column uses snake_case.
  /// Account settings are part of the same member record, so they are read with
  /// the profile and written one row at a time.
  @override
  Map<String, bool> get preferences =>
      Map<String, bool>.unmodifiable(_preferences);

  @override
  bool preference(String key, {bool fallback = true}) =>
      _preferences[key] ?? fallback;

  /// Flips the switch immediately and puts the old value back if the server
  /// refuses, so a setting never shows as saved when it was not.
  @override
  void setPreference(String key, bool value) {
    final column = _preferenceColumns[key];
    final account = _account;
    if (column == null || account == null) return;
    final previous = _preferences[key];
    _preferences[key] = value;
    _notify();
    unawaited(_savePreference(account.id, column, key, value, previous));
  }

  Future<void> _savePreference(
    String profileId,
    String column,
    String key,
    bool value,
    bool? previous,
  ) async {
    try {
      await _client.from('user_preferences').upsert(<String, dynamic>{
        'profile_id': profileId,
        column: value,
      }, onConflict: 'profile_id');
    } catch (_) {
      // The optimistic value must not outlive a refused write.
      if (previous == null) {
        _preferences.remove(key);
      } else {
        _preferences[key] = previous;
      }
      _notify();
    }
  }

  void _adoptPreferences(Map<String, dynamic>? row) {
    _preferences.clear();
    if (row == null) return;
    for (final entry in _preferenceColumns.entries) {
      final value = row[entry.value];
      if (value is bool) _preferences[entry.key] = value;
    }
  }

  static String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  /// Storage paths are not stored alongside the URL, so the object key is read
  /// back out of it. A URL this build did not produce is left alone.
  Future<void> _removeAvatarObject(String url) async {
    final marker = '/object/public/${AppEnv.avatarBucket}/';
    final at = url.indexOf(marker);
    if (at < 0) return;
    final objectPath = url.substring(at + marker.length);
    if (objectPath.isEmpty) return;
    try {
      await _client.storage.from(AppEnv.avatarBucket).remove([objectPath]);
    } catch (_) {
      // An orphaned object is not worth failing the member's action over; the
      // next replace sweeps a different key and support can clear the folder.
    }
  }

  void _setAccount(Account? account) {
    _account = account;
    if (account == null) _preferences.clear();
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }
}
