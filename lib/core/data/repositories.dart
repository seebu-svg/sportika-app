import 'package:sportika/shared/models/profile_module.dart';
import 'package:sportika/shared/models/profile_setup.dart';
import 'package:flutter/foundation.dart';

import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/community_game.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/identity_document.dart';
import 'package:sportika/shared/models/match.dart';
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
///
/// The last three members are the remote read state: a device store has no
/// in-flight request and no transport to fail, so it answers "never loading,
/// never failed" and refresh means a plain re-read. Implementations that use
/// `implements` must supply all three themselves.
abstract class FixtureRepository extends SportikaRepository {
  /// True while a reload is in flight, so a screen can tell "empty" from
  /// "not loaded yet".
  bool get loading => false;

  /// Why the last read failed, or null while it is healthy. A section keeps
  /// showing its last good rows and puts this in a banner instead of blanking.
  String? get lastError => null;

  /// Re-reads and republishes. Pull-to-refresh and a section's retry call this.
  Future<void> refresh() => reload();

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
  bool get loading => false;
  String? get lastError => null;
  Future<void> refresh() => reload();

  List<CommunityGame> get games;
  void publishGame(CommunityGame game);
  void toggleGameJoin(CommunityGame game);
}

/// Read/write surface for the standalone official match feature.
///
/// This is a separate aggregate from [FixtureRepository]: a match owns its own
/// sport, sides, invited participants, assigned scorer and event log, and it
/// exists outside any tournament. Every mutation mirrors one RPC of migration
/// 0007, so the device store and the server refuse exactly the same calls.
abstract class MatchRepository extends SportikaRepository {
  List<SportMatch> get matches;
  SportMatch? matchById(String id);

  /// The local match created from a tournament fixture, or null.
  /// The server enforces the same one-match-per-fixture rule with a partial
  /// unique index (migration 0008).
  SportMatch? matchOfFixture(String tournamentId, String fixtureId);

  /// Public matches, plus the invite-only ones the caller is on.
  List<SportMatch> get discoverableMatches;
  List<SportMatch> get myMatches;
  List<SportMatch> get myOrganizedMatches;
  List<SportMatch> get myScoringMatches;
  List<SportMatch> get liveMatches;
  List<SportMatch> get completedMatches;

  /// Pending invitations addressed to the caller, newest first.
  List<SportMatch> get myInvites;

  /// The event log folded through the sport's own engine.
  MatchProgress progressOf(SportMatch match);

  Future<SportMatch> createMatch(MatchDraft draft);

  Future<void> updateMatch(
    String matchId, {
    required String title,
    required String venue,
    required DateTime scheduledAt,
    required String sideA,
    required String sideB,
    required int capacity,
  });

  Future<void> cancelMatch(String matchId, {String? reason});
  Future<void> inviteParticipant(
    String matchId,
    String profileId, {
    int side = 1,
    String? displayName,
  });
  Future<void> respondToInvite(String matchId, {required bool accept});
  Future<void> removeParticipant(String matchId, String profileId);

  /// Joins a public match on [side] (0 or 1) without waiting for an invitation.
  /// Being in the match is the consent, so the row is written accepted and the
  /// organizer is told. Joining twice is not an error; the per-side cap is
  /// `capacity / 2` for team disciplines, 1 for singles and 2 for doubles, and
  /// the server refuses a full side with `side_full`.
  Future<void> joinMatch(String matchId, {int side = 0});

  /// Leaves a match the caller joined, before kick-off. The organizer cannot
  /// leave their own match, and the server refuses a started one.
  Future<void> leaveMatch(String matchId);

  /// Invites every accepted member of [squadId] to [side]. Organizer or scorer
  /// only, and the caller must be on the squad. Consent stays with the players:
  /// they are invited, not enrolled. Returns how many invitations were written.
  Future<int> addSquadToMatch(String matchId, String squadId, {int side = 0});

  Future<void> assignMatchScorer(String matchId, String scorerId);
  Future<void> revokeMatchScorer(String matchId);
  Future<void> startMatch(String matchId);

  /// Stops and restarts scoring without changing [SportMatch.status]: the
  /// server writes `paused_at`/`paused_by`/`pause_reason` and keeps the match
  /// live, so a paused match still reads as live in every existing pill.
  /// Both calls are no-ops when the match is already in that state, which is
  /// what makes a double tap on a slow connection safe.
  Future<void> pauseMatch(String matchId, {String? reason});
  Future<void> resumeMatch(String matchId);

  /// Appends one scoring action. [clientId] is the idempotency key: passing the
  /// same value twice returns the original entry instead of a second one.
  Future<MatchEvent> recordEvent(
    String matchId, {
    required String kind,
    int? side,
    Map<String, dynamic> data = const {},
    String? clientId,
    DateTime? at,
  });

  /// Withdraws the newest active entry. Anything older is refused.
  Future<void> voidEvent(String matchId, String eventId);

  /// Puts the official result on the record and moves the match to review.
  ///
  /// Padel, futsal and badminton are not told what their score was: both
  /// backends re-derive the set/game lines, the totals and the winner from the
  /// point or rally log the server holds (`complete_padel_match`, 0013;
  /// `submit_match_result`, 0021/0024), so a device that sends a friendlier
  /// number cannot put it on the official record. The three score arguments are
  /// therefore only authoritative for cricket, whose engine result the app
  /// still submits itself.
  Future<void> submitResult(
    String matchId, {
    required String headline,
    required String detail,
    required List<String> sideScores,
    required List<int> sideValues,
    required int winnerIndex,
  });

  Future<void> publishResult(String matchId);

  Future<void> correctResult(
    String matchId, {
    required String headline,
    required String detail,
    required List<String> sideScores,
    required List<int> sideValues,
    required int winnerIndex,
    required String reason,
  });

  Future<void> recordMatchWalkover(
    String matchId, {
    required int winnerIndex,
    required String reason,
  });

  /// Retires a live badminton match that will not reach the winning game.
  ///
  /// The winner is the side that takes the result, the reason is required and
  /// audited, and the partial score comes from the rally log the server holds
  /// (`retire_match`, migration 0024). The match keeps the walkover terminal
  /// status, because a retirement is a walkover with a score attached.
  Future<void> retireMatch(
    String matchId, {
    required int winnerIndex,
    required String reason,
  });

  /// Challenges an official result. Free by product decision: like recording a
  /// point and publishing a result, this is never gated on an entitlement.
  /// [reason] has to be 5 to 500 characters, and a member can only have one
  /// live dispute per match.
  Future<MatchDispute> raiseMatchDispute(String matchId, String reason);

  /// The organizer's answer. [status] is `underReview` (no resolution),
  /// `resolved` or `rejected` (resolution required, 3 to 500 characters).
  Future<MatchDispute> resolveMatchDispute(
    String matchId,
    String disputeId, {
    required MatchDisputeStatus status,
    String? resolution,
  });

  /// The disputes already loaded with the match. Never a network call: reads
  /// come through the nested select and realtime refreshes.
  List<MatchDispute> disputesOf(String matchId);

  /// Realtime subscription for one match. The device store has nothing to
  /// subscribe to and returns immediately.
  Future<void> watchMatch(String matchId);
  Future<void> unwatchMatch(String matchId);

  /// Subscribes to every match the signed-in member can see, so a tournament
  /// fixture result updates the public feed without opening each workspace.
  /// The local repository implements this as a no-op (it is already in-process).
  Future<void> watchAllMatches();
  Future<void> unwatchAllMatches();

  /// Where the last write landed, for the sync banner above the scorer.
  MatchSyncState get sync;
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

  /// Loads [accountId] into the directory so [accountById] can answer
  /// synchronously right afterwards.
  ///
  /// The on-device store is already loaded when a session is accepted, so its
  /// body is empty; a server-backed store fetches the profile here. Callers that
  /// already know the account is local pay nothing.
  Future<void> hydrateAccount(String accountId) async {}

  Future<void> signIn(String accountId);
  Future<void> signOut();
  Future<void> markOnboardingSeen();
  Future<void> resetDemoData();
  Future<void> clearLocalData();
  String? takeStorageNotice();

  /// Only the demo adapter calls this: a server-backed store creates the account
  /// row from the signup trigger, not from the app.
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
    String? email,
    DateTime? dateOfBirth,
    ProfileGender? gender,
    Map<String, String>? playingPositions,
    bool playingPreferencesSkipped = false,
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

  /// Points the signed-in account at an imported picture, or at nothing when
  /// [path] is null and the preset avatar comes back. The bytes themselves are
  /// owned by the profile photo store, not by this repository.
  Future<void> setProfilePhoto(String? path);

  List<Sport> sportsPlayedBy(String accountId);
  List<Fixture> appearancesOf(String accountId);
  List<Fixture> officialMatchesPlayed();
}

/// The three surfaces one account directory has to supply together.
///
/// A store that answers [SessionRepository] from the server must answer
/// [ProfileRepository] from the same place; keeping them in one type stops a
/// build from pairing a remote session with a profile read off the device.
///
/// [PreferencesRepository] rides along because account settings (reminders,
/// invitations, profile visibility) are part of the same member record once the
/// server owns identity. A device-only build answers all three from
/// [LocalSportikaRepository].
abstract class AccountRepository
    implements SessionRepository, ProfileRepository, PreferencesRepository {}

/// Read/write surface for the Me module: granular identity edits, optional
/// identity documents and organizer-authorised scorer assignments.
///
/// This is deliberately separate from [ProfileRepository]: the statistics that
/// come from local fixtures stay there, while the rows this module edits live in
/// PostgreSQL. Every write derives its subject from `auth.uid()`; no method takes
/// an account id.
abstract class ProfileModuleRepository implements Listenable {
  /// The member's own card, preferred sports and optional identity summary.
  Future<ProfileModuleSnapshot> load();

  /// Name, city, bio, date of birth, gender and play style. The unique handle
  /// and the sport set are separate calls on purpose.
  Future<void> savePersonalInformation({
    required String displayName,
    required String city,
    required String bio,
    required DateTime dateOfBirth,
    required ProfileGender? gender,
    required PlayStyle playStyle,
  });

  /// Renames the handle through the server's unique index.
  Future<void> changeUsername(String username);

  /// The optional athlete attributes (height, weight, laterality, preferred
  /// jersey). Every argument is nullable so a member can leave any single field
  /// blank; a null clears the stored value rather than being ignored.
  Future<void> saveAthleteDetails({
    required int? heightCm,
    required double? weightKg,
    required ProfileSide? dominantHand,
    required ProfileSide? dominantFoot,
    required int? preferredJersey,
  });

  /// Replaces the whole preferred-sport set.
  Future<void> saveSportsPreferences(List<ProfileSportPreference> sports);

  /// Submits the optional CNIC / B-Form record. Never a verification claim.
  Future<void> submitIdentityDocument(IdentitySubmission submission);

  /// Withdraws the optional identity record and its stored images.
  Future<void> deleteIdentityDocument();

  /// Whether this build can attach identity documents at all. Demo builds
  /// cannot, and the screen says so instead of pretending to save.
  bool get supportsIdentityDocuments;

  /// Assignments the caller scored or authorised, newest first.
  Future<List<ScorerAssignment>> loadAssignments();

  /// Public member cards matching [query], used when an organizer picks a
  /// scorer. Excludes the caller.
  Future<List<ProfileSummary>> searchPlayers(String query);

  /// Records that the caller organizes [tournamentId]. First writer wins.
  Future<void> claimOrganizer(String tournamentId);

  /// Assigns [scorerId] to one match of a tournament the caller organizes.
  Future<ScorerAssignment> assignScorer({
    required String tournamentId,
    required String fixtureId,
    required String scorerId,
  });

  /// Revokes an assignment. Only the organizer who made it may call this.
  Future<void> revokeScorer({
    required String tournamentId,
    required String fixtureId,
    required String scorerId,
  });

  /// The scorer's answer to their own assignment.
  Future<void> respondToAssignment({
    required String assignmentId,
    required bool accept,
  });
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

  /// Re-reads the inbox from the server.
  ///
  /// The device store already holds the whole inbox, so this is a no-op there;
  /// the server-backed repository refetches the first page and refreshes the
  /// unread count.
  Future<void> syncNotifications();

  /// Loads the page behind the current one.
  ///
  /// The device store has a single page, so this does nothing there.
  Future<void> loadMoreNotifications();

  /// Whether another page exists behind the one on screen.
  bool get hasMoreNotifications;

  /// Whether a read is in flight. The centre shows a spinner for it.
  bool get loadingNotifications;

  /// The last failure, if any. The centre shows a retry when it is set.
  String? get notificationError;

  /// One notification in full, or null when it is not this member's.
  Future<AppNotification?> notificationById(String id);

  /// Which families of notification this member wants to receive.
  NotificationPreferences get notificationPreferences;

  /// Saves the delivery preferences.
  Future<void> updateNotificationPreferences(
    NotificationPreferences preferences,
  );

  /// Reads the stored delivery preferences.
  ///
  /// The preferences screen calls this before it draws, so the switches show
  /// what the server already holds rather than what the app assumes.
  Future<void> loadNotificationPreferences();

  /// Starts the live subscription for the member's inbox.
  ///
  /// The device store has nothing to subscribe to, so this is a no-op there.
  Future<void> watchNotifications();

  /// Stops the live subscription. Called when the member signs out.
  Future<void> unwatchNotifications();
}

/// Read/write surface for the team feature.
abstract class TeamRepository extends SportikaRepository {
  bool get loading => false;
  String? get lastError => null;
  Future<void> refresh() => reload();

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
  bool get loading => false;
  String? get lastError => null;
  Future<void> refresh() => reload();

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
