import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/shared/widgets/global_app_header.dart';
import 'package:sportika/features/profile/screens/edit_profile_screen.dart';
import 'package:sportika/features/profile/screens/settings_screen.dart';
import 'package:sportika/shared/navigation/navigation.dart';

import 'helpers/harness.dart';

/// The sheet has no visible title row that survives redesigns, so the open and
/// dismissed probes are the modal sheet itself.
Finder quickMenu() => find.byType(BottomSheet);

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Account menu'));
  await tester.pumpAndSettle();
  expect(quickMenu(), findsOneWidget);
}

void main() {
  for (final size in [const Size(320, 568), const Size(800, 360)]) {
    testWidgets('Menu fits $size and dismisses by back, backdrop and drag', (
      tester,
    ) async {
      final state = await freshState();
      await state.signIn('acc-seebu');
      await pumpApp(tester, state: state, size: size, textScale: 1.3);
      await openMenu(tester);
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(quickMenu(), findsNothing);
      await openMenu(tester);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(quickMenu(), findsNothing);
      await openMenu(tester);
      await tester.dragFrom(
        tester.getTopLeft(find.byType(BottomSheet)) + const Offset(240, 16),
        const Offset(0, 600),
      );
      await tester.pumpAndSettle();
      expect(quickMenu(), findsNothing);
      expect(state.isSignedIn, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Account actions reuse profile tab and existing screens', (
    tester,
  ) async {
    final state = await freshState();
    await state.signIn('acc-seebu');
    await pumpApp(tester, state: state);
    await openMenu(tester);
    await tester.tap(find.text('Edit Profile'));
    await tester.pumpAndSettle();
    expect(find.byType(EditProfileScreen), findsOneWidget);
    expect(quickMenu(), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openMenu(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openMenu(tester);
    // The identity card is the profile affordance; its brand eyebrow sits
    // inside the tap target that opens the athlete tab.
    await tester.tap(find.text('SPORTIKA ATHLETE'));
    await tester.pumpAndSettle();
    expect(homeTabRequest.value, 4);
    expect(quickMenu(), findsNothing);
  });

  testWidgets(
    'Dismiss and cancel preserve session; confirmed logout clears it',
    (tester) async {
      final state = await freshState();
      await state.signIn('acc-seebu');
      await pumpApp(tester, state: state);
      await openMenu(tester);
      await tester.tap(find.byTooltip('Close account menu'));
      await tester.pumpAndSettle();
      expect(state.isSignedIn, isTrue);
      await openMenu(tester);
      await tester.tap(find.text('Log Out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(state.isSignedIn, isTrue);
      await openMenu(tester);
      await tester.tap(find.text('Log Out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log Out'));
      await tester.pumpAndSettle();
      expect(state.isSignedIn, isFalse);
      expect(authFlow(tester).authenticated, isFalse);
      expect(find.byType(GlobalAppHeader), findsNothing);
    },
  );
}
