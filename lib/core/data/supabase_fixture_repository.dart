import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/core/data/supabase_match_repository.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';

/// Tournament fixtures, projected from the match module.
///
/// A fixture is not a second aggregate: migration 0008 gave `public.matches`
/// the `tournament_id`/`fixture_id` columns and a partial unique index that
/// keeps one match per fixture, and migration 0016 generates a draw as match
/// rows. So this repository owns no read of its own — it projects
/// [MatchRepository] rows into [Fixture] for the bracket, the scorer workspace
/// and the review queue, and forwards every write to the match RPCs. The event
/// log, the scorer authorization, the results and the disputes therefore exist
/// exactly once.
///
/// The [FixtureRepository] mutators are synchronous because eight screens call
/// them that way. Each one starts the matching `Future` and records a refusal in
/// [lastError]; the list then repaints from the match module's own reload, which
/// is the same path a second device's write takes.
class SupabaseFixtureRepository extends ChangeNotifier
    implements FixtureRepository {
  SupabaseFixtureRepository({
    required MatchRepository matches,
    required TournamentRepository tournaments,
    AccountRepository? accounts,
    // Named parameters cannot be private initializing formals.
    // ignore: prefer_initializing_formals
  }) : _matches = matches,
       // ignore: prefer_initializing_formals
       _tournaments = tournaments,
       // ignore: prefer_initializing_formals
       _accounts = accounts {
    _matches.addListener(_forward);
    _tournaments.addListener(_forward);
  }

  final MatchRepository _matches;
  final TournamentRepository _tournaments;
  final AccountRepository? _accounts;

  String? _lastError;

  @override
  bool get loading => false;

  @override
  String? get lastError => _lastError;

  @override
  Future<void> refresh() => reload();

  @override
  Future<void> reload() async {
    await _matches.reload();
    await _tournaments.reload();
  }

  void _forward() => notifyListeners();

  @override
  void dispose() {
    _matches.removeListener(_forward);
    _tournaments.removeListener(_forward);
    super.dispose();
  }

  String? get _uid => _accounts?.currentAccount?.id;

  // ── Read ────────────────────────────────────────────────────────────────

  /// Every match that carries a tournament id, in schedule order.
  @override
  List<Fixture> get fixtures {
    final out = <Fixture>[];
    for (final match in _matches.matches) {
      final tournamentId = match.tournamentId;
      if (tournamentId == null) continue;
      final tournament = _tournaments.tournamentById(tournamentId);
      if (tournament == null) continue;
      out.add(_project(match, tournament));
    }
    out.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return out;
  }

  @override
  Fixture? fixtureById(String id) {
    for (final fixture in fixtures) {
      if (fixture.id == id) return fixture;
    }
    // A bracket that only knows the match id still resolves.
    return fixtures.where((f) => f.id == id).firstOrNull;
  }

  @override
  List<Fixture> fixturesFor(String tournamentId) =>
      fixtures.where((f) => f.tournamentId == tournamentId).toList();

  @override
  Tournament? tournamentOf(Fixture f) =>
      _tournaments.tournamentById(f.tournamentId);

  @override
  List<Fixture> get publicFixtures => fixtures;

  @override
  List<Fixture> get liveFixtures =>
      fixtures.where((f) => f.status == FixtureStatus.live).toList();

  @override
  List<Fixture> get completedFixtures => fixtures
      .where(
        (f) =>
            f.status == FixtureStatus.published ||
            f.status == FixtureStatus.walkover,
      )
      .toList();

  @override
  List<Fixture> get scheduledFixtures => fixtures
      .where(
        (f) =>
            f.status == FixtureStatus.upcoming ||
            f.status == FixtureStatus.submitted,
      )
      .toList();

  @override
  List<Fixture> get myScoringFixtures {
    final id = _uid;
    if (id == null) return <Fixture>[];
    return fixtures
        .where(
          (f) =>
              f.scorerAccountIds.contains(id) &&
              f.status != FixtureStatus.published,
        )
        .toList();
  }

  @override
  List<Fixture> get myOrganizerFixtures {
    final mine = _myTournamentIds();
    return fixtures.where((f) => mine.contains(f.tournamentId)).toList();
  }

  @override
  List<Fixture> get fixturesAwaitingReview {
    final mine = _myTournamentIds();
    return fixtures
        .where(
          (f) =>
              mine.contains(f.tournamentId) &&
              f.status == FixtureStatus.submitted,
        )
        .toList();
  }

  @override
  List<Fixture> get myOrganizerDisputes {
    final mine = _myTournamentIds();
    return fixtures
        .where(
          (f) =>
              mine.contains(f.tournamentId) &&
              f.disputeNote != null &&
              !f.disputeResolved,
        )
        .toList();
  }

  @override
  List<Fixture> get myFixtures {
    final me = _uid;
    if (me == null) return <Fixture>[];
    final entryIds = _myEntryIds(me);
    return fixtures
        .where(
          (f) =>
              entryIds.contains(f.home.entryId) ||
              entryIds.contains(f.away.entryId),
        )
        .toList();
  }

  @override
  List<Fixture> officialMatchesPlayed() => completedFixtures;

  @override
  List<Fixture> appearancesOf(String accountId) {
    final entryIds = _myEntryIds(accountId);
    return fixtures
        .where(
          (f) =>
              entryIds.contains(f.home.entryId) ||
              entryIds.contains(f.away.entryId),
        )
        .toList();
  }

  @override
  List<Fixture> filterFixtures({Sport? sport, DateTime? day}) =>
      scheduledFixtures.where((f) {
        final tournament = tournamentOf(f);
        if (tournament == null) return false;
        if (sport != null && tournament.sport != sport) return false;
        if (day != null) {
          final same =
              f.scheduledAt.year == day.year &&
              f.scheduledAt.month == day.month &&
              f.scheduledAt.day == day.day;
          if (!same) return false;
        }
        return true;
      }).toList();

  @override
  List<String> sideLabelsOf(Fixture f) => <String>[f.home.label, f.away.label];

  @override
  String sideLabel(Fixture f, int index) => sideLabelsOf(f)[index.clamp(0, 1)];

  @override
  MatchProgress progressOfFixture(Fixture f) => SportEngines.progressOf(
    sport: tournamentOf(f)?.sport ?? Sport.cricket,
    sides: sideLabelsOf(f),
    rules: SportEngines.rulesOr(
      tournamentOf(f)?.sport ?? Sport.cricket,
      f.rules,
    ),
    rawEvents: f.events,
  );

  Set<String> _myTournamentIds() {
    final me = _uid;
    if (me == null) return <String>{};
    return _tournaments.tournamentsForOrganizer(me).map((t) => t.id).toSet();
  }

  Set<String> _myEntryIds(String accountId) => _tournaments.entries
      .where(
        (e) =>
            e.memberAccountIds.contains(accountId) &&
            e.status != EntryStatus.withdrawn,
      )
      .map((e) => e.id)
      .toSet();

  // ── Write ───────────────────────────────────────────────────────────────

  /// The match row behind a fixture id, or null when the tournament's draw has
  /// not been generated yet.
  SportMatch? _matchFor(String fixtureId) => _matches.matches
      .where((m) => m.fixtureId == fixtureId || m.id == fixtureId)
      .firstOrNull;

  @override
  void assignScorer(String fixtureId, String accountId) {
    final match = _matchFor(fixtureId);
    if (match == null) return;
    _send(_matches.assignMatchScorer(match.id, accountId));
  }

  @override
  void replaceScorer(String fixtureId, String fromId, String toId) {
    final match = _matchFor(fixtureId);
    if (match == null) return;
    // The server upserts the assignment, so handing it to the new scorer is the
    // transfer; the old scorer loses write access in the same statement.
    _send(_matches.assignMatchScorer(match.id, toId));
  }

  @override
  void removeScorer(String fixtureId, String accountId) {
    final match = _matchFor(fixtureId);
    if (match == null) return;
    _send(_matches.revokeMatchScorer(match.id));
  }

  @override
  void startOfficialScoring(String fixtureId) {
    final match = _matchFor(fixtureId);
    if (match == null) return;
    _send(_matches.startMatch(match.id));
  }

  @override
  void recordOfficialEvent(String fixtureId, ScoringEvent event) {
    final match = _matchFor(fixtureId);
    if (match == null) return;
    _send(
      _matches.recordEvent(
        match.id,
        kind: event.kind,
        side: event.side,
        data: event.data,
        // The engine's event id is the idempotency key: a retried tap with the
        // same id returns the original entry instead of a second point.
        clientId: event.id,
        at: event.at,
      ),
    );
  }

  @override
  void undoOfficialEvent(String fixtureId) {
    final match = _matchFor(fixtureId);
    if (match == null) return;
    final last = match.lastActiveEvent;
    if (last == null) return;
    _send(_matches.voidEvent(match.id, last.id));
  }

  @override
  void submitOfficialResult(String fixtureId) {
    final match = _matchFor(fixtureId);
    if (match == null) return;
    final fixture = fixtureById(fixtureId);
    if (fixture == null) return;
    final progress = progressOfFixture(fixture);
    _send(
      _matches.submitResult(
        match.id,
        headline: progress.headline,
        detail: progress.detailRows.join(' · '),
        sideScores: progress.scoreDisplay,
        sideValues: progress.scoreValues,
        winnerIndex: progress.winnerIndex,
      ),
    );
  }

  @override
  void publishOfficialResult(String fixtureId, {String? correctionReason}) {
    final match = _matchFor(fixtureId);
    if (match == null) return;
    _send(_matches.publishResult(match.id));
  }

  @override
  void recordWalkover(String fixtureId, int winnerIndex, String reason) {
    final match = _matchFor(fixtureId);
    if (match == null) return;
    _send(
      _matches.recordMatchWalkover(
        match.id,
        winnerIndex: winnerIndex,
        reason: reason,
      ),
    );
  }

  @override
  void updateFixtureSchedule(
    String fixtureId, {
    DateTime? scheduledAt,
    String? venue,
    String? scorerId,
  }) {
    final match = _matchFor(fixtureId);
    if (match == null) return;
    if (scorerId != null) _send(_matches.assignMatchScorer(match.id, scorerId));
    _send(
      _matches.updateMatch(
        match.id,
        title: match.title,
        venue: venue ?? match.venue,
        scheduledAt: scheduledAt ?? match.scheduledAt,
        sideA: match.sideNames.isNotEmpty ? match.sideNames[0] : '',
        sideB: match.sideNames.length > 1 ? match.sideNames[1] : '',
        capacity: match.capacity,
      ),
    );
  }

  @override
  void raiseDispute(String fixtureId, String note) {
    final match = _matchFor(fixtureId);
    if (match == null) return;
    _send(_matches.raiseMatchDispute(match.id, note));
  }

  @override
  void resolveDispute(
    String fixtureId, {
    required bool upholdResult,
    String? note,
  }) {
    final match = _matchFor(fixtureId);
    if (match == null) return;
    final dispute = match.disputes.where((d) => d.status.isOpen).firstOrNull;
    if (dispute == null) return;
    _send(
      _matches.resolveMatchDispute(
        match.id,
        dispute.id,
        status: upholdResult
            ? MatchDisputeStatus.resolved
            : MatchDisputeStatus.rejected,
        resolution: note,
      ),
    );
  }

  /// Starts one write and records its refusal. The list repaints from the match
  /// module either way, so a refused tap never leaves a score on screen that the
  /// server did not accept.
  void _send(Future<Object?> future) {
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object error) {
          _lastError = error is MatchRepositoryException
              ? error.message
              : 'That change was not saved.';
          notifyListeners();
        },
      ),
    );
  }

  // ── Projection ──────────────────────────────────────────────────────────

  /// One match as a tournament fixture.
  ///
  /// The draw writes side names into the match row, so a side's entry is
  /// resolved by label — the label is unique inside a tournament, which is what
  /// the entries table's unique constraint guarantees.
  Fixture _project(SportMatch match, Tournament tournament) {
    final entries = _tournaments.entriesFor(tournament.id);
    String entryOf(int index) {
      final label = index < match.sideNames.length
          ? match.sideNames[index]
          : '';
      final entry = entries.where((e) => e.label == label).firstOrNull;
      return entry?.id ?? 'tbd-${match.id}-$index';
    }

    final openDispute = match.disputes
        .where((d) => d.status.isOpen)
        .firstOrNull;
    final round = (match.rules['round'] as num?)?.toInt() ?? 1;
    final stage =
        (match.rules['stage'] as String?) ??
        (tournament.format == TournamentFormat.group
            ? 'Group stage'
            : _stageName(round));

    return Fixture(
      id: match.fixtureId ?? match.id,
      tournamentId: tournament.id,
      stage: stage,
      round: round,
      group: match.rules['group'] as String?,
      home: FixtureSide(
        entryId: entryOf(0),
        label: match.sideNames.isNotEmpty ? match.sideNames[0] : '',
        group: match.rules['group'] as String?,
      ),
      away: FixtureSide(
        entryId: entryOf(1),
        label: match.sideNames.length > 1 ? match.sideNames[1] : '',
        group: match.rules['group'] as String?,
      ),
      scheduledAt: match.scheduledAt,
      venue: match.venue,
      status: match.status,
      scorerAccountIds: <String>[if (match.scorerId != null) match.scorerId!],
      submittedByScorerId: match.submittedAt == null ? null : match.scorerId,
      startedAt: match.startedAt,
      completedAt: match.completedAt,
      events: match.scoringLog,
      rules: <String, dynamic>{...tournament.rules, ...match.rules},
      result: match.result,
      corrections: match.corrections,
      disputeNote: openDispute?.reason,
      disputeRaisedBy: openDispute?.raisedById,
      disputeResolved: openDispute == null && match.disputes.isNotEmpty,
    );
  }

  static String _stageName(int round) => switch (round) {
    1 => 'Round 1',
    2 => 'Quarter-final',
    3 => 'Semi-final',
    4 => 'Final',
    _ => 'Round $round',
  };
}
