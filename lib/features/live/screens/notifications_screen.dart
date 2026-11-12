import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/state/app_state.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/shared/widgets/widgets.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final items = state.myNotifications;

    return Scaffold(
      appBar: sportikaAppBar(
        'Notifications',
        actions: [
          if (state.unreadCount > 0)
            TextButton(
              onPressed: state.markAllNotificationsRead,
              child: const Text(
                'Mark all read',
                style: TextStyle(fontSize: 12),
              ),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: items.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: EmptyState(
                title: 'Nothing yet',
                body:
                    'Entry decisions, fixture changes and published results will '
                    'arrive here.',
                icon: Icons.notifications_none,
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) =>
                  _NotificationTile(notification: items[i]),
            ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final tone = _tone(notification.kind);

    return SurfaceCard(
      onTap: () {
        state.markNotificationRead(notification.id);
        openNotificationRoute(context, notification.route);
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
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: notification.read
                              ? FontWeight.w600
                              : FontWeight.w800,
                          color: SportikaColors.text,
                        ),
                      ),
                    ),
                    if (!notification.read)
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: tone,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  notification.body,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: SportikaColors.textMuted,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  timeAgo(notification.at),
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

  Color _tone(NotificationKind kind) => switch (kind) {
    NotificationKind.entryDecision => SportikaColors.blueBright,
    NotificationKind.fixtureChange => SportikaColors.gold,
    NotificationKind.scorerAssignment => SportikaColors.mint,
    NotificationKind.resultSubmitted => SportikaColors.gold,
    NotificationKind.resultPublished => SportikaColors.mint,
    NotificationKind.resultCorrected => SportikaColors.gold,
    NotificationKind.dispute => SportikaColors.danger,
  };

  IconData _icon(NotificationKind kind) => switch (kind) {
    NotificationKind.entryDecision => Icons.how_to_reg_outlined,
    NotificationKind.fixtureChange => Icons.event_outlined,
    NotificationKind.scorerAssignment => Icons.sports_score,
    NotificationKind.resultSubmitted => Icons.hourglass_top,
    NotificationKind.resultPublished => Icons.verified_outlined,
    NotificationKind.resultCorrected => Icons.edit_note,
    NotificationKind.dispute => Icons.gavel,
  };
}

/// Bell with an unread count, used in every root tab header.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<AppState>().unreadCount;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: SportikaColors.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => pushScreen(context, const NotificationsScreen()),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 38,
                width: 38,
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
          Positioned(right: -3, top: -4, child: AppBadge(count: unread)),
        ],
      ),
    );
  }
}
