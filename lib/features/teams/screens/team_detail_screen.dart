import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/features/teams/widgets/invite_players_sheet.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/fixture_tile.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/module_media_panel.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Premium Sportika Team Profile.
///
/// Frontend-only redesign:
/// - Team media and identity
/// - Performance dashboard
/// - Next-match spotlight
/// - Overview / Roster / Matches / Tournaments
/// - Captain management and invitations
/// - Existing official fixture navigation
class TeamDetailScreen extends StatefulWidget {
  const TeamDetailScreen({super.key, required this.squadId});

  final String squadId;

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final teams = context.watch<TeamsController>();
    final squad = teams.squadById(widget.squadId);

    if (squad == null) {
      return ScreenScaffold(
        title: 'Team',
        child: ErrorState(
          title: 'This squad is gone',
          message: 'It was deleted or removed. Go back to your squads.',
          onRetry: () => Navigator.of(context).maybePop(),
          retryLabel: 'Back to teams',
        ),
      );
    }

    final accounts = teams.accounts;
    final entries = context.watch<TournamentsController>().entries;
    final fixtures = context.watch<FixturesController>().fixtures;

    final me = teams.currentAccountId;
    final isCaptain = squad.ownerId == me;

    final accountMap = {for (final account in accounts) account.id: account};

    final members = squad.memberAccountIds
        .map((id) => accountMap[id])
        .whereType<Account>()
        .toList();

    final invited = squad.invitedAccountIds
        .map((id) => accountMap[id])
        .whereType<Account>()
        .toList();

    final myEntries = entries
        .where((entry) => entry.squadId == squad.id)
        .toList();

    final entryIds = myEntries.map((entry) => entry.id).toSet();

    final squadFixtures = fixtures.where((fixture) {
      return entryIds.contains(fixture.home.entryId) ||
          entryIds.contains(fixture.away.entryId);
    }).toList();

    final results =
        squadFixtures.where((fixture) => fixture.result != null).toList()
          ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

    final upcoming =
        squadFixtures
            .where(
              (fixture) =>
                  fixture.result == null &&
                  fixture.status != FixtureStatus.cancelled,
            )
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    var won = 0;
    var drawn = 0;

    for (final fixture in results) {
      final winner = fixture.result!.winnerIndex;

      if (winner < 0) {
        drawn++;
        continue;
      }

      final mySide = entryIds.contains(fixture.home.entryId) ? 0 : 1;

      if (winner == mySide) {
        won++;
      }
    }

    final lost = results.length - won - drawn;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('TEAM PROFILE'),
        centerTitle: true,
        actions: [
          if (isCaptain)
            IconButton(
              tooltip: 'Invite players',
              icon: const Icon(Icons.person_add_alt_1_rounded),
              onPressed: () => showInvitePlayersSheet(context, squad.id),
            ),
          PopupMenuButton<String>(
            tooltip: 'Team options',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (value) {
              switch (value) {
                case 'invite':
                  showInvitePlayersSheet(context, squad.id);
                case 'leave':
                  _confirmLeave(context, squad);
                case 'delete':
                  _confirmDelete(context, squad);
              }
            },
            itemBuilder: (context) => [
              if (isCaptain)
                const PopupMenuItem(
                  value: 'invite',
                  child: Text('Invite players'),
                ),
              PopupMenuItem(
                value: isCaptain ? 'delete' : 'leave',
                child: Text(
                  isCaptain ? 'Delete squad' : 'Leave squad',
                  style: const TextStyle(color: SportikaColors.danger),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: NestedScrollView(
                headerSliverBuilder: (context, innerScrolled) => [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TeamIdentityHero(
                          squad: squad,
                          memberCount: members.length,
                          isCaptain: isCaptain,
                          onInvite: () =>
                              showInvitePlayersSheet(context, squad.id),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(SportikaSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _PerformanceDashboard(
                                played: results.length,
                                won: won,
                                drawn: drawn,
                                lost: lost,
                              ),
                              if (upcoming.isNotEmpty) ...[
                                const SizedBox(height: SportikaSpacing.lg),
                                _NextMatchSpotlight(fixture: upcoming.first),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _TeamTabsHeader(
                      controller: _tabs,
                      background: Theme.of(context).scaffoldBackgroundColor,
                    ),
                  ),
                ],
                body: TabBarView(
                  controller: _tabs,
                  children: [
                    _OverviewTab(
                      squad: squad,
                      results: results,
                      upcoming: upcoming,
                      entriesCount: myEntries.length,
                      membersCount: members.length,
                      won: won,
                      drawn: drawn,
                      lost: lost,
                      onOpenRoster: () => _tabs.animateTo(1),
                      onOpenMatches: () => _tabs.animateTo(2),
                      onOpenTournaments: () => _tabs.animateTo(3),
                    ),
                    _RosterTab(
                      squad: squad,
                      members: members,
                      invited: invited,
                      me: me,
                      isCaptain: isCaptain,
                      onInvite: () => showInvitePlayersSheet(context, squad.id),
                      onManage: (member) => _showMemberActions(
                        context,
                        squad: squad,
                        member: member,
                        isCaptain: isCaptain,
                        isMe: member.id == me,
                      ),
                    ),
                    _MatchesTab(upcoming: upcoming, results: results),
                    _TournamentsTab(entries: myEntries),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMemberActions(
    BuildContext context, {
    required Squad squad,
    required Account member,
    required bool isCaptain,
    required bool isMe,
  }) async {
    if (!isCaptain) return;

    final teams = context.read<TeamsController>();

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: SportikaColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(SportikaRadius.xl),
        ),
      ),
      builder: (sheetContext) => AppSheet(
        title: member.displayName,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMe && member.id != squad.ownerId)
              SheetOption(
                icon: Icons.military_tech_outlined,
                title: 'Make captain',
                subtitle: 'Hands over squad management',
                onTap: () => Navigator.pop(sheetContext, 'captain'),
              ),
            if (!isMe)
              SheetOption(
                icon: Icons.person_remove_outlined,
                title: 'Remove from squad',
                subtitle: 'The player keeps their own history',
                tone: SportikaColors.danger,
                onTap: () => Navigator.pop(sheetContext, 'remove'),
              ),
            SheetOption(
              icon: Icons.close,
              title: 'Close',
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted) return;

    switch (action) {
      case 'captain':
        teams.transferCaptain(squad.id, member.id);
        showSnack(context, '${member.displayName} is now captain');
      case 'remove':
        teams.removeSquadMember(squad.id, member.id);
        showSnack(context, '${member.displayName} removed');
    }
  }

  Future<void> _confirmLeave(BuildContext context, Squad squad) async {
    final teams = context.read<TeamsController>();

    final confirmed = await _confirm(
      context,
      title: 'Leave ${squad.name}?',
      body: 'You will need a new invitation to rejoin.',
      confirmLabel: 'Leave',
    );

    if (!context.mounted || !confirmed) return;

    try {
      teams.leaveSquad(squad.id);
      Navigator.of(context).pop();
    } on StateError catch (error) {
      showSnack(context, error.message, error: true);
    }
  }

  Future<void> _confirmDelete(BuildContext context, Squad squad) async {
    final teams = context.read<TeamsController>();

    final confirmed = await _confirm(
      context,
      title: 'Delete ${squad.name}?',
      body:
          'The squad and pending invitations are removed. '
          'Past results stay with the tournament.',
      confirmLabel: 'Delete',
    );

    if (!context.mounted || !confirmed) return;

    teams.deleteSquad(squad.id);
    Navigator.of(context).pop();
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title, style: SportikaType.title),
        content: Text(body, style: SportikaType.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: SportikaColors.danger,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    return result ?? false;
  }
}

// -----------------------------------------------------------------------------
// TEAM IDENTITY HERO
// -----------------------------------------------------------------------------

class _TeamIdentityHero extends StatelessWidget {
  const _TeamIdentityHero({
    required this.squad,
    required this.memberCount,
    required this.isCaptain,
    required this.onInvite,
  });

  final Squad squad;
  final int memberCount;
  final bool isCaptain;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ModuleMediaPanel(
          bucket: 'team-media',
          entity: squad.id,
          canEdit: isCaptain,
          label: squad.name,
        ),
        Padding(
          padding: const EdgeInsets.all(SportikaSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colors.primary.withValues(alpha: .28),
                          colors.surfaceContainerHighest,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(SportikaRadius.lg),
                      border: Border.all(
                        color: colors.primary.withValues(alpha: .35),
                      ),
                    ),
                    child: Icon(
                      Icons.shield_rounded,
                      size: 43,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: SportikaSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          squad.name,
                          style: SportikaType.title.copyWith(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: SportikaSpacing.sm),
                        Wrap(
                          spacing: SportikaSpacing.xs,
                          runSpacing: SportikaSpacing.xs,
                          children: [
                            SportTag(squad.sport),
                            StatusPill(
                              squad.type.label,
                              color: SportikaColors.blueBright,
                              icon: Icons.groups_2_outlined,
                            ),
                          ],
                        ),
                        const SizedBox(height: SportikaSpacing.sm),
                        Row(
                          children: [
                            Icon(
                              Icons.people_outline_rounded,
                              size: 15,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '$memberCount '
                              '${memberCount == 1 ? 'player' : 'players'}',
                              style: SportikaType.caption,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (isCaptain) ...[
                const SizedBox(height: SportikaSpacing.md),
                PrimaryButton(
                  label: 'Invite players',
                  icon: Icons.person_add_alt_1_rounded,
                  onPressed: onInvite,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// PERFORMANCE DASHBOARD
// -----------------------------------------------------------------------------

class _PerformanceDashboard extends StatelessWidget {
  const _PerformanceDashboard({
    required this.played,
    required this.won,
    required this.drawn,
    required this.lost,
  });

  final int played;
  final int won;
  final int drawn;
  final int lost;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final winRate = played == 0 ? 0.0 : won / played;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('TEAM PERFORMANCE', style: SportikaType.action),
        const SizedBox(height: SportikaSpacing.md),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                value: '$played',
                label: 'Played',
                icon: Icons.sports_score_rounded,
                tone: colors.primary,
              ),
            ),
            const SizedBox(width: SportikaSpacing.xs),
            Expanded(
              child: _MetricCard(
                value: '$won',
                label: 'Won',
                icon: Icons.emoji_events_outlined,
                tone: SportikaColors.mint,
              ),
            ),
            const SizedBox(width: SportikaSpacing.xs),
            Expanded(
              child: _MetricCard(
                value: '$drawn',
                label: 'Drawn',
                icon: Icons.handshake_outlined,
                tone: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: SportikaSpacing.xs),
            Expanded(
              child: _MetricCard(
                value: '$lost',
                label: 'Lost',
                icon: Icons.trending_down_rounded,
                tone: SportikaColors.danger,
              ),
            ),
          ],
        ),
        const SizedBox(height: SportikaSpacing.md),
        SurfaceCard(
          padding: const EdgeInsets.all(SportikaSpacing.md),
          child: Column(
            children: [
              Row(
                children: [
                  const Text('Win rate', style: SportikaType.bodyStrong),
                  const Spacer(),
                  Text(
                    '${(winRate * 100).toStringAsFixed(1)}%',
                    style: SportikaType.bodyStrong.copyWith(
                      color: SportikaColors.mint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SportikaSpacing.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(SportikaRadius.pill),
                child: LinearProgressIndicator(
                  value: winRate,
                  minHeight: 8,
                  backgroundColor: colors.surfaceContainerHighest,
                  valueColor: const AlwaysStoppedAnimation(SportikaColors.mint),
                ),
              ),
              const SizedBox(height: SportikaSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  played == 0
                      ? 'Performance appears after official results.'
                      : '$won wins from $played completed matches',
                  style: SportikaType.caption,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.tone,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: SportikaSpacing.md,
        horizontal: 4,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SportikaRadius.md),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, size: 19, color: tone),
          const SizedBox(height: SportikaSpacing.sm),
          Text(
            value,
            style: SportikaType.title.copyWith(fontSize: 23, color: tone),
          ),
          const SizedBox(height: 3),
          Text(label, style: SportikaType.caption),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// NEXT MATCH SPOTLIGHT
// -----------------------------------------------------------------------------

class _NextMatchSpotlight extends StatelessWidget {
  const _NextMatchSpotlight({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('NEXT MATCH', style: SportikaType.action),
            const Spacer(),
            Icon(Icons.arrow_forward_rounded, size: 18, color: colors.primary),
          ],
        ),
        const SizedBox(height: SportikaSpacing.sm),
        Container(
          padding: const EdgeInsets.all(SportikaSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SportikaRadius.lg),
            border: Border.all(color: colors.primary.withValues(alpha: .35)),
            gradient: LinearGradient(
              colors: [
                colors.primary.withValues(alpha: .12),
                colors.surfaceContainerLow,
              ],
            ),
          ),
          child: officialFixtureTile(
            context,
            fixture,
            onTap: () => pushRoute(
              context,
              AppRoute.fixtureDetail,
              args: FixtureDetailArgs(fixture.id),
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// PINNED TABS
// -----------------------------------------------------------------------------

class _TeamTabsHeader extends SliverPersistentHeaderDelegate {
  _TeamTabsHeader({required this.controller, required this.background});

  final TabController controller;
  final Color background;

  @override
  double get minExtent => 52;

  @override
  double get maxExtent => 52;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: background,
      elevation: overlapsContent ? 2 : 0,
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: colors.primary,
        unselectedLabelColor: colors.onSurfaceVariant,
        indicatorColor: colors.primary,
        indicatorWeight: 3,
        dividerColor: colors.outlineVariant,
        tabs: const [
          Tab(text: 'Overview'),
          Tab(text: 'Roster'),
          Tab(text: 'Matches'),
          Tab(text: 'Tournaments'),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TeamTabsHeader oldDelegate) {
    return controller != oldDelegate.controller ||
        background != oldDelegate.background;
  }
}

// -----------------------------------------------------------------------------
// OVERVIEW TAB
// -----------------------------------------------------------------------------

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.squad,
    required this.results,
    required this.upcoming,
    required this.entriesCount,
    required this.membersCount,
    required this.won,
    required this.drawn,
    required this.lost,
    required this.onOpenRoster,
    required this.onOpenMatches,
    required this.onOpenTournaments,
  });

  final Squad squad;
  final List<Fixture> results;
  final List<Fixture> upcoming;
  final int entriesCount;
  final int membersCount;
  final int won;
  final int drawn;
  final int lost;
  final VoidCallback onOpenRoster;
  final VoidCallback onOpenMatches;
  final VoidCallback onOpenTournaments;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('team-overview'),
      padding: const EdgeInsets.all(SportikaSpacing.md),
      children: [
        const Text('TEAM HUB', style: SportikaType.action),
        const SizedBox(height: SportikaSpacing.md),
        _OverviewLink(
          icon: Icons.groups_rounded,
          title: 'Team roster',
          subtitle: '$membersCount registered players',
          onTap: onOpenRoster,
        ),
        _OverviewLink(
          icon: Icons.calendar_month_rounded,
          title: 'Match center',
          subtitle: '${upcoming.length} upcoming fixtures',
          onTap: onOpenMatches,
        ),
        _OverviewLink(
          icon: Icons.emoji_events_outlined,
          title: 'Tournaments',
          subtitle: '$entriesCount tournament entries',
          onTap: onOpenTournaments,
        ),
        const SizedBox(height: SportikaSpacing.lg),
        const Text('RECENT FORM', style: SportikaType.action),
        const SizedBox(height: SportikaSpacing.md),
        if (results.isEmpty)
          const EmptyState(
            title: 'Your journey starts here',
            body: 'Recent form appears after official results.',
            icon: Icons.insights_outlined,
          )
        else
          _RecentForm(squad: squad, results: results),
        const SizedBox(height: SportikaSpacing.lg),
        const Text('LATEST RESULT', style: SportikaType.action),
        const SizedBox(height: SportikaSpacing.sm),
        if (results.isEmpty)
          const EmptyState(
            title: 'No results yet',
            body: 'Your first completed match will appear here.',
            icon: Icons.scoreboard_outlined,
          )
        else
          officialFixtureTile(
            context,
            results.first,
            onTap: () => pushRoute(
              context,
              AppRoute.fixtureDetail,
              args: FixtureDetailArgs(results.first.id),
            ),
          ),
      ],
    );
  }
}

class _OverviewLink extends StatelessWidget {
  const _OverviewLink({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
      child: SurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.all(SportikaSpacing.md),
        child: Row(
          children: [
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(SportikaRadius.md),
              ),
              child: Icon(icon, color: colors.primary),
            ),
            const SizedBox(width: SportikaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SportikaType.bodyStrong),
                  const SizedBox(height: 3),
                  Text(subtitle, style: SportikaType.caption),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _RecentForm extends StatelessWidget {
  const _RecentForm({required this.squad, required this.results});

  final Squad squad;
  final List<Fixture> results;

  @override
  Widget build(BuildContext context) {
    final recent = results.take(5).toList();
    final colors = Theme.of(context).colorScheme;

    return SurfaceCard(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      child: Row(
        children: [
          for (final fixture in recent) ...[
            Expanded(
              child: _FormResult(fixture: fixture, squadId: squad.id),
            ),
            if (fixture != recent.last)
              const SizedBox(width: SportikaSpacing.sm),
          ],
          if (recent.length < 5)
            for (var i = recent.length; i < 5; i++) ...[
              if (i > 0) const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: Container(
                  height: 39,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(SportikaRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: const Text('–', style: SportikaType.caption),
                ),
              ),
            ],
        ],
      ),
    );
  }
}

class _FormResult extends StatelessWidget {
  const _FormResult({required this.fixture, required this.squadId});

  final Fixture fixture;
  final String squadId;

  @override
  Widget build(BuildContext context) {
    final entries = context.watch<TournamentsController>().entries;
    final squadEntryIds = entries
        .where((entry) => entry.squadId == squadId)
        .map((entry) => entry.id)
        .toSet();

    final winner = fixture.result?.winnerIndex ?? -1;
    final mySide = squadEntryIds.contains(fixture.home.entryId) ? 0 : 1;

    final isDraw = winner < 0;
    final isWin = !isDraw && winner == mySide;

    final label = isDraw ? 'D' : (isWin ? 'W' : 'L');

    final tone = isDraw
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : isWin
        ? SportikaColors.mint
        : SportikaColors.danger;

    return Container(
      height: 39,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(SportikaRadius.sm),
        border: Border.all(color: tone.withValues(alpha: .25)),
      ),
      alignment: Alignment.center,
      child: Text(label, style: SportikaType.bodyStrong.copyWith(color: tone)),
    );
  }
}

// -----------------------------------------------------------------------------
// ROSTER TAB
// -----------------------------------------------------------------------------

class _RosterTab extends StatelessWidget {
  const _RosterTab({
    required this.squad,
    required this.members,
    required this.invited,
    required this.me,
    required this.isCaptain,
    required this.onInvite,
    required this.onManage,
  });

  final Squad squad;
  final List<Account> members;
  final List<Account> invited;
  final String? me;
  final bool isCaptain;
  final VoidCallback onInvite;
  final ValueChanged<Account> onManage;

  @override
  Widget build(BuildContext context) {
    final teams = context.read<TeamsController>();

    return ListView(
      key: const PageStorageKey('team-roster'),
      padding: const EdgeInsets.all(SportikaSpacing.md),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'SQUAD MEMBERS  ·  ${members.length}',
                style: SportikaType.action,
              ),
            ),
            if (isCaptain)
              TextButton.icon(
                onPressed: onInvite,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Invite'),
              ),
          ],
        ),
        const SizedBox(height: SportikaSpacing.sm),
        if (members.isEmpty)
          const EmptyState(
            title: 'No players yet',
            body: 'Invite players to build your roster.',
            icon: Icons.groups_outlined,
          )
        else
          for (final member in members)
            Padding(
              padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
              child: _MemberRow(
                account: member,
                isCaptain: member.id == squad.ownerId,
                isMe: member.id == me,
                canManage: isCaptain,
                onManage: () => onManage(member),
              ),
            ),
        if (invited.isNotEmpty) ...[
          const SizedBox(height: SportikaSpacing.lg),
          Text(
            'PENDING INVITATIONS  ·  ${invited.length}',
            style: SportikaType.action,
          ),
          const SizedBox(height: SportikaSpacing.md),
          for (final player in invited)
            Padding(
              padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
              child: _InvitedRow(
                account: player,
                canCancel: isCaptain || player.id == me,
                onCancel: () => teams.cancelInvite(squad.id, player.id),
                onAccept: player.id == me
                    ? () => teams.respondToInvite(squad.id, accept: true)
                    : null,
                onDecline: player.id == me
                    ? () => teams.respondToInvite(squad.id, accept: false)
                    : null,
              ),
            ),
        ],
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.account,
    required this.isCaptain,
    required this.isMe,
    required this.canManage,
    required this.onManage,
  });

  final Account account;
  final bool isCaptain;
  final bool isMe;
  final bool canManage;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SurfaceCard(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      onTap: canManage ? onManage : null,
      child: Row(
        children: [
          AccountAvatar(account: account, size: 48),
          const SizedBox(width: SportikaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        account.displayName,
                        style: SportikaType.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 5),
                      const Text('(you)', style: SportikaType.caption),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  account.city.isEmpty ? 'Sportika athlete' : account.city,
                  style: SportikaType.caption,
                ),
              ],
            ),
          ),
          if (isCaptain)
            const StatusPill(
              'Captain',
              color: SportikaColors.gold,
              icon: Icons.military_tech_outlined,
            )
          else if (canManage)
            Icon(Icons.more_vert_rounded, color: colors.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _InvitedRow extends StatelessWidget {
  const _InvitedRow({
    required this.account,
    required this.canCancel,
    required this.onCancel,
    this.onAccept,
    this.onDecline,
  });

  final Account account;
  final bool canCancel;
  final VoidCallback onCancel;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      borderColor: SportikaColors.gold.withValues(alpha: .35),
      child: Row(
        children: [
          AccountAvatar(account: account, size: 42),
          const SizedBox(width: SportikaSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.displayName,
                  style: SportikaType.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Invitation pending',
                  style: SportikaType.caption.copyWith(
                    color: SportikaColors.gold,
                  ),
                ),
              ],
            ),
          ),
          if (onAccept != null) ...[
            TextButton(onPressed: onAccept, child: const Text('Join')),
            IconButton(
              tooltip: 'Decline invitation',
              onPressed: onDecline,
              icon: const Icon(Icons.close_rounded),
            ),
          ] else if (canCancel)
            IconAction(
              icon: Icons.close_rounded,
              label: 'Cancel invite for ${account.displayName}',
              onPressed: onCancel,
            ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// MATCHES TAB
// -----------------------------------------------------------------------------

class _MatchesTab extends StatelessWidget {
  const _MatchesTab({required this.upcoming, required this.results});

  final List<Fixture> upcoming;
  final List<Fixture> results;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('team-matches'),
      padding: const EdgeInsets.all(SportikaSpacing.md),
      children: [
        const Text('UPCOMING FIXTURES', style: SportikaType.action),
        const SizedBox(height: SportikaSpacing.md),
        if (upcoming.isEmpty)
          const EmptyState(
            title: 'No matches scheduled',
            body: 'Fixtures appear when organizers publish the draw.',
            icon: Icons.event_busy_outlined,
          )
        else
          for (final fixture in upcoming)
            Padding(
              padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
              child: officialFixtureTile(
                context,
                fixture,
                onTap: () => pushRoute(
                  context,
                  AppRoute.fixtureDetail,
                  args: FixtureDetailArgs(fixture.id),
                ),
              ),
            ),
        const SizedBox(height: SportikaSpacing.lg),
        const Text('MATCH RESULTS', style: SportikaType.action),
        const SizedBox(height: SportikaSpacing.md),
        if (results.isEmpty)
          const EmptyState(
            title: 'No results yet',
            body: 'Published match results appear here.',
            icon: Icons.scoreboard_outlined,
          )
        else
          for (final fixture in results)
            Padding(
              padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
              child: officialFixtureTile(
                context,
                fixture,
                onTap: () => pushRoute(
                  context,
                  AppRoute.fixtureDetail,
                  args: FixtureDetailArgs(fixture.id),
                ),
              ),
            ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// TOURNAMENTS TAB
// -----------------------------------------------------------------------------

class _TournamentsTab extends StatelessWidget {
  const _TournamentsTab({required this.entries});

  final List<Entry> entries;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('team-tournaments'),
      padding: const EdgeInsets.all(SportikaSpacing.md),
      children: [
        const Text('TOURNAMENT ENTRIES', style: SportikaType.action),
        const SizedBox(height: SportikaSpacing.md),
        if (entries.isEmpty)
          EmptyState(
            title: 'No tournaments yet',
            body: 'Enter a tournament to represent your squad.',
            icon: Icons.emoji_events_outlined,
            action: GhostButton(
              label: 'Browse tournaments',
              icon: Icons.emoji_events_outlined,
              onPressed: () => Navigator.of(context).pop(),
            ),
          )
        else
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
              child: SurfaceCard(
                padding: const EdgeInsets.all(SportikaSpacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: SportikaColors.gold.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(SportikaRadius.md),
                      ),
                      child: const Icon(
                        Icons.emoji_events_outlined,
                        color: SportikaColors.gold,
                      ),
                    ),
                    const SizedBox(width: SportikaSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.label, style: SportikaType.bodyStrong),
                          const SizedBox(height: 4),
                          Text(
                            '${entry.memberAccountIds.length} players'
                            ' · ${dayLabel(entry.submittedAt)}',
                            style: SportikaType.caption,
                          ),
                        ],
                      ),
                    ),
                    StatusPill(
                      entry.status.label,
                      color: statusColor(entry.status.key),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
