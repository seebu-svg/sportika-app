import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sportika/app.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/onboarding/screens/splash_screen.dart';
import 'package:sportika/features/onboarding/screens/welcome_screen.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/models/enums.dart';

import 'helpers/harness.dart';

void main() {
  testWidgets('splash automatically opens the first launch carousel', (
    tester,
  ) async {
    final state = await freshState(onboardingSeen: false);
    await tester.pumpWidget(
      ChangeNotifierProvider<LocalSportikaRepository>.value(
        value: state,
        child: const SportikaApp(),
      ),
    );
    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('SPORTIKA'), findsOneWidget);
    await pumpAuthTimers(tester);
    expect(authFlow(tester).stage, AuthStage.onboarding);
    expect(find.text('01 / 04'), findsOneWidget);
  });

  testWidgets('swipe, pagination, next and get started cover four sports', (
    tester,
  ) async {
    await pumpApp(tester, state: await freshState(onboardingSeen: false));
    expect(find.text('DISCOVER GAMES'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-350, 0));
    await tester.pumpAndSettle();
    expect(authFlow(tester).onboardingIndex, 1);
    expect(find.text('CONNECT WITH PLAYERS'), findsOneWidget);
    await tapVisible(tester, find.text('NEXT'));
    expect(authFlow(tester).onboardingIndex, 2);
    expect(find.text('MATCHES & TOURNAMENTS'), findsOneWidget);
    await tapVisible(tester, find.byTooltip('Go to Badminton'));
    expect(authFlow(tester).onboardingIndex, 3);
    expect(find.text('SCORES & PERFORMANCE'), findsOneWidget);
    expect(find.text('04 / 04'), findsOneWidget);
    expect(find.text('NEXT'), findsNothing);
    await tapVisible(tester, find.byTooltip('Go to Cricket'));
    expect(authFlow(tester).onboardingIndex, 0);
    await tapVisible(tester, find.byTooltip('Go to Badminton'));
    await tapVisible(tester, find.text('GET STARTED'));
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.text('SIGN IN'), findsOneWidget);
    expect(find.text('CREATE ACCOUNT'), findsOneWidget);
    await tapVisible(tester, find.text('SIGN IN'));
    expect(authFlow(tester).stage, AuthStage.signIn);
    authFlow(tester).back();
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('CREATE ACCOUNT'));
    expect(authFlow(tester).stage, AuthStage.createAccount);
    expect(find.text('ORGANIZER'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('skip persists across a cold launch without a session', (
    tester,
  ) async {
    await pumpApp(tester, state: await freshState(onboardingSeen: false));
    await tapVisible(tester, find.text('SKIP'));
    expect(authFlow(tester).stage, AuthStage.welcome);
    await tester.pumpWidget(const SizedBox.shrink());
    final reopened = LocalSportikaRepository(await LocalStorage.open());
    await reopened.load();
    expect(reopened.onboardingSeen, isTrue);
    await pumpApp(tester, state: reopened);
    expect(authFlow(tester).stage, AuthStage.signIn);
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('a restored session goes straight to Home', (tester) async {
    final state = await freshState(onboardingSeen: false);
    await state.signIn('acc-seebu');
    await pumpApp(tester, state: state);
    expect(authFlow(tester).stage, AuthStage.home);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
  });

  for (final size in [
    const Size(320, 568),
    const Size(430, 932),
    const Size(844, 390),
    const Size(1024, 768),
  ]) {
    testWidgets('all four slides and welcome fit $size with large text', (
      tester,
    ) async {
      await pumpApp(
        tester,
        state: await freshState(onboardingSeen: false),
        size: size,
        textScale: 1.5,
      );
      for (final sport in Sport.values) {
        await tapVisible(tester, find.byTooltip('Go to ${sport.label}'));
        expect(tester.takeException(), isNull, reason: sport.label);
        // The copy remains scrollable separately from the pinned controls.
        final copy = switch (sport) {
          Sport.cricket => 'Find a cricket game',
          Sport.padel => 'Meet players',
          Sport.futsal => 'Create a futsal match',
          Sport.badminton => 'Track badminton rallies',
        };
        final body = find.textContaining(copy);
        await tester.ensureVisible(body);
        await tester.pumpAndSettle();
        final copyViewport = find
            .ancestor(of: body, matching: find.byType(SingleChildScrollView))
            .first;
        expect(
          tester.getRect(body).overlaps(tester.getRect(copyViewport)),
          isTrue,
        );
      }
      await tapVisible(tester, find.text('GET STARTED'));
      expect(find.byType(WelcomeScreen), findsOneWidget);
      await tester.ensureVisible(find.text('CREATE ACCOUNT'));
      expect(tester.takeException(), isNull, reason: 'welcome');
    });
  }

  testWidgets('reduced motion keeps pagination and splash usable', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(tester, state: await freshState(onboardingSeen: false));
    await tester.tap(find.byTooltip('Go to Badminton'));
    await tester.pumpAndSettle();
    expect(authFlow(tester).onboardingIndex, 3);
    expect(tester.takeException(), isNull);
  });
}
