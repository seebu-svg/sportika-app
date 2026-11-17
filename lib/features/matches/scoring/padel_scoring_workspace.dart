import 'package:flutter/material.dart';

import 'package:sportika/features/matches/scoring/match_scoring_validator.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/padel/padel.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// One console for the engine's live game, sets, point controls and history.
class PadelScoringWorkspace extends StatefulWidget {
  const PadelScoringWorkspace({
    super.key,
    required this.match,
    required this.progress,
    required this.accent,
    required this.onRecord,
  });

  final SportMatch match;
  final MatchProgress progress;
  final Color accent;
  final RecordMatchEvent onRecord;

  @override
  State<PadelScoringWorkspace> createState() => _PadelScoringWorkspaceState();
}

class _PadelScoringWorkspaceState extends State<PadelScoringWorkspace> {
  bool _historyOpen = false;

  SportMatch get match => widget.match;
  MatchProgress get progress => widget.progress;

  static int? _value(dynamic value) =>
      value is num &&
          value.isFinite &&
          value >= 0 &&
          value == value.truncateToDouble()
      ? value.toInt()
      : null;

  static int? _at(dynamic pair, int side) =>
      pair is List && pair.length > side ? _value(pair[side]) : null;

  String _name(int side) => match.sideNames.length > side
      ? match.sideNames[side]
      : 'Team ${side + 1}';

  String _point(int side) {
    final state = progress.state;
    if (state['inTiebreak'] == true) {
      return '${_at(state['tiebreakPoints'], side) ?? '—'}';
    }
    final a = _at(state['points'], side);
    final b = _at(state['points'], 1 - side);
    if (a == null || b == null) return '—';
    if (a >= 3 && b >= 3 && a > b && state['noAd'] != true) return 'AD';
    return const ['0', '15', '30', '40'][a.clamp(0, 3)];
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
    final servingSide = _value(state['servingSide']);
    final servingMember = _value(state['servingMember']);
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
    final points = state['points'];
    final a = _at(points, 0);
    final b = _at(points, 1);
    final deuce = !inTb && a != null && b != null && a >= 3 && b >= 3;
    final gameA = _at(state['games'], 0);
    final gameB = _at(state['games'], 1);
    final game = gameA != null && gameB != null ? '${gameA + gameB + 1}' : '—';
    final contextLabel = complete
        ? 'Match complete'
        : inTb
        ? '${decider ? 'Super tie-break' : 'Tie-break'} · first to $target, win by 2'
        : 'Set ${sets.length + 1} · Game $game'
              '${deuce
                  ? a == b
                        ? state['noAd'] == true
                              ? ' · Golden point'
                              : ' · Deuce'
                        : ' · Advantage'
                  : ''}';
    final scoreStyle = SportikaType.hero.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return SurfaceCard(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: SportikaSpacing.md,
            runSpacing: SportikaSpacing.xs,
            children: [
              Text(
                complete
                    ? 'MATCH COMPLETE'
                    : paused
                    ? 'SCORING PAUSED'
                    : 'LIVE PADEL',
                style: SportikaType.micro.copyWith(
                  color: paused && !complete
                      ? SportikaColors.gold
                      : SportikaColors.textMuted,
                ),
              ),
              Text(match.formatLabel, style: SportikaType.caption),
            ],
          ),
          const SizedBox(height: SportikaSpacing.sm),
          Text(contextLabel, style: SportikaType.bodyStrong),
          if (complete) ...[
            const SizedBox(height: SportikaSpacing.xs),
            Text(
              progress.resultLabel.isEmpty
                  ? progress.headline
                  : progress.resultLabel,
              style: SportikaType.caption,
            ),
          ],
          const SizedBox(height: SportikaSpacing.md),
          for (var side = 0; side < 2; side++) ...[
            if (side > 0)
              const Divider(height: 1, color: SportikaColors.borderSubtle),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SportikaSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: _TeamIdentity(
                      name: _name(side),
                      participants: match.participantsOnSide(side),
                      doubles: match.discipline == MatchDiscipline.doubles,
                      serving: !complete && servingSide == side,
                      servingMember: servingMember,
                    ),
                  ),
                  const SizedBox(width: SportikaSpacing.md),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        complete
                            ? 'SETS'
                            : inTb
                            ? 'TB POINTS'
                            : 'POINTS',
                        style: SportikaType.micro,
                      ),
                      const SizedBox(height: SportikaSpacing.xs),
                      Text(
                        complete
                            ? '${_at(state['setsWon'], side) ?? '—'}'
                            : _point(side),
                        style: scoreStyle,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: SportikaSpacing.sm),
          _SetTable(
            names: [_name(0), _name(1)],
            completed: sets,
            active: complete
                ? null
                : decider
                ? state['tiebreakPoints']
                : state['games'],
            showActive: !complete,
            activeTb: decider,
          ),
          if (!complete) ...[
            const SizedBox(height: SportikaSpacing.md),
            if (paused) ...[
              Text(
                match.pauseReason == null || match.pauseReason!.isEmpty
                    ? 'Scoring is paused. Resume from the live controls to record points.'
                    : 'Scoring is paused: ${match.pauseReason}',
                style: SportikaType.caption.copyWith(
                  color: SportikaColors.gold,
                ),
              ),
              const SizedBox(height: SportikaSpacing.sm),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked =
                    constraints.maxWidth <
                    SportikaSpacing.xl *
                        10 *
                        MediaQuery.textScalerOf(context).scale(1);
                final pads = [
                  for (var side = 0; side < 2; side++)
                    _PointPad(
                      key: ValueKey('padel-point-$side'),
                      name: _name(side),
                      enabled: !paused,
                      onTap: () =>
                          widget.onRecord(PadelEngine.kPoint, side, const {}),
                    ),
                ];
                return stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          pads[0],
                          const SizedBox(height: SportikaSpacing.sm),
                          pads[1],
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: pads[0]),
                          const SizedBox(width: SportikaSpacing.sm),
                          Expanded(child: pads[1]),
                        ],
                      );
              },
            ),
          ],
          const SizedBox(height: SportikaSpacing.sm),
          const Divider(height: 1, color: SportikaColors.borderSubtle),
          Semantics(
            expanded: _historyOpen,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                minimumSize: const Size(
                  kMinInteractiveDimension,
                  kMinInteractiveDimension,
                ),
                foregroundColor: SportikaColors.textMuted,
                textStyle: SportikaType.action,
              ),
              onPressed: () => setState(() => _historyOpen = !_historyOpen),
              icon: Icon(_historyOpen ? Icons.expand_less : Icons.expand_more),
              label: Text(
                'Point history · ${_value(state['pointCount']) ?? '—'} points',
              ),
            ),
          ),
          if (_historyOpen)
            _PointHistory(
              history: PadelEngine().pointHistory(
                sides: match.sideNames,
                rules: match.rules,
                events: match.scoringLog.map(ScoringEvent.fromJson).toList(),
              ),
              names: [_name(0), _name(1)],
            ),
        ],
      ),
    );
  }
}

class _TeamIdentity extends StatelessWidget {
  const _TeamIdentity({
    required this.name,
    required this.participants,
    required this.doubles,
    required this.serving,
    required this.servingMember,
  });
  final String name;
  final List<MatchParticipant> participants;
  final bool doubles;
  final bool serving;
  final int? servingMember;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(name, style: SportikaType.bodyStrong),
      for (final person in participants.take(doubles ? 2 : 1))
        if (person.displayName != name)
          Text(person.displayName, style: SportikaType.caption),
      if (serving) ...[
        const SizedBox(height: SportikaSpacing.xs),
        Text(
          doubles &&
                  servingMember != null &&
                  servingMember! < participants.length
              ? 'Serving · ${participants[servingMember!].displayName}'
              : doubles && servingMember != null
              ? 'Serving · Player ${servingMember! + 1}'
              : 'Serving',
          style: SportikaType.caption.copyWith(color: SportikaColors.gold),
        ),
      ],
    ],
  );
}

class _PointPad extends StatelessWidget {
  const _PointPad({
    super.key,
    required this.name,
    required this.enabled,
    required this.onTap,
  });
  final String name;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Award point to $name',
    child: FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size(
          kMinInteractiveDimension,
          SportikaSpacing.xl * 3,
        ),
        padding: const EdgeInsets.all(SportikaSpacing.md),
        backgroundColor: SportikaColors.surfaceAlt,
        foregroundColor: SportikaColors.text,
        disabledBackgroundColor: SportikaColors.surfaceSunken,
        disabledForegroundColor: SportikaColors.textDim,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SportikaRadius.md),
        ),
      ),
      onPressed: enabled ? onTap : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '+ Point',
            style: SportikaType.action.copyWith(
              color: enabled ? SportikaColors.text : SportikaColors.textDim,
            ),
          ),
          const SizedBox(height: SportikaSpacing.xs),
          Text(
            name,
            textAlign: TextAlign.center,
            style: SportikaType.body.copyWith(
              color: enabled ? SportikaColors.text : SportikaColors.textDim,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SetTable extends StatelessWidget {
  const _SetTable({
    required this.names,
    required this.completed,
    required this.active,
    required this.showActive,
    required this.activeTb,
  });
  final List<String> names;
  final List completed;
  final dynamic active;
  final bool showActive;
  final bool activeTb;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final count = completed.length + (showActive ? 1 : 0);
      if (count == 0) {
        return const Text('No completed sets.', style: SportikaType.caption);
      }
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final teamWidth = SportikaSpacing.xl * 4 * scale;
      final minWidth = teamWidth + count * SportikaSpacing.xl * 3 * scale;
      Widget cell(Widget child) => Padding(
        padding: const EdgeInsets.all(SportikaSpacing.sm),
        child: child,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: minWidth > constraints.maxWidth
                  ? minWidth
                  : constraints.maxWidth,
              child: Table(
                columnWidths: {0: FixedColumnWidth(teamWidth)},
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                border: const TableBorder(
                  horizontalInside: BorderSide(
                    color: SportikaColors.borderSubtle,
                  ),
                ),
                children: [
                  TableRow(
                    children: [
                      cell(
                        const Text('Set scores', style: SportikaType.caption),
                      ),
                      for (var i = 0; i < count; i++)
                        cell(
                          Text(
                            'Set ${i + 1}\n${i < completed.length
                                ? 'Complete'
                                : activeTb
                                ? 'Live TB'
                                : 'Live'}',
                            textAlign: TextAlign.center,
                            style: SportikaType.caption.copyWith(
                              color: i < completed.length
                                  ? SportikaColors.textMuted
                                  : SportikaColors.mint,
                            ),
                          ),
                        ),
                    ],
                  ),
                  for (var side = 0; side < 2; side++)
                    TableRow(
                      children: [
                        cell(Text(names[side], style: SportikaType.caption)),
                        for (var i = 0; i < count; i++)
                          cell(
                            Text(
                              '${_PadelScoringWorkspaceState._at(i < completed.length ? completed[i] : active, side) ?? '—'}',
                              textAlign: TextAlign.center,
                              style: SportikaType.scoreSmall.copyWith(
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
          ),
          if (minWidth > constraints.maxWidth) ...[
            const SizedBox(height: SportikaSpacing.xs),
            const Text(
              'Scroll horizontally to view all sets',
              style: SportikaType.caption,
            ),
          ],
        ],
      );
    },
  );
}

class _PointHistory extends StatelessWidget {
  const _PointHistory({required this.history, required this.names});
  final List<PadelPointRecord> history;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const Text('No points recorded yet.', style: SportikaType.caption);
    }
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      height:
          SportikaSpacing.xl *
          (history.length < 3 ? history.length * 4 : 10) *
          scale,
      child: Scrollbar(
        interactive: false,
        child: ListView.separated(
          primary: false,
          itemCount: history.length,
          separatorBuilder: (_, _) =>
              const Divider(height: 1, color: SportikaColors.borderSubtle),
          itemBuilder: (context, index) {
            final point = history[history.length - 1 - index];
            final tags = [
              if (point.tiebreak) 'TB',
              if (point.goldenPoint) 'GP',
              if (point.isDecidingPoint) 'Match',
            ];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: SportikaSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${point.index} · Set ${point.setIndex + 1} · ${point.tiebreak ? 'TB point' : 'Game'} ${point.gameIndex}'
                    '${tags.isEmpty ? '' : ' · ${tags.join(' · ')}'}',
                    style: SportikaType.micro,
                  ),
                  const SizedBox(height: SportikaSpacing.xs),
                  Text(
                    '${point.scoreBefore} → ${point.scoreAfter}',
                    style: SportikaType.bodyStrong,
                  ),
                  const SizedBox(height: SportikaSpacing.xs),
                  Text(
                    'Point · ${point.winnerSide >= 0 && point.winnerSide < names.length ? names[point.winnerSide] : '—'}',
                    style: SportikaType.caption,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
