import 'package:flutter/material.dart';
import 'package:sportika/features/matches/widgets/match_report_widgets.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Only event-backed statistics. Untracked metrics are deliberately omitted.
class FutsalMatchReport extends StatelessWidget {
  const FutsalMatchReport({
    super.key,
    required this.match,
    required this.progress,
  });
  final SportMatch match;
  final MatchProgress progress;

  @override
  Widget build(BuildContext context) {
    final events = match.events.where((e) => !e.voided).toList();
    int count(String kind, int side, [String? colour]) => events
        .where(
          (e) =>
              e.kind == kind &&
              e.side == side &&
              (colour == null || e.data['colour'] == colour),
        )
        .length;
    final elapsed = (progress.state['elapsed'] as num?)?.toInt() ?? 0;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('MATCH STATISTICS', style: SportikaType.label),
          const SizedBox(height: 14),
          MatchReportLegend(match: match),
          if (match.corrections.isNotEmpty)
            const Text(
              'Event log totals. The official corrected score is shown above.',
              style: SportikaType.caption,
            ),
          const SizedBox(height: 12),
          for (final metric in [
            'Goals',
            'Fouls',
            'Yellow cards',
            'Red cards',
            'Substitutions',
          ])
            MatchStatComparison(
              label: metric,
              home: switch (metric) {
                'Goals' => count('goal', 0),
                'Fouls' => count('foul', 0),
                'Yellow cards' => count('card', 0, 'yellow'),
                'Red cards' => count('card', 0, 'red'),
                _ => count('substitution', 0),
              },
              away: switch (metric) {
                'Goals' => count('goal', 1),
                'Fouls' => count('foul', 1),
                'Yellow cards' => count('card', 1, 'yellow'),
                'Red cards' => count('card', 1, 'red'),
                _ => count('substitution', 1),
              },
            ),
          const Divider(),
          if (progress.isComplete)
            Text(
              'Recorded playing time: ${elapsed ~/ 60}m ${elapsed % 60}s',
              style: SportikaType.caption,
            ),
          if (progress.state['extraTime'] == true)
            const Text('Extra time played', style: SportikaType.caption),
          if ((progress.state['shootoutTaken'] as List? ?? [0, 0]).any(
            (n) => n != 0,
          ))
            Text(
              'Penalty shootout: ${(progress.state['shootoutScores'] as List).join(' – ')}',
              style: SportikaType.bodyStrong,
            ),
          if (match.result != null)
            Text(
              match.publishedAt == null
                  ? 'Result awaiting organizer publication'
                  : 'Official result published',
              style: SportikaType.caption.copyWith(
                color: match.publishedAt == null
                    ? SportikaColors.gold
                    : SportikaColors.mint,
              ),
            ),
          if (events.any((e) => e.kind == 'goal')) ...[
            const SizedBox(height: 12),
            const Text('GOALSCORERS', style: SportikaType.label),
            for (final e in events.where((e) => e.kind == 'goal'))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${e.data['player'] ?? 'Scorer not recorded'}${e.data['goalType'] == 'ownGoal'
                      ? ' (OG)'
                      : e.data['goalType'] == 'penalty'
                      ? ' (P)'
                      : ''} · ${match.sideNames[e.side ?? 0]}',
                  style: SportikaType.caption,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
