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

/// Sportika Activity Center.
///
/// Displays the existing notification feed with a premium sports-oriented
/// presentation. All notification data and actions remain controller-driven.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ScrollController _scroll = ScrollController();

  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();

    _scroll.addListener(_onScroll);

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

  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore) return;

    final position = _scroll.position;
    final state = context.read<NotificationsController>();

    if (!state.hasMore || state.loading) return;

    if (position.extentAfter < 280) {
      _loadMore(state);
    }
  }

  Future<void> _loadMore(NotificationsController state) async {
    if (_loadingMore || state.loading || !state.hasMore) return;

    _loadingMore = true;

    try {
      await state.loadMore();
    } finally {
      _loadingMore = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NotificationsController>();

    return Scaffold(
      appBar: sportikaAppBar(
        'Notifications',
        subtitle: state.unreadCount > 0
            ? '${state.unreadCount} unread updates'
            : 'You are up to date',
        actions: [
          IconButton(
            tooltip: 'Notification preferences',
            onPressed: () =>
                pushRoute(context, AppRoute.notificationPreferences),
            icon: const Icon(
              Icons.tune_rounded,
              color: SportikaColors.textBody,
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _buildBody(context, state),
    );
  }

  Widget _buildBody(BuildContext context, NotificationsController state) {
    final width = MediaQuery.sizeOf(context).width;

    final inset = width > 760 ? (width - 720) / 2 : 16.0;

    if (state.loading && state.myNotifications.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(inset, 20, inset, 0),
        child: const LoadingSkeleton(
          rows: 4,
          rowHeight: 90,
          label: 'Loading notifications',
        ),
      );
    }

    if (state.error != null && state.myNotifications.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(inset, 20, inset, 0),
        child: ErrorState(
          title: 'Notifications did not load',
          message: state.error,
          onRetry: state.refresh,
        ),
      );
    }

    final groups = state.groupedNotifications;

    return RefreshIndicator(
      onRefresh: state.refresh,
      color: SportikaColors.mint,
      backgroundColor: SportikaColors.surface,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // =====================================
          // ACTIVITY HEADER
          // =====================================

          SliverPadding(
            padding: EdgeInsets.fromLTRB(inset, 16, inset, 0),
            sliver: SliverToBoxAdapter(
              child: _ActivityHeader(unread: state.unreadCount),
            ),
          ),

          // =====================================
          // FILTERS
          // =====================================
          SliverPadding(
            padding: EdgeInsets.fromLTRB(inset, 18, inset, 12),
            sliver: SliverToBoxAdapter(child: _filters(state)),
          ),

          // =====================================
          // ERROR BANNER
          // =====================================
          if (state.error != null)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(inset, 0, inset, 14),
              sliver: SliverToBoxAdapter(
                child: _RetryNotice(onRetry: state.refresh),
              ),
            ),

          // =====================================
          // EMPTY STATE
          // =====================================
          if (state.visibleNotifications.isEmpty)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(inset, 36, inset, 36),
              sliver: SliverToBoxAdapter(
                child: EmptyState(
                  title: state.unreadOnly ? 'All caught up' : 'No activity yet',
                  body: state.unreadOnly
                      ? 'You have no unread notifications. Switch to All to revisit previous updates.'
                      : 'Match invitations, tournament activity, scoring assignments and results will appear here.',
                  icon: state.unreadOnly
                      ? Icons.done_all_rounded
                      : Icons.notifications_none_rounded,
                ),
              ),
            ),

          // =====================================
          // GROUPED NOTIFICATIONS
          // =====================================
          for (final group in NotificationGroup.values)
            if ((groups[group]?.isNotEmpty ?? false)) ...[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(inset, 12, inset, 12),
                sliver: SliverToBoxAdapter(
                  child: _GroupHeader(
                    label: group.label,
                    count: groups[group]!.length,
                  ),
                ),
              ),

              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: inset),
                sliver: SliverList.separated(
                  itemCount: groups[group]!.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = groups[group]![index];

                    return _NotificationTile(
                      key: ValueKey(item.id),
                      notification: item,
                    );
                  },
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 12)),
            ],

          SliverToBoxAdapter(child: _footer(state)),
        ],
      ),
    );
  }

  Widget _filters(NotificationsController state) {
    return Row(
      children: [
        _ActivityFilter(
          label: 'All',
          selected: !state.unreadOnly,
          onTap: () => state.setUnreadOnly(false),
        ),

        const SizedBox(width: 8),

        _ActivityFilter(
          label: state.unreadCount > 0
              ? 'Unread ${state.unreadCount}'
              : 'Unread',
          selected: state.unreadOnly,
          onTap: () => state.setUnreadOnly(true),
        ),

        const Spacer(),

        if (state.unreadCount > 0)
          TextButton(
            onPressed: state.markAllNotificationsRead,
            child: Text(
              'Mark all read',
              style: SportikaType.caption.copyWith(
                color: SportikaColors.mint,
                fontWeight: SportikaFontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _footer(NotificationsController state) {
    if (state.loading && state.hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: SportikaColors.mint,
            ),
          ),
        ),
      );
    }

    if (state.hasMore) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: TextButton.icon(
            onPressed: () => _loadMore(state),
            icon: const Icon(Icons.expand_more_rounded),
            label: const Text('Load older activity'),
          ),
        ),
      );
    }

    return const SizedBox(height: 36);
  }
}

// ============================================================
// ACTIVITY HEADER
// ============================================================

class _ActivityHeader extends StatelessWidget {
  const _ActivityHeader({required this.unread});

  final int unread;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: SportikaColors.blueBright.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(SportikaRadius.md),
            ),
            child: const Icon(
              Icons.notifications_active_outlined,
              color: SportikaColors.blueBright,
              size: 27,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YOUR SPORTIKA ACTIVITY',
                  style: SportikaType.micro.copyWith(
                    color: SportikaColors.mint,
                    letterSpacing: 1.1,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  unread > 0 ? 'Stay in the game' : 'You are all caught up',
                  style: SportikaType.bodyStrong.copyWith(fontSize: 17),
                ),

                const SizedBox(height: 4),

                Text(
                  unread > 0
                      ? '$unread ${unread == 1 ? 'update needs' : 'updates need'} your attention.'
                      : 'Your latest match and team activity lives here.',
                  style: SportikaType.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// FILTER
// ============================================================

class _ActivityFilter extends StatelessWidget {
  const _ActivityFilter({
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
      button: true,
      selected: selected,
      child: Material(
        color: selected ? SportikaColors.blueSubtle : SportikaColors.surfaceAlt,
        borderRadius: BorderRadius.circular(SportikaRadius.pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SportikaRadius.pill),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              style: SportikaType.caption.copyWith(
                fontWeight: SportikaFontWeight.bold,
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

// ============================================================
// GROUP HEADER
// ============================================================

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: SportikaType.label.copyWith(
              color: SportikaColors.textMuted,
              letterSpacing: 1,
            ),
          ),
        ),
        Text(
          '$count',
          style: SportikaType.micro.copyWith(color: SportikaColors.textDim),
        ),
      ],
    );
  }
}

// ============================================================
// NOTIFICATION TILE
// ============================================================

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    super.key,
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
    final controller = context.read<NotificationsController>();
    final tone = _tone(notification.kind);
    final unread = !notification.read;

    return Semantics(
      container: true,
      label: unread
          ? 'Unread notification: ${notification.title}'
          : notification.title,
      child: SurfaceCard(
        onTap: () {
          final target = navigationContext ?? context;

          controller.markNotificationRead(notification.id);

          beforeOpen?.call();

          _navigate(target);
        },
        borderColor: unread
            ? tone.withValues(alpha: 0.45)
            : SportikaColors.borderSubtle,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 14,
          vertical: compact ? 11 : 14,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // CATEGORY ICON
            Container(
              width: compact ? 36 : 42,
              height: compact ? 36 : 42,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(SportikaRadius.sm),
              ),
              child: Icon(
                _icon(notification.kind),
                size: compact ? 18 : 20,
                color: tone,
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          maxLines: compact ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: SportikaType.bodyStrong.copyWith(
                            fontSize: compact ? 12.5 : 13.5,
                            height: 1.3,
                            fontWeight: unread
                                ? SportikaFontWeight.extraBold
                                : SportikaFontWeight.semibold,
                            color: unread
                                ? SportikaColors.text
                                : SportikaColors.textBody,
                          ),
                        ),
                      ),

                      if (unread) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(top: 5),
                          decoration: const BoxDecoration(
                            color: SportikaColors.mint,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 5),

                  Text(
                    notification.body,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: SportikaType.caption.copyWith(
                      height: 1.45,
                      color: SportikaColors.textMuted,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _category(notification.kind),
                          style: SportikaType.micro.copyWith(
                            color: tone,
                            fontWeight: SportikaFontWeight.bold,
                          ),
                        ),
                      ),

                      Text(
                        timeAgo(notification.at),
                        style: SportikaType.micro.copyWith(
                          color: SportikaColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigate(BuildContext context) async {
    if (!context.mounted) return;

    final result = await openNotification(context, notification);

    if (!context.mounted) return;

    if (result == NotificationOpenResult.unavailable) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('That notification is no longer available.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  String _category(NotificationKind kind) => switch (kind) {
    NotificationKind.entryDecision ||
    NotificationKind.tournamentUpdate => 'TOURNAMENT',
    NotificationKind.fixtureChange ||
    NotificationKind.matchInvite ||
    NotificationKind.matchUpdate ||
    NotificationKind.matchReminder => 'MATCH',
    NotificationKind.scorerAssignment => 'SCORING',
    NotificationKind.resultSubmitted ||
    NotificationKind.resultPublished ||
    NotificationKind.resultCorrected => 'RESULT',
    NotificationKind.dispute => 'DISPUTE',
    NotificationKind.teamUpdate => 'TEAM',
    NotificationKind.accountUpdate => 'ACCOUNT',
    NotificationKind.platformUpdate => 'SPORTIKA',
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

// ============================================================
// PREMIUM NOTIFICATION BELL
// ============================================================

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<NotificationsController>().unreadCount;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: SportikaColors.surfaceAlt,
            borderRadius: BorderRadius.circular(SportikaRadius.control),
            child: Tooltip(
              message: 'Notifications',
              child: Semantics(
                button: true,
                label: unread > 0
                    ? 'Notifications, $unread unread'
                    : 'Notifications',
                child: InkWell(
                  onTap: () => showNotificationPreview(context),
                  borderRadius: BorderRadius.circular(SportikaRadius.control),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        SportikaRadius.control,
                      ),
                      border: Border.all(
                        color: unread > 0
                            ? SportikaColors.blueBright.withValues(alpha: 0.45)
                            : SportikaColors.border,
                      ),
                    ),
                    child: Icon(
                      unread > 0
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_none_rounded,
                      size: 21,
                      color: unread > 0
                          ? SportikaColors.mint
                          : SportikaColors.textBody,
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

// ============================================================
// RETRY NOTICE
// ============================================================

class _RetryNotice extends StatelessWidget {
  const _RetryNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            color: SportikaColors.gold,
            size: 19,
          ),

          const SizedBox(width: 10),

          const Expanded(
            child: Text(
              'Some updates could not load.',
              style: SportikaType.caption,
            ),
          ),

          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

// ============================================================
// NOTIFICATION PREVIEW
// ============================================================

Future<void> showNotificationPreview(BuildContext context) async {
  final controller = context.read<NotificationsController>();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: SportikaColors.page,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(SportikaRadius.xl),
      ),
    ),
    builder: (_) => ChangeNotifierProvider.value(
      value: controller,
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
      if (!mounted) return;

      context.read<NotificationsController>().start();
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
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // HEADER
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Activity', style: SportikaType.display(24)),

                        const SizedBox(height: 3),

                        Text(
                          state.unreadCount > 0
                              ? '${state.unreadCount} unread updates'
                              : 'You are up to date',
                          style: SportikaType.caption,
                        ),
                      ],
                    ),
                  ),

                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // MARK ALL READ
              if (state.unreadCount > 0)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: state.markAllNotificationsRead,
                    icon: const Icon(Icons.done_all_rounded, size: 17),
                    label: const Text('Mark all read'),
                  ),
                ),

              // NOTIFICATION LIST
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
                          rowHeight: 74,
                          label: 'Loading notifications',
                        )
                      else if (items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: EmptyState(
                            title: 'Nothing yet',
                            body: 'Your match, team and tournament activity will appear here.',
                            icon: Icons.notifications_none_rounded,
                          ),
                        )
                      else
                        for (final item in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _NotificationTile(
                              key: ValueKey(item.id),
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

              const SizedBox(height: 12),

              // VIEW ALL
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

                    if (target.mounted) {
                      pushRoute(target, AppRoute.notifications);
                    }
                  },
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('View all notifications'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
