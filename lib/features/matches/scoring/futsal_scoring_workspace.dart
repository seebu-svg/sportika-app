import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/matches/widgets/futsal_sheet.dart';
import 'package:sportika/features/matches/widgets/futsal_lineups.dart';

import 'package:sportika/features/live/widgets/live_clock.dart';
import 'package:sportika/features/matches/scoring/match_scoring_shell.dart';
import 'package:sportika/features/matches/scoring/match_scoring_validator.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/futsal/futsal.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Futsal: a clock driven by persisted clock events, the period controls,
/// goals with a scorer, fouls, cards, substitutions and the shootout panel.
///
/// The clock never keeps its own time — it reads the elapsed seconds the engine
/// folded from `clock` events plus the seconds since the last `start`/`resume`,
/// so a resume, a reassignment or a cold restart all replay identically.
class FutsalScoringWorkspace extends StatefulWidget {
  const FutsalScoringWorkspace({
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
  State<FutsalScoringWorkspace> createState() => _FutsalScoringWorkspaceState();
}

class _FutsalScoringWorkspaceState extends State<FutsalScoringWorkspace> {
  List<String> get _sides => widget.match.sideNames;

  int get _half => (widget.progress.state['half'] as num?)?.toInt() ?? 1;

  String get _phase => widget.progress.state['phase'] as String? ?? 'pre';

  bool get _running => widget.progress.state['running'] == true;

  int get _halfMinutes =>
      (widget.progress.state['periodMinutes'] as num?)?.toInt() ?? 20;

  int get _halves => (widget.progress.state['periods'] as num?)?.toInt() ?? 2;

  /// Seconds played in the current period, including the part of the current
  /// run that has not been banked yet.
  int _elapsed(BuildContext context) {
    final banked =
        (widget.progress.state['periodElapsed'] as num?)?.toInt() ?? 0;
    if (!_running) return banked;
    final resumeAt = DateTime.tryParse(
      widget.progress.state['resumeAt'] as String? ?? '',
    );
    if (resumeAt == null) return banked;
    final delta = LiveClockScope.nowOf(context).difference(resumeAt).inSeconds;
    final total = banked + (delta > 0 ? delta : 0);
    return total;
  }

  void _clock(String action) =>
      widget.onRecord(FutsalEngine.kClock, null, {'action': action});

  Future<void> _goal(int side) async {
    var type = 'regular';
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SportikaColors.surfaceElevated,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) {
          final rosterSide = type == 'ownGoal' ? 1 - side : side;
          final players = widget.match.participantsOnSide(rosterSide);
          void choose(MatchParticipant? player) => Navigator.pop(ctx, {
            'half': _half - 1,
            'goalType': type,
            if (player != null) 'player': player.displayName,
            if (player != null) 'playerId': player.profileId,
          });
          return FutsalSheet(
            title: 'Who scored?',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Goal for ${_sides[side]}',
                  style: SportikaType.bodyStrong,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final entry in {
                      'regular': 'Open play',
                      'penalty': 'Penalty goal',
                      'ownGoal': 'Own goal',
                    }.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: type == entry.key,
                        onSelected: (_) => update(() => type = entry.key),
                      ),
                  ],
                ),
                if (type == 'ownGoal')
                  Text(
                    'Select a player from ${_sides[1 - side]}. The goal counts for ${_sides[side]}.',
                    style: SportikaType.caption,
                  ),
                for (final player in players)
                  ListTile(
                    title: Text(player.displayName),
                    leading: PlayerAvatar(
                      initials: initialsOf(player.displayName),
                      size: 32,
                      photoUrl: context
                          .read<SessionController>()
                          .accountById(player.profileId)
                          ?.photoUrl,
                      photoPath: context
                          .read<SessionController>()
                          .accountById(player.profileId)
                          ?.photoPath,
                      color: widget.accent,
                    ),
                    onTap: () => choose(player),
                  ),
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('No scorer named'),
                  onTap: () => choose(null),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (selected == null || !mounted) return;
    widget.onRecord(FutsalEngine.kGoal, side, selected);
  }

  Future<MatchParticipant?> _pickPlayer(int side, String title) =>
      showModalBottomSheet<MatchParticipant>(
        context: context,
        isScrollControlled: true,
        backgroundColor: SportikaColors.surfaceElevated,
        builder: (ctx) => FutsalSheet(
          title: title,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.match.participantsOnSide(side).isEmpty)
                const Text(
                  'No accepted players on this team. Invite players before recording a player event.',
                ),
              for (final p in widget.match.participantsOnSide(side))
                ListTile(
                  title: Text(p.displayName),
                  onTap: () => Navigator.pop(ctx, p),
                ),
            ],
          ),
        ),
      );

  Future<void> _card(int side) async {
    final colour = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: SportikaColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => FutsalSheet(
        title: 'Which card?',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final colour in ['yellow', 'red'])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PrimaryButton(
                  label: colour == 'yellow' ? 'Yellow card' : 'Red card',
                  small: true,
                  tone: colour == 'yellow'
                      ? SportikaColors.gold
                      : SportikaColors.danger,
                  onPressed: () => Navigator.pop(ctx, colour),
                ),
              ),
          ],
        ),
      ),
    );
    if (colour == null || !mounted) return;
    final player = await _pickPlayer(side, 'Player receiving the card');
    if (player == null || !mounted) return;
    widget.onRecord('card', side, {
      'colour': colour,
      'half': _half - 1,
      'player': player.displayName,
      'playerId': player.profileId,
    });
  }

  Future<void> _foul(int side) async {
    final confirmed = await scoringConfirm(
      context,
      title: 'Record a foul?',
      body: '${_sides[side]} committed a foul in half $_half.',
      confirmLabel: 'Record foul',
    );
    if (!confirmed) return;
    widget.onRecord('foul', side, {'half': _half - 1});
  }

  Future<void> _substitution(int side) async {
    final incoming = await _pickPlayer(side, 'Player coming on');
    if (incoming == null || !mounted) return;
    final outgoing = await _pickPlayer(side, 'Player going off');
    if (outgoing == null || !mounted) return;
    widget.onRecord('substitution', side, {
      'in': incoming.displayName,
      'out': outgoing.displayName,
      'inId': incoming.profileId,
      'outId': outgoing.profileId,
      'half': _half - 1,
    });
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _elapsed(context);
    final shootout = _phase == 'shootout';
    final complete = _phase == 'complete';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          borderColor: widget.accent.withValues(alpha: 0.45),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _phaseLabel,
                      style: SportikaType.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(
                    _running ? 'Clock running' : 'Clock stopped',
                    color: _running
                        ? SportikaColors.mint
                        : SportikaColors.textMuted,
                    icon: _running ? Icons.timer : Icons.pause_circle_outline,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 8,
                children: [
                  Text(
                    _mmss(elapsed),
                    style: SportikaType.hero.copyWith(color: widget.accent),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'of ${_mmss(_halfMinutes * 60)}',
                      style: SportikaType.caption,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SportikaSpacing.sm),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  switch (_phase) {
                    'pre' => PrimaryButton(
                      label: 'Start clock',
                      icon: Icons.play_arrow_rounded,
                      small: true,
                      tone: widget.accent,
                      onPressed: () => _clock('start'),
                    ),
                    'running' => GhostButton(
                      label: 'Pause clock',
                      icon: Icons.pause,
                      onPressed: () => _clock('stop'),
                    ),
                    'paused' => PrimaryButton(
                      label: 'Resume clock',
                      icon: Icons.play_arrow_rounded,
                      small: true,
                      tone: widget.accent,
                      onPressed: () => _clock('resume'),
                    ),
                    'halfTime' => PrimaryButton(
                      label: _halves > 2 && _half >= 2
                          ? 'Start extra time ${_half - 1}'
                          : 'Start half ${(_half + 1).clamp(1, _halves)}',
                      icon: Icons.play_arrow_rounded,
                      small: true,
                      tone: widget.accent,
                      onPressed: () => _clock('resume'),
                    ),
                    _ => const SizedBox.shrink(),
                  },
                  if (_phase == 'running' || _phase == 'paused')
                    GhostButton(
                      label: _half < _halves ? 'End half $_half' : 'Full time',
                      icon: Icons.flag_outlined,
                      onPressed: () async {
                        final ok = await scoringConfirm(
                          context,
                          title: _half < _halves
                              ? 'End half $_half?'
                              : 'End the match?',
                          body: _half < _halves
                              ? 'The break starts now. The clock is banked at '
                                    '${_mmss(elapsed)}.'
                              : 'Full time at ${_mmss(elapsed)}. The scores are '
                                    'final unless a shootout is needed.',
                          confirmLabel: _half < _halves
                              ? 'End half'
                              : 'Full time',
                        );
                        if (ok) _clock('end_half');
                      },
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${widget.progress.state['extraTime'] == true ? 'Extra time' : 'Regulation'} · period $_half · $_halfMinutes minutes',
                style: SportikaType.caption.copyWith(fontSize: 10.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: SportikaSpacing.sm),
        if (_phase == 'pre')
          FutsalLineups(match: widget.match, onRecord: widget.onRecord),
        if (shootout)
          _ShootoutPanel(
            sides: _sides,
            shootout: widget.progress.contextChips.firstWhere(
              (c) => c.startsWith('Shootout'),
              orElse: () => 'Shootout',
            ),
            onRecord: widget.onRecord,
          )
        else if (!complete && (_phase == 'running' || _phase == 'paused')) ...[
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle('Goal', padding: EdgeInsets.zero),
                Row(
                  children: [
                    for (var side = 0; side < 2; side++) ...[
                      if (side == 1) const SizedBox(width: 8),
                      Expanded(
                        child: ScoringPad(
                          label: 'Goal',
                          hint: _sides[side],
                          icon: Icons.sports_soccer,
                          big: true,
                          tone: side == 0 ? widget.accent : SportikaColors.mint,
                          onTap: () => _goal(side),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: SportikaSpacing.sm),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle('Match sheet', padding: EdgeInsets.zero),
                for (var side = 0; side < 2; side++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _sides[side],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SportikaType.bodyStrong,
                          ),
                        ),
                        _SheetAction(label: 'Foul', onTap: () => _foul(side)),
                        const SizedBox(width: 6),
                        _SheetAction(
                          label: 'Card',
                          tone: SportikaColors.gold,
                          onTap: () => _card(side),
                        ),
                        const SizedBox(width: 6),
                        _SheetAction(
                          label: 'Sub',
                          tone: SportikaColors.mint,
                          onTap: () => _substitution(side),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                const HelperText(
                  'Fouls, cards and substitutions are kept on the match sheet. '
                  'They do not change the score.',
                ),
              ],
            ),
          ),
          const SectionTitle('Discipline'),
          _DisciplineCard(
            match: widget.match,
            accent: widget.accent,
            half: _half - 1,
          ),
        ],
      ],
    );
  }

  String get _phaseLabel => switch (_phase) {
    'pre' => 'Kick-off pending',
    'running' =>
      '${_half > 2 ? 'Extra time ${_half - 2}' : 'Half $_half'} · running',
    'paused' =>
      '${_half > 2 ? 'Extra time ${_half - 2}' : 'Half $_half'} · stopped',
    'halfTime' =>
      _halves > 2 && _half >= 2 ? 'Extra-time interval' : 'Half time',
    'shootout' => 'Penalty shootout',
    'complete' => 'Full time',
    _ => 'Match',
  };

  static String _mmss(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.label,
    required this.onTap,
    this.tone = SportikaColors.textBody,
  });

  final String label;
  final VoidCallback onTap;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SportikaColors.surfaceAlt,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: SportikaColors.border),
          ),
          child: Text(
            label,
            style: SportikaType.caption.copyWith(
              color: tone,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}

class _ShootoutPanel extends StatelessWidget {
  const _ShootoutPanel({
    required this.sides,
    required this.shootout,
    required this.onRecord,
  });

  final List<String> sides;
  final String shootout;
  final RecordMatchEvent onRecord;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      borderColor: SportikaColors.gold.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const Text('Penalty shootout', style: SportikaType.bodyStrong),
              Text(shootout, style: SportikaType.caption),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Best of five, then sudden death. Record every kick.',
            style: SportikaType.caption,
          ),
          for (var side = 0; side < 2; side++) ...[
            const SizedBox(height: SportikaSpacing.sm),
            Text(
              sides[side],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SportikaType.label,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: ScoringPad(
                    label: 'Scored',
                    tone: SportikaColors.mint,
                    onTap: () =>
                        onRecord(FutsalEngine.kPenalty, side, {'scored': true}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ScoringPad(
                    label: 'Missed',
                    tone: SportikaColors.surfaceAlt,
                    onTap: () => onRecord(FutsalEngine.kPenalty, side, {
                      'scored': false,
                    }),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Fouls and cards per side, counted from the sheet entries.
class _DisciplineCard extends StatelessWidget {
  const _DisciplineCard({
    required this.match,
    required this.accent,
    required this.half,
  });

  final int half;

  final SportMatch match;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final fouls = [0, 0];
    final periodFouls = [0, 0];
    final yellow = [0, 0];
    final red = [0, 0];
    var subs = 0;
    for (final e in match.events) {
      if (e.voided) continue;
      final side = e.side;
      switch (e.kind) {
        case 'foul':
          if (side != null && side >= 0 && side < 2) {
            fouls[side] += 1;
            if (e.data['half'] == half ||
                (half >= 2 &&
                    e.data['half'] is int &&
                    (e.data['half'] as int) >= 1)) {
              periodFouls[side] += 1;
            }
          }
        case 'card':
          if (side != null && side < 2) {
            if (e.data['colour'] == 'red') {
              red[side] += 1;
            } else {
              yellow[side] += 1;
            }
          }
        case 'substitution':
          subs += 1;
      }
    }
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var side = 0; side < 2; side++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    match.sideNames[side],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SportikaType.bodyStrong,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${periodFouls[side]} period / ${fouls[side]} total',
                        style: SportikaType.caption.copyWith(
                          color: periodFouls[side] >= 5
                              ? SportikaColors.gold
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _CardDot(
                        count: yellow[side],
                        colour: SportikaColors.gold,
                      ),
                      const SizedBox(width: 4),
                      _CardDot(count: red[side], colour: SportikaColors.danger),
                    ],
                  ),
                ],
              ),
            ),
          if (subs > 0)
            Text(
              '$subs substitution${subs == 1 ? '' : 's'} recorded',
              style: SportikaType.caption.copyWith(fontSize: 10.5),
            ),
          const SizedBox(height: 4),
          Text(
            'Accumulated fouls reset at half time. From the sixth foul, use the applicable penalty procedure. Second-half fouls carry into extra time.',
            style: SportikaType.caption.copyWith(fontSize: 10.5, color: accent),
          ),
        ],
      ),
    );
  }
}

class _CardDot extends StatelessWidget {
  const _CardDot({required this.count, required this.colour});

  final int count;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: count > 0 ? colour : SportikaColors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: count > 0 ? colour : SportikaColors.borderSubtle,
        ),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: count > 0
              ? (colour.computeLuminance() > .45
                    ? SportikaColors.deepest
                    : SportikaColors.text)
              : SportikaColors.textDim,
        ),
      ),
    );
  }
}
