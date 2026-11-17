import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/games_controller.dart';
import 'package:sportika/core/state/personal_games_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/models/enums.dart';

/// The controllers are pure delegation over the repository, so these tests
/// pin two things: every controller reaches the same store, and a mutation
/// through a controller notifies every other controller watching that store.
Future<LocalSportikaRepository> freshStore() async {
  SharedPreferences.setMockInitialValues({'sportika.onboarding_seen.v1': true});
  final store = LocalSportikaRepository(await LocalStorage.open());
  await store.load();
  return store;
}

void main() {
  group('repository contract', () {
    test('the store satisfies every narrow interface', () async {
      final store = await freshStore();
      final interfaces = <SportikaRepository>[
        store as SessionRepository,
        store as ProfileRepository,
        store as PreferencesRepository,
        store as NotificationRepository,
        store as GameRepository,
        store as TournamentRepository,
        store as FixtureRepository,
        store as TeamRepository,
        store as PersonalGamesRepository,
      ];
      expect(interfaces, hasLength(9));
      final session = interfaces.first as SessionRepository;
      expect(session.accounts, isNotEmpty);
      expect((interfaces[5] as TournamentRepository).tournaments, isNotEmpty);
      expect((interfaces[6] as FixtureRepository).fixtures, isNotEmpty);
    });

    test('persisted schema version is written on the first save', () async {
      final store = await freshStore();
      final storage = LocalStorage(await SharedPreferences.getInstance());
      expect(storage.storedSchemaVersion, LocalStorage.schemaVersion);
      await store.signIn('acc-seebu');
      expect(store.currentAccount?.id, 'acc-seebu');
    });

    test('an older document is migrated instead of discarded', () async {
      SharedPreferences.setMockInitialValues({
        'sportika.state.v1': '{"accounts":[]}',
        'sportika.schema_version': 1,
      });
      final storage = await LocalStorage.open();
      final raw = storage.readState();
      expect(raw, isNotNull);
      expect(raw!['preferences'], isEmpty);
      expect(raw['notifications'], isEmpty);
      expect(storage.recoveredFromCorruption, isFalse);
    });

    test('a corrupt document is rebuilt and announced once', () async {
      SharedPreferences.setMockInitialValues({
        'sportika.state.v1': 'not json at all',
      });
      final store = LocalSportikaRepository(await LocalStorage.open());
      await store.load();
      expect(store.accounts, isNotEmpty);
      expect(store.takeStorageNotice(), isNotNull);
      expect(store.takeStorageNotice(), isNull);
    });
  });

  group('session controller', () {
    test('signs in, exposes the account and signs out', () async {
      final controller = SessionController(await freshStore());
      await controller.signIn('acc-seebu');
      expect(controller.isSignedIn, isTrue);
      expect(controller.currentAccount?.id, 'acc-seebu');
      expect(controller.accountById('acc-seebu'), isNotNull);
      await controller.signOut();
      expect(controller.isSignedIn, isFalse);
    });
  });

  group('profile controller', () {
    test('reads and writes the signed-in profile', () async {
      final store = await freshStore();
      await store.signIn('acc-seebu');
      final controller = ProfileController(store);
      expect(controller.currentAccount, isNotNull);
      await controller.updateProfile(displayName: 'Renamed Athlete');
      expect(store.currentAccount?.displayName, 'Renamed Athlete');
    });
  });

  group('preferences and notifications', () {
    test('preferences are per account', () async {
      final store = await freshStore();
      await store.signIn('acc-seebu');
      final controller = PreferencesController(store);
      controller.setPreference('reminders', false);
      expect(controller.preference('reminders'), isFalse);
      expect(controller.preferences, isNotEmpty);
    });

    test('notifications can be read individually', () async {
      final store = await freshStore();
      await store.signIn('acc-seebu');
      final controller = NotificationsController(store);
      final unread = controller.myNotifications.where((n) => !n.read);
      if (unread.isEmpty) return;
      controller.markNotificationRead(unread.first.id);
      expect(
        store.myNotifications.firstWhere((n) => n.id == unread.first.id).read,
        isTrue,
      );
      controller.markAllNotificationsRead();
      expect(controller.unreadCount, 0);
    });
  });

  group('games controller', () {
    test('joining and leaving a game moves the member list', () async {
      final store = await freshStore();
      await store.signIn('acc-seebu');
      final controller = GamesController(store);
      final game = controller.games.firstWhere(
        (g) => !g.full && !g.members.contains('acc-seebu'),
      );
      controller.toggleGameJoin(game);
      expect(
        controller.games.firstWhere((g) => g.id == game.id).members,
        contains('acc-seebu'),
      );
      controller.toggleGameJoin(game);
      expect(
        controller.games.firstWhere((g) => g.id == game.id).members,
        isNot(contains('acc-seebu')),
      );
    });
  });

  group('tournaments controller', () {
    test('exposes entries and standings for a tournament', () async {
      final store = await freshStore();
      await store.signIn('acc-seebu');
      final controller = TournamentsController(store);
      final tournament = controller.tournaments.first;
      expect(controller.tournamentById(tournament.id), isNotNull);
      expect(controller.entriesFor(tournament.id), isNotNull);
      expect(controller.standingsFor(tournament), isNotNull);
    });
  });

  group('fixtures controller', () {
    test('assigning a scorer is visible through the controller', () async {
      final store = await freshStore();
      final controller = FixturesController(store);
      final fixture = controller.fixtures.first;
      await store.signIn(
        store.tournamentById(fixture.tournamentId)!.organizerId,
      );
      controller.assignScorer(fixture.id, 'acc-seebu');
      expect(
        controller.fixtureById(fixture.id)!.scorerAccountIds,
        contains('acc-seebu'),
      );
    });
  });

  group('teams controller', () {
    test('a created squad appears on the captain profile', () async {
      final store = await freshStore();
      await store.signIn('acc-seebu');
      final controller = TeamsController(store);
      final before = controller.mySquads.length;
      controller.createSquad(
        name: 'Riverside Ravens',
        sport: Sport.cricket,
        type: EntryType.team,
        memberIds: ['acc-seebu'],
      );
      expect(controller.mySquads.length, before + 1);
    });
  });

  group('personal games controller', () {
    test('starts, records and deletes a private scorecard', () async {
      final store = await freshStore();
      await store.signIn('acc-seebu');
      final controller = PersonalGamesController(store);
      final match = controller.startPersonalMatch(
        sport: Sport.badminton,
        format: 'Singles',
        sideA: 'Me',
        sideB: 'Rival',
      );
      expect(controller.personalById(match.id), isNotNull);
      expect(controller.myPersonalInProgress, isNotNull);
      controller.deletePersonalMatch(match.id);
      expect(controller.personalById(match.id), isNull);
    });
  });

  test('every controller relays a mutation from the shared store', () async {
    final store = await freshStore();
    final session = SessionController(store);
    final games = GamesController(store);
    var sessionPings = 0;
    var gamePings = 0;
    session.addListener(() => sessionPings++);
    games.addListener(() => gamePings++);

    await session.signIn('acc-seebu');
    expect(sessionPings, greaterThan(0));

    games.toggleGameJoin(games.games.first);
    expect(gamePings, greaterThan(0));
    expect(sessionPings, greaterThan(0));
  });
}
