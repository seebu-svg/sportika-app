import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sportika/core/data/supabase_profile_module_repository.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/identity_document.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/profile_module.dart';
import 'package:sportika/shared/models/profile_setup.dart';

const owner = '31111111-1111-1111-1111-111111111111';
const other = '32222222-2222-2222-2222-222222222222';
const tournament = '44444444-4444-4444-4444-444444444444';
const fixture = '55555555-5555-5555-5555-555555555555';

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

/// Records every request so the test can assert the exact wire shape.
class _Backend {
  final List<http.Request> calls = <http.Request>[];
  final Map<String, http.Response Function(http.Request)> routes =
      <String, http.Response Function(http.Request)>{};

  late final SupabaseClient client = SupabaseClient(
    'https://example.supabase.co',
    'test-key',
    authOptions: const AuthClientOptions(
      autoRefreshToken: false,
      authFlowType: AuthFlowType.implicit,
    ),
    httpClient: MockClient((request) async {
      calls.add(request);
      final route = routes[_key(request)];
      if (route == null) {
        return http.Response(
          jsonEncode({
            'message': 'No route for ${request.method} ${request.url.path}',
            'code': 'PGRST000',
          }),
          404,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
      return route(request);
    }),
  );

  static String _key(http.Request request) =>
      '${request.method} ${request.url.path}';

  http.Response json(Object body, int status, http.Request request) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
        request: request,
      );

  http.Request call(String method, String path) => calls.singleWhere(
    (request) => request.method == method && request.url.path == path,
  );

  http.Request? maybeCall(String method, String path) {
    for (final request in calls) {
      if (request.method == method && request.url.path == path) return request;
    }
    return null;
  }

  Future<void> signIn() async {
    routes['POST /auth/v1/token'] = (request) => json(_session(), 200, request);
    await client.auth.signInWithPassword(
      email: 'test@example.com',
      password: 'test-password',
    );
  }

  void dispose() => client.dispose();
}

Map<String, dynamic> _profileRow() => {
  'id': owner,
  'username': 'zain',
  'display_name': '  Zain Malik  ',
  'bio': 'Weekend padel.',
  'city': 'Karachi',
  'avatar_preset': 'midnight',
  'avatar_url': null,
  'play_style': 'competitive',
  'profile_setup_complete': true,
  'profiles_private': {
    'date_of_birth': '1999-04-12',
    'gender': 'man',
    'height_cm': 182,
    'weight_kg': 74.5,
    'dominant_hand': 'right',
    'dominant_foot': null,
    'preferred_jersey': 10,
  },
  'profile_sports': [
    {'sport_key': 'padel', 'level': 'advanced', 'position': 'Left side'},
    {'sport_key': 'cricket', 'level': null, 'position': '  '},
    // A key this build does not know is skipped instead of guessed.
    {'sport_key': 'kabaddi', 'level': 'pro', 'position': null},
  ],
  'profile_identity_documents': {
    'document_type': 'cnic',
    'document_number': '1234512345671',
    'front_path': '$owner/front-1.png',
    'back_path': null,
    'submitted_at': '2026-11-01T10:00:00Z',
  },
};

void main() {
  test(
    'load maps the owned row, the sports and the optional identity',
    () async {
      final backend = _Backend();
      addTearDown(backend.dispose);
      await backend.signIn();
      backend.routes['GET /rest/v1/profiles'] = (request) =>
          backend.json([_profileRow()], 200, request);

      final repo = SupabaseProfileModuleRepository(client: backend.client);
      final snapshot = await repo.load();

      expect(snapshot.personal.displayName, 'Zain Malik');
      expect(snapshot.personal.username, 'zain');
      expect(snapshot.personal.dateOfBirth, DateTime(1999, 4, 12));
      expect(snapshot.personal.gender, ProfileGender.man);
      expect(snapshot.personal.playStyle, PlayStyle.competitive);
      expect(snapshot.personal.setupComplete, isTrue);

      // Sorted by the shared sport order, unknown keys dropped, blanks null.
      expect(snapshot.sports.map((s) => s.sport), [Sport.cricket, Sport.padel]);
      expect(snapshot.sports.first.level, isNull);
      expect(snapshot.sports.first.position, isNull);
      expect(snapshot.sports.last.level, PlayingLevel.advanced);
      expect(snapshot.sports.last.position, 'Left side');

      expect(snapshot.identity?.kind, IdentityDocumentKind.cnic);
      expect(snapshot.identity?.hasFront, isTrue);
      expect(snapshot.identity?.hasBack, isFalse);
      expect(snapshot.identity?.maskedNumber, '•••••••••5671');

      final read = backend.call('GET', '/rest/v1/profiles');
      final select = read.url.queryParameters['select']!;
      expect(
        select,
        contains(
          'profiles_private(date_of_birth,gender,height_cm,'
          'weight_kg,dominant_hand,dominant_foot,preferred_jersey)',
        ),
      );
      expect(select, contains('profile_sports(sport_key,level,position)'));
      expect(select, contains('profile_identity_documents('));
      expect(read.url.queryParameters['id'], 'eq.$owner');

      // Athlete columns fold into the private row; a null clears, not zero.
      expect(snapshot.athlete?.heightCm, 182);
      expect(snapshot.athlete?.weightKg, 74.5);
      expect(snapshot.athlete?.dominantHand, ProfileSide.right);
      expect(snapshot.athlete?.dominantFoot, isNull);
      expect(snapshot.athlete?.preferredJersey, 10);
    },
  );

  test(
    'a write sends the date as a day and the gender as its column',
    () async {
      final backend = _Backend();
      addTearDown(backend.dispose);
      await backend.signIn();
      backend.routes['POST /rest/v1/rpc/update_profile_details'] = (request) =>
          backend.json({}, 200, request);

      final repo = SupabaseProfileModuleRepository(client: backend.client);
      var notified = 0;
      repo.addListener(() => notified++);

      await repo.savePersonalInformation(
        displayName: '  Ali Raza ',
        city: ' Lahore ',
        bio: ' New to padel. ',
        dateOfBirth: DateTime(1998, 2, 3, 15, 30),
        gender: ProfileGender.nonBinary,
        playStyle: PlayStyle.social,
      );

      final call = backend.call('POST', '/rest/v1/rpc/update_profile_details');
      final body = jsonDecode(call.body) as Map<String, dynamic>;
      expect(body['p_display_name'], 'Ali Raza');
      expect(body['p_city'], 'Lahore');
      expect(body['p_bio'], 'New to padel.');
      expect(body['p_date_of_birth'], '1998-02-03');
      expect(body['p_gender'], 'non_binary');
      expect(body['p_play_style'], 'social');
      expect(notified, 1);
    },
  );

  test('athlete details send the laterality key and clear blanks', () async {
    final backend = _Backend();
    addTearDown(backend.dispose);
    await backend.signIn();
    const athleteRpc = 'POST /rest/v1/rpc/update_profile_athlete_details';
    backend.routes[athleteRpc] = (request) => backend.json({}, 200, request);

    final repo = SupabaseProfileModuleRepository(client: backend.client);
    var notified = 0;
    repo.addListener(() => notified++);

    await repo.saveAthleteDetails(
      heightCm: 180,
      weightKg: 72.5,
      dominantHand: ProfileSide.left,
      dominantFoot: null,
      preferredJersey: null,
    );

    final body = jsonDecode(
      backend.call('POST', '/rest/v1/rpc/update_profile_athlete_details').body,
    ) as Map<String, dynamic>;
    expect(body['p_height_cm'], 180);
    expect(body['p_weight_kg'], 72.5);
    expect(body['p_dominant_hand'], 'left');
    expect(body['p_dominant_foot'], isNull);
    expect(body['p_preferred_jersey'], isNull);
    expect(notified, 1);
  });

  test('the handle is normalized before it reaches the unique index', () async {
    final backend = _Backend();
    addTearDown(backend.dispose);
    await backend.signIn();
    backend.routes['POST /rest/v1/rpc/change_profile_username'] = (request) =>
        backend.json({}, 200, request);

    final repo = SupabaseProfileModuleRepository(client: backend.client);
    await repo.changeUsername('@Ali.Raza');

    final body = jsonDecode(
      backend.call('POST', '/rest/v1/rpc/change_profile_username').body,
    ) as Map<String, dynamic>;
    expect(body['p_username'], 'ali.raza');

    backend.routes['POST /rest/v1/rpc/change_profile_username'] = (request) =>
        backend.json(
          {'message': '23505: duplicate key value', 'code': '23505'},
          409,
          request,
        );
    await expectLater(
      repo.changeUsername('zain'),
      throwsA(
        isA<ProfileModuleException>()
            .having((e) => e.code, 'code', '23505')
            .having(
              (e) => e.message,
              'message',
              'That username is already taken. Try another.',
            ),
      ),
    );
  });

  test('an empty sport set never reaches the server', () async {
    final backend = _Backend();
    addTearDown(backend.dispose);
    await backend.signIn();
    backend.routes['POST /rest/v1/rpc/replace_profile_sports'] = (request) =>
        backend.json({}, 200, request);

    final repo = SupabaseProfileModuleRepository(client: backend.client);
    await expectLater(
      repo.saveSportsPreferences(const <ProfileSportPreference>[]),
      throwsA(
        isA<ProfileModuleException>().having(
          (e) => e.code,
          'code',
          'sports_required',
        ),
      ),
    );
    expect(
      backend.maybeCall('POST', '/rest/v1/rpc/replace_profile_sports'),
      isNull,
    );

    // The skipped answer keeps a sport with a null level.
    await repo.saveSportsPreferences([
      const ProfileSportPreference(Sport.cricket),
      const ProfileSportPreference(
        Sport.padel,
        level: PlayingLevel.pro,
        position: 'Right side',
      ),
    ]);
    final body = jsonDecode(
      backend.call('POST', '/rest/v1/rpc/replace_profile_sports').body,
    ) as Map<String, dynamic>;
    expect(body['p_sports'], [
      {'sport_key': 'cricket', 'level': null, 'position': null},
      {'sport_key': 'padel', 'level': 'pro', 'position': 'Right side'},
    ]);
  });

  test(
    'an assignment carries the fixture and refuses a non-organizer',
    () async {
      final backend = _Backend();
      addTearDown(backend.dispose);
      await backend.signIn();
      backend.routes['POST /rest/v1/rpc/assign_official_scorer'] = (request) =>
          backend.json(
            {
              'id': 'a-1',
              'tournament_id': tournament,
              'fixture_id': fixture,
              'scorer_profile_id': other,
              'authorized_by': owner,
              'status': 'assigned',
              'created_at': '2026-11-01T10:00:00Z',
            },
            200,
            request,
          );

      final repo = SupabaseProfileModuleRepository(client: backend.client);
      final assignment = await repo.assignScorer(
        tournamentId: tournament,
        fixtureId: fixture,
        scorerId: other,
      );
      expect(assignment.fixtureId, fixture);
      expect(assignment.scorerId, other);
      expect(assignment.authorizedBy, owner);
      expect(assignment.status, ScorerAssignmentStatus.assigned);

      final body = jsonDecode(
        backend.call('POST', '/rest/v1/rpc/assign_official_scorer').body,
      ) as Map<String, dynamic>;
      expect(body, {
        'p_tournament_id': tournament,
        'p_fixture_id': fixture,
        'p_scorer_id': other,
      });

      // The database derives the organizer from auth.uid(); a refusal is final.
      backend.routes['POST /rest/v1/rpc/assign_official_scorer'] = (request) =>
          backend.json(
            {'message': 'not_match_organizer', 'code': '42501'},
            403,
            request,
          );
      await expectLater(
        repo.assignScorer(
          tournamentId: tournament,
          fixtureId: fixture,
          scorerId: other,
        ),
        throwsA(
          isA<ProfileModuleException>().having(
            (e) => e.message,
            'message',
            'Only the organizer who owns this match can change it.',
          ),
        ),
      );
    },
  );

  test('the scorer answers only their own assignment', () async {
    final backend = _Backend();
    addTearDown(backend.dispose);
    await backend.signIn();
    backend.routes['GET /rest/v1/official_scorer_assignments'] = (request) =>
        backend.json(
          [
            {
              'id': 'a-1',
              'tournament_id': tournament,
              'fixture_id': fixture,
              'scorer_profile_id': other,
              'authorized_by': owner,
              'status': 'accepted',
              'created_at': '2026-11-01T10:00:00Z',
            },
          ],
          200,
          request,
        );
    backend.routes['POST /rest/v1/rpc/respond_to_scorer_assignment'] = (
      request,
    ) => backend.json({}, 200, request);

    final repo = SupabaseProfileModuleRepository(client: backend.client);
    final rows = await repo.loadAssignments();
    expect(rows.single.status, ScorerAssignmentStatus.accepted);
    expect(rows.single.fixtureId, fixture);

    final list = backend.call('GET', '/rest/v1/official_scorer_assignments');
    expect(
      list.url.queryParameters['or'],
      '(scorer_profile_id.eq.$owner,authorized_by.eq.$owner)',
    );

    await repo.respondToAssignment(assignmentId: 'a-1', accept: false);
    final body = jsonDecode(
      backend.call('POST', '/rest/v1/rpc/respond_to_scorer_assignment').body,
    ) as Map<String, dynamic>;
    expect(body, {'p_assignment_id': 'a-1', 'p_accept': false});
  });

  test('a validation refusal keeps the database sentence', () async {
    final backend = _Backend();
    addTearDown(backend.dispose);
    await backend.signIn();
    backend.routes['POST /rest/v1/rpc/update_profile_details'] = (request) =>
        backend.json(
          {'message': 'invalid_display_name', 'code': '22023'},
          400,
          request,
        );

    final repo = SupabaseProfileModuleRepository(client: backend.client);
    await expectLater(
      repo.savePersonalInformation(
        displayName: '',
        city: 'Karachi',
        bio: '',
        dateOfBirth: DateTime(1999, 4, 12),
        gender: null,
        playStyle: PlayStyle.weekly,
      ),
      throwsA(
        isA<ProfileModuleException>().having(
          (e) => e.message,
          'message',
          'Enter a full name between 2 and 80 characters.',
        ),
      ),
    );
  });

  test(
    'without a session every call refuses before touching the wire',
    () async {
      final backend = _Backend();
      addTearDown(backend.dispose);
      final repo = SupabaseProfileModuleRepository(client: backend.client);

      await expectLater(
        repo.load(),
        throwsA(
          isA<ProfileModuleException>().having((e) => e.code, 'code', '28000'),
        ),
      );
      await expectLater(
        repo.loadAssignments(),
        throwsA(isA<ProfileModuleException>()),
      );
      expect(backend.calls, isEmpty);
    },
  );
}
