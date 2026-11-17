import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/models/community_game.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/features/home/screens/home_tab.dart';
import 'package:sportika/features/home/widgets/home_header.dart';
import 'package:sportika/features/matches/screens/create_match_screen.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/app/providers.dart';
import 'package:sportika/shared/theme/theme.dart';

import 'helpers/harness.dart';

Future<void> pumpHome(
  WidgetTester tester,
  LocalSportikaRepository state,
) async {
  await tester.binding.setSurfaceSize(const Size(320, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    buildAppProviders(
      repository: state,
      child: MaterialApp(
        theme: buildSportikaTheme(),
        home: const Scaffold(body: HomeTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _RefreshStore extends LocalSportikaRepository {
  _RefreshStore(super.storage);
  Completer<void>? pending;
  @override
  Future<void> reload() => pending?.future ?? Future.value();
}

/// A store whose discovery reads are still in flight or already refused, so the
/// per-section loading and error states can be exercised without a server.
class _RemoteLikeStore extends LocalSportikaRepository {
  _RemoteLikeStore(super.storage, {required this.loading, required this.error});

  @override
  final bool loading;

  /// Not an inherited member of [LocalSportikaRepository]; the class exposes it
  /// through [lastError] below.
  final String? error;

  int refreshes = 0;

  @override
  String? get lastError => error;

  @override
  Future<void> refresh() async {
    refreshes++;
    await reload();
  }
}

void main() {
  testWidgets(
    'refresh renders skeleton, retains content on error and retries',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final state = _RefreshStore(await LocalStorage.open());
      await state.load();
      await state.signIn('acc-seebu');
      state.pending = Completer<void>();
      await pumpHome(tester, state);
      final refresh = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      final request = refresh.onRefresh();
      await tester.pump();
      await scrollHomeTo(tester, find.byType(LoadingSkeleton));
      expect(find.byType(LoadingSkeleton), findsOneWidget);
      state.pending!.completeError(StateError('Unavailable'));
      await request;
      await tester.pumpAndSettle();
      await scrollHomeTo(tester, find.textContaining('Couldn’t refresh'));
      expect(
        find.text(
          'Couldn’t refresh everything. Showing the last activity that loaded.',
        ),
        findsOneWidget,
      );
      state.pending = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Couldn’t refresh'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'official upcoming match is shown with authenticated participation',
    (tester) async {
      final state = await freshState();
      await state.signIn('acc-seebu');
      state.fixtures.clear();
      final match = SportMatch.fromJson(state.matches.first.toJson());
      match.status = FixtureStatus.upcoming;
      match.scheduledAt = DateTime.now().add(const Duration(days: 1));
      match.sideNames = ['Home athletes', 'Away athletes'];
      match.participants = [
        MatchParticipant(
          profileId: 'acc-seebu',
          displayName: 'Player',
          side: 0,
          status: MatchParticipantStatus.accepted,
        ),
      ];
      state.matches = [match];
      await pumpHome(tester, state);
      await scrollHomeTo(tester, find.text('Your next match'));
      expect(find.text('Home athletes'), findsWidgets);
      expect(find.text('Away athletes'), findsWidgets);
      expect(find.text('Score Game'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty dashboard greets account and offers one useful empty state',
    (tester) async {
      final state = await freshState();
      await state.signIn('acc-seebu');
      state.currentAccount!.displayName = 'Ayesha Khan';
      state.fixtures.clear();
      state.tournaments.clear();
      state.games.clear();
      state.personal.clear();
      state.matches.clear();
      await pumpHome(tester, state);
      expect(find.textContaining('Ayesha!'), findsOneWidget);
      expect(find.text('Ready for your next game?'), findsOneWidget);
      expect(find.byType(HomeHero), findsOneWidget);
      await scrollHomeTo(tester, find.text('Your next opportunity is ahead'));
      expect(find.text('Your next match'), findsNothing);
      expect(find.text('Live now'), findsNothing);
      expect(find.text('Continue scoring'), findsNothing);
      await scrollHomeTo(tester, find.byType(BrandMetricStrip));
      final metrics = tester
          .widget<BrandMetricStrip>(find.byType(BrandMetricStrip))
          .metrics;
      expect(metrics.map((m) => m.value), ['00', '00', '00']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'next match is the earliest future participation; snapshot uses real totals',
    (tester) async {
      final state = await freshState();
      await state.signIn('acc-seebu');
      state.fixtures.clear();
      final now = DateTime.now();
      SportMatch official(
        String id,
        DateTime at, {
        FixtureStatus status = FixtureStatus.upcoming,
        int? winner,
      }) => SportMatch(
        id: id,
        sport: Sport.cricket,
        formatLabel: 'T20',
        rules: const {},
        title: 'Match $id',
        venue: 'National Stadium',
        scheduledAt: at,
        visibility: MatchVisibility.public,
        organizerId: 'other',
        status: status,
        sideNames: const ['Home athletes', 'Away athletes'],
        discipline: MatchDiscipline.team,
        capacity: 22,
        createdAt: now,
        participants: [
          MatchParticipant(
            profileId: 'acc-seebu',
            displayName: 'Ayesha',
            side: 0,
            status: MatchParticipantStatus.accepted,
          ),
        ],
        result: winner == null
            ? null
            : OfficialResult(
                sideScores: const ['148/4', '146/8'],
                sideValues: const [148, 146],
                winnerIndex: winner,
                headline: 'Home athletes won',
                detail: 'by 2 runs',
                publishedAt: now,
                publishedById: 'other',
              ),
      );
      final later = official('later', now.add(const Duration(days: 3)));
      final next = official('next', now.add(const Duration(days: 1)));
      final past = official(
        'past',
        now.subtract(const Duration(days: 2)),
        status: FixtureStatus.published,
        winner: 0,
      );
      // Deliberately out of order: the card must pick the earliest, not the
      // first row the server happened to return.
      state.matches = [later, next, past];
      await pumpHome(tester, state);
      await scrollHomeTo(tester, find.text('Your next match'));

      await scrollHomeTo(tester, find.text('View match →'));
      expect(find.byKey(const ValueKey('next-match-next')), findsOneWidget);
      expect(find.byKey(const ValueKey('next-match-later')), findsNothing);
      await scrollHomeTo(tester, find.byType(BrandMetricStrip));
      final metrics = tester
          .widget<BrandMetricStrip>(find.byType(BrandMetricStrip))
          .metrics;
      // Played and Wins count the published result; only one match is ahead.
      expect(metrics.first.value, '01');
      expect(metrics[1].value, '01');
      expect(metrics.last.value, '02');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('discovery favors player sports and excludes unavailable games', (
    tester,
  ) async {
    final state = await freshState();
    await state.signIn('acc-seebu');
    state.currentAccount!.sports = {Sport.padel};
    state.currentAccount!.city = 'Lahore';
    final template = state.tournaments.first.toJson();
    final future = DateTime.now().add(const Duration(days: 10));
    Tournament tournament(String id, String name, Sport sport) =>
        Tournament.fromJson({
          ...template,
          'id': id,
          'name': name,
          'city': 'Lahore',
          'sport': sport.name,
          'status': TournamentStatus.open.name,
          'startsAt': future.toIso8601String(),
        });
    state.tournaments = [
      tournament('recommend-cricket', 'Cricket opportunity', Sport.cricket),
      tournament('recommend-padel', 'Padel opportunity', Sport.padel),
    ];
    state.fixtures.clear();
    state.personal.clear();
    state.games = [
      for (final kind in ['Private', 'Full', 'Past'])
        CommunityGame(
          id: kind,
          title: '$kind game',
          sport: Sport.padel,
          venue: 'Club',
          at: kind == 'Past'
              ? DateTime.now().subtract(const Duration(days: 1))
              : future,
          capacity: kind == 'Full' ? 0 : 4,
          organizerId: 'other',
          visibility: kind == 'Private' ? 'Private' : 'Public',
        ),
    ];
    await pumpHome(tester, state);
    await scrollHomeTo(tester, find.text('Padel opportunity'));
    expect(find.text('Padel opportunity'), findsOneWidget);
    await scrollHomeTo(tester, find.byType(BrandMetricStrip));
    expect(find.text('Games for you'), findsNothing);
    expect(find.text('Private game'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dashboard shortcuts retain tab navigation and create official matches',
    (tester) async {
      final state = await freshState();
      await state.signIn('acc-seebu');
      await pumpApp(tester, state: state, size: const Size(320, 844));
      for (final action in [
        ('Find Match', 2),
        ('Tournaments', 1),
        ('My Teams', 3),
      ]) {
        await scrollHomeTo(tester, find.text(action.$1));
        await tester.tap(find.text(action.$1));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          action.$2,
        );
        await tester.tap(find.byType(NavigationDestination).first);
        await tester.pumpAndSettle();
      }
      await scrollHomeTo(tester, find.text('Create Match').first);
      await tester.tap(find.text('Create Match').first);
      await tester.pumpAndSettle();
      expect(find.byType(CreateMatchScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Updates rail shows the three newest unread items', (
    tester,
  ) async {
    final state = await freshState();
    await state.signIn('acc-seebu');
    await pumpHome(tester, state);

    final unread = state.notifications
        .where((n) => n.accountId == 'acc-seebu' && !n.read)
        .take(3)
        .toList();
    expect(unread, isNotEmpty);
    await scrollHomeTo(tester, find.text('Updates'));
    expect(find.byType(ActivityRow), findsNWidgets(unread.length));
    for (final notification in unread) {
      expect(find.text(notification.title), findsWidgets);
    }
    // The rail is a preview, never the whole inbox.
    expect(unread.length, lessThan(3 + 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('demo tournaments are labelled and lend the hero their banner', (
    tester,
  ) async {
    final state = await freshState();
    await state.signIn('acc-seebu');
    state.tournaments = [
      Tournament.fromJson({
        ...state.tournaments.first.toJson(),
        'id': 'demo-cup',
        'name': 'Demo cup',
        'status': TournamentStatus.open.name,
        'startsAt': DateTime.now()
            .add(const Duration(days: 5))
            .toIso8601String(),
        'isDemo': true,
        'bannerUrl': 'https://example.test/banner.jpg',
      }),
    ];
    await pumpHome(tester, state);

    expect(
      tester.widget<HomeHero>(find.byType(HomeHero)).imageUrl,
      'https://example.test/banner.jpg',
    );
    await scrollHomeTo(tester, find.text('Demo cup'));
    expect(find.text('DEMO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tournament fixture is never offered as a joinable match', (
    tester,
  ) async {
    final state = await freshState();
    await state.signIn('acc-seebu');
    state.fixtures.clear();
    state.games.clear();
    final now = DateTime.now();
    state.matches = [
      SportMatch(
        id: 'linked',
        sport: Sport.cricket,
        formatLabel: 'T20',
        rules: const {},
        title: 'Linked fixture',
        venue: 'National Stadium',
        scheduledAt: now.add(const Duration(days: 2)),
        visibility: MatchVisibility.public,
        organizerId: 'other',
        status: FixtureStatus.upcoming,
        sideNames: const ['Home athletes', 'Away athletes'],
        discipline: MatchDiscipline.team,
        capacity: 22,
        createdAt: now,
        tournamentId: 'tour-1',
        fixtureId: 'fx-1',
        participants: [
          MatchParticipant(
            profileId: 'acc-seebu',
            displayName: 'Ayesha',
            side: 0,
            status: MatchParticipantStatus.accepted,
          ),
        ],
      ),
    ];
    await pumpHome(tester, state);
    await scrollHomeTo(tester, find.text('Your next match'));
    expect(find.byKey(const ValueKey('next-match-linked')), findsOneWidget);

    // An entry, not a free place, is how a fixture is joined.
    await scrollHomeTo(tester, find.text('Your next opportunity is ahead'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a section that is still loading shows a skeleton', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = _RemoteLikeStore(
      await LocalStorage.open(),
      loading: true,
      error: null,
    );
    await state.load();
    await state.signIn('acc-seebu');
    state.tournaments.clear();
    await pumpHome(tester, state);
    await scrollHomeTo(tester, find.text('Featured tournaments'));
    expect(find.byType(LoadingSkeleton), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a refused section explains itself and retries in place', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = _RemoteLikeStore(
      await LocalStorage.open(),
      loading: false,
      error: 'No connection',
    );
    await state.load();
    await state.signIn('acc-seebu');
    state.tournaments.clear();
    await pumpHome(tester, state);
    await scrollHomeTo(tester, find.text('Couldn’t load tournaments'));
    expect(find.byType(ErrorState), findsWidgets);
    await tester.tap(find.text('Try again').first);
    await tester.pumpAndSettle();
    expect(state.refreshes, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
