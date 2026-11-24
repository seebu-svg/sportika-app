import 'dart:async';

import 'package:flutter/material.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/features/matches/scoring/match_scoring_validator.dart'
    show RecordMatchEvent;
import 'package:sportika/features/matches/widgets/futsal_lineups.dart';
import 'package:sportika/features/matches/widgets/futsal_match_report.dart';
import 'package:sportika/features/matches/widgets/match_event_timeline.dart'
    show eventTitle;
import 'package:sportika/features/matches/widgets/match_result_card.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/module_media_panel.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// What the Futsal Match Center can ask its host to do.
///
/// Every entry point is a callback so the view stays stateless about writes: the
/// detail screen owns the controller, the confirmations and the busy flag, in
/// the same shape the Padel Match Center uses.
class FutsalMatchActions {
  const FutsalMatchActions({
    this.onScore,
    this.onRecord,
    this.onRefresh,
    this.canManageMedia = false,
  });

  /// Opens the scoring workspace. Null when the caller may not score.
  final VoidCallback? onScore;

  /// Writes a `lineup` event. Null makes the lineup grid read-only, which is
  /// what a spectator, the review stage and a completed match all need.
  final RecordMatchEvent? onRecord;

  final Future<void> Function()? onRefresh;

  final bool canManageMedia;
}

/// The fold phase, read from the broadcast state the four engines share.
const String _pre = 'pre';
const String _running = 'running';
const String _paused = 'paused';
const String _halfTime = 'halfTime';
const String _shootout = 'shootout';
const String _complete = 'complete';

/// The dedicated futsal match surface.
///
/// Futsal is not a racket sport on a shared template: a match is two teams of
/// five, a running clock and a folded score, so the generic four-tab body was
/// the wrong shape. This view is the only door into a futsal match: the
/// scoreboard, the one action the caller may take, the starting fives, the
/// goal/card/foul feed, the shootout and the official result, in the order a
/// player reads them.
class FutsalMatchCenterView extends StatefulWidget {
  const FutsalMatchCenterView({
    super.key,
    required this.match,
    required this.progress,
    this.accountId,
    this.actions = const FutsalMatchActions(),
    this.banners = const [],
  });

  final SportMatch match;
  final MatchProgress progress;
  final String? accountId;
  final FutsalMatchActions actions;

  /// Sync and error warnings rendered under the scoreboard.
  final List<Widget> banners;

  @override
  State<FutsalMatchCenterView> createState() => _FutsalMatchCenterViewState();
}

class _FutsalMatchCenterViewState extends State<FutsalMatchCenterView> {
  final _lineupsKey = GlobalKey();
  final _resultKey = GlobalKey();

  SportMatch get match => widget.match;
  MatchProgress get progress => widget.progress;

  String get _phase => (progress.state['phase'] as String?) ?? _pre;

  void _reveal(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: SportikaMotion.base,
      curve: SportikaMotion.standard,
      alignment: .1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = match.result;
    final canScore = match.canScore(widget.accountId);
    final editableLineups =
        canScore && _phase == _pre && match.status != FixtureStatus.cancelled;

    final body = ListView(
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        FutsalScoreboard(match: match, progress: progress),
        ...widget.banners,
        const SizedBox(height: SportikaSpacing.md),
        _primaryAction(context, result, canScore),
        SectionTitle(
          'Starting fives',
          key: _lineupsKey,
          action: editableLineups ? null : 'Read only',
        ),
        if (!editableLineups)
          Padding(
            padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
            child: Text(
              _phase == _pre
                  ? 'The starting five is set by the scorer before kick-off.'
                  : 'The lineups are locked once the match has started.',
              style: SportikaType.caption,
            ),
          ),
        FutsalLineups(
          match: match,
          onRecord: editableLineups ? widget.actions.onRecord : null,
        ),
        if (_hasShootout) ...[
          const SectionTitle('Penalty shootout'),
          _ShootoutPanel(match: match, progress: progress),
        ],
        const SectionTitle('Match feed'),
        _FutsalFeed(match: match),
        const SectionTitle('Match statistics'),
        FutsalMatchReport(match: match, progress: progress),
        if (result != null) ...[
          const SectionTitle('Official result'),
          MatchResultCard(key: _resultKey, match: match),
        ],
        if (match.isTournamentMatch) ...[
          const SizedBox(height: SportikaSpacing.sm),
          _TournamentLink(match: match),
        ],
        ModuleMediaPanelIfAny(actions: widget.actions, match: match),
        const SizedBox(height: SportikaSpacing.xl),
      ],
    );

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: sportikaMaxContentWidth),
          child: widget.actions.onRefresh == null
              ? body
              : RefreshIndicator(
                  onRefresh: widget.actions.onRefresh!,
                  child: body,
                ),
        ),
      ),
    );
  }

  bool get _hasShootout {
    if (_phase == _shootout) return true;
    final taken = progress.state['shootoutTaken'];
    if (taken is List && taken.any((n) => n is num && n > 0)) return true;
    return progress.completionReason.toLowerCase().contains('penalt');
  }

  /// One door, one button. The label says what this caller can do right now, so
  /// a spectator never taps a control that would be refused.
  Widget _primaryAction(
    BuildContext context,
    OfficialResult? result,
    bool canScore,
  ) {
    final (label, icon, onPressed) = switch (result != null) {
      true => (
        'View result',
        Icons.emoji_events_outlined,
        () => _reveal(_resultKey),
      ),
      false when !canScore => (
        'You are not scoring this match',
        Icons.visibility_outlined,
        null,
      ),
      false when _phase == _pre => (
        'Set up lineups',
        Icons.groups_outlined,
        () => _reveal(_lineupsKey),
      ),
      false => (
        _phase == _running ? 'Score the match' : 'Open the scoreboard',
        Icons.sports_score,
        widget.actions.onScore,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: SportikaSpacing.xs),
      child: PrimaryButton(
        label: label,
        icon: icon,
        tone: SportikaColors.mint,
        onPressed: onPressed,
      ),
    );
  }
}

/// The futsal scoreboard: two sides, the folded score, the phase and a clock
/// that keeps running while the fold says the clock is running.
class FutsalScoreboard extends StatelessWidget {
  const FutsalScoreboard({
    super.key,
    required this.match,
    required this.progress,
  });

  final SportMatch match;
  final MatchProgress progress;

  @override
  Widget build(BuildContext context) {
    final result = match.result;
    final scores = result != null && result.sideValues.length >= 2
        ? result.sideValues
        : progress.scoreValues;
    final winner = result != null
        ? result.winnerIndex
        : progress.isComplete
        ? progress.winnerIndex
        : -1;
    final names = [
      for (var side = 0; side < 2; side++)
        match.sideLabels.length > side
            ? match.sideLabels[side]
            : 'Side ${side + 1}',
    ];
    final status = futsalStatusOf(match);
    final phase = (progress.state['phase'] as String?) ?? _pre;
    return Container(
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      decoration: BoxDecoration(
        color: SportikaColors.scoreboardSurface,
        borderRadius: BorderRadius.circular(SportikaRadius.xl),
        border: Border.all(color: SportikaColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'SPORTIKA · FUTSAL MATCH CENTER',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.micro.copyWith(
                    color: SportikaColors.textDim,
                  ),
                ),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              StatusPill(status.label, color: status.tone, icon: status.icon),
            ],
          ),
          const SizedBox(height: SportikaSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _SideName(
                  name: names[0],
                  winner: winner == 0,
                  alignment: CrossAxisAlignment.start,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SportikaSpacing.md,
                ),
                child: Text(
                  '${scores.isNotEmpty ? scores[0] : 0} – '
                  '${scores.length > 1 ? scores[1] : 0}',
                  style: SportikaType.score.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: _SideName(
                  name: names.length > 1 ? names[1] : 'Side 2',
                  winner: winner == 1,
                  alignment: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.md),
          Row(
            children: [
              Icon(status.icon, size: SportikaSpacing.lg, color: status.tone),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: Text(
                  _phaseLine(phase),
                  maxLines: 2,
                  style: SportikaType.caption,
                ),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              FutsalClock(progress: progress),
            ],
          ),
          const SizedBox(height: SportikaSpacing.sm),
          Text(
            [
              dateShort(match.scheduledAt.toLocal()),
              if (match.venue.isNotEmpty) match.venue,
              match.formatLabel,
            ].join(' · '),
            maxLines: 2,
            style: SportikaType.caption,
          ),
          if (progress.completionReason.isNotEmpty && progress.isComplete) ...[
            const SizedBox(height: SportikaSpacing.xs),
            Text(progress.completionReason, style: SportikaType.caption),
          ],
        ],
      ),
    );
  }

  String _phaseLine(String phase) => switch (phase) {
    _running => 'Play in progress',
    _paused =>
      match.pauseReason?.isNotEmpty == true
          ? 'Clock stopped: ${match.pauseReason}'
          : 'Clock stopped',
    _halfTime => 'Half time',
    _shootout => 'Penalty shootout',
    _complete => 'Full time',
    _ => 'Ready for kick-off',
  };
}

class _SideName extends StatelessWidget {
  const _SideName({
    required this.name,
    required this.winner,
    required this.alignment,
  });

  final String name;
  final bool winner;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: alignment,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: alignment == CrossAxisAlignment.end
            ? TextAlign.end
            : TextAlign.start,
        style: winner
            ? SportikaType.title.copyWith(color: SportikaColors.gold)
            : SportikaType.title,
      ),
      if (winner)
        Text(
          'Winner',
          style: SportikaType.micro.copyWith(color: SportikaColors.gold),
        ),
    ],
  );
}

/// The match clock, banked from the recorded stop/resume pairs.
///
/// The fold gives the elapsed seconds up to the last recorded action plus the
/// timestamp of the resume that is still open, so a running clock only needs a
/// one-second tick on top of that: the value is never invented, it is the same
/// number the server fold has, plus the wall time since the last resume.
class FutsalClock extends StatefulWidget {
  const FutsalClock({super.key, required this.progress});

  final MatchProgress progress;

  @override
  State<FutsalClock> createState() => _FutsalClockState();
}

class _FutsalClockState extends State<FutsalClock> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant FutsalClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool get _running => widget.progress.state['running'] == true;

  void _syncTicker() {
    if (_running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!_running && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  int get _seconds {
    final banked =
        (widget.progress.state['periodElapsed'] as num?)?.toInt() ?? 0;
    if (!_running) return banked;
    final resumeAt = DateTime.tryParse(
      (widget.progress.state['resumeAt'] as String?) ?? '',
    );
    if (resumeAt == null) return banked;
    final since = DateTime.now().toUtc().difference(resumeAt.toUtc()).inSeconds;
    return banked + (since < 0 ? 0 : since);
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _seconds;
    final text =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
    final half = (widget.progress.state['half'] as num?)?.toInt() ?? 1;
    final extra = widget.progress.state['extraTime'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: SportikaType.bodyStrong.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          extra ? 'Extra time · $half' : 'Half $half',
          style: SportikaType.micro.copyWith(color: SportikaColors.textDim),
        ),
      ],
    );
  }
}

/// The one status vocabulary a futsal match speaks. Paused is a live match
/// whose clock stopped, exactly like the pause column on the row.
({String label, Color tone, IconData icon}) futsalStatusOf(SportMatch match) {
  final tone = statusColor(match.status.key);
  final icon = statusIcon(match.status.key);
  if (match.status == FixtureStatus.cancelled) {
    return (label: match.status.label, tone: tone, icon: icon);
  }
  if (match.status == FixtureStatus.walkover) {
    return (label: match.status.label, tone: tone, icon: Icons.flag_outlined);
  }
  if (match.status == FixtureStatus.published) {
    return (
      label: match.status.label,
      tone: tone,
      icon: Icons.verified_outlined,
    );
  }
  if (match.awaitingReview) {
    return (
      label: match.status.label,
      tone: tone,
      icon: Icons.hourglass_top_outlined,
    );
  }
  if (match.isLive) {
    return match.isPaused
        ? (
            label: 'Paused',
            tone: SportikaColors.gold,
            icon: Icons.pause_circle_outline,
          )
        : (label: 'Live', tone: SportikaColors.mint, icon: Icons.sensors);
  }
  return (label: match.status.label, tone: tone, icon: Icons.schedule);
}

/// Kick-by-kick shootout readout. The per-side tallies come from the fold; the
/// order comes from the recorded `penalty` entries, so a correction that voids
/// a kick removes it here too.
class _ShootoutPanel extends StatelessWidget {
  const _ShootoutPanel({required this.match, required this.progress});

  final SportMatch match;
  final MatchProgress progress;

  @override
  Widget build(BuildContext context) {
    final scores = (progress.state['shootoutScores'] as List? ?? const [0, 0])
        .map((n) => n is num ? n.toInt() : 0)
        .toList();
    final taken = (progress.state['shootoutTaken'] as List? ?? const [0, 0])
        .map((n) => n is num ? n.toInt() : 0)
        .toList();
    final kicks =
        match.events.where((e) => !e.voided && e.kind == 'penalty').toList()
          ..sort((a, b) => a.seq.compareTo(b.seq));
    final decided = progress.isComplete && scores.length >= 2;
    return SurfaceCard(
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${scores.isNotEmpty ? scores[0] : 0} – '
            '${scores.length > 1 ? scores[1] : 0}',
            style: SportikaType.scoreSmall.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: SportikaSpacing.xs),
          Text(
            '${taken.isNotEmpty ? taken[0] : 0} and '
            '${taken.length > 1 ? taken[1] : 0} kicks taken'
            '${decided ? ' · decided' : ' · next kicker alternates'}',
            style: SportikaType.caption,
          ),
          if (kicks.isNotEmpty) ...[
            const SizedBox(height: SportikaSpacing.sm),
            for (final kick in kicks)
              Padding(
                padding: const EdgeInsets.only(bottom: SportikaSpacing.xxs),
                child: Row(
                  children: [
                    Icon(
                      kick.data['scored'] == true
                          ? Icons.check_circle_outline
                          : Icons.cancel_outlined,
                      size: SportikaSpacing.lg,
                      color: kick.data['scored'] == true
                          ? SportikaColors.mint
                          : SportikaColors.danger,
                    ),
                    const SizedBox(width: SportikaSpacing.sm),
                    Expanded(
                      child: Text(
                        _sideName(kick.side),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SportikaType.body,
                      ),
                    ),
                    Text(
                      kick.data['scored'] == true ? 'Scored' : 'Missed',
                      style: SportikaType.caption,
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _sideName(int? side) {
    if (side == null || side < 0 || side >= match.sideNames.length) {
      return 'Penalty';
    }
    return match.sideNames[side];
  }
}

/// The recorded match feed: goals, cards, fouls, substitutions and the clock,
/// newest first, with a header each time the half changes.
class _FutsalFeed extends StatelessWidget {
  const _FutsalFeed({required this.match});

  final SportMatch match;

  @override
  Widget build(BuildContext context) {
    final events = match.events.where((e) => !e.voided).toList()
      ..sort((a, b) => b.seq.compareTo(a.seq));
    if (events.isEmpty) {
      return const Text(
        'No entries yet. The clock, the goals and the cards appear here as the '
        'scorer records them.',
        style: SportikaType.caption,
      );
    }
    final children = <Widget>[];
    String? group;
    for (final event in events) {
      final label = _groupOf(event);
      if (label != group) {
        group = label;
        children.add(
          Padding(
            padding: const EdgeInsets.only(
              top: SportikaSpacing.sm,
              bottom: SportikaSpacing.xs,
            ),
            child: Text(
              label.toUpperCase(),
              style: SportikaType.label.copyWith(color: SportikaColors.textDim),
            ),
          ),
        );
      }
      children.add(_FeedRow(event: event, match: match));
    }
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: SportikaSpacing.md,
        vertical: SportikaSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  String _groupOf(MatchEvent event) {
    final half = event.data['half'];
    if (half is num && half > 0) return 'Half ${half.toInt()}';
    final action = event.data['action'];
    if (event.kind == 'clock' && action is String) {
      return switch (action) {
        'start' => 'Kick-off',
        'end_half' => 'Half time',
        'end_match' => 'Full time',
        'stop' || 'resume' => 'Match clock',
        _ => 'Match clock',
      };
    }
    if (event.kind == 'penalty') return 'Penalty shootout';
    if (event.kind == 'lineup') return 'Lineups';
    return 'Match clock';
  }
}

class _FeedRow extends StatelessWidget {
  const _FeedRow({required this.event, required this.match});

  final MatchEvent event;
  final SportMatch match;

  @override
  Widget build(BuildContext context) {
    final core = (event.kind == 'goal')
        ? Icons.sports_soccer
        : event.kind == 'card'
        ? Icons.style_outlined
        : event.kind == 'foul'
        ? Icons.front_hand_outlined
        : event.kind == 'substitution'
        ? Icons.swap_horiz
        : event.kind == 'penalty'
        ? Icons.adjust
        : Icons.timer_outlined;
    final tone = event.kind == 'goal'
        ? SportikaColors.mint
        : event.kind == 'card'
        ? SportikaColors.gold
        : SportikaColors.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SportikaSpacing.xs),
      child: Row(
        children: [
          Icon(core, size: SportikaSpacing.lg, color: tone),
          const SizedBox(width: SportikaSpacing.sm),
          Expanded(
            child: Text(
              eventTitle(event, match),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SportikaType.body,
            ),
          ),
          const SizedBox(width: SportikaSpacing.sm),
          Text(
            timeLabel(event.at.toLocal()),
            style: SportikaType.micro.copyWith(
              color: SportikaColors.textDim,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _TournamentLink extends StatelessWidget {
  const _TournamentLink({required this.match});

  final SportMatch match;

  @override
  Widget build(BuildContext context) {
    final competition = match.rules['competitionName'];
    final stage = match.rules['stage'];
    final id = match.tournamentId;
    return TextButton.icon(
      style: TextButton.styleFrom(alignment: Alignment.centerLeft),
      onPressed: id == null
          ? null
          : () => pushRoute(
              context,
              AppRoute.tournamentDetail,
              args: TournamentDetailArgs(id),
            ),
      icon: const Icon(Icons.emoji_events_outlined, size: SportikaSpacing.lg),
      label: Text(
        [
          competition is String && competition.isNotEmpty
              ? competition
              : 'View tournament',
          if (stage is String && stage.isNotEmpty) stage,
        ].join(' · '),
      ),
    );
  }
}

/// The match media panel, kept out of the view above only so the ownership of
/// the permission flag stays obvious.
class ModuleMediaPanelIfAny extends StatelessWidget {
  const ModuleMediaPanelIfAny({
    super.key,
    required this.actions,
    required this.match,
  });

  final FutsalMatchActions actions;
  final SportMatch match;

  @override
  Widget build(BuildContext context) => ModuleMediaPanel(
    bucket: 'match-media',
    entity: match.id,
    canEdit: actions.canManageMedia,
    label: match.title,
    showEmptyArtwork: false,
  );
}
