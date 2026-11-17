import 'package:flutter/material.dart';
import 'package:sportika/app/env.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/profile_photo_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
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
                  'Your sign-in details, notifications, privacy and the data '
                  'stored on this device.',
            ),
            const SectionHeader('Account and security'),
            SurfaceCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                children: [
                  _SecurityRow(
                    label: 'Email',
                    value: me.email,
                    actionLabel: 'Change',
                    onPressed: () => pushRoute(context, AppRoute.changeEmail),
                  ),
                  const SizedBox(height: SportikaSpacing.md),
                  _SecurityRow(
                    label: 'Password',
                    value: '••••••••',
                    actionLabel: 'Change',
                    onPressed: () =>
                        pushRoute(context, AppRoute.changePassword),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SportikaSpacing.md),
            GhostButton(
              label: 'Sign out of all devices',
              icon: Icons.devices_outlined,
              expand: true,
              onPressed: () => _signOutEverywhere(context),
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
                            const Text(
                              'Sportika member',
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
              text: AppEnv.demoMode
                  ? 'Sportika keeps everything on this device. Clearing local '
                        'data removes the saved session, scorecards, settings '
                        'and your imported profile picture.'
                  : 'Your account, profile and scorecards live in your '
                        'Sportika account. Notification choices, privacy '
                        'settings and your imported picture stay on this '
                        'device. Clearing them signs this device out and '
                        'removes the picture.',
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
            if (AppEnv.demoMode) ...[
              const SizedBox(height: 8),
              GhostButton(
                label: 'Reset demo data',
                icon: Icons.restart_alt,
                tone: SportikaColors.textBody,
                expand: true,
                onPressed: () => _resetDemo(context),
              ),
            ],
            const SectionHeader('Session'),
            GhostButton(
              label: 'Sign out',
              icon: Icons.logout,
              expand: true,
              onPressed: () async {
                final navigator = Navigator.of(context);
                await context.read<AuthFlowController>().signOut();
                if (navigator.mounted) navigator.popUntil((r) => r.isFirst);
              },
            ),
            const SectionHeader('About'),
            const InfoBanner(
              icon: Icons.info_outline,
              text: AppEnv.demoMode
                  ? 'Sportika prototype · Cricket, Padel, Futsal and '
                        'Badminton. Personal scorecards and official results are '
                        'separate records. All data is fictional.'
                  : 'Sportika · Cricket, Padel, Futsal and Badminton. Personal '
                        'scorecards and official results are kept as separate '
                        'records.',
            ),
          ],
        ],
      ),
    );
  }

  void _setPreference(BuildContext context, String key, bool value) {
    context.read<PreferencesController>().setPreference(key, value);
  }

  /// Revokes every refresh token for this account, not just this device.
  Future<void> _signOutEverywhere(BuildContext context) async {
    final flow = context.read<AuthFlowController>();
    final navigator = Navigator.of(context);
    final confirmed = await _confirm(
      context,
      title: 'Sign out of all devices?',
      body:
          'Every device, including this one, has to sign in again with your '
          'password.',
      confirmLabel: 'Sign out',
    );
    if (!context.mounted || !confirmed) return;
    await flow.signOutEverywhere();
    if (navigator.mounted) navigator.popUntil((r) => r.isFirst);
  }

  Future<void> _clearLocalData(BuildContext context) async {
    final session = context.read<SessionController>();
    final photos = context.read<ProfilePhotoController>();
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
    // The document no longer references any picture, so the files have to go
    // with it instead of quietly filling the device.
    await photos.purgeStoredFiles();
    if (navigator.mounted) navigator.popUntil((r) => r.isFirst);
  }

  Future<void> _resetDemo(BuildContext context) async {
    final session = context.read<SessionController>();
    final photos = context.read<ProfilePhotoController>();
    final confirmed = await _confirm(
      context,
      title: 'Reset demo data?',
      body:
          'Restores the original seed, including the demo accounts and '
          'dropping your profile picture. Your session is kept.',
      confirmLabel: 'Reset',
    );
    if (!context.mounted || !confirmed) return;
    await session.resetDemoData();
    await photos.purgeStoredFiles();
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

/// One credential row: what it is, its current value and the way to change it.
class _SecurityRow extends StatelessWidget {
  const _SecurityRow({
    required this.label,
    required this.value,
    required this.actionLabel,
    this.onPressed,
  });

  final String label;
  final String value;
  final String actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: SportikaType.label),
              const SizedBox(height: 4),
              Text(
                value,
                style: SportikaType.bodyStrong,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: SportikaSpacing.sm),
        TextButton(onPressed: onPressed, child: Text(actionLabel)),
      ],
    );
  }
}
