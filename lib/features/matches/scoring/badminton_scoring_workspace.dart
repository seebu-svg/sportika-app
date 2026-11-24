import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sportika/features/matches/scoring/match_scoring_shell.dart';
import 'package:sportika/features/matches/scoring/match_scoring_validator.dart';
import 'package:sportika/features/personal_games/scoring/badminton/badminton.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/default_avatar.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Courtside badminton scoring UI. All scoring remains authoritative in the
/// existing engine. The parent shell owns persistence and match actions.
///
/// For a genuinely sticky scoring dock, mount [BadmintonRallyDock] in the
/// parent Scaffold.bottomNavigationBar, and set [showInlineRallyControls] to
/// false here. A child of a scrollable Column cannot be made screen-sticky.
class BadmintonScoringWorkspace extends StatelessWidget {
  const BadmintonScoringWorkspace({
    super.key,
    required this.match,
    required this.progress,
    required this.accent,
    this.onRecord,
    this.onUndo,
    this.onPause,
    this.onResume,
    this.onFinish,
    this.isPaused = false,
    this.showInlineRallyControls = true,
  });

  final SportMatch match;
  final MatchProgress progress;
  final Color accent;
  final RecordMatchEvent? onRecord;
  final VoidCallback? onUndo;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onFinish;
  final bool isPaused;
  final bool showInlineRallyControls;

  static List<int> _pair(Object? raw) {
    final values = raw is List ? raw : const [];
    return List<int>.generate(2, (i) {
      if (i >= values.length) return 0;
      final value = values[i];
      return value is num ? value.toInt() : 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final gamesToWin = (match.rules['gamesToWin'] as num?)?.toInt() ?? 2;
    final target = (match.rules['pointsToWinGame'] as num?)?.toInt() ?? 21;
    final cap = (match.rules['cap'] as num?)?.toInt() ?? 30;
    final bestOf = gamesToWin * 2 - 1;

    final points = _pair(progress.state['points']);
    final gamesWon = _pair(progress.state['gamesWon']);

    final rawServer = (progress.state['server'] as num?)?.toInt() ?? 0;
    final server = rawServer == 1 ? 1 : 0;

    final game = (progress.state['game'] as num?)?.toInt() ?? 1;

    final rawGames = progress.state['completedGames'];
    final completed = rawGames is List ? rawGames : const [];

    final finalPoints = progress.isComplete && completed.isNotEmpty
        ? _pair(completed.last)
        : points;

    final situation = progress.isComplete
        ? null
        : BadmintonEngine.situationFor(
            points: points,
            gamesWon: gamesWon,
            gamesToWin: gamesToWin,
            toWin: target,
            cap: cap,
            sides: match.sideNames,
          );

    final serveCourt = BadmintonEngine.serveCourtFor(points[server]);

    final betweenGames =
        !progress.isComplete &&
        completed.isNotEmpty &&
        points.every((value) => value == 0);

    final decidingInterval =
        game == bestOf && situation?.kind == BadmintonSituationKind.interval;

    final rallies = [0, 0];

    for (final event in match.events) {
      if (!event.voided && event.kind == BadmintonEngine.kRally) {
        if (event.side == 0) rallies[0]++;
        if (event.side == 1) rallies[1]++;
      }
    }

    final duration = match.startedAt != null && match.completedAt != null
        ? match.completedAt!.difference(match.startedAt!).inMinutes
        : null;

    final canScore = onRecord != null && !progress.isComplete && !isPaused;

    final canControl = !progress.isComplete;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          discipline: match.discipline.label,
          game: game,
          bestOf: bestOf,
          complete: progress.isComplete,
          paused: isPaused,
          accent: accent,
        ),

        const SizedBox(height: SportikaSpacing.sm),

        _Scoreboard(
          names: match.sideNames,
          points: finalPoints,
          games: gamesWon,
          server: progress.isComplete ? null : server,
          accent: accent,
          complete: progress.isComplete,
        ),

        if (progress.isComplete) ...[
          const SizedBox(height: SportikaSpacing.sm),
          _ResultBanner(names: match.sideNames, gamesWon: gamesWon),
        ] else ...[
          const SizedBox(height: SportikaSpacing.sm),

          _ServiceCourt(
            names: match.sideNames,
            server: server,
            court: serveCourt,
            doubles: match.discipline == MatchDiscipline.doubles,
            accent: accent,
          ),

          if (betweenGames || decidingInterval || situation != null) ...[
            const SizedBox(height: SportikaSpacing.sm),

            _SituationBanner(
              situation: situation,
              betweenGames: betweenGames,
              decidingInterval: decidingInterval,
            ),
          ],
        ],

        if (showInlineRallyControls &&
            onRecord != null &&
            !progress.isComplete) ...[
          const SizedBox(height: SportikaSpacing.md),

          BadmintonRallyDock(
            names: match.sideNames,
            accent: accent,
            enabled: canScore,
            onRally: (side) =>
                onRecord!(BadmintonEngine.kRally, side, const {}),
            onUndo: canControl ? onUndo : null,
            onPauseResume: canControl ? (isPaused ? onResume : onPause) : null,
            onFinish: canControl ? onFinish : null,
            paused: isPaused,
          ),
        ] else if (canControl &&
            (onUndo != null ||
                onPause != null ||
                onResume != null ||
                onFinish != null)) ...[
          const SizedBox(height: SportikaSpacing.md),

          _ActionBar(
            onUndo: onUndo,
            onPauseResume: isPaused ? onResume : onPause,
            onFinish: onFinish,
            paused: isPaused,
          ),
        ],

        const SizedBox(height: SportikaSpacing.md),

        _GameProgress(
          names: match.sideNames,
          completed: completed,
          current: points,
          complete: progress.isComplete,
          bestOf: bestOf,
          accent: accent,
        ),

        const SizedBox(height: SportikaSpacing.md),

        _Insights(
          games: gamesWon,
          rallies: rallies,
          duration: duration,
          corrected: match.corrections.isNotEmpty,
        ),

        const SizedBox(height: SportikaSpacing.sm),

        _Rules(
          target: target,
          cap: cap,
          bestOf: bestOf,
          doubles: match.discipline == MatchDiscipline.doubles,
        ),
      ],
    );
  }
}

// ============================================================
// MATCH HEADER
// ============================================================

class _Header extends StatelessWidget {
  const _Header({
    required this.discipline,
    required this.game,
    required this.bestOf,
    required this.complete,
    required this.paused,
    required this.accent,
  });

  final String discipline;
  final int game;
  final int bestOf;
  final bool complete;
  final bool paused;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sports_tennis_rounded, color: accent, size: 20),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: Text(
                  'BADMINTON · $discipline',
                  style: SportikaType.micro.copyWith(color: accent),
                ),
              ),
              StatusPill(
                complete
                    ? 'FINAL'
                    : paused
                    ? 'PAUSED'
                    : 'LIVE',
                color: complete
                    ? SportikaColors.mint
                    : paused
                    ? SportikaColors.gold
                    : accent,
              ),
            ],
          ),

          const SizedBox(height: SportikaSpacing.sm),

          Text(
            complete ? 'Match complete' : 'Game $game of $bestOf',
            style: SportikaType.title,
          ),

          Text(
            'Official scoring · Best of $bestOf',
            style: SportikaType.caption,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// UNIFIED SCOREBOARD
// ============================================================

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({
    required this.names,
    required this.points,
    required this.games,
    required this.server,
    required this.accent,
    required this.complete,
  });

  final List<String> names;
  final List<int> points;
  final List<int> games;
  final int? server;
  final Color accent;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('SCOREBOARD', style: SportikaType.micro),
              ),
              StatusPill(
                complete ? 'FINAL GAME' : 'RALLY POINTS',
                color: accent,
              ),
            ],
          ),

          const SizedBox(height: SportikaSpacing.md),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _ScoreSide(
                  name: names[0],
                  points: points[0],
                  games: games[0],
                  serving: server == 0,
                  tone: accent,
                ),
              ),
              Text(
                '–',
                style: SportikaType.title.copyWith(
                  color: SportikaColors.textMuted,
                ),
              ),
              Expanded(
                child: _ScoreSide(
                  name: names[1],
                  points: points[1],
                  games: games[1],
                  serving: server == 1,
                  tone: SportikaColors.mint,
                ),
              ),
            ],
          ),

          const SizedBox(height: SportikaSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: SportikaSpacing.sm),

          Text(
            'GAMES WON    ${games[0]}  –  ${games[1]}',
            style: SportikaType.bodyStrong,
          ),
        ],
      ),
    );
  }
}

class _ScoreSide extends StatelessWidget {
  const _ScoreSide({
    required this.name,
    required this.points,
    required this.games,
    required this.serving,
    required this.tone,
  });

  final String name;
  final int points;
  final int games;
  final bool serving;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const BrandedDefaultAvatar(size: 40),

        const SizedBox(height: SportikaSpacing.sm),

        Text(
          name,
          style: SportikaType.bodyStrong,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: SportikaSpacing.xs),

        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: FittedBox(
            key: ValueKey(points),
            fit: BoxFit.scaleDown,
            child: Text(
              '$points',
              style: SportikaType.title.copyWith(color: tone, fontSize: 52),
            ),
          ),
        ),

        Text(
          '$games ${games == 1 ? 'game' : 'games'}',
          style: SportikaType.caption,
        ),

        if (serving) ...[
          const SizedBox(height: SportikaSpacing.xs),
          StatusPill('SERVING', color: tone, icon: Icons.sports_tennis_rounded),
        ],
      ],
    );
  }
}

// ============================================================
// SERVICE COURT
// ============================================================

/// Court diagram is illustrative: only the serving SIDE and court are known.
/// It deliberately does not claim to identify individual doubles players.
class _ServiceCourt extends StatelessWidget {
  const _ServiceCourt({
    required this.names,
    required this.server,
    required this.court,
    required this.doubles,
    required this.accent,
  });

  final List<String> names;
  final int server;
  final String court;
  final bool doubles;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final serving = names[server];
    final receiving = names[1 - server];

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('SERVICE POSITION', style: SportikaType.bodyStrong),
              ),
              StatusPill('$court court', color: accent),
            ],
          ),

          const SizedBox(height: SportikaSpacing.sm),

          Text(
            '$serving serving  →  $receiving receiving',
            style: SportikaType.caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: SportikaSpacing.sm),

          SizedBox(
            height: 116,
            child: CustomPaint(
              painter: _CourtPainter(
                accent: accent,
                surface: SportikaColors.surfaceAlt,
                line: SportikaColors.borderSubtle,
                servingRight: court.toLowerCase().contains('right'),
                serverOnLeft: server == 0,
              ),
            ),
          ),

          if (doubles) ...[
            const SizedBox(height: SportikaSpacing.sm),
            const HelperText(
              'Team-level service only. Individual doubles server '
              'and receiver positions are not recorded in this match.',
            ),
          ],
        ],
      ),
    );
  }
}

class _CourtPainter extends CustomPainter {
  const _CourtPainter({
    required this.accent,
    required this.surface,
    required this.line,
    required this.servingRight,
    required this.serverOnLeft,
  });

  final Color accent;
  final Color surface;
  final Color line;
  final bool servingRight;
  final bool serverOnLeft;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect,
        const Radius.circular(SportikaRadius.control),
      ),
      Paint()..color = surface,
    );

    final paint = Paint()
      ..color = line
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawRect(rect.deflate(7), paint);

    final left = rect.left + 7;
    final right = rect.right - 7;
    final top = rect.top + 7;
    final bottom = rect.bottom - 7;
    final middle = (left + right) / 2;
    final centerY = (top + bottom) / 2;

    canvas.drawLine(Offset(middle, top), Offset(middle, bottom), paint);

    canvas.drawLine(Offset(left, centerY), Offset(right, centerY), paint);

    canvas.drawLine(
      Offset((left + middle) / 2, top),
      Offset((left + middle) / 2, bottom),
      paint,
    );

    canvas.drawLine(
      Offset((middle + right) / 2, top),
      Offset((middle + right) / 2, bottom),
      paint,
    );

    final x = serverOnLeft ? (left + middle) / 2 : (middle + right) / 2;

    final y = servingRight
        ? top + (bottom - top) * .25
        : top + (bottom - top) * .75;

    canvas.drawCircle(Offset(x, y), 9, Paint()..color = accent);

    canvas.drawCircle(
      Offset(x, y),
      12,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CourtPainter oldDelegate) =>
      oldDelegate.accent != accent ||
      oldDelegate.surface != surface ||
      oldDelegate.line != line ||
      oldDelegate.servingRight != servingRight ||
      oldDelegate.serverOnLeft != serverOnLeft;
}

// ============================================================
// MATCH SITUATIONS
// ============================================================

class _SituationBanner extends StatelessWidget {
  const _SituationBanner({
    required this.situation,
    required this.betweenGames,
    required this.decidingInterval,
  });

  final BadmintonSituation? situation;
  final bool betweenGames;
  final bool decidingInterval;

  @override
  Widget build(BuildContext context) {
    if (betweenGames) {
      return const InfoBanner(
        icon: Icons.swap_horiz_rounded,
        text:
            'Game complete. Change ends before the next rally. '
            'The winning side serves first.',
        tone: SportikaColors.gold,
      );
    }

    if (decidingInterval) {
      return const InfoBanner(
        icon: Icons.swap_horiz_rounded,
        text: 'Deciding-game interval. Change ends at 11 points.',
        tone: SportikaColors.gold,
      );
    }

    if (situation == null) {
      return const SizedBox.shrink();
    }

    final tone = switch (situation!.kind) {
      BadmintonSituationKind.interval => SportikaColors.gold,
      BadmintonSituationKind.goldenPoint => SportikaColors.gold,
      BadmintonSituationKind.deuce => SportikaColors.gold,
      _ => SportikaColors.mint,
    };

    final icon = switch (situation!.kind) {
      BadmintonSituationKind.interval => Icons.local_drink_outlined,
      BadmintonSituationKind.goldenPoint => Icons.flag_outlined,
      BadmintonSituationKind.deuce => Icons.balance_outlined,
      _ => Icons.info_outline_rounded,
    };

    return InfoBanner(icon: icon, text: situation!.label, tone: tone);
  }
}

// ============================================================
// RALLY SCORING DOCK
// ============================================================

/// Can also be mounted by the parent shell as a fixed bottom scoring dock.
/// This widget does not own any match state.
class BadmintonRallyDock extends StatelessWidget {
  const BadmintonRallyDock({
    super.key,
    required this.names,
    required this.accent,
    required this.enabled,
    required this.onRally,
    this.onUndo,
    this.onPauseResume,
    this.onFinish,
    this.paused = false,
  });

  final List<String> names;
  final Color accent;
  final bool enabled;
  final ValueChanged<int> onRally;
  final VoidCallback? onUndo;
  final VoidCallback? onPauseResume;
  final VoidCallback? onFinish;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('RALLY WON BY', style: SportikaType.bodyStrong),

          const SizedBox(height: SportikaSpacing.sm),

          Row(
            children: [
              Expanded(
                child: ScoringPad(
                  label: '+1 RALLY',
                  hint: names[0],
                  big: true,
                  tone: accent,
                  enabled: enabled,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onRally(0);
                  },
                ),
              ),

              const SizedBox(width: SportikaSpacing.sm),

              Expanded(
                child: ScoringPad(
                  label: '+1 RALLY',
                  hint: names[1],
                  big: true,
                  tone: SportikaColors.mint,
                  enabled: enabled,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onRally(1);
                  },
                ),
              ),
            ],
          ),

          if (onUndo != null || onPauseResume != null || onFinish != null) ...[
            const SizedBox(height: SportikaSpacing.sm),

            _ActionBar(
              onUndo: onUndo,
              onPauseResume: onPauseResume,
              onFinish: onFinish,
              paused: paused,
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// MATCH ACTIONS
// ============================================================

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    this.onUndo,
    this.onPauseResume,
    this.onFinish,
    required this.paused,
  });

  final VoidCallback? onUndo;
  final VoidCallback? onPauseResume;
  final VoidCallback? onFinish;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: SportikaSpacing.sm,
      runSpacing: SportikaSpacing.sm,
      alignment: WrapAlignment.spaceBetween,
      children: [
        if (onUndo != null)
          GhostButton(
            label: 'Undo',
            icon: Icons.undo_rounded,
            onPressed: onUndo,
          ),

        if (onPauseResume != null)
          GhostButton(
            label: paused ? 'Resume' : 'Pause',
            icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            onPressed: onPauseResume,
          ),

        if (onFinish != null)
          GhostButton(
            label: 'Finish',
            icon: Icons.flag_outlined,
            onPressed: () => _confirmFinish(context, onFinish!),
          ),
      ],
    );
  }

  Future<void> _confirmFinish(BuildContext context, VoidCallback finish) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Finish match?'),
        content: const Text(
          'Review the score before finishing. '
          'The match controller will validate the result.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      finish();
    }
  }
}

// ============================================================
// GAME PROGRESS
// ============================================================

class _GameProgress extends StatelessWidget {
  const _GameProgress({
    required this.names,
    required this.completed,
    required this.current,
    required this.complete,
    required this.bestOf,
    required this.accent,
  });

  final List<String> names;
  final List<dynamic> completed;
  final List<int> current;
  final bool complete;
  final int bestOf;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final games = [
      for (final raw in completed) BadmintonScoringWorkspace._pair(raw),
      if (!complete) current,
    ];

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('GAME PROGRESS', style: SportikaType.bodyStrong),
              ),
              StatusPill('BEST OF $bestOf', color: accent),
            ],
          ),

          const SizedBox(height: SportikaSpacing.md),

          Row(
            children: [
              const Expanded(
                flex: 3,
                child: Text('SIDE', style: SportikaType.micro),
              ),
              for (var i = 0; i < bestOf; i++)
                Expanded(
                  child: Text(
                    'G${i + 1}',
                    textAlign: TextAlign.center,
                    style: SportikaType.micro,
                  ),
                ),
            ],
          ),

          const Divider(),

          for (var side = 0; side < 2; side++) ...[
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    names[side],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SportikaType.bodyStrong,
                  ),
                ),
                for (var i = 0; i < bestOf; i++)
                  Expanded(
                    child: Text(
                      i < games.length ? '${games[i][side]}' : '–',
                      textAlign: TextAlign.center,
                      style: SportikaType.bodyStrong.copyWith(
                        color: i == completed.length && !complete
                            ? accent
                            : i < completed.length &&
                                  games[i][side] > games[i][1 - side]
                            ? SportikaColors.mint
                            : SportikaColors.text,
                      ),
                    ),
                  ),
              ],
            ),

            if (side == 0) const SizedBox(height: SportikaSpacing.md),
          ],

          if (!complete) ...[
            const SizedBox(height: SportikaSpacing.md),
            Text(
              'Game ${completed.length + 1} in progress',
              style: SportikaType.caption,
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// FINAL RESULT
// ============================================================

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.names, required this.gamesWon});

  final List<String> names;
  final List<int> gamesWon;

  @override
  Widget build(BuildContext context) {
    final winner = gamesWon[0] == gamesWon[1]
        ? null
        : gamesWon[0] > gamesWon[1]
        ? names[0]
        : names[1];

    return SurfaceCard(
      child: Row(
        children: [
          const Icon(Icons.emoji_events_outlined, color: SportikaColors.gold),

          const SizedBox(width: SportikaSpacing.sm),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  winner == null ? 'Final result' : 'Match winner',
                  style: SportikaType.caption,
                ),
                Text(
                  winner ?? 'Result recorded',
                  style: SportikaType.bodyStrong,
                ),
              ],
            ),
          ),

          Text('${gamesWon[0]}–${gamesWon[1]}', style: SportikaType.title),
        ],
      ),
    );
  }
}

// ============================================================
// MATCH INSIGHTS
// ============================================================

class _Insights extends StatelessWidget {
  const _Insights({
    required this.games,
    required this.rallies,
    required this.duration,
    required this.corrected,
  });

  final List<int> games;
  final List<int> rallies;
  final int? duration;
  final bool corrected;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('MATCH INSIGHTS', style: SportikaType.bodyStrong),

          const SizedBox(height: SportikaSpacing.md),

          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: 'GAMES',
                  value: '${games[0]}–${games[1]}',
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'RALLIES',
                  value: '${rallies[0]}–${rallies[1]}',
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'DURATION',
                  value: duration == null ? '—' : '${duration}m',
                ),
              ),
            ],
          ),

          if (corrected) ...[
            const SizedBox(height: SportikaSpacing.sm),

            const HelperText(
              'Rally totals reflect non-voided events. '
              'Published corrections appear in the official result.',
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: SportikaType.titleMedium),
        ),
        const SizedBox(height: SportikaSpacing.xs),
        Text(label, style: SportikaType.micro),
      ],
    );
  }
}

// ============================================================
// MATCH RULES
// ============================================================

class _Rules extends StatelessWidget {
  const _Rules({
    required this.target,
    required this.cap,
    required this.bestOf,
    required this.doubles,
  });

  final int target;
  final int cap;
  final int bestOf;
  final bool doubles;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        leading: const Icon(Icons.menu_book_outlined),
        title: const Text('Match rules', style: SportikaType.bodyStrong),
        subtitle: const Text(
          'Scoring, intervals and service',
          style: SportikaType.caption,
        ),
        children: [
          const Divider(),

          _RuleLine('Format', 'Best of $bestOf games'),
          _RuleLine('Game target', '$target points'),
          const _RuleLine('Winning margin', 'Two points'),
          _RuleLine('Maximum score', '$cap points'),
          const _RuleLine('Interval', 'At 11 points'),
          const _RuleLine(
            'Change ends',
            'After each game and at 11 in the deciding game',
          ),
          if (doubles)
            const _RuleLine(
              'Doubles rotation',
              'Individual service rotation not tracked',
            ),
        ],
      ),
    );
  }
}

class _RuleLine extends StatelessWidget {
  const _RuleLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SportikaSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: SportikaType.caption)),

          const SizedBox(width: SportikaSpacing.sm),

          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: SportikaType.bodyStrong,
            ),
          ),
        ],
      ),
    );
  }
}
