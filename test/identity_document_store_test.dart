import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportika/core/data/identity_document_store.dart';
import 'package:sportika/core/data/supabase_identity_document_store.dart';
import 'package:sportika/shared/models/identity_document.dart';

import 'helpers/photo_fixture.dart';

const owner = '31111111-1111-1111-1111-111111111111';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'document images retain rectangular shape and are re-encoded to PNG',
    () async {
      final result = await prepareIdentityImage(await pngBytes(800, 480));
      expect(await decodedSize(result), (800, 480));
      expect(result.take(4), [137, 80, 78, 71]);
      final portrait = await prepareIdentityImage(await pngBytes(1200, 2400));
      expect(await decodedSize(portrait), (800, 1600));
      await expectLater(
        prepareIdentityImage(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
      await expectLater(
        prepareIdentityImage(Uint8List(5 * 1024 * 1024 + 1)),
        throwsFormatException,
      );
    },
  );

  for (final rejectRow in [false, true]) {
    test(
      'private upload ${rejectRow ? 'cleans up after failed row insert' : 'stores only owner paths and normalized number'}',
      () async {
        final calls = <http.Request>[];
        final client = SupabaseClient(
          'https://example.supabase.co',
          'test-key',
          authOptions: const AuthClientOptions(
            autoRefreshToken: false,
            authFlowType: AuthFlowType.implicit,
          ),
          httpClient: MockClient((request) async {
            calls.add(request);
            var status = 200;
            Object body = <String, dynamic>{};
            if (request.url.path == '/auth/v1/token') {
              body = {
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
            } else if (request.url.path ==
                '/rest/v1/profile_identity_documents') {
              status = rejectRow ? 400 : 201;
              body = rejectRow ? {'message': 'Rejected', 'code': '23514'} : [];
            } else if (request.method == 'POST') {
              body = {'Key': 'identity-documents/$owner/front.png'};
            } else if (request.method == 'DELETE') {
              body = [];
            }
            return http.Response(
              jsonEncode(body),
              status,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);
        await client.auth.signInWithPassword(
          email: 'test@example.com',
          password: 'test-password',
        );
        final store = SupabaseIdentityDocumentStore(client);
        final saving = store.save(
          accountId: owner,
          submission: IdentitySubmission(
            kind: IdentityDocumentKind.cnic,
            number: '12345-1234567-1',
            front: await pngBytes(800, 480),
          ),
        );
        if (rejectRow) {
          await expectLater(saving, throwsA(isA<PostgrestException>()));
        } else {
          await saving;
        }
        final rowCall = calls.singleWhere(
          (r) => r.url.path == '/rest/v1/profile_identity_documents',
        );
        final row = jsonDecode(rowCall.body) as Map<String, dynamic>;
        expect(row['document_number'], '1234512345671');
        expect(row['front_path'], startsWith('$owner/front-'));
        expect(row['front_path'], endsWith('.png'));
        expect(row['front_path'], isNot(contains('http')));
        expect(row['back_path'], isNull);
        final upload = calls.singleWhere(
          (r) =>
              r.url.path.startsWith('/storage/v1/object/identity-documents/') &&
              r.method == 'POST',
        );
        expect(upload.headers['content-type'], contains('multipart/form-data'));
        expect(
          latin1.decode(upload.bodyBytes).toLowerCase(),
          contains('content-type: image/png'),
        );
        expect(upload.url.path, isNot(contains('1234512345671')));
        expect(
          calls.where((r) => r.method == 'DELETE').length,
          rejectRow ? 1 : 0,
        );
        await expectLater(
          store.save(
            accountId: 'another-owner',
            submission: const IdentitySubmission(
              kind: IdentityDocumentKind.bForm,
              number: '1234512345671',
            ),
          ),
          throwsStateError,
        );
      },
    );
  }
}
