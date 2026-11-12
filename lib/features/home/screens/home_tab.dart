import 'package:sportika/shared/widgets/editorial.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/games_controller.dart';
import 'package:sportika/core/state/personal_games_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/shared/widgets/fixture_tile.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/home/widgets/home_header.dart';
import 'package:sportika/features/home/widgets/role_empty_state.dart';

/// Home and discovery (spec §5): greet the player, filter by sport, resume a
/// private card, follow live matches, see your own fixtures and find a
/// tournament to join.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  /// Null means "All sports" - the selector above the cards drives every
  /// fixture and tournament list on this tab.
  Sport? _sport;

  /// One horizontal rhythm for the whole tab: 20 on phones, centred 720
  /// column on tablets and desktop so nothing stretches edge to edge.
  double _pagePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width > 760 ? (width - 720) / 2 : 20;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FixturesController>();
    final me = context.read<ProfileController>().currentAccount;
    if (me == null) return const SizedBox.shrink();

    bool inSport(Fixture f) =>
        _sport == null || state.tournamentOf(f)?.sport == _sport;

    final resume = context.read<PersonalGamesController>().myPersonalInProgress;
    final upcoming = state.myFixtures
        .where((f) => f.status == FixtureStatus.upcoming && inSport(f))
        .take(2)
        .toList();
    final live = state.liveFixtures.where(inSport).take(2).toList();
    final discover = context
        .read<TournamentsController>()
        .liveTournaments
        .where(
          (t) =>
              (t.status == TournamentStatus.open ||
                  t.status == TournamentStatus.inProgress) &&
              (_sport == null || t.sport == _sport),
        )
        .take(2)
        .toList();

    final official = state.myFixtures;
    final wins = official.where((f) {
      final result = f.result;
      if (result == null) return false;
      return result.winnerIndex == _mySide(state, f);
    }).length;
    final scheduled = official
        .where((f) => f.status == FixtureStatus.upcoming)
        .length;

    final tools = [
      if (context.read<SessionController>().canOrganize)
        (
          icon: Icons.dashboard_customize_outlined,
          title: 'Organizer dashboard',
          subtitle: 'Entries, draws, results to review',
          tone: SportikaColors.mint,
          open: () => pushRoute(context, AppRoute.organizerDashboard),
        ),
      if (context.read<SessionController>().hasRole(UserRole.scorer))
        (
          icon: Icons.sports_score,
          title: 'Scorer workspace',
          subtitle: 'Fixtures assigned to you',
          tone: SportikaColors.blueBright,
          open: () => pushRoute(context, AppRoute.scorerWorkspace),
        ),
    ];

    final page = _pagePadding(context);

    return RefreshIndicator(
      onRefresh: () => context.read<SessionController>().reload(),
      color: SportikaColors.mint,
      backgroundColor: SportikaColors.surface,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: HomeHeader(account: me, pagePadding: page),
          ),
          // Full-bleed photographic hero, outside the content padding.
          SliverToBoxAdapter(
            child: HomeHero(sport: _sport, pagePadding: page),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(page, 22, page, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                BrandMetricStrip(
                  metrics: [
                    (
                      value: _pad(
                        context
                            .read<ProfileController>()
                            .officialMatchesPlayed()
                            .length,
                      ),
                      label: 'Matches played',
                    ),
                    (value: _pad(wins), label: 'Victories'),
                    (value: _pad(scheduled), label: 'Coming up'),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'FICTIONAL DEMO · KARACHI COMMUNITY',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.4,
                    color: SportikaColors.textMuted,
                  ),
                ),
                const SizedBox(height: 30),
                _title(
                  'Your sports',
                  action: 'My teams',
                  onAction: () => openHomeTab(context, 3),
                ),
                const SizedBox(height: 12),
                _sports(),
                const SizedBox(height: 30),
                _title('Quick actions'),
                const SizedBox(height: 12),
                _quickActions(context),
                if (resume.isNotEmpty) ...[
                  const SizedBox(height: 30),
                  _title(
                    'Continue scoring',
                    action: 'All cards',
                    onAction: () => pushRoute(context, AppRoute.matchHistory),
                  ),
                  const SizedBox(height: 12),
                  for (final match in resume.take(2))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: const Border(
                            left: BorderSide(
                              color: SportikaColors.mint,
                              width: 3,
                            ),
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.play_circle_outline,
                                    size: 18,
                                    color: SportikaColors.mint,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'RESUME YOUR SCORECARD',
                                        maxLines: 1,
                                        softWrap: false,
                                        style: TextStyle(
                                          fontSize: 10,
                                          letterSpacing: 1.2,
                                          fontWeight: FontWeight.w800,
                                          color: SportikaColors.mint,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            personalScorecardTile(context, match),
                          ],
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 30),
                _title(
                  'Upcoming match',
                  action: 'My matches',
                  onAction: () => pushRoute(context, AppRoute.matchHistory),
                ),
                const SizedBox(height: 12),
                if (upcoming.isEmpty)
                  RoleAwareEmpty(
                    title: 'Nothing scheduled yet',
                    newcomerBody: 'Enter your first tournament and your fixtures appear here.',
                    playerBody: 'Enter a tournament and your fixtures will show up here.',
                    organizerBody: 'Your draw has no upcoming fixtures. Generate a draw from the organizer dashboard.',
                    icon: Icons.event_available,
                    action: GhostButton(
                      label: 'Browse tournaments',
                      icon: Icons.emoji_events_outlined,
                      onPressed: () => openHomeTab(context, 1),
                    ),
                  )
                else
                  for (final fixture in upcoming)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _upcomingMatch(context, state, fixture),
                    ),
                const SizedBox(height: 30),
                _title(
                  'Live now',
                  action: 'Match center',
                  onAction: () => openHomeTab(context, 2),
                ),
                const SizedBox(height: 12),
                if (live.isEmpty)
                  const RoleAwareEmpty(
                    title: 'No live fixtures',
                    newcomerBody: 'Pick a sport and follow live scores once matches start.',
                    playerBody: 'Scheduled matches appear here as soon as a scorer starts them.',
                    organizerBody: 'No fixture is being scored right now. Assign a scorer to start one.',
                    icon: Icons.sensors_off,
                  )
                else
                  for (final fixture in live)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _liveScore(context, state, fixture),
                    ),
                const SizedBox(height: 30),
                _title(
                  'Upcoming tournaments',
                  action: 'Explore',
                  onAction: () => openHomeTab(context, 1),
                ),
                const SizedBox(height: 12),
                if (discover.isEmpty)
                  const RoleAwareEmpty(
                    title: 'No open tournaments',
                    newcomerBody: 'New events appear here as soon as organizers publish them.',
                    playerBody: 'Nothing open right now. Check back after the next draw.',
                    organizerBody: 'You have no published events. Publish one from the organizer dashboard.',
                    icon: Icons.emoji_events_outlined,
                  )
                else
                  for (final tournament in discover)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _discoverCard(context, state, tournament),
                    ),
                const SizedBox(height: 30),
                _title(
                  'Discover games near you',
                  action: 'See all',
                  onAction: () => openHomeTab(context, 1),
                ),
                const SizedBox(height: 12),
                if (!context.read<GamesController>().games.any(
                  (g) => _sport == null || g.sport == _sport,
                ))
                  const EmptyState(
                    title: 'Find your next game',
                    body: 'New community games will appear here.',
                    icon: Icons.sports_outlined,
                  ),
                _gameRail(context, state),
                const SizedBox(height: 30),
                _title(
                  'Recent activity',
                  action: 'View all',
                  onAction: () => pushRoute(context, AppRoute.notifications),
                ),
                const SizedBox(height: 12),
                if (context
                    .read<NotificationsController>()
                    .myNotifications
                    .isEmpty)
                  const EmptyState(
                    title: 'You’re all caught up',
                    body: 'Match updates and community news will appear here.',
                    icon: Icons.check_circle_outline,
                  ),
                for (final notification
                    in context
                        .read<NotificationsController>()
                        .myNotifications
                        .take(3))
                  ActivityRow(notification: notification),
                if (tools.isNotEmpty) ...[
                  const SizedBox(height: 30),
                  _title('Your tools'),
                  const SizedBox(height: 12),
                  SurfaceCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        for (final tool in tools)
                          SheetOption(
                            icon: tool.icon,
                            title: tool.title,
                            subtitle: tool.subtitle,
                            tone: tool.tone,
                            onTap: tool.open,
                          ),
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

  // ---------------------------------------------------------------- sports --

  Widget _sports() {
    return SizedBox(
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

  /// One compact strip instead of four floating tiles - monochrome icons,
  /// hairline dividers, no colored containers.
  Widget _quickActions(BuildContext context) {
    final actions = [
      (
        label: 'Find game',
        icon: Icons.search_rounded,
        open: () => openHomeTab(context, 1),
      ),
      (
        label: 'Create match',
        icon: Icons.add_circle_outline_rounded,
        open: () => pushRoute(context, AppRoute.createGame),
      ),
      (
        label: 'Personal score',
        icon: Icons.edit_note_rounded,
        open: () => pushRoute(context, AppRoute.matchHistory),
      ),
      (
        label: 'My teams',
        icon: Icons.groups_rounded,
        open: () => openHomeTab(context, 3),
      ),
    ];

    return SurfaceCard(
      padding: EdgeInsets.zero,
      onTap: null,
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0)
              const SizedBox(
                height: 40,
                child: VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: SportikaColors.borderSubtle,
                ),
              ),
            Expanded(
              child: InkWell(
                onTap: actions[i].open,
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 62,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        actions[i].icon,
                        size: 19,
                        color: SportikaColors.textBody,
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          actions[i].label,
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .1,
                            color: SportikaColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --------------------------------------------------------------- fixture --

  Widget _upcomingMatch(
    BuildContext context,
    FixturesController state,
    Fixture fixture,
  ) {
    final tournament = state.tournamentOf(fixture);
    final sport = tournament?.sport ?? Sport.cricket;
    final venue = [
      if (fixture.venue.isNotEmpty) fixture.venue,
      if (tournament != null && tournament.city.isNotEmpty) tournament.city,
    ].join(', ');
    final d = fixture.scheduledAt;

    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Editorial date block - condensed numerals, no container.
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    d.day.toString().padLeft(2, '0'),
                    style: const TextStyle(
                      fontFamily: 'Barlow Condensed',
                      fontSize: 26,
                      height: .9,
                      fontWeight: FontWeight.w800,
                      color: SportikaColors.text,
                    ),
                  ),
                  Text(
                    _monthShort(d).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w800,
                      color: SportikaColors.mint,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Container(width: 1, height: 34, color: SportikaColors.border),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tournament?.name ?? 'Tournament fixture',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.1,
                        color: SportikaColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      venue.isEmpty
                          ? '${fixture.stage} · ${timeLabel(d)}'
                          : '$venue · ${timeLabel(d)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: SportikaColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              _pill(
                sport.label.toUpperCase(),
                sportColor(sport).withValues(alpha: 0.12),
                sportColor(sport),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _matchSide(state.sideLabel(fixture, 0), sport),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'VS',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 2,
                color: SportikaColors.textDim,
              ),
            ),
          ),
          _matchSide(state.sideLabel(fixture, 1), sport),
          const SizedBox(height: 12),
          const Divider(),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => pushRoute(
                context,
                AppRoute.fixtureDetail,
                args: FixtureDetailArgs(fixture.id),
              ),
              child: const Text('View details →'),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ live board --

  /// Broadcast-style scoreboard: dark floor, big condensed numerals, one
  /// live indicator and the situation label the scoring engine provides.
  Widget _liveScore(
    BuildContext context,
    FixturesController state,
    Fixture fixture,
  ) {
    final progress = state.progressOfFixture(fixture);
    final home = progress.scoreDisplay.isNotEmpty
        ? progress.scoreDisplay[0]
        : '–';
    final away = progress.scoreDisplay.length > 1
        ? progress.scoreDisplay[1]
        : '–';
    final sport = state.tournamentOf(fixture)?.sport ?? Sport.cricket;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: SportikaColors.deepest,
        border: Border.all(color: SportikaColors.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Broadcast lower-third bar.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: SportikaColors.border)),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: SportikaColors.mint,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'LIVE',
                  style: TextStyle(
                    fontSize: 10,
                    color: SportikaColors.mint,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    sport.label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: SportikaColors.textMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    progress.statusLabel ?? 'In progress',
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: SportikaColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Column(
              children: [
                _scoreLine(state.sideLabel(fixture, 0), home),
                const Divider(color: SportikaColors.border),
                _scoreLine(state.sideLabel(fixture, 1), away),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => pushRoute(
                context,
                AppRoute.fixtureDetail,
                args: FixtureDetailArgs(fixture.id),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 0,
                ),
                minimumSize: const Size(48, 44),
              ),
              child: const Text(
                'Open match center →',
                style: TextStyle(
                  color: SportikaColors.mintSoft,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _scoreLine(String label, String score) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        flex: 5,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      const SizedBox(width: 16),
      Flexible(
        flex: 4,
        child: Align(
          alignment: Alignment.centerRight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              score,
              style: const TextStyle(
                fontFamily: 'Barlow Condensed',
                fontSize: 34,
                height: 1.2,
                fontWeight: FontWeight.w800,
                letterSpacing: .5,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    ],
  );

  // ---------------------------------------------------------- tournaments --

  Widget _discoverCard(
    BuildContext context,
    FixturesController state,
    Tournament tournament,
  ) {
    final confirmed = context.read<TournamentsController>().confirmedCountFor(
      tournament,
    );
    final left = (tournament.registrationLimit - confirmed).clamp(0, 999);

    return _surface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              SportPhoto(sport: tournament.sport, height: 150, radius: 0),
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
                        maxLines: 1,
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
                      foregroundColor: SportikaColors.blue,
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
  Widget _gameRail(BuildContext context, FixturesController state) {
    final games = context
        .read<GamesController>()
        .games
        .where((g) => _sport == null || g.sport == _sport)
        .take(6)
        .toList();
    if (games.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 196,
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
                  SportPhoto(sport: game.sport, height: 196, radius: 16),
                  // Bottom scrim only under the type block.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 96,
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
                          maxLines: 1,
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

  Widget _matchSide(String label, Sport sport) => Row(
    children: [
      SportGlyph(sport: sport, size: 18, color: sportColor(sport)),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
        ),
      ),
    ],
  );

  // ------------------------------------------------------------- primitives --

  Widget _title(String title, {String? action, VoidCallback? onAction}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
              color: SportikaColors.textMuted,
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
  }) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: SportikaColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: SportikaColors.border),
    ),
    child: child,
  );

  String _monthShort(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[d.month - 1];
  }

  /// Index of the side the signed-in account plays for, or -1.
  int _mySide(FixturesController state, Fixture fixture) {
    final me = context.read<ProfileController>().currentAccount?.id;
    if (me == null) return -1;
    final myEntryIds = context
        .read<TournamentsController>()
        .entries
        .where((e) => e.memberAccountIds.contains(me))
        .map((e) => e.id)
        .toSet();
    if (myEntryIds.contains(fixture.home.entryId)) return 0;
    if (myEntryIds.contains(fixture.away.entryId)) return 1;
    return -1;
  }

  String _pad(int value) => value.toString().padLeft(2, '0');
}

String greeting(String name) {
  return '${greetingEyebrow()}, $name';
}
