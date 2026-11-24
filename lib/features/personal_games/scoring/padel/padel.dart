import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';

/// Padel scoring for pairs: point by point into games, games into sets with
/// deuce/advantage or a golden point, tie-breaks, an optional super tie-break
/// deciding set, explicit service rotation and the match winner (spec §3).
///
/// The fold is pure: [evaluate] and [pointHistory] read the log and never keep
/// state of their own, so a replay, an undo and a second device always land on
/// the same score. The same rules are mirrored in
/// `supabase/migrations/0008_padel_match_module.sql`, which refuses a point the
/// fold says cannot happen.
class PadelEngine implements SportEngine {
  static const String kPoint = 'point';

  @override
  Sport get sport => Sport.padel;

  @override
  List<String> get formats => const [
    '1 set · first to 6',
    'Best of 3 sets',
    'Best of 5 sets',
    'Best of 3 · golden point',
    'Best of 3 · super tie-break',
  ];

  @override
  Map<String, dynamic> rulesForFormat(String format) {
    final goldenPoint = format.contains('golden point');
    final superTiebreak = format.contains('super tie-break');
    return {
      'setsToWin': format.startsWith('1 ')
          ? 1
          : format.contains('5')
          ? 3
          : 2,
      'gamesToWinSet': 6,
      'tiebreakAt': 6,
      'tiebreakPoints': 7,
      'finalSetTiebreakPoints': format.startsWith('1 ') ? 7 : 10,
      'noAd': goldenPoint,
      'matchTiebreak': superTiebreak,
    };
  }

  @override
  String describeRules(Map<String, dynamic> rules) {
    final r = _PadelRules.from(rules);
    final decider = r.matchTiebreak && r.setsToWin > 1
        ? '${r.finalTb}-point match tie-break instead of a decider'
        : 'tie-break at ${r.tiebreakAt}-${r.tiebreakAt}, '
              '${r.finalTb}-point decider';
    return 'Best of ${r.setsToWin * 2 - 1} sets · $decider · '
        '${r.noAd ? 'golden point (no advantage)' : 'advantage'}';
  }

  @override
  MatchProgress evaluate({
    required List<String> sides,
    required Map<String, dynamic> rules,
    required List<ScoringEvent> events,
  }) {
    final r = _PadelRules.from(rules);
    final st = _PadelState();

    for (final e in events) {
      if (e.kind != kPoint) continue;
      final outcome = _applyPoint(st, e.side ?? 0, r);
      if (outcome == _PointOutcome.match) break;
    }

    final completed = st.done;
    final winner = completed ? st.winner : -1;

    // The one per-side set summary, including the set still in play: the score
    // lines and scoreDisplay must read from the same fold, and side B always
    // sees every pair reversed so each side reads its own games first. The
    // server builds the same two orders in
    // `supabase/migrations/0013_padel_scoring.sql`.
    String setsText(int s) {
      final parts = <String>[];
      for (final set in st.completedSets) {
        parts.add(s == 0 ? '${set[0]}-${set[1]}' : '${set[1]}-${set[0]}');
      }
      if (!completed && st.hasLiveSet) {
        final cur = st.deciderTiebreak ? st.tb : st.games;
        parts.add(s == 0 ? '${cur[0]}-${cur[1]}' : '${cur[1]}-${cur[0]}');
      }
      return parts.isEmpty ? '-' : parts.join(', ');
    }

    final lines = [
      ScoreLine(
        label: sides[0],
        value: '${st.setsWon[0]}',
        sub: setsText(0),
        leading: completed ? winner == 0 : st.servingSide == 0,
        muted:
            !completed &&
            st.setsWon[0] == 0 &&
            st.games[0] == 0 &&
            st.points[0] == 0,
      ),
      ScoreLine(
        label: sides[1],
        value: '${st.setsWon[1]}',
        sub: setsText(1),
        leading: completed ? winner == 1 : st.servingSide == 1,
        muted:
            !completed &&
            st.setsWon[1] == 0 &&
            st.games[1] == 0 &&
            st.points[1] == 0,
      ),
    ];

    final chips = <String>[];
    if (completed) {
      chips.add('Final: ${st.setsWon[0]}-${st.setsWon[1]} in sets');
    } else if (st.inTiebreak) {
      chips.add(
        '${st.deciderTiebreak ? 'Super tie-break' : 'Tie-break'} '
        '${st.tb[0]}-${st.tb[1]} · first to ${_targetFor(st, r)}, win by 2',
      );
    } else {
      chips.add(
        'Set ${st.setsCompleted + 1} · games ${st.games[0]}-${st.games[1]}',
      );
      chips.add(_gameScoreText(st, sides, r));
    }
    if (!completed) chips.add('Service: ${sides[st.servingSide]}');
    if (r.noAd && !completed) chips.add('Golden point on deuce');

    final detail = <String>[];
    for (var i = 0; i < st.completedSets.length; i++) {
      final g = st.completedSets[i];
      final w = _setWinner(g);
      detail.add(
        'Set ${i + 1}: ${g[0]}-${g[1]}'
        '${w == null ? ' (level)' : '  won by ${sides[w]}'}',
      );
    }
    if (!completed) {
      detail.add(
        st.inTiebreak
            ? 'Set ${st.setsCompleted + 1} '
                  '${st.deciderTiebreak ? 'super tie-break' : 'tie-break'}: '
                  '${st.tb[0]}-${st.tb[1]}'
            : 'Set ${st.setsCompleted + 1} in progress: '
                  '${st.games[0]}-${st.games[1]}'
                  '  (${_gameScoreText(st, sides, r)})',
      );
    }

    return MatchProgress(
      sport: Sport.padel,
      sides: sides,
      lines: lines,
      headline: completed
          ? '${sides[winner]} win ${st.setsWon[winner]}-${st.setsWon[1 - winner]}'
          : events.isEmpty
          ? 'Record the first point to start the match'
          : 'Set ${st.setsCompleted + 1} · ${st.games[0]}-${st.games[1]}',
      statusLabel: completed
          ? 'Match complete'
          : st.deciderTiebreak
          ? 'Super tie-break'
          : st.inTiebreak
          ? 'Tie-break'
          : 'Points counting',
      detailRows: detail,
      contextChips: chips,
      isComplete: completed,
      winnerIndex: winner,
      resultLabel: completed
          ? '${sides[winner]} won ${st.setsWon[winner]}-${st.setsWon[1 - winner]}'
          : '',
      completionReason: completed
          ? r.matchTiebreak && st.wonDecider
                ? 'Match tie-break won (${st.completedSets.last[0]}-'
                      '${st.completedSets.last[1]})'
                : 'Sets to win reached (${r.setsToWin})'
          : '',
      scoreValues: [st.setsWon[0], st.setsWon[1]],
      scoreDisplay: [setsText(0), setsText(1)],
      actions: completed
          ? []
          : [
              ScoreAction(
                id: 'point',
                label: 'Point won by',
                hint: 'Pick the side that took the point',
                style: ActionStyle.primary,
                pickSide: true,
                build: (ctx) => ScoringEvent(
                  id: '',
                  kind: kPoint,
                  side: ctx.side ?? 0,
                  data: const {},
                  at: DateTime.now(),
                  byAccountId: ctx.by,
                ),
              ),
            ],
      state: {
        'completedSets': st.completedSets,
        'points': st.points,
        'tiebreakPoints': st.tb,
        'setsWon': [st.setsWon[0], st.setsWon[1]],
        'games': [st.games[0], st.games[1]],
        'inTiebreak': st.inTiebreak,
        'deciderTiebreak': st.deciderTiebreak,
        'matchTiebreak': r.matchTiebreak,
        'noAd': r.noAd,
        'setsToWin': r.setsToWin,
        'gamesToWinSet': r.gamesToWinSet,
        'servingSide': st.servingSide,
        'servingMember': st.servingMember,
        'servingName': sides[st.servingSide],
        'pointCount': st.pointCount,
      },
    );
  }

  /// Point-by-point history, folded with the same reducer as [evaluate].
  ///
  /// Each record carries the score before and after the point, who served it
  /// and which side won, so the workspace can show an honest log without a
  /// second rules implementation.
  List<PadelPointRecord> pointHistory({
    required List<String> sides,
    required Map<String, dynamic> rules,
    required List<ScoringEvent> events,
  }) {
    final r = _PadelRules.from(rules);
    final st = _PadelState();
    final history = <PadelPointRecord>[];

    for (final e in events) {
      if (e.kind != kPoint) continue;
      final side = e.side ?? 0;
      final setIndex = st.setsCompleted;
      final gameIndex = st.deciderTiebreak
          ? st.tb[0] + st.tb[1] + 1
          : st.games[0] + st.games[1] + 1;
      final serverSide = st.servingSide;
      final serverMember = st.servingMember;
      final before = _gameScoreText(st, sides, r);
      final wasTiebreak = st.inTiebreak;
      final wasGolden = _isGoldenPoint(st, r);

      final outcome = _applyPoint(st, side, r);

      history.add(
        PadelPointRecord(
          index: history.length + 1,
          setIndex: setIndex,
          gameIndex: gameIndex,
          serverSide: serverSide,
          serverMember: serverMember,
          winnerSide: side,
          scoreBefore: before,
          scoreAfter: _afterLabel(st, sides, side, outcome, r),
          tiebreak: wasTiebreak,
          goldenPoint: wasGolden,
          setsWonAfter: [st.setsWon[0], st.setsWon[1]],
          gamesAfter: [st.games[0], st.games[1]],
        ),
      );

      if (outcome == _PointOutcome.match) break;
    }
    return history;
  }

  // ── Fold internals ──────────────────────────────────────────────────────

  /// Folds one point into [st] and reports how far the score moved.
  _PointOutcome _applyPoint(_PadelState st, int s, _PadelRules r) {
    final o = 1 - s;
    st.pointCount++;

    if (st.inTiebreak) {
      st.tb[s]++;
      // Service in a tie-break changes after the first point, then every two.
      if ((st.tb[0] + st.tb[1]).isOdd) st.endServiceTurn();
      final need = _targetFor(st, r);
      if (st.tb[s] >= need && st.tb[s] - st.tb[o] >= 2) {
        st.tb = [0, 0];
        st.inTiebreak = false;
        st.games[s]++; // 6→7 for a regular TB, 0→1 for the deciding super TB
        final decider = st.deciderTiebreak;
        st.deciderTiebreak = false;
        _completeSet(st, s);
        if (decider) st.wonDecider = true;
        return _matchOrSet(st, s, r);
      }
      return _PointOutcome.point;
    }

    st.points[s]++;
    final won = r.noAd
        ? st.points[s] >= 4 && st.points[s] - st.points[o] >= 1
        : st.points[s] >= 4 && st.points[s] - st.points[o] >= 2;
    if (!won) return _PointOutcome.point;

    st.points = [0, 0];
    st.games[s]++;
    st.endServiceTurn();
    if (st.games[s] >= r.gamesToWinSet && st.games[s] - st.games[o] >= 2) {
      _completeSet(st, s);
      return _matchOrSet(st, s, r);
    }
    if (st.games[0] == r.tiebreakAt && st.games[1] == r.tiebreakAt) {
      st.inTiebreak = true;
    }
    return _PointOutcome.game;
  }

  /// After a set closes, either the match is over or the next set (or the
  /// super tie-break that replaces a decider) opens.
  _PointOutcome _matchOrSet(_PadelState st, int s, _PadelRules r) {
    if (st.setsWon[0] >= r.setsToWin || st.setsWon[1] >= r.setsToWin) {
      st.done = true;
      st.winner = st.setsWon[0] >= r.setsToWin ? 0 : 1;
      return _PointOutcome.match;
    }
    if (r.matchTiebreak &&
        r.setsToWin > 1 &&
        st.setsWon[0] == r.setsToWin - 1 &&
        st.setsWon[1] == r.setsToWin - 1) {
      st.inTiebreak = true;
      st.deciderTiebreak = true;
    }
    return _PointOutcome.set;
  }

  void _completeSet(_PadelState st, int winner) {
    st.completedSets.add([st.games[0], st.games[1]]);
    st.setsWon[winner]++;
    st.games = [0, 0];
    st.points = [0, 0];
    st.tb = [0, 0];
    st.inTiebreak = false;
    st.setsCompleted++;
    // Service continues in order across sets.
  }

  int? _setWinner(List<int> g) => g[0] == g[1] ? null : (g[0] > g[1] ? 0 : 1);

  int _targetFor(_PadelState st, _PadelRules r) =>
      st.deciderTiebreak ||
          (st.setsWon[0] == r.setsToWin - 1 && st.setsWon[1] == r.setsToWin - 1)
      ? r.finalTb
      : r.tbPoints;

  bool _isGoldenPoint(_PadelState st, _PadelRules r) =>
      r.noAd &&
      !st.inTiebreak &&
      st.points[0] >= 3 &&
      st.points[0] == st.points[1];

  String _gameScoreText(_PadelState st, List<String> sides, _PadelRules r) {
    if (st.inTiebreak) {
      return st.deciderTiebreak
          ? 'Super tie-break ${st.tb[0]}-${st.tb[1]}'
          : 'Tie-break ${st.tb[0]}-${st.tb[1]}';
    }
    const names = ['0', '15', '30', '40'];
    final a = st.points[0], b = st.points[1];
    if (a < 3 || b < 3) {
      if (a <= 3 && b <= 3) return '${names[a]}-${names[b]}';
    }
    if (a == b) return r.noAd ? '40-40 · golden point' : 'Deuce';
    if (r.noAd) {
      return a > b ? 'Game point ${sides[0]}' : 'Game point ${sides[1]}';
    }
    return a > b ? 'Advantage ${sides[0]}' : 'Advantage ${sides[1]}';
  }

  String _afterLabel(
    _PadelState st,
    List<String> sides,
    int winner,
    _PointOutcome outcome,
    _PadelRules r,
  ) {
    final wonBy = sides[winner];
    return switch (outcome) {
      _PointOutcome.match => 'match · $wonBy',
      _PointOutcome.set => 'set · $wonBy',
      _PointOutcome.game => 'game · $wonBy',
      _PointOutcome.point => _gameScoreText(st, sides, r),
    };
  }
}

/// How far one recorded point moved the score.
enum _PointOutcome { point, game, set, match }

/// One point of the log, as the workspace history panel renders it.
class PadelPointRecord {
  const PadelPointRecord({
    required this.index,
    required this.setIndex,
    required this.gameIndex,
    required this.serverSide,
    required this.serverMember,
    required this.winnerSide,
    required this.scoreBefore,
    required this.scoreAfter,
    required this.tiebreak,
    required this.goldenPoint,
    required this.setsWonAfter,
    required this.gamesAfter,
  });

  /// 1-based position in the log.
  final int index;

  /// 0-based set the point belonged to.
  final int setIndex;

  /// 1-based game of that set (tie-break point count in a tie-break).
  final int gameIndex;

  /// Which pair served, and which of its two players (0 or 1).
  final int serverSide;
  final int serverMember;

  final int winnerSide;
  final String scoreBefore;
  final String scoreAfter;
  final bool tiebreak;
  final bool goldenPoint;
  final List<int> setsWonAfter;
  final List<int> gamesAfter;

  bool get isDecidingPoint => scoreAfter.startsWith('match ·');
}

/// Rules map as the engine reads it, with the same defaults as the server.
class _PadelRules {
  const _PadelRules({
    required this.setsToWin,
    required this.gamesToWinSet,
    required this.tiebreakAt,
    required this.tbPoints,
    required this.finalTb,
    required this.noAd,
    required this.matchTiebreak,
  });

  factory _PadelRules.from(Map<String, dynamic> rules) => _PadelRules(
    setsToWin: (rules['setsToWin'] as num?)?.toInt() ?? 2,
    gamesToWinSet: (rules['gamesToWinSet'] as num?)?.toInt() ?? 6,
    tiebreakAt: (rules['tiebreakAt'] as num?)?.toInt() ?? 6,
    tbPoints: (rules['tiebreakPoints'] as num?)?.toInt() ?? 7,
    finalTb: (rules['finalSetTiebreakPoints'] as num?)?.toInt() ?? 10,
    noAd: rules['noAd'] == true,
    matchTiebreak: rules['matchTiebreak'] == true,
  );

  final int setsToWin;
  final int gamesToWinSet;
  final int tiebreakAt;
  final int tbPoints;
  final int finalTb;
  final bool noAd;
  final bool matchTiebreak;
}

class _PadelState {
  List<int> points = [0, 0];
  List<int> games = [0, 0];
  List<int> setsWon = [0, 0];
  List<int> tb = [0, 0];
  final List<List<int>> completedSets = [];
  int setsCompleted = 0;
  bool inTiebreak = false;

  /// The tie-break *is* the deciding set (super tie-break), not a 6-6 shootout.
  bool deciderTiebreak = false;
  bool wonDecider = false;
  bool done = false;
  int winner = -1;
  int pointCount = 0;

  /// How many service turns each pair has finished. The pair's two players
  /// alternate, so the server is `serveTurns[side] % 2`.
  List<int> serveTurns = [0, 0];
  int servingSide = 0;

  int get servingMember => serveTurns[servingSide] % 2;

  bool get hasLiveSet =>
      games[0] > 0 ||
      games[1] > 0 ||
      points[0] > 0 ||
      points[1] > 0 ||
      tb[0] > 0 ||
      tb[1] > 0;

  /// Service alternates every game and every tie-break turn.
  void endServiceTurn() {
    serveTurns[servingSide]++;
    servingSide = 1 - servingSide;
  }
}
