// A whole cricket match, end to end: the toss, both XIs, both innings and the
// result, first through the repository as the organizer, then as the assigned
// scorer. The refusals are here too, because the plan turns the client's
// completeness rule into a door the shell must keep shut, and turns the fixture
// into a normal draft that carries its ids and its scorer into the match.

import 'package:flutter_test/flutter_test.dart';

import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/features/matches/scoring/match_scoring_validator.dart';
import 'package:sportika/features/personal_games/scoring/cricket/cricket.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/widgets/widgets.dart';

import 'match_scoring_test.dart' as harness;

void main() {
  late LocalSportikaRepository store;
  late Account organizer;
  late Account scorer;
  late Account stranger;
  late List<Account> sideA;
  late List<Account> sideB;

  setUp(() async {
    store = await harness.loadedStore();
    organizer = store.accounts[0];
    scorer = store.accounts[1];
    stranger = store.accounts[2];
    sideA = [store.accounts[0], store.accounts[3], store.accounts[4]];
    sideB = [store.accounts[5], store.accounts[6], store.accounts[7]];
    await store.signIn(organizer.id);
  });

  Future<SportMatch> cricketMatch({
    String? scorerId,
    Map<String, dynamic> overrides = const {
      'oversPerInnings': 2,
      'wicketsPerInnings': 3,
      'innings': 2,
    },
  }) async {
    final format = SportEngines.formatsFor(Sport.cricket).first;
    return store.createMatch(
      MatchDraft(
        sport: Sport.cricket,
        formatLabel: format,
        rules: {...SportEngines.rulesFor(Sport.cricket, format), ...overrides},
        title: 'Cricket flow',
        venue: 'Ground one',
        scheduledAt: DateTime.now().add(const Duration(hours: 1)),
        visibility: MatchVisibility.public,
        sideA: 'Alpha',
        sideB: 'Bravo',
        capacity: 30,
        discipline: MatchDiscipline.team,
        scorerId: scorerId,
      ),
    );
  }

  Future<void> accept(SportMatch match, Account account, int side) async {
    await store.inviteParticipant(match.id, account.id, side: side);
    await store.signIn(account.id);
    await store.respondToInvite(match.id, accept: true);
    await store.signIn(organizer.id);
  }

  /// Fills both sides, so a lineup can name three accepted players per team.
  Future<void> stockSides(SportMatch match) async {
    for (final account in sideA) {
      if (account.id != organizer.id) await accept(match, account, 0);
    }
    for (final account in sideB) {
      await accept(match, account, 1);
    }
  }

  MatchProgress current(SportMatch match) =>
      store.progressOf(store.matchById(match.id)!);

  /// Records through the validator the Match Center uses, so the flow proves
  /// the two agree rather than only that the repository accepts a write.
  Future<void> record(
    SportMatch match,
    String kind,
    int? side, [
    Map<String, dynamic> data = const {},
  ]) async {
    final refusal = MatchScoringValidator.validate(
      match: store.matchById(match.id)!,
      progress: current(match),
      kind: kind,
      side: side,
      data: data,
    );
    expect(refusal, isNull, reason: '$kind was refused: $refusal');
    await store.recordEvent(match.id, kind: kind, side: side, data: data);
  }

  Future<void> ball(
    SportMatch match,
    int side,
    int runs, {
    String? striker,
    String? nonStriker,
    String? bowler,
    String? extra,
    String? dismissal,
    String? dismissedBatter,
  }) {
    final data = <String, dynamic>{
      'runs': runs,
      'extra': ?extra,
      'dismissal': ?dismissal,
      'dismissedBatter': ?dismissedBatter,
      'striker': ?striker,
      'nonStriker': ?nonStriker,
      'bowler': ?bowler,
    };
    if (dismissal != null) data['wicket'] = true;
    return record(match, CricketEngine.kBall, side, data);
  }

  /// The setup every scorer walks through before the first delivery.
  Future<void> setUpBothSides(SportMatch match) async {
    await record(match, CricketEngine.kToss, 0, {'decision': 'bat'});
    await record(match, CricketEngine.kLineup, 0, {
      'players': [for (final a in sideA) a.id],
    });
    await record(match, CricketEngine.kLineup, 1, {
      'players': [for (final a in sideB) a.id],
    });
    await record(match, CricketEngine.kInningsStart, 0);
  }

  test(
    'the organizer carries a match from the toss to a published result',
    () async {
      final match = await cricketMatch();
      await stockSides(match);

      // Nothing is written before the match starts.
      await expectLater(
        store.recordEvent(
          match.id,
          kind: CricketEngine.kBall,
          side: 0,
          data: const {'runs': 1},
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Scores can only be recorded while the match is live.',
          ),
        ),
      );

      await store.startMatch(match.id);
      await setUpBothSides(match);

      // An innings exists on the board before its first delivery.
      expect(current(match).state['open'], isTrue);
      expect(current(match).lines[0].value, '0/0');

      await ball(
        match,
        0,
        4,
        striker: sideA[0].displayName,
        nonStriker: sideA[1].displayName,
        bowler: sideB[0].displayName,
      );
      await ball(
        match,
        0,
        1,
        striker: sideA[0].displayName,
        nonStriker: sideA[1].displayName,
        bowler: sideB[0].displayName,
      );
      // A wide costs a run and does not cost a ball.
      await ball(
        match,
        0,
        0,
        extra: 'wide',
        striker: sideA[1].displayName,
        nonStriker: sideA[0].displayName,
        bowler: sideB[0].displayName,
      );
      await ball(
        match,
        0,
        2,
        striker: sideA[1].displayName,
        nonStriker: sideA[0].displayName,
        bowler: sideB[0].displayName,
      );
      // A wicket installs the next name in the XI for the workspace.
      await ball(
        match,
        0,
        0,
        striker: sideA[1].displayName,
        nonStriker: sideA[0].displayName,
        bowler: sideB[0].displayName,
        dismissal: 'Bowled',
        dismissedBatter: sideA[1].displayName,
      );
      await ball(
        match,
        0,
        6,
        striker: sideA[2].displayName,
        nonStriker: sideA[0].displayName,
        bowler: sideB[0].displayName,
      );

      await record(match, CricketEngine.kInningsEnd, 0, {
        'reason': 'Innings closed',
      });

      final first = current(match);
      expect(first.lines[0].value, '14/1');
      expect(first.state['open'], isFalse);
      expect(first.state['nextBatSide'], 1);
      // The incoming side is due to bat, so the second innings can be opened.
      await record(match, CricketEngine.kInningsStart, 1);
      expect(current(match).state['target'], 15);

      await ball(
        match,
        1,
        4,
        striker: sideB[0].displayName,
        nonStriker: sideB[1].displayName,
        bowler: sideA[0].displayName,
      );
      await ball(
        match,
        1,
        6,
        striker: sideB[0].displayName,
        nonStriker: sideB[1].displayName,
        bowler: sideA[0].displayName,
      );
      await record(match, CricketEngine.kInningsEnd, 1, {
        'reason': 'Innings closed',
      });

      final finished = current(match);
      expect(finished.isComplete, isTrue);
      expect(finished.winnerIndex, 0);
      expect(finished.resultLabel, 'Alpha won by 4 runs');

      await store.submitResult(
        match.id,
        headline: finished.headline,
        detail: finished.detailRows.join(' · '),
        sideScores: finished.scoreDisplay,
        sideValues: finished.scoreValues,
        winnerIndex: finished.winnerIndex,
      );
      expect(store.matchById(match.id)!.status, FixtureStatus.submitted);

      await store.publishResult(match.id);
      final published = store.matchById(match.id)!;
      expect(published.status, FixtureStatus.published);
      expect(published.result!.winnerIndex, 0);
    },
  );

  test(
    'the assigned scorer records and submits, but never publishes',
    () async {
      final match = await cricketMatch(scorerId: scorer.id);
      await stockSides(match);

      await store.signIn(scorer.id);
      expect(store.matchById(match.id)!.canScore(scorer.id), isTrue);
      await store.startMatch(match.id);
      await setUpBothSides(match);
      await ball(
        match,
        0,
        4,
        striker: sideA[0].displayName,
        nonStriker: sideA[1].displayName,
        bowler: sideB[0].displayName,
      );
      await record(match, CricketEngine.kInningsEnd, 0, {
        'reason': 'Innings closed',
      });
      await record(match, CricketEngine.kInningsStart, 1);
      await ball(
        match,
        1,
        1,
        striker: sideB[0].displayName,
        nonStriker: sideB[1].displayName,
        bowler: sideA[0].displayName,
      );
      await record(match, CricketEngine.kInningsEnd, 1, {
        'reason': 'Innings closed',
      });

      final progress = current(match);
      expect(progress.isComplete, isTrue);
      await store.submitResult(
        match.id,
        headline: progress.headline,
        detail: progress.detailRows.join(' · '),
        sideScores: progress.scoreDisplay,
        sideValues: progress.scoreValues,
        winnerIndex: progress.winnerIndex,
      );
      expect(store.matchById(match.id)!.status, FixtureStatus.submitted);

      await expectLater(
        store.publishResult(match.id),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Only the organizer can publish the result.',
          ),
        ),
      );
    },
  );

  test('a third account is refused at the log and at the submission', () async {
    final match = await cricketMatch();
    await stockSides(match);
    await store.startMatch(match.id);
    await setUpBothSides(match);

    await store.signIn(stranger.id);
    await expectLater(
      store.recordEvent(
        match.id,
        kind: CricketEngine.kBall,
        side: 0,
        data: const {'runs': 1},
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'Only the organizer or the assigned official scorer can record scores.',
        ),
      ),
    );
    expect(current(match).lines[0].value, '0/0');
    await expectLater(
      store.submitResult(
        match.id,
        headline: 'Alpha won',
        detail: 'Log',
        sideScores: const ['1/0', '0/0'],
        sideValues: const [1, 0],
        winnerIndex: 0,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'Only the organizer or the official scorer can submit.',
        ),
      ),
    );
  });

  testWidgets('the shell refuses to submit half a match until it is ended', (
    tester,
  ) async {
    final match = await cricketMatch();
    await stockSides(match);
    await store.startMatch(match.id);
    await setUpBothSides(match);
    await ball(
      match,
      0,
      4,
      striker: sideA[0].displayName,
      nonStriker: sideA[1].displayName,
      bowler: sideB[0].displayName,
    );
    await record(match, CricketEngine.kInningsEnd, 0, {
      'reason': 'Innings closed',
    });
    expect(current(match).isComplete, isFalse);

    await harness.pumpScoring(tester, store, match.id);
    expect(find.text('End the match first'), findsOneWidget);
    final blocked = tester.widget<PrimaryButton>(
      find.widgetWithText(PrimaryButton, 'End the match first'),
    );
    expect(blocked.onPressed, isNull);
    await harness.drainSnack(tester);

    // An abandoned game is finished with the match_end event, and that makes
    // the fold complete, so the result becomes submittable.
    await harness.tapText(tester, find.text('End match'));
    await harness.confirmDialog(tester, 'End match');
    final ended = current(match);
    expect(ended.isComplete, isTrue);
    expect(ended.headline, 'No result');
    expect(ended.completionReason, 'Match ended');
    await harness.drainSnack(tester);

    expect(find.text('Submit final result'), findsOneWidget);
    await harness.tapText(tester, find.text('Submit final result'));
    await harness.confirmDialog(tester, 'Submit');
    expect(store.matchById(match.id)!.status, FixtureStatus.submitted);
    await harness.drainSnack(tester);
  });

  test('a fixture draft carries its ids, its rules and its scorer', () async {
    await store.createTournament(
      name: 'Cricket Cup',
      city: 'Lahore',
      sport: Sport.cricket,
      format: TournamentFormat.knockout,
      entryType: EntryType.team,
      startsAt: DateTime.now().add(const Duration(days: 1)),
      endsAt: DateTime.now().add(const Duration(days: 3)),
      registrationLimit: 8,
      entryFee: 'Free',
      rulesSummary: '2 overs · 3 wickets',
      rules: const {'oversPerInnings': 2, 'wicketsPerInnings': 3},
      publishNow: true,
    );
    final tournament = store.tournaments.firstWhere(
      (t) => t.name == 'Cricket Cup',
    );
    final fixture = Fixture(
      id: 'cup-fixture',
      tournamentId: tournament.id,
      stage: 'Semi final',
      round: 1,
      home: FixtureSide(entryId: 'cup-home', label: 'Alpha XI'),
      away: FixtureSide(entryId: 'cup-away', label: 'Bravo XI'),
      scheduledAt: DateTime.now().add(const Duration(hours: 2)),
      venue: 'Cup ground',
      status: FixtureStatus.upcoming,
      scorerAccountIds: [scorer.id],
      events: const [],
      rules: const {'oversPerInnings': 2, 'wicketsPerInnings': 3},
      corrections: [],
    );
    store.fixtures.add(fixture);
    store.notifyListeners();

    // The same draft the create screen builds from a fixture door.
    final created = await store.createMatch(
      MatchDraft(
        sport: tournament.sport,
        formatLabel: SportEngines.formatsFor(tournament.sport).first,
        rules: {
          ...SportEngines.rulesFor(tournament.sport, tournament.matchRules),
          ...fixture.rules,
          'competitionName': tournament.name,
          'stage': fixture.stage,
        },
        title: '${tournament.name} · ${fixture.stage}',
        venue: fixture.venue,
        scheduledAt: fixture.scheduledAt,
        visibility: MatchVisibility.public,
        sideA: fixture.home.label,
        sideB: fixture.away.label,
        capacity: 22,
        discipline: MatchDiscipline.team,
        scorerId: fixture.scorerAccountIds.firstOrNull,
        tournamentId: tournament.id,
        fixtureId: fixture.id,
      ),
    );

    expect(store.matchOfFixture(tournament.id, fixture.id)?.id, created.id);
    expect(created.tournamentId, tournament.id);
    expect(created.fixtureId, fixture.id);
    expect(created.rules['competitionName'], 'Cricket Cup');
    expect(created.rules['stage'], 'Semi final');
    expect(created.rules['oversPerInnings'], 2);
    expect(created.sideNames, ['Alpha XI', 'Bravo XI']);
    expect(created.canScore(fixture.scorerAccountIds.first), isTrue);

    // And the fixture's scorer can open it, the same way the Match Center will.
    await store.signIn(scorer.id);
    await store.startMatch(created.id);
    await record(created, CricketEngine.kToss, 1, {'decision': 'bowl'});
    expect(current(created).state['nextBatSide'], 0);
  });
}
