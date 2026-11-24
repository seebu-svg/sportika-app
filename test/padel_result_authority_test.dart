import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide LocalStorage;

import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/core/data/supabase_match_repository.dart';
import 'package:sportika/features/personal_games/scoring/padel/padel.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';

/// Phase 2, task 2: the official padel result is written by PostgreSQL.
///
/// Two halves of one seam:
///
///  * the Supabase adapter must send a padel result through
///    `complete_padel_match(uuid)`, the door that takes no score at all, and it
///    must tell a double tap apart from a refusal and from an answer that never
///    arrived;
///  * the device store must keep the same authority in demo mode, re-deriving
///    both sides' set lines from the points it holds instead of painting the
///    numbers the caller sent.
///
/// What the SQL itself does - deriving the two reading orders, refusing forged
/// totals, rewriting forged set lines, agreeing between the two doors - is
/// proved by supabase/tests/padel_result_authority_test.sql, so nothing here
/// re-asserts a number the database already owns.

const scorer = '31111111-1111-1111-1111-111111111111';
const matchId = '9aaa1111-1111-1111-1111-111111111111';

/// The server's own fold of the log this fake holds: three sets, one each to
/// side A and side B before the decider, so the two sides genuinely differ.
const derivedScores = ['6-0, 0-6, 7-6', '0-6, 6-0, 6-7'];
const derivedValues = [2, 1];
const derivedWinner = 0;

/// A payload that flatters side A in both the set lines and the totals. It is
/// what a tampered build could send, and what must never reach the record.
const forgedScores = ['6-0, 6-0, 10-7', '0-6, 0-6, 7-10'];
const forgedValues = [3, 0];

/// A fake PostgREST that answers the two result doors the way migrations 0013
/// and 0020 do: `complete_padel_match` takes a match id alone and writes the
/// fold's own strings, the generic door keeps storing what the app folds for
/// every sport except padel, and both enforce the lifecycle rule that only a
/// live match may be submitted - which is what makes a replay refuse with 22023.
class _AuthorityBackend {
  _AuthorityBackend({this.sportKey = 'padel'});

  final String sportKey;

  final List<http.Request> calls = [];

  /// The last body sent to each RPC, so a test can read the wire format.
  final Map<String, Map<String, dynamic>> bodies = {};

  /// The `match_results` row on the record, or null while nothing was written.
  Map<String, dynamic>? stored;

  /// Set to make the next RPC refuse with (identifier, SQLSTATE), the way
  /// PostgREST passes a PL/pgSQL `raise exception` through.
  (String, String)? refusal;

  /// True makes the next completion write the row and then lose the answer,
  /// which is what a connection dropped mid-submission looks like to the app.
  bool dropAnswer = false;

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

  Future<void> signIn() => client.auth.signInWithPassword(
    email: 'test@example.com',
    password: 'test-password',
  );

  void dispose() => client.dispose();

  http.Response _rpc(String name, http.Request request) {
    bodies[name] = jsonDecode(request.body) as Map<String, dynamic>;
    final injected = refusal;
    if (injected != null) {
      refusal = null;
      return _error(injected.$1, injected.$2, request);
    }
    switch (name) {
      case 'complete_padel_match':
        // The RPC's own guard: `if v_match.status <> 'live'`. A scorer who taps
        // twice, or retries a completion whose answer was lost, is refused here
        // rather than served a second row.
        if (stored != null) {
          return _error('invalid_match_transition', '22023', request);
        }
        stored = _resultRow(derivedScores, derivedValues, derivedWinner);
        if (dropAnswer) {
          dropAnswer = false;
          throw http.ClientException('connection reset by peer');
        }
        return _json(stored!, 200, request);
      case 'submit_match_result':
        if (stored != null) {
          return _error('invalid_match_transition', '22023', request);
        }
        final sent = bodies[name]!;
        final padel = sportKey == 'padel';
        // Migration 0020 overwrites the caller's array with the fold's for
        // padel and stores it as sent for the sports the app still folds.
        stored = _resultRow(
          padel
              ? derivedScores
              : (sent['p_side_scores'] as List<dynamic>)
                    .map((e) => '$e')
                    .toList(),
          padel
              ? derivedValues
              : (sent['p_side_values'] as List<dynamic>)
                    .map((e) => (e as num).toInt())
                    .toList(),
          (sent['p_winner_index'] as num?)?.toInt() ?? -1,
        );
        return _json(stored!, 200, request);
    }
    return _json({'message': 'unknown rpc $name'}, 500, request);
  }

  Map<String, dynamic> _resultRow(
    List<String> scores,
    List<int> values,
    int winner,
  ) => {
    'id': 'res-1',
    'match_id': matchId,
    'side_scores': scores,
    'side_values': values,
    'winner_index': winner,
    'headline': 'Rao won 2-1',
    'detail': 'Set 1: 6-0 · Set 2: 0-6 · Set 3: 7-6',
    'published_at': '2026-05-01T19:00:00Z',
    'published_by': scorer,
    'walkover': false,
  };

  Map<String, dynamic> _row() => {
    'id': matchId,
    'sport_key': sportKey,
    'format_label': 'Best of 3 sets',
    'rules': const {'setsToWin': 2, 'gamesToWinSet': 6},
    'title': 'Court three showdown',
    'venue': 'Court three',
    'scheduled_at': '2026-05-01T18:00:00Z',
    'visibility': 'public',
    'organizer_id': scorer,
    'scorer_id': scorer,
    'status': stored == null ? 'live' : 'submitted',
    'side_a_name': 'Rao',
    'side_b_name': 'Malik',
    'capacity': 2,
    'discipline': 'singles',
    'started_at': '2026-05-01T17:59:00Z',
    'submitted_at': stored == null ? null : '2026-05-01T19:00:00Z',
    'completed_at': null,
    'event_count': 0,
    'created_at': '2026-04-30T00:00:00Z',
    'match_participants': const [
      {
        'profile_id': scorer,
        'side': 0,
        'status': 'accepted',
        'invited_by': scorer,
        'updated_at': '2026-04-30T00:00:00Z',
        'profiles': {'display_name': 'Rao'},
      },
    ],
    'match_events': const [],
    'match_results': stored == null ? const [] : [stored],
    'match_result_corrections': const [],
    'match_disputes': const [],
  };

  http.Response _error(String identifier, String code, http.Request request) =>
      _json(
        {'message': identifier, 'code': code, 'hint': null, 'details': null},
        400,
        request,
      );

  http.Response _json(Object body, int status, http.Request request) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
        request: request,
      );

  int rpcCalls(String rpc) =>
      calls.where((r) => r.url.path == '/rest/v1/rpc/$rpc').length;
}

Map<String, dynamic> _session() => {
  'access_token': 'test-access-token',
  'refresh_token': 'test-refresh-token',
  'token_type': 'bearer',
  'expires_in': 3600,
  'user': {
    'id': scorer,
    'aud': 'authenticated',
    'email': 'test@example.com',
    'created_at': '2026-01-01T00:00:00Z',
    'app_metadata': {},
    'user_metadata': {},
  },
};

void main() {
  // ── The Supabase door ────────────────────────────────────────────────────

  group('padel result authority: completion RPC', () {
    late _AuthorityBackend backend;
    late SupabaseMatchRepository repo;

    Future<void> connect({_AuthorityBackend? via}) async {
      backend = via ?? _AuthorityBackend();
      repo = SupabaseMatchRepository(client: backend.client);
      await backend.signIn();
    }

    tearDown(() {
      repo.dispose();
      backend.dispose();
    });

    /// The submission the review sheet makes: the device's own reading of the
    /// match, which for padel has to be ignored on its way to the record.
    Future<void> submit() => repo.submitResult(
      matchId,
      headline: 'Rao won 3-0',
      detail: 'Best of 3 sets',
      sideScores: forgedScores,
      sideValues: forgedValues,
      winnerIndex: 0,
    );

    test('padel is submitted by the door that takes no score', () async {
      await connect();
      await repo.reload();

      await submit();

      expect(backend.rpcCalls('complete_padel_match'), 1);
      expect(backend.rpcCalls('submit_match_result'), 0);
      // Only the match id goes over the wire: there is nothing to tamper with.
      expect(backend.bodies['complete_padel_match'], {'p_match_id': matchId});
      expect(backend.stored!['side_scores'], derivedScores);
    });

    test(
      'the record, and every surface reading it, is the server\'s',
      () async {
        await connect();
        await repo.reload();

        await submit();

        final settled = repo.matchById(matchId)!;
        expect(settled.status, FixtureStatus.submitted);
        expect(settled.result!.sideScores, derivedScores);
        expect(settled.result!.sideValues, derivedValues);
        expect(settled.result!.winnerIndex, derivedWinner);
        // Neither forged string survived anywhere in the loaded aggregate.
        expect(settled.result!.sideScores, isNot(contains(forgedScores.first)));
        expect(repo.sync, MatchSyncState.idle);
      },
    );

    test('the sport is resolved even before the match is loaded', () async {
      await connect();

      await submit();

      // No snapshot was read, so the adapter had to ask which sport this is,
      // one column at a time, and still chose the padel door.
      final probe = backend.calls.firstWhere(
        (r) => r.url.path == '/rest/v1/matches',
      );
      expect(probe.url.queryParameters['select'], 'sport_key');
      expect(backend.rpcCalls('complete_padel_match'), 1);
    });

    test('a replayed completion is the result the scorer asked for', () async {
      await connect();
      await repo.reload();
      await submit();

      // Double tap, or the retry of a submission whose answer was lost: the
      // RPC refuses on the lifecycle rule, and the read back says the result
      // is already on the record, so nothing is reported as a failure.
      await expectLater(submit(), completes);

      expect(backend.rpcCalls('complete_padel_match'), 2);
      expect(repo.matchById(matchId)!.result!.sideScores, derivedScores);
      expect(repo.sync, MatchSyncState.idle);
    });

    test('a lifecycle refusal that wrote nothing is still a refusal', () async {
      await connect();
      await repo.reload();
      backend.refusal = ('invalid_match_transition', '22023');

      await expectLater(
        submit(),
        throwsA(
          isA<MatchRepositoryException>().having(
            (e) => e.code,
            'code',
            '22023',
          ),
        ),
      );

      expect(backend.stored, isNull);
      expect(repo.matchById(matchId)!.hasResult, isFalse);
      expect(repo.sync, MatchSyncState.failed);
    });

    test(
      'a refusal that is not a lifecycle clash is reported as it is',
      () async {
        await connect();
        await repo.reload();
        backend.refusal = ('not_match_scorer', '42501');

        await expectLater(
          submit(),
          throwsA(
            isA<MatchRepositoryException>().having(
              (e) => e.message,
              'message',
              contains('official scorer'),
            ),
          ),
        );

        // The retry read only belongs to 22023; a permission refusal is final.
        expect(backend.rpcCalls('complete_padel_match'), 1);
      },
    );

    test(
      'a dropped answer is retried, and the retry succeeds quietly',
      () async {
        await connect();
        await repo.reload();
        backend.dropAnswer = true;

        await expectLater(
          submit(),
          throwsA(
            isA<MatchRepositoryException>().having(
              (e) => e.message,
              'message',
              'The result could not be submitted.',
            ),
          ),
        );
        // The completion did land; the device simply was not told.
        expect(backend.stored!['side_scores'], derivedScores);

        await expectLater(submit(), completes);
        expect(repo.matchById(matchId)!.result!.sideScores, derivedScores);
        expect(repo.sync, MatchSyncState.idle);
      },
    );

    test(
      'the sports without a server fold still submit their own result',
      () async {
        for (final sport in [Sport.badminton, Sport.cricket, Sport.futsal]) {
          await connect(via: _AuthorityBackend(sportKey: sport.key));
          await repo.reload();

          await repo.submitResult(
            matchId,
            headline: 'Rao won 2-1',
            detail: sport.label,
            sideScores: const ['21-19, 18-21, 21-15', '19-21, 21-18, 15-21'],
            sideValues: const [2, 1],
            winnerIndex: 0,
          );

          expect(
            backend.rpcCalls('complete_padel_match'),
            0,
            reason: sport.key,
          );
          expect(backend.rpcCalls('submit_match_result'), 1, reason: sport.key);
          expect(
            backend.bodies['submit_match_result']!['p_side_scores'],
            const ['21-19, 18-21, 21-15', '19-21, 21-18, 15-21'],
            reason: sport.key,
          );
        }
      },
    );
  });

  // ── The device mirror ────────────────────────────────────────────────────

  group('padel result authority: device store', () {
    late LocalSportikaRepository store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'sportika.onboarding_seen.v1': true,
      });
      store = LocalSportikaRepository(await LocalStorage.open());
      await store.load();
      await store.signIn(store.accounts[0].id);
    });

    tearDown(() => store.dispose());

    Future<SportMatch> liveMatch(String format) async {
      final created = await store.createMatch(
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
      await store.startMatch(created.id);
      return store.matchById(created.id)!;
    }

    /// [games] games won by [side], four points each, which is how the engine
    /// folds a game it never had to break. The client ids run on a single
    /// counter, because the device store dedupes a repeated id exactly as the
    /// server does - reusing one would silently drop the next set's points.
    var tap = 0;
    Future<void> games(String matchId, int side, int count) async {
      for (var i = 0; i < count * 4; i++) {
        await store.recordEvent(
          matchId,
          kind: PadelEngine.kPoint,
          side: side,
          clientId: 'tap-${tap++}',
        );
      }
    }

    Future<void> submit(String matchId) => store.submitResult(
      matchId,
      headline: 'Rao won 3-0',
      detail: 'Best of 3 sets',
      sideScores: forgedScores,
      sideValues: forgedValues,
      winnerIndex: 1,
    );

    test(
      'a padel result is re-derived, not accepted from the payload',
      () async {
        final m = await liveMatch('1 set · first to 6');
        await games(m.id, 1, 3); // Malik takes the first three games.
        await games(m.id, 0, 6); // Rao closes it out 6-3.

        await submit(m.id);

        final result = store.matchById(m.id)!.result!;
        expect(result.sideScores, ['6-3', '3-6']);
        expect(result.sideValues, [1, 0]);
        // The payload claimed a side B win in straight sets; the log does not.
        expect(result.winnerIndex, 0);
      },
    );

    test('each side reads its own order across three sets', () async {
      final m = await liveMatch('Best of 3 sets');
      await games(m.id, 1, 3); // Set 1 to Rao, 6-3.
      await games(m.id, 0, 6);
      await games(m.id, 0, 6); // Set 2 to Rao, 6-0, so the match ends 2-0.

      await submit(m.id);

      final result = store.matchById(m.id)!.result!;
      expect(result.sideScores, ['6-3, 6-0', '3-6, 0-6']);
      expect(result.sideScores.first, isNot(result.sideScores.last));
    });

    test('a log the engine has not finished cannot be submitted', () async {
      final m = await liveMatch('Best of 3 sets');
      await games(m.id, 0, 6); // One set won, two still to play.

      await expectLater(
        submit(m.id),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('not finished'),
          ),
        ),
      );

      expect(store.matchById(m.id)!.hasResult, isFalse);
      expect(store.matchById(m.id)!.status, FixtureStatus.live);
    });

    test('a second submission changes nothing', () async {
      final m = await liveMatch('1 set · first to 6');
      await games(m.id, 0, 6);
      await games(m.id, 1, 3);

      await submit(m.id);
      final first = store.matchById(m.id)!.result!;
      await expectLater(submit(m.id), completes);

      final again = store.matchById(m.id)!.result!;
      expect(again.sideScores, first.sideScores);
      expect(again.publishedAt, first.publishedAt);
    });

    test(
      'the engine and the stored result still agree, side by side',
      () async {
        final m = await liveMatch('Best of 3 sets');
        await games(m.id, 1, 6); // Set 1 to Malik, 6-0.
        await games(m.id, 0, 2); // Rao takes two games of set 2, ...
        await games(m.id, 1, 6); // ... and Malik still wins it 6-2, match 2-0.

        final live = store.matchById(m.id)!;
        final progress = store.progressOf(live);
        expect(progress.isComplete, isTrue);
        expect(progress.scoreDisplay, ['0-6, 2-6', '6-0, 6-2']);

        await store.submitResult(
          m.id,
          headline: 'Malik won 2-0',
          detail: 'Best of 3 sets',
          sideScores: const ['', ''],
          sideValues: const [0, 0],
          winnerIndex: -1,
        );

        final result = store.matchById(m.id)!.result!;
        expect(result.sideScores, progress.scoreDisplay);
        expect(result.sideValues, progress.scoreValues);
        expect(result.winnerIndex, progress.winnerIndex);
      },
    );
  });
}
