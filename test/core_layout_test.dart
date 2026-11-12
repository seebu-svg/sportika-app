import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/harness.dart';

/// Layout matrix: every shell tab must render without overflow from the
/// smallest phone we support to a large handset.
void main() {
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets('core navigation fits a $width pixel phone', (tester) async {
      final state = await freshState();
      await state.signIn('acc-seebu');
      await pumpApp(tester, state: state, size: Size(width, 844));

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
