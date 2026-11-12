import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Settings: the preferences, privacy and destructive actions that used to sit
/// inline at the bottom of the profile tab.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _notificationKeys = {
    'reminders': ('Match reminders', 'A nudge before your fixtures'),
    'invites': ('Community invitations', 'When a squad or game invites you'),
  };

  static const _privacyKeys = {
    'publicProfile': (
      'Show sports profile',
      'Your sports and levels stay visible to other players. '
          'Personal scorecards are always private.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileController>();
    final session = context.watch<SessionController>();
    final me = profile.currentAccount;
    final prefs = context.watch<PreferencesController>();

    return ScreenScaffold(
      title: 'Settings',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (me == null)
            const ErrorState(
              title: 'Signed out',
              message: 'Sign in again to manage your settings.',
            )
          else ...[
            const ScreenHeader(
              eyebrow: 'Account',
              title: 'Settings',
              subtitle:
                  'Notifications, privacy and the data stored on this '
                  'device.',
            ),
            const SectionHeader('Notifications'),
            for (final entry in _notificationKeys.entries)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.value.$1, style: SportikaType.bodyStrong),
                subtitle: Text(entry.value.$2, style: SportikaType.caption),
                value: prefs.preference(entry.key),
                onChanged: (value) => _setPreference(context, entry.key, value),
              ),
            const SectionHeader('Privacy'),
            for (final entry in _privacyKeys.entries)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.value.$1, style: SportikaType.bodyStrong),
                subtitle: Text(entry.value.$2, style: SportikaType.caption),
                value: prefs.preference(entry.key),
                onChanged: (value) => _setPreference(context, entry.key, value),
              ),
            const SectionHeader('Roles'),
            SurfaceCard(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Signed in as', style: SportikaType.label),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      AccountAvatar(account: me, size: 36),
                      const SizedBox(width: SportikaSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              me.displayName,
                              style: SportikaType.bodyStrong,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              me.roles.map((r) => r.label).join(' · '),
                              style: SportikaType.caption,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SectionHeader('Local data'),
            const InlineBanner(
              text:
                  'Sportika keeps everything on this device. Clearing local '
                  'data removes the saved session, scorecards and settings.',
              icon: Icons.storage_outlined,
              tone: SportikaColors.textMuted,
            ),
            const SizedBox(height: SportikaSpacing.md),
            GhostButton(
              label: 'Clear local data',
              icon: Icons.delete_sweep_outlined,
              tone: SportikaColors.danger,
              expand: true,
              onPressed: () => _clearLocalData(context),
            ),
            const SizedBox(height: 8),
            GhostButton(
              label: 'Reset demo data',
              icon: Icons.restart_alt,
              tone: SportikaColors.textBody,
              expand: true,
              onPressed: () => _resetDemo(context),
            ),
            const SectionHeader('Session'),
            GhostButton(
              label: 'Sign out',
              icon: Icons.logout,
              expand: true,
              onPressed: () async {
                final navigator = Navigator.of(context);
                await session.signOut();
                if (navigator.mounted) navigator.popUntil((r) => r.isFirst);
              },
            ),
            const SectionHeader('About'),
            const InfoBanner(
              icon: Icons.info_outline,
              text:
                  'Sportika prototype · Cricket, Padel, Futsal and Badminton. '
                  'Personal scorecards and official results are separate '
                  'records. All data is fictional.',
            ),
          ],
        ],
      ),
    );
  }

  void _setPreference(BuildContext context, String key, bool value) {
    context.read<PreferencesController>().setPreference(key, value);
  }

  Future<void> _clearLocalData(BuildContext context) async {
    final session = context.read<SessionController>();
    final confirmed = await _confirm(
      context,
      title: 'Clear local data?',
      body:
          'This wipes every saved byte on this device, including your '
          'session. The demo world is rebuilt on the next launch.',
      confirmLabel: 'Clear',
    );
    if (!context.mounted || !confirmed) return;
    final navigator = Navigator.of(context);
    await session.clearLocalData();
    if (navigator.mounted) navigator.popUntil((r) => r.isFirst);
  }

  Future<void> _resetDemo(BuildContext context) async {
    final session = context.read<SessionController>();
    final confirmed = await _confirm(
      context,
      title: 'Reset demo data?',
      body:
          'Restores the original seed, including the demo accounts. '
          'Your session is kept.',
      confirmLabel: 'Reset',
    );
    if (!context.mounted || !confirmed) return;
    await session.resetDemoData();
    if (context.mounted) showSnack(context, 'Demo data reset');
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title, style: SportikaType.title),
        content: Text(body, style: SportikaType.body),
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
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
