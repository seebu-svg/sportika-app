import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sportika/core/state/notifications_controller.dart';
import 'package:sportika/features/live/screens/notifications_screen.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';

import 'helpers/fake_notification_repository.dart';
import 'helpers/harness.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/shared/navigation/notification_links.dart';

AppNotification item(int i, {bool read = false}) => AppNotification(
  id: 'n$i',
  accountId: 'account',
  kind: NotificationKind.values[i % NotificationKind.values.length],
  title: 'Update $i',
  body: 'Your sports activity has an update.',
  read: read,
  at: DateTime.now().subtract(Duration(minutes: i)),
);

Future<void> pumpInbox(
  WidgetTester tester,
  FakeNotificationRepository repo, {
  bool preview = false,
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => NotificationsController(repo),
      child: MaterialApp(
        theme: buildSportikaTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => const NotificationsScreen(),
        ),
        home: preview
            ? const Scaffold(body: Center(child: NotificationBell()))
            : const NotificationsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('bell preview limits latest items and marks shared inbox read', (
    tester,
  ) async {
    final repo = FakeNotificationRepository(items: List.generate(8, item));
    await pumpInbox(tester, repo, preview: true);
    await tester.tap(find.byType(NotificationBell));
    await tester.pumpAndSettle();
    expect(find.text('Update 0'), findsOneWidget);
    expect(find.text('Update 5'), findsNothing);
    expect(find.text('8 unread'), findsOneWidget);
    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();
    expect(repo.markAllCalls, 1);
    expect(find.text('You are up to date'), findsOneWidget);
    expect(find.text('View all'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty unread filter keeps All available and supports pagination',
    (tester) async {
      final repo = FakeNotificationRepository(items: [item(0, read: true)])
        ..hasMore = true;
      await pumpInbox(tester, repo);
      await tester.tap(find.text('Unread'));
      await tester.pumpAndSettle();
      expect(find.text('You are all caught up'), findsOneWidget);
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('Update 0'), findsOneWidget);
      await tester.tap(find.text('Load older notifications'));
      await tester.pumpAndSettle();
      expect(repo.loadMoreCalls, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('preview retries without hiding cached notifications', (
    tester,
  ) async {
    final repo = FakeNotificationRepository(items: [item(0)])
      ..error = 'Unavailable';
    await pumpInbox(tester, repo, preview: true);
    await tester.tap(find.byType(NotificationBell));
    await tester.pumpAndSettle();
    expect(find.text('Update 0'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(repo.syncCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'notification targets retain match, result, tournament and team routes',
    (tester) async {
      final repo = await freshState();
      await repo.signIn('acc-seebu');
      await pumpApp(tester, state: repo);
      final context = tester.element(find.byType(NotificationBell));
      AppNotification target(String type, String id) => AppNotification(
        id: 'link-$type',
        read: false,
        accountId: repo.currentAccount!.id,
        kind: NotificationKind.matchUpdate,
        title: 'Activity update',
        body: '',
        at: DateTime.now(),
        entityType: type,
        entityId: id,
      );
      final match = repo.discoverableMatches.first;
      expect(
        resolveNotificationTarget(context, target('match', match.id))?.route,
        AppRoute.matchDetail,
      );
      expect(
        resolveNotificationTarget(context, target('result', match.id))?.route,
        AppRoute.matchDetail,
      );
      expect(
        resolveNotificationTarget(
          context,
          target('tournament', repo.tournaments.first.id),
        )?.route,
        AppRoute.tournamentDetail,
      );
      expect(
        resolveNotificationTarget(
          context,
          target('team', repo.mySquads.first.id),
        )?.route,
        AppRoute.teamDetail,
      );
      expect(
        resolveNotificationTarget(context, target('team', 'removed-team')),
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 568), const Size(800, 360)]) {
    testWidgets(
      'preview fits $size with enlarged text and receives live updates',
      (tester) async {
        final repo = FakeNotificationRepository(items: [item(0)]);
        await pumpInbox(tester, repo, preview: true, size: size, scale: 1.5);
        await tester.tap(find.byType(NotificationBell));
        await tester.pumpAndSettle();
        repo.emit(item(1));
        await tester.pumpAndSettle();
        expect(find.text('2 unread'), findsOneWidget);
        expect(find.text('View all'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
