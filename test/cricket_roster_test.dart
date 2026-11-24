// The roster projection: who is on strike, who comes in next and who never
// batted. Everything here is replayed from the delivery log, so the tests pin
// the three cases the workspace depends on — an odd run, an over end and a
// wicket — plus the voided entry that must not survive an undo.

import 'package:flutter_test/flutter_test.dart';

import 'package:sportika/features/matches/scoring/cricket_roster.dart';
import 'package:sportika/features/personal_games/scoring/cricket/cricket.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';

void main() {
  const names = ['Ann', 'Ben', 'Cal', 'Dee'];
  const ids = ['acc-a', 'acc-b', 'acc-c', 'acc-d'];

  SportMatch team({
    List<MatchEvent> events = const [],
    bool withXi = true,
    int xiSize = 4,
  }) {
    var seq = 0;
    MatchEvent at(String kind, int? side, Map<String, dynamic> data) {
      seq++;
      return MatchEvent(
        id: 'ev-$seq',
        seq: seq,
        clientId: 'client-$seq',
        kind: kind,
        side: side,
        data: data,
        at: DateTime.utc(2026, 5, 1).add(Duration(seconds: seq)),
        byAccountId: 'organizer',
      );
    }

    final log = [
      if (withXi)
        at(CricketEngine.kLineup, 0, {'players': ids.take(xiSize).toList()}),
      ...events,
    ];
    final match = SportMatch(
      id: 'roster',
      sport: Sport.cricket,
      formatLabel: 'T2',
      rules: const {'oversPerInnings': 2, 'wicketsPerInnings': 3},
      title: 'Roster test',
      venue: 'Ground one',
      scheduledAt: DateTime.utc(2026, 5, 1, 18),
      visibility: MatchVisibility.public,
      organizerId: 'organizer',
      status: FixtureStatus.live,
      sideNames: const ['Alpha', 'Bravo'],
      discipline: MatchDiscipline.team,
      capacity: 22,
      createdAt: DateTime.utc(2026, 4, 30),
      participants: [
        for (var i = 0; i < 4; i++)
          MatchParticipant(
            profileId: ids[i],
            displayName: names[i],
            side: 0,
            status: MatchParticipantStatus.accepted,
          ),
        MatchParticipant(
          profileId: 'acc-bowl',
          displayName: 'Cy',
          side: 1,
          status: MatchParticipantStatus.accepted,
        ),
      ],
      events: log,
    )..eventCount = log.length;
    return match;
  }

  MatchEvent ball(
    int seq,
    int runs, {
    String striker = 'Ann',
    String nonStriker = 'Ben',
    bool wicket = false,
    String? dismissed,
    String extra = '',
    bool voided = false,
  }) => MatchEvent(
    id: 'ball-$seq',
    seq: seq,
    clientId: 'ball-client-$seq',
    kind: CricketEngine.kBall,
    side: 0,
    data: {
      'runs': runs,
      'striker': striker,
      'nonStriker': nonStriker,
      'bowler': 'Cy',
      if (extra.isNotEmpty) 'extra': extra,
      if (wicket) 'wicket': true,
      if (wicket) 'dismissal': 'Bowled',
      'dismissedBatter': ?dismissed,
    },
    at: DateTime.utc(2026, 5, 1).add(Duration(seconds: seq)),
    byAccountId: 'organizer',
    voided: voided,
  );

  group('the order', () {
    test('reads the named XI in batting order', () {
      final match = team();
      expect(CricketRoster.order(match, 0).map((p) => p.name), names);
      expect(CricketRoster.hasLineup(match, 0), isTrue);
      expect(CricketRoster.hasLineup(match, 1), isFalse);
    });

    test('falls back to the accepted roster when no XI was named', () {
      final match = team(withXi: false);
      expect(CricketRoster.hasLineup(match, 0), isFalse);
      expect(CricketRoster.order(match, 0).map((p) => p.name), names);
    });
  });

  group('the strike', () {
    test('seeds the opening pair from a named XI', () {
      final strike = CricketRoster.strike(team(), 0);
      expect(strike.striker, 'Ann');
      expect(strike.nonStriker, 'Ben');
      expect(strike.bowler, isNull);
      expect(strike.legalBalls, 0);
    });

    test('leaves the opening pair to the scorer when no XI is named', () {
      final strike = CricketRoster.strike(team(withXi: false), 0);
      expect(strike.striker, isNull);
      expect(strike.nonStriker, isNull);
    });

    test('swaps the strike on an odd number of runs', () {
      final strike = CricketRoster.strike(team(), 0); // XI seeds Ann/Ben
      expect(strike.striker, 'Ann');
      final match = team(events: [ball(2, 1)]);
      final after = CricketRoster.strike(match, 0);
      expect(after.striker, 'Ben');
      expect(after.nonStriker, 'Ann');
      expect(after.bowler, 'Cy');
    });

    test('changes ends and clears the bowler at the end of an over', () {
      final match = team(
        events: [
          for (var i = 0; i < 6; i++)
            ball(i + 2, 0, striker: 'Ann', nonStriker: 'Ben'),
        ],
      );
      final strike = CricketRoster.strike(match, 0);
      expect(strike.legalBalls, 6);
      expect(strike.newOver, isTrue);
      expect(strike.striker, 'Ben');
      expect(strike.nonStriker, 'Ann');
      expect(strike.bowler, isNull);
    });

    test('a wide does not end the over', () {
      final match = team(
        events: [
          for (var i = 0; i < 6; i++) ball(i + 2, 0),
          ball(9, 0, extra: 'wide'),
        ],
      );
      final strike = CricketRoster.strike(match, 0);
      expect(strike.legalBalls, 6);
      expect(strike.newOver, isFalse);
    });

    test('installs the next XI batter after a wicket', () {
      final match = team(events: [ball(2, 0, wicket: true, dismissed: 'Ann')]);
      final strike = CricketRoster.strike(match, 0);
      expect(strike.striker, 'Cal');
      expect(strike.nonStriker, 'Ben');
    });

    test('ignores a withdrawn delivery', () {
      final match = team(events: [ball(2, 1), ball(3, 1, voided: true)]);
      final strike = CricketRoster.strike(match, 0);
      // Only the first ball counts, so the single still swapped the strike.
      expect(strike.striker, 'Ben');
      expect(strike.nonStriker, 'Ann');
    });
  });

  test('lists the XI members who never came out to bat', () {
    final match = team(
      events: [
        ball(2, 1),
        ball(3, 2, striker: 'Cal', nonStriker: 'Ann'),
      ],
    );
    final recorded = {
      for (final e in match.events.where(
        (e) => e.kind == CricketEngine.kBall,
      )) ...[e.data['striker'] as String, e.data['nonStriker'] as String],
    };
    expect(CricketRoster.didNotBat(match, 0, recorded), ['Dee']);
    expect(CricketRoster.didNotBat(team(withXi: false), 0, recorded), isEmpty);
  });
}
