import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/shared/data/local_storage.dart';

/// Storage whose writer can be told to fail, so the optimistic-mutation paths
/// can be exercised without a real disk. The repository paints every change
/// before it persists it, so the tests below prove the undo runs and the
/// player is told instead of the screen drifting away from saved data.
class _FlakyStorage extends LocalStorage {
  // The super constructor's parameter is library-private, so it cannot be
  // forwarded with a super parameter from this file.
  // ignore: use_super_parameters
  _FlakyStorage(SharedPreferences prefs) : super(prefs);

  bool failWrites = false;

  @override
  Future<void> writeState(Map<String, dynamic> state) async {
    if (failWrites) throw StateError('disk is full');
    await super.writeState(state);
  }
}

/// A seeded store plus the storage handle, so a test can start failing writes
/// after the initial load has already succeeded.
Future<(LocalSportikaRepository, _FlakyStorage)> flakyStore() async {
  SharedPreferences.setMockInitialValues({'sportika.onboarding_seen.v1': true});
  final storage = _FlakyStorage(await SharedPreferences.getInstance());
  final store = LocalSportikaRepository(storage);
  await store.load();
  return (store, storage);
}

void main() {
  group('a failed save is undone, not painted over', () {
    test('joining a game rolls the roster back', () async {
      final (store, storage) = await flakyStore();
      await store.signIn('acc-seebu');
      final game = store.games.firstWhere(
        (g) => !g.full && !g.members.contains('acc-seebu'),
      );

      storage.failWrites = true;
      store.toggleGameJoin(game);
      await pumpEventQueue();

      expect(
        store.games.firstWhere((g) => g.id == game.id).members,
        isNot(contains('acc-seebu')),
      );
      expect(store.takeStorageNotice(), contains('could not be saved'));
    });

    test('a tournament entry is withdrawn from the list again', () async {
      final (store, storage) = await flakyStore();
      await store.signIn('acc-seebu');
      final tournament = store.tournaments.firstWhere(
        (t) => store.myEntryFor(t.id) == null,
      );
      final before = store.entries.length;

      storage.failWrites = true;
      await store.submitEntry(tournamentId: tournament.id);

      expect(store.myEntryFor(tournament.id), isNull);
      expect(store.entries.length, before);
      expect(store.takeStorageNotice(), contains('could not be saved'));
    });

    test('an added squad member is removed again', () async {
      final (store, storage) = await flakyStore();
      await store.signIn('acc-seebu');

      storage.failWrites = true;
      store.addSquadMember('sqd-strikers', 'acc-sana');
      await pumpEventQueue();

      expect(
        store.squadById('sqd-strikers')!.memberAccountIds,
        isNot(contains('acc-sana')),
      );
      expect(store.takeStorageNotice(), contains('could not be saved'));
    });

    test('leaving a squad puts the player and the squad back', () async {
      final (store, storage) = await flakyStore();
      await store.signIn('acc-zain');
      final index = store.squads.indexWhere((s) => s.id == 'sqd-strikers');

      storage.failWrites = true;
      store.leaveSquad('sqd-strikers');
      await pumpEventQueue();

      expect(store.squadById('sqd-strikers'), isNotNull);
      expect(store.squads.indexWhere((s) => s.id == 'sqd-strikers'), index);
      expect(
        store.squadById('sqd-strikers')!.memberAccountIds,
        contains('acc-zain'),
      );
      expect(store.takeStorageNotice(), contains('could not be saved'));
    });

    test('a save that succeeds keeps the change and stays quiet', () async {
      final (store, storage) = await flakyStore();
      await store.signIn('acc-seebu');
      storage.failWrites = false;
      final game = store.games.firstWhere(
        (g) => !g.full && !g.members.contains('acc-seebu'),
      );

      store.toggleGameJoin(game);
      await pumpEventQueue();

      expect(
        store.games.firstWhere((g) => g.id == game.id).members,
        contains('acc-seebu'),
      );
      expect(store.takeStorageNotice(), isNull);
    });
  });
}
