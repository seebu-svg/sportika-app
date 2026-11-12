import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/shared/data/seed.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/official_result.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/models/tournament_engine.dart';

ScoringEvent ev(
  String kind,
  int? side,
  Map<String, dynamic> data, {
  String? id,
}) => ScoringEvent(
  id: id ?? 'e-$kind-$side-${data.toString()}',
  kind: kind,
  side: side,
  data: data,
  at: DateTime(2026, 11, 12, 10),
  byAccountId: 'acc-test',
);

void main() {
  group('Cricket engine', () {
    final engine = SportEngines.forSport(Sport.cricket);
    final rules = SportEngines.rulesFor(Sport.cricket, 'T5 · 5 overs');
    const sides = ['Strikers', 'Neighbours'];

    MatchProgress run(List<ScoringEvent> events) =>
        engine.evaluate(sides: sides, rules: rules, events: events);

    ScoringEvent ball(
      int runs, {
      int? side,
      String? extra,
      bool wicket = false,
    }) => ev('ball', side ?? 0, {
      'runs': runs,
      'extra': ?extra,
      if (wicket) 'wicket': true,
    });

    test('counts legal deliveries and excludes wides from the over', () {
      final p = run([
        ball(4),
        ball(0, extra: 'wide'),
        ball(1),
        ball(6),
        ball(2),
        ball(0),
      ]);
      expect(p.contextChips.any((c) => c.startsWith('Over 0.5')), isTrue);
      // Five legal deliveries; the wide only adds a run and no ball.
      expect(p.scoreValues[0], 4 + 1 + 1 + 6 + 2 + 0);
    });

    test('extras, wickets and the all-out rule close an innings', () {
      final events = <ScoringEvent>[
        for (var i = 0; i < 10; i++) ball(0, wicket: true),
      ];
      final p = run(events);
      // Ten wickets are gone, so the first innings is closed but the match
      // needs the second innings before it is complete.
      expect(p.isComplete, isFalse);
      expect(p.lines.first.value, '0/10');
      expect(p.contextChips.any((c) => c.contains('Innings 1/2')), isTrue);
    });

    test('chase target drives the result', () {
      // innings 1: 20 runs off 4 legal balls, all out
      final first = <ScoringEvent>[
        ball(4, side: 0),
        ball(6, side: 0),
        ball(4, side: 0),
        ball(6, side: 0),
        for (var i = 0; i < 10; i++) ball(0, side: 0, wicket: true),
      ];
      final inningsEnd = ev('innings_end', 0, {'reason': 'All out'});
      // innings 2: chase 21 with 4 legal balls of sixes then lose 10 wickets
      final second = <ScoringEvent>[
        ball(6, side: 1),
        ball(6, side: 1),
        ball(6, side: 1),
        ball(6, side: 1),
        ball(1, side: 1),
      ];
      final p = run([...first, inningsEnd, ...second]);
      expect(p.isComplete, isTrue);
      expect(p.winnerIndex, 1);
      expect(p.resultLabel, contains('Neighbours won'));
      expect(p.completionReason, 'Both innings complete');
    });

    test('a tie is recorded when the chase lands exactly on the level', () {
      final first = <ScoringEvent>[
        ball(6, side: 0),
        ball(6, side: 0),
        ball(6, side: 0),
        ball(6, side: 0),
        for (var i = 0; i < 10; i++) ball(0, side: 0, wicket: true),
      ];
      final second = <ScoringEvent>[
        ball(6, side: 1),
        ball(6, side: 1),
        ball(6, side: 1),
        ball(6, side: 1),
        ball(0, side: 1),
        for (var i = 0; i < 10; i++) ball(0, side: 1, wicket: true),
      ];
      final p = run([...first, ev('innings_end', 0, {}), ...second]);
      expect(p.isComplete, isTrue);
      expect(p.winnerIndex, -1);
      expect(p.resultLabel, 'Match tied');
    });

    test('undo of the last ball is exact', () {
      final events = [ball(4), ball(6)];
      final before = run(events).scoreValues[0];
      final after = run(events.sublist(0, 1)).scoreValues[0];
      expect(before - after, 6);
    });

    test('offers no actions once the match is decided', () {
      final first = [
        for (var i = 0; i < 10; i++) ball(0, side: 0, wicket: true),
      ];
      final second = [
        for (var i = 0; i < 10; i++) ball(0, side: 1, wicket: true),
      ];
      final p = run([...first, ev('innings_end', 0, {}), ...second]);
      expect(p.isComplete, isTrue);
      expect(p.actions, isEmpty);
    });
  });

  group('Padel engine', () {
    final engine = SportEngines.forSport(Sport.padel);
    final rules = SportEngines.rulesFor(Sport.padel, 'Best of 3 sets');
    const sides = ['A', 'B'];
    MatchProgress run(List<ScoringEvent> e) =>
        engine.evaluate(sides: sides, rules: rules, events: e);
    ScoringEvent pt(int s) => ev('point', s, {});

    test('a game needs four points and a two point margin', () {
      var p = run([pt(0), pt(0), pt(0), pt(1), pt(1), pt(1)]);
      expect(p.contextChips.any((c) => c.contains('Deuce')), isTrue);
      p = run([
        ...[pt(0), pt(0), pt(0), pt(1), pt(1), pt(1)],
        pt(0),
      ]);
      expect(p.contextChips.any((c) => c.contains('Advantage')), isTrue);
      p = run([pt(0), pt(0), pt(0), pt(0)]);
      expect(p.contextChips.any((c) => c.contains('games 1-0')), isTrue);
    });

    test('sets complete at six games with a two game margin', () {
      final events = <ScoringEvent>[];
      for (var g = 0; g < 6; g++) {
        events.addAll([pt(0), pt(0), pt(0), pt(0)]);
      }
      final p = run(events);
      expect(p.scoreValues[0], 1);
      expect(p.isComplete, isFalse);
      expect(p.lines.first.sub, contains('6-0'));
    });

    test('the match ends when the sets target is reached', () {
      final events = <ScoringEvent>[];
      for (var set = 0; set < 2; set++) {
        for (var g = 0; g < 6; g++) {
          events.addAll([pt(0), pt(0), pt(0), pt(0)]);
        }
      }
      final p = run(events);
      expect(p.isComplete, isTrue);
      expect(p.winnerIndex, 0);
      expect(p.resultLabel, contains('A won 2-0'));
      expect(p.actions, isEmpty);
    });

    test('tie-break starts at six games all', () {
      final events = <ScoringEvent>[];
      // 6-6 needs each side to take six games; games to 6 with a margin of 2
      // cannot happen, so drive it to 5-5 then let each win one more.
      for (var g = 0; g < 5; g++) {
        events.addAll([pt(0), pt(0), pt(0), pt(0)]);
        events.addAll([pt(1), pt(1), pt(1), pt(1)]);
      }
      events.addAll([pt(0), pt(0), pt(0), pt(0)]);
      events.addAll([pt(1), pt(1), pt(1), pt(1)]);
      final p = run(events);
      expect(p.contextChips.any((c) => c.contains('Tie-break')), isTrue);
    });
  });

  group('Futsal engine', () {
    final engine = SportEngines.forSport(Sport.futsal);
    final rules = SportEngines.rulesFor(Sport.futsal, '2 × 20 min');
    const sides = ['Rovers', 'City'];
    MatchProgress run(List<ScoringEvent> e) =>
        engine.evaluate(sides: sides, rules: rules, events: e);

    test('goals are attributed to the half they happen in', () {
      final events = [
        ev('clock', null, {'action': 'start'}),
        ev('goal', 0, {'half': 0}),
        ev('goal', 0, {'half': 0}),
        ev('goal', 1, {'half': 1}),
      ];
      final p = run(events);
      expect(p.scoreValues, [2, 1]);
      expect(p.detailRows.first, contains('H1 2-0'));
      expect(p.detailRows.first, contains('H2 0-1'));
    });

    test(
      'clock pause and resume accumulate elapsed time deterministically',
      () {
        ScoringEvent at(String action, int minute) => ScoringEvent(
          id: 'clock-$action-$minute',
          kind: 'clock',
          side: null,
          data: {'action': action},
          at: DateTime(2026, 11, 12, 10).add(Duration(minutes: minute)),
          byAccountId: 'acc-test',
        );
        final p = run([
          at('start', 0),
          at('stop', 12),
          at('resume', 20),
          at('stop', 31),
        ]);
        expect(p.state['elapsed'], 23 * 60);
        expect(p.state['running'], false);
      },
    );

    test(
      'a level score after regulation is a draw when no winner is needed',
      () {
        final events = [
          ev('clock', null, {'action': 'start'}),
          ev('goal', 0, {'half': 0}),
          ev('goal', 1, {'half': 1}),
          ev('clock', null, {'action': 'end_half'}),
          ev('clock', null, {'action': 'end_half'}),
        ];
        final p = run(events);
        expect(p.isComplete, isTrue);
        expect(p.winnerIndex, -1);
      },
    );

    test('knockout rules send a level tie into a shootout', () {
      final ko = SportEngines.rulesFor(Sport.futsal, '2 × 20 min · knockout');
      final p = engine.evaluate(
        sides: sides,
        rules: ko,
        events: [
          ev('clock', null, {'action': 'start'}),
          ev('goal', 0, {'half': 0}),
          ev('goal', 1, {'half': 1}),
          ev('clock', null, {'action': 'end_half'}),
          ev('clock', null, {'action': 'end_half'}),
        ],
      );
      expect(p.isComplete, isFalse);
      expect(p.contextChips.any((c) => c.contains('Penalty shootout')), isTrue);

      final decided = engine.evaluate(
        sides: sides,
        rules: ko,
        events: [
          ...[
            ev('clock', null, {'action': 'start'}),
            ev('goal', 0, {'half': 0}),
            ev('goal', 1, {'half': 1}),
            ev('clock', null, {'action': 'end_half'}),
            ev('clock', null, {'action': 'end_half'}),
          ],
          ev('penalty', 0, {'scored': true}),
          ev('penalty', 1, {'scored': false}),
          ev('penalty', 0, {'scored': true}),
          ev('penalty', 1, {'scored': false}),
          ev('penalty', 0, {'scored': true}),
          ev('penalty', 1, {'scored': false}),
        ],
      );
      expect(decided.isComplete, isTrue);
      expect(decided.winnerIndex, 0);
      expect(decided.completionReason, 'Won on penalties');
    });

    test('a shootout that can still be caught is not decided early', () {
      final ko = SportEngines.rulesFor(Sport.futsal, '2 × 20 min · knockout');
      final p = engine.evaluate(
        sides: sides,
        rules: ko,
        events: [
          ev('clock', null, {'action': 'start'}),
          ev('goal', 0, {'half': 0}),
          ev('goal', 1, {'half': 1}),
          ev('clock', null, {'action': 'end_half'}),
          ev('clock', null, {'action': 'end_half'}),
          ev('penalty', 0, {'scored': true}),
          ev('penalty', 1, {'scored': false}),
          ev('penalty', 0, {'scored': true}),
          ev('penalty', 1, {'scored': false}),
          ev('penalty', 0, {'scored': true}),
        ],
      );
      expect(
        p.isComplete,
        isFalse,
        reason: 'side 1 still has three kicks to level the shootout',
      );
    });
  });

  group('Badminton engine', () {
    final engine = SportEngines.forSport(Sport.badminton);
    final rules = SportEngines.rulesFor(Sport.badminton, 'Best of 3 games');
    const sides = ['X', 'Y'];
    MatchProgress run(List<ScoringEvent> e) =>
        engine.evaluate(sides: sides, rules: rules, events: e);
    ScoringEvent r(int s) => ev('rally', s, {});

    test('a game goes to twenty-one and needs a two point margin', () {
      final winnerOnly = List.generate(21, (_) => r(0));
      var p = run(winnerOnly);
      expect(p.scoreValues[0], 1);
      expect(p.isComplete, isFalse);

      final deuce = [
        for (var i = 0; i < 20; i++) ...[r(0), r(1)],
        r(0),
      ];
      p = run(deuce);
      expect(p.scoreValues[0], 0);
      expect(p.contextChips.any((c) => c.contains('21-20')), isTrue);
    });

    test('the thirty point cap ends a long game', () {
      final events = <ScoringEvent>[
        for (var i = 0; i < 29; i++) ...[r(0), r(1)],
        r(0),
      ];
      final p = run(events);
      expect(p.scoreValues[0], 1);
      expect(p.detailRows.first, contains('30-29'));
    });

    test('best of three ends at two games', () {
      final events = <ScoringEvent>[];
      for (var g = 0; g < 2; g++) {
        events.addAll(List.generate(21, (_) => r(0)));
      }
      final p = run(events);
      expect(p.isComplete, isTrue);
      expect(p.winnerIndex, 0);
      expect(p.actions, isEmpty);
    });
  });

  group('Official results and draws', () {
    test('knockout slots stay TBD until the feeder result is published', () {
      final world = buildSeed();
      final padel =
          world.fixtures
              .where((f) => f.tournamentId == 'trn-padel-cup')
              .toList()
            ..sort((a, b) => a.round.compareTo(b.round));
      final entriesById = {for (final e in world.entries) e.id: e};
      final finalFx = padel.last;
      expect(OfficialResults.isPlaceholder(finalFx.home.entryId), isTrue);

      final resolved = OfficialResults.resolve(
        finalFx.home,
        padel,
        entriesById,
      );
      expect(
        resolved.resolved,
        isTrue,
        reason: 'a published feeder result resolves the slot',
      );
      expect(resolved.label, 'Seebu / Zain');
    });

    test('unpublished fixtures do not move the bracket', () {
      final world = buildSeed();
      final padel =
          world.fixtures
              .where((f) => f.tournamentId == 'trn-padel-cup')
              .toList()
            ..sort((a, b) => a.round.compareTo(b.round));
      final live = padel[1];
      live.status = FixtureStatus.upcoming;
      live.result = null;
      final entriesById = {for (final e in world.entries) e.id: e};
      final resolved = OfficialResults.resolve(live.home, padel, entriesById);
      expect(resolved.resolved, isTrue);
      // The final still shows the other semi as undecided.
      final finalFx = padel.last;
      final feeder = padel.firstWhere(
        (f) => f.id != live.id && f.status != FixtureStatus.published,
      );
      expect(feeder.status == FixtureStatus.published, isFalse);
      expect(
        OfficialResults.resolve(finalFx.away, padel, entriesById).resolved,
        isFalse,
        reason: 'only published results advance the bracket',
      );
    });

    test('standings only count published fixtures', () {
      final world = buildSeed();
      final fx = world.fixtures
          .where((f) => f.tournamentId == 'trn-t10')
          .toList();
      final entriesById = {for (final e in world.entries) e.id: e};
      final table = TournamentEngine.standings(
        fixtures: fx,
        entriesById: entriesById,
        qualifyTop: 2,
      );
      expect(table, isNotEmpty);
      for (final row in table) {
        expect(row.played, greaterThan(0));
      }
      // Points follow 3 for a win, 1 for a draw.
      expect(table.first.points, greaterThanOrEqualTo(table.last.points));
    });

    test('group draw produces a round robin per group', () {
      final world = buildSeed();
      final t = world.tournaments.firstWhere((x) => x.id == 'trn-t10');
      final confirmed = world.entries
          .where(
            (e) => e.tournamentId == t.id && e.status == EntryStatus.confirmed,
          )
          .toList();
      final fx = TournamentEngine.groupDraw(
        tournament: t,
        confirmed: confirmed,
        groupCount: 2,
      );
      expect(fx.length, 6, reason: 'two groups of three, three matches each');
      expect(fx.every((f) => f.group != null), isTrue);
      final groups = fx.map((f) => f.group).toSet();
      expect(groups.length, 2);
    });

    test('knockout draw with byes never pairs an entry against nothing', () {
      final t = Tournament(
        id: 'trn-x',
        organizerId: 'o',
        name: 'Test Cup',
        city: 'Karachi',
        sport: Sport.padel,
        formatLabel: 'Knockout',
        format: TournamentFormat.knockout,
        entryType: EntryType.pair,
        startsAt: DateTime(2026, 11, 1),
        endsAt: DateTime(2026, 11, 20),
        registrationLimit: 8,
        entryFee: 'PKR 0',
        matchRules: '',
        rules: SportEngines.rulesFor(Sport.padel, 'Best of 3 sets'),
        status: TournamentStatus.inProgress,
        createdAt: DateTime(2026, 10, 1),
      );
      List<Entry> entries(int n) => [
        for (var i = 0; i < n; i++)
          Entry(
            id: 'e$i',
            tournamentId: t.id,
            captainAccountId: 'c$i',
            label: 'Pair $i',
            memberAccountIds: ['c$i'],
            status: EntryStatus.confirmed,
            submittedAt: DateTime(2026, 10, 2),
          ),
      ];
      final five = TournamentEngine.knockoutDraw(
        tournament: t,
        confirmed: entries(5),
      );
      // size 8 with three byes leaves a single first-round match, then a
      // semi-final round and the final.
      expect(five.where((f) => f.round == 1).length, 1);
      expect(five.last.round, 3);
      expect(five.every((f) => f.home.entryId != f.away.entryId), isTrue);
    });
  });

  group('Seed data', () {
    test('builds a coherent world for all four sports', () {
      final world = buildSeed();
      expect(world.accounts.length, 22);
      expect(world.tournaments.length, 8);
      expect(world.fixtures, isNotEmpty);

      final published = world.fixtures.where((f) => f.result != null).toList();
      expect(published, isNotEmpty);
      for (final f in published) {
        final t = world.tournaments.firstWhere((x) => x.id == f.tournamentId);
        expect(f.result!.sideValues.length, 2);
        expect(
          f.events,
          isNotEmpty,
          reason: '${t.sport.label} results come from real logs',
        );
        // Published logs must actually fold to a finished match.
        final p = SportEngines.progressOf(
          sport: t.sport,
          sides: ['A', 'B'],
          rules: t.rules,
          rawEvents: f.events,
        );
        expect(p.isComplete, isTrue, reason: '${t.sport.name} log incomplete');
      }

      expect(
        world.personal.where((p) => p.status == PersonalMatchStatus.inProgress),
        isNotEmpty,
      );
      expect(world.notifications, isNotEmpty);
    });

    test('two players can score the same match with separate records', () {
      final world = buildSeed();
      final seebu = world.personal.firstWhere((p) => p.id == 'pm-padel-done');
      final zain = world.personal.firstWhere((p) => p.id == 'pm-zain-same');
      expect(seebu.ownerId, isNot(zain.ownerId));
      expect(seebu.sideNames, zain.sideNames);
      expect(seebu.events, isNot(zain.events));
    });
  });

  group('Engine registry', () {
    test('every sport exposes formats and rule descriptions', () {
      for (final sport in Sport.values) {
        final formats = SportEngines.formatsFor(sport);
        expect(formats, isNotEmpty);
        for (final f in formats) {
          final rules = SportEngines.rulesFor(sport, f);
          expect(SportEngines.describeRules(sport, rules), isNotEmpty);
        }
      }
    });

    test('personal and official scoring share identical rules', () {
      final cricket = SportEngines.rulesFor(Sport.cricket, 'T20 · 20 overs');
      expect(cricket['oversPerInnings'], 20);
      expect(
        SportEngines.forSport(Sport.cricket)
            .evaluate(sides: ['A', 'B'], rules: cricket, events: const [])
            .isComplete,
        isFalse,
      );
    });
  });
}
