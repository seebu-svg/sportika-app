// Parity between the two folds that decide a cricket result.
//
// The sequences below are the literal ones supabase/tests/cricket_scoring_test.sql
// writes through record_match_event. That suite asserts what the SERVER folds;
// this one asserts that CricketEngine folds the same log to the same per-side
// run totals, the same score strings, the same winner and the same completion,
// because those are the exact values submit_match_result compares the caller's
// payload against. If _cricket_fold_detail and CricketEngine drift on ANY of
// them, a genuine scorer would hit score_payload_mismatch — so a drift has to
// turn one of these two suites red rather than disagree silently.
//
// The one place they are DELIBERATELY allowed to differ is the "won by N
// wickets" headline. CricketEngine still computes that margin from the FIRST
// innings' wicket cap (the confirmed bug this task fixes on the server only —
// the frontend is intentionally untouched), so the engine and the SQL fold
// disagree exactly when the two sides name XIs of different sizes. The C2 group
// pins both halves of that fact: the gated values agree, the headline does not,
// and submit is safe precisely because it never gates on the headline.

import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/features/personal_games/scoring/cricket/cricket.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';

void main() {
  final engine = CricketEngine();
  final sides = ['Coast', 'Dale'];
  // One over a side, ten wickets, two innings: the shape the SQL fixtures use so
  // the sequences stay short without changing any fold rule.
  final rules = <String, dynamic>{
    'oversPerInnings': 1,
    'wicketsPerInnings': 10,
    'innings': 2,
  };

  final start = DateTime.utc(2026, 4, 1, 14);
  var ordinal = 0;
  ScoringEvent ev(
    String kind,
    int? side, [
    Map<String, dynamic> data = const {},
  ]) => ScoringEvent(
    id: '$kind-${ordinal++}',
    kind: kind,
    side: side,
    data: data,
    at: start.add(Duration(seconds: ordinal)),
    byAccountId: 'organizer',
  );

  ScoringEvent toss(int side, String decision) =>
      ev(CricketEngine.kToss, side, {'decision': decision});
  ScoringEvent lineup(int side, int count) => ev(CricketEngine.kLineup, side, {
    'players': List<String>.generate(count, (i) => 'p$side-$i'),
  });
  ScoringEvent inningsStart(int side) => ev(CricketEngine.kInningsStart, side);
  ScoringEvent ball(int side, int runs, {String? wicket}) {
    final data = <String, dynamic>{'runs': runs};
    if (wicket != null) {
      data['wicket'] = true;
      data['dismissal'] = wicket;
    }
    return ev(CricketEngine.kBall, side, data);
  }

  ScoringEvent matchEnd() =>
      ev(CricketEngine.kMatchEnd, null, {'reason': 'Abandoned'});

  MatchProgress fold(List<ScoringEvent> log) =>
      engine.evaluate(sides: sides, rules: rules, events: log);

  group('win by runs (C1)', () {
    // Coast bats first and defends three; Dale managed only one.
    final log = <ScoringEvent>[
      toss(0, 'bat'),
      inningsStart(0),
      ball(0, 1),
      ball(0, 1),
      ball(0, 1),
      ball(0, 0),
      ball(0, 0),
      ball(0, 0),
      inningsStart(1),
      ball(1, 1),
      ball(1, 0),
      ball(1, 0),
      ball(1, 0),
      ball(1, 0),
      ball(1, 0),
    ];

    test('folds the totals submit compares against', () {
      final p = fold(log);
      // _cricket_fold_detail -> 'scoreValues' is [3, 1] in the SQL suite.
      expect(p.scoreValues, [3, 1]);
      expect(p.scoreDisplay, ['3/0', '1/0']);
      expect(p.winnerIndex, 0);
      expect(p.isComplete, isTrue);
      expect(p.state['innings'], 2);
    });

    test('a defence headline agrees on both sides', () {
      // The runs margin never touched the engine bug, so server and client match.
      expect(fold(log).resultLabel, 'Coast won by 2 runs');
    });

    test('one closed innings does not finish a two-innings match', () {
      final between = <ScoringEvent>[
        toss(0, 'bat'),
        inningsStart(0),
        ball(0, 1),
        ball(0, 1),
        ball(0, 1),
        ball(0, 0),
        ball(0, 0),
        ball(0, 0),
      ];
      final p = fold(between);
      expect(p.isComplete, isFalse);
      expect(p.state['open'], isFalse);
      expect(p.state['nextBatSide'], 1);
    });
  });

  group('win by wickets with unequal XIs (C2 — the margin regression)', () {
    // Coast names a full XI (cap 10); Dale only five, so Dale's own cap is 4.
    // Dale chases three down with one wicket in hand and four balls to spare.
    final log = <ScoringEvent>[
      lineup(0, 11),
      lineup(1, 5),
      toss(0, 'bat'),
      inningsStart(0),
      ball(0, 0),
      ball(0, 0),
      ball(0, 0),
      ball(0, 0),
      ball(0, 1),
      ball(0, 1),
      inningsStart(1),
      ball(1, 0, wicket: 'Bowled'),
      ball(1, 0, wicket: 'Caught'),
      ball(1, 0, wicket: 'LBW'),
      ball(1, 3),
    ];

    test('the squad sizes that seed the wicket caps agree', () {
      // _cricket_fold_detail -> 'state' -> 'battingSize' is [11, 5].
      expect(fold(log).state['battingSize'], [11, 5]);
    });

    test(
      'the gated values still agree so the real submit is never refused',
      () {
        final p = fold(log);
        // submit_match_result compares exactly these two against the SQL fold:
        expect(p.scoreValues, [2, 3]);
        expect(p.winnerIndex, 1);
        // and rewrites these from the fold, which also match:
        expect(p.scoreDisplay, ['2/0', '3/3']);
        expect(p.isComplete, isTrue);
      },
    );

    test('the engine still reports the buggy margin while the server fixes it', () {
      // CricketEngine reads the FIRST innings' cap: 10 - 3 = 7.
      expect(fold(log).resultLabel, 'Dale won by 7 wickets');
      // _cricket_fold_detail reads the CHASING innings' own cap: 4 - 3 = 1, so
      // the SQL suite asserts 'Dale won by 1 wickets' and submit_match_result
      // overwrites the caller's headline with the corrected one. The headline is
      // not part of the parity contract, which is exactly why a genuine scorer
      // submits successfully and still gets the fixed record.
    });
  });

  group('abandonment (C4)', () {
    final log = <ScoringEvent>[
      toss(0, 'bat'),
      inningsStart(0),
      ball(0, 1),
      matchEnd(),
    ];

    test('an early match_end completes with no winner', () {
      final p = fold(log);
      expect(p.isComplete, isTrue);
      expect(p.winnerIndex, -1);
      expect(p.resultLabel, '');
      expect(p.scoreDisplay, ['1/0', '-']);
      expect(p.state['ended'], isTrue);
    });
  });

  group('the server builds a subset of the engine state', () {
    test(
      'every key _cricket_fold_detail merges into the refusal is present',
      () {
        // A chase in progress: innings 1 is closed so a target exists, innings
        // 2 is open and the toss is recorded — the richest state the refusal
        // ever inspects. (The engine emits `target` only when it is non-null.)
        final state = fold(<ScoringEvent>[
          toss(0, 'bat'),
          inningsStart(0),
          ball(0, 1),
          ball(0, 1),
          ball(0, 1),
          ball(0, 0),
          ball(0, 0),
          ball(0, 0),
          inningsStart(1),
          ball(1, 0),
        ]).state;
        // These are the keys the SQL state object builds in 0026 and that
        // _cricket_event_refusal reads back. A rename on either side must fail
        // here rather than false-refuse a scorer.
        for (final key in const [
          'innings',
          'batSide',
          'nextBatSide',
          'open',
          'ended',
          'target',
          'battingSize',
          'toss',
        ]) {
          expect(state.containsKey(key), isTrue, reason: 'missing $key');
        }
      },
    );
  });
}
