import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/monetization_controller.dart';
import 'package:sportika/core/state/profile_module_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/features/profile/widgets/achievements.dart';
import 'package:sportika/features/profile/widgets/passport_section.dart';
import 'package:sportika/features/profile/widgets/sporting_record.dart';
import 'package:sportika/features/profile/widgets/sports_passport.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/identity_document.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/profile_module.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Me: the member's Sports Passport.
///
/// One passport card, the sports they actually play, their official record,
/// the part of their journey the records can prove, their teams, and the
/// account controls underneath. Identity rows come from
/// [ProfileModuleController] (PostgreSQL in a connected build, the device
/// document in a demo build); results, teams and tournaments stay on the
/// stores that own them, so nothing working had to be duplicated.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProfileModuleController>().ensureLoaded();
    });
  }

  Future<void> _refresh() async {
    final module = context.read<ProfileModuleController>();
    final profile = context.read<ProfileRepository>();
    final fixtures = context.read<FixtureRepository>();
    final tournaments = context.read<TournamentRepository>();
    final teams = context.read<TeamRepository>();
    await Future.wait([
      module.refresh(),
      profile.reload(),
      fixtures.refresh(),
      tournaments.refresh(),
      teams.refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SessionController>();
    final module = context.watch<ProfileModuleController>();
    final me = context.watch<ProfileController>().currentAccount;
    if (me == null) return const SizedBox.shrink();

    final snapshot = module.snapshot;
    final fixtures = context.watch<FixturesController>();
    final tournaments = context.watch<TournamentsController>();
    final teams = context.watch<TeamsController>();

    final myEntries = tournaments.entries
        .where(
          (entry) =>
              entry.memberAccountIds.contains(me.id) &&
              entry.status != EntryStatus.withdrawn,
        )
        .toList();
    final myEntryIds = myEntries.map((entry) => entry.id).toSet();
    final official = memberOfficialFixtures(
      fixtures: fixtures.fixtures,
      myEntryIds: myEntryIds,
    );
    final record = sportingRecordOf(
      fixtures: fixtures.fixtures,
      myEntryIds: myEntryIds,
    );
    final sports = snapshot?.sports ?? const <ProfileSportPreference>[];
    final squads = teams.squads
        .where((squad) => squad.memberAccountIds.contains(me.id))
        .toList();
    final activeTournaments = <Tournament>[
      for (final id in myEntries.map((entry) => entry.tournamentId).toSet())
        if (tournaments.tournamentById(id) case final Tournament tournament)
          if (tournament.status != TournamentStatus.completed &&
              tournament.status != TournamentStatus.draft)
            tournament,
    ];
    final tournamentCount = tournaments.tournaments
        .where(
          (tournament) =>
              tournament.organizerId == me.id ||
              myEntries.any((entry) => entry.tournamentId == tournament.id),
        )
        .length;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: SportikaColors.mint,
      backgroundColor: SportikaColors.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
        children: [
          Text(
            'MY PASSPORT',
            style: SportikaType.hero.copyWith(fontSize: 30, letterSpacing: .4),
          ),
          const SizedBox(height: 12),
          SportsPassportCard(
            account: me,
            onEditProfile: () => pushRoute(context, AppRoute.editProfile),
          ),
          if (!me.setupComplete) ...[
            const SizedBox(height: 12),
            const InlineBanner(
              text:
                  'Some passport details are still missing. Complete them so '
                  'organizers can recognize you.',
            ),
          ],
          if (snapshot == null && module.error != null) ...[
            const SizedBox(height: 16),
            ErrorState(
              title: 'Your profile card could not be loaded',
              message: module.error,
              compact: true,
              onRetry: module.refresh,
            ),
          ] else if (snapshot == null) ...[
            const SizedBox(height: 18),
            const LoadingSkeleton(rows: 2, label: 'Loading profile'),
          ],
          if (snapshot != null)
            PassportSection(
              title: 'My sports',
              detail: sports.isEmpty
                  ? null
                  : '${sports.length.toString().padLeft(2, '0')} selected',
              action: 'Edit sports',
              onAction: () => pushRoute(context, AppRoute.sportsPreferences),
              child: sports.isEmpty
                  ? _EmptyPassportCard(
                      icon: Icons.sports_outlined,
                      title: 'No preferred sports yet',
                      body:
                          'Choose the sports you play to complete your '
                          'passport.',
                      action: GhostButton(
                        label: 'Choose sports',
                        icon: Icons.tune,
                        onPressed: () =>
                            pushRoute(context, AppRoute.sportsPreferences),
                      ),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final preference in sports)
                          _SportChip(preference: preference),
                      ],
                    ),
            ),
          PassportSection(
            title: 'Sporting record',
            detail: 'Official published results only',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SportingRecordStrip(record: record),
                if (record.draws > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    record.draws == 1
                        ? '1 match drawn · a draw counts as neither a win nor '
                              'a loss'
                        : '${record.draws} matches drawn · a draw counts as '
                              'neither a win nor a loss',
                    style: SportikaType.caption,
                  ),
                ],
                if (record.isEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Your first official result sets your win rate.',
                    style: SportikaType.caption,
                  ),
                ],
              ],
            ),
          ),
          const SportStatisticsCard(),
          PassportSection(
            title: 'My journey',
            detail: official.isEmpty && activeTournaments.isEmpty
                ? 'Nothing played yet'
                : [
                    if (activeTournaments.isNotEmpty)
                      '${activeTournaments.length} active '
                          '${activeTournaments.length == 1 ? 'tournament' : 'tournaments'}',
                    if (official.isNotEmpty)
                      '${official.length} official '
                          '${official.length == 1 ? 'match' : 'matches'}',
                  ].join(' · '),
            action: 'View history',
            onAction: () => pushRoute(context, AppRoute.matchHistory),
            child: official.isEmpty && activeTournaments.isEmpty
                ? FirstMatchCard(
                    onFindTournament: () => openHomeTab(context, 1),
                  )
                : _JourneyList(
                    activeTournaments: activeTournaments.take(2).toList(),
                    matches: official.take(3).toList(),
                    myEntryIds: myEntryIds,
                    fixtures: fixtures,
                  ),
          ),
          PassportSection(
            title: 'My teams',
            detail: squads.isEmpty
                ? null
                : '${squads.length} ${squads.length == 1 ? 'team' : 'teams'}',
            action: 'View all',
            onAction: () => pushRoute(context, AppRoute.teamMemberships),
            child: _TeamsList(
              squads: squads.take(3).toList(),
              invites: teams.myInvites.length,
              meId: me.id,
            ),
          ),
          const PassportAchievements(),
          const SectionTitle('Account & settings'),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                SheetOption(
                  icon: Icons.person_outline,
                  title: 'Personal information',
                  subtitle: 'Name, handle, date of birth, city and bio',
                  onTap: () => pushRoute(context, AppRoute.personalInformation),
                ),
                SheetOption(
                  icon: Icons.tune,
                  title: 'Sports preferences',
                  subtitle: sports.isEmpty
                      ? 'Choose the sports you play'
                      : '${sports.length} preferred '
                            '${sports.length == 1 ? 'sport' : 'sports'}',
                  tone: SportikaColors.mint,
                  onTap: () => pushRoute(context, AppRoute.sportsPreferences),
                ),
                SheetOption(
                  icon: Icons.badge_outlined,
                  title: 'Identity documents',
                  subtitle: snapshot?.identity == null
                      ? 'CNIC or B-Form · optional'
                      : '${snapshot!.identity!.kind.label} on file',
                  tone: SportikaColors.gold,
                  onTap: () => pushRoute(context, AppRoute.identityDocuments),
                ),
                SheetOption(
                  icon: Icons.lock_outline,
                  title: 'Settings & privacy',
                  subtitle: 'Notifications, privacy and local data',
                  onTap: () => pushRoute(context, AppRoute.settings),
                ),
                SheetOption(
                  icon: Icons.workspace_premium_outlined,
                  title: 'Billing & plans',
                  subtitle: context.watch<MonetizationController>().isPro
                      ? 'Organizer Pro is active'
                      : 'Tournament pass, Organizer Pro, payment history',
                  tone: SportikaColors.gold,
                  onTap: () => pushRoute(context, AppRoute.pricing),
                ),
              ],
            ),
          ),
          const SectionTitle('Records'),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                SheetOption(
                  icon: Icons.emoji_events_outlined,
                  title: 'Tournament history',
                  subtitle: tournamentCount == 0
                      ? 'No tournaments yet'
                      : '$tournamentCount '
                            '${tournamentCount == 1 ? 'tournament' : 'tournaments'}',
                  onTap: () => pushRoute(context, AppRoute.tournamentHistory),
                ),
                SheetOption(
                  icon: Icons.sports_score,
                  title: 'Scorer assignments',
                  subtitle: 'Matches you score or hand over',
                  tone: SportikaColors.blueBright,
                  onTap: () => pushRoute(context, AppRoute.scorerAssignments),
                ),
              ],
            ),
          ),
          if (state.canOrganize || fixtures.myScoringFixtures.isNotEmpty) ...[
            const SectionTitle('Your sports tools'),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  if (state.canOrganize)
                    SheetOption(
                      icon: Icons.dashboard_customize_outlined,
                      title: 'My tournaments',
                      subtitle: 'Events, entries, draws, result review',
                      tone: SportikaColors.mint,
                      onTap: () =>
                          pushRoute(context, AppRoute.organizerDashboard),
                    ),
                  if (fixtures.myScoringFixtures.isNotEmpty)
                    SheetOption(
                      icon: Icons.scoreboard_outlined,
                      title: 'Scorer workspace',
                      subtitle:
                          '${fixtures.myScoringFixtures.length} fixtures assigned',
                      tone: SportikaColors.blueBright,
                      onTap: () => pushRoute(context, AppRoute.scorerWorkspace),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: SportikaSpacing.md),
          const InfoBanner(
            icon: Icons.info_outline,
            text:
                'Sportika prototype · Cricket, Padel, Futsal and Badminton. '
                'Personal scorecards and official results are separate records.',
          ),
        ],
      ),
    );
  }
}

/// One preferred sport as a compact passport chip: glyph, name, claimed level.
class _SportChip extends StatelessWidget {
  const _SportChip({required this.preference});

  final ProfileSportPreference preference;

  @override
  Widget build(BuildContext context) {
    final tone = sportColor(preference.sport);
    final detail = [
      if (preference.level != null) preference.level!.label,
      if (preference.position != null) preference.position!,
    ].join(' · ');

    return Semantics(
      label: '${preference.sport.label}${detail.isEmpty ? '' : ', $detail'}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        decoration: BoxDecoration(
          color: SportikaColors.surfaceSunken,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tone.withValues(alpha: .32)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 28,
              width: 28,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Center(
                child: SportGlyph(
                  sport: preference.sport,
                  size: 16,
                  color: tone,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  preference.sport.label,
                  style: SportikaType.bodyStrong.copyWith(fontSize: 12.5),
                ),
                Text(
                  detail.isEmpty ? 'No level set' : detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.caption.copyWith(fontSize: 10.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Active tournaments first, then the most recent published results.
class _JourneyList extends StatelessWidget {
  const _JourneyList({
    required this.activeTournaments,
    required this.matches,
    required this.myEntryIds,
    required this.fixtures,
  });

  final List<Tournament> activeTournaments;
  final List<Fixture> matches;
  final Set<String> myEntryIds;
  final FixturesController fixtures;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      for (final tournament in activeTournaments)
        _JourneyRow(
          leading: const _JourneyBadge(
            icon: Icons.emoji_events_outlined,
            tone: SportikaColors.blueBright,
          ),
          title: tournament.name,
          subtitle:
              '${tournament.sport.label} · ${tournament.status.label} · '
              'starts ${dayLabel(tournament.startsAt)}',
          onTap: () => pushRoute(
            context,
            AppRoute.tournamentDetail,
            args: TournamentDetailArgs(tournament.id),
          ),
        ),
      for (final fixture in matches)
        _JourneyRow(
          leading: _OutcomeBadge(outcome: outcomeOf(fixture, myEntryIds)),
          title:
              fixtures.tournamentOf(fixture)?.name ??
              'Official tournament match',
          subtitle: _matchLine(fixture),
          onTap: () => pushRoute(
            context,
            AppRoute.fixtureDetail,
            args: FixtureDetailArgs(fixture.id),
          ),
        ),
    ];

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            rows[i],
          ],
        ],
      ),
    );
  }

  String _matchLine(Fixture fixture) {
    final mySide = myEntryIds.contains(fixture.home.entryId) ? 0 : 1;
    final opponent = fixtures.sideLabel(fixture, mySide == 0 ? 1 : 0);
    final stage = fixture.stage.isEmpty
        ? 'Round ${fixture.round}'
        : fixture.stage;
    final when = dayLabel(fixture.completedAt ?? fixture.scheduledAt);
    return '$stage · vs $opponent · $when';
  }
}

/// The member's squads, plus any invitation still waiting on an answer.
class _TeamsList extends StatelessWidget {
  const _TeamsList({
    required this.squads,
    required this.invites,
    required this.meId,
  });

  final List<Squad> squads;
  final int invites;
  final String meId;

  @override
  Widget build(BuildContext context) {
    if (squads.isEmpty && invites == 0) {
      return _EmptyPassportCard(
        icon: Icons.groups_outlined,
        title: 'No teams yet',
        body:
            'Create a squad or accept an invitation and your teams appear '
            'here.',
        action: GhostButton(
          label: 'Manage teams',
          icon: Icons.group_add_outlined,
          onPressed: () => pushRoute(context, AppRoute.teamMemberships),
        ),
      );
    }

    final rows = <Widget>[
      if (invites > 0)
        _JourneyRow(
          leading: const _JourneyBadge(
            icon: Icons.mail_outline,
            tone: SportikaColors.gold,
          ),
          title: invites == 1
              ? 'Team invitation waiting'
              : '$invites team invitations waiting',
          subtitle: 'Answer from Team memberships',
          onTap: () => pushRoute(context, AppRoute.teamMemberships),
        ),
      for (final squad in squads)
        _JourneyRow(
          leading: _SquadBadge(squad: squad),
          title: squad.name,
          subtitle:
              '${squad.sport.label} · ${squad.memberAccountIds.length} '
              '${squad.memberAccountIds.length == 1 ? 'player' : 'players'}'
              '${squad.ownerId == meId ? ' · Captain' : ''}',
          onTap: () => pushRoute(
            context,
            AppRoute.teamDetail,
            args: TeamDetailArgs(squad.id),
          ),
        ),
    ];

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _SquadBadge extends StatelessWidget {
  const _SquadBadge({required this.squad});

  final Squad squad;

  @override
  Widget build(BuildContext context) {
    final tone = sportColor(squad.sport);
    return Container(
      height: 32,
      width: 32,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: tone.withValues(alpha: .34)),
      ),
      child: Center(
        child: SportGlyph(sport: squad.sport, size: 16, color: tone),
      ),
    );
  }
}

class _JourneyRow extends StatelessWidget {
  const _JourneyRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
          child: Row(
            children: [
              leading,
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SportikaType.bodyStrong,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SportikaType.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                size: 17,
                color: SportikaColors.textDim,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JourneyBadge extends StatelessWidget {
  const _JourneyBadge({required this.icon, required this.tone});

  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      width: 30,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: tone.withValues(alpha: .34)),
      ),
      child: Icon(icon, size: 15, color: tone),
    );
  }
}

class _OutcomeBadge extends StatelessWidget {
  const _OutcomeBadge({required this.outcome});

  final SportingOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final tone = outcome.tone;
    return Container(
      height: 30,
      width: 30,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: tone.withValues(alpha: .38)),
      ),
      child: Center(
        child: Text(
          outcome.letter,
          style: TextStyle(
            fontFamily: SportikaType.displayFamily,
            fontSize: 15,
            height: 1,
            fontWeight: FontWeight.w800,
            color: tone,
          ),
        ),
      ),
    );
  }
}

/// Quiet in-place empty state: one line of copy and, at most, one action.
class _EmptyPassportCard extends StatelessWidget {
  const _EmptyPassportCard({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      fillColor: SportikaColors.surfaceSunken,
      borderColor: SportikaColors.borderSubtle,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 34,
            width: 34,
            decoration: BoxDecoration(
              color: SportikaColors.surfaceAlt,
              borderRadius: BorderRadius.circular(SportikaRadius.sm),
              border: Border.all(color: SportikaColors.borderSubtle),
            ),
            child: Icon(icon, size: 17, color: SportikaColors.textDim),
          ),
          const SizedBox(width: SportikaSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: SportikaType.bodyStrong),
                const SizedBox(height: 3),
                Text(body, style: SportikaType.caption),
                if (action != null) ...[const SizedBox(height: 12), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
