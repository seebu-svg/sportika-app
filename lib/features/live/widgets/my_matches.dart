import 'package:flutter/foundation.dart';

import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/profile/widgets/sporting_record.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';

/// Where a My Matches row was read from.
///
/// Both sources are official: [officialMatch] is the match module's own
/// aggregate (`public.matches`), [tournamentFixture] is a fixture the member
/// appeared in. A live build projects the second from the first, which is why
/// the list below de-duplicates them.
enum MyMatchSource { officialMatch, tournamentFixture }

/// Why the member is on a match. Never inferred: a match is the organizer's,
/// the appointed scorer's, a joined player's, or a pending invitation.
enum MyMatchRole { playing, organizing, scoring, invited }

extension MyMatchRoleX on MyMatchRole {
  String get label => switch (this) {
    MyMatchRole.playing => 'Playing',
    MyMatchRole.organizing => 'Organizer',
    MyMatchRole.scoring => 'Scorer',
    MyMatchRole.invited => 'Invited',
  };
}

/// The four states the filter row exposes.
///
/// [completed] collects everything that is no longer upcoming or live, so an
/// awaiting-review or cancelled match stays reachable; each row keeps drawing
/// its own exact status pill, so no match is ever relabelled as finished when
/// its result was not published.
enum MyMatchPhase { all, upcoming, live, completed }

/// One row of the unified list, independent of the model it came from.
@immutable
class MyMatchRecord {
  const MyMatchRecord({
    required this.key,
    required this.source,
    required this.sport,
    required this.context,
    required this.sideA,
    required this.sideB,
    required this.status,
    required this.scheduledAt,
    required this.role,
    this.scoreA,
    this.scoreB,
    this.venue = '',
    this.mySide,
    this.winnerIndex,
    this.matchId,
    this.fixtureId,
  });

  /// Stable identity for a list row and for de-duplication.
  final String key;
  final MyMatchSource source;
  final Sport sport;

  /// Tournament name and stage, or the match's own title.
  final String context;
  final String sideA;
  final String sideB;

  /// Formatted score per side: the published result first, the live fold when
  /// the match is still running, and null when there is nothing to show.
  final String? scoreA;
  final String? scoreB;

  final FixtureStatus status;
  final DateTime scheduledAt;
  final String venue;
  final MyMatchRole role;

  /// The member's side (0/1) when they were an accepted player, else null.
  final int? mySide;

  /// Published winner (0/1), -1 for a draw, null when nothing is published.
  final int? winnerIndex;

  final String? matchId;
  final String? fixtureId;

  MyMatchPhase get phase => switch (status) {
    FixtureStatus.upcoming => MyMatchPhase.upcoming,
    FixtureStatus.live => MyMatchPhase.live,
    _ => MyMatchPhase.completed,
  };

  bool get isLive => status == FixtureStatus.live;

  /// Only a published (or walked-over) result proves anything about the
  /// member's record; a submitted, cancelled or unplayed match never does.
  bool get publishedResult =>
      winnerIndex != null &&
      (status == FixtureStatus.published || status == FixtureStatus.walkover);

  SportingOutcome get outcome {
    if (!publishedResult || mySide == null) return SportingOutcome.unrecorded;
    final winner = winnerIndex!;
    if (winner != 0 && winner != 1) return SportingOutcome.draw;
    return winner == mySide ? SportingOutcome.win : SportingOutcome.loss;
  }

  bool matchesQuery(String needle) =>
      sideA.toLowerCase().contains(needle) ||
      sideB.toLowerCase().contains(needle) ||
      context.toLowerCase().contains(needle) ||
      venue.toLowerCase().contains(needle) ||
      sport.label.toLowerCase().contains(needle) ||
      role.label.toLowerCase().contains(needle);
}

/// Every official match the member is on, from both controllers, without
/// repeats.
///
/// The match module is authoritative: in a live build a tournament fixture is
/// projected from the same match row, so a fixture is dropped when a match
/// already represents it (same id, or the same tournament/fixture pair). A row
/// exists only because a controller returned it; nothing is estimated.
List<MyMatchRecord> myMatchesFor({
  required String? accountId,
  required MatchController matches,
  required FixturesController fixtures,
  required TournamentsController tournaments,
}) {
  final records = <MyMatchRecord>[];
  if (accountId == null) return records;

  final representedIds = <String>{};
  final representedLinks = <String>{};

  for (final match in matches.matches) {
    final role = _roleOfMatch(match, accountId);
    if (role == null) continue;
    final fixtureId = match.fixtureId;
    final tournamentId = match.tournamentId;
    if (fixtureId != null) {
      representedIds.add(fixtureId);
      if (tournamentId != null) {
        representedLinks.add('$tournamentId/$fixtureId');
      }
    }
    records.add(
      _fromMatch(
        match,
        accountId: accountId,
        role: role,
        progress: match.events.isEmpty ? null : matches.progressOf(match),
        tournaments: tournaments,
      ),
    );
  }

  final myEntryIds = _myEntryIds(tournaments, accountId);
  for (final fixture in fixtures.appearancesOf(accountId)) {
    // A live build projects a fixture from the match row above; when that row
    // is already in the list this fixture is the same match. When it is not -
    // a drawn fixture has no match participants, only entrants - the fixture
    // is the member's row, so it must survive this de-duplication.
    if (representedIds.contains(fixture.id) ||
        representedLinks.contains('${fixture.tournamentId}/${fixture.id}')) {
      continue;
    }
    final tournament = fixtures.tournamentOf(fixture);
    final role = _roleOfFixture(
      fixture,
      accountId: accountId,
      myEntryIds: myEntryIds,
      organizerId: tournament?.organizerId,
    );
    if (role == null) continue;
    records.add(
      _fromFixture(
        fixture,
        tournament: tournament,
        role: role,
        mySide: _sideOf(fixture, myEntryIds),
        progress: fixture.events.isEmpty
            ? null
            : fixtures.progressOfFixture(fixture),
        labels: fixtures.sideLabelsOf(fixture),
      ),
    );
  }

  records.sort(_compare);
  return records;
}

/// Rows matching one filter combination. Search and filters only ever narrow
/// the rows the controllers returned.
List<MyMatchRecord> filterMyMatches(
  Iterable<MyMatchRecord> records, {
  MyMatchPhase phase = MyMatchPhase.all,
  Sport? sport,
  String query = '',
}) {
  final needle = query.trim().toLowerCase();
  return [
    for (final record in records)
      if ((phase == MyMatchPhase.all || record.phase == phase) &&
          (sport == null || record.sport == sport) &&
          (needle.isEmpty || record.matchesQuery(needle)))
        record,
  ];
}

/// The member's official record over the rows that carry a published result.
///
/// Same rule as the Me passport: a draw is played but undecided, and a match
/// without a published result is left out rather than counted as a defeat.
SportingRecord recordOf(Iterable<MyMatchRecord> records) {
  var played = 0, wins = 0, losses = 0, draws = 0;
  for (final record in records) {
    switch (record.outcome) {
      case SportingOutcome.win:
        played++;
        wins++;
      case SportingOutcome.loss:
        played++;
        losses++;
      case SportingOutcome.draw:
        played++;
        draws++;
      case SportingOutcome.unrecorded:
        break;
    }
  }
  return SportingRecord(
    played: played,
    wins: wins,
    losses: losses,
    draws: draws,
  );
}

// ── Sources ────────────────────────────────────────────────────────────────

MyMatchRecord _fromMatch(
  SportMatch match, {
  required String accountId,
  required MyMatchRole role,
  required MatchProgress? progress,
  required TournamentsController tournaments,
}) {
  final tournamentId = match.tournamentId;
  final tournament = tournamentId == null
      ? null
      : tournaments.tournamentById(tournamentId);
  final stage = (match.rules['stage'] as String?)?.trim() ?? '';
  final context = [
    if (tournament != null && tournament.name.trim().isNotEmpty)
      tournament.name.trim()
    else
      match.title.trim(),
    if (stage.isNotEmpty) stage,
  ].where((part) => part.isNotEmpty).join(' · ');

  final participant = match.participantOf(accountId);
  final scores = _scores(
    match.result?.sideScores,
    progress,
    live: match.isLive,
  );

  return MyMatchRecord(
    key: 'match:${match.id}',
    source: MyMatchSource.officialMatch,
    sport: match.sport,
    context: context,
    sideA: match.sideNames.isNotEmpty && match.sideNames[0].trim().isNotEmpty
        ? match.sideNames[0].trim()
        : 'Side A',
    sideB: match.sideNames.length > 1 && match.sideNames[1].trim().isNotEmpty
        ? match.sideNames[1].trim()
        : 'Side B',
    scoreA: scores?[0],
    scoreB: scores?[1],
    status: match.status,
    scheduledAt: match.scheduledAt,
    venue: match.venue,
    role: role,
    mySide:
        participant != null &&
            participant.status == MatchParticipantStatus.accepted
        ? participant.side
        : null,
    winnerIndex: match.result?.winnerIndex,
    matchId: match.id,
  );
}

MyMatchRecord _fromFixture(
  Fixture fixture, {
  required Tournament? tournament,
  required MyMatchRole role,
  required int? mySide,
  required MatchProgress? progress,
  required List<String> labels,
}) {
  final stage = fixture.stage.trim();
  final context = [
    if (tournament != null && tournament.name.trim().isNotEmpty)
      tournament.name.trim(),
    if (stage.isNotEmpty) stage,
  ].where((part) => part.isNotEmpty).join(' · ');

  final scores = _scores(
    fixture.result?.sideScores,
    progress,
    live: fixture.status == FixtureStatus.live,
  );

  return MyMatchRecord(
    key: 'fixture:${fixture.id}',
    source: MyMatchSource.tournamentFixture,
    sport: tournament?.sport ?? Sport.cricket,
    context: context,
    sideA: labels.isNotEmpty && labels[0].trim().isNotEmpty
        ? labels[0].trim()
        : 'Side A',
    sideB: labels.length > 1 && labels[1].trim().isNotEmpty
        ? labels[1].trim()
        : 'Side B',
    scoreA: scores?[0],
    scoreB: scores?[1],
    status: fixture.status,
    scheduledAt: fixture.scheduledAt,
    venue: fixture.venue,
    role: role,
    mySide: mySide,
    winnerIndex: fixture.result?.winnerIndex,
    fixtureId: fixture.id,
  );
}

// ── Role and side resolution ───────────────────────────────────────────────

MyMatchRole? _roleOfMatch(SportMatch match, String accountId) {
  if (match.organizerId == accountId) return MyMatchRole.organizing;
  if (match.scorerId == accountId) return MyMatchRole.scoring;
  final participant = match.participantOf(accountId);
  return switch (participant?.status) {
    MatchParticipantStatus.accepted => MyMatchRole.playing,
    MatchParticipantStatus.invited => MyMatchRole.invited,
    _ => null,
  };
}

MyMatchRole? _roleOfFixture(
  Fixture fixture, {
  required String accountId,
  required Set<String> myEntryIds,
  required String? organizerId,
}) {
  if (organizerId == accountId) return MyMatchRole.organizing;
  if (fixture.scorerAccountIds.contains(accountId)) return MyMatchRole.scoring;
  if (_sideOf(fixture, myEntryIds) != null) return MyMatchRole.playing;
  return null;
}

int? _sideOf(Fixture fixture, Set<String> myEntryIds) {
  if (myEntryIds.contains(fixture.home.entryId)) return 0;
  if (myEntryIds.contains(fixture.away.entryId)) return 1;
  return null;
}

/// Entries that still stand for the member. A withdrawn entry is not theirs to
/// play any more, so the fixture it points at is not an appearance.
Set<String> _myEntryIds(TournamentsController tournaments, String accountId) =>
    {
      for (final entry in tournaments.entriesById.values)
        if (entry.memberAccountIds.contains(accountId) &&
            entry.status != EntryStatus.withdrawn)
          entry.id,
    };

// ── Ordering and scores ────────────────────────────────────────────────────

/// Live first, then the next match up, then the newest results.
int _compare(MyMatchRecord a, MyMatchRecord b) {
  final rank = _phaseRank(a.phase).compareTo(_phaseRank(b.phase));
  if (rank != 0) return rank;
  return a.phase == MyMatchPhase.completed
      ? b.scheduledAt.compareTo(a.scheduledAt)
      : a.scheduledAt.compareTo(b.scheduledAt);
}

int _phaseRank(MyMatchPhase phase) => switch (phase) {
  MyMatchPhase.live => 0,
  MyMatchPhase.upcoming => 1,
  MyMatchPhase.completed => 2,
  MyMatchPhase.all => 3,
};

List<String>? _scores(
  List<String>? published,
  MatchProgress? progress, {
  required bool live,
}) {
  if (published != null && published.length >= 2 && !_blank(published)) {
    return published;
  }
  // A running match has no stored result yet: the folded event log is the only
  // score there is, and it is the same string the scoring workspace paints.
  if (!live || progress == null) return null;
  final display = progress.scoreDisplay;
  if (display.length < 2 || _blank(display)) return null;
  return display;
}

bool _blank(List<String> values) => values.every((v) => v.trim().isEmpty);
