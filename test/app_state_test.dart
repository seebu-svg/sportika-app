import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/padel/padel.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/state/app_state.dart';

/// Acceptance criteria from the Sportika spec, exercised through the same
/// state object the UI uses (spec §6).
ScoringEvent ev(
  String kind,
  int side, {
  required String id,
  Map<String, dynamic> data = const {},
}) => ScoringEvent(
  id: id,
  kind: kind,
  side: side,
  data: data,
  at: DateTime(2026, 11, 12, 10),
  byAccountId: 'acc-test',
);

/// One decided padel match: two sets won 6-0, 6-0.
List<ScoringEvent> padelWin(String tag) => [
  for (var set = 0; set < 2; set++)
    for (var game = 0; game < 6; game++)
      for (var point = 0; point < 4; point++)
        ev(PadelEngine.kPoint, 0, id: '$tag-s$set-g$game-p$point'),
];

Future<AppState> freshState() async {
  SharedPreferences.setMockInitialValues({});
  final storage = await LocalStorage.open();
  final state = AppState(storage);
  await state.load();
  return state;
}

void main() {
  final padelFormat = SportEngines.formatsFor(Sport.padel).first;

  test('unassigned players cannot mutate official scores', () async {
    final state = await freshState();
    await state.signIn('acc-zain');
    final fixture = state.liveFixtures.first;
    final before = fixture.events.length;
    state.recordOfficialEvent(
      fixture.id,
      ev(PadelEngine.kPoint, 0, id: 'forbidden'),
    );
    state.undoOfficialEvent(fixture.id);
    state.submitOfficialResult(fixture.id);
    expect(fixture.events.length, before);
    expect(fixture.status, FixtureStatus.live);
  });

  test(
    'community joins survive a restart and cannot exceed capacity',
    () async {
      final state = await freshState();
      await state.signIn('acc-zain');
      final game = state.games.firstWhere((g) => !g.full);
      final before = game.members.length;
      state.toggleGameJoin(game);
      expect(game.members.length, before + 1);
      await Future<void>.delayed(Duration.zero);
      final reopened = AppState(await LocalStorage.open());
      await reopened.load();
      expect(
        reopened.games.firstWhere((g) => g.id == game.id).members,
        contains('acc-zain'),
      );
      state.toggleGameJoin(game);
      expect(game.members.length, before);
      final full = state.games.firstWhere((g) => g.full);
      state.toggleGameJoin(full);
      expect(full.members.length, full.capacity);
    },
  );

  test('a personal scorecard auto-saves and resumes after a restart', () async {
    final state = await freshState();
    await state.signIn('acc-seebu');

    final match = state.startPersonalMatch(
      sport: Sport.padel,
      format: padelFormat,
      sideA: 'Seebu / Zain',
      sideB: 'Haris / Maria',
    );
    for (var i = 0; i < 5; i++) {
      state.recordPersonalEvent(
        match.id,
        ev(PadelEngine.kPoint, 0, id: 'pm-live-$i'),
      );
    }

    // A fresh state object reads the same document the app wrote.
    await Future<void>.delayed(Duration.zero);
    final reopened = AppState(await LocalStorage.open());
    await reopened.load();

    expect(reopened.currentAccount?.id, 'acc-seebu');
    final resumed = reopened.personalById(match.id);
    expect(resumed, isNotNull);
    expect(resumed!.events.length, 5);
    expect(resumed.status, PersonalMatchStatus.inProgress);
    expect(reopened.myPersonalInProgress.map((m) => m.id), contains(match.id));
  });

  test('two accounts keep separate records for the same fixture', () async {
    final state = await freshState();
    await state.signIn('acc-seebu');

    final mine = state.startPersonalMatch(
      sport: Sport.padel,
      format: padelFormat,
      sideA: 'Seebu / Zain',
      sideB: 'Haris / Maria',
    );
    state.recordPersonalEvent(
      mine.id,
      ev(PadelEngine.kPoint, 0, id: 'seebu-1'),
    );

    await state.signIn('acc-zain');
    final theirs = state.startPersonalMatch(
      sport: Sport.padel,
      format: padelFormat,
      sideA: 'Seebu / Zain',
      sideB: 'Haris / Maria',
    );

    // Same sides, same sport - but Seebu's entries are not Zain's.
    expect(state.myPersonal.map((m) => m.id), contains(theirs.id));
    expect(state.myPersonal.map((m) => m.id), isNot(contains(mine.id)));
    expect(state.personalById(mine.id)!.events.length, 1);
    expect(theirs.events, isEmpty);

    final seeded = state.personalById('pm-padel-done')!;
    expect(seeded.ownerId, 'acc-seebu');
    expect(state.myPersonal.map((m) => m.id), isNot(contains(seeded.id)));
  });

  test('a retried action is recorded once', () async {
    final state = await freshState();
    await state.signIn('acc-seebu');

    final match = state.startPersonalMatch(
      sport: Sport.padel,
      format: padelFormat,
      sideA: 'A',
      sideB: 'B',
    );
    final event = ev(PadelEngine.kPoint, 0, id: 'retry-1');
    state.recordPersonalEvent(match.id, event);
    state.recordPersonalEvent(match.id, event);
    expect(state.personalById(match.id)!.events.length, 1);

    // Official scoring dedupes on the same key.
    final fixture = state.fixtures.firstWhere(
      (f) => f.status == FixtureStatus.live,
    );
    await state.signIn(fixture.scorerAccountIds.first);
    final before = fixture.events.length;
    final official = ev(PadelEngine.kPoint, 1, id: 'retry-official');
    state.recordOfficialEvent(fixture.id, official);
    state.recordOfficialEvent(fixture.id, official);
    expect(fixture.events.length, before + 1);
  });

  test('official scoring survives a mid-match scorer transfer', () async {
    final state = await freshState();
    final fixture = state.fixtures.firstWhere(
      (f) => f.status == FixtureStatus.live && f.scorerAccountIds.isNotEmpty,
    );
    final from = fixture.scorerAccountIds.first;
    final to = const [
      'acc-seebu',
      'acc-haris',
      'acc-maria',
    ].firstWhere((id) => id != from);
    final before = fixture.events.length;

    await state.signIn(from);
    expect(state.myScoringFixtures.map((f) => f.id), contains(fixture.id));

    // Organizer hands the fixture to another scorer; the log is untouched.
    await state.signIn('acc-yasir');
    state.replaceScorer(fixture.id, from, to);

    await state.signIn(to);
    expect(fixture.events.length, before);
    expect(fixture.scorerAccountIds, contains(to));
    expect(fixture.scorerAccountIds, isNot(contains(from)));
    expect(state.myScoringFixtures.map((f) => f.id), contains(fixture.id));

    // The new scorer picks up exactly where the previous one stopped.
    state.recordOfficialEvent(
      fixture.id,
      ev(PadelEngine.kPoint, 0, id: 'transfer-1'),
    );
    expect(fixture.events.length, before + 1);

    await Future<void>.delayed(Duration.zero);
    final reopened = AppState(await LocalStorage.open());
    await reopened.load();
    expect(reopened.fixtureById(fixture.id)!.events.length, before + 1);
  });

  test('the bracket only moves when the organizer publishes', () async {
    final state = await freshState();
    await state.signIn('acc-yasir');

    final rules = SportEngines.rulesFor(Sport.padel, padelFormat);
    await state.createTournament(
      name: 'Test Padel Open',
      city: 'Karachi',
      sport: Sport.padel,
      format: TournamentFormat.knockout,
      entryType: EntryType.pair,
      startsAt: DateTime(2026, 12, 1, 18),
      endsAt: DateTime(2026, 12, 2, 22),
      registrationLimit: 4,
      entryFee: 'PKR 0',
      rulesSummary: SportEngines.describeRules(Sport.padel, rules),
      rules: rules,
      publishNow: true,
    );
    final tournament = state.tournaments.first;

    for (final id in const [
      'acc-seebu',
      'acc-zain',
      'acc-haris',
      'acc-maria',
    ]) {
      await state.signIn(id);
      await state.submitEntry(tournamentId: tournament.id, memberIds: [id]);
    }
    await state.signIn('acc-yasir');
    for (final entry in state.entriesFor(tournament.id)) {
      await state.decideEntry(entry.id, approve: true);
    }

    expect(await state.generateDraw(tournament.id), 3);

    final rounds = state.roundsFor(tournament);
    expect(rounds.length, 2);
    final semi = rounds.first.first;
    final finalFixture = rounds.last.first;
    final finalSidesBefore = state.sideLabelsOf(finalFixture);
    expect(finalSidesBefore.where((s) => s == 'TBD').length, 2);

    // Scorer records and submits - nothing advances yet.
    for (final event in padelWin('semi')) {
      state.recordOfficialEvent(semi.id, event);
    }
    state.submitOfficialResult(semi.id);

    expect(semi.status, FixtureStatus.submitted);
    expect(semi.result, isNull);
    expect(state.sideLabelsOf(finalFixture), finalSidesBefore);
    expect(
      state.fixturesFor(tournament.id).where((f) => f.result != null),
      isEmpty,
    );

    // The organizer publishes; only now does the bracket resolve.
    await state.signIn('acc-yasir');
    state.publishOfficialResult(semi.id);

    expect(semi.status, FixtureStatus.published);
    expect(semi.result, isNotNull);
    final winner = state.sideLabelsOf(semi)[semi.result!.winnerIndex];
    // Only the played semi resolves its slot; the other one is still open.
    expect(state.sideLabelsOf(finalFixture), contains(winner));
    expect(state.sideLabelsOf(finalFixture).where((s) => s == 'TBD').length, 1);
  });
}
