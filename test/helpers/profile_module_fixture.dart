import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/identity_document.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/profile_module.dart';
import 'package:sportika/shared/models/profile_setup.dart';

/// Test-only stand-in for the Me module's server.
///
/// It holds the same record shape the PostgreSQL repository returns, so a widget
/// test can prove what the screen reads and what it writes without a live
/// project. Nothing here is imported by `lib/`.
class ProfileModuleFixture extends ChangeNotifier
    implements ProfileModuleRepository {
  ProfileModuleFixture({
    ProfilePersonalInformation? personal,
    List<ProfileSportPreference>? sports,
    this.identity,
    this.supportsIdentityDocuments = true,
  }) : personal =
           personal ??
           ProfilePersonalInformation(
             displayName: 'Zain Malik',
             username: 'zain',
             city: 'Karachi',
             bio: 'Weekend padel.',
             dateOfBirth: DateTime(1999, 4, 12),
             gender: ProfileGender.man,
             playStyle: PlayStyle.weekly,
             avatarPreset: 'midnight',
             avatarUrl: null,
             setupComplete: true,
           ),
       sports = [...?sports];

  ProfilePersonalInformation personal;
  List<ProfileSportPreference> sports;
  ProfileIdentityRecord? identity;

  @override
  final bool supportsIdentityDocuments;

  /// A stalled read, used to assert the loading state before it resolves.
  Completer<void>? loadBarrier;

  /// Failures the next call throws. A [ProfileModuleException] message reaches
  /// the member verbatim; anything else is shown through the controller's
  /// fallback sentence.
  Object? loadError;
  Object? writeError;
  Object? assignmentsError;

  List<ScorerAssignment> assignments = const <ScorerAssignment>[];
  List<ProfileSummary> players = const <ProfileSummary>[];
  List<ScorerAssignment> organizerAssignmentsSeed = const <ScorerAssignment>[];

  // ── Recorded calls ──────────────────────────────────────────────────────
  int loads = 0;
  String? savedDisplayName;
  String? savedCity;
  String? savedBio;
  DateTime? savedDateOfBirth;
  ProfileGender? savedGender;
  PlayStyle? savedPlayStyle;
  String? savedUsername;
  List<ProfileSportPreference>? savedSports;
  final List<IdentitySubmission> submittedIdentities = <IdentitySubmission>[];
  int deletedIdentities = 0;
  final List<String> claimedTournaments = <String>[];
  final List<String> assigned = <String>[];
  final List<String> revoked = <String>[];
  final List<String> responses = <String>[];
  String? lastSearch;

  void _throwIfSet(Object? error) {
    if (error != null) throw error;
  }

  @override
  Future<ProfileModuleSnapshot> load() async {
    loads++;
    if (loadBarrier != null) await loadBarrier!.future;
    _throwIfSet(loadError);
    return ProfileModuleSnapshot(
      personal: personal,
      sports: sports,
      identity: identity,
    );
  }

  @override
  Future<void> savePersonalInformation({
    required String displayName,
    required String city,
    required String bio,
    required DateTime dateOfBirth,
    required ProfileGender? gender,
    required PlayStyle playStyle,
  }) async {
    _throwIfSet(writeError);
    savedDisplayName = displayName;
    savedCity = city;
    savedBio = bio;
    savedDateOfBirth = dateOfBirth;
    savedGender = gender;
    savedPlayStyle = playStyle;
    personal = ProfilePersonalInformation(
      displayName: displayName.trim(),
      username: personal.username,
      city: city.trim(),
      bio: bio.trim(),
      dateOfBirth: dateOfBirth,
      gender: gender,
      playStyle: playStyle,
      avatarPreset: personal.avatarPreset,
      avatarUrl: personal.avatarUrl,
      setupComplete: personal.setupComplete,
    );
    notifyListeners();
  }

  @override
  Future<void> changeUsername(String username) async {
    _throwIfSet(writeError);
    savedUsername = username;
    personal = ProfilePersonalInformation(
      displayName: personal.displayName,
      username: username,
      city: personal.city,
      bio: personal.bio,
      dateOfBirth: personal.dateOfBirth,
      gender: personal.gender,
      playStyle: personal.playStyle,
      avatarPreset: personal.avatarPreset,
      avatarUrl: personal.avatarUrl,
      setupComplete: personal.setupComplete,
    );
    notifyListeners();
  }

  @override
  Future<void> saveSportsPreferences(
    List<ProfileSportPreference> sports,
  ) async {
    _throwIfSet(writeError);
    savedSports = sports;
    this.sports = sports;
    notifyListeners();
  }

  @override
  Future<void> submitIdentityDocument(IdentitySubmission submission) async {
    _throwIfSet(writeError);
    submittedIdentities.add(submission);
    identity = ProfileIdentityRecord(
      kind: submission.kind,
      submittedAt: DateTime(2026, 11, 1),
      number: submission.number,
      hasFront: submission.front != null,
      hasBack: submission.back != null,
    );
    notifyListeners();
  }

  @override
  Future<void> deleteIdentityDocument() async {
    _throwIfSet(writeError);
    deletedIdentities++;
    identity = null;
    notifyListeners();
  }

  @override
  Future<List<ScorerAssignment>> loadAssignments() async {
    _throwIfSet(assignmentsError);
    return assignments;
  }

  @override
  Future<List<ProfileSummary>> searchPlayers(String query) async {
    lastSearch = query;
    return players;
  }

  @override
  Future<void> claimOrganizer(String tournamentId) async {
    claimedTournaments.add(tournamentId);
  }

  @override
  Future<ScorerAssignment> assignScorer({
    required String tournamentId,
    required String fixtureId,
    required String scorerId,
  }) async {
    assigned.add('$tournamentId|$fixtureId|$scorerId');
    return ScorerAssignment(
      id: 'a-${assigned.length}',
      tournamentId: tournamentId,
      fixtureId: fixtureId,
      scorerId: scorerId,
      authorizedBy: 'me',
      status: ScorerAssignmentStatus.assigned,
      createdAt: DateTime(2026, 11, 1),
    );
  }

  @override
  Future<void> revokeScorer({
    required String tournamentId,
    required String fixtureId,
    required String scorerId,
  }) async {
    revoked.add('$tournamentId|$fixtureId|$scorerId');
  }

  @override
  Future<void> respondToAssignment({
    required String assignmentId,
    required bool accept,
  }) async {
    responses.add('$assignmentId:${accept ? 'accept' : 'decline'}');
  }
}

/// One assignment row for either side of the scorer screen.
ScorerAssignment assignmentRow({
  required String id,
  required String scorerId,
  required String authorizedBy,
  String tournamentId = 't-1',
  String fixtureId = 'f-1',
  ScorerAssignmentStatus status = ScorerAssignmentStatus.assigned,
}) => ScorerAssignment(
  id: id,
  tournamentId: tournamentId,
  fixtureId: fixtureId,
  scorerId: scorerId,
  authorizedBy: authorizedBy,
  status: status,
  createdAt: DateTime(2026, 11, 1),
);

/// A sport row helper that keeps the tests readable.
ProfileSportPreference sportRow(
  Sport sport, {
  PlayingLevel? level,
  String? position,
}) => ProfileSportPreference(sport, level: level, position: position);
