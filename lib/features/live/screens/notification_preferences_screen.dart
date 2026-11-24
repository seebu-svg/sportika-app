import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/notifications_controller.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Sportika Notification Control Center.
///
/// Uses the existing PostgreSQL-backed notification preferences.
/// Updates are optimistic, serialized and coalesced so rapid changes
/// cannot start competing writes from this screen.
class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  NotificationPreferences? _draft;

  bool _saving = false;
  bool _loading = true;
  bool _dirty = false;

  String? _localError;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadPreferences();
    });
  }

  Future<void> _loadPreferences() async {
    final controller = context.read<NotificationsController>();

    setState(() {
      _loading = true;
      _localError = null;
    });

    try {
      await controller.loadPreferences();

      if (!mounted) return;

      setState(() {
        // A load response must never overwrite switches the
        // member changed while the request was in flight.
        if (!_dirty) {
          _draft = controller.preferences;
        }

        _localError = controller.error;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _localError = '$error';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  NotificationPreferences _values(NotificationsController controller) {
    return _draft ?? controller.preferences;
  }

  void _change(
    NotificationsController controller,
    NotificationPreferences Function(NotificationPreferences current) update,
  ) {
    final current = _values(controller);

    setState(() {
      _draft = update(current);
      _dirty = true;
      _localError = null;
    });

    // Only one writer can be active. While it is saving,
    // further changes update the draft and will be picked
    // up by the next loop iteration.
    if (!_saving) {
      _flushChanges(controller);
    }
  }

  Future<void> _flushChanges(NotificationsController controller) async {
    if (_saving || !_dirty) return;

    _saving = true;

    if (mounted) setState(() {});

    try {
      while (mounted && _dirty) {
        final next = _draft!;

        setState(() {
          _dirty = false;
        });

        try {
          await controller.updatePreferences(next);

          if (!mounted) return;

          // The controller exposes the latest server-confirmed
          // values. A reported error must not be treated as a
          // successful save.
          if (controller.error != null) {
            setState(() {
              _localError = controller.error;
              _dirty = true;
            });
            break;
          }

          if (!_dirty) {
            setState(() {
              _draft = controller.preferences;
              _localError = null;
            });
          }
        } catch (error) {
          if (!mounted) return;

          setState(() {
            _localError = '$error';
            _dirty = true;
          });

          break;
        }
      }
    } finally {
      _saving = false;

      if (mounted) setState(() {});
    }
  }

  void _retrySave() {
    final controller = context.read<NotificationsController>();

    if (_dirty && _draft != null) {
      setState(() => _localError = null);
      _flushChanges(controller);
    } else {
      _loadPreferences();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NotificationsController>();
    final values = _values(controller);

    final width = MediaQuery.sizeOf(context).width;

    final horizontalPadding = width > 760
        ? (width - 720) / 2
        : SportikaSpacing.md;

    return Scaffold(
      appBar: sportikaAppBar('Notifications', subtitle: 'Your preferences'),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            SportikaSpacing.md,
            horizontalPadding,
            SportikaSpacing.xxl,
          ),
          children: [
            // ==========================================
            // BRANDED HEADER
            // ==========================================

            _NotificationHeader(saving: _saving, loading: _loading),

            const SizedBox(height: SportikaSpacing.lg),

            // ==========================================
            // SAVE ERROR
            // ==========================================
            if (_localError != null) ...[
              SurfaceCard(
                borderColor: SportikaColors.danger.withValues(alpha: 0.4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: SportikaColors.danger,
                        ),
                        const SizedBox(width: SportikaSpacing.sm),
                        Expanded(
                          child: Text(
                            _dirty
                                ? 'Changes not saved'
                                : 'Could not load preferences',
                            style: SportikaType.bodyStrong,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: SportikaSpacing.sm),
                    Text(_localError!, style: SportikaType.caption),
                    const SizedBox(height: SportikaSpacing.md),
                    GhostButton(
                      label: _dirty ? 'Retry saving' : 'Try again',
                      icon: Icons.refresh_rounded,
                      expand: true,
                      onPressed: _retrySave,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SportikaSpacing.lg),
            ],

            // ==========================================
            // SPORTS ACTIVITY
            // ==========================================
            const _PreferenceSectionHeader(
              title: 'SPORTS ACTIVITY',
              subtitle: 'Choose which match and community updates reach you.',
            ),

            const SizedBox(height: SportikaSpacing.sm),

            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _PreferenceRow(
                    icon: Icons.sports_score_rounded,
                    title: 'Match activity',
                    body: 'Invitations, schedule changes, cancellations, results and disputes.',
                    value: values.matchActivity,
                    onChanged: (value) => _change(
                      controller,
                      (current) => current.copyWith(matchActivity: value),
                    ),
                  ),

                  const _PreferenceDivider(),

                  _PreferenceRow(
                    icon: Icons.emoji_events_outlined,
                    title: 'Tournament updates',
                    body: 'Registrations, draws, fixtures and tournament announcements.',
                    value: values.tournamentUpdates,
                    onChanged: (value) => _change(
                      controller,
                      (current) => current.copyWith(tournamentUpdates: value),
                    ),
                  ),

                  const _PreferenceDivider(),

                  _PreferenceRow(
                    icon: Icons.groups_2_outlined,
                    title: 'Team activity',
                    body: 'Squad invitations and roster changes.',
                    value: values.teamActivity,
                    onChanged: (value) => _change(
                      controller,
                      (current) => current.copyWith(teamActivity: value),
                    ),
                  ),

                  const _PreferenceDivider(),

                  _PreferenceRow(
                    icon: Icons.assignment_ind_outlined,
                    title: 'Scorer assignments',
                    body: 'Official scoring assignments and reminders.',
                    value: values.scorerAssignments,
                    onChanged: (value) => _change(
                      controller,
                      (current) => current.copyWith(scorerAssignments: value),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: SportikaSpacing.lg),

            // ==========================================
            // PLATFORM UPDATES
            // ==========================================
            const _PreferenceSectionHeader(
              title: 'FROM SPORTIKA',
              subtitle: 'Announcements from the Sportika platform.',
            ),

            const SizedBox(height: SportikaSpacing.sm),

            SurfaceCard(
              padding: EdgeInsets.zero,
              child: _PreferenceRow(
                icon: Icons.campaign_outlined,
                title: 'Platform announcements',
                body: 'News and updates from Sportika.',
                value: values.platformAnnouncements,
                onChanged: (value) => _change(
                  controller,
                  (current) => current.copyWith(platformAnnouncements: value),
                ),
              ),
            ),

            const SizedBox(height: SportikaSpacing.lg),

            // ==========================================
            // ACCOUNT SECURITY
            // ==========================================
            const _SecurityNotice(),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// BRANDED HEADER
// ============================================================

class _NotificationHeader extends StatelessWidget {
  const _NotificationHeader({required this.saving, required this.loading});

  final bool saving;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: SportikaColors.blueBright.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(SportikaRadius.md),
            ),
            child: const Padding(
              padding: EdgeInsets.all(SportikaSpacing.md),
              child: Icon(
                Icons.notifications_active_outlined,
                color: SportikaColors.blueBright,
                size: 28,
              ),
            ),
          ),

          const SizedBox(width: SportikaSpacing.md),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Stay in the game', style: SportikaType.bodyStrong),
                const SizedBox(height: SportikaSpacing.xs),
                const Text(
                  'Control the updates that matter to you.',
                  style: SportikaType.caption,
                ),
                if (saving || loading) ...[
                  const SizedBox(height: SportikaSpacing.xs),
                  Text(
                    saving ? 'Saving preferences...' : 'Loading preferences...',
                    style: SportikaType.micro.copyWith(
                      color: SportikaColors.mint,
                    ),
                  ),
                ],
              ],
            ),
          ),

          if (saving || loading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: SportikaColors.mint,
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// SECTION HEADER
// ============================================================

class _PreferenceSectionHeader extends StatelessWidget {
  const _PreferenceSectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: SportikaType.label),
        const SizedBox(height: SportikaSpacing.xs),
        Text(subtitle, style: SportikaType.caption),
      ],
    );
  }
}

// ============================================================
// PREFERENCE ROW
// ============================================================

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.icon,
    required this.title,
    required this.body,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SportikaSpacing.md,
          vertical: SportikaSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: SportikaColors.surfaceElevated,
                borderRadius: BorderRadius.circular(SportikaRadius.sm),
              ),
              child: Padding(
                padding: const EdgeInsets.all(SportikaSpacing.sm),
                child: Icon(
                  icon,
                  size: 20,
                  color: value ? SportikaColors.mint : SportikaColors.textMuted,
                ),
              ),
            ),

            const SizedBox(width: SportikaSpacing.md),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SportikaType.bodyStrong),
                  const SizedBox(height: SportikaSpacing.xs),
                  Text(body, style: SportikaType.caption),
                ],
              ),
            ),

            const SizedBox(width: SportikaSpacing.sm),

            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: SportikaColors.mint,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SECTION DIVIDER
// ============================================================

class _PreferenceDivider extends StatelessWidget {
  const _PreferenceDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      color: SportikaColors.borderSubtle,
    );
  }
}

// ============================================================
// SECURITY NOTICE
// ============================================================

class _SecurityNotice extends StatelessWidget {
  const _SecurityNotice();

  @override
  Widget build(BuildContext context) {
    return const SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.verified_user_outlined,
            color: SportikaColors.mint,
            size: 22,
          ),

          SizedBox(width: SportikaSpacing.md),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Account protection', style: SportikaType.bodyStrong),
                SizedBox(height: SportikaSpacing.xs),
                Text(
                  'Account and security notices always reach you. These essential notifications cannot be switched off.',
                  style: SportikaType.caption,
                ),
              ],
            ),
          ),

          SizedBox(width: SportikaSpacing.sm),

          Icon(
            Icons.lock_outline_rounded,
            color: SportikaColors.textMuted,
            size: 18,
          ),
        ],
      ),
    );
  }
}
