import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';

MatchEvent event(
  int seq,
  String kind,
  int? side,
  Map<String, dynamic> data, {
  bool voided = false,
}) => MatchEvent(
  id: 'event-$seq',
  seq: seq,
  clientId: 'client-$seq',
  kind: kind,
  side: side,
  data: data,
  at: DateTime.utc(2026, 5, 1).add(Duration(minutes: seq)),
  byAccountId: 'acc-organizer',
  voided: voided,
);

SportMatch matchWith({
  Sport sport = Sport.cricket,
  Map<String, dynamic>? rules,
  List<MatchEvent> events = const [],
  List<MatchParticipant> participants = const [],
  OfficialResult? result,
  List<ResultCorrection> corrections = const [],
}) => SportMatch(
  id: 'match-1',
  sport: sport,
  formatLabel: 'Test format',
  rules: rules ?? const {},
  title: 'Model test match',
  venue: 'Court one',
  scheduledAt: DateTime.utc(2026, 5, 1, 18),
  visibility: MatchVisibility.invite,
  organizerId: 'acc-organizer',
  scorerId: 'acc-scorer',
  status: FixtureStatus.live,
  sideNames: const ['Alpha', 'Bravo'],
  discipline: MatchDiscipline.doubles,
  capacity: 4,
  eventCount: events.isEmpty ? 0 : events.last.seq,
  createdAt: DateTime.utc(2026, 4, 30),
  participants: List<MatchParticipant>.from(participants),
  events: List<MatchEvent>.from(events),
  result: result,
  corrections: List<ResultCorrection>.from(corrections),
);

Future<LocalSportikaRepository> loadedStore() async {
  SharedPreferences.setMockInitialValues({'sportika.onboarding_seen.v1': true});
  final store = LocalSportikaRepository(await LocalStorage.open());
  await store.load();
  return store;
}

void main() {
  test('a match survives a JSON round trip with every nested record', () {
    final result = OfficialResult(
      sideScores: const ['6/1', '5/2'],
      sideValues: const [6, 5],
      winnerIndex: 0,
      headline: 'Alpha won by 1 run',
      detail: 'Tight finish',
      publishedAt: DateTime.utc(2026, 5, 1, 20),
      publishedById: 'acc-organizer',
    );
    final original = matchWith(
      events: [
        event(1, 'ball', 0, {'runs': 4}),
      ],
      participants: [
        MatchParticipant(
          profileId: 'acc-scorer',
          displayName: 'Sana Scorer',
          side: 1,
          status: MatchParticipantStatus.accepted,
          invitedById: 'acc-organizer',
          joinedAt: DateTime.utc(2026, 4, 30, 9),
        ),
      ],
      result: result,
      corrections: [
        ResultCorrection(
          id: 'cor-1',
          previous: result,
          current: result,
          reason: 'Scoring error on the last ball',
          byAccountId: 'acc-organizer',
          at: DateTime.utc(2026, 5, 2),
        ),
      ],
    );

    final restored = SportMatch.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.sport, Sport.cricket);
    expect(restored.visibility, MatchVisibility.invite);
    expect(restored.discipline, MatchDiscipline.doubles);
    expect(restored.status, FixtureStatus.live);
    expect(restored.scorerId, 'acc-scorer');
    expect(restored.eventCount, 1);
    expect(restored.participants.single.displayName, 'Sana Scorer');
    expect(
      restored.participants.single.status,
      MatchParticipantStatus.accepted,
    );
    expect(restored.events.single.data['runs'], 4);
    expect(restored.result!.headline, 'Alpha won by 1 run');
    expect(
      restored.corrections.single.reason,
      'Scoring error on the last ball',
    );
    expect(restored.sideNames, ['Alpha', 'Bravo']);
  });

  test('voided entries leave the log without rewinding the sequence', () {
    final match = matchWith(
      rules: const {'oversPerInnings': 1},
      events: [
        event(1, 'ball', 0, {'runs': 4}),
        event(2, 'ball', 0, {'runs': 6}, voided: true),
        event(3, 'ball', 0, {'runs': 2}),
      ],
    );

    expect(match.scoringLog.map((e) => e['id']), ['event-1', 'event-3']);
    expect(match.eventCount, 3);
    expect(match.lastActiveEvent!.id, 'event-3');

    final folded = SportEngines.progressOf(
      sport: match.sport,
      sides: match.sideNames,
      rules: const {'oversPerInnings': 1},
      rawEvents: match.scoringLog,
    );
    expect(folded.lines.first.value, '6/0');
  });

  test('the last active entry skips the voided tail', () {
    final match = matchWith(
      events: [
        event(1, 'ball', 0, {'runs': 1}),
        event(2, 'ball', 0, {'runs': 2}, voided: true),
      ],
    );
    expect(match.lastActiveEvent!.id, 'event-1');
  });

  test('the store folds the log exactly like the engine does', () async {
    final store = await loadedStore();
    final cricketRules = {
      'oversPerInnings': 1,
      'wicketsPerInnings': 10,
      'innings': 2,
    };
    final match = matchWith(
      rules: cricketRules,
      events: [
        for (var i = 0; i < 6; i++) event(i + 1, 'ball', 0, {'runs': 1}),
        for (var i = 0; i < 6; i++) event(i + 7, 'ball', 1, {'runs': 1}),
      ],
    );
    store.matches.add(match);

    final fromStore = store.progressOf(match);
    final direct = SportEngines.progressOf(
      sport: Sport.cricket,
      sides: match.sideNames,
      rules: cricketRules,
      rawEvents: match.scoringLog,
    );

    expect(fromStore.scoreDisplay, direct.scoreDisplay);
    expect(fromStore.isComplete, isTrue);
    expect(fromStore.winnerIndex, -1);
    expect(fromStore.resultLabel, 'Match tied');
  });

  test('every sport folds to a complete result through the model', () async {
    final store = await loadedStore();

    // Padel: one set, four straight games.
    final padelRules = {
      'setsToWin': 1,
      'gamesToWinSet': 6,
      'tiebreakAt': 6,
      'tiebreakPoints': 7,
      'finalSetTiebreakPoints': 7,
      'noAd': false,
    };
    final padel = matchWith(
      sport: Sport.padel,
      rules: padelRules,
      events: [for (var i = 0; i < 24; i++) event(i + 1, 'point', 0, const {})],
    );
    expect(store.progressOf(padel).isComplete, isTrue);
    expect(store.progressOf(padel).winnerIndex, 0);

    // Badminton: first to five rallies, one game wins it.
    final badmintonRules = {
      'gamesToWin': 1,
      'pointsToWinGame': 5,
      'cap': 7,
      'discipline': 'singles',
    };
    final badminton = matchWith(
      sport: Sport.badminton,
      rules: badmintonRules,
      events: [for (var i = 0; i < 5; i++) event(i + 1, 'rally', 1, const {})],
    );
    expect(store.progressOf(badminton).isComplete, isTrue);
    expect(store.progressOf(badminton).winnerIndex, 1);

    // Futsal: two goals, then the clock closes the match.
    final futsalRules = {
      'halves': 2,
      'halfMinutes': 15,
      'winnerRequired': true,
      'shootout': true,
    };
    final futsal = matchWith(
      sport: Sport.futsal,
      rules: futsalRules,
      events: [
        event(1, 'clock', null, {'action': 'start'}),
        event(2, 'goal', 0, {'half': 0}),
        event(3, 'goal', 0, {'half': 0}),
        event(4, 'goal', 1, {'half': 1}),
        event(5, 'clock', null, {'action': 'end_match'}),
      ],
    );
    final futsalProgress = store.progressOf(futsal);
    expect(futsalProgress.isComplete, isTrue);
    expect(futsalProgress.winnerIndex, 0);
    expect(futsalProgress.scoreDisplay, ['2', '1']);
  });

  test('a queued scoring tap survives a storage round trip', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await LocalStorage.open();
    expect(storage.readMatchOutbox(), isEmpty);

    await storage.writeMatchOutbox([
      {
        'matchId': 'match-1',
        'clientId': 'client-9',
        'kind': 'ball',
        'side': 0,
        'data': {'runs': 4},
        'at': '2026-05-01T18:00:00.000Z',
      },
    ]);

    final reopened = await LocalStorage.open();
    final entry = reopened.readMatchOutbox().single;
    expect(entry['clientId'], 'client-9');
    expect(entry['kind'], 'ball');
    expect((entry['data'] as Map)['runs'], 4);

    await reopened.writeMatchOutbox(const []);
    expect(reopened.readMatchOutbox(), isEmpty);
  });

  test('an older document gains an empty match list', () async {
    SharedPreferences.setMockInitialValues({
      LocalStorage.dataKey: '{"version": 1}',
      LocalStorage.schemaKey: 1,
    });
    final storage = await LocalStorage.open();
    final state = storage.readState()!;
    expect(state['matches'], isA<List<dynamic>>());
    expect(state['preferences'], isA<Map<String, dynamic>>());
    expect(LocalStorage.schemaVersion, 3);
  });
}
