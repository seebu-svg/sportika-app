import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/shared/navigation/navigation.dart';

import 'helpers/harness.dart';

void main() {
  testWidgets('five tabs expose tournaments, standalone matches and teams', (
    tester,
  ) async {
    final state = await freshState();
    await state.signIn('acc-seebu');
    await pumpApp(tester, state: state);

    final destinations = tester.widgetList<NavigationDestination>(
      find.byType(NavigationDestination),
    );
    expect(destinations.map((tab) => tab.label), [
      'Home',
      'Tournaments',
      'Matches',
      'Team',
      'Me',
    ]);

    Future<void> select(int index) async {
      await tester.tap(find.byType(NavigationDestination).at(index));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        index,
      );
      expect(tester.takeException(), isNull);
    }

    // Tournaments: discovery scopes, creation and the competition feed.
    await select(HomeTabIndex.tournaments);
    expect(find.text('The arena awaits.'), findsOneWidget);
    expect(find.byTooltip('Create tournament'), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('My tournaments'), findsOneWidget);
    expect(find.text('Managing'), findsOneWidget);

    // Matches: standalone discovery, creation and status scopes.
    await select(HomeTabIndex.matches);
    expect(find.text('Match Center'), findsOneWidget);
    expect(find.text('Create Match'), findsOneWidget);
    for (final label in ['All', 'Live', 'Upcoming', 'Results']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.byTooltip('More match options'));
    await tester.pumpAndSettle();
    expect(find.text('Open to join only'), findsOneWidget);
    expect(find.text('Pickup games'), findsOneWidget);
    await tester.tap(find.text('Open to join only'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Team keeps its own discovery sections.
    await select(HomeTabIndex.teams);
    await tapVisible(tester, find.text('Find Teams'));
    expect(tester.takeException(), isNull);
    await tapVisible(tester, find.text('Players').first);
    expect(find.byType(TextField), findsWidgets);

    // A game notification must still select Matches and open pickup games.
    await openNotificationRoute(
      tester.element(find.byType(NavigationBar)),
      'games',
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      HomeTabIndex.matches,
    );
    expect(matchSectionRequest.value, 4);
    expect(tester.takeException(), isNull);

    await select(HomeTabIndex.me);
    await select(HomeTabIndex.home);
  });
}
