import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/widgets.dart';

enum _AccountAction { viewProfile, editProfile, settings, logOut }

/// Dismiss the sheet before navigating so destinations never stack over it.
Future<void> showAccountQuickMenu(BuildContext context, Account account) async {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  final username = account.username.trim();
  final action = await showModalBottomSheet<_AccountAction>(
    context: context,
    backgroundColor: SportikaColors.surfaceElevated,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 480),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(SportikaRadius.xl),
      ),
      side: BorderSide(color: SportikaColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    sheetAnimationStyle: reduceMotion
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: SportikaMotion.base,
            reverseDuration: SportikaMotion.fast,
          ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          SportikaSpacing.md,
          0,
          SportikaSpacing.md,
          SportikaSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    hint: 'Open Me profile',
                    child: InkWell(
                      onTap: () => Navigator.pop(
                        sheetContext,
                        _AccountAction.viewProfile,
                      ),
                      borderRadius: BorderRadius.circular(SportikaRadius.md),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: kMinInteractiveDimension,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(SportikaSpacing.sm),
                          child: Row(
                            children: [
                              ExcludeSemantics(
                                child: AccountAvatar(
                                  account: account,
                                  size: kMinInteractiveDimension,
                                ),
                              ),
                              const SizedBox(width: SportikaSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      account.displayName,
                                      style: SportikaType.bodyStrong,
                                    ),
                                    if (username.isNotEmpty) ...[
                                      const SizedBox(
                                        height: SportikaSpacing.xs,
                                      ),
                                      Text(
                                        username.startsWith('@')
                                            ? username
                                            : '@$username',
                                        style: SportikaType.caption,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: SportikaSpacing.xs),
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: SportikaSpacing.lg,
                                color: SportikaColors.textDim,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close account menu',
                  constraints: const BoxConstraints(
                    minWidth: kMinInteractiveDimension,
                    minHeight: kMinInteractiveDimension,
                  ),
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(
                    Icons.close_rounded,
                    size: SportikaSpacing.lg,
                    color: SportikaColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SportikaSpacing.sm),
            const Divider(height: 1, color: SportikaColors.borderSubtle),
            const SizedBox(height: SportikaSpacing.xs),
            _AccountMenuOption(
              icon: Icons.edit_outlined,
              title: 'Edit Profile',
              onTap: () =>
                  Navigator.pop(sheetContext, _AccountAction.editProfile),
            ),
            _AccountMenuOption(
              icon: Icons.settings_outlined,
              title: 'Settings',
              onTap: () => Navigator.pop(sheetContext, _AccountAction.settings),
            ),
            const SizedBox(height: SportikaSpacing.xs),
            const Divider(height: 1, color: SportikaColors.borderSubtle),
            const SizedBox(height: SportikaSpacing.xs),
            _AccountMenuOption(
              icon: Icons.logout_rounded,
              title: 'Log Out',
              danger: true,
              onTap: () => Navigator.pop(sheetContext, _AccountAction.logOut),
            ),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case _AccountAction.viewProfile:
      openHomeTab(context, 4);
    case _AccountAction.editProfile:
      await pushRoute(context, AppRoute.editProfile);
    case _AccountAction.settings:
      await pushRoute(context, AppRoute.settings);
    case _AccountAction.logOut:
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Log out?', style: SportikaType.title),
          content: const Text(
            'Log out of Sportika on this device? You can sign in again when you’re ready.',
            style: SportikaType.body,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: SportikaColors.danger,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Log Out'),
            ),
          ],
        ),
      );
      if (!context.mounted || confirmed != true) return;
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      try {
        await context.read<AuthFlowController>().signOut();
        if (navigator.mounted) navigator.popUntil((route) => route.isFirst);
      } catch (_) {
        if (!messenger.mounted) return;
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Could not finish logging out. Please try again.'),
            ),
          );
      }
  }
}

/// Neutral navigation rows, with logout separated by both position and tone.
class _AccountMenuOption extends StatelessWidget {
  const _AccountMenuOption({
    required this.icon,
    required this.title,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tone = danger ? SportikaColors.danger : SportikaColors.textBody;
    return ListTile(
      onTap: onTap,
      minTileHeight: kMinInteractiveDimension,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: SportikaSpacing.sm,
        vertical: SportikaSpacing.xs,
      ),
      horizontalTitleGap: SportikaSpacing.md,
      minLeadingWidth: SportikaSpacing.lg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SportikaRadius.md),
      ),
      leading: Icon(icon, size: SportikaSpacing.lg, color: tone),
      title: Text(title, style: SportikaType.bodyStrong.copyWith(color: tone)),
      trailing: danger
          ? null
          : const Icon(
              Icons.chevron_right_rounded,
              size: SportikaSpacing.lg,
              color: SportikaColors.textDim,
            ),
    );
  }
}
