import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/profile/widgets/optional_identity_fields.dart';
import 'package:sportika/shared/theme/theme.dart';

import 'helpers/auth_service_fixture.dart';
import 'helpers/harness.dart';

void main() {
  late AuthFlowController flow;

  Future<void> pump(
    WidgetTester tester, {
    double width = 600,
    double scale = 1,
  }) async {
    final store = await freshState();
    final session = SessionController(store);
    final service = AuthServiceFixture(store);
    flow = AuthFlowController(session, service: service);
    flow.updateBirthDate('01/01/1990');
    addTearDown(() {
      flow.dispose();
      service.dispose();
      session.dispose();
      store.dispose();
    });
    await tester.binding.setSurfaceSize(Size(width, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: flow,
        child: MaterialApp(
          theme: buildSportikaTheme(),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: const SingleChildScrollView(
                child: OptionalIdentityFields(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'formats numbers, validates partial input and clears draft on skip',
    (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextFormField), '1234567890123');
      await tester.pump();
      expect(flow.identityDocuments.number, '12345-6789012-3');
      await tester.enterText(find.byType(TextFormField), '123');
      await tester.pump();
      expect(find.textContaining('Use 13 digits'), findsOneWidget);
      await tester.tap(find.text('Skip for Now'));
      await tester.pumpAndSettle();
      expect(flow.identityDocuments.isEmpty, isTrue);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.textContaining('Use 13 digits'), findsNothing);
    },
  );

  testWidgets('selected images refresh after removal without an inline error', (
    tester,
  ) async {
    await pump(tester);
    flow.identityDocuments.front = Uint8List.fromList([1, 2, 3]);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: flow,
        child: MaterialApp(
          theme: buildSportikaTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: OptionalIdentityFields()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Selected · Preview masked'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove CNIC front image'));
    await tester.pumpAndSettle();
    expect(flow.identityDocuments.front, isNull);
    expect(find.text('Selected · Preview masked'), findsNothing);
    expect(find.text('No image selected'), findsNWidgets(2));
  });

  testWidgets(
    'under 18 uses supported B-Form fields and fits narrow scaled layouts',
    (tester) async {
      await pump(tester, width: 320, scale: 1.8);
      flow.updateBirthDate('01/01/2015');
      // The parent birth-date field normally schedules this rebuild.
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: flow,
          child: MaterialApp(
            theme: buildSportikaTheme(),
            home: const Scaffold(
              body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(1.8)),
                child: SingleChildScrollView(child: OptionalIdentityFields()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('B-Form · Under 18'), findsOneWidget);
      expect(find.text('Choose image'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('CNIC cards fit a narrow phone with large text', (tester) async {
    await pump(tester, width: 320, scale: 1.8);
    await tester.pumpAndSettle();
    expect(find.text('CNIC front'), findsOneWidget);
    expect(find.text('CNIC back'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final skip in [true, false]) {
    testWidgets(
      'pending picker errors are discarded after ${skip ? 'skip' : 'age change'}',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final result = Completer<Object?>();
        const channel = MethodChannel('plugins.flutter.io/image_picker');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) => result.future,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        await pump(tester);
        await tester.tap(find.text('Choose image').first);
        await tester.pump();
        expect(find.text('Choosing image…'), findsOneWidget);
        if (skip) {
          await tester.tap(find.text('Skip for Now'));
        } else {
          flow.updateBirthDate('01/01/2015');
        }
        result.completeError(PlatformException(code: 'denied'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Could not open'), findsNothing);
        expect(find.text('Choosing image…'), findsNothing);
        expect(flow.identityDocuments.isEmpty, isTrue);
        debugDefaultTargetPlatformOverride = null;
        expect(tester.takeException(), isNull);
      },
    );
  }
}
