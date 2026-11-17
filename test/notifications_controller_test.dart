import 'package:flutter_test/flutter_test.dart';

import 'package:sportika/core/state/notifications_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';

import 'helpers/fake_notification_repository.dart';

AppNotification _n({
  required String id,
  required DateTime at,
  bool read = false,
  NotificationKind kind = NotificationKind.matchInvite,
}) => AppNotification(
  id: id,
  accountId: 'acct-1',
  kind: kind,
  title: 't-$id',
  body: 'b-$id',
  read: read,
  at: at,
);

void main() {
  final now = DateTime.now();

  group('NotificationsController list and filter', () {
    test('exposes the repository inbox newest first and counts unread', () {
      final repo = FakeNotificationRepository(
        items: [
          _n(id: 'a', at: now, read: false),
          _n(id: 'b', at: now.subtract(const Duration(hours: 2)), read: true),
          _n(id: 'c', at: now.subtract(const Duration(hours: 3)), read: false),
        ],
      );
      final controller = NotificationsController(repo);

      expect(controller.myNotifications.map((n) => n.id), ['a', 'b', 'c']);
      expect(controller.unreadCount, 2);
      expect(controller.hasAny, isTrue);
      expect(controller.hasUnread, isTrue);
    });

    test('unreadOnly filter narrows the visible list and the groups', () {
      final repo = FakeNotificationRepository(
        items: [
          _n(id: 'unread', at: now, read: false),
          _n(id: 'read', at: now, read: true),
        ],
      );
      final controller = NotificationsController(repo);

      expect(
        controller.visibleNotifications.map((n) => n.id),
        containsAll(['unread', 'read']),
      );

      controller.setUnreadOnly(true);

      expect(controller.unreadOnly, isTrue);
      expect(controller.visibleNotifications.map((n) => n.id), ['unread']);
      // A read item never lingers as a stray header under the unread filter.
      final today = controller.groupedNotifications[NotificationGroup.today]!;
      expect(today.map((n) => n.id), ['unread']);
    });

    test('setUnreadOnly notifies listeners only on a real change', () {
      final repo = FakeNotificationRepository();
      final controller = NotificationsController(repo);

      var notifies = 0;
      controller.addListener(() => notifies++);
      controller.setUnreadOnly(false); // already false
      expect(notifies, 0);
      controller.setUnreadOnly(true);
      expect(notifies, 1);
    });
  });

  group('NotificationsController date grouping', () {
    test('splits the inbox into today, yesterday and earlier', () {
      final repo = FakeNotificationRepository(
        items: [
          _n(id: 'today', at: now),
          _n(id: 'yesterday', at: now.subtract(const Duration(days: 1))),
          _n(id: 'earlier', at: now.subtract(const Duration(days: 4))),
        ],
      );
      final controller = NotificationsController(repo);
      final groups = controller.groupedNotifications;

      expect(groups[NotificationGroup.today]!.map((n) => n.id), ['today']);
      expect(groups[NotificationGroup.yesterday]!.map((n) => n.id), [
        'yesterday',
      ]);
      expect(groups[NotificationGroup.earlier]!.map((n) => n.id), ['earlier']);
    });

    test('midnight timestamps belong to the correct local date', () {
      final today = DateTime(now.year, now.month, now.day);
      final repo = FakeNotificationRepository(
        items: [
          _n(id: 'midnight', at: today.toUtc()),
          _n(
            id: 'yesterday-midnight',
            at: today.subtract(const Duration(days: 1)).toUtc(),
          ),
        ],
      );
      final controller = NotificationsController(repo);
      expect(
        controller.groupedNotifications[NotificationGroup.today]!.single.id,
        'midnight',
      );
      expect(
        controller.groupedNotifications[NotificationGroup.yesterday]!.single.id,
        'yesterday-midnight',
      );
    });

    test('group labels read the way the centre prints them', () {
      expect(NotificationGroup.today.label, 'Today');
      expect(NotificationGroup.yesterday.label, 'Yesterday');
      expect(NotificationGroup.earlier.label, 'Earlier');
    });
  });

  group('NotificationsController delegation', () {
    test('start / stop drive the live subscription', () async {
      final repo = FakeNotificationRepository();
      final controller = NotificationsController(repo);

      await controller.start();
      expect(repo.watchCalls, 1);
      await controller.stop();
      expect(repo.unwatchCalls, 1);
    });

    test('refresh pulls the inbox from the repository', () async {
      final repo = FakeNotificationRepository();
      final controller = NotificationsController(repo);

      await controller.refresh();
      expect(repo.syncCalls, 1);
    });

    test('loadMore forwards to the repository', () async {
      final repo = FakeNotificationRepository();
      final controller = NotificationsController(repo);

      await controller.loadMore();
      expect(repo.loadMoreCalls, 1);
    });

    test('mark-read and mark-all-read reach the repository', () {
      final repo = FakeNotificationRepository(
        items: [
          _n(id: 'a', at: now),
          _n(id: 'b', at: now),
        ],
      );
      final controller = NotificationsController(repo);

      controller.markNotificationRead('a');
      expect(repo.markReadCalls, ['a']);
      controller.markAllNotificationsRead();
      expect(repo.markAllCalls, 1);
      expect(controller.unreadCount, 0);
    });

    test('preference read and write reach the repository', () async {
      final repo = FakeNotificationRepository();
      final controller = NotificationsController(repo);

      await controller.loadPreferences();
      expect(repo.loadPreferencesCalls, 1);

      const prefs = NotificationPreferences(teamActivity: false);
      await controller.updatePreferences(prefs);
      expect(repo.preferenceWrites.single, same(prefs));
      expect(controller.preferences, same(prefs));
    });

    test('loading, hasMore and error mirror the repository', () {
      final repo = FakeNotificationRepository();
      repo.loading = true;
      repo.hasMore = true;
      repo.error = 'offline';
      final controller = NotificationsController(repo);

      expect(controller.loading, isTrue);
      expect(controller.hasMore, isTrue);
      expect(controller.error, 'offline');
    });
  });

  group('NotificationsController change propagation', () {
    test('a repository change repaints the controller', () {
      final repo = FakeNotificationRepository();
      final controller = NotificationsController(repo);

      var notifies = 0;
      controller.addListener(() => notifies++);
      repo.emit(_n(id: 'live', at: now));

      expect(notifies, 1);
      expect(controller.myNotifications.map((n) => n.id), contains('live'));
    });
  });
}
