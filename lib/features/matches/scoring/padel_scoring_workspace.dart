import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sportika/features/matches/scoring/match_scoring_validator.dart';
import 'package:sportika/features/matches/widgets/padel_serving_indicator.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/padel/padel.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Premium official Padel scoring console.
///
/// All scores, match states and point history come from PadelEngine.
/// This widget only presents the fold and dispatches point events.
class PadelScoringWorkspace extends StatefulWidget {
  const PadelScoringWorkspace({
    super.key,
    required this.match,
    required this.progress,
    required this.accent,
    required this.onRecord,
    this.onUndo,
    this.busy = false,
  });

  final SportMatch match;
  final MatchProgress progress;
  final Color accent;
  final RecordMatchEvent onRecord;
  final VoidCallback? onUndo;
  final bool busy;

  @override
  State<PadelScoringWorkspace> createState() => _PadelScoringWorkspaceState();
}

class _PadelScoringWorkspaceState extends State<PadelScoringWorkspace> {
  bool _historyOpen = false;

  List<PadelPointRecord> _history = const [];
  String? _historySignature;

  SportMatch get match => widget.match;
  MatchProgress get progress => widget.progress;

  @override
  void initState() {
    super.initState();
    _refreshHistory();
  }

  @override
  void didUpdateWidget(covariant PadelScoringWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshHistory();
  }

  void _refreshHistory() {
    // Compare the serialized log and match configuration so undo,
    // corrections, rule changes and match replacement invalidate the cache.
    //
    // This avoids rebuilding the full point history on unrelated local
    // UI rebuilds, such as expanding the history section.
    final signature = [
      match.id,
      match.sideNames.join('|'),
      match.rules.toString(),
      match.scoringLog.toString(),
    ].join('::');

    if (_historySignature == signature) return;

    _historySignature = signature;
    _history = PadelEngine().pointHistory(
      sides: match.sideNames,
      rules: match.rules,
      events: match.scoringLog.map(ScoringEvent.fromJson).toList(),
    );
  }

  static int? _value(dynamic value) {
    if (value is! num ||
        !value.isFinite ||
        value < 0 ||
        value != value.truncateToDouble()) {
      return null;
    }
    return value.toInt();
  }

  static int? _at(dynamic pair, int side) {
    if (pair is! List || side < 0 || side >= pair.length) {
      return null;
    }
    return _value(pair[side]);
  }

  String _name(int side) => match.sideNames.length > side
      ? match.sideNames[side]
      : 'Team ${side + 1}';

  String _point(int side) {
    final state = progress.state;

    if (state['inTiebreak'] == true) {
      return '${_at(state['tiebreakPoints'], side) ?? '—'}';
    }

    final own = _at(state['points'], side);
    final other = _at(state['points'], 1 - side);

    if (own == null || other == null) return '—';

    if (own >= 3 && other >= 3 && own > other && state['noAd'] != true) {
      return 'AD';
    }

    return const ['0', '15', '30', '40'][own.clamp(0, 3)];
  }

  void _awardPoint(int side) {
    if (widget.busy || progress.isComplete || match.isPaused) {
      return;
    }

    widget.onRecord(PadelEngine.kPoint, side, const {});
  }

  @override
  Widget build(BuildContext context) {
    final state = progress.state;

    final complete = progress.isComplete;
    final paused = match.isPaused;
    final inTb = state['inTiebreak'] == true;
    final decider = state['deciderTiebreak'] == true;

    final rawSets = state['completedSets'];
    final sets = rawSets is List ? rawSets : const [];

    final setsToWin = _value(state['setsToWin']);

    final decidingSet =
        setsToWin != null &&
        _at(state['setsWon'], 0) == setsToWin - 1 &&
        _at(state['setsWon'], 1) == setsToWin - 1;

    final target =
        _value(
          match.rules[decider || decidingSet
              ? 'finalSetTiebreakPoints'
              : 'tiebreakPoints'],
        ) ??
        (decider || decidingSet ? 10 : 7);

    final a = _at(state['points'], 0);
    final b = _at(state['points'], 1);

    final deuce = !inTb && a != null && b != null && a >= 3 && b >= 3;

    final gameA = _at(state['games'], 0);
    final gameB = _at(state['games'], 1);

    final game = gameA != null && gameB != null ? '${gameA + gameB + 1}' : '—';

    final contextLabel = complete
        ? 'Match complete'
        : inTb
        ? '${decider ? 'Super tie-break' : 'Tie-break'}'
              ' · First to $target, win by 2'
        : 'Set ${sets.length + 1} · Game $game'
              '${deuce
                  ? a == b
                        ? state['noAd'] == true
                              ? ' · Golden point'
                              : ' · Deuce'
                        : ' · Advantage'
                  : ''}';

    final names = [_name(0), _name(1)];
    final canScore = !complete && !paused && !widget.busy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PadelMatchHeader(
          format: match.formatLabel,
          contextLabel: contextLabel,
          complete: complete,
          paused: paused,
          inTiebreak: inTb,
          goldenPoint: deuce && a == b && state['noAd'] == true,
          resultLabel: complete
              ? (progress.resultLabel.isEmpty
                    ? progress.headline
                    : progress.resultLabel)
              : null,
        ),

        const SizedBox(height: SportikaSpacing.md),

        _PadelLiveScoreboard(
          match: match,
          progress: progress,
          names: names,
          points: [_point(0), _point(1)],
          sets: [_at(state['setsWon'], 0), _at(state['setsWon'], 1)],
          games: [_at(state['games'], 0), _at(state['games'], 1)],
          complete: complete,
          inTiebreak: inTb,
          accent: widget.accent,
        ),

        const SizedBox(height: SportikaSpacing.md),

        if (!complete) ...[
          if (paused)
            Padding(
              padding: const EdgeInsets.only(bottom: SportikaSpacing.md),
              child: _PadelStateNotice(
                icon: Icons.pause_circle_outline,
                text: match.pauseReason == null || match.pauseReason!.isEmpty
                    ? 'Scoring is paused. Resume the match to award points.'
                    : 'Scoring paused: ${match.pauseReason}',
              ),
            ),

          _PadelPointControls(
            names: names,
            enabled: canScore,
            onPoint: _awardPoint,
            onUndo: widget.onUndo,
            canUndo: !widget.busy && match.lastActiveEvent != null,
          ),

          const SizedBox(height: SportikaSpacing.md),
        ] else if (widget.onUndo != null) ...[
          _UndoAction(
            onUndo: widget.onUndo,
            enabled: !widget.busy && match.lastActiveEvent != null,
          ),
          const SizedBox(height: SportikaSpacing.md),
        ],

        _SetTable(
          names: names,
          completed: sets,
          active: complete || decider ? null : state['games'],
          showActive: !complete,
          activeTb: inTb,
          decider: decider,
          setsToWin: setsToWin,
          setsWon: state['setsWon'],
          history: _history,
          paused: paused,
          resultLabel: complete ? progress.resultLabel : '',
        ),

        const SizedBox(height: SportikaSpacing.md),

        _PadelHistoryPanel(
          history: _history,
          names: names,
          expanded: _historyOpen,
          pointCount: _value(state['pointCount']) ?? _history.length,
          onToggle: () {
            setState(() {
              _historyOpen = !_historyOpen;
            });
          },
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------------
// MATCH HEADER
// -------------------------------------------------------------------------

class _PadelMatchHeader extends StatelessWidget {
  const _PadelMatchHeader({
    required this.format,
    required this.contextLabel,
    required this.complete,
    required this.paused,
    required this.inTiebreak,
    required this.goldenPoint,
    this.resultLabel,
  });

  final String format;
  final String contextLabel;
  final bool complete;
  final bool paused;
  final bool inTiebreak;
  final bool goldenPoint;
  final String? resultLabel;

  @override
  Widget build(BuildContext context) {
    final status = complete
        ? 'FINAL'
        : paused
        ? 'PAUSED'
        : 'LIVE';

    final statusColor = complete
        ? SportikaColors.textMuted
        : paused
        ? SportikaColors.gold
        : SportikaColors.mint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: SportikaSpacing.sm),
            Text(
              'SPORTIKA PADEL',
              style: SportikaType.micro.copyWith(
                color: SportikaColors.textMuted,
              ),
            ),
            const Spacer(),
            _PadelTag(label: status, color: statusColor),
          ],
        ),

        const SizedBox(height: SportikaSpacing.sm),

        Text(contextLabel, style: SportikaType.bodyStrong),

        const SizedBox(height: SportikaSpacing.xs),

        Wrap(
          spacing: SportikaSpacing.sm,
          runSpacing: SportikaSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(format, style: SportikaType.caption),
            if (inTiebreak)
              const _PadelTag(
                label: 'TIE-BREAK',
                color: SportikaColors.blueBright,
              ),
            if (goldenPoint)
              const _PadelTag(
                label: 'GOLDEN POINT',
                color: SportikaColors.gold,
              ),
          ],
        ),

        if (resultLabel != null && resultLabel!.isNotEmpty) ...[
          const SizedBox(height: SportikaSpacing.sm),
          Text(
            resultLabel!,
            style: SportikaType.caption.copyWith(color: SportikaColors.mint),
          ),
        ],
      ],
    );
  }
}

class _PadelTag extends StatelessWidget {
  const _PadelTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SportikaSpacing.sm,
        vertical: SportikaSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(SportikaRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(label, style: SportikaType.micro.copyWith(color: color)),
    );
  }
}

// -------------------------------------------------------------------------
// LIVE SCOREBOARD
// -------------------------------------------------------------------------

class _PadelLiveScoreboard extends StatelessWidget {
  const _PadelLiveScoreboard({
    required this.match,
    required this.progress,
    required this.names,
    required this.points,
    required this.sets,
    required this.games,
    required this.complete,
    required this.inTiebreak,
    required this.accent,
  });

  final SportMatch match;
  final MatchProgress progress;
  final List<String> names;
  final List<String> points;
  final List<int?> sets;
  final List<int?> games;
  final bool complete;
  final bool inTiebreak;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      borderColor: accent.withValues(alpha: 0.35),
      padding: const EdgeInsets.all(SportikaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            complete
                ? 'FINAL SCORE'
                : inTiebreak
                ? 'LIVE TIE-BREAK POINTS'
                : 'CURRENT POINTS',
            textAlign: TextAlign.center,
            style: SportikaType.micro.copyWith(color: SportikaColors.textMuted),
          ),

          const SizedBox(height: SportikaSpacing.md),

          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 340;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: narrow ? 3 : 4,
                    child: _PadelTeamCard(
                      name: names[0],
                      participants: match.participantsOnSide(0),
                      doubles: match.discipline == MatchDiscipline.doubles,
                      accent: accent,
                    ),
                  ),

                  const SizedBox(width: SportikaSpacing.xs),

                  Expanded(
                    flex: narrow ? 4 : 5,
                    child: _CentralScore(
                      left: complete ? '${sets[0] ?? '—'}' : points[0],
                      right: complete ? '${sets[1] ?? '—'}' : points[1],
                      complete: complete,
                      inTiebreak: inTiebreak,
                    ),
                  ),

                  const SizedBox(width: SportikaSpacing.xs),

                  Expanded(
                    flex: narrow ? 3 : 4,
                    child: _PadelTeamCard(
                      name: names[1],
                      participants: match.participantsOnSide(1),
                      doubles: match.discipline == MatchDiscipline.doubles,
                      accent: SportikaColors.blueBright,
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: SportikaSpacing.md),

          // The existing widget owns serving rotation and player identity.
          // Do not independently calculate serving order here.
          PadelServingIndicator(match: match, progress: progress),

          const SizedBox(height: SportikaSpacing.md),

          const Divider(height: 1, color: SportikaColors.borderSubtle),

          const SizedBox(height: SportikaSpacing.md),

          Row(
            children: [
              Expanded(
                child: _ScoreMetric(
                  label: 'SETS',
                  value: '${sets[0] ?? '—'} - ${sets[1] ?? '—'}',
                ),
              ),
              Expanded(
                child: _ScoreMetric(
                  label: 'GAMES',
                  value: '${games[0] ?? '—'} - ${games[1] ?? '—'}',
                ),
              ),
              Expanded(
                child: _ScoreMetric(
                  label: 'FORMAT',
                  value: match.formatLabel,
                  compact: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CentralScore extends StatelessWidget {
  const _CentralScore({
    required this.left,
    required this.right,
    required this.complete,
    required this.inTiebreak,
  });

  final String left;
  final String right;
  final bool complete;
  final bool inTiebreak;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                left,
                style: SportikaType.hero.copyWith(
                  color: SportikaColors.mint,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SportikaSpacing.xs,
                ),
                child: Text(
                  ':',
                  style: SportikaType.title.copyWith(
                    color: SportikaColors.textDim,
                  ),
                ),
              ),
              Text(
                right,
                style: SportikaType.hero.copyWith(
                  color: SportikaColors.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: SportikaSpacing.xs),

        Text(
          complete
              ? 'SETS WON'
              : inTiebreak
              ? 'TB POINTS'
              : 'LIVE SCORE',
          style: SportikaType.micro.copyWith(color: SportikaColors.textMuted),
        ),
      ],
    );
  }
}

class _PadelTeamCard extends StatelessWidget {
  const _PadelTeamCard({
    required this.name,
    required this.participants,
    required this.doubles,
    required this.accent,
  });

  final String name;
  final List<MatchParticipant> participants;
  final bool doubles;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final players = participants.take(doubles ? 2 : 1).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (players.isEmpty)
                _PlayerInitialAvatar(name: name, accent: accent)
              else
                for (var i = 0; i < players.length; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  _PlayerInitialAvatar(
                    name: players[i].displayName,
                    accent: accent,
                  ),
                ],
            ],
          ),
        ),

        const SizedBox(height: SportikaSpacing.sm),

        Tooltip(
          message: name,
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: SportikaType.bodyStrong,
          ),
        ),

        if (players.isNotEmpty) ...[
          const SizedBox(height: SportikaSpacing.xs),
          Text(
            players
                .map((p) => p.displayName)
                .where((name) => name.isNotEmpty)
                .join(' / '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: SportikaType.caption.copyWith(
              color: SportikaColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

class _PlayerInitialAvatar extends StatelessWidget {
  const _PlayerInitialAvatar({required this.name, required this.accent});

  final String name;
  final Color accent;

  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .toList();

    if (parts.isEmpty) return '?';

    return parts.map((part) => part[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Text(
        initials,
        style: SportikaType.bodyStrong.copyWith(color: accent),
      ),
    );
  }
}

class _ScoreMetric extends StatelessWidget {
  const _ScoreMetric({
    required this.label,
    required this.value,
    this.compact = false,
  });

  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: SportikaType.micro.copyWith(color: SportikaColors.textMuted),
        ),
        const SizedBox(height: SportikaSpacing.xs),
        Text(
          value,
          maxLines: compact ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: compact
              ? SportikaType.caption.copyWith(color: SportikaColors.text)
              : SportikaType.title,
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------------
// POINT CONTROLS
// -------------------------------------------------------------------------

class _PadelPointControls extends StatelessWidget {
  const _PadelPointControls({
    required this.names,
    required this.enabled,
    required this.onPoint,
    required this.onUndo,
    required this.canUndo,
  });

  final List<String> names;
  final bool enabled;
  final ValueChanged<int> onPoint;
  final VoidCallback? onUndo;
  final bool canUndo;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Text('AWARD POINT', style: SportikaType.bodyStrong),
              Spacer(),
              Icon(Icons.bolt_rounded, color: SportikaColors.mint, size: 18),
            ],
          ),

          const SizedBox(height: SportikaSpacing.md),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var side = 0; side < 2; side++) ...[
                if (side > 0) const SizedBox(width: SportikaSpacing.sm),
                Expanded(
                  child: _PointPad(
                    key: ValueKey('padel-point-$side'),
                    name: names[side],
                    enabled: enabled,
                    primary: side == 0,
                    onTap: () => onPoint(side),
                  ),
                ),
              ],
            ],
          ),

          if (onUndo != null) ...[
            const SizedBox(height: SportikaSpacing.sm),
            _UndoAction(onUndo: onUndo, enabled: canUndo),
          ],
        ],
      ),
    );
  }
}

class _PointPad extends StatelessWidget {
  const _PointPad({
    super.key,
    required this.name,
    required this.enabled,
    required this.primary,
    required this.onTap,
  });

  final String name;
  final bool enabled;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = primary ? SportikaColors.mint : SportikaColors.blueBright;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 46,
          child: Center(
            child: Tooltip(
              message: name,
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: SportikaType.bodyStrong,
              ),
            ),
          ),
        ),

        const SizedBox(height: SportikaSpacing.sm),

        Semantics(
          label: 'Award point to $name',
          button: true,
          enabled: enabled,
          child: FilledButton(
            onPressed: enabled
                ? () {
                    // Feedback is only a local tap acknowledgement.
                    // Official scoring remains controlled by onRecord.
                    HapticFeedback.selectionClick();
                    onTap();
                  }
                : null,
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(
                Size(kMinInteractiveDimension, 76),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(
                  horizontal: SportikaSpacing.sm,
                  vertical: SportikaSpacing.md,
                ),
              ),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return SportikaColors.surfaceSunken;
                }
                if (states.contains(WidgetState.pressed)) {
                  return accent.withValues(alpha: 0.20);
                }
                return accent.withValues(alpha: 0.10);
              }),
              foregroundColor: const WidgetStatePropertyAll(
                SportikaColors.text,
              ),
              side: WidgetStateProperty.resolveWith(
                (states) => BorderSide(
                  color: states.contains(WidgetState.pressed)
                      ? accent
                      : accent.withValues(alpha: 0.35),
                ),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(SportikaRadius.md),
                ),
              ),
              animationDuration: SportikaMotion.fast,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_circle_outline,
                  color: enabled ? accent : SportikaColors.textDim,
                  size: 23,
                ),
                const SizedBox(height: SportikaSpacing.xs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '+ POINT',
                    style: SportikaType.title.copyWith(
                      color: enabled
                          ? SportikaColors.text
                          : SportikaColors.textDim,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _UndoAction extends StatelessWidget {
  const _UndoAction({required this.onUndo, required this.enabled});

  final VoidCallback? onUndo;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: TextButton.icon(
        onPressed: enabled ? onUndo : null,
        style: TextButton.styleFrom(
          foregroundColor: SportikaColors.textMuted,
          disabledForegroundColor: SportikaColors.textDim,
          minimumSize: const Size(
            kMinInteractiveDimension,
            kMinInteractiveDimension,
          ),
          textStyle: SportikaType.action,
        ),
        icon: const Icon(Icons.undo_rounded, size: SportikaSpacing.lg),
        label: const Text('Undo last point'),
      ),
    );
  }
}

// -------------------------------------------------------------------------
// SET-BY-SET TABLE
// -------------------------------------------------------------------------

class _SetTable extends StatelessWidget {
  const _SetTable({
    required this.names,
    required this.completed,
    required this.active,
    required this.showActive,
    required this.activeTb,
    required this.decider,
    required this.setsToWin,
    required this.setsWon,
    required this.history,
    required this.paused,
    required this.resultLabel,
  });

  final List<String> names;
  final List completed;
  final dynamic active;
  final dynamic setsWon;
  final bool showActive;
  final bool activeTb;
  final bool decider;
  final bool paused;
  final int? setsToWin;
  final List<PadelPointRecord> history;
  final String resultLabel;

  @override
  Widget build(BuildContext context) {
    final played = completed.length + (showActive ? 1 : 0);

    final configured = setsToWin != null && setsToWin! > 0
        ? setsToWin! * 2 - 1
        : played;

    final count = configured > played ? configured : played;

    if (count == 0) {
      return const Text('No completed sets.', style: SportikaType.caption);
    }

    final tieBreaks = <int, List<int>>{};

    for (final point in history) {
      if (point.tiebreak &&
          point.setIndex >= 0 &&
          point.setIndex < completed.length &&
          point.winnerSide >= 0 &&
          point.winnerSide < 2) {
        final tally = tieBreaks.putIfAbsent(point.setIndex, () => [0, 0]);
        tally[point.winnerSide]++;
      }
    }

    final wonA = _PadelScoringWorkspaceState._at(setsWon, 0);
    final wonB = _PadelScoringWorkspaceState._at(setsWon, 1);

    final leader = wonA != null && wonB != null && wonA != wonB
        ? (wonA > wonB ? 0 : 1)
        : null;

    final summary = !showActive
        ? resultLabel.isNotEmpty
              ? resultLabel
              : 'Match complete'
        : [
            'Set ${completed.length + 1} of $count',
            if (leader != null)
              '${names[leader]} lead '
                  '${leader == 0 ? wonA : wonB}'
                  '–'
                  '${leader == 0 ? wonB : wonA}'
            else if (wonA != null && wonB != null)
              'Sets level $wonA–$wonB',
            if (paused) 'Paused',
          ].join(' · ');

    return SurfaceCard(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('SET-BY-SET SCORE', style: SportikaType.bodyStrong),

          const SizedBox(height: SportikaSpacing.md),

          LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(1);

              final teamWidth = SportikaSpacing.xl * 4 * scale;

              final columnWidth = SportikaSpacing.xl * 2 * scale;

              final minWidth = teamWidth + count * columnWidth;

              final available = constraints.maxWidth;

              final width = minWidth > available ? minWidth : available;

              bool isActive(int set) => showActive && set == completed.length;

              Widget cell(int set, Widget child) {
                return Container(
                  alignment: Alignment.center,
                  constraints: const BoxConstraints(
                    minHeight: SportikaSpacing.xl * 2,
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: SportikaSpacing.sm,
                    horizontal: SportikaSpacing.xs,
                  ),
                  color: isActive(set) ? SportikaColors.mintSubtle : null,
                  child: child,
                );
              }

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
                          for (var i = 0; i < count; i++)
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
                            children: [
                              const Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: SportikaSpacing.sm,
                                ),
                                child: Text('TEAM', style: SportikaType.micro),
                              ),
                              for (var i = 0; i < count; i++)
                                cell(
                                  i,
                                  Column(
                                    children: [
                                      Text(
                                        'SET ${i + 1}',
                                        style: SportikaType.micro.copyWith(
                                          color: isActive(i)
                                              ? SportikaColors.mint
                                              : SportikaColors.textMuted,
                                        ),
                                      ),
                                      if (isActive(i) && activeTb)
                                        Text(
                                          decider ? 'SUPER TB' : 'TB',
                                          style: SportikaType.micro,
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),

                          for (var side = 0; side < 2; side++)
                            TableRow(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: SportikaSpacing.md,
                                    horizontal: SportikaSpacing.xs,
                                  ),
                                  child: Text(
                                    names[side],
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: SportikaType.bodyStrong,
                                  ),
                                ),
                                for (var i = 0; i < count; i++)
                                  Builder(
                                    builder: (context) {
                                      final done = i < completed.length;

                                      final own =
                                          _PadelScoringWorkspaceState._at(
                                            done
                                                ? completed[i]
                                                : isActive(i)
                                                ? active
                                                : null,
                                            side,
                                          );

                                      final other = done
                                          ? _PadelScoringWorkspaceState._at(
                                              completed[i],
                                              1 - side,
                                            )
                                          : null;

                                      final won =
                                          done &&
                                          own != null &&
                                          other != null &&
                                          own > other;

                                      final annotation = tieBreaks[i];

                                      return Semantics(
                                        label:
                                            'Set ${i + 1}, '
                                            '${names[side]}'
                                            '${won ? ', set winner' : ''}',
                                        child: cell(
                                          i,
                                          Column(
                                            children: [
                                              Text(
                                                own?.toString() ?? '—',
                                                style: SportikaType.score.copyWith(
                                                  color: won
                                                      ? SportikaColors.text
                                                      : done
                                                      ? SportikaColors.textMuted
                                                      : isActive(i)
                                                      ? SportikaColors.mint
                                                      : SportikaColors.textDim,
                                                  fontWeight: won
                                                      ? SportikaFontWeight
                                                            .extraBold
                                                      : SportikaFontWeight
                                                            .medium,
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                              if (annotation != null) ...[
                                                const SizedBox(
                                                  height: SportikaSpacing.xs,
                                                ),
                                                Text(
                                                  'TB ${annotation[side]}',
                                                  style: SportikaType.micro,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: SportikaSpacing.sm),

                  Text(summary, style: SportikaType.caption),

                  if (minWidth > available) ...[
                    const SizedBox(height: SportikaSpacing.xs),
                    const Text(
                      'Scroll horizontally to view all sets',
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
}

// -------------------------------------------------------------------------
// POINT HISTORY
// -------------------------------------------------------------------------

class _PadelHistoryPanel extends StatelessWidget {
  const _PadelHistoryPanel({
    required this.history,
    required this.names,
    required this.expanded,
    required this.pointCount,
    required this.onToggle,
  });

  final List<PadelPointRecord> history;
  final List<String> names;
  final bool expanded;
  final int pointCount;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final recent = history.length <= 3
        ? history.reversed.toList()
        : history.reversed.take(3).toList();

    return SurfaceCard(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('POINT HISTORY', style: SportikaType.bodyStrong),
              ),
              Text('$pointCount points', style: SportikaType.caption),
            ],
          ),

          const SizedBox(height: SportikaSpacing.sm),

          if (history.isEmpty)
            const Text('No points recorded yet.', style: SportikaType.caption)
          else ...[
            if (!expanded)
              for (final point in recent)
                _PointHistoryItem(point: point, names: names),

            if (expanded) _PointHistory(history: history, names: names),

            const SizedBox(height: SportikaSpacing.xs),

            Semantics(
              expanded: expanded,
              child: TextButton.icon(
                onPressed: onToggle,
                style: TextButton.styleFrom(
                  foregroundColor: SportikaColors.textMuted,
                  minimumSize: const Size(
                    kMinInteractiveDimension,
                    kMinInteractiveDimension,
                  ),
                  textStyle: SportikaType.action,
                ),
                icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                label: Text(
                  expanded ? 'Show recent points' : 'View all points',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PointHistory extends StatelessWidget {
  const _PointHistory({required this.history, required this.names});

  final List<PadelPointRecord> history;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);

    final height = (SportikaSpacing.xl * 11 * scale)
        .clamp(180.0, 520.0)
        .toDouble();

    return SizedBox(
      height: height,
      child: Scrollbar(
        interactive: false,
        child: ListView.separated(
          primary: false,
          itemCount: history.length,
          separatorBuilder: (_, _) =>
              const Divider(height: 1, color: SportikaColors.borderSubtle),
          itemBuilder: (context, index) {
            final point = history[history.length - 1 - index];

            return _PointHistoryItem(point: point, names: names);
          },
        ),
      ),
    );
  }
}

class _PointHistoryItem extends StatelessWidget {
  const _PointHistoryItem({required this.point, required this.names});

  final PadelPointRecord point;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final winner = point.winnerSide >= 0 && point.winnerSide < names.length
        ? names[point.winnerSide]
        : 'Unknown side';

    final tags = [
      if (point.tiebreak) 'TB',
      if (point.goldenPoint) 'GP',
      if (point.isDecidingPoint) 'Match',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SportikaSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: SportikaColors.mintSubtle,
              borderRadius: BorderRadius.circular(SportikaRadius.sm),
            ),
            child: const Icon(
              Icons.sports_tennis,
              size: 17,
              color: SportikaColors.mint,
            ),
          ),

          const SizedBox(width: SportikaSpacing.sm),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$winner won point',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.bodyStrong,
                ),

                const SizedBox(height: SportikaSpacing.xs),

                Text(
                  'Set ${point.setIndex + 1}'
                  ' · ${point.tiebreak ? 'TB point' : 'Game'}'
                  ' ${point.gameIndex}'
                  ' · #${point.index}',
                  style: SportikaType.micro,
                ),

                if (tags.isNotEmpty) ...[
                  const SizedBox(height: SportikaSpacing.xs),
                  Wrap(
                    spacing: SportikaSpacing.xs,
                    runSpacing: SportikaSpacing.xs,
                    children: [
                      for (final tag in tags)
                        _PadelTag(label: tag, color: SportikaColors.gold),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: SportikaSpacing.sm),

          Flexible(
            child: Text(
              '${point.scoreBefore} → '
              '${point.scoreAfter}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: SportikaType.caption.copyWith(color: SportikaColors.text),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------------
// MATCH STATE NOTICE
// -------------------------------------------------------------------------

class _PadelStateNotice extends StatelessWidget {
  const _PadelStateNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      decoration: BoxDecoration(
        color: SportikaColors.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(SportikaRadius.md),
        border: Border.all(color: SportikaColors.gold.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: SportikaColors.gold, size: 20),
          const SizedBox(width: SportikaSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: SportikaType.caption.copyWith(color: SportikaColors.gold),
            ),
          ),
        ],
      ),
    );
  }
}
