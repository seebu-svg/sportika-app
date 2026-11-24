import 'package:flutter/material.dart';

import 'package:sportika/features/matches/widgets/match_detail_banner.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/match_scoreboard.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Match identity and authoritative score, without nested result surfaces.
class MatchDetailHero extends StatelessWidget {
  const MatchDetailHero({
    super.key,
    required this.match,
    required this.progress,
  });
  final SportMatch match;
  final MatchProgress progress;

  @override
  Widget build(BuildContext context) {
    final cancelled = match.status == FixtureStatus.cancelled;
    final result = cancelled ? null : match.result;
    final paused = match.isLive && match.isPaused;
    final winner =
        result?.winnerIndex ??
        (progress.isComplete ? progress.winnerIndex : -1);
    final names = [
      for (var i = 0; i < 2; i++)
        match.sideLabels.length > i ? match.sideLabels[i] : 'Side ${i + 1}',
    ];
    final outcome = cancelled
        ? 'No official result was awarded.'
        : result?.headline.isNotEmpty == true
        ? result!.headline
        : result != null
        ? (result.walkover
              ? 'Awarded by walkover'
              : result.winnerIndex < 0
              ? 'Match drawn'
              : '')
        : progress.isComplete
        ? progress.resultLabel
        : '';
    final competition = match.rules['competitionName'];
    final round = match.rules['stage'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MatchDetailBanner(sport: match.sport),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SportikaSpacing.lg,
            SportikaSpacing.xs,
            SportikaSpacing.lg,
            SportikaSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(match.title, style: SportikaType.hero),
              const SizedBox(height: SportikaSpacing.sm),
              Text(
                [
                  match.sport.label,
                  if (match.formatLabel.isNotEmpty) match.formatLabel,
                ].join(' · '),
                style: SportikaType.caption,
              ),
              if ((competition is String && competition.isNotEmpty) ||
                  (round is String && round.isNotEmpty)) ...[
                const SizedBox(height: SportikaSpacing.xs),
                Text(
                  [
                    if (competition is String && competition.isNotEmpty)
                      competition,
                    if (round is String && round.isNotEmpty) round,
                  ].join(' · '),
                  style: SportikaType.caption,
                ),
              ],
              const SizedBox(height: SportikaSpacing.md),
              Text(
                paused ? 'Paused' : match.status.label,
                style: SportikaType.caption.copyWith(
                  color: paused
                      ? SportikaColors.gold
                      : statusColor(match.status.key),
                ),
              ),
              const SizedBox(height: SportikaSpacing.md),
              const Divider(height: 1, color: SportikaColors.borderSubtle),
              const SizedBox(height: SportikaSpacing.md),
              MatchScoreboard(
                sport: match.sport,
                labels: names,
                compact: true,
                showDetails: false,
                showOutcome: false,
                progress:
                    !cancelled &&
                        (match.isLive || match.awaitingReview || result != null)
                    ? progress
                    : null,
                result: result,
                finished: match.isFinished,
              ),
              if (!cancelled && winner >= 0 && winner < names.length) ...[
                const SizedBox(height: SportikaSpacing.sm),
                Text(
                  '${names[winner]} · Winner',
                  style: SportikaType.bodyStrong.copyWith(
                    color: SportikaColors.gold,
                  ),
                ),
              ],
              if (outcome.isNotEmpty) ...[
                const SizedBox(height: SportikaSpacing.xs),
                Text(outcome, style: SportikaType.body),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
