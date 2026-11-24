import 'dart:async';

import 'package:flutter/foundation.dart';
// Supabase ships its own `LocalStorage`; this file needs Sportika's on-device
// document store under that name.
import 'package:supabase_flutter/supabase_flutter.dart' hide LocalStorage;

import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';

/// A refusal the scorer or organizer can read as-is.
class MatchRepositoryException implements Exception {
  const MatchRepositoryException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// The match module against PostgreSQL.
///
/// Reads use one nested select so a match, its roster, its log and its result
/// always describe the same instant. Every write is a single RPC from migration
/// 0007: the server derives the actor from `auth.uid()`, assigns the sequence
/// number under a row lock, dedupes a retried client event id and refuses an
/// invalid transition. The client never sends an actor id and never writes a
/// table directly.
///
/// Two things are added on top of the RPC surface:
///
///  * a realtime channel per open match, so a second device sees the same score
///    without polling;
///  * a durable outbox. A scoring tap recorded while the connection is down is
///    written to the device, painted immediately, and retried with its original
///    client event id — which is exactly the key the server dedupes on, so a
///    retry can never double-count a run.
class SupabaseMatchRepository extends ChangeNotifier
    implements MatchRepository {
  SupabaseMatchRepository({required this._client, this.outbox});

  final SupabaseClient _client;

  /// Where a scoring tap waits while the connection is down. Null disables the
  /// outbox, which is what unit tests without a document store use.
  final LocalStorage? outbox;

  /// One nested select for the whole aggregate. The participant's name rides
  /// along through the public profile row, which RLS already scopes.
  ///
  /// The embed has to name its foreign key: match_participants points at
  /// profiles twice (profile_id and invited_by), so a bare `profiles(...)` is
  /// ambiguous and PostgREST refuses the whole read with PGRST201, which would
  /// leave the list empty even though the match row itself was written.
  static const String _select =
      '*, '
      'match_participants(*, '
      'profiles!match_participants_profile_id_fkey(display_name)), '
      'match_events(*), '
      'match_results(*), '
      'match_result_corrections(*), '
      'match_disputes(*)';

  List<SportMatch> _snapshot = [];

  /// Taps that have not reached the server yet, per match. They are folded in
  /// front of the server log so the score paints without waiting.
  final Map<String, List<MatchEvent>> _pending = {};

  final Map<String, RealtimeChannel> _channels = {};
  RealtimeChannel? _allChannel;

  MatchSyncState _sync = MatchSyncState.idle;

  @override
  MatchSyncState get sync => _sync;

  void _requireSession() {
    if (_client.auth.currentUser == null) {
      throw const MatchRepositoryException(
        'Sign in again to score an official match.',
        code: '28000',
      );
    }
  }

  // ── Read ────────────────────────────────────────────────────────────────

  /// Matches still in flight are patched in front of the server log.
  List<SportMatch> _merged() {
    if (_pending.isEmpty) return _snapshot;
    return [
      for (final m in _snapshot)
        if (_pending[m.id] == null || _pending[m.id]!.isEmpty)
          m
        else
          _withPending(m, _pending[m.id]!),
    ];
  }

  SportMatch _withPending(SportMatch m, List<MatchEvent> pending) {
    final events = [...m.events, ...pending];
    return SportMatch.fromJson({
      ...m.toJson(),
      'events': events.map((e) => e.toJson()).toList(),
      'eventCount': events.length,
    });
  }

  @override
  List<SportMatch> get matches => _merged();

  @override
  SportMatch? matchById(String id) =>
      matches.where((m) => m.id == id).firstOrNull;

  @override
  SportMatch? matchOfFixture(String tournamentId, String fixtureId) => matches
      .where((m) => m.tournamentId == tournamentId && m.fixtureId == fixtureId)
      .firstOrNull;

  @override
  Future<void> reload() async {
    _requireSession();
    try {
      // A bounded window: a month back covers results that are still being
      // reviewed and six months ahead covers a whole season's schedule. Reading
      // every row ever written is what made the feed slow and stale at once.
      final now = DateTime.now();
      final rows = await _client
          .from('matches')
          .select(_select)
          .gte(
            'scheduled_at',
            now.subtract(const Duration(days: 30)).toUtc().toIso8601String(),
          )
          .lte(
            'scheduled_at',
            now.add(const Duration(days: 180)).toUtc().toIso8601String(),
          )
          .order('scheduled_at', ascending: true)
          .limit(300);
      _snapshot = rows.map(_matchFromRow).toList();
      _sync = MatchSyncState.idle;
      notifyListeners();
    } catch (error) {
      _sync = MatchSyncState.offline;
      notifyListeners();
      throw _mapError(error, fallback: 'Matches could not be loaded.');
    }
    await flushOutbox();
  }

  /// Re-reads one match. Realtime callbacks use this so a change on another
  /// device lands without re-fetching the whole list.
  Future<void> _refreshMatch(String matchId) async {
    if (_client.auth.currentUser == null) return;
    try {
      final row = await _client
          .from('matches')
          .select(_select)
          .eq('id', matchId)
          .maybeSingle();
      if (row == null) return;
      final fresh = _matchFromRow(row);
      final index = _snapshot.indexWhere((m) => m.id == matchId);
      if (index == -1) {
        _snapshot = [..._snapshot, fresh];
      } else {
        _snapshot = [..._snapshot]..[index] = fresh;
      }
      notifyListeners();
    } catch (_) {
      // A failed refresh is not a failed write: the next tap retries.
    }
  }

  @override
  List<SportMatch> get discoverableMatches =>
      matches.where(_canView).toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  bool _canView(SportMatch m) {
    final me = _client.auth.currentUser?.id;
    if (me == null) return false;
    if (m.visibility == MatchVisibility.public) return true;
    if (m.organizerId == me || m.scorerId == me) return true;
    final p = m.participantOf(me);
    return p != null &&
        (p.status == MatchParticipantStatus.invited ||
            p.status == MatchParticipantStatus.accepted);
  }

  bool _isOnMatch(SportMatch m, String me) {
    if (m.organizerId == me || m.scorerId == me) return true;
    final p = m.participantOf(me);
    return p != null &&
        (p.status == MatchParticipantStatus.invited ||
            p.status == MatchParticipantStatus.accepted);
  }

  @override
  List<SportMatch> get myMatches {
    final me = _client.auth.currentUser?.id;
    if (me == null) return [];
    return matches.where((m) => _isOnMatch(m, me)).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  @override
  List<SportMatch> get myOrganizedMatches {
    final me = _client.auth.currentUser?.id;
    if (me == null) return [];
    return matches.where((m) => m.organizerId == me).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  @override
  List<SportMatch> get myScoringMatches {
    final me = _client.auth.currentUser?.id;
    if (me == null) return [];
    return matches
        .where(
          (m) =>
              (m.scorerId == me ||
                  (m.organizerId == me && m.scorerId == null)) &&
              m.status != FixtureStatus.published &&
              m.status != FixtureStatus.walkover &&
              m.status != FixtureStatus.cancelled,
        )
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  @override
  List<SportMatch> get liveMatches =>
      matches
          .where((m) => m.status == FixtureStatus.live && _canView(m))
          .toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  @override
  List<SportMatch> get completedMatches =>
      matches.where((m) => m.isFinished && _canView(m)).toList()
        ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

  @override
  List<SportMatch> get myInvites {
    final me = _client.auth.currentUser?.id;
    if (me == null) return [];
    return matches
        .where(
          (m) => m.participantOf(me)?.status == MatchParticipantStatus.invited,
        )
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  @override
  MatchProgress progressOf(SportMatch match) => SportEngines.progressOf(
    sport: match.sport,
    sides: match.sideNames,
    rules: SportEngines.rulesOr(match.sport, match.rules),
    rawEvents: match.scoringLog,
  );

  // ── Writes ──────────────────────────────────────────────────────────────

  Future<T> _rpc<T>(
    String function,
    Map<String, dynamic> params, {
    required String fallback,
  }) async {
    _requireSession();
    try {
      return await _client.rpc(function, params: params) as T;
    } catch (error) {
      _sync = MatchSyncState.failed;
      notifyListeners();
      throw _mapError(error, fallback: fallback);
    }
  }

  @override
  Future<SportMatch> createMatch(MatchDraft draft) async {
    await _rpc<dynamic>('create_match', {
      'p_sport_key': draft.sport.key,
      'p_format_label': draft.formatLabel.trim(),
      'p_rules': {...draft.rules, 'discipline': draft.discipline.key},
      'p_title': draft.title.trim(),
      'p_venue': draft.venue.trim(),
      'p_scheduled_at': draft.scheduledAt.toUtc().toIso8601String(),
      'p_visibility': draft.visibility.key,
      'p_side_a': draft.sideA.trim(),
      'p_side_b': draft.sideB.trim(),
      'p_capacity': draft.capacity,
      'p_discipline': draft.discipline.key,
      'p_scorer_id': draft.scorerId,
      'p_tournament_id': draft.tournamentId,
      'p_fixture_id': draft.fixtureId,
    }, fallback: 'The match could not be created.');
    await reload();
    final created = matches
        .where(
          (m) =>
              m.title == draft.title.trim() &&
              m.organizerId == _client.auth.currentUser?.id,
        )
        .firstOrNull;
    if (created == null) {
      throw const MatchRepositoryException(
        'The match was created but could not be read back.',
      );
    }
    return created;
  }

  @override
  Future<void> updateMatch(
    String matchId, {
    required String title,
    required String venue,
    required DateTime scheduledAt,
    required String sideA,
    required String sideB,
    required int capacity,
  }) async {
    await _rpc<dynamic>('update_match', {
      'p_match_id': matchId,
      'p_title': title.trim(),
      'p_venue': venue.trim(),
      'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
      'p_side_a': sideA.trim(),
      'p_side_b': sideB.trim(),
      'p_capacity': capacity,
    }, fallback: 'The match could not be updated.');
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
  }

  @override
  Future<void> cancelMatch(String matchId, {String? reason}) async {
    await _rpc<dynamic>('cancel_match', {
      'p_match_id': matchId,
      'p_reason': reason,
    }, fallback: 'The match could not be cancelled.');
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
  }

  @override
  Future<void> inviteParticipant(
    String matchId,
    String profileId, {
    int side = 1,
    String? displayName,
  }) async {
    await _rpc<dynamic>('invite_match_participant', {
      'p_match_id': matchId,
      'p_profile_id': profileId,
      'p_side': side,
    }, fallback: 'The invitation could not be sent.');
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
  }

  @override
  Future<void> respondToInvite(String matchId, {required bool accept}) async {
    await _rpc<dynamic>('respond_match_invite', {
      'p_match_id': matchId,
      'p_accept': accept,
    }, fallback: 'Your answer could not be saved.');
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
  }

  @override
  Future<void> removeParticipant(String matchId, String profileId) async {
    await _rpc<dynamic>('remove_match_participant', {
      'p_match_id': matchId,
      'p_profile_id': profileId,
    }, fallback: 'The player could not be removed.');
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
  }

  @override
  Future<void> joinMatch(String matchId, {int side = 0}) async {
    await _rpc<dynamic>('join_match', {
      'p_match_id': matchId,
      'p_side': side,
    }, fallback: 'You could not join this match.');
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
  }

  @override
  Future<void> leaveMatch(String matchId) async {
    await _rpc<dynamic>('leave_match', {
      'p_match_id': matchId,
    }, fallback: 'You could not leave this match.');
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
  }

  @override
  Future<int> addSquadToMatch(
    String matchId,
    String squadId, {
    int side = 0,
  }) async {
    final added = await _rpc<dynamic>('add_match_squad', {
      'p_match_id': matchId,
      'p_side': side,
      'p_squad_id': squadId,
    }, fallback: 'The squad could not be added.');
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
    return added is int ? added : int.tryParse('$added') ?? 0;
  }

  @override
  Future<void> assignMatchScorer(String matchId, String scorerId) async {
    await _rpc<dynamic>('assign_match_scorer', {
      'p_match_id': matchId,
      'p_scorer_id': scorerId,
    }, fallback: 'The official scorer could not be assigned.');
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
  }

  @override
  Future<void> revokeMatchScorer(String matchId) async {
    await _rpc<dynamic>('revoke_match_scorer', {
      'p_match_id': matchId,
    }, fallback: 'The official scorer could not be revoked.');
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
  }

  @override
  Future<void> startMatch(String matchId) async {
    await _rpc<dynamic>('start_match', {
      'p_match_id': matchId,
    }, fallback: 'The match could not be started.');
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
  }

  @override
  Future<void> pauseMatch(String matchId, {String? reason}) async {
    final trimmed = reason?.trim();
    await _rpc<dynamic>('pause_match', {
      'p_match_id': matchId,
      'p_reason': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
    }, fallback: 'Scoring could not be paused.');
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
  }

  @override
  Future<void> resumeMatch(String matchId) async {
    await _rpc<dynamic>('resume_match', {
      'p_match_id': matchId,
    }, fallback: 'Scoring could not be resumed.');
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
  }

  @override
  Future<MatchEvent> recordEvent(
    String matchId, {
    required String kind,
    int? side,
    Map<String, dynamic> data = const {},
    String? clientId,
    DateTime? at,
  }) async {
    final cid = clientId ?? newId('ev');
    final local = MatchEvent(
      id: 'pending-$cid',
      seq: (matchById(matchId)?.eventCount ?? 0) + 1,
      clientId: cid,
      kind: kind,
      side: side,
      data: Map<String, dynamic>.from(data),
      at: at ?? DateTime.now(),
      byAccountId: _client.auth.currentUser?.id ?? '',
    );

    _requireSession();
    try {
      final row = await _client.rpc(
        'record_match_event',
        params: {
          'p_match_id': matchId,
          'p_client_event_id': cid,
          'p_kind': kind,
          'p_side': side,
          'p_data': data,
        },
      );
      _sync = MatchSyncState.idle;
      final event = _eventFromRow(Map<String, dynamic>.from(row as Map));
      await _settlePending(matchId, cid);
      await _refreshMatch(matchId);
      notifyListeners();
      return event;
    } on PostgrestException catch (error) {
      // The server answered and refused. Retrying would refuse again, so the
      // error goes back to the scorer instead of the outbox.
      _sync = MatchSyncState.failed;
      notifyListeners();
      throw _mapError(error, fallback: 'That entry could not be recorded.');
    } catch (_) {
      // The server did not answer. Keep the tap, paint it, retry with the same
      // client event id so the server dedupes rather than double-counts.
      _pending.putIfAbsent(matchId, () => []).add(local);
      _sync = MatchSyncState.offline;
      notifyListeners();
      await _queue(local, matchId);
      return local;
    }
  }

  @override
  Future<void> voidEvent(String matchId, String eventId) async {
    if (eventId.startsWith('pending-')) {
      // Never reached the server, so undo is purely local.
      final cid = eventId.substring('pending-'.length);
      _pending[matchId]?.removeWhere((e) => e.clientId == cid);
      notifyListeners();
      await _dequeue(matchId, cid);
      return;
    }
    await _rpc<dynamic>('void_match_event', {
      'p_match_id': matchId,
      'p_event_id': eventId,
    }, fallback: 'That entry could not be undone.');
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
  }

  @override
  Future<void> submitResult(
    String matchId, {
    required String headline,
    required String detail,
    required List<String> sideScores,
    required List<int> sideValues,
    required int winnerIndex,
  }) async {
    // Padel is the one sport whose result the server folds itself, so it is
    // submitted through the door that takes no score at all. The device's own
    // reading is still what the workspace paints, but it never becomes the
    // official record: `complete_padel_match` derives both sides' set strings,
    // the set totals and the winner from the point log it has locked.
    if (await _isPadel(matchId)) {
      await _completePadel(matchId);
      return;
    }
    await _rpc<dynamic>('submit_match_result', {
      'p_match_id': matchId,
      'p_headline': headline.trim(),
      'p_detail': detail.trim(),
      'p_side_scores': sideScores,
      'p_side_values': sideValues,
      'p_winner_index': winnerIndex,
    }, fallback: 'The result could not be submitted.');
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
  }

  /// Whether [matchId] names a padel match, which is the only case that changes
  /// which RPC may be called. The loaded snapshot normally already knows; a
  /// one-column read answers when the match is not in it, and a read that fails
  /// falls through to the generic door, where migration 0013 still re-checks
  /// the totals and the winner against the server's own fold.
  Future<bool> _isPadel(String matchId) async {
    final loaded = matchById(matchId);
    if (loaded != null) return loaded.sport == Sport.padel;
    try {
      final row = await _client
          .from('matches')
          .select('sport_key')
          .eq('id', matchId)
          .maybeSingle();
      return row?['sport_key'] == 'padel';
    } catch (_) {
      return false;
    }
  }

  /// `complete_padel_match(p_match_id)` of migration 0013, plus the retry
  /// semantics the submission button needs: a scorer can tap twice, and a
  /// completion whose answer was lost in transit has already been written.
  /// The RPC refuses both by the lifecycle rule alone - it only accepts a live
  /// match - so the row is read back to tell "already submitted" (success) from
  /// "nothing was written yet" (the error the scorer has to see).
  Future<void> _completePadel(String matchId) async {
    try {
      await _rpc<dynamic>('complete_padel_match', {
        'p_match_id': matchId,
      }, fallback: 'The result could not be submitted.');
    } on MatchRepositoryException catch (error) {
      if (error.code != '22023') rethrow;
      await _refreshMatch(matchId);
      final current = matchById(matchId);
      final settled =
          current?.result != null &&
          (current!.status == FixtureStatus.submitted ||
              current.status == FixtureStatus.published);
      if (!settled) rethrow;
      // Nothing failed: the submission the scorer asked for is on the record.
      _sync = MatchSyncState.idle;
      return;
    }
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
  }

  @override
  Future<void> publishResult(String matchId) async {
    await _rpc<dynamic>('publish_match_result', {
      'p_match_id': matchId,
    }, fallback: 'The result could not be published.');
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
  }

  @override
  Future<void> correctResult(
    String matchId, {
    required String headline,
    required String detail,
    required List<String> sideScores,
    required List<int> sideValues,
    required int winnerIndex,
    required String reason,
  }) async {
    await _rpc<dynamic>('correct_match_result', {
      'p_match_id': matchId,
      'p_headline': headline.trim(),
      'p_detail': detail.trim(),
      'p_side_scores': sideScores,
      'p_side_values': sideValues,
      'p_winner_index': winnerIndex,
      'p_reason': reason.trim(),
    }, fallback: 'The correction could not be saved.');
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
  }

  @override
  Future<void> recordMatchWalkover(
    String matchId, {
    required int winnerIndex,
    required String reason,
  }) async {
    await _rpc<dynamic>('record_match_walkover', {
      'p_match_id': matchId,
      'p_winner_index': winnerIndex,
      'p_reason': reason.trim(),
    }, fallback: 'The walkover could not be recorded.');
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
  }

  @override
  Future<void> retireMatch(
    String matchId, {
    required int winnerIndex,
    required String reason,
  }) async {
    await _rpc<dynamic>('retire_match', {
      'p_match_id': matchId,
      'p_winner_index': winnerIndex,
      'p_reason': reason.trim(),
    }, fallback: 'The retirement could not be recorded.');
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
  }

  @override
  Future<MatchDispute> raiseMatchDispute(String matchId, String reason) async {
    final row = await _rpc<dynamic>('raise_match_dispute', {
      'p_match_id': matchId,
      'p_reason': reason.trim(),
    }, fallback: 'The dispute could not be raised.');
    final dispute = _disputeFromRow(Map<String, dynamic>.from(row as Map));
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
    return dispute;
  }

  @override
  Future<MatchDispute> resolveMatchDispute(
    String matchId,
    String disputeId, {
    required MatchDisputeStatus status,
    String? resolution,
  }) async {
    final trimmed = resolution?.trim();
    final row = await _rpc<dynamic>('resolve_match_dispute', {
      'p_dispute_id': disputeId,
      'p_resolution': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      'p_status': status.key,
    }, fallback: 'The dispute could not be resolved.');
    final dispute = _disputeFromRow(Map<String, dynamic>.from(row as Map));
    await _refreshMatch(matchId);
    _sync = MatchSyncState.idle;
    return dispute;
  }

  @override
  List<MatchDispute> disputesOf(String matchId) => [
    ...?matchById(matchId)?.disputes,
  ];

  // ── Realtime ────────────────────────────────────────────────────────────

  @override
  Future<void> watchMatch(String matchId) async {
    if (_channels.containsKey(matchId)) return;
    if (_client.auth.currentUser == null) return;

    void refresh(PostgresChangePayload _) => _refreshMatch(matchId);

    final channel = _client
        .channel('match:$matchId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'match_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'match_id',
            value: matchId,
          ),
          callback: refresh,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'matches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: matchId,
          ),
          callback: refresh,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'match_results',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'match_id',
            value: matchId,
          ),
          callback: refresh,
        )
        // Roster moves (invites sent, answers, removals) touch only
        // match_participants, so without this the participants sheet on a
        // second device stayed stale until a manual refresh.
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'match_participants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'match_id',
            value: matchId,
          ),
          callback: refresh,
        );
    _channels[matchId] = channel;
    channel.subscribe();
  }

  @override
  Future<void> unwatchMatch(String matchId) async {
    final channel = _channels.remove(matchId);
    if (channel == null) return;
    await channel.unsubscribe();
  }

  /// Subscribes to every match the signed-in member can see.
  /// A single app-level channel watches INSERT/UPDATE/DELETE on `matches`; any
  /// change calls `reload()` so the discovery feed and tournament fixtures
  /// reflect live data without opening each workspace.
  /// Realtime respects RLS, so the member receives only rows they can SELECT.
  @override
  Future<void> watchAllMatches() async {
    if (_allChannel != null) return;
    final channel = _client
        .channel('all-matches')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'matches',
          callback: (_) => unawaited(reload()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'matches',
          callback: (_) => unawaited(reload()),
        );
    _allChannel = channel;
    channel.subscribe();
  }

  @override
  Future<void> unwatchAllMatches() async {
    final channel = _allChannel;
    _allChannel = null;
    if (channel != null) await channel.unsubscribe();
  }

  // ── Offline outbox ──────────────────────────────────────────────────────

  Future<void> _queue(MatchEvent event, String matchId) async {
    final storage = outbox;
    if (storage == null) return;
    final entries = storage.readMatchOutbox();
    if (entries.any((e) => e['clientId'] == event.clientId)) return;
    entries.add({
      'matchId': matchId,
      'clientId': event.clientId,
      'kind': event.kind,
      'side': event.side,
      'data': event.data,
      'at': event.at.toIso8601String(),
    });
    await storage.writeMatchOutbox(entries);
  }

  Future<void> _dequeue(String matchId, String clientId) async {
    final storage = outbox;
    if (storage == null) return;
    final entries = storage.readMatchOutbox()
      ..removeWhere(
        (e) => e['clientId'] == clientId && e['matchId'] == matchId,
      );
    await storage.writeMatchOutbox(entries);
  }

  Future<void> _settlePending(String matchId, String clientId) async {
    _pending[matchId]?.removeWhere((e) => e.clientId == clientId);
    if (_pending[matchId]?.isEmpty ?? false) _pending.remove(matchId);
    await _dequeue(matchId, clientId);
  }

  /// Retries every queued tap with its original client event id. Safe to call
  /// on resume, on reconnect and on reload: the server returns the existing row
  /// for an id it already has.
  Future<void> flushOutbox() async {
    final storage = outbox;
    if (storage == null) return;
    final entries = storage.readMatchOutbox();
    if (entries.isEmpty) {
      _sync = MatchSyncState.idle;
      return;
    }
    _sync = MatchSyncState.syncing;
    notifyListeners();

    var sent = 0;
    for (final entry in [...entries]) {
      final matchId = entry['matchId'] as String?;
      if (matchId == null) {
        entries.remove(entry);
        continue;
      }
      try {
        await _client.rpc(
          'record_match_event',
          params: {
            'p_match_id': matchId,
            'p_client_event_id': entry['clientId'],
            'p_kind': entry['kind'],
            'p_side': entry['side'],
            'p_data': entry['data'] ?? const <String, dynamic>{},
          },
        );
        await _settlePending(matchId, entry['clientId'] as String);
        sent++;
      } on PostgrestException {
        // The server refused it outright: dropping it is the only way to stop
        // a permanent retry loop, and the next reload shows the real log.
        await _settlePending(matchId, entry['clientId'] as String);
      } catch (_) {
        // Still offline; keep it for the next attempt.
      }
    }

    await storage.writeMatchOutbox(storage.readMatchOutbox());
    if (sent > 0) {
      _sync = storage.readMatchOutbox().isEmpty
          ? MatchSyncState.idle
          : MatchSyncState.offline;
      notifyListeners();
      await reload();
    } else {
      _sync = MatchSyncState.offline;
      notifyListeners();
    }
  }

  // ── Row mapping ─────────────────────────────────────────────────────────

  SportMatch _matchFromRow(Map<String, dynamic> row) {
    final participants = <MatchParticipant>[];
    final rawParticipants = row['match_participants'];
    if (rawParticipants is List) {
      for (final raw in rawParticipants) {
        final p = Map<String, dynamic>.from(raw as Map);
        final profile = p['profiles'];
        final name = profile is Map
            ? (profile['display_name'] as String? ?? '')
            : '';
        participants.add(
          MatchParticipant(
            profileId: p['profile_id'] as String? ?? '',
            displayName: name,
            side: (p['side'] as num?)?.toInt() ?? 0,
            status: MatchParticipantStatusX.fromKey(
              p['status'] as String? ?? 'invited',
            ),
            invitedById: p['invited_by'] as String?,
            joinedAt: DateTime.tryParse(p['updated_at'] as String? ?? ''),
          ),
        );
      }
    }

    final events = <MatchEvent>[];
    final rawEvents = row['match_events'];
    if (rawEvents is List) {
      for (final raw in rawEvents) {
        events.add(_eventFromRow(Map<String, dynamic>.from(raw as Map)));
      }
      events.sort((a, b) => a.seq.compareTo(b.seq));
    }

    OfficialResult? result;
    final rawResult = row['match_results'];
    final resultRow = rawResult is List
        ? (rawResult.isEmpty
              ? null
              : Map<String, dynamic>.from(rawResult.first as Map))
        : (rawResult is Map ? Map<String, dynamic>.from(rawResult) : null);
    if (resultRow != null) result = _resultFromRow(resultRow);

    final corrections = <ResultCorrection>[];
    final rawCorrections = row['match_result_corrections'];
    if (rawCorrections is List) {
      for (final raw in rawCorrections) {
        final c = Map<String, dynamic>.from(raw as Map);
        final previous = c['previous'];
        final current = c['current'];
        if (previous is! Map || current is! Map) continue;
        corrections.add(
          ResultCorrection(
            id: c['id'] as String? ?? '',
            previous: OfficialResult.fromJson(
              Map<String, dynamic>.from(previous),
            ),
            current: OfficialResult.fromJson(
              Map<String, dynamic>.from(current),
            ),
            reason: c['reason'] as String? ?? '',
            byAccountId: c['changed_by'] as String? ?? '',
            at: DateTime.tryParse(c['at'] as String? ?? '') ?? DateTime.now(),
          ),
        );
      }
      corrections.sort((a, b) => b.at.compareTo(a.at));
    }

    final discipline = MatchDisciplineX.fromKey(
      row['discipline'] as String? ?? 'team',
    );
    final disputes = <MatchDispute>[];
    final rawDisputes = row['match_disputes'];
    if (rawDisputes is List) {
      for (final raw in rawDisputes) {
        disputes.add(_disputeFromRow(Map<String, dynamic>.from(raw as Map)));
      }
      disputes.sort((a, b) => b.raisedAt.compareTo(a.raisedAt));
    }
    final rules = Map<String, dynamic>.from(row['rules'] as Map? ?? const {});
    rules['discipline'] ??= discipline.key;

    return SportMatch(
      id: row['id'] as String,
      sport: SportX.fromKey(row['sport_key'] as String? ?? 'cricket'),
      formatLabel: row['format_label'] as String? ?? '',
      rules: rules,
      title: row['title'] as String? ?? '',
      venue: row['venue'] as String? ?? '',
      scheduledAt:
          DateTime.tryParse(row['scheduled_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      visibility: MatchVisibilityX.fromKey(
        row['visibility'] as String? ?? 'public',
      ),
      organizerId: row['organizer_id'] as String? ?? '',
      scorerId: row['scorer_id'] as String?,
      status: FixtureStatusX.fromKey(row['status'] as String? ?? 'upcoming'),
      sideNames: [
        row['side_a_name'] as String? ?? 'Side A',
        row['side_b_name'] as String? ?? 'Side B',
      ],
      discipline: discipline,
      capacity: (row['capacity'] as num?)?.toInt() ?? 10,
      startedAt: DateTime.tryParse(row['started_at'] as String? ?? '')
          ?.toLocal(),
      submittedAt: DateTime.tryParse(row['submitted_at'] as String? ?? '')
          ?.toLocal(),
      completedAt: DateTime.tryParse(row['completed_at'] as String? ?? '')
          ?.toLocal(),
      publishedAt: DateTime.tryParse(row['published_at'] as String? ?? '')
          ?.toLocal(),
      pausedAt: DateTime.tryParse(row['paused_at'] as String? ?? '')?.toLocal(),
      pausedBy: row['paused_by'] as String?,
      pauseReason: row['pause_reason'] as String?,
      eventCount: (row['event_count'] as num?)?.toInt() ?? events.length,
      tournamentId: row['tournament_id'] as String?,
      fixtureId: row['fixture_id'] as String?,
      isDemo: row['is_demo'] as bool? ?? false,
      participants: participants,
      events: events,
      result: result,
      corrections: corrections,
      disputes: disputes,
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  MatchEvent _eventFromRow(Map<String, dynamic> row) => MatchEvent(
    id: row['id'] as String? ?? '',
    seq: (row['seq'] as num?)?.toInt() ?? 0,
    clientId: row['client_event_id'] as String? ?? '',
    kind: row['kind'] as String? ?? '',
    side: (row['side'] as num?)?.toInt(),
    data: Map<String, dynamic>.from(row['data'] as Map? ?? const {}),
    at:
        DateTime.tryParse(row['recorded_at'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    byAccountId: row['recorded_by'] as String? ?? '',
    voided: row['voided'] as bool? ?? false,
  );

  OfficialResult _resultFromRow(Map<String, dynamic> row) => OfficialResult(
    sideScores: (row['side_scores'] as List<dynamic>? ?? const [])
        .map((e) => '$e')
        .toList(),
    sideValues: (row['side_values'] as List<dynamic>? ?? const [])
        .map((e) => (e as num).toInt())
        .toList(),
    winnerIndex: (row['winner_index'] as num?)?.toInt() ?? -1,
    headline: row['headline'] as String? ?? '',
    detail: row['detail'] as String? ?? '',
    publishedAt:
        DateTime.tryParse(row['published_at'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    publishedById: row['published_by'] as String? ?? '',
    walkover: row['walkover'] as bool? ?? false,
  );

  /// A `match_disputes` row, in the table's column names. `resolved_by` can be
  /// null while a dispute is still being reviewed, and `resolution` is only
  /// present once it has been closed - both are the server's guarantees, not
  /// something this client re-checks.
  MatchDispute _disputeFromRow(Map<String, dynamic> row) =>
      MatchDispute.fromRow(row);

  // ── Errors ──────────────────────────────────────────────────────────────

  MatchRepositoryException _mapError(Object error, {required String fallback}) {
    if (error is MatchRepositoryException) return error;
    if (error is PostgrestException) {
      return switch (error.code) {
        '28000' => const MatchRepositoryException(
          'Sign in again to score an official match.',
          code: '28000',
        ),
        '42501' => MatchRepositoryException(
          _messageFor(error.message),
          code: '42501',
        ),
        '22023' || '23514' || '23505' => MatchRepositoryException(
          _messageFor(error.message),
          code: error.code,
        ),
        'P0002' => MatchRepositoryException(
          // P0002 is "no row found". The match module raises it for a missing
          // match, event, dispute, participant or result, and each of those
          // needs its own sentence instead of "that match is gone".
          const {
                'match_not_found',
                'event_not_found',
                'dispute_not_found',
                'participant_not_found',
                'result_missing',
                'nothing_to_undo',
              }.contains(error.message.split('\n').first.trim())
              ? _messageFor(error.message)
              : 'That match could not be found. Pull to refresh.',
          code: 'P0002',
        ),
        _ => MatchRepositoryException(fallback, code: error.code),
      };
    }
    return MatchRepositoryException(fallback);
  }

  /// The RPCs raise stable snake_case identifiers; the member sees a sentence.
  String _messageFor(String? raw) {
    final message = raw ?? '';
    final code = message.split('\n').first.trim();
    return switch (code) {
      'not_match_organizer' => 'Only the organizer can do that.',
      'not_match_scorer' =>
        'Only the organizer or the assigned official scorer can do that.',
      'invalid_match_transition' => 'That match can no longer change that way.',
      'match_full' => 'This match is already full.',
      'side_full' =>
        'That side is full. Join the other side or wait for a place.',
      'match_not_public' =>
        'This match is invite-only, so it cannot be joined.',
      'organizer_cannot_leave' => 'The organizer cannot leave their own match.',
      'not_participant' => 'You are not on this match.',
      'not_squad_member' => 'You can only add a squad you belong to.',
      'squad_not_found' => 'That squad could not be found. Pull to refresh.',
      'squad_below_minimum' =>
        'A futsal team needs at least five members on the squad.',
      'draw_needs_full_squads' =>
        'Every confirmed squad needs five members before the draw can run.',
      'entry_type_mismatch' =>
        'That squad does not match the kind of entry this tournament takes.',
      'lineup_incomplete' =>
        'A starting five needs five players from that side who accepted.',
      'not_last_event' => 'Only the newest entry can be undone.',
      'invalid_result_payload' => 'A result needs a score for both sides.',
      'invalid_correction_reason' => 'Say why the result is being corrected.',
      'invalid_match_title' =>
        'Give the match a title between 2 and 80 characters.',
      'invalid_side_name' => 'Both sides need a name of 1 to 40 characters.',
      'invalid_capacity' => 'Capacity has to be between 2 and 100 players.',
      'invalid_discipline' => 'Pick the discipline this sport is played in.',
      'invalid_visibility' => 'Pick who can see this match.',
      'invalid_schedule' => 'Pick a start time for the match.',
      'invalid_venue' => 'Keep the venue to 80 characters or fewer.',
      'invalid_sport' ||
      'invalid_format' => 'Pick a supported sport and format.',
      'scorer_not_found' => 'Pick a registered member as the official scorer.',
      'player_not_found' => 'That member could not be found.',
      'organizer_already_joined' => 'You are already on this match.',
      'invite_not_found' => 'That invitation is not yours.',
      'participant_not_found' => 'That player is not on this match.',
      'cannot_remove_organizer' =>
        'The organizer cannot be removed from their own match.',
      'result_missing' => 'Submit a result before publishing.',
      'match_not_found' => 'That match could not be found. Pull to refresh.',
      'match_complete' =>
        'This match is already complete. Undo the last point to make changes.',
      'result_already_submitted' =>
        'The result has been submitted and cannot be undone.',
      'incomplete_fixture_link' =>
        'A tournament match needs both a tournament and a fixture id.',
      'match_paused' =>
        'Scoring is paused. Resume the match before recording another point.',
      'invalid_pause_reason' =>
        'Give the reason in 3 to 200 characters, or leave it out.',
      'nothing_to_undo' => 'There is no entry left to undo.',
      'event_not_found' => 'That entry no longer exists. Pull to refresh.',
      'event_already_voided' => 'That entry has already been undone.',
      'roster_incomplete' =>
        'Both sides need a player who has accepted before the match can start.',
      'roster_overflow' =>
        'That is more players than this discipline and capacity allow.',
      'score_payload_mismatch' =>
        'The server scores this match itself, so the result has to come from '
            'the recorded points. Reload the scoreboard and submit again.',
      'no_result_to_dispute' => 'There is no official result to dispute yet.',
      'invalid_dispute_reason' =>
        'Say what is wrong with the result in 5 to 500 characters.',
      'invalid_dispute_resolution' =>
        'A closed dispute needs a resolution of 3 to 500 characters.',
      'invalid_dispute_status' =>
        'Pick one of the answers the server recognises.',
      'dispute_already_open' =>
        'You already have a live dispute on this match.',
      'dispute_already_closed' => 'This dispute has already been answered.',
      'dispute_not_found' =>
        'That dispute could not be found. Pull to refresh.',
      'not_match_stakeholder' => 'Only the players, the scorer or the organizer can dispute this result.',
      'forbidden' => 'You are not allowed to do that on this match.',
      'not_authenticated' => 'Sign in again to score an official match.',
      'wrong_sport' => 'That scoring action does not belong to this sport.',
      'invalid_client_event' =>
        'That entry needs a client id so a retry cannot count twice.',
      'invalid_event_kind' => 'That kind of entry is not recognised.',
      'invalid_event_side' => 'Pick which side the entry belongs to.',
      'invalid_event_data' => 'That entry carries data the server cannot read.',
      'invalid_void_reason' => 'Say why the entry is being withdrawn.',
      'invalid_rally_side' => 'Pick which side won the rally.',
      'invalid_retire_reason' =>
        'Say why the match is being retired in 3 to 200 characters.',
      'invalid_padel_rules' ||
      'invalid_rules' => 'Those padel rules are not a format the server knows.',
      'invalid_tournament_id' => 'That tournament id is not valid.',
      'invalid_fixture_id' => 'That fixture id is not valid.',
      'match_not_complete' =>
        'The match is not finished yet. Keep scoring, or record a walkover.',
      'match_event_cannot_be_restored' =>
        'A withdrawn entry stays withdrawn. Record the point again instead.',
      'not_tournament_organizer' =>
        'Only the member who claimed this tournament can do that.',
      'fixture_already_linked' =>
        'That draw slot already has a match. Pull to refresh.',
      'match_events_are_immutable' =>
        'A recorded point can only be withdrawn by undo, never rewritten.',
      _ => 'The server refused that change. Pull to refresh and try again.',
    };
  }

  @override
  void dispose() {
    for (final channel in _channels.values) {
      channel.unsubscribe();
    }
    _channels.clear();
    _allChannel?.unsubscribe();
    _allChannel = null;
    super.dispose();
  }
}
