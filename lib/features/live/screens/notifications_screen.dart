import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/core/state/notifications_controller.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/shared/navigation/notification_links.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// The in-app inbox.
///
/// One screen for every family of message: invitations, schedule changes,
/// results, disputes, squad activity and account notices. It reads only from
/// [NotificationsController], so the same screen draws the device inbox and
/// the server inbox without knowing which one it is talking to.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // The live channel is shared with the header bell, so it stays open for
    // the whole session. This only makes sure it is already running.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NotificationsController>().start();
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// Pulls the next page in when the member reaches the end of the list.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      context.read<NotificationsController>().loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NotificationsController>();

    return Scaffold(
      appBar: sportikaAppBar(
        'Notifications',
        subtitle: state.unreadCount > 0
            ? '${state.unreadCount} unread'
            : 'You are up to date',
        actions: [
          IconButton(
            tooltip: 'Notification settings',
            onPressed: () =>
                pushRoute(context, AppRoute.notificationPreferences),
            icon: const Icon(Icons.tune, size: 20),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _body(context, state),
    );
  }

  Widget _body(BuildContext context, NotificationsController state) {
    if (state.loading && state.myNotifications.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: LoadingSkeleton(
          rows: 4,
          rowHeight: 82,
          label: 'Loading notifications',
        ),
      );
    }

    final error = state.error;
    if (error != null && state.myNotifications.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: ErrorState(
          title: 'Notifications did not load',
          message: error,
          onRetry: state.refresh,
        ),
      );
    }

    final groups = state.groupedNotifications;
    final page = MediaQuery.sizeOf(context).width > 760
        ? (MediaQuery.sizeOf(context).width - 720) / 2
        : 16.0;
    return RefreshIndicator(
      onRefresh: state.refresh,
      color: SportikaColors.mint,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: page - 16),
            sliver: SliverToBoxAdapter(child: _filters(state)),
          ),
          if (state.error != null)
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: page),
              sliver: SliverToBoxAdapter(
                child: _RetryNotice(onRetry: state.refresh),
              ),
            ),
          if (state.visibleNotifications.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 48,
                  horizontal: 24,
                ),
                child: EmptyState(
                  title: state.unreadOnly
                      ? 'You are all caught up'
                      : 'Nothing yet',
                  body: state.unreadOnly
                      ? 'Switch to All to revisit your match and team updates.'
                      : 'Match invitations, team updates and results will arrive here.',
                  icon: state.unreadOnly
                      ? Icons.done_all
                      : Icons.notifications_none,
                ),
              ),
            ),
          for (final group in NotificationGroup.values)
            if (groups[group]!.isNotEmpty) ...[
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: page - 16),
                sliver: SliverToBoxAdapter(child: _groupHeader(group)),
              ),
              SliverList.separated(
                itemCount: groups[group]!.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) => Padding(
                  padding: EdgeInsets.symmetric(horizontal: page),
                  child: _NotificationTile(notification: groups[group]![i]),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ],
          SliverToBoxAdapter(child: _footer(state)),
        ],
      ),
    );
  }

  /// The two filters, with the unread count on the one that filters.
  Widget _filters(NotificationsController state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _FilterChip(
            label: 'All',
            selected: !state.unreadOnly,
            onTap: () => state.setUnreadOnly(false),
          ),
          _FilterChip(
            label: state.unreadCount > 0
                ? 'Unread · ${state.unreadCount}'
                : 'Unread',
            selected: state.unreadOnly,
            onTap: () => state.setUnreadOnly(true),
          ),
          if (state.unreadCount > 0)
            TextButton(
              onPressed: state.markAllNotificationsRead,
              child: const Text(
                'Mark all read',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  Widget _groupHeader(NotificationGroup group) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Text(
        group.label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: SportikaColors.textDim,
        ),
      ),
    );
  }

  /// The end of the list: a spinner while another page loads, or the hint
  /// that there is nothing older.
  Widget _footer(NotificationsController state) {
    if (state.loading && state.hasMore) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 18, 16, 26),
        child: Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: SportikaColors.blueBright,
            ),
          ),
        ),
      );
    }
    if (state.hasMore) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: TextButton.icon(
            onPressed: state.loadMore,
            icon: const Icon(Icons.expand_more_rounded),
            label: const Text('Load older notifications'),
          ),
        ),
      );
    }
    return const SizedBox(height: 28);
  }
}

/// One filter button.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? SportikaColors.blueSubtle : SportikaColors.surfaceAlt,
        borderRadius: BorderRadius.circular(SportikaRadius.pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SportikaRadius.pill),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SportikaRadius.pill),
              border: Border.all(
                color: selected
                    ? SportikaColors.blueBright
                    : SportikaColors.border,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected
                    ? SportikaColors.text
                    : SportikaColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One message in the inbox.
class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    this.compact = false,
    this.navigationContext,
    this.beforeOpen,
  });

  final AppNotification notification;
  final bool compact;
  final BuildContext? navigationContext;
  final VoidCallback? beforeOpen;

  @override
  Widget build(BuildContext context) {
    final state = context.read<NotificationsController>();
    final tone = _tone(notification.kind);

    return SurfaceCard(
      onTap: () {
        final target = navigationContext ?? context;
        beforeOpen?.call();
        _open(target, state);
      },
      borderColor: notification.read
          ? SportikaColors.border
          : tone.withValues(alpha: 0.4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 34,
            width: 34,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_icon(notification.kind), size: 17, color: tone),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        notification.title,
                        maxLines: compact ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.3,
                          fontWeight: notification.read
                              ? FontWeight.w600
                              : FontWeight.w800,
                          color: SportikaColors.text,
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: notification.read
                          ? const SizedBox.shrink()
                          : Container(
                              key: const ValueKey('unread'),
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: tone,
                                shape: BoxShape.circle,
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  notification.body,
                  maxLines: compact ? 1 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: SportikaColors.textMuted,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${_category(notification.kind)} · ${timeAgo(notification.at)}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: SportikaColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Marks the message read and opens where it points.
  ///
  /// A message about something that no longer exists, or that belongs to
  /// somebody else, says so instead of opening a screen the member may not
  /// see.
  Future<void> _open(
    BuildContext context,
    NotificationsController state,
  ) async {
    state.markNotificationRead(notification.id);
    final result = await openNotification(context, notification);
    if (result != NotificationOpenResult.unavailable) return;
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('That is no longer available.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  String _category(NotificationKind kind) => switch (kind) {
    NotificationKind.entryDecision ||
    NotificationKind.tournamentUpdate => 'Tournaments',
    NotificationKind.fixtureChange ||
    NotificationKind.matchInvite ||
    NotificationKind.matchUpdate ||
    NotificationKind.matchReminder => 'Matches',
    NotificationKind.scorerAssignment => 'Scorer assignment',
    NotificationKind.resultSubmitted ||
    NotificationKind.resultPublished ||
    NotificationKind.resultCorrected ||
    NotificationKind.dispute => 'Results',
    NotificationKind.teamUpdate => 'Teams',
    NotificationKind.accountUpdate ||
    NotificationKind.platformUpdate => 'System',
  };

  Color _tone(NotificationKind kind) => switch (kind) {
    NotificationKind.entryDecision => SportikaColors.blueBright,
    NotificationKind.fixtureChange => SportikaColors.gold,
    NotificationKind.scorerAssignment => SportikaColors.mint,
    NotificationKind.resultSubmitted => SportikaColors.gold,
    NotificationKind.resultPublished => SportikaColors.mint,
    NotificationKind.resultCorrected => SportikaColors.gold,
    NotificationKind.dispute => SportikaColors.danger,
    NotificationKind.matchInvite => SportikaColors.blueBright,
    NotificationKind.matchUpdate => SportikaColors.blueBright,
    NotificationKind.matchReminder => SportikaColors.gold,
    NotificationKind.tournamentUpdate => SportikaColors.blue,
    NotificationKind.teamUpdate => SportikaColors.mint,
    NotificationKind.accountUpdate => SportikaColors.gold,
    NotificationKind.platformUpdate => SportikaColors.textDim,
  };

  IconData _icon(NotificationKind kind) => switch (kind) {
    NotificationKind.entryDecision => Icons.how_to_reg_outlined,
    NotificationKind.fixtureChange => Icons.event_outlined,
    NotificationKind.scorerAssignment => Icons.sports_score,
    NotificationKind.resultSubmitted => Icons.hourglass_top,
    NotificationKind.resultPublished => Icons.verified_outlined,
    NotificationKind.resultCorrected => Icons.edit_note,
    NotificationKind.dispute => Icons.gavel,
    NotificationKind.matchInvite => Icons.person_add_alt_1_outlined,
    NotificationKind.matchUpdate => Icons.sports_outlined,
    NotificationKind.matchReminder => Icons.alarm_outlined,
    NotificationKind.tournamentUpdate => Icons.emoji_events_outlined,
    NotificationKind.teamUpdate => Icons.groups_outlined,
    NotificationKind.accountUpdate => Icons.shield_outlined,
    NotificationKind.platformUpdate => Icons.campaign_outlined,
  };
}

/// Bell with an unread count, used in every root tab header.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<NotificationsController>().unreadCount;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: SportikaColors.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            child: Tooltip(
              message: 'Notifications',
              child: Semantics(
                button: true,
                label: unread > 0
                    ? 'Notifications, $unread unread'
                    : 'Notifications',
                child: InkWell(
                  onTap: () => showNotificationPreview(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 44,
                    width: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: SportikaColors.border),
                    ),
                    child: const Icon(
                      Icons.notifications_none,
                      size: 19,
                      color: SportikaColors.textBody,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (unread > 0)
            Positioned(right: -3, top: -4, child: AppBadge(count: unread)),
        ],
      ),
    );
  }
}

class _RetryNotice extends StatelessWidget {
  const _RetryNotice({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(
        Icons.cloud_off_outlined,
        size: 18,
        color: SportikaColors.textMuted,
      ),
      const SizedBox(width: 8),
      const Expanded(
        child: Text(
          'Updates couldn’t load. Try again.',
          style: TextStyle(fontSize: 12, color: SportikaColors.textMuted),
        ),
      ),
      TextButton(onPressed: onRetry, child: const Text('Retry')),
    ],
  );
}

/// The preview shares the session controller, including live unread updates.
Future<void> showNotificationPreview(BuildContext context) async {
  final state = context.read<NotificationsController>();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: SportikaColors.page,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => ChangeNotifierProvider.value(
      value: state,
      child: _NotificationPreview(navigationContext: context),
    ),
  );
}

class _NotificationPreview extends StatefulWidget {
  const _NotificationPreview({required this.navigationContext});
  final BuildContext navigationContext;
  @override
  State<_NotificationPreview> createState() => _NotificationPreviewState();
}

class _NotificationPreviewState extends State<_NotificationPreview> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotificationsController>().start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NotificationsController>();
    final items = state.myNotifications.take(5).toList();
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .78,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        fontFamily: 'Barlow Condensed',
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close notifications',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Align(
                        key: ValueKey(state.unreadCount),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          state.unreadCount > 0
                              ? '${state.unreadCount} unread'
                              : 'You are up to date',
                          style: const TextStyle(
                            fontSize: 12,
                            color: SportikaColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: state.unreadCount > 0
                        ? state.markAllNotificationsRead
                        : null,
                    child: const Text(
                      'Mark all read',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Flexible(
                child: RefreshIndicator(
                  onRefresh: state.refresh,
                  color: SportikaColors.mint,
                  child: ListView(
                    shrinkWrap: true,
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      if (state.error != null)
                        _RetryNotice(onRetry: state.refresh),
                      if (state.loading && items.isEmpty)
                        const LoadingSkeleton(
                          rows: 4,
                          rowHeight: 68,
                          label: 'Loading notifications',
                        )
                      else if (items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: EmptyState(
                            title: 'Nothing yet',
                            body: 'Your match, team and tournament updates will appear here.',
                            icon: Icons.notifications_none_rounded,
                          ),
                        )
                      else
                        for (final item in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _NotificationTile(
                              notification: item,
                              compact: true,
                              navigationContext: widget.navigationContext,
                              beforeOpen: () => Navigator.pop(context),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: SportikaColors.mint,
                    foregroundColor: SportikaColors.deepest,
                  ),
                  onPressed: () {
                    final target = widget.navigationContext;
                    state.setUnreadOnly(false);
                    Navigator.pop(context);
                    pushRoute(target, AppRoute.notifications);
                  },
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text(
                    'View all',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
