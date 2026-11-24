import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/matches/screens/futsal_match_center_view.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/futsal/futsal.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/widgets.dart';

import 'match_scoring_test.dart' as harness;

/// The Futsal Match Center is the only door into a futsal match, so these tests
/// pin the three things a caller reads off it: the folded score, the one action
/// their role allows, and the state of the lineups.
void main() {
  final engine = FutsalEngine();
  final base = DateTime.now().toUtc();

  MatchEvent at(
    int seq,
    int minute,
    String kind,
    int? side, [
    Map<String, dynamic> data = const {},
  ]) => MatchEvent(
    id: 'ev-$seq',
    seq: seq,
    clientId: 'client-$seq',
    kind: kind,
    side: side,
    data: data,
    at: base.add(Duration(minutes: minute)),
    byAccountId: 'organizer',
  );

  MatchEvent clock(int seq, int minute, String action) =>
      at(seq, minute, 'clock', null, {'action': action});

  MatchEvent goal(int seq, int minute, int side, {int half = 0}) =>
      at(seq, minute, 'goal', side, {'half': half, 'goalType': 'regular'});

  SportMatch buildMatch({
    FixtureStatus status = FixtureStatus.live,
    String format = '2 × 20 min',
    List<MatchEvent> events = const [],
    OfficialResult? result,
    String organizerId = 'organizer',
    String? scorerId = 'scorer',
  }) {
    final match = SportMatch(
      id: 'center',
      sport: Sport.futsal,
      formatLabel: format,
      rules: {
        ...engine.rulesForFormat(format),
        'lineups': [
          [for (var i = 0; i < 5; i++) 'a$i'],
          [for (var i = 0; i < 5; i++) 'b$i'],
        ],
      },
      title: 'Futsal derby',
      venue: 'Court 1',
      scheduledAt: base,
      visibility: MatchVisibility.public,
      organizerId: organizerId,
      scorerId: scorerId,
      status: status,
      sideNames: ['North Five', 'South Five'],
      discipline: MatchDiscipline.team,
      capacity: 10,
      createdAt: base,
      participants: [
        for (var side = 0; side < 2; side++)
          for (var i = 0; i < 5; i++)
            MatchParticipant(
              profileId: '${side == 0 ? 'a' : 'b'}$i',
              displayName: '${side == 0 ? 'North' : 'South'} Player ${i + 1}',
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
    MatchProgress? progress,
    FutsalMatchActions actions = const FutsalMatchActions(),
  }) async {
    final store = await harness.loadedStore();
    // Tall enough that the ListView builds every section: the feed, the
    // shootout and the result card all sit below the fold on a real phone.
    await tester.binding.setSurfaceSize(const Size(420, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SessionController(store),
        child: MaterialApp(
          theme: buildSportikaTheme(),
          home: Scaffold(
            body: FutsalMatchCenterView(
              match: match,
              progress: progress ?? fold(match),
              accountId: accountId,
              actions: actions,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the scoreboard reads the fold, not a stored score', () {
    testWidgets('shows the goals, the phase and the banked clock', (
      tester,
    ) async {
      final match = buildMatch(
        events: [clock(1, 0, 'start'), goal(2, 3, 0), clock(3, 20, 'end_half')],
      );
      await pump(tester, match, accountId: 'organizer');

      expect(find.text('North Five'), findsWidgets);
      expect(find.text('South Five'), findsWidgets);
      expect(find.text('1 – 0'), findsOneWidget);
      // Half time: the clock shows the banked 20 minutes and stays there.
      expect(find.text('20:00'), findsOneWidget);
      expect(find.text('Half 1'), findsOneWidget);
      expect(find.text('Half time'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('names the winner once the fold is complete', (tester) async {
      final match = buildMatch(
        events: [
          clock(1, 0, 'start'),
          goal(2, 3, 1),
          clock(3, 20, 'end_half'),
          clock(4, 25, 'resume'),
          clock(5, 45, 'end_half'),
        ],
      );
      await pump(tester, match, accountId: 'organizer');

      expect(find.text('0 – 1'), findsOneWidget);
      expect(find.text('Winner'), findsOneWidget);
      expect(find.text('Full time'), findsOneWidget);
      expect(find.text('Regulation complete'), findsOneWidget);
    });
  });

  group('one door, one button', () {
    testWidgets('a scorer before kick-off is sent to the lineups', (
      tester,
    ) async {
      final match = buildMatch();
      await pump(
        tester,
        match,
        accountId: 'organizer',
        actions: FutsalMatchActions(onScore: () {}, onRecord: (k, s, d) {}),
      );
      expect(find.text('Set up lineups'), findsOneWidget);
      expect(find.text('You are not scoring this match'), findsNothing);
    });

    testWidgets('a scorer on a running clock is sent to the scoreboard', (
      tester,
    ) async {
      final match = buildMatch(events: [clock(1, 0, 'start')]);
      var opened = 0;
      await pump(
        tester,
        match,
        accountId: 'organizer',
        actions: FutsalMatchActions(onScore: () => opened++),
      );
      await harness.tapText(tester, find.text('Score the match'));
      expect(opened, 1);
    });

    testWidgets('a spectator gets a disabled explanation, not a control', (
      tester,
    ) async {
      final match = buildMatch();
      await pump(tester, match, accountId: 'stranger');
      expect(find.text('You are not scoring this match'), findsOneWidget);
      final button = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(button.onPressed, isNull);
      expect(find.text('Set up lineups'), findsNothing);
    });

    testWidgets('a published result turns the button into View result', (
      tester,
    ) async {
      final match = buildMatch(
        status: FixtureStatus.published,
        events: [
          clock(1, 0, 'start'),
          goal(2, 3, 0),
          clock(3, 20, 'end_half'),
          clock(4, 25, 'resume'),
          clock(5, 45, 'end_half'),
        ],
        result: OfficialResult(
          sideScores: const ['1', '0'],
          sideValues: const [1, 0],
          winnerIndex: 0,
          headline: 'North Five win 1-0',
          detail: 'Derived from the log',
          publishedAt: base,
          publishedById: 'organizer',
        ),
      );
      await pump(tester, match, accountId: 'organizer');
      expect(find.text('View result'), findsOneWidget);
      expect(find.text('OFFICIAL RESULT'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('lineups are editable only where the server would accept a write', () {
    testWidgets('a scorer before kick-off can edit both sides', (tester) async {
      final match = buildMatch();
      await pump(
        tester,
        match,
        accountId: 'organizer',
        actions: FutsalMatchActions(onRecord: (k, s, d) {}),
      );
      expect(find.text('Edit Lineup'), findsNWidgets(2));
      expect(find.text('Read only'), findsNothing);
    });

    testWidgets('a spectator sees the same five, read only', (tester) async {
      final match = buildMatch();
      await pump(tester, match, accountId: 'stranger');
      expect(find.text('Edit Lineup'), findsNothing);
      expect(find.text('Read only'), findsOneWidget);
      expect(
        find.text('The starting five is set by the scorer before kick-off.'),
        findsOneWidget,
      );
    });

    testWidgets('the grid locks the moment the clock starts', (tester) async {
      final match = buildMatch(events: [clock(1, 0, 'start')]);
      await pump(
        tester,
        match,
        accountId: 'organizer',
        actions: FutsalMatchActions(onRecord: (k, s, d) {}),
      );
      expect(find.text('Edit Lineup'), findsNothing);
      expect(
        find.text('The lineups are locked once the match has started.'),
        findsOneWidget,
      );
    });
  });

  group('the shootout', () {
    testWidgets('reads the tallies and the kicks from the log', (tester) async {
      final match = buildMatch(
        format: '2 × 20 min · knockout',
        events: [
          clock(1, 0, 'start'),
          clock(2, 20, 'end_half'),
          clock(3, 25, 'resume'),
          clock(4, 45, 'end_half'),
          at(5, 46, 'penalty', 0, {'scored': true}),
          at(6, 47, 'penalty', 1, {'scored': false}),
          at(7, 48, 'penalty', 0, {'scored': true}),
        ],
      );
      await pump(tester, match, accountId: 'organizer');

      expect(find.text('Penalty shootout'), findsWidgets);
      expect(find.text('2 – 0'), findsOneWidget);
      expect(
        find.text('2 and 1 kicks taken · next kicker alternates'),
        findsOneWidget,
      );
      expect(find.text('Scored'), findsNWidgets(2));
      expect(find.text('Missed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the feed', () {
    testWidgets('says so when the log is empty', (tester) async {
      final match = buildMatch();
      await pump(tester, match, accountId: 'organizer');
      expect(find.textContaining('No entries yet.'), findsOneWidget);
    });

    testWidgets('lists the recorded entries newest first', (tester) async {
      final match = buildMatch(
        events: [
          clock(1, 0, 'start'),
          goal(2, 3, 0),
          at(3, 5, 'card', 1, {'colour': 'yellow', 'half': 0}),
        ],
      );
      await pump(tester, match, accountId: 'organizer');
      expect(find.text('Yellow card'), findsOneWidget);
      expect(find.text('Goal'), findsOneWidget);
      expect(find.text('KICK-OFF'), findsOneWidget);
    });
  });
}
