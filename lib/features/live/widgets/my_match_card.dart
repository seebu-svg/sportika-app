import 'package:flutter/material.dart';

import 'package:sportika/features/live/widgets/my_matches.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/filter_chip_row.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// One compact fixture card of the My Matches list.
///
/// Shared by both sources so a tournament appearance and an official match read
/// the same way: sport and exact status on top, the two sides and their scores
/// in the middle, and one meta line carrying the date, venue and the member's
/// role. No nested cards, no gradient surfaces.
class MyMatchCard extends StatelessWidget {
  const MyMatchCard({super.key, required this.record, this.onTap});

  final MyMatchRecord record;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final invited = record.role == MyMatchRole.invited;
    final statusLabel = _statusLabel(invited);
    final accent = invited
        ? SportikaColors.gold
        : statusColor(record.status.key);
    final winner = record.winnerIndex;

    Color sideTone(int side) {
      if (winner == null || (winner != 0 && winner != 1)) {
        return SportikaColors.text;
      }
      return winner == side ? SportikaColors.text : SportikaColors.textMuted;
    }

    /// A live score is the only coloured readout in the card; once a result is
    /// published the split between winner and loser carries the meaning.
    Color scoreTone(int side) =>
        record.isLive ? SportikaColors.mint : sideTone(side);

    final meta = [
      dateShort(record.scheduledAt),
      if (record.venue.trim().isNotEmpty) record.venue.trim(),
    ].join(' · ');

    final scoreLine = record.scoreA == null && record.scoreB == null
        ? ''
        : ', ${record.scoreA ?? '—'} to ${record.scoreB ?? '—'}';

    return Semantics(
      button: true,
      container: true,
      label:
          '${record.sport.label}: ${record.sideA} versus ${record.sideB}, '
          '${statusLabel.toLowerCase()}, ${record.role.label.toLowerCase()}, '
          '${dayLabel(record.scheduledAt)} at '
          '${timeLabel(record.scheduledAt)}$scoreLine',
      child: ExcludeSemantics(
        child: SurfaceCard(
          onTap: onTap,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          borderColor: record.isLive
              ? SportikaColors.mint.withValues(alpha: 0.42)
              : SportikaColors.border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SportTag(record.sport, compact: true),
                  const SizedBox(width: SportikaSpacing.sm),
                  Expanded(
                    child: Text(
                      record.context,
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
              const SizedBox(height: SportikaSpacing.sm),
              _SideRow(
                label: record.sideA,
                score: record.scoreA,
                labelTone: sideTone(0),
                scoreTone: scoreTone(0),
              ),
              const SizedBox(height: SportikaSpacing.xs),
              _SideRow(
                label: record.sideB,
                score: record.scoreB,
                labelTone: sideTone(1),
                scoreTone: scoreTone(1),
              ),
              const SizedBox(height: SportikaSpacing.sm),
              const Divider(height: 1, color: SportikaColors.borderSubtle),
              const SizedBox(height: SportikaSpacing.xs + 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SportikaType.caption,
                    ),
                  ),
                  const SizedBox(width: SportikaSpacing.xs),
                  Text(
                    record.role.label,
                    style: SportikaType.micro.copyWith(color: _roleTone),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: SportikaColors.textDim,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color get _roleTone => switch (record.role) {
    MyMatchRole.organizing => SportikaColors.blueBright,
    MyMatchRole.scoring => SportikaColors.gold,
    MyMatchRole.invited => SportikaColors.gold,
    MyMatchRole.playing => SportikaColors.textDim,
  };

  /// The exact state, in the shortest wording a dense card can carry: the
  /// awaiting-review state keeps its meaning without wrapping the header.
  String _statusLabel(bool invited) {
    if (invited) return 'Invited';
    if (record.status == FixtureStatus.submitted) return 'In review';
    return record.status.label;
  }
}

class _SideRow extends StatelessWidget {
  const _SideRow({
    required this.label,
    required this.labelTone,
    required this.scoreTone,
    this.score,
  });

  final String label;
  final String? score;
  final Color labelTone;
  final Color scoreTone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SportikaType.bodyStrong.copyWith(color: labelTone),
          ),
        ),
        if (score != null) ...[
          const SizedBox(width: SportikaSpacing.sm),
          // A cricket score carries the over count, so the readout is allowed
          // to scale down instead of truncating digits.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 156),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                score!,
                maxLines: 1,
                softWrap: false,
                style: SportikaType.scoreSmall.copyWith(color: scoreTone),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Compact status filter row used above the list.
class MyMatchPhaseChips extends StatelessWidget {
  const MyMatchPhaseChips({
    super.key,
    required this.selected,
    required this.counts,
    required this.onChanged,
  });

  final MyMatchPhase selected;

  /// Row count per phase; only the four filterable ones are read.
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
            _phaseLabel(phase),
            badge: counts[phase] ?? 0,
            icon: _phaseIcon(phase),
          ),
      ],
    );
  }

  static String _phaseLabel(MyMatchPhase phase) => switch (phase) {
    MyMatchPhase.all => 'All',
    MyMatchPhase.upcoming => 'Upcoming',
    MyMatchPhase.live => 'Live',
    MyMatchPhase.completed => 'Completed',
  };

  static IconData? _phaseIcon(MyMatchPhase phase) => switch (phase) {
    MyMatchPhase.all => null,
    MyMatchPhase.upcoming => Icons.schedule_rounded,
    MyMatchPhase.live => Icons.sensors_rounded,
    MyMatchPhase.completed => Icons.flag_outlined,
  };
}
