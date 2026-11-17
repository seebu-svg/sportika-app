import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/app.dart';
import 'package:sportika/app/env.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/features/auth/screens/change_email_screen.dart';
import 'package:sportika/features/auth/screens/change_password_screen.dart';
import 'package:sportika/features/auth/screens/sign_in_screen.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';
import 'package:sportika/features/profile/screens/settings_screen.dart';

import 'helpers/auth_service_fixture.dart';
import 'helpers/harness.dart';

/// The two credentials a signed-in member can change without signing out, and
/// the one action that ends every session the account has.
///
/// Both writes are reauthenticated server-side, and the address change is only
/// applied once both inboxes confirm, so these tests assert as much about what
/// must *not* happen locally - no stage reset, no half-applied email - as about
/// what does.
Finder _field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is AuthField && w.label == label),
  matching: find.byType(TextField),
);

/// The message a field is marked with, independent of the banner that repeats
/// it at the top of the screen.
String? _fieldError(WidgetTester tester, String label) => tester
    .widget<AuthField>(
      find.byWidgetPredicate((w) => w is AuthField && w.label == label),
    )
    .errorText;

Future<void> _enter(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(_field(label));
  await tester.enterText(_field(label), text);
  await tester.pump();
}

Future<void> _submit(WidgetTester tester, String label) =>
    tapVisible(tester, find.text(label));

/// Runs the three-second snack bar out so the test does not end on a timer.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

/// Pumps the app with a member who is already signed in and inside the shell.
Future<AuthServiceFixture> _pumpSignedIn(
  WidgetTester tester,
  LocalSportikaRepository state,
) async {
  await state.signIn(state.accounts.first.id);
  final service = AuthServiceFixture(
    state,
    restoredAccountId: state.accounts.first.id,
  );
  addTearDown(service.dispose);
  await pumpApp(tester, state: state, authenticationService: service);
  return service;
}

Future<void> _open(WidgetTester tester, String route) async {
  unawaited(pushRoute(tester.element(find.byType(RootGate)), route));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('settings lists both credentials and drops the demo controls', (
    tester,
  ) async {
    final state = await freshState();
    final account = state.accounts.first;
    await _pumpSignedIn(tester, state);

    await _open(tester, AppRoute.settings);

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('ACCOUNT AND SECURITY'), findsOneWidget);
    expect(find.text('EMAIL'), findsOneWidget);
    expect(find.text(account.email), findsWidgets);
    expect(find.text('PASSWORD'), findsOneWidget);
    expect(find.text('Sign out of all devices'), findsOneWidget);
    // A build without DEMO_MODE has no demo world to talk about.
    expect(AppEnv.demoMode, isFalse);
    expect(find.text('Reset demo data'), findsNothing);
    expect(
      find.textContaining('live in your Sportika account'),
      findsOneWidget,
    );
    expect(find.textContaining('All data is fictional'), findsNothing);

    await tapVisible(tester, find.widgetWithText(TextButton, 'Change').last);
    expect(find.byType(ChangePasswordScreen), findsOneWidget);
  });

  testWidgets('a new password is proved against the current one', (
    tester,
  ) async {
    final state = await freshState();
    final account = state.accounts.first;
    final service = await _pumpSignedIn(tester, state);
    final flow = authFlow(tester);
    await _open(tester, AppRoute.changePassword);

    await _submit(tester, 'Update password');
    expect(service.passwordChanges, 0);
    expect(
      _fieldError(tester, 'Current password'),
      'Enter your current password.',
    );
    expect(find.text('Enter your current password.'), findsWidgets);

    await _enter(tester, 'Current password', AuthServiceFixture.validPassword);
    await _enter(tester, 'New password', 'BrandNewPass9!');
    await _enter(tester, 'Confirm new password', 'different');
    await _submit(tester, 'Update password');
    expect(service.passwordChanges, 0);
    expect(
      _fieldError(tester, 'Confirm new password'),
      'Both passwords must match.',
    );

    await _enter(tester, 'Current password', 'WrongPassword9!');
    await _enter(tester, 'Confirm new password', 'BrandNewPass9!');
    await _submit(tester, 'Update password');
    expect(service.passwordChanges, 0);
    expect(
      _fieldError(tester, 'Current password'),
      'Your current password is incorrect.',
    );
    expect(find.text('Your current password is incorrect.'), findsWidgets);

    await _enter(tester, 'Current password', AuthServiceFixture.validPassword);
    await _submit(tester, 'Update password');
    await _settle(tester);

    expect(service.passwordChanges, 1);
    expect(service.passwords[account.email.toLowerCase()], 'BrandNewPass9!');
    expect(
      find.textContaining(
        'Password updated. Use it the next time you sign in.',
      ),
      findsOneWidget,
    );
    // The reauthentication the server demanded must not have ended the session
    // or bounced the member out of the screen they were standing in.
    expect(flow.canAccessApp, isTrue);
    expect(flow.stage, AuthStage.home);
    expect(find.byType(ChangePasswordScreen), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
  });

  testWidgets('a changed password can revoke every other device', (
    tester,
  ) async {
    final state = await freshState();
    final account = state.accounts.first;
    final service = await _pumpSignedIn(tester, state);
    await _open(tester, AppRoute.changePassword);
    await _enter(tester, 'Current password', AuthServiceFixture.validPassword);
    await _enter(tester, 'New password', 'BrandNewPass9!');
    await _enter(tester, 'Confirm new password', 'BrandNewPass9!');
    await _submit(tester, 'Update password');
    await _settle(tester);

    await tapVisible(tester, find.text('Sign out everywhere'));
    expect(find.text('Sign out of all devices?'), findsOneWidget);
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Sign out'));
    await _settle(tester);

    expect(service.signOutEverywhereCalls, 1);
    expect(service.session, isNull);
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      Navigator.of(tester.element(find.byType(SignInScreen))).canPop(),
      isFalse,
    );

    // The old password no longer opens anything; the new one does.
    expect(service.passwords[account.email.toLowerCase()], 'BrandNewPass9!');
  });

  testWidgets('an email change waits for both inboxes', (tester) async {
    final state = await freshState();
    final account = state.accounts.first;
    final taken = state.accounts.last.email;
    final service = await _pumpSignedIn(tester, state);
    await _open(tester, AppRoute.changeEmail);

    // The address on file is shown but not editable here.
    expect(find.byType(ChangeEmailScreen), findsOneWidget);
    expect(find.text('CURRENT ADDRESS'), findsOneWidget);
    expect(find.text(account.email), findsWidgets);

    await _enter(tester, 'New email address', account.email);
    await _submit(tester, 'Send confirmation');
    expect(service.emailChanges, 0);
    expect(
      _fieldError(tester, 'New email address'),
      'That is already your email address.',
    );

    await _enter(tester, 'New email address', taken);
    await _submit(tester, 'Send confirmation');
    expect(service.emailChanges, 0);
    expect(
      _fieldError(tester, 'Current password'),
      'Enter your current password.',
    );

    await _enter(tester, 'Current password', 'WrongPassword9!');
    await _submit(tester, 'Send confirmation');
    expect(service.emailChanges, 0);
    expect(
      _fieldError(tester, 'Current password'),
      'Your current password is incorrect.',
    );

    // The address belongs to someone else, and only the server can say so -
    // which it does now that the request is authorised.
    await _enter(tester, 'Current password', AuthServiceFixture.validPassword);
    await _submit(tester, 'Send confirmation');
    expect(service.emailChanges, 0);
    expect(
      _fieldError(tester, 'New email address'),
      'That email address is already in use.',
    );

    await _enter(tester, 'New email address', 'fresh@example.com');
    await _submit(tester, 'Send confirmation');
    await _settle(tester);

    expect(service.emailChanges, 1);
    expect(service.pendingEmailChange, 'fresh@example.com');
    expect(
      find.textContaining('The change is applied only after both inboxes'),
      findsOneWidget,
    );
    expect(find.textContaining('Confirmation sent.'), findsOneWidget);
    // Nothing was applied early: the account still signs in with the old
    // address, so a half-confirmed change cannot lock the member out.
    expect(account.email, isNot('fresh@example.com'));
    expect(state.accountByEmail('fresh@example.com'), isNull);
    expect(service.session, isNotNull);
  });

  testWidgets('the security screens cannot be opened while signed out', (
    tester,
  ) async {
    await pumpApp(tester);

    await _open(tester, AppRoute.changePassword);
    expect(find.byType(ChangePasswordScreen), findsNothing);
    await _open(tester, AppRoute.changeEmail);
    expect(find.byType(ChangeEmailScreen), findsNothing);
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(authFlow(tester).canAccessApp, isFalse);
  });
}
