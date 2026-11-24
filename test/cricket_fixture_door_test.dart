// The door from a tournament fixture into a cricket match. A cricket fixture is
// set up as an official match, the way a futsal one is, and only a fixture that
// was already scored the old way keeps the legacy scorecard. Badminton must
// still get its scorecard, so it is asserted here as the untouched case.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/features/live/screens/fixture_detail_screen.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';

import 'match_scoring_test.dart' as harness;

void main() {
  late LocalSportikaRepository store;
  late String tournamentName;

  setUp(() async {
    store = await harness.loadedStore();
    await store.signIn(store.accounts[0].id);
  });

  /// Publishes a one-fixture cup and returns the fixture id. Fixture events are
  /// plain maps, because a fixture written before the Match Center existed is
  /// exactly the legacy shape the scorecard door has to keep serving.
  Future<String> createCup({
    Sport sport = Sport.cricket,
    List<Map<String, dynamic>> events = const [],
  }) async {
    tournamentName = '${sport.name} cup';
    await store.createTournament(
      name: tournamentName,
      city: 'Lahore',
      sport: sport,
      format: TournamentFormat.knockout,
      entryType: EntryType.team,
      startsAt: DateTime.now().add(const Duration(days: 1)),
      endsAt: DateTime.now().add(const Duration(days: 3)),
      registrationLimit: 8,
      entryFee: 'Free',
      rulesSummary: 'Two over games',
      rules: const {'oversPerInnings': 2, 'wicketsPerInnings': 3},
      publishNow: true,
    );
    final tournament = store.tournaments.firstWhere(
      (t) => t.name == tournamentName,
    );
    final id = '${sport.name}-fixture';
    store.fixtures.add(
      Fixture(
        id: id,
        tournamentId: tournament.id,
        stage: 'Semi final',
        round: 1,
        home: FixtureSide(entryId: 'cup-home', label: 'Alpha XI'),
        away: FixtureSide(entryId: 'cup-away', label: 'Bravo XI'),
        scheduledAt: DateTime.now().add(const Duration(hours: 2)),
        venue: 'Cup ground',
        status: FixtureStatus.upcoming,
        scorerAccountIds: [store.accounts[1].id],
        events: events,
        rules: const {'oversPerInnings': 2, 'wicketsPerInnings': 3},
        corrections: [],
      ),
    );
    store.notifyListeners();
    return id;
  }

  Future<void> show(WidgetTester tester, String fixtureId) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SessionController(store)),
          ChangeNotifierProvider(create: (_) => ProfileController(store)),
          ChangeNotifierProvider(create: (_) => TournamentsController(store)),
          ChangeNotifierProvider(create: (_) => FixturesController(store)),
          ChangeNotifierProvider(create: (_) => MatchController(store)),
        ],
        child: MaterialApp(
          theme: buildSportikaTheme(),
          home: FixtureDetailScreen(fixtureId: fixtureId),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a fresh cricket fixture is set up as a match, not a scorecard', (
    tester,
  ) async {
    final fixtureId = await createCup();
    await show(tester, fixtureId);
    expect(find.text('Set up Cricket Match Center'), findsOneWidget);
    expect(find.text('Open legacy scorecard'), findsNothing);
    expect(find.text('View scorecard'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('once the match exists the fixture opens it', (tester) async {
    final fixtureId = await createCup();
    final fixture = store.fixtures.firstWhere((f) => f.id == fixtureId);
    final tournament = store.tournaments.firstWhere(
      (t) => t.name == tournamentName,
    );
    await store.createMatch(
      MatchDraft(
        sport: Sport.cricket,
        formatLabel: SportEngines.formatsFor(Sport.cricket).first,
        rules: {
          ...fixture.rules,
          'competitionName': tournament.name,
          'stage': fixture.stage,
        },
        title: '${tournament.name} · ${fixture.stage}',
        venue: fixture.venue,
        scheduledAt: fixture.scheduledAt,
        visibility: MatchVisibility.public,
        sideA: fixture.home.label,
        sideB: fixture.away.label,
        capacity: 22,
        discipline: MatchDiscipline.team,
        scorerId: fixture.scorerAccountIds.firstOrNull,
        tournamentId: tournament.id,
        fixtureId: fixture.id,
      ),
    );
    await show(tester, fixtureId);
    expect(find.text('Open Cricket Match Center'), findsOneWidget);
    expect(find.text('Set up Cricket Match Center'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a fixture already scored the old way keeps its own door', (
    tester,
  ) async {
    final fixtureId = await createCup(
      events: [
        ScoringEvent(
          id: 'legacy-1',
          kind: 'ball',
          side: 0,
          data: const {'runs': 4},
          at: DateTime.now(),
          byAccountId: 'organizer',
        ).toJson(),
      ],
    );
    await show(tester, fixtureId);
    expect(find.text('Open legacy scorecard'), findsOneWidget);
    expect(find.textContaining('Set up Cricket Match Center'), findsNothing);
    expect(find.textContaining('Finish it here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('badminton keeps its scorecard door', (tester) async {
    final fixtureId = await createCup(sport: Sport.badminton);
    await show(tester, fixtureId);
    expect(find.textContaining('Cricket Match Center'), findsNothing);
    expect(find.text('View scorecard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
