import 'package:flutter/material.dart';

import 'package:sportika/features/matches/scoring/match_scoring_shell.dart';
import 'package:sportika/features/matches/scoring/match_scoring_validator.dart';
import 'package:sportika/features/personal_games/scoring/badminton/badminton.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Badminton: who serves, rally point buttons, the 11-point interval, the game
/// grid and the 21-with-a-two-point-margin / 30 cap rules read from the match.
class BadmintonScoringWorkspace extends StatelessWidget {
  const BadmintonScoringWorkspace({
    super.key,
    required this.match,
    required this.progress,
    required this.accent,
    this.onRecord,
  });

  final SportMatch match;
  final MatchProgress progress;
  final Color accent;
  final RecordMatchEvent? onRecord;

  @override
  Widget build(BuildContext context) {
    final rules = match.rules;
    final gamesToWin = (rules['gamesToWin'] as num?)?.toInt() ?? 2;
    final toWin = (rules['pointsToWinGame'] as num?)?.toInt() ?? 21;
    final cap = (rules['cap'] as num?)?.toInt() ?? 30;
    final points = _pair(progress.state['points']);
    final gamesWon = _pair(progress.state['gamesWon']);
    final server = (progress.state['server'] as num?)?.toInt() ?? 0;
    final game = (progress.state['game'] as num?)?.toInt() ?? 1;
    final rawGames = progress.state['completedGames'];
    final completedGames = rawGames is List ? rawGames : const [];

    final displayPoints = progress.isComplete && completedGames.isNotEmpty
        ? _pair(completedGames.last)
        : points;
    final intervalAt = (toWin / 2).ceil();
    final interval =
        (points[0] == intervalAt && points[1] < intervalAt) ||
        (points[1] == intervalAt && points[0] < intervalAt);
    final gamePoint = _gamePoint(points, match.sideNames, toWin, cap);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      progress.isComplete
                          ? 'Match complete'
                          : 'Game $game · $toWin points, win by 2',
                      style: SportikaType.caption,
                    ),
                  ),
                  StatusPill(
                    '${match.discipline.label} · best of ${gamesToWin * 2 - 1}',
                    color: accent,
                  ),
                ],
              ),
              const SizedBox(height: SportikaSpacing.sm),
              Row(
                children: [
                  for (var side = 0; side < 2; side++) ...[
                    if (side == 1) const SizedBox(width: 8),
                    Expanded(
                      child: _SideCard(
                        name: match.sideNames[side],
                        games: gamesWon[side],
                        points: displayPoints[side],
                        serving: !progress.isComplete && server == side,
                        setsText: side < progress.lines.length
                            ? progress.lines[side].sub
                            : null,
                        accent: side == 0 ? accent : SportikaColors.mint,
                      ),
                    ),
                  ],
                ],
              ),
              if (interval || gamePoint != null) ...[
                const SizedBox(height: SportikaSpacing.sm),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (interval)
                      StatusPill(
                        '$intervalAt-point interval',
                        color: SportikaColors.gold,
                        icon: Icons.local_drink_outlined,
                      ),
                    if (gamePoint != null)
                      StatusPill(gamePoint, color: SportikaColors.mint),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: SportikaSpacing.sm),
        if (onRecord != null && !progress.isComplete)
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle('Rally won by', padding: EdgeInsets.zero),
                Row(
                  children: [
                    for (var side = 0; side < 2; side++) ...[
                      if (side == 1) const SizedBox(width: 8),
                      Expanded(
                        child: ScoringPad(
                          label: 'Rally',
                          hint: match.sideNames[side],
                          big: true,
                          tone: side == 0 ? accent : SportikaColors.mint,
                          onTap: () =>
                              onRecord!(BadmintonEngine.kRally, side, const {}),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: SportikaSpacing.sm),
                HelperText(
                  'Every rally scores. A game is won at $toWin with a two-point '
                  'margin, and the score is capped at $cap. Change ends after '
                  'each game.',
                ),
              ],
            ),
          ),
        if (!progress.isComplete) ...[
          Text(
            'Serving side: ${match.sideNames[server]} · receiving side: ${match.sideNames[1 - server]}',
            style: SportikaType.caption,
          ),
          if (match.discipline == MatchDiscipline.doubles)
            const HelperText(
              'Service is tracked by side. Individual server and receiver rotation is not available in the official match data.',
            ),
          if (completedGames.isNotEmpty && points.every((p) => p == 0))
            const InfoBanner(
              text: 'Game complete · change ends before the next rally. The winning side serves first.',
              tone: SportikaColors.gold,
            ),
          if (game == gamesToWin * 2 - 1 &&
              ((points[0] == intervalAt && points[1] < intervalAt) ||
                  (points[1] == intervalAt && points[0] < intervalAt)))
            const InfoBanner(
              text: 'Deciding game · interval and change of ends',
              tone: SportikaColors.gold,
            ),
        ],
        const SectionTitle('Games'),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (completedGames.isEmpty)
                const Text('No game finished yet.', style: SportikaType.caption)
              else
                for (var i = 0; i < completedGames.length; i++)
                  _GameRow(
                    index: i + 1,
                    games: _pair(completedGames[i]),
                    sides: match.sideNames,
                    accent: accent,
                    note: null,
                  ),
              if (!progress.isComplete)
                _GameRow(
                  index: completedGames.length + 1,
                  games: points,
                  sides: match.sideNames,
                  accent: accent,
                  note: 'In progress',
                ),
            ],
          ),
        ),
        const SectionTitle('Match statistics'),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Games won · ${gamesWon[0]} – ${gamesWon[1]}',
                style: SportikaType.bodyStrong,
              ),
              Text(
                'Rally points · ${match.events.where((e) => !e.voided && e.kind == BadmintonEngine.kRally && e.side == 0).length} – ${match.events.where((e) => !e.voided && e.kind == BadmintonEngine.kRally && e.side == 1).length}',
                style: SportikaType.caption,
              ),
              if (match.startedAt != null && match.completedAt != null)
                Text(
                  'Match duration · ${match.completedAt!.difference(match.startedAt!).inMinutes} min',
                  style: SportikaType.caption,
                ),
              if (match.corrections.isNotEmpty)
                const HelperText(
                  'Statistics reflect the rally log. Published corrections are shown in the official result.',
                ),
            ],
          ),
        ),
      ],
    );
  }

  static List<int> _pair(Object? raw) {
    final list = raw is List ? raw : const [];
    return [
      for (var i = 0; i < 2; i++)
        i < list.length ? ((list[i] as num?)?.toInt() ?? 0) : 0,
    ];
  }

  static String? _gamePoint(
    List<int> points,
    List<String> sides,
    int toWin,
    int cap,
  ) {
    if (points[0] >= cap - 1 && points[1] >= cap - 1) {
      return 'Golden point · next rally wins';
    }
    if (points[0] == points[1] && points[0] >= toWin - 1) {
      return 'Deuce · win by 2';
    }
    if (points[0] >= toWin - 1 && points[0] > points[1]) {
      return 'Game point · ${sides[0]}';
    }
    if (points[1] >= toWin - 1 && points[1] > points[0]) {
      return 'Game point · ${sides[1]}';
    }
    return null;
  }
}

class _SideCard extends StatelessWidget {
  const _SideCard({
    required this.name,
    required this.games,
    required this.points,
    required this.serving,
    required this.setsText,
    required this.accent,
  });

  final String name;
  final int games;
  final int points;
  final bool serving;
  final String? setsText;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: SportikaColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: serving ? accent : SportikaColors.borderSubtle,
          width: serving ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SportikaType.bodyStrong.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$points',
                style: SportikaType.title.copyWith(color: accent),
              ),
              const Spacer(),
              Text(
                '$games ${games == 1 ? 'game' : 'games'}',
                style: SportikaType.caption.copyWith(fontSize: 10),
              ),
            ],
          ),
          if ((setsText ?? '').isNotEmpty)
            Text(
              setsText!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SportikaType.caption.copyWith(fontSize: 10),
            ),
          if (serving)
            Text(
              'Serving · ${points.isEven ? 'right' : 'left'} court',
              style: SportikaType.micro.copyWith(
                color: SportikaColors.gold,
                fontSize: 9,
              ),
            ),
        ],
      ),
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({
    required this.index,
    required this.games,
    required this.sides,
    required this.accent,
    required this.note,
  });

  final int index;
  final List<int> games;
  final List<String> sides;
  final Color accent;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final winner = games[0] == games[1] ? -1 : (games[0] > games[1] ? 0 : 1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text('Game $index', style: SportikaType.caption),
          ),
          Text(
            '${games[0]} - ${games[1]}',
            style: SportikaType.bodyStrong.copyWith(
              color: note == null ? accent : SportikaColors.text,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              note ?? (winner < 0 ? 'Level' : '${sides[winner]} won'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SportikaType.caption.copyWith(fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}
