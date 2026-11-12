import 'package:flutter/material.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/live/screens/notifications_screen.dart';
import 'package:sportika/shared/navigation/navigation.dart';

String greetingEyebrow() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'GOOD MORNING';
  if (hour < 17) return 'GOOD AFTERNOON';
  return 'GOOD EVENING';
}

/// Home greeting row: avatar, time-aware greeting and the notification bell.
class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.account,
    required this.pagePadding,
  });

  final Account account;
  final double pagePadding;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(pagePadding, 14, pagePadding, 16),
        child: Row(
          children: [
            InkWell(
              onTap: () => openHomeTab(context, 4),
              borderRadius: BorderRadius.circular(24),
              child: AccountAvatar(account: account, size: 40),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${greetingEyebrow()} · ${account.city.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.6,
                      color: SportikaColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Let’s play, ${account.displayName.split(' ').first}.',
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const NotificationBell(),
          ],
        ),
      ),
    );
  }
}

/// Full-bleed photographic hero. The sport follows the active filter so the
/// banner stays personal without adding another control.
class HomeHero extends StatelessWidget {
  const HomeHero({super.key, required this.sport, required this.pagePadding});

  final Sport? sport;
  final double pagePadding;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final height = (width.clamp(320, 760) * .46).clamp(200, 300).toDouble();
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SportPhoto(sport: sport ?? Sport.cricket, height: height, radius: 0),
          // Single bottom scrim: photo visible at the top, type readable at the
          // base. No extra gradients stacked on top of this.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x14061426),
                  Color(0xCC09182D),
                  SportikaColors.page,
                ],
                stops: [.05, .62, 1],
              ),
            ),
          ),
          Positioned(
            left: pagePadding,
            right: pagePadding,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'THE GAME CONNECTS US',
                  style: SportikaType.micro.copyWith(
                    color: SportikaColors.mint,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'YOUR NEXT MATCH\nSTARTS HERE.',
                    maxLines: 2,
                    softWrap: false,
                    style: TextStyle(
                      fontFamily: SportikaType.displayFamily,
                      fontSize: 42,
                      height: .95,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.3,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Discover games, find your people and make it count.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SportikaType.caption.copyWith(
                          color: SportikaColors.textBody,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: () => openHomeTab(context, 1),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'FIND A GAME',
                              style: SportikaType.micro.copyWith(
                                color: SportikaColors.mint,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.arrow_forward,
                              size: 14,
                              color: SportikaColors.mint,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One notification in the Home activity timeline.
class ActivityRow extends StatelessWidget {
  const ActivityRow({super.key, required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => pushRoute(context, AppRoute.notifications),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  const SizedBox(height: 5),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: notification.read
                          ? SportikaColors.textDim
                          : SportikaColors.mint,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Expanded(child: VerticalDivider(width: 1)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: SportikaType.bodyStrong.copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      notification.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SportikaType.caption.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      timeAgo(notification.at),
                      style: SportikaType.micro.copyWith(
                        color: SportikaColors.textDim,
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
  }
}
