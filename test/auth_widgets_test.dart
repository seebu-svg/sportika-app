import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/app.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/features/auth/screens/sign_in_screen.dart';
import 'package:sportika/features/auth/screens/verify_email_screen.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/onboarding.dart';

import 'helpers/auth_service_fixture.dart';
import 'helpers/harness.dart';

Finder field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is AuthField && w.label == label),
  matching: find.byType(TextField),
);
Future<void> enter(WidgetTester tester, String label, String text) async {
  final target = field(label);
  await tester.ensureVisible(target);
  await tester.enterText(target, text);
  await tester.pump();
}

void main() {
  testWidgets('sign-in errors, visibility, loading and keyboard submit', (
    tester,
  ) async {
    final state = await freshState();
    final service = AuthServiceFixture(state);
    addTearDown(service.dispose);
    await pumpApp(tester, state: state, authenticationService: service);
    await tapVisible(tester, find.text('SIGN IN').last);
    expect(find.text('Enter a valid email address.'), findsWidgets);
    await enter(tester, 'Email address', state.accounts.first.email);
    await enter(tester, 'Password', 'incorrect');
    await tapVisible(tester, find.byTooltip('Show password'));
    expect(tester.widget<TextField>(field('Password')).obscureText, isFalse);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Email or password is incorrect.'), findsOneWidget);
    service.signInBarrier = Completer<void>();
    await enter(tester, 'Password', AuthServiceFixture.validPassword);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(tester.widget<TextField>(field('Password')).enabled, isFalse);
    service.signInBarrier!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('first-run onboarding, welcome, signup, OTP and full setup', (
    tester,
  ) async {
    final state = await freshState(onboardingSeen: false);
    final service = AuthServiceFixture(state);
    addTearDown(service.dispose);
    await pumpApp(
      tester,
      state: state,
      authenticationService: service,
      emailVerificationEnabled: true,
    );
    expect(find.text('SKIP'), findsOneWidget);
    await tapVisible(tester, find.text('NEXT'));
    await tapVisible(tester, find.text('NEXT'));
    await tapVisible(tester, find.text('NEXT'));
    await tapVisible(tester, find.text('GET STARTED'));
    await tapVisible(tester, find.text('CREATE ACCOUNT'));
    await enter(tester, 'Full name', 'New Player');
    await enter(tester, 'Email address', 'new@example.com');
    await enter(tester, 'Password', 'NewPassword9!');
    await tapVisible(tester, find.byType(Checkbox));
    await tapVisible(tester, find.text('CONTINUE'));
    expect(service.registeredIntent, AccountIntent.player);
    final otp = find.descendant(
      of: find.byType(AuthOtpInput),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(otp);
    await tester.enterText(otp, '000000');
    await tester.pumpAndSettle();
    expect(find.text('The code is invalid or expired.'), findsWidgets);
    await tester.enterText(otp, '123456');
    await tester.pumpAndSettle();
    await enter(tester, 'Username', 'new_player');
    await chooseBirthDate(tester, DateTime(1998, 5, 12));
    await tapVisible(tester, find.text('CONTINUE'));
    await tapVisible(tester, find.text('Skip photo for now'));
    await tapVisible(tester, find.text('PADEL').first);
    await tapVisible(tester, find.text('CONTINUE'));
    await tapVisible(tester, find.text('CONTINUE'));
    await tapVisible(tester, find.text('FINISH SETUP'));
    expect(state.currentAccount!.setupComplete, isTrue);
    final flow = authFlow(tester);
    expect(flow.stage, AuthStage.home);
    flow.enterApp();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('forgot/reset screens require a code and service confirmation', (
    tester,
  ) async {
    final state = await pumpApp(tester);
    await tapVisible(tester, find.text('FORGOT?'));
    await enter(tester, 'Email address', state.accounts.first.email);
    await tapVisible(tester, find.text('SEND RESET CODE'));
    await enter(tester, 'New password', 'ChangedPassword9!');
    await enter(tester, 'Confirm password', 'ChangedPassword9!');
    await tapVisible(tester, find.text('UPDATE PASSWORD'));
    expect(authFlow(tester).inlineField, 'otp');
    final otp = find.descendant(
      of: find.byType(AuthOtpInput),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(otp);
    await tester.enterText(otp, '654321');
    await tapVisible(tester, find.text('UPDATE PASSWORD'));
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(
      find.text('Password updated. Sign in with your new password.'),
      findsOneWidget,
    );
  });

  testWidgets('the signup code screen keeps the account step reachable', (
    tester,
  ) async {
    final state = await freshState();
    final service = AuthServiceFixture(state);
    addTearDown(service.dispose);
    await pumpApp(
      tester,
      state: state,
      authenticationService: service,
      emailVerificationEnabled: true,
    );
    final flow = authFlow(tester);
    flow.openCreateAccount();
    await tester.pumpAndSettle();
    await enter(tester, 'Full name', 'Switching Sides');
    await enter(tester, 'Email address', 'switch@example.com');
    await enter(tester, 'Password', 'SwitchPassword9!');
    await tapVisible(tester, find.byType(Checkbox));
    await tapVisible(tester, find.text('CONTINUE'));

    // Signup purpose on the shared code screen: the step rail, the inbox copy
    // and a way back to the address that turned out to be wrong.
    expect(find.text('VERIFY EMAIL'), findsWidgets);
    expect(find.text('CHECK YOUR'), findsOneWidget);
    expect(find.text('VERIFY & CONTINUE'), findsOneWidget);
    expect(find.text('Wrong address?'), findsOneWidget);
    expect(find.byType(AuthStepRail), findsOneWidget);

    await tapVisible(tester, find.text('Change email'));

    expect(flow.stage, AuthStage.createAccount);
    expect(flow.otp, isEmpty);
    expect(
      tester.widget<TextField>(field('Email address')).controller!.text,
      'switch@example.com',
    );
  });

  testWidgets('signup goes straight to the profile while verification is off', (
    tester,
  ) async {
    final state = await freshState();
    final service = AuthServiceFixture(state);
    addTearDown(service.dispose);
    await pumpApp(tester, state: state, authenticationService: service);
    final accounts = state.accounts.length;
    final flow = authFlow(tester);

    flow.openCreateAccount();
    await tester.pumpAndSettle();
    // The rail cannot promise a second screen the journey no longer has. Rail
    // labels are rendered upper-cased.
    expect(find.text('VERIFY'), findsNothing);
    expect(find.text('ACCOUNT'), findsOneWidget);
    expect(find.text('PROFILE'), findsOneWidget);

    await enter(tester, 'Full name', 'Straight Through');
    await enter(tester, 'Email address', 'straight@example.com');
    await enter(tester, 'Password', 'StraightPassword9!');
    await tapVisible(tester, find.byType(Checkbox));
    await tapVisible(tester, find.text('CONTINUE'));

    // No code screen: the secure session from the service lands the member on
    // the first profile step, with the account already created.
    expect(find.byType(VerifyEmailScreen), findsNothing);
    expect(flow.stage, AuthStage.profileBasics);
    expect(flow.email, 'straight@example.com');
    expect(state.accounts, hasLength(accounts + 1));
    expect(find.text('PROFILE SETUP'), findsWidgets);
  });

  testWidgets('system back follows auth stages and terms preserve signup', (
    tester,
  ) async {
    await pumpApp(tester);
    final flow = authFlow(tester);
    flow.openCreateAccount();
    await tester.pumpAndSettle();
    await enter(tester, 'Full name', 'Remember Me');
    await tapVisible(tester, find.text('Terms & Privacy'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(flow.stage, AuthStage.createAccount);
    expect(
      tester.widget<TextField>(field('Full name')).controller!.text,
      'Remember Me',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(flow.stage, AuthStage.welcome);
  });

  testWidgets(
    'logout from settings clears pushed pages and cannot navigate back',
    (tester) async {
      final state = await freshState();
      await state.signIn('acc-seebu');
      final service = AuthServiceFixture(state, restoredAccountId: 'acc-seebu');
      addTearDown(service.dispose);
      await pumpApp(tester, state: state, authenticationService: service);
      final context = tester.element(find.byType(RootGate));
      unawaited(pushRoute(context, AppRoute.settings));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Sign out'));
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(state.currentAccount, isNull);
      expect(
        Navigator.of(tester.element(find.byType(SignInScreen))).canPop(),
        isFalse,
      );
    },
  );

  testWidgets('revocation hides a protected page and returns to sign-in', (
    tester,
  ) async {
    final state = await freshState();
    await state.signIn('acc-seebu');
    final service = AuthServiceFixture(state, restoredAccountId: 'acc-seebu');
    addTearDown(service.dispose);
    await pumpApp(tester, state: state, authenticationService: service);
    final context = tester.element(find.byType(RootGate));
    unawaited(pushRoute(context, AppRoute.editProfile));
    await tester.pumpAndSettle();
    service.revoke();
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text('Edit profile'), findsNothing);
    expect(authFlow(tester).canAccessApp, isFalse);
  });

  testWidgets('named and typed routes cannot bypass authentication', (
    tester,
  ) async {
    await pumpApp(tester);
    final context = tester.element(find.byType(RootGate));
    unawaited(Navigator.of(context).pushNamed(AppRoute.settings));
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
    unawaited(pushRoute(context, AppRoute.editProfile));
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text('Edit profile'), findsNothing);
  });

  testWidgets('timeout ends loading and ignores a late login completion', (
    tester,
  ) async {
    final state = await freshState();
    final service = AuthServiceFixture(state);
    addTearDown(service.dispose);
    service.signInBarrier = Completer<void>();
    await pumpApp(tester, state: state, authenticationService: service);
    final flow = authFlow(tester);
    flow.email = state.accounts.first.email;
    flow.password = AuthServiceFixture.validPassword;
    final pending = flow.submitSignIn();
    await tester.pump(const Duration(seconds: 26));
    await pending;
    await tester.pump();
    expect(flow.busy, isFalse);
    expect(flow.inlineError, contains('timed out'));
    service.signInBarrier!.complete();
    await tester.pumpAndSettle();
    expect(flow.canAccessApp, isFalse);
    expect(state.currentAccount, isNull);
  });

  for (final size in [
    const Size(320, 568),
    const Size(844, 390),
    const Size(1024, 768),
  ]) {
    testWidgets('all auth stages fit $size with large text and keyboard', (
      tester,
    ) async {
      final state = await freshState(onboardingSeen: false);
      final service = AuthServiceFixture(state);
      addTearDown(service.dispose);
      await pumpApp(
        tester,
        state: state,
        authenticationService: service,
        size: size,
        textScale: 1.5,
        emailVerificationEnabled: true,
      );
      void noOverflow(String stage) =>
          expect(tester.takeException(), isNull, reason: stage);
      noOverflow('onboarding');
      final flow = authFlow(tester);
      await flow.finishOnboarding();
      await tester.pumpAndSettle();
      noOverflow('welcome');
      flow.openSignIn();
      await tester.pumpAndSettle();
      noOverflow('sign in');
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      await tester.pump();
      noOverflow('keyboard');
      tester.view.resetViewInsets();
      flow.openForgotPassword();
      await tester.pumpAndSettle();
      noOverflow('forgot');
      flow.email = state.accounts.first.email;
      await flow.submitForgotPassword();
      await tester.pumpAndSettle();
      noOverflow('reset');
      flow.openCreateAccount();
      await tester.pumpAndSettle();
      noOverflow('create');
      flow.openTerms(AuthStage.createAccount);
      await tester.pumpAndSettle();
      noOverflow('terms');
      flow.closeTerms();
      flow.fullName = 'New Player';
      flow.email = 'new@example.com';
      flow.password = 'NewPassword9!';
      flow.acceptedTerms = true;
      await flow.submitAccountDetails();
      await tester.pumpAndSettle();

      await tester.pumpAndSettle();
      noOverflow('verify');
      await flow.verifyCode('123456');
      await tester.pumpAndSettle();
      noOverflow('basics');
      flow.saveBasics(
        name: 'New Player',
        handleValue: 'new_player',
        dateOfBirthValue: DateTime(1998, 5, 12),
        cityValue: 'Karachi',
        bioValue: '',
      );
      await tester.pumpAndSettle();
      noOverflow('photo');
      flow.continueFromPhoto();
      await tester.pumpAndSettle();
      noOverflow('sports');
      flow.toggleSport(Sport.cricket);
      flow.submitSports();
      await tester.pumpAndSettle();
      noOverflow('levels');
      flow.submitLevels();
      await tester.pumpAndSettle();
      noOverflow('review');
      await flow.finishSetup();
      await tester.pumpAndSettle();
      noOverflow('complete');
    });
  }
}
