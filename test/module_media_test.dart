import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sportika/core/data/module_media_store.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/module_media_panel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/photo_fixture.dart';

/// Stands in for the store so a panel test never needs the Supabase singleton.
class _FakeMediaStore extends ModuleMediaStore {
  _FakeMediaStore({
    this.claimResult = true,
    this.manageResult = true,
    this.claimFailure,
  }) : super(
         SupabaseClient(
           'https://example.supabase.co',
           'test-key',
           authOptions: const AuthClientOptions(
             autoRefreshToken: false,
             authFlowType: AuthFlowType.implicit,
           ),
         ),
       );

  final bool claimResult;
  final bool manageResult;
  final Object? claimFailure;

  /// Every authority call in the order the panel made them.
  final List<String> log = [];

  @override
  Future<String?> path(String bucket, String entity, String slot) async => null;

  @override
  Future<bool> claim(String bucket, String entity) async {
    log.add('claim:$bucket/$entity');
    final failure = claimFailure;
    if (failure != null) throw failure;
    return claimResult;
  }

  @override
  Future<bool> canManage(String bucket, String entity) async {
    log.add('manage:$bucket/$entity');
    return manageResult;
  }

  @override
  String publicUrl(String bucket, String path) =>
      'https://cdn.example.test/$bucket/$path';

  @override
  Future<void> save(
    String bucket,
    String entity,
    String slot,
    Uint8List? bytes,
  ) async {}
}

Future<void> _pumpPanel(
  WidgetTester tester,
  _FakeMediaStore store, {
  bool canEdit = true,
  String bucket = 'team-media',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildSportikaTheme(),
      home: Scaffold(
        body: ModuleMediaPanel(
          bucket: bucket,
          entity: 'sqd-claimtest-a4',
          canEdit: canEdit,
          label: 'Alpha United',
          store: store,
          enabled: true,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'artwork renders to the required square and banner dimensions',
    () async {
      final source = await pngBytes(1600, 1000);
      expect(
        await decodedSize(
          await ModuleMediaStore.prepare(source, false, .5, .5),
        ),
        (512, 512),
      );
      expect(
        await decodedSize(await ModuleMediaStore.prepare(source, true, 0, 1)),
        (1280, 720),
      );
    },
  );
  test('artwork rejects non-image and oversized inputs', () async {
    await expectLater(
      ModuleMediaStore.prepare(Uint8List(20), false, .5, .5),
      throwsFormatException,
    );
    await expectLater(
      ModuleMediaStore.prepare(Uint8List(13 * 1024 * 1024), true, .5, .5),
      throwsFormatException,
    );
  });

  test('claim posts bucket and entity to the ownership RPC', () async {
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
        return http.Response(
          jsonEncode(true),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );

    expect(
      await ModuleMediaStore(client).claim('team-media', 'sqd-m3x-a4'),
      isTrue,
    );

    final call = calls.single;
    expect(call.method, 'POST');
    expect(call.url.path, '/rest/v1/rpc/claim_media_entity');
    expect(jsonDecode(call.body), {
      'p_bucket': 'team-media',
      'p_entity': 'sqd-m3x-a4',
    });
  });

  testWidgets('an editor claims the entity before asking for permission', (
    tester,
  ) async {
    final store = _FakeMediaStore();
    await _pumpPanel(tester, store);

    // The claim has to precede the permission check, or a team whose creator
    // has never registered ownership is answered "no" and shows no controls.
    expect(store.log, [
      'claim:team-media/sqd-claimtest-a4',
      'manage:team-media/sqd-claimtest-a4',
    ]);
    expect(find.text('Add logo'), findsOneWidget);
    expect(find.text('Add banner'), findsOneWidget);
  });

  testWidgets('a visitor neither claims ownership nor sees controls', (
    tester,
  ) async {
    final store = _FakeMediaStore();
    await _pumpPanel(tester, store, canEdit: false);

    expect(store.log, isEmpty);
    expect(find.text('Add logo'), findsNothing);
    expect(find.text('Delete logo'), findsNothing);
  });

  testWidgets('a refused claim leaves the panel read-only without an error', (
    tester,
  ) async {
    final store = _FakeMediaStore(claimResult: false, manageResult: false);
    await _pumpPanel(tester, store);

    expect(find.text('Add banner'), findsNothing);
    expect(find.textContaining('Media is unavailable'), findsNothing);
  });

  testWidgets('a claim failure explains itself instead of a blank slot', (
    tester,
  ) async {
    final store = _FakeMediaStore(
      claimFailure: const PostgrestException(
        message: 'Too many artwork claims in the last 24 hours.',
        code: '23514',
      ),
    );
    await _pumpPanel(tester, store);

    expect(find.textContaining('Try again tomorrow'), findsOneWidget);
    expect(find.text('Add logo'), findsNothing);
  });

  testWidgets('match banners are authorized by the match, never claimed', (
    tester,
  ) async {
    final store = _FakeMediaStore();
    await _pumpPanel(tester, store, bucket: 'match-media');

    expect(store.log, ['manage:match-media/sqd-claimtest-a4']);
    expect(find.text('Add banner'), findsOneWidget);
    expect(find.text('Add logo'), findsNothing);
  });

  testWidgets('an empty slot keeps its shape and names itself', (tester) async {
    final store = _FakeMediaStore();
    await _pumpPanel(tester, store);

    // The logo monogram and the banner caption stand in for missing artwork.
    expect(find.text('A'), findsOneWidget);
    expect(find.text('No cover image yet'), findsOneWidget);
    expect(find.text('Alpha United'), findsOneWidget);
  });
}
