import 'package:flutter/foundation.dart';

import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/shared/models/models.dart';

/// A controllable in-memory [NotificationRepository] used to stand in for the
/// server side and the device side of [CompositeNotificationRepository], and
/// for the single source behind [NotificationsController].
///
/// It records every interaction so a test can assert where a call was routed
/// rather than only what came back, and [emit] lets a test make the source
/// change on its own — the way realtime or a device mutation would.
class FakeNotificationRepository extends ChangeNotifier
    implements NotificationRepository {
  FakeNotificationRepository({
    List<AppNotification> items = const [],
    NotificationPreferences preferences = const NotificationPreferences(),
  }) : _items = [...items],
       // The public named parameter cannot initialize a private field directly.
       // ignore: prefer_initializing_formals
       _preferences = preferences;

  final List<AppNotification> _items;
  NotificationPreferences _preferences;

  // ── Interaction counters a test reads back ──────────────────────────────
  int syncCalls = 0;
  int loadMoreCalls = 0;
  int watchCalls = 0;
  int unwatchCalls = 0;
  int loadPreferencesCalls = 0;
  int markAllCalls = 0;
  final List<String> markReadCalls = [];
  final List<NotificationPreferences> preferenceWrites = [];

  bool hasMore = false;
  bool loading = false;
  String? error;

  @override
  List<AppNotification> get myNotifications => List.unmodifiable(_items);

  @override
  int get unreadCount => _items.where((n) => !n.read).length;

  @override
  Future<void> reload() => syncNotifications();

  @override
  Future<void> syncNotifications() async => syncCalls++;

  @override
  Future<void> loadMoreNotifications() async => loadMoreCalls++;

  @override
  bool get hasMoreNotifications => hasMore;

  @override
  bool get loadingNotifications => loading;

  @override
  String? get notificationError => error;

  @override
  Future<AppNotification?> notificationById(String id) async {
    for (final n in _items) {
      if (n.id == id) return n;
    }
    return null;
  }

  @override
  void markNotificationRead(String id) {
    markReadCalls.add(id);
    final index = _items.indexWhere((n) => n.id == id);
    if (index < 0 || _items[index].read) return;
    _items[index] = _asRead(_items[index]);
    notifyListeners();
  }

  @override
  void markAllNotificationsRead() {
    markAllCalls++;
    for (var i = 0; i < _items.length; i++) {
      if (!_items[i].read) _items[i] = _asRead(_items[i]);
    }
    notifyListeners();
  }

  @override
  NotificationPreferences get notificationPreferences => _preferences;

  @override
  Future<void> updateNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    preferenceWrites.add(preferences);
    _preferences = preferences;
    notifyListeners();
  }

  @override
  Future<void> loadNotificationPreferences() async => loadPreferencesCalls++;

  @override
  Future<void> watchNotifications() async => watchCalls++;

  @override
  Future<void> unwatchNotifications() async => unwatchCalls++;

  /// Makes the source change underneath the composite, the way a realtime row
  /// or a device-side event would.
  void emit(AppNotification notification) {
    _items.insert(0, notification);
    notifyListeners();
  }

  /// Seeds the value a later [loadNotificationPreferences] will surface,
  /// without recording it as a client write.
  void seedPreferences(NotificationPreferences preferences) {
    _preferences = preferences;
  }

  static AppNotification _asRead(AppNotification n) => AppNotification(
    id: n.id,
    accountId: n.accountId,
    kind: n.kind,
    title: n.title,
    body: n.body,
    route: n.route,
    read: true,
    at: n.at,
    type: n.type,
    entityType: n.entityType,
    entityId: n.entityId,
    payload: n.payload,
    actorId: n.actorId,
    expiresAt: n.expiresAt,
  );
}
