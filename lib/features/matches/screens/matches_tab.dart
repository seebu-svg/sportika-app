import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/features/discover/screens/games_tab.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/features/matches/widgets/match_center_hero.dart';
import 'package:sportika/features/matches/widgets/match_feed_content.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/cinematic_backdrop.dart';
import 'package:sportika/shared/widgets/filter_chip_row.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Discovery and play for standalone official matches.
///
/// Tournament fixtures belong to the Tournaments tab: this feed only reads
/// matches with no [SportMatch.tournamentId], so a fixture can never appear in
/// two places with two different scores.
class MatchesTab extends StatefulWidget {
  const MatchesTab({super.key, this.initialScope = 0});
  final int initialScope;

  @override
  State<MatchesTab> createState() => _MatchesTabState();
}

class _MatchesTabState extends State<MatchesTab> {
  late int _scope = widget.initialScope;
  Sport? _sport;
  bool _mine = false;
  bool _joinable = false;
  bool _searchOpen = false;
  bool _loading = false;
  bool _answeringInvite = false;
  String? _error;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void didUpdateWidget(covariant MatchesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialScope != widget.initialScope) {
      _scope = widget.initialScope;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final controller = context.read<MatchController>();
      await controller.refresh();
      if (mounted) setState(() => _error = controller.lastError);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The invitation card is the only place an invite reaches a member without
  /// the notifications screen, so it answers through the same RPC the sheet
  /// uses (`respond_match_invite`).
  Future<void> _respondInvite(SportMatch match, bool accept) async {
    final controller = context.read<MatchController>();
    setState(() => _answeringInvite = true);
    final ok = await controller.respondToInvite(match.id, accept: accept);
    if (!mounted) return;
    setState(() => _answeringInvite = false);
    if (!ok && mounted) {
      showSnack(
        context,
        controller.lastError ?? 'That did not work',
        error: true,
      );
    }
  }

  void _openGames() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: sportikaAppBar('Pickup games'),
        body: const SafeArea(child: GamesTab()),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final matches = context.watch<MatchController>();
    final needle = _search.text.trim().toLowerCase();
    bool accepts(Sport sport, String text) =>
        (_sport == null || _sport == sport) &&
        (needle.isEmpty || text.toLowerCase().contains(needle));
    final filtered =
        _search.text.isNotEmpty || _sport != null || _mine || _joinable;
    final source = switch (_scope) {
      1 => matches.liveMatches,
      2 =>
        matches.discoverableMatches
            .where((m) => m.status == FixtureStatus.upcoming)
            .toList(),
      3 => matches.completedMatches,
      _ => matches.discoverableMatches,
    };
    final mine = matches.myMatches.map((m) => m.id).toSet();
    final visible = source
        .where(
          (m) =>
              m.tournamentId == null &&
              !m.isDemo &&
              (!_mine || mine.contains(m.id)) &&
              (!_joinable || m.isOpenToJoin) &&
              accepts(
                m.sport,
                '${m.title} ${m.venue} ${m.sideNames.join(' ')} ${m.sport.label}',
              ),
        )
        .toList();
    final cards =
        <MatchFeedItem>[
          for (final m in visible)
            MatchFeedItem(
              title: m.title,
              sport: m.sport,
              status: m.status,
              date: m.scheduledAt,
              venue: m.venue,
              format: m.formatLabel,
              sides: m.sideLabels,
              result: m.result,
              paused: m.pausedAt != null,
              openToJoin: m.isOpenToJoin,
              loadProgress: m.events.any((event) => !event.voided)
                  ? () => matches.progressOf(m)
                  : null,
              onTap: () => pushRoute(
                context,
                AppRoute.matchDetail,
                args: MatchArgs(m.id),
              ),
            ),
        ]..sort(
          (a, b) =>
              _scope == 3 ? b.date.compareTo(a.date) : a.date.compareTo(b.date),
        );
    final featured = _featuredMatch(cards);
    final remaining = cards.where((item) => item != featured).toList();
    final liveCount = cards
        .where((item) => item.status == FixtureStatus.live)
        .length;
    final upcomingCount = cards
        .where((item) => item.status == FixtureStatus.upcoming)
        .length;
    final scopeTone = switch (_scope) {
      1 => SportikaColors.mint,
      2 => SportikaColors.blueBright,
      3 => SportikaColors.gold,
      _ => SportikaColors.mint,
    };

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: sportikaMaxContentWidth),
        child: CinematicBackdrop(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    SportikaSpacing.lg,
                    SportikaSpacing.md,
                    SportikaSpacing.lg,
                    SportikaSpacing.sm,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MatchCenterHero(
                          selectedSport: _sport,
                          liveCount: liveCount,
                          upcomingCount: upcomingCount,
                          matchCount: cards.length,
                        ),
                        const SizedBox(height: SportikaSpacing.md),
                        MatchSportSelector(
                          selected: _sport,
                          onChanged: (sport) => setState(() => _sport = sport),
                        ),
                        if (matches.myInvites.isNotEmpty) ...[
                          const SizedBox(height: SportikaSpacing.md),
                          _InvitesCard(
                            invites: matches.myInvites,
                            busy: _answeringInvite,
                            onRespond: _respondInvite,
                            onOpen: (id) => pushRoute(
                              context,
                              AppRoute.matchDetail,
                              args: MatchArgs(id),
                            ),
                          ),
                        ],
                        const SizedBox(height: SportikaSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton.icon(
                                  onPressed: () =>
                                      pushRoute(context, AppRoute.createMatch),
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Create Match'),
                                ),
                              ),
                            ),
                            _ToolbarGroup(
                              children: [
                                IconButton(
                                  tooltip: _searchOpen
                                      ? 'Close search'
                                      : 'Search matches',
                                  isSelected: _searchOpen,
                                  onPressed: () => setState(() {
                                    _searchOpen = !_searchOpen;
                                    if (!_searchOpen) _search.clear();
                                  }),
                                  icon: Icon(
                                    _searchOpen ? Icons.close : Icons.search,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  tooltip: 'More match options',
                                  onSelected: (value) {
                                    switch (value) {
                                      case 'mine':
                                        setState(() => _mine = !_mine);
                                      case 'joinable':
                                        setState(() => _joinable = !_joinable);
                                      case 'personal':
                                        pushRoute(
                                          context,
                                          AppRoute.personalGames,
                                        );
                                      case 'games':
                                        _openGames();
                                      case 'scorer':
                                        pushRoute(
                                          context,
                                          AppRoute.scorerWorkspace,
                                        );
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    CheckedPopupMenuItem(
                                      value: 'mine',
                                      checked: _mine,
                                      child: const Text('My matches only'),
                                    ),
                                    CheckedPopupMenuItem(
                                      value: 'joinable',
                                      checked: _joinable,
                                      child: const Text('Open to join only'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'personal',
                                      child: Text('Personal games'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'games',
                                      child: Text('Pickup games'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'scorer',
                                      child: Text('Scorer assignments'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (_searchOpen) ...[
                          const SizedBox(height: SportikaSpacing.sm),
                          TextField(
                            controller: _search,
                            autofocus: true,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              hintText: 'Search matches, teams or venues',
                              prefixIcon: Icon(Icons.search),
                            ),
                          ),
                        ],
                        const SizedBox(height: SportikaSpacing.sm),
                        FilterChipRow<int>(
                          label: 'Match status',
                          selected: _scope,
                          onChanged: (v) => setState(() => _scope = v),
                          tone: scopeTone,
                          choices: const [
                            FilterChoice(0, 'All'),
                            FilterChoice(1, 'Live'),
                            FilterChoice(2, 'Upcoming'),
                            FilterChoice(3, 'Results'),
                          ],
                        ),
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.only(top: SportikaSpacing.sm),
                            child: LinearProgressIndicator(),
                          ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(
                              top: SportikaSpacing.sm,
                            ),
                            child: ErrorState(
                              title: 'Matches could not refresh',
                              message: _error!,
                              onRetry: _refresh,
                            ),
                          ),
                        if (matches.sync.isWarning)
                          const Padding(
                            padding: EdgeInsets.only(top: SportikaSpacing.sm),
                            child: InlineBanner(
                              text: 'Matches may be out of date. Pull down to refresh.',
                              tone: SportikaColors.gold,
                              icon: Icons.cloud_off,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_loading && cards.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(SportikaSpacing.lg),
                      child: LoadingSkeleton(
                        rows: 3,
                        label: 'Loading matches',
                        rowHeight: 116,
                      ),
                    ),
                  )
                else if (cards.isEmpty && _error == null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      title: filtered
                          ? 'No matches for these filters'
                          : [
                              'No matches yet',
                              'No live matches',
                              'No upcoming matches',
                              'No results yet',
                            ][_scope],
                      body: filtered
                          ? 'Change your filters or clear your search.'
                          : 'Create a match or open one from your invitations.',
                      icon: Icons.sports_score,
                    ),
                  ),
                if (featured != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      SportikaSpacing.lg,
                      SportikaSpacing.md,
                      SportikaSpacing.lg,
                      SportikaSpacing.lg,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FeedHeading(title: 'Featured match'),
                          const SizedBox(height: SportikaSpacing.sm),
                          MatchFeedCard(item: featured, featured: true),
                        ],
                      ),
                    ),
                  ),
                if (remaining.isNotEmpty) ...[
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SportikaSpacing.lg,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _FeedHeading(
                        title: _mine
                            ? [
                                'My matches',
                                'My live matches',
                                'My upcoming matches',
                                'My results',
                              ][_scope]
                            : [
                                'All matches',
                                'Live now',
                                'Upcoming matches',
                                'Results',
                              ][_scope],
                        count: remaining.length,
                        tone: scopeTone,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      SportikaSpacing.lg,
                      SportikaSpacing.sm,
                      SportikaSpacing.lg,
                      SportikaSpacing.xl,
                    ),
                    sliver: SliverList.separated(
                      itemCount: remaining.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: SportikaSpacing.sm),
                      itemBuilder: (_, i) => MatchFeedCard(item: remaining[i]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  MatchFeedItem? _featuredMatch(List<MatchFeedItem> items) {
    for (final status in [FixtureStatus.live, FixtureStatus.upcoming]) {
      for (final item in items) {
        if (item.status == status) return item;
      }
    }
    MatchFeedItem? latestResult;
    for (final item in items) {
      if (item.status != FixtureStatus.published &&
          item.status != FixtureStatus.walkover) {
        continue;
      }
      if (latestResult == null || item.date.isAfter(latestResult.date)) {
        latestResult = item;
      }
    }
    return latestResult;
  }
}

/// Pending invitations, newest first.
///
/// An invitation used to be reachable only through the notification list, and a
/// member who dismissed that notification had no way back into the match. The
/// card answers through `respond_match_invite`, the same RPC the match sheet
/// uses, so the two surfaces cannot disagree.
class _InvitesCard extends StatelessWidget {
  const _InvitesCard({
    required this.invites,
    required this.busy,
    required this.onRespond,
    required this.onOpen,
  });

  final List<SportMatch> invites;
  final bool busy;
  final Future<void> Function(SportMatch match, bool accept) onRespond;
  final void Function(String matchId) onOpen;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(SportikaSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.mark_email_unread_outlined, size: 18),
            const SizedBox(width: SportikaSpacing.sm),
            const Expanded(
              child: Text('Your invitations', style: SportikaType.bodyStrong),
            ),
            Text('${invites.length}', style: SportikaType.caption),
          ],
        ),
        const SizedBox(height: SportikaSpacing.sm),
        for (final invite in invites)
          Padding(
            padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () => onOpen(invite.id),
                  borderRadius: BorderRadius.circular(SportikaRadius.md),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: SportikaSpacing.xs,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          invite.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: SportikaType.bodyStrong,
                        ),
                        Text(
                          '${invite.sport.label} · '
                          '${dateShort(invite.scheduledAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SportikaType.caption,
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: PrimaryButton(
                        label: 'Accept',
                        icon: Icons.check_circle_outline,
                        tone: SportikaColors.mint,
                        onPressed: busy ? null : () => onRespond(invite, true),
                      ),
                    ),
                    const SizedBox(width: SportikaSpacing.sm),
                    Expanded(
                      child: GhostButton(
                        label: 'Decline',
                        icon: Icons.close,
                        tone: SportikaColors.danger,
                        expand: true,
                        onPressed: busy ? null : () => onRespond(invite, false),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Section rule above a group of fixtures: a tone bar, the broadcast title and
/// an optional count so the feed stays scannable.
class _FeedHeading extends StatelessWidget {
  const _FeedHeading({
    required this.title,
    this.count,
    this.tone = SportikaColors.mint,
  });

  final String title;
  final int? count;
  final Color tone;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 3,
        height: 18,
        decoration: BoxDecoration(
          color: tone,
          borderRadius: BorderRadius.circular(SportikaRadius.pill),
        ),
      ),
      const SizedBox(width: SportikaSpacing.sm),
      Expanded(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SportikaType.headline,
        ),
      ),
      if (count != null)
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SportikaSpacing.sm,
            vertical: SportikaSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: SportikaColors.surfaceSunken,
            borderRadius: BorderRadius.circular(SportikaRadius.pill),
            border: Border.all(color: SportikaColors.borderSubtle),
          ),
          child: Text(
            '$count',
            style: SportikaType.micro.copyWith(color: SportikaColors.textBody),
          ),
        ),
    ],
  );
}

/// Groups the search and overflow actions into one toolbar capsule.
class _ToolbarGroup extends StatelessWidget {
  const _ToolbarGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: SportikaColors.surfaceSunken.withValues(
      alpha: SportikaOpacity.heavy,
    ),
    borderRadius: BorderRadius.circular(SportikaRadius.md),
    clipBehavior: Clip.antiAlias,
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SportikaRadius.md),
        border: Border.all(color: SportikaColors.borderSubtle),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}
