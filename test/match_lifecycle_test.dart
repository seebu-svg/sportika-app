import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';

Future<LocalSportikaRepository> loadedStore() async {
  SharedPreferences.setMockInitialValues({'sportika.onboarding_seen.v1': true});
  final store = LocalSportikaRepository(await LocalStorage.open());
  await store.load();
  return store;
}

void main() {
  late LocalSportikaRepository store;
  late Account organizer;
  late Account scorer;
  late Account player;
  late Account spare;

  setUp(() async {
    store = await loadedStore();
    organizer = store.accounts[0];
    scorer = store.accounts[1];
    player = store.accounts[2];
    spare = store.accounts[3];
    await store.signIn(organizer.id);
  });

  Future<SportMatch> newMatch({int capacity = 4}) {
    final format = SportEngines.formatsFor(Sport.padel).first;
    return store.createMatch(
      MatchDraft(
        sport: Sport.padel,
        formatLabel: format,
        rules: SportEngines.rulesFor(Sport.padel, format),
        title: 'Court three showdown',
        venue: 'Court three',
        scheduledAt: DateTime.now().add(const Duration(days: 1)),
        visibility: MatchVisibility.public,
        sideA: 'Rao & Iqbal',
        sideB: 'Malik & Farooq',
        capacity: capacity,
        discipline: MatchDiscipline.doubles,
      ),
    );
  }

  test('creating a match puts the organizer on side A', () async {
    final match = await newMatch();

    expect(match.status, FixtureStatus.upcoming);
    expect(match.organizerId, organizer.id);
    expect(
      match.participantOf(organizer.id)!.status,
      MatchParticipantStatus.accepted,
    );
    expect(match.participantOf(organizer.id)!.side, 0);
    expect(match.acceptedCount, 1);
    expect(match.rules['discipline'], 'doubles');
    expect(store.myOrganizedMatches.map((m) => m.id), contains(match.id));
    expect(store.discoverableMatches.map((m) => m.id), contains(match.id));
  });

  test('the create form mirrors the RPC refusals', () async {
    Future<void> refused(MatchDraft draft) =>
        expectLater(store.createMatch(draft), throwsA(isA<StateError>()));

    MatchDraft draft({
      String title = 'Court three showdown',
      String format = '1 set · first to 6',
      int capacity = 4,
      MatchDiscipline discipline = MatchDiscipline.doubles,
      String sideA = 'Rao & Iqbal',
      String sideB = 'Malik & Farooq',
    }) => MatchDraft(
      sport: Sport.padel,
      formatLabel: format,
      rules: SportEngines.rulesFor(Sport.padel, format),
      title: title,
      venue: 'Court three',
      scheduledAt: DateTime.now().add(const Duration(days: 1)),
      visibility: MatchVisibility.public,
      sideA: sideA,
      sideB: sideB,
      capacity: capacity,
      discipline: discipline,
    );

    await refused(draft(title: 'A'));
    await refused(draft(format: ' '));
    await refused(draft(capacity: 1));
    await refused(draft(capacity: 101));
    await refused(draft(discipline: MatchDiscipline.team));
    await refused(draft(sideB: ''));
    await refused(
      MatchDraft(
        sport: Sport.padel,
        formatLabel: '1 set · first to 6',
        rules: const {},
        title: 'No start time',
        venue: '',
        scheduledAt: DateTime(1999),
        visibility: MatchVisibility.public,
        sideA: 'A',
        sideB: 'B',
        capacity: 4,
        discipline: MatchDiscipline.doubles,
      ),
    );
  });

  test('invitations move through invited, accepted and declined', () async {
    final match = await newMatch(capacity: 2);

    await store.inviteParticipant(match.id, player.id, side: 1);
    expect(
      match.participantOf(player.id)!.status,
      MatchParticipantStatus.invited,
    );

    // The invitee answers for themselves.
    await store.signIn(player.id);
    expect(store.myInvites.map((m) => m.id), contains(match.id));
    await store.respondToInvite(match.id, accept: true);
    expect(
      match.participantOf(player.id)!.status,
      MatchParticipantStatus.accepted,
    );
    expect(match.acceptedCount, 2);
    expect(store.myInvites, isEmpty);

    // Capacity is now full, so a third player cannot be added.
    await store.signIn(organizer.id);
    await expectLater(
      store.inviteParticipant(match.id, spare.id, side: 1),
      throwsA(isA<StateError>()),
    );

    // And an outsider cannot answer somebody else's invitation.
    await store.signIn(spare.id);
    await expectLater(
      store.respondToInvite(match.id, accept: true),
      throwsA(isA<StateError>()),
    );
  });

  test('declining frees a place again', () async {
    final match = await newMatch(capacity: 2);
    await store.inviteParticipant(match.id, player.id, side: 1);

    await store.signIn(player.id);
    await store.respondToInvite(match.id, accept: false);
    expect(
      match.participantOf(player.id)!.status,
      MatchParticipantStatus.declined,
    );
    expect(match.acceptedCount, 1);

    await store.signIn(organizer.id);
    await store.inviteParticipant(match.id, spare.id, side: 1);
    expect(
      match.participantOf(spare.id)!.status,
      MatchParticipantStatus.invited,
    );
  });

  test(
    'only the organizer assigns, transfers and revokes the scorer',
    () async {
      final match = await newMatch();

      await store.assignMatchScorer(match.id, scorer.id);
      expect(match.scorerId, scorer.id);
      expect(
        store.myScoringMatches.map((m) => m.id),
        isNot(contains(match.id)),
      );

      await store.signIn(scorer.id);
      expect(store.myScoringMatches.map((m) => m.id), contains(match.id));
      await expectLater(
        store.assignMatchScorer(match.id, player.id),
        throwsA(isA<StateError>()),
      );

      await store.signIn(organizer.id);
      await store.assignMatchScorer(match.id, player.id);
      expect(match.scorerId, player.id);
      await store.revokeMatchScorer(match.id);
      expect(match.scorerId, isNull);
    },
  );

  test('scoring is limited to the organizer and the assigned scorer', () async {
    final match = await newMatch();
    await store.assignMatchScorer(match.id, scorer.id);

    // Nobody may record before the match starts.
    await expectLater(
      store.recordEvent(match.id, kind: 'point', side: 0),
      throwsA(isA<StateError>()),
    );

    // A player who is not the scorer cannot start it.
    await store.signIn(player.id);
    await expectLater(store.startMatch(match.id), throwsA(isA<StateError>()));

    await store.signIn(scorer.id);
    await store.startMatch(match.id);
    expect(match.status, FixtureStatus.live);
    expect(match.startedAt, isNotNull);
    await expectLater(store.startMatch(match.id), throwsA(isA<StateError>()));

    // The scorer records; another player is refused.
    final first = await store.recordEvent(
      match.id,
      kind: 'point',
      side: 0,
      clientId: 'tap-1',
    );
    expect(first.seq, 1);
    expect(match.eventCount, 1);

    await store.signIn(player.id);
    await expectLater(
      store.recordEvent(match.id, kind: 'point', side: 1),
      throwsA(isA<StateError>()),
    );
  });

  test('a retried tap is a no-op, not a second score', () async {
    final match = await newMatch();
    await store.startMatch(match.id);

    final first = await store.recordEvent(
      match.id,
      kind: 'point',
      side: 0,
      clientId: 'tap-1',
    );
    final retry = await store.recordEvent(
      match.id,
      kind: 'point',
      side: 0,
      clientId: 'tap-1',
    );

    expect(retry.id, first.id);
    expect(match.events.length, 1);
    expect(match.eventCount, 1);
  });

  test('undo withdraws the newest entry only', () async {
    final match = await newMatch();
    await store.startMatch(match.id);

    final first = await store.recordEvent(
      match.id,
      kind: 'point',
      side: 0,
      clientId: 'tap-1',
    );
    final second = await store.recordEvent(
      match.id,
      kind: 'point',
      side: 1,
      clientId: 'tap-2',
    );

    await expectLater(
      store.voidEvent(match.id, first.id),
      throwsA(isA<StateError>()),
    );

    await store.voidEvent(match.id, second.id);
    expect(second.voided, isTrue);
    expect(match.lastActiveEvent!.id, first.id);
    // The sequence pointer never moves backwards.
    expect(match.eventCount, 2);

    await store.voidEvent(match.id, first.id);
    expect(match.lastActiveEvent, isNull);
    expect(match.scoringLog, isEmpty);
  });

  test('submit, publish and correct follow the RPC matrix', () async {
    final match = await newMatch(capacity: 2);
    await store.assignMatchScorer(match.id, scorer.id);
    await store.startMatch(match.id);
    await store.recordEvent(match.id, kind: 'point', side: 0, clientId: 'a');
    await store.recordEvent(match.id, kind: 'point', side: 0, clientId: 'b');
    // Padel is submitted from the server's fold of the log, so this match has
    // to have played its set out before the scorer can put a result on it.
    for (var i = 0; i < 24; i++) {
      await store.recordEvent(
        match.id,
        kind: 'point',
        side: 0,
        clientId: 'c$i',
      );
    }

    await store.signIn(scorer.id);
    await store.submitResult(
      match.id,
      headline: 'Rao & Iqbal lead',
      detail: 'Points 30-0',
      sideScores: const ['6-0', '0-6'],
      sideValues: const [1, 0],
      winnerIndex: 0,
    );
    expect(match.status, FixtureStatus.submitted);
    expect(match.awaitingReview, isTrue);
    // The scorer's own strings are not what the record keeps: the fold's are.
    expect(match.result!.sideScores, ['6-0', '0-6']);
    expect(match.result!.headline, 'Rao & Iqbal lead');

    // The scorer cannot publish their own result.
    await expectLater(
      store.publishResult(match.id),
      throwsA(isA<StateError>()),
    );
    // And the log is closed for scoring.
    await expectLater(
      store.recordEvent(match.id, kind: 'point', side: 1),
      throwsA(isA<StateError>()),
    );

    await store.signIn(organizer.id);
    await store.publishResult(match.id);
    expect(match.status, FixtureStatus.published);
    expect(match.publishedAt, isNotNull);
    expect(store.completedMatches.map((m) => m.id), contains(match.id));

    await expectLater(
      store.correctResult(
        match.id,
        headline: 'Rao & Iqbal lead',
        detail: 'Points 40-0',
        sideScores: const ['40', '0'],
        sideValues: const [40, 0],
        winnerIndex: 0,
        reason: '  ',
      ),
      throwsA(isA<StateError>()),
    );

    await store.correctResult(
      match.id,
      headline: 'Rao & Iqbal take it',
      detail: 'Points 40-0 after the correction',
      sideScores: const ['40', '0'],
      sideValues: const [40, 0],
      winnerIndex: 0,
      reason: 'The last point was recorded twice',
    );
    expect(match.status, FixtureStatus.published);
    expect(
      match.corrections.single.reason,
      'The last point was recorded twice',
    );
    expect(match.result!.headline, 'Rao & Iqbal take it');
  });

  test('walkover and cancellation are organizer decisions', () async {
    final walkover = await newMatch();
    await store.signIn(player.id);
    await expectLater(
      store.recordMatchWalkover(walkover.id, winnerIndex: 0, reason: 'No show'),
      throwsA(isA<StateError>()),
    );

    await store.signIn(organizer.id);
    await expectLater(
      store.recordMatchWalkover(walkover.id, winnerIndex: 5, reason: 'No show'),
      throwsA(isA<StateError>()),
    );
    await store.recordMatchWalkover(
      walkover.id,
      winnerIndex: 1,
      reason: 'Opponents did not arrive',
    );
    expect(walkover.status, FixtureStatus.walkover);
    expect(walkover.result!.walkover, isTrue);
    expect(walkover.result!.winnerIndex, 1);

    final cancelled = await newMatch();
    await store.signIn(player.id);
    await expectLater(
      store.cancelMatch(cancelled.id),
      throwsA(isA<StateError>()),
    );

    await store.signIn(organizer.id);
    await store.cancelMatch(cancelled.id, reason: 'Court flooded');
    expect(cancelled.status, FixtureStatus.cancelled);

    // A cancelled match can no longer be lost by a walkover.
    await expectLater(
      store.recordMatchWalkover(cancelled.id, winnerIndex: 0, reason: 'Late'),
      throwsA(isA<StateError>()),
    );
  });

  test('the roster is organizer-managed and locked after submission', () async {
    final match = await newMatch(capacity: 4);
    await store.inviteParticipant(match.id, player.id, side: 1);

    // A player cannot remove someone else, and cannot remove the organizer.
    await store.signIn(spare.id);
    await expectLater(
      store.removeParticipant(match.id, player.id),
      throwsA(isA<StateError>()),
    );

    await store.signIn(organizer.id);
    await expectLater(
      store.removeParticipant(match.id, organizer.id),
      throwsA(isA<StateError>()),
    );
    await store.removeParticipant(match.id, player.id);
    expect(
      match.participantOf(player.id)!.status,
      MatchParticipantStatus.removed,
    );

    // Editing is only possible before the first ball.
    await store.startMatch(match.id);
    await expectLater(
      store.updateMatch(
        match.id,
        title: 'Renamed late',
        venue: 'Court three',
        scheduledAt: DateTime.now(),
        sideA: 'Rao & Iqbal',
        sideB: 'Malik & Farooq',
        capacity: 4,
      ),
      throwsA(isA<StateError>()),
    );
  });
}
