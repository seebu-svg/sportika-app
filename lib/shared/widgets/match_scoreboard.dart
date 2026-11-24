import 'dart:async';

import 'package:flutter/material.dart';

import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Shared identity layout; each sport owns the meaning of its score and detail.
class MatchScoreboard extends StatelessWidget {
  const MatchScoreboard({
    super.key,
    required this.sport,
    required this.labels,
    this.progress,
    this.result,
    this.players = const [[], []],
    this.discipline,
    this.finished = false,
    this.versus = false,
    this.compact = false,
    this.showDetails = true,
    this.showOutcome = true,
  });

  final Sport sport;
  final List<String> labels;
  final MatchProgress? progress;
  final OfficialResult? result;
  final List<List<Account>> players;
  final String? discipline;
  final bool finished;
  final bool versus;
  final bool compact;
  final bool showDetails;
  final bool showOutcome;

  @override
  Widget build(BuildContext context) {
    // A published correction is authoritative. Never combine it with an older
    // event fold whose final scores disagree with that result.
    final p =
        result == null ||
            (!result!.walkover &&
                progress != null &&
                result!.sideScores.join('|') ==
                    progress!.scoreDisplay.join('|'))
        ? progress
        : null;
    if (sport == Sport.padel) {
      return PadelScoreboard(
        progress: p,
        labels: labels,
        players: players,
        discipline: discipline,
        result: result,
        finished: finished,
        compact: compact,
        showDetails: showDetails,
        showOutcome: showOutcome,
      );
    }
    final scores =
        result?.sideScores ??
        (compact ? p?.scoreDisplay : p?.lines.map((l) => l.value).toList());
    final details = switch (sport) {
      Sport.cricket => CricketScoreboard(progress: p),
      Sport.padel => PadelScoreboard(progress: p),
      Sport.futsal => FutsalScoreboard(progress: p),
      Sport.badminton => BadmintonScoreboard(progress: p),
    };
    final racket = sport == Sport.padel || sport == Sport.badminton;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (racket && discipline != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(discipline!, style: SportikaType.caption),
          ),
        for (var side = 0; side < 2; side++) ...[
          if (side == 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: versus
                  ? const Text('VS', style: SportikaType.micro)
                  : const SizedBox(height: 0),
            ),
          Row(
            children: [
              if (!compact && players.length > side && players[side].isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final player in players[side].take(2))
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: AccountAvatar(account: player, size: 28),
                      ),
                  ],
                )
              else if (!compact)
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: SportikaColors.blueSubtle,
                    borderRadius: BorderRadius.circular(racket ? 16 : 10),
                    border: Border.all(color: SportikaColors.borderStrong),
                  ),
                  child: Text(
                    initialsOf(labels[side]),
                    style: SportikaType.label,
                  ),
                ),
              if (!compact) const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      labels[side],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SportikaType.bodyStrong,
                    ),
                    if (sport == Sport.cricket &&
                        p != null &&
                        p.lines.length > side)
                      Text(
                        '${p.lines[side].sub ?? ''}${!finished && !p.isComplete && p.statusLabel == 'Innings in progress' && p.lines[side].leading ? ' · Batting' : ''}',
                        style: SportikaType.caption,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  scores != null &&
                          scores.length > side &&
                          scores[side].isNotEmpty
                      ? scores[side]
                      : '—',
                  textAlign: TextAlign.end,
                  style: SportikaType.title.copyWith(
                    color: SportikaColors.text,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (showDetails && p != null) ...[const SizedBox(height: 10), details],
        if (showOutcome && result != null && result!.headline.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(result!.headline, style: SportikaType.caption),
        ] else if (showOutcome &&
            p != null &&
            p.isComplete &&
            p.resultLabel.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(p.resultLabel, style: SportikaType.caption),
        ],
      ],
    );
  }
}

class _ScoreDetails extends StatelessWidget {
  const _ScoreDetails(this.items);
  final List<String> items;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 5,
    children: [
      for (final text in items) Text(text, style: SportikaType.caption),
    ],
  );
}

class CricketScoreboard extends StatelessWidget {
  const CricketScoreboard({super.key, this.progress});
  final MatchProgress? progress;
  @override
  Widget build(BuildContext context) => _ScoreDetails([
    if (progress != null)
      ...progress!.contextChips.where((c) => c.startsWith('Innings ')),
    if (progress?.statusLabel != null) progress!.statusLabel!,
  ]);
}

/// Padel's broadcast score strip. All values come from the existing fold/result.
class PadelScoreboard extends StatelessWidget {
  const PadelScoreboard({
    super.key,
    this.progress,
    this.labels = const [],
    this.players = const [[], []],
    this.discipline,
    this.result,
    this.finished = false,
    this.compact = false,
    this.showDetails = true,
    this.showOutcome = true,
  });
  final MatchProgress? progress;
  final List<String> labels;
  final List<List<Account>> players;
  final String? discipline;
  final OfficialResult? result;
  final bool finished, compact, showDetails, showOutcome;

  static int? _number(dynamic value) =>
      value is num &&
          value.isFinite &&
          value >= 0 &&
          value == value.truncateToDouble()
      ? value.toInt()
      : null;
  static int? _at(dynamic values, int side) =>
      values is List && values.length > side ? _number(values[side]) : null;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final state = p?.state ?? const <String, dynamic>{};
    final complete = finished || result != null || p?.isComplete == true;
    final live = p != null && !complete;
    final rawSets = state['completedSets'];
    final sets = rawSets is List ? rawSets : const [];
    final tieBreak = state['inTiebreak'] == true;
    final decider = state['deciderTiebreak'] == true;
    final winner = result?.winnerIndex ?? (complete ? p?.winnerIndex : null);
    final active = decider ? state['tiebreakPoints'] : state['games'];
    final activeA = _at(active, 0);
    final activeB = _at(active, 1);
    final leader =
        live && activeA != null && activeB != null && activeA != activeB
        ? (activeA > activeB ? 0 : 1)
        : null;
    final a = _at(state['points'], 0);
    final b = _at(state['points'], 1);
    final deuce =
        live && !tieBreak && a != null && b != null && a >= 3 && b >= 3;
    String name(int side) => labels.length > side
        ? labels[side]
        : p != null && p.sides.length > side
        ? p.sides[side]
        : 'Side ${side + 1}';
    String serverLabel(int side) {
      final member = _number(state['servingMember']);
      if (players.length > side &&
          member != null &&
          member < players[side].length &&
          players[side].length > 1) {
        return 'Serving · ${players[side][member].displayName}';
      }
      return 'Serving';
    }

    String points(int side) {
      if (tieBreak) return '${_at(state['tiebreakPoints'], side) ?? '—'}';
      final own = _at(state['points'], side);
      final other = _at(state['points'], 1 - side);
      if (own == null || other == null) return '—';
      if (own >= 3 && other >= 3 && own > other && state['noAd'] != true) {
        return 'AD';
      }
      return const ['0', '15', '30', '40'][own.clamp(0, 3)];
    }

    final outcome = result?.headline.isNotEmpty == true
        ? result!.headline
        : complete
        ? p?.resultLabel ?? ''
        : '';
    final numeric = SportikaType.scoreSmall.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget cell(String text, {bool emphasis = false, bool point = false}) =>
        Container(
          alignment: Alignment.center,
          constraints: BoxConstraints(minHeight: compact ? 56 : 64),
          padding: const EdgeInsets.symmetric(horizontal: SportikaSpacing.xs),
          decoration: BoxDecoration(
            color: point ? SportikaColors.mintSubtle : null,
            border: point
                ? const Border(left: BorderSide(color: SportikaColors.border))
                : null,
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: (point ? SportikaType.hero : numeric).copyWith(
              color: point
                  ? SportikaColors.mint
                  : emphasis
                  ? SportikaColors.text
                  : SportikaColors.textMuted,
            ),
          ),
        );
    Widget heading(String text, {bool active = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: SportikaSpacing.sm),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: SportikaType.micro.copyWith(
          color: active ? SportikaColors.mint : SportikaColors.textMuted,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: SportikaSpacing.md,
          runSpacing: SportikaSpacing.xs,
          children: [
            Text(
              complete
                  ? 'FINAL'
                  : live
                  ? 'LIVE'
                  : 'MATCH SCORE',
              style: SportikaType.micro.copyWith(
                color: complete
                    ? SportikaColors.gold
                    : live
                    ? SportikaColors.mint
                    : SportikaColors.textMuted,
              ),
            ),
            if (live) Text('SET ${sets.length + 1}', style: SportikaType.micro),
            if (discipline != null)
              Text(discipline!, style: SportikaType.micro),
            if (live && tieBreak)
              Text(
                decider ? 'SUPER TIE-BREAK' : 'TIE-BREAK',
                style: SportikaType.micro,
              ),
            if (deuce)
              Text(
                a == b
                    ? state['noAd'] == true
                          ? 'GOLDEN POINT'
                          : 'DEUCE'
                    : 'ADVANTAGE',
                style: SportikaType.micro,
              ),
          ],
        ),
        const SizedBox(height: SportikaSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final count = sets.length + (live ? 1 : 0);
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final minWidth = (140 + count * 42 + 52 + (live ? 68 : 0)) * scale;
            final scrolling = minWidth > constraints.maxWidth;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Container(
                    width: scrolling ? minWidth : constraints.maxWidth,
                    decoration: BoxDecoration(
                      color: SportikaColors.surfaceSunken,
                      border: Border.all(color: SportikaColors.borderSubtle),
                      borderRadius: BorderRadius.circular(SportikaRadius.sm),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Table(
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      columnWidths: {
                        0: const FlexColumnWidth(),
                        for (var i = 0; i < count; i++)
                          i + 1: FixedColumnWidth(42 * scale),
                        count + 1: FixedColumnWidth(52 * scale),
                        if (live) count + 2: FixedColumnWidth(68 * scale),
                      },
                      border: const TableBorder(
                        horizontalInside: BorderSide(
                          color: SportikaColors.borderSubtle,
                        ),
                      ),
                      children: [
                        TableRow(
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(
                                left: SportikaSpacing.md,
                              ),
                              child: Text('TEAM', style: SportikaType.micro),
                            ),
                            for (var i = 0; i < count; i++)
                              heading(
                                'S${i + 1}',
                                active: live && i == sets.length,
                              ),
                            heading('SETS'),
                            if (live)
                              heading(
                                tieBreak ? 'TB PTS' : 'POINTS',
                                active: true,
                              ),
                          ],
                        ),
                        for (var side = 0; side < 2; side++)
                          TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(
                                  SportikaSpacing.md,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name(side),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: SportikaType.bodyStrong.copyWith(
                                        color: winner == side
                                            ? SportikaColors.gold
                                            : SportikaColors.text,
                                      ),
                                    ),
                                    if (!compact && players.length > side)
                                      for (final player in players[side].take(
                                        2,
                                      ))
                                        if (player.displayName != name(side))
                                          Text(
                                            player.displayName,
                                            style: SportikaType.caption,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                    if (winner == side ||
                                        leader == side ||
                                        live &&
                                            _number(state['servingSide']) ==
                                                side)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: SportikaSpacing.xs,
                                        ),
                                        child: Text(
                                          [
                                            if (winner == side) 'Winner',
                                            if (live &&
                                                _number(state['servingSide']) ==
                                                    side)
                                              serverLabel(side),
                                            if (leader == side) 'Set leader',
                                          ].join(' · '),
                                          style: SportikaType.caption.copyWith(
                                            color: winner == side
                                                ? SportikaColors.gold
                                                : SportikaColors.mint,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              for (var i = 0; i < count; i++)
                                cell(
                                  '${_at(i < sets.length ? sets[i] : active, side) ?? '—'}',
                                  emphasis: i == sets.length
                                      ? leader == side
                                      : (_at(sets[i], side) ?? -1) >
                                            (_at(sets[i], 1 - side) ?? -1),
                                ),
                              cell(
                                result != null && p == null
                                    ? (result!.sideValues.length > side
                                          ? '${result!.sideValues[side]}'
                                          : '—')
                                    : '${_at(state['setsWon'], side) ?? '—'}',
                                emphasis: winner == side,
                              ),
                              if (live) cell(points(side), point: true),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                if (scrolling)
                  const Padding(
                    padding: EdgeInsets.only(top: SportikaSpacing.xs),
                    child: Text(
                      'Scroll to view all scores',
                      style: SportikaType.caption,
                    ),
                  ),
              ],
            );
          },
        ),
        if (showDetails &&
            live &&
            p.statusLabel != null &&
            !tieBreak &&
            !deuce) ...[
          const SizedBox(height: SportikaSpacing.xs),
          Text(p.statusLabel!, style: SportikaType.caption),
        ],
        if (showOutcome && outcome.isNotEmpty) ...[
          const SizedBox(height: SportikaSpacing.sm),
          Text(outcome, style: SportikaType.caption),
        ],
      ],
    );
  }
}

class FutsalScoreboard extends StatefulWidget {
  const FutsalScoreboard({super.key, this.progress});
  final MatchProgress? progress;

  @override
  State<FutsalScoreboard> createState() => _FutsalScoreboardState();
}

class _FutsalScoreboardState extends State<FutsalScoreboard> {
  Timer? _timer;

  void _syncTimer() {
    _timer?.cancel();
    if (widget.progress?.state['running'] == true) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant FutsalScoreboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    if (p == null) return const SizedBox.shrink();
    // Match the existing scorer: period time comes from the recorded clock
    // anchor, and only advances while that clock is explicitly running.
    var elapsed = (p.state['periodElapsed'] as int?) ?? 0;
    final anchor = DateTime.tryParse(p.state['resumeAt'] as String? ?? '');
    if (p.state['running'] == true && anchor != null) {
      elapsed += DateTime.now().difference(anchor).inSeconds.clamp(0, 86400);
    }
    final clock =
        '${(elapsed ~/ 60).toString().padLeft(2, '0')}:${(elapsed % 60).toString().padLeft(2, '0')}';
    return _ScoreDetails([
      for (final chip in p.contextChips)
        if (!chip.startsWith('Clock')) chip,
      if (p.state.containsKey('periodElapsed'))
        'Clock $clock${p.state['running'] == true ? ' · Running' : ' · Stopped'}',
    ]);
  }
}

class BadmintonScoreboard extends StatelessWidget {
  const BadmintonScoreboard({super.key, this.progress});
  final MatchProgress? progress;
  @override
  Widget build(BuildContext context) => _ScoreDetails([
    if (progress != null) ...[
      'Games won · ${progress!.scoreValues.join(' – ')}',
      ..._completedScores(progress!, 'completedGames', 'Game'),
      ...progress!.contextChips,
    ],
  ]);
}

List<String> _completedScores(
  MatchProgress progress,
  String key,
  String label,
) {
  final values = progress.state[key];
  if (values is! List) return const [];
  return [
    for (var i = 0; i < values.length; i++)
      if (values[i] is List && (values[i] as List).length == 2)
        '$label ${i + 1} · ${(values[i] as List).join(' – ')}',
  ];
}
