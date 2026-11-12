import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';

/// Badminton rally-point scoring for singles or doubles: every rally scores,
/// games to 21 (win by 2, capped at 30), and the match winner (spec §3).
class BadmintonEngine implements SportEngine {
  static const String kRally = 'rally';

  @override
  Sport get sport => Sport.badminton;

  @override
  List<String> get formats => const [
    'Best of 3 games',
    'Best of 5 games',
    'Singles · best of 3',
    'Doubles · best of 3',
  ];

  @override
  Map<String, dynamic> rulesForFormat(String format) => {
    'gamesToWin': format.contains('5') ? 3 : 2,
    'pointsToWinGame': 21,
    'cap': 30,
    'discipline': format.contains('Singles')
        ? 'singles'
        : format.contains('Doubles')
        ? 'doubles'
        : 'doubles',
  };

  @override
  String describeRules(Map<String, dynamic> rules) {
    final needed = (rules['gamesToWin'] as int? ?? 2);
    return '${rules['discipline'] ?? 'doubles'} · best of ${needed * 2 - 1} games'
        ' to ${rules['pointsToWinGame'] ?? 21} (win by 2, cap ${rules['cap'] ?? 30})';
  }

  @override
  MatchProgress evaluate({
    required List<String> sides,
    required Map<String, dynamic> rules,
    required List<ScoringEvent> events,
  }) {
    final gamesToWin = (rules['gamesToWin'] as num?)?.toInt() ?? 2;
    final toWin = (rules['pointsToWinGame'] as num?)?.toInt() ?? 21;
    final cap = (rules['cap'] as num?)?.toInt() ?? 30;

    var points0 = 0, points1 = 0;
    final gamesWon = [0, 0];
    final completedGames = <List<int>>[];
    var done = false, winner = -1;
    var server = (rules['firstServer'] as num?)?.toInt() ?? 0;

    for (final e in events) {
      if (e.kind != kRally || done) continue;
      final s = e.side ?? 0;
      server = s;
      if (s == 0) {
        points0++;
      } else {
        points1++;
      }

      final p = s == 0 ? points0 : points1;
      final q = s == 0 ? points1 : points0;
      final gameWon = (p >= toWin && p - q >= 2) || p >= cap;
      if (gameWon) {
        completedGames.add([points0, points1]);
        gamesWon[s]++;
        points0 = 0;
        points1 = 0;
        if (gamesWon[s] >= gamesToWin) {
          done = true;
          winner = s;
          break;
        }
      }
    }

    final completed = done;
    final gamesTotal = completedGames.length;

    String gamesText(int s) {
      final parts = <String>[];
      for (final g in completedGames) {
        parts.add(s == 0 ? '${g[0]}-${g[1]}' : '${g[1]}-${g[0]}');
      }
      if (!completed && (points0 > 0 || points1 > 0)) {
        parts.add(s == 0 ? '$points0-$points1' : '$points1-$points0');
      }
      return parts.isEmpty ? '-' : parts.join(', ');
    }

    final lines = [
      ScoreLine(
        label: sides[0],
        value: '${gamesWon[0]}',
        sub: gamesText(0),
        leading: completed ? winner == 0 : points0 > points1,
        muted: !completed && gamesWon[0] == 0 && points0 == 0,
      ),
      ScoreLine(
        label: sides[1],
        value: '${gamesWon[1]}',
        sub: gamesText(1),
        leading: completed ? winner == 1 : points1 > points0,
        muted: !completed && gamesWon[1] == 0 && points1 == 0,
      ),
    ];

    final chips = <String>[];
    if (completed) {
      chips.add('Games: ${gamesWon[0]}-${gamesWon[1]}');
    } else if (events.isNotEmpty) {
      chips.add('Game ${gamesTotal + 1} · $points0-$points1');
      final gp = _gamePointLabel(points0, points1, toWin, cap, sides);
      if (gp != null) chips.add(gp);
    }
    if (!completed && events.isNotEmpty) {
      chips.add('Service: ${sides[server]}');
    }

    final detail = <String>[
      for (var i = 0; i < completedGames.length; i++)
        'Game ${i + 1}: ${completedGames[i][0]}-${completedGames[i][1]}'
            '  won by ${sides[completedGames[i][0] > completedGames[i][1] ? 0 : 1]}',
      if (!completed && (points0 > 0 || points1 > 0))
        'Game ${gamesTotal + 1} in progress: $points0-$points1',
    ];

    return MatchProgress(
      sport: Sport.badminton,
      sides: sides,
      lines: lines,
      headline: completed
          ? '${sides[winner]} win ${gamesWon[winner]}-${gamesWon[1 - winner]}'
          : events.isEmpty
          ? 'Record the first rally to start game 1'
          : 'Game ${gamesTotal + 1} · $points0-$points1',
      statusLabel: completed
          ? 'Match complete'
          : (rules['discipline'] == 'singles' ? 'Singles' : 'Doubles'),
      detailRows: detail,
      contextChips: chips,
      isComplete: completed,
      winnerIndex: winner,
      resultLabel: completed
          ? '${sides[winner]} won ${gamesWon[winner]}-${gamesWon[1 - winner]}'
          : '',
      completionReason: completed ? 'Games to win reached ($gamesToWin)' : '',
      scoreValues: [gamesWon[0], gamesWon[1]],
      scoreDisplay: [gamesText(0), gamesText(1)],
      actions: completed
          ? []
          : [
              ScoreAction(
                id: 'rally',
                label: 'Rally won by',
                hint: 'Point goes to the side that won the rally',
                style: ActionStyle.primary,
                pickSide: true,
                build: (ctx) => ScoringEvent(
                  id: '',
                  kind: kRally,
                  side: ctx.side ?? 0,
                  data: const {},
                  at: DateTime.now(),
                  byAccountId: ctx.by,
                ),
              ),
            ],
      state: {
        'completedGames': completedGames,
        'server': server,
        'gamesWon': [gamesWon[0], gamesWon[1]],
        'points': [points0, points1],
        'game': gamesTotal + 1,
      },
    );
  }

  String? _gamePointLabel(
    int a,
    int b,
    int target,
    int cap,
    List<String> sides,
  ) {
    if (a == cap - 1 && b == cap - 1) return 'Golden point · next rally wins';
    if (a == b && a >= target - 1) return 'Deuce · win by 2';
    if (a >= target - 1 && a > b) return 'Game point · ${sides[0]}';
    if (b >= target - 1 && b > a) return 'Game point · ${sides[1]}';
    return null;
  }
}
