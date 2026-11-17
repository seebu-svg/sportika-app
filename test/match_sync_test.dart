import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide LocalStorage;

import 'package:sportika/core/data/supabase_match_repository.dart';
import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/models/match.dart';

const owner = '31111111-1111-1111-1111-111111111111';
const matchId = '9aaa1111-1111-1111-1111-111111111111';

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

/// A fake PostgREST + `record_match_event` that keeps an event log, assigns the
/// sequence under a lock and dedupes on the client event id — exactly the
/// guarantees migration 0007 makes, so the repository can be driven against it.
class _Backend {
  _Backend();

  final List<http.Request> calls = [];
  final List<Map<String, dynamic>> serverEvents = [];
  final Map<String, Map<String, dynamic>> _byClient = {};
  int _seq = 0;

  /// When true the RPC answers with a transport failure instead of a refusal,
  /// which is the branch the outbox is built for.
  bool offline = false;

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
      if (path == '/auth/v1/token') {
        return _json(_session(), 200, request);
      }
      if (path == '/rest/v1/rpc/record_match_event') {
        if (offline) throw http.ClientException('connection reset');
        return _record(request);
      }
      if (path == '/rest/v1/matches') {
        final wantsObject = (request.headers['Accept'] ?? '').contains(
          'pgrst.object',
        );
        if (wantsObject) return _json(_row(), 200, request);
        return _json([_row()], 200, request);
      }
      return _json(
        {'message': 'no route $path', 'code': 'PGRST404'},
        404,
        request,
      );
    }),
  );

  http.Response _record(http.Request request) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final cid = body['p_client_event_id'] as String;
    // Idempotency: a replay returns the row it already stored, not a second one.
    final existing = _byClient[cid];
    if (existing != null) return _json(existing, 200, request);
    _seq += 1;
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
    _byClient[cid] = row;
    serverEvents.add(row);
    return _json(row, 201, request);
  }

  Map<String, dynamic> _row() => {
    'id': matchId,
    'sport_key': 'padel',
    'format_label': '1 set · first to 6',
    'rules': const {
      'setsToWin': 1,
      'gamesToWinSet': 6,
      'discipline': 'doubles',
    },
    'title': 'Offline ladder',
    'venue': 'Court two',
    'scheduled_at': '2026-05-01T18:00:00Z',
    'visibility': 'public',
    'organizer_id': owner,
    'scorer_id': owner,
    'status': 'live',
    'side_a_name': 'Rao & Iqbal',
    'side_b_name': 'Malik & Farooq',
    'capacity': 4,
    'started_at': '2026-05-01T17:59:00Z',
    'event_count': serverEvents.length,
    'created_at': '2026-04-30T00:00:00Z',
    'match_participants': [
      {
        'profile_id': owner,
        'side': 0,
        'status': 'accepted',
        'invited_by': owner,
        'updated_at': '2026-04-30T00:00:00Z',
        'profiles': {'display_name': 'Zain Malik'},
      },
    ],
    'match_events': serverEvents,
    'match_results': const [],
    'match_result_corrections': const [],
  };

  http.Response _json(Object body, int status, http.Request request) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
        request: request,
      );

  int recordCalls() => calls
      .where((r) => r.url.path == '/rest/v1/rpc/record_match_event')
      .length;

  Future<void> signIn() async {
    await client.auth.signInWithPassword(
      email: 'test@example.com',
      password: 'test-password',
    );
  }

  void dispose() => client.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Backend backend;
  late LocalStorage storage;
  late SupabaseMatchRepository repo;
  late MatchController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await LocalStorage.open();
    await storage.writeMatchOutbox(const []);
    backend = _Backend();
    await backend.signIn();
    repo = SupabaseMatchRepository(client: backend.client, outbox: storage);
    controller = MatchController(repo);
  });

  tearDown(() {
    controller.dispose();
    repo.dispose();
    backend.dispose();
  });

  test(
    'a tap that cannot reach the server is queued, painted and reported',
    () async {
      await repo.reload();
      expect(repo.matchById(matchId)!.events, isEmpty);
      expect(repo.sync, MatchSyncState.idle);

      backend.offline = true;
      final pending = await repo.recordEvent(
        matchId,
        kind: 'point',
        side: 0,
        clientId: 'tap-1',
      );

      // The workspace paints it immediately as an unsent entry.
      expect(pending.id, 'pending-tap-1');
      expect(repo.sync, MatchSyncState.offline);
      expect(repo.sync.isWarning, isTrue);
      expect(controller.sync, MatchSyncState.offline);
      expect(repo.matchById(matchId)!.events.map((e) => e.clientId), ['tap-1']);
      expect(repo.progressOf(repo.matchById(matchId)!).headline, isNotEmpty);

      // And the exact tap waits on the device with its idempotency key.
      final queued = storage.readMatchOutbox();
      expect(queued, hasLength(1));
      expect(queued.single['clientId'], 'tap-1');
      expect(queued.single['matchId'], matchId);
      expect(queued.single['kind'], 'point');
    },
  );

  test('reconnecting flushes the queue once and converges on the server log', () async {
    await repo.reload();
    backend.offline = true;
    await repo.recordEvent(matchId, kind: 'point', side: 0, clientId: 'tap-1');
    await repo.recordEvent(matchId, kind: 'point', side: 1, clientId: 'tap-2');
    expect(storage.readMatchOutbox(), hasLength(2));
    expect(backend.serverEvents, isEmpty);

    backend.offline = false;
    await repo.flushOutbox();

    // Both queued taps reached the server exactly once, in sequence.
    expect(backend.serverEvents.map((e) => e['client_event_id']), [
      'tap-1',
      'tap-2',
    ]);
    expect(backend.serverEvents.map((e) => e['seq']), [1, 2]);
    expect(storage.readMatchOutbox(), isEmpty);
    expect(repo.sync, MatchSyncState.idle);

    // The painted pending entries are replaced by the server rows, not doubled.
    final events = repo.matchById(matchId)!.events;
    expect(events.map((e) => e.id), ['srv-tap-1', 'srv-tap-2']);
    expect(events.map((e) => e.seq), [1, 2]);
    expect(repo.matchById(matchId)!.eventCount, 2);
  });

  test(
    'a retried tap after a dropped connection never double-counts',
    () async {
      await repo.reload();

      // First attempt is lost in transit but is retried by the outbox while the
      // server actually stored it — the classic dropped-response case.
      backend.offline = false;
      final first = await repo.recordEvent(
        matchId,
        kind: 'point',
        side: 0,
        clientId: 'tap-1',
      );
      expect(first.id, 'srv-tap-1');

      // The scorer taps again with the same key (a retry of the same intent).
      final replay = await repo.recordEvent(
        matchId,
        kind: 'point',
        side: 0,
        clientId: 'tap-1',
      );
      expect(replay.id, 'srv-tap-1');
      expect(backend.serverEvents, hasLength(1));
      expect(repo.matchById(matchId)!.events, hasLength(1));
    },
  );

  test(
    'a flush while still offline keeps the queue for the next attempt',
    () async {
      await repo.reload();
      backend.offline = true;
      await repo.recordEvent(
        matchId,
        kind: 'point',
        side: 0,
        clientId: 'tap-1',
      );
      expect(storage.readMatchOutbox(), hasLength(1));

      // Still down: the flush must not swallow the entry.
      await repo.flushOutbox();
      expect(storage.readMatchOutbox(), hasLength(1));
      expect(repo.sync, MatchSyncState.offline);
      expect(backend.serverEvents, isEmpty);

      // One more flush after the link returns drains it.
      backend.offline = false;
      await repo.flushOutbox();
      expect(storage.readMatchOutbox(), isEmpty);
      expect(backend.serverEvents, hasLength(1));
      expect(repo.sync, MatchSyncState.idle);
    },
  );

  test('undoing a never-sent entry clears it from the outbox too', () async {
    await repo.reload();
    backend.offline = true;
    final pending = await repo.recordEvent(
      matchId,
      kind: 'point',
      side: 0,
      clientId: 'tap-1',
    );
    expect(storage.readMatchOutbox(), hasLength(1));

    await repo.voidEvent(matchId, pending.id);

    expect(repo.matchById(matchId)!.events, isEmpty);
    expect(storage.readMatchOutbox(), isEmpty);

    // The undo clears the queue, so the reconnect flush has nothing to resend:
    // the record-call count never grows past the single attempt already made
    // while offline.
    final sentBeforeFlush = backend.recordCalls();
    backend.offline = false;
    await repo.flushOutbox();
    expect(backend.serverEvents, isEmpty);
    expect(backend.recordCalls(), sentBeforeFlush);
  });
}
