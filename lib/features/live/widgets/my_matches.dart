import 'package:flutter/foundation.dart';

import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/profile/widgets/sporting_record.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';

/// Authoritative source of a My Matches row.
enum MyMatchSource { officialMatch, tournamentFixture }

/// A user's relationship to a match.
///
/// One universal Sportika account can hold multiple roles simultaneously.
enum MyMatchRole { playing, organizing, scoring, invited }

extension MyMatchRoleX on MyMatchRole {
  String get label => switch (this) {
    MyMatchRole.playing => 'Playing',
    MyMatchRole.organizing => 'Organizer',
    MyMatchRole.scoring => 'Scorer',
    MyMatchRole.invited => 'Invited',
  };
}

/// The existing enum is preserved for current filter callers.
///
/// `completed` represents History, including published, cancelled,
/// submitted, and other non-live/non-upcoming statuses.
enum MyMatchPhase { all, upcoming, live, completed }

extension MyMatchPhaseX on MyMatchPhase {
  String get label => switch (this) {
    MyMatchPhase.all => 'All',
    MyMatchPhase.upcoming => 'Upcoming',
    MyMatchPhase.live => 'Live',
    MyMatchPhase.completed => 'History',
  };
}

/// A single official match or tournament fixture.
///
/// All fields originate from existing controllers. No match or score
/// is estimated or generated.
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
    this.roles = const <MyMatchRole>{},
    this.scoreA,
    this.scoreB,
    this.venue = '',
    this.mySide,
    this.winnerIndex,
    this.matchId,
    this.fixtureId,
    this.tournamentId,
  });

  /// Stable row identity.
  final String key;

  final MyMatchSource source;
  final Sport sport;

  final String context;
  final String sideA;
  final String sideB;

  final String? scoreA;
  final String? scoreB;

  final FixtureStatus status;
  final DateTime scheduledAt;
  final String venue;

  /// Primary role retained for existing UI callers.
  final MyMatchRole role;

  /// All applicable roles.
  ///
  /// Older direct constructors may omit this field. In that case,
  /// [effectiveRoles] still includes [role].
  final Set<MyMatchRole> roles;

  /// The user's confirmed playing side.
  ///
  /// Administrative roles never establish participation.
  final int? mySide;

  /// 0 or 1 = winning side.
  /// -1 = explicit draw.
  /// null = no published winner.
  final int? winnerIndex;

  final String? matchId;
  final String? fixtureId;
  final String? tournamentId;

  Set<MyMatchRole> get effectiveRoles =>
      Set<MyMatchRole>.unmodifiable({...roles, role});

  MyMatchRole get primaryRole => role;

  bool get isParticipant =>
      effectiveRoles.contains(MyMatchRole.playing) &&
      (mySide == 0 || mySide == 1);

  bool get isOrganizer => effectiveRoles.contains(MyMatchRole.organizing);

  bool get isScorer => effectiveRoles.contains(MyMatchRole.scoring);

  bool get isInvited => effectiveRoles.contains(MyMatchRole.invited);

  bool get isTournamentMatch =>
      tournamentId != null || source == MyMatchSource.tournamentFixture;

  MyMatchPhase get phase => switch (status) {
    FixtureStatus.upcoming => MyMatchPhase.upcoming,
    FixtureStatus.live => MyMatchPhase.live,
    _ => MyMatchPhase.completed,
  };

  bool get isLive => status == FixtureStatus.live;

  bool get hasScore =>
      scoreA != null &&
      scoreB != null &&
      scoreA!.trim().isNotEmpty &&
      scoreB!.trim().isNotEmpty;

  /// Only final, authoritative results are eligible for sporting records.
  bool get isResultPublished =>
      (status == FixtureStatus.published || status == FixtureStatus.walkover) &&
      (winnerIndex == -1 || winnerIndex == 0 || winnerIndex == 1);

  /// Backward-compatible alias.
  bool get publishedResult => isResultPublished;

  SportingOutcome get outcome {
    if (!isResultPublished || !isParticipant) {
      return SportingOutcome.unrecorded;
    }

    return switch (winnerIndex) {
      -1 => SportingOutcome.draw,
      0 ||
      1 => winnerIndex == mySide ? SportingOutcome.win : SportingOutcome.loss,
      _ => SportingOutcome.unrecorded,
    };
  }

  /// A normalized representation of searchable record information.
  String get searchText => [
    sideA,
    sideB,
    context,
    venue,
    sport.label,
    for (final matchRole in effectiveRoles) matchRole.label,
  ].join(' ').toLowerCase();

  bool matchesQuery(String needle) {
    final normalized = needle.trim().toLowerCase();

    return normalized.isEmpty || searchText.contains(normalized);
  }
}

/// Build a unified, de-duplicated list of the user's official matches.
///
/// Official match records take precedence over their projected fixtures.
/// Fixture identity is scoped to its tournament whenever possible.
List<MyMatchRecord> myMatchesFor({
  required String? accountId,
  required MatchController matches,
  required FixturesController fixtures,
  required TournamentsController tournaments,
}) {
  final records = <MyMatchRecord>[];

  if (accountId == null || accountId.trim().isEmpty) {
    return records;
  }

  final representedLinks = <String>{};

  // ============================================================
  // OFFICIAL MATCHES
  // ============================================================

  for (final match in matches.matches) {
    final roles = _rolesOfMatch(match, accountId);

    if (roles.isEmpty) continue;

    final fixtureId = match.fixtureId;
    final tournamentId = match.tournamentId;

    if (fixtureId != null && tournamentId != null) {
      representedLinks.add(_fixtureLink(tournamentId, fixtureId));
    }

    records.add(
      _fromMatch(
        match,
        accountId: accountId,
        roles: roles,
        progress: match.isLive && match.events.isNotEmpty
            ? matches.progressOf(match)
            : null,
        tournaments: tournaments,
      ),
    );
  }

  // ============================================================
  // TOURNAMENT FIXTURES
  // ============================================================

  final myEntryIds = _myEntryIds(tournaments, accountId);

  for (final fixture in fixtures.appearancesOf(accountId)) {
    final link = _fixtureLink(fixture.tournamentId, fixture.id);

    if (representedLinks.contains(link)) {
      continue;
    }

    final tournament = fixtures.tournamentOf(fixture);

    // Do not invent a sport when tournament metadata is missing.
    // The fixture cannot be accurately represented without it.
    if (tournament == null) {
      continue;
    }

    final mySide = _sideOf(fixture, myEntryIds);

    final roles = _rolesOfFixture(
      fixture,
      accountId: accountId,
      mySide: mySide,
      organizerId: tournament.organizerId,
    );

    if (roles.isEmpty) continue;

    records.add(
      _fromFixture(
        fixture,
        tournament: tournament,
        roles: roles,
        mySide: mySide,
        progress:
            fixture.status == FixtureStatus.live && fixture.events.isNotEmpty
            ? fixtures.progressOfFixture(fixture)
            : null,
        labels: fixtures.sideLabelsOf(fixture),
      ),
    );
  }

  records.sort(_compare);

  return records;
}

/// Apply UI filters without changing the authoritative record set.
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
          (needle.isEmpty || record.searchText.contains(needle)))
        record,
  ];
}

/// Calculate the user's official sporting record.
///
/// Only accepted participation with an authoritative result counts.
/// Administrative responsibilities and pending invitations do not count.
SportingRecord recordOf(Iterable<MyMatchRecord> records) {
  var played = 0;
  var wins = 0;
  var losses = 0;
  var draws = 0;

  // Guard against accidental duplicate rows in caller-supplied data.
  final counted = <String>{};

  for (final record in records) {
    final identity = record.tournamentId != null && record.fixtureId != null
        ? _fixtureLink(record.tournamentId!, record.fixtureId!)
        : record.key;

    if (counted.contains(identity)) continue;

    final outcome = record.outcome;

    if (outcome == SportingOutcome.unrecorded) {
      continue;
    }

    counted.add(identity);

    switch (outcome) {
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

// ============================================================
// SOURCE MAPPING
// ============================================================

MyMatchRecord _fromMatch(
  SportMatch match, {
  required String accountId,
  required Set<MyMatchRole> roles,
  required MatchProgress? progress,
  required TournamentsController tournaments,
}) {
  final tournamentId = match.tournamentId;

  final tournament = tournamentId == null
      ? null
      : tournaments.tournamentById(tournamentId);

  final rawStage = match.rules['stage'];

  final stage = rawStage is String ? rawStage.trim() : '';

  final title = tournament != null && tournament.name.trim().isNotEmpty
      ? tournament.name.trim()
      : match.title.trim();

  final context = [
    if (title.isNotEmpty) title,
    if (stage.isNotEmpty) stage,
  ].join(' · ');

  final participant = match.participantOf(accountId);

  final mySide =
      participant != null &&
          participant.status == MatchParticipantStatus.accepted &&
          (participant.side == 0 || participant.side == 1)
      ? participant.side
      : null;

  final scores = _scores(
    match.result?.sideScores,
    progress,
    live: match.isLive,
    published:
        match.status == FixtureStatus.published ||
        match.status == FixtureStatus.walkover,
  );

  return MyMatchRecord(
    key: 'match:${match.id}',
    source: MyMatchSource.officialMatch,
    sport: match.sport,
    context: context,
    sideA: _sideLabel(match.sideNames, 0),
    sideB: _sideLabel(match.sideNames, 1),
    scoreA: scores?[0],
    scoreB: scores?[1],
    status: match.status,
    scheduledAt: match.scheduledAt,
    venue: match.venue,
    role: _primaryRole(roles),
    roles: Set<MyMatchRole>.unmodifiable(roles),
    mySide: mySide,
    winnerIndex: match.result?.winnerIndex,
    matchId: match.id,
    fixtureId: match.fixtureId,
    tournamentId: tournamentId,
  );
}

MyMatchRecord _fromFixture(
  Fixture fixture, {
  required Tournament tournament,
  required Set<MyMatchRole> roles,
  required int? mySide,
  required MatchProgress? progress,
  required List<String> labels,
}) {
  final stage = fixture.stage.trim();

  final context = [
    if (tournament.name.trim().isNotEmpty) tournament.name.trim(),
    if (stage.isNotEmpty) stage,
  ].join(' · ');

  final scores = _scores(
    fixture.result?.sideScores,
    progress,
    live: fixture.status == FixtureStatus.live,
    published:
        fixture.status == FixtureStatus.published ||
        fixture.status == FixtureStatus.walkover,
  );

  return MyMatchRecord(
    key: 'fixture:${fixture.tournamentId}/${fixture.id}',
    source: MyMatchSource.tournamentFixture,
    sport: tournament.sport,
    context: context,
    sideA: _sideLabel(labels, 0),
    sideB: _sideLabel(labels, 1),
    scoreA: scores?[0],
    scoreB: scores?[1],
    status: fixture.status,
    scheduledAt: fixture.scheduledAt,
    venue: fixture.venue,
    role: _primaryRole(roles),
    roles: Set<MyMatchRole>.unmodifiable(roles),
    mySide: mySide,
    winnerIndex: fixture.result?.winnerIndex,
    fixtureId: fixture.id,
    tournamentId: fixture.tournamentId,
  );
}

// ============================================================
// ROLE RESOLUTION
// ============================================================

Set<MyMatchRole> _rolesOfMatch(SportMatch match, String accountId) {
  final roles = <MyMatchRole>{};

  final participant = match.participantOf(accountId);

  if (participant?.status == MatchParticipantStatus.accepted) {
    roles.add(MyMatchRole.playing);
  }

  if (match.organizerId == accountId) {
    roles.add(MyMatchRole.organizing);
  }

  if (match.scorerId == accountId) {
    roles.add(MyMatchRole.scoring);
  }

  if (participant?.status == MatchParticipantStatus.invited) {
    roles.add(MyMatchRole.invited);
  }

  return roles;
}

Set<MyMatchRole> _rolesOfFixture(
  Fixture fixture, {
  required String accountId,
  required int? mySide,
  required String? organizerId,
}) {
  final roles = <MyMatchRole>{};

  if (mySide != null) {
    roles.add(MyMatchRole.playing);
  }

  if (organizerId == accountId) {
    roles.add(MyMatchRole.organizing);
  }

  if (fixture.scorerAccountIds.contains(accountId)) {
    roles.add(MyMatchRole.scoring);
  }

  return roles;
}

/// Prefer the playing role for athlete-facing presentation.
///
/// The full set remains available for organizer/scorer controls.
MyMatchRole _primaryRole(Set<MyMatchRole> roles) {
  if (roles.contains(MyMatchRole.playing)) {
    return MyMatchRole.playing;
  }

  if (roles.contains(MyMatchRole.organizing)) {
    return MyMatchRole.organizing;
  }

  if (roles.contains(MyMatchRole.scoring)) {
    return MyMatchRole.scoring;
  }

  return MyMatchRole.invited;
}

int? _sideOf(Fixture fixture, Set<String> myEntryIds) {
  if (myEntryIds.contains(fixture.home.entryId)) {
    return 0;
  }

  if (myEntryIds.contains(fixture.away.entryId)) {
    return 1;
  }

  return null;
}

/// Non-withdrawn tournament entries containing the current account.
Set<String> _myEntryIds(TournamentsController tournaments, String accountId) {
  return {
    for (final entry in tournaments.entriesById.values)
      if (entry.memberAccountIds.contains(accountId) &&
          entry.status != EntryStatus.withdrawn)
        entry.id,
  };
}

// ============================================================
// SORTING
// ============================================================

/// Live first, upcoming next, then history newest first.
int _compare(MyMatchRecord a, MyMatchRecord b) {
  final phaseComparison = _phaseRank(a.phase).compareTo(_phaseRank(b.phase));

  if (phaseComparison != 0) {
    return phaseComparison;
  }

  final dateComparison = a.phase == MyMatchPhase.completed
      ? b.scheduledAt.compareTo(a.scheduledAt)
      : a.scheduledAt.compareTo(b.scheduledAt);

  if (dateComparison != 0) {
    return dateComparison;
  }

  // Stable ordering when timestamps are identical.
  return a.key.compareTo(b.key);
}

int _phaseRank(MyMatchPhase phase) {
  return switch (phase) {
    MyMatchPhase.live => 0,
    MyMatchPhase.upcoming => 1,
    MyMatchPhase.completed => 2,
    MyMatchPhase.all => 3,
  };
}

// ============================================================
// SCORE RESOLUTION
// ============================================================

/// Resolve exactly two displayable scores.
///
/// Live matches prefer the event fold.
/// Published matches prefer the official result.
/// Other statuses do not display provisional results.
List<String>? _scores(
  List<String>? stored,
  MatchProgress? progress, {
  required bool live,
  required bool published,
}) {
  if (live) {
    final liveScores = _validScores(progress?.scoreDisplay);

    if (liveScores != null) {
      return liveScores;
    }

    // A live match may have no scoring events yet.
    return null;
  }

  if (published) {
    return _validScores(stored);
  }

  return null;
}

List<String>? _validScores(List<String>? values) {
  if (values == null || values.length < 2) {
    return null;
  }

  final first = values[0].trim();
  final second = values[1].trim();

  if (first.isEmpty || second.isEmpty) {
    return null;
  }

  return [first, second];
}

// ============================================================
// HELPERS
// ============================================================

String _fixtureLink(String tournamentId, String fixtureId) {
  return '$tournamentId/$fixtureId';
}

String _sideLabel(List<String> labels, int index) {
  if (index < labels.length) {
    final value = labels[index].trim();

    if (value.isNotEmpty) {
      return value;
    }
  }

  return index == 0 ? 'Side A' : 'Side B';
}
