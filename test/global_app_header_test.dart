import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/shared/widgets/global_app_header.dart';
import 'package:sportika/app/providers.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/live/screens/notifications_screen.dart';

import 'helpers/harness.dart';

/// Both header variants name their bell action "Notifications", but the Home
/// variant appends the unread count, so the probe matches on the prefix.
Finder notificationsAction() => find.byWidgetPredicate(
  (widget) =>
      widget is Tooltip &&
      (widget.message?.startsWith('Notifications') ?? false),
);

void main() {
  testWidgets('long label respects safe area and large accessibility text', (
    tester,
  ) async {
    final state = await freshState();
    await state.signIn('acc-seebu');
    await tester.binding.setSurfaceSize(const Size(280, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildAppProviders(
        repository: state,
        child: MaterialApp(
          theme: buildSportikaTheme(),
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(280, 600),
              padding: EdgeInsets.only(top: 32),
              textScaler: TextScaler.linear(3),
            ),
            child: Scaffold(
              body: Column(
                children: [
                  GlobalAppHeader(
                    section: 'Tournament management and discovery',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.byType(BrandMark)).dy,
      greaterThanOrEqualTo(32),
    );
    expect(find.byTooltip('Account menu'), findsOneWidget);
    expect(notificationsAction(), findsOneWidget);
  });
  for (final width in [320.0, 400.0]) {
    testWidgets('all five tabs share header geometry at width $width', (
      tester,
    ) async {
      final state = await freshState();
      await state.signIn('acc-seebu');
      await pumpApp(
        tester,
        state: state,
        size: Size(width, 844),
        textScale: 1.3,
      );
      final header = find.byType(GlobalAppHeader);
      final bounds = tester.getRect(header);
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byType(NavigationDestination).at(i));
        await tester.pumpAndSettle();
        expect(header, findsOneWidget);
        expect(tester.getRect(header), bounds);
        expect(
          tester.widget<GlobalAppHeader>(header).section,
          ['Home', 'Tournaments', 'Matches', 'Team', 'Me'][i],
        );
        expect(find.byTooltip('Account menu'), findsOneWidget);
        // The Home tab swaps NotificationBell for its own action pair and
        // folds the unread count into its label, so the shared probe is the
        // tooltip prefix both variants expose.
        expect(notificationsAction(), findsOneWidget);
        final avatar = tester.widget<AccountAvatar>(
          find.descendant(of: header, matching: find.byType(AccountAvatar)),
        );
        expect(avatar.account.id, state.currentAccount!.id);
        expect(tester.takeException(), isNull);
      }
      state.markAllNotificationsRead();
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: header, matching: find.byType(AppBadge)),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      expect(find.text('View all'), findsOneWidget);
      await tester.tap(find.text('View all'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);
    });
  }
}
