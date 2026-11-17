import 'package:flutter/material.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/shared/navigation/navigation.dart';

String greetingEyebrow() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'GOOD MORNING';
  if (hour < 17) return 'GOOD AFTERNOON';
  return 'GOOD EVENING';
}

/// Editorial discovery banner with the featured event's photograph first,
/// falling back to the same sport photography when a remote banner fails.
class HomeHero extends StatelessWidget {
  const HomeHero({
    super.key,
    required this.sport,
    required this.pagePadding,
    this.imageUrl,
    this.featuredTournament,
  });

  final Sport? sport;
  final double pagePadding;
  final String? imageUrl;

  /// Real parent-provided context, independent of the banner's URL.
  final Tournament? featuredTournament;

  Widget _backdrop(double height) {
    final fallback = SportPhoto(
      sport: sport ?? Sport.cricket,
      height: height,
      radius: 0,
    );
    final url = imageUrl;
    if (url == null || url.isEmpty) return fallback;
    return Image.network(
      url,
      fit: BoxFit.cover,
      height: height,
      errorBuilder: (_, _, _) => fallback,
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = featuredTournament;
    final title = event?.name.trim();
    final headline = title != null && title.isNotEmpty
        ? title
        : 'Find your next match';
    final supporting = event == null
        ? 'Explore ${sport?.label ?? 'sports'} matches and tournaments.'
        : [
            event.sport.label,
            dayLabel(event.startsAt.toLocal()),
            if (event.city.trim().isNotEmpty) event.city.trim(),
          ].join(' · ');
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          event == null
              ? 'DISCOVER SPORTIKA'
              : event.isDemo
              ? 'FEATURED TOURNAMENT · DEMO'
              : 'FEATURED TOURNAMENT',
          style: SportikaType.micro,
        ),
        const SizedBox(height: SportikaSpacing.sm),
        Text(headline, style: SportikaType.title),
      ],
    );
    final action = FilledButton.icon(
      onPressed: () => openMatchTab(context, section: 5),
      icon: const Icon(Icons.arrow_forward_rounded, size: SportikaSpacing.lg),
      label: const Text('Find a match'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(
          kMinInteractiveDimension,
          kMinInteractiveDimension,
        ),
        backgroundColor: SportikaColors.mint,
        foregroundColor: SportikaColors.deepest,
        textStyle: SportikaType.action,
        padding: const EdgeInsets.symmetric(
          horizontal: SportikaSpacing.md,
          vertical: SportikaSpacing.sm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SportikaRadius.sm),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(SportikaRadius.lg),
      child: ColoredBox(
        color: SportikaColors.surface,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final wide =
                constraints.maxWidth >= SportikaSpacing.xl * 16 * scale;
            final roomyText =
                scale > 1.3 || constraints.maxWidth < SportikaSpacing.xl * 10;
            Widget photo(double height) => ClipRRect(
              borderRadius: BorderRadius.circular(SportikaRadius.sm),
              child: SizedBox(height: height, child: _backdrop(height)),
            );
            final copy = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (wide || roomyText)
                  heading
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: heading),
                      const SizedBox(width: SportikaSpacing.md),
                      SizedBox(
                        width: SportikaSpacing.xl * 3,
                        child: photo(SportikaSpacing.xl * 3),
                      ),
                    ],
                  ),
                const SizedBox(height: SportikaSpacing.sm),
                Text(supporting, style: SportikaType.caption),
                const SizedBox(height: SportikaSpacing.md),
                action,
              ],
            );
            return Padding(
              padding: EdgeInsets.all(pagePadding),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(flex: 3, child: copy),
                        const SizedBox(width: SportikaSpacing.lg),
                        Expanded(flex: 2, child: photo(SportikaSpacing.xl * 6)),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (roomyText) ...[
                          photo(SportikaSpacing.xl * 3),
                          const SizedBox(height: SportikaSpacing.md),
                        ],
                        copy,
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

/// Compact Home feed entry; navigation continues to open the notification inbox.
class ActivityRow extends StatelessWidget {
  const ActivityRow({super.key, required this.notification});
  final AppNotification notification;

  IconData get _icon => switch (notification.kind) {
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

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    hint: 'Open notifications',
    child: InkWell(
      onTap: () => pushRoute(context, AppRoute.notifications),
      borderRadius: BorderRadius.circular(SportikaRadius.sm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SportikaSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.only(top: SportikaSpacing.xs),
                  child: Icon(
                    _icon,
                    size: SportikaSpacing.lg,
                    color: SportikaColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: SportikaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: notification.read
                          ? SportikaType.body
                          : SportikaType.bodyStrong,
                    ),
                    if (notification.body.trim().isNotEmpty) ...[
                      const SizedBox(height: SportikaSpacing.xs),
                      Text(notification.body, style: SportikaType.caption),
                    ],
                    const SizedBox(height: SportikaSpacing.xs),
                    Wrap(
                      spacing: SportikaSpacing.sm,
                      runSpacing: SportikaSpacing.xs,
                      children: [
                        Text(
                          timeAgo(notification.at),
                          style: SportikaType.caption.copyWith(
                            color: SportikaColors.textDim,
                          ),
                        ),
                        if (!notification.read)
                          Text(
                            'Unread',
                            style: SportikaType.caption.copyWith(
                              color: SportikaColors.mint,
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
      ),
    ),
  );
}
