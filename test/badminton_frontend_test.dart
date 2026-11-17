import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/features/matches/scoring/badminton_scoring_workspace.dart';
import 'package:sportika/features/personal_games/scoring/badminton/badminton.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';

void main() {
  final engine = BadmintonEngine();
  final rules = engine.rulesForFormat('Singles · best of 3');
  final time = DateTime.utc(2026);
  SportMatch fixture() => SportMatch(
    id: 'badminton',
    sport: Sport.badminton,
    formatLabel: 'Singles · best of 3',
    rules: rules,
    title: 'Official singles',
    venue: 'Court 1',
    scheduledAt: time,
    visibility: MatchVisibility.public,
    organizerId: 'organizer',
    status: FixtureStatus.live,
    sideNames: ['Ahmed', 'Hamza'],
    discipline: MatchDiscipline.singles,
    capacity: 2,
    createdAt: time,
  );
  MatchProgress fold(List<int> winners) => engine.evaluate(
    sides: ['Ahmed', 'Hamza'],
    rules: rules,
    events: [
      for (var i = 0; i < winners.length; i++)
        ScoringEvent(
          id: '$i',
          kind: 'rally',
          side: winners[i],
          data: const {},
          at: time,
          byAccountId: 'organizer',
        ),
    ],
  );
  Future<void> pump(
    WidgetTester tester,
    MatchProgress progress, {
    bool scorer = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BadmintonScoringWorkspace(
              match: fixture(),
              progress: progress,
              accent: Colors.blue,
              onRecord: scorer ? (kind, side, data) {} : null,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'spectators see service court and no rally controls at narrow width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pump(tester, fold([0]));
      expect(find.text('Serving · left court'), findsOneWidget);
      expect(find.text('Rally won by'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('deuce and cap cues follow engine data', (tester) async {
    final deuce = [
      for (var i = 0; i < 20; i++) ...[0, 1],
    ];
    await pump(tester, fold(deuce), scorer: true);
    expect(find.text('DEUCE · WIN BY 2'), findsOneWidget);
    await pump(
      tester,
      fold([
        for (var i = 0; i < 29; i++) ...[0, 1],
      ]),
    );
    expect(find.text('GOLDEN POINT · NEXT RALLY WINS'), findsOneWidget);
  });
  testWidgets(
    'completed matches show only finished games and no scoring controls',
    (tester) async {
      await pump(tester, fold(List.filled(42, 0)), scorer: true);
      expect(find.text('Match complete'), findsOneWidget);
      expect(find.text('In progress'), findsNothing);
      expect(find.text('Rally won by'), findsNothing);
      expect(find.text('Games won · 2 – 0'), findsOneWidget);
    },
  );
}
