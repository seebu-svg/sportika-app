import 'package:flutter/foundation.dart';

import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/community_game.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/tournament_engine.dart';

/// The persistence boundary every feature controller talks to.
///
/// Controllers only ever see `Future`-returning methods and immutable
/// snapshots, so a REST-backed implementation can replace
/// [LocalSportikaRepository] without touching a single screen.
abstract class SportikaRepository implements Listenable {
  /// Re-reads the backing store. Pull-to-refresh and retry call this: the
  /// local implementation re-decodes the saved document, a REST one would
  /// refetch.
  Future<void> reload();
}

/// Read/write surface for the fixture feature.
abstract class FixtureRepository extends SportikaRepository {
  List<Fixture> get fixtures;
  Fixture? fixtureById(String id);
  List<Fixture> fixturesFor(String tournamentId);
  Tournament? tournamentOf(Fixture f);
  List<Fixture> get publicFixtures;
  List<Fixture> get liveFixtures;
  List<Fixture> get completedFixtures;
  List<Fixture> get scheduledFixtures;
  List<Fixture> get myScoringFixtures;
  List<Fixture> get myOrganizerFixtures;
  List<Fixture> get fixturesAwaitingReview;
  List<Fixture> get myOrganizerDisputes;
  List<Fixture> get myFixtures;
  List<Fixture> officialMatchesPlayed();
  List<Fixture> appearancesOf(String accountId);
  List<Fixture> filterFixtures({Sport? sport, DateTime? day});
  List<String> sideLabelsOf(Fixture f);
  String sideLabel(Fixture f, int index);
  MatchProgress progressOfFixture(Fixture f);
  void assignScorer(String fixtureId, String accountId);
  void replaceScorer(String fixtureId, String fromId, String toId);
  void removeScorer(String fixtureId, String accountId);
  void startOfficialScoring(String fixtureId);
  void recordOfficialEvent(String fixtureId, ScoringEvent event);
  void undoOfficialEvent(String fixtureId);
  void submitOfficialResult(String fixtureId);
  void publishOfficialResult(String fixtureId, {String? correctionReason});
  void recordWalkover(String fixtureId, int winnerIndex, String reason);
  void updateFixtureSchedule(
    String fixtureId, {
    DateTime? scheduledAt,
    String? venue,
    String? scorerId,
  });
  void raiseDispute(String fixtureId, String note);
  void resolveDispute(
    String fixtureId, {
    required bool upholdResult,
    String? note,
  });
}

/// Read/write surface for the game feature.
abstract class GameRepository extends SportikaRepository {
  List<CommunityGame> get games;
  void publishGame(CommunityGame game);
  void toggleGameJoin(CommunityGame game);
}

/// Read/write surface for the personal games feature.
abstract class PersonalGamesRepository extends SportikaRepository {
  List<PersonalMatch> get personal;
  List<PersonalMatch> get myPersonal;
  List<PersonalMatch> get myPersonalInProgress;
  PersonalMatch? personalById(String id);
  PersonalMatch startPersonalMatch({
    required Sport sport,
    required String format,
    required String sideA,
    required String sideB,
  });
  void recordPersonalEvent(String matchId, ScoringEvent event);
  void undoPersonalEvent(String matchId);
  void replacePersonalEvent(String id, int index, ScoringEvent event);
  void updatePersonalDetails(
    String id,
    Map<String, dynamic> details, {
    List<String>? sides,
  });
  void setPersonalStatus(String id, PersonalMatchStatus status);
  void deletePersonalMatch(String matchId);
  MatchProgress progressOfPersonal(PersonalMatch m);
}

/// Read/write surface for the session feature.
abstract class SessionRepository extends SportikaRepository {
  bool get ready;
  bool get onboardingSeen;
  bool get isSignedIn;
  Account? get currentAccount;
  List<Account> get accounts;
  bool hasRole(UserRole role);
  bool get canOrganize;
  Account? accountById(String? id);
  Account? accountByEmail(String email);
  Future<void> signIn(String accountId);
  Future<void> signOut();
  Future<void> markOnboardingSeen();
  Future<void> resetDemoData();
  Future<void> clearLocalData();
  String? takeStorageNotice();
  Future<Account> createAccount({
    required String displayName,
    required String email,
    required String city,
    required AccountIntent intent,
  });
  Future<void> completeProfileSetup({
    required String displayName,
    required String handle,
    required String bio,
    required String city,
    required Set<Sport> sports,
    required Map<String, PlayingLevel> levels,
    required PlayStyle playStyle,
    required String avatar,
  });
}

/// Read/write surface for the profile feature.
abstract class ProfileRepository extends SportikaRepository {
  Account? get currentAccount;
  Future<void> updateProfile({
    String? displayName,
    String? city,
    String? email,
  });
  List<Sport> sportsPlayedBy(String accountId);
  List<Fixture> appearancesOf(String accountId);
  List<Fixture> officialMatchesPlayed();
}

/// Read/write surface for the preferences feature.
abstract class PreferencesRepository extends SportikaRepository {
  Map<String, bool> get preferences;
  bool preference(String key, {bool fallback = true});
  void setPreference(String key, bool value);
}

/// Read/write surface for the notification feature.
abstract class NotificationRepository extends SportikaRepository {
  List<AppNotification> get myNotifications;
  int get unreadCount;
  void markNotificationRead(String id);
  void markAllNotificationsRead();
}

/// Read/write surface for the team feature.
abstract class TeamRepository extends SportikaRepository {
  List<Squad> get squads;
  List<Squad> get mySquads;
  List<Squad> squadsFor(Sport sport, EntryType type);
  List<Squad> squadsOf(String accountId);
  List<Account> get accounts;
  List<Account> get otherPlayers;
  Squad createSquad({
    required String name,
    required Sport sport,
    required EntryType type,
    required List<String> memberIds,
  });
  void addSquadMember(String squadId, String accountId);
  void removeSquadMember(String squadId, String accountId);
  Squad? squadById(String id);
  void inviteToSquad(String squadId, String accountId);
  void cancelSquadInvite(String squadId, String accountId);
  void respondToSquadInvite(
    String squadId,
    String accountId, {
    required bool accept,
  });
  void transferCaptain(String squadId, String accountId);
  void leaveSquad(String squadId);
  void deleteSquad(String squadId);
  String? get currentAccountId;
}

/// Read/write surface for the tournament feature.
abstract class TournamentRepository extends SportikaRepository {
  List<Tournament> get tournaments;
  List<Entry> get entries;
  Map<String, Entry> get entriesById;
  Tournament? tournamentById(String id);
  List<Entry> entriesFor(String tournamentId);
  List<Entry> confirmedEntriesFor(String tournamentId);
  List<Entry> pendingEntriesFor(String tournamentId);
  Entry? myEntryFor(String tournamentId);
  int confirmedCountFor(Tournament t);
  bool canRegisterFor(Tournament t);
  List<Tournament> get liveTournaments;
  List<Tournament> get myTournaments;
  List<Tournament> tournamentsForOrganizer(String? accountId);
  List<Tournament> filterTournaments({
    Sport? sport,
    bool myEntriesOnly = false,
  });
  List<StandingRow> standingsFor(Tournament t);
  List<List<Fixture>> roundsFor(Tournament t);
  Future<void> createTournament({
    required String name,
    required String city,
    required Sport sport,
    required TournamentFormat format,
    required EntryType entryType,
    required DateTime startsAt,
    required DateTime endsAt,
    required int registrationLimit,
    required String entryFee,
    required String rulesSummary,
    required Map<String, dynamic> rules,
    required bool publishNow,
  });
  void setTournamentStatus(String tournamentId, TournamentStatus status);
  Future<void> submitEntry({
    required String tournamentId,
    String? squadId,
    List<String>? memberIds,
  });
  Future<void> withdrawEntry(String entryId);
  Future<void> decideEntry(
    String entryId, {
    required bool approve,
    String? note,
  });
  Future<int> generateDraw(String tournamentId);
}
