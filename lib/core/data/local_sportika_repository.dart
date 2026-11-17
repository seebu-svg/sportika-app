import 'package:sportika/shared/models/profile_setup.dart';
// The store implements all nine repository interfaces, so every member below
// is an interface implementation. Annotating one hundred members with
// `@override` would obscure the code without adding information.
// ignore_for_file: annotate_overrides

import 'package:flutter/foundation.dart';

import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/models/community_game.dart';
import 'package:sportika/shared/data/seed.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/official_result.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/models/tournament_engine.dart';
import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/core/data/profile_photo.dart';

/// The single source of truth for the prototype.
///
/// Everything is persisted to one JSON document after each mutation, so a
/// personal scorecard survives closing the app, and official scoring resumes
/// from the last saved event (spec §2.3, §6).
class LocalSportikaRepository extends ChangeNotifier
    implements
        FixtureRepository,
        GameRepository,
        MatchRepository,
        NotificationRepository,
        PersonalGamesRepository,
        PreferencesRepository,
        ProfileRepository,
        SessionRepository,
        TeamRepository,
        TournamentRepository {
  LocalSportikaRepository(this._storage, {bool seedOnFirstRun = true})
    // ignore: prefer_initializing_formals
    : seedOnFirstRun = seedOnFirstRun;

  final LocalStorage _storage;

  /// Whether this build is allowed to fall back on the fictional Karachi world.
  ///
  /// A live build passes false: with no saved document it starts empty and
  /// shows only what PostgreSQL holds, so a real member never sees a seeded
  /// tournament presented as a record. Demo builds keep the seed, which is the
  /// whole point of an internal preview.
  final bool seedOnFirstRun;

  /// The device document handle. Exposed so adapters that own a separate
  /// document (the demo billing ledger) write through the same storage instead
  /// of opening a second one.
  LocalStorage get storage => _storage;

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
    final wasMember = game.members.contains(id);
    if (wasMember) {
      game.members.remove(id);
    } else if (game.members.length < game.capacity) {
      game.members.add(id);
    } else {
      return;
    }
    _paintThenPersist(
      undo: () => wasMember ? game.members.add(id) : game.members.remove(id),
    );
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
      _adopt(_freshWorld());
      if (_storage.recoveredFromCorruption) {
        _storageNotice = seedOnFirstRun
            ? 'Saved data could not be read, so the demo world was rebuilt.'
            : 'Saved data could not be read, so the on-device copy was reset.';
      }
    } else {
      try {
        _decode(raw);
      } catch (_) {
        // A corrupt document should never brick the prototype.
        _adopt(_freshWorld());
        _storageNotice = seedOnFirstRun
            ? 'Saved data could not be read, so the demo world was rebuilt.'
            : 'Saved data could not be read, so the on-device copy was reset.';
      }
    }
    final sessionId = _storage.readSessionAccountId();
    currentAccount = accounts.where((a) => a.id == sessionId).firstOrNull;
    onboardingSeen = _storage.readOnboardingSeen();
    ready = true;
    notifyListeners();
    await _persist();
  }

  @override
  Future<void> reload() => load();

  // The device document is already in memory before the first frame: there is
  // no request in flight and no network that can fail, so a live section asks
  // the server while this store answers with the plain re-read.
  @override
  bool get loading => false;

  @override
  String? get lastError => null;

  @override
  Future<void> refresh() => reload();

  /// The world a fresh or corrupt document starts from.
  SeedWorld _freshWorld() => seedOnFirstRun ? buildSeed() : emptySeedWorld();

  void _adopt(SeedWorld world) {
    preferences = {};
    games = seedOnFirstRun ? seedCommunityGames() : <CommunityGame>[];
    accounts = world.accounts;
    squads = world.squads;
    tournaments = world.tournaments;
    entries = world.entries;
    fixtures = world.fixtures;
    personal = world.personal;
    notifications = world.notifications;
    matches = seedOnFirstRun ? matchSeed(world.accounts) : <SportMatch>[];
  }

  void _decode(Map<String, dynamic> raw) {
    List<T> listOf<T>(String key, T Function(Map<String, dynamic>) parse) =>
        (raw[key] as List<dynamic>? ?? [])
            .map((e) => parse(Map<String, dynamic>.from(e as Map)))
            .toList();

    games = raw.containsKey('games')
        ? listOf('games', CommunityGame.fromJson)
        : (seedOnFirstRun ? seedCommunityGames() : <CommunityGame>[]);
    preferences = Map<String, bool>.from(raw['preferences'] as Map? ?? {});
    accounts = listOf('accounts', Account.fromJson);
    squads = listOf('squads', Squad.fromJson);
    tournaments = listOf('tournaments', Tournament.fromJson);
    entries = listOf('entries', Entry.fromJson);
    fixtures = listOf('fixtures', Fixture.fromJson);
    personal = listOf('personal', PersonalMatch.fromJson);
    notifications = listOf('notifications', AppNotification.fromJson);
    final storedPrefs = raw['notificationPreferences'];
    if (storedPrefs is Map) {
      _notificationPreferences = NotificationPreferences.fromJson(
        Map<String, dynamic>.from(storedPrefs),
      );
    }
    matches = raw.containsKey('matches')
        ? listOf('matches', SportMatch.fromJson)
        : matchSeed(accounts);
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
    'notificationPreferences': _notificationPreferences.toJson(),
    'matches': matches.map((e) => e.toJson()).toList(),
  };

  Future<void> _persist() => _storage.writeState(toJson());

  static const String _saveFailureNotice =
      'The last change could not be saved on this device. It was undone so the '
      'screen still matches your saved data.';

  /// Every mutation is painted first and written afterwards, so a tap never
  /// waits on disk. If the write fails the change is rolled back through [undo]
  /// and the player is told, instead of the screen promising a save that did
  /// not happen.
  void _paintThenPersist({required VoidCallback undo}) {
    notifyListeners();
    _settle(undo);
  }

  /// Awaitable form for the mutations whose callers already wait.
  Future<void> _commitSettled({required VoidCallback undo}) async {
    notifyListeners();
    await _settle(undo);
  }

  Future<bool> _settle(VoidCallback undo) async {
    try {
      await _persist();
      return true;
    } catch (_) {
      undo();
      _storageNotice = _saveFailureNotice;
      notifyListeners();
      return false;
    }
  }

  void _commit() {
    notifyListeners();
    _settle(() {});
  }

  // ── Session & roles ────────────────────────────────────────────────────

  bool get isSignedIn => currentAccount != null;

  bool hasRole(UserRole role) => currentAccount?.has(role) ?? false;

  /// Every signed-in account may create tournaments.
  bool get canOrganize => isSignedIn;

  Account? accountById(String? id) =>
      accounts.where((a) => a.id == id).firstOrNull;

  /// Nothing to fetch: the whole document is decoded before the first session
  /// can name an account.
  Future<void> hydrateAccount(String accountId) async {}

  Future<void> signIn(String accountId) async {
    final account = accountById(accountId);
    if (account == null) throw StateError('Account profile is unavailable.');
    await _storage.writeSessionAccountId(accountId);
    currentAccount = account;
    notifyListeners();
  }

  Account? accountByEmail(String email) {
    final needle = email.trim().toLowerCase();
    return accounts.where((a) => a.email.toLowerCase() == needle).firstOrNull;
  }

  Future<void> markOnboardingSeen() async {
    if (onboardingSeen) return;
    await _storage.writeOnboardingSeen(true);
    onboardingSeen = true;
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

  /// Commits the reviewed profile together; failed writes restore all fields.
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
    final a = currentAccount;
    if (a == null) throw StateError('Sign in before saving your profile.');
    final before = Account.fromJson(a.toJson());
    final wasSeen = onboardingSeen;
    try {
      a.displayName = displayName.trim();
      a.city = city.trim();
      a.handle = handle.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();
      a.bio = bio.trim();
      a.sports = Set.of(sports);
      a.levels = Map.of(levels);
      a.playStyle = playStyle;
      a.avatar = avatar;
      if (email != null) a.email = email.trim();
      a.dateOfBirth = dateOfBirth ?? a.dateOfBirth;
      a.gender = gender;
      a.playingPositions = Map.of(playingPositions ?? {});
      a.playingPreferencesSkipped = playingPreferencesSkipped;
      a.setupComplete = true;
      await _storage.writeOnboardingSeen(true);
      await _persist();
      onboardingSeen = true;
      notifyListeners();
    } catch (_) {
      a.displayName = before.displayName;
      a.city = before.city;
      a.handle = before.handle;
      a.bio = before.bio;
      a.sports = before.sports;
      a.levels = before.levels;
      a.playStyle = before.playStyle;
      a.avatar = before.avatar;
      a.email = before.email;
      a.dateOfBirth = before.dateOfBirth;
      a.gender = before.gender;
      a.playingPositions = before.playingPositions;
      a.playingPreferencesSkipped = before.playingPreferencesSkipped;
      a.setupComplete = before.setupComplete;
      onboardingSeen = wasSeen;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> signOut() async {
    currentAccount = null;
    notifyListeners();
    await _storage.writeSessionAccountId(null);
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

  /// Saves only the fields Me → Personal information edits. Email, the avatar
  /// and the sport set have their own paths, so a half-filled form can never
  /// overwrite something the member did not touch.
  Future<void> applyProfileInformation({
    required String displayName,
    required String city,
    required String bio,
    required DateTime dateOfBirth,
    ProfileGender? gender,
    required PlayStyle playStyle,
  }) async {
    final a = currentAccount;
    if (a == null) throw StateError('Sign in before saving your profile.');
    final before = Account.fromJson(a.toJson());
    a
      ..displayName = displayName.trim()
      ..city = city.trim()
      ..bio = bio.trim()
      ..dateOfBirth = dateOfBirth
      ..gender = gender
      ..playStyle = playStyle;
    try {
      await _persist();
      notifyListeners();
    } catch (_) {
      _restoreAccount(a, before);
      notifyListeners();
      rethrow;
    }
  }

  /// Renames the handle. The device world has no unique index, so the check is
  /// made here to keep the same answer the server gives (username_taken).
  Future<void> applyProfileHandle(String handle) async {
    final a = currentAccount;
    if (a == null) throw StateError('Sign in before saving your profile.');
    final wanted = normalizeProfileHandle(handle);
    final taken = accounts.any(
      (other) => other.id != a.id && other.username.toLowerCase() == wanted,
    );
    if (taken) {
      throw StateError('That username is already taken. Try another.');
    }
    final before = a.handle;
    a.handle = wanted;
    try {
      await _persist();
      notifyListeners();
    } catch (_) {
      a.handle = before;
      notifyListeners();
      rethrow;
    }
  }

  /// Replaces the preferred-sport set. A skipped preference step keeps the
  /// sports but drops every level and position, matching the server payload.
  Future<void> applySportsPreferences({
    required Set<Sport> sports,
    required Map<String, PlayingLevel> levels,
    required Map<String, String> positions,
    required bool skipped,
  }) async {
    final a = currentAccount;
    if (a == null) throw StateError('Sign in before saving your profile.');
    final before = Account.fromJson(a.toJson());
    a
      ..sports = Set.of(sports)
      ..levels = skipped ? <String, PlayingLevel>{} : Map.of(levels)
      ..playingPositions = skipped ? <String, String>{} : Map.of(positions)
      ..playingPreferencesSkipped = skipped;
    try {
      await _persist();
      notifyListeners();
    } catch (_) {
      _restoreAccount(a, before);
      notifyListeners();
      rethrow;
    }
  }

  static void _restoreAccount(Account a, Account before) {
    a
      ..displayName = before.displayName
      ..email = before.email
      ..city = before.city
      ..handle = before.handle
      ..bio = before.bio
      ..dateOfBirth = before.dateOfBirth
      ..gender = before.gender
      ..playingPositions = before.playingPositions
      ..playingPreferencesSkipped = before.playingPreferencesSkipped
      ..sports = before.sports
      ..levels = before.levels
      ..playStyle = before.playStyle
      ..avatar = before.avatar
      ..photoPath = before.photoPath
      ..photoUrl = before.photoUrl
      ..setupComplete = before.setupComplete;
  }

  /// Moves the signed-in account's picture reference. The bytes belong to the
  /// profile photo store, so a save that the device refuses has to put the old
  /// reference back and say so: the caller deletes the freshly written file
  /// only after this resolves.
  Future<void> setProfilePhoto(String? path) async {
    final a = currentAccount;
    if (a == null) {
      throw const PhotoException(
        PhotoFailure.notSignedIn,
        'Sign in before changing your profile picture.',
      );
    }
    final previous = a.photoPath;
    a.photoPath = path == null || path.isEmpty ? null : path;
    if (!await _settle(() => a.photoPath = previous)) {
      throw const PhotoException(
        PhotoFailure.persistence,
        'This device would not save the new picture, so your previous avatar '
        'is still in place.',
      );
    }
    notifyListeners();
  }

  Future<void> resetDemoData() async {
    _adopt(_freshWorld());
    final keep = currentAccount?.id;
    currentAccount = accountById(keep) ?? accounts.first;
    _commit();
  }

  /// Wipes the persisted document, the stored session and the onboarding flag.
  Future<void> clearLocalData() async {
    await _storage.clearAll();
    currentAccount = null;
    onboardingSeen = false;
    _adopt(_freshWorld());
    _commit();
  }

  // ── Notifications ──────────────────────────────────────────────────────

  /// The delivery preferences. The server owns the real ones; the device
  /// store keeps a copy so a demo build honours the same switches.
  NotificationPreferences _notificationPreferences =
      const NotificationPreferences();

  List<AppNotification> get myNotifications {
    final id = currentAccount?.id;
    final list = notifications.where((n) => n.accountId == id).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return list;
  }

  int get unreadCount => myNotifications.where((n) => !n.read).length;

  @override
  NotificationPreferences get notificationPreferences =>
      _notificationPreferences;

  /// The device document already holds them.
  @override
  Future<void> loadNotificationPreferences() async {}

  @override
  Future<void> updateNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    _notificationPreferences = preferences;
    _commit();
  }

  /// The device document already holds the whole inbox.
  @override
  Future<void> syncNotifications() async {}

  /// The device document has a single page.
  @override
  Future<void> loadMoreNotifications() async {}

  @override
  bool get hasMoreNotifications => false;

  @override
  bool get loadingNotifications => false;

  @override
  String? get notificationError => null;

  @override
  Future<AppNotification?> notificationById(String id) async =>
      myNotifications.where((n) => n.id == id).firstOrNull;

  /// Nothing to subscribe to: the device store is already live.
  @override
  Future<void> watchNotifications() async {}

  @override
  Future<void> unwatchNotifications() async {}

  /// Whether the member still wants this family of notification.
  ///
  /// The categories are the server's vocabulary, so the same switch means the
  /// same thing on both sides. Account and platform messages always arrive: a
  /// security notice is not something a member may switch off.
  bool _categoryEnabled(String category) {
    final prefs = _notificationPreferences;
    return switch (category) {
      'match' || 'dispute' => prefs.matchActivity,
      'scorer' => prefs.scorerAssignments,
      'tournament' => prefs.tournamentUpdates,
      'team' => prefs.teamActivity,
      'platform' => prefs.platformAnnouncements,
      _ => true,
    };
  }

  /// Creates the in-app notifications for one event.
  ///
  /// [category] names the family the delivery preferences speak about, and
  /// [entityType] and [entityId] say what the notification points at. The app
  /// resolves that pair into a route; it never follows a path from the store.
  void _notify(
    Iterable<String> accountIds, {
    required NotificationKind kind,
    required String title,
    required String body,
    String? route,
    String type = '',
    String category = 'match',
    String? entityType,
    String? entityId,
    Map<String, dynamic> payload = const {},
  }) {
    for (final id in accountIds) {
      if (!_categoryEnabled(category)) continue;
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
          type: type,
          entityType: entityType,
          entityId: entityId,
          payload: payload,
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
        type: n.type,
        entityType: n.entityType,
        entityId: n.entityId,
        payload: n.payload,
        actorId: n.actorId,
        expiresAt: n.expiresAt,
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
        type: n.type,
        entityType: n.entityType,
        entityId: n.entityId,
        payload: n.payload,
        actorId: n.actorId,
        expiresAt: n.expiresAt,
      );
    }
    _commit();
  }

  /// The name behind an account id, for the wording of a message.
  String _accountName(String accountId) {
    for (final a in accounts) {
      if (a.id == accountId) return a.displayName;
    }
    return 'A player';
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
    _notify(
      [accountId],
      kind: NotificationKind.teamUpdate,
      title: 'Added to ${s.name}',
      body:
          '${currentAccount?.displayName ?? 'The captain'} added you to the '
          'squad roster.',
      route: 'teams',
      type: 'team_member_joined',
      category: 'team',
      entityType: 'team',
      entityId: s.id,
      payload: {'squadId': s.id},
    );
    _paintThenPersist(undo: () => s.memberAccountIds.remove(accountId));
  }

  void removeSquadMember(String squadId, String accountId) {
    final s = squads.where((x) => x.id == squadId).firstOrNull;
    if (s == null) return;
    final index = s.memberAccountIds.indexOf(accountId);
    if (index < 0) return;
    s.memberAccountIds.removeAt(index);
    _notify(
      [accountId],
      kind: NotificationKind.teamUpdate,
      title: 'Removed from ${s.name}',
      body: 'You are no longer on this squad roster.',
      route: 'teams',
      type: 'team_member_left',
      category: 'team',
      entityType: 'team',
      entityId: s.id,
      payload: {'squadId': s.id},
    );
    _paintThenPersist(undo: () => s.memberAccountIds.insert(index, accountId));
  }

  Squad? squadById(String id) => squads.where((s) => s.id == id).firstOrNull;

  String? get currentAccountId => currentAccount?.id;

  /// Invites a player. The invite is persisted separately from membership so
  /// the captain can see who has not answered yet.
  void inviteToSquad(String squadId, String accountId) {
    final s = squadById(squadId);
    if (s == null || s.memberAccountIds.contains(accountId)) return;
    if (s.invitedAccountIds.contains(accountId)) return;
    s.invitedAccountIds.add(accountId);
    _notify(
      [accountId],
      kind: NotificationKind.teamUpdate,
      title: 'Squad invitation',
      body:
          '${currentAccount?.displayName ?? 'The captain'} invited you to '
          '${s.name}.',
      route: 'teams',
      type: 'team_invite',
      category: 'team',
      entityType: 'team',
      entityId: s.id,
      payload: {'squadId': s.id},
    );
    _commit();
  }

  void cancelSquadInvite(String squadId, String accountId) {
    final s = squadById(squadId);
    if (s == null) return;
    s.invitedAccountIds.remove(accountId);
    _notify(
      [accountId],
      kind: NotificationKind.teamUpdate,
      title: 'Squad invitation withdrawn',
      body: '${s.name} is no longer waiting for your answer.',
      route: 'teams',
      type: 'team_invite',
      category: 'team',
      entityType: 'team',
      entityId: s.id,
      payload: {'squadId': s.id},
    );
    _commit();
  }

  /// Answers an invite addressed to [accountId]. Accepting joins the roster.
  void respondToSquadInvite(
    String squadId,
    String accountId, {
    required bool accept,
  }) {
    final s = squadById(squadId);
    if (s == null || !s.invitedAccountIds.contains(accountId)) return;
    s.invitedAccountIds.remove(accountId);
    final joined = accept && !s.memberAccountIds.contains(accountId);
    if (joined) {
      s.memberAccountIds.add(accountId);
    }
    _notify(
      [s.ownerId],
      kind: NotificationKind.teamUpdate,
      title: accept ? 'Squad invitation accepted' : 'Squad invitation declined',
      body:
          '${_accountName(accountId)} '
          '${accept ? 'joined' : 'declined'} ${s.name}.',
      route: 'teams',
      type: accept ? 'team_member_joined' : 'team_join_request',
      category: 'team',
      entityType: 'team',
      entityId: s.id,
      payload: {'squadId': s.id, 'memberId': accountId},
    );
    _paintThenPersist(
      undo: () {
        if (joined) s.memberAccountIds.remove(accountId);
        s.invitedAccountIds.add(accountId);
      },
    );
  }

  /// Hands the captaincy over; the old captain stays on the roster.
  void transferCaptain(String squadId, String accountId) {
    final s = squadById(squadId);
    if (s == null || !s.memberAccountIds.contains(accountId)) return;
    final index = squads.indexOf(s);
    squads[index] = Squad(
      id: s.id,
      ownerId: accountId,
      name: s.name,
      sport: s.sport,
      type: s.type,
      memberAccountIds: s.memberAccountIds,
      invitedAccountIds: s.invitedAccountIds,
      createdAt: s.createdAt,
    );
    _notify(
      [accountId, s.ownerId],
      kind: NotificationKind.teamUpdate,
      title: 'Squad captaincy transferred',
      body: '${_accountName(accountId)} now captains ${s.name}.',
      route: 'teams',
      type: 'team_member_joined',
      category: 'team',
      entityType: 'team',
      entityId: s.id,
      payload: {'squadId': s.id},
    );
    _commit();
  }

  /// Removes the current account from the roster. A captain cannot leave while
  /// other members remain: the squad would be unmanageable.
  void leaveSquad(String squadId) {
    final me = currentAccount;
    final s = squadById(squadId);
    if (me == null || s == null) return;
    if (s.ownerId == me.id && s.memberAccountIds.length > 1) {
      throw StateError('Transfer the captaincy before leaving this squad');
    }
    final squadIndex = squads.indexOf(s);
    final members = List<String>.of(s.memberAccountIds);
    final invites = List<String>.of(s.invitedAccountIds);
    s.memberAccountIds.remove(me.id);
    s.invitedAccountIds.remove(me.id);
    if (s.memberAccountIds.isEmpty) squads.remove(s);
    _notify(
      [s.ownerId],
      kind: NotificationKind.teamUpdate,
      title: '${me.displayName} left ${s.name}',
      body: 'The squad roster has changed.',
      route: 'teams',
      type: 'team_member_left',
      category: 'team',
      entityType: 'team',
      entityId: s.id,
      payload: {'squadId': s.id},
    );
    _paintThenPersist(
      undo: () {
        if (!squads.contains(s)) squads.insert(squadIndex, s);
        s.memberAccountIds = members;
        s.invitedAccountIds
          ..clear()
          ..addAll(invites);
      },
    );
  }

  /// Captains can delete their own squad outright.
  void deleteSquad(String squadId) {
    final s = squadById(squadId);
    if (s == null) return;
    squads.remove(s);
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

  bool _ownsTournament(String id) =>
      currentAccount != null &&
      tournamentById(id)?.organizerId == currentAccount!.id;

  bool _ownsFixture(Fixture fixture) => _ownsTournament(fixture.tournamentId);

  void setTournamentStatus(String tournamentId, TournamentStatus status) {
    if (!_ownsTournament(tournamentId)) return;
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

    final entryCount = entries.length;
    final notificationCount = notifications.length;
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
    await _commitSettled(
      undo: () {
        entries.removeRange(entryCount, entries.length);
        notifications.removeRange(notificationCount, notifications.length);
      },
    );
  }

  Future<void> withdrawEntry(String entryId) async {
    final e = entries.where((x) => x.id == entryId).firstOrNull;
    if (e == null || e.status == EntryStatus.withdrawn) return;
    final previous = e.status;
    e.status = EntryStatus.withdrawn;
    await _commitSettled(undo: () => e.status = previous);
  }

  Future<void> decideEntry(
    String entryId, {
    required bool approve,
    String? note,
  }) async {
    final e = entries.where((x) => x.id == entryId).firstOrNull;
    if (e == null || !_ownsTournament(e.tournamentId)) return;
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
    if (!_ownsTournament(tournamentId)) return 0;
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
        .where((a) => a.id == t.organizerId)
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
            // A premium organizer picks the group count in the setup form; every
            // tournament made before that key existed, and every free one, keeps
            // the two-group draw the engine has always used.
            groupCount: (t.rules['groupCount'] as num?)?.toInt() ?? 2,
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
    if (f == null || !_ownsFixture(f)) return;
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
    if (f == null || !_ownsFixture(f)) return;
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
    if (f == null || !_ownsFixture(f)) return;
    f.scorerAccountIds.remove(accountId);
    _commit();
  }

  /// The scorer's own answer to an assignment on a device fixture. Accepting
  /// changes nothing — being in the list is the access — while declining hands
  /// it back so the organizer has to choose someone else.
  Future<void> respondToScorerAssignment(
    String fixtureId, {
    required bool accept,
  }) async {
    final me = currentAccount?.id;
    final f = fixtureById(fixtureId);
    if (me == null || f == null || !f.scorerAccountIds.contains(me)) {
      throw StateError('That scorer assignment is not yours.');
    }
    if (accept) return;
    f.scorerAccountIds.remove(me);
    notifyListeners();
    final saved = await _settle(() => f.scorerAccountIds.add(me));
    if (!saved) {
      throw StateError('This device would not save your answer. Try again.');
    }
  }

  /// Called when a scorer opens the fixture: marks it live and starts the log.
  void startOfficialScoring(String fixtureId) {
    final f = fixtureById(fixtureId);
    if (f == null || !f.scorerAccountIds.contains(currentAccount?.id)) {
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
    if (f == null || !f.scorerAccountIds.contains(currentAccount?.id)) {
      return;
    }
    if (f.status == FixtureStatus.submitted ||
        f.status == FixtureStatus.published ||
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
    if (f == null || !f.scorerAccountIds.contains(currentAccount?.id)) {
      return;
    }
    if (f.events.isEmpty) {
      return;
    }
    if (f.status == FixtureStatus.submitted ||
        f.status == FixtureStatus.published ||
        f.status == FixtureStatus.walkover) {
      return;
    }
    f.events.removeLast();
    _commit();
  }

  /// Scorer hands the finished match to the organizer for review.
  void submitOfficialResult(String fixtureId) {
    final f = fixtureById(fixtureId);
    if (f == null || !f.scorerAccountIds.contains(currentAccount?.id)) {
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
    if (f == null || !_ownsFixture(f)) return;
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
    if (f == null || !_ownsFixture(f)) return;
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
    if (f == null || !_ownsFixture(f)) return;
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
    if (f == null || !_ownsFixture(f)) return;
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
    return accounts.where((a) => a.id != id).toList();
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

  // ── Standalone official matches ────────────────────────────────────────
  //
  // Every method mirrors the guard of its RPC in migration 0007, so a demo or
  // test build refuses exactly what the server refuses. The caller is always
  // the signed-in account: no method takes an actor id.

  List<SportMatch> matches = [];

  MatchSyncState _sync = MatchSyncState.idle;

  MatchSyncState get sync => _sync;

  String _requireMatchActor() {
    final me = currentAccount?.id;
    if (me == null) throw StateError('Sign in to manage a match.');
    return me;
  }

  SportMatch _requireMatch(String matchId) {
    final m = matchById(matchId);
    if (m == null) throw StateError('That match no longer exists.');
    return m;
  }

  SportMatch? matchById(String id) =>
      matches.where((m) => m.id == id).firstOrNull;

  @override
  SportMatch? matchOfFixture(String tournamentId, String fixtureId) => matches
      .where((m) => m.tournamentId == tournamentId && m.fixtureId == fixtureId)
      .firstOrNull;

  bool _canViewMatch(SportMatch m) {
    final me = currentAccount?.id;
    if (me == null) return false;
    if (m.visibility == MatchVisibility.public) return true;
    if (m.organizerId == me || m.scorerId == me) return true;
    final p = m.participantOf(me);
    return p != null &&
        (p.status == MatchParticipantStatus.invited ||
            p.status == MatchParticipantStatus.accepted);
  }

  bool _isOnMatch(SportMatch m, String me) {
    if (m.organizerId == me || m.scorerId == me) return true;
    final p = m.participantOf(me);
    return p != null &&
        (p.status == MatchParticipantStatus.invited ||
            p.status == MatchParticipantStatus.accepted);
  }

  List<SportMatch> get discoverableMatches =>
      matches.where(_canViewMatch).toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  List<SportMatch> get myMatches {
    final me = currentAccount?.id;
    if (me == null) return [];
    return matches.where((m) => _isOnMatch(m, me)).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  List<SportMatch> get myOrganizedMatches {
    final me = currentAccount?.id;
    if (me == null) return [];
    return matches.where((m) => m.organizerId == me).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  List<SportMatch> get myScoringMatches {
    final me = currentAccount?.id;
    if (me == null) return [];
    return matches
        .where(
          (m) =>
              (m.scorerId == me ||
                  (m.organizerId == me && m.scorerId == null)) &&
              m.status != FixtureStatus.published &&
              m.status != FixtureStatus.walkover &&
              m.status != FixtureStatus.cancelled,
        )
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  List<SportMatch> get liveMatches =>
      matches
          .where((m) => m.status == FixtureStatus.live && _canViewMatch(m))
          .toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  List<SportMatch> get completedMatches =>
      matches.where((m) => m.isFinished && _canViewMatch(m)).toList()
        ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

  List<SportMatch> get myInvites {
    final me = currentAccount?.id;
    if (me == null) return [];
    return matches
        .where(
          (m) => m.participantOf(me)?.status == MatchParticipantStatus.invited,
        )
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  MatchProgress progressOf(SportMatch match) => SportEngines.progressOf(
    sport: match.sport,
    sides: match.sideNames,
    rules: SportEngines.rulesOr(match.sport, match.rules),
    rawEvents: match.scoringLog,
  );

  void _validateMatchFields({
    required String title,
    required String venue,
    required String sideA,
    required String sideB,
    required int capacity,
    required DateTime scheduledAt,
  }) {
    final t = title.trim(), v = venue.trim();
    final a = sideA.trim(), b = sideB.trim();
    if (t.length < 2 || t.length > 80) {
      throw StateError('Give the match a title between 2 and 80 characters.');
    }
    if (v.length > 80) {
      throw StateError('Keep the venue to 80 characters or fewer.');
    }
    if (a.isEmpty || a.length > 40 || b.isEmpty || b.length > 40) {
      throw StateError('Both sides need a name of 1 to 40 characters.');
    }
    if (capacity < 2 || capacity > 100) {
      throw StateError('Capacity has to be between 2 and 100 players.');
    }
    if (scheduledAt.isBefore(DateTime(2000))) {
      throw StateError('Pick a start time for the match.');
    }
  }

  Future<SportMatch> createMatch(MatchDraft draft) async {
    final me = _requireMatchActor();
    _validateMatchFields(
      title: draft.title,
      venue: draft.venue,
      sideA: draft.sideA,
      sideB: draft.sideB,
      capacity: draft.capacity,
      scheduledAt: draft.scheduledAt,
    );
    if (draft.formatLabel.trim().isEmpty) {
      throw StateError('Pick a format for the match.');
    }
    final allowed = MatchDisciplineX.forSport(draft.sport);
    if (!allowed.contains(draft.discipline)) {
      throw StateError(
        '${draft.sport.label} is played as '
        '${allowed.map((d) => d.label.toLowerCase()).join(' or ')}.',
      );
    }

    final match = SportMatch(
      id: newId('match'),
      sport: draft.sport,
      formatLabel: draft.formatLabel.trim(),
      rules: {...draft.rules, 'discipline': draft.discipline.key},
      title: draft.title.trim(),
      venue: draft.venue.trim(),
      scheduledAt: draft.scheduledAt,
      visibility: draft.visibility,
      organizerId: me,
      scorerId: draft.scorerId,
      status: FixtureStatus.upcoming,
      sideNames: [draft.sideA.trim(), draft.sideB.trim()],
      discipline: draft.discipline,
      capacity: draft.capacity,
      createdAt: DateTime.now(),
      tournamentId: draft.tournamentId,
      fixtureId: draft.fixtureId,
      participants: [
        MatchParticipant(
          profileId: me,
          displayName: currentAccount?.displayName ?? 'Organizer',
          side: 0,
          status: MatchParticipantStatus.accepted,
          invitedById: me,
          joinedAt: DateTime.now(),
        ),
      ],
    );
    matches.insert(0, match);
    if (draft.scorerId != null) {
      _notify(
        [draft.scorerId!],
        kind: NotificationKind.scorerAssignment,
        title: 'You are the official scorer',
        body: '${match.title} · ${match.sport.label}. No entries yet.',
        route: 'match',
      );
    }
    notifyListeners();
    final saved = await _settle(() => matches.remove(match));
    if (!saved) {
      _sync = MatchSyncState.failed;
      throw StateError('This device would not save the match. Try again.');
    }
    _sync = MatchSyncState.idle;
    return match;
  }

  Future<void> updateMatch(
    String matchId, {
    required String title,
    required String venue,
    required DateTime scheduledAt,
    required String sideA,
    required String sideB,
    required int capacity,
  }) async {
    final me = _requireMatchActor();
    final m = _requireMatch(matchId);
    if (m.organizerId != me) {
      throw StateError('Only the organizer can edit this match.');
    }
    if (m.status != FixtureStatus.upcoming) {
      throw StateError('A match can only be edited before it starts.');
    }
    _validateMatchFields(
      title: title,
      venue: venue,
      sideA: sideA,
      sideB: sideB,
      capacity: capacity,
      scheduledAt: scheduledAt,
    );
    final before = (
      m.title,
      m.venue,
      m.scheduledAt,
      List<String>.from(m.sideNames),
      m.capacity,
    );
    m.title = title.trim();
    m.venue = venue.trim();
    m.scheduledAt = scheduledAt;
    m.sideNames = [sideA.trim(), sideB.trim()];
    m.capacity = capacity;
    notifyListeners();
    final saved = await _settle(() {
      m.title = before.$1;
      m.venue = before.$2;
      m.scheduledAt = before.$3;
      m.sideNames = before.$4;
      m.capacity = before.$5;
    });
    if (!saved) throw StateError('This device would not save the change.');
  }

  Future<void> cancelMatch(String matchId, {String? reason}) async {
    final me = _requireMatchActor();
    final m = _requireMatch(matchId);
    if (m.organizerId != me) {
      throw StateError('Only the organizer can cancel this match.');
    }
    if (m.status != FixtureStatus.upcoming && m.status != FixtureStatus.live) {
      throw StateError('That match can no longer be cancelled.');
    }
    final previousStatus = m.status;
    m.status = FixtureStatus.cancelled;
    m.completedAt = DateTime.now();
    notifyListeners();
    final saved = await _settle(() {
      m.status = previousStatus;
      m.completedAt = null;
    });
    if (!saved) {
      throw StateError('This device would not save the cancellation.');
    }
  }

  Future<void> inviteParticipant(
    String matchId,
    String profileId, {
    int side = 1,
    String? displayName,
  }) async {
    final me = _requireMatchActor();
    final m = _requireMatch(matchId);
    if (m.organizerId != me) {
      throw StateError('Only the organizer can invite players.');
    }
    if (m.status != FixtureStatus.upcoming && m.status != FixtureStatus.live) {
      throw StateError('Invitations close once the result is submitted.');
    }
    if (profileId.isEmpty) throw StateError('Pick a member to invite.');
    if (profileId == m.organizerId) {
      throw StateError('You are already on this match.');
    }
    if (side != 0 && side != 1) throw StateError('Pick a side for the player.');
    if (m.acceptedCount >= m.capacity) {
      throw StateError('This match is full.');
    }

    final name = displayName ?? accountById(profileId)?.displayName ?? 'Player';
    final existing = m.participantOf(profileId);
    if (existing != null) {
      existing
        ..side = side
        ..status = existing.status == MatchParticipantStatus.accepted
            ? MatchParticipantStatus.accepted
            : MatchParticipantStatus.invited;
    } else {
      m.participants.add(
        MatchParticipant(
          profileId: profileId,
          displayName: name,
          side: side,
          status: MatchParticipantStatus.invited,
          invitedById: me,
        ),
      );
    }
    _notify(
      [profileId],
      kind: NotificationKind.fixtureChange,
      title: 'Match invitation',
      body:
          '${currentAccount?.displayName ?? 'An organizer'} invited you to '
          '${m.title}.',
      route: 'match',
    );
    notifyListeners();
    final saved = await _settle(() {});
    if (!saved) throw StateError('This device would not save the invitation.');
  }

  Future<void> respondToInvite(String matchId, {required bool accept}) async {
    final me = _requireMatchActor();
    final m = _requireMatch(matchId);
    final p = m.participantOf(me);
    if (p == null ||
        (p.status != MatchParticipantStatus.invited &&
            p.status != MatchParticipantStatus.accepted)) {
      throw StateError('That invitation is not yours.');
    }
    if (accept &&
        m.acceptedCount >= m.capacity &&
        p.status != MatchParticipantStatus.accepted) {
      throw StateError('This match is full.');
    }
    final previous = p.status;
    p.status = accept
        ? MatchParticipantStatus.accepted
        : MatchParticipantStatus.declined;
    if (accept) p.joinedAt ??= DateTime.now();
    notifyListeners();
    final saved = await _settle(() => p.status = previous);
    if (!saved) {
      throw StateError('This device would not save your answer. Try again.');
    }
  }

  Future<void> removeParticipant(String matchId, String profileId) async {
    final me = _requireMatchActor();
    final m = _requireMatch(matchId);
    if (m.organizerId != me && profileId != me) {
      throw StateError('Only the organizer can remove another player.');
    }
    if (profileId == m.organizerId) {
      throw StateError('The organizer cannot be removed from their own match.');
    }
    if (m.status != FixtureStatus.upcoming && m.status != FixtureStatus.live) {
      throw StateError('The roster is locked once the result is submitted.');
    }
    final p = m.participantOf(profileId);
    if (p == null) throw StateError('That player is not on this match.');
    final previous = p.status;
    p.status = MatchParticipantStatus.removed;
    notifyListeners();
    final saved = await _settle(() => p.status = previous);
    if (!saved) throw StateError('This device would not save the change.');
  }

  Future<void> assignMatchScorer(String matchId, String scorerId) async {
    final me = _requireMatchActor();
    final m = _requireMatch(matchId);
    if (m.organizerId != me) {
      throw StateError('Only the organizer can assign the official scorer.');
    }
    if (m.status != FixtureStatus.upcoming && m.status != FixtureStatus.live) {
      throw StateError('The scorer cannot be changed after submission.');
    }
    if (scorerId.trim().isEmpty) throw StateError('Pick a member to score.');

    final previous = m.scorerId;
    m.scorerId = scorerId;
    _notify(
      [scorerId],
      kind: NotificationKind.scorerAssignment,
      title: previous == null
          ? 'You are the official scorer'
          : 'Scoring access transferred',
      body:
          '${m.title} · ${m.events.length} '
          '${m.events.length == 1 ? 'entry' : 'entries'} carried forward.',
      route: 'match',
    );
    notifyListeners();
    final saved = await _settle(() => m.scorerId = previous);
    if (!saved) throw StateError('This device would not save the scorer.');
  }

  Future<void> revokeMatchScorer(String matchId) async {
    final me = _requireMatchActor();
    final m = _requireMatch(matchId);
    if (m.organizerId != me) {
      throw StateError('Only the organizer can revoke the official scorer.');
    }
    if (m.status != FixtureStatus.upcoming && m.status != FixtureStatus.live) {
      throw StateError('The scorer cannot be changed after submission.');
    }
    final previous = m.scorerId;
    m.scorerId = null;
    notifyListeners();
    final saved = await _settle(() => m.scorerId = previous);
    if (!saved) throw StateError('This device would not save the change.');
  }

  Future<void> startMatch(String matchId) async {
    final me = _requireMatchActor();
    final m = _requireMatch(matchId);
    if (!m.canScore(me)) {
      throw StateError(
        'Only the organizer or the assigned official scorer can start this match.',
      );
    }
    if (m.status != FixtureStatus.upcoming) {
      throw StateError('That match has already started.');
    }
    m.status = FixtureStatus.live;
    m.startedAt = DateTime.now();
    notifyListeners();
    final saved = await _settle(() {
      m.status = FixtureStatus.upcoming;
      m.startedAt = null;
    });
    if (!saved) throw StateError('This device would not save the start.');
  }

  /// Mirrors `pause_match` (0013): organizer or scorer, live only, an optional
  /// reason of 3 to 200 characters, and a pause on an already paused match is a
  /// no-op so a double tap cannot fail in the scorer's face.
  Future<void> pauseMatch(String matchId, {String? reason}) async {
    final me = _requireMatchActor();
    final m = _requireMatch(matchId);
    if (!m.canScore(me)) {
      throw StateError(
        'Only the organizer or the assigned official scorer can pause scoring.',
      );
    }
    if (m.status != FixtureStatus.live) {
      throw StateError('Only a live match can be paused.');
    }
    final trimmed = reason?.trim() ?? '';
    if (trimmed.isNotEmpty && (trimmed.length < 3 || trimmed.length > 200)) {
      throw StateError(
        'Give the reason in 3 to 200 characters, or leave it out.',
      );
    }
    if (m.isPaused) return;

    final previous = (m.pausedAt, m.pausedBy, m.pauseReason);
    m.pausedAt = DateTime.now();
    m.pausedBy = me;
    m.pauseReason = trimmed.isEmpty ? null : trimmed;
    notifyListeners();
    final saved = await _settle(() {
      m.pausedAt = previous.$1;
      m.pausedBy = previous.$2;
      m.pauseReason = previous.$3;
    });
    if (!saved) throw StateError('This device would not save the pause.');
  }

  /// Mirrors `resume_match`: the same actors, live only, and a no-op when the
  /// match is not paused.
  Future<void> resumeMatch(String matchId) async {
    final me = _requireMatchActor();
    final m = _requireMatch(matchId);
    if (!m.canScore(me)) {
      throw StateError(
        'Only the organizer or the assigned official scorer can resume scoring.',
      );
    }
    if (m.status != FixtureStatus.live) {
      throw StateError('Only a live match can be resumed.');
    }
    if (!m.isPaused) return;

    final previous = (m.pausedAt, m.pausedBy, m.pauseReason);
    m.pausedAt = null;
    m.pausedBy = null;
    m.pauseReason = null;
    notifyListeners();
    final saved = await _settle(() {
      m.pausedAt = previous.$1;
      m.pausedBy = previous.$2;
      m.pauseReason = previous.$3;
    });
    if (!saved) throw StateError('This device would not save the resume.');
  }

  Future<MatchEvent> recordEvent(
    String matchId, {
    required String kind,
    int? side,
    Map<String, dynamic> data = const {},
    String? clientId,
    DateTime? at,
  }) async {
    final me = _requireMatchActor();
    final m = _requireMatch(matchId);
    if (!m.canScore(me)) {
      throw StateError(
        'Only the organizer or the assigned official scorer can record scores.',
      );
    }
    if (m.status != FixtureStatus.live) {
      throw StateError('Scores can only be recorded while the match is live.');
    }
    if (m.isPaused) {
      throw StateError(
        'Scoring is paused. Resume the match before recording another point.',
      );
    }
    final cid = clientId ?? newId('ev');
    final existing = m.events.where((e) => e.clientId == cid).firstOrNull;
    if (existing != null) return existing;

    final seq = m.eventCount + 1;
    final event = MatchEvent(
      id: newId('mev'),
      seq: seq,
      clientId: cid,
      kind: kind,
      side: side,
      data: Map<String, dynamic>.from(data),
      at: at ?? DateTime.now(),
      byAccountId: me,
    );
    m.events.add(event);
    m.eventCount = seq;
    notifyListeners();
    final saved = await _settle(() {
      m.events.remove(event);
    });
    if (!saved) {
      _sync = MatchSyncState.failed;
      throw StateError('This device would not save that entry. Try again.');
    }
    _sync = MatchSyncState.idle;
    return event;
  }

  Future<void> voidEvent(String matchId, String eventId) async {
    final me = _requireMatchActor();
    final m = _requireMatch(matchId);
    if (!m.canScore(me)) {
      throw StateError('Only the organizer or the official scorer can undo.');
    }
    if (m.status != FixtureStatus.live) {
      throw StateError('Undo is only available while the match is live.');
    }
    final event = m.events.where((e) => e.id == eventId).firstOrNull;
    if (event == null) throw StateError('That entry no longer exists.');
    if (event.voided) return;
    if (m.lastActiveEvent?.id != event.id) {
      throw StateError('Only the newest entry can be undone.');
    }
    event.voided = true;
    notifyListeners();
    final saved = await _settle(() => event.voided = false);
    if (!saved) throw StateError('This device would not save the undo.');
  }

  void _validateResultPayload(
    List<String> sideScores,
    List<int> sideValues,
    int winnerIndex,
  ) {
    if (sideScores.length != 2 || sideValues.length != 2) {
      throw StateError('A result needs a score for both sides.');
    }
    if (winnerIndex < -1 || winnerIndex > 1) {
      throw StateError('Pick the winner, or a draw.');
    }
  }

  Future<void> submitResult(
    String matchId, {
    required String headline,
    required String detail,
    required List<String> sideScores,
    required List<int> sideValues,
    required int winnerIndex,
  }) async {
    final me = _requireMatchActor();
    final m = _requireMatch(matchId);
    if (!m.canScore(me)) {
      throw StateError('Only the organizer or the official scorer can submit.');
    }
    if (m.status != FixtureStatus.live) {
      throw StateError('Only a live match can be submitted for review.');
    }
    _validateResultPayload(sideScores, sideValues, winnerIndex);

    final previous = (m.result, m.status, m.submittedAt);
    m.result = OfficialResult(
      sideScores: List<String>.from(sideScores),
      sideValues: List<int>.from(sideValues),
      winnerIndex: winnerIndex,
      headline: headline.trim(),
      detail: detail.trim(),
      publishedAt: DateTime.now(),
      publishedById: me,
    );
    m.status = FixtureStatus.submitted;
    m.submittedAt = DateTime.now();
    _notify(
      [m.organizerId],
      kind: NotificationKind.resultSubmitted,
      title: 'Result awaiting review',
      body: '${m.title} · ${headline.trim()}',
      route: 'match',
    );
    notifyListeners();
    final saved = await _settle(() {
      m.result = previous.$1;
      m.status = previous.$2;
      m.submittedAt = previous.$3;
    });
    if (!saved) throw StateError('This device would not save the result.');
  }

  Future<void> publishResult(String matchId) async {
    final me = _requireMatchActor();
    final m = _requireMatch(matchId);
    if (m.organizerId != me) {
      throw StateError('Only the organizer can publish the result.');
    }
    if (m.status != FixtureStatus.submitted) {
      throw StateError('There is no submitted result to publish.');
    }
    if (m.result == null) {
      throw StateError('Submit a result before publishing.');
    }

    final previous = (m.status, m.publishedAt, m.completedAt);
    final result = m.result!;
    m.result = OfficialResult(
      sideScores: result.sideScores,
      sideValues: result.sideValues,
      winnerIndex: result.winnerIndex,
      headline: result.headline,
      detail: result.detail,
      publishedAt: DateTime.now(),
      publishedById: me,
      walkover: result.walkover,
    );
    m.status = FixtureStatus.published;
    m.publishedAt = DateTime.now();
    m.completedAt ??= DateTime.now();
    _notify(
      {m.organizerId, if (m.scorerId != null) m.scorerId!},
      kind: NotificationKind.resultPublished,
      title: 'Result published',
      body: '${m.title} · ${result.headline}',
      route: 'match',
    );
    notifyListeners();
    final saved = await _settle(() {
      m.result = result;
      m.status = previous.$1;
      m.publishedAt = previous.$2;
      m.completedAt = previous.$3;
    });
    if (!saved) throw StateError('This device would not save the publication.');
  }

  Future<void> correctResult(
    String matchId, {
    required String headline,
    required String detail,
    required List<String> sideScores,
    required List<int> sideValues,
    required int winnerIndex,
    required String reason,
  }) async {
    final me = _requireMatchActor();
    final m = _requireMatch(matchId);
    if (m.organizerId != me) {
      throw StateError('Only the organizer can correct a published result.');
    }
    if (m.status != FixtureStatus.published) {
      throw StateError('Only a published result can be corrected.');
    }
    if (reason.trim().length < 3) {
      throw StateError('Say why the result is being corrected.');
    }
    _validateResultPayload(sideScores, sideValues, winnerIndex);
    final previous = m.result;
    if (previous == null) {
      throw StateError('There is no published result here.');
    }

    final current = OfficialResult(
      sideScores: List<String>.from(sideScores),
      sideValues: List<int>.from(sideValues),
      winnerIndex: winnerIndex,
      headline: headline.trim(),
      detail: detail.trim(),
      publishedAt: DateTime.now(),
      publishedById: me,
    );
    final correction = ResultCorrection(
      id: newId('cor'),
      previous: previous,
      current: current,
      reason: reason.trim(),
      byAccountId: me,
      at: DateTime.now(),
    );
    m.result = current;
    m.corrections.insert(0, correction);
    notifyListeners();
    final saved = await _settle(() {
      m.result = previous;
      m.corrections.remove(correction);
    });
    if (!saved) throw StateError('This device would not save the correction.');
  }

  Future<void> recordMatchWalkover(
    String matchId, {
    required int winnerIndex,
    required String reason,
  }) async {
    final me = _requireMatchActor();
    final m = _requireMatch(matchId);
    if (m.organizerId != me) {
      throw StateError('Only the organizer can award a walkover.');
    }
    if (m.status != FixtureStatus.upcoming &&
        m.status != FixtureStatus.live &&
        m.status != FixtureStatus.submitted) {
      throw StateError('That match can no longer be decided by walkover.');
    }
    if (winnerIndex != 0 && winnerIndex != 1) {
      throw StateError('Pick which side takes the walkover.');
    }

    final previousStatus = m.status;
    final previousResult = m.result;
    final winnerName = m.sideNames[winnerIndex];
    m.result = OfficialResult(
      sideScores: winnerIndex == 0 ? const ['W', 'L'] : const ['L', 'W'],
      sideValues: winnerIndex == 0 ? const [1, 0] : const [0, 1],
      winnerIndex: winnerIndex,
      headline: '$winnerName won by walkover',
      detail: reason.trim().isEmpty
          ? 'Walkover'
          : 'Walkover · ${reason.trim()}',
      publishedAt: DateTime.now(),
      publishedById: me,
      walkover: true,
    );
    m.status = FixtureStatus.walkover;
    m.completedAt = DateTime.now();
    notifyListeners();
    final saved = await _settle(() {
      m.status = previousStatus;
      m.result = previousResult;
      m.completedAt = null;
    });
    if (!saved) throw StateError('This device would not save the walkover.');
  }

  /// Mirrors `raise_match_dispute` (0014): a result has to exist, the caller has
  /// to be on the match, the reason is 5 to 500 characters, and a member may
  /// only have one live dispute per match. Nothing here gates on an entitlement:
  /// disputing a result is free, like scoring and publishing one.
  Future<MatchDispute> raiseMatchDispute(String matchId, String reason) async {
    final me = _requireMatchActor();
    final m = _requireMatch(matchId);
    if (!_canViewMatch(m)) {
      throw StateError('That match could not be found.');
    }
    if (!m.hasResult) {
      throw StateError('There is no official result to dispute yet.');
    }
    final trimmed = reason.trim();
    if (trimmed.length < 5 || trimmed.length > 500) {
      throw StateError(
        'Say what is wrong with the result in 5 to 500 characters.',
      );
    }
    if (!m.canDispute(me)) {
      throw StateError(
        'Only the players, the scorer or the organizer can dispute this result.',
      );
    }
    if (m.disputes.any((d) => d.raisedById == me && d.status.isOpen)) {
      throw StateError('You already have a live dispute on this match.');
    }

    final dispute = MatchDispute(
      id: newId('dsp'),
      matchId: matchId,
      raisedById: me,
      reason: trimmed,
      status: MatchDisputeStatus.open,
      raisedAt: DateTime.now(),
    );
    m.disputes.insert(0, dispute);
    notifyListeners();
    final saved = await _settle(() => m.disputes.remove(dispute));
    if (!saved) throw StateError('This device would not save the dispute.');
    return dispute;
  }

  /// Mirrors `resolve_match_dispute`: the match organizer answers, or the owner
  /// of the tournament the fixture belongs to (the device knows its own
  /// tournaments). `underReview` carries no resolution; a closed dispute needs
  /// one of 3 to 500 characters and can never be answered twice.
  Future<MatchDispute> resolveMatchDispute(
    String matchId,
    String disputeId, {
    required MatchDisputeStatus status,
    String? resolution,
  }) async {
    final me = _requireMatchActor();
    final m = _requireMatch(matchId);
    final tournamentOwner = m.tournamentId == null
        ? null
        : tournamentById(m.tournamentId!)?.organizerId;
    if (m.organizerId != me && tournamentOwner != me) {
      throw StateError('Only the organizer can answer a dispute.');
    }
    final dispute = m.disputes.where((d) => d.id == disputeId).firstOrNull;
    if (dispute == null) {
      throw StateError('That dispute could not be found.');
    }
    if (status == MatchDisputeStatus.open) {
      throw StateError('Pick one of the answers the server recognises.');
    }
    final trimmed = resolution?.trim() ?? '';
    final closed =
        status == MatchDisputeStatus.resolved ||
        status == MatchDisputeStatus.rejected;
    if (closed && (trimmed.length < 3 || trimmed.length > 500)) {
      throw StateError(
        'A closed dispute needs a resolution of 3 to 500 characters.',
      );
    }
    if (!closed && trimmed.isNotEmpty) {
      throw StateError('Only a closed dispute carries a resolution.');
    }
    if (!dispute.status.isOpen) {
      throw StateError('This dispute has already been answered.');
    }

    final previous = (
      dispute.status,
      dispute.resolution,
      dispute.resolvedById,
      dispute.resolvedAt,
    );
    dispute.status = status;
    dispute.resolution = closed ? trimmed : null;
    dispute.resolvedById = me;
    dispute.resolvedAt = closed ? DateTime.now() : null;
    notifyListeners();
    final saved = await _settle(() {
      dispute.status = previous.$1;
      dispute.resolution = previous.$2;
      dispute.resolvedById = previous.$3;
      dispute.resolvedAt = previous.$4;
    });
    if (!saved) throw StateError('This device would not save the answer.');
    return dispute;
  }

  List<MatchDispute> disputesOf(String matchId) => [
    ...?matchById(matchId)?.disputes,
  ];

  /// The device store has nothing to subscribe to: every change already
  /// notifies the controllers in-process.
  Future<void> watchMatch(String matchId) async {}
  Future<void> unwatchMatch(String matchId) async {}
  Future<void> watchAllMatches() async {}
  Future<void> unwatchAllMatches() async {}
}
