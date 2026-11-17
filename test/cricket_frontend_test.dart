import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/features/matches/widgets/cricket_match_report.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';

import 'match_model_test.dart' show event, matchWith;

void main() {
  final match = matchWith(
    rules: const {'oversPerInnings': 5},
    events: [
      event(1, 'ball', 0, {'runs': 4, 'striker': 'Ali', 'bowler': 'Zain'}),
      event(2, 'ball', 0, {
        'runs': 2,
        'extra': 'wide',
        'striker': 'Ali',
        'bowler': 'Zain',
      }),
      event(3, 'ball', 0, {
        'runs': 6,
        'extra': 'noball',
        'striker': 'Ali',
        'bowler': 'Zain',
      }),
      event(4, 'ball', 0, {
        'runs': 2,
        'extra': 'bye',
        'striker': 'Ali',
        'bowler': 'Zain',
      }),
      event(5, 'ball', 0, {'runs': 6}, voided: true),
      event(6, 'innings_end', 0, {}),
      event(7, 'ball', 1, {'runs': 1, 'striker': 'Zain', 'bowler': 'Ali'}),
    ],
  );

  MatchProgress progressOf(SportMatch m) =>
      SportEngines.forSport(m.sport).evaluate(
        sides: m.sideNames,
        rules: m.rules,
        events: m.events
            .where((e) => !e.voided)
            .map((e) => e.toScoringEvent())
            .toList(),
      );

  test(
    'innings projection excludes undo and separates penalty from bat runs',
    () {
      final report = CricketInningsReport(
        CricketInningsReport.deliveries(match, 0),
      );
      expect(report.balls.length, 4);
      expect(report.legalBalls, 2);
      expect(report.extra('wide'), 3);
      expect(report.extra('noball'), 1);
      expect(report.extra('bye'), 2);
      expect(
        report.balls.fold<int>(0, (n, e) => n + CricketInningsReport.total(e)),
        16,
      );
      expect(CricketInningsReport.deliveries(match, 1).length, 1);
    },
  );

  test('batting, bowling and wicket projections keep the log semantics', () {
    final report = CricketInningsReport(
      CricketInningsReport.deliveries(match, 0),
    );
    final batter = report.batting.single;
    expect(batter.name, 'Ali');
    expect(batter.runs, 10, reason: 'byes and wides are not bat runs');
    expect(batter.balls, 2, reason: 'wides and no-balls are not legal balls');
    expect(batter.fours, 1);
    expect(batter.sixes, 1);
    expect(batter.strikeRate, '500.0');
    expect(batter.notOut, isTrue);

    final bowler = report.bowling.single;
    expect(bowler.name, 'Zain');
    expect(bowler.overs, '0.2');
    expect(bowler.runs, 14, reason: 'byes are not charged to the bowler');
    expect(bowler.wickets, 0);
    expect(bowler.economy, '42.00');

    // No wicket fell in this innings, so only the unbroken stand is listed.
    expect(report.wickets, isEmpty);
    expect(report.partnerships.single.runs, 16);
    expect(report.partnerships.single.unbroken, isTrue);
    expect(report.overs.single.number, 1);
    expect(report.overs.single.runs, 16);
  });

  for (final width in [320.0, 390.0, 600.0]) {
    testWidgets('scorecard fits $width dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildSportikaTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CricketMatchReport(
                match: match,
                progress: progressOf(match),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A live match opens on the innings being batted.
      await tester.tap(find.text('1ST INNINGS'));
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsOneWidget);
      expect(find.text('SCORECARD'), findsOneWidget);
      expect(find.text('BATTING'), findsOneWidget);
      expect(find.text('BOWLING'), findsOneWidget);
      expect(find.text('EXTRAS'), findsOneWidget);
      expect(find.text('WD'), findsOneWidget);
      expect(find.text('500.0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('innings switch, overs and commentary views render', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildSportikaTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CricketMatchReport(
              match: match,
              progress: progressOf(match),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('1ST INNINGS'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Overs'));
    await tester.pumpAndSettle();
    expect(find.text('Over 1'), findsOneWidget);
    expect(find.text('16 runs'), findsOneWidget);
    expect(find.text('BATTING'), findsNothing);

    await tester.tap(find.text('Commentary'));
    await tester.pumpAndSettle();
    expect(find.text('OVER 1'), findsOneWidget);
    expect(find.text('Zain to Ali'), findsWidgets);
    expect(find.text('Wide · 3 runs'), findsOneWidget);

    await tester.tap(find.text('2ND INNINGS'));
    await tester.pumpAndSettle();
    expect(find.text('Zain to Ali'), findsNothing);
    expect(find.text('Ali to Zain'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an innings without deliveries shows a polished empty state', (
    tester,
  ) async {
    final onlyFirst = matchWith(
      rules: const {'oversPerInnings': 5},
      events: [
        event(1, 'ball', 0, {'runs': 4, 'striker': 'Ali', 'bowler': 'Zain'}),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildSportikaTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CricketMatchReport(
              match: onlyFirst,
              progress: progressOf(onlyFirst),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('2ND INNINGS'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing recorded yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long names and large text scale never overflow', (tester) async {
    final longNames = matchWith(
      rules: const {'oversPerInnings': 5},
      events: [
        event(1, 'ball', 0, {
          'runs': 6,
          'striker': 'Muhammad Abdul Rahman Siddiqui',
          'bowler': 'Zain ul Abideen Chaudhry',
        }),
        event(2, 'ball', 0, {
          'runs': 2,
          'extra': 'wide',
          'striker': 'Muhammad Abdul Rahman Siddiqui',
          'bowler': 'Zain ul Abideen Chaudhry',
        }),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(320, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildSportikaTheme(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: CricketMatchReport(
                match: longNames,
                progress: progressOf(longNames),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('BATTING'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
