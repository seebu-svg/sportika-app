import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/notifications_controller.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// What the member wants to be told about.
///
/// The switches are stored in PostgreSQL and are enforced while a
/// notification is generated, so turning one off stops the message rather than
/// hiding it after the fact.
class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  /// The values on screen while a save is in flight.
  NotificationPreferences? _pending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NotificationsController>().loadPreferences();
    });
  }

  /// What the screen draws: the pending values first, then what the server
  /// last confirmed.
  NotificationPreferences _values(NotificationsController state) =>
      _pending ?? state.preferences;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NotificationsController>();
    final values = _values(state);

    return Scaffold(
      appBar: sportikaAppBar(
        'Notification settings',
        subtitle: 'Choose what reaches you',
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width > 760
              ? (MediaQuery.sizeOf(context).width - 720) / 2
              : 16,
          14,
          MediaQuery.sizeOf(context).width > 760
              ? (MediaQuery.sizeOf(context).width - 720) / 2
              : 16,
          30,
        ),
        children: [
          if (state.error != null) ...[
            ErrorState(
              title: 'The setting did not save',
              message: state.error,
              onRetry: state.loadPreferences,
              retryLabel: 'Try again',
              compact: true,
            ),
            const SizedBox(height: SportikaSpacing.md),
          ],
          _PreferenceRow(
            title: 'Match activity',
            body:
                'Invitations, schedule changes, cancellations, results and '
                'disputes.',
            value: values.matchActivity,
            onChanged: (v) => _save(values.copyWith(matchActivity: v), state),
          ),
          const SizedBox(height: SportikaSpacing.sm),
          _PreferenceRow(
            title: 'Tournament updates',
            body:
                'Registrations, draws, fixtures and tournament announcements.',
            value: values.tournamentUpdates,
            onChanged: (v) =>
                _save(values.copyWith(tournamentUpdates: v), state),
          ),
          const SizedBox(height: SportikaSpacing.sm),
          _PreferenceRow(
            title: 'Team activity',
            body: 'Squad invitations and roster changes.',
            value: values.teamActivity,
            onChanged: (v) => _save(values.copyWith(teamActivity: v), state),
          ),
          const SizedBox(height: SportikaSpacing.sm),
          _PreferenceRow(
            title: 'Scorer assignments',
            body: 'Assignments to score, and reminders about them.',
            value: values.scorerAssignments,
            onChanged: (v) =>
                _save(values.copyWith(scorerAssignments: v), state),
          ),
          const SizedBox(height: SportikaSpacing.sm),
          _PreferenceRow(
            title: 'Platform announcements',
            body: 'News from Sportika itself.',
            value: values.platformAnnouncements,
            onChanged: (v) =>
                _save(values.copyWith(platformAnnouncements: v), state),
          ),
          const SizedBox(height: SportikaSpacing.lg),
          const InlineBanner(
            text:
                'Account and security notices always reach you. They are '
                'about your own account, so they cannot be switched off.',
            icon: Icons.shield_outlined,
            tone: SportikaColors.gold,
          ),
        ],
      ),
    );
  }

  /// Saves one switch and puts the screen back in step with the server.
  Future<void> _save(
    NotificationPreferences next,
    NotificationsController state,
  ) async {
    setState(() => _pending = next);
    await state.updatePreferences(next);
    if (!mounted) return;
    setState(() => _pending = null);
  }
}

/// One switch with its explanation.
class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.title,
    required this.body,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String body;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: SportikaColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: SportikaColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: SportikaColors.mint,
          ),
        ],
      ),
    );
  }
}
