import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportika/app/providers.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/features/discover/screens/tournaments_tab.dart';
import 'package:sportika/features/discover/screens/tournament_detail_screen.dart';
import 'package:sportika/features/discover/screens/create_tournament_screen.dart';
import 'package:sportika/features/discover/widgets/tournament_card.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/filter_chip_row.dart';
import 'package:sportika/shared/widgets/state_views.dart';

import 'helpers/harness.dart';

Future<void> pumpTournament(
  WidgetTester tester,
  LocalSportikaRepository state,
  Widget child, {
  double width = 390,
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    buildAppProviders(
      repository: state,
      child: MaterialApp(
        theme: buildSportikaTheme(),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  final scroll = find
      .byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      )
      .last;
  await tester.scrollUntilVisible(target, 240, scrollable: scroll);
  await tester.pumpAndSettle();
}

class _GatedTournamentStore extends LocalSportikaRepository {
  _GatedTournamentStore(super.storage);
  Completer<void>? gate;
  @override
  Future<void> reload() => gate?.future ?? Future.value();
}

void main() {
  testWidgets('discovery searches, filters, sorts and keeps ownership scopes', (
    tester,
  ) async {
    final state = await freshState();
    await state.signIn('acc-seebu');
    final template = state.tournaments.first.toJson();
    Tournament event(
      String id,
      String name,
      Sport sport,
      TournamentStatus status,
      String owner,
    ) => Tournament.fromJson({
      ...template,
      'id': id,
      'name': name,
      'sport': sport.name,
      'status': status.name,
      'organizerId': owner,
    });
    state.tournaments = [
      event('a', 'Cricket Open', Sport.cricket, TournamentStatus.open, 'other'),
      event(
        'b',
        'Padel Draft',
        Sport.padel,
        TournamentStatus.draft,
        'acc-seebu',
      ),
      event(
        'c',
        'Padel Finals',
        Sport.padel,
        TournamentStatus.inProgress,
        'other',
      ),
    ];
    state.entries.clear();
    await pumpTournament(tester, state, const TournamentsTab());
    expect(find.text('Discover'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Cricket');
    await tester.pumpAndSettle();
    expect(
      tester.widget<TournamentCard>(find.byType(TournamentCard)).tournament.id,
      'a',
    );
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    final scopes = tester.widget<FilterChipRow<int>>(
      find.byWidgetPredicate(
        (w) => w is FilterChipRow<int> && w.label == 'Tournament section',
      ),
    );
    scopes.onChanged(2);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TournamentCard>(find.byType(TournamentCard)).tournament.id,
      'b',
    );
    scopes.onChanged(1);
    await tester.pumpAndSettle();
    expect(find.text('No tournament entries yet'), findsOneWidget);
    scopes.onChanged(0);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sort tournaments'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Starting soon'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byTooltip('Filter registration and competition status'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(TournamentStatus.completed.label));
    await tester.pumpAndSettle();
    expect(find.text('No tournaments match your search'), findsOneWidget);
    await tester.tap(find.text('Reset filters').first);
    await tester.pumpAndSettle();
    expect(find.text('No tournaments match your search'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('create action works for a signed-in player', (tester) async {
    final state = await freshState();
    await state.signIn('acc-seebu');
    await pumpApp(tester, state: state);
    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create tournament').first);
    await tester.pumpAndSettle();
    expect(find.byType(CreateTournamentScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 800.0]) {
    testWidgets(
      'tournament discovery and details fit $width with enlarged text',
      (tester) async {
        final state = await freshState();
        await state.signIn('acc-seebu');
        final tournament = state.tournaments.first;
        await pumpTournament(
          tester,
          state,
          const TournamentsTab(),
          width: width,
          scale: 1.3,
        );
        await reveal(tester, find.byType(TournamentCard));
        expect(tester.takeException(), isNull);
        await pumpTournament(
          tester,
          state,
          TournamentDetailScreen(id: tournament.id),
          width: width,
          scale: 1.3,
        );
        final selector = find.byWidgetPredicate(
          (w) => w is FilterChipRow<int> && w.label == 'Tournament details',
        );
        await reveal(tester, selector);
        final changeSection = tester
            .widget<FilterChipRow<int>>(selector)
            .onChanged;
        for (var i = 0; i < 4; i++) {
          changeSection(i);
          await tester.pumpAndSettle();
          final scrollable = tester.state<ScrollableState>(
            find
                .byWidgetPredicate(
                  (w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down,
                )
                .last,
          );
          scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Detail section $i at $width',
          );
        }
        changeSection(0);
        await tester.pumpAndSettle();
        expect(find.text(tournament.matchRules), findsOneWidget);
      },
    );
  }

  testWidgets(
    'individual registration and withdrawal preserve the entry workflow',
    (tester) async {
      final state = await freshState();
      await state.signIn('acc-seebu');
      final tournament = state.tournaments.first;
      tournament.entryType = EntryType.individual;
      tournament.status = TournamentStatus.open;
      state.entries.clear();
      state.fixtures.clear();
      await pumpTournament(
        tester,
        state,
        TournamentDetailScreen(id: tournament.id),
      );
      await reveal(tester, find.text('Register for this tournament'));
      await tester.tap(find.text('Register for this tournament'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Register'));
      await tester.pumpAndSettle();
      expect(state.myEntryFor(tournament.id)?.status, EntryStatus.pending);
      await reveal(tester, find.text('Withdraw entry'));
      await tester.tap(find.text('Withdraw entry'));
      await tester.pumpAndSettle();
      expect(
        state.entriesFor(tournament.id).single.status,
        EntryStatus.withdrawn,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('management tools depend on tournament ownership', (
    tester,
  ) async {
    final state = await freshState();
    await state.signIn('acc-seebu');
    final template = state.tournaments.first.toJson();
    final mine = Tournament.fromJson({
      ...template,
      'id': 'owned-event',
      'organizerId': 'acc-seebu',
    });
    state.tournaments = [mine];
    state.entries.clear();
    state.fixtures.clear();
    await pumpTournament(tester, state, TournamentDetailScreen(id: mine.id));
    await reveal(tester, find.text('ORGANIZER WORKSPACE'));
    expect(find.text('ORGANIZER WORKSPACE'), findsOneWidget);
    await reveal(tester, find.text('Publish draw & fixtures'));
    await tester.tap(find.text('Publish draw & fixtures'));
    await tester.pumpAndSettle();
    expect(
      find.text('Confirm at least two entries before publishing a draw'),
      findsOneWidget,
    );
    await state.signIn(
      state.accounts.firstWhere((a) => a.id != 'acc-seebu').id,
    );
    await tester.pumpAndSettle();
    expect(find.text('ORGANIZER WORKSPACE'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh skeleton and retry retain competition content', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = _GatedTournamentStore(await LocalStorage.open());
    await state.load();
    await state.signIn('acc-seebu');
    await pumpTournament(tester, state, const TournamentsTab());
    state.gate = Completer<void>();
    final request = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();
    await reveal(tester, find.byType(LoadingSkeleton));
    expect(find.byType(LoadingSkeleton), findsOneWidget);
    state.gate!.completeError(StateError('offline'));
    await request;
    await tester.pumpAndSettle();
    await reveal(tester, find.byType(ErrorState));
    expect(find.text('Tournaments could not refresh'), findsOneWidget);
    state.gate = null;
    tester.widget<ErrorState>(find.byType(ErrorState)).onRetry!();
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
