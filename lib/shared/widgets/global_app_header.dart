import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/home/widgets/account_quick_menu.dart';
import 'package:sportika/features/live/screens/notifications_screen.dart';
import 'package:sportika/shared/models/models.dart' show Account;
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Shared, fixed root-tab identity and account actions.
class GlobalAppHeader extends StatelessWidget {
  const GlobalAppHeader({
    super.key,
    required this.section,
    this.useHomeActions = false,
  });

  final String section;
  final bool useHomeActions;
  static const horizontalPadding = 20.0;

  @override
  Widget build(BuildContext context) {
    final account = context.watch<SessionController>().currentAccount;
    // Reserve the same scaled height on every tab, including short labels.
    final scale = MediaQuery.textScalerOf(context);
    final height = 26 + scale.scale(20) * 1.1 + scale.scale(11) * 1.2;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: SportikaColors.glass,
        border: Border(bottom: BorderSide(color: SportikaColors.borderSubtle)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: useHomeActions
              ? height.clamp(SportikaSpacing.xxxl, double.infinity)
              : height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Row(
              children: [
                const BrandMark(size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SPORTIKA',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: SportikaType.displayFamily,
                          fontSize: 20,
                          height: 1.1,
                          fontWeight: SportikaFontWeight.extraBold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        section,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.2,
                          fontWeight: SportikaFontWeight.semibold,
                          color: SportikaColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (useHomeActions) ...[
                  const SizedBox(width: SportikaSpacing.xs),
                  _HomeHeaderActions(account: account),
                ] else ...[
                  const SizedBox(width: 8),
                  const NotificationBell(),
                  const SizedBox(width: 4),
                  SizedBox.square(
                    dimension: 44,
                    child: IconButton(
                      tooltip: 'Account menu',
                      style: IconButton.styleFrom(
                        backgroundColor: SportikaColors.surfaceAlt,
                        side: const BorderSide(color: SportikaColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            SportikaRadius.control,
                          ),
                        ),
                      ),
                      onPressed: account == null
                          ? null
                          : () => showAccountQuickMenu(context, account),
                      icon: account == null
                          ? const Icon(Icons.person_outline)
                          : AccountAvatar(account: account, size: 28),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeHeaderActions extends StatelessWidget {
  const _HomeHeaderActions({required this.account});

  final Account? account;

  @override
  Widget build(BuildContext context) {
    final unread = context.select<NotificationsController, int>(
      (controller) => controller.unreadCount,
    );
    final hasUnread = unread > 0;
    final profile = account;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HomeHeaderButton(
          label: hasUnread ? 'Notifications, $unread unread' : 'Notifications',
          highlighted: hasUnread,
          onPressed: () => showNotificationPreview(context),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    top: hasUnread ? SportikaSpacing.xs : 0,
                    end: hasUnread ? SportikaSpacing.xxs : 0,
                  ),
                  child: Icon(
                    hasUnread
                        ? Icons.notifications_rounded
                        : Icons.notifications_none_rounded,
                    size: SportikaIconSize.lg,
                    color: hasUnread
                        ? SportikaColors.mint
                        : SportikaColors.textBody,
                  ),
                ),
              ),
              if (hasUnread)
                PositionedDirectional(
                  top: SportikaSpacing.xxs,
                  end: SportikaSpacing.xxs,
                  child: _UnreadBadge(count: unread),
                ),
            ],
          ),
        ),
        const SizedBox(width: SportikaSpacing.xs),
        _HomeHeaderButton(
          label: 'Account menu',
          onPressed: profile == null
              ? null
              : () => showAccountQuickMenu(context, profile),
          child: profile == null
              ? const Icon(Icons.person_outline_rounded)
              : AccountAvatar(
                  account: profile,
                  size: SportikaSpacing.xl,
                  ring: SportikaColors.mint,
                ),
        ),
      ],
    );
  }
}

class _HomeHeaderButton extends StatelessWidget {
  const _HomeHeaderButton({
    required this.label,
    required this.onPressed,
    required this.child,
    this.highlighted = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget child;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: SportikaSpacing.xxxl,
    child: IconButton(
      tooltip: label,
      onPressed: onPressed,
      style:
          IconButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: SportikaColors.textBody,
            backgroundColor: highlighted
                ? Color.alphaBlend(
                    SportikaColors.mintSubtle,
                    SportikaColors.surface,
                  )
                : SportikaColors.surface,
            disabledBackgroundColor: SportikaColors.surfaceSunken,
            side: BorderSide(
              color: highlighted
                  ? SportikaColors.mint.withValues(alpha: SportikaOpacity.muted)
                  : SportikaColors.border,
              width: SportikaBorder.hairline,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SportikaRadius.button),
            ),
            animationDuration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : SportikaMotion.fast,
          ).copyWith(
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return SportikaColors.overlay;
              }
              if (states.contains(WidgetState.focused) ||
                  states.contains(WidgetState.hovered)) {
                return SportikaColors.overlaySoft;
              }
              return null;
            }),
          ),
      icon: ExcludeSemantics(child: child),
    ),
  );
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(
      minWidth: SportikaIconSize.md,
      maxWidth: SportikaSpacing.xl,
      minHeight: SportikaIconSize.sm,
      maxHeight: SportikaIconSize.md,
    ),
    padding: const EdgeInsets.symmetric(horizontal: SportikaSpacing.xxs),
    decoration: BoxDecoration(
      color: SportikaColors.mint,
      borderRadius: BorderRadius.circular(SportikaRadius.badge),
      border: Border.all(color: SportikaColors.page),
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: SportikaType.micro.copyWith(color: SportikaColors.deepest),
      ),
    ),
  );
}
