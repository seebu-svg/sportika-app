import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/harness.dart';

/// Layout matrix: every shell tab must render without overflow from the
/// smallest phone we support to a large handset, at both the default and the
/// clamped maximum text scale.
void main() {
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('core navigation fits ${width}px at textScale $scale', (
        tester,
      ) async {
        final state = await freshState();
        await state.signIn('acc-seebu');
        await pumpApp(
          tester,
          state: state,
          size: Size(width, 844),
          textScale: scale,
        );

        expect(tester.takeException(), isNull);
        for (var index = 1; index < 5; index++) {
          await tester.tap(find.byType(NavigationDestination).at(index));
          await tester.pump(const Duration(milliseconds: 600));
          expect(
            tester.takeException(),
            isNull,
            reason: 'Tab $index at width $width, textScale $scale',
          );
        }
      });
    }
  }
}
