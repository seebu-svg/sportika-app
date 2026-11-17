import 'package:sportika/shared/widgets/editorial.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/games_controller.dart';
import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/widgets/match_scoreboard.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/home/widgets/home_header.dart';
import 'package:sportika/features/home/widgets/role_empty_state.dart';

/// Participation-first dashboard using account activity and sports discovery.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  /// Discovery filter; personal participation and totals stay account-wide.
  Sport? _sport;
  bool _refreshing = false;
  bool _refreshFailed = false;

  /// Cached so [dispose] can close the live channel without reading the
  /// element tree after it has been torn down.
  MatchController? _matches;

  @override
  void initState() {
    super.initState();
    // Live scores arrive through the realtime channel, so Home opens it on the
    // first frame instead of polling. The inbox channel is session-wide and
    // shared with the header bell; starting it here only makes sure it runs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<MatchController>().watchAllMatches();
      context.read<NotificationsController>().start();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _matches ??= context.read<MatchController>();
  }

  @override
  void dispose() {
    // Only the match channel is Home's to close: the inbox channel belongs to
    // the session, so it stays open for every other screen.
    _matches?.unwatchAllMatches();
    super.dispose();
  }

  /// Pull-to-refresh reloads every source Home paints, in parallel, so one
  /// slow endpoint cannot leave the rest of the dashboard stale.
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _refreshFailed = false;
    });
    try {
      await Future.wait([
        context.read<SessionController>().reload(),
        context.read<MatchController>().refresh(),
        context.read<TournamentsController>().refresh(),
        context.read<FixturesController>().refresh(),
        context.read<GamesController>().refresh(),
        context.read<TeamsController>().refresh(),
        context.read<NotificationsController>().refresh(),
      ]);
      if (mounted) _refreshFailed = _anySourceFailed(context);
    } catch (_) {
      if (mounted) setState(() => _refreshFailed = true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// True when any source Home reads is holding a failure. A section keeps its
  /// last good rows, so this only decides whether the banner appears.
  static bool _anySourceFailed(BuildContext context) =>
      context.read<MatchController>().lastError != null ||
      context.read<TournamentsController>().lastError != null ||
      context.read<FixturesController>().lastError != null ||
      context.read<GamesController>().lastError != null ||
      context.read<TeamsController>().lastError != null ||
      context.read<NotificationsController>().error != null;

  /// One horizontal rhythm for the whole tab: 20 on phones, centred 720
  /// column on tablets and desktop so nothing stretches edge to edge.
  double _pagePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width > 760 ? (width - 720) / 2 : 20;
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<ProfileController>().currentAccount;
    final official = context.watch<MatchController>();
    final tournaments = context.watch<TournamentsController>();
    final games = context.watch<GamesController>();
    final inbox = context.watch<NotificationsController>();
    if (me == null) return const SizedBox.shrink();

    final now = DateTime.now();

    /// Side and winner, so one rule decides a win in every section below.
    bool won(SportMatch m) {
      final side = m.participantOf(me.id)?.side;
      final winner = m.result?.winnerIndex;
      return side != null && winner != null && winner >= 0 && winner == side;
    }

    // The match module is the only source of a member's own fixtures, so a
    // tournament result and a pickup result can never be counted twice.
    final mine = official.myMatches.where((m) => m.isParticipant(me.id));
    final myUpcoming =
        mine
            .where(
              (m) =>
                  m.status == FixtureStatus.upcoming &&
                  !m.scheduledAt.isBefore(now),
            )
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final liveNow = official.liveMatches.take(2).toList();
    // Matches this member is the appointed scorer for: an obligation, so it
    // keeps its own tile in the activity block.
    final scoring = official.myScoringMatches
        .where((m) => m.scorerId == me.id)
        .toList();

    // Open tournaments, ranked the way a player picks one: their own sports
    // first, then their own city, then whatever starts soonest.
    final featured =
        tournaments.liveTournaments
            .where(
              (t) =>
                  t.status == TournamentStatus.open &&
                  !t.startsAt.isBefore(now),
            )
            .toList()
          ..sort((a, b) {
            int relevance(Tournament t) =>
                (me.sports.contains(t.sport) ? 2 : 0) +
                (t.city.toLowerCase() == me.city.toLowerCase() ? 1 : 0);
            final rank = relevance(b).compareTo(relevance(a));
            return rank != 0 ? rank : a.startsAt.compareTo(b.startsAt);
          });

    // Open matches with room left. A tournament fixture has no free place to
    // claim — a place is earned through an entry — so it is excluded.
    final recommendations =
        official.discoverableMatches
            .where(
              (m) =>
                  m.tournamentId == null &&
                  m.status == FixtureStatus.upcoming &&
                  !m.scheduledAt.isBefore(now) &&
                  m.acceptedCount < m.capacity &&
                  (_sport == null || m.sport == _sport),
            )
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final hasGames = games.games.any(
      (g) =>
          g.visibility == 'Public' &&
          !g.full &&
          !g.at.isBefore(now) &&
          (_sport == null || g.sport == _sport),
    );

    // The three newest unread items; "See all" opens the full inbox.
    final updateRail = inbox.myNotifications
        .where((n) => !n.read)
        .take(3)
        .toList();

    // Honest numbers: only published results of matches this member played.
    final played = mine
        .where((m) => m.status == FixtureStatus.published)
        .toList();
    final wins = played.where(won).length;
    final bySport = <Sport, ({int played, int wins})>{};
    for (final m in played) {
      final current = bySport[m.sport] ?? (played: 0, wins: 0);
      bySport[m.sport] = (
        played: current.played + 1,
        wins: current.wins + (won(m) ? 1 : 0),
      );
    }
    final breakdown = bySport.entries.toList()
      ..sort((a, b) => b.value.played.compareTo(a.value.played));

    final heroTournament = featured.isEmpty ? null : featured.first;
    final firstName = me.displayName.trim().split(RegExp(r'\s+')).first;
    final page = _pagePadding(context);

    return RefreshIndicator(
      onRefresh: _refresh,
      color: SportikaColors.mint,
      backgroundColor: SportikaColors.surface,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(page, 16, page, 16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LET’S PLAY',
                    style: SportikaType.micro.copyWith(
                      color: SportikaColors.mint,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${greeting(firstName.isEmpty ? 'Player' : firstName)}!',
                    style: SportikaType.hero.copyWith(fontSize: 26),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    (myUpcoming.isNotEmpty || liveNow.isNotEmpty)
                        ? 'Your next game is on the horizon. Make it count.'
                        : 'Ready for your next game?',
                    style: SportikaType.caption,
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: page),
            sliver: SliverToBoxAdapter(
              child: HomeHero(
                sport:
                    _sport ??
                    (heroTournament?.sport ??
                        (me.sports.isEmpty ? Sport.cricket : me.sports.first)),
                // The featured event's own banner outranks stock photography;
                // the widget falls back when the URL 404s.
                imageUrl: heroTournament?.bannerUrl,
                featuredTournament: heroTournament,
                pagePadding: SportikaSpacing.lg,
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(page, 24, page, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _title('Quick actions'),
                const SizedBox(height: 12),
                _quickActions(context),
                if (_refreshFailed) ...[
                  const SizedBox(height: 12),
                  InlineBanner(
                    text: 'Couldn’t refresh everything. Showing the last activity that loaded.',
                    icon: Icons.cloud_off_outlined,
                    action: TextButton(
                      onPressed: _refresh,
                      child: const Text('Try again'),
                    ),
                  ),
                ],
                if (_refreshing) ...[
                  const SizedBox(height: 12),
                  const LoadingSkeleton(
                    rows: 1,
                    rowHeight: 36,
                    label: 'Loading home activity',
                  ),
                ],
                if (myUpcoming.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _title(
                    'Your next match',
                    action: 'My matches',
                    onAction: () => openMatchTab(context, section: 3),
                  ),
                  const SizedBox(height: 12),
                  KeyedSubtree(
                    key: ValueKey('next-match-${myUpcoming.first.id}'),
                    child: _officialCard(context, official, myUpcoming.first),
                  ),
                ],
                if (liveNow.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _title(
                    'Live now',
                    action: 'Match center',
                    onAction: () => openMatchTab(context),
                  ),
                  const SizedBox(height: 12),
                  for (final match in liveNow)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _officialCard(context, official, match),
                    ),
                ],
                if (featured.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _title(
                    'Featured tournaments',
                    action: 'See all',
                    onAction: () => openHomeTab(context, 1),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth < 360
                          ? constraints.maxWidth - 16
                          : (constraints.maxWidth < 600
                                ? 310.0
                                : (constraints.maxWidth - 12) / 2);
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final tournament in featured.take(4))
                              Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: SizedBox(
                                  width: width,
                                  child: _discoverCard(context, tournament),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ] else if (tournaments.loading) ...[
                  const SizedBox(height: 28),
                  _title('Featured tournaments'),
                  const SizedBox(height: 12),
                  const LoadingSkeleton(
                    rows: 1,
                    rowHeight: 150,
                    label: 'Loading tournaments',
                  ),
                ] else if (tournaments.lastError != null) ...[
                  const SizedBox(height: 28),
                  _title('Featured tournaments'),
                  const SizedBox(height: 12),
                  ErrorState(
                    title: 'Couldn’t load tournaments',
                    message: tournaments.lastError,
                    compact: true,
                    onRetry: tournaments.refresh,
                  ),
                ],
                const SizedBox(height: 24),
                _title(
                  'Matches for you',
                  action: 'See all',
                  onAction: () => openMatchTab(context, section: 5),
                ),
                const SizedBox(height: 10),
                _sports(),
                const SizedBox(height: 12),
                for (final match in recommendations.take(2))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _discoveryMatch(context, match),
                  ),
                if (hasGames) _gameRail(context),
                if (games.lastError != null) ...[
                  const SizedBox(height: 10),
                  ErrorState(
                    title: 'Couldn’t load pickup games',
                    message: games.lastError,
                    compact: true,
                    onRetry: games.refresh,
                  ),
                ],
                if (!hasGames && recommendations.isEmpty)
                  AccountEmptyState(
                    title: 'Your next opportunity is ahead',
                    newcomerBody:
                        'Find a match or bring your own team together.',
                    playerBody: 'No open matches for this sport. Try another sport or create a match.',
                    icon: Icons.sports_outlined,
                    action: GhostButton(
                      label: 'Create Match',
                      icon: Icons.add,
                      onPressed: () => pushRoute(context, AppRoute.createMatch),
                    ),
                  ),

                // ── Updates ─────────────────────────────────────────────
                if (updateRail.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _title(
                    'Updates',
                    action: 'See all',
                    onAction: () => pushRoute(context, AppRoute.notifications),
                  ),
                  const SizedBox(height: 12),
                  Column(
                    children: [
                      for (
                        var index = 0;
                        index < updateRail.length;
                        index++
                      ) ...[
                        if (index > 0)
                          const Divider(
                            height: 1,
                            color: SportikaColors.borderSubtle,
                          ),
                        ActivityRow(notification: updateRail[index]),
                      ],
                    ],
                  ),
                ],

                // ── Activity ────────────────────────────────────────────
                const SizedBox(height: 28),
                _title('Your activity'),
                const SizedBox(height: 6),
                const Text(
                  'Your official match record, across all sports.',
                  style: SportikaType.caption,
                ),
                const SizedBox(height: 16),
                if (scoring.isNotEmpty) ...[
                  _surface(
                    child: Column(
                      children: [
                        for (final match in scoring.take(2))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.assignment_outlined,
                              color: SportikaColors.gold,
                            ),
                            title: Text(
                              match.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: const Text('Official scorer assignment'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => pushRoute(
                              context,
                              AppRoute.matchDetail,
                              args: MatchArgs(match.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                BrandMetricStrip(
                  compact: true,
                  metrics: [
                    (value: _pad(played.length), label: 'Played'),
                    (value: _pad(wins), label: 'Wins'),
                    (value: _pad(myUpcoming.length), label: 'Upcoming'),
                  ],
                ),
                if (breakdown.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _surface(
                    child: Column(
                      children: [
                        for (final entry in breakdown)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                SportGlyph(
                                  sport: entry.key,
                                  size: 16,
                                  color: sportColor(entry.key),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    entry.key.label,
                                    style: SportikaType.bodyStrong.copyWith(
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${entry.value.wins}W · '
                                  '${entry.value.played - entry.value.wins}L',
                                  style: SportikaType.caption,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (played.isEmpty && myUpcoming.isEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Every player starts somewhere. Join a match or a tournament to build your record.',
                    style: SportikaType.caption,
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- sports --

  Widget _sports() {
    return SizedBox(
      key: const ValueKey('home-sports-filter'),
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _sportChip(null, 'All', null),
          for (final sport in Sport.values)
            _sportChip(sport, sport.label, sport),
        ],
      ),
    );
  }

  Widget _sportChip(Sport? sport, String label, Sport? glyphSport) {
    final selected = _sport == sport;
    final tone = sport == null ? SportikaColors.blueBright : sportColor(sport);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: () => setState(() => _sport = sport),
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected
                  ? tone.withValues(alpha: 0.14)
                  : SportikaColors.surfaceSunken,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? tone : SportikaColors.border,
                width: selected ? 1.2 : 1,
              ),
            ),
            child: Semantics(
              selected: selected,
              button: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (glyphSport == null)
                    Icon(
                      Icons.apps_rounded,
                      size: 16,
                      color: selected ? tone : SportikaColors.textMuted,
                    )
                  else
                    SportGlyph(
                      sport: glyphSport,
                      size: 16,
                      color: selected ? tone : SportikaColors.textMuted,
                    ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .2,
                      color: selected ? tone : SportikaColors.textBody,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------- quick actions --

  /// Four direct actions, wrapping into two columns for smaller screens.
  Widget _quickActions(BuildContext context) {
    final actions = [
      (
        label: 'Create Match',
        icon: Icons.add_circle_outline_rounded,
        open: () => pushRoute(context, AppRoute.createMatch),
      ),
      (
        label: 'Find Match',
        icon: Icons.search_rounded,
        open: () => openMatchTab(context, section: 5),
      ),
      (
        label: 'Tournaments',
        icon: Icons.emoji_events_outlined,
        open: () => openHomeTab(context, 1),
      ),
      (
        label: 'My Teams',
        icon: Icons.groups_rounded,
        open: () => openHomeTab(context, 3),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth < 380 ||
                MediaQuery.textScalerOf(context).scale(12) > 16
            ? 2
            : 4;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final action in actions)
              SizedBox(
                width: width,
                child: Material(
                  color: SportikaColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: SportikaColors.borderSubtle),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: action.open,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 16,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            action.icon,
                            size: 22,
                            color: SportikaColors.mint,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            action.label,
                            textAlign: TextAlign.center,
                            style: SportikaType.caption.copyWith(
                              color: SportikaColors.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _discoveryMatch(BuildContext context, SportMatch match) {
    return _surface(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () =>
            pushRoute(context, AppRoute.matchDetail, args: MatchArgs(match.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SportPhoto(sport: match.sport, height: 200, radius: 0),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, SportikaColors.deepest],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 14,
                    left: 14,
                    child: _pill(
                      match.sport.label.toUpperCase(),
                      SportikaColors.deepest,
                      SportikaColors.mint,
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Text(
                      match.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SportikaType.title.copyWith(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${dayLabel(match.scheduledAt)} · ${timeLabel(match.scheduledAt)}',
                    style: SportikaType.bodyStrong,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    match.venue,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SportikaType.caption,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${match.capacity - match.acceptedCount} spots available',
                          style: SportikaType.caption.copyWith(
                            color: SportikaColors.mint,
                          ),
                        ),
                      ),
                      const Text('View match', style: SportikaType.label),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: SportikaColors.mint,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _officialCard(
    BuildContext context,
    MatchController state,
    SportMatch match,
  ) {
    final session = context.read<SessionController>();
    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SportGlyph(
                sport: match.sport,
                color: SportikaColors.mint,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${match.sport.label} · ${match.formatLabel}',
                  style: SportikaType.caption,
                ),
              ),
              _pill(
                match.isLive ? 'LIVE' : 'UPCOMING',
                SportikaColors.blueSubtle,
                match.isLive ? SportikaColors.mint : SportikaColors.gold,
              ),
            ],
          ),
          const SizedBox(height: 12),
          MatchScoreboard(
            sport: match.sport,
            labels: match.sideLabels,
            versus: true,
            progress: match.isLive ? state.progressOf(match) : null,
            players: [
              for (var side = 0; side < 2; side++)
                [
                  for (final p in match.participantsOnSide(side))
                    if (session.accountById(p.profileId) != null)
                      session.accountById(p.profileId)!,
                ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${dayLabel(match.scheduledAt)} · ${timeLabel(match.scheduledAt)} · ${match.venue}',
            style: SportikaType.caption,
          ),
          TextButton(
            onPressed: () => pushRoute(
              context,
              AppRoute.matchDetail,
              args: MatchArgs(match.id),
            ),
            child: Text(match.isLive ? 'Follow live →' : 'View match →'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- tournaments --

  Widget _discoverCard(BuildContext context, Tournament tournament) {
    final confirmed = context.read<TournamentsController>().confirmedCountFor(
      tournament,
    );
    final left = (tournament.registrationLimit - confirmed).clamp(0, 999);
    final banner = tournament.bannerUrl;

    return _surface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: banner == null || banner.isEmpty
                    ? SportPhoto(
                        sport: tournament.sport,
                        height: 150,
                        radius: 0,
                      )
                    : Image.network(
                        banner,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => SportPhoto(
                          sport: tournament.sport,
                          height: 150,
                          radius: 0,
                        ),
                      ),
              ),
              Positioned(
                left: 14,
                bottom: 12,
                child: ColoredBox(
                  color: SportikaColors.deepest.withValues(alpha: .82),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    child: Text(
                      tournament.sport.label.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              // Demo content is labelled, never passed off as a real event.
              if (tournament.isDemo)
                Positioned(
                  top: 10,
                  right: 10,
                  child: _pill(
                    'DEMO',
                    SportikaColors.gold,
                    SportikaColors.deepest,
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tournament.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Barlow Condensed',
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .2,
                          color: SportikaColors.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.people_alt_outlined,
                      size: 14,
                      color: left == 0
                          ? SportikaColors.textDim
                          : SportikaColors.mint,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      left == 0 ? 'Full' : '$left spots left',
                      style: TextStyle(
                        fontSize: 11,
                        color: left == 0
                            ? SportikaColors.textDim
                            : SportikaColors.mint,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${dayLabel(tournament.startsAt)} · ${timeLabel(tournament.startsAt)}'
                  ' · ${tournament.city}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: SportikaColors.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => pushRoute(
                      context,
                      AppRoute.tournamentDetail,
                      args: TournamentDetailArgs(tournament.id),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SportikaColors.mint,
                      side: const BorderSide(
                        color: SportikaColors.borderStrong,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'View tournament',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ games rail --

  /// Horizontal, image-backed discovery cards - photography first, one line
  /// of condensed title and the availability state.
  Widget _gameRail(BuildContext context) {
    final games =
        context
            .read<GamesController>()
            .games
            .where(
              (g) =>
                  g.visibility == 'Public' &&
                  !g.full &&
                  !g.at.isBefore(DateTime.now()) &&
                  (_sport == null || g.sport == _sport),
            )
            .toList()
          ..sort((a, b) {
            final me = context.read<ProfileController>().currentAccount!;
            final rank = (me.sports.contains(b.sport) ? 1 : 0).compareTo(
              me.sports.contains(a.sport) ? 1 : 0,
            );
            return rank != 0 ? rank : a.at.compareTo(b.at);
          });
    if (games.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 216,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: games.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final game = games[i];
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => pushRoute(
              context,
              AppRoute.gameDetail,
              args: GameDetailArgs(game),
            ),
            child: SizedBox(
              width: 240,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SportPhoto(sport: game.sport, height: 216, radius: 16),
                  // Bottom scrim only under the type block.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 140,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(16),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            SportikaColors.deepest.withValues(alpha: .92),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: ColoredBox(
                      color: SportikaColors.deepest.withValues(alpha: .82),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SportGlyph(
                              sport: game.sport,
                              size: 13,
                              color: sportColor(game.sport),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              game.sport.label.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 8.5,
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (game.full
                                    ? SportikaColors.gold
                                    : SportikaColors.mint)
                                .withValues(alpha: .92),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        game.full ? 'FULL' : 'OPEN',
                        style: const TextStyle(
                          color: SportikaColors.deepest,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .8,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          game.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Barlow Condensed',
                            fontSize: 19,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${game.venue} · ${dayLabel(game.at)} '
                          '${timeLabel(game.at)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: SportikaColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------- others --

  // ------------------------------------------------------------- primitives --

  Widget _title(String title, {String? action, VoidCallback? onAction}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: .1,
              color: SportikaColors.text,
            ),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(48, 44),
            ),
            child: Text(
              action,
              style: const TextStyle(
                color: SportikaColors.blue,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
      ],
    );
  }

  Widget _pill(String text, Color background, Color foreground) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 9,
        color: foreground,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.7,
      ),
    ),
  );

  Widget _surface({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(18),
  }) => Material(
    color: SportikaColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: SportikaColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );

  String _pad(int value) => value.toString().padLeft(2, '0');
}

String greeting(String name) {
  final hour = DateTime.now().hour;
  final salutation = hour < 12
      ? 'Good morning'
      : hour < 17
      ? 'Good afternoon'
      : 'Good evening';
  return '$salutation, $name';
}
