import 'package:flutter/material.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';

/// Keeps the current score and recovery controls visible while scoring scrolls.
class MatchScoringDock extends StatelessWidget {
  const MatchScoringDock({
    super.key,
    required this.match,
    required this.progress,
    required this.sync,
    required this.busy,
    this.onUndo,
    this.onPause,
  });
  final SportMatch match;
  final MatchProgress progress;
  final MatchSyncState sync;
  final bool busy;
  final VoidCallback? onUndo;
  final VoidCallback? onPause;

  @override
  Widget build(BuildContext context) {
    final paused = match.isPaused;
    final syncTone = sync.isWarning
        ? SportikaColors.gold
        : SportikaColors.textMuted;
    final syncIcon = switch (sync) {
      MatchSyncState.idle =>
        busy ? Icons.save_outlined : Icons.cloud_done_outlined,
      MatchSyncState.syncing => Icons.sync_rounded,
      MatchSyncState.offline => Icons.cloud_off_outlined,
      MatchSyncState.failed => Icons.error_outline_rounded,
    };
    final syncLabel = busy && sync == MatchSyncState.idle
        ? 'Saving entry…'
        : sync.label;
    final gap = MediaQuery.viewInsetsOf(context).bottom > 0
        ? SportikaSpacing.xs
        : SportikaSpacing.sm;
    final labels = match.sideLabels;
    final scoreStyle = SportikaType.score.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final nameHeight =
        MediaQuery.textScalerOf(context).scale(SportikaType.caption.fontSize!) *
        SportikaType.caption.height! *
        2;

    Widget side(int index, {required bool stacked}) {
      final name = labels.length > index ? labels[index] : '—';
      final score = progress.scoreDisplay.length > index
          ? progress.scoreDisplay[index]
          : '—';
      final identity = Tooltip(
        message: name,
        child: SizedBox(
          height: nameHeight,
          child: Align(
            alignment: stacked
                ? AlignmentDirectional.centerStart
                : Alignment.center,
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: stacked ? TextAlign.start : TextAlign.center,
              style: SportikaType.caption,
            ),
          ),
        ),
      );
      // Keep the engine's complete string, including cricket composites.
      // Scrolling preserves readable type instead of scaling scores down.
      final readout = Semantics(
        label: '$name, $score',
        child: ExcludeSemantics(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(score, maxLines: 1, style: scoreStyle),
          ),
        ),
      );
      return stacked
          ? Row(
              children: [
                Expanded(child: identity),
                const SizedBox(width: SportikaSpacing.md),
                Flexible(child: readout),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                identity,
                SizedBox(height: gap),
                readout,
              ],
            );
    }

    final controlStyle = TextButton.styleFrom(
      minimumSize: const Size(
        kMinInteractiveDimension,
        kMinInteractiveDimension,
      ),
      padding: const EdgeInsets.symmetric(horizontal: SportikaSpacing.sm),
      foregroundColor: SportikaColors.textBody,
      disabledForegroundColor: SportikaColors.textDim,
      textStyle: SportikaType.action,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SportikaRadius.sm),
      ),
    );

    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: SportikaSpacing.md,
          vertical: gap,
        ),
        decoration: const BoxDecoration(
          color: SportikaColors.deepest,
          border: Border(top: BorderSide(color: SportikaColors.borderStrong)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height:
                  MediaQuery.textScalerOf(context)
                      .scale(SportikaType.micro.fontSize!) *
                  SportikaType.micro.height! *
                  2,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      paused ? 'SCORING PAUSED' : 'LIVE SCORING',
                      maxLines: 2,
                      style: SportikaType.micro.copyWith(
                        color: paused
                            ? SportikaColors.gold
                            : SportikaColors.mint,
                      ),
                    ),
                  ),
                  const SizedBox(width: SportikaSpacing.sm),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Icon(
                            syncIcon,
                            size: SportikaSpacing.md,
                            color: syncTone,
                          ),
                          const SizedBox(width: SportikaSpacing.xs),
                          Flexible(
                            child: Text(
                              syncLabel,
                              textAlign: TextAlign.end,
                              maxLines: 2,
                              style: SportikaType.micro.copyWith(
                                color: syncTone,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: gap),
            LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(1);
                final stacked =
                    constraints.maxWidth < SportikaSpacing.xl * 10 * scale;
                if (stacked) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [side(0, stacked: true), side(1, stacked: true)],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: side(0, stacked: false)),
                    const SizedBox(width: SportikaSpacing.lg),
                    Expanded(child: side(1, stacked: false)),
                  ],
                );
              },
            ),
            SizedBox(height: gap),
            const Divider(height: 1, color: SportikaColors.borderSubtle),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    style: controlStyle,
                    onPressed: busy ? null : onUndo,
                    icon: const Icon(Icons.undo_rounded),
                    label: const Text('Undo'),
                  ),
                ),
                const SizedBox(width: SportikaSpacing.sm),
                Expanded(
                  child: TextButton.icon(
                    style: controlStyle,
                    onPressed: busy ? null : onPause,
                    icon: Icon(
                      paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    ),
                    label: Text(paused ? 'Resume' : 'Pause'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
