// Parity between the two folds that decide a futsal result.
//
// The sequences below are the literal ones supabase/tests/futsal_scoring_test.sql
// writes through record_match_event. That suite asserts what the server folds;
// this one asserts that FutsalEngine folds the same log to the same goals, the
// same winner and the same shootout tallies. If _futsal_fold_detail and
// FutsalEngine ever drift, one of the two suites goes red instead of the app
// and the database disagreeing in silence.

import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/futsal/futsal.dart';

void main() {
  final engine = FutsalEngine();
  final kickOff = DateTime.utc(2026, 4, 1, 18);

  // An event stamped p_minute minutes after kick-off, the way recorded_at
  // stamps a real log. The clock folds the gaps between stamps, so the minute
  // offsets are what make elapsed time meaningful here.
  ScoringEvent at(
    int minute,
    String kind,
    int? side, [
    Map<String, dynamic> data = const {},
  ]) => ScoringEvent(
    id: '$kind-$minute-$side',
    kind: kind,
    side: side,
    data: data,
    at: kickOff.add(Duration(minutes: minute)),
    byAccountId: 'organizer',
  );

  ScoringEvent clock(int minute, String action) =>
      at(minute, 'clock', null, {'action': action});

  ScoringEvent goal(int minute, int side, {int half = 0, String? type}) =>
      at(minute, 'goal', side, {'half': half, 'goalType': type ?? 'regular'});

  ScoringEvent kick(int minute, int side, bool scored) =>
      at(minute, 'penalty', side, {'scored': scored});

  MatchProgress fold(List<ScoringEvent> events, String format) =>
      engine.evaluate(
        sides: ['North Five', 'South Five'],
        rules: engine.rulesForFormat(format),
        events: events,
      );

  group('regulation', () {
    // The F1 log from the SQL suite: five goals across both halves, a card, a
    // foul and a substitution, all of which must not move the score.
    final log = <ScoringEvent>[
      clock(0, 'start'),
      goal(3, 0),
      goal(7, 1),
      goal(11, 0),
      goal(14, 0),
      goal(16, 0, type: 'ownGoal'),
      at(18, 'card', 1, {'colour': 'yellow', 'half': 0}),
      at(19, 'foul', 1, {'half': 0}),
      at(19, 'substitution', 1, {'inId': 'b7', 'outId': 'b6', 'half': 0}),
      clock(20, 'end_half'),
      clock(25, 'resume'),
      goal(30, 0, half: 1),
      clock(45, 'end_half'),
    ];

    test('folds the same five goals and the same winner as the server', () {
      final progress = fold(log, '2 × 20 min');
      // submit_match_result stores these two strings; the SQL suite asserts
      // they read ["5", "1"] whatever the caller sent.
      expect(progress.scoreDisplay, ['5', '1']);
      expect(progress.scoreValues, [5, 1]);
      expect(progress.isComplete, isTrue);
      expect(progress.winnerIndex, 0);
      expect(progress.completionReason, 'Regulation complete');
      expect(progress.state['phase'], 'complete');
    });

    test('keeps the per-half buckets the report and the SQL fold print', () {
      final progress = fold(log, '2 × 20 min');
      // _futsal_fold_detail returns byHalf [[4, 1], [1, 0]].
      expect(progress.lines[0].sub, 'Half 1 4 · Half 2 1');
      expect(progress.lines[1].sub, 'Half 1 1 · Half 2 0');
    });

    test(
      'banks the played minutes from the stamps, not from the wall clock',
      () {
        final progress = fold(log, '2 × 20 min');
        // 20 minutes in the first half plus 20 in the second.
        expect(progress.state['elapsed'], 40 * 60);
        expect(progress.state['half'], 2);
        expect(progress.state['periods'], 2);
      },
    );
  });

  group('shootout decided early', () {
    // The F2 log: level after regulation, no extra time, so straight to kicks.
    final log = <ScoringEvent>[
      clock(0, 'start'),
      clock(20, 'end_half'),
      clock(25, 'resume'),
      clock(45, 'end_half'),
    ];

    test('leaves a level knockout at the shootout', () {
      expect(fold(log, '2 × 20 min · knockout').state['phase'], 'shootout');
      expect(fold(log, '2 × 20 min · knockout').isComplete, isFalse);
    });

    test('ignores a goal logged after the shootout began', () {
      // The server refuses the write; the fold must also refuse to count it in
      // case the row exists from an older build.
      final withGoal = [...log, goal(46, 0, half: 1)];
      final progress = fold(withGoal, '2 × 20 min · knockout');
      expect(progress.scoreDisplay, ['0', '0']);
      expect(progress.state['phase'], 'shootout');
    });

    test('decides 4-1 before the fifth kick of the second side', () {
      // _tap_kick order in the SQL suite: A, B, A, B, A, B, A.
      final kicks = <ScoringEvent>[
        ...log,
        kick(46, 0, true),
        kick(47, 1, true),
        kick(48, 0, true),
        kick(49, 1, false),
        kick(50, 0, true),
        kick(51, 1, false),
        kick(52, 0, true),
      ];

      final progress = fold(kicks, '2 × 20 min · knockout');
      expect(progress.state['shootoutScores'], [4, 1]);
      expect(progress.state['shootoutTaken'], [4, 3]);
      expect(progress.isComplete, isTrue);
      expect(progress.winnerIndex, 0);
      expect(progress.completionReason, 'Won on penalties');
      // The match itself is still 0-0: penalties never enter the score line.
      expect(progress.scoreDisplay, ['0', '0']);
    });
  });

  group('extra time then sudden death', () {
    // The F3 log: tied after regulation, two extra halves, still tied, then
    // five kicks each at 5-5 and one more pair.
    final log = <ScoringEvent>[
      clock(0, 'start'),
      clock(20, 'end_half'),
      clock(25, 'resume'),
      clock(45, 'end_half'),
    ];

    test('plays the extra halves instead of shooting out', () {
      expect(
        fold(log, '2 × 20 min · extra time & penalties').state['phase'],
        'halfTime',
      );
      final inExtra = [...log, clock(50, 'resume')];
      final progress = fold(inExtra, '2 × 20 min · extra time & penalties');
      expect(progress.state['extraTime'], isTrue);
      expect(progress.state['periodMinutes'], 5);
      expect(progress.state['phase'], 'running');
    });

    test('reaches the shootout only after both extra halves', () {
      final throughExtra = [
        ...log,
        clock(50, 'resume'),
        clock(55, 'end_half'),
        clock(56, 'resume'),
        clock(61, 'end_half'),
      ];
      final progress = fold(
        throughExtra,
        '2 × 20 min · extra time & penalties',
      );
      expect(progress.state['phase'], 'shootout');
      expect(progress.isComplete, isFalse);
    });

    test('breaks a 5-5 shootout in sudden death', () {
      final kicks = <ScoringEvent>[
        ...log,
        clock(50, 'resume'),
        clock(55, 'end_half'),
        clock(56, 'resume'),
        clock(61, 'end_half'),
      ];
      for (var i = 0; i < 5; i++) {
        kicks.add(kick(62 + i * 2, 0, true));
        kicks.add(kick(63 + i * 2, 1, true));
      }
      final tied = fold(kicks, '2 × 20 min · extra time & penalties');
      expect(tied.state['shootoutScores'], [5, 5]);
      expect(tied.state['phase'], 'shootout');
      expect(tied.isComplete, isFalse);

      kicks.add(kick(74, 0, true));
      expect(
        fold(kicks, '2 × 20 min · extra time & penalties').state['phase'],
        'shootout',
        reason: 'one scored kick alone decides nothing',
      );

      kicks.add(kick(75, 1, false));
      final decided = fold(kicks, '2 × 20 min · extra time & penalties');
      expect(decided.state['shootoutTaken'], [6, 6]);
      expect(decided.state['shootoutScores'], [6, 5]);
      expect(decided.isComplete, isTrue);
      expect(decided.winnerIndex, 0);
      expect(decided.scoreDisplay, ['0', '0']);
    });
  });

  group('abandonment', () {
    // The F4 log: one goal to side B, then the scorer ends it early.
    final log = <ScoringEvent>[
      clock(0, 'start'),
      goal(4, 1),
      clock(6, 'end_match'),
    ];

    test('completes an unfinished match at the end_match entry', () {
      final progress = fold(log, '2 × 20 min');
      expect(progress.state['phase'], 'complete');
      expect(progress.completionReason, 'Match ended by scorer/organizer');
      expect(progress.winnerIndex, 1);
      // submit_match_result would store these strings.
      expect(progress.scoreDisplay, ['0', '1']);
    });

    test('hands the win to whoever led when it was ended', () {
      final level = <ScoringEvent>[clock(0, 'start'), clock(6, 'end_match')];
      final progress = fold(level, '2 × 20 min');
      expect(progress.isComplete, isTrue);
      expect(progress.winnerIndex, -1);
      expect(progress.resultLabel, 'Drawn');
    });
  });

  group('the two folds agree on the shape of the state', () {
    test('every key _futsal_fold_detail builds has a Dart twin', () {
      final state = fold(<ScoringEvent>[], '2 × 20 min').state;
      // These are the keys jsonb_build_object writes in 0021. A rename on
      // either side has to fail here, not at runtime.
      for (final key in const [
        'phase',
        'half',
        'periodElapsed',
        'periodMinutes',
        'periods',
        'shootoutTaken',
        'shootoutScores',
        'elapsed',
        'running',
        'extraTime',
      ]) {
        expect(state.containsKey(key), isTrue, reason: 'missing $key');
      }
      expect(state['phase'], 'pre');
      expect(state['half'], 1);
      expect(state['periods'], 2);
    });

    test('a blank rules map still folds as two 20-minute halves', () {
      final progress = engine.evaluate(
        sides: ['A', 'B'],
        rules: const {},
        events: [clock(0, 'start')],
      );
      expect(progress.state['periods'], 2);
      expect(progress.state['periodMinutes'], 20);
      expect(progress.state['phase'], 'running');
    });
  });
}
