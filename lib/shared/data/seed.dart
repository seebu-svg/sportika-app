import 'dart:math';

import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/official_result.dart';
import 'package:sportika/features/personal_games/scoring/cricket/cricket.dart';
import 'package:sportika/features/personal_games/scoring/futsal/futsal.dart';
import 'package:sportika/features/personal_games/scoring/padel/padel.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/models/tournament_engine.dart';

/// Everything the prototype ships with on first launch.
///
/// Match logs here are generated with the same sport engines the app uses,
/// so demo fixtures always contain rule-legal sequences rather than typed-in
/// scores.
class SeedWorld {
  final List<Account> accounts;
  final List<Squad> squads;
  final List<Tournament> tournaments;
  final List<Entry> entries;
  final List<Fixture> fixtures;
  final List<PersonalMatch> personal;
  final List<AppNotification> notifications;

  SeedWorld({
    required this.accounts,
    required this.squads,
    required this.tournaments,
    required this.entries,
    required this.fixtures,
    required this.personal,
    required this.notifications,
  });
}

/// The document a live build starts from.
///
/// Nothing here is invented: tournaments, fixtures, teams and scorecards come
/// from PostgreSQL, and an account that has played nothing genuinely has no
/// history. Empty lists, not the fictional Karachi world.
SeedWorld emptySeedWorld() => SeedWorld(
  accounts: [],
  squads: [],
  tournaments: [],
  entries: [],
  fixtures: [],
  personal: [],
  notifications: [],
);

SeedWorld buildSeed() {
  final now = DateTime.now();
  final day = now.day, mon = now.month, yr = now.year;
  DateTime at(int daysFromNow, {int hour = 15, int minute = 0}) =>
      DateTime(yr, mon, day + daysFromNow, hour, minute);

  // ── Accounts ───────────────────────────────────────────────────────────
  final seebu = Account(
    id: 'acc-seebu',
    displayName: 'Seebu Ali',
    email: 'seebu@sportika.pk',
    city: 'Karachi',
    roles: [UserRole.player, UserRole.scorer],
  );
  final zain = Account(
    id: 'acc-zain',
    displayName: 'Zain Rehman',
    email: 'zain@sportika.pk',
    city: 'Karachi',
    roles: [UserRole.player],
  );
  final haris = Account(
    id: 'acc-haris',
    displayName: 'Haris Nadeem',
    email: 'haris@sportika.pk',
    city: 'Karachi',
    roles: [UserRole.player, UserRole.scorer],
  );
  final maria = Account(
    id: 'acc-maria',
    displayName: 'Maria Fatima',
    email: 'maria@sportika.pk',
    city: 'Clifton',
    roles: [UserRole.player, UserRole.scorer],
  );
  final bilal = Account(
    id: 'acc-bilal',
    displayName: 'Bilal Ahmed',
    email: 'bilal@sportika.pk',
    city: 'DHA',
    roles: [UserRole.player],
  );
  final sana = Account(
    id: 'acc-sana',
    displayName: 'Sana Khan',
    email: 'sana@sportika.pk',
    city: 'Gulberg',
    roles: [UserRole.player],
  );
  final yasir = Account(
    id: 'acc-yasir',
    displayName: 'Yasir Malik',
    email: 'yasir@sportika.pk',
    city: 'Karachi',
    roles: [UserRole.organizer, UserRole.scorer],
  );
  final imran = Account(
    id: 'acc-imran',
    displayName: 'Imran Shah',
    email: 'imran@sportika.pk',
    city: 'Lahore',
    roles: [UserRole.organizer],
  );

  final accounts = [seebu, zain, haris, maria, bilal, sana, yasir, imran];

  // ── Squads the signed-in player owns ───────────────────────────────────
  final squads = [
    Squad(
      id: 'sqd-strikers',
      ownerId: seebu.id,
      name: 'Sportika Strikers',
      sport: Sport.cricket,
      type: EntryType.team,
      memberAccountIds: [seebu.id, zain.id, haris.id, maria.id, bilal.id],
      createdAt: at(-21),
    ),
    Squad(
      id: 'sqd-padel-pair',
      ownerId: seebu.id,
      name: 'Seebu / Zain',
      sport: Sport.padel,
      type: EntryType.pair,
      memberAccountIds: [seebu.id, zain.id],
      createdAt: at(-14),
    ),
    Squad(
      id: 'sqd-futsal',
      ownerId: seebu.id,
      name: 'Sea View FC',
      sport: Sport.futsal,
      type: EntryType.team,
      memberAccountIds: [seebu.id, zain.id, bilal.id],
      createdAt: at(-9),
    ),
  ];

  // ── Tournaments ────────────────────────────────────────────────────────
  final padelRules = SportEngines.rulesFor(Sport.padel, 'Best of 3 sets');
  final cricketRules = SportEngines.rulesFor(Sport.cricket, 'T10 · 10 overs');
  final futsalRules = SportEngines.rulesFor(
    Sport.futsal,
    '2 × 20 min · knockout',
  );
  final badmintonRules = SportEngines.rulesFor(
    Sport.badminton,
    'Best of 3 games',
  );

  final padelCup = Tournament(
    id: 'trn-padel-cup',
    organizerId: yasir.id,
    name: 'Karachi Padel Cup',
    city: 'Karachi',
    sport: Sport.padel,
    formatLabel: 'Knockout · best of 3 sets',
    format: TournamentFormat.knockout,
    entryType: EntryType.pair,
    startsAt: at(-2),
    endsAt: at(4),
    registrationLimit: 8,
    entryFee: 'PKR 6,000 / pair',
    matchRules: SportEngines.describeRules(Sport.padel, padelRules),
    rules: padelRules,
    status: TournamentStatus.inProgress,
    createdAt: at(-30),
  );
  final t10 = Tournament(
    id: 'trn-t10',
    organizerId: yasir.id,
    name: 'Sea View T10 League',
    city: 'Karachi',
    sport: Sport.cricket,
    formatLabel: 'Group play · T10',
    format: TournamentFormat.group,
    entryType: EntryType.team,
    startsAt: at(-6),
    endsAt: at(10),
    registrationLimit: 12,
    entryFee: 'PKR 15,000 / team',
    matchRules: SportEngines.describeRules(Sport.cricket, cricketRules),
    rules: cricketRules,
    status: TournamentStatus.inProgress,
    createdAt: at(-40),
  );
  final futsalCup = Tournament(
    id: 'trn-futsal',
    organizerId: imran.id,
    name: 'Clifton Futsal Championship',
    city: 'Karachi',
    sport: Sport.futsal,
    formatLabel: 'Knockout · 2 × 20 min',
    format: TournamentFormat.knockout,
    entryType: EntryType.team,
    startsAt: at(1),
    endsAt: at(6),
    registrationLimit: 16,
    entryFee: 'PKR 8,000 / team',
    matchRules: SportEngines.describeRules(Sport.futsal, futsalRules),
    rules: futsalRules,
    status: TournamentStatus.open,
    createdAt: at(-12),
  );
  final badmintonOpen = Tournament(
    id: 'trn-badminton',
    organizerId: yasir.id,
    name: 'Winter Badminton Open',
    city: 'Lahore',
    sport: Sport.badminton,
    formatLabel: 'Group play · best of 3',
    format: TournamentFormat.group,
    entryType: EntryType.pair,
    startsAt: at(-24),
    endsAt: at(-18),
    registrationLimit: 12,
    entryFee: 'PKR 4,000 / pair',
    matchRules: SportEngines.describeRules(Sport.badminton, badmintonRules),
    rules: badmintonRules,
    status: TournamentStatus.completed,
    createdAt: at(-52),
  );
  final tournaments = [padelCup, t10, futsalCup, badmintonOpen];

  // ── Entries ────────────────────────────────────────────────────────────
  Entry mk(
    String id,
    Tournament t,
    String label,
    List<String> members,
    EntryStatus status, {
    String? squadId,
    int ago = 10,
  }) => Entry(
    id: id,
    tournamentId: t.id,
    squadId: squadId,
    captainAccountId: members.first,
    label: label,
    memberAccountIds: members,
    status: status,
    submittedAt: at(-ago),
  );

  final entries = [
    // Padel cup - four confirmed pairs (seeded in this order).
    mk(
      'ent-p1',
      padelCup,
      'Seebu / Zain',
      [seebu.id, zain.id],
      EntryStatus.confirmed,
      squadId: 'sqd-padel-pair',
      ago: 18,
    ),
    mk(
      'ent-p2',
      padelCup,
      'Haris / Maria',
      [haris.id, maria.id],
      EntryStatus.confirmed,
      ago: 17,
    ),
    mk(
      'ent-p3',
      padelCup,
      'Bilal / Sana',
      [bilal.id, sana.id],
      EntryStatus.confirmed,
      ago: 16,
    ),
    mk(
      'ent-p4',
      padelCup,
      'Kamran / Daniyal',
      [sana.id, bilal.id],
      EntryStatus.confirmed,
      ago: 15,
    ),
    mk(
      'ent-p5',
      padelCup,
      'Ali / Rehan',
      [zain.id, haris.id],
      EntryStatus.pending,
      ago: 2,
    ),

    // T10 - six teams across two groups, one awaiting review.
    mk(
      'ent-c1',
      t10,
      'Harbour Heroes',
      [seebu.id, zain.id, haris.id, maria.id, bilal.id],
      EntryStatus.confirmed,
      squadId: 'sqd-strikers',
      ago: 24,
    ),
    mk(
      'ent-c2',
      t10,
      'Clifton Chargers',
      [bilal.id, sana.id, zain.id, haris.id, maria.id],
      EntryStatus.confirmed,
      ago: 23,
    ),
    mk(
      'ent-c3',
      t10,
      'KDA Kings',
      [haris.id, maria.id, sana.id, bilal.id, zain.id],
      EntryStatus.confirmed,
      ago: 22,
    ),
    mk(
      'ent-c4',
      t10,
      'Gwadar Giants',
      [sana.id, bilal.id, zain.id, haris.id, maria.id],
      EntryStatus.confirmed,
      ago: 21,
    ),
    mk(
      'ent-c5',
      t10,
      'DHA Dynamos',
      [maria.id, zain.id, bilal.id, haris.id, sana.id],
      EntryStatus.confirmed,
      ago: 20,
    ),
    mk(
      'ent-c6',
      t10,
      'Korangi Storm',
      [zain.id, haris.id, maria.id, sana.id, bilal.id],
      EntryStatus.confirmed,
      ago: 19,
    ),
    mk(
      'ent-c7',
      t10,
      'Civic Centre XI',
      [maria.id, bilal.id],
      EntryStatus.pending,
      ago: 3,
    ),

    // Futsal - two confirmed, two pending for the organizer to review.
    mk(
      'ent-f1',
      futsalCup,
      'Sea View FC',
      [seebu.id, zain.id, bilal.id],
      EntryStatus.confirmed,
      squadId: 'sqd-futsal',
      ago: 8,
    ),
    mk(
      'ent-f2',
      futsalCup,
      'Clifton Five',
      [haris.id, maria.id, sana.id],
      EntryStatus.confirmed,
      ago: 7,
    ),
    mk(
      'ent-f3',
      futsalCup,
      'Gulberg United',
      [bilal.id, zain.id, haris.id],
      EntryStatus.pending,
      ago: 2,
    ),
    mk(
      'ent-f4',
      futsalCup,
      'Korangi Kids',
      [sana.id, maria.id, zain.id],
      EntryStatus.pending,
      ago: 1,
    ),

    // Badminton - completed event, four pairs in two groups.
    mk(
      'ent-b1',
      badmintonOpen,
      'Zain / Maria',
      [zain.id, maria.id],
      EntryStatus.confirmed,
      ago: 40,
    ),
    mk(
      'ent-b2',
      badmintonOpen,
      'Haris / Sana',
      [haris.id, sana.id],
      EntryStatus.confirmed,
      ago: 39,
    ),
    mk(
      'ent-b3',
      badmintonOpen,
      'Seebu / Bilal',
      [seebu.id, bilal.id],
      EntryStatus.confirmed,
      ago: 38,
    ),
    mk(
      'ent-b4',
      badmintonOpen,
      'Kamran / Ali',
      [maria.id, sana.id],
      EntryStatus.confirmed,
      ago: 37,
    ),
  ];
  final entriesById = {for (final e in entries) e.id: e};

  // ── Draws ──────────────────────────────────────────────────────────────
  final scorerPool = [haris.id, maria.id, seebu.id, yasir.id];

  List<Entry> confirmedOf(String trnId) => entries
      .where(
        (e) => e.tournamentId == trnId && e.status == EntryStatus.confirmed,
      )
      .toList();

  final fixtures = <Fixture>[
    ...TournamentEngine.knockoutDraw(
      tournament: padelCup,
      confirmed: confirmedOf(padelCup.id),
      scorerPool: scorerPool,
    ),
    ...TournamentEngine.groupDraw(
      tournament: t10,
      confirmed: confirmedOf(t10.id),
      groupCount: 2,
      scorerPool: scorerPool,
    ),
    ...TournamentEngine.knockoutDraw(
      tournament: futsalCup,
      confirmed: confirmedOf(futsalCup.id),
      scorerPool: scorerPool,
    ),
    ...TournamentEngine.groupDraw(
      tournament: badmintonOpen,
      confirmed: confirmedOf(badmintonOpen.id),
      groupCount: 2,
      scorerPool: scorerPool,
    ),
  ];

  // ── Scripted official matches ──────────────────────────────────────────
  Tournament trnOf(Fixture f) =>
      tournaments.firstWhere((t) => t.id == f.tournamentId);

  void finish(
    Fixture f,
    List<Map<String, dynamic>> log,
    FixtureStatus status, {
    String? submittedBy,
    String? publishedBy,
    String? startedBy,
  }) {
    f.events = log;
    f.status = status;
    if (startedBy != null) f.startedAt = at(-3);
    f.submittedByScorerId = submittedBy;
    if (publishedBy != null) {
      final p = SportEngines.progressOf(
        sport: trnOf(f).sport,
        sides: _sideLabels(f, fixtures, entriesById),
        rules: trnOf(f).rules,
        rawEvents: log,
      );
      f.result = OfficialResults.fromProgress(p, publishedById: publishedBy);
      f.completedAt = at(-1);
    }
  }

  // Padel: quarter-final 1 published 2-0, quarter-final 2 live, final upcoming.
  final padelFx = fixtures.where((f) => f.tournamentId == padelCup.id).toList()
    ..sort((a, b) => a.round.compareTo(b.round));
  if (padelFx.length >= 3) {
    finish(
      padelFx[0],
      _padelMatch(winner: 0, winnerSets: 2, loserSets: 0, seed: 11),
      FixtureStatus.published,
      submittedBy: haris.id,
      publishedBy: yasir.id,
      startedBy: haris.id,
    );
    // Live: one set done, second set in progress.
    finish(
      padelFx[1],
      _padelPartial(
        setWinner: 0,
        currentGames: [3, 2],
        currentPoints: [30, 15],
        seed: 7,
      ),
      FixtureStatus.live,
      startedBy: maria.id,
    );
    padelFx.last.scorerAccountIds = [seebu.id];
    padelFx[2].scheduledAt = at(3, hour: 18);
  }

  // T10 group: two published, one live.
  final cricketFx = fixtures.where((f) => f.tournamentId == t10.id).toList();
  if (cricketFx.length >= 3) {
    finish(
      cricketFx[0],
      _cricketMatch(seed: 3, battingFirst: 0),
      FixtureStatus.published,
      submittedBy: haris.id,
      publishedBy: yasir.id,
    );
    finish(
      cricketFx[1],
      _cricketMatch(seed: 19, battingFirst: 1),
      FixtureStatus.published,
      submittedBy: maria.id,
      publishedBy: yasir.id,
    );
    final live = _cricketInnings(
      seed: 5,
      battingFirst: 0,
      maxWickets: 4,
      overs: 6,
    );
    finish(cricketFx[2], live, FixtureStatus.live, submittedBy: seebu.id);
  }

  // Futsal: one fixture submitted for organizer review, one upcoming.
  final futsalFx =
      fixtures.where((f) => f.tournamentId == futsalCup.id).toList()
        ..sort((a, b) => a.round.compareTo(b.round));
  if (futsalFx.isNotEmpty) {
    finish(
      futsalFx.first,
      _futsalMatch(seed: 2, minutes: 20),
      FixtureStatus.submitted,
      submittedBy: yasir.id,
    );
    futsalFx.first.startedAt = at(-1);
  }

  // Badminton: whole group stage published, so standings and a champion show.
  final badmintonFx = fixtures
      .where((f) => f.tournamentId == badmintonOpen.id)
      .toList();
  for (var i = 0; i < badmintonFx.length; i++) {
    finish(
      badmintonFx[i],
      _badmintonMatch(seed: 100 + i, winner: i.isEven ? 0 : 1),
      FixtureStatus.published,
      submittedBy: maria.id,
      publishedBy: yasir.id,
    );
  }

  // One correction audit trail so the history screen has content (spec §4.5).
  if (badmintonFx.length > 1) {
    final f = badmintonFx[1];
    final previous = f.result!;
    final fixed = OfficialResult(
      sideScores: previous.sideScores,
      sideValues: [previous.sideValues[0], previous.sideValues[1] + 1],
      winnerIndex: previous.winnerIndex,
      headline: 'Corrected result published',
      detail: 'Scorer mis-entered the third game.',
      publishedAt: at(-1),
      publishedById: yasir.id,
    );
    f.corrections = [
      ResultCorrection(
        id: 'corr-1',
        previous: previous,
        current: fixed,
        reason: 'Scorer mis-entered the third game; games total corrected.',
        byAccountId: yasir.id,
        at: at(-1),
      ),
    ];
    f.result = fixed;
  }

  // One escalated dispute, owned by the tournament organizer.
  if (cricketFx.length > 3) {
    cricketFx[3].disputeNote =
        'Home team claims the last over was scored as a no-ball.';
    cricketFx[3].disputeRaisedBy = seebu.id;
    cricketFx[3].disputeResolved = false;
  }

  // ── Personal scorecards (private to their owner) ───────────────────────
  final personal = [
    PersonalMatch(
      id: 'pm-cricket-live',
      ownerId: seebu.id,
      sport: Sport.cricket,
      formatLabel: 'T5 · 5 overs',
      sideNames: ['Strikers', 'Neighbours'],
      events: _cricketInnings(
        seed: 41,
        battingFirst: 0,
        maxWickets: 3,
        overs: 5,
      ),
      rules: SportEngines.rulesFor(Sport.cricket, 'T5 · 5 overs'),
      status: PersonalMatchStatus.inProgress,
      createdAt: at(0, hour: 9),
      updatedAt: at(0, hour: 10),
    ),
    PersonalMatch(
      id: 'pm-padel-done',
      ownerId: seebu.id,
      sport: Sport.padel,
      formatLabel: 'Best of 3 sets',
      sideNames: ['Seebu / Zain', 'Haris / Maria'],
      events: _padelMatch(winner: 1, winnerSets: 2, loserSets: 1, seed: 23),
      rules: SportEngines.rulesFor(Sport.padel, 'Best of 3 sets'),
      status: PersonalMatchStatus.completed,
      createdAt: at(-4),
      updatedAt: at(-4, hour: 20),
      autoCompletedReason: 'Sets to win reached (2)',
    ),
    PersonalMatch(
      id: 'pm-futsal-done',
      ownerId: seebu.id,
      sport: Sport.futsal,
      formatLabel: '2 × 15 min',
      sideNames: ['Sea View FC', 'Office Team'],
      events: _futsalMatch(seed: 8, minutes: 15),
      rules: SportEngines.rulesFor(Sport.futsal, '2 × 15 min'),
      status: PersonalMatchStatus.completed,
      createdAt: at(-8),
      updatedAt: at(-8, hour: 19),
      autoCompletedReason: 'Match ended by scorer/organizer',
    ),
    // A second owner's card proves personal records stay private (spec §2.3).
    PersonalMatch(
      id: 'pm-zain-same',
      ownerId: zain.id,
      sport: Sport.padel,
      formatLabel: 'Best of 3 sets',
      sideNames: ['Seebu / Zain', 'Haris / Maria'],
      events: _padelMatch(winner: 0, winnerSets: 2, loserSets: 0, seed: 77),
      rules: SportEngines.rulesFor(Sport.padel, 'Best of 3 sets'),
      status: PersonalMatchStatus.completed,
      createdAt: at(-4),
      updatedAt: at(-4, hour: 21),
      autoCompletedReason: 'Sets to win reached (2)',
    ),
  ];

  // ── Notifications ──────────────────────────────────────────────────────
  final notifications = [
    AppNotification(
      id: 'ntf-1',
      accountId: seebu.id,
      kind: NotificationKind.scorerAssignment,
      title: 'You are scoring the Padel final',
      body:
          'Karachi Padel Cup · ${padelFx.isNotEmpty ? padelFx.last.stage : 'Final'} · '
          'court assignment confirmed.',
      route: 'scorer',
      read: false,
      at: at(0, hour: 8),
    ),
    AppNotification(
      id: 'ntf-2',
      accountId: seebu.id,
      kind: NotificationKind.resultPublished,
      title: 'Official result published',
      body: 'Sea View T10 League · group stage result is now official.',
      route: 'matchCenter',
      read: false,
      at: at(-1, hour: 18),
    ),
    AppNotification(
      id: 'ntf-3',
      accountId: seebu.id,
      kind: NotificationKind.entryDecision,
      title: 'Entry confirmed',
      body: 'Sea View FC accepted into the Clifton Futsal Championship.',
      route: 'tournaments',
      read: true,
      at: at(-2, hour: 11),
    ),
    AppNotification(
      id: 'ntf-4',
      accountId: yasir.id,
      kind: NotificationKind.resultSubmitted,
      title: 'Score submitted for review',
      body: 'Clifton Futsal Championship · semi-final score awaiting your review.',
      route: 'organizer',
      read: false,
      at: at(0, hour: 9),
    ),
    AppNotification(
      id: 'ntf-5',
      accountId: yasir.id,
      kind: NotificationKind.dispute,
      title: 'Escalated result dispute',
      body: 'Sea View T10 League · a player flagged a scoring question on a published result.',
      route: 'organizer',
      read: false,
      at: at(0, hour: 7),
    ),
  ];

  // Additional fictional community profiles and upcoming competitions.
  const names = [
    'Ahmed Raza',
    'Hamza Farooq',
    'Ayesha Siddiqui',
    'Omar Iqbal',
    'Hassan Javed',
    'Fatima Noor',
    'Saad Qureshi',
    'Usman Tariq',
    'Hina Aslam',
    'Ali Memon',
    'Daniyal Sheikh',
    'Zoya Ahmed',
    'Rafay Khan',
    'Anum Shah',
  ];
  for (var i = 0; i < names.length; i++) {
    accounts.add(
      Account(
        id: 'demo-player-$i',
        displayName: names[i],
        email: 'player$i@example.invalid',
        city: 'Karachi',
        roles: [UserRole.player],
      ),
    );
  }
  const teamNames = [
    'Clifton Aces',
    'DHA Falcons',
    'Karachi United',
    'Gulshan Smashers',
    'North Nazimabad XI',
    'Kokan Warriors',
    'Seaview Racquets',
  ];
  for (var i = 0; i < teamNames.length; i++) {
    squads.add(
      Squad(
        id: 'demo-team-$i',
        ownerId: 'demo-player-$i',
        name: teamNames[i],
        sport: Sport.values[i % 4],
        type: EntryType.team,
        memberAccountIds: [
          'demo-player-$i',
          'demo-player-${(i + 1) % names.length}',
        ],
        createdAt: at(-10),
      ),
    );
  }
  for (var i = 0; i < 4; i++) {
    final base = tournaments[i];
    tournaments.add(
      Tournament(
        id: 'demo-tournament-$i',
        organizerId: yasir.id,
        name: [
          'Karachi Champions Trophy',
          'Clifton Cricket Invitational',
          'DHA Futsal League',
          'Karachi Shuttle Masters',
        ][i],
        city: 'Karachi',
        sport: base.sport,
        formatLabel: base.formatLabel,
        format: base.format,
        entryType: base.entryType,
        startsAt: at(14 + i * 3),
        endsAt: at(17 + i * 3),
        registrationLimit: 16,
        entryFee: 'Free · community showcase',
        matchRules: base.matchRules,
        rules: Map.of(base.rules),
        status: TournamentStatus.open,
        createdAt: at(-2),
      ),
    );
  }
  // Independent showcase draws exercise official results and live assignments.
  var showcaseIndex = 0;
  for (final t in tournaments.skip(4)) {
    final participants = List.generate(
      6,
      (i) => Entry(
        id: '${t.id}-entry-$i',
        tournamentId: t.id,
        captainAccountId: 'demo-player-$i',
        label: teamNames[(i + t.sport.index) % teamNames.length],
        memberAccountIds: ['demo-player-$i'],
        status: EntryStatus.confirmed,
        submittedAt: at(-7),
      ),
    );
    entries.addAll(participants);
    for (final e in participants) {
      entriesById[e.id] = e;
    }
    final draw = TournamentEngine.groupDraw(
      tournament: t,
      confirmed: participants,
      groupCount: 1,
      scorerPool: scorerPool,
    );
    fixtures.addAll(draw);
    for (final f in draw) {
      final log = switch (t.sport) {
        Sport.cricket => _cricketMatch(
          seed: 200 + showcaseIndex,
          battingFirst: 0,
        ),
        Sport.padel => _padelMatch(
          winner: 0,
          winnerSets: 2,
          loserSets: 1,
          seed: 200 + showcaseIndex,
        ),
        Sport.futsal => _futsalMatch(seed: 200 + showcaseIndex, minutes: 20),
        Sport.badminton => _badmintonMatch(
          seed: 200 + showcaseIndex,
          winner: 0,
        ),
      };
      if (showcaseIndex < 7) {
        finish(
          f,
          log,
          FixtureStatus.published,
          submittedBy: seebu.id,
          publishedBy: yasir.id,
          startedBy: seebu.id,
        );
      } else if (showcaseIndex < 13) {
        finish(
          f,
          log.take(6).toList(),
          FixtureStatus.live,
          startedBy: seebu.id,
        );
      }
      showcaseIndex++;
    }
    t.status = t.id == 'demo-tournament-0'
        ? TournamentStatus.completed
        : TournamentStatus.inProgress;
  }

  for (var i = personal.length; i < 10; i++) {
    final sport = Sport.values[i % 4];
    final format = [
      'T5 · 5 overs',
      'Best of 3 sets',
      '2 × 15 min',
      'Best of 3 games',
    ][i % 4];
    personal.add(
      PersonalMatch(
        id: 'demo-personal-$i',
        ownerId: seebu.id,
        sport: sport,
        formatLabel: format,
        sideNames: ['Clifton friends', 'DHA neighbours'],
        events: [],
        rules: SportEngines.rulesFor(sport, format),
        status: PersonalMatchStatus.inProgress,
        createdAt: at(-i),
        updatedAt: at(-i),
      ),
    );
  }
  for (var i = notifications.length; i < 15; i++) {
    notifications.add(
      AppNotification(
        id: 'demo-notification-$i',
        accountId: seebu.id,
        kind: NotificationKind.fixtureChange,
        title: 'Your next match is calling',
        body: 'Karachi community fixtures are open. Find your next game.',
        route: 'matchCenter',
        read: i.isEven,
        at: at(-i),
      ),
    );
  }

  return SeedWorld(
    accounts: accounts,
    squads: squads,
    tournaments: tournaments,
    entries: entries,
    fixtures: fixtures,
    personal: personal,
    notifications: notifications,
  );
}

List<String> _sideLabels(
  Fixture f,
  List<Fixture> all,
  Map<String, Entry> entriesById,
) => [
  OfficialResults.resolve(f.home, all, entriesById).label,
  OfficialResults.resolve(f.away, all, entriesById).label,
];

// ─── Event log generators ─────────────────────────────────────────────────
// Each helper produces rule-legal logs that the engines fold exactly like a
// real scoring session, with stable ids so replays stay idempotent.

int _seq = 0;
Map<String, dynamic> _ev(
  String kind,
  int? side,
  Map<String, dynamic> data, {
  DateTime? at,
}) => {
  'id': 'seed-ev-${_seq++}',
  'kind': kind,
  'side': side,
  'data': data,
  'at': (at ?? DateTime.now()).toIso8601String(),
  'by': 'seed',
};

/// Full padel match ending [winnerSets]-[loserSets].
List<Map<String, dynamic>> _padelMatch({
  required int winner,
  required int winnerSets,
  required int loserSets,
  required int seed,
}) {
  final rnd = Random(seed);
  final out = <Map<String, dynamic>>[];
  for (final setWinner in _setPattern(winner, winnerSets, loserSets)) {
    out.addAll(
      _padelSet(winnerOfSet: setWinner, loserGames: rnd.nextInt(5), rnd: rnd),
    );
  }
  return out;
}

/// Order the sets are won in, so the match only closes on the last one.
List<int> _setPattern(int winner, int winnerSets, int loserSets) {
  final p = <int>[];
  var w = winnerSets, l = loserSets;
  while (l > 0 && w > 1) {
    p
      ..add(1 - winner)
      ..add(winner);
    l--;
    w--;
  }
  while (l > 0) {
    p.add(1 - winner);
    l--;
  }
  while (w > 0) {
    p.add(winner);
    w--;
  }
  return p;
}

/// A 6-[loserGames] set. One winning game is held back so the set cannot
/// close before the final game is recorded.
List<Map<String, dynamic>> _padelSet({
  required int winnerOfSet,
  required int loserGames,
  required Random rnd,
}) {
  final w = winnerOfSet, l = 1 - winnerOfSet;
  final lg = loserGames.clamp(0, 4);
  final out = <Map<String, dynamic>>[];
  var wLeft = 5, lLeft = lg;
  while (wLeft > 0 || lLeft > 0) {
    if (lLeft > 0 && (wLeft == 0 || rnd.nextBool())) {
      out.addAll(_padelGame(l, rnd.nextInt(3)));
      lLeft--;
    } else {
      out.addAll(_padelGame(w, rnd.nextInt(3)));
      wLeft--;
    }
  }
  out.addAll(_padelGame(w, rnd.nextInt(4))); // 6th game closes the set
  return out;
}

/// Points for one padel game won by [winner] with [loserPoints] (0–3).
List<Map<String, dynamic>> _padelGame(int winner, int loserPoints) {
  final l = 1 - winner;
  final lp = loserPoints.clamp(0, 3);
  final seq = <int>[];
  for (var i = 0; i < lp; i++) {
    seq
      ..add(winner)
      ..add(l);
  }
  // lp <= 2 closes at 4-lp; a 3-3 deuce needs two straight winners.
  seq.add(winner);
  if (lp == 3) seq.add(winner);
  for (
    var i = seq.where((s) => s == winner).length;
    i < (lp == 3 ? 5 : 4);
    i++
  ) {
    seq.add(winner);
  }
  return [for (final s in seq) _ev(PadelEngine.kPoint, s, {})];
}

/// A padel match stopped mid-way: one finished set plus a live set.
List<Map<String, dynamic>> _padelPartial({
  required int setWinner,
  required List<int> currentGames,
  required List<int> currentPoints,
  required int seed,
}) {
  final rnd = Random(seed);
  final out = <Map<String, dynamic>>[];
  out.addAll(_padelSet(winnerOfSet: setWinner, loserGames: 3, rnd: rnd));

  // Games of the set in play, interleaved so neither side reaches six.
  var g0 = currentGames[0], g1 = currentGames[1];
  while (g0 > 0 || g1 > 0) {
    if (g0 > 0 && (g1 == 0 || rnd.nextBool())) {
      out.addAll(_padelGame(0, rnd.nextInt(3)));
      g0--;
    } else {
      out.addAll(_padelGame(1, rnd.nextInt(3)));
      g1--;
    }
  }

  // Points of the game currently in play, given in tennis notation.
  final p0 = _notationPoints(currentPoints[0]),
      p1 = _notationPoints(currentPoints[1]);
  final pts = <int>[];
  for (var i = 0; i < p1; i++) {
    pts
      ..add(0)
      ..add(1);
  }
  for (var i = 0; i < p0 - p1; i++) {
    pts.add(0);
  }
  out.addAll([for (final s in pts) _ev(PadelEngine.kPoint, s, {})]);
  return out;
}

int _notationPoints(int v) => switch (v) {
  0 => 0,
  15 => 1,
  30 => 2,
  _ => 3,
};

/// Two-innings cricket match log; the engine decides the actual result.
List<Map<String, dynamic>> _cricketMatch({
  required int seed,
  required int battingFirst,
}) {
  final rnd = Random(seed);
  final overs = 10;
  final first = _inningsEvents(
    side: battingFirst,
    overs: overs,
    maxWickets: 10,
    rnd: rnd,
    chaseTarget: null,
  );
  final firstRuns = _sumRuns(first);
  final second = _inningsEvents(
    side: 1 - battingFirst,
    overs: overs,
    maxWickets: 10,
    rnd: rnd,
    chaseTarget: firstRuns + 1,
  );
  return [...first, ...second];
}

/// A single unfinished innings, used for live fixtures and personal cards.
List<Map<String, dynamic>> _cricketInnings({
  required int seed,
  required int battingFirst,
  required int maxWickets,
  required int overs,
}) => _inningsEvents(
  side: battingFirst,
  overs: overs,
  maxWickets: maxWickets,
  rnd: Random(seed),
  chaseTarget: null,
);

List<Map<String, dynamic>> _inningsEvents({
  required int side,
  required int overs,
  required int maxWickets,
  required Random rnd,
  required int? chaseTarget,
}) {
  final out = <Map<String, dynamic>>[];
  // Only legal deliveries advance [legalBalls], mirroring the engine, so the
  // generated log actually closes its innings under the same rules.
  var legalBalls = 0, runs = 0, wickets = 0;
  while (legalBalls < overs * 6 && wickets < maxWickets) {
    if (chaseTarget != null && runs >= chaseTarget) break;
    final roll = rnd.nextInt(100);
    Map<String, dynamic> ev;
    if (roll < 6) {
      ev = _ev(CricketEngine.kBall, side, {'runs': 0, 'extra': 'wide'});
      runs += 1;
    } else if (roll < 9) {
      ev = _ev(CricketEngine.kBall, side, {'runs': 1, 'extra': 'noball'});
      runs += 2;
    } else {
      final (runsOffBat, isWicket) = switch (roll) {
        < 40 => (0, false),
        < 68 => (1, false),
        < 76 => (2, false),
        < 80 => (3, false),
        < 90 => (4, false),
        < 95 => (6, false),
        _ => (0, true),
      };
      ev = _ev(CricketEngine.kBall, side, {
        'runs': runsOffBat,
        if (isWicket) 'wicket': true,
      });
      legalBalls++;
      runs += runsOffBat;
      if (isWicket) wickets++;
    }
    out.add(ev);
  }
  return out;
}

int _sumRuns(List<Map<String, dynamic>> log) {
  var total = 0;
  for (final e in log) {
    final d = e['data'] as Map<String, dynamic>;
    total += (d['runs'] as num?)?.toInt() ?? 0;
    if (d['extra'] == 'wide' || d['extra'] == 'noball') total += 1;
  }
  return total;
}

/// Futsal log: clock control events plus goals in each half.
List<Map<String, dynamic>> _futsalMatch({
  required int seed,
  required int minutes,
}) {
  final rnd = Random(seed);
  final base = DateTime.now().subtract(const Duration(hours: 3));
  final out = <Map<String, dynamic>>[
    _ev(FutsalEngine.kClock, null, {'action': 'start'}, at: base),
  ];
  for (var half = 0; half < 2; half++) {
    final goals = rnd.nextInt(4);
    for (var g = 0; g < goals; g++) {
      out.add(
        _ev(FutsalEngine.kGoal, rnd.nextInt(2), {
          'half': half,
        }, at: base.add(Duration(minutes: half * minutes + 3 + g * 4))),
      );
    }
    out.add(
      _ev(FutsalEngine.kClock, null, {
        'action': 'stop',
      }, at: base.add(Duration(minutes: half * minutes + minutes - 1))),
    );
    out.add(
      _ev(FutsalEngine.kClock, null, {
        'action': 'end_half',
      }, at: base.add(Duration(minutes: half * minutes + minutes))),
    );
    if (half == 0) {
      out.add(
        _ev(FutsalEngine.kClock, null, {
          'action': 'resume',
        }, at: base.add(Duration(minutes: minutes + 10))),
      );
    }
  }
  out.add(
    _ev(FutsalEngine.kClock, null, {
      'action': 'end_match',
    }, at: base.add(Duration(minutes: 2 * minutes + 12))),
  );
  return out;
}

/// Badminton match log won [gamesTo]-[loserGames] by [winner].
List<Map<String, dynamic>> _badmintonMatch({
  required int seed,
  required int winner,
  int gamesTo = 2,
}) {
  final rnd = Random(seed);
  final out = <Map<String, dynamic>>[];
  final loserGames = rnd.nextInt(gamesTo); // never reaches gamesTo first
  final pattern = <int>[];
  var w = gamesTo, l = loserGames;
  while (l > 0 && w > 1) {
    pattern
      ..add(1 - winner)
      ..add(winner);
    l--;
    w--;
  }
  while (w > 0) {
    pattern.add(winner);
    w--;
  }
  for (final gameWinner in pattern) {
    out.addAll(_badmintonGame(gameWinner, 8 + rnd.nextInt(11)));
  }
  return out;
}

List<Map<String, dynamic>> _badmintonGame(int winner, int loserScore) {
  final l = 1 - winner;
  final ls = loserScore.clamp(0, 19);
  final seq = <int>[];
  for (var i = 0; i < ls; i++) {
    seq
      ..add(winner)
      ..add(l);
  }
  for (var i = 0; i < 21 - ls; i++) {
    seq.add(winner);
  }
  return [for (final s in seq) _ev('rally', s, {})];
}

// ─── Standalone official matches ──────────────────────────────────────────
// Three matches cover the states the match module has to render: one being
// scored live, one open for invitations, and one already published. They live
// beside the tournament fixtures, not inside them.

/// Turns an engine-shaped event log into sequenced match events.
List<MatchEvent> _matchLog(
  List<Map<String, dynamic>> raw, {
  required String by,
}) {
  var seq = 0;
  return [
    for (final e in raw)
      MatchEvent(
        id: e['id'] as String? ?? 'ev-${seq + 1}',
        seq: ++seq,
        clientId: e['id'] as String? ?? 'ev-$seq',
        kind: e['kind'] as String? ?? '',
        side: (e['side'] as num?)?.toInt(),
        data: Map<String, dynamic>.from(e['data'] as Map? ?? const {}),
        at: DateTime.tryParse(e['at'] as String? ?? '') ?? DateTime.now(),
        byAccountId: by,
      ),
  ];
}

List<SportMatch> matchSeed(List<Account> accounts, {DateTime? now}) {
  final base = now ?? DateTime.now();
  String name(int i) => i < accounts.length
      ? accounts[i].displayName
      : 'Sportika member ${i + 1}';
  String pid(int i) =>
      i < accounts.length ? accounts[i].id : 'acc-member-${i + 1}';

  final organizer = pid(0);
  final scorer = pid(1);

  final cricketRules = {
    ...SportEngines.rulesFor(Sport.cricket, 'T10 · 10 overs'),
    'discipline': 'team',
  };
  final cricketLog = _matchLog([
    for (var i = 0; i < 9; i++)
      _ev(CricketEngine.kBall, 0, {
        'runs': i.isEven ? 1 : (i == 7 ? 4 : 0),
        'batter': name(2),
        'bowler': name(3),
      }, at: base.subtract(Duration(minutes: 30 - i * 2))),
  ], by: scorer);

  final badmintonRules = {
    ...SportEngines.rulesFor(
      Sport.badminton,
      SportEngines.formatsFor(Sport.badminton).first,
    ),
    'discipline': 'singles',
  };
  final badmintonRaw = _badmintonMatch(seed: 7, winner: 0);
  final badmintonLog = _matchLog(badmintonRaw, by: organizer);
  // The published result is the fold of the same rally log the match carries,
  // so the seeded result and the seeded events can never disagree.
  final badmintonFold = SportEngines.progressOf(
    sport: Sport.badminton,
    sides: [name(0), name(2)],
    rules: badmintonRules,
    rawEvents: badmintonRaw,
  );

  final padelRules = {
    ...SportEngines.rulesFor(
      Sport.padel,
      SportEngines.formatsFor(Sport.padel).first,
    ),
    'discipline': 'doubles',
  };

  final live = SportMatch(
    id: 'match-seed-cricket',
    sport: Sport.cricket,
    formatLabel: 'T10 · 10 overs',
    rules: cricketRules,
    title: 'Friday night tape-ball derby',
    venue: 'Gulberg Grounds, Karachi',
    scheduledAt: base.subtract(const Duration(minutes: 32)),
    visibility: MatchVisibility.public,
    organizerId: organizer,
    scorerId: scorer,
    status: FixtureStatus.live,
    sideNames: ['${name(2)} XI', '${name(3)} XI'],
    discipline: MatchDiscipline.team,
    capacity: 22,
    startedAt: base.subtract(const Duration(minutes: 31)),
    eventCount: cricketLog.length,
    createdAt: base.subtract(const Duration(days: 2)),
    participants: [
      MatchParticipant(
        profileId: organizer,
        displayName: name(0),
        side: 0,
        status: MatchParticipantStatus.accepted,
        invitedById: organizer,
      ),
      MatchParticipant(
        profileId: pid(2),
        displayName: name(2),
        side: 0,
        status: MatchParticipantStatus.accepted,
        invitedById: organizer,
      ),
      MatchParticipant(
        profileId: pid(3),
        displayName: name(3),
        side: 1,
        status: MatchParticipantStatus.accepted,
        invitedById: organizer,
      ),
      MatchParticipant(
        profileId: pid(4),
        displayName: name(4),
        side: 1,
        status: MatchParticipantStatus.invited,
        invitedById: organizer,
      ),
    ],
    events: cricketLog,
  );

  final upcoming = SportMatch(
    id: 'match-seed-padel',
    sport: Sport.padel,
    formatLabel: SportEngines.formatsFor(Sport.padel).first,
    rules: padelRules,
    title: 'Saturday morning padel ladder',
    venue: 'Clifton Padel Courts',
    scheduledAt: base.add(const Duration(days: 1, hours: 2)),
    visibility: MatchVisibility.public,
    organizerId: scorer,
    status: FixtureStatus.upcoming,
    sideNames: ['${name(1)} & ${name(5)}', '${name(6)} & ${name(7)}'],
    discipline: MatchDiscipline.doubles,
    capacity: 4,
    createdAt: base.subtract(const Duration(days: 1)),
    participants: [
      MatchParticipant(
        profileId: scorer,
        displayName: name(1),
        side: 0,
        status: MatchParticipantStatus.accepted,
        invitedById: scorer,
      ),
      MatchParticipant(
        profileId: pid(5),
        displayName: name(5),
        side: 0,
        status: MatchParticipantStatus.accepted,
        invitedById: scorer,
      ),
      MatchParticipant(
        profileId: pid(6),
        displayName: name(6),
        side: 1,
        status: MatchParticipantStatus.invited,
        invitedById: scorer,
      ),
    ],
  );

  final published = SportMatch(
    id: 'match-seed-badminton',
    sport: Sport.badminton,
    formatLabel: SportEngines.formatsFor(Sport.badminton).first,
    rules: badmintonRules,
    title: 'Club championship · court 3',
    venue: 'Johar Sports Club',
    scheduledAt: base.subtract(const Duration(days: 3)),
    visibility: MatchVisibility.public,
    organizerId: organizer,
    scorerId: scorer,
    status: FixtureStatus.published,
    sideNames: [name(0), name(2)],
    discipline: MatchDiscipline.singles,
    capacity: 2,
    startedAt: base.subtract(const Duration(days: 3, hours: 1)),
    submittedAt: base.subtract(const Duration(days: 3, minutes: 40)),
    completedAt: base.subtract(const Duration(days: 3, minutes: 30)),
    publishedAt: base.subtract(const Duration(days: 3, minutes: 20)),
    eventCount: badmintonLog.length,
    createdAt: base.subtract(const Duration(days: 5)),
    participants: [
      MatchParticipant(
        profileId: organizer,
        displayName: name(0),
        side: 0,
        status: MatchParticipantStatus.accepted,
        invitedById: organizer,
      ),
      MatchParticipant(
        profileId: pid(2),
        displayName: name(2),
        side: 1,
        status: MatchParticipantStatus.accepted,
        invitedById: organizer,
      ),
    ],
    events: badmintonLog,
    result: OfficialResult(
      sideScores: badmintonFold.scoreDisplay,
      sideValues: badmintonFold.scoreValues,
      winnerIndex: badmintonFold.winnerIndex,
      headline:
          '${badmintonFold.sides[badmintonFold.winnerIndex]} won '
          '${badmintonFold.scoreValues[badmintonFold.winnerIndex]}-'
          '${badmintonFold.scoreValues[1 - badmintonFold.winnerIndex]}',
      detail: badmintonFold.detailRows.join(' · '),
      publishedAt: base.subtract(const Duration(days: 3, minutes: 20)),
      publishedById: organizer,
    ),
  );

  return [live, upcoming, published];
}
