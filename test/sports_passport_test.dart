import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sportika/features/profile/widgets/sporting_record.dart';
import 'package:sportika/features/profile/widgets/sports_passport.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';

/// One tournament fixture. A null [winner] means the organizer has not
/// published a result, which is what a live or submitted match looks like.
Fixture _fixture({
  required String id,
  String homeEntryId = 'ent-me',
  String awayEntryId = 'ent-them',
  FixtureStatus status = FixtureStatus.published,
  int? winner,
  DateTime? completedAt,
}) => Fixture(
  id: id,
  tournamentId: 'trn-1',
  stage: 'Group A · Round 1',
  round: 1,
  home: FixtureSide(entryId: homeEntryId, label: 'Seebu / Zain'),
  away: FixtureSide(entryId: awayEntryId, label: 'Haris / Maria'),
  scheduledAt: completedAt ?? DateTime(2026, 11, 10, 18),
  venue: 'Gulberg Grounds',
  status: status,
  scorerAccountIds: const [],
  events: const [],
  rules: const {},
  result: winner == null
      ? null
      : OfficialResult(
          sideScores: const ['6', '4'],
          sideValues: const [6, 4],
          winnerIndex: winner,
          headline: winner < 0 ? 'Drawn 6-6' : 'Side ${winner + 1} won',
          detail: '',
          publishedAt: DateTime(2026, 11, 10, 20),
          publishedById: 'acc-organizer',
        ),
  corrections: const [],
  completedAt: completedAt ?? DateTime(2026, 11, 10, 19),
);

Account _account({
  String city = 'Karachi',
  String displayName = 'Zara Qureshi',
}) => Account(
  id: 'acc-zara',
  displayName: displayName,
  email: 'zara@sportika.pk',
  city: city,
  roles: const [UserRole.player],
  handle: 'zara.q',
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
  double textScale = 1.0,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildSportikaTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('sportingRecordOf', () {
    const myEntryIds = {'ent-me'};

    test('counts wins, losses and draws from finished fixtures only', () {
      final record = sportingRecordOf(
        myEntryIds: myEntryIds,
        fixtures: [
          _fixture(id: 'f-win', winner: 0),
          _fixture(
            id: 'f-win-away',
            homeEntryId: 'ent-them',
            awayEntryId: 'ent-me',
            winner: 1,
          ),
          _fixture(id: 'f-loss', winner: 1),
          _fixture(id: 'f-draw', winner: -1),
          // Walkovers are published outcomes, so they count too.
          _fixture(id: 'f-walkover', status: FixtureStatus.walkover, winner: 1),
          // A submitted result is still under review: never official.
          _fixture(
            id: 'f-submitted',
            status: FixtureStatus.submitted,
            winner: 1,
          ),
          // A cancelled match keeps its old result but must not be counted.
          _fixture(
            id: 'f-cancelled',
            status: FixtureStatus.cancelled,
            winner: 1,
          ),
          // Finished without a published result proves nothing.
          _fixture(id: 'f-unrecorded'),
          // Somebody else's match.
          _fixture(
            id: 'f-other',
            homeEntryId: 'ent-a',
            awayEntryId: 'ent-b',
            winner: 0,
          ),
        ],
      );

      expect(record.played, 5);
      expect(record.wins, 2);
      expect(record.losses, 2);
      expect(record.draws, 1);
      // A draw is neither a win nor a loss, but it was still played.
      expect(record.winRate, 40);
      expect(record.winRateLabel, '40%');
      expect(record.isEmpty, isFalse);
    });

    test('leaves the win rate unset until a match is completed', () {
      final record = sportingRecordOf(
        myEntryIds: myEntryIds,
        fixtures: [_fixture(id: 'f-upcoming', status: FixtureStatus.upcoming)],
      );

      expect(record.played, 0);
      expect(record.isEmpty, isTrue);
      expect(record.winRate, isNull);
      // A dash, because 0% would claim the member has lost every match.
      expect(record.winRateLabel, '—');
      expect(SportingRecord.empty.played, 0);
    });
  });

  group('outcomeOf', () {
    const myEntryIds = {'ent-me'};

    test('reads the member side of the fixture', () {
      expect(
        outcomeOf(_fixture(id: 'f1', winner: 0), myEntryIds),
        SportingOutcome.win,
      );
      expect(
        outcomeOf(_fixture(id: 'f2', winner: 1), myEntryIds),
        SportingOutcome.loss,
      );
      expect(
        outcomeOf(_fixture(id: 'f3', winner: -1), myEntryIds),
        SportingOutcome.draw,
      );
      expect(
        outcomeOf(_fixture(id: 'f4'), myEntryIds),
        SportingOutcome.unrecorded,
      );
      expect(
        outcomeOf(
          _fixture(
            id: 'f5',
            homeEntryId: 'ent-a',
            awayEntryId: 'ent-b',
            winner: 0,
          ),
          myEntryIds,
        ),
        SportingOutcome.unrecorded,
      );
    });
  });

  group('memberOfficialFixtures', () {
    test('keeps only the member finished matches, newest first', () {
      final fixtures = memberOfficialFixtures(
        myEntryIds: const {'ent-me'},
        fixtures: [
          _fixture(id: 'f-old', winner: 0, completedAt: DateTime(2026, 11, 1)),
          _fixture(id: 'f-new', winner: 1, completedAt: DateTime(2026, 11, 9)),
          _fixture(id: 'f-mid', winner: 1, completedAt: DateTime(2026, 11, 5)),
          _fixture(
            id: 'f-cancelled',
            status: FixtureStatus.cancelled,
            winner: 0,
            completedAt: DateTime(2026, 11, 8),
          ),
          _fixture(
            id: 'f-someone-else',
            homeEntryId: 'ent-a',
            awayEntryId: 'ent-b',
            winner: 0,
          ),
        ],
      );

      expect(fixtures.map((f) => f.id), ['f-new', 'f-mid', 'f-old']);
    });
  });

  testWidgets('the passport card carries only the member record', (
    tester,
  ) async {
    var edits = 0;
    await _pump(
      tester,
      SportsPassportCard(account: _account(), onEditProfile: () => edits++),
    );

    expect(find.text('SPORTIKA · ATHLETE PASSPORT'), findsOneWidget);
    expect(find.text('Zara Qureshi'), findsOneWidget);
    expect(find.text('@zara.q'), findsOneWidget);
    expect(find.text('Karachi'), findsOneWidget);
    expect(find.text('MEMBERSHIP'), findsOneWidget);
    expect(find.text('SPORTIKA MEMBER'), findsOneWidget);
    // No rank, tier or serial number is invented for the card.
    expect(find.textContaining('Rank'), findsNothing);
    expect(find.textContaining('LVL'), findsNothing);

    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    expect(edits, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty city is called out instead of left blank', (
    tester,
  ) async {
    await _pump(
      tester,
      SportsPassportCard(
        account: _account(city: ''),
        onEditProfile: () {},
      ),
    );

    expect(find.text('City not set'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the record strip shows a dash, never 0%, before a match', (
    tester,
  ) async {
    await _pump(
      tester,
      const SportingRecordStrip(record: SportingRecord.empty),
    );

    expect(find.text('0'), findsNWidgets(3));
    expect(find.text('—'), findsOneWidget);
    expect(find.text('MATCHES'), findsOneWidget);
    expect(find.text('WINS'), findsOneWidget);
    expect(find.text('LOSSES'), findsOneWidget);
    expect(find.text('WIN RATE'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the record strip reports the real win rate once played', (
    tester,
  ) async {
    await _pump(
      tester,
      const SportingRecordStrip(
        record: SportingRecord(played: 4, wins: 3, losses: 1, draws: 0),
      ),
    );

    expect(find.text('4'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the first-match card points at a real tournament list', (
    tester,
  ) async {
    var taps = 0;
    await _pump(tester, FirstMatchCard(onFindTournament: () => taps++));

    expect(find.text('Your journey starts here'), findsOneWidget);
    expect(
      find.text(
        'Play your first official match to start building your sporting '
        'record.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Find a tournament'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the passport holds together on a narrow phone at 1.3 text', (
    tester,
  ) async {
    await _pump(
      tester,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SportsPassportCard(
            account: _account(
              displayName: 'Muhammad Abdul Rahman Qureshi',
              city: 'Karachi, Pakistan',
            ),
            onEditProfile: () {},
          ),
          const SizedBox(height: 16),
          const SportingRecordStrip(
            record: SportingRecord(played: 12, wins: 10, losses: 1, draws: 1),
          ),
        ],
      ),
      size: const Size(320, 844),
      textScale: 1.3,
    );

    expect(find.text('Muhammad Abdul Rahman Qureshi'), findsOneWidget);
    expect(find.text('83%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a member with no name still gets a readable handle', (
    tester,
  ) async {
    await _pump(
      tester,
      SportsPassportCard(
        account: _account(displayName: '   '),
        onEditProfile: () {},
      ),
    );

    expect(find.text('@zara.q'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
