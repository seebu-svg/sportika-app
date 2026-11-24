import 'package:flutter/material.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Completed rounds come directly from the sport engine's event fold.
class RacketMatchReport extends StatelessWidget {
  const RacketMatchReport({
    super.key,
    required this.match,
    required this.progress,
  });
  final SportMatch match;
  final MatchProgress progress;

  // Validate only the display value; completion remains the engine's decision.
  static num? _score(dynamic round, int side) {
    if (round is! List || round.length <= side) return null;
    final value = round[side];
    return value is num &&
            value.isFinite &&
            value >= 0 &&
            value == value.truncateToDouble()
        ? value
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final padel = match.sport == Sport.padel;
    final raw = progress.state[padel ? 'completedSets' : 'completedGames'];
    final rounds = raw is List ? raw : const [];
    final kind = padel ? 'Set' : 'Game';
    // A racket match is played as singles or doubles; saying which removes the
    // ambiguity a two-name header leaves for a pair.
    final discipline = match.discipline == MatchDiscipline.team
        ? null
        : match.discipline.label;
    final labels = match.sideLabels;

    Widget cell(Widget child, {bool team = false}) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SportikaSpacing.sm,
        vertical: SportikaSpacing.md,
      ),
      child: Align(
        alignment: team ? AlignmentDirectional.centerStart : Alignment.center,
        child: child,
      ),
    );

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            discipline == null ? '$kind Scores' : '$kind Scores · $discipline',
            style: SportikaType.bodyStrong,
          ),
          const SizedBox(height: SportikaSpacing.md),
          if (match.corrections.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: SportikaSpacing.md),
              child: Text(
                'This round breakdown reflects the event log and may differ from the corrected official result shown above.',
                style: SportikaType.caption,
              ),
            ),
          if (rounds.isEmpty)
            Text(
              'No completed ${padel ? 'sets' : 'games'} yet. Recorded rounds appear here as play progresses.',
              style: SportikaType.caption,
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(1);
                final teamWidth = SportikaSpacing.xl * 5 * scale;
                final scoreWidth = SportikaSpacing.lg * 3 * scale;
                final minimumWidth = teamWidth + rounds.length * scoreWidth;
                final scrolls = minimumWidth > constraints.maxWidth;
                final width = scrolls ? minimumWidth : constraints.maxWidth;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: width,
                        child: Table(
                          columnWidths: {
                            0: FixedColumnWidth(teamWidth),
                            for (var i = 0; i < rounds.length; i++)
                              i + 1: const FlexColumnWidth(),
                          },
                          defaultVerticalAlignment:
                              TableCellVerticalAlignment.middle,
                          border: const TableBorder(
                            horizontalInside: BorderSide(
                              color: SportikaColors.borderSubtle,
                            ),
                          ),
                          children: [
                            TableRow(
                              decoration: const BoxDecoration(
                                color: SportikaColors.surfaceSunken,
                              ),
                              children: [
                                cell(
                                  const Text(
                                    'Team',
                                    style: SportikaType.caption,
                                  ),
                                  team: true,
                                ),
                                for (var i = 0; i < rounds.length; i++)
                                  cell(
                                    Text(
                                      '${i + 1}',
                                      semanticsLabel: '$kind ${i + 1}',
                                      style: SportikaType.caption,
                                    ),
                                  ),
                              ],
                            ),
                            for (var side = 0; side < 2; side++)
                              TableRow(
                                children: [
                                  cell(
                                    Text(
                                      labels.length > side &&
                                              labels[side].trim().isNotEmpty
                                          ? labels[side]
                                          : 'Team ${side + 1}',
                                      style: SportikaType.bodyStrong,
                                    ),
                                    team: true,
                                  ),
                                  for (var i = 0; i < rounds.length; i++)
                                    cell(_scoreCell(rounds[i], side, kind, i)),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (scrolls) ...[
                      const SizedBox(height: SportikaSpacing.sm),
                      const Text(
                        'Scroll horizontally to view all scores',
                        style: SportikaType.caption,
                      ),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _scoreCell(dynamic round, int side, String kind, int index) {
    final score = _score(round, side);
    final opponent = _score(round, 1 - side);
    final higher =
        round is List &&
        round.length == 2 &&
        score != null &&
        opponent != null &&
        score > opponent;
    return Text(
      score == null ? '—' : '$score',
      semanticsLabel:
          '$kind ${index + 1}, ${score == null ? 'score unavailable' : '$score'}',
      style: SportikaType.scoreSmall.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        color: higher ? SportikaColors.text : SportikaColors.textMuted,
        fontWeight: higher
            ? SportikaType.bodyStrong.fontWeight
            : SportikaType.body.fontWeight,
      ),
    );
  }
}
