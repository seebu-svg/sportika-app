import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/live/widgets/live_clock.dart';
import 'package:sportika/features/matches/scoring/futsal_roster.dart';
import 'package:sportika/features/matches/scoring/match_scoring_shell.dart';
import 'package:sportika/features/matches/scoring/match_scoring_validator.dart';
import 'package:sportika/features/matches/widgets/futsal_lineups.dart';
import 'package:sportika/features/matches/widgets/futsal_sheet.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/futsal/futsal.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Official Sportika Futsal scoring workspace.
///
/// All authoritative state is supplied by the match shell.
/// No local clock, score, or match event is persisted here.
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
  bool _submitting = false;
  bool _dialogOpen = false;

  List<String> get _sides => widget.match.sideNames;

  int get _half => (widget.progress.state['half'] as num?)?.toInt() ?? 1;

  int get _periodMinutes =>
      (widget.progress.state['periodMinutes'] as num?)?.toInt() ?? 20;

  int get _periods => (widget.progress.state['periods'] as num?)?.toInt() ?? 2;

  String get _phase => widget.progress.state['phase'] as String? ?? 'pre';

  bool get _running => widget.progress.state['running'] == true;

  bool get _active => _phase == 'running' || _phase == 'paused';

  bool get _locked => _submitting || _dialogOpen;

  int _elapsed(BuildContext context) {
    final banked =
        (widget.progress.state['periodElapsed'] as num?)?.toInt() ?? 0;

    if (!_running) return banked;

    final resumeAt = DateTime.tryParse(
      widget.progress.state['resumeAt'] as String? ?? '',
    );

    if (resumeAt == null) return banked;

    final difference = LiveClockScope.nowOf(context)
        .difference(resumeAt)
        .inSeconds;

    return banked + (difference < 0 ? 0 : difference);
  }

  /// Prevents synchronous duplicate event submissions.
  ///
  /// The parent match shell remains responsible for durable
  /// deduplication and server-authoritative validation.
  void _record(String kind, int? side, Map<String, dynamic> data) {
    if (_submitting) return;

    setState(() => _submitting = true);

    try {
      widget.onRecord(kind, side, data);
    } catch (_) {
      if (mounted) {
        _message('Unable to record the event. Try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<T?> _sheet<T>({required String title, required Widget child}) async {
    if (_locked) return null;

    setState(() => _dialogOpen = true);

    try {
      return await showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        backgroundColor: SportikaColors.surfaceElevated,
        builder: (context) => SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: FutsalSheet(
              title: title,
              child: FlexibleSheetContent(child: child),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _dialogOpen = false);
      }
    }
  }

  FutsalRosterState _roster(int side) =>
      FutsalRoster.resolve(widget.match, side);

  List<MatchParticipant> _players(int side, {Set<String>? eligibleIds}) {
    final participants = widget.match.participantsOnSide(side);

    if (eligibleIds == null) {
      return participants;
    }

    return participants
        .where((p) => eligibleIds.contains(p.profileId))
        .toList();
  }

  Future<MatchParticipant?> _pickPlayer(
    int side,
    String title, {
    Set<String>? eligibleIds,
  }) {
    final players = _players(side, eligibleIds: eligibleIds);

    return _sheet<MatchParticipant>(
      title: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (players.isEmpty)
            const Padding(
              padding: EdgeInsets.all(SportikaSpacing.md),
              child: HelperText('No eligible players are available.'),
            ),
          for (final player in players)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: PlayerAvatar(
                initials: initialsOf(player.displayName),
                size: 36,
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
              title: Text(player.displayName, style: SportikaType.bodyStrong),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(context, player),
            ),
        ],
      ),
    );
  }

  Future<void> _goal(int side) async {
    if (!_active || _locked) return;

    final selected = await _sheet<Map<String, dynamic>>(
      title: 'Record goal',
      child: _GoalSelection(
        match: widget.match,
        side: side,
        accent: widget.accent,
      ),
    );

    if (!mounted || selected == null || !_active) {
      return;
    }

    _record(FutsalEngine.kGoal, side, {...selected, 'half': _half - 1});
  }

  Future<void> _card(int side) async {
    if (!_active || _locked) return;

    final roster = _roster(side);

    final colour = await _sheet<String>(
      title: 'Disciplinary card',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(
            label: 'Yellow card',
            tone: SportikaColors.gold,
            onPressed: () => Navigator.pop(context, 'yellow'),
          ),
          const SizedBox(height: SportikaSpacing.sm),
          PrimaryButton(
            label: 'Red card',
            tone: SportikaColors.danger,
            onPressed: () => Navigator.pop(context, 'red'),
          ),
        ],
      ),
    );

    if (!mounted || colour == null || !_active) {
      return;
    }

    // Prefer players on court. Disciplinary exceptions
    // involving substitutes require separate engine rules.
    final player = await _pickPlayer(
      side,
      'Player receiving the card',
      eligibleIds: roster.onCourt,
    );

    if (!mounted || player == null || !_active) {
      return;
    }

    if (!_roster(side).onCourt.contains(player.profileId)) {
      _message('Player is no longer on court.');
      return;
    }

    _record('card', side, {
      'colour': colour,
      'half': _half - 1,
      'player': player.displayName,
      'playerId': player.profileId,
    });
  }

  Future<void> _foul(int side) async {
    if (!_active || _locked) return;

    final confirmed = await scoringConfirm(
      context,
      title: 'Record a foul?',
      body: '${_sides[side]} committed a foul.',
      confirmLabel: 'Record foul',
    );

    if (!mounted || !confirmed || !_active) return;

    _record('foul', side, {'half': _half - 1});
  }

  Future<void> _substitution(int side) async {
    if (!_active || _locked) return;

    final roster = _roster(side);

    if (roster.onCourt.isEmpty || roster.bench.isEmpty) {
      _message('Configure the lineup and available substitutes first.');
      return;
    }

    final outgoing = await _pickPlayer(
      side,
      'Player leaving the court',
      eligibleIds: roster.onCourt,
    );

    if (!mounted || outgoing == null || !_active) return;

    final incoming = await _pickPlayer(
      side,
      'Player entering the court',
      eligibleIds: roster.bench,
    );

    if (!mounted || incoming == null || !_active) return;

    // Re-resolve because match state may have changed
    // while the scorer was selecting players.
    final latest = _roster(side);

    if (!FutsalRoster.canSubstitute(
      roster: latest,
      outId: outgoing.profileId,
      inId: incoming.profileId,
    )) {
      _message('This substitution is no longer available.');
      return;
    }

    final confirmed = await scoringConfirm(
      context,
      title: 'Confirm substitution?',
      body:
          '${incoming.displayName} IN\n'
          '${outgoing.displayName} OUT',
      confirmLabel: 'Record substitution',
    );

    if (!mounted || !confirmed || !_active) return;

    if (!FutsalRoster.canSubstitute(
      roster: _roster(side),
      outId: outgoing.profileId,
      inId: incoming.profileId,
    )) {
      _message('Roster changed. Select players again.');
      return;
    }

    _record('substitution', side, {
      'in': incoming.displayName,
      'out': outgoing.displayName,
      'inId': incoming.profileId,
      'outId': outgoing.profileId,
      'half': _half - 1,
    });
  }

  void _clock(String action) {
    if (_locked) return;

    final allowed = switch (action) {
      'start' => _phase == 'pre',
      'stop' => _phase == 'running',
      'resume' => _phase == 'paused' || _phase == 'halfTime',
      'end_half' => _phase == 'running' || _phase == 'paused',
      _ => false,
    };

    if (!allowed) return;

    _record(FutsalEngine.kClock, null, {'action': action});
  }

  Future<void> _endPeriod(int elapsed) async {
    if (!_active || _locked) return;

    final isFinal = _half >= _periods;

    final confirmed = await scoringConfirm(
      context,
      title: isFinal ? 'End match?' : 'End period $_half?',
      body: isFinal
          ? 'Full time at ${_mmss(elapsed)}. '
                'The match engine will determine the next phase.'
          : 'The current period will end at '
                '${_mmss(elapsed)}.',
      confirmLabel: isFinal ? 'Full time' : 'End period',
    );

    if (!mounted || !confirmed) return;

    _clock('end_half');
  }

  List<int> _scores() {
    final state = widget.progress.state;
    final a = state['scoreA'];
    final b = state['scoreB'];

    if (a is num && b is num) {
      return [a.toInt(), b.toInt()];
    }

    final scores = [0, 0];

    for (final event in widget.match.events) {
      if (event.voided || event.kind != FutsalEngine.kGoal) {
        continue;
      }

      final side = event.side;

      if (side != null && side >= 0 && side < 2) {
        scores[side]++;
      }
    }

    return scores;
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _elapsed(context);
    final scores = _scores();
    final shootout = _phase == 'shootout';
    final complete = _phase == 'complete';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FutsalScoreHero(
          sides: _sides,
          scores: scores,
          phase: _phase,
          half: _half,
          elapsed: elapsed,
          periodMinutes: _periodMinutes,
          running: _running,
          accent: widget.accent,
        ),

        const SizedBox(height: SportikaSpacing.sm),

        _ClockControls(
          phase: _phase,
          half: _half,
          periods: _periods,
          busy: _locked,
          onClock: _clock,
          onEndPeriod: () => _endPeriod(elapsed),
        ),

        if (_phase == 'pre') ...[
          const SizedBox(height: SportikaSpacing.md),
          FutsalLineups(match: widget.match, onRecord: widget.onRecord),
        ],

        if (_active) ...[
          const SizedBox(height: SportikaSpacing.md),

          _FutsalQuickActions(
            sides: _sides,
            accent: widget.accent,
            enabled: !_locked,
            onGoal: _goal,
            onFoul: _foul,
            onCard: _card,
            onSubstitution: _substitution,
          ),

          const SizedBox(height: SportikaSpacing.md),

          _ActiveRosterPanel(match: widget.match),

          const SizedBox(height: SportikaSpacing.md),

          _DisciplineCard(
            match: widget.match,
            half: _half - 1,
            accent: widget.accent,
          ),
        ],

        if (shootout) ...[
          const SizedBox(height: SportikaSpacing.md),
          _ShootoutPanel(
            match: widget.match,
            progress: widget.progress,
            sides: _sides,
            enabled: !_locked,
            onRecord: _record,
          ),
        ],

        if (_phase != 'pre') ...[
          const SizedBox(height: SportikaSpacing.md),
          _FutsalTimeline(match: widget.match),
        ],

        if (complete) ...[
          const SizedBox(height: SportikaSpacing.md),
          const InfoBanner(
            icon: Icons.emoji_events_outlined,
            text:
                'Match completed. Review the official result '
                'in the Match Center.',
          ),
        ],

        const SizedBox(height: SportikaSpacing.lg),
      ],
    );
  }

  static String _mmss(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final minutes = (safe ~/ 60).toString().padLeft(2, '0');
    final remainder = (safe % 60).toString().padLeft(2, '0');
    return '$minutes:$remainder';
  }
}

/// Scroll-safe content for player and action sheets.
class FlexibleSheetContent extends StatelessWidget {
  const FlexibleSheetContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.65,
      ),
      child: SingleChildScrollView(child: child),
    );
  }
}

/// Broadcast-inspired scoreboard with live match clock.
class _FutsalScoreHero extends StatelessWidget {
  const _FutsalScoreHero({
    required this.sides,
    required this.scores,
    required this.phase,
    required this.half,
    required this.elapsed,
    required this.periodMinutes,
    required this.running,
    required this.accent,
  });

  final List<String> sides;
  final List<int> scores;
  final String phase;
  final int half;
  final int elapsed;
  final int periodMinutes;
  final bool running;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final label = switch (phase) {
      'pre' => 'KICK-OFF PENDING',
      'running' => 'LIVE · PERIOD $half',
      'paused' => 'PAUSED · PERIOD $half',
      'halfTime' => 'PERIOD BREAK',
      'shootout' => 'PENALTY SHOOTOUT',
      'complete' => 'FULL TIME',
      _ => 'FUTSAL MATCH',
    };

    return Container(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      decoration: BoxDecoration(
        color: SportikaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.sports_soccer, color: accent),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: Text(
                  'SPORTIKA / FUTSAL',
                  style: SportikaType.micro.copyWith(color: accent),
                ),
              ),
              StatusPill(
                label,
                color: running ? SportikaColors.mint : SportikaColors.textMuted,
              ),
            ],
          ),

          const SizedBox(height: SportikaSpacing.lg),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _HeroTeam(
                  name: sides[0],
                  alignment: CrossAxisAlignment.start,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SportikaSpacing.sm,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    '${scores[0]} : ${scores[1]}',
                    key: ValueKey('${scores[0]}:${scores[1]}'),
                    style: SportikaType.hero.copyWith(
                      color: SportikaColors.text,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _HeroTeam(
                  name: sides[1],
                  alignment: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),

          const SizedBox(height: SportikaSpacing.md),
          const Divider(),
          const SizedBox(height: SportikaSpacing.sm),

          Text(
            _FutsalScoringWorkspaceState._mmss(elapsed),
            style: SportikaType.hero.copyWith(color: accent),
          ),
          Text(
            'OF ${_FutsalScoringWorkspaceState._mmss(periodMinutes * 60)}'
            ' · PERIOD $half',
            style: SportikaType.micro,
          ),
        ],
      ),
    );
  }
}

class _HeroTeam extends StatelessWidget {
  const _HeroTeam({required this.name, required this.alignment});

  final String name;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignment,
      children: [
        const CircleAvatar(
          backgroundColor: SportikaColors.surfaceAlt,
          child: Icon(Icons.shield_outlined, color: SportikaColors.text),
        ),
        const SizedBox(height: SportikaSpacing.sm),
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: alignment == CrossAxisAlignment.end
              ? TextAlign.end
              : TextAlign.start,
          style: SportikaType.bodyStrong,
        ),
      ],
    );
  }
}

class _ClockControls extends StatelessWidget {
  const _ClockControls({
    required this.phase,
    required this.half,
    required this.periods,
    required this.busy,
    required this.onClock,
    required this.onEndPeriod,
  });

  final String phase;
  final int half;
  final int periods;
  final bool busy;
  final ValueChanged<String> onClock;
  final VoidCallback onEndPeriod;

  @override
  Widget build(BuildContext context) {
    if (phase == 'complete' || phase == 'shootout') {
      return const SizedBox.shrink();
    }

    return SurfaceCard(
      child: Wrap(
        spacing: SportikaSpacing.sm,
        runSpacing: SportikaSpacing.sm,
        children: [
          if (phase == 'pre')
            PrimaryButton(
              label: 'Start match',
              icon: Icons.play_arrow_rounded,
              small: true,
              onPressed: busy ? null : () => onClock('start'),
            ),
          if (phase == 'running')
            GhostButton(
              label: 'Pause clock',
              icon: Icons.pause_rounded,
              onPressed: busy ? null : () => onClock('stop'),
            ),
          if (phase == 'paused' || phase == 'halfTime')
            PrimaryButton(
              label: phase == 'halfTime' ? 'Start next period' : 'Resume clock',
              icon: Icons.play_arrow_rounded,
              small: true,
              onPressed: busy ? null : () => onClock('resume'),
            ),
          if (phase == 'running' || phase == 'paused')
            GhostButton(
              label: half >= periods ? 'Full time' : 'End period',
              icon: Icons.flag_outlined,
              onPressed: busy ? null : onEndPeriod,
            ),
        ],
      ),
    );
  }
}

class _FutsalQuickActions extends StatelessWidget {
  const _FutsalQuickActions({
    required this.sides,
    required this.accent,
    required this.enabled,
    required this.onGoal,
    required this.onFoul,
    required this.onCard,
    required this.onSubstitution,
  });

  final List<String> sides;
  final Color accent;
  final bool enabled;
  final ValueChanged<int> onGoal;
  final ValueChanged<int> onFoul;
  final ValueChanged<int> onCard;
  final ValueChanged<int> onSubstitution;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Quick scoring', padding: EdgeInsets.zero),
        const SizedBox(height: SportikaSpacing.sm),

        Row(
          children: [
            for (var side = 0; side < 2; side++) ...[
              if (side > 0) const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: ScoringPad(
                  label: 'GOAL',
                  hint: sides[side],
                  icon: Icons.sports_soccer,
                  big: true,
                  tone: side == 0 ? accent : SportikaColors.mint,
                  onTap: enabled ? () => onGoal(side) : null,
                ),
              ),
            ],
          ],
        ),

        const SizedBox(height: SportikaSpacing.md),

        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('MATCH ACTIONS', style: SportikaType.bodyStrong),
              const SizedBox(height: SportikaSpacing.md),

              for (var side = 0; side < 2; side++) ...[
                Text(
                  sides[side],
                  style: SportikaType.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: SportikaSpacing.sm),

                Row(
                  children: [
                    Expanded(
                      child: _QuickAction(
                        label: 'Foul',
                        icon: Icons.flag_outlined,
                        onTap: enabled ? () => onFoul(side) : null,
                      ),
                    ),
                    const SizedBox(width: SportikaSpacing.sm),
                    Expanded(
                      child: _QuickAction(
                        label: 'Card',
                        icon: Icons.style_outlined,
                        tone: SportikaColors.gold,
                        onTap: enabled ? () => onCard(side) : null,
                      ),
                    ),
                    const SizedBox(width: SportikaSpacing.sm),
                    Expanded(
                      child: _QuickAction(
                        label: 'Sub',
                        icon: Icons.swap_horiz_rounded,
                        tone: SportikaColors.mint,
                        onTap: enabled ? () => onSubstitution(side) : null,
                      ),
                    ),
                  ],
                ),

                if (side == 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: SportikaSpacing.md),
                    child: Divider(),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.tone = SportikaColors.textBody,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SportikaColors.surfaceAlt,
      borderRadius: BorderRadius.circular(SportikaRadius.control),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.all(SportikaSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SportikaRadius.control),
            border: Border.all(color: SportikaColors.borderSubtle),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: tone),
              const SizedBox(height: SportikaSpacing.xs),
              Text(label, style: SportikaType.caption.copyWith(color: tone)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalSelection extends StatefulWidget {
  const _GoalSelection({
    required this.match,
    required this.side,
    required this.accent,
  });

  final SportMatch match;
  final int side;
  final Color accent;

  @override
  State<_GoalSelection> createState() => _GoalSelectionState();
}

class _GoalSelectionState extends State<_GoalSelection> {
  String _type = 'regular';

  @override
  Widget build(BuildContext context) {
    final playerSide = _type == 'ownGoal' ? 1 - widget.side : widget.side;

    final roster = FutsalRoster.resolve(widget.match, playerSide);

    final participants = widget.match.participantsOnSide(playerSide);

    final active = participants
        .where((p) => roster.onCourt.contains(p.profileId))
        .toList();

    final others = participants
        .where((p) => !roster.onCourt.contains(p.profileId))
        .toList();

    void select(MatchParticipant? player) {
      Navigator.pop(context, {
        'goalType': _type,
        if (player != null) 'player': player.displayName,
        if (player != null) 'playerId': player.profileId,
      });
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Goal for ${widget.match.sideNames[widget.side]}',
          style: SportikaType.bodyStrong,
        ),
        const SizedBox(height: SportikaSpacing.md),

        Wrap(
          spacing: SportikaSpacing.sm,
          runSpacing: SportikaSpacing.sm,
          children: [
            for (final entry in const {
              'regular': 'Open play',
              'penalty': 'Penalty',
              'ownGoal': 'Own goal',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _type == entry.key,
                onSelected: (_) {
                  setState(() => _type = entry.key);
                },
              ),
          ],
        ),

        const SizedBox(height: SportikaSpacing.md),

        if (_type == 'ownGoal')
          const HelperText(
            'Select the player from the team that '
            'conceded the own goal.',
          ),

        const Text('ON COURT', style: SportikaType.micro),

        for (final player in active)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(player.displayName),
            leading: const Icon(Icons.person_rounded),
            onTap: () => select(player),
          ),

        if (active.isEmpty)
          const HelperText('No active players found in the official lineup.'),

        if (others.isNotEmpty) ...[
          const SizedBox(height: SportikaSpacing.sm),
          const Text('OTHER REGISTERED PLAYERS', style: SportikaType.micro),
          for (final player in others)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(player.displayName),
              subtitle: const Text('Use for retrospective corrections only'),
              onTap: () => select(player),
            ),
        ],

        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.help_outline),
          title: const Text('No scorer named'),
          onTap: () => select(null),
        ),
      ],
    );
  }
}

class _ActiveRosterPanel extends StatelessWidget {
  const _ActiveRosterPanel({required this.match});

  final SportMatch match;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('ON-COURT LINEUPS', style: SportikaType.bodyStrong),
          const SizedBox(height: SportikaSpacing.md),

          for (var side = 0; side < 2; side++) ...[
            _RosterTeam(match: match, side: side),
            if (side == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: SportikaSpacing.md),
                child: Divider(),
              ),
          ],
        ],
      ),
    );
  }
}

class _RosterTeam extends StatelessWidget {
  const _RosterTeam({required this.match, required this.side});

  final SportMatch match;
  final int side;

  @override
  Widget build(BuildContext context) {
    final roster = FutsalRoster.resolve(match, side);

    final names = {
      for (final p in match.participantsOnSide(side))
        p.profileId: p.displayName,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                match.sideNames[side],
                style: SportikaType.bodyStrong,
              ),
            ),
            Text(
              '${roster.onCourtCount}/5 ON COURT',
              style: SportikaType.micro,
            ),
          ],
        ),

        const SizedBox(height: SportikaSpacing.sm),

        if (roster.onCourt.isEmpty)
          const HelperText('No on-court lineup available.')
        else
          Wrap(
            spacing: SportikaSpacing.sm,
            runSpacing: SportikaSpacing.sm,
            children: [
              for (final id in roster.onCourt)
                Chip(
                  avatar: Icon(
                    id == roster.goalkeeperId
                        ? Icons.shield_outlined
                        : Icons.person_outline,
                    color: SportikaColors.text,
                  ),
                  label: Text(names[id] ?? 'Unknown player'),
                ),
            ],
          ),

        const SizedBox(height: SportikaSpacing.sm),

        Text(
          '${roster.benchCount} available substitutes'
          ' · ${roster.dismissed.length} dismissed',
          style: SportikaType.caption,
        ),

        if (!roster.hasGoalkeeper)
          const Padding(
            padding: EdgeInsets.only(top: SportikaSpacing.xs),
            child: HelperText('Goalkeeper not explicitly assigned.'),
          ),
      ],
    );
  }
}

/// Counts recorded disciplinary events.
///
/// Period indexing follows the existing zero-based
/// `half` event payload.
class _DisciplineCard extends StatelessWidget {
  const _DisciplineCard({
    required this.match,
    required this.half,
    required this.accent,
  });

  final SportMatch match;
  final int half;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final totalFouls = [0, 0];
    final accumulatedFouls = [0, 0];
    final yellow = [0, 0];
    final red = [0, 0];

    // Regulation first half = 0.
    // Regulation second half and extra time = 1+.
    final accumulationGroup = half == 0 ? 0 : 1;

    for (final event in match.events) {
      if (event.voided) continue;

      final side = event.side;

      if (side == null || side < 0 || side > 1) {
        continue;
      }

      switch (event.kind) {
        case 'foul':
          totalFouls[side]++;

          final eventHalf = (event.data['half'] as num?)?.toInt();

          if (eventHalf != null &&
              (eventHalf == 0 ? 0 : 1) == accumulationGroup) {
            accumulatedFouls[side]++;
          }

        case 'card':
          if (event.data['colour'] == 'yellow') {
            yellow[side]++;
          } else if (event.data['colour'] == 'red') {
            red[side]++;
          }
      }
    }

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('DISCIPLINE', style: SportikaType.bodyStrong),

          const SizedBox(height: SportikaSpacing.md),

          for (var side = 0; side < 2; side++) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    match.sideNames[side],
                    style: SportikaType.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${accumulatedFouls[side]} fouls',
                  style: SportikaType.caption.copyWith(
                    color: accumulatedFouls[side] >= 5
                        ? SportikaColors.gold
                        : SportikaColors.text,
                  ),
                ),
                const SizedBox(width: SportikaSpacing.sm),
                _CardCounter(count: yellow[side], color: SportikaColors.gold),
                const SizedBox(width: SportikaSpacing.xs),
                _CardCounter(count: red[side], color: SportikaColors.danger),
              ],
            ),

            if (accumulatedFouls[side] >= 5)
              const Padding(
                padding: EdgeInsets.only(top: SportikaSpacing.xs),
                child: HelperText(
                  'Accumulated foul threshold approaching '
                  'or reached. Apply the official rules.',
                ),
              ),

            if (side == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: SportikaSpacing.md),
                child: Divider(),
              ),
          ],

          const SizedBox(height: SportikaSpacing.sm),

          Text(
            'Accumulated fouls: second-half counts '
            'carry into extra time under standard rules. '
            'Match-specific rules remain authoritative.',
            style: SportikaType.caption.copyWith(color: accent),
          ),
        ],
      ),
    );
  }
}

class _CardCounter extends StatelessWidget {
  const _CardCounter({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: SportikaColors.surfaceAlt,
        borderRadius: BorderRadius.circular(SportikaRadius.badge),
        border: Border.all(color: color),
      ),
      child: Text(
        '$count',
        style: SportikaType.bodyStrong.copyWith(color: color),
      ),
    );
  }
}

/// Displays recorded kicks and lets the scorer submit
/// a new result. The match engine must validate turn
/// order and completion.
class _ShootoutPanel extends StatelessWidget {
  const _ShootoutPanel({
    required this.match,
    required this.progress,
    required this.sides,
    required this.enabled,
    required this.onRecord,
  });

  final SportMatch match;
  final MatchProgress progress;
  final List<String> sides;
  final bool enabled;
  final RecordMatchEvent onRecord;

  @override
  Widget build(BuildContext context) {
    final kicks =
        match.events
            .where((e) => !e.voided && e.kind == FutsalEngine.kPenalty)
            .toList()
          ..sort((a, b) => a.seq.compareTo(b.seq));

    final counts = [0, 0];
    final scored = [0, 0];

    for (final kick in kicks) {
      final side = kick.side;

      if (side == null || side < 0 || side > 1) {
        continue;
      }

      counts[side]++;

      if (kick.data['scored'] == true) {
        scored[side]++;
      }
    }

    // Only use an authoritative turn if the engine
    // exposes one. Do not infer turn order from counts.
    final rawTurn = progress.state['penaltySide'];
    final turn = rawTurn is num ? rawTurn.toInt() : null;

    return SurfaceCard(
      borderColor: SportikaColors.gold.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('PENALTY SHOOTOUT', style: SportikaType.bodyStrong),
          const SizedBox(height: SportikaSpacing.sm),

          const HelperText(
            'Record each kick. The official engine '
            'determines turn order and the result.',
          ),

          const SizedBox(height: SportikaSpacing.md),

          for (var side = 0; side < 2; side++) ...[
            Row(
              children: [
                Expanded(
                  child: Text(sides[side], style: SportikaType.bodyStrong),
                ),
                Text(
                  '${scored[side]} / ${counts[side]}',
                  style: SportikaType.titleMedium,
                ),
              ],
            ),

            const SizedBox(height: SportikaSpacing.sm),

            Wrap(
              spacing: SportikaSpacing.xs,
              children: [
                for (final kick in kicks.where((e) => e.side == side))
                  Icon(
                    kick.data['scored'] == true
                        ? Icons.check_circle
                        : Icons.cancel_outlined,
                    color: kick.data['scored'] == true
                        ? SportikaColors.mint
                        : SportikaColors.danger,
                  ),
              ],
            ),

            const SizedBox(height: SportikaSpacing.sm),

            Row(
              children: [
                Expanded(
                  child: ScoringPad(
                    label: 'Scored',
                    tone: SportikaColors.mint,
                    onTap: enabled && (turn == null || turn == side)
                        ? () => onRecord(FutsalEngine.kPenalty, side, {
                            'scored': true,
                          })
                        : null,
                  ),
                ),
                const SizedBox(width: SportikaSpacing.sm),
                Expanded(
                  child: ScoringPad(
                    label: 'Missed',
                    tone: SportikaColors.surfaceAlt,
                    onTap: enabled && (turn == null || turn == side)
                        ? () => onRecord(FutsalEngine.kPenalty, side, {
                            'scored': false,
                          })
                        : null,
                  ),
                ),
              ],
            ),

            if (side == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: SportikaSpacing.md),
                child: Divider(),
              ),
          ],
        ],
      ),
    );
  }
}

class _FutsalTimeline extends StatelessWidget {
  const _FutsalTimeline({required this.match});

  final SportMatch match;

  @override
  Widget build(BuildContext context) {
    final events =
        match.events
            .where(
              (e) =>
                  !e.voided &&
                  const {
                    FutsalEngine.kGoal,
                    'foul',
                    'card',
                    'substitution',
                  }.contains(e.kind),
            )
            .toList()
          ..sort((a, b) => b.seq.compareTo(a.seq));

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('MATCH TIMELINE', style: SportikaType.bodyStrong),

          const SizedBox(height: SportikaSpacing.md),

          if (events.isEmpty)
            const HelperText('Official match events will appear here.')
          else
            for (final event in events.take(8)) ...[
              _TimelineEntry(event: event, match: match),
              const SizedBox(height: SportikaSpacing.sm),
            ],
        ],
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({required this.event, required this.match});

  final MatchEvent event;
  final SportMatch match;

  @override
  Widget build(BuildContext context) {
    final side = event.side;

    final team = side != null && side >= 0 && side < 2
        ? match.sideNames[side]
        : 'Match';

    final icon = switch (event.kind) {
      FutsalEngine.kGoal => Icons.sports_soccer,
      'foul' => Icons.flag_outlined,
      'card' => Icons.style_outlined,
      'substitution' => Icons.swap_horiz,
      _ => Icons.circle_outlined,
    };

    final title = switch (event.kind) {
      FutsalEngine.kGoal => 'Goal',
      'foul' => 'Foul',
      'card' => 'Card',
      'substitution' => 'Substitution',
      _ => 'Match event',
    };

    final description = switch (event.kind) {
      FutsalEngine.kGoal =>
        event.data['player'] as String? ?? 'Scorer not specified',
      'card' => event.data['player'] as String? ?? 'Player not specified',
      'substitution' =>
        '${event.data['in'] ?? 'Player'} in · '
            '${event.data['out'] ?? 'Player'} out',
      _ => team,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          backgroundColor: SportikaColors.surfaceAlt,
          child: Icon(
            icon,
            color: event.kind == 'card'
                ? SportikaColors.gold
                : SportikaColors.text,
          ),
        ),
        const SizedBox(width: SportikaSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$title · $team', style: SportikaType.bodyStrong),
              Text(description, style: SportikaType.caption),
            ],
          ),
        ),
      ],
    );
  }
}
