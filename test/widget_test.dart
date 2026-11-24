import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:sportika/features/auth/services/authentication_service.dart';

import 'helpers/auth_service_fixture.dart';

import 'helpers/harness.dart';

void main() {
  testWidgets('sign-in has no seeded-account bypass', (tester) async {
    await pumpApp(
      tester,
      authenticationService: UnavailableAuthenticationService(),
    );
    expect(find.text('DEMO ACCESS'), findsNothing);
    expect(find.text('Seebu Ali'), findsNothing);
    expect(find.text('SIGN IN'), findsWidgets);
    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
  });

  testWidgets('verified service sign-in opens the five-tab shell', (
    tester,
  ) async {
    final state = await pumpApp(tester);
    await tester.enterText(
      find.byType(TextField).at(0),
      state.accountById('acc-seebu')!.email,
    );
    await tester.enterText(
      find.byType(TextField).at(1),
      AuthServiceFixture.validPassword,
    );
    await tapVisible(tester, find.text('SIGN IN').last);
    for (final tab in ['Home', 'Tournaments', 'Matches', 'Team', 'Me']) {
      expect(find.text(tab), findsWidgets);
    }
  });

  testWidgets('a personal scorecard can be opened from the shell', (
    tester,
  ) async {
    final state = await freshState(onboardingSeen: false);
    await state.signIn('acc-seebu');
    await pumpApp(tester, state: state);

    // The seeded in-progress cricket card is offered on Home.
    await scrollHomeTo(tester, find.text('Continue scoring'));
    expect(find.text('Continue scoring'), findsOneWidget);
    await scrollHomeTo(tester, find.text('Neighbours').first);
    await tester.tap(find.text('Neighbours').first);
    await tester.pumpAndSettle();

    // Tapping it resumes the private scorecard instead of starting a new one.
    expect(find.text('Private scorecard · T5 · 5 overs'), findsOneWidget);
    expect(find.text('In progress · auto-saved'), findsOneWidget);
  });
}
