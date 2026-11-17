import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/app/env.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/features/auth/screens/sign_in_screen.dart';
import 'package:sportika/features/auth/screens/verify_email_screen.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

import 'helpers/auth_service_fixture.dart';
import 'helpers/harness.dart';

/// Passwordless sign-in.
///
/// The typed six-digit code is the primary path, because a mail scanner or a
/// desktop client can open a magic link before the member ever sees it. These
/// tests stay on the code, on the answers the server is allowed to give about
/// an address that has no account, and on the resend cooldown the project
/// enforces per address. The shipped build has email verification off, so each
/// test turns the code screen back on explicitly.
Finder _otp() => find.descendant(
  of: find.byType(AuthOtpInput),
  matching: find.byType(TextField),
);

/// Pumps the app with the code screen enabled, which the tests below need.
Future<LocalSportikaRepository> _pumpWithCodes(
  WidgetTester tester, {
  required LocalSportikaRepository state,
  required AuthServiceFixture service,
}) => pumpApp(
  tester,
  state: state,
  authenticationService: service,
  emailVerificationEnabled: true,
);

Future<void> _enter(WidgetTester tester, String label, String text) async {
  final target = find.descendant(
    of: find.byWidgetPredicate((w) => w is AuthField && w.label == label),
    matching: find.byType(TextField),
  );
  await tester.ensureVisible(target);
  await tester.enterText(target, text);
  await tester.pump();
}

/// Types the address and asks for a code instead of a password.
Future<void> _requestCode(WidgetTester tester, String email) async {
  await _enter(tester, 'Email address', email);
  await tapVisible(tester, find.text('Email me a sign-in code'));
}

void main() {
  testWidgets('a code request replaces the password and signs the member in', (
    tester,
  ) async {
    final state = await freshState();
    final account = state.accounts.first;
    final service = AuthServiceFixture(state);
    addTearDown(service.dispose);
    await _pumpWithCodes(tester, state: state, service: service);

    await _requestCode(tester, account.email);

    expect(service.signInCodeCalls, 1);
    expect(find.byType(VerifyEmailScreen), findsOneWidget);
    final flow = authFlow(tester);
    expect(flow.stage, AuthStage.verifyEmail);
    expect(flow.codePurpose, AuthCodePurpose.signIn);
    // Sign-in copy: no signup step rail and no "wrong address" escape hatch,
    // because the address was already typed on the previous screen.
    expect(find.text('PASSWORDLESS SIGN-IN'), findsOneWidget);
    expect(find.text('Wrong address?'), findsNothing);
    expect(find.text('Change email'), findsNothing);
    expect(find.text('VERIFY & CONTINUE'), findsNothing);
    expect(
      find.text(
        'If that address has a Sportika account, a sign-in code is on its way.',
      ),
      findsOneWidget,
    );

    // A wrong code is refused and keeps the member out of the app.
    await tester.enterText(_otp(), '000000');
    await tester.pumpAndSettle();
    expect(find.text('The code is invalid or expired.'), findsWidgets);
    expect(service.session, isNull);
    expect(flow.canAccessApp, isFalse);

    // The right code lands in the app without a password ever being typed.
    await tester.enterText(_otp(), '123456');
    await tester.pumpAndSettle();
    expect(service.signInCalls, 0);
    expect(flow.stage, AuthStage.home);
    expect(find.byType(SignInScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('a second code waits for the server cooldown', (tester) async {
    final state = await freshState();
    final service = AuthServiceFixture(state);
    addTearDown(service.dispose);
    await _pumpWithCodes(tester, state: state, service: service);
    await _requestCode(tester, state.accounts.first.email);
    final flow = authFlow(tester);

    // Still cooling down: the only resend affordance is the countdown, and
    // asking for another code is refused instead of spending the hourly quota.
    expect(find.text('RESEND IN 30s'), findsOneWidget);
    expect(find.text('Resend code'), findsNothing);
    await flow.resendCode();
    await tester.pumpAndSettle();
    expect(service.signInCodeCalls, 1);
  });

  testWidgets('once the cooldown passes, resend issues a fresh code', (
    tester,
  ) async {
    final state = await freshState();
    final service = AuthServiceFixture(state)..cooldown = Duration.zero;
    addTearDown(service.dispose);
    await _pumpWithCodes(tester, state: state, service: service);
    await _requestCode(tester, state.accounts.first.email);
    final flow = authFlow(tester);
    expect(find.text('DIDN\'T GET IT?'), findsOneWidget);

    await tapVisible(tester, find.text('Resend code'));

    // GoTrue has no resend endpoint for a sign-in code: the request is the
    // resend, and the answer stays just as neutral as the first one.
    expect(service.signInCodeCalls, 2);
    expect(flow.codePurpose, AuthCodePurpose.signIn);
    expect(
      find.text(
        'If that address has a Sportika account, a new code has been sent.',
      ),
      findsOneWidget,
    );
    await tester.enterText(_otp(), '123456');
    await tester.pumpAndSettle();
    expect(authFlow(tester).stage, AuthStage.home);
  });

  testWidgets('back from a sign-in code returns to sign in, not to signup', (
    tester,
  ) async {
    final state = await freshState();
    final service = AuthServiceFixture(state);
    addTearDown(service.dispose);
    await _pumpWithCodes(tester, state: state, service: service);
    await _requestCode(tester, state.accounts.first.email);
    final flow = authFlow(tester);

    flow.back();
    await tester.pumpAndSettle();

    expect(flow.stage, AuthStage.signIn);
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(flow.codePurpose, isNot(AuthCodePurpose.signIn));
  });

  testWidgets('an unknown address gets the same screen and no account', (
    tester,
  ) async {
    final state = await freshState();
    final service = AuthServiceFixture(state);
    addTearDown(service.dispose);
    final accounts = state.accounts.length;
    await _pumpWithCodes(tester, state: state, service: service);

    await _requestCode(tester, 'nobody@example.com');

    // The request cannot reveal whether the address exists, and it must never
    // create an account: that is the create_user: false flag on the wire.
    expect(find.byType(VerifyEmailScreen), findsOneWidget);
    expect(service.registerCalls, 0);
    await tester.enterText(_otp(), '123456');
    await tester.pumpAndSettle();
    expect(find.text('The code is invalid or expired.'), findsWidgets);
    expect(state.accounts, hasLength(accounts));
    expect(authFlow(tester).canAccessApp, isFalse);
  });

  testWidgets('a malformed address never reaches the server', (tester) async {
    final state = await freshState();
    final service = AuthServiceFixture(state);
    addTearDown(service.dispose);
    await _pumpWithCodes(tester, state: state, service: service);

    await _enter(tester, 'Email address', 'not-an-email');
    await tapVisible(tester, find.text('Email me a sign-in code'));

    expect(service.signInCodeCalls, 0);
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text('Enter a valid email address.'), findsWidgets);
  });

  testWidgets('no printed demo code ships in a non-demo build', (tester) async {
    // The demo notices are compile-time gated, so this binary - built without
    // DEMO_MODE - must not be able to render one at all.
    expect(AppEnv.demoMode, isFalse);
    final state = await freshState();
    final service = AuthServiceFixture(state);
    addTearDown(service.dispose);
    await _pumpWithCodes(tester, state: state, service: service);
    await _requestCode(tester, state.accounts.first.email);

    expect(find.textContaining('Demo verification code'), findsNothing);
    expect(find.textContaining('No email is sent'), findsNothing);
    expect(find.textContaining('Local frontend demo'), findsNothing);
  });

  testWidgets('code entry is not offered while verification is off', (
    tester,
  ) async {
    // The shipped default: no code can be mailed, so the link that would open
    // the verify screen is gone and the controller refuses the request even if
    // something still calls it.
    expect(AppEnv.emailVerificationEnabled, isFalse);
    final state = await freshState();
    final service = AuthServiceFixture(state);
    addTearDown(service.dispose);
    await pumpApp(tester, state: state, authenticationService: service);

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text('Email me a sign-in code'), findsNothing);
    expect(find.text('SIGN IN'), findsWidgets);

    final flow = authFlow(tester);
    flow.email = state.accounts.first.email;
    await flow.beginPasswordlessSignIn();
    await tester.pumpAndSettle();
    expect(service.signInCodeCalls, 0);
    expect(flow.stage, AuthStage.signIn);
    expect(find.byType(VerifyEmailScreen), findsNothing);
  });
}
