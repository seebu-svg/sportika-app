import 'dart:async';

import 'package:flutter/material.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';

/// The single tick source for anything that measures time on a live card.
///
/// Screens never call `DateTime.now()` to describe a match in progress: they
/// read [LiveClock.nowOf] and rebuild when the scope notifies. That keeps one
/// timer for the whole board instead of one per card, and it makes the clock a
/// seam — a widget test wraps the subtree in `LiveClock(ticking: false)` and
/// time stands still.
class LiveClock extends StatefulWidget {
  const LiveClock({
    super.key,
    required this.child,
    this.interval = const Duration(seconds: 1),
    this.ticking = true,
  });

  final Widget child;
  final Duration interval;

  /// False freezes the clock. Tests and screenshot harnesses use this so a
  /// pending timer can never outlive the test or make `pumpAndSettle` spin.
  final bool ticking;

  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  late final ValueNotifier<DateTime> _now = ValueNotifier(DateTime.now());
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.ticking) {
      _timer = Timer.periodic(widget.interval, (_) {
        _now.value = DateTime.now();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _now.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LiveClockScope(now: _now, child: widget.child);
}

/// Publishes the current instant to the subtree.
class LiveClockScope extends InheritedNotifier<ValueNotifier<DateTime>> {
  const LiveClockScope({
    super.key,
    required ValueNotifier<DateTime> now,
    required super.child,
  }) : super(notifier: now);

  /// Current instant. Falls back to the wall clock when no scope is mounted so
  /// a screen can be built in isolation without a wrapper.
  static DateTime nowOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LiveClockScope>();
    return scope?.notifier?.value ?? DateTime.now();
  }
}

/// Elapsed match time, re-derived on every tick of the nearest [LiveClock].
class LiveElapsed extends StatelessWidget {
  const LiveElapsed({
    super.key,
    required this.since,
    this.tone = SportikaColors.mint,
    this.prefix = 'LIVE',
  });

  final DateTime since;
  final Color tone;

  /// Leading label. Pass an empty string for the bare time.
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final elapsed = LiveClockScope.nowOf(context).difference(since);
    final text = formatElapsed(elapsed);
    return Semantics(
      label: prefix.isEmpty ? 'Elapsed $text' : '$prefix, elapsed $text',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (prefix.isNotEmpty) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
            ),
            const SizedBox(width: 5),
            Text(
              prefix,
              style: SportikaType.micro.copyWith(
                color: tone,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: SportikaType.micro.copyWith(
              color: SportikaColors.textBody,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// `MM:SS` under an hour, `H:MM:SS` beyond. Negative durations (a fixture that
/// has not started yet) clamp to zero rather than rendering a minus sign.
String formatElapsed(Duration elapsed) {
  final total = elapsed.isNegative ? Duration.zero : elapsed;
  final hours = total.inHours;
  final minutes = total.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = total.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
