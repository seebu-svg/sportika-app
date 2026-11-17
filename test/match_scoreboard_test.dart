import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/match_scoreboard.dart';
import 'package:sportika/shared/widgets/widgets.dart';

void main() {
  for (final sport in Sport.values) {
    testWidgets('${sport.name}: no recorded score stays unknown', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildSportikaTheme(),
          home: Scaffold(
            body: MatchScoreboard(sport: sport, labels: const ['Home', 'Away']),
          ),
        ),
      );
      expect(find.text('—'), findsNWidgets(2));
      expect(find.textContaining('Clock'), findsNothing);
      expect(find.textContaining('Innings'), findsNothing);
    });
    testWidgets('${sport.name}: engine data fits narrow screens', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(280, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final engine = SportEngines.forSport(sport);
      final rules = engine.rulesForFormat(engine.formats.first);
      var progress = engine.evaluate(
        sides: ['Home', 'Away'],
        rules: rules,
        events: [],
      );
      final action = progress.actions.first;
      final event = action.build(const ActionContext(side: 0, by: 'tester'));
      progress = engine.evaluate(
        sides: ['Home', 'Away'],
        rules: rules,
        events: [event],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildSportikaTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.3),
                  ),
                  child: MatchScoreboard(
                    sport: sport,
                    labels: const [
                      'A very long team or doubles player name',
                      'Another long opponent name',
                    ],
                    progress: progress,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      for (final line in progress.lines) {
        expect(find.text(line.value), findsWidgets);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final sport in [Sport.padel, Sport.badminton]) {
    testWidgets('${sport.name}: completed progression and doubles identities', (
      tester,
    ) async {
      final engine = SportEngines.forSport(sport);
      final rules = engine.rulesForFormat(engine.formats.first);
      final count = sport == Sport.padel ? 24 : 42;
      final progress = engine.evaluate(
        sides: ['A', 'B'],
        rules: rules,
        events: [
          for (var i = 0; i < count; i++)
            ScoringEvent(
              id: '$i',
              kind: sport == Sport.padel ? 'point' : 'rally',
              side: 0,
              data: {},
              at: DateTime(2026),
              byAccountId: 'scorer',
            ),
        ],
      );
      expect(progress.isComplete, isTrue);
      final players = [
        for (var i = 0; i < 4; i++)
          Account(
            id: '$i',
            displayName: 'Player $i',
            email: '$i@test.com',
            city: '',
            roles: [],
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildSportikaTheme(),
          home: Scaffold(
            body: MatchScoreboard(
              sport: sport,
              labels: const ['A', 'B'],
              progress: progress,
              players: [players.take(2).toList(), players.skip(2).toList()],
              discipline: 'Doubles',
            ),
          ),
        ),
      );
      expect(find.byType(AccountAvatar), findsNWidgets(4));
      expect(find.text('Doubles'), findsOneWidget);
      expect(
        find.text(sport == Sport.padel ? 'Set 1 · 6 – 0' : 'Game 1 · 21 – 0'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Running and stopped clocks follow the recorded period state', (
    tester,
  ) async {
    final engine = SportEngines.forSport(Sport.futsal);
    final start = DateTime.now().subtract(const Duration(seconds: 62));
    ScoringEvent event(String action, DateTime at) => ScoringEvent(
      id: action,
      kind: 'clock',
      side: null,
      data: {'action': action},
      at: at,
      byAccountId: 'scorer',
    );
    final started = event('start', start);
    final running = engine.evaluate(
      sides: ['A', 'B'],
      rules: {},
      events: [started],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FutsalScoreboard(progress: running)),
      ),
    );
    expect(find.textContaining('Clock 01:02'), findsOneWidget);
    final paused = engine.evaluate(
      sides: ['A', 'B'],
      rules: {},
      events: [started, event('stop', start.add(const Duration(seconds: 70)))],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FutsalScoreboard(progress: paused)),
      ),
    );
    expect(find.text('Clock 01:10 · Stopped'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Clock 01:10 · Stopped'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Published correction suppresses stale event progress', (
    tester,
  ) async {
    final engine = SportEngines.forSport(Sport.futsal);
    final progress = engine.evaluate(sides: ['A', 'B'], rules: {}, events: []);
    final result = OfficialResult(
      sideScores: ['3', '2'],
      sideValues: [3, 2],
      winnerIndex: 0,
      headline: 'A won',
      detail: '',
      publishedAt: DateTime(2026),
      publishedById: 'organizer',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchScoreboard(
            sport: Sport.futsal,
            labels: const ['A', 'B'],
            progress: progress,
            result: result,
          ),
        ),
      ),
    );
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.textContaining('Clock'), findsNothing);
  });
}
