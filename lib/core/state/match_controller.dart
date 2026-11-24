import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/core/state/feature_controller.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';

/// Official matches: discovery, invitations, the scorer's workspace and the
/// result lifecycle.
///
/// Every mutation returns whether it landed so a screen can stay free of
/// try/catch, and the last refusal is kept in [lastError] for the banner above
/// the score. That is the one place a server message becomes a sentence the
/// member reads.
class MatchController extends FeatureController<MatchRepository> {
  MatchController(super.repo);

  /// The last refusal, or null after a successful change.
  String? lastError;

  /// Where the last write stands: idle, syncing, offline or failed.
  MatchSyncState get sync => repo.sync;

  void clearError() {
    if (lastError == null) return;
    lastError = null;
    notifyListeners();
  }

  // ── Reads ───────────────────────────────────────────────────────────────

  List<SportMatch> get matches => repo.matches;
  SportMatch? matchById(String id) => repo.matchById(id);

  /// The local match created from a tournament fixture, or null.
  SportMatch? matchOfFixture(String tournamentId, String fixtureId) =>
      repo.matchOfFixture(tournamentId, fixtureId);

  /// Public matches plus the invite-only ones the caller is on.
  List<SportMatch> get discoverableMatches => repo.discoverableMatches;

  /// Pull to refresh: reloads the store and retries anything still queued.
  Future<void> refresh() async {
    await _guardVoid(repo.reload);
  }

  List<SportMatch> get myMatches => repo.myMatches;
  List<SportMatch> get myOrganizedMatches => repo.myOrganizedMatches;
  List<SportMatch> get myScoringMatches => repo.myScoringMatches;
  List<SportMatch> get liveMatches => repo.liveMatches;
  List<SportMatch> get completedMatches => repo.completedMatches;
  List<SportMatch> get myInvites => repo.myInvites;

  MatchProgress progressOf(SportMatch match) => repo.progressOf(match);

  MatchProgress? progressFor(String matchId) {
    final match = repo.matchById(matchId);
    return match == null ? null : repo.progressOf(match);
  }

  /// Discovery filters: sport, and whether to show only the caller's matches.
  List<SportMatch> filterMatches({
    Sport? sport,
    String query = '',
    bool mineOnly = false,
  }) {
    final needle = query.trim().toLowerCase();
    final source = mineOnly ? repo.myMatches : repo.discoverableMatches;
    return source.where((m) {
      if (sport != null && m.sport != sport) return false;
      if (needle.isEmpty) return true;
      return m.title.toLowerCase().contains(needle) ||
          m.venue.toLowerCase().contains(needle) ||
          m.sideNames.any((s) => s.toLowerCase().contains(needle)) ||
          m.sport.label.toLowerCase().contains(needle);
    }).toList();
  }

  // ── Writes ──────────────────────────────────────────────────────────────

  Future<SportMatch?> createMatch(MatchDraft draft) =>
      _guard(() => repo.createMatch(draft));

  /// Returns false and explains through [lastError] when the server refuses.
  Future<bool> updateMatch(
    String matchId, {
    required String title,
    required String venue,
    required DateTime scheduledAt,
    required String sideA,
    required String sideB,
    required int capacity,
  }) => _guardVoid(
    () => repo.updateMatch(
      matchId,
      title: title,
      venue: venue,
      scheduledAt: scheduledAt,
      sideA: sideA,
      sideB: sideB,
      capacity: capacity,
    ),
  );

  Future<bool> cancelMatch(String matchId, {String? reason}) =>
      _guardVoid(() => repo.cancelMatch(matchId, reason: reason));

  Future<bool> inviteParticipant(
    String matchId,
    String profileId, {
    int side = 1,
    String? displayName,
  }) => _guardVoid(
    () => repo.inviteParticipant(
      matchId,
      profileId,
      side: side,
      displayName: displayName,
    ),
  );

  Future<bool> respondToInvite(String matchId, {required bool accept}) =>
      _guardVoid(() => repo.respondToInvite(matchId, accept: accept));

  Future<bool> removeParticipant(String matchId, String profileId) =>
      _guardVoid(() => repo.removeParticipant(matchId, profileId));

  /// Joins a public match on the given side without an invitation.
  Future<bool> joinMatch(String matchId, {int side = 0}) =>
      _guardVoid(() => repo.joinMatch(matchId, side: side));

  Future<bool> leaveMatch(String matchId) =>
      _guardVoid(() => repo.leaveMatch(matchId));

  /// Invites a whole squad; returns how many invitations were written, or null
  /// when it was refused (see [lastError]).
  Future<int?> addSquadToMatch(
    String matchId,
    String squadId, {
    int side = 0,
  }) => _guard(() => repo.addSquadToMatch(matchId, squadId, side: side));

  Future<bool> assignScorer(String matchId, String scorerId) =>
      _guardVoid(() => repo.assignMatchScorer(matchId, scorerId));

  Future<bool> revokeScorer(String matchId) =>
      _guardVoid(() => repo.revokeMatchScorer(matchId));

  Future<bool> startMatch(String matchId) =>
      _guardVoid(() => repo.startMatch(matchId));

  /// Holds scoring without ending the match. The reason is optional, but when
  /// given it has to be 3 to 200 characters.
  Future<bool> pauseMatch(String matchId, {String? reason}) =>
      _guardVoid(() => repo.pauseMatch(matchId, reason: reason));

  Future<bool> resumeMatch(String matchId) =>
      _guardVoid(() => repo.resumeMatch(matchId));

  /// Records one scoring tap. A queued tap still returns an event, so the
  /// workspace paints the score immediately and the banner says it will sync.
  Future<MatchEvent?> recordEvent(
    String matchId, {
    required String kind,
    int? side,
    Map<String, dynamic> data = const {},
    String? clientId,
    DateTime? at,
  }) => _guard(
    () => repo.recordEvent(
      matchId,
      kind: kind,
      side: side,
      data: data,
      clientId: clientId,
      at: at,
    ),
  );

  Future<bool> voidEvent(String matchId, String eventId) =>
      _guardVoid(() => repo.voidEvent(matchId, eventId));

  Future<bool> submitResult(
    String matchId, {
    required String headline,
    required String detail,
    required List<String> sideScores,
    required List<int> sideValues,
    required int winnerIndex,
  }) => _guardVoid(
    () => repo.submitResult(
      matchId,
      headline: headline,
      detail: detail,
      sideScores: sideScores,
      sideValues: sideValues,
      winnerIndex: winnerIndex,
    ),
  );

  Future<bool> publishResult(String matchId) =>
      _guardVoid(() => repo.publishResult(matchId));

  Future<bool> correctResult(
    String matchId, {
    required String headline,
    required String detail,
    required List<String> sideScores,
    required List<int> sideValues,
    required int winnerIndex,
    required String reason,
  }) => _guardVoid(
    () => repo.correctResult(
      matchId,
      headline: headline,
      detail: detail,
      sideScores: sideScores,
      sideValues: sideValues,
      winnerIndex: winnerIndex,
      reason: reason,
    ),
  );

  Future<bool> recordWalkover(
    String matchId, {
    required int winnerIndex,
    required String reason,
  }) => _guardVoid(
    () => repo.recordMatchWalkover(
      matchId,
      winnerIndex: winnerIndex,
      reason: reason,
    ),
  );

  /// Retires a live badminton match with a reason and a winner. The partial
  /// score is derived from the rally log, so nothing here can invent one.
  Future<bool> retireMatch(
    String matchId, {
    required int winnerIndex,
    required String reason,
  }) => _guardVoid(
    () => repo.retireMatch(matchId, winnerIndex: winnerIndex, reason: reason),
  );

  /// Every dispute raised on a match, newest first. Free of any entitlement
  /// gate: a result can always be challenged and answered.
  List<MatchDispute> disputesOf(String matchId) => repo.disputesOf(matchId);

  /// Returns the new dispute, or null with the refusal in [lastError].
  Future<MatchDispute?> raiseDispute(String matchId, String reason) =>
      _guard(() => repo.raiseMatchDispute(matchId, reason));

  Future<MatchDispute?> resolveDispute(
    String matchId,
    String disputeId, {
    required MatchDisputeStatus status,
    String? resolution,
  }) => _guard(
    () => repo.resolveMatchDispute(
      matchId,
      disputeId,
      status: status,
      resolution: resolution,
    ),
  );

  Future<void> watchMatch(String matchId) => repo.watchMatch(matchId);
  Future<void> unwatchMatch(String matchId) => repo.unwatchMatch(matchId);

  /// Subscribes to every visible match so live scores appear without opening
  /// each workspace. The local repository implements this as a no-op.
  Future<void> watchAllMatches() => repo.watchAllMatches();
  Future<void> unwatchAllMatches() => repo.unwatchAllMatches();

  // ── Error plumbing ──────────────────────────────────────────────────────

  Future<T?> _guard<T>(Future<T> Function() action) async {
    lastError = null;
    try {
      final value = await action();
      notifyListeners();
      return value;
    } catch (error) {
      lastError = _describe(error);
      notifyListeners();
      return null;
    }
  }

  Future<bool> _guardVoid(Future<void> Function() action) async {
    lastError = null;
    try {
      await action();
      notifyListeners();
      return true;
    } catch (error) {
      lastError = _describe(error);
      notifyListeners();
      return false;
    }
  }

  String _describe(Object error) {
    if (error is StateError) return error.message;
    final text = error.toString();
    // Repository exceptions already carry a member-facing sentence.
    return text.isEmpty ? 'That change could not be saved.' : text;
  }
}
