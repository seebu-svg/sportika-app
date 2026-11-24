// The Cricket Match Center is the only guided door into a cricket match, so
// these tests pin the three things a caller reads off it: the one action their
// role allows, the toss, and the XIs. The setup writes are asserted by their
// payload, because the center must hand the host exactly what the validator
// expects.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/matches/screens/cricket_match_center_view.dart';
import 'package:sportika/features/personal_games/scoring/cricket/cricket.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/widgets.dart';

import 'match_scoring_test.dart' as harness;

void main() {
  final engine = CricketEngine();
  final base = DateTime.now().toUtc();
  var seq = 0;

  MatchEvent at(
    String kind,
    int? side, [
    Map<String, dynamic> data = const {},
  ]) {
    seq++;
    return MatchEvent(
      id: 'ev-$seq',
      seq: seq,
      clientId: 'client-$seq',
      kind: kind,
      side: side,
      data: data,
      at: base.add(Duration(minutes: seq)),
      byAccountId: 'organizer',
    );
  }

  MatchEvent toss(int side, String decision) =>
      at(CricketEngine.kToss, side, {'decision': decision});

  MatchEvent openInnings(int side) => at(CricketEngine.kInningsStart, side);

  MatchEvent lineup(int side) => at(CricketEngine.kLineup, side, {
    'players': ['a0', 'a1', 'a2'],
  });

  SportMatch buildMatch({
    FixtureStatus status = FixtureStatus.live,
    List<MatchEvent> events = const [],
    OfficialResult? result,
  }) {
    final match = SportMatch(
      id: 'center-cricket',
      sport: Sport.cricket,
      formatLabel: 'T2 · 2 overs',
      rules: {
        ...engine.rulesForFormat('T2 · 2 overs'),
        'oversPerInnings': 2,
        'wicketsPerInnings': 3,
      },
      title: 'Cricket derby',
      venue: 'Ground one',
      scheduledAt: base,
      visibility: MatchVisibility.public,
      organizerId: 'organizer',
      scorerId: 'scorer',
      status: status,
      sideNames: const ['Alpha', 'Bravo'],
      discipline: MatchDiscipline.team,
      capacity: 22,
      createdAt: base,
      participants: [
        for (var side = 0; side < 2; side++)
          for (var i = 0; i < 3; i++)
            MatchParticipant(
              profileId: '${side == 0 ? 'a' : 'b'}$i',
              displayName: '${side == 0 ? 'Alpha' : 'Bravo'} Player ${i + 1}',
              side: side,
              status: MatchParticipantStatus.accepted,
            ),
      ],
      events: events,
      result: result,
    );
    match.eventCount = events.length;
    return match;
  }

  MatchProgress fold(SportMatch match) => engine.evaluate(
    sides: match.sideNames,
    rules: match.rules,
    events: match.events.map((e) => e.toScoringEvent()).toList(),
  );

  Future<void> pump(
    WidgetTester tester,
    SportMatch match, {
    String? accountId,
    CricketMatchActions actions = const CricketMatchActions(),
    Size size = const Size(420, 3000),
    double textScale = 1,
  }) async {
    final store = await harness.loadedStore();
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SessionController(store),
        child: MaterialApp(
          theme: buildSportikaTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: CricketMatchCenterView(
              match: match,
              progress: fold(match),
              accountId: accountId,
              actions: actions,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  PrimaryButton primaryByLabel(WidgetTester tester, String label) =>
      tester.widget<PrimaryButton>(find.widgetWithText(PrimaryButton, label));

  /// The side names are painted three times over (scoreboard, toss panel,
  /// scorecard), so the toss chips are picked inside their own card.
  Finder inTossPanel(String text) => find.descendant(
    of: find
        .ancestor(
          of: find.text('WHO WON THE TOSS?'),
          matching: find.byType(SurfaceCard),
        )
        .first,
    matching: find.text(text),
  );

  group('one door, one button', () {
    testWidgets('an upcoming match offers to start', (tester) async {
      final match = buildMatch(status: FixtureStatus.upcoming);
      var started = 0;
      await pump(
        tester,
        match,
        accountId: 'organizer',
        actions: CricketMatchActions(onStart: () async => started++),
      );
      expect(find.text('Start the match'), findsOneWidget);
      await harness.tapText(tester, find.text('Start the match'));
      expect(started, 1);
    });

    testWidgets('a live match with no toss asks for the toss', (tester) async {
      await pump(tester, buildMatch(), accountId: 'organizer');
      expect(find.text('Set the toss'), findsOneWidget);
    });

    testWidgets('a recorded toss without XIs asks for the XIs', (tester) async {
      final match = buildMatch(events: [toss(0, 'bat')]);
      await pump(tester, match, accountId: 'organizer');
      expect(find.text('Name the XIs'), findsOneWidget);
      expect(
        find.textContaining('won the toss and elected to bat'),
        findsWidgets,
      );
    });

    testWidgets('toss and XIs ask for the innings to start', (tester) async {
      final match = buildMatch(events: [toss(0, 'bat'), lineup(0), lineup(1)]);
      final writes = <(String, int?, Map<String, dynamic>)>[];
      await pump(
        tester,
        match,
        accountId: 'organizer',
        actions: CricketMatchActions(
          onRecord: (kind, side, data) => writes.add((kind, side, data)),
        ),
      );
      expect(find.text('Start the innings'), findsOneWidget);
      await harness.tapText(tester, find.text('Start the innings'));
      expect(writes.single.$1, CricketEngine.kInningsStart);
      expect(writes.single.$2, 0);
    });

    testWidgets('an open innings sends the scorer to the pad', (tester) async {
      final match = buildMatch(
        events: [toss(0, 'bat'), lineup(0), lineup(1), openInnings(0)],
      );
      var opened = 0;
      await pump(
        tester,
        match,
        accountId: 'organizer',
        actions: CricketMatchActions(onScore: () => opened++),
      );
      expect(find.text('Score the match'), findsOneWidget);
      await harness.tapText(tester, find.text('Score the match'));
      expect(opened, 1);
    });

    testWidgets('a published result turns the button into View result', (
      tester,
    ) async {
      final match = buildMatch(
        status: FixtureStatus.published,
        events: [
          toss(0, 'bat'),
          lineup(0),
          lineup(1),
          openInnings(0),
          at(CricketEngine.kBall, 0, {
            'runs': 4,
            'striker': 'Alpha Player 1',
            'nonStriker': 'Alpha Player 2',
            'bowler': 'Bravo Player 1',
          }),
          at(CricketEngine.kInningsEnd, null, {'reason': 'Innings closed'}),
          at(CricketEngine.kInningsStart, 1),
          at(CricketEngine.kBall, 1, {
            'runs': 1,
            'striker': 'Bravo Player 1',
            'nonStriker': 'Bravo Player 2',
            'bowler': 'Alpha Player 1',
          }),
          at(CricketEngine.kInningsEnd, null, {'reason': 'Innings closed'}),
        ],
        result: OfficialResult(
          sideScores: const ['4/0', '1/0'],
          sideValues: const [4, 1],
          winnerIndex: 0,
          headline: 'Alpha won by 3 runs',
          detail: 'Derived from the log',
          publishedAt: base,
          publishedById: 'organizer',
        ),
      );
      await pump(tester, match, accountId: 'organizer');
      expect(find.text('View result'), findsOneWidget);
      expect(find.text('OFFICIAL RESULT'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('the toss', () {
    testWidgets('is written as a toss event with the winner and decision', (
      tester,
    ) async {
      final writes = <(String, int?, Map<String, dynamic>)>[];
      await pump(
        tester,
        buildMatch(),
        accountId: 'organizer',
        actions: CricketMatchActions(
          onRecord: (kind, side, data) => writes.add((kind, side, data)),
        ),
      );
      await harness.tapText(tester, inTossPanel('Bravo'));
      await harness.tapText(tester, inTossPanel('Bowl'));
      await harness.tapText(tester, find.text('Record the toss'));
      expect(writes.single.$1, CricketEngine.kToss);
      expect(writes.single.$2, 1);
      expect(writes.single.$3, {'decision': 'bowl'});
    });

    testWidgets('is read only once it is on the record', (tester) async {
      final match = buildMatch(events: [toss(1, 'bowl')]);
      await pump(
        tester,
        match,
        accountId: 'organizer',
        actions: CricketMatchActions(onRecord: (k, s, d) {}),
      );
      expect(find.text('Record the toss'), findsNothing);
      expect(
        find.text('Bravo won the toss and elected to bowl.'),
        findsOneWidget,
      );
    });
  });

  group('the XIs', () {
    testWidgets('are written in the order the players were tapped', (
      tester,
    ) async {
      final writes = <(String, int?, Map<String, dynamic>)>[];
      final match = buildMatch(events: [toss(0, 'bat')]);
      await pump(
        tester,
        match,
        accountId: 'organizer',
        actions: CricketMatchActions(
          onRecord: (kind, side, data) => writes.add((kind, side, data)),
        ),
      );
      await harness.tapText(tester, find.text('Edit XI').first);
      await harness.tapText(tester, find.text('Alpha Player 2'));
      expect(primaryByLabel(tester, 'Save XI').onPressed, isNull);
      await harness.tapText(tester, find.text('Alpha Player 1'));
      await harness.tapText(tester, find.text('Save XI'));
      expect(writes.single.$1, CricketEngine.kLineup);
      expect(writes.single.$2, 0);
      expect(writes.single.$3, {
        'players': ['a1', 'a0'],
      });
    });

    testWidgets('are read only for a spectator', (tester) async {
      await pump(tester, buildMatch(), accountId: 'stranger');
      expect(find.text('You are not scoring this match'), findsOneWidget);
      expect(find.text('Edit XI'), findsNothing);
      expect(find.text('Read only'), findsWidgets);
      final button = primaryByLabel(tester, 'You are not scoring this match');
      expect(button.onPressed, isNull);
    });
  });

  group('layout', () {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      testWidgets('holds together at ${width.toInt()} dp with large text', (
        tester,
      ) async {
        final match = buildMatch(
          events: [
            toss(0, 'bat'),
            lineup(0),
            lineup(1),
            openInnings(0),
            at(CricketEngine.kBall, 0, {
              'runs': 6,
              'striker': 'Alpha Player 1',
              'nonStriker': 'Alpha Player 2',
              'bowler': 'Bravo Player 1',
            }),
          ],
        );
        await pump(
          tester,
          match,
          accountId: 'organizer',
          size: Size(width, 3200),
          textScale: 1.3,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
