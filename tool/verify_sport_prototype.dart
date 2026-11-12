import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';

void check(bool valid, String message) {
  if (!valid) throw StateError(message);
}

void main() {
  final now = DateTime(2026, 11, 12, 10);
  ScoringEvent event(
    String kind,
    int? side, {
    Map<String, dynamic> data = const {},
    int seconds = 0,
  }) => ScoringEvent(
    id: '$kind-$side-$seconds',
    kind: kind,
    side: side,
    data: data,
    at: now.add(Duration(seconds: seconds)),
    byAccountId: 'private-prototype',
  );
  MatchProgress evaluate(
    Sport sport,
    List<ScoringEvent> events, {
    String? format,
  }) => SportEngines.forSport(sport).evaluate(
    sides: ['A', 'B'],
    rules: SportEngines.rulesFor(
      sport,
      format ?? SportEngines.formatsFor(sport).first,
    ),
    events: events,
  );
  final cricket = evaluate(Sport.cricket, [
    event('ball', 0, data: {'runs': 4, 'batter': 'Ali', 'bowler': 'Zain'}),
    event('ball', 0, data: {'extra': 'wide', 'runs': 0}),
    event('ball', 0, data: {'extra': 'bye', 'runs': 1}),
  ]);
  check(cricket.scoreValues[0] == 6, 'Cricket extras total');
  check(
    cricket.contextChips.any((s) => s.contains('Over 0.2')),
    'Cricket legal deliveries',
  );
  final points = <ScoringEvent>[];
  for (var game = 0; game < 12; game++) {
    for (var point = 0; point < 4; point++) {
      points.add(event('point', game % 2));
    }
  }
  final tb = evaluate(Sport.padel, points);
  check(tb.state['inTiebreak'] == true, 'Padel tie-break at 6–6');
  check(tb.contextChips.contains('Service: A'), 'Padel first tie-break server');
  points.add(event('point', 0));
  check(
    evaluate(Sport.padel, points).contextChips.contains('Service: B'),
    'Tie-break service changes after first point',
  );
  points.addAll(List.generate(6, (_) => event('point', 0)));
  final padel = evaluate(Sport.padel, points);
  check(
    padel.isComplete && padel.winnerIndex == 0,
    'Padel tie-break completion',
  );
  check(
    (padel.state['completedSets'] as List).first[0] == 7,
    'Padel set tracker 7–6',
  );
  final rallies = [
    ...List.generate(5, (_) => event('rally', 0)),
    event('rally', 1),
  ];
  check(
    evaluate(Sport.badminton, rallies).state['server'] == 1,
    'Rally winner serves despite trailing',
  );
  final capped = [
    ...List.generate(
      29,
      (_) => [event('rally', 0), event('rally', 1)],
    ).expand((e) => e),
    event('rally', 0),
  ];
  final badminton = evaluate(Sport.badminton, capped);
  check(
    (badminton.state['completedGames'] as List).first[0] == 30,
    'Badminton 30 point cap',
  );
  final futsal = evaluate(Sport.futsal, [
    event('clock', null, data: {'action': 'start'}),
    event('goal', 0, data: {'half': 0}),
    event('foul', 0, data: {'half': 0}),
    event('yellow_card', 0, data: {'half': 0}),
    event('clock', null, data: {'action': 'stop'}, seconds: 61),
  ]);
  check(futsal.scoreValues[0] == 1, 'Discipline events do not change goals');
  check(
    futsal.state['periodElapsed'] == 61 && futsal.state['running'] == false,
    'Futsal persisted period clock',
  );
  final resumed = evaluate(Sport.futsal, [
    event('clock', null, data: {'action': 'start'}),
    event('clock', null, data: {'action': 'stop'}, seconds: 61),
    event('clock', null, data: {'action': 'resume'}, seconds: 120),
  ]);
  check(
    resumed.state['resumeAt'] ==
        now.add(const Duration(seconds: 120)).toIso8601String(),
    'Futsal resume anchor',
  );
  // ignore: avoid_print
  print(
    'Sport prototype checks passed: cricket extras, padel tie-break/service/tracker, badminton service/cap, futsal discipline/clock.',
  );
}
