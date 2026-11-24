import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sportika/features/matches/widgets/cricket_match_report.dart';
import 'package:sportika/features/matches/scoring/cricket_roster.dart';
import 'package:sportika/features/matches/scoring/match_scoring_shell.dart';
import 'package:sportika/features/matches/scoring/match_scoring_validator.dart';
import 'package:sportika/features/personal_games/scoring/cricket/cricket.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/default_avatar.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Official scoring UI. The match shell owns persistence and authoritative state.
///
/// A parent can mount [CricketDeliveryPad] in its bottomNavigationBar. For a
/// fully functional external dock, provide a [CricketScoringController] to both
/// this workspace and the parent; the controller exposes the same safe actions.
class CricketScoringController extends ChangeNotifier {
  bool _enabled = false;
  ValueChanged<int>? _runs;
  ValueChanged<String>? _extra;
  VoidCallback? _wicket;

  bool get enabled => _enabled;

  void recordRuns(int runs) => _runs?.call(runs);
  void recordExtra(String extra) => _extra?.call(extra);
  void recordWicket() => _wicket?.call();

  void attach({
    required bool enabled,
    required ValueChanged<int> runs,
    required ValueChanged<String> extra,
    required VoidCallback wicket,
  }) {
    _enabled = enabled;
    _runs = runs;
    _extra = extra;
    _wicket = wicket;
    notifyListeners();
  }

  void detach() {
    _enabled = false;
    _runs = null;
    _extra = null;
    _wicket = null;
    notifyListeners();
  }
}

class CricketScoringWorkspace extends StatefulWidget {
  const CricketScoringWorkspace({
    super.key,
    required this.match,
    required this.progress,
    required this.accent,
    required this.onRecord,
    this.showInlineDeliveryPad = true,
    this.controller,
  });

  final SportMatch match;
  final MatchProgress progress;
  final Color accent;
  final RecordMatchEvent onRecord;
  final bool showInlineDeliveryPad;
  final CricketScoringController? controller;

  @override
  State<CricketScoringWorkspace> createState() =>
      _CricketScoringWorkspaceState();
}

class _CricketScoringWorkspaceState extends State<CricketScoringWorkspace> {
  String? _strikerPick;
  String? _nonStrikerPick;
  String? _bowlerPick;
  bool _recording = false;

  int get _innings => (widget.progress.state['innings'] as num?)?.toInt() ?? 0;
  bool get _open => widget.progress.state['open'] == true;
  bool get _complete => widget.progress.isComplete;
  bool get _canRecord => _open && !_complete && !_recording;

  int get _batSide {
    final active = (widget.progress.state['batSide'] as num?)?.toInt();
    if (_open && (active == 0 || active == 1)) return active!;
    final next = (widget.progress.state['nextBatSide'] as num?)?.toInt();
    if (next == 0 || next == 1) return next!;
    if (active == 0 || active == 1) return active!;
    return 0;
  }

  int get _bowlingSide => 1 - _batSide;

  List<MatchEvent> get _balls =>
      widget.match.events
          .where(
            (e) =>
                !e.voided &&
                e.kind == CricketEngine.kBall &&
                e.side == _batSide,
          )
          .toList()
        ..sort((a, b) => a.seq.compareTo(b.seq));

  ({
    String? striker,
    String? nonStriker,
    String? bowler,
    int legalBalls,
    bool newOver,
  })
  get _projected => CricketRoster.strike(widget.match, _batSide);

  String? get _striker => _strikerPick ?? _projected.striker;
  String? get _nonStriker => _nonStrikerPick ?? _projected.nonStriker;
  String? get _bowler => _bowlerPick ?? _projected.bowler;

  Map<String, dynamic>? get _toss {
    final value = widget.progress.state['toss'];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncController();
    });
  }

  @override
  void didUpdateWidget(covariant CricketScoringWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.match != widget.match ||
        oldWidget.progress.state['innings'] !=
            widget.progress.state['innings'] ||
        oldWidget.progress.state['batSide'] !=
            widget.progress.state['batSide'] ||
        oldWidget.progress.state['nextBatSide'] !=
            widget.progress.state['nextBatSide']) {
      _clearPicks();
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncController();
    });
  }

  @override
  void dispose() {
    widget.controller?.detach();
    super.dispose();
  }

  void _syncController() {
    widget.controller?.attach(
      enabled: _canRecord,
      runs: (runs) => _ball({'runs': runs, 'dot': runs == 0}),
      extra: _extra,
      wicket: _wicket,
    );
  }

  void _clearPicks() {
    _strikerPick = null;
    _nonStrikerPick = null;
    _bowlerPick = null;
  }

  List<String> _namesOn(int side) => CricketRoster.namesOn(widget.match, side);

  List<String> _availableBatters({String? exclude}) {
    final dismissed = <String>{};
    for (final e in _balls) {
      if (e.data['wicket'] != true) continue;
      final name = e.data['dismissedBatter'] ?? e.data['striker'];
      if (name is String && name.isNotEmpty) dismissed.add(name);
    }
    return [
      for (final name in _namesOn(_batSide))
        if (name != exclude && !dismissed.contains(name)) name,
    ];
  }

  Future<void> _pickStriker() async {
    if (!_canRecord) return;
    final side = _batSide;
    final picked = await pickScoringName(
      context,
      title: 'Select striker',
      names: _availableBatters(exclude: _nonStriker),
      hint: widget.match.sideNames[side],
    );
    if (mounted && picked != null && side == _batSide && _canRecord) {
      setState(() => _strikerPick = picked);
    }
  }

  Future<void> _pickNonStriker() async {
    if (!_canRecord) return;
    final side = _batSide;
    final picked = await pickScoringName(
      context,
      title: 'Select non-striker',
      names: _availableBatters(exclude: _striker),
    );
    if (mounted && picked != null && side == _batSide && _canRecord) {
      setState(() => _nonStrikerPick = picked);
    }
  }

  Future<void> _pickBowler() async {
    if (!_canRecord) return;
    final side = _batSide;
    final picked = await pickScoringName(
      context,
      title: 'Select bowler',
      names: _namesOn(_bowlingSide),
      hint: widget.match.sideNames[_bowlingSide],
    );
    if (mounted && picked != null && side == _batSide && _canRecord) {
      setState(() => _bowlerPick = picked);
    }
  }

  void _swapStrike() {
    if (!_canRecord) return;
    final striker = _striker;
    final nonStriker = _nonStriker;
    if (striker == null || nonStriker == null) return;
    setState(() {
      _strikerPick = nonStriker;
      _nonStrikerPick = striker;
    });
    HapticFeedback.selectionClick();
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _ball(Map<String, dynamic> data) {
    if (!_canRecord) {
      _message('This innings is not open for scoring.');
      return;
    }
    final striker = _striker;
    final nonStriker = _nonStriker;
    final bowler = _bowler;
    if (striker == null || nonStriker == null || bowler == null) {
      _message('Select both batters and the bowler first.');
      return;
    }
    if (striker == nonStriker) {
      _message('Striker and non-striker must be different.');
      return;
    }
    setState(() => _recording = true);
    _syncController();
    try {
      widget.onRecord(CricketEngine.kBall, _batSide, {
        ...data,
        'striker': striker,
        'nonStriker': nonStriker,
        'bowler': bowler,
        if (data['wicket'] == true)
          'dismissedBatter': data['dismissedBatter'] ?? striker,
      });
      HapticFeedback.selectionClick();
      // Clear manual selections only after the shell accepts the event.
      // The next authoritative projection is provided by CricketRoster.
      if (mounted) setState(_clearPicks);
    } catch (_) {
      _message('Could not record delivery. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _recording = false);
        _syncController();
      }
    }
  }

  Future<void> _extra(String type) async {
    if (!_canRecord) return;
    final side = _batSide;
    final title = switch (type) {
      'wide' => 'Wide delivery',
      'noball' => 'No-ball delivery',
      'bye' => 'Byes',
      _ => 'Leg byes',
    };
    final runs = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SportikaColors.surfaceElevated,
      builder: (ctx) => AppSheet(
        title: title,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              type == 'noball' ? 'Runs off the bat' : 'Additional runs',
              style: SportikaType.bodyStrong,
            ),
            const SizedBox(height: SportikaSpacing.md),
            Wrap(
              spacing: SportikaSpacing.sm,
              runSpacing: SportikaSpacing.sm,
              children: [
                for (var n = 0; n <= 6; n++)
                  ActionChip(
                    label: Text('$n'),
                    onPressed: () => Navigator.pop(ctx, n),
                  ),
              ],
            ),
            const SizedBox(height: SportikaSpacing.sm),
            const HelperText(
              'Penalty runs are applied by the existing scoring engine.',
            ),
          ],
        ),
      ),
    );
    if (!mounted || runs == null || side != _batSide || !_canRecord) return;
    _ball({'runs': runs, 'extra': type});
  }

  Future<void> _wicket() async {
    if (!_canRecord) return;
    final side = _batSide;
    final striker = _striker;
    final nonStriker = _nonStriker;
    if (striker == null || nonStriker == null) {
      _message('Select both batters before recording a wicket.');
      return;
    }
    final outcome = await showModalBottomSheet<CricketWicketResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SportikaColors.surfaceElevated,
      builder: (_) =>
          CricketWicketSheet(striker: striker, nonStriker: nonStriker),
    );
    if (!mounted || outcome == null || side != _batSide || !_canRecord) return;
    _ball({
      'runs': outcome.runs,
      if (outcome.extra != null) 'extra': outcome.extra,
      'wicket': true,
      'dismissal': outcome.dismissal,
      'dismissedBatter': outcome.dismissed,
    });
  }

  void _startInnings() {
    if (_open || _complete) return;
    final side = (widget.progress.state['nextBatSide'] as num?)?.toInt();
    if (side != 0 && side != 1) return;
    try {
      widget.onRecord(CricketEngine.kInningsStart, side!, const {});
      setState(_clearPicks);
    } catch (_) {
      _message('Could not start the next innings.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final deliveries = CricketInningsReport.deliveries(widget.match, _batSide);
    final legal = deliveries.where(CricketInningsReport.legal).length;
    final runs = deliveries.fold<int>(
      0,
      (sum, e) => sum + CricketInningsReport.total(e),
    );
    final wickets = deliveries.where((e) => e.data['wicket'] == true).length;
    final oversLimit =
        (widget.match.rules['oversPerInnings'] as num?)?.toInt() ?? 10;
    final remaining = (oversLimit * 6 - legal).clamp(0, oversLimit * 6);
    final target = (widget.progress.state['target'] as num?)?.toInt();
    final chase = _innings >= 2 && target != null;
    final runsNeeded = chase ? (target - runs).clamp(0, target) : null;
    final crr = legal == 0 ? null : runs * 6 / legal;
    final rrr = chase && remaining > 0 ? runsNeeded! * 6 / remaining : null;
    final toss = _toss;
    final tossWinner = (toss?['winner'] as num?)?.toInt();
    final nextSide = (widget.progress.state['nextBatSide'] as num?)?.toInt();
    final batters = _batters();
    final bowlers = _bowlers();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CricketScoreHero(
          team: widget.match.sideNames[_batSide],
          opponent: widget.match.sideNames[_bowlingSide],
          innings: _innings,
          runs: runs,
          wickets: wickets,
          legalBalls: legal,
          oversLimit: oversLimit,
          runRate: crr,
          target: chase ? target : null,
          requiredRate: rrr,
          runsNeeded: runsNeeded,
          ballsRemaining: remaining,
          accent: widget.accent,
          isLive: _open && !_complete,
          isComplete: _complete,
        ),
        if (toss != null && (tossWinner == 0 || tossWinner == 1)) ...[
          const SizedBox(height: SportikaSpacing.sm),
          InfoBanner(
            icon: Icons.sports_cricket,
            text:
                '${widget.match.sideNames[tossWinner!]} won the toss and elected to '
                '${toss['decision'] == 'bowl' ? 'bowl' : 'bat'}.',
            tone: widget.accent,
          ),
        ],
        if (!_open &&
            !_complete &&
            _innings == 1 &&
            (nextSide == 0 || nextSide == 1)) ...[
          const SizedBox(height: SportikaSpacing.sm),
          PrimaryButton(
            label: 'Open second innings',
            icon: Icons.play_arrow_rounded,
            onPressed: _startInnings,
          ),
        ],
        const SizedBox(height: SportikaSpacing.sm),
        CricketMatchSituation(
          innings: _innings,
          isOpen: _open,
          isComplete: _complete,
          target: chase ? target : null,
          runsNeeded: runsNeeded,
          ballsRemaining: chase ? remaining : null,
          accent: widget.accent,
        ),
        const SizedBox(height: SportikaSpacing.sm),
        CricketCreasePanel(
          striker: _striker,
          nonStriker: _nonStriker,
          bowler: _bowler,
          batters: batters,
          bowlers: bowlers,
          accent: widget.accent,
          enabled: _canRecord,
          onStrikerTap: _pickStriker,
          onNonStrikerTap: _pickNonStriker,
          onBowlerTap: _pickBowler,
          onSwapStrike: _swapStrike,
        ),
        const SizedBox(height: SportikaSpacing.sm),
        CricketOverRibbon(
          deliveries: deliveries,
          legalBalls: legal,
          accent: widget.accent,
        ),
        if (widget.showInlineDeliveryPad) ...[
          const SizedBox(height: SportikaSpacing.md),
          CricketDeliveryPad(
            accent: widget.accent,
            enabled: _canRecord,
            onRuns: (value) => _ball({'runs': value, 'dot': value == 0}),
            onExtra: _extra,
            onWicket: _wicket,
          ),
        ],
        const SizedBox(height: SportikaSpacing.md),
        CricketMiniScorecard(
          batters: batters,
          bowlers: bowlers,
          striker: _striker,
          nonStriker: _nonStriker,
          currentBowler: _bowler,
          accent: widget.accent,
        ),
        const SizedBox(height: SportikaSpacing.md),
      ],
    );
  }

  List<CricketBatterLine> _batters() {
    final rows = <String, CricketBatterLine>{};
    for (final event in _balls) {
      final name = (event.data['striker'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      final row = rows.putIfAbsent(name, () => CricketBatterLine(name));
      final runs = (event.data['runs'] as num?)?.toInt() ?? 0;
      final extra = event.data['extra'] as String?;
      if (extra == null || extra == 'noball') row.runs += runs;
      if (extra != 'wide' && extra != 'noball') row.balls++;
      if ((extra == null || extra == 'noball') && runs == 4) row.fours++;
      if ((extra == null || extra == 'noball') && runs == 6) row.sixes++;
      if (event.data['wicket'] == true) {
        final dismissed = (event.data['dismissedBatter'] as String?) ?? name;
        final out = rows.putIfAbsent(
          dismissed,
          () => CricketBatterLine(dismissed),
        );
        out.out = true;
        out.howOut = event.data['dismissal'] as String?;
      }
    }
    return rows.values.toList();
  }

  List<CricketBowlerLine> _bowlers() {
    final rows = <String, CricketBowlerLine>{};
    for (final event in _balls) {
      final name = (event.data['bowler'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      final row = rows.putIfAbsent(name, () => CricketBowlerLine(name));
      final runs = (event.data['runs'] as num?)?.toInt() ?? 0;
      final extra = event.data['extra'] as String?;
      if (extra == 'wide' || extra == 'noball') {
        row.runs += 1 + runs;
      } else if (extra == null) {
        row.runs += runs;
      }
      if (CricketInningsReport.legal(event)) row.balls++;
      if (event.data['wicket'] == true &&
          const {
            'Bowled',
            'Caught',
            'LBW',
            'Stumped',
            'Caught & bowled',
            'Hit wicket',
          }.contains(event.data['dismissal'])) {
        row.wickets++;
      }
    }
    return rows.values.toList();
  }
}

class CricketScoreHero extends StatelessWidget {
  const CricketScoreHero({
    super.key,
    required this.team,
    required this.innings,
    required this.runs,
    required this.wickets,
    required this.legalBalls,
    required this.oversLimit,
    required this.runRate,
    required this.accent,
    required this.isLive,
    this.opponent,
    this.isComplete = false,
    this.target,
    this.requiredRate,
    this.runsNeeded,
    this.ballsRemaining,
  });

  final String team;
  final String? opponent;
  final int innings, runs, wickets, legalBalls, oversLimit;
  final double? runRate, requiredRate;
  final int? target, runsNeeded, ballsRemaining;
  final Color accent;
  final bool isLive, isComplete;

  @override
  Widget build(BuildContext context) {
    final overs = '${legalBalls ~/ 6}.${legalBalls % 6}';
    return Container(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      decoration: BoxDecoration(
        color: SportikaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(SportikaRadius.xl),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.sports_cricket, color: accent),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: Text(
                  'SPORTIKA / CRICKET',
                  style: SportikaType.micro.copyWith(color: accent),
                ),
              ),
              StatusPill(
                isComplete
                    ? 'FINAL'
                    : isLive
                    ? 'LIVE'
                    : 'PRE-MATCH',
                color: isLive ? SportikaColors.mint : SportikaColors.textMuted,
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.lg),
          Text(
            team,
            style: SportikaType.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (opponent != null)
            Text(
              'vs $opponent',
              style: SportikaType.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: SportikaSpacing.xs),
          Text(
            innings == 0 ? 'INNINGS NOT STARTED' : 'INNINGS $innings',
            style: SportikaType.micro,
          ),
          const SizedBox(height: SportikaSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Text(
                      '$runs/$wickets',
                      key: ValueKey('$runs/$wickets'),
                      style: SportikaType.title.copyWith(
                        color: SportikaColors.text,
                        fontSize: (SportikaType.title.fontSize ?? 28) * 1.8,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: SportikaSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$overs / $oversLimit', style: SportikaType.titleMedium),
                  const Text('OVERS', style: SportikaType.micro),
                ],
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.md),
          const Divider(),
          const SizedBox(height: SportikaSpacing.sm),
          Wrap(
            spacing: SportikaSpacing.lg,
            runSpacing: SportikaSpacing.md,
            children: [
              _HeroMetric(
                label: 'CURRENT RATE',
                value: runRate?.toStringAsFixed(2) ?? '—',
              ),
              if (target != null)
                _HeroMetric(label: 'TARGET', value: '$target'),
              if (requiredRate != null)
                _HeroMetric(
                  label: 'REQUIRED RATE',
                  value: requiredRate!.toStringAsFixed(2),
                ),
            ],
          ),
          if (target != null &&
              runsNeeded != null &&
              ballsRemaining != null) ...[
            const SizedBox(height: SportikaSpacing.md),
            InfoBanner(
              icon: Icons.flag_outlined,
              text: runsNeeded == 0
                  ? 'Target reached'
                  : 'Need $runsNeeded runs from $ballsRemaining balls',
              tone: accent,
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: SportikaType.micro),
      const SizedBox(height: SportikaSpacing.xs),
      Text(value, style: SportikaType.titleMedium),
    ],
  );
}

class CricketMatchSituation extends StatelessWidget {
  const CricketMatchSituation({
    super.key,
    required this.innings,
    required this.isOpen,
    required this.isComplete,
    required this.accent,
    this.target,
    this.runsNeeded,
    this.ballsRemaining,
  });

  final int innings;
  final bool isOpen, isComplete;
  final Color accent;
  final int? target, runsNeeded, ballsRemaining;

  @override
  Widget build(BuildContext context) {
    String? message;
    var icon = Icons.info_outline_rounded;
    if (isComplete) {
      message = 'Match completed. View the official result in Match Center.';
      icon = Icons.emoji_events_outlined;
    } else if (!isOpen && innings == 1) {
      message = 'Innings break. Start the second innings when ready.';
      icon = Icons.pause_circle_outline_rounded;
    } else if (!isOpen && innings == 0) {
      message = 'Waiting for the first innings to start.';
    } else if (target != null && runsNeeded != null && ballsRemaining != null) {
      message = runsNeeded == 0
          ? 'Target reached'
          : 'Chasing $target: $runsNeeded needed from $ballsRemaining balls';
      icon = Icons.flag_outlined;
    }
    if (message == null) return const SizedBox.shrink();
    return InfoBanner(icon: icon, text: message, tone: accent);
  }
}

class CricketCreasePanel extends StatelessWidget {
  const CricketCreasePanel({
    super.key,
    required this.striker,
    required this.nonStriker,
    required this.bowler,
    required this.batters,
    required this.bowlers,
    required this.accent,
    required this.onStrikerTap,
    required this.onNonStrikerTap,
    required this.onBowlerTap,
    this.onSwapStrike,
    this.enabled = true,
  });

  final String? striker, nonStriker, bowler;
  final List<CricketBatterLine> batters;
  final List<CricketBowlerLine> bowlers;
  final Color accent;
  final VoidCallback onStrikerTap, onNonStrikerTap, onBowlerTap;
  final VoidCallback? onSwapStrike;
  final bool enabled;

  CricketBatterLine? _batter(String? name) {
    for (final row in batters) {
      if (row.name == name) return row;
    }
    return null;
  }

  CricketBowlerLine? _bowler(String? name) {
    for (final row in bowlers) {
      if (row.name == name) return row;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final activeBowler = _bowler(bowler);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('AT THE CREASE', style: SportikaType.bodyStrong),
              ),
              if (enabled &&
                  striker != null &&
                  nonStriker != null &&
                  onSwapStrike != null)
                IconButton(
                  tooltip: 'Swap striker and non-striker',
                  onPressed: onSwapStrike,
                  icon: Icon(Icons.swap_vert_rounded, color: accent),
                ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.sm),
          _CreasePerson(
            label: 'STRIKER',
            name: striker,
            batter: _batter(striker),
            accent: accent,
            highlighted: true,
            onTap: enabled ? onStrikerTap : null,
          ),
          const SizedBox(height: SportikaSpacing.sm),
          _CreasePerson(
            label: 'NON-STRIKER',
            name: nonStriker,
            batter: _batter(nonStriker),
            accent: SportikaColors.textMuted,
            highlighted: false,
            onTap: enabled ? onNonStrikerTap : null,
          ),
          const SizedBox(height: SportikaSpacing.sm),
          const Divider(),
          InkWell(
            onTap: enabled ? onBowlerTap : null,
            borderRadius: BorderRadius.circular(SportikaRadius.control),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: SportikaSpacing.sm),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: SportikaColors.surfaceAlt,
                    child: Icon(
                      Icons.sports_cricket,
                      color: SportikaColors.mint,
                    ),
                  ),
                  const SizedBox(width: SportikaSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('CURRENT BOWLER', style: SportikaType.micro),
                        Text(
                          bowler ?? 'Select bowler',
                          style: SportikaType.bodyStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (activeBowler != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${activeBowler.overs} - ${activeBowler.runs} - '
                          '${activeBowler.wickets}',
                          style: SportikaType.bodyStrong,
                        ),
                        const Text('O - R - W', style: SportikaType.micro),
                      ],
                    ),
                  const SizedBox(width: SportikaSpacing.xs),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: SportikaColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreasePerson extends StatelessWidget {
  const _CreasePerson({
    required this.label,
    required this.name,
    required this.batter,
    required this.accent,
    required this.highlighted,
    required this.onTap,
  });

  final String label;
  final String? name;
  final CricketBatterLine? batter;
  final Color accent;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(SportikaRadius.control),
    child: Container(
      padding: const EdgeInsets.all(SportikaSpacing.sm),
      decoration: BoxDecoration(
        color: SportikaColors.surfaceAlt,
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        border: Border.all(
          color: highlighted
              ? accent.withValues(alpha: 0.45)
              : SportikaColors.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          const BrandedDefaultAvatar(size: 40),
          const SizedBox(width: SportikaSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: SportikaType.micro.copyWith(color: accent)),
                Text(
                  name ?? 'Select batter',
                  style: SportikaType.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (batter != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${batter!.runs} (${batter!.balls})',
                  style: SportikaType.bodyStrong,
                ),
                Text(
                  '${batter!.fours} fours · ${batter!.sixes} sixes',
                  style: SportikaType.micro,
                ),
              ],
            ),
          const SizedBox(width: SportikaSpacing.xs),
          const Icon(
            Icons.chevron_right_rounded,
            color: SportikaColors.textMuted,
          ),
        ],
      ),
    ),
  );
}

/// Over boundary is assigned BEFORE each event. An illegal ball after six
/// legal balls therefore belongs to the next over, not the completed one.
class CricketOverRibbon extends StatelessWidget {
  const CricketOverRibbon({
    super.key,
    required this.deliveries,
    required this.legalBalls,
    required this.accent,
  });

  final List<MatchEvent> deliveries;
  final int legalBalls;
  final Color accent;

  String _label(MatchEvent event) {
    final runs = (event.data['runs'] as num?)?.toInt() ?? 0;
    final extra = event.data['extra'] as String?;
    final label = switch (extra) {
      'wide' => 'WD${runs == 0 ? '' : runs}',
      'noball' => 'NB${runs == 0 ? '' : runs}',
      'bye' => 'B$runs',
      'legbye' => 'LB$runs',
      _ => '$runs',
    };
    return event.data['wicket'] == true ? 'W · $label' : label;
  }

  Color _tone(MatchEvent event) {
    if (event.data['wicket'] == true) return SportikaColors.danger;
    if (event.data['extra'] == 'wide' || event.data['extra'] == 'noball') {
      return SportikaColors.gold;
    }
    final runs = (event.data['runs'] as num?)?.toInt() ?? 0;
    return runs == 4 || runs == 6 ? accent : SportikaColors.text;
  }

  @override
  Widget build(BuildContext context) {
    final overs = <List<MatchEvent>>[<MatchEvent>[]];
    var legalCount = 0;
    for (final event in deliveries) {
      if (legalCount ~/ 6 >= overs.length) {
        overs.add(<MatchEvent>[]);
      }
      overs.last.add(event);
      if (CricketInningsReport.legal(event)) legalCount++;
    }
    final current = overs.last;
    final number = overs.length;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('THIS OVER', style: SportikaType.bodyStrong),
              ),
              Text('OVER $number', style: SportikaType.micro),
            ],
          ),
          const SizedBox(height: SportikaSpacing.md),
          if (current.isEmpty)
            const HelperText('No deliveries recorded yet.')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final delivery in current)
                    Padding(
                      padding: const EdgeInsets.only(right: SportikaSpacing.sm),
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                          horizontal: SportikaSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: SportikaColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(
                            SportikaRadius.control,
                          ),
                          border: Border.all(
                            color: _tone(delivery).withValues(alpha: 0.45),
                          ),
                        ),
                        child: Text(
                          _label(delivery),
                          style: SportikaType.bodyStrong.copyWith(
                            color: _tone(delivery),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class CricketDeliveryPad extends StatelessWidget {
  const CricketDeliveryPad({
    super.key,
    required this.accent,
    required this.enabled,
    required this.onRuns,
    required this.onExtra,
    required this.onWicket,
    this.compact = false,
  });

  final Color accent;
  final bool enabled;
  final ValueChanged<int> onRuns;
  final ValueChanged<String> onExtra;
  final VoidCallback onWicket;
  final bool compact;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('RECORD DELIVERY', style: SportikaType.bodyStrong),
            ),
            StatusPill(
              enabled ? 'READY' : 'LOCKED',
              color: enabled ? SportikaColors.mint : SportikaColors.textMuted,
            ),
          ],
        ),
        const SizedBox(height: SportikaSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = SportikaSpacing.sm;
            final width = (constraints.maxWidth - spacing * 2) / 3;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final runs in [0, 1, 2, 3, 4, 6])
                  SizedBox(
                    width: width,
                    child: ScoringPad(
                      label: '$runs',
                      big: true,
                      tone: runs == 4 || runs == 6
                          ? accent
                          : SportikaColors.surfaceAlt,
                      onTap: enabled ? () => onRuns(runs) : null,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: SportikaSpacing.md),
        Wrap(
          spacing: SportikaSpacing.sm,
          runSpacing: SportikaSpacing.sm,
          children: [
            ScoringPad(
              label: 'Wide',
              tone: SportikaColors.gold,
              onTap: enabled ? () => onExtra('wide') : null,
            ),
            ScoringPad(
              label: 'No ball',
              tone: SportikaColors.gold,
              onTap: enabled ? () => onExtra('noball') : null,
            ),
            ScoringPad(
              label: 'Bye',
              onTap: enabled ? () => onExtra('bye') : null,
            ),
            ScoringPad(
              label: 'Leg bye',
              onTap: enabled ? () => onExtra('legbye') : null,
            ),
          ],
        ),
        const SizedBox(height: SportikaSpacing.md),
        ScoringPad(
          label: 'WICKET',
          icon: Icons.sports_cricket,
          wide: true,
          tone: SportikaColors.danger,
          onTap: enabled ? onWicket : null,
        ),
        if (!compact) ...[
          const SizedBox(height: SportikaSpacing.sm),
          const HelperText(
            'Undo and close-innings actions remain in the match shell.',
          ),
        ],
      ],
    ),
  );
}

/// Result of the guided wicket entry. Keeps the existing engine event schema.
class CricketWicketResult {
  const CricketWicketResult({
    required this.dismissal,
    required this.dismissed,
    required this.extra,
    required this.runs,
  });

  final String dismissal, dismissed;
  final String? extra;
  final int runs;
}

class CricketWicketSheet extends StatefulWidget {
  const CricketWicketSheet({
    super.key,
    required this.striker,
    required this.nonStriker,
  });

  final String? striker, nonStriker;

  @override
  State<CricketWicketSheet> createState() => _CricketWicketSheetState();
}

class _CricketWicketSheetState extends State<CricketWicketSheet> {
  static const _dismissals = [
    'Bowled',
    'Caught',
    'LBW',
    'Run out',
    'Stumped',
    'Caught & bowled',
    'Hit wicket',
  ];

  String? _dismissal;
  String? _dismissed;
  String _delivery = 'legal';
  int _runs = 0;

  bool _allowed(String dismissal, String delivery) {
    if (delivery == 'legal') return true;
    if (delivery == 'wide') {
      return dismissal == 'Run out' || dismissal == 'Stumped';
    }
    return dismissal == 'Run out';
  }

  @override
  Widget build(BuildContext context) {
    final dismissed = _dismissal == 'Run out' ? _dismissed : widget.striker;
    final valid =
        _dismissal != null &&
        dismissed != null &&
        _allowed(_dismissal!, _delivery);

    return AppSheet(
      title: 'Record wicket',
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('1. Dismissal type', style: SportikaType.bodyStrong),
            const SizedBox(height: SportikaSpacing.sm),
            Wrap(
              spacing: SportikaSpacing.sm,
              runSpacing: SportikaSpacing.sm,
              children: [
                for (final value in _dismissals)
                  ChoiceChip(
                    label: Text(value),
                    selected: _dismissal == value,
                    onSelected: (_) => setState(() {
                      _dismissal = value;
                      _dismissed = value == 'Run out' ? null : widget.striker;
                      if (!_allowed(value, _delivery)) _delivery = 'legal';
                    }),
                  ),
              ],
            ),
            if (_dismissal != null) ...[
              const SizedBox(height: SportikaSpacing.md),
              const Text('2. Dismissed batter', style: SportikaType.bodyStrong),
              const SizedBox(height: SportikaSpacing.sm),
              if (_dismissal == 'Run out')
                Wrap(
                  spacing: SportikaSpacing.sm,
                  runSpacing: SportikaSpacing.sm,
                  children: [
                    for (final name in {widget.striker, widget.nonStriker})
                      if (name != null)
                        ChoiceChip(
                          label: Text(name),
                          selected: _dismissed == name,
                          onSelected: (_) => setState(() => _dismissed = name),
                        ),
                  ],
                )
              else
                Text(
                  widget.striker ?? 'Select the striker first',
                  style: SportikaType.bodyStrong,
                ),
              const SizedBox(height: SportikaSpacing.md),
              const Text('3. Delivery type', style: SportikaType.bodyStrong),
              const SizedBox(height: SportikaSpacing.sm),
              Wrap(
                spacing: SportikaSpacing.sm,
                runSpacing: SportikaSpacing.sm,
                children: [
                  for (final option in const [
                    ('legal', 'Legal'),
                    ('wide', 'Wide'),
                    ('noball', 'No ball'),
                  ])
                    ChoiceChip(
                      label: Text(option.$2),
                      selected: _delivery == option.$1,
                      onSelected: _allowed(_dismissal!, option.$1)
                          ? (_) => setState(() => _delivery = option.$1)
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: SportikaSpacing.md),
              const Text('4. Runs completed', style: SportikaType.bodyStrong),
              const SizedBox(height: SportikaSpacing.sm),
              Wrap(
                spacing: SportikaSpacing.sm,
                runSpacing: SportikaSpacing.sm,
                children: [
                  for (var n = 0; n <= 6; n++)
                    ChoiceChip(
                      label: Text('$n'),
                      selected: _runs == n,
                      onSelected: (_) => setState(() => _runs = n),
                    ),
                ],
              ),
              const SizedBox(height: SportikaSpacing.md),
              Text(
                'Confirm: $_dismissal · ${dismissed ?? 'Choose batter'} · '
                '$_runs runs',
                style: SportikaType.caption,
              ),
              const SizedBox(height: SportikaSpacing.sm),
              PrimaryButton(
                label: 'Record wicket',
                tone: SportikaColors.danger,
                onPressed: () {
                  if (!valid) return;
                  Navigator.pop(
                    context,
                    CricketWicketResult(
                      dismissal: _dismissal!,
                      dismissed: dismissed,
                      extra: _delivery == 'legal' ? null : _delivery,
                      runs: _runs,
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class CricketMiniScorecard extends StatefulWidget {
  const CricketMiniScorecard({
    super.key,
    required this.batters,
    required this.bowlers,
    required this.accent,
    this.striker,
    this.nonStriker,
    this.currentBowler,
  });

  final List<CricketBatterLine> batters;
  final List<CricketBowlerLine> bowlers;
  final Color accent;
  final String? striker, nonStriker, currentBowler;

  @override
  State<CricketMiniScorecard> createState() => _CricketMiniScorecardState();
}

class _CricketMiniScorecardState extends State<CricketMiniScorecard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final batting = [...widget.batters]
      ..sort((a, b) {
        int rank(CricketBatterLine line) {
          if (line.name == widget.striker) return 0;
          if (line.name == widget.nonStriker) return 1;
          return 2;
        }

        return rank(a).compareTo(rank(b));
      });
    final bowling = [...widget.bowlers]
      ..sort((a, b) {
        if (a.name == widget.currentBowler) return -1;
        if (b.name == widget.currentBowler) return 1;
        return 0;
      });
    final shownBatters = _expanded ? batting : batting.take(2);
    final shownBowlers = _expanded ? bowling : bowling.take(1);

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'MATCH SCORECARD',
                    style: SportikaType.bodyStrong,
                  ),
                ),
                Text(
                  _expanded ? 'COLLAPSE' : 'EXPAND',
                  style: SportikaType.micro,
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: SportikaColors.textMuted,
                ),
              ],
            ),
          ),
          const SizedBox(height: SportikaSpacing.md),
          const Text('BATTING', style: SportikaType.micro),
          const SizedBox(height: SportikaSpacing.sm),
          const _ScorecardHeader(
            first: 'BATTER',
            columns: ['R', 'B', '4s', '6s'],
          ),
          const Divider(),
          if (batting.isEmpty)
            const HelperText(
              'Batting statistics appear after the first delivery.',
            )
          else
            for (final batter in shownBatters)
              _BatterScoreRow(batter: batter, accent: widget.accent),
          const SizedBox(height: SportikaSpacing.lg),
          const Text('BOWLING', style: SportikaType.micro),
          const SizedBox(height: SportikaSpacing.sm),
          const _ScorecardHeader(first: 'BOWLER', columns: ['O', 'R', 'W']),
          const Divider(),
          if (bowling.isEmpty)
            const HelperText(
              'Bowling statistics appear after the first delivery.',
            )
          else
            for (final bowler in shownBowlers)
              _BowlerScoreRow(bowler: bowler, accent: SportikaColors.mint),
        ],
      ),
    );
  }
}

class _ScorecardHeader extends StatelessWidget {
  const _ScorecardHeader({required this.first, required this.columns});
  final String first;
  final List<String> columns;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(flex: 4, child: Text(first, style: SportikaType.micro)),
      for (final column in columns)
        Expanded(
          child: Text(
            column,
            textAlign: TextAlign.end,
            style: SportikaType.micro,
          ),
        ),
    ],
  );
}

class _BatterScoreRow extends StatelessWidget {
  const _BatterScoreRow({required this.batter, required this.accent});
  final CricketBatterLine batter;
  final Color accent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: SportikaSpacing.sm),
    child: Row(
      children: [
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                batter.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SportikaType.bodyStrong,
              ),
              Text(
                batter.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SportikaType.micro,
              ),
            ],
          ),
        ),
        _StatCell('${batter.runs}', accent: accent),
        _StatCell('${batter.balls}'),
        _StatCell('${batter.fours}'),
        _StatCell('${batter.sixes}'),
      ],
    ),
  );
}

class _BowlerScoreRow extends StatelessWidget {
  const _BowlerScoreRow({required this.bowler, required this.accent});
  final CricketBowlerLine bowler;
  final Color accent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: SportikaSpacing.sm),
    child: Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(
            bowler.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SportikaType.bodyStrong,
          ),
        ),
        _StatCell(bowler.overs),
        _StatCell('${bowler.runs}'),
        _StatCell('${bowler.wickets}', accent: accent),
      ],
    ),
  );
}

class _StatCell extends StatelessWidget {
  const _StatCell(this.value, {this.accent});
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Text(
      value,
      textAlign: TextAlign.end,
      style: SportikaType.bodyStrong.copyWith(
        color: accent ?? SportikaColors.text,
      ),
    ),
  );
}

class CricketBatterLine {
  CricketBatterLine(this.name);
  final String name;
  int runs = 0, balls = 0, fours = 0, sixes = 0;
  bool out = false;
  String? howOut;
  String get label => out ? (howOut ?? 'Out') : 'Not out';
  double get strikeRate => balls == 0 ? 0 : runs * 100 / balls;
}

class CricketBowlerLine {
  CricketBowlerLine(this.name);
  final String name;
  int balls = 0, runs = 0, wickets = 0;
  String get overs => '${balls ~/ 6}.${balls % 6}';
  double get economy => balls == 0 ? 0 : runs * 6 / balls;
}
