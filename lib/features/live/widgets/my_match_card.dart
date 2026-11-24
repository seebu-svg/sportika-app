import 'package:flutter/material.dart';

import 'package:sportika/features/live/widgets/my_matches.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/filter_chip_row.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Premium, compact scoreboard card for an official match or fixture.
///
/// Keeps exact controller-driven statuses, real scores, and roles.
/// No fabricated team logos, scores, or results.
class MyMatchCard extends StatelessWidget {
  const MyMatchCard({super.key, required this.record, this.onTap});

  final MyMatchRecord record;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    final invited = record.isInvited && !record.isParticipant;
    final statusLabel = _statusLabel(invited);

    final accent = invited
        ? SportikaColors.gold
        : statusColor(record.status.key);

    final hasScore = record.hasScore;
    final hasPublishedWinner =
        record.publishedResult &&
        (record.winnerIndex == 0 || record.winnerIndex == 1);

    Color sideTone(int side) {
      if (!hasPublishedWinner) return theme.textBody;

      return record.winnerIndex == side ? SportikaColors.text : theme.textMuted;
    }

    Color scoreTone(int side) {
      if (record.isLive) return theme.live;
      return sideTone(side);
    }

    final meta = [
      dateShort(record.scheduledAt),
      timeLabel(record.scheduledAt),
      if (record.venue.trim().isNotEmpty) record.venue.trim(),
    ].join(' · ');

    final roles = record.effectiveRoles;
    final extraRoles = roles.length > 1 ? roles.length - 1 : 0;

    final scoreSummary = hasScore
        ? ', ${record.scoreA} to ${record.scoreB}'
        : '';

    final semanticLabel =
        '${record.sport.label}: '
        '${record.sideA} versus ${record.sideB}, '
        '$statusLabel, '
        '${roles.map((role) => role.label).join(', ')}, '
        '${dayLabel(record.scheduledAt)} at '
        '${timeLabel(record.scheduledAt)}'
        '$scoreSummary';

    return Semantics(
      container: true,
      button: onTap != null,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: SurfaceCard(
          onTap: onTap,
          padding: const EdgeInsets.all(SportikaSpacing.md),
          borderColor: record.isLive
              ? theme.live.withValues(alpha: SportikaOpacity.medium)
              : theme.borderSubtle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ========================================
              // COMPETITION / STATUS HEADER
              // ========================================

              Row(
                children: [
                  SportTag(record.sport, compact: true),

                  const SizedBox(width: SportikaSpacing.sm),

                  Expanded(
                    child: Text(
                      record.context.isEmpty
                          ? 'Official match'
                          : record.context,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SportikaType.micro,
                    ),
                  ),

                  const SizedBox(width: SportikaSpacing.xs),

                  StatusPill(
                    statusLabel,
                    color: accent,
                    icon: invited
                        ? Icons.mail_outline_rounded
                        : statusIcon(record.status.key),
                  ),
                ],
              ),

              const SizedBox(height: SportikaSpacing.md),

              // ========================================
              // SCOREBOARD
              // ========================================
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        _ScoreboardSide(
                          name: record.sideA,
                          score: hasScore ? record.scoreA : null,
                          nameColor: sideTone(0),
                          scoreColor: scoreTone(0),
                          isWinner:
                              hasPublishedWinner && record.winnerIndex == 0,
                        ),

                        const SizedBox(height: SportikaSpacing.md),

                        _ScoreboardSide(
                          name: record.sideB,
                          score: hasScore ? record.scoreB : null,
                          nameColor: sideTone(1),
                          scoreColor: scoreTone(1),
                          isWinner:
                              hasPublishedWinner && record.winnerIndex == 1,
                        ),
                      ],
                    ),
                  ),

                  if (!hasScore)
                    Padding(
                      padding: const EdgeInsets.only(left: SportikaSpacing.md),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.surfaceSunken,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(SportikaRadius.control),
                          ),
                          border: Border.all(color: theme.borderSubtle),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: SportikaSpacing.sm,
                            vertical: SportikaSpacing.xs,
                          ),
                          child: Text(
                            'VS',
                            style: SportikaType.bodyStrong.copyWith(
                              color: theme.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: SportikaSpacing.md),

              Divider(
                height: SportikaBorder.hairline,
                color: theme.borderSubtle,
              ),

              const SizedBox(height: SportikaSpacing.sm),

              // ========================================
              // MATCH METADATA / USER ROLE
              // ========================================
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: SportikaIconSize.sm,
                    color: theme.textMuted,
                  ),

                  const SizedBox(width: SportikaSpacing.xs),

                  Expanded(
                    child: Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SportikaType.caption,
                    ),
                  ),

                  const SizedBox(width: SportikaSpacing.sm),

                  _MatchRoleBadge(
                    role: record.primaryRole,
                    extraRoles: extraRoles,
                  ),

                  if (onTap != null) ...[
                    const SizedBox(width: SportikaSpacing.xs),
                    Icon(
                      Icons.arrow_outward_rounded,
                      size: SportikaIconSize.md,
                      color: theme.textMuted,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(bool invited) {
    if (invited) return 'Invited';

    if (record.status == FixtureStatus.submitted) {
      return 'In review';
    }

    return record.status.label;
  }
}

// ============================================================
// SCOREBOARD SIDE
// ============================================================

class _ScoreboardSide extends StatelessWidget {
  const _ScoreboardSide({
    required this.name,
    required this.score,
    required this.nameColor,
    required this.scoreColor,
    required this.isWinner,
  });

  final String name;
  final String? score;
  final Color nameColor;
  final Color scoreColor;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Row(
      children: [
        // Generic sport-team identity.
        // Do not invent logos or use unrelated profile photos.
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.surfaceSunken,
            borderRadius: const BorderRadius.all(
              Radius.circular(SportikaRadius.control),
            ),
            border: Border.all(
              color: isWinner
                  ? theme.live.withValues(alpha: SportikaOpacity.medium)
                  : theme.borderSubtle,
            ),
          ),
          child: SizedBox.square(
            dimension: SportikaSpacing.xxl,
            child: Icon(
              Icons.shield_outlined,
              size: SportikaIconSize.md,
              color: isWinner ? theme.live : theme.textMuted,
            ),
          ),
        ),

        const SizedBox(width: SportikaSpacing.sm),

        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.bodyStrong.copyWith(
                    color: nameColor,
                    fontWeight: isWinner ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),

              if (isWinner) ...[
                const SizedBox(width: SportikaSpacing.xs),
                Icon(
                  Icons.emoji_events_outlined,
                  size: SportikaIconSize.sm,
                  color: theme.live,
                ),
              ],
            ],
          ),
        ),

        if (score != null) ...[
          const SizedBox(width: SportikaSpacing.sm),

          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 156),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                score!,
                maxLines: 1,
                softWrap: false,
                style: SportikaType.scoreSmall.copyWith(
                  color: scoreColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================
// MATCH ROLE BADGE
// ============================================================

class _MatchRoleBadge extends StatelessWidget {
  const _MatchRoleBadge({required this.role, required this.extraRoles});

  final MyMatchRole role;
  final int extraRoles;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    final tone = switch (role) {
      MyMatchRole.playing => theme.live,
      MyMatchRole.organizing => SportikaColors.blueBright,
      MyMatchRole.scoring => SportikaColors.gold,
      MyMatchRole.invited => SportikaColors.gold,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          switch (role) {
            MyMatchRole.playing => Icons.sports_rounded,
            MyMatchRole.organizing => Icons.admin_panel_settings_outlined,
            MyMatchRole.scoring => Icons.edit_note_rounded,
            MyMatchRole.invited => Icons.mail_outline_rounded,
          },
          size: SportikaIconSize.sm,
          color: tone,
        ),

        const SizedBox(width: SportikaSpacing.xs),

        Text(role.label, style: SportikaType.micro.copyWith(color: tone)),

        if (extraRoles > 0) ...[
          const SizedBox(width: SportikaSpacing.xs),
          Text(
            '+$extraRoles',
            style: SportikaType.micro.copyWith(color: theme.textMuted),
          ),
        ],
      ],
    );
  }
}

// ============================================================
// MATCH PHASE FILTERS
// ============================================================

class MyMatchPhaseChips extends StatelessWidget {
  const MyMatchPhaseChips({
    super.key,
    required this.selected,
    required this.counts,
    required this.onChanged,
  });

  final MyMatchPhase selected;

  /// Real match count for each phase.
  final Map<MyMatchPhase, int> counts;

  final ValueChanged<MyMatchPhase> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChipRow<MyMatchPhase>(
      label: 'Filter by match status',
      selected: selected,
      onChanged: onChanged,
      choices: [
        for (final phase in MyMatchPhase.values)
          FilterChoice(
            phase,
            phase.label,
            badge: counts[phase] ?? 0,
            icon: _phaseIcon(phase),
          ),
      ],
    );
  }

  static IconData? _phaseIcon(MyMatchPhase phase) {
    return switch (phase) {
      MyMatchPhase.all => null,
      MyMatchPhase.upcoming => Icons.schedule_rounded,
      MyMatchPhase.live => Icons.sensors_rounded,
      MyMatchPhase.completed => Icons.history_rounded,
    };
  }
}
