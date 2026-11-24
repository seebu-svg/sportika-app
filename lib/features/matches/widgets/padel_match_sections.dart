import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/matches/widgets/match_event_timeline.dart';
import 'package:sportika/features/matches/widgets/padel_match_center.dart';
import 'package:sportika/features/matches/widgets/padel_match_lineup.dart';
import 'package:sportika/features/matches/widgets/racket_match_report.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/module_media_panel.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Everything a host must be able to do from the shared Padel tab bodies.
///
/// Both layouts had these actions; keeping them in one callback bundle is what
/// lets the detail screen and the scoring shell mount the identical Match
/// Center without either one losing a workflow. A null field simply hides the
/// affordance, exactly as before.
class PadelMatchActions {
  const PadelMatchActions({
    this.onInviteSide,
    this.onRefresh,
    this.canManageMedia = false,
    this.canManageRoster = false,
  });

  /// Opens the participants sheet for one side. Null while a mutation runs.
  final ValueChanged<int>? onInviteSide;

  /// Pull-to-refresh target for every tab body.
  final Future<void> Function()? onRefresh;

  /// Organizer-only: the Summary tab shows the editable media panel.
  final bool canManageMedia;

  /// Whether the roster may be invited into (drives the lineup affordance).
  final bool canManageRoster;

  PadelMatchActions copyWith({ValueChanged<int>? onInviteSide}) =>
      PadelMatchActions(
        onInviteSide: onInviteSide ?? this.onInviteSide,
        onRefresh: onRefresh,
        canManageMedia: canManageMedia,
        canManageRoster: canManageRoster,
      );
}

/// The Match Center for one Padel match: the shared photo hero, the shared tab
/// strip, and the shared bodies under it.
///
/// This is the widget that unifies the two layouts. The detail screen mounts it
/// inside its own Scaffold and management drawer, and the scoring shell mounts
/// the very same view once a match has a recorded result and is no longer live
/// — so one published Padel match cannot render two different ways again. A
/// live or scheduled Padel match never reaches this view from the shell: the
/// scoring console owns those states untouched.
class PadelMatchCenterView extends StatelessWidget {
  const PadelMatchCenterView({
    super.key,
    required this.match,
    required this.progress,
    this.accountId,
    this.actions = const PadelMatchActions(),
    this.banners = const [],
  });

  final SportMatch match;
  final MatchProgress progress;
  final String? accountId;
  final PadelMatchActions actions;

  /// Sync/error warnings rendered between the hero and the tab strip.
  final List<Widget> banners;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: PadelMatchTabBar.labels.length,
      child: SafeArea(
        top: false,
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
                      PadelMatchHero(
                        match: match,
                        progress: progress,
                        accountId: accountId,
                      ),
                      ...banners,
                    ],
                  ),
                ),
                const SliverPersistentHeader(
                  pinned: true,
                  delegate: _PadelTabHeader(tabBar: PadelMatchTabBar()),
                ),
              ],
              body: TabBarView(
                children: [
                  PadelSummaryTab(match: match, actions: actions),
                  PadelScorecardTab(match: match, progress: progress),
                  PadelPlayersTab(
                    match: match,
                    progress: progress,
                    accountId: accountId,
                    actions: actions,
                  ),
                  PadelTimelineTab(match: match, actions: actions),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pins the tab strip under the hero without a second AppBar, so the strip
/// height comes from [PadelMatchTabBar] alone.
class _PadelTabHeader extends SliverPersistentHeaderDelegate {
  const _PadelTabHeader({required this.tabBar});

  final PadelMatchTabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(color: SportikaColors.background, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _PadelTabHeader oldDelegate) => false;
}

/// One scrollable, refreshable tab body. Same wrapper for all four so a pull
/// behaves identically everywhere.
class PadelTabBody extends StatelessWidget {
  const PadelTabBody({
    super.key,
    required this.match,
    required this.tab,
    required this.children,
    this.onRefresh,
  });

  final SportMatch match;
  final String tab;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final body = ListView(
      key: PageStorageKey('${match.id}-$tab'),
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      physics: const AlwaysScrollableScrollPhysics(),
      children: children,
    );
    if (onRefresh == null) return body;
    return RefreshIndicator(onRefresh: onRefresh!, child: body);
  }
}

/// Summary: match details, the tournament navigation the detail layout already
/// offered, the official scorer and the match media.
class PadelSummaryTab extends StatelessWidget {
  const PadelSummaryTab({
    super.key,
    required this.match,
    required this.actions,
  });

  final SportMatch match;
  final PadelMatchActions actions;

  @override
  Widget build(BuildContext context) {
    return PadelTabBody(
      match: match,
      tab: 'summary',
      onRefresh: actions.onRefresh,
      children: [
        const Text('Match details', style: SportikaType.bodyStrong),
        const SizedBox(height: SportikaSpacing.md),
        PadelMatchFacts(match: match),
        if (match.isTournamentMatch) ...[
          const SizedBox(height: SportikaSpacing.xs),
          PadelTournamentLink(match: match),
        ],
        const SizedBox(height: SportikaSpacing.md),
        const Text('Official scorer', style: SportikaType.bodyStrong),
        const SizedBox(height: SportikaSpacing.sm),
        PadelScorerRow(match: match),
        ModuleMediaPanel(
          bucket: 'match-media',
          entity: match.id,
          canEdit: actions.canManageMedia,
          label: match.title,
          showEmptyArtwork: false,
        ),
      ],
    );
  }
}

/// Scorecard: in-play context, then the engine's completed-set breakdown. The
/// breakdown stays labelled as the event log so it cannot be mistaken for the
/// official result above it.
class PadelScorecardTab extends StatelessWidget {
  const PadelScorecardTab({
    super.key,
    required this.match,
    required this.progress,
  });

  final SportMatch match;
  final MatchProgress progress;

  @override
  Widget build(BuildContext context) {
    final inPlay =
        match.isLive && !progress.isComplete && match.corrections.isEmpty;
    return PadelTabBody(
      match: match,
      tab: 'scorecard',
      children: [
        Text('${match.sport.label} scorecard', style: SportikaType.bodyStrong),
        const SizedBox(height: SportikaSpacing.md),
        if (inPlay) ...[
          for (final contextLine in progress.contextChips)
            Padding(
              padding: const EdgeInsets.only(bottom: SportikaSpacing.xs),
              child: Text(contextLine, style: SportikaType.body),
            ),
          const SizedBox(height: SportikaSpacing.sm),
        ],
        RacketMatchReport(match: match, progress: progress),
      ],
    );
  }
}

/// Players: the head-to-head lineup with its invitation workflow.
class PadelPlayersTab extends StatelessWidget {
  const PadelPlayersTab({
    super.key,
    required this.match,
    required this.progress,
    required this.actions,
    this.accountId,
  });

  final SportMatch match;
  final MatchProgress progress;
  final PadelMatchActions actions;
  final String? accountId;

  @override
  Widget build(BuildContext context) {
    return PadelTabBody(
      match: match,
      tab: 'players',
      onRefresh: actions.onRefresh,
      children: [
        PadelMatchLineup(
          match: match,
          progress: progress,
          accountId: accountId,
          onInviteSide: actions.onInviteSide,
        ),
      ],
    );
  }
}

/// Timeline: the whole recorded log, filterable.
class PadelTimelineTab extends StatelessWidget {
  const PadelTimelineTab({
    super.key,
    required this.match,
    required this.actions,
  });

  final SportMatch match;
  final PadelMatchActions actions;

  @override
  Widget build(BuildContext context) {
    return PadelTabBody(
      match: match,
      tab: 'timeline',
      onRefresh: actions.onRefresh,
      children: [
        MatchEventTimeline(
          match: match,
          showFilters: true,
          paginated: true,
          limit: match.events.length,
        ),
      ],
    );
  }
}

/// Jump to the competition this match belongs to. Display-only: the match row
/// carries a TEXT tournament id that may not address a tournament the account
/// can open, so the route simply asks for it and the detail screen handles the
/// miss.
class PadelTournamentLink extends StatelessWidget {
  const PadelTournamentLink({super.key, required this.match});
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

/// Who is recording this match, resolved from the account list first and the
/// roster second, exactly as the detail layout did.
class PadelScorerRow extends StatelessWidget {
  const PadelScorerRow({super.key, required this.match});
  final SportMatch match;

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
      child: Row(
        children: [
          const Icon(
            Icons.verified_user_outlined,
            size: SportikaSpacing.lg,
            color: SportikaColors.gold,
          ),
          const SizedBox(width: SportikaSpacing.sm),
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
        ],
      ),
    );
  }
}
