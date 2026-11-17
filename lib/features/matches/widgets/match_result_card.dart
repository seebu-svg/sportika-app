import 'package:flutter/material.dart';

import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Displays the recorded result, never a score reconstructed from older events.
class MatchResultCard extends StatelessWidget {
  const MatchResultCard({super.key, required this.match});
  final SportMatch match;

  @override
  Widget build(BuildContext context) {
    final result = match.result;
    if (result == null || match.status == FixtureStatus.cancelled) {
      return const SizedBox.shrink();
    }
    final published =
        match.status == FixtureStatus.published ||
        match.status == FixtureStatus.walkover;
    final names = match.sideLabels;
    return SurfaceCard(
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: SportikaSpacing.md,
            runSpacing: SportikaSpacing.xs,
            children: [
              Text(
                published ? 'OFFICIAL RESULT' : 'AWAITING REVIEW',
                style: SportikaType.micro.copyWith(
                  color: published
                      ? SportikaColors.textMuted
                      : SportikaColors.gold,
                ),
              ),
              if (match.corrections.isNotEmpty)
                const Text('Corrected', style: SportikaType.caption),
            ],
          ),
          const SizedBox(height: SportikaSpacing.sm),
          Text(_outcome(result, names), style: SportikaType.headline),
          if (result.detail.isNotEmpty) ...[
            const SizedBox(height: SportikaSpacing.xs),
            Text(result.detail, style: SportikaType.caption),
          ],
          const SizedBox(height: SportikaSpacing.lg),
          ResultScoreLines(
            labels: names,
            scores: result.sideScores,
            winnerIndex: result.winnerIndex,
            walkover: result.walkover,
          ),
          const SizedBox(height: SportikaSpacing.md),
          Text(
            !published
                ? 'Scoring is closed. The organizer reviews and publishes this result.'
                : 'Published ${dateShort(result.publishedAt.toLocal())}',
            style: SportikaType.caption,
          ),
          if (result.walkover) ...[
            const SizedBox(height: SportikaSpacing.xs),
            const Text(
              'Awarded without a played result.',
              style: SportikaType.caption,
            ),
          ],
        ],
      ),
    );
  }
}

String _outcome(OfficialResult result, List<String> names) {
  if (result.headline.isNotEmpty) return result.headline;
  if (result.walkover) return 'Awarded by walkover';
  if (result.winnerIndex < 0) return 'Match drawn';
  if (result.winnerIndex < names.length) {
    return '${names[result.winnerIndex]} won';
  }
  return 'Result recorded';
}

/// Shared scoreboard for result review and correction comparisons.
/// Scores are opaque official strings; their format belongs to each sport.
class ResultScoreLines extends StatelessWidget {
  const ResultScoreLines({
    super.key,
    required this.labels,
    required this.scores,
    this.winnerIndex = -1,
    this.walkover = false,
  });
  final List<String> labels;
  final List<String> scores;
  final int winnerIndex;
  final bool walkover;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final stacked = constraints.maxWidth < SportikaSpacing.xl * 12 * scale;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1, color: SportikaColors.borderSubtle),
          for (var side = 0; side < labels.length; side++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SportikaSpacing.md),
              child: Builder(
                builder: (context) {
                  final winner = winnerIndex == side;
                  final name = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(labels[side], style: SportikaType.bodyStrong),
                      if (winner) ...[
                        const SizedBox(height: SportikaSpacing.xs),
                        Text(
                          walkover ? 'Awarded · Walkover' : 'Winner',
                          style: SportikaType.caption.copyWith(
                            color: SportikaColors.mint,
                          ),
                        ),
                      ],
                    ],
                  );
                  final score = Text(
                    walkover
                        ? winner
                              ? 'W/O'
                              : '—'
                        : scores.length > side && scores[side].isNotEmpty
                        ? scores[side]
                        : '—',
                    textAlign: stacked ? TextAlign.start : TextAlign.end,
                    style: SportikaType.score.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  );
                  return stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            name,
                            const SizedBox(height: SportikaSpacing.sm),
                            score,
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: name),
                            const SizedBox(width: SportikaSpacing.lg),
                            Flexible(child: score),
                          ],
                        );
                },
              ),
            ),
            const Divider(height: 1, color: SportikaColors.borderSubtle),
          ],
        ],
      );
    },
  );
}

class MatchCorrectionHistory extends StatelessWidget {
  const MatchCorrectionHistory({super.key, required this.match});
  final SportMatch match;

  @override
  Widget build(BuildContext context) {
    final corrections = List<ResultCorrection>.from(match.corrections)
      ..sort((a, b) => b.at.compareTo(a.at));
    if (corrections.isEmpty) return const SizedBox.shrink();
    return SurfaceCard(
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('CORRECTION HISTORY', style: SportikaType.label),
          const SizedBox(height: SportikaSpacing.md),
          _CorrectionEntry(
            correction: corrections.first,
            names: match.sideLabels,
          ),
          if (corrections.length > 1) ...[
            const SizedBox(height: SportikaSpacing.sm),
            ExpansionTile(
              key: PageStorageKey('match-corrections-${match.id}'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              iconColor: SportikaColors.textMuted,
              collapsedIconColor: SportikaColors.textMuted,
              title: Text(
                'Older corrections (${corrections.length - 1})',
                style: SportikaType.action,
              ),
              children: [
                for (final correction in corrections.skip(1)) ...[
                  const Divider(height: 1, color: SportikaColors.borderSubtle),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: SportikaSpacing.md,
                    ),
                    child: _CorrectionEntry(
                      correction: correction,
                      names: match.sideLabels,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CorrectionEntry extends StatelessWidget {
  const _CorrectionEntry({required this.correction, required this.names});
  final ResultCorrection correction;
  final List<String> names;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(dateShort(correction.at.toLocal()), style: SportikaType.caption),
      const SizedBox(height: SportikaSpacing.xs),
      Text(correction.reason, style: SportikaType.bodyStrong),
      const SizedBox(height: SportikaSpacing.md),
      LayoutBuilder(
        builder: (context, constraints) {
          final previous = _CorrectionVersion(
            label: 'PREVIOUS',
            result: correction.previous,
            names: names,
          );
          final updated = _CorrectionVersion(
            label: 'UPDATED',
            result: correction.current,
            names: names,
          );
          if (constraints.maxWidth >=
              SportikaSpacing.xl *
                  20 *
                  MediaQuery.textScalerOf(context).scale(1)) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: previous),
                const SizedBox(width: SportikaSpacing.lg),
                Expanded(child: updated),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              previous,
              const SizedBox(height: SportikaSpacing.md),
              updated,
            ],
          );
        },
      ),
    ],
  );
}

class _CorrectionVersion extends StatelessWidget {
  const _CorrectionVersion({
    required this.label,
    required this.result,
    required this.names,
  });
  final String label;
  final OfficialResult result;
  final List<String> names;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: SportikaType.micro),
      const SizedBox(height: SportikaSpacing.xs),
      Text(_outcome(result, names), style: SportikaType.body),
      if (result.detail.isNotEmpty)
        Text(result.detail, style: SportikaType.caption),
      const SizedBox(height: SportikaSpacing.sm),
      for (var side = 0; side < names.length; side++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: SportikaSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(names[side], style: SportikaType.caption)),
              const SizedBox(width: SportikaSpacing.sm),
              Flexible(
                child: Text(
                  result.walkover
                      ? result.winnerIndex == side
                            ? 'W/O'
                            : '—'
                      : result.sideScores.length > side &&
                            result.sideScores[side].isNotEmpty
                      ? result.sideScores[side]
                      : '—',
                  textAlign: TextAlign.end,
                  style: SportikaType.bodyStrong.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
