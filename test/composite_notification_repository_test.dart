import 'package:flutter_test/flutter_test.dart';

import 'package:sportika/core/data/composite_notification_repository.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';

import 'helpers/fake_notification_repository.dart';

/// Composite-inbox construction helpers.
///
/// Ids follow the same convention as production (UUIDs on the server, `ntf…`
/// on the device) so nothing accidentally collides. The default timestamps
/// space the two sources apart so a merge assertion has a defined order.
AppNotification _n({
  required String id,
  DateTime? at,
  bool read = false,
  NotificationKind kind = NotificationKind.teamUpdate,
  String accountId = 'acct-1',
}) => AppNotification(
  id: id,
  accountId: accountId,
  kind: kind,
  title: 't-$id',
  body: 'b-$id',
  read: read,
  at: at ?? DateTime(2026, 11, 15, 12),
);

void main() {
  group('CompositeNotificationRepository reads', () {
    test('merges both sources newest first', () {
      final server = FakeNotificationRepository(
        items: [
          _n(
            id: 'aaaaaaaa-0000-0000-0000-000000000001',
            at: DateTime(2026, 11, 15, 10),
          ),
          _n(
            id: 'aaaaaaaa-0000-0000-0000-000000000002',
            at: DateTime(2026, 11, 14, 10),
          ),
        ],
      );
      final device = FakeNotificationRepository(
        items: [_n(id: 'ntf-device-1', at: DateTime(2026, 11, 15, 11))],
      );
      final inbox = CompositeNotificationRepository(
        server: server,
        device: device,
      );

      expect(
        inbox.myNotifications.map((n) => n.id),
        orderedEquals([
          'ntf-device-1',
          'aaaaaaaa-0000-0000-0000-000000000001',
          'aaaaaaaa-0000-0000-0000-000000000002',
        ]),
      );
    });

    test('de-duplicates by id and prefers the server row', () {
      final dupServer = _n(id: 'shared', at: DateTime(2026, 11, 15, 9));
      final dupDevice = _n(
        id: 'shared',
        at: DateTime(2026, 11, 15, 9),
        read: true,
      );
      final server = FakeNotificationRepository(items: [dupServer]);
      final device = FakeNotificationRepository(items: [dupDevice]);
      final inbox = CompositeNotificationRepository(
        server: server,
        device: device,
      );

      expect(inbox.myNotifications, hasLength(1));
      // putIfAbsent means the server copy wins when a row ever appears twice.
      expect(inbox.myNotifications.single.read, isFalse);
    });

    test('unreadCount sums unread across both sources', () {
      final server = FakeNotificationRepository(
        items: [
          _n(id: 'aaaaaaaa-0000-0000-0000-000000000001', read: false),
          _n(id: 'aaaaaaaa-0000-0000-0000-000000000002', read: true),
        ],
      );
      final device = FakeNotificationRepository(
        items: [
          _n(id: 'ntf-a', read: false),
          _n(id: 'ntf-b', read: false),
          _n(id: 'ntf-c', read: true),
        ],
      );
      final inbox = CompositeNotificationRepository(
        server: server,
        device: device,
      );

      expect(inbox.unreadCount, 3);
    });

    test('hasMoreNotifications / loading / error mirror the server', () {
      final server = FakeNotificationRepository();
      server.hasMore = true;
      server.loading = true;
      server.error = 'boom';
      final device = FakeNotificationRepository();
      final inbox = CompositeNotificationRepository(
        server: server,
        device: device,
      );

      expect(inbox.hasMoreNotifications, isTrue);
      expect(inbox.loadingNotifications, isTrue);
      expect(inbox.notificationError, 'boom');
    });

    test('notificationById tries the server first, then the device', () async {
      final server = FakeNotificationRepository(items: [_n(id: 'srv-1')]);
      final device = FakeNotificationRepository(items: [_n(id: 'ntf-1')]);
      final inbox = CompositeNotificationRepository(
        server: server,
        device: device,
      );

      expect((await inbox.notificationById('srv-1'))?.id, 'srv-1');
      expect((await inbox.notificationById('ntf-1'))?.id, 'ntf-1');
      expect(await inbox.notificationById('missing'), isNull);
    });
  });

  group('CompositeNotificationRepository sync and pagination', () {
    test('syncNotifications pulls the server and repaints', () async {
      final server = FakeNotificationRepository();
      final device = FakeNotificationRepository();
      final inbox = CompositeNotificationRepository(
        server: server,
        device: device,
      );

      var repaints = 0;
      inbox.addListener(() => repaints++);
      await inbox.syncNotifications();

      expect(server.syncCalls, 1);
      expect(repaints, greaterThan(0));
    });

    test('loadMoreNotifications forwards to the server only', () async {
      final server = FakeNotificationRepository();
      final device = FakeNotificationRepository();
      final inbox = CompositeNotificationRepository(
        server: server,
        device: device,
      );

      await inbox.loadMoreNotifications();

      expect(server.loadMoreCalls, 1);
      expect(device.loadMoreCalls, 0);
    });

    test('reload routes through syncNotifications', () async {
      final server = FakeNotificationRepository();
      final device = FakeNotificationRepository();
      final inbox = CompositeNotificationRepository(
        server: server,
        device: device,
      );

      await inbox.reload();

      expect(server.syncCalls, 1);
    });
  });

  group('CompositeNotificationRepository writes', () {
    test('markNotificationRead actually marks the owning side read', () {
      final server = FakeNotificationRepository(
        items: [_n(id: 'aaaaaaaa-0000-0000-0000-000000000001')],
      );
      final device = FakeNotificationRepository(items: [_n(id: 'ntf-1')]);
      final inbox = CompositeNotificationRepository(
        server: server,
        device: device,
      );

      inbox.markNotificationRead('aaaaaaaa-0000-0000-0000-000000000001');
      expect(server.myNotifications.single.read, isTrue);
      expect(device.myNotifications.single.read, isFalse);

      inbox.markNotificationRead('ntf-1');
      expect(device.myNotifications.single.read, isTrue);
    });

    test('markAllNotificationsRead clears both sources', () {
      final server = FakeNotificationRepository(items: [_n(id: 'srv-1')]);
      final device = FakeNotificationRepository(items: [_n(id: 'ntf-1')]);
      final inbox = CompositeNotificationRepository(
        server: server,
        device: device,
      );

      inbox.markAllNotificationsRead();

      expect(server.markAllCalls, 1);
      expect(device.markAllCalls, 1);
      expect(inbox.unreadCount, 0);
    });
  });

  group('CompositeNotificationRepository preferences', () {
    test(
      'updateNotificationPreferences writes the server and mirrors device',
      () async {
        final server = FakeNotificationRepository();
        final device = FakeNotificationRepository();
        final inbox = CompositeNotificationRepository(
          server: server,
          device: device,
        );
        const prefs = NotificationPreferences(
          matchActivity: false,
          tournamentUpdates: true,
          teamActivity: false,
          scorerAssignments: true,
          platformAnnouncements: false,
        );

        await inbox.updateNotificationPreferences(prefs);

        expect(server.preferenceWrites.single, same(prefs));
        expect(device.preferenceWrites.single, same(prefs));
        expect(inbox.notificationPreferences, same(prefs));
      },
    );

    test('loadNotificationPreferences reads the server then mirrors into '
        'the device gate', () async {
      final server = FakeNotificationRepository();
      server.seedPreferences(
        const NotificationPreferences(
          matchActivity: false,
          teamActivity: false,
        ),
      );
      final device = FakeNotificationRepository();
      final inbox = CompositeNotificationRepository(
        server: server,
        device: device,
      );

      await inbox.loadNotificationPreferences();

      expect(server.loadPreferencesCalls, 1);
      // The device store now holds the server value, so both category gates
      // agree about which families are on.
      expect(device.preferenceWrites.single.matchActivity, isFalse);
      expect(device.preferenceWrites.single.teamActivity, isFalse);
      expect(inbox.notificationPreferences.matchActivity, isFalse);
    });
  });

  group('CompositeNotificationRepository live subscription', () {
    test('watch / unwatch reach both sources', () async {
      final server = FakeNotificationRepository();
      final device = FakeNotificationRepository();
      final inbox = CompositeNotificationRepository(
        server: server,
        device: device,
      );

      await inbox.watchNotifications();
      expect(server.watchCalls, 1);
      expect(device.watchCalls, 1);

      await inbox.unwatchNotifications();
      expect(server.unwatchCalls, 1);
      expect(device.unwatchCalls, 1);
    });

    test('a server emit repaints the composite (realtime)', () {
      final server = FakeNotificationRepository();
      final device = FakeNotificationRepository();
      final inbox = CompositeNotificationRepository(
        server: server,
        device: device,
      );

      var repaints = 0;
      inbox.addListener(() => repaints++);
      server.emit(_n(id: 'aaaaaaaa-0000-0000-0000-000000000009'));

      expect(repaints, 1);
      expect(
        inbox.myNotifications.map((n) => n.id),
        contains('aaaaaaaa-0000-0000-0000-000000000009'),
      );
    });

    test('a device emit repaints the composite (local event)', () {
      final server = FakeNotificationRepository();
      final device = FakeNotificationRepository();
      final inbox = CompositeNotificationRepository(
        server: server,
        device: device,
      );

      var repaints = 0;
      inbox.addListener(() => repaints++);
      device.emit(_n(id: 'ntf-live'));

      expect(repaints, 1);
      expect(inbox.myNotifications.map((n) => n.id), contains('ntf-live'));
    });

    test('dispose detaches both listeners without disposing the sources', () {
      final server = FakeNotificationRepository();
      final device = FakeNotificationRepository();
      final inbox = CompositeNotificationRepository(
        server: server,
        device: device,
      );

      var repaints = 0;
      inbox.addListener(() => repaints++);
      inbox.dispose();

      // Sources must still be alive after the composite goes away — the app
      // owns them, not this wrapper.
      server.emit(_n(id: 'aaaaaaaa-0000-0000-0000-000000000010'));
      device.emit(_n(id: 'ntf-after'));
      expect(repaints, 0, reason: 'composite listener must be detached');
      expect(
        server.myNotifications.map((n) => n.id),
        contains('aaaaaaaa-0000-0000-0000-000000000010'),
      );
      expect(device.myNotifications.map((n) => n.id), contains('ntf-after'));
    });
  });
}
