// The store implements all nine repository interfaces, so every member below
// is an interface implementation. Annotating one hundred members with
// `@override` would obscure the code without adding information.
// ignore_for_file: annotate_overrides

import 'package:flutter/foundation.dart';

import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/models/community_game.dart';
import 'package:sportika/shared/data/seed.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/official_result.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/models/tournament_engine.dart';
import 'package:sportika/core/data/repositories.dart';

/// The single source of truth for the prototype.
///
/// Everything is persisted to one JSON document after each mutation, so a
/// personal scorecard survives closing the app, and official scoring resumes
/// from the last saved event (spec §2.3, §6).
class LocalSportikaRepository extends ChangeNotifier
    implements
        FixtureRepository,
        GameRepository,
        NotificationRepository,
        PersonalGamesRepository,
        PreferencesRepository,
        ProfileRepository,
        SessionRepository,
        TeamRepository,
        TournamentRepository {
  LocalSportikaRepository(this._storage);

  final LocalStorage _storage;

  bool ready = false;

  String? _storageNotice;

  /// A one-time message about the persisted document (corrupt payload or a
  /// migration). Reading it clears it so the shell shows it exactly once.
  String? takeStorageNotice() {
    final notice = _storageNotice;
    _storageNotice = null;
    return notice;
  }

  /// Device-level flag so onboarding only plays once. Returning accounts never
  /// see it again, even after signing out.
  bool onboardingSeen = false;
  Map<String, bool> preferences = {};
  bool preference(String key, {bool fallback = true}) =>
      preferences['${currentAccount?.id}:$key'] ?? fallback;
  void setPreference(String key, bool value) {
    preferences['${currentAccount?.id}:$key'] = value;
    _commit();
  }

  Account? currentAccount;

  List<CommunityGame> games = seedCommunityGames();

  void publishGame(CommunityGame game) {
    games.insert(0, game);
    _commit();
  }

  void toggleGameJoin(CommunityGame game) {
    final id = currentAccount?.id;
    if (id == null) return;
    if (game.members.contains(id)) {
      game.members.remove(id);
    } else if (game.members.length < game.capacity) {
      game.members.add(id);
    }
    _commit();
  }

  List<Account> accounts = [];
  List<Squad> squads = [];
  List<Tournament> tournaments = [];
  List<Entry> entries = [];
  List<Fixture> fixtures = [];
  List<PersonalMatch> personal = [];
  List<AppNotification> notifications = [];

  // ── Lifecycle ──────────────────────────────────────────────────────────

  Future<void> load() async {
    final raw = _storage.readState();
    if (raw == null) {
      _adopt(buildSeed());
      if (_storage.recoveredFromCorruption) {
        _storageNotice =
            'Saved data could not be read, so the demo world was rebuilt.';
      }
    } else {
      try {
        _decode(raw);
      } catch (_) {
        // A corrupt document should never brick the prototype.
        _adopt(buildSeed());
        _storageNotice =
            'Saved data could not be read, so the demo world was rebuilt.';
      }
    }
    final sessionId = _storage.readSessionAccountId();
    currentAccount = accounts.where((a) => a.id == sessionId).firstOrNull;
    onboardingSeen = _storage.readOnboardingSeen();
    ready = true;
    notifyListeners();
    await _persist();
  }

  void _adopt(SeedWorld world) {
    preferences = {};
    games = seedCommunityGames();
    accounts = world.accounts;
    squads = world.squads;
    tournaments = world.tournaments;
    entries = world.entries;
    fixtures = world.fixtures;
    personal = world.personal;
    notifications = world.notifications;
  }

  void _decode(Map<String, dynamic> raw) {
    List<T> listOf<T>(String key, T Function(Map<String, dynamic>) parse) =>
        (raw[key] as List<dynamic>? ?? [])
            .map((e) => parse(Map<String, dynamic>.from(e as Map)))
            .toList();

    games = raw.containsKey('games')
        ? listOf('games', CommunityGame.fromJson)
        : seedCommunityGames();
    preferences = Map<String, bool>.from(raw['preferences'] as Map? ?? {});
    accounts = listOf('accounts', Account.fromJson);
    squads = listOf('squads', Squad.fromJson);
    tournaments = listOf('tournaments', Tournament.fromJson);
    entries = listOf('entries', Entry.fromJson);
    fixtures = listOf('fixtures', Fixture.fromJson);
    personal = listOf('personal', PersonalMatch.fromJson);
    notifications = listOf('notifications', AppNotification.fromJson);
  }

  Map<String, dynamic> toJson() => {
    'preferences': preferences,
    'games': games.map((e) => e.toJson()).toList(),
    'accounts': accounts.map((e) => e.toJson()).toList(),
    'squads': squads.map((e) => e.toJson()).toList(),
    'tournaments': tournaments.map((e) => e.toJson()).toList(),
    'entries': entries.map((e) => e.toJson()).toList(),
    'fixtures': fixtures.map((e) => e.toJson()).toList(),
    'personal': personal.map((e) => e.toJson()).toList(),
    'notifications': notifications.map((e) => e.toJson()).toList(),
  };

  Future<void> _persist() => _storage.writeState(toJson());

  void _commit() {
    notifyListeners();
    _persist();
  }

  // ── Session & roles ────────────────────────────────────────────────────

  bool get isSignedIn => currentAccount != null;

  bool hasRole(UserRole role) => currentAccount?.has(role) ?? false;

  /// Organizer screens are gated by the role alone; this app has no
  /// separate approval desk.
  bool get canOrganize => hasRole(UserRole.organizer);

  Account? accountById(String? id) =>
      accounts.where((a) => a.id == id).firstOrNull;

  Future<void> signIn(String accountId) async {
    currentAccount = accountById(accountId);
    await _storage.writeSessionAccountId(accountId);
    _commit();
  }

  Account? accountByEmail(String email) {
    final needle = email.trim().toLowerCase();
    return accounts.where((a) => a.email.toLowerCase() == needle).firstOrNull;
  }

  Future<void> markOnboardingSeen() async {
    if (onboardingSeen) return;
    onboardingSeen = true;
    await _storage.writeOnboardingSeen(true);
    notifyListeners();
  }

  /// Registers an account at the end of OTP verification and keeps the session
  /// open. Profile setup stays incomplete until [completeProfileSetup] runs.
  Future<Account> createAccount({
    required String displayName,
    required String email,
    required String city,
    required AccountIntent intent,
  }) async {
    final account = Account(
      id: newId('acc'),
      displayName: displayName.trim(),
      email: email.trim(),
      city: city.trim(),
      roles: intent.roles,
      setupComplete: false,
    );
    accounts.add(account);
    currentAccount = account;
    onboardingSeen = true;
    await _storage.writeSessionAccountId(account.id);
    await _storage.writeOnboardingSeen(true);
    _commit();
    return account;
  }

  /// Commits the four profile-setup screens in one go, so an interrupted
  /// setup can be resumed without half-written preferences.
  Future<void> completeProfileSetup({
    required String displayName,
    required String handle,
    required String bio,
    required String city,
    required Set<Sport> sports,
    required Map<String, PlayingLevel> levels,
    required PlayStyle playStyle,
    required String avatar,
  }) async {
    final a = currentAccount;
    if (a == null) return;
    if (displayName.trim().isNotEmpty) a.displayName = displayName.trim();
    if (city.trim().isNotEmpty) a.city = city.trim();
    a.handle = handle.trim().replaceAll('@', '').toLowerCase();
    a.bio = bio.trim();
    a.sports = sports;
    a.levels = levels;
    a.playStyle = playStyle;
    a.avatar = avatar;
    a.setupComplete = true;
    onboardingSeen = true;
    await _storage.writeOnboardingSeen(true);
    _commit();
  }

  Future<void> signOut() async {
    currentAccount = null;
    await _storage.writeSessionAccountId(null);
    _commit();
  }

  Future<void> updateProfile({
    String? displayName,
    String? city,
    String? email,
  }) async {
    final a = currentAccount;
    if (a == null) return;
    if (displayName != null && displayName.trim().isNotEmpty) {
      a.displayName = displayName.trim();
    }
    if (city != null) a.city = city;
    if (email != null) a.email = email;
    _commit();
  }

  Future<void> resetDemoData() async {
    _adopt(buildSeed());
    final keep = currentAccount?.id;
    currentAccount = accountById(keep) ?? accounts.first;
    _commit();
  }

  /// Wipes the persisted document, the stored session and the onboarding flag.
  Future<void> clearLocalData() async {
    await _storage.clearAll();
    currentAccount = null;
    onboardingSeen = false;
    _adopt(buildSeed());
    _commit();
  }

  // ── Notifications ──────────────────────────────────────────────────────

  List<AppNotification> get myNotifications {
    final id = currentAccount?.id;
    final list = notifications.where((n) => n.accountId == id).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return list;
  }

  int get unreadCount => myNotifications.where((n) => !n.read).length;

  void _notify(
    Iterable<String> accountIds, {
    required NotificationKind kind,
    required String title,
    required String body,
    String? route,
  }) {
    for (final id in accountIds) {
      notifications.insert(
        0,
        AppNotification(
          id: newId('ntf'),
          accountId: id,
          kind: kind,
          title: title,
          body: body,
          route: route,
          read: false,
          at: DateTime.now(),
        ),
      );
    }
  }

  void markNotificationRead(String id) {
    final n = notifications.where((x) => x.id == id).firstOrNull;
    if (n == null || n.read) return;
    notifications.removeWhere((x) => x.id == id);
    notifications.insert(
      0,
      AppNotification(
        id: n.id,
        accountId: n.accountId,
        kind: n.kind,
        title: n.title,
        body: n.body,
        route: n.route,
        read: true,
        at: n.at,
      ),
    );
    _commit();
  }

  void markAllNotificationsRead() {
    final id = currentAccount?.id;
    for (var i = 0; i < notifications.length; i++) {
      final n = notifications[i];
      if (n.accountId != id || n.read) continue;
      notifications[i] = AppNotification(
        id: n.id,
        accountId: n.accountId,
        kind: n.kind,
        title: n.title,
        body: n.body,
        route: n.route,
        read: true,
        at: n.at,
      );
    }
    _commit();
  }

  // ── Personal scoring ───────────────────────────────────────────────────

  List<PersonalMatch> get myPersonal {
    final id = currentAccount?.id;
    final list = personal.where((p) => p.ownerId == id).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  List<PersonalMatch> get myPersonalInProgress => myPersonal
      .where((p) => p.status == PersonalMatchStatus.inProgress)
      .toList();

  PersonalMatch? personalById(String id) =>
      personal.where((p) => p.id == id).firstOrNull;

  PersonalMatch startPersonalMatch({
    required Sport sport,
    required String format,
    required String sideA,
    required String sideB,
  }) {
    final owner = currentAccount;
    if (owner == null) throw StateError('Sign in to start a scorecard');
    final match = PersonalMatch(
      id: newId('pm'),
      ownerId: owner.id,
      sport: sport,
      formatLabel: format,
      sideNames: [sideA.trim(), sideB.trim()],
      events: [],
      rules: SportEngines.rulesFor(sport, format),
      status: PersonalMatchStatus.inProgress,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    personal.insert(0, match);
    _commit();
    return match;
  }

  /// Appends a scoring action exactly once.
  ///
  /// The event id doubles as the dedupe key, so a double tap or a retried
  /// request cannot record the same action twice (spec §6).
  void recordPersonalEvent(String matchId, ScoringEvent event) {
    final m = personalById(matchId);
    if (m == null ||
        m.ownerId != currentAccount?.id ||
        m.status != PersonalMatchStatus.inProgress) {
      return;
    }
    final id = event.id.isEmpty ? newId('ev') : event.id;
    if (m.events.any((e) => e['id'] == id)) {
      return;
    }
    m.events.add({
      ...event.toJson(),
      'id': id,
      'by': currentAccount?.id ?? event.byAccountId,
    });
    m.updatedAt = DateTime.now();
    final progress = progressOfPersonal(m);
    if (progress.isComplete) {
      m.status = PersonalMatchStatus.completed;
      m.autoCompletedReason = progress.completionReason;
    }
    _commit();
  }

  void undoPersonalEvent(String matchId) {
    final m = personalById(matchId);
    if (m == null || m.ownerId != currentAccount?.id || m.events.isEmpty) {
      return;
    }
    final wasPaused = m.status == PersonalMatchStatus.paused;
    m.events.removeLast();
    m.updatedAt = DateTime.now();
    final progress = progressOfPersonal(m);
    m.status = progress.isComplete
        ? PersonalMatchStatus.completed
        : (wasPaused
              ? PersonalMatchStatus.paused
              : PersonalMatchStatus.inProgress);
    m.autoCompletedReason = progress.isComplete
        ? progress.completionReason
        : null;
    _commit();
  }

  void updatePersonalDetails(
    String id,
    Map<String, dynamic> details, {
    List<String>? sides,
  }) {
    final m = personalById(id);
    if (m == null || m.ownerId != currentAccount?.id) {
      return;
    }
    m.details.addAll(details);
    if (m.events.isEmpty &&
        m.sport == Sport.badminton &&
        details.containsKey('discipline')) {
      m.rules['discipline'] = details['discipline'];
    }
    if (sides != null) {
      m.sideNames = sides;
    }
    m.updatedAt = DateTime.now();
    _commit();
  }

  void setPersonalStatus(String id, PersonalMatchStatus status) {
    final m = personalById(id);
    if (m == null ||
        m.ownerId != currentAccount?.id ||
        m.status == PersonalMatchStatus.completed) {
      return;
    }
    if (m.sport == Sport.futsal) {
      final progress = progressOfPersonal(m);
      String? clockAction;
      if (status != PersonalMatchStatus.inProgress &&
          progress.state['running'] == true) {
        clockAction = 'stop';
        m.details['resumeClockOnResume'] = status == PersonalMatchStatus.paused;
      } else if (status == PersonalMatchStatus.inProgress &&
          m.status == PersonalMatchStatus.paused &&
          m.details['resumeClockOnResume'] == true &&
          progress.state['phase'] == 'paused') {
        clockAction = 'resume';
        m.details['resumeClockOnResume'] = false;
      }
      if (clockAction != null) {
        m.events.add(
          ScoringEvent(
            id: newId('ev'),
            kind: 'clock',
            side: null,
            data: {'action': clockAction},
            at: DateTime.now(),
            byAccountId: currentAccount!.id,
          ).toJson(),
        );
      }
    }
    m.status = status;
    if (status == PersonalMatchStatus.completed) {
      m.autoCompletedReason = 'Ended manually; recorded score retained';
    }
    m.updatedAt = DateTime.now();
    _commit();
  }

  void replacePersonalEvent(String id, int index, ScoringEvent event) {
    final m = personalById(id);
    if (m == null ||
        m.ownerId != currentAccount?.id ||
        index < 0 ||
        index >= m.events.length) {
      return;
    }
    final wasPaused = m.status == PersonalMatchStatus.paused;
    final previous = m.events[index];
    final previousData = previous['data'] as Map? ?? {};
    m.events[index] = {
      ...event.toJson(),
      'id': previous['id'],
      'at': previous['at'],
      'data': {
        for (final key in ['batter', 'bowler', 'player', 'dismissal'])
          if (previousData.containsKey(key)) key: previousData[key],
        ...event.data,
      },
    };
    final progress = progressOfPersonal(m);
    m.status = progress.isComplete
        ? PersonalMatchStatus.completed
        : (wasPaused
              ? PersonalMatchStatus.paused
              : PersonalMatchStatus.inProgress);
    m.autoCompletedReason = progress.isComplete
        ? progress.completionReason
        : null;
    m.updatedAt = DateTime.now();
    _commit();
  }

  void deletePersonalMatch(String matchId) {
    personal.removeWhere(
      (p) => p.id == matchId && p.ownerId == currentAccount?.id,
    );
    _commit();
  }

  MatchProgress progressOfPersonal(PersonalMatch m) => SportEngines.progressOf(
    sport: m.sport,
    sides: m.sideNames,
    rules: SportEngines.rulesOr(m.sport, m.rules),
    rawEvents: m.events,
  );

  // ── Squads ─────────────────────────────────────────────────────────────

  List<Squad> get mySquads {
    final id = currentAccount?.id;
    return squads.where((s) => s.ownerId == id).toList();
  }

  List<Squad> squadsFor(Sport sport, EntryType type) =>
      mySquads.where((s) => s.sport == sport && s.type == type).toList();

  Squad createSquad({
    required String name,
    required Sport sport,
    required EntryType type,
    required List<String> memberIds,
  }) {
    final owner = currentAccount;
    if (owner == null) throw StateError('Sign in to create a squad');
    final members = {owner.id, ...memberIds}.toList();
    final squad = Squad(
      id: newId('sqd'),
      ownerId: owner.id,
      name: name.trim(),
      sport: sport,
      type: type,
      memberAccountIds: members,
      createdAt: DateTime.now(),
    );
    squads.insert(0, squad);
    _commit();
    return squad;
  }

  void addSquadMember(String squadId, String accountId) {
    final s = squads.where((x) => x.id == squadId).firstOrNull;
    if (s == null || s.memberAccountIds.contains(accountId)) return;
    s.memberAccountIds.add(accountId);
    _commit();
  }

  void removeSquadMember(String squadId, String accountId) {
    final s = squads.where((x) => x.id == squadId).firstOrNull;
    if (s == null) return;
    s.memberAccountIds.remove(accountId);
    _commit();
  }

  // ── Tournaments & entries ──────────────────────────────────────────────

  Tournament? tournamentById(String id) =>
      tournaments.where((t) => t.id == id).firstOrNull;

  Fixture? fixtureById(String id) =>
      fixtures.where((f) => f.id == id).firstOrNull;

  Map<String, Entry> get entriesById => {for (final e in entries) e.id: e};

  List<Entry> entriesFor(String tournamentId) =>
      entries.where((e) => e.tournamentId == tournamentId).toList();

  List<Entry> confirmedEntriesFor(String tournamentId) => entries
      .where(
        (e) =>
            e.tournamentId == tournamentId && e.status == EntryStatus.confirmed,
      )
      .toList();

  Entry? myEntryFor(String tournamentId) {
    final id = currentAccount?.id;
    if (id == null) return null;
    return entries
        .where(
          (e) =>
              e.tournamentId == tournamentId && e.memberAccountIds.contains(id),
        )
        .firstOrNull;
  }

  int confirmedCountFor(Tournament t) => confirmedEntriesFor(t.id).length;

  bool canRegisterFor(Tournament t) =>
      t.status == TournamentStatus.open &&
      confirmedEntriesFor(t.id).length < t.registrationLimit &&
      myEntryFor(t.id) == null;

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
  }) async {
    final org = currentAccount;
    if (org == null) return;
    final t = Tournament(
      id: newId('trn'),
      organizerId: org.id,
      name: name.trim(),
      city: city,
      sport: sport,
      formatLabel: format == TournamentFormat.knockout
          ? 'Knockout · ${rulesSummary.split('·').first.trim()}'
          : 'Group play · ${rulesSummary.split('·').first.trim()}',
      format: format,
      entryType: entryType,
      startsAt: startsAt,
      endsAt: endsAt,
      registrationLimit: registrationLimit,
      entryFee: entryFee,
      matchRules: rulesSummary,
      rules: rules,
      status: publishNow ? TournamentStatus.open : TournamentStatus.draft,
      createdAt: DateTime.now(),
    );
    tournaments.insert(0, t);
    _commit();
  }

  void setTournamentStatus(String tournamentId, TournamentStatus status) {
    final t = tournamentById(tournamentId);
    if (t == null) return;
    t.status = status;
    _commit();
  }

  Future<void> submitEntry({
    required String tournamentId,
    String? squadId,
    List<String>? memberIds,
  }) async {
    final me = currentAccount;
    final t = tournamentById(tournamentId);
    if (me == null || t == null) return;
    if (myEntryFor(tournamentId) != null) return;

    final squad = squadId == null
        ? null
        : squads.where((s) => s.id == squadId).firstOrNull;
    final members = squad?.memberAccountIds ?? memberIds ?? [me.id];
    final label =
        squad?.name ??
        (members.length > 1
            ? members
                  .map(
                    (m) => accountById(m)?.displayName.split(' ').first ?? '?',
                  )
                  .join(' / ')
            : me.displayName);

    entries.add(
      Entry(
        id: newId('ent'),
        tournamentId: tournamentId,
        squadId: squadId,
        captainAccountId: me.id,
        label: label,
        memberAccountIds: members.isEmpty ? [me.id] : members,
        status: EntryStatus.pending,
        submittedAt: DateTime.now(),
      ),
    );

    _notify(
      [t.organizerId],
      kind: NotificationKind.entryDecision,
      title: 'New entry to review',
      body: '$label registered for ${t.name}.',
      route: 'organizer',
    );
    _commit();
  }

  Future<void> withdrawEntry(String entryId) async {
    final e = entries.where((x) => x.id == entryId).firstOrNull;
    if (e == null) return;
    e.status = EntryStatus.withdrawn;
    _commit();
  }

  Future<void> decideEntry(
    String entryId, {
    required bool approve,
    String? note,
  }) async {
    final e = entries.where((x) => x.id == entryId).firstOrNull;
    if (e == null) return;
    final t = tournamentById(e.tournamentId);
    e.status = approve ? EntryStatus.confirmed : EntryStatus.rejected;
    e.decisionNote = note;
    if (t != null) {
      _notify(
        [e.captainAccountId, ...e.memberAccountIds],
        kind: NotificationKind.entryDecision,
        title: approve ? 'Entry confirmed' : 'Entry not accepted',
        body:
            '${e.label} · ${t.name}${note == null || note.isEmpty ? '' : ' - $note'}',
        route: 'tournaments',
      );
    }
    _commit();
  }

  /// Publishes the draw. Only confirmed entries take part (spec §4.3).
  Future<int> generateDraw(String tournamentId) async {
    final t = tournamentById(tournamentId);
    if (t == null) return 0;
    final confirmed = confirmedEntriesFor(tournamentId);
    if (confirmed.length < 2) return 0;

    // Keep any already-published results out of danger: refuse to redraw.
    if (fixtures.any(
      (f) =>
          f.tournamentId == tournamentId && f.status == FixtureStatus.published,
    )) {
      return 0;
    }

    fixtures.removeWhere((f) => f.tournamentId == tournamentId);
    final scorerPool = accounts
        .where((a) => a.has(UserRole.scorer))
        .map((a) => a.id)
        .toList();
    final draw = t.format == TournamentFormat.knockout
        ? TournamentEngine.knockoutDraw(
            tournament: t,
            confirmed: confirmed,
            scorerPool: scorerPool,
          )
        : TournamentEngine.groupDraw(
            tournament: t,
            confirmed: confirmed,
            groupCount: confirmed.length >= 6 ? 2 : 2,
            scorerPool: scorerPool,
          );

    fixtures.addAll(draw);
    t.status = TournamentStatus.inProgress;

    final assigned = <String, int>{};
    for (final f in draw) {
      for (final s in f.scorerAccountIds) {
        assigned[s] = (assigned[s] ?? 0) + 1;
      }
    }
    for (final entry in assigned.entries) {
      _notify(
        [entry.key],
        kind: NotificationKind.scorerAssignment,
        title: 'Fixtures assigned to you',
        body: 'You are scoring ${entry.value} fixture(s) in ${t.name}.',
        route: 'scorer',
      );
    }
    _commit();
    return draw.length;
  }

  // ── Fixtures: assignment, scoring, publishing ──────────────────────────

  List<Fixture> fixturesFor(String tournamentId) =>
      fixtures.where((f) => f.tournamentId == tournamentId).toList();

  /// Fixtures where the signed-in account may record official scores.
  List<Fixture> get myScoringFixtures {
    final id = currentAccount?.id;
    if (id == null) return [];
    return fixtures
        .where(
          (f) =>
              f.scorerAccountIds.contains(id) &&
              f.status != FixtureStatus.published,
        )
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  List<Fixture> get myOrganizerFixtures {
    final id = currentAccount?.id;
    final mine = tournaments
        .where((t) => t.organizerId == id)
        .map((t) => t.id)
        .toSet();
    return fixtures.where((f) => mine.contains(f.tournamentId)).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  List<Fixture> get fixturesAwaitingReview {
    final id = currentAccount?.id;
    final mine = tournaments
        .where((t) => t.organizerId == id)
        .map((t) => t.id)
        .toSet();
    return fixtures
        .where(
          (f) =>
              mine.contains(f.tournamentId) &&
              f.status == FixtureStatus.submitted,
        )
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  List<String> sideLabelsOf(Fixture f) => [
    OfficialResults.resolve(f.home, fixtures, entriesById).label,
    OfficialResults.resolve(f.away, fixtures, entriesById).label,
  ];

  String sideLabel(Fixture f, int index) => sideLabelsOf(f)[index.clamp(0, 1)];

  MatchProgress progressOfFixture(Fixture f) => SportEngines.progressOf(
    sport: tournamentById(f.tournamentId)?.sport ?? Sport.cricket,
    sides: sideLabelsOf(f),
    rules: SportEngines.rulesOr(
      tournamentById(f.tournamentId)?.sport ?? Sport.cricket,
      f.rules,
    ),
    rawEvents: f.events,
  );

  String get _actorId => currentAccount?.id ?? 'unknown';

  void assignScorer(String fixtureId, String accountId) {
    final f = fixtureById(fixtureId);
    if (f == null) return;
    if (!f.scorerAccountIds.contains(accountId)) {
      f.scorerAccountIds.add(accountId);
      // Access transfers without touching the recorded events (spec §4.5).
      final t = tournamentById(f.tournamentId);
      _notify(
        [accountId],
        kind: NotificationKind.scorerAssignment,
        title: 'New scoring assignment',
        body:
            '${t?.name ?? 'Tournament'} · ${f.stage}. '
            '${f.events.isEmpty ? 'No entries yet.' : '${f.events.length} entries already recorded.'}',
        route: 'scorer',
      );
    }
    _commit();
  }

  void replaceScorer(String fixtureId, String fromId, String toId) {
    final f = fixtureById(fixtureId);
    if (f == null) return;
    f.scorerAccountIds.remove(fromId);
    if (!f.scorerAccountIds.contains(toId)) f.scorerAccountIds.add(toId);
    final t = tournamentById(f.tournamentId);
    _notify(
      [toId],
      kind: NotificationKind.scorerAssignment,
      title: 'Scoring access transferred',
      body:
          '${t?.name ?? 'Tournament'} · ${f.stage}. '
          '${f.events.length} recorded entries carried forward.',
      route: 'scorer',
    );
    _commit();
  }

  void removeScorer(String fixtureId, String accountId) {
    final f = fixtureById(fixtureId);
    if (f == null) return;
    f.scorerAccountIds.remove(accountId);
    _commit();
  }

  /// Called when a scorer opens the fixture: marks it live and starts the log.
  void startOfficialScoring(String fixtureId) {
    final f = fixtureById(fixtureId);
    if (f == null ||
        !hasRole(UserRole.scorer) ||
        !f.scorerAccountIds.contains(currentAccount?.id)) {
      return;
    }
    if (f.status == FixtureStatus.upcoming) {
      f.status = FixtureStatus.live;
      f.startedAt = DateTime.now();
      f.submittedByScorerId = _actorId;
      _commit();
    }
  }

  void recordOfficialEvent(String fixtureId, ScoringEvent event) {
    final f = fixtureById(fixtureId);
    if (f == null ||
        !hasRole(UserRole.scorer) ||
        !f.scorerAccountIds.contains(currentAccount?.id)) {
      return;
    }
    if (f.status == FixtureStatus.published ||
        f.status == FixtureStatus.walkover) {
      return;
    }
    if (f.status == FixtureStatus.upcoming) {
      f.status = FixtureStatus.live;
      f.startedAt = DateTime.now();
    }
    final id = event.id.isEmpty ? newId('ev') : event.id;
    if (f.events.any((e) => e['id'] == id)) {
      return;
    }
    f.events.add({...event.toJson(), 'id': id, 'by': _actorId});
    f.submittedByScorerId = _actorId;
    _commit();
  }

  void undoOfficialEvent(String fixtureId) {
    final f = fixtureById(fixtureId);
    if (f == null ||
        !hasRole(UserRole.scorer) ||
        !f.scorerAccountIds.contains(currentAccount?.id)) {
      return;
    }
    if (f.events.isEmpty) {
      return;
    }
    if (f.status == FixtureStatus.published ||
        f.status == FixtureStatus.walkover) {
      return;
    }
    f.events.removeLast();
    _commit();
  }

  /// Scorer hands the finished match to the organizer for review.
  void submitOfficialResult(String fixtureId) {
    final f = fixtureById(fixtureId);
    if (f == null ||
        !hasRole(UserRole.scorer) ||
        !f.scorerAccountIds.contains(currentAccount?.id)) {
      return;
    }
    if (f.status == FixtureStatus.published) {
      return;
    }
    f.status = FixtureStatus.submitted;
    f.submittedByScorerId = _actorId;
    final t = tournamentById(f.tournamentId);
    if (t != null) {
      _notify(
        [t.organizerId],
        kind: NotificationKind.resultSubmitted,
        title: 'Score submitted for review',
        body: '${t.name} · ${f.stage} is waiting for your review.',
        route: 'organizer',
      );
    }
    _commit();
  }

  /// Organizer publishes. This is the only path that moves brackets or tables.
  void publishOfficialResult(String fixtureId, {String? correctionReason}) {
    final f = fixtureById(fixtureId);
    if (f == null) return;
    final t = tournamentById(f.tournamentId);
    if (t == null) return;

    final progress = progressOfFixture(f);
    final fresh = OfficialResults.fromProgress(
      progress,
      publishedById: _actorId,
    );

    if (f.result != null) {
      // Correction keeps the previous result, the reason and who changed it.
      f.corrections.add(
        ResultCorrection(
          id: newId('corr'),
          previous: f.result!,
          current: fresh,
          reason: (correctionReason == null || correctionReason.trim().isEmpty)
              ? 'Correction without a stated reason'
              : correctionReason.trim(),
          byAccountId: _actorId,
          at: DateTime.now(),
        ),
      );
      final players = <String>{
        ...entriesFor(t.id).expand((e) => e.memberAccountIds),
      };
      _notify(
        players,
        kind: NotificationKind.resultCorrected,
        title: 'Official result corrected',
        body:
            '${t.name} · ${f.stage}. Reason: '
            '${(correctionReason ?? '').trim().isEmpty ? 'not stated' : correctionReason!.trim()}',
        route: 'matchCenter',
      );
    } else {
      final players = <String>{
        ...entriesFor(t.id).expand((e) => e.memberAccountIds),
      };
      _notify(
        players,
        kind: NotificationKind.resultPublished,
        title: 'Official result published',
        body: '${t.name} · ${f.stage}: ${fresh.headline}',
        route: 'matchCenter',
      );
    }

    f.result = fresh;
    f.status = FixtureStatus.published;
    f.completedAt = DateTime.now();
    _commit();
  }

  /// Organizer records a walkover; the bracket advances the same way.
  void recordWalkover(String fixtureId, int winnerIndex, String reason) {
    final f = fixtureById(fixtureId);
    if (f == null) return;
    final t = tournamentById(f.tournamentId);
    final fresh = OfficialResult(
      sideScores: [winnerIndex == 0 ? 'W' : 'L', winnerIndex == 0 ? 'L' : 'W'],
      sideValues: [winnerIndex == 0 ? 1 : 0, winnerIndex == 0 ? 0 : 1],
      winnerIndex: winnerIndex,
      headline: '${sideLabel(f, winnerIndex)} won by walkover',
      detail: reason.trim().isEmpty
          ? 'Walkover'
          : 'Walkover · ${reason.trim()}',
      publishedAt: DateTime.now(),
      publishedById: _actorId,
      walkover: true,
    );
    if (f.result != null) {
      f.corrections.add(
        ResultCorrection(
          id: newId('corr'),
          previous: f.result!,
          current: fresh,
          reason:
              'Walkover recorded'
              '${reason.trim().isEmpty ? '' : ': ${reason.trim()}'}',
          byAccountId: _actorId,
          at: DateTime.now(),
        ),
      );
    }
    f.result = fresh;
    f.status = FixtureStatus.walkover;
    f.completedAt = DateTime.now();
    if (t != null) {
      _notify(
        entriesFor(t.id).expand((e) => e.memberAccountIds),
        kind: NotificationKind.resultPublished,
        title: 'Walkover recorded',
        body: '${t.name} · ${f.stage}: ${fresh.headline}',
        route: 'matchCenter',
      );
    }
    _commit();
  }

  void updateFixtureSchedule(
    String fixtureId, {
    DateTime? scheduledAt,
    String? venue,
    String? scorerId,
  }) {
    final f = fixtureById(fixtureId);
    if (f == null) return;
    final t = tournamentById(f.tournamentId);
    final changes = <String>[];
    if (scheduledAt != null && scheduledAt != f.scheduledAt) {
      f.scheduledAt = scheduledAt;
      changes.add('new time');
    }
    if (venue != null && venue != f.venue) {
      f.venue = venue;
      changes.add('new venue');
    }
    if (scorerId != null && !f.scorerAccountIds.contains(scorerId)) {
      f.scorerAccountIds.add(scorerId);
      changes.add('scorer assigned');
    }
    if (changes.isNotEmpty && t != null) {
      final players = entriesFor(t.id).expand((e) => e.memberAccountIds);
      _notify(
        players,
        kind: NotificationKind.fixtureChange,
        title: 'Fixture updated',
        body: '${t.name} · ${f.stage}: ${changes.join(', ')}.',
        route: 'matchCenter',
      );
    }
    _commit();
  }

  void raiseDispute(String fixtureId, String note) {
    final f = fixtureById(fixtureId);
    if (f == null) return;
    f.disputeNote = note.trim();
    f.disputeRaisedBy = _actorId;
    f.disputeResolved = false;
    final tournament = tournamentById(f.tournamentId);
    _notify(
      [if (tournament != null) tournament.organizerId],
      kind: NotificationKind.dispute,
      title: 'Result dispute raised',
      body:
          '${tournament?.name ?? 'Tournament'} · ${f.stage}: '
          '${note.trim()}',
      route: 'organizer',
    );
    _commit();
  }

  void resolveDispute(
    String fixtureId, {
    required bool upholdResult,
    String? note,
  }) {
    final f = fixtureById(fixtureId);
    if (f == null) return;
    f.disputeResolved = true;
    final raiser = f.disputeRaisedBy;
    if (raiser != null) {
      _notify(
        [raiser],
        kind: NotificationKind.dispute,
        title: upholdResult
            ? 'Dispute reviewed - result stands'
            : 'Dispute reviewed',
        body:
            '${tournamentById(f.tournamentId)?.name ?? 'Tournament'} · ${f.stage}'
            '${note == null || note.isEmpty ? '' : ': $note'}',
        route: 'matchCenter',
      );
    }
    _commit();
  }

  // ── Organizer review desk ──────────────────────────────────────────────

  /// Disputes on fixtures that belong to tournaments the signed-in
  /// organizer runs.
  List<Fixture> get myOrganizerDisputes {
    final me = currentAccount?.id;
    if (me == null) return [];
    final mine = tournaments
        .where((t) => t.organizerId == me)
        .map((t) => t.id)
        .toSet();
    return fixtures
        .where(
          (f) =>
              f.disputeNote != null &&
              !f.disputeResolved &&
              mine.contains(f.tournamentId),
        )
        .toList();
  }

  // ── Derived views used by the UI ───────────────────────────────────────

  List<Tournament> get liveTournaments {
    const order = {
      TournamentStatus.open: 0,
      TournamentStatus.inProgress: 1,
      TournamentStatus.draft: 2,
      TournamentStatus.completed: 3,
    };
    final list = tournaments.toList()
      ..sort((a, b) {
        final byStatus = order[a.status]!.compareTo(order[b.status]!);
        return byStatus != 0 ? byStatus : a.startsAt.compareTo(b.startsAt);
      });
    return list;
  }

  List<Fixture> get publicFixtures {
    final list =
        fixtures
            .where(
              (f) =>
                  f.status != FixtureStatus.cancelled &&
                  f.status != FixtureStatus.walkover,
            )
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return list;
  }

  List<Fixture> get liveFixtures =>
      publicFixtures.where((f) => f.status == FixtureStatus.live).toList();

  List<Fixture> get completedFixtures =>
      publicFixtures.where((f) => f.status == FixtureStatus.published).toList()
        ..sort(
          (a, b) => (b.completedAt ?? b.scheduledAt).compareTo(
            a.completedAt ?? a.scheduledAt,
          ),
        );

  /// Upcoming and submitted fixtures, soonest first.
  List<Fixture> get scheduledFixtures => publicFixtures
      .where(
        (f) =>
            f.status == FixtureStatus.upcoming ||
            f.status == FixtureStatus.submitted ||
            f.status == FixtureStatus.live,
      )
      .toList();

  List<Fixture> officialMatchesPlayed() {
    final me = currentAccount?.id;
    if (me == null) return [];
    final myEntryIds = entries
        .where((e) => e.memberAccountIds.contains(me))
        .map((e) => e.id)
        .toSet();
    return fixtures
        .where(
          (f) =>
              f.status == FixtureStatus.published &&
              (myEntryIds.contains(f.home.entryId) ||
                  myEntryIds.contains(f.away.entryId)),
        )
        .toList()
      ..sort(
        (a, b) => (b.completedAt ?? b.scheduledAt).compareTo(
          a.completedAt ?? a.scheduledAt,
        ),
      );
  }

  Tournament? tournamentOf(Fixture f) => tournamentById(f.tournamentId);

  /// Fixtures the signed-in account is competing in, as a player.
  List<Fixture> get myFixtures {
    final me = currentAccount?.id;
    if (me == null) return [];
    final myEntryIds = entries
        .where(
          (e) =>
              e.memberAccountIds.contains(me) &&
              e.status != EntryStatus.withdrawn,
        )
        .map((e) => e.id)
        .toSet();
    return fixtures
        .where(
          (f) =>
              myEntryIds.contains(f.home.entryId) ||
              myEntryIds.contains(f.away.entryId),
        )
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  /// Tournaments the signed-in account has an active entry in.
  List<Tournament> get myTournaments {
    final me = currentAccount?.id;
    if (me == null) return [];
    final ids = entries
        .where(
          (e) =>
              e.memberAccountIds.contains(me) &&
              e.status != EntryStatus.withdrawn,
        )
        .map((e) => e.tournamentId)
        .toSet();
    return tournaments.where((t) => ids.contains(t.id)).toList();
  }

  List<StandingRow> standingsFor(Tournament t) => TournamentEngine.standings(
    fixtures: fixturesFor(t.id),
    entriesById: entriesById,
    qualifyTop: 2,
  );

  List<List<Fixture>> roundsFor(Tournament t) =>
      TournamentEngine.roundsOf(fixturesFor(t.id));

  List<Tournament> tournamentsForOrganizer(String? accountId) =>
      tournaments.where((t) => t.organizerId == accountId).toList();

  List<Entry> pendingEntriesFor(String tournamentId) =>
      entriesFor(tournamentId)
          .where((e) => e.status == EntryStatus.pending)
          .toList();

  /// Players available to invite into a squad.
  List<Account> get otherPlayers {
    final id = currentAccount?.id;
    return accounts.where((a) => a.has(UserRole.player) && a.id != id).toList();
  }

  /// Squads (teams) the given account belongs to.
  List<Squad> squadsOf(String accountId) =>
      squads.where((s) => s.memberAccountIds.contains(accountId)).toList();

  /// Sports an account has real exposure to: official fixtures they appear in,
  /// plus the sports of the teams they are on.
  List<Sport> sportsPlayedBy(String accountId) {
    final myEntryIds = entries
        .where(
          (e) =>
              e.memberAccountIds.contains(accountId) &&
              e.status != EntryStatus.withdrawn,
        )
        .map((e) => e.id)
        .toSet();
    final found = <Sport>{};
    for (final f in fixtures) {
      if (!myEntryIds.contains(f.home.entryId) &&
          !myEntryIds.contains(f.away.entryId)) {
        continue;
      }
      final tournament = tournamentOf(f);
      if (tournament != null) found.add(tournament.sport);
    }
    found.addAll(squadsOf(accountId).map((s) => s.sport));
    return Sport.values.where(found.contains).toList();
  }

  /// Official fixtures the given account has appeared in.
  List<Fixture> appearancesOf(String accountId) {
    final myEntryIds = entries
        .where(
          (e) =>
              e.memberAccountIds.contains(accountId) &&
              e.status != EntryStatus.withdrawn,
        )
        .map((e) => e.id)
        .toSet();
    return fixtures
        .where(
          (f) =>
              myEntryIds.contains(f.home.entryId) ||
              myEntryIds.contains(f.away.entryId),
        )
        .toList();
  }

  /// Simple discovery filter shared by Home and Match Center (spec §5).
  List<Tournament> filterTournaments({
    Sport? sport,
    bool myEntriesOnly = false,
  }) {
    final me = currentAccount?.id;
    return liveTournaments.where((t) {
      if (sport != null && t.sport != sport) return false;
      if (myEntriesOnly) {
        final hasEntry = entries.any(
          (e) =>
              e.tournamentId == t.id &&
              me != null &&
              e.memberAccountIds.contains(me) &&
              e.status != EntryStatus.withdrawn,
        );
        if (!hasEntry) return false;
      }
      return true;
    }).toList();
  }

  List<Fixture> filterFixtures({Sport? sport, DateTime? day}) {
    return scheduledFixtures.where((f) {
      final t = tournamentById(f.tournamentId);
      if (t == null) return false;
      if (sport != null && t.sport != sport) return false;
      if (day != null) {
        final same =
            f.scheduledAt.year == day.year &&
            f.scheduledAt.month == day.month &&
            f.scheduledAt.day == day.day;
        if (!same) return false;
      }
      return true;
    }).toList();
  }
}
