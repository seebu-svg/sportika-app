import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sportika/app.dart';
import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/features/auth/services/authentication_service.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';

import 'auth_service_fixture.dart';

import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';

/// Shared widget-test harness.
///
/// The splash has a 1750 ms branding timer. Service requests use the explicitly
/// injected test fixture; no production demo login is enabled. Every
/// test that needs the shell funnels through [pumpAuthTimers] instead of
/// hard-coding pump durations of its own.
const Duration authTimer = Duration(milliseconds: 1900);

/// A loaded, seeded state. Pass `onboardingSeen: false` when the journey under
/// test has to start at onboarding instead of the sign-in gate.
Future<LocalSportikaRepository> freshState({bool onboardingSeen = true}) async {
  SharedPreferences.setMockInitialValues(
    onboardingSeen ? {'sportika.onboarding_seen.v1': true} : {},
  );
  final state = LocalSportikaRepository(await LocalStorage.open());
  await state.load();
  return state;
}

/// Pumps the real app at a phone-sized surface and resolves the splash.
///
/// [textScale] drives the platform text scale factor so the layout matrix can
/// exercise the 1.3 ceiling the app clamps to. [emailVerificationEnabled]
/// defaults to the flag the app is built with; tests for the code screen pass
/// `true` explicitly, because the shipped build has it off. [profileModule]
/// replaces the device adapter, so a test can drive the Me module with a fake
/// server that fails, stalls or returns a chosen record. [monetizationRepository]
/// does the same for billing, which is how the pricing, upgrade and history
/// screens are tested against a paid, pending or empty ledger without a database.
Future<LocalSportikaRepository> pumpApp(
  WidgetTester tester, {
  LocalSportikaRepository? state,
  Size size = const Size(400, 844),
  double textScale = 1.0,
  AuthenticationService? authenticationService,
  bool? emailVerificationEnabled,
  ProfileModuleRepository? profileModule,
  MonetizationRepository? monetizationRepository,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final appState = state ?? await freshState();
  final service =
      authenticationService ??
      AuthServiceFixture(
        appState,
        restoredAccountId: appState.currentAccount?.id,
      );
  if (authenticationService == null) addTearDown(service.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<LocalSportikaRepository>.value(
      value: appState,
      child: SportikaApp(
        authenticationService: service,
        emailVerificationEnabled: emailVerificationEnabled,
        profileModuleRepository: profileModule,
        monetizationRepository: monetizationRepository,
      ),
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

/// Auth flow shared by root and pushed pages.
AuthFlowController authFlow(WidgetTester tester) =>
    tester.element(find.byType(RootGate)).read<AuthFlowController>();

/// Select a date through the same dialog callback the calendar uses.
Future<void> chooseBirthDate(WidgetTester tester, DateTime date) async {
  await tapVisible(tester, find.byTooltip('Choose date of birth'));
  final calendar = tester.widget<CalendarDatePicker>(
    find.byType(CalendarDatePicker),
  );
  expect(calendar.initialCalendarMode, DatePickerMode.year);
  calendar.onDateChanged(date);
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}
