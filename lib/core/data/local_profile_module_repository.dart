import 'package:flutter/foundation.dart';

import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/identity_document.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/profile_module.dart';
import 'package:sportika/shared/models/profile_setup.dart';

/// The Me module when identity lives on the device instead of PostgreSQL.
///
/// This is an adapter, never a second store: every read and write goes through
/// [LocalSportikaRepository], so the profile screen and the rest of the demo
/// world cannot disagree. What a device-only build genuinely cannot do —
/// private document uploads, organizer claims and cross-member assignment
/// records — is answered honestly instead of simulated.
class LocalProfileModuleRepository extends ChangeNotifier
    implements ProfileModuleRepository {
  LocalProfileModuleRepository(this._device) {
    _device.addListener(_relay);
  }

  final LocalSportikaRepository _device;

  void _relay() => notifyListeners();

  @override
  void dispose() {
    _device.removeListener(_relay);
    super.dispose();
  }

  /// A device build has no private bucket to upload to. The screen says so and
  /// keeps the step optional, exactly as the MVP requires.
  @override
  bool get supportsIdentityDocuments => false;

  Account get _account {
    final account = _device.currentAccount;
    if (account == null) {
      throw const ProfileModuleException(
        'Sign in again to manage your profile.',
        code: '28000',
      );
    }
    return account;
  }

  // ── Read ────────────────────────────────────────────────────────────────

  @override
  Future<ProfileModuleSnapshot> load() async {
    final account = _account;
    final sports = <ProfileSportPreference>[
      for (final sport in account.sports)
        ProfileSportPreference(
          sport,
          level: account.levels[sport.key],
          position: account.playingPositions[sport.key],
        ),
    ]..sort((a, b) => a.sport.index.compareTo(b.sport.index));

    return ProfileModuleSnapshot(
      personal: ProfilePersonalInformation(
        displayName: account.displayName,
        username: account.username,
        city: account.city,
        bio: account.bio,
        dateOfBirth: account.dateOfBirth,
        gender: account.gender,
        playStyle: account.playStyle,
        avatarPreset: account.avatar,
        avatarUrl: account.photoUrl,
        setupComplete: account.setupComplete,
      ),
      sports: sports,
      // Documents are never written to the device document, so there is
      // nothing to read back.
      identity: null,
      athlete: ProfileAthleteDetails(
        heightCm: account.heightCm,
        weightKg: account.weightKg,
        dominantHand: ProfileSideX.fromKey(account.dominantHand),
        dominantFoot: ProfileSideX.fromKey(account.dominantFoot),
        preferredJersey: account.preferredJersey,
      ),
    );
  }

  @override
  Future<List<ScorerAssignment>> loadAssignments() async {
    final me = _device.currentAccount?.id;
    if (me == null) return const <ScorerAssignment>[];

    final rows = <ScorerAssignment>[];
    // Matches handed to me: being on the fixture is the access, so a device
    // assignment is already accepted.
    for (final fixture in _device.fixtures) {
      if (!fixture.scorerAccountIds.contains(me)) continue;
      final tournament = _device.tournamentById(fixture.tournamentId);
      rows.add(
        ScorerAssignment(
          id: 'device-${fixture.id}-$me',
          tournamentId: fixture.tournamentId,
          fixtureId: fixture.id,
          scorerId: me,
          authorizedBy: tournament?.organizerId ?? '',
          status: ScorerAssignmentStatus.accepted,
          createdAt: fixture.startedAt ?? fixture.scheduledAt,
        ),
      );
    }
    // Matches I organized and handed to someone else.
    for (final tournament in _device.tournamentsForOrganizer(me)) {
      for (final fixture in _device.fixturesFor(tournament.id)) {
        for (final scorer in fixture.scorerAccountIds) {
          if (scorer == me) continue;
          rows.add(
            ScorerAssignment(
              id: 'device-${fixture.id}-$scorer',
              tournamentId: tournament.id,
              fixtureId: fixture.id,
              scorerId: scorer,
              authorizedBy: me,
              status: ScorerAssignmentStatus.assigned,
              createdAt: fixture.startedAt ?? fixture.scheduledAt,
            ),
          );
        }
      }
    }
    rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return rows;
  }

  @override
  Future<List<ProfileSummary>> searchPlayers(String query) async {
    final me = _device.currentAccount?.id;
    final term = query.trim().toLowerCase();
    return _device.accounts
        .where(
          (account) =>
              account.id != me &&
              (term.isEmpty ||
                  account.displayName.toLowerCase().contains(term) ||
                  account.username.toLowerCase().contains(term)),
        )
        .map(
          (account) => ProfileSummary(
            id: account.id,
            displayName: account.displayName,
            username: account.username,
            city: account.city,
            avatarUrl: account.photoUrl,
          ),
        )
        .toList();
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
    _account;
    await _device.applyProfileInformation(
      displayName: displayName,
      city: city,
      bio: bio,
      dateOfBirth: dateOfBirth,
      gender: gender,
      playStyle: playStyle,
    );
  }

  @override
  Future<void> changeUsername(String username) async {
    _account;
    final wanted = normalizeProfileHandle(username);
    if (!RegExp(r'^[a-z0-9._]{3,30}$').hasMatch(wanted)) {
      throw const ProfileModuleException(
        'Use 3–30 letters, numbers, dots or underscores.',
        code: 'invalid_username',
      );
    }
    try {
      await _device.applyProfileHandle(wanted);
    } on StateError catch (error) {
      throw ProfileModuleException(error.message, code: '23505');
    }
  }

  @override
  Future<void> saveAthleteDetails({
    required int? heightCm,
    required double? weightKg,
    required ProfileSide? dominantHand,
    required ProfileSide? dominantFoot,
    required int? preferredJersey,
  }) async {
    _account;
    await _device.applyProfileAthleteDetails(
      heightCm: heightCm,
      weightKg: weightKg,
      dominantHand: dominantHand?.key,
      dominantFoot: dominantFoot?.key,
      preferredJersey: preferredJersey,
    );
  }

  @override
  Future<void> saveSportsPreferences(
    List<ProfileSportPreference> sports,
  ) async {
    _account;
    if (sports.isEmpty) {
      throw const ProfileModuleException(
        'Choose at least one preferred sport.',
        code: 'sports_required',
      );
    }
    final skipped = sports.every((sport) => sport.level == null);
    await _device.applySportsPreferences(
      sports: {for (final sport in sports) sport.sport},
      levels: {
        for (final sport in sports)
          if (sport.level != null) sport.sport.key: sport.level!,
      },
      positions: {
        for (final sport in sports)
          if (sport.position != null && sport.position!.isNotEmpty)
            sport.sport.key: sport.position!,
      },
      skipped: skipped,
    );
  }

  @override
  Future<void> submitIdentityDocument(IdentitySubmission submission) async {
    throw const ProfileModuleException(
      'Identity documents need a Sportika account. Your profile works '
      'without them.',
      code: 'unsupported',
    );
  }

  @override
  Future<void> deleteIdentityDocument() async {
    throw const ProfileModuleException(
      'There are no identity documents to withdraw in this build.',
      code: 'unsupported',
    );
  }

  /// The account that created a device tournament already organizes it; there
  /// is no second member who could claim it.
  @override
  Future<void> claimOrganizer(String tournamentId) async {
    _account;
  }

  @override
  Future<ScorerAssignment> assignScorer({
    required String tournamentId,
    required String fixtureId,
    required String scorerId,
  }) async {
    final me = _account.id;
    _device.assignScorer(fixtureId, scorerId);
    final fixture = _device.fixtureById(fixtureId);
    if (fixture == null || !fixture.scorerAccountIds.contains(scorerId)) {
      throw const ProfileModuleException(
        'Only the organizer of this match can assign a scorer.',
        code: '42501',
      );
    }
    return ScorerAssignment(
      id: 'device-$fixtureId-$scorerId',
      tournamentId: tournamentId,
      fixtureId: fixtureId,
      scorerId: scorerId,
      authorizedBy: me,
      status: ScorerAssignmentStatus.assigned,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> revokeScorer({
    required String tournamentId,
    required String fixtureId,
    required String scorerId,
  }) async {
    _account;
    final fixture = _device.fixtureById(fixtureId);
    if (fixture == null || !fixture.scorerAccountIds.contains(scorerId)) {
      throw const ProfileModuleException(
        'That scorer assignment could not be found.',
        code: 'assignment_not_found',
      );
    }
    _device.removeScorer(fixtureId, scorerId);
  }

  @override
  Future<void> respondToAssignment({
    required String assignmentId,
    required bool accept,
  }) async {
    final me = _account.id;
    final match = (await loadAssignments())
        .where((assignment) => assignment.id == assignmentId)
        .firstOrNull;
    if (match == null || match.scorerId != me) {
      throw const ProfileModuleException(
        'That scorer assignment is not yours to answer.',
        code: '42501',
      );
    }
    try {
      await _device.respondToScorerAssignment(match.fixtureId, accept: accept);
    } on StateError catch (error) {
      throw ProfileModuleException(error.message);
    }
  }
}
