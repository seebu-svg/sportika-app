import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/navigation/navigation.dart';

import 'helpers/harness.dart';

void main() {
  testWidgets('standalone matches and tournament fixtures stay in their tabs', (
    tester,
  ) async {
    final state = await freshState();
    await state.signIn('acc-seebu');

    final tournament = state.tournaments.firstWhere(
      (event) => event.status != TournamentStatus.draft && !event.isDemo,
    );

    state.fixtures.add(
      Fixture(
        id: 'separation-fixture',
        tournamentId: tournament.id,
        stage: 'Group A',
        round: 1,
        home: FixtureSide(entryId: 'separation-home', label: 'Fixture Home XI'),
        away: FixtureSide(entryId: 'separation-away', label: 'Fixture Away XI'),
        scheduledAt: DateTime.now(),
        venue: 'Separation Court',
        status: FixtureStatus.live,
        scorerAccountIds: const [],
        events: const [],
        rules: const {},
        corrections: [],
      ),
    );

    await state.createMatch(
      MatchDraft(
        sport: Sport.padel,
        formatLabel: 'Singles',
        rules: const {},
        title: 'Standalone Separation Match',
        venue: 'Court One',
        scheduledAt: DateTime.now().add(const Duration(hours: 2)),
        visibility: MatchVisibility.public,
        sideA: 'Standalone A',
        sideB: 'Standalone B',
        capacity: 4,
        discipline: MatchDisciplineX.forSport(Sport.padel).first,
      ),
    );
    state.notifyListeners();

    await pumpApp(tester, state: state);

    Future<void> select(int index) async {
      await tester.tap(find.byType(NavigationDestination).at(index));
      await tester.pumpAndSettle();
    }

    await select(HomeTabIndex.matches);
    await tester.scrollUntilVisible(
      find.text('Standalone Separation Match'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Standalone Separation Match'), findsOneWidget);
    expect(find.text('Fixture Home XI'), findsNothing);
    expect(find.text('Fixture Away XI'), findsNothing);

    await select(HomeTabIndex.tournaments);
    await tester.scrollUntilVisible(
      find.text('Live fixtures'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Live fixtures'), findsOneWidget);
    expect(find.text('Fixture Home XI'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
