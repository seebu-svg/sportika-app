import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/features/matches/widgets/match_scoring_dock.dart';
import 'package:sportika/features/matches/widgets/racket_match_report.dart';
import 'package:sportika/features/matches/widgets/match_management_widgets.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/profile_module.dart';
import 'package:sportika/features/matches/widgets/match_detail_hero.dart';
import 'package:sportika/features/matches/widgets/match_result_card.dart';
import 'package:sportika/features/matches/widgets/match_result_dialogs.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';

OfficialResult result({
  int winner = 0,
  bool walkover = false,
  String headline = 'Clifton won',
  List<String> scores = const ['125/4', '120/8'],
}) => OfficialResult(
  sideScores: scores,
  sideValues: [125, 120],
  winnerIndex: winner,
  headline: headline,
  detail: 'Community championship',
  publishedAt: DateTime(2026, 11, 16, 18),
  publishedById: 'organizer',
  walkover: walkover,
);
SportMatch fixture(FixtureStatus status, OfficialResult? official) =>
    SportMatch(
      id: 'result',
      sport: Sport.cricket,
      formatLabel: 'T10',
      rules: SportEngines.rulesFor(Sport.cricket, 'T10'),
      title: 'Community championship under the lights',
      venue: 'Clifton ground',
      scheduledAt: DateTime(2026, 11, 16, 18),
      visibility: MatchVisibility.public,
      organizerId: 'organizer',
      status: status,
      sideNames: ['Clifton championship eleven', 'Karachi community all stars'],
      discipline: MatchDiscipline.team,
      capacity: 22,
      createdAt: DateTime(2026, 11, 15),
      result: official,
    );
Future<void> show(
  WidgetTester tester,
  Widget child, {
  double width = 320,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildSportikaTheme(),
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(20), child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'correction sheet preserves score notation and uses a draw headline',
    (tester) async {
      final match = fixture(
        FixtureStatus.published,
        result(winner: -1, headline: 'Draw'),
      );
      CorrectedResult? corrected;
      await show(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              corrected = await showCorrectResultSheet(context, match: match);
            },
            child: const Text('Correct'),
          ),
        ),
      );
      await tester.tap(find.text('Correct'));
      await tester.pumpAndSettle();
      Finder field(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );
      expect(
        tester
            .widget<TextField>(field('Displayed score').first)
            .controller!
            .text,
        '125/4',
      );
      await tester.enterText(field('Headline'), '');
      await tester.enterText(
        field('Why is this changing? (required)'),
        'Recorded total corrected',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save correction'));
      await tester.tap(find.text('Save correction'));
      await tester.pumpAndSettle();
      expect(corrected?.headline, 'Match drawn');
      expect(corrected?.sideScores, ['125/4', '120/8']);
      expect(corrected?.sideValues, [125, 120]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scoring dock shows sync state and disables recovery controls while busy',
    (tester) async {
      final match = fixture(FixtureStatus.live, null);
      final progress = SportEngines.forSport(match.sport)
          .evaluate(sides: match.sideNames, rules: match.rules, events: []);
      for (final width in [320.0, 360.0, 430.0]) {
        for (final sync in MatchSyncState.values) {
          await show(
            tester,
            MatchScoringDock(
              match: match,
              progress: progress,
              sync: sync,
              busy: false,
              onUndo: () {},
              onPause: () {},
            ),
            width: width,
          );
          expect(find.textContaining(sync.label), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
      await show(
        tester,
        MatchScoringDock(
          match: match,
          progress: progress,
          sync: MatchSyncState.syncing,
          busy: true,
          onUndo: () {},
          onPause: () {},
        ),
      );
      expect(find.text('Saving entry…'), findsOneWidget);
      for (final button in tester.widgetList<IconButton>(
        find.byType(IconButton),
      )) {
        expect(button.onPressed, isNull);
      }
    },
  );

  testWidgets(
    'member selection wraps long names without losing the selected state',
    (tester) async {
      const member = ProfileSummary(
        id: 'member',
        displayName: 'A very long community player name',
        username: 'communityplayer',
        city: 'Karachi',
      );
      var selected = false;
      await show(
        tester,
        MatchMemberSearchTile(
          player: member,
          selected: true,
          onTap: () => selected = true,
        ),
      );
      await tester.tap(find.text(member.label));
      expect(selected, isTrue);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('padel report derives completed sets from recorded points', (
    tester,
  ) async {
    final match = fixture(FixtureStatus.live, null)..sport = Sport.padel;
    final engine = SportEngines.forSport(match.sport);
    match.rules = engine.rulesForFormat(engine.formats.first);
    final events = [
      for (var i = 0; i < 24; i++)
        ScoringEvent(
          id: '$i',
          kind: 'point',
          side: 0,
          data: const {},
          at: DateTime(2026, 11, 16, 18),
          byAccountId: 'scorer',
        ),
    ];
    final progress = engine.evaluate(
      sides: match.sideNames,
      rules: match.rules,
      events: events,
    );
    await show(tester, RacketMatchReport(match: match, progress: progress));
    expect(find.text('Set 1'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final status in [
    FixtureStatus.submitted,
    FixtureStatus.published,
    FixtureStatus.walkover,
  ]) {
    testWidgets(
      '${status.name}: hero displays authoritative result at narrow enlarged text',
      (tester) async {
        final match = fixture(
          status,
          result(walkover: status == FixtureStatus.walkover),
        );
        final engine = SportEngines.forSport(match.sport);
        final progress = engine.evaluate(
          sides: match.sideNames,
          rules: match.rules,
          events: [],
        );
        await show(tester, MatchDetailHero(match: match, progress: progress));
        expect(find.byType(MatchResultCard), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(MatchResultCard),
            matching: find.text(
              status == FixtureStatus.submitted
                  ? 'AWAITING REVIEW'
                  : 'OFFICIAL RESULT',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.text(status == FixtureStatus.walkover ? 'W/O' : '125/4'),
          findsOneWidget,
        );
        expect(find.text('WINNER'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('cancelled match never presents a stale result as official', (
    tester,
  ) async {
    final match = fixture(FixtureStatus.cancelled, result());
    final progress = SportEngines.forSport(match.sport)
        .evaluate(sides: match.sideNames, rules: match.rules, events: []);
    await show(tester, MatchDetailHero(match: match, progress: progress));
    expect(find.byType(MatchResultCard), findsNothing);
    expect(
      find.text('This match was cancelled. No official result was awarded.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'draw and corrected result retain both score versions and reason',
    (tester) async {
      final previous = result();
      final current = result(
        winner: -1,
        headline: '',
        scores: ['125/4', '125/8'],
      );
      final match = fixture(FixtureStatus.published, current);
      match.corrections.add(
        ResultCorrection(
          id: 'correction',
          previous: previous,
          current: current,
          reason: 'Final over total corrected',
          byAccountId: 'organizer',
          at: DateTime(2026, 11, 16, 19),
        ),
      );
      await show(
        tester,
        Column(
          children: [
            MatchResultCard(match: match),
            MatchCorrectionHistory(match: match),
          ],
        ),
      );
      expect(find.text('Match drawn'), findsOneWidget);
      expect(find.text('WINNER'), findsNothing);
      expect(find.text('CORRECTED'), findsOneWidget);
      expect(find.text('Final over total corrected'), findsOneWidget);
      expect(find.text('PREVIOUS'), findsOneWidget);
      expect(find.text('UPDATED'), findsOneWidget);
      expect(find.textContaining('120/8'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'submit review remains scrollable and returns the explicit decision',
    (tester) async {
      final match = fixture(FixtureStatus.live, null);
      final progress = SportEngines.forSport(match.sport)
          .evaluate(sides: match.sideNames, rules: match.rules, events: []);
      bool? submitted;
      await show(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              submitted = await confirmSubmitResult(
                context,
                match: match,
                progress: progress,
              );
            },
            child: const Text('Review'),
          ),
        ),
      );
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.text('FINAL SCORE REVIEW'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Keep scoring'));
      await tester.pumpAndSettle();
      expect(submitted, isFalse);
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(submitted, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
