import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/core/data/supabase_identity_document_store.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/identity_document.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/profile_module.dart';
import 'package:sportika/shared/models/profile_setup.dart';

/// The Me module against PostgreSQL.
///
/// Every write goes through a security-definer function that derives the subject
/// from `auth.uid()`. Reads use the owner's own row, which RLS already scopes, so
/// no method accepts an account id from the caller.
///
/// [accounts] is the session's account directory. After a write it is reloaded so
/// the header, drawer and every other screen see the same name and handle without
/// a second source of truth.
class SupabaseProfileModuleRepository extends ChangeNotifier
    implements ProfileModuleRepository {
  SupabaseProfileModuleRepository({
    required SupabaseClient client,
    AccountRepository? accounts,
    // A named parameter cannot be a private initializing formal, so both fields
    // are assigned from the matching parameter below.
    // ignore: prefer_initializing_formals
  }) : _client = client,
       // ignore: prefer_initializing_formals
       _accounts = accounts;

  final SupabaseClient _client;
  final AccountRepository? _accounts;

  /// One round trip for the whole owned record. Selecting the parts separately
  /// would let a reload land between rows and paint a profile that never existed
  /// as a whole.
  static const String _select =
      'id, username, display_name, bio, city, avatar_preset, avatar_url, '
      'play_style, profile_setup_complete, '
      'profiles_private(date_of_birth, gender, height_cm, weight_kg, '
      'dominant_hand, dominant_foot, preferred_jersey), '
      'profile_sports(sport_key, level, position), '
      'profile_identity_documents(document_type, document_number, front_path, '
      'back_path, submitted_at)';

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const ProfileModuleException(
        'Sign in again to manage your profile.',
        code: '28000',
      );
    }
    return id;
  }

  void _requireSession() {
    if (_client.auth.currentUser == null) {
      throw const ProfileModuleException(
        'Sign in again to manage your profile.',
        code: '28000',
      );
    }
  }

  @override
  bool get supportsIdentityDocuments => true;

  // ── Read ────────────────────────────────────────────────────────────────

  @override
  Future<ProfileModuleSnapshot> load() async {
    final uid = _uid;
    Map<String, dynamic>? row;
    try {
      row = await _client
          .from('profiles')
          .select(_select)
          .eq('id', uid)
          .maybeSingle();
    } catch (error) {
      throw _mapError(error, fallback: 'Your profile could not be loaded.');
    }
    if (row == null) {
      throw const ProfileModuleException(
        'Your profile could not be found. Sign out and back in to repair it.',
      );
    }
    return _snapshotFromRow(row);
  }

  @override
  Future<List<ScorerAssignment>> loadAssignments() async {
    final uid = _uid;
    try {
      final rows = await _client
          .from('official_scorer_assignments')
          .select(
            'id, tournament_id, fixture_id, scorer_profile_id, authorized_by, '
            'status, created_at',
          )
          .or('scorer_profile_id.eq.$uid,authorized_by.eq.$uid')
          .order('created_at', ascending: false);
      return rows.map(ScorerAssignment.fromRow).toList();
    } catch (error) {
      throw _mapError(
        error,
        fallback: 'Your scorer assignments could not be loaded.',
      );
    }
  }

  @override
  Future<List<ProfileSummary>> searchPlayers(String query) async {
    final uid = _uid;
    final term = query.trim();
    try {
      var builder = _client
          .from('profiles')
          .select('id, display_name, username, city, avatar_url')
          .neq('id', uid);
      if (term.isNotEmpty) {
        builder = builder.ilike('display_name', '%$term%');
      }
      final rows = await builder.order('display_name').limit(20);
      return rows
          .map(ProfileSummary.fromRow)
          .where(
            (p) => p.displayName.trim().isNotEmpty || p.username.isNotEmpty,
          )
          .toList();
    } catch (error) {
      throw _mapError(error, fallback: 'Players could not be loaded.');
    }
  }

  // ── Writes ──────────────────────────────────────────────────────────────

  @override
  Future<void> savePersonalInformation({
    required String displayName,
    required String city,
    required String bio,
    required DateTime dateOfBirth,
    required ProfileGender? gender,
    required PlayStyle playStyle,
  }) async {
    _requireSession();
    try {
      await _client.rpc(
        'update_profile_details',
        params: <String, dynamic>{
          'p_display_name': displayName.trim(),
          'p_city': city.trim(),
          'p_bio': bio.trim(),
          'p_date_of_birth': _dateOnly(dateOfBirth),
          'p_gender': profileGenderColumn(gender),
          'p_play_style': playStyle.key,
        },
      );
    } catch (error) {
      throw _mapError(
        error,
        fallback: 'Your personal information could not be saved.',
      );
    }
    await _accounts?.reload();
    notifyListeners();
  }

  @override
  Future<void> changeUsername(String username) async {
    _requireSession();
    try {
      await _client.rpc(
        'change_profile_username',
        params: {'p_username': normalizeProfileHandle(username)},
      );
    } catch (error) {
      throw _mapError(error, fallback: 'That username could not be saved.');
    }
    await _accounts?.reload();
    notifyListeners();
  }

  @override
  Future<void> saveAthleteDetails({
    required int? heightCm,
    required double? weightKg,
    required ProfileSide? dominantHand,
    required ProfileSide? dominantFoot,
    required int? preferredJersey,
  }) async {
    _requireSession();
    try {
      await _client.rpc(
        'update_profile_athlete_details',
        params: <String, dynamic>{
          'p_height_cm': heightCm,
          'p_weight_kg': weightKg,
          'p_dominant_hand': dominantHand?.key,
          'p_dominant_foot': dominantFoot?.key,
          'p_preferred_jersey': preferredJersey,
        },
      );
    } catch (error) {
      throw _mapError(
        error,
        fallback: 'Your athlete details could not be saved.',
      );
    }
    notifyListeners();
  }

  @override
  Future<void> saveSportsPreferences(
    List<ProfileSportPreference> sports,
  ) async {
    _requireSession();
    if (sports.isEmpty) {
      throw const ProfileModuleException(
        'Choose at least one preferred sport.',
        code: 'sports_required',
      );
    }
    try {
      await _client.rpc(
        'replace_profile_sports',
        params: {
          'p_sports': [for (final sport in sports) sport.toRow()],
        },
      );
    } catch (error) {
      throw _mapError(
        error,
        fallback: 'Your sports preferences could not be saved.',
      );
    }
    await _accounts?.reload();
    notifyListeners();
  }

  @override
  Future<void> submitIdentityDocument(IdentitySubmission submission) async {
    final uid = _uid;
    try {
      await SupabaseIdentityDocumentStore(_client)
          .save(accountId: uid, submission: submission);
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw const ProfileModuleException(
          'You already have identity documents on file. Withdraw them before '
          'submitting again.',
          code: '23505',
        );
      }
      throw _mapError(
        error,
        fallback: 'Your documents could not be saved. Nothing was uploaded.',
      );
    } on FormatException catch (error) {
      throw ProfileModuleException(error.message);
    }
    notifyListeners();
  }

  @override
  Future<void> deleteIdentityDocument() async {
    final uid = _uid;
    Map<String, dynamic>? row;
    try {
      row = await _client
          .from('profile_identity_documents')
          .select('front_path, back_path')
          .eq('profile_id', uid)
          .maybeSingle();
    } catch (error) {
      throw _mapError(error, fallback: 'Your documents could not be loaded.');
    }
    if (row == null) return;

    final paths = [
      row['front_path'],
      row['back_path'],
    ].whereType<String>().toList();
    try {
      await _client
          .from('profile_identity_documents')
          .delete()
          .eq('profile_id', uid);
    } catch (error) {
      throw _mapError(
        error,
        fallback: 'Your documents could not be withdrawn.',
      );
    }
    if (paths.isNotEmpty) {
      try {
        await _client.storage
            .from(SupabaseIdentityDocumentStore.bucket)
            .remove(paths);
      } catch (_) {
        // An orphaned private object is not worth failing the withdrawal over;
        // the row that pointed at it is already gone.
      }
    }
    notifyListeners();
  }

  @override
  Future<void> claimOrganizer(String tournamentId) async {
    _requireSession();
    try {
      await _client.rpc(
        'claim_tournament_organizer',
        params: {'p_tournament_id': tournamentId},
      );
    } catch (error) {
      throw _mapError(
        error,
        fallback: 'This tournament is already claimed by another organizer.',
      );
    }
  }

  @override
  Future<ScorerAssignment> assignScorer({
    required String tournamentId,
    required String fixtureId,
    required String scorerId,
  }) async {
    _requireSession();
    try {
      final row = await _client.rpc(
        'assign_official_scorer',
        params: {
          'p_tournament_id': tournamentId,
          'p_fixture_id': fixtureId,
          'p_scorer_id': scorerId,
        },
      );
      notifyListeners();
      return ScorerAssignment.fromRow(Map<String, dynamic>.from(row as Map));
    } catch (error) {
      throw _mapError(
        error,
        fallback: 'The scorer could not be assigned to this match.',
      );
    }
  }

  @override
  Future<void> revokeScorer({
    required String tournamentId,
    required String fixtureId,
    required String scorerId,
  }) async {
    _requireSession();
    try {
      await _client.rpc(
        'revoke_official_scorer',
        params: {'p_fixture_id': fixtureId, 'p_scorer_id': scorerId},
      );
    } catch (error) {
      throw _mapError(error, fallback: 'The assignment could not be revoked.');
    }
    notifyListeners();
  }

  @override
  Future<void> respondToAssignment({
    required String assignmentId,
    required bool accept,
  }) async {
    _requireSession();
    try {
      await _client.rpc(
        'respond_to_scorer_assignment',
        params: {'p_assignment_id': assignmentId, 'p_accept': accept},
      );
    } catch (error) {
      throw _mapError(error, fallback: 'Your reply could not be saved.');
    }
    notifyListeners();
  }

  // ── Mapping ─────────────────────────────────────────────────────────────

  ProfileModuleSnapshot _snapshotFromRow(Map<String, dynamic> row) {
    final priv = _firstEmbedded(row['profiles_private']);
    final identity = _firstEmbedded(row['profile_identity_documents']);

    final sports = <ProfileSportPreference>[];
    for (final entry in _embeddedList(row['profile_sports'])) {
      final sport = Sport.values
          .where((s) => s.key == entry['sport_key'])
          .firstOrNull;
      // A key this build does not know means the reference table grew ahead of
      // the app; skipping is better than drawing the wrong sport.
      if (sport == null) continue;
      final levelKey = entry['level'] as String?;
      sports.add(
        ProfileSportPreference(
          sport,
          level: levelKey == null || levelKey.isEmpty
              ? null
              : PlayingLevel.values.where((l) => l.key == levelKey).firstOrNull,
          position: (entry['position'] as String?)?.trim().isEmpty == true
              ? null
              : entry['position'] as String?,
        ),
      );
    }
    sports.sort((a, b) => a.sport.index.compareTo(b.sport.index));

    final kindKey = identity?['document_type'] as String?;
    final submittedAt = DateTime.tryParse(
      identity?['submitted_at'] as String? ?? '',
    );

    return ProfileModuleSnapshot(
      personal: ProfilePersonalInformation(
        displayName: (row['display_name'] as String? ?? '').trim(),
        username: row['username'] as String? ?? '',
        city: row['city'] as String? ?? '',
        bio: row['bio'] as String? ?? '',
        dateOfBirth: DateTime.tryParse(priv?['date_of_birth'] as String? ?? ''),
        gender: profileGenderFromColumn(priv?['gender'] as String?),
        playStyle: PlayStyleX.fromKey(row['play_style'] as String?),
        avatarPreset: row['avatar_preset'] as String? ?? 'midnight',
        avatarUrl: row['avatar_url'] as String?,
        setupComplete: row['profile_setup_complete'] as bool? ?? false,
      ),
      athlete: _athleteFromPrivate(priv),
      sports: sports,
      identity: kindKey == null || submittedAt == null
          ? null
          : ProfileIdentityRecord(
              kind: kindKey == 'b_form'
                  ? IdentityDocumentKind.bForm
                  : IdentityDocumentKind.cnic,
              submittedAt: submittedAt,
              number: identity?['document_number'] as String?,
              hasFront:
                  (identity?['front_path'] as String?)?.isNotEmpty == true,
              hasBack: (identity?['back_path'] as String?)?.isNotEmpty == true,
            ),
    );
  }

  /// Reads the athlete columns out of the embedded `profiles_private` row. A
  /// key that is absent means the backend predates the column, so the value
  /// stays null instead of failing the whole profile read.
  static ProfileAthleteDetails _athleteFromPrivate(Map<String, dynamic>? priv) {
    if (priv == null) return ProfileAthleteDetails.empty;
    return ProfileAthleteDetails(
      heightCm: (priv['height_cm'] as num?)?.toInt(),
      weightKg: (priv['weight_kg'] as num?)?.toDouble(),
      dominantHand: ProfileSideX.fromKey(priv['dominant_hand'] as String?),
      dominantFoot: ProfileSideX.fromKey(priv['dominant_foot'] as String?),
      preferredJersey: (priv['preferred_jersey'] as num?)?.toInt(),
    );
  }

  /// PostgREST returns a to-one embed as an object and a to-many embed as an
  /// array depending on which side of the relationship it is reading from.
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

  static String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  ProfileModuleException _mapError(Object error, {required String fallback}) {
    if (error is ProfileModuleException) return error;
    if (error is PostgrestException) {
      return switch (error.code) {
        '28000' => const ProfileModuleException(
          'Sign in again to continue.',
          code: '28000',
        ),
        '23505' => const ProfileModuleException(
          'That username is already taken. Try another.',
          code: '23505',
        ),
        '42501' => const ProfileModuleException(
          'Only the organizer who owns this match can change it.',
          code: '42501',
        ),
        '22023' || '23514' => ProfileModuleException(
          _messageFor(error.message),
          code: error.code,
        ),
        'P0002' => const ProfileModuleException(
          'Your profile could not be found. Sign out and back in to repair it.',
          code: 'P0002',
        ),
        _ => ProfileModuleException(fallback, code: error.code),
      };
    }
    return ProfileModuleException(fallback);
  }

  /// The RPCs raise stable snake_case identifiers; the member sees a sentence.
  static String _messageFor(String raw) {
    final message = raw.toLowerCase();
    if (message.contains('invalid_display_name')) {
      return 'Enter a full name between 2 and 80 characters.';
    }
    if (message.contains('invalid_username')) {
      return 'Use 3–30 letters, numbers, dots or underscores.';
    }
    if (message.contains('invalid_city')) {
      return 'Enter your city, up to 80 characters.';
    }
    if (message.contains('invalid_bio')) {
      return 'Keep your bio under 120 characters.';
    }
    if (message.contains('invalid_date_of_birth')) {
      return 'Choose a valid date of birth on or before today.';
    }
    if (message.contains('invalid_gender')) {
      return 'Choose one of the listed gender options.';
    }
    if (message.contains('invalid_play_style')) {
      return 'Choose a valid play style.';
    }
    if (message.contains('invalid_height')) {
      return 'Enter a height between 50 and 280 cm.';
    }
    if (message.contains('invalid_weight')) {
      return 'Enter a weight between 20 and 400 kg.';
    }
    if (message.contains('invalid_preferred_jersey')) {
      return 'Enter a jersey number between 1 and 999.';
    }
    if (message.contains('invalid_dominant_hand') ||
        message.contains('invalid_dominant_foot')) {
      return 'Choose a valid dominant side.';
    }
    if (message.contains('sports_required')) {
      return 'Choose at least one preferred sport.';
    }
    if (message.contains('duplicate_sport')) {
      return 'Each sport can only be chosen once.';
    }
    if (message.contains('invalid_level') ||
        message.contains('invalid_position')) {
      return 'Choose a valid level and position.';
    }
    if (message.contains('not_match_organizer') ||
        message.contains('not_assignment_owner') ||
        message.contains('tournament_already_claimed')) {
      return 'Only the tournament organizer can assign or revoke a scorer.';
    }
    if (message.contains('scorer_not_found') ||
        message.contains('invalid_assignment') ||
        message.contains('assignment_not_found')) {
      return 'That scorer assignment could not be found.';
    }
    return 'Those details could not be saved.';
  }
}
