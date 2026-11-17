import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';

/// Installs the process-wide crash guards.
///
/// Debug builds keep Flutter's loud red screen and console report — that is the
/// fastest way to see a bug while developing. Release builds swap in
/// [SportikaErrorScreen] and swallow the exception after reporting it, so a
/// single bad frame cannot leave a player staring at a blank window.
void installGlobalErrorHandling({
  void Function(Object error, StackTrace stack)? onReport,
}) {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    previous?.call(details);
    onReport?.call(details.exception, details.stack ?? StackTrace.current);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    onReport?.call(error, stack);
    return true;
  };

  if (kReleaseMode) {
    ErrorWidget.builder = (details) => const SportikaErrorScreen();
  }
}

/// The frame a release build shows in place of a crashed widget.
///
/// It deliberately depends on nothing from the provider tree: the widget that
/// failed may have been the one holding the listeners.
class SportikaErrorScreen extends StatelessWidget {
  const SportikaErrorScreen({super.key, this.detail, this.onRetry});

  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: SportikaColors.page,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.build_circle_outlined,
                  size: 40,
                  color: SportikaColors.gold,
                ),
                const SizedBox(height: 14),
                Text(
                  'That screen hit a snag',
                  textAlign: TextAlign.center,
                  style: SportikaType.headline.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your saved games are safe on this device. Go back and try '
                  'again, or restart Sportika if this keeps happening.',
                  textAlign: TextAlign.center,
                  style: SportikaType.body.copyWith(
                    color: SportikaColors.textMuted,
                    height: 1.45,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    detail!,
                    textAlign: TextAlign.center,
                    style: SportikaType.caption.copyWith(
                      color: SportikaColors.textDim,
                    ),
                  ),
                ],
                if (onRetry != null) ...[
                  const SizedBox(height: 18),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: SportikaColors.blue,
                    ),
                    onPressed: onRetry,
                    child: const Text('Try again'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
