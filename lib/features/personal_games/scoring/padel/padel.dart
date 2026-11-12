import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';

/// Padel scoring for pairs: point by point into games, games into sets with
/// deuce/advantage and tie-breaks, and the match winner (spec §3).
class PadelEngine implements SportEngine {
  static const String kPoint = 'point';

  @override
  Sport get sport => Sport.padel;

  @override
  List<String> get formats => const [
    '1 set · first to 6',
    'Best of 3 sets',
    'Best of 5 sets',
  ];

  @override
  Map<String, dynamic> rulesForFormat(String format) => {
    'setsToWin': format.startsWith('1 ')
        ? 1
        : format.contains('5')
        ? 3
        : 2,
    'gamesToWinSet': 6,
    'tiebreakAt': 6,
    'tiebreakPoints': 7,
    'finalSetTiebreakPoints': format.startsWith('1 ') ? 7 : 10,
    'noAd': false,
  };

  @override
  String describeRules(Map<String, dynamic> rules) {
    final needed = (rules['setsToWin'] as int? ?? 2);
    return 'Best of ${needed * 2 - 1} sets · tie-break at ${(rules['tiebreakAt'] ?? 6)}'
        '-${rules['tiebreakAt'] ?? 6}, ${rules['finalSetTiebreakPoints'] ?? 10}-point decider';
  }

  @override
  MatchProgress evaluate({
    required List<String> sides,
    required Map<String, dynamic> rules,
    required List<ScoringEvent> events,
  }) {
    final setsToWin = (rules['setsToWin'] as num?)?.toInt() ?? 2;
    final gamesToWinSet = (rules['gamesToWinSet'] as num?)?.toInt() ?? 6;
    final tiebreakAt = (rules['tiebreakAt'] as num?)?.toInt() ?? 6;
    final tbPoints = (rules['tiebreakPoints'] as num?)?.toInt() ?? 7;
    final finalSetTb = (rules['finalSetTiebreakPoints'] as num?)?.toInt() ?? 10;
    final noAd = rules['noAd'] == true;

    final st = _PadelState();

    int targetForCurrentSet() =>
        st.setsWon[0] == setsToWin - 1 && st.setsWon[1] == setsToWin - 1
        ? finalSetTb
        : tbPoints;

    for (final e in events) {
      if (e.kind != kPoint) continue;
      final s = e.side ?? 0;
      final o = 1 - s;

      if (st.inTiebreak) {
        st.tb[s]++;
        final need = targetForCurrentSet();
        if (st.tb[s] >= need && st.tb[s] - st.tb[o] >= 2) {
          st.tb = [0, 0];
          st.inTiebreak = false;
          st.games[s]++; // 7-6
          st.totalGames++;
          _completeSet(st, s, sides);
        }
      } else {
        st.points[s]++;
        final won = noAd
            ? st.points[s] >= 4 && st.points[s] - st.points[o] >= 1
            : st.points[s] >= 4 && st.points[s] - st.points[o] >= 2;
        if (won) {
          st.points = [0, 0];
          st.games[s]++;
          st.totalGames++;
          if (st.games[s] >= gamesToWinSet && st.games[s] - st.games[o] >= 2) {
            _completeSet(st, s, sides);
          } else if (st.games[0] == tiebreakAt && st.games[1] == tiebreakAt) {
            st.inTiebreak = true;
          }
        }
      }

      if (st.setsWon[0] >= setsToWin || st.setsWon[1] >= setsToWin) {
        st.done = true;
        st.winner = st.setsWon[0] >= setsToWin ? 0 : 1;
        break;
      }
    }

    final completed = st.done;
    final winner = completed ? st.winner : -1;

    // Per-side set summary, including the set still in play.
    String setsText(int s) {
      final parts = <String>[];
      for (var i = 0; i < st.completedSets.length; i++) {
        final s0 = st.completedSets[i][0], s1 = st.completedSets[i][1];
        parts.add(s == 0 ? '$s0-$s1' : '$s1-$s0');
      }
      if (!completed &&
          (st.games[0] > 0 ||
              st.games[1] > 0 ||
              st.points[0] > 0 ||
              st.points[1] > 0)) {
        final cur = [st.games[0], st.games[1]];
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
        'Tie-break ${st.tb[0]}-${st.tb[1]} · first to ${targetForCurrentSet()}, win by 2',
      );
    } else {
      chips.add(
        'Set ${st.setsCompleted + 1} · games ${st.games[0]}-${st.games[1]}',
      );
      chips.add(_gameScoreText(st, sides, noAd));
    }
    if (!completed) chips.add('Service: ${sides[st.servingSide]}');

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
            ? 'Set ${st.setsCompleted + 1} tie-break: ${st.tb[0]}-${st.tb[1]}'
            : 'Set ${st.setsCompleted + 1} in progress: ${st.games[0]}-${st.games[1]}'
                  '  (${_gameScoreText(st, sides, noAd)})',
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
      statusLabel: completed ? 'Match complete' : 'Points counting',
      detailRows: detail,
      contextChips: chips,
      isComplete: completed,
      winnerIndex: winner,
      resultLabel: completed
          ? '${sides[winner]} won ${st.setsWon[winner]}-${st.setsWon[1 - winner]}'
          : '',
      completionReason: completed ? 'Sets to win reached ($setsToWin)' : '',
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
      },
    );
  }

  void _completeSet(_PadelState st, int winner, List<String> sides) {
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

  String _gameScoreText(_PadelState st, List<String> sides, bool noAd) {
    if (st.inTiebreak) return 'Tie-break ${st.tb[0]}-${st.tb[1]}';
    const names = ['0', '15', '30', '40'];
    final a = st.points[0], b = st.points[1];
    if (a < 3 || b < 3) {
      if (a <= 3 && b <= 3) return '${names[a]}-${names[b]}';
    }
    if (a == b) return 'Deuce';
    if (noAd) {
      return a > b ? 'Game point ${sides[0]}' : 'Game point ${sides[1]}';
    }
    return a > b ? 'Advantage ${sides[0]}' : 'Advantage ${sides[1]}';
  }
}

class _PadelState {
  List<int> points = [0, 0];
  List<int> games = [0, 0];
  List<int> setsWon = [0, 0];
  List<int> tb = [0, 0];
  final List<List<int>> completedSets = [];
  int setsCompleted = 0;
  bool inTiebreak = false;
  bool done = false;
  int winner = -1;

  /// Completed games determine service order across set boundaries.
  int totalGames = 0;

  int get servingSide =>
      (totalGames + (inTiebreak ? (tb[0] + tb[1] + 1) ~/ 2 : 0)) % 2;
}
