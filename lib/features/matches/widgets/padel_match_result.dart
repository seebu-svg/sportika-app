import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// A Padel result presentation driven exclusively by the recorded result.
class PadelMatchResult extends StatelessWidget {
  const PadelMatchResult({super.key, required this.match});
  final SportMatch match;

  // Only display a matrix when both official strings describe the same sets.
  // Custom corrections remain visible verbatim instead of being reinterpreted.
  List<List<String>> _sets(List<String> scores) {
    if (scores.length != 2) return const [];
    final pattern = RegExp(r'^(\d+)\s*[-–]\s*(\d+)$');
    final first = scores[0].split(',');
    final second = scores[1].split(',');
    if (first.length != second.length) return const [];
    final sets = <List<String>>[];
    for (var i = 0; i < first.length; i++) {
      final a = pattern.firstMatch(first[i].trim());
      final b = pattern.firstMatch(second[i].trim());
      if (a == null || b == null || a[1] != b[2] || a[2] != b[1]) {
        return const [];
      }
      if (int.tryParse(a[1]!) == null || int.tryParse(a[2]!) == null) {
        return const [];
      }
      sets.add([a[1]!, a[2]!]);
    }
    return sets;
  }

  @override
  Widget build(BuildContext context) {
    final result = match.result;
    if (result == null || match.status == FixtureStatus.cancelled) {
      return const SizedBox.shrink();
    }
    final published =
        match.status == FixtureStatus.published ||
        match.status == FixtureStatus.walkover;
    final names = [
      for (var side = 0; side < 2; side++)
        match.sideLabels.length > side
            ? match.sideLabels[side]
            : 'Side ${side + 1}',
    ];
    final winner = result.winnerIndex;
    final hasWinner = winner >= 0 && winner < 2;
    final players = hasWinner
        ? match
              .participantsOnSide(winner)
              .take(match.discipline == MatchDiscipline.doubles ? 2 : 1)
              .toList()
        : <MatchParticipant>[];
    final sets = result.walkover ? <List<String>>[] : _sets(result.sideScores);
    final title = hasWinner
        ? names[winner]
        : winner < 0
        ? 'Match drawn'
        : 'Result recorded';
    Widget score(int side) => Text(
      result.walkover
          ? winner == side
                ? 'W/O'
                : '—'
          : result.sideValues.length > side
          ? '${result.sideValues[side]}'
          : '—',
      style: SportikaType.hero.copyWith(
        color: winner == side ? SportikaColors.text : SportikaColors.textMuted,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      decoration: BoxDecoration(
        color: SportikaColors.surfaceSunken,
        borderRadius: BorderRadius.circular(SportikaRadius.md),
        border: Border.all(color: SportikaColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: SportikaSpacing.md,
            runSpacing: SportikaSpacing.xs,
            children: [
              Text(
                published
                    ? result.walkover
                          ? 'OFFICIAL RESULT · WALKOVER'
                          : 'FINAL · OFFICIAL RESULT'
                    : 'AWAITING REVIEW',
                style: SportikaType.micro,
              ),
              if (match.corrections.isNotEmpty)
                const Text('Corrected', style: SportikaType.micro),
            ],
          ),
          const SizedBox(height: SportikaSpacing.md),
          if (players.isNotEmpty) ...[
            Wrap(
              spacing: SportikaSpacing.md,
              runSpacing: SportikaSpacing.sm,
              children: [
                for (final player in players) _WinnerAvatar(player: player),
              ],
            ),
            const SizedBox(height: SportikaSpacing.sm),
          ],
          Text(title, style: SportikaType.hero),
          if (hasWinner) ...[
            const SizedBox(height: SportikaSpacing.xs),
            Text(
              result.walkover ? 'Awarded by walkover' : 'Match winner',
              style: SportikaType.caption.copyWith(color: SportikaColors.gold),
            ),
          ],
          const SizedBox(height: SportikaSpacing.lg),
          Text(
            result.walkover ? 'AWARDED RESULT' : 'FINAL SETS',
            style: SportikaType.micro,
          ),
          const SizedBox(height: SportikaSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    score(0),
                    const SizedBox(height: SportikaSpacing.xs),
                    Text(names[0], style: SportikaType.bodyStrong),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: SportikaSpacing.md),
                child: Text('–', style: SportikaType.title),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    score(1),
                    const SizedBox(height: SportikaSpacing.xs),
                    Text(
                      names[1],
                      textAlign: TextAlign.end,
                      style: SportikaType.bodyStrong,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!result.walkover) ...[
            const SizedBox(height: SportikaSpacing.md),
            const Divider(height: 1, color: SportikaColors.borderSubtle),
            if (sets.isNotEmpty)
              LayoutBuilder(
                builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(context).scale(1);
                  final minWidth =
                      (SportikaSpacing.xl * 4 +
                          sets.length * SportikaSpacing.xl * 2) *
                      scale;
                  Widget cell(Widget child) => Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: SportikaSpacing.sm,
                      horizontal: SportikaSpacing.xs,
                    ),
                    child: child,
                  );
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: minWidth > constraints.maxWidth
                          ? minWidth
                          : constraints.maxWidth,
                      child: Table(
                        columnWidths: {
                          0: FixedColumnWidth(SportikaSpacing.xl * 4 * scale),
                        },
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.middle,
                        children: [
                          TableRow(
                            children: [
                              cell(
                                const Text('TEAM', style: SportikaType.micro),
                              ),
                              for (var i = 0; i < sets.length; i++)
                                cell(
                                  Text(
                                    'S${i + 1}',
                                    textAlign: TextAlign.center,
                                    style: SportikaType.micro,
                                  ),
                                ),
                            ],
                          ),
                          for (var side = 0; side < 2; side++)
                            TableRow(
                              children: [
                                cell(
                                  Text(
                                    names[side],
                                    style: SportikaType.bodyStrong,
                                  ),
                                ),
                                for (final set in sets)
                                  cell(
                                    Text(
                                      set[side],
                                      textAlign: TextAlign.center,
                                      style: SportikaType.scoreSmall.copyWith(
                                        color:
                                            int.parse(set[side]) >
                                                int.parse(set[1 - side])
                                            ? SportikaColors.text
                                            : SportikaColors.textDim,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
              )
            else
              for (var side = 0; side < 2; side++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: SportikaSpacing.sm,
                  ),
                  child: Text(
                    '${names[side]} · ${result.sideScores.length > side && result.sideScores[side].isNotEmpty ? result.sideScores[side] : '—'}',
                    style: SportikaType.body,
                  ),
                ),
          ],
          if (result.headline.isNotEmpty || result.detail.isNotEmpty) ...[
            const SizedBox(height: SportikaSpacing.sm),
            if (result.headline.isNotEmpty)
              Text(result.headline, style: SportikaType.body),
            if (result.detail.isNotEmpty)
              Text(result.detail, style: SportikaType.caption),
          ],
          const SizedBox(height: SportikaSpacing.md),
          Text(
            published ? 'Published ${dateShort(result.publishedAt.toLocal())}' : 'Scoring is closed. The organizer reviews and publishes this result.',
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

class _WinnerAvatar extends StatelessWidget {
  const _WinnerAvatar({required this.player});
  final MatchParticipant player;
  @override
  Widget build(BuildContext context) {
    final account = context.watch<SessionController>().accountById(
      player.profileId,
    );
    return SizedBox(
      width: SportikaSpacing.xl * 3,
      child: Column(
        children: [
          PlayerAvatar(
            initials: initialsOf(player.displayName),
            photoUrl: account?.photoUrl,
            photoPath: account?.photoPath,
            size: SportikaSpacing.xl * 2,
            color: SportikaColors.textMuted,
            ring: SportikaColors.surfaceSunken,
          ),
          const SizedBox(height: SportikaSpacing.xs),
          Tooltip(
            message: player.displayName,
            child: Text(
              player.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: SportikaType.caption,
            ),
          ),
        ],
      ),
    );
  }
}
