import 'package:flutter_test/flutter_test.dart';

import 'helpers/harness.dart';

void main() {
  testWidgets('the sign-in gate lists the demo accounts', (tester) async {
    await pumpApp(tester);

    expect(find.text('DEMO ACCESS'), findsOneWidget);
    expect(find.text('Seebu Ali'), findsOneWidget);
    expect(find.text('Yasir Malik'), findsOneWidget);
  });

  testWidgets('signing in opens the five-tab shell', (tester) async {
    await pumpApp(tester);

    // The demo row sits below the fold on a phone-sized surface.
    await tapVisible(tester, find.text('Seebu Ali'));
    await tester.pump(const Duration(milliseconds: 400));
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
