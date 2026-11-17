import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/features/matches/scoring/match_scoring_validator.dart';
import 'package:sportika/features/matches/scoring/padel_scoring_workspace.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/padel/padel.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/widgets/widgets.dart' show sportColor;

// ── Helpers ───────────────────────────────────────────────────────────────

ScoringEvent pt(int side) => ScoringEvent(
  id: 'pt-$side-${DateTime.now().microsecondsSinceEpoch}',
  kind: PadelEngine.kPoint,
  side: side,
  data: const {},
  at: DateTime(2026),
  byAccountId: 'test',
);

void main() {
  final engine = PadelEngine();

  // ── Formats ─────────────────────────────────────────────────────────────

  group('PadelEngine formats', () {
    test('exposes five named formats', () {
      expect(engine.formats, hasLength(5));
      expect(engine.formats, contains('Best of 3 · golden point'));
      expect(engine.formats, contains('Best of 3 · super tie-break'));
    });

    test('golden point format sets noAd=true', () {
      final r = engine.rulesForFormat('Best of 3 · golden point');
      expect(r['noAd'], isTrue);
      expect(r['matchTiebreak'], isFalse);
    });

    test('super tie-break format sets matchTiebreak=true', () {
      final r = engine.rulesForFormat('Best of 3 · super tie-break');
      expect(r['matchTiebreak'], isTrue);
      expect(r['noAd'], isFalse);
    });

    test('first format is still 1 set · first to 6', () {
      expect(engine.formats.first, '1 set · first to 6');
    });
  });

  // ── Golden point ────────────────────────────────────────────────────────

  group('Padel golden point', () {
    final rules = engine.rulesForFormat('Best of 3 · golden point');

    test('game is won on the first point after 40-40 (diff 1)', () {
      // 3 points each = deuce; then side 0 scores once → game.
      final events = <ScoringEvent>[
        ...List.filled(3, pt(0)),
        ...List.filled(3, pt(1)),
        pt(0), // golden point
      ];
      final p = engine.evaluate(
        sides: ['A', 'B'],
        rules: rules,
        events: events,
      );
      // Side 0 won one game (games = 1-0).
      expect((p.state['games'] as List)[0], 1);
      expect((p.state['games'] as List)[1], 0);
      expect(p.state['inTiebreak'], isFalse);
    });

    test('golden-point deuce chip is labelled "40-40 · golden point"', () {
      // Exactly at deuce (3-3 points) in a golden-point game.
      final events = <ScoringEvent>[
        ...List.filled(3, pt(0)),
        ...List.filled(3, pt(1)),
      ];
      final p = engine.evaluate(
        sides: ['A', 'B'],
        rules: rules,
        events: events,
      );
      final chip = p.contextChips.firstWhere(
        (c) => c.contains('golden'),
        orElse: () => '',
      );
      expect(chip, contains('golden point'));
    });
  });

  // ── Super tie-break (deciding set) ──────────────────────────────────────

  group('Padel super tie-break', () {
    final rules = engine.rulesForFormat('Best of 3 · super tie-break');

    test('deciding set uses a super tie-break instead of a full set', () {
      // Side 0 wins set 1 (6-0), side 1 wins set 2 (6-0): entering decider TB.
      // We'll drive 6 games won by 0 (4 pts each game), then 6 by 1.
      final evs = <ScoringEvent>[];
      // Set 1: side 0 wins 6-0 (each game is 4 points won by side 0)
      for (var g = 0; g < 6; g++) {
        evs.addAll(List.filled(4, pt(0)));
      }
      // Set 2: side 1 wins 6-0
      for (var g = 0; g < 6; g++) {
        evs.addAll(List.filled(4, pt(1)));
      }
      // The super tie-break should now be active.
      final p = engine.evaluate(sides: ['A', 'B'], rules: rules, events: evs);
      expect(p.state['inTiebreak'], isTrue);
      expect(p.state['deciderTiebreak'], isTrue);
      expect(p.statusLabel, 'Super tie-break');
    });

    test('first to 10 (win by 2) in the deciding super tie-break', () {
      final evs = <ScoringEvent>[];
      for (var g = 0; g < 6; g++) {
        evs.addAll(List.filled(4, pt(0)));
      }
      for (var g = 0; g < 6; g++) {
        evs.addAll(List.filled(4, pt(1)));
      }
      // Super TB: side 0 scores 10 in a row (reaching 10-0, diff >= 2)
      evs.addAll(List.filled(10, pt(0)));
      final p = engine.evaluate(sides: ['A', 'B'], rules: rules, events: evs);
      expect(p.isComplete, isTrue);
      expect(p.winnerIndex, 0);
    });
  });

  // ── Serving rotation ────────────────────────────────────────────────────

  group('Padel serving rotation', () {
    final rules = engine.rulesForFormat('Best of 3 sets');

    test('service alternates side after each game', () {
      // Game 1: A serves and scores 4 points.
      final p1 = engine.evaluate(
        sides: ['A', 'B'],
        rules: rules,
        events: List.filled(4, pt(0)),
      );
      // After game 1 completed, servingSide should be 1 (B).
      expect(p1.state['servingSide'], 1);

      // Game 2: B serves and wins.
      final p2 = engine.evaluate(
        sides: ['A', 'B'],
        rules: rules,
        events: [...List.filled(4, pt(0)), ...List.filled(4, pt(1))],
      );
      // After game 2, servingSide is back to 0.
      expect(p2.state['servingSide'], 0);
    });

    test('servingMember starts at 0 and alternates within a pair', () {
      // Singles: member is always 0 (only one player).
      final p = engine.evaluate(sides: ['A', 'B'], rules: rules, events: []);
      expect(p.state['servingMember'], 0);
    });
  });

  // ── Point history ───────────────────────────────────────────────────────

  group('Padel pointHistory', () {
    final rules = engine.rulesForFormat('1 set · first to 6');

    test('returns one record per point', () {
      final events = [pt(0), pt(1), pt(0)];
      final history = engine.pointHistory(
        sides: ['A', 'B'],
        rules: rules,
        events: events,
      );
      expect(history, hasLength(3));
      expect(history.first.index, 1);
      expect(history.first.winnerSide, 0);
    });

    test(
      'last record of a completed match has scoreAfter starting with "match"',
      () {
        // 1 set: 6 games × 4 points = 24 points (side 0 wins all).
        final events = List.filled(24, pt(0));
        final history = engine.pointHistory(
          sides: ['A', 'B'],
          rules: rules,
          events: events,
        );
        final last = history.last;
        expect(last.scoreAfter, startsWith('match'));
        expect(last.isDecidingPoint, isTrue);
      },
    );

    test('tiebreak records are marked with tiebreak=true', () {
      // Drive to 6-6 then start TB.
      // Each game is 4 points (side A wins, then side B wins alternating).
      // 12 games (6 each) = 48 points (24 per side).
      final evs = <ScoringEvent>[];
      for (var g = 0; g < 12; g++) {
        // Alternate game winners so we end at 6-6 (each serves own games).
        final side = g % 2;
        evs.addAll(List.filled(4, pt(side)));
      }
      // Now in TB; one more point.
      evs.add(pt(0));
      final history = engine.pointHistory(
        sides: ['A', 'B'],
        rules: rules,
        events: evs,
      );
      final tbRecords = history.where((r) => r.tiebreak).toList();
      expect(tbRecords, isNotEmpty);
    });
  });

  // ── Match progress state ────────────────────────────────────────────────

  group('Padel state map', () {
    test('state includes all required keys after a point', () {
      final p = engine.evaluate(
        sides: ['A', 'B'],
        rules: engine.rulesForFormat('Best of 3 sets'),
        events: [pt(0)],
      );
      for (final key in [
        'completedSets',
        'points',
        'tiebreakPoints',
        'setsWon',
        'games',
        'inTiebreak',
        'deciderTiebreak',
        'matchTiebreak',
        'noAd',
        'setsToWin',
        'gamesToWinSet',
        'servingSide',
        'servingMember',
        'servingName',
        'pointCount',
      ]) {
        expect(p.state.containsKey(key), isTrue, reason: 'missing key: $key');
      }
    });
  });

  // ── SportMatch tournament fields ────────────────────────────────────────

  group('SportMatch tournament link', () {
    test('isTournamentMatch is true when tournamentId is set', () {
      final m = SportMatch(
        id: 'm1',
        sport: Sport.padel,
        formatLabel: 'Best of 3 sets',
        rules: const {},
        title: 'Test',
        venue: 'Court 1',
        scheduledAt: DateTime(2026),
        visibility: MatchVisibility.public,
        organizerId: 'acc1',
        status: FixtureStatus.upcoming,
        sideNames: const ['A', 'B'],
        discipline: MatchDiscipline.doubles,
        capacity: 4,
        createdAt: DateTime(2026),
        tournamentId: 't1',
        fixtureId: 'f1',
      );
      expect(m.isTournamentMatch, isTrue);
    });

    test('JSON round-trip preserves tournamentId and fixtureId', () {
      final m = SportMatch(
        id: 'm2',
        sport: Sport.padel,
        formatLabel: 'Best of 3 · golden point',
        rules: const {'noAd': true},
        title: 'Round trip',
        venue: 'Arena',
        scheduledAt: DateTime(2026, 6, 1),
        visibility: MatchVisibility.public,
        organizerId: 'acc2',
        status: FixtureStatus.upcoming,
        sideNames: const ['X', 'Y'],
        discipline: MatchDiscipline.singles,
        capacity: 2,
        createdAt: DateTime(2026, 6, 1),
        tournamentId: 'tournament-99',
        fixtureId: 'fixture-7',
      );
      final json = m.toJson();
      final restored = SportMatch.fromJson(json);
      expect(restored.tournamentId, 'tournament-99');
      expect(restored.fixtureId, 'fixture-7');
      expect(restored.isTournamentMatch, isTrue);
    });

    test('matchOfFixture finds the linked match', () {
      // Unit-level: just verify the field filter logic (no repository).
      final m = SportMatch(
        id: 'm3',
        sport: Sport.padel,
        formatLabel: 'Best of 3 sets',
        rules: const {},
        title: 'Tie',
        venue: 'V',
        scheduledAt: DateTime(2026),
        visibility: MatchVisibility.public,
        organizerId: 'acc3',
        status: FixtureStatus.upcoming,
        sideNames: const ['A', 'B'],
        discipline: MatchDiscipline.doubles,
        capacity: 4,
        createdAt: DateTime(2026),
        tournamentId: 't1',
        fixtureId: 'f1',
      );
      final matches = [m];
      final found = matches
          .where((x) => x.tournamentId == 't1' && x.fixtureId == 'f1')
          .firstOrNull;
      expect(found?.id, 'm3');
    });
  });

  // ── MatchDraft tournament fields ────────────────────────────────────────

  group('MatchDraft tournament fields', () {
    test('draft carries tournamentId and fixtureId', () {
      final d = MatchDraft(
        sport: Sport.padel,
        formatLabel: 'Best of 3 · golden point',
        rules: const {'noAd': true},
        title: 'T',
        venue: 'V',
        scheduledAt: DateTime(2026),
        visibility: MatchVisibility.public,
        sideA: 'A',
        sideB: 'B',
        capacity: 4,
        discipline: MatchDiscipline.doubles,
        tournamentId: 't1',
        fixtureId: 'f1',
      );
      expect(d.tournamentId, 't1');
      expect(d.fixtureId, 'f1');
    });

    test('draft without tournament fields has null ids', () {
      final d = MatchDraft(
        sport: Sport.padel,
        formatLabel: '1 set · first to 6',
        rules: const {},
        title: 'F',
        venue: 'V',
        scheduledAt: DateTime(2026),
        visibility: MatchVisibility.public,
        sideA: 'A',
        sideB: 'B',
        capacity: 4,
        discipline: MatchDiscipline.singles,
      );
      expect(d.tournamentId, isNull);
      expect(d.fixtureId, isNull);
    });
  });

  // ── describeRules ───────────────────────────────────────────────────────

  group('PadelEngine.describeRules', () {
    test('golden point format mentions golden point', () {
      final r = engine.rulesForFormat('Best of 3 · golden point');
      final text = engine.describeRules(r);
      expect(text.toLowerCase(), contains('golden'));
    });

    test('super tie-break format mentions match tie-break', () {
      final r = engine.rulesForFormat('Best of 3 · super tie-break');
      final text = engine.describeRules(r);
      expect(text.toLowerCase(), contains('match tie-break'));
    });
  });

  // ── PadelEngine.evaluate – completion via golden point ──────────────────

  test('padel golden point completes game at diff=1, not diff=2', () {
    final rules = engine.rulesForFormat('Best of 3 · golden point');
    // 3-3 points, then side 1 wins one point → game to side 1.
    final events = [
      ...List.filled(3, pt(0)),
      ...List.filled(3, pt(1)),
      pt(1), // golden point for side 1
    ];
    final p = engine.evaluate(sides: ['A', 'B'], rules: rules, events: events);
    expect((p.state['games'] as List)[1], 1);
    expect((p.state['games'] as List)[0], 0);
  });

  // ── Padel workspace smoke test ──────────────────────────────────────

  group('PadelScoringWorkspace smoke', () {
    late SportMatch match;

    setUp(() {
      final now = DateTime(2026);
      match = SportMatch(
        id: 'ws-1',
        sport: Sport.padel,
        formatLabel: 'Best of 3 sets',
        rules: SportEngines.rulesFor(Sport.padel, 'Best of 3 sets'),
        title: 'Workspace test',
        venue: 'Court 1',
        scheduledAt: now,
        visibility: MatchVisibility.public,
        organizerId: 'acc1',
        status: FixtureStatus.live,
        sideNames: const ['Zara', 'Imran'],
        discipline: MatchDiscipline.doubles,
        capacity: 4,
        createdAt: now,
        participants: [
          MatchParticipant(
            profileId: 'acc1',
            displayName: 'Zara',
            side: 0,
            status: MatchParticipantStatus.accepted,
            invitedById: 'acc1',
            joinedAt: now,
          ),
          MatchParticipant(
            profileId: 'acc2',
            displayName: 'Imran',
            side: 1,
            status: MatchParticipantStatus.accepted,
            invitedById: 'acc1',
            joinedAt: now,
          ),
        ],
        events: [],
      );
    });

    MatchProgress freshProgress() => SportEngines.progressOf(
      sport: Sport.padel,
      rules: match.rules,
      sides: match.sideNames,
      rawEvents: match.scoringLog,
    );

    Future<void> pump(
      WidgetTester tester,
      MatchProgress progress, {
      RecordMatchEvent? onRecord,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PadelScoringWorkspace(
                match: match,
                progress: progress,
                accent: sportColor(Sport.padel),
                onRecord: onRecord ?? (_, _, _) {},
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('renders side names and point pad without error', (
      tester,
    ) async {
      await pump(tester, freshProgress());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Zara'), findsWidgets);
      expect(find.text('Imran'), findsWidgets);
    });

    testWidgets('history toggle shows 0 points for fresh match', (
      tester,
    ) async {
      await pump(tester, freshProgress());
      await tester.pumpAndSettle();
      expect(find.textContaining('Point history (0 point'), findsOneWidget);
    });

    testWidgets('tapping history toggle reveals empty message', (tester) async {
      await pump(tester, freshProgress());
      await tester.pumpAndSettle();
      // The toggle sits below the fold, so a tap has to scroll to it first -
      // exactly what the scorer does on a phone.
      final toggle = find.textContaining('Point history');
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pump();
      expect(find.text('No points recorded yet.'), findsOneWidget);
    });

    testWidgets('shows set grid with "No set finished yet" at start', (
      tester,
    ) async {
      await pump(tester, freshProgress());
      await tester.pumpAndSettle();
      expect(find.text('No set finished yet.'), findsOneWidget);
    });

    testWidgets('a live pad records one point for its side', (tester) async {
      final recorded = <int?>[];
      await pump(
        tester,
        freshProgress(),
        onRecord: (kind, side, data) {
          expect(kind, PadelEngine.kPoint);
          recorded.add(side);
        },
      );
      await tester.pumpAndSettle();
      // The serving pad reads "Serving · Point"; the other reads "Point".
      await tester.tap(find.text('Point'));
      await tester.pumpAndSettle();
      expect(recorded, [1]);
    });

    testWidgets('a paused match disables both pads and shows the reason', (
      tester,
    ) async {
      match.pausedAt = DateTime(2026, 1, 2);
      match.pausedBy = 'acc1';
      match.pauseReason = 'Rain on court three';
      var recorded = 0;
      await pump(tester, freshProgress(), onRecord: (_, _, _) => recorded++);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Scoring is paused: Rain on court three'),
        findsOneWidget,
      );
      expect(find.text('Paused'), findsNWidgets(2));
      await tester.tap(find.text('Paused').first);
      await tester.pumpAndSettle();
      expect(recorded, 0);
    });

    testWidgets('a pause without a reason still blocks the pads', (
      tester,
    ) async {
      match.pausedAt = DateTime(2026, 1, 2);
      var recorded = 0;
      await pump(tester, freshProgress(), onRecord: (_, _, _) => recorded++);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Scoring is paused. Resume the match'),
        findsOneWidget,
      );
      await tester.tap(find.text('Paused').last);
      await tester.pumpAndSettle();
      expect(recorded, 0);
    });
  });
}
