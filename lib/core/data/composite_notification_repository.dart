import 'package:flutter/foundation.dart';

import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/shared/models/models.dart';

/// One inbox over two sources: the server and the device.
///
/// A live build reads the inbox from PostgreSQL, but the app still runs its
/// teams, tournaments, fixtures and pickup games in the on-device document,
/// and the device store generates a notification for each of those events.
/// Reading only the server table would hide every one of them, so the centre
/// is handed this composite instead: it merges both sources behind the same
/// [NotificationRepository] the controller already talks to, and no screen
/// knows there is more than one place behind it.
///
/// Three rules keep the two sources honest:
///
///  * the merged list is de-duplicated by id and ordered newest first, so a
///    row is never drawn twice and the date groups stay contiguous;
///  * delivery preferences are owned by the server, and every write is
///    mirrored into the device store so its own category gate refuses the same
///    families the server does;
///  * a change in either source repaints the inbox, because both are listened
///    to and re-emitted here — a device-generated notification shows up without
///    a round trip, and a server row shows up over realtime.
///
/// The composite owns neither source: it is constructed from repositories that
/// somebody else created and must not dispose. It only removes its own
/// listeners when it is disposed.
class CompositeNotificationRepository extends ChangeNotifier
    implements NotificationRepository {
  CompositeNotificationRepository({
    required this.server,
    required this.device,
  }) {
    _onServerChange = () => notifyListeners();
    _onDeviceChange = () => notifyListeners();
    server.addListener(_onServerChange);
    device.addListener(_onDeviceChange);
  }

  /// The PostgreSQL inbox: cross-member official-match and account events.
  final NotificationRepository server;

  /// The on-device inbox: teams, tournaments, fixtures and pickup games.
  final NotificationRepository device;

  late final VoidCallback _onServerChange;
  late final VoidCallback _onDeviceChange;

  // ── Reads ──────────────────────────────────────────────────────────────

  @override
  List<AppNotification> get myNotifications {
    // Server ids are UUIDs and device ids are `ntf…`, so the two never
    // collide; the map is only here to drop a duplicate should a source ever
    // report the same row twice.
    final byId = <String, AppNotification>{};
    for (final n in server.myNotifications) {
      byId[n.id] = n;
    }
    for (final n in device.myNotifications) {
      byId.putIfAbsent(n.id, () => n);
    }
    final merged = byId.values.toList()..sort((a, b) => b.at.compareTo(a.at));
    return List.unmodifiable(merged);
  }

  @override
  int get unreadCount => myNotifications.where((n) => !n.read).length;

  @override
  bool get hasMoreNotifications => server.hasMoreNotifications;

  @override
  bool get loadingNotifications => server.loadingNotifications;

  @override
  String? get notificationError => server.notificationError;

  @override
  Future<void> reload() => syncNotifications();

  @override
  Future<void> syncNotifications() async {
    // The device list is already in memory; only the server has a page to pull.
    await server.syncNotifications();
    notifyListeners();
  }

  @override
  Future<void> loadMoreNotifications() => server.loadMoreNotifications();

  @override
  Future<AppNotification?> notificationById(String id) async =>
      await server.notificationById(id) ?? await device.notificationById(id);

  // ── Writes ─────────────────────────────────────────────────────────────

  @override
  void markNotificationRead(String id) {
    // Ids are disjoint across the two sources, so each implementation quietly
    // no-ops on a row it does not own.
    server.markNotificationRead(id);
    device.markNotificationRead(id);
    notifyListeners();
  }

  @override
  void markAllNotificationsRead() {
    server.markAllNotificationsRead();
    device.markAllNotificationsRead();
    notifyListeners();
  }

  // ── Preferences ────────────────────────────────────────────────────────

  @override
  NotificationPreferences get notificationPreferences =>
      server.notificationPreferences;

  @override
  Future<void> loadNotificationPreferences() async {
    await server.loadNotificationPreferences();
    // Mirror what the server holds into the device gate so both agree.
    await device.updateNotificationPreferences(server.notificationPreferences);
    notifyListeners();
  }

  @override
  Future<void> updateNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    await server.updateNotificationPreferences(preferences);
    await device.updateNotificationPreferences(preferences);
    notifyListeners();
  }

  // ── Live subscription ──────────────────────────────────────────────────

  @override
  Future<void> watchNotifications() async {
    await server.watchNotifications();
    await device.watchNotifications();
  }

  @override
  Future<void> unwatchNotifications() async {
    await server.unwatchNotifications();
    await device.unwatchNotifications();
  }

  @override
  void dispose() {
    // Never dispose the sources; only detach this composite's listeners.
    server.removeListener(_onServerChange);
    device.removeListener(_onDeviceChange);
    super.dispose();
  }
}
