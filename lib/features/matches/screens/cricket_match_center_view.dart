import 'package:flutter/material.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/features/matches/scoring/cricket_roster.dart';
import 'package:sportika/features/matches/scoring/match_scoring_validator.dart';
import 'package:sportika/features/matches/widgets/cricket_lineups.dart';
import 'package:sportika/features/matches/widgets/cricket_match_report.dart';
import 'package:sportika/features/matches/widgets/match_event_timeline.dart';
import 'package:sportika/features/matches/widgets/match_result_card.dart';
import 'package:sportika/features/personal_games/scoring/cricket/cricket.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/match_scoreboard.dart';
import 'package:sportika/shared/widgets/module_media_panel.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// What the Cricket Match Center can ask its host to do.
///
/// Every entry point is a callback so the view stays stateless about writes: the
/// detail screen owns the controller, the confirmations and the busy flag, in
/// the same shape the Futsal Match Center uses.
class CricketMatchActions {
  const CricketMatchActions({
    this.onStart,
    this.onScore,
    this.onRecord,
    this.onRefresh,
    this.canManageMedia = false,
  });

  /// Starts the match. Null when the caller may not manage it.
  final Future<void> Function()? onStart;

  /// Opens the scoring workspace. Null when the caller may not score.
  final VoidCallback? onScore;

  /// Writes a `toss`, `lineup` or `innings_start` event. Null makes the setup
  /// panels read-only, which is what a spectator, the review stage and a
  /// completed match all need.
  final RecordMatchEvent? onRecord;

  final Future<void> Function()? onRefresh;

  final bool canManageMedia;
}

/// The dedicated cricket match surface.
///
/// A cricket match is not read as a score alone: the toss decides who bats, the
/// XI decides who comes in next, and both innings have to be started before
/// they can be scored. This view is the only guided door into a cricket match —
/// the scoreboard, the one action the caller may take, the toss, the XIs, the
/// innings in progress, the feed and the scorecard, in the order a player reads
/// them.
class CricketMatchCenterView extends StatefulWidget {
  const CricketMatchCenterView({
    super.key,
    required this.match,
    required this.progress,
    this.accountId,
    this.actions = const CricketMatchActions(),
    this.banners = const [],
  });

  final SportMatch match;
  final MatchProgress progress;
  final String? accountId;
  final CricketMatchActions actions;

  /// Sync and error warnings rendered under the scoreboard.
  final List<Widget> banners;

  @override
  State<CricketMatchCenterView> createState() => _CricketMatchCenterViewState();
}

class _CricketMatchCenterViewState extends State<CricketMatchCenterView> {
  final _tossKey = GlobalKey();
  final _lineupsKey = GlobalKey();
  final _resultKey = GlobalKey();

  SportMatch get match => widget.match;
  MatchProgress get progress => widget.progress;

  Map? get _toss {
    final toss = progress.state['toss'];
    return toss is Map ? toss : null;
  }

  Map<String, dynamic>? get _tossData =>
      _toss == null ? null : Map<String, dynamic>.from(_toss!);

  int get _innings => (progress.state['innings'] as num?)?.toInt() ?? 0;

  bool get _open => progress.state['open'] == true;

  int get _nextBatSide =>
      (progress.state['nextBatSide'] as num?)?.toInt() ?? -1;

  bool get _xisNamed =>
      CricketRoster.hasLineup(match, 0) && CricketRoster.hasLineup(match, 1);

  bool get _live => match.isLive;

  /// Setup may only be written while the match is live and before the first
  /// ball, which is exactly the window the validator accepts.
  bool get _setupEditable =>
      widget.actions.onRecord != null && _live && _innings == 0;

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

  /// Validates before writing, so a refusal is shown instead of a dead event.
  void _write(String kind, int? side, Map<String, dynamic> data) {
    final record = widget.actions.onRecord;
    if (record == null) return;
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
    record(kind, side, data);
  }

  void _startInnings() {
    final side = _nextBatSide;
    if (side < 0) {
      showSnack(
        context,
        'Record the toss before opening the innings.',
        error: true,
      );
      return;
    }
    _write(CricketEngine.kInningsStart, side, const {});
  }

  Future<void> _startMatch() async {
    final start = widget.actions.onStart;
    if (start == null) return;
    await start();
  }

  @override
  Widget build(BuildContext context) {
    final result = match.result;
    final canScore = match.canScore(widget.accountId);

    final body = ListView(
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _scoreboard(),
        ...widget.banners,
        const SizedBox(height: SportikaSpacing.md),
        _primaryAction(result, canScore),
        SectionTitle(
          'Toss',
          key: _tossKey,
          action: _setupEditable ? null : 'Read only',
        ),
        _TossPanel(
          match: match,
          toss: _tossData,
          onWrite: _setupEditable ? _write : null,
        ),
        SectionTitle(
          'Playing XIs',
          key: _lineupsKey,
          action: _setupEditable ? null : 'Read only',
        ),
        if (!_setupEditable)
          Padding(
            padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
            child: Text(
              _innings == 0
                  ? 'The XIs are named by the scorer before the first ball.'
                  : 'The XIs are locked once the innings has started.',
              style: SportikaType.caption,
            ),
          ),
        CricketLineups(
          match: match,
          onRecord: _setupEditable && _toss != null
              ? widget.actions.onRecord
              : null,
        ),
        const SectionTitle('Innings'),
        _InningsPanel(match: match, progress: progress),
        const SectionTitle('Match feed'),
        MatchEventTimeline(match: match, limit: 40),
        const SectionTitle('Scorecard'),
        CricketMatchReport(match: match, progress: progress),
        if (result != null) ...[
          const SectionTitle('Official result'),
          MatchResultCard(key: _resultKey, match: match),
        ],
        if (match.isTournamentMatch) ...[
          const SizedBox(height: SportikaSpacing.sm),
          _TournamentLink(match: match),
        ],
        ModuleMediaPanel(
          bucket: 'match-media',
          entity: match.id,
          canEdit: widget.actions.canManageMedia,
          label: match.title,
          showEmptyArtwork: false,
        ),
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

  /// The scoreboard block: the eyebrow, the status, the toss, both scores and
  /// the facts a player checks first.
  Widget _scoreboard() {
    final toss = _tossData;
    final winner = (toss?['winner'] as num?)?.toInt() ?? -1;
    final tossLine = winner >= 0
        ? '${match.sideNames[winner]} won the toss and elected to '
              '${toss?['decision'] == 'bowl' ? 'bowl' : 'bat'}'
        : null;
    final status = _statusOf(match);
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
                  'SPORTIKA · CRICKET MATCH CENTER',
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
          if (tossLine != null) ...[
            const SizedBox(height: 6),
            Text(
              tossLine,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SportikaType.caption,
            ),
          ],
          const SizedBox(height: SportikaSpacing.md),
          MatchScoreboard(
            sport: Sport.cricket,
            labels: match.sideNames,
            progress: progress,
            result: match.result,
            finished: progress.isComplete,
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

  /// One door, one button. The label says what this caller can do right now, so
  /// a spectator never taps a control that would be refused.
  Widget _primaryAction(OfficialResult? result, bool canScore) {
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
      false when match.status == FixtureStatus.upcoming => (
        'Start the match',
        Icons.play_arrow_rounded,
        widget.actions.onStart == null ? null : () => _startMatch(),
      ),
      false when _toss == null => (
        'Set the toss',
        Icons.casino_outlined,
        () => _reveal(_tossKey),
      ),
      false when !_xisNamed => (
        'Name the XIs',
        Icons.groups_outlined,
        () => _reveal(_lineupsKey),
      ),
      false when _innings == 0 || (!_open && _nextBatSide >= 0) => (
        'Start the innings',
        Icons.sports_cricket,
        widget.actions.onRecord == null ? null : _startInnings,
      ),
      false => ('Score the match', Icons.sports_score, widget.actions.onScore),
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

/// The one status vocabulary a cricket match speaks. Paused is a live match
/// whose clock stopped, exactly like the pause column on the row.
({String label, Color tone, IconData icon}) _statusOf(SportMatch match) {
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

/// The toss: two taps before the first ball, a read-only line afterwards.
///
/// It is recorded as a `toss` event rather than a rules field because the toss
/// is a match event: it happens at a time, in front of both captains, and a
/// correction should be visible in the feed like any other.
class _TossPanel extends StatefulWidget {
  const _TossPanel({required this.match, required this.toss, this.onWrite});

  final SportMatch match;
  final Map<String, dynamic>? toss;
  final void Function(String kind, int? side, Map<String, dynamic> data)?
  onWrite;

  @override
  State<_TossPanel> createState() => _TossPanelState();
}

class _TossPanelState extends State<_TossPanel> {
  int _winner = 0;
  String _decision = 'bat';

  void _record() {
    widget.onWrite?.call(CricketEngine.kToss, _winner, {'decision': _decision});
  }

  @override
  Widget build(BuildContext context) {
    final toss = widget.toss;
    final winner = (toss?['winner'] as num?)?.toInt() ?? -1;
    if (toss != null && winner >= 0) {
      final decision = toss['decision'] == 'bowl' ? 'bowl' : 'bat';
      return SurfaceCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.casino_outlined,
              size: 18,
              color: SportikaColors.textDim,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${widget.match.sideNames[winner]} won the toss and elected to '
                '$decision.',
                style: SportikaType.body,
              ),
            ),
          ],
        ),
      );
    }
    final editable = widget.onWrite != null;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('WHO WON THE TOSS?', style: SportikaType.label),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var side = 0; side < 2; side++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: side == 0 ? 8 : 0),
                    child: ChoiceChip(
                      label: Text(
                        widget.match.sideNames[side],
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected: _winner == side,
                      onSelected: editable
                          ? (_) => setState(() => _winner = side)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.sm),
          const Text('THEY ELECTED TO', style: SportikaType.label),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final option in const ['bat', 'bowl'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(option == 'bat' ? 'Bat' : 'Bowl'),
                    selected: _decision == option,
                    onSelected: editable
                        ? (_) => setState(() => _decision = option)
                        : null,
                  ),
                ),
            ],
          ),
          if (editable) ...[
            const SizedBox(height: SportikaSpacing.sm),
            PrimaryButton(
              label: 'Record the toss',
              icon: Icons.how_to_vote_outlined,
              onPressed: _record,
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: SportikaSpacing.sm),
              child: HelperText(
                'The scorer records the toss once the match is live.',
              ),
            ),
        ],
      ),
    );
  }
}

/// The innings in progress: the total, the rate, the three people on the field
/// and the XI members still waiting to bat.
class _InningsPanel extends StatelessWidget {
  const _InningsPanel({required this.match, required this.progress});

  final SportMatch match;
  final MatchProgress progress;

  @override
  Widget build(BuildContext context) {
    final open = progress.state['open'] == true;
    final next = (progress.state['nextBatSide'] as num?)?.toInt() ?? -1;
    final current = (progress.state['batSide'] as num?)?.toInt() ?? -1;
    final side = open && current >= 0 ? current : next;
    if (side < 0 || !open) {
      return Text(
        progress.isComplete
            ? 'No innings is in progress. The scorecard above holds the result.'
            : 'No innings is open. Record the toss, name the XIs and start the '
                  'innings.',
        style: SportikaType.caption,
      );
    }
    final report = CricketInningsReport(
      CricketInningsReport.deliveries(match, side),
    );
    final strike = CricketRoster.strike(match, side);
    final didNotBat = CricketInningsReport.didNotBat(match, side);
    final target = (progress.state['target'] as num?)?.toInt();
    final remaining =
        ((match.rules['oversPerInnings'] as num?)?.toInt() ?? 10) * 6 -
        report.legalBalls;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            match.sideNames[side],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SportikaType.title,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              Text(report.scoreLabel, style: SportikaType.scoreSmall),
              Text(
                '${report.oversLabel} overs',
                style: SportikaType.bodyStrong,
              ),
              Text('CRR ${report.runRate}', style: SportikaType.bodyStrong),
              if (target != null) ...[
                Text('Target $target', style: SportikaType.bodyStrong),
                Text(
                  'RRR ${remaining <= 0 ? '—' : ((target - report.totalRuns).clamp(0, target) * 6 / remaining).toStringAsFixed(2)}',
                  style: SportikaType.bodyStrong,
                ),
              ],
            ],
          ),
          const SizedBox(height: SportikaSpacing.sm),
          _Person('Striker', strike.striker),
          _Person('Non-striker', strike.nonStriker),
          _Person('Bowler', strike.bowler),
          if (didNotBat.isNotEmpty) ...[
            const SizedBox(height: SportikaSpacing.sm),
            Text(
              'Did not bat: ${didNotBat.join(', ')}',
              style: SportikaType.caption,
            ),
          ],
        ],
      ),
    );
  }
}

class _Person extends StatelessWidget {
  const _Person(this.label, this.name);

  final String label;
  final String? name;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(
          width: 84,
          child: Text(label.toUpperCase(), style: SportikaType.label),
        ),
        Expanded(
          child: Text(
            name ?? 'Not set',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SportikaType.bodyStrong.copyWith(
              fontSize: 13,
              color: name == null
                  ? SportikaColors.textMuted
                  : SportikaColors.text,
            ),
          ),
        ),
      ],
    ),
  );
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
