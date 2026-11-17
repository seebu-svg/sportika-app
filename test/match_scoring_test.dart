import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/matches/scoring/match_scoring_shell.dart';
import 'package:sportika/features/matches/scoring/match_scoring_validator.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';

Future<LocalSportikaRepository> loadedStore() async {
  SharedPreferences.setMockInitialValues({'sportika.onboarding_seen.v1': true});
  final store = LocalSportikaRepository(await LocalStorage.open());
  await store.load();
  return store;
}

/// The scoring screen needs a route underneath it: submitting pops back, and a
/// test that pushed on top of a real host can prove the screen closed itself.
class _ScoringHost extends StatefulWidget {
  const _ScoringHost({required this.matchId});

  final String matchId;

  @override
  State<_ScoringHost> createState() => _ScoringHostState();
}

class _ScoringHostState extends State<_ScoringHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              MatchScoringScreen(matchId: widget.matchId, ticking: false),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('scoreboard closed')));
}

/// Pumps the workspace over a loaded store. The clock is frozen so the futsal
/// timer can never outlive the test.
Future<MatchController> pumpScoring(
  WidgetTester tester,
  LocalSportikaRepository store,
  String matchId, {
  Size size = const Size(420, 1000),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final session = SessionController(store);
  final matches = MatchController(store);
  addTearDown(matches.dispose);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionController>.value(value: session),
        ChangeNotifierProvider<MatchController>.value(value: matches),
      ],
      child: MaterialApp(
        theme: buildSportikaTheme(),
        home: _ScoringHost(matchId: matchId),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return matches;
}

Finder pad(String label, [String? hint]) => find.byWidgetPredicate(
  (widget) =>
      widget is ScoringPad &&
      widget.label == label &&
      (hint == null || widget.hint == hint),
);

Future<void> tapText(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> tapPad(WidgetTester tester, Finder finder) =>
    tapText(tester, finder);

/// Taps the confirm button of the open dialog, never the control that opened it.
Future<void> confirmDialog(WidgetTester tester, String label) async {
  final button = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.text(label),
  );
  expect(button, findsOneWidget);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// Runs the three-second snack bar out so the test does not end on a timer.
Future<void> drainSnack(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

void main() {
  late LocalSportikaRepository store;
  late Account organizer;
  late Account player;

  setUp(() async {
    store = await loadedStore();
    organizer = store.accounts[0];
    player = store.accounts[1];
    await store.signIn(organizer.id);
  });

  /// Creates a match with the sport's own format, then overrides the rules the
  /// test needs so a whole match fits in a handful of taps.
  Future<SportMatch> createMatch({
    required Sport sport,
    Map<String, dynamic> overrides = const {},
    MatchDiscipline? discipline,
    int capacity = 4,
  }) async {
    final format = SportEngines.formatsFor(sport).first;
    return store.createMatch(
      MatchDraft(
        sport: sport,
        formatLabel: format,
        rules: {...SportEngines.rulesFor(sport, format), ...overrides},
        title: '${sport.label} scoring test',
        venue: 'Court one',
        scheduledAt: DateTime.now().add(const Duration(hours: 1)),
        visibility: MatchVisibility.public,
        sideA: 'Rao & Iqbal',
        sideB: 'Malik & Farooq',
        capacity: capacity,
        discipline: discipline ?? MatchDisciplineX.forSport(sport).first,
      ),
    );
  }

  /// One accepted player per side, so a scorer can name a striker and a bowler.
  Future<void> fillSides(SportMatch match) async {
    await store.inviteParticipant(match.id, player.id, side: 1);
    await store.signIn(player.id);
    await store.respondToInvite(match.id, accept: true);
    await store.signIn(organizer.id);
  }

  test('the validator refuses what the sport cannot fold', () async {
    final padel = await createMatch(sport: Sport.padel);
    final padelProgress = store.progressOf(padel);
    expect(
      MatchScoringValidator.validate(
        match: padel,
        progress: padelProgress,
        kind: 'ball',
        side: 0,
      ),
      'Padel scores point by point.',
    );
    expect(
      MatchScoringValidator.validate(
        match: padel,
        progress: padelProgress,
        kind: 'point',
        side: 5,
      ),
      'Pick the pair that won the point.',
    );

    final cricket = await createMatch(
      sport: Sport.cricket,
      discipline: MatchDiscipline.team,
    );
    final cricketProgress = store.progressOf(cricket);
    expect(
      MatchScoringValidator.validate(
        match: cricket,
        progress: cricketProgress,
        kind: 'ball',
        side: 0,
        data: const {'runs': 9},
      ),
      'Runs on a ball run from 0 to 6.',
    );
    expect(
      MatchScoringValidator.validate(
        match: cricket,
        progress: cricketProgress,
        kind: 'ball',
        side: 0,
        data: const {'runs': 1, 'extra': 'overthrow'},
      ),
      'That extra is not one cricket understands.',
    );
    expect(
      MatchScoringValidator.validate(
        match: cricket,
        progress: cricketProgress,
        kind: 'ball',
        side: null,
        data: const {'runs': 1},
      ),
      'Pick the side that is batting.',
    );

    final futsal = await createMatch(
      sport: Sport.futsal,
      discipline: MatchDiscipline.team,
    );
    final futsalProgress = store.progressOf(futsal);
    expect(
      MatchScoringValidator.validate(
        match: futsal,
        progress: futsalProgress,
        kind: 'clock',
        data: const {'action': 'pause'},
      ),
      'That clock action is not one futsal understands.',
    );
    expect(
      MatchScoringValidator.validate(
        match: futsal,
        progress: futsalProgress,
        kind: 'card',
        side: 0,
        data: const {'colour': 'blue'},
      ),
      'Cards are yellow or red.',
    );
    expect(
      MatchScoringValidator.validate(
        match: futsal,
        progress: futsalProgress,
        kind: 'substitution',
        side: 0,
        data: const {'in': 'Rao', 'out': 'Rao'},
      ),
      'A player cannot replace themselves.',
    );

    final badminton = await createMatch(sport: Sport.badminton);
    expect(
      MatchScoringValidator.validate(
        match: badminton,
        progress: store.progressOf(badminton),
        kind: 'goal',
        side: 0,
      ),
      'Badminton scores rally by rally.',
    );
  });

  test('the validator refuses an entry once the match is complete', () async {
    final match = await createMatch(
      sport: Sport.badminton,
      overrides: const {'gamesToWin': 1, 'pointsToWinGame': 3, 'cap': 5},
    );
    await store.startMatch(match.id);
    for (var i = 0; i < 3; i++) {
      await store.recordEvent(match.id, kind: 'rally', side: 0);
    }
    final progress = store.progressOf(match);
    expect(progress.isComplete, isTrue);
    expect(
      MatchScoringValidator.validate(
        match: match,
        progress: progress,
        kind: 'rally',
        side: 1,
      ),
      'This match is complete. Submit the result instead.',
    );
  });

  testWidgets('padel: points win the set and the result submits', (
    tester,
  ) async {
    final match = await createMatch(sport: Sport.padel);
    await store.startMatch(match.id);
    final controller = await pumpScoring(tester, store, match.id);

    // Twenty-four points with no reply is 6-0: one set, match over.
    for (var i = 0; i < 24; i++) {
      await tapPad(tester, find.byKey(const ValueKey('padel-point-0')));
    }

    expect(store.matchById(match.id)!.events.length, 24);
    final progress = controller.progressOf(store.matchById(match.id)!);
    expect(progress.isComplete, isTrue);
    expect(progress.winnerIndex, 0);

    // Completed matches remove the point pads, preventing a dead scoring tap.
    expect(find.byKey(const ValueKey('padel-point-1')), findsNothing);
    expect(store.matchById(match.id)!.events.length, 24);
    await drainSnack(tester);

    await tapText(tester, find.text('Submit final result'));
    await confirmDialog(tester, 'Submit');

    final submitted = store.matchById(match.id)!;
    expect(submitted.status, FixtureStatus.submitted);
    expect(submitted.result, isNotNull);
    expect(submitted.result!.winnerIndex, 0);
    expect(find.text('scoreboard closed'), findsOneWidget);
    await drainSnack(tester);
  });

  testWidgets('badminton: rallies reach the game and the result submits', (
    tester,
  ) async {
    final match = await createMatch(
      sport: Sport.badminton,
      overrides: const {'gamesToWin': 1, 'pointsToWinGame': 5, 'cap': 7},
    );
    await store.startMatch(match.id);
    await pumpScoring(tester, store, match.id);

    final second = match.sideNames.last;
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      await tapPad(tester, pad('Rally', second));
    }

    final progress = store.progressOf(store.matchById(match.id)!);
    expect(progress.isComplete, isTrue);
    expect(progress.winnerIndex, 1);
    expect(store.matchById(match.id)!.events.map((e) => e.side), [
      1,
      1,
      1,
      1,
      1,
    ]);

    await tester.tap(find.text('Submit final result'));
    await tester.pumpAndSettle();
    await confirmDialog(tester, 'Submit');
    expect(store.matchById(match.id)!.status, FixtureStatus.submitted);
    await drainSnack(tester);
  });

  testWidgets('cricket: the innings flip the batting side and the log closes', (
    tester,
  ) async {
    final match = await createMatch(
      sport: Sport.cricket,
      discipline: MatchDiscipline.team,
      overrides: const {
        'oversPerInnings': 1,
        'wicketsPerInnings': 3,
        'innings': 2,
      },
    );
    await fillSides(match);
    for (var side = 0; side < 2; side++) {
      final member = store.accounts[side + 2];
      await store.inviteParticipant(match.id, member.id, side: side);
      await store.signIn(member.id);
      await store.respondToInvite(match.id, accept: true);
      await store.signIn(organizer.id);
    }
    await store.startMatch(match.id);
    await pumpScoring(tester, store, match.id);

    // Name the striker and the bowler from the roster sheets.
    await tapText(tester, find.text('STRIKER'));
    expect(find.text('Who is on strike?'), findsOneWidget);
    await tester.tap(find.text(organizer.displayName).last);
    await tester.pumpAndSettle();
    expect(find.text(organizer.displayName), findsOneWidget);

    await tapText(tester, find.text('BOWLER'));
    expect(find.text('Who is bowling?'), findsOneWidget);
    await tester.tap(find.text(player.displayName).last);
    await tester.pumpAndSettle();

    await tapText(tester, find.text('NON-STRIKER'));
    await tester.tap(find.text(store.accounts[2].displayName).last);
    await tester.pumpAndSettle();

    // Six singles close the one-over innings.
    for (var i = 0; i < 6; i++) {
      await tapPad(tester, pad('1'));
    }

    final afterFirst = store.matchById(match.id)!;
    expect(afterFirst.events.length, 6);
    expect(store.progressOf(afterFirst).isComplete, isFalse);
    expect(afterFirst.events.every((e) => e.side == 0), isTrue);
    expect(afterFirst.events.first.data['striker'], organizer.displayName);
    expect(afterFirst.events.first.data['bowler'], player.displayName);
    expect(afterFirst.events[1].data['striker'], store.accounts[2].displayName);
    expect(afterFirst.events[1].data['nonStriker'], organizer.displayName);

    await tapText(tester, find.text('STRIKER'));
    await tester.tap(find.text(player.displayName).last);
    await tester.pumpAndSettle();
    await tapText(tester, find.text('NON-STRIKER'));
    await tester.tap(find.text(store.accounts[3].displayName).last);
    await tester.pumpAndSettle();
    await tapText(tester, find.text('BOWLER'));
    await tester.tap(find.text(organizer.displayName).last);
    await tester.pumpAndSettle();

    // The workspace now sends the other side in, so the second innings is the
    // reply rather than more runs for the side that already batted.
    for (var i = 0; i < 6; i++) {
      await tapPad(tester, pad('1'));
    }

    final finished = store.matchById(match.id)!;
    expect(finished.events.length, 12);
    expect(finished.events.skip(6).every((e) => e.side == 1), isTrue);
    final progress = store.progressOf(finished);
    expect(progress.isComplete, isTrue);
    expect(progress.resultLabel, 'Match tied');

    await tapText(tester, find.text('Submit final result'));
    await tester.pumpAndSettle();
    await confirmDialog(tester, 'Submit');
    expect(store.matchById(match.id)!.status, FixtureStatus.submitted);
    await drainSnack(tester);
  });

  testWidgets('futsal: the clock, goals and full time close the match', (
    tester,
  ) async {
    final match = await createMatch(
      sport: Sport.futsal,
      discipline: MatchDiscipline.team,
      overrides: const {'halfMinutes': 1, 'halves': 2, 'winnerRequired': true},
    );
    await fillSides(match);
    await store.startMatch(match.id);
    await pumpScoring(tester, store, match.id);

    await tapText(tester, find.text('Start clock'));
    expect(
      store.progressOf(store.matchById(match.id)!).state['phase'],
      'running',
    );

    // Two goals for the home side, named from the roster sheet.
    for (var i = 0; i < 2; i++) {
      await tapPad(tester, pad('Goal', match.sideNames.first));
      expect(find.text('Who scored?'), findsOneWidget);
      await tester.tap(find.text('No scorer named'));
      await tester.pumpAndSettle();
    }
    expect(store.matchById(match.id)!.events.last.kind, 'goal');
    expect(store.matchById(match.id)!.events.last.data['player'], isNull);

    // The athletic sheet: a foul and a yellow card in the first half.
    await tapPad(tester, find.text('Foul').first);
    await confirmDialog(tester, 'Record foul');
    await drainSnack(tester);
    await tapPad(tester, find.text('Card').first);
    await tester.tap(find.text('Yellow card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(organizer.displayName));
    await tester.pumpAndSettle();
    final futsal = store.matchById(match.id)!;
    expect(
      futsal.events.where((e) => e.kind == 'foul' || e.kind == 'card').length,
      2,
    );

    // Half one closes, half two starts, then the away side pulls one back.
    await tapText(tester, find.text('End half 1'));
    await confirmDialog(tester, 'End half');
    expect(
      store.progressOf(store.matchById(match.id)!).state['phase'],
      'halfTime',
    );

    await tapText(tester, find.text('Start half 2'));
    await tapPad(tester, pad('Goal', match.sideNames.last));
    await tester.tap(find.text('No scorer named'));
    await tester.pumpAndSettle();
    await drainSnack(tester);

    await tapText(tester, find.text('Full time'));
    await confirmDialog(tester, 'Full time');

    final finished = store.progressOf(store.matchById(match.id)!);
    expect(finished.isComplete, isTrue);
    expect(finished.winnerIndex, 0);
    expect(finished.scoreDisplay, ['2', '1']);
    await drainSnack(tester);
  });
}
