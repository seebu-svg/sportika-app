import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/core/state/feature_controller.dart';
import 'package:sportika/shared/models/models.dart';

/// The date groups the notification centre draws.
enum NotificationGroup { today, yesterday, earlier }

extension NotificationGroupX on NotificationGroup {
  String get label => switch (this) {
    NotificationGroup.today => 'Today',
    NotificationGroup.yesterday => 'Yesterday',
    NotificationGroup.earlier => 'Earlier',
  };
}

/// The notification centre's state.
///
/// The screen only ever talks to this controller: the list, the filter, the
/// loading and error flags, the pagination and the delivery preferences. The
/// repository behind it decides whether the inbox lives on the device or in
/// PostgreSQL.
class NotificationsController
    extends FeatureController<NotificationRepository> {
  NotificationsController(super.repo);

  bool _unreadOnly = false;

  /// Whether the centre shows only what has not been read yet.
  bool get unreadOnly => _unreadOnly;

  /// Everything the inbox holds, newest first.
  List<AppNotification> get myNotifications => repo.myNotifications;

  /// What the centre draws, after the filter.
  List<AppNotification> get visibleNotifications => _unreadOnly
      ? myNotifications.where((n) => !n.read).toList(growable: false)
      : myNotifications;

  /// The number the bell shows.
  int get unreadCount => repo.unreadCount;

  /// Whether a read is in flight.
  bool get loading => repo.loadingNotifications;

  /// Whether another page waits behind the one on screen.
  bool get hasMore => repo.hasMoreNotifications;

  /// The last failure, if any.
  String? get error => repo.notificationError;

  /// Which families of notification this member wants.
  NotificationPreferences get preferences => repo.notificationPreferences;

  /// The visible inbox split into the three date groups the centre draws.
  ///
  /// The grouping happens here rather than in the screen so the filter and
  /// the groups always agree: an item that the unread filter hides never
  /// leaves a stray header behind.
  Map<NotificationGroup, List<AppNotification>> get groupedNotifications {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfYesterday = startOfToday.subtract(const Duration(days: 1));
    final groups = <NotificationGroup, List<AppNotification>>{
      NotificationGroup.today: <AppNotification>[],
      NotificationGroup.yesterday: <AppNotification>[],
      NotificationGroup.earlier: <AppNotification>[],
    };
    for (final n in visibleNotifications) {
      final at = n.at.toLocal();
      final group = !at.isBefore(startOfToday)
          ? NotificationGroup.today
          : !at.isBefore(startOfYesterday)
          ? NotificationGroup.yesterday
          : NotificationGroup.earlier;
      groups[group]!.add(n);
    }
    return groups;
  }

  /// Whether the inbox holds anything at all, whatever the filter says.
  bool get hasAny => myNotifications.isNotEmpty;

  /// Whether the unread filter would leave something on screen.
  bool get hasUnread => unreadCount > 0;

  /// Switches between the whole inbox and the unread part of it.
  void setUnreadOnly(bool value) {
    if (_unreadOnly == value) return;
    _unreadOnly = value;
    notifyListeners();
  }

  /// Pull-to-refresh and the retry button both land here.
  Future<void> refresh() async {
    await repo.syncNotifications();
  }

  /// Loads the page behind the current one.
  Future<void> loadMore() async {
    await repo.loadMoreNotifications();
  }

  void markNotificationRead(String id) => repo.markNotificationRead(id);

  void markAllNotificationsRead() => repo.markAllNotificationsRead();

  /// Reads the stored preferences before the preferences screen is drawn.
  Future<void> loadPreferences() => repo.loadNotificationPreferences();

  /// Saves the delivery preferences.
  Future<void> updatePreferences(NotificationPreferences preferences) =>
      repo.updateNotificationPreferences(preferences);

  /// Starts the live subscription while the centre is on screen.
  Future<void> start() => repo.watchNotifications();

  /// Stops the live subscription when the centre closes.
  Future<void> stop() => repo.unwatchNotifications();
}
