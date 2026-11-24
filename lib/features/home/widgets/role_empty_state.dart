import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/state_views.dart';

enum _AccountPreferences { loading, unavailable, unselected, selected }

/// Contextual account empty state.
///
/// Sport preferences do not establish account age,
/// experience, participation history or user role.
///
/// Existing public constructor and behavior are preserved.
class AccountEmptyState extends StatelessWidget {
  const AccountEmptyState({
    super.key,
    required this.title,
    required this.newcomerBody,
    required this.playerBody,
    this.icon = Icons.event_available,
    this.action,
  });

  final String title;

  /// Legacy parameter name.
  ///
  /// Used when an available account has no selected sports.
  /// Does not imply a new account or onboarding requirement.
  final String newcomerBody;

  /// Legacy parameter name.
  ///
  /// Used when sports are selected. Selection does not
  /// imply a Player role or sporting experience.
  final String playerBody;

  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    // Keep the scalar selection optimization.
    //
    // Unrelated SessionController notifications do not
    // rebuild this widget unless the preference state changes.
    final preferences = context.select<SessionController, _AccountPreferences>((
      session,
    ) {
      if (!session.ready) {
        return _AccountPreferences.loading;
      }

      final account = session.currentAccount;

      if (account == null) {
        return _AccountPreferences.unavailable;
      }

      return account.sports.isEmpty
          ? _AccountPreferences.unselected
          : _AccountPreferences.selected;
    });

    if (preferences == _AccountPreferences.loading) {
      return const _SportikaEmptyLoading();
    }

    final body = switch (preferences) {
      _AccountPreferences.unselected => newcomerBody,
      _AccountPreferences.selected => playerBody,
      _AccountPreferences.unavailable =>
        'Account details are not available yet. '
            'Please try again when your account information is available.',
      _AccountPreferences.loading => '',
    };

    final variant = switch (preferences) {
      _AccountPreferences.unselected => SportikaEmptyVariant.discovery,
      _AccountPreferences.selected => SportikaEmptyVariant.standard,
      _AccountPreferences.unavailable => SportikaEmptyVariant.unavailable,
      _AccountPreferences.loading => SportikaEmptyVariant.standard,
    };

    return SportikaEmptyState(
      title: title,
      body: body,
      icon: preferences == _AccountPreferences.unavailable
          ? Icons.person_outline_rounded
          : icon,
      variant: variant,
      action: action,
    );
  }
}

/// Semantic visual variants for Sportika empty states.
///
/// These describe presentation, not user identity.
enum SportikaEmptyVariant { standard, discovery, unavailable }

/// Reusable premium Sportika empty-state component.
///
/// Can also be used for:
/// - Empty match lists
/// - Tournament discovery
/// - Team collections
/// - Notification feeds
///
/// Uses the active shared theme and never fabricates data.
class SportikaEmptyState extends StatelessWidget {
  const SportikaEmptyState({
    super.key,
    required this.title,
    required this.body,
    required this.icon,
    this.action,
    this.variant = SportikaEmptyVariant.standard,
  });

  final String title;
  final String body;
  final IconData icon;
  final Widget? action;
  final SportikaEmptyVariant variant;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    final accent = switch (variant) {
      SportikaEmptyVariant.standard => theme.brandBright,
      SportikaEmptyVariant.discovery => theme.live,
      SportikaEmptyVariant.unavailable => theme.textMuted,
    };

    final eyebrow = switch (variant) {
      SportikaEmptyVariant.standard => 'SPORTIKA',
      SportikaEmptyVariant.discovery => 'EXPLORE SPORTIKA',
      SportikaEmptyVariant.unavailable => 'ACCOUNT STATUS',
    };

    final supportingIcon = switch (variant) {
      SportikaEmptyVariant.standard => Icons.bolt_rounded,
      SportikaEmptyVariant.discovery => Icons.explore_outlined,
      SportikaEmptyVariant.unavailable => Icons.info_outline_rounded,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        final compact = availableWidth < SportikaBreakpoints.phone;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: SportikaBreakpoints.maxContent,
            ),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(SportikaRadius.xl),
                border: Border.all(
                  color: theme.borderSubtle,
                  width: SportikaBorder.hairline,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(
                  compact ? SportikaSpacing.lg : SportikaSpacing.xl,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // ----------------------------------
                    // BRANDED ICON ARTWORK
                    // ----------------------------------

                    _SportikaEmptyArtwork(
                      icon: icon,
                      accent: accent,
                      variant: variant,
                    ),

                    const SizedBox(height: SportikaSpacing.lg),

                    // ----------------------------------
                    // SECTION EYEBROW
                    // ----------------------------------
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          supportingIcon,
                          size: SportikaIconSize.sm,
                          color: accent,
                        ),
                        const SizedBox(width: SportikaSpacing.xs),
                        Flexible(
                          child: Text(
                            eyebrow,
                            textAlign: TextAlign.center,
                            style: context.sportikaText.of(
                              SportikaTextRole.eyebrow,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: SportikaSpacing.sm),

                    // ----------------------------------
                    // EDITORIAL HEADLINE
                    // ----------------------------------
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        softWrap: true,
                        style: context.sportikaText.of(
                          SportikaTextRole.title,
                          color: theme.textPrimary,
                        ),
                      ),
                    ),

                    if (body.trim().isNotEmpty) ...[
                      const SizedBox(height: SportikaSpacing.sm),

                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: SportikaSpacing.xl * 14,
                        ),
                        child: Text(
                          body,
                          textAlign: TextAlign.center,
                          softWrap: true,
                          style: context.sportikaText.of(
                            SportikaTextRole.body,
                            color: theme.textBody,
                          ),
                        ),
                      ),
                    ],

                    // ----------------------------------
                    // OPTIONAL CALL TO ACTION
                    // ----------------------------------
                    if (action != null) ...[
                      const SizedBox(height: SportikaSpacing.xl),

                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: SportikaTouchTarget.minimum,
                          maxWidth: SportikaSpacing.xl * 12,
                        ),
                        child: SizedBox(
                          width: compact ? double.infinity : null,
                          child: action!,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Decorative sport-themed icon treatment.
///
/// The layered surfaces provide visual depth
/// without continuous animation or expensive blur.
class _SportikaEmptyArtwork extends StatelessWidget {
  const _SportikaEmptyArtwork({
    required this.icon,
    required this.accent,
    required this.variant,
  });

  final IconData icon;
  final Color accent;
  final SportikaEmptyVariant variant;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return ExcludeSemantics(
      child: Container(
        width: SportikaTouchTarget.prominent + SportikaSpacing.xl,
        height: SportikaTouchTarget.prominent + SportikaSpacing.xl,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.surfaceAlt,
          border: Border.all(color: theme.borderSubtle),
        ),
        child: Container(
          width: SportikaTouchTarget.prominent,
          height: SportikaTouchTarget.prominent,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: SportikaOpacity.soft),
            border: Border.all(
              color: accent.withValues(alpha: SportikaOpacity.muted),
            ),
          ),
          child: Icon(icon, size: SportikaIconSize.xl, color: accent),
        ),
      ),
    );
  }
}

/// Branded loading placeholder.
///
/// Matches the final card's overall visual language
/// without implying that account data is missing.
class _SportikaEmptyLoading extends StatelessWidget {
  const _SportikaEmptyLoading();

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Semantics(
      label: 'Loading account details',
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(SportikaSpacing.xl),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(SportikaRadius.xl),
          border: Border.all(color: theme.borderSubtle),
        ),
        child: const ExcludeSemantics(
          child: LoadingSkeleton(rows: 2, label: 'Loading account details'),
        ),
      ),
    );
  }
}
