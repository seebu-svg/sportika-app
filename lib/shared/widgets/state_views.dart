import 'package:flutter/material.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/layout.dart';

/// Neutral placeholder block. Deliberately static: a repeating pulse would keep
/// `pumpAndSettle` waiting forever in widget tests, and the local-first reads
/// resolve within a frame anyway.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.height = 14,
    this.width,
    this.radius = SportikaRadius.sm,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: SportikaColors.surfaceAlt,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: SportikaColors.borderSubtle),
      ),
    );
  }
}

/// Multi-line skeleton shaped like a list of cards.
class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({
    super.key,
    this.rows = 3,
    this.label = 'Loading',
    this.rowHeight = 74,
  });

  final int rows;
  final String label;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      container: true,
      child: Column(
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: SportikaSpacing.md),
              child: SkeletonBox(height: rowHeight, radius: SportikaRadius.lg),
            ),
        ],
      ),
    );
  }
}

/// Recoverable failure: explains what broke and offers the retry the caller
/// wired up. Used where a read can genuinely fail once a remote repository is
/// dropped in behind the same interface.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    this.title = 'Something went wrong',
    this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
    this.icon = Icons.cloud_off_outlined,
    this.compact = false,
  });

  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          vertical: compact ? 18 : 28,
          horizontal: SportikaSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: SportikaColors.dangerSubtle,
          borderRadius: BorderRadius.circular(SportikaRadius.lg),
          border: Border.all(
            color: SportikaColors.danger.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: SportikaColors.danger, size: compact ? 20 : 26),
            const SizedBox(height: SportikaSpacing.sm),
            Text(
              title,
              textAlign: TextAlign.center,
              style: SportikaType.bodyStrong,
            ),
            if (message != null) ...[
              const SizedBox(height: SportikaSpacing.xs),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: SportikaType.caption,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: SportikaSpacing.md),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                style: TextButton.styleFrom(
                  foregroundColor: SportikaColors.danger,
                  minimumSize: const Size(0, 40),
                ),
                label: Text(retryLabel, style: SportikaType.action),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Non-blocking advisory strip (storage recovery, offline note, validation
/// summary). [InfoBanner] remains the informational variant.
class InlineBanner extends StatelessWidget {
  const InlineBanner({
    super.key,
    required this.text,
    this.tone = SportikaColors.gold,
    this.icon = Icons.info_outline,
    this.action,
    this.onDismiss,
    this.dismissLabel = 'Dismiss',
  });

  final String text;
  final Color tone;
  final IconData icon;
  final Widget? action;
  final VoidCallback? onDismiss;
  final String dismissLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(SportikaRadius.md),
          border: Border.all(color: tone.withValues(alpha: 0.32)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: tone),
            const SizedBox(width: SportikaSpacing.sm),
            Expanded(child: Text(text, style: SportikaType.caption)),
            ?action,
            if (onDismiss != null)
              IconAction(
                icon: Icons.close,
                label: dismissLabel,
                onPressed: onDismiss,
                size: 16,
                tone: SportikaColors.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal proportion bar used by sport statistics.
class StatBar extends StatelessWidget {
  const StatBar({
    super.key,
    required this.label,
    required this.value,
    this.total,
    this.tone = SportikaColors.mint,
    this.trailing,
  });

  final String label;
  final int value;
  final int? total;
  final Color tone;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final max = total ?? (value == 0 ? 1 : value);
    final ratio = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Semantics(
      label: '$label $value${total == null ? '' : ' of ${total!}'}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: SportikaType.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  trailing ?? '$value',
                  style: SportikaType.bodyStrong.copyWith(fontSize: 12.5),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(SportikaRadius.pill),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                color: tone,
                backgroundColor: SportikaColors.borderSubtle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
