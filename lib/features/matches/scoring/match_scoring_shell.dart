import 'package:sportika/features/matches/widgets/cricket_match_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sportika/features/matches/widgets/match_vs_card.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/matches/scoring/badminton_scoring_workspace.dart';
import 'package:sportika/features/matches/scoring/cricket_scoring_workspace.dart';
import 'package:sportika/features/matches/scoring/futsal_scoring_workspace.dart';
import 'package:sportika/features/matches/scoring/match_scoring_validator.dart';
import 'package:sportika/features/matches/scoring/padel_scoring_workspace.dart';
import 'package:sportika/features/matches/widgets/match_event_timeline.dart';
import 'package:sportika/features/matches/widgets/match_scoring_dock.dart';
import 'package:sportika/features/matches/widgets/match_result_card.dart';
import 'package:sportika/features/matches/widgets/match_result_dialogs.dart';
import 'package:sportika/features/live/widgets/live_clock.dart';
import 'package:sportika/features/personal_games/scoring/cricket/cricket.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/futsal/futsal.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// The official scoring workspace for one match.
///
/// It owns everything the four sports have in common — the score readout, the
/// sync banner, undo, the end-of-innings/end-of-match buttons and submitting
/// the result — and dispatches the body to exactly one sport workspace. Each
/// workspace writes single events through the same log, and every number it
/// paints comes from that sport's engine, never from a shared generic scorer.
class MatchScoringScreen extends StatefulWidget {
  const MatchScoringScreen({
    super.key,
    required this.matchId,
    this.ticking = true,
  });

  final String matchId;

  /// The clock seam: a widget test builds the screen with `ticking: false` so
  /// the futsal timer cannot outlive the test or make `pumpAndSettle` spin.
  final bool ticking;

  @override
  State<MatchScoringScreen> createState() => _MatchScoringScreenState();
}

class _MatchScoringScreenState extends State<MatchScoringScreen> {
  MatchController? _controller;
  bool _busy = false;
  bool _recording = false;
  Duration? _lastRallyTap;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller = context.read<MatchController>();
      _controller!.watchMatch(widget.matchId);
      _controller!.clearError();
    });
  }

  @override
  void dispose() {
    _controller?.unwatchMatch(widget.matchId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MatchController>();
    final me = context.watch<SessionController>().currentAccount;
    final match = controller.matchById(widget.matchId);

    if (match == null) {
      return LiveClock(
        ticking: widget.ticking,
        child: ScreenScaffold(
          title: 'Scoring',
          onRefresh: controller.refresh,
          child: ErrorState(
            title: 'Match not available',
            message:
                'This match is no longer visible to your account. It may have '
                'been cancelled or removed.',
            onRetry: controller.refresh,
            retryLabel: 'Try again',
          ),
        ),
      );
    }

    final progress = controller.progressOf(match);
    final accent = sportColor(match.sport);
    final mayScore = match.canScore(me?.id);
    final live = match.status == FixtureStatus.live;

    return LiveClock(
      ticking: widget.ticking,
      child: ScreenScaffold(
        title: 'Scoring',
        bottomNavigationBar: mayScore && live
            ? MatchScoringDock(
                match: match,
                progress: progress,
                sync: controller.sync,
                busy: _busy || _recording,
                onUndo: match.lastActiveEvent == null
                    ? null
                    : () => _undo(match),
                onPause: () => _togglePause(match),
              )
            : null,
        subtitle: '${match.sideNames.first} vs ${match.sideNames.last}',
        onRefresh: controller.refresh,
        actions: [
          IconButton(
            tooltip: 'Match details',
            onPressed: () => pushRoute(
              context,
              AppRoute.matchDetail,
              args: MatchArgs(match.id),
            ),
            icon: const Icon(Icons.info_outline),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (match.result != null && !live)
              MatchResultCard(match: match)
            else if (match.sport == Sport.futsal ||
                match.sport == Sport.cricket ||
                match.sport == Sport.badminton)
              MatchVsCard(
                match: match,
                progress: progress,
                showScore: live || match.isFinished,
              )
            else if (match.sport != Sport.padel)
              ScoreSummary(progress: progress, accent: accent),
            const SizedBox(height: SportikaSpacing.sm),
            if (controller.sync.isWarning)
              Padding(
                padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
                child: InlineBanner(
                  text: controller.sync == MatchSyncState.offline
                      ? 'Offline. Entries stay on this device and sync when the '
                            'connection returns.'
                      : 'The last entry did not reach the server.',
                  tone: SportikaColors.gold,
                  icon: controller.sync == MatchSyncState.offline
                      ? Icons.cloud_off
                      : Icons.error_outline,
                ),
              ),
            if (controller.lastError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
                child: InlineBanner(
                  text: controller.lastError!,
                  tone: SportikaColors.danger,
                  onDismiss: controller.clearError,
                ),
              ),
            if (!mayScore)
              const InfoBanner(
                text:
                    'Only the organizer or the assigned official scorer can '
                    'record this match. You are seeing it live.',
                tone: SportikaColors.textMuted,
                icon: Icons.lock_outline,
              )
            else if (match.status == FixtureStatus.upcoming)
              _StartCard(
                busy: _busy,
                onStart: () => _start(match),
                hint: match.scorerId == null
                    ? 'You are scoring this match as the organizer.'
                    : 'You are the official scorer for this match.',
              )
            else if (!live)
              InfoBanner(
                text: match.status == FixtureStatus.submitted
                    ? 'The result is waiting to be published, so the log is '
                          'closed.'
                    : 'This match is closed for scoring.',
                tone: SportikaColors.textMuted,
                icon: Icons.lock_clock,
              ),
            if (mayScore && live) ...[
              if (match.isPaused && match.sport != Sport.padel)
                const InfoBanner(
                  text: 'Scoring is paused. Resume from the controls below to record the next entry.',
                  tone: SportikaColors.gold,
                  icon: Icons.pause_circle_outline,
                ),
              IgnorePointer(
                ignoring:
                    _recording ||
                    _busy ||
                    (match.isPaused && match.sport != Sport.padel),
                child: _workspace(match, progress, accent),
              ),
              if (_recording) const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: SportikaSpacing.md),
              _ControlBar(
                match: match,
                progress: progress,
                accent: accent,
                busy: _busy || _recording,
                onUndo: () => _undo(match),
                onEndInnings: () => _endInnings(match, progress),
                onEndMatch: () => _endMatch(match),
                onSubmit: () => _submit(match, progress),
              ),
            ],
            if (match.sport == Sport.cricket && match.events.isNotEmpty)
              CricketMatchReport(match: match, progress: progress),
            if (match.events.isNotEmpty) ...[
              const SectionTitle('Entry log'),
              MatchEventTimeline(match: match, limit: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _workspace(SportMatch match, MatchProgress progress, Color accent) =>
      switch (match.sport) {
        Sport.cricket => CricketScoringWorkspace(
          match: match,
          progress: progress,
          accent: accent,
          onRecord: _record,
        ),
        Sport.padel => PadelScoringWorkspace(
          match: match,
          progress: progress,
          accent: accent,
          onRecord: _record,
        ),
        Sport.futsal => FutsalScoringWorkspace(
          match: match,
          progress: progress,
          accent: accent,
          onRecord: _record,
        ),
        Sport.badminton => BadmintonScoringWorkspace(
          match: match,
          progress: progress,
          accent: accent,
          onRecord: _record,
        ),
      };

  // ── Writes ──────────────────────────────────────────────────────────────

  /// One tap. The validator refuses a payload the sport cannot fold, and the
  /// client id makes a retry a no-op instead of a second score.
  void _record(String kind, int? side, Map<String, dynamic> data) {
    final controller = context.read<MatchController>();
    final match = controller.matchById(widget.matchId);
    if (match == null || _recording) return;
    if (match.sport == Sport.badminton) {
      final now = SchedulerBinding.instance.currentSystemFrameTimeStamp;
      if (_lastRallyTap != null &&
          (now - _lastRallyTap!).inMilliseconds < 450) {
        return;
      }
      _lastRallyTap = now;
    }
    final accountId = context.read<SessionController>().currentAccount?.id;
    if (!match.canScore(accountId) || !match.isLive) {
      showSnack(
        context,
        'Scoring access has changed. Refresh the match.',
        error: true,
      );
      return;
    }
    final progress = controller.progressOf(match);
    final refusal = MatchScoringValidator.validate(
      match: match,
      progress: progress,
      kind: kind,
      side: side,
      data: data,
    );
    if (refusal != null) {
      showSnack(context, refusal, error: true);
      return;
    }
    setState(() => _recording = true);
    controller
        .recordEvent(
          match.id,
          kind: kind,
          side: side,
          data: data,
          clientId: MatchEventIds.next(),
        )
        .then((event) {
          if (!mounted) return;
          setState(() => _recording = false);
          if (event != null) return;
          showSnack(
            context,
            controller.lastError ?? 'That entry could not be recorded.',
            error: true,
          );
        });
  }

  Future<void> _togglePause(SportMatch match) async {
    if (_busy || _recording) return;
    String? reason;
    if (!match.isPaused) {
      reason = await showPauseMatchDialog(context);
      if (reason == null || !mounted) return;
    }
    final controller = context.read<MatchController>();
    setState(() => _busy = true);
    final ok = match.isPaused
        ? await controller.resumeMatch(match.id)
        : await controller.pauseMatch(
            match.id,
            reason: reason!.isEmpty ? null : reason,
          );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      showSnack(
        context,
        controller.lastError ?? 'The scoring state could not be changed.',
        error: true,
      );
    }
  }

  Future<void> _start(SportMatch match) async {
    setState(() => _busy = true);
    final ok = await context.read<MatchController>().startMatch(match.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      showSnack(
        context,
        context.read<MatchController>().lastError ?? 'The match did not start.',
        error: true,
      );
      return;
    }
    showSnack(context, 'The clock is yours — record the first entry.');
  }

  Future<void> _undo(SportMatch match) async {
    final last = match.lastActiveEvent;
    if (last == null) {
      showSnack(context, 'There is nothing to undo yet.');
      return;
    }
    final confirmed = await scoringConfirm(
      context,
      title: match.sport == Sport.padel
          ? 'Undo last point?'
          : 'Undo the last entry?',
      body:
          '${eventTitle(last, match)} is withdrawn from the score. The log keeps it, '
          'struck through, so the history stays honest.',
      confirmLabel: match.sport == Sport.padel ? 'Undo point' : 'Undo entry',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    final ok = await context.read<MatchController>().voidEvent(
      match.id,
      last.id,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      showSnack(
        context,
        context.read<MatchController>().lastError ?? 'That entry stands.',
        error: true,
      );
    }
  }

  Future<void> _endInnings(SportMatch match, MatchProgress progress) async {
    final open = progress.actions.any((a) => a.id == 'end_innings');
    if (!open) {
      showSnack(context, 'There is no innings to close.');
      return;
    }
    final side = (progress.state['batSide'] as num?)?.toInt() ?? 0;
    final confirmed = await scoringConfirm(
      context,
      title: 'End the innings?',
      body:
          '${match.sideNames[side]} stop batting here. The other side bats '
          'next and the target is set from the runs on the board.',
      confirmLabel: 'End innings',
    );
    if (!confirmed) return;
    _record(CricketEngine.kInningsEnd, side, {'reason': 'Innings closed'});
  }

  Future<void> _endMatch(SportMatch match) async {
    final confirmed = await scoringConfirm(
      context,
      title: 'End the match now?',
      body:
          'Use this for an abandoned or shortened game. The score stands as it '
          'is and the result can be submitted.',
      confirmLabel: 'End match',
      danger: true,
    );
    if (!confirmed) return;
    _record(FutsalEngine.kClock, null, {'action': 'end_match'});
  }

  Future<void> _submit(SportMatch match, MatchProgress progress) async {
    final confirmed = await confirmSubmitResult(
      context,
      match: match,
      progress: progress,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    final ok = await context.read<MatchController>().submitResult(
      match.id,
      headline: progress.headline.isEmpty
          ? progress.resultLabel
          : progress.headline,
      detail: progress.detailRows.join(' · '),
      sideScores: progress.scoreDisplay,
      sideValues: progress.scoreValues,
      winnerIndex: progress.isComplete ? progress.winnerIndex : -1,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      showSnack(
        context,
        context.read<MatchController>().lastError ?? 'The result was not sent.',
        error: true,
      );
      return;
    }
    showSnack(context, 'Result submitted for review.');
    Navigator.of(context).pop();
  }
}

// ── Shared pieces the sport workspaces reuse ──────────────────────────────

/// The score readout above every workspace, folded from the event log by the
/// sport's own engine.
class ScoreSummary extends StatelessWidget {
  const ScoreSummary({super.key, required this.progress, required this.accent});

  final MatchProgress progress;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      borderColor: accent.withValues(alpha: 0.42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  progress.headline.isEmpty
                      ? 'No entries yet'
                      : progress.headline,
                  style: SportikaType.bodyStrong,
                ),
              ),
              if (progress.statusLabel != null)
                StatusPill(progress.statusLabel!, color: accent),
            ],
          ),
          const SizedBox(height: SportikaSpacing.md),
          for (var i = 0; i < progress.lines.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 18,
                color: SportikaColors.borderSubtle,
                thickness: 1,
              ),
            _ScoreLineRow(line: progress.lines[i], accent: accent),
          ],
          if (progress.contextChips.isNotEmpty) ...[
            const SizedBox(height: SportikaSpacing.md),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final chip in progress.contextChips)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: SportikaColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: SportikaColors.borderSubtle),
                    ),
                    child: Text(
                      chip,
                      style: SportikaType.caption.copyWith(
                        fontSize: 10.5,
                        color: SportikaColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ScoreLineRow extends StatelessWidget {
  const _ScoreLineRow({required this.line, required this.accent});

  final ScoreLine line;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final tone = line.muted ? SportikaColors.textDim : SportikaColors.text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 4,
          height: 34,
          decoration: BoxDecoration(
            color: line.leading ? accent : SportikaColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SportikaType.bodyStrong.copyWith(color: tone),
              ),
              if ((line.sub ?? '').isNotEmpty)
                Text(
                  line.sub!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.caption,
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          line.value,
          style: SportikaType.scoreSmall.copyWith(
            color: line.leading ? accent : tone,
          ),
        ),
      ],
    );
  }
}

/// Undo, the sport's own close-out button and submitting the result.
class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.match,
    required this.progress,
    required this.accent,
    required this.busy,
    required this.onUndo,
    required this.onEndInnings,
    required this.onEndMatch,
    required this.onSubmit,
  });

  final SportMatch match;
  final MatchProgress progress;
  final Color accent;
  final bool busy;
  final VoidCallback onUndo;
  final VoidCallback onEndInnings;
  final VoidCallback onEndMatch;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final canUndo = match.lastActiveEvent != null && !busy;
    final inningsOpen = progress.actions.any((a) => a.id == 'end_innings');
    final clockEnd =
        match.sport == Sport.futsal && progress.state['phase'] != 'complete';
    return SurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              GhostButton(
                label: match.sport == Sport.padel ? 'Undo point' : 'Undo',
                icon: Icons.undo,
                onPressed: canUndo ? onUndo : null,
              ),
              if (inningsOpen)
                GhostButton(
                  label: 'End innings',
                  icon: Icons.flag_outlined,
                  onPressed: busy ? null : onEndInnings,
                ),
              if (clockEnd)
                GhostButton(
                  label: 'End match',
                  icon: Icons.timer_off_outlined,
                  onPressed: busy ? null : onEndMatch,
                ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.sm),
          PrimaryButton(
            label: progress.isComplete
                ? 'Submit final result'
                : 'Submit result for review',
            icon: Icons.task_alt,
            busy: busy,
            tone: accent,
            onPressed: busy ? null : onSubmit,
          ),
          if (!progress.isComplete) ...[
            const SizedBox(height: 6),
            Text(
              'Submitting closes the log. The organizer publishes the result '
              'afterwards.',
              style: SportikaType.caption.copyWith(fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _StartCard extends StatelessWidget {
  const _StartCard({
    required this.busy,
    required this.onStart,
    required this.hint,
  });

  final bool busy;
  final VoidCallback onStart;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Ready when you are', style: SportikaType.bodyStrong),
          const SizedBox(height: 4),
          Text(
            'Starting the match opens the log for scoring. $hint',
            style: SportikaType.caption,
          ),
          const SizedBox(height: SportikaSpacing.md),
          PrimaryButton(
            label: 'Start the match',
            icon: Icons.play_arrow_rounded,
            busy: busy,
            onPressed: busy ? null : onStart,
          ),
        ],
      ),
    );
  }
}

/// One tap target of a sport scoring pad.
class ScoringPad extends StatelessWidget {
  const ScoringPad({
    super.key,
    required this.label,
    required this.onTap,
    this.tone = SportikaColors.surfaceAlt,
    this.icon,
    this.hint,
    this.big = false,
    this.wide = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final Color tone;
  final IconData? icon;
  final String? hint;
  final bool big;
  final bool wide;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final foreground = tone.computeLuminance() > .45
        ? SportikaColors.deepest
        : SportikaColors.text;
    return SizedBox(
      width: wide ? double.infinity : null,
      child: Semantics(
        button: true,
        enabled: enabled,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Material(
            color: tone,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                constraints: BoxConstraints(minHeight: big ? 58 : 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18, color: foreground),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: big ? 22 : 13,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: foreground,
                      ),
                    ),
                    if (hint != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        hint!,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: foreground.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────

/// A confirmation the scorer must read before a destructive close-out.
Future<bool> scoringConfirm(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Confirm',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: SportikaColors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SportikaRadius.lg),
      ),
      title: Text(title, style: SportikaType.headline),
      content: Text(body, style: SportikaType.body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            confirmLabel,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: danger ? SportikaColors.danger : SportikaColors.blueBright,
            ),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Asks which side an action belongs to.
Future<int?> pickScoringSide(
  BuildContext context, {
  required String title,
  required List<String> sides,
  String? hint,
}) => showModalBottomSheet<int>(
  context: context,
  backgroundColor: SportikaColors.surfaceElevated,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (ctx) => AppSheet(
    title: title,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hint != null) ...[
          InfoBanner(text: hint),
          const SizedBox(height: 12),
        ],
        for (var i = 0; i < sides.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PrimaryButton(
              label: sides[i],
              icon: Icons.sports_score,
              small: true,
              tone: i == 0 ? SportikaColors.blue : SportikaColors.mint,
              onPressed: () => Navigator.pop(ctx, i),
            ),
          ),
      ],
    ),
  ),
);

/// Picks an existing roster name. Full squads can scroll within the sheet.
Future<String?> pickScoringName(
  BuildContext context, {
  required String title,
  required List<String> names,
  String hint = 'Pick from the players on that side.',
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  backgroundColor: SportikaColors.surfaceElevated,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (ctx) => SingleChildScrollView(
    child: AppSheet(
      title: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (names.isEmpty)
            const Text(
              'Nobody is listed on this side yet.',
              style: SportikaType.caption,
            )
          else ...[
            Text(hint, style: SportikaType.caption),
            const SizedBox(height: 8),
            for (final name in names)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: PlayerAvatar(
                  initials: initialsOf(name),
                  size: 30,
                  color: SportikaColors.blue,
                ),
                title: Text(name, style: SportikaType.bodyStrong),
                onTap: () => Navigator.pop(ctx, name),
              ),
          ],
        ],
      ),
    ),
  ),
);
