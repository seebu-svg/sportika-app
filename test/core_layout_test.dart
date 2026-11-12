import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportika/app.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/state/app_state.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('core navigation fits a $width pixel phone', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      final state = AppState(await LocalStorage.open());
      await state.load();
      await state.signIn('acc-seebu');
      await tester.pumpWidget(
        ChangeNotifierProvider.value(value: state, child: const SportikaApp()),
      );
      // Resolve the splash and session-check timers to reach the shell.
      await tester.pump(const Duration(milliseconds: 1900));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 1900));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (var index = 1; index < 5; index++) {
        await tester.tap(find.byType(NavigationDestination).at(index));
        await tester.pump(const Duration(milliseconds: 600));
        expect(
          tester.takeException(),
          isNull,
          reason: 'Tab $index at width $width',
        );
      }
    });
  }
}
