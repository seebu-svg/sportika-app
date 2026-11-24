import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/games_controller.dart';
import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/features/home/widgets/home_header.dart';
import 'package:sportika/features/home/widgets/role_empty_state.dart';
import 'package:sportika/shared/models/community_game.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/match_scoreboard.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Sportika Athlete Command Center.
///
/// Content hierarchy:
/// 1. Cinematic welcome
/// 2. Primary and secondary actions
/// 3. Athlete snapshot
/// 4. Upcoming match
/// 5. Live matches
/// 6. Match discovery
/// 7. Featured tournaments
/// 8. Official scoring and activity
/// 9. Notifications
///
/// All personal statistics remain account-wide.
/// The selected sport filters discovery only.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  Sport? _sport;

  bool _refreshing = false;
  bool _refreshFailed = false;

  MatchController? _matches;

  @override
  void initState() {
    super.initState();

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
    _matches?.unwatchAllMatches();
    super.dispose();
  }

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

      if (mounted) {
        setState(() {
          _refreshFailed = _anySourceFailed(context);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _refreshFailed = true);
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  static bool _anySourceFailed(BuildContext context) {
    return context.read<MatchController>().lastError != null ||
        context.read<TournamentsController>().lastError != null ||
        context.read<FixturesController>().lastError != null ||
        context.read<GamesController>().lastError != null ||
        context.read<TeamsController>().lastError != null ||
        context.read<NotificationsController>().error != null;
  }

  double _pagePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final contentWidth = SportikaSpacing.xl * 22.5;
    final gutter = SportikaSpacing.md;

    return width > contentWidth + gutter * 2
        ? (width - contentWidth) / 2
        : gutter;
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<ProfileController>().currentAccount;
    final official = context.watch<MatchController>();
    final tournaments = context.watch<TournamentsController>();
    final gamesController = context.watch<GamesController>();
    final inbox = context.watch<NotificationsController>();

    if (me == null) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now();

    bool won(SportMatch match) {
      final side = match.participantOf(me.id)?.side;
      final winner = match.result?.winnerIndex;

      return side != null && winner != null && winner >= 0 && winner == side;
    }

    final mine = official.myMatches
        .where((match) => match.isParticipant(me.id))
        .toList();

    final myUpcoming =
        mine
            .where(
              (match) =>
                  match.status == FixtureStatus.upcoming &&
                  !match.scheduledAt.isBefore(now),
            )
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    final liveNow = official.liveMatches.take(2).toList();

    final scoring = official.myScoringMatches
        .where((match) => match.scorerId == me.id)
        .toList();

    final featured =
        tournaments.liveTournaments
            .where(
              (tournament) =>
                  tournament.status == TournamentStatus.open &&
                  !tournament.startsAt.isBefore(now),
            )
            .toList()
          ..sort((a, b) {
            int relevance(Tournament tournament) {
              return (me.sports.contains(tournament.sport) ? 2 : 0) +
                  (tournament.city.toLowerCase() == me.city.toLowerCase()
                      ? 1
                      : 0);
            }

            final rank = relevance(b).compareTo(relevance(a));

            return rank != 0 ? rank : a.startsAt.compareTo(b.startsAt);
          });

    final recommendations =
        official.discoverableMatches
            .where(
              (match) =>
                  match.tournamentId == null &&
                  match.status == FixtureStatus.upcoming &&
                  !match.scheduledAt.isBefore(now) &&
                  match.acceptedCount < match.capacity &&
                  (_sport == null || match.sport == _sport),
            )
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    final openGames =
        gamesController.games
            .where(
              (game) =>
                  game.visibility == 'Public' &&
                  !game.full &&
                  !game.at.isBefore(now) &&
                  (_sport == null || game.sport == _sport),
            )
            .toList()
          ..sort((a, b) {
            final rank = (me.sports.contains(b.sport) ? 1 : 0).compareTo(
              me.sports.contains(a.sport) ? 1 : 0,
            );

            return rank != 0 ? rank : a.at.compareTo(b.at);
          });

    final updateRail = inbox.myNotifications
        .where((notification) => !notification.read)
        .take(3)
        .toList();

    final played = mine
        .where((match) => match.status == FixtureStatus.published)
        .toList();

    final wins = played.where(won).length;

    final bySport = <Sport, ({int played, int wins})>{};

    for (final match in played) {
      final current = bySport[match.sport] ?? (played: 0, wins: 0);

      bySport[match.sport] = (
        played: current.played + 1,
        wins: current.wins + (won(match) ? 1 : 0),
      );
    }

    final breakdown = bySport.entries.toList()
      ..sort((a, b) => b.value.played.compareTo(a.value.played));

    final name = me.displayName.trim();
    final firstName = name.isEmpty
        ? 'Athlete'
        : name.split(RegExp(r'\s+')).first;

    final page = _pagePadding(context);

    return RefreshIndicator(
      onRefresh: _refresh,
      color: SportikaColors.mint,
      backgroundColor: SportikaColors.surface,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ----------------------------------------
          // 1. CINEMATIC WELCOME
          // ----------------------------------------

          SliverToBoxAdapter(
            child: HomeGreeting(
              sport: me.sports.firstOrNull ?? Sport.cricket,
              title: "Let's play, $firstName.",
              supporting: myUpcoming.isNotEmpty
                  ? 'Your next match is waiting. Make it count.'
                  : liveNow.isNotEmpty
                  ? 'The action is live. Stay in the game.'
                  : 'Find your next challenge. Make every game count.',
              pagePadding: page,
            ),
          ),

          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              page,
              SportikaSpacing.lg,
              page,
              SportikaSpacing.xxl,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ----------------------------------
                // 2. QUICK ACTIONS
                // ----------------------------------

                _sectionTitle(context, 'Make your move'),
                const SizedBox(height: SportikaSpacing.sm),

                _quickActions(context),

                // ----------------------------------
                // REFRESH STATUS
                // ----------------------------------
                if (_refreshFailed) ...[
                  const SizedBox(height: SportikaSpacing.md),
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
                  const SizedBox(height: SportikaSpacing.md),
                  const LoadingSkeleton(
                    rows: 1,
                    rowHeight: 36,
                    label: 'Loading home activity',
                  ),
                ],

                // ----------------------------------
                // 3. ATHLETE SNAPSHOT
                // ----------------------------------
                const SizedBox(height: SportikaSpacing.xl),

                _sectionTitle(
                  context,
                  'Your arena',
                  subtitle: 'Your official match record',
                ),

                const SizedBox(height: SportikaSpacing.md),

                BrandMetricStrip(
                  compact: true,
                  metrics: [
                    (value: _pad(played.length), label: 'Played'),
                    (value: _pad(wins), label: 'Wins'),
                    (value: _pad(myUpcoming.length), label: 'Upcoming'),
                  ],
                ),

                // ----------------------------------
                // 4. YOUR NEXT MATCH
                // ----------------------------------
                if (myUpcoming.isNotEmpty) ...[
                  const SizedBox(height: SportikaSpacing.xl),

                  _sectionTitle(
                    context,
                    'Next up',
                    action: 'My matches',
                    onAction: () => openMatchTab(context, section: 3),
                  ),

                  const SizedBox(height: SportikaSpacing.md),

                  KeyedSubtree(
                    key: ValueKey('next-match-${myUpcoming.first.id}'),
                    child: _officialCard(context, official, myUpcoming.first),
                  ),
                ],

                // ----------------------------------
                // 5. LIVE MATCH CENTER
                // ----------------------------------
                if (liveNow.isNotEmpty) ...[
                  const SizedBox(height: SportikaSpacing.xl),

                  _sectionTitle(
                    context,
                    'Live now',
                    icon: Icons.sensors_rounded,
                    accent: SportikaColors.mint,
                    action: 'Match center',
                    onAction: () => openMatchTab(context),
                  ),

                  const SizedBox(height: SportikaSpacing.md),

                  for (final match in liveNow)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: SportikaSpacing.sm,
                      ),
                      child: _officialCard(context, official, match),
                    ),
                ],

                // ----------------------------------
                // 6. DISCOVER MATCHES
                // ----------------------------------
                const SizedBox(height: SportikaSpacing.xl),

                _sectionTitle(
                  context,
                  'Discover matches',
                  subtitle: 'Find your next sporting challenge',
                  action: 'See all',
                  onAction: () => openMatchTab(context, section: 5),
                ),

                const SizedBox(height: SportikaSpacing.md),

                _sports(),

                const SizedBox(height: SportikaSpacing.md),

                for (final match in recommendations.take(2))
                  Padding(
                    padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
                    child: _discoveryMatch(context, match),
                  ),

                if (openGames.isNotEmpty) _gameRail(context, openGames),

                if (gamesController.lastError != null) ...[
                  const SizedBox(height: SportikaSpacing.sm),
                  ErrorState(
                    title: 'Couldn’t load pickup games',
                    message: gamesController.lastError,
                    compact: true,
                    onRetry: gamesController.refresh,
                  ),
                ],

                if (openGames.isEmpty &&
                    recommendations.isEmpty &&
                    gamesController.lastError == null)
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

                // ----------------------------------
                // 7. FEATURED TOURNAMENTS
                // ----------------------------------
                if (featured.isNotEmpty) ...[
                  const SizedBox(height: SportikaSpacing.xl),

                  _sectionTitle(
                    context,
                    'Featured tournaments',
                    subtitle: 'Compete beyond the everyday',
                    action: 'See all',
                    onAction: () =>
                        openHomeTab(context, HomeTabIndex.tournaments),
                  ),

                  const SizedBox(height: SportikaSpacing.md),

                  LayoutBuilder(
                    builder: (context, constraints) {
                      final available = constraints.maxWidth;

                      final cardWidth = available < SportikaSpacing.xl * 11
                          ? available
                          : available < SportikaSpacing.xl * 19
                          ? SportikaSpacing.xl * 9.5
                          : (available - SportikaSpacing.sm) / 2;

                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final tournament in featured.take(4))
                              Padding(
                                padding: const EdgeInsets.only(
                                  right: SportikaSpacing.sm,
                                ),
                                child: SizedBox(
                                  width: cardWidth,
                                  child: _discoverCard(context, tournament),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ] else if (tournaments.loading) ...[
                  const SizedBox(height: SportikaSpacing.xl),
                  _sectionTitle(context, 'Featured tournaments'),
                  const SizedBox(height: SportikaSpacing.md),
                  const LoadingSkeleton(
                    rows: 1,
                    rowHeight: 150,
                    label: 'Loading tournaments',
                  ),
                ] else if (tournaments.lastError != null) ...[
                  const SizedBox(height: SportikaSpacing.xl),
                  _sectionTitle(context, 'Featured tournaments'),
                  const SizedBox(height: SportikaSpacing.md),
                  ErrorState(
                    title: 'Couldn’t load tournaments',
                    message: tournaments.lastError,
                    compact: true,
                    onRetry: tournaments.refresh,
                  ),
                ],

                // ----------------------------------
                // 8. OFFICIAL ACTIVITY
                // ----------------------------------
                if (scoring.isNotEmpty ||
                    breakdown.isNotEmpty ||
                    (played.isEmpty && myUpcoming.isEmpty)) ...[
                  const SizedBox(height: SportikaSpacing.xl),

                  _sectionTitle(
                    context,
                    'Your activity',
                    subtitle: 'Your participation across all sports',
                  ),

                  const SizedBox(height: SportikaSpacing.md),

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
                              subtitle: const Text(
                                'Official scorer assignment',
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => pushRoute(
                                context,
                                AppRoute.matchDetail,
                                args: MatchArgs(match.id),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: SportikaSpacing.sm),
                  ],

                  if (breakdown.isNotEmpty)
                    _surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SPORTS BREAKDOWN',
                            style: SportikaType.label.copyWith(
                              color: SportikaColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: SportikaSpacing.md),
                          for (final entry in breakdown)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: SportikaSpacing.md,
                              ),
                              child: TrailingRow(
                                leading: [
                                  SportGlyph(
                                    sport: entry.key,
                                    size: SportikaIconSize.lg,
                                    color: sportColor(entry.key),
                                  ),
                                  const SizedBox(width: SportikaSpacing.sm),
                                  FittedFlex(
                                    expand: true,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      entry.key.label,
                                      maxLines: 1,
                                      style: SportikaType.bodyStrong,
                                    ),
                                  ),
                                ],
                                trailing: [
                                  Text(
                                    '${entry.value.played} played',
                                    style: SportikaType.caption,
                                  ),
                                  const SizedBox(width: SportikaSpacing.sm),
                                  Text(
                                    '${entry.value.wins} wins',
                                    style: SportikaType.bodyStrong.copyWith(
                                      color: SportikaColors.mint,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                  if (played.isEmpty && myUpcoming.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: SportikaSpacing.sm),
                      child: Text(
                        'Join a match or tournament to start building your official match record.',
                        style: SportikaType.caption,
                      ),
                    ),
                ],

                // ----------------------------------
                // 9. NOTIFICATIONS
                // ----------------------------------
                if (updateRail.isNotEmpty) ...[
                  const SizedBox(height: SportikaSpacing.xl),

                  _sectionTitle(
                    context,
                    'Latest updates',
                    action: 'See all',
                    onAction: () => pushRoute(context, AppRoute.notifications),
                  ),

                  const SizedBox(height: SportikaSpacing.md),

                  _surface(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SportikaSpacing.md,
                    ),
                    child: Column(
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
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SECTION HEADINGS
  // ============================================================

  Widget _sectionTitle(
    BuildContext context,
    String title, {
    String? subtitle,
    String? action,
    VoidCallback? onAction,
    IconData? icon,
    Color? accent,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrailingRow(
          leading: [
            if (icon != null) ...[
              Icon(
                icon,
                color: accent ?? SportikaColors.mint,
                size: SportikaIconSize.lg,
              ),
              const SizedBox(width: SportikaSpacing.sm),
            ],
            FittedFlex(
              expand: true,
              alignment: Alignment.centerLeft,
              child: Text(title, maxLines: 1, style: SportikaType.titleMedium),
            ),
          ],
          trailing: [
            if (action != null)
              TextButton(
                onPressed: onAction,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(action),
                    const SizedBox(width: SportikaSpacing.xs),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: SportikaIconSize.sm,
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (subtitle != null) Text(subtitle, style: SportikaType.caption),
      ],
    );
  }

  // ============================================================
  // QUICK ACTIONS
  // ============================================================

  Widget _quickActions(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _QuickActionCard(
                title: 'Find Match',
                description: 'Discover standalone matches',
                icon: Icons.manage_search_rounded,
                accent: SportikaColors.blueBright,
                primary: true,
                onTap: () => openMatchTab(context, section: 5),
              ),
            ),
            const SizedBox(width: SportikaSpacing.sm),
            Expanded(
              child: _QuickActionCard(
                title: 'Create Match',
                description: 'Start your next game',
                icon: Icons.add_circle_outline_rounded,
                accent: SportikaColors.mint,
                onTap: () => pushRoute(context, AppRoute.createMatch),
              ),
            ),
          ],
        ),
        const SizedBox(height: SportikaSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _QuickShortcut(
                label: 'Tournaments',
                icon: Icons.emoji_events_outlined,
                accent: SportikaColors.gold,
                onTap: () => openHomeTab(context, HomeTabIndex.tournaments),
              ),
            ),
            const SizedBox(width: SportikaSpacing.sm),
            Expanded(
              child: _QuickShortcut(
                label: 'My Teams',
                icon: Icons.groups_outlined,
                accent: SportikaColors.mint,
                onTap: () => openHomeTab(context, HomeTabIndex.teams),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // SPORT FILTER
  // ============================================================

  Widget _sports() {
    return SizedBox(
      key: const ValueKey('home-sports-filter'),
      height: SportikaSpacing.xl + SportikaSpacing.sm,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _sportChip(null, 'All'),
          for (final sport in Sport.values) _sportChip(sport, sport.label),
        ],
      ),
    );
  }

  Widget _sportChip(Sport? sport, String label) {
    final selected = _sport == sport;
    final tone = sport == null ? SportikaColors.blueBright : sportColor(sport);

    return Padding(
      padding: const EdgeInsets.only(right: SportikaSpacing.sm),
      child: Material(
        color: SportikaColors.transparent,
        borderRadius: BorderRadius.circular(SportikaRadius.pill),
        child: InkWell(
          onTap: () => setState(() => _sport = sport),
          borderRadius: BorderRadius.circular(SportikaRadius.pill),
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: SportikaSpacing.md),
            decoration: BoxDecoration(
              color: selected
                  ? tone.withValues(alpha: SportikaOpacity.muted)
                  : SportikaColors.surfaceSunken,
              borderRadius: BorderRadius.circular(SportikaRadius.pill),
              border: Border.all(
                color: selected ? tone : SportikaColors.border,
              ),
            ),
            child: Semantics(
              button: true,
              selected: selected,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (sport == null)
                    Icon(
                      Icons.apps_rounded,
                      size: SportikaIconSize.sm,
                      color: selected ? tone : SportikaColors.textMuted,
                    )
                  else
                    SportGlyph(
                      sport: sport,
                      size: SportikaIconSize.sm,
                      color: selected ? tone : SportikaColors.textMuted,
                    ),
                  const SizedBox(width: SportikaSpacing.xs),
                  Text(
                    label,
                    style: SportikaType.label.copyWith(
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

  // ============================================================
  // OFFICIAL MATCH SCOREBOARD
  // ============================================================

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
          TrailingRow(
            maxFraction: 0.5,
            leading: [
              SportGlyph(
                sport: match.sport,
                color: sportColor(match.sport),
                size: SportikaIconSize.lg,
              ),
              const SizedBox(width: SportikaSpacing.sm),
              FittedFlex(
                expand: true,
                alignment: Alignment.centerLeft,
                child: Text(
                  '${match.sport.label} · ${match.formatLabel}',
                  maxLines: 1,
                  style: SportikaType.label,
                ),
              ),
            ],
            trailing: [
              _pill(
                match.isLive ? 'LIVE' : 'UPCOMING',
                SportikaColors.blueSubtle,
                match.isLive ? SportikaColors.mint : SportikaColors.gold,
              ),
            ],
          ),

          const SizedBox(height: SportikaSpacing.md),

          MatchScoreboard(
            sport: match.sport,
            labels: match.sideLabels,
            versus: true,
            progress: match.isLive ? state.progressOf(match) : null,
            players: [
              for (var side = 0; side < 2; side++)
                [
                  for (final participant in match.participantsOnSide(side))
                    if (session.accountById(participant.profileId) != null)
                      session.accountById(participant.profileId)!,
                ],
            ],
          ),

          const SizedBox(height: SportikaSpacing.sm),

          const Divider(color: SportikaColors.borderSubtle),

          Text(
            '${dayLabel(match.scheduledAt)} · '
            '${timeLabel(match.scheduledAt)} · '
            '${match.venue}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SportikaType.caption,
          ),

          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => pushRoute(
                context,
                AppRoute.matchDetail,
                args: MatchArgs(match.id),
              ),
              iconAlignment: IconAlignment.end,
              icon: const Icon(
                Icons.arrow_forward_rounded,
                size: SportikaIconSize.sm,
              ),
              label: Text(match.isLive ? 'Follow live' : 'View match'),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DISCOVERY MATCH CARD
  // ============================================================

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
              aspectRatio: 16 / 7,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SportPhoto(sport: match.sport, height: 200, radius: 0),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: SportikaGradients.imageFadeStrong,
                    ),
                  ),
                  Positioned(
                    top: SportikaSpacing.md,
                    left: SportikaSpacing.md,
                    child: _pill(
                      match.sport.label.toUpperCase(),
                      SportikaColors.deepest,
                      SportikaColors.mint,
                    ),
                  ),
                  Positioned(
                    left: SportikaSpacing.md,
                    right: SportikaSpacing.md,
                    bottom: SportikaSpacing.md,
                    child: Text(
                      match.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SportikaType.cardTitle.copyWith(
                        color: SportikaColors.onAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(SportikaSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${dayLabel(match.scheduledAt)} · '
                    '${timeLabel(match.scheduledAt)}',
                    style: SportikaType.bodyStrong,
                  ),
                  const SizedBox(height: SportikaSpacing.xs),
                  Text(
                    match.venue,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SportikaType.caption,
                  ),
                  const SizedBox(height: SportikaSpacing.md),
                  TrailingRow(
                    leading: [
                      FittedFlex(
                        expand: true,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${match.capacity - match.acceptedCount} spots available',
                          maxLines: 1,
                          style: SportikaType.caption.copyWith(
                            color: SportikaColors.mint,
                          ),
                        ),
                      ),
                    ],
                    trailing: const [
                      Text('View match', style: SportikaType.label),
                      SizedBox(width: SportikaSpacing.xs),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: SportikaIconSize.sm,
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

  // ============================================================
  // FEATURED TOURNAMENT CARD
  // ============================================================

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
                left: SportikaSpacing.sm,
                bottom: SportikaSpacing.sm,
                child: _pill(
                  tournament.sport.label.toUpperCase(),
                  SportikaColors.deepest,
                  SportikaColors.mint,
                ),
              ),
              if (tournament.isDemo)
                Positioned(
                  top: SportikaSpacing.sm,
                  right: SportikaSpacing.sm,
                  child: _pill(
                    'DEMO',
                    SportikaColors.gold,
                    SportikaColors.deepest,
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(SportikaSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tournament.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.cardTitle,
                ),
                const SizedBox(height: SportikaSpacing.xs),
                Text(
                  '${dayLabel(tournament.startsAt)} · '
                  '${timeLabel(tournament.startsAt)} · '
                  '${tournament.city}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.caption,
                ),
                const SizedBox(height: SportikaSpacing.sm),
                Text(
                  left == 0 ? 'Registration full' : '$left spots left',
                  style: SportikaType.label.copyWith(
                    color: left == 0
                        ? SportikaColors.textMuted
                        : SportikaColors.mint,
                  ),
                ),
                const SizedBox(height: SportikaSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => pushRoute(
                      context,
                      AppRoute.tournamentDetail,
                      args: TournamentDetailArgs(tournament.id),
                    ),
                    child: const Text('View tournament'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PICKUP GAME RAIL
  // ============================================================

  Widget _gameRail(BuildContext context, List<CommunityGame> openGames) {
    if (openGames.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: SportikaSpacing.xl * 6.75,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: openGames.length,
        separatorBuilder: (_, _) => const SizedBox(width: SportikaSpacing.sm),
        itemBuilder: (context, index) {
          final game = openGames[index];

          return SizedBox(
            width: SportikaSpacing.xl * 7.5,
            child: Material(
              color: SportikaColors.surface,
              borderRadius: BorderRadius.circular(SportikaRadius.thumbnail),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => pushRoute(
                  context,
                  AppRoute.gameDetail,
                  args: GameDetailArgs(game),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SportPhoto(
                      sport: game.sport,
                      height: SportikaSpacing.xl * 6.75,
                      radius: 0,
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: SportikaGradients.imageFadeStrong,
                      ),
                    ),
                    Positioned(
                      top: SportikaSpacing.sm,
                      left: SportikaSpacing.sm,
                      child: _pill(
                        game.sport.label.toUpperCase(),
                        SportikaColors.deepest,
                        sportColor(game.sport),
                      ),
                    ),
                    Positioned(
                      top: SportikaSpacing.sm,
                      right: SportikaSpacing.sm,
                      child: _pill(
                        'OPEN',
                        SportikaColors.mint,
                        SportikaColors.deepest,
                      ),
                    ),
                    Positioned(
                      left: SportikaSpacing.md,
                      right: SportikaSpacing.md,
                      bottom: SportikaSpacing.md,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            game.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: SportikaType.cardTitle.copyWith(
                              color: SportikaColors.onAccent,
                            ),
                          ),
                          const SizedBox(height: SportikaSpacing.xs),
                          Text(
                            '${game.venue} · '
                            '${dayLabel(game.at)} '
                            '${timeLabel(game.at)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: SportikaType.caption.copyWith(
                              color: SportikaColors.onAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // SHARED VISUAL PRIMITIVES
  // ============================================================

  Widget _pill(String text, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SportikaSpacing.sm,
        vertical: SportikaSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(SportikaRadius.xs),
      ),
      child: Text(text, style: SportikaType.label.copyWith(color: foreground)),
    );
  }

  Widget _surface({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(SportikaSpacing.md),
  }) {
    return Material(
      color: SportikaColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SportikaRadius.lg),
        side: const BorderSide(color: SportikaColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }

  String _pad(int value) {
    return value.toString().padLeft(2, '0');
  }
}

// ============================================================
// PRIMARY QUICK ACTION
// ============================================================

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.primary = false,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(SportikaRadius.card);

    return Material(
      color: primary ? SportikaColors.blue : SportikaColors.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: primary ? null : SportikaGradients.sportPanel,
          borderRadius: radius,
          border: Border.all(
            color: primary ? SportikaColors.blueBright : SportikaColors.border,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(SportikaSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    FittedFlex(
                      alignment: Alignment.centerLeft,
                      child: Icon(
                        icon,
                        size: SportikaIconSize.xl,
                        color: primary ? SportikaColors.onAccent : accent,
                      ),
                    ),
                    FittedFlex(
                      alignment: Alignment.centerRight,
                      child: Icon(
                        Icons.arrow_outward_rounded,
                        size: SportikaIconSize.sm,
                        color: primary
                            ? SportikaColors.onAccent
                            : SportikaColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: SportikaSpacing.lg),
                Text(
                  title,
                  style: SportikaType.bodyStrong.copyWith(
                    color: primary
                        ? SportikaColors.onAccent
                        : SportikaColors.text,
                  ),
                ),
                const SizedBox(height: SportikaSpacing.xs),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.caption.copyWith(
                    color: primary
                        ? SportikaColors.onAccent
                        : SportikaColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SECONDARY QUICK SHORTCUT
// ============================================================

class _QuickShortcut extends StatelessWidget {
  const _QuickShortcut({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SportikaColors.surface,
      borderRadius: BorderRadius.circular(SportikaRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SportikaSpacing.sm,
            vertical: SportikaSpacing.md,
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: SportikaIconSize.lg),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.label,
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: SportikaIconSize.sm,
                color: SportikaColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Retained for compatibility with existing Home imports.
String greeting(String name) {
  final hour = DateTime.now().hour;

  final salutation = hour < 12
      ? 'Good morning'
      : hour < 17
      ? 'Good afternoon'
      : 'Good evening';

  return '$salutation, $name';
}
