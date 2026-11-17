import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/features/matches/widgets/match_vs_card.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';

import '../test/helpers/harness.dart';

/// The full official-match journey on the device store, driven through the real
/// widget tree: the discovery list and the detail hero are mounted over the
/// same repository the lifecycle calls mutate, so every painted number is the
/// one the shared cricket engine folds from the event log.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an organizer creates, staffs, scores and publishes a match', (
    tester,
  ) async {
    final state = await freshState();
    final organizer = state.accounts[0];
    final scorer = state.accounts[1];
    final player = state.accounts[2];
    await state.signIn(organizer.id);
    await pumpApp(tester, state: state);

    // 1. Create a two-over cricket match, the organizer on side A.
    final format = SportEngines.formatsFor(Sport.cricket).first;
    final match = await state.createMatch(
      MatchDraft(
        sport: Sport.cricket,
        formatLabel: format,
        rules: {
          ...SportEngines.rulesFor(Sport.cricket, format),
          'oversPerInnings': 1,
          'innings': 2,
          'wicketsPerInnings': 10,
        },
        title: 'Sunday throwdown',
        venue: 'Ground two',
        scheduledAt: DateTime.now().add(const Duration(days: 1)),
        visibility: MatchVisibility.public,
        sideA: 'Zara XI',
        sideB: 'Kite XI',
        capacity: 8,
        discipline: MatchDiscipline.team,
      ),
    );
    expect(match.status, FixtureStatus.upcoming);
    expect(match.organizerId, organizer.id);

    // 2. The discovery list the app mounts shows the new fixture.
    Navigator.of(tester.element(find.byType(Navigator).first))
        .pushNamed(AppRoute.matches);
    await tester.pumpAndSettle();
    expect(find.text('Sunday throwdown'), findsWidgets);

    // 3. Invite a player, then hand the scoring pen to a dedicated scorer.
    await state.inviteParticipant(match.id, player.id, side: 1);
    await state.signIn(player.id);
    await state.respondToInvite(match.id, accept: true);
    expect(
      match.participantOf(player.id)!.status,
      MatchParticipantStatus.accepted,
    );

    await state.signIn(organizer.id);
    await state.assignMatchScorer(match.id, scorer.id);
    expect(match.scorerId, scorer.id);

    // 4. The scorer opens the detail hero (the VS card) and starts the match.
    await state.signIn(scorer.id);
    Navigator.of(tester.element(find.byType(Navigator).first))
        .pushNamed(AppRoute.matchDetail, arguments: MatchArgs(match.id));
    await tester.pumpAndSettle();
    expect(find.byType(MatchVsCard), findsWidgets);
    expect(find.text('Zara XI'), findsWidgets);
    expect(find.text('Kite XI'), findsWidgets);

    await state.startMatch(match.id);
    expect(match.status, FixtureStatus.live);

    // 5. Score one legal over of six singles on the log the engine folds.
    for (var ball = 0; ball < 6; ball++) {
      await state.recordEvent(
        match.id,
        kind: 'ball',
        side: 0,
        data: const {'runs': 1},
        clientId: 'over-$ball',
      );
    }
    final live = state.matchById(match.id)!;
    expect(live.eventCount, 6);
    expect(
      state.progressOf(live).isComplete,
      isFalse,
      reason: 'second innings pending',
    );

    // 6. The remaining innings is chased out, then the result is submitted.
    for (var ball = 0; ball < 6; ball++) {
      await state.recordEvent(
        match.id,
        kind: 'ball',
        side: 1,
        data: const {'runs': 1},
        clientId: 'inn2-$ball',
      );
    }
    expect(state.progressOf(state.matchById(match.id)!).isComplete, isTrue);

    await state.submitResult(
      match.id,
      headline: 'Zara XI defend six',
      detail: '6 runs each side, side A struck first',
      sideScores: const ['6', '6'],
      sideValues: const [6, 6],
      winnerIndex: 0,
    );
    expect(state.matchById(match.id)!.status, FixtureStatus.submitted);
    expect(state.matchById(match.id)!.awaitingReview, isTrue);

    // 7. Only the organizer can publish, and publishing settles the fixture.
    await expectLater(
      state.publishResult(match.id),
      throwsA(isA<StateError>()),
      reason: 'the scorer cannot publish their own submission',
    );

    await state.signIn(organizer.id);
    await state.publishResult(match.id);
    final done = state.matchById(match.id)!;
    expect(done.status, FixtureStatus.published);
    expect(done.publishedAt, isNotNull);
    expect(state.completedMatches.map((m) => m.id), contains(done.id));
  });
}
