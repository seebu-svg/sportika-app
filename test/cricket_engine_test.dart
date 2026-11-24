// The cricket fold: the toss seeds the first innings, an innings can be opened
// before its first ball, a named XI caps the wickets, and an early end is a
// result. Every case here is a rule the workspace and the Match Center read off
// `MatchProgress`, so the fold is where they are pinned.

import 'package:flutter_test/flutter_test.dart';

import 'package:sportika/features/personal_games/scoring/cricket/cricket.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';

void main() {
  final engine = CricketEngine();
  final start = DateTime.utc(2026, 5, 1, 18);
  var seq = 0;

  ScoringEvent at(
    String kind,
    int? side, [
    Map<String, dynamic> data = const {},
  ]) {
    seq++;
    return ScoringEvent(
      id: 'ev-$seq',
      kind: kind,
      side: side,
      data: data,
      at: start.add(Duration(seconds: seq)),
      byAccountId: 'organizer',
    );
  }

  ScoringEvent toss(int side, String decision) =>
      at(CricketEngine.kToss, side, {'decision': decision});

  ScoringEvent openInnings(int side) => at(CricketEngine.kInningsStart, side);

  ScoringEvent ball(
    int side,
    int runs, {
    String? extra,
    bool wicket = false,
    String striker = 'Ann',
    String nonStriker = 'Ben',
  }) => at(CricketEngine.kBall, side, {
    'runs': runs,
    'extra': ?extra,
    if (wicket) 'wicket': true,
    if (wicket) 'dismissal': 'Bowled',
    if (wicket) 'dismissedBatter': striker,
    'striker': striker,
    'nonStriker': nonStriker,
    'bowler': 'Cy',
  });

  ScoringEvent lineup(int side, int size) => at(CricketEngine.kLineup, side, {
    'players': [for (var i = 0; i < size; i++) 'p$side-$i'],
  });

  ScoringEvent closeInnings() =>
      at(CricketEngine.kInningsEnd, null, {'reason': 'Innings closed'});

  ScoringEvent endMatch() =>
      at(CricketEngine.kMatchEnd, null, {'reason': 'Match ended'});

  MatchProgress fold(
    List<ScoringEvent> events, {
    int overs = 2,
    int wickets = 3,
  }) => engine.evaluate(
    sides: const ['Alpha', 'Bravo'],
    rules: {
      'oversPerInnings': overs,
      'wicketsPerInnings': wickets,
      'innings': 2,
    },
    events: events,
  );

  group('the toss', () {
    test('electing to bat puts the winner in first', () {
      final progress = fold([toss(0, 'bat'), openInnings(0), ball(0, 4)]);
      expect(progress.state['nextBatSide'], 0);
      expect(progress.lines[0].value, '4/0');
      expect(progress.state['toss'], {
        'winner': 0,
        'decision': 'bat',
        'batSide': 0,
      });
    });

    test('electing to bowl puts the other side in first', () {
      final progress = fold([toss(0, 'bowl'), openInnings(1), ball(1, 4)]);
      expect(progress.state['nextBatSide'], 1);
      expect(progress.lines[1].value, '4/0');
      expect(progress.state['toss'], {
        'winner': 0,
        'decision': 'bowl',
        'batSide': 1,
      });
    });

    test('is ignored once a delivery has been recorded', () {
      final progress = fold([ball(0, 1), toss(1, 'bat')]);
      expect(progress.state.containsKey('toss'), isFalse);
    });
  });

  group('opening an innings', () {
    test('shows 0/0 and an open innings before the first ball', () {
      final progress = fold([toss(0, 'bat'), openInnings(0)]);
      expect(progress.state['innings'], 1);
      expect(progress.state['open'], isTrue);
      expect(progress.state['phase'], 'innings');
      expect(progress.lines[0].value, '0/0');
      expect(progress.isComplete, isFalse);
    });

    test('the second innings flips the side and starts at nothing', () {
      final progress = fold([
        toss(0, 'bat'),
        openInnings(0),
        ball(0, 4),
        closeInnings(),
        openInnings(1),
      ]);
      expect(progress.state['innings'], 2);
      expect(progress.state['nextBatSide'], 1);
      expect(progress.lines[1].value, '0/0');
      expect(progress.state['target'], 5);
    });

    test('there is no side due next once the match is complete', () {
      final progress = fold([
        toss(0, 'bat'),
        openInnings(0),
        closeInnings(),
        openInnings(1),
        closeInnings(),
      ]);
      expect(progress.isComplete, isTrue);
      expect(progress.state['nextBatSide'], -1);
      expect(progress.state['phase'], 'complete');
      expect(progress.resultLabel, 'Match tied');
    });
  });

  group('a named XI is all out one short of its size', () {
    test('four named batters are all out at three wickets', () {
      final progress = fold([
        lineup(0, 4),
        openInnings(0),
        ball(0, 0, wicket: true, striker: 'Ann', nonStriker: 'Ben'),
        ball(0, 0, wicket: true, striker: 'Cal', nonStriker: 'Ben'),
        ball(0, 0, wicket: true, striker: 'Dee', nonStriker: 'Ben'),
      ], wickets: 10);
      expect(progress.state['battingSize'], [4, 0]);
      expect(progress.lines[0].sub, contains('All out'));
      expect(progress.state['phase'], 'break');
    });

    test('without a lineup the rules decide', () {
      final progress = fold([
        openInnings(0),
        ball(0, 0, wicket: true),
        ball(0, 0, wicket: true),
        ball(0, 0, wicket: true),
      ]);
      expect(progress.state['battingSize'], [0, 0]);
      expect(progress.lines[0].sub, contains('All out'));
    });
  });

  group('closing an innings', () {
    test('the chase closes the moment the target is passed', () {
      final progress = fold([
        openInnings(0),
        ball(0, 4),
        closeInnings(),
        openInnings(1),
        ball(1, 4),
        ball(1, 1),
      ]);
      expect(progress.lines[1].sub, contains('Target passed'));
      expect(progress.isComplete, isTrue);
      expect(progress.winnerIndex, 1);
      expect(progress.resultLabel, 'Bravo won by 3 wickets');
    });

    test('defending a total wins by runs', () {
      final progress = fold([
        openInnings(0),
        ball(0, 4),
        closeInnings(),
        openInnings(1),
        ball(1, 1),
        closeInnings(),
      ]);
      expect(progress.isComplete, isTrue);
      expect(progress.winnerIndex, 0);
      expect(progress.resultLabel, 'Alpha won by 3 runs');
    });
  });

  group('an early end', () {
    test('after one innings is complete and has no result', () {
      final progress = fold([ball(0, 4), endMatch()]);
      expect(progress.isComplete, isTrue);
      expect(progress.headline, 'No result');
      expect(progress.resultLabel, '');
      expect(progress.winnerIndex, -1);
      expect(progress.completionReason, 'Match ended');
    });

    test('after two innings keeps the folded result', () {
      final progress = fold([
        ball(0, 4),
        closeInnings(),
        ball(1, 1),
        endMatch(),
      ]);
      expect(progress.isComplete, isTrue);
      expect(progress.resultLabel, 'Alpha won by 3 runs');
      expect(progress.completionReason, 'Match ended');
    });

    test('nothing is counted after the end', () {
      final progress = fold([ball(0, 4), endMatch(), ball(0, 6)]);
      expect(progress.lines[0].value, '4/0');
      expect(progress.scoreValues, [4, 0]);
    });
  });

  test('a log of deliveries alone folds exactly as before', () {
    final progress = fold([
      ball(0, 1),
      ball(0, 1),
      ball(0, 1),
      ball(0, 1),
      ball(0, 1),
      ball(0, 1),
    ]);
    expect(progress.scoreDisplay, ['6/0', '-']);
    expect(progress.state['innings'], 1);
    expect(progress.state['open'], isTrue);
    expect(progress.state['nextBatSide'], 0);
    expect(progress.state.containsKey('toss'), isFalse);
    expect(progress.contextChips.first, 'Innings 1/2');
    expect(progress.isComplete, isFalse);
  });

  test('a wide still costs a run and does not count as a ball faced', () {
    final progress = fold([openInnings(0), ball(0, 0, extra: 'wide')]);
    expect(progress.lines[0].value, '1/0');
    expect(progress.lines[0].sub, contains('0.0 ov'));
  });
}
