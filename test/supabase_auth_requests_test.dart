import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show Request, Response;
import 'package:http/testing.dart';
import 'package:sportika/app/env.dart';
import 'package:sportika/features/auth/services/supabase_authentication_service.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The wire contract between [SupabaseAuthenticationService] and GoTrue.
///
/// These tests do not talk to a project and do not claim to prove that a
/// deployment is configured correctly. They pin the five request shapes that
/// silently break a production flow when the adapter is rewritten: a sign-in
/// OTP that creates accounts, a verify call with the wrong token type, or a
/// password change that skips reauthentication are all invisible in a unit
/// test of the UI and all fatal against a live server.
void main() {
  late _Harness harness;

  setUp(() => harness = _Harness());
  tearDown(() => harness.dispose());

  test('signup posts the address, the password and the display name', () async {
    await harness.service.register(
      name: 'Amina Yusuf',
      email: 'player@example.com',
      password: 'Sportika9!',
      intent: AccountIntent.player,
      acceptedTerms: true,
    );

    final call = harness.single('/auth/v1/signup');
    expect(call.method, 'POST');
    expect(call.body['email'], 'player@example.com');
    expect(call.body['password'], 'Sportika9!');
    expect(call.body['data'], {'display_name': 'Amina Yusuf'});
  });

  test(
    'a sign-in code never creates an account and returns to the app',
    () async {
      await harness.service.requestSignInCode(email: 'player@example.com');

      final call = harness.single('/auth/v1/otp');
      expect(call.method, 'POST');
      expect(call.body['email'], 'player@example.com');
      // The one flag that turns the sign-in screen into a signup route.
      expect(call.body['create_user'], false);
      expect(call.url.queryParameters['redirect_to'], AppEnv.authCallback);
    },
  );

  test('a typed sign-in code is verified as an email token', () async {
    await harness.service.requestSignInCode(email: 'player@example.com');
    final session = await harness.service.verifySignInCode(
      challengeId: 'player@example.com',
      code: '246810',
    );

    final call = harness.single('/auth/v1/verify');
    expect(call.body['type'], 'email');
    expect(call.body['token'], '246810');
    expect(call.body['email'], 'player@example.com');
    expect(session.accountId, _accountId);
  });

  test(
    'an address that never confirmed signup retries with the signup type',
    () async {
      harness.rejectVerifyTypes = {'email'};
      await harness.service.requestSignInCode(email: 'player@example.com');
      final session = await harness.service.verifySignInCode(
        challengeId: 'player@example.com',
        code: '246810',
      );

      final types = harness
          .paths('/auth/v1/verify')
          .map((call) => call.body['type']);
      expect(types, ['email', 'signup']);
      expect(session.accountId, _accountId);
    },
  );

  test('a signup code is verified as a signup token', () async {
    await harness.service.verifyEmail(
      challengeId: 'player@example.com',
      code: '123456',
    );

    final call = harness.single('/auth/v1/verify');
    expect(call.body['type'], 'signup');
  });

  test(
    'changing the password proves the current one before writing the new one',
    () async {
      await harness.signIn();
      harness.calls.clear();

      await harness.service.changePassword(
        currentPassword: 'Sportika9!',
        password: 'NewSportika9!',
      );

      expect(harness.calls.map((call) => '${call.method} ${call.url.path}'), [
        'POST /auth/v1/token',
        'PUT /auth/v1/user',
      ]);
      expect(harness.calls.first.body['password'], 'Sportika9!');
      expect(harness.calls.last.body, {'password': 'NewSportika9!'});
    },
  );

  test(
    'changing the email reauthenticates and redirects the confirmation home',
    () async {
      await harness.signIn();
      harness.calls.clear();

      await harness.service.changeEmail(
        currentPassword: 'Sportika9!',
        email: 'new@example.com',
      );

      expect(harness.calls.first.url.path, '/auth/v1/token');
      final call = harness.single('/auth/v1/user');
      expect(call.method, 'PUT');
      expect(call.body['email'], 'new@example.com');
      expect(call.body.containsKey('password'), isFalse);
      expect(call.url.queryParameters['redirect_to'], AppEnv.authCallback);
    },
  );

  test('a recovery code is verified as a recovery token', () async {
    await harness.service.resetPassword(
      challengeId: 'player@example.com',
      code: '654321',
      password: 'NewSportika9!',
    );

    final call = harness.single('/auth/v1/verify');
    expect(call.body['type'], 'recovery');
    expect(harness.single('/auth/v1/user').body['password'], 'NewSportika9!');
  });

  test('signing out everywhere asks the server to revoke globally', () async {
    await harness.signIn();
    harness.calls.clear();

    await harness.service.signOutEverywhere();

    // GoTrue posts /logout for every scope; only the query says whether other
    // devices lose their tokens too.
    final logout = harness.paths('/auth/v1/logout');
    expect(logout, isNotEmpty);
    expect(logout.first.url.queryParameters['scope'], 'global');
  });
}

const String _accountId = '11111111-2222-3333-4444-555555555555';
const String _email = 'player@example.com';

/// One recorded auth request, exactly as GoTrue would have received it.
class _Call {
  _Call(this.method, this.url, this.body);

  final String method;
  final Uri url;
  final Map<String, dynamic> body;
}

/// A GoTrue client whose transport is a recording mock.
class _Harness {
  _Harness() {
    final client = SupabaseClient(
      'https://test-project.supabase.co',
      'sb_publishable_test_key',
      // No auto-refresh timer (it would outlive the test) and no PKCE verifier
      // storage, which only the deep-link exchange needs.
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
      httpClient: MockClient(_handle),
    );
    service = SupabaseAuthenticationService(client);
    _clients.add(client);
  }

  final List<_Call> calls = [];
  final List<SupabaseClient> _clients = [];
  late final SupabaseAuthenticationService service;

  /// Token types whose verify call should fail, to exercise the fallback.
  Set<String> rejectVerifyTypes = {};

  _Call single(String path) {
    final matches = paths(path);
    expect(matches, hasLength(1), reason: 'expected exactly one $path call');
    return matches.single;
  }

  List<_Call> paths(String path) =>
      calls.where((call) => call.url.path == path).toList();

  Future<void> signIn() async {
    await service.signIn(email: _email, password: 'Sportika9!');
  }

  void dispose() {
    service.dispose();
    for (final client in _clients) {
      client.dispose();
    }
  }

  Future<Response> _handle(Request request) async {
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    calls.add(_Call(request.method, request.url, body));
    return Response(
      jsonEncode(_payload(request.url.path, body)),
      _status(request.url.path, body),
      headers: {'content-type': 'application/json'},
    );
  }

  int _status(String path, Map<String, dynamic> body) {
    if (path == '/auth/v1/verify' && rejectVerifyTypes.contains(body['type'])) {
      return 400;
    }
    return 200;
  }

  Map<String, dynamic> _payload(String path, Map<String, dynamic> body) {
    switch (path) {
      case '/auth/v1/verify' when rejectVerifyTypes.contains(body['type']):
        return {
          'code': 'invalid_otp',
          'error_code': 'invalid_otp',
          'msg': 'Token has expired or is invalid',
        };
      case '/auth/v1/token':
      case '/auth/v1/verify':
        return _session(email: (body['email'] as String?) ?? _email);
      case '/auth/v1/user':
        return _user(email: (body['email'] as String?) ?? _email);
      case '/auth/v1/signup':
        // Confirmation required: the server answers with the user only.
        return _user(email: (body['email'] as String?) ?? _email);
      default:
        return {};
    }
  }

  Map<String, dynamic> _user({String email = _email}) => {
    'id': _accountId,
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': email,
    'app_metadata': {
      'provider': 'email',
      'providers': ['email'],
    },
    'user_metadata': {'display_name': 'Amina Yusuf'},
    'created_at': '2026-11-01T00:00:00.000Z',
    'confirmed_at': '2026-11-01T00:00:00.000Z',
  };

  Map<String, dynamic> _session({String email = _email}) => {
    'access_token': 'test-access-token',
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'test-refresh-token',
    'user': _user(email: email),
  };
}
