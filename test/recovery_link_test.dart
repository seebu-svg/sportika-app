import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/app/env.dart';
import 'package:sportika/features/auth/screens/reset_password_screen.dart';
import 'package:sportika/features/auth/screens/sign_in_screen.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

import 'helpers/auth_service_fixture.dart';
import 'helpers/harness.dart';

/// Recovery that started in the mail app instead of inside Sportika.
///
/// A recovery link carries its own proof: the SDK exchanges it, holds a
/// short-lived session for the account and fires the event the flow turns into
/// this screen. A six-digit field with nothing to type into it would read as a
/// broken form, so the link mode drops it - and the flow has to drop the
/// session again if the member walks away before choosing a password.
Future<void> _enter(WidgetTester tester, String label, String text) async {
  final target = find.descendant(
    of: find.byWidgetPredicate((w) => w is AuthField && w.label == label),
    matching: find.byType(TextField),
  );
  await tester.ensureVisible(target);
  await tester.enterText(target, text);
  await tester.pump();
}

/// Opens the app signed out, then plays the part of the exchanged link.
Future<AuthServiceFixture> _openLink(WidgetTester tester) async {
  final state = await freshState();
  final service = AuthServiceFixture(state);
  addTearDown(service.dispose);
  await pumpApp(tester, state: state, authenticationService: service);
  expect(find.byType(SignInScreen), findsOneWidget);
  service.beginRecovery(state.accounts.first.id);
  await tester.pumpAndSettle();
  return service;
}

void main() {
  testWidgets('an opened link lands on the reset screen with no code field', (
    tester,
  ) async {
    await _openLink(tester);
    final flow = authFlow(tester);

    expect(find.byType(ResetPasswordScreen), findsOneWidget);
    expect(flow.stage, AuthStage.resetPassword);
    expect(flow.recoveryFromLink, isTrue);
    expect(find.byType(AuthOtpInput), findsNothing);
    expect(find.text('Resend reset code'), findsNothing);
    expect(
      find.text('Opened from your email link. No code is needed.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('The link you opened already confirmed this address'),
      findsOneWidget,
    );
    // A recovery session is not a signed-in member: the shell stays closed and
    // no protected screen is reachable while the password is still the old one.
    expect(flow.canAccessApp, isFalse);
    expect(find.byType(NavigationBar), findsNothing);
    // And the release build prints no demo code for it either.
    expect(AppEnv.demoMode, isFalse);
    expect(find.textContaining('Demo recovery code'), findsNothing);
  });

  testWidgets('the link sets a new password without ever asking for a code', (
    tester,
  ) async {
    final state = await freshState();
    final account = state.accounts.first;
    final service = AuthServiceFixture(state);
    addTearDown(service.dispose);
    await pumpApp(tester, state: state, authenticationService: service);
    service.beginRecovery(account.id);
    await tester.pumpAndSettle();
    final flow = authFlow(tester);

    await tapVisible(tester, find.text('UPDATE PASSWORD'));
    expect(flow.stage, AuthStage.resetPassword);
    expect(find.text('Use at least 8 characters.'), findsWidgets);

    await _enter(tester, 'New password', 'RecoveredPass9!');
    await _enter(tester, 'Confirm password', 'nope');
    await tapVisible(tester, find.text('UPDATE PASSWORD'));
    expect(find.text('Both passwords must match.'), findsWidgets);

    await _enter(tester, 'Confirm password', 'RecoveredPass9!');
    await tapVisible(tester, find.text('UPDATE PASSWORD'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(
      find.text('Password updated. Sign in with your new password.'),
      findsOneWidget,
    );
    // The recovery session is gone, so the member has to prove the new password
    // like anyone else.
    expect(service.recoveryPending, isFalse);
    expect(flow.recoveryFromLink, isFalse);
    expect(service.session, isNull);
    expect(service.passwords[account.email.toLowerCase()], 'RecoveredPass9!');

    await _enter(tester, 'Email address', account.email);
    await _enter(tester, 'Password', 'RecoveredPass9!');
    await tapVisible(tester, find.text('SIGN IN').last);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(flow.stage, AuthStage.home);
  });

  testWidgets('walking away from a link recovery drops its session', (
    tester,
  ) async {
    final service = await _openLink(tester);
    final flow = authFlow(tester);
    expect(service.session, isNotNull);

    await tapVisible(tester, find.text('Back to sign in'));

    expect(flow.stage, AuthStage.signIn);
    expect(flow.recoveryFromLink, isFalse);
    expect(service.recoveryPending, isFalse);
    expect(service.session, isNull);
    expect(find.byType(SignInScreen), findsOneWidget);

    // A recovery started from scratch inside the app is the typed-code path
    // again, so the code field has to come back.
    await tapVisible(tester, find.text('FORGOT?'));
    await _enter(tester, 'Email address', 'someone@example.com');
    await tapVisible(tester, find.text('SEND RESET CODE'));
    expect(flow.recoveryFromLink, isFalse);
    expect(find.byType(AuthOtpInput), findsOneWidget);
    expect(
      find.textContaining('Enter the reset code sent to someone@example.com'),
      findsOneWidget,
    );
  });
}
