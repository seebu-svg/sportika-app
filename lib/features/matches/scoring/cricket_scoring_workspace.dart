import 'package:sportika/features/matches/widgets/cricket_match_report.dart';
import 'package:flutter/material.dart';

import 'package:sportika/features/matches/scoring/match_scoring_shell.dart';
import 'package:sportika/features/matches/scoring/match_scoring_validator.dart';
import 'package:sportika/features/personal_games/scoring/cricket/cricket.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Cricket: runs off the bat, the four extras, wickets with a dismissal, the
/// over ribbon, and batting/bowling cards.
///
/// The run pad writes one `ball` event per delivery; the score above the pad is
/// folded from those events by [CricketEngine], so the card and the engine can
/// never disagree.
class CricketScoringWorkspace extends StatefulWidget {
  const CricketScoringWorkspace({
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
  State<CricketScoringWorkspace> createState() =>
      _CricketScoringWorkspaceState();
}

class _CricketScoringWorkspaceState extends State<CricketScoringWorkspace> {
  String? _striker;
  String? _nonStriker;
  int _seenSeq = -1;
  String? _bowler;
  int _firstBatSide = 0;

  /// Engine's open innings, or the side the scorer chose to bat first.
  ///
  /// Between innings the engine reports the side that has just batted, so the
  /// workspace flips it: the other side walks out to bat.
  int get _batSide {
    final fromEngine =
        (widget.progress.state['batSide'] as num?)?.toInt() ?? -1;
    if (fromEngine < 0) return _firstBatSide;
    final innings = (widget.progress.state['innings'] as num?)?.toInt() ?? 0;
    final open = widget.progress.actions.any((a) => a.id == 'end_innings');
    if (innings > 0 && !open && !widget.progress.isComplete) {
      return 1 - fromEngine;
    }
    return fromEngine;
  }

  bool get _inningsEmpty =>
      widget.progress.state['innings'] == null ||
      (widget.progress.state['innings'] as num?)?.toInt() == 0;

  List<MatchEvent> get _balls =>
      widget.match.events
          .where((e) => !e.voided && e.kind == CricketEngine.kBall)
          .toList()
        ..sort((a, b) => a.seq.compareTo(b.seq));

  @override
  void initState() {
    super.initState();
    // Carry the batter/bowler from the last delivery so a resumed match does
    // not ask again on the first build.
    _restorePlayers();
  }

  @override
  void didUpdateWidget(covariant CricketScoringWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    _restorePlayers();
  }

  void _restorePlayers() {
    final balls = _balls.where((e) => e.side == _batSide).toList();
    final last = balls.lastOrNull;
    final seq = widget.match.lastActiveEvent?.seq ?? -1;
    if (_seenSeq == seq) return;
    _seenSeq = seq;
    _striker = last?.data['striker'] as String?;
    _nonStriker = last?.data['nonStriker'] as String?;
    _bowler = last?.data['bowler'] as String?;
    if (last == null) return;
    final runs = (last.data['runs'] as num?)?.toInt() ?? 0;
    if (runs.isOdd) {
      final previous = _striker;
      _striker = _nonStriker;
      _nonStriker = previous;
    }
    if (last.data['wicket'] == true) {
      final dismissed = last.data['dismissedBatter'] ?? last.data['striker'];
      if (_striker == dismissed) _striker = null;
      if (_nonStriker == dismissed) _nonStriker = null;
    }
    final legal = balls
        .where((e) => e.data['extra'] != 'wide' && e.data['extra'] != 'noball')
        .length;
    if (last.data['extra'] != 'wide' &&
        last.data['extra'] != 'noball' &&
        legal > 0 &&
        legal % 6 == 0) {
      final previous = _striker;
      _striker = _nonStriker;
      _nonStriker = previous;
      _bowler = null;
    }
  }

  void _ball(Map<String, dynamic> data) {
    if (_striker == null || _nonStriker == null || _bowler == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select two batters and a bowler before recording a delivery.',
          ),
        ),
      );
      return;
    }
    widget.onRecord(CricketEngine.kBall, _batSide, {
      ...data,
      'striker': _striker,
      'nonStriker': _nonStriker,
      'bowler': _bowler,
      if (data['wicket'] == true)
        'dismissedBatter': data['dismissedBatter'] ?? _striker,
    });
  }

  Future<void> _extra(String type) async {
    final runs = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => AppSheet(
        title: type == 'noball'
            ? 'No ball + runs off the bat'
            : type == 'wide'
            ? 'Wide + additional runs'
            : 'Runs from ${type == 'bye' ? 'byes' : 'leg byes'}',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var n = type == 'bye' || type == 'legbye' ? 1 : 0; n <= 6; n++)
              ActionChip(
                label: Text('$n'),
                onPressed: () => Navigator.pop(ctx, n),
              ),
          ],
        ),
      ),
    );
    if (runs != null && mounted) _ball({'runs': runs, 'extra': type});
  }

  Future<void> _pickNonStriker() async {
    final picked = await pickScoringName(
      context,
      title: 'Non-striker',
      names: _namesOn(_batSide)
          .where(
            (n) =>
                n != _striker &&
                !_balls.any(
                  (e) =>
                      e.side == _batSide &&
                      e.data['wicket'] == true &&
                      (e.data['dismissedBatter'] ?? e.data['striker']) == n,
                ),
          )
          .toList(),
    );
    if (picked != null && mounted) setState(() => _nonStriker = picked);
  }

  List<String> _namesOn(int side) => [
    for (final p in widget.match.participantsOnSide(side)) p.displayName,
  ];

  Future<void> _pickStriker() async {
    final names = _namesOn(_batSide)
        .where(
          (n) =>
              n != _nonStriker &&
              !_balls.any(
                (e) =>
                    e.side == _batSide &&
                    e.data['wicket'] == true &&
                    (e.data['dismissedBatter'] ?? e.data['striker']) == n,
              ),
        )
        .toList();
    final picked = await pickScoringName(
      context,
      title: 'Who is on strike?',
      names: names,
      hint: 'Batters from ${widget.match.sideNames[_batSide]}.',
    );
    if (picked != null && mounted) setState(() => _striker = picked);
  }

  Future<void> _pickBowler() async {
    final names = _namesOn(1 - _batSide);
    final picked = await pickScoringName(
      context,
      title: 'Who is bowling?',
      names: names,
      hint: 'Bowlers from ${widget.match.sideNames[1 - _batSide]}.',
    );
    if (picked != null && mounted) setState(() => _bowler = picked);
  }

  Future<void> _wicket() async {
    const types = [
      'Bowled',
      'Caught',
      'LBW',
      'Run out',
      'Stumped',
      'Caught & bowled',
    ];
    final type = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: SportikaColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => AppSheet(
        title: 'How was the batter out?',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in types)
                  ChoiceChip(
                    label: Text(t),
                    selected: false,
                    onSelected: (_) => Navigator.pop(ctx, t),
                  ),
              ],
            ),
            const SizedBox(height: SportikaSpacing.md),
            const HelperText(
              'The dismissal is stored with the wicket, so the bowling card '
              'credits the bowler and the batter card shows how they went.',
            ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;
    var dismissed = _striker;
    if (type == 'Run out') {
      dismissed = await pickScoringName(
        context,
        title: 'Who was run out?',
        names: [?_striker, ?_nonStriker],
      );
      if (dismissed == null || !mounted) return;
    }
    _ball({
      'runs': 0,
      'wicket': true,
      'dismissal': type,
      'dismissedBatter': dismissed,
    });
  }

  @override
  Widget build(BuildContext context) {
    final over = widget.progress.contextChips.firstWhere(
      (c) => c.startsWith('This over') || c.startsWith('New over'),
      orElse: () => '',
    );
    final deliveries = CricketInningsReport.deliveries(widget.match, _batSide);
    final legal = deliveries.where(CricketInningsReport.legal).length;
    final total = deliveries.fold<int>(
      0,
      (n, e) => n + CricketInningsReport.total(e),
    );
    final target = (widget.progress.state['target'] as num?)?.toInt();
    final remaining =
        ((widget.match.rules['oversPerInnings'] as num?)?.toInt() ?? 10) * 6 -
        legal;
    final batters = _batters();
    final bowlers = _bowlers();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            Text(
              'CRR ${legal == 0 ? '—' : (total * 6 / legal).toStringAsFixed(2)}',
              style: SportikaType.bodyStrong,
            ),
            if (target != null &&
                (widget.progress.state['innings'] as num? ?? 0) >= 2) ...[
              Text('Target $target', style: SportikaType.bodyStrong),
              Text(
                'RRR ${remaining <= 0 ? '—' : ((target - total).clamp(0, target) * 6 / remaining).toStringAsFixed(2)}',
                style: SportikaType.bodyStrong,
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _PersonChip(
                      label: 'Striker',
                      value: _striker ?? 'Not set',
                      accent: widget.accent,
                      onTap: _pickStriker,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PersonChip(
                      label: 'Bowler',
                      value: _bowler ?? 'Not set',
                      accent: SportikaColors.mint,
                      onTap: _pickBowler,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _PersonChip(
                label: 'Non-striker',
                value: _nonStriker ?? 'Not set',
                accent: widget.accent,
                onTap: _pickNonStriker,
              ),
              if (_inningsEmpty) ...[
                const SizedBox(height: SportikaSpacing.sm),
                const Text('Who bats first?', style: SportikaType.label),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (var side = 0; side < 2; side++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: side == 0 ? 8 : 0),
                          child: ChoiceChip(
                            label: Text(
                              widget.match.sideNames[side],
                              overflow: TextOverflow.ellipsis,
                            ),
                            selected: _firstBatSide == side,
                            onSelected: (_) => setState(() {
                              _firstBatSide = side;
                              _striker = null;
                              _nonStriker = null;
                              _bowler = null;
                            }),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (over.isNotEmpty) ...[
                const SizedBox(height: SportikaSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: SportikaColors.surfaceSunken,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: SportikaColors.borderSubtle),
                  ),
                  child: Text(
                    over,
                    maxLines: 2,
                    style: SportikaType.caption.copyWith(
                      color: SportikaColors.textBody,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: SportikaSpacing.sm),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('Runs off the bat', padding: EdgeInsets.zero),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final runs in [0, 1, 2, 3, 4, 6])
                    SizedBox(
                      width: 62,
                      child: ScoringPad(
                        label: '$runs',
                        big: true,
                        tone: runs == 4 || runs == 6
                            ? widget.accent
                            : SportikaColors.surfaceAlt,
                        onTap: () => _ball({'runs': runs, 'dot': runs == 0}),
                      ),
                    ),
                ],
              ),
              const SectionTitle(
                'Extras',
                padding: EdgeInsets.only(top: 16, bottom: 8),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ScoringPad(
                    label: 'Wide',
                    tone: SportikaColors.gold,
                    onTap: () => _extra('wide'),
                  ),
                  ScoringPad(
                    label: 'No ball',
                    tone: SportikaColors.gold,
                    onTap: () => _extra('noball'),
                  ),
                  ScoringPad(label: 'Bye', onTap: () => _extra('bye')),
                  ScoringPad(label: 'Leg bye', onTap: () => _extra('legbye')),
                ],
              ),
              const SizedBox(height: SportikaSpacing.md),
              ScoringPad(
                label: 'Wicket',
                icon: Icons.sports_cricket,
                wide: true,
                tone: SportikaColors.danger,
                onTap: _wicket,
              ),
              const SizedBox(height: 6),
              const HelperText(
                'Close the innings from the bar below when the overs are done '
                'or the side is all out.',
              ),
            ],
          ),
        ),
        if (batters.isNotEmpty) ...[
          const SectionTitle('Batting'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final b in batters)
                  _BatterRow(line: b, accent: widget.accent),
              ],
            ),
          ),
        ],
        if (bowlers.isNotEmpty) ...[
          const SectionTitle('Bowling'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final b in bowlers)
                  _BowlerRow(line: b, accent: SportikaColors.mint),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Runs, balls faced, boundaries and dismissals per batter, folded from the
  /// delivery log for the match report.
  List<_BatterLine> _batters() {
    final rows = <String, _BatterLine>{};
    for (final e in _balls.where((e) => e.side == _batSide)) {
      final name = (e.data['striker'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      final row = rows.putIfAbsent(name, () => _BatterLine(name));
      final runs = (e.data['runs'] as num?)?.toInt() ?? 0;
      final extra = e.data['extra'] as String?;
      if (extra != 'wide' && extra != 'bye' && extra != 'legbye') {
        row.runs += runs;
      }
      if (extra == null || extra == 'bye' || extra == 'legbye') row.balls += 1;
      if ((extra == null || extra == 'noball') && runs == 4) row.fours += 1;
      if ((extra == null || extra == 'noball') && runs == 6) row.sixes += 1;
      if (e.data['wicket'] == true) {
        final dismissed = e.data['dismissedBatter'] as String? ?? name;
        final out = rows.putIfAbsent(dismissed, () => _BatterLine(dismissed));
        out.out = true;
        out.howOut = e.data['dismissal'] as String?;
      }
    }
    return rows.values.toList();
  }

  /// Balls, runs conceded and wickets per bowler.
  List<_BowlerLine> _bowlers() {
    final rows = <String, _BowlerLine>{};
    for (final e in _balls.where((e) => e.side == _batSide)) {
      final name = (e.data['bowler'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      final row = rows.putIfAbsent(name, () => _BowlerLine(name));
      final runs = (e.data['runs'] as num?)?.toInt() ?? 0;
      final extra = e.data['extra'] as String?;
      if (extra == 'wide' || extra == 'noball') {
        row.runs += 1 + runs;
      } else if (extra == null) {
        row.runs += runs;
        row.balls += 1;
      } else {
        row.balls += 1; // byes and leg byes are legal deliveries
      }
      if (e.data['wicket'] == true &&
          {
            'Bowled',
            'Caught',
            'LBW',
            'Stumped',
            'Caught & bowled',
            'Hit wicket',
          }.contains(e.data['dismissal'])) {
        row.wickets += 1;
      }
    }
    return rows.values.toList();
  }
}

class _BatterLine {
  _BatterLine(this.name);

  final String name;
  int runs = 0;
  int balls = 0;
  int fours = 0;
  int sixes = 0;
  bool out = false;
  String? howOut;

  String get label => out ? (howOut ?? 'Out') : 'Not out';
}

class _BowlerLine {
  _BowlerLine(this.name);

  final String name;
  int balls = 0;
  int runs = 0;
  int wickets = 0;

  String get overs => '${balls ~/ 6}.${balls % 6}';
}

class _BatterRow extends StatelessWidget {
  const _BatterRow({required this.line, required this.accent});

  final _BatterLine line;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.bodyStrong,
                ),
                Text(
                  line.label,
                  style: SportikaType.caption.copyWith(fontSize: 10.5),
                ),
              ],
            ),
          ),
          Text(
            '${line.runs} (${line.balls})',
            style: SportikaType.bodyStrong.copyWith(color: accent),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 54,
            child: Text(
              '${line.fours}×4  ${line.sixes}×6',
              textAlign: TextAlign.right,
              style: SportikaType.caption.copyWith(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _BowlerRow extends StatelessWidget {
  const _BowlerRow({required this.line, required this.accent});

  final _BowlerLine line;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.bodyStrong,
                ),
                Text(
                  '${line.overs} overs',
                  style: SportikaType.caption.copyWith(fontSize: 10.5),
                ),
              ],
            ),
          ),
          Text(
            '${line.runs} runs',
            style: SportikaType.caption.copyWith(
              color: SportikaColors.textMuted,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${line.wickets} w',
            style: SportikaType.bodyStrong.copyWith(color: accent),
          ),
        ],
      ),
    );
  }
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({
    required this.label,
    required this.value,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final String value;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: SportikaColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: SportikaType.micro.copyWith(color: accent, fontSize: 9),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SportikaType.bodyStrong.copyWith(fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
