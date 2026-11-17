import 'dart:async';

import 'package:flutter/foundation.dart';
// Supabase ships its own `LocalStorage`; this file needs Sportika's on-device
// document store under that name.
import 'package:supabase_flutter/supabase_flutter.dart' hide LocalStorage;

import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';

/// A refusal the member can read as-is.
class NotificationRepositoryException implements Exception {
  const NotificationRepositoryException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// The in-app inbox against PostgreSQL.
///
/// The server owns the inbox: it decides who is notified, when, and with what
/// wording, and it enforces the delivery preferences while the notification is
/// generated. This class only reads it, marks it read and listens for new
/// rows.
///
/// Three properties matter and are all enforced here:
///
///  * the member only ever sees their own rows — the policy on the table says
///    so, and every read goes through a function that filters by `auth.uid()`;
///  * a notification is never created or edited by the client, so the only
///    writes are the two mark-as-read functions;
///  * the live channel is torn down when the session ends and rebuilt when a
///    new one starts, and every reconnect is followed by an authoritative
///    reload so a message that arrived while the socket was down is not lost.
class SupabaseNotificationRepository extends ChangeNotifier
    implements NotificationRepository {
  SupabaseNotificationRepository({
    required SupabaseClient client,
    // A named parameter cannot be a private initializing formal, so the field
    // is assigned from the matching parameter below.
  })
    // ignore: prefer_initializing_formals
    : _client = client {
    _authState = _client.auth.onAuthStateChange.listen(_handleAuthState);
    if (_client.auth.currentUser != null) {
      unawaited(_startWatching());
    }
  }

  final SupabaseClient _client;

  late final StreamSubscription<AuthState> _authState;

  /// The inbox as the app knows it: the newest page plus anything the member
  /// has scrolled further back into.
  final List<AppNotification> _items = [];

  int _unread = 0;
  bool _loading = false;
  bool _hasMore = false;
  String? _error;
  NotificationPreferences _preferences = const NotificationPreferences();

  /// The cursor for the next page: the created_at and id of the last row on
  /// screen. Keyset pagination never repeats or skips a row, even when a new
  /// notification lands mid-scroll.
  DateTime? _before;
  String? _beforeId;

  RealtimeChannel? _channel;
  String? _channelUserId;
  bool _disposed = false;

  static const int _pageSize = 30;

  // ── Reads ────────────────────────────────────────────────────────────────

  @override
  List<AppNotification> get myNotifications => List.unmodifiable(_items);

  @override
  int get unreadCount => _unread;

  @override
  bool get hasMoreNotifications => _hasMore;

  @override
  bool get loadingNotifications => _loading;

  @override
  String? get notificationError => _error;

  @override
  NotificationPreferences get notificationPreferences => _preferences;

  @override
  Future<void> reload() => syncNotifications();

  @override
  Future<void> syncNotifications() async {
    if (_disposed) return;
    if (_client.auth.currentUser == null) {
      _items.clear();
      _unread = 0;
      _hasMore = false;
      notifyListeners();
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final rows = await _fetchPage(reset: true);
      final count = await _fetchUnreadCount();
      if (_disposed) return;
      _items
        ..clear()
        ..addAll(rows);
      _unread = count;
      _error = null;
    } catch (error) {
      if (_disposed) return;
      _error = _messageFor(error);
    } finally {
      if (!_disposed) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  @override
  Future<void> loadMoreNotifications() async {
    if (_disposed || _loading || !_hasMore) return;
    if (_client.auth.currentUser == null) return;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final rows = await _fetchPage(reset: false);
      if (_disposed) return;
      final known = _items.map((n) => n.id).toSet();
      for (final row in rows) {
        if (known.contains(row.id)) continue;
        _items.add(row);
      }
      _hasMore = rows.length >= _pageSize;
      _error = null;
    } catch (error) {
      if (_disposed) return;
      _error = _messageFor(error);
    } finally {
      if (!_disposed) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  @override
  Future<AppNotification?> notificationById(String id) async {
    try {
      final data = await _client.rpc(
        'get_notification',
        params: {'p_notification_id': id},
      );
      if (data is! Map) return null;
      final row = Map<String, dynamic>.from(data);
      if (row['id'] == null) return null;
      return _fromRow(row);
    } catch (_) {
      // A notification that is not this member's is simply absent.
      return null;
    }
  }

  // ── Writes ───────────────────────────────────────────────────────────────

  /// Marks one notification read.
  ///
  /// The row is painted as read straight away and the server call follows, so
  /// the badge never waits for the network. A failure leaves the row unread
  /// in the server and the next reload restores the truth.
  @override
  void markNotificationRead(String id) {
    final index = _items.indexWhere((n) => n.id == id);
    if (index < 0) return;
    final current = _items[index];
    if (current.read) return;

    _items[index] = _copyWith(current, read: true);
    if (_unread > 0) _unread -= 1;
    notifyListeners();

    unawaited(
      _client
          .rpc('mark_notification_read', params: {'p_notification_id': id})
          .then((_) => _refreshUnread())
          .catchError((Object _) {}),
    );
  }

  @override
  void markAllNotificationsRead() {
    var changed = false;
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].read) continue;
      _items[i] = _copyWith(_items[i], read: true);
      changed = true;
    }
    if (!changed && _unread == 0) return;
    _unread = 0;
    notifyListeners();

    unawaited(
      _client
          .rpc('mark_all_notifications_read')
          .then((_) => _refreshUnread())
          .catchError((Object _) {}),
    );
  }

  @override
  Future<void> updateNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    final previous = _preferences;
    _preferences = preferences;
    notifyListeners();
    try {
      await _client.rpc(
        'update_notification_preferences',
        params: {
          'p_match_activity': preferences.matchActivity,
          'p_tournament_updates': preferences.tournamentUpdates,
          'p_team_activity': preferences.teamActivity,
          'p_scorer_assignments': preferences.scorerAssignments,
          'p_platform_announcements': preferences.platformAnnouncements,
        },
      );
    } catch (error) {
      // The switch did not stick, so the old state comes back.
      _preferences = previous;
      _error = _messageFor(error);
      notifyListeners();
    }
  }

  /// Reads the stored preferences. Called when the preferences screen opens.
  @override
  Future<void> loadNotificationPreferences() async {
    try {
      final data = await _client.rpc('get_notification_preferences');
      if (data is! Map) return;
      final row = Map<String, dynamic>.from(data);
      if (row['profile_id'] == null) return;
      _preferences = NotificationPreferences.fromJson(row);
      notifyListeners();
    } catch (error) {
      _error = _messageFor(error);
      notifyListeners();
    }
  }

  // ── Realtime ─────────────────────────────────────────────────────────────

  @override
  Future<void> watchNotifications() async {
    if (_client.auth.currentUser == null) return;
    await _startWatching();
  }

  @override
  Future<void> unwatchNotifications() async {
    await _stopWatching();
  }

  /// Subscribes to the member's own rows.
  ///
  /// The table policy scopes the stream to the recipient, so a second member's
  /// notification is never even delivered to this socket. A new row and a
  /// changed row both trigger an authoritative reload, which keeps the badge,
  /// the list and the server in step without a second ordering rule on the
  /// client.
  Future<void> _startWatching() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    if (_channel != null && _channelUserId == userId) {
      await syncNotifications();
      return;
    }
    await _stopWatching();

    _channelUserId = userId;
    final channel = _client
        .channel('notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: userId,
          ),
          callback: (_) => unawaited(_onServerChange()),
        );
    _channel = channel;
    channel.subscribe((status, _) {
      // A fresh subscription means the socket was (re)established. The server
      // is the authority, so the inbox is read again from the top. Anything
      // that arrived while the socket was down is picked up by that read.
      if (status == RealtimeSubscribeStatus.subscribed) {
        unawaited(syncNotifications());
      }
    });
  }

  Future<void> _stopWatching() async {
    final channel = _channel;
    _channel = null;
    _channelUserId = null;
    if (channel != null) {
      await channel.unsubscribe();
    }
  }

  /// A row changed on the server. The list is refreshed from the top so the
  /// order, the badge and the read state all come from one place.
  Future<void> _onServerChange() async {
    if (_disposed) return;
    await syncNotifications();
  }

  void _handleAuthState(AuthState state) {
    if (_disposed) return;
    switch (state.event) {
      // The first look at storage counts as a sign-in when a session was
      // restored, and as a sign-out when there was nothing to restore.
      case AuthChangeEvent.initialSession:
      case AuthChangeEvent.signedIn:
        if (state.session == null) {
          unawaited(_handleSignOut());
          return;
        }
        unawaited(_startWatching());
      // Signing out empties the inbox.
      case AuthChangeEvent.signedOut:
        unawaited(_handleSignOut());
      case AuthChangeEvent.tokenRefreshed:
      case AuthChangeEvent.userUpdated:
      case AuthChangeEvent.passwordRecovery:
        break;
      // Anything else the SDK may report, an account deletion included, also
      // leaves the inbox unreadable, so it is cleared rather than left stale.
      default:
        if (state.session == null) {
          unawaited(_handleSignOut());
        }
        break;
    }
  }

  /// Signing out closes the channel and empties the inbox, so the next member
  /// at this device never sees the previous member's notifications.
  Future<void> _handleSignOut() async {
    await _stopWatching();
    _items.clear();
    _unread = 0;
    _hasMore = false;
    _before = null;
    _beforeId = null;
    _error = null;
    notifyListeners();
  }

  // ── Internals ────────────────────────────────────────────────────────────

  Future<List<AppNotification>> _fetchPage({required bool reset}) async {
    final data = await _client.rpc(
      'list_my_notifications',
      params: {
        'p_limit': _pageSize,
        'p_before': reset ? null : _before?.toIso8601String(),
        'p_before_id': reset ? null : _beforeId,
        'p_unread_only': false,
        'p_category': null,
      },
    );
    final rows = <AppNotification>[];
    if (data is List) {
      for (final entry in data) {
        if (entry is Map) rows.add(_fromRow(Map<String, dynamic>.from(entry)));
      }
    }
    if (rows.isNotEmpty) {
      final last = rows.last;
      _before = last.at;
      _beforeId = last.id;
    }
    _hasMore = rows.length >= _pageSize;
    return rows;
  }

  Future<int> _fetchUnreadCount() async {
    final data = await _client.rpc('my_unread_notification_count');
    if (data is num) return data.toInt();
    if (data is List && data.isNotEmpty && data.first is num) {
      return (data.first as num).toInt();
    }
    return 0;
  }

  Future<void> _refreshUnread() async {
    try {
      final count = await _fetchUnreadCount();
      if (_disposed) return;
      _unread = count;
      notifyListeners();
    } catch (_) {
      // The badge keeps its last known value until the next reload.
    }
  }

  AppNotification _fromRow(Map<String, dynamic> row) {
    final type = (row['type'] as String?) ?? '';
    return AppNotification(
      id: (row['id'] as String?) ?? '',
      accountId: (row['recipient_id'] as String?) ?? '',
      kind: NotificationKindX.fromServerType(type),
      title: (row['title'] as String?) ?? '',
      body: (row['body'] as String?) ?? '',
      read: row['read_at'] != null,
      at:
          DateTime.tryParse((row['created_at'] as String?) ?? '') ??
          DateTime.now(),
      type: type,
      entityType: row['entity_type'] as String?,
      entityId: row['entity_id'] as String?,
      payload: Map<String, dynamic>.from(row['payload'] as Map? ?? const {}),
      actorId: row['actor_id'] as String?,
      expiresAt: DateTime.tryParse((row['expires_at'] as String?) ?? ''),
    );
  }

  AppNotification _copyWith(AppNotification source, {required bool read}) {
    return AppNotification(
      id: source.id,
      accountId: source.accountId,
      kind: source.kind,
      title: source.title,
      body: source.body,
      route: source.route,
      read: read,
      at: source.at,
      type: source.type,
      entityType: source.entityType,
      entityId: source.entityId,
      payload: source.payload,
      actorId: source.actorId,
      expiresAt: source.expiresAt,
    );
  }

  /// The server refuses a request with a stable identifier; the member sees a
  /// sentence instead.
  String _messageFor(Object error) {
    if (error is PostgrestException) {
      if (error.code == '28000') {
        return 'Sign in again to see your notifications.';
      }
      if (error.code == '42501') {
        return 'That notification is not yours to open.';
      }
      final message = error.message;
      if (message.contains('not_authenticated')) {
        return 'Sign in again to see your notifications.';
      }
      if (error.code == 'PGRST116' || message.contains('No rows found')) {
        return 'That notification is no longer available.';
      }
    }
    return 'Notifications could not be loaded. Pull to refresh.';
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_authState.cancel());
    unawaited(_stopWatching());
    super.dispose();
  }
}
