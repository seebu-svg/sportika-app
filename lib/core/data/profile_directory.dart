import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/onboarding.dart';

/// A bounded read of the public profile directory.
///
/// Scoreboards, rosters and player search all name the *other* side of a
/// contest. Row level security in migration 0003 lets any signed-in member read
/// a public profile, but [SupabaseAccountRepository] only ever hydrates the
/// signed-in one, so every opponent used to render as an unknown player.
///
/// This is the fix, with two deliberate limits:
///
/// * it reads at most [rowLimit] rows in one query, because the directory is a
///   convenience for the screens on screen, not a people search engine;
/// * a failure here never fails the session. A member with no directory still
///   signs in and still sees their own profile; only the other names fall back
///   to whatever the row already carries.
///
/// The signed-in account is deliberately excluded from [accounts]: whoever owns
/// the session stays authoritative in [SupabaseAccountRepository] so an
/// unsaved edit cannot be overwritten by a stale directory row.
class ProfileDirectory {
  ProfileDirectory(this._client);

  final SupabaseClient _client;

  /// Rows read per refresh. Karachi's whole player base fits; anything beyond
  /// this is a search, and search is the profile module's job.
  static const int rowLimit = 200;

  /// The columns a card needs. Private details (date of birth, gender) are not
  /// selected: they are readable only by their owner.
  static const String _columns =
      'id, username, display_name, bio, city, avatar_preset, avatar_url, '
      'play_style, profile_setup_complete, '
      'profile_sports(sport_key, level, position)';

  Map<String, Account> _byId = const <String, Account>{};

  /// False until the first successful load, so a screen can tell "nobody else
  /// exists" from "the directory has not been read yet".
  bool get loaded => _byId.isNotEmpty;

  bool get loading => _loading;
  bool _loading = false;

  String? _lastError;

  /// Why the last read failed, or null. Kept for the diagnostics a support
  /// screen shows; the UI degrades silently by design.
  String? get lastError => _lastError;

  /// Every directory member except the signed-in one.
  List<Account> get accounts => _byId.values.toList()
    ..sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );

  Account? byId(String? id) => id == null ? null : _byId[id];

  /// Reads the directory. Safe to call again on every profile reload.
  Future<void> load({String? exceptAccountId}) async {
    if (_client.auth.currentUser == null) return;
    _loading = true;
    try {
      final rows = await _client
          .from('profiles')
          .select(_columns)
          .order('profile_setup_complete', ascending: false)
          .order('display_name')
          .limit(rowLimit);
      final next = <String, Account>{};
      for (final row in rows.cast<Map<String, dynamic>>()) {
        final id = row['id'] as String?;
        if (id == null || id == exceptAccountId) continue;
        next[id] = _accountFromRow(row);
      }
      _byId = next;
      _lastError = null;
    } catch (error) {
      // A directory that will not load is not a reason to lose the session, but
      // it must not look like an empty league either.
      _lastError = 'Player directory could not be refreshed: $error';
      debugPrint('Sportika profile directory: $error');
    } finally {
      _loading = false;
    }
  }

  /// Drops everything. Called on sign-out so the next member never sees the
  /// previous member's cached opponents.
  void clear() {
    _byId = const <String, Account>{};
    _lastError = null;
  }

  Account _accountFromRow(Map<String, dynamic> row) {
    final sports = <Sport>{};
    final levels = <String, PlayingLevel>{};
    final positions = <String, String>{};
    for (final entry in _embeddedList(row['profile_sports'])) {
      final key = entry['sport_key'] as String?;
      if (key == null) continue;
      final sport = SportX.fromKey(key);
      sports.add(sport);
      levels[sport.key] = PlayingLevelX.fromKey(entry['level'] as String?);
      final position = entry['position'] as String?;
      if (position != null && position.isNotEmpty) {
        positions[sport.key] = position;
      }
    }

    return Account(
      id: row['id'] as String,
      displayName: row['display_name'] as String? ?? '',
      // The directory cannot read an email; the handle is the public name.
      email: '',
      city: row['city'] as String? ?? '',
      roles: const <UserRole>[],
      handle: row['username'] as String? ?? '',
      bio: row['bio'] as String? ?? '',
      playingPositions: positions,
      sports: sports,
      levels: levels,
      playStyle: PlayStyleX.fromKey(row['play_style'] as String?),
      avatar: row['avatar_preset'] as String? ?? 'midnight',
      photoUrl: row['avatar_url'] as String?,
      setupComplete: row['profile_setup_complete'] as bool? ?? false,
    );
  }

  static List<Map<String, dynamic>> _embeddedList(Object? value) =>
      (value as List<dynamic>? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
}
