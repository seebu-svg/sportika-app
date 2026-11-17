import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/home/widgets/account_quick_menu.dart';
import 'package:sportika/features/live/screens/notifications_screen.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Shared, fixed root-tab identity and account actions.
class GlobalAppHeader extends StatelessWidget {
  const GlobalAppHeader({super.key, required this.section});

  final String section;
  static const horizontalPadding = 20.0;

  @override
  Widget build(BuildContext context) {
    final account = context.watch<SessionController>().currentAccount;
    // Reserve the same scaled height on every tab, including short labels.
    final scale = MediaQuery.textScalerOf(context);
    final height = 26 + scale.scale(20) * 1.1 + scale.scale(11) * 1.2;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: SportikaColors.page,
        border: Border(bottom: BorderSide(color: SportikaColors.borderSubtle)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: height,
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
                          fontWeight: FontWeight.w800,
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
                          fontWeight: FontWeight.w600,
                          color: SportikaColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
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
                        borderRadius: BorderRadius.circular(12),
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
            ),
          ),
        ),
      ),
    );
  }
}
