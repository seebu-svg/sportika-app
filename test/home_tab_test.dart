import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportika/app/providers.dart';
import 'package:sportika/features/home/screens/home_tab.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/models/enums.dart';

void main() {
  for (final width in [320.0, 390.0, 800.0]) {
    testWidgets(
      'Home sections fit and scroll at $width pixels with enlarged text',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        SharedPreferences.setMockInitialValues({});
        final state = LocalSportikaRepository(await LocalStorage.open());
        await state.load();
        await state.signIn('acc-seebu');
        await tester.pumpWidget(
          buildAppProviders(
            repository: state,
            child: MaterialApp(
              theme: buildSportikaTheme(),
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 844),
                  textScaler: const TextScaler.linear(1.3),
                ),
                child: const Scaffold(body: HomeTab()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('home-sports-filter')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Matches for you'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('home-sports-filter')),
          findsOneWidget,
        );
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Padel'),
          100,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('home-sports-filter')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Padel').first);
        await tester.pumpAndSettle();
        // Return to the top so the full-bleed hero is back in the tree;
        // its photograph must follow the selected sport.
        position.jumpTo(0);
        await tester.pumpAndSettle();
        expect(
          tester.widget<SportPhoto>(find.byType(SportPhoto).first).sport,
          Sport.padel,
        );
        for (
          double offset = 0;
          offset <= position.maxScrollExtent + 400;
          offset += 400
        ) {
          position.jumpTo(offset.clamp(0, position.maxScrollExtent));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'Home offset $offset');
        }
        expect(find.text('Your activity'), findsOneWidget);
      },
    );
  }
}
