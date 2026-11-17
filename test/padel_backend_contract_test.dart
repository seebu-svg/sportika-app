import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide LocalStorage;

import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/core/data/supabase_match_repository.dart';
import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';

/// The contract the padel backend (migrations 0012, 0013 and 0014) makes with
/// the app, checked from both sides of the seam:
///
///  * the models carry the pause columns and the dispute rows, in JSON and in
///    the server's column names;
///  * the device repository refuses exactly what the RPCs refuse, so demo mode
///    and widget tests exercise real permission semantics;
///  * the Supabase adapter calls the right RPC with the right parameter names,
///    reads the new columns back, and turns every stable error identifier into
///    a sentence a member can act on.
///
/// The SQL side of the same contract is proved by supabase/tests/padel_*.sql.
const owner = '31111111-1111-1111-1111-111111111111';
const player = '32222222-2222-2222-2222-222222222222';
const matchId = '9aaa1111-1111-1111-1111-111111111111';
const disputeId = '9bbb2222-2222-2222-2222-222222222222';

SportMatch _match({
  FixtureStatus status = FixtureStatus.live,
  DateTime? pausedAt,
  String? pauseReason,
  OfficialResult? result,
  List<MatchParticipant>? participants,
  List<MatchDispute>? disputes,
}) {
  final now = DateTime(2026, 5, 1, 18);
  return SportMatch(
    id: matchId,
    sport: Sport.padel,
    formatLabel: '1 set · first to 6',
    rules: const {'setsToWin': 1, 'gamesToWinSet': 6, 'discipline': 'singles'},
    title: 'Court three showdown',
    venue: 'Court three',
    scheduledAt: now,
    visibility: MatchVisibility.public,
    organizerId: owner,
    scorerId: owner,
    status: status,
    sideNames: const ['Rao', 'Malik'],
    discipline: MatchDiscipline.singles,
    capacity: 2,
    createdAt: now,
    pausedAt: pausedAt,
    pausedBy: pausedAt == null ? null : owner,
    pauseReason: pauseReason,
    result: result,
    disputes: disputes,
    participants:
        participants ??
        [
          MatchParticipant(
            profileId: owner,
            displayName: 'Rao',
            side: 0,
            status: MatchParticipantStatus.accepted,
            invitedById: owner,
            joinedAt: now,
          ),
          MatchParticipant(
            profileId: player,
            displayName: 'Malik',
            side: 1,
            status: MatchParticipantStatus.accepted,
            invitedById: owner,
            joinedAt: now,
          ),
        ],
  );
}

OfficialResult _result() => OfficialResult(
  sideScores: const ['6', '3'],
  sideValues: const [6, 3],
  winnerIndex: 0,
  headline: 'Rao won 6-3',
  detail: '1 set · first to 6',
  publishedAt: DateTime(2026, 5, 1, 19),
  publishedById: owner,
);

MatchDispute _dispute({
  MatchDisputeStatus status = MatchDisputeStatus.open,
  String? resolution,
}) => MatchDispute(
  id: disputeId,
  matchId: matchId,
  raisedById: player,
  reason: 'The third game was scored to the wrong side.',
  status: status,
  resolution: resolution,
  resolvedById: resolution == null ? null : owner,
  resolvedAt: resolution == null ? null : DateTime(2026, 5, 2),
  raisedAt: DateTime(2026, 5, 1, 20),
);

Map<String, dynamic> _session() => {
  'access_token': 'test-access-token',
  'refresh_token': 'test-refresh-token',
  'token_type': 'bearer',
  'expires_in': 3600,
  'user': {
    'id': owner,
    'aud': 'authenticated',
    'email': 'test@example.com',
    'created_at': '2026-01-01T00:00:00Z',
    'app_metadata': {},
    'user_metadata': {},
  },
};

/// A fake PostgREST that answers the new padel RPCs the way migrations 0012 to
/// 0014 do: the paused columns and the dispute rows live on the match, the
/// parameters are the SQL named arguments, and a refusal is the server's own
/// identifier with its own SQLSTATE. A test injects one refusal at a time.
class _PadelBackend {
  _PadelBackend();

  final List<http.Request> calls = [];

  /// The match as the server holds it.
  DateTime? pausedAt;
  String? pausedBy;
  String? pauseReason;
  bool submitted = false;
  List<Map<String, dynamic>> disputes = [];

  /// Set to make the next RPC refuse with (identifier, SQLSTATE).
  (String, String)? refusal;

  int _seq = 0;

  late final SupabaseClient client = SupabaseClient(
    'https://example.supabase.co',
    'test-key',
    authOptions: const AuthClientOptions(
      autoRefreshToken: false,
      authFlowType: AuthFlowType.implicit,
    ),
    httpClient: MockClient((request) async {
      calls.add(request);
      final path = request.url.path;
      if (path == '/auth/v1/token') return _json(_session(), 200, request);
      if (path.startsWith('/rest/v1/rpc/')) {
        return _rpc(path.split('/').last, request);
      }
      if (path == '/rest/v1/matches') {
        final wantsObject = (request.headers['Accept'] ?? '').contains(
          'pgrst.object',
        );
        return _json(wantsObject ? _row() : [_row()], 200, request);
      }
      return _json(
        {'message': 'no route $path', 'code': 'PGRST404'},
        404,
        request,
      );
    }),
  );

  http.Response _rpc(String name, http.Request request) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final injected = refusal;
    if (injected != null) {
      refusal = null;
      return _json(
        {
          'message': injected.$1,
          'code': injected.$2,
          'hint': null,
          'details': null,
        },
        400,
        request,
      );
    }
    switch (name) {
      case 'pause_match':
        pausedAt = DateTime.parse('2026-05-01T18:30:00Z');
        pausedBy = owner;
        pauseReason = body['p_reason'] as String?;
        return _json(_row(), 200, request);
      case 'resume_match':
        pausedAt = null;
        pausedBy = null;
        pauseReason = null;
        return _json(_row(), 200, request);
      case 'record_match_event':
        // Padel points run through `_padel_award_point`, which returns the row
        // it stored for a replayed client id - never a second one.
        _seq += 1;
        final cid = body['p_client_event_id'] as String;
        final row = {
          'id': 'srv-$cid',
          'seq': _seq,
          'client_event_id': cid,
          'kind': body['p_kind'],
          'side': body['p_side'],
          'data': body['p_data'] ?? const <String, dynamic>{},
          'recorded_at': '2026-05-01T18:00:00Z',
          'recorded_by': owner,
          'voided': false,
        };
        return _json(row, 201, request);
      case 'raise_match_dispute':
        _seq += 1;
        final row = {
          'id': 'dsp-$_seq',
          'match_id': matchId,
          'raised_by': owner,
          'reason': body['p_reason'],
          'status': 'open',
          'resolution': null,
          'resolved_by': null,
          'resolved_at': null,
          'created_at': '2026-05-01T20:00:00Z',
        };
        disputes = [row, ...disputes];
        return _json(row, 201, request);
      case 'resolve_match_dispute':
        final status = body['p_status'] as String;
        final closed = status == 'resolved' || status == 'rejected';
        final updated = [
          for (final d in disputes)
            if (d['id'] == body['p_dispute_id'])
              {
                ...d,
                'status': status,
                'resolution': body['p_resolution'],
                'resolved_by': owner,
                'resolved_at': closed ? '2026-05-02T09:00:00Z' : null,
              }
            else
              d,
        ];
        disputes = updated;
        return _json(updated.first, 200, request);
    }
    return _json({'message': 'unknown rpc $name'}, 500, request);
  }

  Map<String, dynamic> _row() => {
    'id': matchId,
    'sport_key': 'padel',
    'format_label': '1 set · first to 6',
    'rules': const {'setsToWin': 1, 'gamesToWinSet': 6},
    'title': 'Court three showdown',
    'venue': 'Court three',
    'scheduled_at': '2026-05-01T18:00:00Z',
    'visibility': 'public',
    'organizer_id': owner,
    'scorer_id': owner,
    'status': submitted ? 'submitted' : 'live',
    'side_a_name': 'Rao',
    'side_b_name': 'Malik',
    'capacity': 2,
    'started_at': '2026-05-01T17:59:00Z',
    'submitted_at': submitted ? '2026-05-01T19:00:00Z' : null,
    'completed_at': null,
    'paused_at': pausedAt?.toIso8601String(),
    'paused_by': pausedBy,
    'pause_reason': pauseReason,
    'event_count': _seq,
    'tournament_id': null,
    'fixture_id': null,
    'created_at': '2026-04-30T00:00:00Z',
    'match_participants': [
      {
        'profile_id': owner,
        'side': 0,
        'status': 'accepted',
        'invited_by': owner,
        'updated_at': '2026-04-30T00:00:00Z',
        'profiles': {'display_name': 'Rao'},
      },
    ],
    'match_events': const [],
    'match_results': submitted
        ? [
            {
              'id': 'res-1',
              'match_id': matchId,
              'side_a_score': '6',
              'side_b_score': '3',
              'side_a_value': 6,
              'side_b_value': 3,
              'winner_index': 0,
              'headline': 'Rao won 6-3',
              'detail': '1 set · first to 6',
              'published_at': '2026-05-01T19:00:00Z',
              'published_by': owner,
              'walkover': false,
            },
          ]
        : const [],
    'match_result_corrections': const [],
    'match_disputes': disputes,
  };

  http.Response _json(Object body, int status, http.Request request) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
        request: request,
      );

  /// The body the adapter last sent to one RPC.
  Map<String, dynamic> bodyFor(String rpc) {
    final call = calls.lastWhere((r) => r.url.path == '/rest/v1/rpc/$rpc');
    return jsonDecode(call.body) as Map<String, dynamic>;
  }

  int rpcCalls(String rpc) =>
      calls.where((r) => r.url.path == '/rest/v1/rpc/$rpc').length;

  Future<void> signIn() => client.auth.signInWithPassword(
    email: 'test@example.com',
    password: 'test-password',
  );

  void dispose() => client.dispose();
}

void main() {
  // ── Models ───────────────────────────────────────────────────────────────

  group('padel backend models', () {
    test('a match without pause columns is not paused', () {
      final m = _match();
      expect(m.isPaused, isFalse);
      expect(m.pausedAt, isNull);
      expect(m.pauseReason, isNull);
      expect(m.disputes, isEmpty);
      expect(m.hasResult, isFalse);
    });

    test('pause columns survive the device JSON round-trip', () {
      final m = _match(
        pausedAt: DateTime(2026, 5, 1, 18, 30),
        pauseReason: 'Rain on court three',
      );
      final restored = SportMatch.fromJson(m.toJson());
      expect(restored.isPaused, isTrue);
      expect(restored.pausedAt, m.pausedAt);
      expect(restored.pausedBy, owner);
      expect(restored.pauseReason, 'Rain on court three');
      // A pause never changes the lifecycle status: the match is still live.
      expect(restored.status, FixtureStatus.live);
    });

    test('disputes survive the device JSON round-trip', () {
      final m = _match(
        result: _result(),
        disputes: [_dispute(status: MatchDisputeStatus.underReview)],
      );
      final restored = SportMatch.fromJson(m.toJson());
      expect(restored.disputes, hasLength(1));
      final d = restored.disputes.single;
      expect(d.id, disputeId);
      expect(d.matchId, matchId);
      expect(d.raisedById, player);
      expect(d.status, MatchDisputeStatus.underReview);
      expect(d.status.isOpen, isTrue);
      expect(d.resolution, isNull);
      expect(d.raisedAt, DateTime(2026, 5, 1, 20));
    });

    test('a closed dispute keeps its answer through JSON', () {
      final d = _dispute(
        status: MatchDisputeStatus.resolved,
        resolution: 'Recounted from the log; the score stands.',
      );
      final restored = MatchDispute.fromJson(d.toJson());
      expect(restored.status, MatchDisputeStatus.resolved);
      expect(restored.status.isOpen, isFalse);
      expect(restored.resolution, d.resolution);
      expect(restored.resolvedById, owner);
      expect(restored.resolvedAt, DateTime(2026, 5, 2));
    });

    test('fromRow reads the match_disputes column names', () {
      final d = MatchDispute.fromRow({
        'id': disputeId,
        'match_id': matchId,
        'raised_by': player,
        'reason': 'Wrong side served the decider.',
        'status': 'under_review',
        'resolution': null,
        'resolved_by': null,
        'resolved_at': null,
        'created_at': '2026-05-01T20:00:00Z',
      });
      expect(d.matchId, matchId);
      expect(d.raisedById, player);
      expect(d.status, MatchDisputeStatus.underReview);
      expect(d.resolvedById, isNull);
      expect(d.resolvedAt, isNull);
      expect(d.raisedAt.toUtc(), DateTime.utc(2026, 5, 1, 20));
    });

    test('status keys are the values the SQL check constraint accepts', () {
      expect(MatchDisputeStatus.values.map((s) => s.key), [
        'open',
        'under_review',
        'resolved',
        'rejected',
      ]);
      expect(
        MatchDisputeStatusX.fromKey('under_review'),
        MatchDisputeStatus.underReview,
      );
      // An unknown value must not throw: a row from a newer server still reads.
      expect(MatchDisputeStatusX.fromKey('nonsense'), MatchDisputeStatus.open);
    });

    test('only open and under_review count as a live dispute', () {
      expect(MatchDisputeStatus.open.isOpen, isTrue);
      expect(MatchDisputeStatus.underReview.isOpen, isTrue);
      expect(MatchDisputeStatus.resolved.isOpen, isFalse);
      expect(MatchDisputeStatus.rejected.isOpen, isFalse);
    });

    test('canDispute covers the members of the match, not a bystander', () {
      final m = _match(result: _result());
      expect(m.canDispute(owner), isTrue); // organizer and scorer
      expect(m.canDispute(player), isTrue); // accepted participant
      expect(m.canDispute('someone-else'), isFalse);
      expect(m.canDispute(null), isFalse);
    });

    test('a declined or removed player cannot dispute', () {
      for (final status in [
        MatchParticipantStatus.declined,
        MatchParticipantStatus.removed,
      ]) {
        final m = _match(
          result: _result(),
          participants: [
            MatchParticipant(
              profileId: player,
              displayName: 'Malik',
              side: 1,
              status: status,
              invitedById: owner,
              joinedAt: DateTime(2026),
            ),
          ],
        );
        expect(m.canDispute(player), isFalse, reason: '$status');
        expect(m.canDispute(owner), isTrue);
      }
    });

    test('only the organizer answers a dispute', () {
      final m = _match(result: _result());
      expect(m.canResolveDispute(owner), isTrue);
      expect(m.canResolveDispute(player), isFalse);
      expect(m.canResolveDispute(null), isFalse);
    });
  });

  // ── Device mirror ────────────────────────────────────────────────────────

  group('padel backend device mirror', () {
    late LocalSportikaRepository store;
    late MatchController controller;
    late Account organizer;
    late Account member;
    late Account bystander;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'sportika.onboarding_seen.v1': true,
      });
      store = LocalSportikaRepository(await LocalStorage.open());
      await store.load();
      organizer = store.accounts[0];
      member = store.accounts[2];
      bystander = store.accounts[3];
      await store.signIn(organizer.id);
      controller = MatchController(store);
    });

    tearDown(() {
      controller.dispose();
      store.dispose();
    });

    Future<SportMatch> newMatch() {
      const format = '1 set · first to 6';
      return store.createMatch(
        MatchDraft(
          sport: Sport.padel,
          formatLabel: format,
          rules: SportEngines.rulesFor(Sport.padel, format),
          title: 'Court three showdown',
          venue: 'Court three',
          scheduledAt: DateTime.now().add(const Duration(days: 1)),
          visibility: MatchVisibility.public,
          sideA: 'Rao',
          sideB: 'Malik',
          capacity: 2,
          discipline: MatchDiscipline.singles,
        ),
      );
    }

    /// A live match with an accepted player on side B, signed in as organizer.
    Future<SportMatch> liveMatch() async {
      final created = await newMatch();
      await store.inviteParticipant(created.id, member.id, side: 1);
      await store.signIn(member.id);
      await store.respondToInvite(created.id, accept: true);
      await store.signIn(organizer.id);
      await store.startMatch(created.id);
      return store.matchById(created.id)!;
    }

    Future<void> submit(SportMatch m) => store.submitResult(
      m.id,
      headline: 'Rao won 6-3',
      detail: '1 set · first to 6',
      sideScores: const ['6', '3'],
      sideValues: const [6, 3],
      winnerIndex: 0,
    );

    test('pause keeps the match live and records who and why', () async {
      final m = await liveMatch();
      await store.pauseMatch(m.id, reason: 'Rain on court three');

      final paused = store.matchById(m.id)!;
      expect(paused.isPaused, isTrue);
      expect(paused.status, FixtureStatus.live);
      expect(paused.pausedBy, organizer.id);
      expect(paused.pauseReason, 'Rain on court three');
      expect(paused.pausedAt, isNotNull);
    });

    test('a pause without a reason stores no reason', () async {
      final m = await liveMatch();
      await store.pauseMatch(m.id);
      expect(store.matchById(m.id)!.isPaused, isTrue);
      expect(store.matchById(m.id)!.pauseReason, isNull);
    });

    test('pausing twice is a no-op, not a refusal', () async {
      final m = await liveMatch();
      await store.pauseMatch(m.id, reason: 'First reason');
      final first = store.matchById(m.id)!.pausedAt;
      await store.pauseMatch(m.id, reason: 'Second reason');

      final paused = store.matchById(m.id)!;
      expect(paused.pausedAt, first);
      expect(paused.pauseReason, 'First reason');
    });

    test('the reason bounds mirror invalid_pause_reason', () async {
      final m = await liveMatch();
      await expectLater(
        store.pauseMatch(m.id, reason: 'ab'),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        store.pauseMatch(m.id, reason: 'x' * 201),
        throwsA(isA<StateError>()),
      );
      // Trimming happens before the length check, exactly like the RPC.
      await expectLater(
        store.pauseMatch(m.id, reason: '  ab  '),
        throwsA(isA<StateError>()),
      );
      await store.pauseMatch(m.id, reason: '  Rain delay  ');
      expect(store.matchById(m.id)!.pauseReason, 'Rain delay');
    });

    test('a member who cannot score cannot pause or resume', () async {
      final m = await liveMatch();
      await store.signIn(bystander.id);
      await expectLater(store.pauseMatch(m.id), throwsA(isA<StateError>()));
      await store.signIn(organizer.id);
      await store.pauseMatch(m.id);
      await store.signIn(bystander.id);
      await expectLater(store.resumeMatch(m.id), throwsA(isA<StateError>()));
      expect(store.matchById(m.id)!.isPaused, isTrue);
    });

    test('only a live match can be paused', () async {
      final created = await newMatch();
      await expectLater(
        store.pauseMatch(created.id),
        throwsA(isA<StateError>()),
      );
      expect(store.matchById(created.id)!.isPaused, isFalse);
    });

    test('a paused match refuses a point until it is resumed', () async {
      final m = await liveMatch();
      await store.recordEvent(m.id, kind: 'point', side: 0, clientId: 'tap-1');
      await store.pauseMatch(m.id, reason: 'Lights failed');

      await expectLater(
        store.recordEvent(m.id, kind: 'point', side: 0, clientId: 'tap-2'),
        throwsA(isA<StateError>()),
      );
      expect(store.matchById(m.id)!.events, hasLength(1));

      await store.resumeMatch(m.id);
      final resumed = store.matchById(m.id)!;
      expect(resumed.isPaused, isFalse);
      expect(resumed.pausedBy, isNull);
      expect(resumed.pauseReason, isNull);

      await store.recordEvent(m.id, kind: 'point', side: 0, clientId: 'tap-2');
      expect(store.matchById(m.id)!.events, hasLength(2));
    });

    test('undo still works while paused, as the server allows', () async {
      final m = await liveMatch();
      final event = await store.recordEvent(
        m.id,
        kind: 'point',
        side: 0,
        clientId: 'tap-1',
      );
      await store.pauseMatch(m.id);
      await store.voidEvent(m.id, event.id);
      expect(store.matchById(m.id)!.events.single.voided, isTrue);
    });

    test('resuming a match that is not paused is a no-op', () async {
      final m = await liveMatch();
      await store.resumeMatch(m.id);
      expect(store.matchById(m.id)!.isPaused, isFalse);
    });

    test('the pause survives a reload of the device store', () async {
      final m = await liveMatch();
      await store.pauseMatch(m.id, reason: 'Rain on court three');
      await store.load();
      final restored = store.matchById(m.id)!;
      expect(restored.isPaused, isTrue);
      expect(restored.pauseReason, 'Rain on court three');
      expect(restored.pausedBy, organizer.id);
    });

    test('a result is required before a dispute', () async {
      final m = await liveMatch();
      await store.signIn(member.id);
      await expectLater(
        store.raiseMatchDispute(m.id, 'The score is wrong.'),
        throwsA(isA<StateError>()),
      );
      expect(store.disputesOf(m.id), isEmpty);
    });

    test('the reason bounds mirror invalid_dispute_reason', () async {
      final m = await liveMatch();
      await submit(m);
      await store.signIn(member.id);
      await expectLater(
        store.raiseMatchDispute(m.id, 'bad'),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        store.raiseMatchDispute(m.id, 'x' * 501),
        throwsA(isA<StateError>()),
      );
      final d = await store.raiseMatchDispute(m.id, '  Wrong side served.  ');
      expect(d.reason, 'Wrong side served.');
      expect(d.status, MatchDisputeStatus.open);
      expect(d.raisedById, member.id);
    });

    test('a bystander cannot dispute, a member can', () async {
      final m = await liveMatch();
      await submit(m);
      await store.signIn(bystander.id);
      await expectLater(
        store.raiseMatchDispute(m.id, 'The score is wrong.'),
        throwsA(isA<StateError>()),
      );
      await store.signIn(member.id);
      expect(
        await store.raiseMatchDispute(m.id, 'The score is wrong.'),
        isA<MatchDispute>(),
      );
      expect(store.disputesOf(m.id), hasLength(1));
    });

    test(
      'one live dispute per member, but a second member may raise',
      () async {
        final m = await liveMatch();
        await submit(m);
        await store.signIn(member.id);
        await store.raiseMatchDispute(m.id, 'The score is wrong.');
        await expectLater(
          store.raiseMatchDispute(m.id, 'Still wrong, differently.'),
          throwsA(isA<StateError>()),
        );
        await store.signIn(organizer.id);
        await store.raiseMatchDispute(m.id, 'I disagree with the tally too.');
        expect(store.disputesOf(m.id), hasLength(2));
      },
    );

    test('only the organizer answers a dispute', () async {
      final m = await liveMatch();
      await submit(m);
      await store.signIn(member.id);
      final d = await store.raiseMatchDispute(m.id, 'The score is wrong.');
      await expectLater(
        store.resolveMatchDispute(
          m.id,
          d.id,
          status: MatchDisputeStatus.resolved,
          resolution: 'Recounted; the score stands.',
        ),
        throwsA(isA<StateError>()),
      );
      expect(store.disputesOf(m.id).single.status, MatchDisputeStatus.open);
    });

    test('under review carries no resolution and stays live', () async {
      final m = await liveMatch();
      await submit(m);
      await store.signIn(member.id);
      final d = await store.raiseMatchDispute(m.id, 'The score is wrong.');
      await store.signIn(organizer.id);

      await expectLater(
        store.resolveMatchDispute(
          m.id,
          d.id,
          status: MatchDisputeStatus.underReview,
          resolution: 'Looking at it.',
        ),
        throwsA(isA<StateError>()),
      );

      final reviewed = await store.resolveMatchDispute(
        m.id,
        d.id,
        status: MatchDisputeStatus.underReview,
      );
      expect(reviewed.status, MatchDisputeStatus.underReview);
      expect(reviewed.status.isOpen, isTrue);
      expect(reviewed.resolution, isNull);
      expect(reviewed.resolvedAt, isNull);
      // Still one live dispute, so the member cannot raise another yet.
      await store.signIn(member.id);
      await expectLater(
        store.raiseMatchDispute(m.id, 'Another complaint.'),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'a closed dispute needs a resolution of 3 to 500 characters',
      () async {
        final m = await liveMatch();
        await submit(m);
        await store.signIn(member.id);
        final d = await store.raiseMatchDispute(m.id, 'The score is wrong.');
        await store.signIn(organizer.id);

        for (final status in [
          MatchDisputeStatus.resolved,
          MatchDisputeStatus.rejected,
        ]) {
          await expectLater(
            store.resolveMatchDispute(m.id, d.id, status: status),
            throwsA(isA<StateError>()),
          );
          await expectLater(
            store.resolveMatchDispute(
              m.id,
              d.id,
              status: status,
              resolution: 'ab',
            ),
            throwsA(isA<StateError>()),
          );
        }
        // `open` is not an answer the server accepts.
        await expectLater(
          store.resolveMatchDispute(
            m.id,
            d.id,
            status: MatchDisputeStatus.open,
          ),
          throwsA(isA<StateError>()),
        );

        final closed = await store.resolveMatchDispute(
          m.id,
          d.id,
          status: MatchDisputeStatus.rejected,
          resolution: 'The log confirms the published score.',
        );
        expect(closed.status, MatchDisputeStatus.rejected);
        expect(closed.status.isOpen, isFalse);
        expect(closed.resolvedById, organizer.id);
        expect(closed.resolvedAt, isNotNull);
      },
    );

    test('an answered dispute cannot be answered twice', () async {
      final m = await liveMatch();
      await submit(m);
      await store.signIn(member.id);
      final d = await store.raiseMatchDispute(m.id, 'The score is wrong.');
      await store.signIn(organizer.id);
      await store.resolveMatchDispute(
        m.id,
        d.id,
        status: MatchDisputeStatus.resolved,
        resolution: 'Recounted from the log.',
      );
      await expectLater(
        store.resolveMatchDispute(
          m.id,
          d.id,
          status: MatchDisputeStatus.rejected,
          resolution: 'Changed my mind.',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a member may raise again once their dispute is closed', () async {
      final m = await liveMatch();
      await submit(m);
      await store.signIn(member.id);
      final first = await store.raiseMatchDispute(m.id, 'The score is wrong.');
      await store.signIn(organizer.id);
      await store.resolveMatchDispute(
        m.id,
        first.id,
        status: MatchDisputeStatus.resolved,
        resolution: 'Recounted from the log.',
      );
      await store.signIn(member.id);
      await store.raiseMatchDispute(m.id, 'New evidence from the video.');
      expect(store.disputesOf(m.id), hasLength(2));
    });

    test('a dispute never changes the published result', () async {
      final m = await liveMatch();
      await submit(m);
      await store.publishResult(m.id);
      final published = store.matchById(m.id)!;
      await store.signIn(member.id);
      await store.raiseMatchDispute(m.id, 'The score is wrong.');

      final after = store.matchById(m.id)!;
      expect(after.status, FixtureStatus.published);
      expect(after.result!.headline, published.result!.headline);
      expect(after.result!.sideValues, published.result!.sideValues);
    });

    test('disputes survive a reload of the device store', () async {
      final m = await liveMatch();
      await submit(m);
      await store.signIn(member.id);
      await store.raiseMatchDispute(m.id, 'The score is wrong.');
      await store.load();
      final disputes = store.disputesOf(m.id);
      expect(disputes, hasLength(1));
      expect(disputes.single.raisedById, member.id);
      expect(disputes.single.status, MatchDisputeStatus.open);
    });

    test('the controller reports refusals instead of throwing', () async {
      final m = await liveMatch();
      expect(await controller.pauseMatch(m.id, reason: 'ab'), isFalse);
      expect(controller.lastError, isNotNull);

      expect(await controller.pauseMatch(m.id, reason: 'Rain delay'), isTrue);
      expect(controller.lastError, isNull);
      expect(controller.matchById(m.id)!.isPaused, isTrue);

      expect(await controller.resumeMatch(m.id), isTrue);
      expect(controller.matchById(m.id)!.isPaused, isFalse);

      await submit(m);
      await store.signIn(member.id);
      expect(await controller.raiseDispute(m.id, 'bad'), isNull);
      expect(controller.lastError, isNotNull);
      final raised = await controller.raiseDispute(m.id, 'The score is wrong.');
      expect(raised, isNotNull);
      expect(controller.disputesOf(m.id), hasLength(1));
    });
  });

  // ── Supabase adapter ──────────────────────────────────────────────────

  group('padel backend supabase adapter', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    late _PadelBackend backend;
    late LocalStorage storage;
    late SupabaseMatchRepository repo;
    late MatchController controller;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = await LocalStorage.open();
      await storage.writeMatchOutbox(const []);
      backend = _PadelBackend();
      await backend.signIn();
      repo = SupabaseMatchRepository(client: backend.client, outbox: storage);
      controller = MatchController(repo);
    });

    tearDown(() {
      controller.dispose();
      repo.dispose();
      backend.dispose();
    });

    test('the aggregate select reads the dispute rows', () async {
      await repo.reload();
      final select = backend.calls
          .firstWhere((r) => r.url.path == '/rest/v1/matches')
          .url
          .queryParameters['select'];
      // `*` carries the pause columns, the embed carries the disputes.
      expect(select, startsWith('*'));
      expect(select, contains('match_disputes'));
    });

    test('pause_match posts the named arguments the RPC declares', () async {
      await repo.reload();
      await repo.pauseMatch(matchId, reason: '  Rain delay  ');

      final body = backend.bodyFor('pause_match');
      expect(body.keys, ['p_match_id', 'p_reason']);
      expect(body['p_match_id'], matchId);
      expect(body['p_reason'], 'Rain delay');
      expect(backend.pauseReason, 'Rain delay');
    });

    test('an empty reason is sent as null, not as an empty string', () async {
      await repo.reload();
      await repo.pauseMatch(matchId, reason: '   ');
      expect(backend.bodyFor('pause_match')['p_reason'], isNull);

      await repo.pauseMatch(matchId);
      expect(backend.bodyFor('pause_match')['p_reason'], isNull);
    });

    test('the paused columns are read back into the match', () async {
      await repo.reload();
      await repo.pauseMatch(matchId, reason: 'Lights failed');

      final match = repo.matchById(matchId)!;
      expect(match.isPaused, isTrue);
      expect(match.pauseReason, 'Lights failed');
      expect(match.pausedBy, owner);
      expect(match.pausedAt, isNotNull);
      expect(match.status, FixtureStatus.live);
    });

    test('resume_match posts only the match id and clears the pause', () async {
      await repo.reload();
      await repo.pauseMatch(matchId, reason: 'Lights failed');
      await repo.resumeMatch(matchId);

      expect(backend.bodyFor('resume_match').keys, ['p_match_id']);
      final match = repo.matchById(matchId)!;
      expect(match.isPaused, isFalse);
      expect(match.pauseReason, isNull);
      expect(match.pausedBy, isNull);
    });

    test('a point during a pause keeps the servers refusal sentence', () async {
      await repo.reload();
      backend.refusal = ('match_paused', '22023');

      expect(
        await controller.recordEvent(matchId, kind: 'point', side: 0),
        isNull,
      );
      expect(
        controller.lastError,
        'Scoring is paused. Resume the match before recording another point.',
      );
      // A refusal is not a dropped connection: nothing waits in the outbox.
      expect(storage.readMatchOutbox(), isEmpty);
      expect(controller.sync, MatchSyncState.failed);
    });

    test(
      'raise_match_dispute returns the row and refreshes the list',
      () async {
        await repo.reload();
        final dispute = await repo.raiseMatchDispute(
          matchId,
          '  The third game went to the wrong side.  ',
        );

        final body = backend.bodyFor('raise_match_dispute');
        expect(body.keys, ['p_match_id', 'p_reason']);
        expect(body['p_reason'], 'The third game went to the wrong side.');
        expect(dispute.reason, 'The third game went to the wrong side.');
        expect(dispute.status, MatchDisputeStatus.open);
        expect(dispute.raisedById, owner);
        expect(repo.disputesOf(matchId), hasLength(1));
        expect(repo.matchById(matchId)!.disputes.single.id, dispute.id);
      },
    );

    test('resolve_match_dispute sends the SQL status key', () async {
      await repo.reload();
      final dispute = await repo.raiseMatchDispute(
        matchId,
        'The third game went to the wrong side.',
      );
      await repo.resolveMatchDispute(
        matchId,
        dispute.id,
        status: MatchDisputeStatus.underReview,
        resolution: '   ',
      );

      final body = backend.bodyFor('resolve_match_dispute');
      expect(body.keys, ['p_dispute_id', 'p_resolution', 'p_status']);
      expect(body['p_dispute_id'], dispute.id);
      expect(body['p_status'], 'under_review');
      expect(body['p_resolution'], isNull);
      expect(repo.disputesOf(matchId).single.status.isOpen, isTrue);

      await repo.resolveMatchDispute(
        matchId,
        dispute.id,
        status: MatchDisputeStatus.resolved,
        resolution: '  Recounted from the log.  ',
      );
      expect(backend.bodyFor('resolve_match_dispute')['p_status'], 'resolved');
      expect(
        backend.bodyFor('resolve_match_dispute')['p_resolution'],
        'Recounted from the log.',
      );
      final closed = repo.disputesOf(matchId).single;
      expect(closed.status, MatchDisputeStatus.resolved);
      expect(closed.resolvedById, owner);
      expect(closed.resolvedAt, isNotNull);
    });

    test('a refusal is a sentence, never an identifier', () async {
      await repo.reload();
      final refusals = <(String, String, String)>[
        (
          'invalid_pause_reason',
          '22023',
          'Give the reason in 3 to 200 characters, or leave it out.',
        ),
        (
          'not_match_scorer',
          '42501',
          'Only the organizer or the assigned official scorer can do that.',
        ),
        (
          'match_not_found',
          'P0002',
          'That match could not be found. Pull to refresh.',
        ),
      ];
      for (final (id, code, sentence) in refusals) {
        backend.refusal = (id, code);
        expect(await controller.pauseMatch(matchId, reason: 'Rain'), isFalse);
        expect(controller.lastError, sentence, reason: id);
      }
    });

    test(
      'every dispute identifier the server raises has its own sentence',
      () async {
        await repo.reload();
        const generic =
            'The server refused that change. Pull to refresh and try again.';
        final refusals = <(String, String)>[
          ('no_result_to_dispute', '22023'),
          ('invalid_dispute_reason', '22023'),
          ('invalid_dispute_resolution', '22023'),
          ('invalid_dispute_status', '22023'),
          ('dispute_already_open', '23505'),
          ('dispute_already_closed', '22023'),
          ('dispute_not_found', 'P0002'),
          ('not_match_stakeholder', '42501'),
          ('not_match_organizer', '42501'),
          ('forbidden', '42501'),
        ];
        for (final (id, code) in refusals) {
          backend.refusal = (id, code);
          expect(
            await controller.raiseDispute(matchId, 'The score is wrong.'),
            isNull,
          );
          expect(controller.lastError, isNot(generic), reason: id);
        }
        // P0002 for a dispute must not claim the match itself is gone.
        backend.refusal = ('dispute_not_found', 'P0002');
        await controller.raiseDispute(matchId, 'The score is wrong.');
        expect(controller.lastError, contains('dispute'));
        // An identifier the app has never seen still says something usable.
        backend.refusal = ('brand_new_refusal', '22023');
        await controller.raiseDispute(matchId, 'The score is wrong.');
        expect(controller.lastError, generic);
      },
    );

    test(
      'the controller reports a pause and a resume without throwing',
      () async {
        await controller.pauseMatch(matchId, reason: 'Rain delay');
        expect(controller.lastError, isNull);
        expect(controller.matchById(matchId)!.isPaused, isTrue);

        backend.refusal = ('invalid_match_transition', '22023');
        expect(await controller.resumeMatch(matchId), isFalse);
        expect(
          controller.lastError,
          'That match can no longer change that way.',
        );
        expect(controller.matchById(matchId)!.isPaused, isTrue);
      },
    );
  });
}
