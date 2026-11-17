import 'package:sportika/features/matches/widgets/cricket_match_report.dart';
import 'package:sportika/shared/widgets/module_media_panel.dart';
import 'package:flutter/material.dart';
import 'package:sportika/features/matches/widgets/futsal_lineups.dart';
import 'package:sportika/features/matches/widgets/match_roster_card.dart';
import 'package:sportika/features/matches/widgets/futsal_match_report.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/matches/widgets/match_event_timeline.dart';
import 'package:sportika/features/matches/widgets/match_dispute_sheet.dart';
import 'package:sportika/features/matches/widgets/match_lifecycle_bar.dart';
import 'package:sportika/features/matches/widgets/match_participants_sheet.dart';
import 'package:sportika/features/matches/widgets/match_result_dialogs.dart';
import 'package:sportika/features/matches/widgets/match_result_card.dart';
import 'package:sportika/features/matches/widgets/racket_match_report.dart';
import 'package:sportika/features/matches/widgets/match_management_widgets.dart';
import 'package:sportika/features/matches/widgets/match_scorer_sheet.dart';
import 'package:sportika/features/matches/widgets/match_detail_hero.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Everything about one official match: the VS hero, the live score, the
/// lifecycle actions this role may take, the roster, the scorer, the recorded
/// log and the result with its correction history.
///
/// While the screen is open the repository keeps a realtime channel for this
/// match, so a score recorded on another device lands here without a refresh.
class MatchDetailScreen extends StatefulWidget {
  const MatchDetailScreen({super.key, required this.matchId});

  final String matchId;

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  MatchController? _controller;
  bool _busy = false;

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
      return ScreenScaffold(
        title: 'Match',
        onRefresh: controller.refresh,
        child: ErrorState(
          title: 'Match not available',
          message:
              'This match is no longer visible to your account, or it was '
              'removed.',
          onRetry: controller.refresh,
          retryLabel: 'Try again',
        ),
      );
    }

    final progress = controller.progressOf(match);

    final organizer = match.isOrganizer(me?.id);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: sportikaAppBar(
          'Match Center',
          actions: [
            if (match.isLive && match.canScore(me?.id))
              IconButton(
                tooltip: 'Open scoring workspace',
                onPressed: _busy ? null : () => _openScoring(match),
                icon: const Icon(Icons.sports_score),
              ),
            Builder(
              builder: (scaffoldContext) => IconButton(
                tooltip: 'Match management',
                onPressed: () => Scaffold.of(scaffoldContext).openEndDrawer(),
                icon: const Icon(Icons.more_horiz),
              ),
            ),
          ],
        ),
        endDrawer: Drawer(
          backgroundColor: SportikaColors.background,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(SportikaSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Match management',
                          style: SportikaType.title,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close management',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  if (organizer && match.status == FixtureStatus.upcoming)
                    TextButton.icon(
                      onPressed: _busy ? null : () => _edit(match),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit match'),
                    ),
                  MatchLifecycleBar(
                    compact: true,
                    match: match,
                    accountId: me?.id,
                    busy: _busy,
                    onStart: () => _start(match),
                    onScore: () => _openScoring(match),
                    onPause: () => _pause(match),
                    onResume: () => _resume(match),
                    onSubmit: () => _submit(match, progress),
                    onPublish: () => _publish(match),
                    onCorrect: () => _correct(match),
                    onWalkover: () => _walkover(match),
                    onDispute: () =>
                        showMatchDisputeSheet(context, match: match),
                    onCancel: () => _cancel(match),
                    onInvite: () =>
                        showMatchParticipantsSheet(context, match: match),
                    onAssignScorer: () =>
                        showMatchScorerSheet(context, match: match),
                    onRespond: (accept) => _respond(match, accept),
                  ),
                  if (match.corrections.isNotEmpty)
                    MatchCorrectionHistory(match: match),
                  if (match.disputes.isNotEmpty)
                    _DisputeSummary(
                      match: match,
                      onOpen: () =>
                          showMatchDisputeSheet(context, match: match),
                    ),
                  if (organizer)
                    ModuleMediaPanel(
                      bucket: 'match-media',
                      entity: match.id,
                      canEdit: true,
                      label: match.title,
                      showEmptyArtwork: false,
                    ),
                ],
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: sportikaMaxContentWidth,
              ),
              child: NestedScrollView(
                headerSliverBuilder: (context, innerScrolled) => [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        MatchDetailHero(match: match, progress: progress),
                        if (controller.sync.isWarning)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: SportikaSpacing.lg,
                            ),
                            child: InlineBanner(
                              text: controller.sync == MatchSyncState.offline
                                  ? 'Offline. Entries will sync when the connection returns.'
                                  : 'The last change did not reach the server.',
                              tone: SportikaColors.gold,
                              icon: Icons.cloud_off,
                            ),
                          ),
                        if (controller.lastError != null)
                          Padding(
                            padding: const EdgeInsets.all(SportikaSpacing.md),
                            child: InlineBanner(
                              text: controller.lastError!,
                              tone: SportikaColors.danger,
                              onDismiss: controller.clearError,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SliverAppBar(
                    primary: false,
                    pinned: true,
                    automaticallyImplyLeading: false,
                    toolbarHeight: 0,
                    backgroundColor: SportikaColors.background,
                    bottom: TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelStyle: SportikaType.action,
                      indicatorColor: SportikaColors.mint,
                      labelColor: SportikaColors.text,
                      unselectedLabelColor: SportikaColors.textMuted,
                      tabs: [
                        Tab(text: 'Summary'),
                        Tab(text: 'Scorecard'),
                        Tab(text: 'Players'),
                        Tab(text: 'Timeline'),
                      ],
                    ),
                  ),
                ],
                body: TabBarView(
                  children: [
                    _section('summary', controller.refresh, [
                      const Text(
                        'Match details',
                        style: SportikaType.bodyStrong,
                      ),
                      const SizedBox(height: SportikaSpacing.md),
                      _DetailFact(
                        label: 'Scheduled',
                        value: dateShort(match.scheduledAt),
                      ),
                      if (match.venue.isNotEmpty)
                        _DetailFact(label: 'Venue', value: match.venue),
                      _DetailFact(label: 'Format', value: match.formatLabel),
                      _DetailFact(
                        label: 'Discipline',
                        value: match.discipline.label,
                      ),
                      if (match.isPaused &&
                          match.pauseReason?.isNotEmpty == true)
                        _DetailFact(
                          label: 'Pause reason',
                          value: match.pauseReason!,
                        ),
                      if (match.result?.detail.isNotEmpty == true)
                        _DetailFact(
                          label: 'Result detail',
                          value: match.result!.detail,
                        ),
                      if (match.isTournamentMatch)
                        _TournamentLinkCard(match: match),
                      const SizedBox(height: SportikaSpacing.md),
                      const Text(
                        'Official scorer',
                        style: SportikaType.bodyStrong,
                      ),
                      const SizedBox(height: SportikaSpacing.sm),
                      _ScorerRow(match: match, canManage: false, onTap: () {}),
                      ModuleMediaPanel(
                        bucket: 'match-media',
                        entity: match.id,
                        canEdit: false,
                        label: match.title,
                        showEmptyArtwork: false,
                      ),
                    ]),
                    _section('scorecard', controller.refresh, [
                      Text(
                        '${match.sport.label} scorecard',
                        style: SportikaType.bodyStrong,
                      ),
                      const SizedBox(height: SportikaSpacing.md),
                      if (match.sport == Sport.cricket)
                        CricketMatchReport(match: match, progress: progress),
                      if (match.sport == Sport.padel ||
                          match.sport == Sport.badminton) ...[
                        if (match.isLive &&
                            !progress.isComplete &&
                            match.corrections.isEmpty) ...[
                          for (final contextLine in progress.contextChips)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: SportikaSpacing.xs,
                              ),
                              child: Text(
                                contextLine,
                                style: SportikaType.body,
                              ),
                            ),
                          const SizedBox(height: SportikaSpacing.sm),
                        ],
                        RacketMatchReport(match: match, progress: progress),
                      ],
                      if (match.sport == Sport.futsal)
                        FutsalMatchReport(match: match, progress: progress),
                    ]),
                    _section('players', controller.refresh, [
                      MatchRosterCard(
                        match: match,
                        accountId: me?.id,
                        onInviteSide: _busy
                            ? null
                            : (side) => showMatchParticipantsSheet(
                                context,
                                match: match,
                                initialSide: side,
                              ),
                      ),
                      if (match.sport == Sport.futsal) ...[
                        const SizedBox(height: SportikaSpacing.md),
                        FutsalLineups(match: match),
                      ],
                    ]),
                    _section('timeline', controller.refresh, [
                      MatchEventTimeline(
                        match: match,
                        showFilters: true,
                        paginated: true,
                        limit: match.events.length,
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(
    String key,
    Future<void> Function() refresh,
    List<Widget> children,
  ) => RefreshIndicator(
    onRefresh: refresh,
    child: ListView(
      key: PageStorageKey('${widget.matchId}-$key'),
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      physics: const AlwaysScrollableScrollPhysics(),
      children: children,
    ),
  );

  Future<void> _run(Future<bool> Function() action) async {
    final controller = context.read<MatchController>();
    setState(() => _busy = true);
    final ok = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      showSnack(
        context,
        controller.lastError ?? 'That did not work',
        error: true,
      );
    }
  }

  Future<void> _start(SportMatch match) async {
    await _run(() => context.read<MatchController>().startMatch(match.id));
    if (!mounted) return;
    // Re-read the row: the instance captured by the tap is one build old.
    final started = context.read<MatchController>().matchById(match.id);
    if (started != null && started.status == FixtureStatus.live) {
      _openScoring(started);
    }
  }

  void _openScoring(SportMatch match) {
    pushRoute(context, AppRoute.matchScoring, args: MatchArgs(match.id));
  }

  /// Pauses scoring without ending the match. The reason is optional; the
  /// server keeps it on the match and in the lifecycle log.
  Future<void> _pause(SportMatch match) async {
    final reason = await showPauseMatchDialog(context);
    if (reason == null || !mounted) return;
    await _run(
      () => context.read<MatchController>().pauseMatch(
        match.id,
        reason: reason.isEmpty ? null : reason,
      ),
    );
  }

  Future<void> _resume(SportMatch match) async {
    await _run(() => context.read<MatchController>().resumeMatch(match.id));
  }

  Future<void> _submit(SportMatch match, MatchProgress progress) async {
    final confirmed = await confirmSubmitResult(
      context,
      match: match,
      progress: progress,
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => context.read<MatchController>().submitResult(
        match.id,
        headline: progress.headline.isEmpty
            ? progress.resultLabel
            : progress.headline,
        detail: progress.detailRows.join(' · '),
        sideScores: progress.scoreDisplay,
        sideValues: progress.scoreValues,
        winnerIndex: progress.isComplete ? progress.winnerIndex : -1,
      ),
    );
  }

  Future<void> _publish(SportMatch match) async {
    await _run(() => context.read<MatchController>().publishResult(match.id));
  }

  Future<void> _correct(SportMatch match) async {
    final corrected = await showCorrectResultSheet(context, match: match);
    if (corrected == null || !mounted) return;
    await _run(
      () => context.read<MatchController>().correctResult(
        match.id,
        headline: corrected.headline,
        detail: corrected.detail,
        sideScores: corrected.sideScores,
        sideValues: corrected.sideValues,
        winnerIndex: corrected.winnerIndex,
        reason: corrected.reason,
      ),
    );
  }

  Future<void> _walkover(SportMatch match) async {
    final choice = await showWalkoverSheet(context, match: match);
    if (choice == null || !mounted) return;
    await _run(
      () => context.read<MatchController>().recordWalkover(
        match.id,
        winnerIndex: choice.winnerIndex,
        reason: choice.reason,
      ),
    );
  }

  Future<void> _cancel(SportMatch match) async {
    final reason = await showCancelMatchDialog(context);
    if (reason == null || !mounted) return;
    await _run(
      () => context.read<MatchController>().cancelMatch(
        match.id,
        reason: reason.isEmpty ? null : reason,
      ),
    );
  }

  Future<void> _respond(SportMatch match, bool accept) async {
    await _run(
      () => context.read<MatchController>().respondToInvite(
        match.id,
        accept: accept,
      ),
    );
  }

  Future<void> _edit(SportMatch match) async {
    final draft = await showModalBottomSheet<_EditDraft>(
      context: context,
      backgroundColor: SportikaColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) =>
          SingleChildScrollView(child: _EditMatchSheet(match: match)),
    );
    if (draft == null || !mounted) return;
    await _run(
      () => context.read<MatchController>().updateMatch(
        match.id,
        title: draft.title,
        venue: draft.venue,
        scheduledAt: draft.scheduledAt,
        sideA: draft.sideA,
        sideB: draft.sideB,
        capacity: draft.capacity,
      ),
    );
  }
}

class _EditDraft {
  const _EditDraft({
    required this.title,
    required this.venue,
    required this.scheduledAt,
    required this.sideA,
    required this.sideB,
    required this.capacity,
  });

  final String title;
  final String venue;
  final DateTime scheduledAt;
  final String sideA;
  final String sideB;
  final int capacity;
}

class _EditMatchSheet extends StatefulWidget {
  const _EditMatchSheet({required this.match});

  final SportMatch match;

  @override
  State<_EditMatchSheet> createState() => _EditMatchSheetState();
}

class _EditMatchSheetState extends State<_EditMatchSheet> {
  late final TextEditingController _title = TextEditingController(
    text: widget.match.title,
  );
  late final TextEditingController _venue = TextEditingController(
    text: widget.match.venue,
  );
  late final TextEditingController _sideA = TextEditingController(
    text: widget.match.sideNames.isNotEmpty ? widget.match.sideNames[0] : '',
  );
  late final TextEditingController _sideB = TextEditingController(
    text: widget.match.sideNames.length > 1 ? widget.match.sideNames[1] : '',
  );
  late DateTime _scheduledAt = widget.match.scheduledAt;
  late int _capacity = widget.match.capacity;

  String? _error;

  void _save() {
    if (_title.text.trim().length < 2 || _title.text.trim().length > 80) {
      setState(() => _error = 'Use a match title between 2 and 80 characters.');
      return;
    }
    final a = _sideA.text.trim();
    final b = _sideB.text.trim();
    if (a.isEmpty || b.isEmpty || a.toLowerCase() == b.toLowerCase()) {
      setState(() => _error = 'Enter two different side names.');
      return;
    }
    Navigator.of(context).pop(
      _EditDraft(
        title: _title.text.trim(),
        venue: _venue.text.trim(),
        scheduledAt: _scheduledAt,
        sideA: a,
        sideB: b,
        capacity: _capacity,
      ),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _venue.dispose();
    _sideA.dispose();
    _sideB.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: 'Edit match',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MatchSheetIntro(
            icon: Icons.edit_calendar_outlined,
            title: 'Match essentials',
            body: 'Update the fixture details. Existing players, invitations and scores stay with this match.',
          ),
          const SizedBox(height: SportikaSpacing.md),

          TextField(
            controller: _title,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Title',
              isDense: true,
              counterText: '',
            ),
          ),
          const SizedBox(height: SportikaSpacing.md),
          TextField(
            controller: _venue,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Venue',
              isDense: true,
              counterText: '',
            ),
          ),
          const SizedBox(height: SportikaSpacing.md),
          TextField(
            controller: _sideA,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: 'Side A',
              counterText: '',
            ),
          ),
          const SizedBox(height: SportikaSpacing.md),
          TextField(
            controller: _sideB,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: 'Side B',
              counterText: '',
            ),
          ),
          const SizedBox(height: SportikaSpacing.md),
          Text(dateShort(_scheduledAt), style: SportikaType.bodyStrong),
          const SizedBox(height: 8),
          GhostButton(
            label: 'Change time',
            icon: Icons.event_outlined,
            expand: true,
            onPressed: _pickTime,
          ),
          const SizedBox(height: SportikaSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$_capacity players',
                  style: SportikaType.bodyStrong,
                ),
              ),
              IconButton(
                tooltip: 'Fewer places',
                onPressed: _capacity <= 2
                    ? null
                    : () => setState(() => _capacity -= 1),
                icon: const Icon(Icons.remove_circle_outline, size: 20),
              ),
              IconButton(
                tooltip: 'More places',
                onPressed: _capacity >= 100
                    ? null
                    : () => setState(() => _capacity += 1),
                icon: const Icon(Icons.add_circle_outline, size: 20),
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.md),
          if (_error != null) ...[
            InlineBanner(text: _error!, tone: SportikaColors.danger),
            const SizedBox(height: 12),
          ],
          PrimaryButton(
            label: 'Save changes',
            icon: Icons.save_outlined,
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
    );
    if (!mounted) return;
    setState(() {
      _scheduledAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        time?.hour ?? _scheduledAt.hour,
        time?.minute ?? _scheduledAt.minute,
      );
    });
  }
}

/// A one-glance summary of the disputes on this result. The sheet owns the
/// raising and answering; this card only says whether anything is waiting.
class _DisputeSummary extends StatelessWidget {
  const _DisputeSummary({required this.match, required this.onOpen});

  final SportMatch match;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final open = match.disputes.where((d) => d.status.isOpen).length;
    final latest = match.disputes.first;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.gavel_outlined,
                size: 16,
                color: open > 0
                    ? SportikaColors.gold
                    : SportikaColors.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  open > 0
                      ? '$open dispute${open == 1 ? '' : 's'} awaiting an answer'
                      : 'Every dispute on this result has been answered',
                  style: SportikaType.bodyStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            latest.reason,
            style: SportikaType.caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: SportikaSpacing.sm),
          GhostButton(
            label: 'Open disputes',
            icon: Icons.open_in_new,
            expand: true,
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}

class _ScorerRow extends StatelessWidget {
  const _ScorerRow({
    required this.match,
    required this.canManage,
    required this.onTap,
  });

  final SportMatch match;
  final bool canManage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scorer = match.scorerId == null
        ? null
        : context.read<SessionController>().accountById(match.scorerId) ??
              match.participantOf(match.scorerId);
    final name = match.scorerId == null
        ? 'The organizer scores this match'
        : scorer is Account
        ? scorer.displayName
        : scorer is MatchParticipant
        ? scorer.displayName
        : 'Assigned scorer';
    return SurfaceCard(
      onTap: canManage ? onTap : null,
      child: Row(
        children: [
          const Icon(
            Icons.verified_user_outlined,
            size: 18,
            color: SportikaColors.gold,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: SportikaType.bodyStrong),
                Text(
                  match.scorerId == null
                      ? 'Only the organizer can record scores'
                      : 'Records the log and submits the result',
                  style: SportikaType.caption,
                ),
              ],
            ),
          ),
          if (canManage) const Text('Change', style: SportikaType.action),
        ],
      ),
    );
  }
}

class _TournamentLinkCard extends StatelessWidget {
  const _TournamentLinkCard({required this.match});
  final SportMatch match;

  @override
  Widget build(BuildContext context) {
    final competition = match.rules['competitionName'];
    final stage = match.rules['stage'];
    return TextButton.icon(
      style: TextButton.styleFrom(alignment: Alignment.centerLeft),
      onPressed: match.tournamentId == null
          ? null
          : () => pushRoute(
              context,
              AppRoute.tournamentDetail,
              args: TournamentDetailArgs(match.tournamentId!),
            ),
      icon: const Icon(Icons.emoji_events_outlined, size: 18),
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

class _DetailFact extends StatelessWidget {
  const _DetailFact({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: SportikaSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: SportikaType.caption),
        const SizedBox(height: SportikaSpacing.xs),
        Text(value, style: SportikaType.body),
      ],
    ),
  );
}
