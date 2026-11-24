import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';

/// Futsal scoring: goals by team and half, match clock controls, final score,
/// and an optional penalty shootout when a winner is required (spec §3).
class FutsalEngine implements SportEngine {
  static const String kGoal = 'goal';
  static const String kClock = 'clock';
  static const String kPenalty = 'penalty';

  @override
  Sport get sport => Sport.futsal;

  @override
  List<String> get formats => const [
    '2 × 15 min',
    '2 × 20 min',
    '2 × 20 min · knockout',
    '2 × 20 min · extra time & penalties',
  ];

  @override
  Map<String, dynamic> rulesForFormat(String format) => {
    'halves': 2,
    'halfMinutes': format.contains('15') ? 15 : 20,
    'winnerRequired':
        (format.contains('knockout') || format.contains('extra time')),
    'shootout': (format.contains('knockout') || format.contains('extra time')),
    'extraTime': format.contains('extra time'),
    'extraHalfMinutes': 5,
  };

  @override
  String describeRules(Map<String, dynamic> rules) =>
      '${rules['halves'] ?? 2} × ${rules['halfMinutes'] ?? 20} min'
      '${rules['extraTime'] == true ? ' · 2 × 5 min extra time if tied' : ''}'
      '${rules['shootout'] == true ? ' · penalty shootout if tied' : ''}';

  @override
  MatchProgress evaluate({
    required List<String> sides,
    required Map<String, dynamic> rules,
    required List<ScoringEvent> events,
  }) {
    final halfMinutes = (rules['halfMinutes'] as num?)?.toInt() ?? 20;
    final totalHalves = (rules['halves'] as num?)?.toInt() ?? 2;
    final winnerRequired = rules['winnerRequired'] == true;
    final allowShootout = rules['shootout'] == true;

    final extraTime = rules['extraTime'] == true;
    final st = _FutsalState(totalHalves + (extraTime ? 2 : 0));
    st.regulationHalves = totalHalves;
    st.extraHalfMinutes = (rules['extraHalfMinutes'] as num?)?.toInt() ?? 5;

    for (final e in events) {
      switch (e.kind) {
        case kGoal:
          if (st.phase == _Phase.shootout || st.phase == _Phase.complete) break;
          final s = e.side ?? 0;
          final h = e.data['half'] as int? ?? st.halfIndex;
          if (s < 0 || s > 1 || h < 0 || h >= st.byHalf.length) break;
          st.goals[s]++;
          st.byHalf[h][s]++;
          st.scorers.add(
            '${sides[s]} ${e.data['player'] ?? 'Goal'} (${h + 1})',
          );
          break;
        case kPenalty:
          if (st.phase != _Phase.shootout) break;
          final s = e.side ?? 0;
          if (s < 0 || s > 1) break;
          st.taken[s]++;
          if (e.data['scored'] == true) st.shootout[s]++;
          _resolveShootout(st);
          break;
        case kClock:
          _applyClock(st, e, halfMinutes, winnerRequired, allowShootout);
          break;
        default:
          break;
      }
    }

    final clockStopped = st.phase != _Phase.running;
    final liveSeconds = st.elapsedSeconds;

    final lines = [
      ScoreLine(
        label: sides[0],
        value: '${st.goals[0]}',
        sub:
            'Half 1 ${st.byHalf[0][0]} · Half 2 ${st.byHalf[1][0]}'
            '${st.phase == _Phase.shootout || st.phase == _Phase.complete && st.shootoutTotal > 0 ? ' · pens ${st.shootout[0]}' : ''}',
        leading: st.winnerIndex == 0,
      ),
      ScoreLine(
        label: sides[1],
        value: '${st.goals[1]}',
        sub:
            'Half 1 ${st.byHalf[0][1]} · Half 2 ${st.byHalf[1][1]}'
            '${st.phase == _Phase.shootout || st.phase == _Phase.complete && st.shootoutTotal > 0 ? ' · pens ${st.shootout[1]}' : ''}',
        leading: st.winnerIndex == 1,
      ),
    ];

    final chips = <String>[
      _phaseLabel(st, halfMinutes),
      if (st.phase == _Phase.running)
        'Clock running · ${_mmss(liveSeconds)}'
      else
        'Clock ${_mmss(liveSeconds)}',
      if (st.phase == _Phase.shootout)
        'Shootout ${st.shootout[0]}-${st.shootout[1]}',
    ];

    final detail = <String>[
      if (st.halfIndex >= totalHalves)
        'Extra time ${st.byHalf.skip(totalHalves).fold<int>(0, (n, h) => n + h[0])}-${st.byHalf.skip(totalHalves).fold<int>(0, (n, h) => n + h[1])}',
      'Goals by half · H1 ${st.byHalf[0][0]}-${st.byHalf[0][1]} · H2 ${st.byHalf[1][0]}-${st.byHalf[1][1]}',
      if (st.scorers.isNotEmpty) 'Goals: ${st.scorers.join(' · ')}',
      if (st.phase == _Phase.shootout || st.shootoutTotal > 0)
        'Penalties: ${st.shootout[0]}-${st.shootout[1]} (${st.taken[0]}-${st.taken[1]} taken)',
    ];

    final finished = st.phase == _Phase.complete;

    return MatchProgress(
      sport: Sport.futsal,
      sides: sides,
      lines: lines,
      headline: finished
          ? (st.winnerIndex >= 0
                ? '${sides[st.winnerIndex]} win ${st.goals[st.winnerIndex]}-${st.goals[1 - st.winnerIndex]}'
                      '${st.shootoutTotal > 0 ? ' (${st.shootout[st.winnerIndex]}-${st.shootout[1 - st.winnerIndex]} pens)' : ''}'
                : 'Draw ${st.goals[0]}-${st.goals[1]}')
          : st.phase == _Phase.pre
          ? 'Press start on the match clock'
          : '${st.goals[0]}-${st.goals[1]} · ${_phaseLabel(st, halfMinutes)}',
      statusLabel: finished
          ? 'Full time'
          : st.phase == _Phase.paused
          ? 'Clock stopped'
          : st.phase == _Phase.running
          ? 'Running clock'
          : _phaseLabel(st, halfMinutes),
      detailRows: detail,
      contextChips: chips,
      isComplete: finished,
      winnerIndex: st.winnerIndex,
      resultLabel: finished
          ? (st.winnerIndex >= 0 ? '${sides[st.winnerIndex]} won' : 'Drawn')
          : '',
      completionReason: finished ? st.completionReason : '',
      scoreValues: [st.goals[0], st.goals[1]],
      scoreDisplay: ['${st.goals[0]}', '${st.goals[1]}'],
      actions: finished
          ? []
          : _actions(st, sides, clockStopped, halfMinutes, totalHalves),
      state: {
        'resumeAt': st.resumeAt?.toIso8601String(),
        'periodElapsed': st.elapsed[st.halfIndex],
        'phase': st.phase.name,
        'half': st.halfIndex + 1,
        'extraTime': st.halfIndex >= totalHalves,
        'periodMinutes': st.halfIndex >= totalHalves
            ? st.extraHalfMinutes
            : halfMinutes,
        'periods': st.byHalf.length,
        'shootoutTaken': st.taken,
        'shootoutScores': st.shootout,
        'elapsed': st.elapsedSeconds,
        'running': st.phase == _Phase.running,
      },
    );
  }

  void _applyClock(
    _FutsalState st,
    ScoringEvent e,
    int halfMinutes,
    bool winnerRequired,
    bool allowShootout,
  ) {
    final action = e.data['action'] as String?;
    switch (action) {
      case 'start':
        st.phase = _Phase.running;
        st.halfIndex = 0;
        st.resumeAt = e.at;
        break;
      case 'resume':
        if (st.phase == _Phase.paused || st.phase == _Phase.halfTime) {
          if (st.phase == _Phase.halfTime) {
            st.halfIndex = (st.halfIndex + 1).clamp(0, st.byHalf.length - 1);
          }
          st.phase = _Phase.running;
          st.resumeAt = e.at;
        }
        break;
      case 'stop':
        // Elapsed time is taken from the persisted event stamps, so the fold
        // replays identically after a resume, a reassignment or a restart.
        if (st.resumeAt != null) {
          st.elapsed[st.halfIndex] += e.at
              .difference(st.resumeAt!)
              .inSeconds
              .clamp(0, 86400);
          st.resumeAt = null;
        }
        st.phase = _Phase.paused;
        break;
      case 'end_half':
        if (st.phase == _Phase.running && st.resumeAt != null) {
          st.elapsed[st.halfIndex] += e.at
              .difference(st.resumeAt!)
              .inSeconds
              .clamp(0, 86400);
          st.resumeAt = null;
        }
        if (st.halfIndex == st.regulationHalves - 1 &&
            (st.goals[0] != st.goals[1] || !winnerRequired)) {
          _endRegulation(st, winnerRequired, allowShootout);
        } else if (st.halfIndex < st.byHalf.length - 1) {
          st.phase = _Phase.halfTime;
        } else {
          _endRegulation(st, winnerRequired, allowShootout);
        }
        break;
      case 'end_match':
        if (st.phase == _Phase.running && st.resumeAt != null) {
          st.elapsed[st.halfIndex] += e.at
              .difference(st.resumeAt!)
              .inSeconds
              .clamp(0, 86400);
          st.resumeAt = null;
        }
        st.phase = _Phase.complete;
        st.completionReason = 'Match ended by scorer/organizer';
        _decideWinner(st, winnerRequired);
        break;
      default:
        break;
    }
  }

  void _endRegulation(
    _FutsalState st,
    bool winnerRequired,
    bool allowShootout,
  ) {
    if (st.goals[0] != st.goals[1] || !winnerRequired) {
      st.phase = _Phase.complete;
      st.completionReason = 'Regulation complete';
      _decideWinner(st, winnerRequired);
    } else if (allowShootout) {
      st.phase = _Phase.shootout;
    } else {
      st.phase = _Phase.complete;
      st.completionReason = 'Regulation complete';
      _decideWinner(st, winnerRequired);
    }
  }

  void _decideWinner(_FutsalState st, bool winnerRequired) {
    if (st.shootoutTotal > 0 && st.shootout[0] != st.shootout[1]) {
      st.winnerIndex = st.shootout[0] > st.shootout[1] ? 0 : 1;
    } else if (st.goals[0] > st.goals[1]) {
      st.winnerIndex = 0;
    } else if (st.goals[1] > st.goals[0]) {
      st.winnerIndex = 1;
    } else {
      st.winnerIndex = -1;
    }
  }

  /// Standard best-of-5 then sudden-death shootout decision.
  void _resolveShootout(_FutsalState st) {
    const kicks = 5;
    final t0 = st.taken[0], t1 = st.taken[1];
    final s0 = st.shootout[0], s1 = st.shootout[1];
    if (t0 <= kicks && t1 <= kicks) {
      if (s0 > s1 + (kicks - t1)) {
        _finishShootout(st, 0);
        return;
      }
      if (s1 > s0 + (kicks - t0)) {
        _finishShootout(st, 1);
        return;
      }
    }
    if (t0 == t1 && t0 >= kicks && s0 != s1) {
      _finishShootout(st, s0 > s1 ? 0 : 1);
    }
  }

  void _finishShootout(_FutsalState st, int winner) {
    st.phase = _Phase.complete;
    st.winnerIndex = winner;
    st.completionReason = 'Won on penalties';
  }

  List<ScoreAction> _actions(
    _FutsalState st,
    List<String> sides,
    bool clockStopped,
    int halfMinutes,
    int totalHalves,
  ) {
    ScoringEvent clock(
      String action,
      Map<String, dynamic> extra,
      ActionContext ctx,
    ) => ScoringEvent(
      id: '',
      kind: kClock,
      side: null,
      data: {'action': action, ...extra},
      at: DateTime.now(),
      byAccountId: ctx.by,
    );

    final list = <ScoreAction>[
      ScoreAction(
        id: 'goal',
        label: 'Goal',
        hint: 'Pick the scoring side',
        style: ActionStyle.primary,
        pickSide: true,
        build: (ctx) => ScoringEvent(
          id: '',
          kind: kGoal,
          side: ctx.side ?? 0,
          data: {'half': st.halfIndex},
          at: DateTime.now(),
          byAccountId: ctx.by,
        ),
      ),
    ];

    switch (st.phase) {
      case _Phase.pre:
        list.add(
          ScoreAction(
            id: 'start',
            label: 'Start match',
            hint: '$halfMinutes-min halves',
            style: ActionStyle.highlight,
            build: (ctx) => clock('start', {}, ctx),
          ),
        );
      case _Phase.running:
        list.add(
          ScoreAction(
            id: 'pause',
            label: 'Pause clock',
            style: ActionStyle.neutral,
            build: (ctx) => clock('stop', {}, ctx),
          ),
        );
        list.add(
          ScoreAction(
            id: 'end_half',
            label: st.halfIndex < totalHalves - 1
                ? 'End half ${st.halfIndex + 1}'
                : 'Full time',
            style: ActionStyle.subtle,
            build: (ctx) => clock('end_half', {}, ctx),
          ),
        );
      case _Phase.paused:
        list.add(
          ScoreAction(
            id: 'resume',
            label: 'Resume clock',
            style: ActionStyle.highlight,
            build: (ctx) => clock('resume', {}, ctx),
          ),
        );
        list.add(
          ScoreAction(
            id: 'end_half',
            label: st.halfIndex < totalHalves - 1
                ? 'End half ${st.halfIndex + 1}'
                : 'Full time',
            style: ActionStyle.subtle,
            build: (ctx) => clock('end_half', {}, ctx),
          ),
        );
      case _Phase.halfTime:
        list.add(
          ScoreAction(
            id: 'start_half2',
            label: 'Start half ${st.halfIndex + 2}',
            style: ActionStyle.highlight,
            build: (ctx) => clock('resume', {}, ctx),
          ),
        );
      case _Phase.shootout:
        list.add(
          ScoreAction(
            id: 'pen_scored',
            label: 'Penalty scored',
            style: ActionStyle.primary,
            pickSide: true,
            build: (ctx) => ScoringEvent(
              id: '',
              kind: kPenalty,
              side: ctx.side ?? 0,
              data: {'scored': true},
              at: DateTime.now(),
              byAccountId: ctx.by,
            ),
          ),
        );
        list.add(
          ScoreAction(
            id: 'pen_missed',
            label: 'Penalty missed',
            style: ActionStyle.danger,
            pickSide: true,
            build: (ctx) => ScoringEvent(
              id: '',
              kind: kPenalty,
              side: ctx.side ?? 0,
              data: {'scored': false},
              at: DateTime.now(),
              byAccountId: ctx.by,
            ),
          ),
        );
      case _Phase.complete:
        break;
    }

    if (st.phase != _Phase.pre) {
      list.add(
        ScoreAction(
          id: 'end_match',
          label: 'End match now',
          hint: 'Use for abandoned or shortened games',
          style: ActionStyle.subtle,
          build: (ctx) => clock('end_match', {}, ctx),
        ),
      );
    }
    return list;
  }

  String _phaseLabel(_FutsalState st, int halfMinutes) => switch (st.phase) {
    _Phase.pre => 'Kick-off pending',
    _Phase.running =>
      '${st.halfIndex >= st.regulationHalves ? 'Extra time ${st.halfIndex - st.regulationHalves + 1}' : 'Half ${st.halfIndex + 1}'} · running',
    _Phase.paused =>
      '${st.halfIndex >= st.regulationHalves ? 'Extra time ${st.halfIndex - st.regulationHalves + 1}' : 'Half ${st.halfIndex + 1}'} · stopped',
    _Phase.halfTime => 'Half time',
    _Phase.shootout => 'Penalty shootout',
    _Phase.complete => 'Full time',
  };

  String _mmss(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

enum _Phase { pre, running, paused, halfTime, shootout, complete }

class _FutsalState {
  final List<List<int>> byHalf;
  final List<int> elapsed;
  List<int> goals = [0, 0];
  List<int> shootout = [0, 0];
  List<int> taken = [0, 0];
  final List<String> scorers = [];
  _Phase phase = _Phase.pre;
  int halfIndex = 0;
  int regulationHalves = 2;
  int extraHalfMinutes = 5;
  int winnerIndex = -1;
  String completionReason = '';
  DateTime? resumeAt;

  _FutsalState(int halves)
    : byHalf = List.generate(halves, (_) => [0, 0]),
      elapsed = List.filled(halves, 0);

  int get elapsedSeconds {
    var total = 0;
    for (final e in elapsed) {
      total += e;
    }
    return total;
  }

  int get shootoutTotal => taken[0] + taken[1];
}
