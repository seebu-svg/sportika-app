import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sportika/app.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/state/app_state.dart';

/// Shared widget-test harness.
///
/// The splash and session-verification screens are gated behind 1750 ms timers
/// inside `AuthFlowController`. `pumpAndSettle` never advances timers, so every
/// test that needs the shell funnels through [pumpAuthTimers] instead of
/// hard-coding pump durations of its own.
const Duration authTimer = Duration(milliseconds: 1900);

/// A loaded, seeded state. Pass `onboardingSeen: false` when the journey under
/// test has to start at onboarding instead of the sign-in gate.
Future<AppState> freshState({bool onboardingSeen = true}) async {
  SharedPreferences.setMockInitialValues(
    onboardingSeen ? {'sportika.onboarding_seen.v1': true} : {},
  );
  final state = AppState(await LocalStorage.open());
  await state.load();
  return state;
}

/// Pumps the real app at a phone-sized surface and resolves the splash.
Future<AppState> pumpApp(
  WidgetTester tester, {
  AppState? state,
  Size size = const Size(400, 844),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final appState = state ?? await freshState();
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const SportikaApp(),
    ),
  );
  await pumpAuthTimers(tester);
  return appState;
}

/// Advances the splash and session-check timers in order.
Future<void> pumpAuthTimers(WidgetTester tester, {int rounds = 2}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(authTimer);
    await tester.pumpAndSettle();
  }
}

/// Scrolls [finder] into view before tapping, so tests do not depend on a
/// hard-coded drag distance or on the default 800x600 test surface.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Scrolls the Home `CustomScrollView` until [finder] is visible. Home also
/// hosts horizontal rails, so the outer scrollable is captured explicitly
/// instead of using an ambiguous `find.byType(Scrollable).first`.
Future<void> scrollHomeTo(WidgetTester tester, Finder finder) async {
  final scrollable = find
      .descendant(
        of: find.byType(CustomScrollView).first,
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(finder, 320, scrollable: scrollable);
  await tester.pumpAndSettle();
}
