import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sportika/features/live/widgets/live_clock.dart';

void main() {
  test('elapsed formats minutes and hours without negative values', () {
    expect(formatElapsed(const Duration(seconds: 9)), '00:09');
    expect(formatElapsed(const Duration(minutes: 4, seconds: 5)), '04:05');
    expect(
      formatElapsed(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
    expect(formatElapsed(const Duration(seconds: -30)), '00:00');
  });

  testWidgets('LiveElapsed reads the enclosing frozen clock', (tester) async {
    final start = DateTime(2026, 11, 12, 18, 0, 0);
    final now = ValueNotifier<DateTime>(
      start.add(const Duration(minutes: 3, seconds: 7)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LiveClockScope(
          now: now,
          child: LiveElapsed(since: start),
        ),
      ),
    );

    expect(find.text('03:07'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);

    // A tick repaints without a rebuild of the parent: the notifier is the
    // only thing that changed.
    now.value = start.add(const Duration(minutes: 4, seconds: 1));
    await tester.pump();
    expect(find.text('04:01'), findsOneWidget);

    // A frozen clock owns no timer, so the test can settle instantly.
    await tester.pumpAndSettle();
  });

  testWidgets('a frozen LiveClock never schedules a timer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LiveClock(
          ticking: false,
          child: Builder(
            builder: (context) => Text(
              formatElapsed(
                LiveClockScope.nowOf(context).difference(DateTime.now()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('00:00'), findsOneWidget);
  });
}
