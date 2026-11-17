import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/features/matches/widgets/match_event_timeline.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';

MatchEvent entry(
  int seq,
  String kind,
  Map<String, dynamic> data, {
  int? side = 0,
  bool voided = false,
}) => MatchEvent(
  id: '$seq',
  seq: seq,
  clientId: '$seq',
  kind: kind,
  side: side,
  data: data,
  at: DateTime(2026, 11, 16, 18, seq),
  byAccountId: 'scorer',
  voided: voided,
);

SportMatch fixture(Sport sport, List<MatchEvent> events) => SportMatch(
  id: 'timeline',
  sport: sport,
  formatLabel: 'Friendly',
  rules: {},
  title: 'Community match',
  venue: 'Court one',
  scheduledAt: DateTime(2026, 11, 16),
  visibility: MatchVisibility.public,
  organizerId: 'organizer',
  status: FixtureStatus.live,
  sideNames: ['Clifton community championship side', 'Karachi all stars'],
  discipline: MatchDiscipline.team,
  capacity: 22,
  createdAt: DateTime(2026, 11, 15),
  events: events,
);

Future<void> showTimeline(
  WidgetTester tester,
  SportMatch match, {
  int limit = 12,
}) async {
  await tester.binding.setSurfaceSize(const Size(320, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildSportikaTheme(),
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: MatchEventTimeline(
                match: match,
                showFilters: true,
                limit: limit,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'long histories render in batches and retain access to earlier entries',
    (tester) async {
      final match = fixture(Sport.padel, [
        for (var i = 1; i <= 65; i++) entry(i, 'point', {}),
      ]);
      await showTimeline(tester, match, limit: 65);
      expect(find.textContaining('#65 · Recorded'), findsOneWidget);
      expect(find.textContaining('#1 · Recorded'), findsNothing);
      expect(find.text('35 earlier entries kept in the log'), findsOneWidget);
      await tester.ensureVisible(find.text('Show earlier entries'));
      await tester.tap(find.text('Show earlier entries'));
      await tester.pumpAndSettle();
      expect(find.text('5 earlier entries kept in the log'), findsOneWidget);
      await tester.ensureVisible(find.text('Show earlier entries'));
      await tester.tap(find.text('Show earlier entries'));
      await tester.pumpAndSettle();
      expect(find.textContaining('#1 · Recorded'), findsOneWidget);
      expect(find.text('Show earlier entries'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'key moments exclude voided goals while the full log retains sequence order',
    (tester) async {
      final match = fixture(Sport.futsal, [
        entry(1, 'goal', {'half': 0, 'player': 'Ali'}),
        entry(2, 'foul', {'half': 1}, side: 1),
        entry(3, 'goal', {'half': 1}, side: 1, voided: true),
      ]);
      await showTimeline(tester, match);
      expect(find.text('Voided · excluded from score'), findsOneWidget);
      expect(find.text('PERIOD 2'), findsOneWidget);
      expect(
        tester.getTopLeft(find.textContaining('#3 · Recorded')).dy,
        lessThan(tester.getTopLeft(find.textContaining('#1 · Recorded')).dy),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Key moments (1)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('#1 · Recorded'), findsOneWidget);
      expect(find.textContaining('#3 · Recorded'), findsNothing);
      expect(find.textContaining('Foul ·'), findsNothing);
      await tester.tap(find.text('All entries'));
      await tester.pumpAndSettle();
      expect(find.text('Voided · excluded from score'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cricket highlights wickets and boundaries without highlighting withdrawn entries',
    (tester) async {
      final match = fixture(Sport.cricket, [
        entry(1, 'ball', {'runs': 4}),
        entry(2, 'ball', {'runs': 1}),
        entry(3, 'ball', {'runs': 0, 'wicket': true}),
        entry(4, 'ball', {'runs': 6}, voided: true),
      ]);
      await showTimeline(tester, match);
      await tester.tap(find.text('Key moments (2)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Wicket ·'), findsOneWidget);
      expect(find.textContaining('Four ·'), findsOneWidget);
      expect(find.textContaining('Six ·'), findsNothing);
      expect(find.textContaining('1 run ·'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'limits retain an earlier-entry count and empty highlights explain themselves',
    (tester) async {
      final match = fixture(Sport.padel, [
        entry(1, 'point', {}),
        entry(2, 'point', {}),
      ]);
      await showTimeline(tester, match, limit: 1);
      expect(find.text('1 earlier entries kept in the log'), findsOneWidget);
      await tester.tap(find.text('Key moments (0)'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'No key moments recorded yet. See All entries for the full log.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('event detail caps fields and hides bookkeeping identifiers', () {
    final event = entry(1, 'foul', {
      'playerId': 'private-id',
      'half': 1,
      'player': 'Ali',
      'reason': 'Contact',
      'note': 'Extra detail',
      'keeperId': 'private-id',
    });
    expect(eventDetail(event), 'Period 2 · Ali · Reason: Contact');
  });
}
