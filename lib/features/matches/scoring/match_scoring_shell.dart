import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/live/widgets/live_clock.dart';
import 'package:sportika/features/matches/scoring/badminton_scoring_workspace.dart';
import 'package:sportika/features/matches/scoring/cricket_scoring_workspace.dart';
import 'package:sportika/features/matches/scoring/futsal_scoring_workspace.dart';
import 'package:sportika/features/matches/scoring/match_scoring_validator.dart';
import 'package:sportika/features/matches/scoring/padel_scoring_workspace.dart';
import 'package:sportika/features/matches/widgets/cricket_match_report.dart';
import 'package:sportika/features/matches/widgets/match_event_timeline.dart';
import 'package:sportika/features/matches/widgets/match_result_card.dart';
import 'package:sportika/features/matches/widgets/match_result_dialogs.dart';
import 'package:sportika/features/matches/widgets/match_scoring_dock.dart';
import 'package:sportika/features/matches/widgets/match_vs_card.dart';
import 'package:sportika/features/matches/widgets/padel_match_result.dart';
import 'package:sportika/features/personal_games/scoring/cricket/cricket.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/futsal/futsal.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Official scoring shell. Sport engines remain the only source of score data.
class MatchScoringScreen extends StatefulWidget {
  const MatchScoringScreen({
    super.key,
    required this.matchId,
    this.ticking = true,
  });

  final String matchId;
  final bool ticking;

  @override
  State<MatchScoringScreen> createState() => _MatchScoringScreenState();
}

class _MatchScoringScreenState extends State<MatchScoringScreen> {
  MatchController? _controller;
  bool _busy = false;
  bool _recording = false;
  bool _historyExpanded = false;
  DateTime? _lastBadmintonTap;

  bool get _locked => _busy || _recording;

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
  void didUpdateWidget(covariant MatchScoringScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.matchId == widget.matchId) return;
    _controller?.unwatchMatch(oldWidget.matchId);
    _historyExpanded = false;
    _lastBadmintonTap = null;
    if (_controller != null) {
      _controller!.watchMatch(widget.matchId);
      _controller!.clearError();
    }
  }

  @override
  void dispose() {
    _controller?.unwatchMatch(widget.matchId);
    super.dispose();
  }

  SportMatch? _latestMatch(MatchController controller, String id) =>
      controller.matchById(id);

  bool _canMutate(SportMatch? match, {bool requireLive = true}) {
    if (match == null) return false;
    final accountId = context.read<SessionController>().currentAccount?.id;
    return match.canScore(accountId) &&
        (!requireLive || match.status == FixtureStatus.live);
  }

  void _error(String message) {
    if (mounted) showSnack(context, message, error: true);
  }

  /// Serializes lifecycle writes and releases the lock even on exceptions.
  Future<bool> _runAction(
    Future<bool> Function() action, {
    required String fallback,
  }) async {
    if (_locked || !mounted) return false;
    setState(() => _busy = true);
    try {
      final ok = await action();
      if (!ok) _error(_controller?.lastError ?? fallback);
      return ok;
    } catch (_) {
      _error(_controller?.lastError ?? fallback);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
          title: 'Official scoring',
          onRefresh: controller.refresh,
          child: ErrorState(
            title: 'Match not available',
            message:
                'This match is no longer visible to your account. '
                'It may have been cancelled or removed.',
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
    final hasHistory = match.events.isNotEmpty;

    return LiveClock(
      ticking: widget.ticking,
      child: ScreenScaffold(
        title: 'Official scoring',
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
        bottomNavigationBar: mayScore && live
            ? MatchScoringDock(
                match: match,
                progress: progress,
                sync: controller.sync,
                busy: _locked,
                onUndo: match.lastActiveEvent == null || _locked
                    ? null
                    : () => _undo(match),
                onPause: () => _togglePause(match),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OfficialScoringHeader(
              sport: match.sport,
              accent: accent,
              live: live,
              mayScore: mayScore,
              paused: match.isPaused,
              sync: controller.sync,
            ),
            const SizedBox(height: SportikaSpacing.sm),
            if (match.result != null && !live)
              match.sport == Sport.padel
                  ? PadelMatchResult(match: match)
                  : MatchResultCard(match: match)
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
                      ? 'Offline. Entries stay on this device and sync when '
                            'the connection returns.'
                      : 'An entry has not reached the server. Check sync '
                            'before leaving the match.',
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
                    'Only the organizer or assigned official scorer can '
                    'record entries. You are viewing the match.',
                tone: SportikaColors.textMuted,
                icon: Icons.lock_outline,
              )
            else if (match.status == FixtureStatus.upcoming)
              _StartCard(
                busy: _locked,
                onStart: () => _start(match),
                hint: match.scorerId == null
                    ? 'You are scoring as the organizer.'
                    : 'You are the assigned official scorer.',
              )
            else if (!live)
              InfoBanner(
                text: match.status == FixtureStatus.submitted
                    ? 'Result submitted for review. The scoring log is closed.'
                    : 'This match is closed for scoring.',
                tone: SportikaColors.textMuted,
                icon: Icons.lock_clock,
              ),
            if (mayScore && live) ...[
              if (match.isPaused && match.sport != Sport.padel)
                const InfoBanner(
                  text: 'Scoring is paused. Resume from the dock below.',
                  tone: SportikaColors.gold,
                  icon: Icons.pause_circle_outline,
                ),
              IgnorePointer(
                ignoring:
                    _locked || (match.isPaused && match.sport != Sport.padel),
                child: _workspace(match, progress, accent),
              ),
              if (_locked) const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: SportikaSpacing.md),
              _ControlBar(
                match: match,
                progress: progress,
                accent: accent,
                busy: _locked,
                onEndInnings: () => _endInnings(match),
                onEndMatch: () => _endMatch(match),
                onSubmit: () => _submit(match),
              ),
            ],
            if (match.sport == Sport.cricket && hasHistory) ...[
              const SizedBox(height: SportikaSpacing.sm),
              CricketMatchReport(match: match, progress: progress),
            ],
            if (hasHistory) ...[
              const SizedBox(height: SportikaSpacing.md),
              Row(
                children: [
                  const Expanded(child: SectionTitle('Match activity')),
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _historyExpanded = !_historyExpanded),
                    icon: Icon(
                      _historyExpanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    label: Text(_historyExpanded ? 'Show less' : 'View all'),
                  ),
                ],
              ),
              MatchEventTimeline(
                match: match,
                limit: _historyExpanded ? match.events.length : 3,
              ),
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
          onUndo: () => _undo(match),
          busy: _locked,
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

  /// Validates before writing; a stable client ID protects a network retry.
  Future<void> _record(
    String kind,
    int? side,
    Map<String, dynamic> data,
  ) async {
    if (_locked || !mounted) return;
    final controller = context.read<MatchController>();
    final matchId = widget.matchId;
    final match = _latestMatch(controller, matchId);
    if (!_canMutate(match) || match == null) {
      _error('Scoring access or match status changed. Refresh the match.');
      return;
    }
    if (match.isPaused && match.sport != Sport.padel) {
      _error('Resume the match before recording another entry.');
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
      _error(refusal);
      return;
    }
    if (match.sport == Sport.badminton) {
      final now = DateTime.now();
      if (_lastBadmintonTap != null &&
          now.difference(_lastBadmintonTap!).inMilliseconds < 450) {
        return;
      }
      _lastBadmintonTap = now;
    }
    setState(() => _recording = true);
    try {
      final event = await controller.recordEvent(
        match.id,
        kind: kind,
        side: side,
        data: data,
        clientId: MatchEventIds.next(),
      );
      if (event == null) {
        _error(controller.lastError ?? 'That entry could not be recorded.');
      }
    } catch (_) {
      _error(controller.lastError ?? 'That entry could not be recorded.');
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  Future<void> _togglePause(SportMatch snapshot) async {
    if (_locked) return;
    final controller = context.read<MatchController>();
    var match = _latestMatch(controller, snapshot.id);
    if (!_canMutate(match)) {
      _error('You no longer have permission to change this match.');
      return;
    }
    final wasPaused = match!.isPaused;
    String? reason;
    if (!wasPaused) {
      reason = await showPauseMatchDialog(context);
      if (reason == null || !mounted) return;
    }
    match = _latestMatch(controller, snapshot.id);
    if (!_canMutate(match) || match!.isPaused != wasPaused) {
      _error('The match state changed. Please review it and try again.');
      return;
    }
    await _runAction(
      () => wasPaused
          ? controller.resumeMatch(snapshot.id)
          : controller.pauseMatch(
              snapshot.id,
              reason: reason!.isEmpty ? null : reason,
            ),
      fallback: 'The scoring state could not be changed.',
    );
  }

  Future<void> _start(SportMatch snapshot) async {
    if (_locked) return;
    final controller = context.read<MatchController>();
    final match = _latestMatch(controller, snapshot.id);
    if (!_canMutate(match, requireLive: false) ||
        match!.status != FixtureStatus.upcoming) {
      _error('This match cannot be started from its current state.');
      return;
    }
    final ok = await _runAction(
      () => controller.startMatch(snapshot.id),
      fallback: 'The match did not start.',
    );
    if (ok && mounted) showSnack(context, 'Match started. Scoring is open.');
  }

  Future<void> _undo(SportMatch snapshot) async {
    if (_locked) return;
    final controller = context.read<MatchController>();
    final match = _latestMatch(controller, snapshot.id);
    if (!_canMutate(match)) {
      _error('Scoring access has changed. Refresh the match.');
      return;
    }
    final last = match!.lastActiveEvent;
    if (last == null) {
      showSnack(context, 'There is nothing to undo.');
      return;
    }
    final confirmed = await scoringConfirm(
      context,
      title: match.sport == Sport.padel
          ? 'Undo the last point?'
          : 'Undo the last entry?',
      body:
          '${eventTitle(last, match)} will be removed from the live score. '
          'The voided entry stays visible in match history.',
      confirmLabel: match.sport == Sport.padel ? 'Undo point' : 'Undo entry',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    final latest = _latestMatch(controller, snapshot.id);
    if (!_canMutate(latest) || latest!.lastActiveEvent?.id != last.id) {
      _error('The latest entry changed. Review the log before undoing.');
      return;
    }
    await _runAction(
      () => controller.voidEvent(snapshot.id, last.id),
      fallback: 'The entry could not be undone.',
    );
  }

  Future<void> _endInnings(SportMatch snapshot) async {
    if (_locked) return;
    final controller = context.read<MatchController>();
    final match = _latestMatch(controller, snapshot.id);
    if (!_canMutate(match) || match?.sport != Sport.cricket) {
      _error('This innings cannot be closed.');
      return;
    }
    final progress = controller.progressOf(match!);
    if (!progress.actions.any((a) => a.id == 'end_innings')) {
      _error('There is no innings to close.');
      return;
    }
    final side = (progress.state['batSide'] as num?)?.toInt() ?? 0;
    if (side < 0 || side >= match.sideNames.length) return;
    final confirmed = await scoringConfirm(
      context,
      title: 'End the innings?',
      body:
          '${match.sideNames[side]} stop batting here. The next innings '
          'and target will follow the official score.',
      confirmLabel: 'End innings',
    );
    if (!confirmed || !mounted) return;
    final latest = _latestMatch(controller, snapshot.id);
    if (!_canMutate(latest)) {
      _error('Match state changed before the innings could be closed.');
      return;
    }
    final updated = controller.progressOf(latest!);
    if (!updated.actions.any((a) => a.id == 'end_innings') ||
        (updated.state['batSide'] as num?)?.toInt() != side) {
      _error('The active innings changed. Please review the score.');
      return;
    }
    await _record(CricketEngine.kInningsEnd, side, {
      'reason': 'Innings closed',
    });
  }

  Future<void> _endMatch(SportMatch snapshot) async {
    if (_locked) return;
    if (snapshot.sport == Sport.badminton) {
      await _retire(snapshot);
      return;
    }
    final controller = context.read<MatchController>();
    final match = _latestMatch(controller, snapshot.id);
    if (!_canMutate(match)) {
      _error('This match is no longer open for scoring.');
      return;
    }
    final cricket = match!.sport == Sport.cricket;
    final confirmed = await scoringConfirm(
      context,
      title: 'End the match now?',
      body: cricket
          ? 'Use this for an abandoned or shortened cricket match. '
                'The recorded score remains on the official log.'
          : 'Use this for an abandoned or shortened futsal match. '
                'The recorded score remains on the official log.',
      confirmLabel: 'End match',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    if (!_canMutate(_latestMatch(controller, snapshot.id))) {
      _error('Match state changed. Refresh before ending it.');
      return;
    }
    if (cricket) {
      await _record(CricketEngine.kMatchEnd, null, {'reason': 'Match ended'});
    } else {
      await _record(FutsalEngine.kClock, null, {'action': 'end_match'});
    }
  }

  Future<void> _retire(SportMatch snapshot) async {
    if (_locked) return;
    final controller = context.read<MatchController>();
    final match = _latestMatch(controller, snapshot.id);
    if (!_canMutate(match)) {
      _error('This match is no longer open for scoring.');
      return;
    }
    final request = await showMatchRetireSheet(
      context,
      match: match!,
      progress: controller.progressOf(match),
    );
    if (request == null || !mounted) return;
    if (!_canMutate(_latestMatch(controller, snapshot.id))) {
      _error('Match state changed before retirement was recorded.');
      return;
    }
    final ok = await _runAction(
      () => controller.retireMatch(
        snapshot.id,
        winnerIndex: request.winnerIndex,
        reason: request.reason,
      ),
      fallback: 'The retirement was not recorded.',
    );
    if (ok && mounted) {
      showSnack(context, 'Match retirement recorded.');
      Navigator.of(context).pop();
    }
  }

  bool _requiresComplete(Sport sport) =>
      sport == Sport.futsal ||
      sport == Sport.cricket ||
      sport == Sport.badminton;

  Future<void> _submit(SportMatch snapshot) async {
    if (_locked) return;
    final controller = context.read<MatchController>();
    final match = _latestMatch(controller, snapshot.id);
    if (!_canMutate(match)) {
      _error('This match is no longer available for submission.');
      return;
    }
    final progress = controller.progressOf(match!);
    if (_requiresComplete(match.sport) && !progress.isComplete) {
      _error(switch (match.sport) {
        Sport.cricket => 'Close the innings or end the match first.',
        Sport.badminton => 'Finish the winning game or retire the match.',
        _ => 'Reach full time or end the match first.',
      });
      return;
    }
    final confirmed = await confirmSubmitResult(
      context,
      match: match,
      progress: progress,
    );
    if (!confirmed || !mounted) return;
    final latest = _latestMatch(controller, snapshot.id);
    if (!_canMutate(latest)) {
      _error('Match status or scoring permission changed.');
      return;
    }
    final current = controller.progressOf(latest!);
    if (_requiresComplete(latest.sport) && !current.isComplete) {
      _error('The match is no longer complete. Review the score.');
      return;
    }
    // Do not submit a score different from the one the scorer confirmed.
    if (current.scoreDisplay.toString() != progress.scoreDisplay.toString() ||
        current.scoreValues.toString() != progress.scoreValues.toString() ||
        current.winnerIndex != progress.winnerIndex ||
        current.isComplete != progress.isComplete) {
      _error('The score changed while reviewing. Confirm the new result.');
      return;
    }
    final ok = await _runAction(
      () => controller.submitResult(
        snapshot.id,
        headline: current.headline.isEmpty
            ? current.resultLabel
            : current.headline,
        detail: current.detailRows.join(' · '),
        sideScores: current.scoreDisplay,
        sideValues: current.scoreValues,
        winnerIndex: current.isComplete ? current.winnerIndex : -1,
      ),
      fallback: 'The result was not submitted.',
    );
    if (ok && mounted) {
      showSnack(context, 'Result submitted for review.');
      Navigator.of(context).pop();
    }
  }
}

class _OfficialScoringHeader extends StatelessWidget {
  const _OfficialScoringHeader({
    required this.sport,
    required this.accent,
    required this.live,
    required this.mayScore,
    required this.paused,
    required this.sync,
  });

  final Sport sport;
  final Color accent;
  final bool live;
  final bool mayScore;
  final bool paused;
  final MatchSyncState sync;

  @override
  Widget build(BuildContext context) {
    final sportName = switch (sport) {
      Sport.cricket => 'CRICKET',
      Sport.futsal => 'FUTSAL',
      Sport.padel => 'PADEL',
      Sport.badminton => 'BADMINTON',
    };
    final sportIcon = switch (sport) {
      Sport.cricket => Icons.sports_cricket,
      Sport.futsal => Icons.sports_soccer,
      Sport.padel => Icons.sports_tennis,
      Sport.badminton => Icons.sports_tennis,
    };
    return SurfaceCard(
      borderColor: accent.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(sportIcon, color: accent, size: 20),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: Text(
                  '$sportName  ·  OFFICIAL MATCH CENTER',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.label.copyWith(color: accent),
                ),
              ),
              StatusPill(
                live ? (paused ? 'PAUSED' : 'LIVE') : 'MATCH',
                color: live && !paused
                    ? SportikaColors.mint
                    : SportikaColors.textMuted,
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.sm),
          Row(
            children: [
              Icon(
                mayScore
                    ? Icons.verified_user_outlined
                    : Icons.visibility_outlined,
                size: 16,
                color: SportikaColors.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  mayScore ? 'Authorized official scorer' : 'Spectator view',
                  style: SportikaType.caption,
                ),
              ),
              Icon(
                sync.isWarning
                    ? Icons.cloud_off_outlined
                    : Icons.cloud_done_outlined,
                size: 16,
                color: sync.isWarning
                    ? SportikaColors.gold
                    : SportikaColors.mint,
              ),
              const SizedBox(width: 4),
              Text(
                sync.isWarning ? 'Sync attention' : 'Sync normal',
                style: SportikaType.caption,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact score readout for screens that do not have a dedicated score hero.
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
                      borderRadius: BorderRadius.circular(SportikaRadius.pill),
                      border: Border.all(color: SportikaColors.borderSubtle),
                    ),
                    child: Text(
                      chip,
                      style: SportikaType.caption.copyWith(
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
      children: [
        Container(
          width: 4,
          height: 34,
          decoration: BoxDecoration(
            color: line.leading ? accent : SportikaColors.border,
            borderRadius: BorderRadius.circular(SportikaRadius.xxs),
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
        Flexible(
          child: Text(
            line.value,
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SportikaType.scoreSmall.copyWith(
              color: line.leading ? accent : tone,
            ),
          ),
        ),
      ],
    );
  }
}

/// Only close-out actions live here. Frequent undo/pause actions stay in dock.
class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.match,
    required this.progress,
    required this.accent,
    required this.busy,
    required this.onEndInnings,
    required this.onEndMatch,
    required this.onSubmit,
  });

  final SportMatch match;
  final MatchProgress progress;
  final Color accent;
  final bool busy;
  final VoidCallback onEndInnings;
  final VoidCallback onEndMatch;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final inningsOpen = progress.actions.any((a) => a.id == 'end_innings');
    final canEndMatch =
        (match.sport == Sport.futsal &&
            progress.state['phase'] != 'complete') ||
        (match.sport == Sport.cricket &&
            ((progress.state['innings'] as num?)?.toInt() ?? 0) >= 1 &&
            !progress.isComplete &&
            progress.state['ended'] != true) ||
        (match.sport == Sport.badminton && !progress.isComplete);
    final incomplete =
        (match.sport == Sport.futsal ||
            match.sport == Sport.cricket ||
            match.sport == Sport.badminton) &&
        !progress.isComplete;

    return SurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('MATCH CLOSE-OUT', style: SportikaType.label),
          const SizedBox(height: SportikaSpacing.sm),
          if (inningsOpen || canEndMatch)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (inningsOpen)
                  GhostButton(
                    label: 'End innings',
                    icon: Icons.flag_outlined,
                    onPressed: busy ? null : onEndInnings,
                  ),
                if (canEndMatch)
                  GhostButton(
                    label: match.sport == Sport.badminton
                        ? 'Retire / concede'
                        : 'End match',
                    icon: match.sport == Sport.cricket
                        ? Icons.sports_cricket
                        : match.sport == Sport.badminton
                        ? Icons.flag_outlined
                        : Icons.timer_off_outlined,
                    onPressed: busy ? null : onEndMatch,
                  ),
              ],
            ),
          const SizedBox(height: SportikaSpacing.sm),
          PrimaryButton(
            label: incomplete
                ? 'Finish match to submit'
                : progress.isComplete
                ? 'Review final result'
                : 'Review result for submission',
            icon: Icons.task_alt,
            busy: busy && !incomplete,
            tone: accent,
            onPressed: busy || incomplete ? null : onSubmit,
          ),
          const SizedBox(height: 6),
          Text(
            incomplete
                ? switch (match.sport) {
                    Sport.cricket =>
                      'Close the innings or end the match before submission.',
                    Sport.badminton =>
                      'Finish the winning game or retire the match.',
                    _ => 'Reach full time or end the match first.',
                  }
                : 'Review the score carefully. Submission closes the log '
                      'until the organizer publishes the result.',
            style: SportikaType.caption,
          ),
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
          const Row(
            children: [
              Icon(Icons.sports_score, color: SportikaColors.mint),
              SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: Text(
                  'Ready for kick-off',
                  style: SportikaType.bodyStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.sm),
          Text(
            'Starting the match opens the official scoring log. $hint',
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

/// Shared touch-friendly scoring target. Sport-specific layouts stay separate.
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

  /// A null callback renders the pad in its disabled state.
  final VoidCallback? onTap;
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
    final interactive = enabled && onTap != null;
    return SizedBox(
      width: wide ? double.infinity : null,
      child: Semantics(
        button: true,
        enabled: interactive,
        label: hint == null ? label : '$label, $hint',
        child: Opacity(
          opacity: interactive ? 1 : 0.45,
          child: Material(
            color: tone,
            borderRadius: BorderRadius.circular(SportikaRadius.control),
            child: InkWell(
              onTap: interactive ? onTap : null,
              borderRadius: BorderRadius.circular(SportikaRadius.control),
              child: Container(
                constraints: BoxConstraints(minHeight: big ? 64 : 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20, color: foreground),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          (big ? SportikaType.title : SportikaType.bodyStrong)
                              .copyWith(color: foreground),
                    ),
                    if (hint != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        hint!,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SportikaType.caption.copyWith(
                          color: foreground.withValues(alpha: 0.72),
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
            style: SportikaType.bodyStrong.copyWith(
              color: danger ? SportikaColors.danger : SportikaColors.blueBright,
            ),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<int?> pickScoringSide(
  BuildContext context, {
  required String title,
  required List<String> sides,
  String? hint,
}) => showModalBottomSheet<int>(
  context: context,
  backgroundColor: SportikaColors.surfaceElevated,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(
      top: Radius.circular(SportikaRadius.xl),
    ),
  ),
  builder: (ctx) => AppSheet(
    title: title,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hint != null) ...[
          InfoBanner(text: hint),
          const SizedBox(height: SportikaSpacing.md),
        ],
        for (var i = 0; i < sides.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
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

/// Legacy name picker. Player-linked events should use profile IDs instead.
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
    borderRadius: BorderRadius.vertical(
      top: Radius.circular(SportikaRadius.xl),
    ),
  ),
  builder: (ctx) => SafeArea(
    child: FractionallySizedBox(
      heightFactor: 0.72,
      child: AppSheet(
        title: title,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (names.isEmpty)
              const Text(
                'Nobody is listed on this side yet.',
                style: SportikaType.caption,
              )
            else ...[
              Text(hint, style: SportikaType.caption),
              const SizedBox(height: SportikaSpacing.sm),
              for (final name in names)
                ListTile(
                  contentPadding: EdgeInsets.zero,
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
  ),
);
