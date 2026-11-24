import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/cinematic_backdrop.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/widgets.dart';

String greetingEyebrow() {
  final hour = DateTime.now().hour;

  if (hour < 12) return 'GOOD MORNING';
  if (hour < 17) return 'GOOD AFTERNOON';

  return 'GOOD EVENING';
}

/// Shared photographic composition for Home banners.
///
/// The image, sport identity, typography and visual
/// effects are resolved from the shared design system.
class HomeGreeting extends StatelessWidget {
  const HomeGreeting({
    super.key,
    required this.sport,
    required this.title,
    required this.supporting,
    required this.pagePadding,
  });

  final Sport sport;
  final String title;
  final String supporting;
  final double pagePadding;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;
    final identity = SportIdentities.of(sport);

    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final crop = switch (sport) {
      Sport.cricket => const Alignment(0, -0.52),
      Sport.padel => Alignment.center,
      Sport.futsal => const Alignment(0, 0.48),
      Sport.badminton => const Alignment(0, -0.78),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        final compact = width < SportikaBreakpoints.phone;

        final minHeight = compact
            ? SportikaComponentSize.heroMinHeight
            : SportikaComponentSize.heroMinHeight + SportikaSpacing.xl;

        return ColoredBox(
          color: theme.page,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Stack(
              children: [
                // ----------------------------------
                // FULL-BLEED SPORT PHOTOGRAPHY
                // ----------------------------------

                Positioned.fill(
                  child: _HomePhoto(
                    asset: identity.actionPhoto,
                    alignment: crop,
                    maxDecodeWidth: 1440,
                    fallback: SportPhoto(sport: sport, radius: 0),
                  ),
                ),

                // ----------------------------------
                // SPORT-SPECIFIC ATMOSPHERE
                // ----------------------------------
                if (!reduceMotion)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: SportMotionGraphic(tone: identity.tone),
                    ),
                  ),

                // Shared brand scrim.
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: SportikaGradients.headerScrim,
                      ),
                    ),
                  ),
                ),

                // ----------------------------------
                // GREETING CONTENT
                // ----------------------------------
                Container(
                  width: double.infinity,
                  constraints: BoxConstraints(minHeight: minHeight),
                  alignment: AlignmentDirectional.centerStart,
                  padding: EdgeInsets.symmetric(
                    horizontal: pagePadding,
                    vertical: SportikaSpacing.xl,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: SportikaBreakpoints.maxContent,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Time-aware greeting.
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bolt_rounded,
                              size: SportikaIconSize.sm,
                              color: identity.tone,
                            ),
                            const SizedBox(width: SportikaSpacing.xs),
                            Flexible(
                              child: Text(
                                greetingEyebrow(),
                                style: context.sportikaText.of(
                                  SportikaTextRole.eyebrow,
                                  color: identity.tone,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: SportikaSpacing.md),

                        Text(
                          title,
                          maxLines: compact ? 3 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.sportikaText.responsive(
                            SportikaTextRole.heroDisplay,
                            color: theme.textPrimary,
                          ),
                        ),

                        const SizedBox(height: SportikaSpacing.sm),

                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: SportikaSpacing.xl * 12,
                          ),
                          child: Text(
                            supporting,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: context.sportikaText.of(
                              SportikaTextRole.body,
                              color: theme.textBody,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Cinematic match discovery and featured tournament.
///
/// Keeps existing tournament information and
/// navigation behavior.
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
  final Tournament? featuredTournament;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;
    final event = featuredTournament;

    final eventName = event?.name.trim();

    final headline = eventName != null && eventName.isNotEmpty
        ? eventName
        : 'Find your next match';

    final supporting = event == null
        ? 'Explore ${sport?.label ?? 'sports'} '
              'matches and tournaments.'
        : [
            event.sport.label,
            dayLabel(event.startsAt.toLocal()),
            if (event.city.trim().isNotEmpty) event.city.trim(),
          ].join(' · ');

    final photoSport = event?.sport ?? sport ?? Sport.cricket;

    final identity = SportIdentities.of(photoSport);

    final eyebrow = event == null
        ? 'DISCOVER SPORTIKA'
        : event.isDemo
        ? 'FEATURED TOURNAMENT · DEMO'
        : 'FEATURED TOURNAMENT';

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        final compact = width < SportikaBreakpoints.phone;

        final minHeight = compact
            ? SportikaComponentSize.heroMinHeight + SportikaSpacing.xxl
            : SportikaComponentSize.heroMinHeight +
                  SportikaSpacing.xxl +
                  SportikaSpacing.xl;

        return ClipRRect(
          borderRadius: BorderRadius.circular(SportikaRadius.lg),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.surface,
              border: Border.all(
                color: theme.border,
                width: SportikaBorder.hairline,
              ),
              borderRadius: BorderRadius.circular(SportikaRadius.lg),
            ),
            child: Stack(
              children: [
                // ----------------------------------
                // FULL-BLEED FEATURED PHOTOGRAPHY
                // ----------------------------------

                Positioned.fill(
                  child: _HomePhoto(
                    asset: identity.actionPhoto,
                    imageUrl: imageUrl,
                    alignment: Alignment.center,
                    maxDecodeWidth: 1200,
                    fallback: SportPhoto(sport: photoSport, radius: 0),
                  ),
                ),

                // Shared cinematic image treatment.
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: SportikaGradients.headerScrim,
                      ),
                    ),
                  ),
                ),

                // ----------------------------------
                // FEATURED CONTENT
                // ----------------------------------
                Container(
                  width: double.infinity,
                  constraints: BoxConstraints(minHeight: minHeight),
                  alignment: AlignmentDirectional.bottomStart,
                  padding: EdgeInsets.all(pagePadding),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: compact
                          ? width
                          : SportikaBreakpoints.maxContent,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sport identity and feature label.
                        Row(
                          children: [
                            Icon(
                              event == null
                                  ? Icons.sports_rounded
                                  : Icons.emoji_events_outlined,
                              color: identity.tone,
                              size: SportikaIconSize.sm,
                            ),

                            const SizedBox(width: SportikaSpacing.xs),

                            Expanded(
                              child: Text(
                                eyebrow,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: context.sportikaText.of(
                                  SportikaTextRole.eyebrow,
                                  color: identity.tone,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: SportikaSpacing.sm),

                        // Featured headline.
                        Text(
                          headline,
                          maxLines: compact ? 3 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.sportikaText.responsive(
                            SportikaTextRole.hero,
                            color: theme.textPrimary,
                          ),
                        ),

                        const SizedBox(height: SportikaSpacing.sm),

                        Text(
                          supporting,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: context.sportikaText.of(
                            SportikaTextRole.body,
                            color: theme.textBody,
                          ),
                        ),

                        const SizedBox(height: SportikaSpacing.lg),

                        // Standalone match discovery lives on the Matches tab.
                        FilledButton.icon(
                          onPressed: () => openMatchTab(context, section: 5),
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            size: SportikaIconSize.md,
                          ),
                          iconAlignment: IconAlignment.end,
                          label: const Text('Find a match'),
                          style: FilledButton.styleFrom(
                            foregroundColor: SportikaColors.onMint,
                            backgroundColor: theme.live,
                            textStyle: context.sportikaText.of(
                              SportikaTextRole.action,
                            ),
                            minimumSize: const Size(
                              SportikaTouchTarget.minimum,
                              SportikaTouchTarget.comfortable,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: SportikaSpacing.lg,
                              vertical: SportikaSpacing.sm,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                SportikaRadius.control,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Shared Home photography renderer.
///
/// Supports:
/// - Local sport artwork
/// - Optional remote tournament images
/// - Local fallback
/// - Safe decode width calculation
/// - Decorative image semantics
class _HomePhoto extends StatelessWidget {
  const _HomePhoto({
    required this.asset,
    required this.alignment,
    required this.maxDecodeWidth,
    this.imageUrl,
    this.fallback,
  });

  final String asset;
  final Alignment alignment;
  final int maxDecodeWidth;
  final String? imageUrl;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pixelRatio = MediaQuery.devicePixelRatioOf(context);

        final availableWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        final rawWidth = (availableWidth * pixelRatio).ceil();

        final roundedWidth = ((rawWidth / 128).ceil() * 128);

        final decodeWidth = math.max(
          128,
          math.min(roundedWidth, maxDecodeWidth),
        );

        final localPhoto = Image.asset(
          asset,
          fit: BoxFit.cover,
          alignment: alignment,
          cacheWidth: decodeWidth,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) =>
              fallback ?? ColoredBox(color: context.sportika.surface),
        );

        final url = imageUrl?.trim();

        if (url == null || url.isEmpty) {
          return localPhoto;
        }

        return Image.network(
          url,
          fit: BoxFit.cover,
          alignment: alignment,
          cacheWidth: decodeWidth,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => localPhoto,
        );
      },
    );
  }
}

/// Premium sports activity feed row.
///
/// Keeps the existing notification model and
/// notification inbox navigation.
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

  /// Notification emphasis is resolved from the
  /// shared semantic theme.
  Color _tone(SportikaTheme theme) {
    return switch (notification.kind) {
      NotificationKind.resultPublished ||
      NotificationKind.entryDecision => theme.live,

      NotificationKind.tournamentUpdate => theme.achievement,

      NotificationKind.dispute => theme.danger,

      NotificationKind.scorerAssignment ||
      NotificationKind.matchInvite ||
      NotificationKind.matchUpdate => theme.brandBright,

      _ => theme.textMuted,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;
    final tone = _tone(theme);
    final unread = !notification.read;

    final body = notification.body.trim();

    return Semantics(
      button: true,
      hint: 'Open notifications',
      label: [
        notification.title,
        if (body.isNotEmpty) body,
        if (unread) 'Unread notification',
        timeAgo(notification.at),
      ].join('. '),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(SportikaRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => pushRoute(context, AppRoute.notifications),
          borderRadius: BorderRadius.circular(SportikaRadius.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: SportikaTouchTarget.minimum,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SportikaSpacing.sm,
                vertical: SportikaSpacing.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ----------------------------------
                  // CATEGORY ICON
                  // ----------------------------------

                  ExcludeSemantics(
                    child: Container(
                      width: SportikaTouchTarget.minimum,
                      height: SportikaTouchTarget.minimum,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.surfaceAlt,
                        borderRadius: BorderRadius.circular(
                          SportikaRadius.control,
                        ),
                        border: Border.all(color: theme.borderSubtle),
                      ),
                      child: Icon(
                        _icon,
                        color: tone,
                        size: SportikaIconSize.lg,
                      ),
                    ),
                  ),

                  const SizedBox(width: SportikaSpacing.md),

                  // ----------------------------------
                  // ACTIVITY DETAILS
                  // ----------------------------------
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
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: context.sportikaText.of(
                                  unread
                                      ? SportikaTextRole.bodyStrong
                                      : SportikaTextRole.body,
                                  color: unread
                                      ? theme.textPrimary
                                      : theme.textBody,
                                ),
                              ),
                            ),

                            if (unread) ...[
                              const SizedBox(width: SportikaSpacing.sm),
                              ExcludeSemantics(
                                child: Container(
                                  width: SportikaSpacing.xs,
                                  height: SportikaSpacing.xs,
                                  margin: const EdgeInsets.only(
                                    top: SportikaSpacing.xs,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.live,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),

                        if (body.isNotEmpty) ...[
                          const SizedBox(height: SportikaSpacing.xs),
                          Text(
                            body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.sportikaText.of(
                              SportikaTextRole.caption,
                              color: theme.textMuted,
                            ),
                          ),
                        ],

                        const SizedBox(height: SportikaSpacing.xs),

                        Text(
                          timeAgo(notification.at),
                          style: context.sportikaText.of(
                            SportikaTextRole.caption,
                            color: theme.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: SportikaSpacing.xs),

                  Icon(
                    Icons.chevron_right_rounded,
                    size: SportikaIconSize.md,
                    color: theme.textDim,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
