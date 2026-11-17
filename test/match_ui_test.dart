import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/matches/screens/match_detail_screen.dart';
import 'package:sportika/features/matches/screens/matches_tab.dart';
import 'package:sportika/features/matches/widgets/match_vs_card.dart';
import 'package:sportika/features/matches/widgets/match_detail_hero.dart';
import 'package:sportika/features/matches/widgets/match_roster_card.dart';
import 'package:sportika/features/matches/widgets/match_participants_sheet.dart';
import 'package:sportika/features/matches/widgets/match_scorer_sheet.dart';
import 'package:sportika/features/matches/widgets/match_lifecycle_bar.dart';
import 'package:sportika/shared/widgets/match_scoreboard.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/state_views.dart';

Future<LocalSportikaRepository> loadedStore() async {
  SharedPreferences.setMockInitialValues({'sportika.onboarding_seen.v1': true});
  final store = LocalSportikaRepository(await LocalStorage.open());
  await store.load();
  return store;
}

/// A store whose reload never lands, so the loading skeleton can be inspected
/// instead of guessed at from a frame that is already gone.
class _GatedStore extends LocalSportikaRepository {
  _GatedStore(super.storage);

  final Completer<void> gate = Completer<void>();

  @override
  Future<void> reload() => gate.future;
}

/// Pumps [child] under the two controllers every match screen reads.
Future<MatchController> pumpScreen(
  WidgetTester tester,
  LocalSportikaRepository store,
  Widget child, {
  Size size = const Size(400, 844),
  double textScale = 1.0,
  bool ownScaffold = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final session = SessionController(store);
  final matches = MatchController(store);
  addTearDown(matches.dispose);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionController>.value(value: session),
        ChangeNotifierProvider<MatchController>.value(value: matches),
      ],
      child: MaterialApp(
        theme: buildSportikaTheme(),
        home: ownScaffold ? child : Scaffold(body: SafeArea(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return matches;
}

void main() {
  late LocalSportikaRepository store;
  late Account organizer;
  late Account player;

  setUp(() async {
    store = await loadedStore();
    organizer = store.accounts[0];
    player = store.accounts[2];
    await store.signIn(organizer.id);
    // The demo document ships with three matches; the UI tests build their own
    // so the titles and statuses under assertion are the ones the test made.
    store.matches.clear();
  });

  Future<SportMatch> matchWith({
    required Sport sport,
    required String title,
    String sideA = 'Rao & Iqbal',
    String sideB = 'Malik Farooq',
    MatchVisibility visibility = MatchVisibility.public,
    bool start = false,
  }) async {
    final format = SportEngines.formatsFor(sport).first;
    final match = await store.createMatch(
      MatchDraft(
        sport: sport,
        formatLabel: format,
        rules: {
          ...SportEngines.rulesFor(sport, format),
          'discipline': MatchDisciplineX.forSport(sport).first.key,
        },
        title: title,
        venue: 'Court one',
        scheduledAt: DateTime.now().add(const Duration(hours: 3)),
        visibility: visibility,
        sideA: sideA,
        sideB: sideB,
        capacity: 4,
        discipline: MatchDisciplineX.forSport(sport).first,
      ),
    );
    if (start) await store.startMatch(match.id);
    return match;
  }

  group('the VS card', () {
    testWidgets('holds both identities from 320 to 430 dp at 1.3x text', (
      tester,
    ) async {
      final match = await matchWith(
        sport: Sport.cricket,
        title: 'Friday night tape-ball derby',
        sideA: 'Rao & Iqbal XI',
        sideB: 'Malik Farooq XI',
      );

      for (final width in [320.0, 360.0, 390.0, 430.0]) {
        await tester.binding.setSurfaceSize(Size(width, 700));
        await tester.pumpWidget(
          MaterialApp(
            theme: buildSportikaTheme(),
            home: Scaffold(
              body: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: MatchVsCard(match: match),
                  ),
                ),
              ),
            ),
          ),
        );
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        expect(find.text('Rao & Iqbal XI'), findsOneWidget);
        expect(find.text('Malik Farooq XI'), findsOneWidget);
        // The medallion is the shared identity mark, never a lookalike.
        expect(find.text('VS'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('shows the score only when a folded log is handed in', (
      tester,
    ) async {
      final match = await matchWith(
        sport: Sport.cricket,
        title: 'Friday night tape-ball derby',
        start: true,
      );
      await store.recordEvent(
        match.id,
        kind: 'ball',
        side: 0,
        data: const {'runs': 4},
      );
      final progress = store.progressOf(match);
      // Cricket paints a per-side "runs/wickets", so the batting side reads
      // 4/0 while the side yet to bat is a dash. That distinct value is what
      // the card must show only once a score is asked for.
      final batting = progress.scoreDisplay.first;

      await pumpScreen(tester, store, MatchVsCard(match: match));
      expect(find.text('VS'), findsOneWidget);
      expect(find.text(batting), findsNothing);

      await pumpScreen(
        tester,
        store,
        MatchVsCard(match: match, progress: progress, showScore: true),
      );
      expect(find.text(batting), findsOneWidget);
    });
  });

  group('discovery', () {
    testWidgets(
      'submitted cards show official scores and cancelled cards do not',
      (tester) async {
        final match = await matchWith(
          sport: Sport.cricket,
          title: 'Result under review',
        );
        match.status = FixtureStatus.submitted;
        match.result = OfficialResult(
          sideScores: ['91/4', '90/8'],
          sideValues: [91, 90],
          winnerIndex: 0,
          headline: 'Home won',
          detail: '',
          publishedAt: DateTime.now(),
          publishedById: organizer.id,
        );
        await pumpScreen(tester, store, const MatchesTab());
        expect(find.text('91/4'), findsOneWidget);
        expect(find.text('View result'), findsOneWidget);
        match.status = FixtureStatus.cancelled;
        await pumpScreen(tester, store, const MatchesTab());
        expect(find.text('91/4'), findsNothing);
        expect(find.text('View result'), findsNothing);
        expect(find.text('Match details'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('match cards fit a small screen and search can be cleared', (
      tester,
    ) async {
      await matchWith(
        sport: Sport.cricket,
        title: 'Friday night championship at the community sports ground',
        sideA: 'Clifton championship eleven',
        sideB: 'Karachi community all stars',
      );
      await pumpScreen(
        tester,
        store,
        const MatchesTab(),
        size: const Size(320, 700),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView).last, const Offset(0, -260));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'no matching fixture');
      await tester.pumpAndSettle();
      expect(find.text('No matches here yet'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('1 match'), findsOneWidget);
      expect(find.byType(MatchVsCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lists what the member may see and filters it', (tester) async {
      await matchWith(
        sport: Sport.padel,
        title: 'Saturday morning padel ladder',
        start: true,
      );
      final cricket = await matchWith(
        sport: Sport.cricket,
        title: 'Friday night tape-ball derby',
      );
      await matchWith(
        sport: Sport.badminton,
        title: 'Club championship court three',
      );

      await pumpScreen(tester, store, const MatchesTab());

      expect(find.text('Saturday morning padel ladder'), findsOneWidget);
      expect(find.text('Friday night tape-ball derby'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Club championship court three'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(MatchesTab),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      expect(find.text('Club championship court three'), findsOneWidget);
      await tester.drag(find.byType(ListView).last, const Offset(0, 1200));
      await tester.pumpAndSettle();

      // A sport chip narrows the list without a second request.
      await tester.tap(
        find.descendant(
          of: find.byType(MatchesTab),
          matching: find.text('Cricket'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Friday night tape-ball derby'), findsOneWidget);
      expect(find.text('Saturday morning padel ladder'), findsNothing);

      // Back to every sport, then search by title.
      await tester.tap(find.text('All sports'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'derby');
      await tester.pumpAndSettle();
      expect(find.text('Friday night tape-ball derby'), findsOneWidget);
      expect(find.text('Club championship court three'), findsNothing);

      // A search with no hit explains itself instead of showing a blank list.
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('No matches here yet'), findsOneWidget);

      // The live scope reads the status, not the text.
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Live'));
      await tester.pumpAndSettle();
      expect(find.text('Saturday morning padel ladder'), findsOneWidget);
      expect(find.text('Friday night tape-ball derby'), findsNothing);
      expect(cricket.status, FixtureStatus.upcoming);
    });

    testWidgets('walks from the loading skeleton to the empty state', (
      tester,
    ) async {
      final gated = _GatedStore(await LocalStorage.open());
      await gated.load();
      gated.matches.clear();
      await gated.signIn(gated.accounts[0].id);

      await tester.binding.setSurfaceSize(const Size(400, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final session = SessionController(gated);
      final matches = MatchController(gated);
      addTearDown(matches.dispose);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SessionController>.value(value: session),
            ChangeNotifierProvider<MatchController>.value(value: matches),
          ],
          child: MaterialApp(
            theme: buildSportikaTheme(),
            home: const Scaffold(body: SafeArea(child: MatchesTab())),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(LoadingSkeleton), findsOneWidget);

      gated.gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(LoadingSkeleton), findsNothing);
      expect(find.text('No matches here yet'), findsOneWidget);
    });
  });

  group('roster', () {
    testWidgets(
      'long names and multiple badges fit with separate invitation counts',
      (tester) async {
        final match = await matchWith(
          sport: Sport.futsal,
          title: 'Friday futsal',
        );
        match.scorerId = organizer.id;
        match.rules['lineups'] = [
          [organizer.id],
          <String>[],
        ];
        match.participants.addAll([
          MatchParticipant(
            profileId: 'partner',
            displayName: 'A very long substitute player name',
            side: 0,
            status: MatchParticipantStatus.accepted,
          ),
          MatchParticipant(
            profileId: 'pending',
            displayName: 'A very long invited player name',
            side: 1,
            status: MatchParticipantStatus.invited,
          ),
          MatchParticipant(
            profileId: 'declined',
            displayName: 'Previous invitation',
            side: 1,
            status: MatchParticipantStatus.declined,
          ),
        ]);
        var selectedSide = -1;
        await pumpScreen(
          tester,
          store,
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: MatchRosterCard(
                match: match,
                accountId: organizer.id,
                onInviteSide: (side) => selectedSide = side,
              ),
            ),
          ),
          size: const Size(320, 700),
          textScale: 1.3,
        );
        expect(find.text('2/4'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(find.text('STARTER'), findsOneWidget);
        expect(find.text('SUBSTITUTE'), findsOneWidget);
        expect(find.text('SCORER'), findsOneWidget);
        expect(find.text('ORGANIZER'), findsOneWidget);
        expect(find.text('Pending'), findsOneWidget);
        expect(find.text('PENDING'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Invite to side B'));
        await tester.tap(find.text('Invite to side B'));
        await tester.pumpAndSettle();
        expect(selectedSide, 1);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Previous invitations (1)'));
        await tester.tap(find.text('Previous invitations (1)'));
        await tester.pumpAndSettle();
        expect(find.text('DECLINED'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'spectators cannot invite and full rosters show no invite action',
      (tester) async {
        final match = await matchWith(
          sport: Sport.padel,
          title: 'Saturday padel',
        );
        Widget roster(String accountId) => SingleChildScrollView(
          child: MatchRosterCard(
            match: match,
            accountId: accountId,
            onInviteSide: (_) {},
          ),
        );
        await pumpScreen(tester, store, roster(player.id));
        expect(find.text('Invite to side A'), findsNothing);
        expect(find.text('Invite to side B'), findsNothing);
        match.capacity = match.acceptedCount;
        await pumpScreen(tester, store, roster(organizer.id));
        expect(find.text('Invite to side A'), findsNothing);
        expect(find.text('Invite to side B'), findsNothing);
        expect(find.text('0'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('detail actions', () {
    testWidgets('submitted roster and scorer sheets are read-only', (
      tester,
    ) async {
      final match = await matchWith(
        sport: Sport.padel,
        title: 'Saturday padel',
      );
      match.status = FixtureStatus.submitted;
      await pumpScreen(
        tester,
        store,
        Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () =>
                    showMatchParticipantsSheet(context, match: match),
                child: const Text('Roster sheet'),
              ),
              TextButton(
                onPressed: () => showMatchScorerSheet(context, match: match),
                child: const Text('Scorer sheet'),
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Roster sheet'));
      await tester.pumpAndSettle();
      expect(find.text('INVITE TO'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.text('Players').last)).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scorer sheet'));
      await tester.pumpAndSettle();
      expect(find.text('Assign official scorer'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('edit sheet validates a short title without closing the form', (
      tester,
    ) async {
      final match = await matchWith(
        sport: Sport.padel,
        title: 'Saturday padel',
      );
      await pumpScreen(
        tester,
        store,
        MatchDetailScreen(matchId: match.id),
        ownScaffold: true,
        size: const Size(320, 700),
      );
      await tester.tap(find.byTooltip('Edit match'));
      await tester.pumpAndSettle();
      final title = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Title',
      );
      await tester.enterText(title, 'X');
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(
        find.text('Use a match title between 2 and 80 characters.'),
        findsOneWidget,
      );
      expect(match.title, 'Saturday padel');
      expect(tester.takeException(), isNull);
    });

    for (final sport in Sport.values) {
      testWidgets(
        '${sport.name}: detail hero fits narrow enlarged-text layouts',
        (tester) async {
          final match = await matchWith(
            sport: sport,
            title: 'Community championship under the floodlights',
            sideA: 'Clifton championship side',
            sideB: 'Karachi community all stars',
            start: true,
          );
          await pumpScreen(
            tester,
            store,
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: MatchDetailHero(
                  match: match,
                  progress: store.progressOf(match),
                ),
              ),
            ),
            size: const Size(320, 700),
            textScale: 1.3,
          );
          expect(find.byType(MatchScoreboard), findsOneWidget);
          expect(find.byType(MatchVsCard), findsNothing);
          expect(find.text('LIVE SCORE'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'upcoming hero introduces teams without an unrecorded scoreboard',
      (tester) async {
        final match = await matchWith(
          sport: Sport.padel,
          title: 'Saturday padel',
        );
        await pumpScreen(
          tester,
          store,
          SingleChildScrollView(
            child: MatchDetailHero(
              match: match,
              progress: store.progressOf(match),
            ),
          ),
        );
        expect(find.byType(MatchVsCard), findsOneWidget);
        expect(find.byType(MatchScoreboard), findsNothing);
        expect(find.text('Saturday padel'), findsOneWidget);
      },
    );

    testWidgets('busy action panel blocks repeated scoring taps', (
      tester,
    ) async {
      final match = await matchWith(
        sport: Sport.padel,
        title: 'Saturday padel',
        start: true,
      );
      var taps = 0;
      final busy = ValueNotifier(false);
      addTearDown(busy.dispose);
      await pumpScreen(
        tester,
        store,
        SingleChildScrollView(
          child: ValueListenableBuilder<bool>(
            valueListenable: busy,
            builder: (context, value, child) => MatchLifecycleBar(
              match: match,
              accountId: organizer.id,
              busy: value,
              onScore: () => taps++,
            ),
          ),
        ),
      );
      busy.value = true;
      await tester.pump();
      final primary = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(primary.busy, isTrue);
      expect(primary.onPressed, isNull);
      expect(taps, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('follow the role and the status', (tester) async {
      final match = await matchWith(
        sport: Sport.padel,
        title: 'Saturday morning padel ladder',
      );

      await pumpScreen(
        tester,
        store,
        MatchDetailScreen(matchId: match.id),
        ownScaffold: true,
      );

      // The organizer runs the match before it starts.
      expect(find.text('Start match'), findsOneWidget);
      expect(find.text('Invite players'), findsOneWidget);
      expect(find.text('Assign official scorer'), findsOneWidget);
      expect(find.text('Cancel match'), findsOneWidget);

      // A member who is not on the match sees the score but no controls.
      await store.signIn(player.id);
      await tester.pumpAndSettle();
      expect(find.text('Start match'), findsNothing);
      expect(find.text('Invite players'), findsNothing);
      expect(
        find.text(
          'Only the organizer or the assigned official scorer can start this '
          'match.',
        ),
        findsOneWidget,
      );

      // The assigned scorer inherits the start button and nothing else.
      await store.signIn(organizer.id);
      await store.assignMatchScorer(match.id, player.id);
      await store.signIn(player.id);
      await tester.pumpAndSettle();
      expect(find.text('Start match'), findsOneWidget);
      expect(find.text('Invite players'), findsNothing);
      expect(find.text('Cancel match'), findsNothing);
    });

    testWidgets('a match opened while live keeps the scoring door open', (
      tester,
    ) async {
      final match = await matchWith(
        sport: Sport.badminton,
        title: 'Club championship court three',
        start: true,
      );
      await pumpScreen(
        tester,
        store,
        MatchDetailScreen(matchId: match.id),
        ownScaffold: true,
      );

      expect(find.text('Open scoring workspace'), findsOneWidget);
      expect(find.text('End match and submit'), findsOneWidget);
      expect(find.text('Record walkover'), findsOneWidget);
      expect(find.text('Start match'), findsNothing);
    });

    testWidgets('a match the member cannot see explains itself', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        store,
        const MatchDetailScreen(matchId: 'match-that-never-was'),
        ownScaffold: true,
      );

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('Match not available'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}
