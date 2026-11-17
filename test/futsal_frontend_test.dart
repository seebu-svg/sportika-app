import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/features/matches/scoring/futsal_scoring_workspace.dart';
import 'package:sportika/features/matches/scoring/match_scoring_validator.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/futsal/futsal.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';

import 'match_scoring_test.dart' as harness;
import 'helpers/auth_service_fixture.dart';

import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:provider/provider.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/features/matches/screens/create_match_screen.dart';
import 'package:sportika/features/matches/screens/match_detail_screen.dart';

void main() {
  final engine = FutsalEngine();
  final time = DateTime.utc(2026, 1, 1);
  ScoringEvent event(
    String kind,
    int? side,
    Map<String, dynamic> data, [
    int minute = 0,
  ]) => ScoringEvent(
    id: '$kind-$minute',
    kind: kind,
    side: side,
    data: data,
    at: time.add(Duration(minutes: minute)),
    byAccountId: 'organizer',
  );
  MatchProgress fold(List<ScoringEvent> events, {bool extra = true}) =>
      engine.evaluate(
        sides: ['Home', 'Away'],
        rules: engine.rulesForFormat(
          extra ? '2 × 20 min · extra time & penalties' : '2 × 20 min',
        ),
        events: events,
      );

  test('a tied knockout plays both extra periods before penalties', () {
    final log = <ScoringEvent>[
      event('clock', null, {'action': 'start'}),
      event('clock', null, {'action': 'end_half'}, 20),
      event('clock', null, {'action': 'resume'}, 25),
      event('clock', null, {'action': 'end_half'}, 45),
    ];
    expect(fold(log).isComplete, isFalse);
    log.add(event('clock', null, {'action': 'resume'}, 50));
    expect(fold(log).state['extraTime'], true);
    expect(fold(log).state['periodMinutes'], 5);
    log.add(event('clock', null, {'action': 'end_half'}, 55));
    log.add(event('clock', null, {'action': 'resume'}, 56));
    log.add(event('clock', null, {'action': 'end_half'}, 61));
    expect(fold(log).state['phase'], 'shootout');
    expect(fold(log).state['elapsed'], 50 * 60);
    for (var i = 0; i < 3; i++) {
      log.add(event('penalty', 0, {'scored': true}));
      log.add(event('penalty', 1, {'scored': false}));
    }
    expect(fold(log).isComplete, true);
    expect(fold(log).winnerIndex, 0);
    expect(fold(log).scoreDisplay, ['0', '0']);
  });

  test('a regulation winner skips optional extra time', () {
    final progress = fold([
      event('clock', null, {'action': 'start'}),
      event('goal', 0, {
        'half': 0,
        'goalType': 'ownGoal',
        'player': 'Away player',
      }),
      event('clock', null, {'action': 'end_half'}, 20),
      event('clock', null, {'action': 'resume'}, 25),
      event('clock', null, {'action': 'end_half'}, 45),
    ]);
    expect(progress.isComplete, true);
    expect(progress.scoreDisplay, ['1', '0']);
    expect(progress.winnerIndex, 0);
  });

  test('stoppages bank actual time without truncating long periods', () {
    final progress = fold([
      event('clock', null, {'action': 'start'}),
      event('clock', null, {'action': 'stop'}, 28),
      event('clock', null, {'action': 'resume'}, 31),
      event('clock', null, {'action': 'end_half'}, 33),
    ], extra: false);
    expect(progress.state['elapsed'], 30 * 60);
  });

  test('goals before kick-off and repeated clock starts are refused', () {
    final match = SportMatch(
      id: 'm',
      sport: Sport.futsal,
      formatLabel: '2 × 20 min',
      rules: engine.rulesForFormat('2 × 20 min'),
      title: 'Match',
      venue: 'Court',
      scheduledAt: time,
      visibility: MatchVisibility.public,
      organizerId: 'organizer',
      status: FixtureStatus.live,
      sideNames: ['Home', 'Away'],
      discipline: MatchDiscipline.team,
      capacity: 10,
      createdAt: time,
    );
    expect(
      MatchScoringValidator.validate(
        match: match,
        progress: fold([]),
        kind: 'goal',
        side: 0,
      ),
      isNotNull,
    );
    final running = fold([
      event('clock', null, {'action': 'start'}),
    ]);
    expect(
      MatchScoringValidator.validate(
        match: match,
        progress: running,
        kind: 'clock',
        data: {'action': 'start'},
      ),
      isNotNull,
    );
    expect(
      MatchScoringValidator.validate(
        match: match,
        progress: running,
        kind: 'goal',
        side: 0,
        data: {'half': 9},
      ),
      isNotNull,
    );
  });

  testWidgets(
    'own and penalty goals persist their type and credited team at 320dp',
    (tester) async {
      final store = await harness.loadedStore();
      final organizer = store.accounts.first;
      await store.signIn(organizer.id);
      final match = await store.createMatch(
        MatchDraft(
          sport: Sport.futsal,
          formatLabel: '2 × 20 min',
          rules: engine.rulesForFormat('2 × 20 min'),
          title: 'Futsal derby',
          venue: 'Court',
          scheduledAt: DateTime.now(),
          visibility: MatchVisibility.public,
          sideA: 'Home',
          sideB: 'Away',
          capacity: 14,
          discipline: MatchDiscipline.team,
        ),
      );
      await store.startMatch(match.id);
      await harness.pumpScoring(
        tester,
        store,
        match.id,
        size: const Size(320, 720),
      );
      await harness.tapText(tester, find.text('Start clock'));
      for (final type in ['Own goal', 'Penalty goal']) {
        await harness.tapPad(tester, harness.pad('Goal', 'Home'));
        await tester.tap(find.text(type));
        await tester.pumpAndSettle();
        await tester.tap(find.text('No scorer named'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(store.progressOf(store.matchById(match.id)!).scoreDisplay, [
        '2',
        '0',
      ]);
      expect(
        match.events
            .where((e) => e.kind == 'goal')
            .map((e) => e.data['goalType']),
        ['ownGoal', 'penalty'],
      );
      expect(find.byType(FutsalScoringWorkspace), findsOneWidget);
      await harness.drainSnack(tester);
    },
  );
  testWidgets(
    'friendly creation validates, confirms, then opens the Match Center',
    (tester) async {
      final store = await harness.loadedStore();
      await store.signIn(store.accounts.first.id);
      await tester.binding.setSurfaceSize(const Size(320, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final session = SessionController(store);
      final service = AuthServiceFixture(
        store,
        restoredAccountId: store.accounts.first.id,
      );
      final flow = AuthFlowController(session, service: service);
      addTearDown(service.dispose);
      flow.begin();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SessionController>(create: (_) => session),
            ChangeNotifierProvider<AuthFlowController>(create: (_) => flow),
            ChangeNotifierProvider(create: (_) => MatchController(store)),
            ChangeNotifierProvider(create: (_) => TeamsController(store)),
          ],
          child: MaterialApp(
            theme: buildSportikaTheme(),
            onGenerateRoute: onGenerateRoute,
            home: const Scaffold(body: Text('Matches')),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 1900));
      await tester.pumpAndSettle();
      expect(flow.canAccessApp, true);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(
        MaterialPageRoute<void>(builder: (_) => const CreateMatchScreen()),
      );
      await tester.pumpAndSettle();
      await harness.tapText(tester, find.text('Futsal'));
      Finder field(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label,
      );
      await tester.enterText(field('Match title'), 'Friday futsal');
      await tester.enterText(field('Venue'), 'Court 2');
      await tester.enterText(field('Side A'), 'Home five');
      await tester.enterText(field('Side B'), 'Away five');
      final before = store.matches.length;
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      final action = find.byWidgetPredicate(
        (w) => w is PrimaryButton && w.label == 'Create match',
      );
      await harness.tapText(tester, action);
      expect(find.text('Create this match?'), findsOneWidget);
      expect(store.matches.length, before);
      await harness.confirmDialog(tester, 'Create match');
      expect(store.matches.length, before + 1);
      expect(store.matches.first.sport, Sport.futsal);
      expect(store.matches.first.sideNames, ['Home five', 'Away five']);
      expect(find.byType(MatchDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await harness.drainSnack(tester);
    },
  );
}
