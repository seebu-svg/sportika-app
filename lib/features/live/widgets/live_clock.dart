import 'dart:async';

import 'package:flutter/material.dart';

import 'package:sportika/shared/theme/theme.dart';

/// Presentation styles for the same shared live clock.
enum LiveElapsedStyle { inline, badge, scoreboard }

/// One shared clock for the live board.
///
/// The clock pauses while the application is inactive and refreshes
/// from wall-clock time immediately on resume.
///
/// [initialNow] provides deterministic frozen time for screenshots/tests.
/// [nowProvider] allows an injected clock source without changing consumers.
class LiveClock extends StatefulWidget {
  const LiveClock({
    super.key,
    required this.child,
    this.interval = const Duration(seconds: 1),
    this.ticking = true,
    this.initialNow,
    this.nowProvider,
  }) : assert(interval > Duration.zero, 'LiveClock interval must be positive.');

  final Widget child;
  final Duration interval;
  final bool ticking;

  /// Fixed initial instant. Useful with ticking: false.
  final DateTime? initialNow;

  /// Optional injectable time source.
  final DateTime Function()? nowProvider;

  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> with WidgetsBindingObserver {
  late final ValueNotifier<DateTime> _now;

  Timer? _timer;
  bool _appActive = true;

  DateTime _readNow() =>
      widget.nowProvider?.call() ?? widget.initialNow ?? DateTime.now();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _now = ValueNotifier<DateTime>(_readNow());

    _appActive = _isActive(WidgetsBinding.instance.lifecycleState);

    _configureTimer();
  }

  @override
  void didUpdateWidget(covariant LiveClock oldWidget) {
    super.didUpdateWidget(oldWidget);

    final configurationChanged =
        oldWidget.ticking != widget.ticking ||
        oldWidget.interval != widget.interval ||
        oldWidget.initialNow != widget.initialNow ||
        oldWidget.nowProvider != widget.nowProvider;

    if (!configurationChanged) return;

    _timer?.cancel();
    _timer = null;

    // Frozen clocks retain their current value unless an explicit
    // replacement instant or time provider was supplied.
    if (oldWidget.initialNow != widget.initialNow ||
        oldWidget.nowProvider != widget.nowProvider ||
        (!oldWidget.ticking && widget.ticking)) {
      _now.value = _readNow();
    }

    _configureTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = _isActive(state);

    if (_appActive == active) return;

    _appActive = active;

    if (!active) {
      _timer?.cancel();
      _timer = null;
      return;
    }

    if (widget.ticking) {
      _now.value = _readNow();
    }

    _configureTimer();
  }

  bool _isActive(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed;

  void _configureTimer() {
    _timer?.cancel();
    _timer = null;

    if (!widget.ticking || !_appActive) return;

    _scheduleNextTick();
  }

  void _scheduleNextTick() {
    if (!mounted || !widget.ticking || !_appActive) {
      return;
    }

    final intervalMicros = widget.interval.inMicroseconds;

    final current = _readNow();
    final micros = current.microsecondsSinceEpoch;

    // Align the next update to the nearest interval boundary.
    final remainder = micros % intervalMicros;
    final waitMicros = remainder == 0
        ? intervalMicros
        : intervalMicros - remainder;

    _timer = Timer(Duration(microseconds: waitMicros), () {
      if (!mounted || !widget.ticking || !_appActive) {
        return;
      }

      _now.value = _readNow();
      _scheduleNextTick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _now.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LiveClockScope(now: _now, child: widget.child);
  }
}

/// Publishes the current instant to clock-dependent descendants.
///
/// Only descendants that depend on this inherited notifier rebuild
/// when its value changes.
class LiveClockScope extends InheritedNotifier<ValueNotifier<DateTime>> {
  const LiveClockScope({
    super.key,
    required ValueNotifier<DateTime> now,
    required super.child,
  }) : super(notifier: now);

  static DateTime nowOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LiveClockScope>();

    return scope?.notifier?.value ?? DateTime.now();
  }
}

/// Live match elapsed time.
///
/// Always calculates elapsed duration from [since], not from the
/// moment this widget was mounted.
///
/// This is a display clock, not an official scoring clock.
class LiveElapsed extends StatelessWidget {
  const LiveElapsed({
    super.key,
    required this.since,
    this.tone = SportikaColors.mint,
    this.prefix = 'LIVE',
    this.style = LiveElapsedStyle.inline,
  });

  final DateTime since;
  final Color tone;
  final String prefix;
  final LiveElapsedStyle style;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    final elapsed = LiveClockScope.nowOf(context).difference(since);

    final formatted = formatElapsed(elapsed);

    final semanticLabel = prefix.isEmpty
        ? 'Elapsed $formatted'
        : '$prefix, elapsed $formatted';

    return Semantics(
      container: true,
      label: semanticLabel,
      liveRegion: false,
      child: ExcludeSemantics(
        child: switch (style) {
          LiveElapsedStyle.inline => _InlineLiveElapsed(
            text: formatted,
            tone: tone,
            prefix: prefix,
          ),
          LiveElapsedStyle.badge => _BadgeLiveElapsed(
            text: formatted,
            tone: tone,
            prefix: prefix,
          ),
          LiveElapsedStyle.scoreboard => _ScoreboardLiveElapsed(
            text: formatted,
            tone: tone,
            prefix: prefix,
            textColor: theme.textBody,
          ),
        },
      ),
    );
  }
}

// ============================================================
// INLINE LIVE INDICATOR
// ============================================================

class _InlineLiveElapsed extends StatelessWidget {
  const _InlineLiveElapsed({
    required this.text,
    required this.tone,
    required this.prefix,
  });

  final String text;
  final Color tone;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (prefix.isNotEmpty) ...[
          _LiveDot(tone: tone),
          const SizedBox(width: SportikaSpacing.xs),
          Text(
            prefix,
            style: SportikaType.micro.copyWith(
              color: tone,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: SportikaSpacing.sm),
        ],
        Text(
          text,
          style: SportikaType.micro.copyWith(
            color: theme.textBody,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// BADGE LIVE INDICATOR
// ============================================================

class _BadgeLiveElapsed extends StatelessWidget {
  const _BadgeLiveElapsed({
    required this.text,
    required this.tone,
    required this.prefix,
  });

  final String text;
  final Color tone;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surfaceSunken,
        borderRadius: const BorderRadius.all(
          Radius.circular(SportikaRadius.control),
        ),
        border: Border.all(
          color: tone.withValues(alpha: SportikaOpacity.medium),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SportikaSpacing.sm,
          vertical: SportikaSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (prefix.isNotEmpty) ...[
              _LiveDot(tone: tone),
              const SizedBox(width: SportikaSpacing.xs),
              Text(
                prefix,
                style: SportikaType.micro.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: SportikaSpacing.sm),
            ],
            Text(
              text,
              style: SportikaType.bodyStrong.copyWith(
                color: theme.textBody,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SCOREBOARD LIVE INDICATOR
// ============================================================

class _ScoreboardLiveElapsed extends StatelessWidget {
  const _ScoreboardLiveElapsed({
    required this.text,
    required this.tone,
    required this.prefix,
    required this.textColor,
  });

  final String text;
  final Color tone;
  final String prefix;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (prefix.isNotEmpty) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LiveDot(tone: tone),
              const SizedBox(width: SportikaSpacing.xs),
              Text(
                prefix,
                style: SportikaType.micro.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.xxs),
        ],
        Text(
          text,
          style: SportikaType.scoreSmall.copyWith(
            color: textColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// SHARED LIVE DOT
// ============================================================

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.tone});

  final Color tone;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
      child: const SizedBox.square(dimension: SportikaSpacing.xs),
    );
  }
}

// ============================================================
// ELAPSED TIME FORMATTER
// ============================================================

/// MM:SS under one hour.
/// H:MM:SS from one hour onward.
///
/// Negative elapsed durations clamp to zero.
String formatElapsed(Duration elapsed) {
  final total = elapsed.isNegative ? Duration.zero : elapsed;

  final hours = total.inHours;

  final minutes = total.inMinutes.remainder(60).toString().padLeft(2, '0');

  final seconds = total.inSeconds.remainder(60).toString().padLeft(2, '0');

  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
