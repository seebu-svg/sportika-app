import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportika/app.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/state/app_state.dart';

void main() {
  testWidgets('the sign-in gate lists the demo accounts', (tester) async {
    // Onboarding has been seen on this device, so the splash resolves
    // straight to the sign-in gate after its brand timer.
    SharedPreferences.setMockInitialValues({
      'sportika.onboarding_seen.v1': true,
    });
    final storage = await LocalStorage.open();
    final state = AppState(storage);
    await state.load();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const SportikaApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();

    expect(find.text('DEMO ACCESS'), findsOneWidget);
    expect(find.text('Seebu Ali'), findsOneWidget);
    expect(find.text('Yasir Malik'), findsOneWidget);
  });

  testWidgets('signing in opens the five-tab shell', (tester) async {
    SharedPreferences.setMockInitialValues({
      'sportika.onboarding_seen.v1': true,
    });
    final storage = await LocalStorage.open();
    final state = AppState(storage);
    await state.load();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const SportikaApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Seebu Ali'));
    await tester.pumpAndSettle();
    // The demo sign-in routes through the session-check timer.
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Discover'), findsWidgets);
    expect(find.text('Live'), findsWidgets);
    expect(find.text('Team'), findsWidgets);
    expect(find.text('Me'), findsWidgets);
  });

  testWidgets('a personal scorecard can be opened from the shell', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await LocalStorage.open();
    final state = AppState(storage);
    await state.load();
    await state.signIn('acc-seebu');

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const SportikaApp(),
      ),
    );
    await tester.pumpAndSettle();
    // Resolve the splash and session-check timers to reach the shell.
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();

    // The seeded in-progress cricket card is offered on Home.
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -320),
    );
    await tester.pumpAndSettle();
    expect(find.text('Continue scoring'), findsOneWidget);
    await tester.tap(find.text('Neighbours').first);
    await tester.pumpAndSettle();

    // Tapping it resumes the private scorecard instead of starting a new one.
    expect(find.text('Private scorecard · T5 · 5 overs'), findsOneWidget);
    expect(find.text('In progress · auto-saved'), findsOneWidget);
  });
}
