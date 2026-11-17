import 'dart:async';

import 'package:flutter/material.dart';

import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
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

class PadelScoreboard extends StatelessWidget {
  const PadelScoreboard({super.key, this.progress});
  final MatchProgress? progress;
  @override
  Widget build(BuildContext context) => _ScoreDetails([
    if (progress != null) ...[
      'Sets won · ${progress!.scoreValues.join(' – ')}',
      ..._completedScores(progress!, 'completedSets', 'Set'),
      ...progress!.contextChips.where((c) => !c.startsWith('Service:')),
    ],
  ]);
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
      ...progress!.contextChips.where((c) => !c.startsWith('Service:')),
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
