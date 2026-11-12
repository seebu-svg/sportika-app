import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';

/// Limited-overs cricket scoring: runs, extras, wickets, legal deliveries,
/// overs, two innings, chase target and result (spec §3).
class CricketEngine implements SportEngine {
  static const String kBall = 'ball';
  static const String kInningsEnd = 'innings_end';

  @override
  Sport get sport => Sport.cricket;

  @override
  List<String> get formats => const [
    'T5 · 5 overs',
    'T10 · 10 overs',
    'T20 · 20 overs',
  ];

  @override
  Map<String, dynamic> rulesForFormat(String format) {
    final overs = format.contains('T5')
        ? 5
        : format.contains('T10')
        ? 10
        : 20;
    return {'oversPerInnings': overs, 'wicketsPerInnings': 10, 'innings': 2};
  }

  @override
  String describeRules(Map<String, dynamic> rules) =>
      '${rules['oversPerInnings'] ?? 10} overs per innings · 10 wickets';

  @override
  MatchProgress evaluate({
    required List<String> sides,
    required Map<String, dynamic> rules,
    required List<ScoringEvent> events,
  }) {
    final oversPerInnings = (rules['oversPerInnings'] as num?)?.toInt() ?? 10;
    final maxWickets = (rules['wicketsPerInnings'] as num?)?.toInt() ?? 10;
    final maxInnings = (rules['innings'] as num?)?.toInt() ?? 2;
    final perInningsBalls = oversPerInnings * 6;

    final innings = <_Innings>[];

    void close(_Innings inn, String reason) {
      if (!inn.closed) {
        inn.closed = true;
        inn.closeReason = reason;
      }
    }

    for (final e in events) {
      if (e.kind == kInningsEnd) {
        if (innings.isEmpty || innings.last.closed) {
          // Nothing to close: an explicit end before the first ball is ignored.
          continue;
        }
        close(innings.last, e.data['reason'] as String? ?? 'Innings closed');
        continue;
      }
      if (e.kind != kBall) continue;

      final side = e.side ?? 0;
      if (innings.isEmpty) {
        innings.add(_Innings(side, maxWickets, perInningsBalls));
      } else if (innings.last.closed) {
        if (innings.length >= maxInnings) continue;
        innings.add(_Innings(side, maxWickets, perInningsBalls));
      } else if (innings.last.batSide != side && innings.last.hasBall) {
        // Batting changed without closing: treat as the innings having ended.
        close(innings.last, 'Innings ended');
        if (innings.length >= maxInnings) continue;
        innings.add(_Innings(side, maxWickets, perInningsBalls));
      }

      final inn = innings.last;
      inn.batSide = side;
      inn.applyBall(e);

      final target = innings.length == 2 ? innings[0].runs + 1 : null;
      if (inn.legalBalls >= perInningsBalls) {
        close(inn, 'Overs complete');
      } else if (inn.wickets >= maxWickets) {
        close(inn, 'All out');
      } else if (target != null && inn.runs >= target) {
        close(inn, 'Target passed');
      }
    }

    final finished =
        innings.length >= maxInnings && innings.every((i) => i.closed);
    final current = innings.isNotEmpty && !innings.last.closed
        ? innings.last
        : null;
    final target = innings.isNotEmpty && innings[0].closed
        ? innings[0].runs + 1
        : null;

    var winnerIndex = -1;
    var resultLabel = '';
    if (finished) {
      final first = innings[0], second = innings[1];
      if (second.runs > first.runs) {
        winnerIndex = second.batSide;
        resultLabel =
            '${sides[winnerIndex]} won by ${maxWickets - second.wickets} wickets';
      } else if (second.runs < first.runs) {
        winnerIndex = first.batSide;
        resultLabel =
            '${sides[winnerIndex]} won by ${first.runs - second.runs} runs';
      } else {
        resultLabel = 'Match tied';
      }
    }

    final runsBySide = [0, 0];
    for (final i in innings) {
      runsBySide[i.batSide] += i.runs;
    }

    final lines = <ScoreLine>[];
    for (var s = 0; s < 2; s++) {
      final batted = innings.where((i) => i.batSide == s).toList();
      if (batted.isEmpty) {
        lines.add(
          ScoreLine(
            label: sides[s],
            value: '-',
            sub: innings.isEmpty ? 'Match not started' : 'Yet to bat',
          ),
        );
      } else {
        final inn = batted.last;
        lines.add(
          ScoreLine(
            label: sides[s],
            value: '${inn.runs}/${inn.wickets}',
            sub:
                '${_overs(inn.legalBalls)} ov${inn.closed ? ' · ${inn.closeReason}' : ''}',
            leading: identical(inn, current),
          ),
        );
      }
    }

    final chips = <String>[];
    if (innings.isNotEmpty) {
      chips.add('Innings ${innings.length}/$maxInnings');
      final shown = current ?? innings.last;
      chips.add('Over ${_overs(shown.legalBalls)}/$oversPerInnings');
      if (shown.thisOver.isNotEmpty) {
        chips.add('This over: ${shown.thisOver.join(' · ')}');
      } else {
        chips.add('New over');
      }
    }
    if (current != null &&
        current.batSide == innings.last.batSide &&
        target != null &&
        innings.length == 2) {
      final need = target - current.runs;
      final ballsLeft = perInningsBalls - current.legalBalls;
      if (need > 0) chips.add('Need $need off $ballsLeft');
    }

    final detail = <String>[];
    for (final i in innings) {
      detail.add(
        '${sides[i.batSide]}  ${i.runs}/${i.wickets}'
        '  (${_overs(i.legalBalls)})'
        '  ·  extras ${i.wides + i.noballs + i.byes + i.legByes}'
        '  ·  ${i.wickets}/$maxWickets wickets',
      );
    }

    return MatchProgress(
      sport: Sport.cricket,
      sides: sides,
      lines: lines,
      headline: finished
          ? resultLabel
          : innings.isEmpty
          ? 'Choose a scoring action to open the innings'
          : current == null
          ? 'Innings closed - start the next innings'
          : '${sides[current.batSide]} batting',
      statusLabel: finished
          ? 'Result'
          : innings.isEmpty
          ? 'Not started'
          : current == null
          ? 'Between innings'
          : 'Innings in progress',
      detailRows: detail,
      contextChips: chips,
      isComplete: finished,
      winnerIndex: winnerIndex,
      resultLabel: resultLabel,
      completionReason: finished ? 'Both innings complete' : '',
      scoreValues: runsBySide,
      scoreDisplay: lines.map((l) => l.value).toList(),
      actions: _actions(
        current: current,
        inningsCount: innings.length,
        maxInnings: maxInnings,
        perInningsBalls: perInningsBalls,
        finished: finished,
      ),
      state: {
        'innings': innings.length,
        'batSide':
            current?.batSide ?? (innings.isEmpty ? -1 : innings.last.batSide),
        'target': ?target,
      },
    );
  }

  String _overs(int balls) => '${balls ~/ 6}.${balls % 6}';

  List<ScoreAction> _actions({
    _Innings? current,
    required int inningsCount,
    required int maxInnings,
    required int perInningsBalls,
    required bool finished,
  }) {
    if (finished) return [];

    // While an innings is open the batting side is fixed; between innings the
    // scorecard asks who bats next.
    final battingKnown = current != null && current.hasBall;
    final batSide = current?.batSide;

    ScoringEvent build(
      String kind,
      Map<String, dynamic> data,
      int? side,
      String by,
    ) => ScoringEvent(
      id: '',
      kind: kind,
      side: side ?? 0,
      data: data,
      at: DateTime.now(),
      byAccountId: by,
    );

    ScoreAction ball(
      String label,
      Map<String, dynamic> data,
      ActionStyle style,
    ) => ScoreAction(
      id: label,
      label: label,
      style: style,
      pickSide: !battingKnown,
      build: (ctx) =>
          build(kBall, data, battingKnown ? batSide : ctx.side, ctx.by),
    );

    final list = <ScoreAction>[
      ball('0', {'runs': 0, 'dot': true}, ActionStyle.neutral),
      ball('1', {'runs': 1}, ActionStyle.neutral),
      ball('2', {'runs': 2}, ActionStyle.neutral),
      ball('3', {'runs': 3}, ActionStyle.neutral),
      ball('4', {'runs': 4}, ActionStyle.primary),
      ball('6', {'runs': 6}, ActionStyle.primary),
      ball('W', {'runs': 0, 'wicket': true}, ActionStyle.danger),
      ball('Wide', {'runs': 0, 'extra': 'wide'}, ActionStyle.highlight),
      ball('No ball', {'runs': 0, 'extra': 'noball'}, ActionStyle.highlight),
      ball('Bye', {'runs': 1, 'extra': 'bye'}, ActionStyle.subtle),
      ball('Leg bye', {'runs': 1, 'extra': 'legbye'}, ActionStyle.subtle),
    ];

    if (current != null) {
      final ballsLeft = perInningsBalls - current.legalBalls;
      list.add(
        ScoreAction(
          id: 'end_innings',
          label: inningsCount < maxInnings ? 'End innings' : 'End innings',
          hint: '$ballsLeft balls left',
          style: ActionStyle.subtle,
          build: (ctx) => ScoringEvent(
            id: '',
            kind: kInningsEnd,
            side: batSide,
            data: {'reason': 'Innings closed'},
            at: DateTime.now(),
            byAccountId: ctx.by,
          ),
        ),
      );
    }
    return list;
  }
}

/// Mutable per-innings tally built while folding the event log.
class _Innings {
  int batSide;
  final int maxWickets;
  final int maxBalls;

  int runs = 0;
  int wickets = 0;
  int legalBalls = 0;
  int wides = 0;
  int noballs = 0;
  int byes = 0;
  int legByes = 0;
  int batterRuns = 0;

  bool closed = false;
  String closeReason = '';
  final List<String> thisOver = [];

  _Innings(this.batSide, this.maxWickets, this.maxBalls);

  bool get hasBall =>
      legalBalls > 0 ||
      runs > 0 ||
      wickets > 0 ||
      wides > 0 ||
      noballs > 0 ||
      thisOver.isNotEmpty;

  void applyBall(ScoringEvent e) {
    final r = e.flag('runs');
    final extra = e.data['extra'] as String?;
    final isWicket = e.data['wicket'] == true;
    var ballLabel = '$r';

    switch (extra) {
      case 'wide':
        // A wide is not a legal delivery; the penalty plus any runs run go
        // to the batting team as wides.
        wides += 1 + r;
        runs += 1 + r;
        ballLabel = r == 0 ? 'Wd' : 'Wd+$r';
      case 'noball':
        noballs += 1;
        batterRuns += r;
        runs += 1 + r;
        ballLabel = r == 0 ? 'Nb' : 'Nb+$r';
      case 'bye':
        byes += r;
        runs += r;
        legalBalls++;
        ballLabel = 'B$r';
      case 'legbye':
        legByes += r;
        runs += r;
        legalBalls++;
        ballLabel = 'Lb$r';
      default:
        batterRuns += r;
        runs += r;
        legalBalls++;
    }

    if (isWicket) {
      wickets++;
      ballLabel = extra == 'wide'
          ? 'W + Wd'
          : extra == 'noball'
          ? 'W + Nb'
          : 'W';
    }

    if (extra == null || extra == 'bye' || extra == 'legbye') {
      // Legal delivery: it fills a slot of the current over.
      if (legalBalls % 6 == 0) {
        thisOver.clear();
      } else {
        thisOver.add(ballLabel);
      }
    } else {
      thisOver.add(ballLabel);
    }
  }
}
