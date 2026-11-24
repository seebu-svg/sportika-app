import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/widgets.dart';

enum _AccountAction { viewProfile, editProfile, settings, logOut }

/// Premium Sportika Athlete Quick Panel.
///
/// Navigation and authentication behavior remain unchanged.
/// All visual values come from the shared theme.
Future<void> showAccountQuickMenu(BuildContext context, Account account) async {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);

  final theme = context.sportika;
  final username = account.username.trim();

  final action = await showModalBottomSheet<_AccountAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: theme.surfaceHigh,
    barrierColor: SportikaColors.scrim,
    constraints: const BoxConstraints(maxWidth: SportikaBreakpoints.phone),
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(SportikaRadius.xl),
      ),
      side: BorderSide(color: theme.border, width: SportikaBorder.hairline),
    ),
    clipBehavior: Clip.antiAlias,
    sheetAnimationStyle: reduceMotion
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: SportikaMotion.base,
            reverseDuration: SportikaMotion.fast,
          ),
    builder: (sheetContext) {
      final sheetTheme = sheetContext.sportika;

      // The panel has no visible title, so it names itself for screen readers
      // and for tests that assert the sheet opened.
      return Semantics(
        container: true,
        label: 'Account quick menu',
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              SportikaSpacing.gutter,
              0,
              SportikaSpacing.gutter,
              SportikaSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ----------------------------------
                // PANEL HEADER
                // ----------------------------------

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'MY ACCOUNT',
                        style: sheetContext.sportikaText
                            .of(SportikaTextRole.eyebrow)
                            .copyWith(color: sheetTheme.textMuted),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close account menu',
                      onPressed: () => Navigator.pop(sheetContext),
                      constraints: const BoxConstraints(
                        minWidth: SportikaTouchTarget.minimum,
                        minHeight: SportikaTouchTarget.minimum,
                      ),
                      icon: Icon(
                        Icons.close_rounded,
                        size: SportikaIconSize.lg,
                        color: sheetTheme.textMuted,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: SportikaSpacing.sm),

                // ----------------------------------
                // ATHLETE IDENTITY CARD
                // ----------------------------------
                _AthleteIdentityCard(
                  account: account,
                  username: username,
                  onTap: () =>
                      Navigator.pop(sheetContext, _AccountAction.viewProfile),
                ),

                const SizedBox(height: SportikaSpacing.xl),

                // ----------------------------------
                // ACCOUNT ACTIONS
                // ----------------------------------
                _AccountMenuOption(
                  icon: Icons.person_outline_rounded,
                  title: 'Edit Profile',
                  subtitle: 'Update your athlete identity',
                  onTap: () =>
                      Navigator.pop(sheetContext, _AccountAction.editProfile),
                ),

                const SizedBox(height: SportikaSpacing.xs),

                _AccountMenuOption(
                  icon: Icons.tune_rounded,
                  title: 'Settings',
                  subtitle: 'Preferences and account controls',
                  onTap: () =>
                      Navigator.pop(sheetContext, _AccountAction.settings),
                ),

                const SizedBox(height: SportikaSpacing.lg),

                Divider(
                  height: SportikaBorder.hairline,
                  thickness: SportikaBorder.hairline,
                  color: sheetTheme.borderSubtle,
                ),

                const SizedBox(height: SportikaSpacing.sm),

                // ----------------------------------
                // DESTRUCTIVE ACTION
                // ----------------------------------
                _AccountMenuOption(
                  icon: Icons.logout_rounded,
                  title: 'Log Out',
                  subtitle: 'Sign out of this device',
                  danger: true,
                  onTap: () =>
                      Navigator.pop(sheetContext, _AccountAction.logOut),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  if (!context.mounted || action == null) {
    return;
  }

  // ----------------------------------------
  // EXISTING NAVIGATION AND AUTHENTICATION
  // ----------------------------------------

  switch (action) {
    case _AccountAction.viewProfile:
      openHomeTab(context, HomeTabIndex.me);

    case _AccountAction.editProfile:
      await pushRoute(context, AppRoute.editProfile);

    case _AccountAction.settings:
      await pushRoute(context, AppRoute.settings);

    case _AccountAction.logOut:
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          final dialogTheme = dialogContext.sportika;

          return AlertDialog(
            backgroundColor: dialogTheme.surfaceAlt,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SportikaRadius.dialog),
              side: BorderSide(color: dialogTheme.border),
            ),
            title: Text(
              'Log out?',
              style: dialogContext.sportikaText.of(SportikaTextRole.title),
            ),
            content: Text(
              'Log out of Sportika on this device? '
              'You can sign in again when you’re ready.',
              style: dialogContext.sportikaText.of(SportikaTextRole.body),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: dialogTheme.danger,
                  foregroundColor: SportikaColors.onAccent,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Log Out'),
              ),
            ],
          );
        },
      );

      if (!context.mounted || confirmed != true) {
        return;
      }

      final navigator = Navigator.of(context);

      final messenger = ScaffoldMessenger.of(context);

      try {
        await context.read<AuthFlowController>().signOut();

        if (navigator.mounted) {
          navigator.popUntil((route) => route.isFirst);
        }
      } catch (_) {
        if (!messenger.mounted) {
          return;
        }

        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Could not finish logging out. '
                'Please try again.',
              ),
            ),
          );
      }
  }
}

/// Athlete identity card.
///
/// Uses real account information only.
/// No fabricated rankings, statistics or badges.
class _AthleteIdentityCard extends StatelessWidget {
  const _AthleteIdentityCard({
    required this.account,
    required this.username,
    required this.onTap,
  });

  final Account account;
  final String username;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    final formattedUsername = username.isEmpty
        ? null
        : username.startsWith('@')
        ? username
        : '@$username';

    return Semantics(
      button: true,
      label: 'View athlete profile',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(SportikaRadius.xl),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SportikaRadius.xl),
            border: Border.all(
              color: theme.borderStrong,
              width: SportikaBorder.hairline,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [theme.surfaceHigh, theme.surfaceAlt, theme.surface],
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(SportikaRadius.xl),
            child: Padding(
              padding: const EdgeInsets.all(SportikaSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Brand eyebrow.
                  Row(
                    children: [
                      Icon(
                        Icons.bolt_rounded,
                        size: SportikaIconSize.sm,
                        color: theme.live,
                      ),
                      const SizedBox(width: SportikaSpacing.xs),
                      Expanded(
                        child: Text(
                          'SPORTIKA ATHLETE',
                          style: context.sportikaText
                              .of(SportikaTextRole.eyebrow)
                              .copyWith(color: theme.live),
                        ),
                      ),
                      Icon(
                        Icons.arrow_outward_rounded,
                        size: SportikaIconSize.md,
                        color: theme.textMuted,
                      ),
                    ],
                  ),

                  const SizedBox(height: SportikaSpacing.lg),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Avatar with branded ring.
                      Container(
                        padding: const EdgeInsets.all(SportikaBorder.rule),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.brandBright,
                            width: SportikaBorder.rule,
                          ),
                        ),
                        child: ExcludeSemantics(
                          child: AccountAvatar(
                            account: account,
                            size: SportikaComponentSize.avatarLg,
                          ),
                        ),
                      ),

                      const SizedBox(width: SportikaSpacing.md),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              account.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.sportikaText
                                  .of(SportikaTextRole.cardTitle)
                                  .copyWith(color: theme.textPrimary),
                            ),

                            if (formattedUsername != null) ...[
                              const SizedBox(height: SportikaSpacing.xs),
                              Text(
                                formattedUsername,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.sportikaText
                                    .of(SportikaTextRole.caption)
                                    .copyWith(color: theme.textMuted),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(width: SportikaSpacing.xs),

                      Icon(
                        Icons.chevron_right_rounded,
                        color: theme.textMuted,
                        size: SportikaIconSize.lg,
                      ),
                    ],
                  ),

                  const SizedBox(height: SportikaSpacing.lg),

                  // Lightweight profile CTA.
                  // The sheet is narrower than the page at 320px, so the pair
                  // scales down instead of running the arrow off the edge.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'VIEW MY PROFILE',
                          style: context.sportikaText
                              .of(SportikaTextRole.eyebrow)
                              .copyWith(color: theme.brandBright),
                        ),
                        const SizedBox(width: SportikaSpacing.xs),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: SportikaIconSize.sm,
                          color: theme.brandBright,
                        ),
                      ],
                    ),
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

/// Premium navigation action.
///
/// Uses a two-line layout, a themed icon container,
/// accessible tap sizing and a distinct danger state.
class _AccountMenuOption extends StatelessWidget {
  const _AccountMenuOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    final tone = danger ? theme.danger : theme.textBody;

    final titleTone = danger ? theme.danger : theme.textPrimary;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(SportikaRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SportikaRadius.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: SportikaTouchTarget.prominent,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SportikaSpacing.sm,
              vertical: SportikaSpacing.sm,
            ),
            child: Row(
              children: [
                // Icon surface.
                Container(
                  width: SportikaTouchTarget.minimum,
                  height: SportikaTouchTarget.minimum,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: danger
                        ? theme.danger.withValues(alpha: SportikaOpacity.soft)
                        : theme.surfaceAlt,
                    borderRadius: BorderRadius.circular(SportikaRadius.control),
                    border: Border.all(
                      color: danger
                          ? theme.danger.withValues(
                              alpha: SportikaOpacity.muted,
                            )
                          : theme.borderSubtle,
                    ),
                  ),
                  child: Icon(icon, size: SportikaIconSize.lg, color: tone),
                ),

                const SizedBox(width: SportikaSpacing.md),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.sportikaText
                            .of(SportikaTextRole.bodyStrong)
                            .copyWith(color: titleTone),
                      ),
                      const SizedBox(height: SportikaSpacing.xxs),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.sportikaText
                            .of(SportikaTextRole.caption)
                            .copyWith(color: theme.textMuted),
                      ),
                    ],
                  ),
                ),

                if (!danger) ...[
                  const SizedBox(width: SportikaSpacing.xs),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: SportikaIconSize.lg,
                    color: theme.textDim,
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
