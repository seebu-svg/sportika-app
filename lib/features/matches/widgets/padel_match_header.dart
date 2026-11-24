import 'package:flutter/material.dart';

import 'package:sportika/features/matches/widgets/match_detail_banner.dart';
import 'package:sportika/features/matches/widgets/padel_match_result.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/match_scoreboard.dart';

/// Photography-led presentation exclusive to Padel; scores retain their bindings.
class PadelMatchHeader extends StatelessWidget {
  const PadelMatchHeader({
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
    final completedSets = progress.state['completedSets'];
    final setCount = completedSets is List ? completedSets.length : null;
    final setsToWin = progress.state['setsToWin'];
    final format = setsToWin is num && setsToWin > 0
        ? 'Best of ${setsToWin.toInt() * 2 - 1}'
        : match.formatLabel;
    // Use recorded endpoints only; no synthetic running clock or pause totals.
    final end = match.completedAt ?? match.submittedAt;
    final elapsed = match.startedAt != null && end != null
        ? end.difference(match.startedAt!)
        : null;
    final status = paused ? 'Paused' : match.status.label;
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
              Text(
                match.title,
                style: SportikaType.hero,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: SportikaSpacing.sm),
              Text(
                [
                  match.isTournamentMatch ? 'Tournament' : 'Friendly',
                  if (match.discipline != MatchDiscipline.team)
                    match.discipline == MatchDiscipline.doubles
                        ? 'Doubles'
                        : 'Singles',
                  if (format.isNotEmpty) format,
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: SportikaSpacing.md),
              Wrap(
                spacing: SportikaSpacing.md,
                runSpacing: SportikaSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (match.isLive && !progress.isComplete && setCount != null)
                    Text(
                      'SET ${setCount + 1}',
                      style: SportikaType.micro.copyWith(
                        color: SportikaColors.mint,
                      ),
                    ),
                  Text(status, style: SportikaType.caption),
                  if (elapsed != null && !elapsed.isNegative)
                    Text(
                      '${elapsed.inHours > 0 ? '${elapsed.inHours}h ' : ''}${elapsed.inMinutes.remainder(60)}m elapsed',
                      style: SportikaType.caption.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: SportikaSpacing.md),
              const Divider(height: 1, color: SportikaColors.borderSubtle),
              const SizedBox(height: SportikaSpacing.md),
              if (result != null)
                PadelMatchResult(match: match)
              else
                MatchScoreboard(
                  sport: match.sport,
                  labels: names,
                  compact: true,
                  showDetails: false,
                  showOutcome: false,
                  progress:
                      !cancelled &&
                          (match.isLive ||
                              match.awaitingReview ||
                              result != null)
                      ? progress
                      : null,
                  result: result,
                  finished: match.isFinished,
                ),
              if (result == null &&
                  !cancelled &&
                  winner >= 0 &&
                  winner < names.length) ...[
                const SizedBox(height: SportikaSpacing.sm),
                Text(
                  '${names[winner]} · Winner',
                  style: SportikaType.bodyStrong.copyWith(
                    color: SportikaColors.gold,
                  ),
                ),
              ],
              if (result == null && outcome.isNotEmpty) ...[
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
