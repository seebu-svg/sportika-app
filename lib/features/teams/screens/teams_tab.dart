import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/features/teams/widgets/team_discovery_controls.dart';
import 'package:sportika/features/teams/widgets/team_result_card.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/filter_chip_row.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

enum _TeamSection {
  mine('My Teams'),
  teams('Find Teams'),
  players('Players');

  const _TeamSection(this.label);

  final String label;
}

class TeamsTab extends StatefulWidget {
  const TeamsTab({super.key});

  @override
  State<TeamsTab> createState() => _TeamsTabState();
}

class _TeamsTabState extends State<TeamsTab> {
  _TeamSection _section = _TeamSection.mine;
  Sport? _sport;

  final _teamSearch = TextEditingController();
  final _playerSearch = TextEditingController();

  @override
  void dispose() {
    _teamSearch.dispose();
    _playerSearch.dispose();
    super.dispose();
  }

  void _selectSection(_TeamSection section) {
    if (_section == section) return;

    FocusScope.of(context).unfocus();

    setState(() => _section = section);
  }

  void _createSquad() {
    pushRoute(context, AppRoute.createTeam);
  }

  @override
  Widget build(BuildContext context) {
    final teams = context.watch<TeamsController>();
    final tournaments = context.watch<TournamentsController>();
    final profile = context.watch<ProfileController>();

    final me = profile.currentAccount;

    final myEntries = tournaments.entries.where(
      (entry) =>
          me != null &&
          entry.memberAccountIds.contains(me.id) &&
          entry.status != EntryStatus.withdrawn,
    );

    final mySquads = teams.mySquads.where(
      (squad) => _sport == null || squad.sport == _sport,
    );

    final myInvites = teams.myInvites.where(
      (squad) => _sport == null || squad.sport == _sport,
    );

    final filteredEntries = myEntries.where(
      (entry) =>
          _sport == null ||
          tournaments.tournamentById(entry.tournamentId)?.sport == _sport,
    );

    return Column(
      children: [
        Expanded(
          child: Column(
            children: [
              // Compact community identity header.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SportikaSpacing.gutter,
                  SportikaSpacing.md,
                  SportikaSpacing.gutter,
                  SportikaSpacing.sm,
                ),
                child: _CommunityHeader(
                  section: _section,
                  onCreate: _createSquad,
                ),
              ),

              // Premium segmented navigation.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SportikaSpacing.gutter,
                  SportikaSpacing.xs,
                  SportikaSpacing.gutter,
                  SportikaSpacing.sm,
                ),
                child: TeamSectionControl(
                  labels: [
                    for (final section in _TeamSection.values) section.label,
                  ],
                  selected: _section.index,
                  onChanged: (index) {
                    _selectSection(_TeamSection.values[index]);
                  },
                ),
              ),

              // Shared sport filtering.
              SportFilterRow(
                selected: _sport,
                onChanged: (sport) {
                  setState(() => _sport = sport);
                },
                allLabel: 'All Sports',
                padding: const EdgeInsets.symmetric(
                  horizontal: SportikaSpacing.gutter,
                ),
              ),

              // Search appears only in discovery sections.
              if (_section != _TeamSection.mine)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SportikaSpacing.gutter,
                    SportikaSpacing.sm,
                    SportikaSpacing.gutter,
                    SportikaSpacing.md,
                  ),
                  child: _section == _TeamSection.teams
                      ? TeamSearchField(
                          key: const ValueKey('team-search'),
                          controller: _teamSearch,
                          hint: 'Search teams by name',
                        )
                      : TeamSearchField(
                          key: const ValueKey('player-search'),
                          controller: _playerSearch,
                          hint: 'Search athletes by name or city',
                        ),
                ),

              Expanded(
                child: switch (_section) {
                  _TeamSection.mine => _MyTeams(
                    sport: _sport,
                    squadsCount: mySquads.length,
                    invitesCount: myInvites.length,
                    entriesCount: filteredEntries.length,
                    onCreate: _createSquad,
                  ),
                  _TeamSection.teams => ListenableBuilder(
                    listenable: _teamSearch,
                    builder: (context, _) => _TeamDirectory(
                      sport: _sport,
                      query: _teamSearch.text.trim().toLowerCase(),
                    ),
                  ),
                  _TeamSection.players => ListenableBuilder(
                    listenable: _playerSearch,
                    builder: (context, _) => _PlayerDirectory(
                      sport: _sport,
                      query: _playerSearch.text.trim().toLowerCase(),
                    ),
                  ),
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// COMMUNITY HEADER
// -----------------------------------------------------------------------------

class _CommunityHeader extends StatelessWidget {
  const _CommunityHeader({required this.section, required this.onCreate});

  final _TeamSection section;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final title = switch (section) {
      _TeamSection.mine => 'My Teams',
      _TeamSection.teams => 'Discover Teams',
      _TeamSection.players => 'Find Athletes',
    };

    final subtitle = switch (section) {
      _TeamSection.mine => 'YOUR SPORTIKA COMMUNITY',
      _TeamSection.teams => 'EXPLORE THE COMMUNITY',
      _TeamSection.players => 'ATHLETE DISCOVERY',
    };

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subtitle,
                style: SportikaType.caption.copyWith(
                  color: colors.primary,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: SportikaSpacing.xs),
              Text(
                title,
                style: SportikaType.title.copyWith(
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        Material(
          color: colors.primary.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(SportikaRadius.md),
          child: IconButton(
            tooltip: 'Create squad',
            icon: Icon(Icons.group_add_rounded, color: colors.primary),
            onPressed: onCreate,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// MY TEAMS DASHBOARD
// -----------------------------------------------------------------------------

const _resultPadding = EdgeInsets.fromLTRB(
  SportikaSpacing.gutter,
  SportikaSpacing.xxs,
  SportikaSpacing.gutter,
  SportikaSpacing.xl,
);

class _MyTeams extends StatelessWidget {
  const _MyTeams({
    required this.sport,
    required this.squadsCount,
    required this.invitesCount,
    required this.entriesCount,
    required this.onCreate,
  });

  final Sport? sport;
  final int squadsCount;
  final int invitesCount;
  final int entriesCount;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final teams = context.watch<TeamsController>();
    final tournaments = context.watch<TournamentsController>();
    final me = context.watch<ProfileController>().currentAccount;

    final allSquads = teams.mySquads;

    final squads = allSquads
        .where((squad) => sport == null || squad.sport == sport)
        .toList();

    final invites = teams.myInvites
        .where((squad) => sport == null || squad.sport == sport)
        .toList();

    final entries =
        tournaments.entries
            .where(
              (entry) =>
                  me != null &&
                  entry.memberAccountIds.contains(me.id) &&
                  entry.status != EntryStatus.withdrawn,
            )
            .toList()
          ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

    final filteredEntries = entries
        .where(
          (entry) =>
              sport == null ||
              tournaments.tournamentById(entry.tournamentId)?.sport == sport,
        )
        .toList();

    return ListView(
      key: const PageStorageKey(_TeamSection.mine),
      padding: _resultPadding,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _TeamsHero(onCreate: onCreate),

        const SizedBox(height: SportikaSpacing.md),

        _DashboardStats(
          squads: squadsCount,
          invites: invitesCount,
          entries: entriesCount,
        ),

        const SizedBox(height: SportikaSpacing.lg),

        if (invites.isNotEmpty) ...[
          _SectionHeading(
            title: 'Invitations',
            count: invites.length,
            icon: Icons.mark_email_unread_outlined,
          ),
          const SizedBox(height: SportikaSpacing.sm),
          for (final invite in invites)
            Padding(
              padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
              child: _InviteCard(squad: invite),
            ),
          const SizedBox(height: SportikaSpacing.md),
        ],

        _SectionHeading(
          title: 'My Squads',
          count: squads.length,
          icon: Icons.shield_outlined,
        ),

        const SizedBox(height: SportikaSpacing.sm),

        if (squads.isNotEmpty)
          for (final squad in squads)
            Padding(
              padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
              child: _SquadCard(squad: squad),
            )
        else if (teams.loading)
          const LoadingSkeleton(label: 'Loading your squads', rows: 2)
        else if (allSquads.isNotEmpty)
          const EmptyState(
            title: 'No squads for this sport',
            body: 'Choose another sport or select All Sports.',
            icon: Icons.filter_alt_outlined,
          )
        else
          _CreateSquadEmpty(onCreate: onCreate),

        const SizedBox(height: SportikaSpacing.lg),

        _SectionHeading(
          title: 'Tournament Activity',
          count: filteredEntries.length,
          icon: Icons.emoji_events_outlined,
        ),

        const SizedBox(height: SportikaSpacing.sm),

        if (filteredEntries.isNotEmpty)
          for (final entry in filteredEntries)
            Padding(
              padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
              child: _EntryRow(entry: entry),
            )
        else if (tournaments.loading)
          const LoadingSkeleton(label: 'Loading tournament entries', rows: 1)
        else
          EmptyState(
            title: entries.isEmpty
                ? 'No tournament entries'
                : 'No entries for this sport',
            body: entries.isEmpty
                ? 'Registration status and organizer decisions appear here.'
                : 'Choose another sport or select All Sports.',
            icon: Icons.how_to_reg_outlined,
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// BRANDED HERO
// -----------------------------------------------------------------------------

class _TeamsHero extends StatelessWidget {
  const _TeamsHero({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 188),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SportikaRadius.lg),
        border: Border.all(color: colors.primary.withValues(alpha: .25)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary.withValues(alpha: .27),
            colors.surfaceContainerHighest,
            colors.surface,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -36,
            top: -42,
            child: Icon(
              Icons.groups_rounded,
              size: 205,
              color: colors.primary.withValues(alpha: .10),
            ),
          ),
          Positioned(
            right: 24,
            bottom: -48,
            child: Icon(
              Icons.shield_rounded,
              size: 150,
              color: colors.onSurface.withValues(alpha: .045),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(SportikaSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SPORTIKA  /  TEAM COMMUNITY',
                  style: SportikaType.caption.copyWith(
                    color: colors.primary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: SportikaSpacing.md),
                Text(
                  'BUILD YOUR\nLEGACY.',
                  style: SportikaType.title.copyWith(
                    fontSize: 30,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: SportikaSpacing.sm),
                Text(
                  'Find your people. Own your game.',
                  style: SportikaType.caption.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: SportikaSpacing.md),
                SizedBox(
                  width: 165,
                  child: PrimaryButton(
                    label: 'Create Squad',
                    icon: Icons.add_rounded,
                    tone: SportikaColors.mint,
                    small: true,
                    onPressed: onCreate,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SUMMARY STATISTICS
// -----------------------------------------------------------------------------

class _DashboardStats extends StatelessWidget {
  const _DashboardStats({
    required this.squads,
    required this.invites,
    required this.entries,
  });

  final int squads;
  final int invites;
  final int entries;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryMetric(
            icon: Icons.shield_outlined,
            value: squads,
            label: 'My Squads',
            tone: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: SportikaSpacing.sm),
        Expanded(
          child: _SummaryMetric(
            icon: Icons.mail_outline_rounded,
            value: invites,
            label: 'Invites',
            tone: SportikaColors.gold,
          ),
        ),
        const SizedBox(width: SportikaSpacing.sm),
        Expanded(
          child: _SummaryMetric(
            icon: Icons.emoji_events_outlined,
            value: entries,
            label: 'Entries',
            tone: SportikaColors.mint,
          ),
        ),
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.tone,
  });

  final IconData icon;
  final int value;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: SportikaSpacing.md,
        horizontal: SportikaSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SportikaRadius.md),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: tone),
          const SizedBox(height: SportikaSpacing.sm),
          Text(
            '$value',
            style: SportikaType.title.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: SportikaType.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SECTION HEADING
// -----------------------------------------------------------------------------

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.icon, this.count});

  final String title;
  final IconData icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 19, color: colors.primary),
        const SizedBox(width: SportikaSpacing.sm),
        Expanded(
          child: Text(
            title,
            style: SportikaType.bodyStrong.copyWith(fontSize: 17),
          ),
        ),
        if (count != null)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: SportikaSpacing.sm,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(SportikaRadius.pill),
            ),
            child: Text(
              '$count',
              style: SportikaType.caption.copyWith(color: colors.primary),
            ),
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// EMPTY STATE
// -----------------------------------------------------------------------------

class _CreateSquadEmpty extends StatelessWidget {
  const _CreateSquadEmpty({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SportikaRadius.lg),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.shield_outlined, size: 43, color: colors.primary),
          const SizedBox(height: SportikaSpacing.md),
          const Text(
            'Your first squad starts here',
            style: SportikaType.bodyStrong,
          ),
          const SizedBox(height: SportikaSpacing.sm),
          const Text(
            'Create a team or pair, invite athletes, '
            'and start competing.',
            style: SportikaType.caption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: SportikaSpacing.md),
          PrimaryButton(
            label: 'Create Squad',
            icon: Icons.add_rounded,
            tone: SportikaColors.mint,
            small: true,
            onPressed: onCreate,
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// TEAM DISCOVERY
// -----------------------------------------------------------------------------

class _TeamDirectory extends StatelessWidget {
  const _TeamDirectory({required this.sport, required this.query});

  final Sport? sport;
  final String query;

  @override
  Widget build(BuildContext context) {
    final teams = context.watch<TeamsController>();

    final squads = teams.squads
        .where(
          (squad) =>
              (sport == null || squad.sport == sport) &&
              squad.name.toLowerCase().contains(query),
        )
        .toList();

    return _DiscoveryResults(
      section: _TeamSection.teams,
      loading: teams.loading,
      hasDirectory: teams.squads.isNotEmpty,
      count: squads.length,
      title: 'Community Teams',
      itemBuilder: (_, index) => _SquadCard(squad: squads[index]),
    );
  }
}

// -----------------------------------------------------------------------------
// PLAYER DISCOVERY
// -----------------------------------------------------------------------------

class _PlayerDirectory extends StatelessWidget {
  const _PlayerDirectory({required this.sport, required this.query});

  final Sport? sport;
  final String query;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final profile = context.watch<ProfileController>();
    final teams = context.watch<TeamsController>();

    final players =
        session.accounts
            .where(
              (account) =>
                  (sport == null ||
                      profile.sportsPlayedBy(account.id).contains(sport)) &&
                  (account.displayName.toLowerCase().contains(query) ||
                      account.city.toLowerCase().contains(query)),
            )
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));

    return _DiscoveryResults(
      section: _TeamSection.players,
      loading: !session.ready || teams.loading,
      hasDirectory: session.accounts.isNotEmpty,
      count: players.length,
      title: 'Athlete Directory',
      itemBuilder: (context, index) {
        final account = players[index];

        return TeamPlayerCard(
          account: account,
          sports: profile.sportsPlayedBy(account.id),
          appearances: profile.appearancesOf(account.id).length,
          teams: teams.squadsOf(account.id).length,
          isMe: account.id == profile.currentAccount?.id,
          onTap: () => pushRoute(
            context,
            AppRoute.playerProfile,
            args: PlayerProfileArgs(account.id),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// DISCOVERY RESULTS
// -----------------------------------------------------------------------------

class _DiscoveryResults extends StatelessWidget {
  const _DiscoveryResults({
    required this.section,
    required this.loading,
    required this.hasDirectory,
    required this.count,
    required this.title,
    required this.itemBuilder,
  });

  final _TeamSection section;
  final bool loading;
  final bool hasDirectory;
  final int count;
  final String title;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final players = section == _TeamSection.players;
    final noun = players ? 'players' : 'teams';

    if (count == 0) {
      return ListView(
        key: PageStorageKey(section),
        padding: _resultPadding,
        children: [
          if (loading)
            LoadingSkeleton(label: 'Loading $noun')
          else
            EmptyState(
              title: hasDirectory ? 'No $noun found' : 'No $noun yet',
              body: hasDirectory
                  ? 'Clear your search or choose another sport.'
                  : players
                  ? 'Community players will appear here.'
                  : 'Community teams and pairs will appear here.',
              icon: hasDirectory
                  ? Icons.search_off_outlined
                  : players
                  ? Icons.people_outline
                  : Icons.groups_outlined,
            ),
        ],
      );
    }

    return ListView.separated(
      key: PageStorageKey(section),
      padding: _resultPadding,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: count + 1,
      separatorBuilder: (_, index) => SizedBox(
        height: index == 0 ? SportikaSpacing.md : SportikaSpacing.sm,
      ),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _SectionHeading(
            title: title,
            count: count,
            icon: players
                ? Icons.people_outline_rounded
                : Icons.shield_outlined,
          );
        }

        return itemBuilder(context, index - 1);
      },
    );
  }
}

// -----------------------------------------------------------------------------
// SQUAD CARD
// -----------------------------------------------------------------------------

class _SquadCard extends StatelessWidget {
  const _SquadCard({required this.squad});

  final Squad squad;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();

    return TeamSquadCard(
      squad: squad,
      members: [
        for (final id in squad.memberAccountIds) session.accountById(id),
      ],
      onTap: () => pushRoute(
        context,
        AppRoute.teamDetail,
        args: TeamDetailArgs(squad.id),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// TOURNAMENT ENTRY CARD
// -----------------------------------------------------------------------------

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final tournaments = context.watch<TournamentsController>();

    final tournament = tournaments.tournamentById(entry.tournamentId);

    final colors = Theme.of(context).colorScheme;

    return SurfaceCard(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      onTap: tournament == null
          ? null
          : () => pushRoute(
              context,
              AppRoute.tournamentDetail,
              args: TournamentDetailArgs(tournament.id),
            ),
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
                Text(
                  tournament?.name ?? 'Tournament',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.titleMedium,
                ),
                const SizedBox(height: SportikaSpacing.xxs),
                Text(
                  '${entry.label} · ${tournament?.sport.label ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: SportikaSpacing.xs),
          StatusPill(entry.status.label, color: statusColor(entry.status.key)),
          if (tournament != null)
            Icon(
              Icons.chevron_right_rounded,
              size: 17,
              color: colors.onSurfaceVariant,
            ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// INVITATION CARD
// -----------------------------------------------------------------------------

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.squad});

  final Squad squad;

  @override
  Widget build(BuildContext context) {
    final teams = context.read<TeamsController>();
    final captain = context.watch<SessionController>().accountById(
      squad.ownerId,
    );

    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SportikaRadius.lg),
        border: Border.all(
          color: SportikaColors.gold.withValues(alpha: SportikaOpacity.medium),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: SportikaColors.gold.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(SportikaRadius.md),
                ),
                child: const Icon(
                  Icons.mark_email_unread_outlined,
                  color: SportikaColors.gold,
                ),
              ),
              const SizedBox(width: SportikaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      squad.name,
                      style: SportikaType.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      captain == null
                          ? 'Invitation pending'
                          : '${captain.displayName} invited you',
                      style: SportikaType.caption,
                    ),
                  ],
                ),
              ),
              SportTag(squad.sport, compact: true),
            ],
          ),
          const SizedBox(height: SportikaSpacing.md),
          Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: 'Decline',
                  onPressed: () {
                    teams.respondToInvite(squad.id, accept: false);
                  },
                ),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: PrimaryButton(
                  label: 'Join squad',
                  icon: Icons.check_rounded,
                  tone: SportikaColors.mint,
                  small: true,
                  onPressed: () {
                    teams.respondToInvite(squad.id, accept: true);

                    showSnack(context, 'Joined ${squad.name}');
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// STANDALONE SCREEN
// -----------------------------------------------------------------------------

class TeamsScreen extends StatelessWidget {
  const TeamsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teams')),
      body: const TeamsTab(),
    );
  }
}
