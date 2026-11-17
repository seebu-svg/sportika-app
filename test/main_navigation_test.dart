import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/shared/widgets/filter_chip_row.dart';

import 'helpers/harness.dart';

void main() {
  testWidgets('five tabs expose relocated discovery and scoring features', (
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
      'Tournament',
      'Match',
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

    await select(1);
    expect(find.text('My Tournaments'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Managing'),
      100,
      scrollable: find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is FilterChipRow<int> && w.label == 'Tournament section',
        ),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Managing'), findsOneWidget);
    await select(2);
    for (final label in [
      'Live Scores',
      'Upcoming',
      'Results',
      'Personal',
      'Games',
    ]) {
      expect(find.text(label), findsOneWidget);
      await tapVisible(tester, find.text(label));
      expect(tester.takeException(), isNull);
    }
    await select(3);
    await tapVisible(tester, find.text('Find teams'));
    expect(tester.takeException(), isNull);
    await tapVisible(tester, find.text('Players').first);
    expect(find.byType(TextField), findsWidgets);

    // Game notifications must select Match and its pickup discovery section.
    await openNotificationRoute(
      tester.element(find.byType(NavigationBar)),
      'games',
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    expect(matchSectionRequest.value, 4);
    expect(tester.takeException(), isNull);
    await select(4);
    await select(0);
  });
}
