import 'package:sportika/shared/widgets/editorial.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/live/screens/notifications_screen.dart';
import 'package:sportika/shared/widgets/fixture_tile.dart';
import 'package:sportika/features/profile/widgets/achievements.dart';
import 'package:sportika/core/state/fixtures_controller.dart';

/// Profile, roles, history entry points and the demo-data controls.
class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SessionController>();
    final me = context.read<ProfileController>().currentAccount;
    if (me == null) return const SizedBox.shrink();

    final official = context.read<ProfileController>().officialMatchesPlayed();
    final entryIds = context
        .read<TournamentsController>()
        .entries
        .where((e) => e.memberAccountIds.contains(me.id))
        .map((e) => e.id)
        .toSet();
    final wins = official
        .where(
          (f) =>
              f.result?.winnerIndex ==
              (entryIds.contains(f.home.entryId) ? 0 : 1),
        )
        .length;
    final losses =
        official.where((f) => f.result?.winnerIndex != null).length - wins;

    return Column(
      children: [
        const TabHeader(
          title: 'Me',
          subtitle: 'Your profile, statistics, history and settings.',
          actions: [NotificationBell(), SizedBox(width: 16)],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              const EditorialBanner(
                eyebrow: 'THE SPORTIKA ATHLETE',
                title: 'BUILT TO\nKEEP GOING.',
                subtitle: 'Every match is another chapter.',
                height: 206,
              ),
              const SizedBox(height: 14),
              SurfaceCard(
                child: Row(
                  children: [
                    AccountAvatar(account: me, size: 56),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            me.displayName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              color: SportikaColors.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${me.city} · ${me.email}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: SportikaColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 5,
                            runSpacing: 4,
                            children: [
                              for (final role in me.roles)
                                StatusPill(
                                  role.label,
                                  color: SportikaColors.blueBright,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit profile',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () => pushRoute(context, AppRoute.editProfile),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      value: '${official.length}',
                      label: 'Matches',
                      tone: SportikaColors.blueBright,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      value: '$wins',
                      label: 'Wins',
                      tone: SportikaColors.mint,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      value: '$losses',
                      label: 'Losses',
                      tone: SportikaColors.gold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Win rate · ${official.isEmpty ? 0 : (100 * wins / official.length).round()}%',
                style: const TextStyle(
                  color: SportikaColors.mint,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: official.isEmpty ? 0 : wins / official.length,
              ),
              const SectionTitle('My sports'),
              for (final sport in Sport.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(sportGlyph(sport), color: SportikaColors.mint),
                  title: Text(sport.label),
                  subtitle: Text(
                    '${official.where((f) => context.read<FixturesController>().tournamentOf(f)?.sport == sport).length} official appearances',
                  ),
                  trailing: sport == Sport.cricket
                      ? const StatusPill('Primary', color: SportikaColors.mint)
                      : null,
                ),
              SectionTitle(
                'My teams',
                action: 'View teams',
                onAction: () => openHomeTab(context, 3),
              ),
              for (final team
                  in context
                      .read<TeamsController>()
                      .squads
                      .where((s) => s.memberAccountIds.contains(me.id))
                      .take(3))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.groups_outlined),
                  title: Text(team.name),
                  subtitle: Text(
                    '${team.sport.label} · ${team.memberAccountIds.length} players',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openHomeTab(context, 3),
                ),
              const AchievementsSection(),
              const SportStatisticsSection(),
              SectionTitle(
                'Official match history',
                action: 'View all',
                onAction: () => pushRoute(context, AppRoute.matchHistory),
              ),
              if (official.isEmpty)
                const EmptyState(
                  title: 'A fresh start',
                  body: 'Completed official matches will appear here.',
                  icon: Icons.history,
                ),
              for (final match in official.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: officialFixtureTile(context, match),
                ),
              const SectionTitle('Account'),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Column(
                  children: [
                    SheetOption(
                      icon: Icons.settings_outlined,
                      title: 'Settings',
                      subtitle: 'Notifications, privacy and local data',
                      onTap: () => pushRoute(context, AppRoute.settings),
                    ),
                    SheetOption(
                      icon: Icons.badge_outlined,
                      title: 'Edit profile',
                      subtitle: 'Name, city and email',
                      onTap: () => pushRoute(context, AppRoute.editProfile),
                    ),
                    SheetOption(
                      icon: Icons.history,
                      title: 'Match history',
                      subtitle: 'Resume private cards, see official results',
                      tone: SportikaColors.mint,
                      onTap: () => pushRoute(context, AppRoute.matchHistory),
                    ),
                    SheetOption(
                      icon: Icons.notifications_none,
                      title: 'Notifications',
                      subtitle:
                          context.read<NotificationsController>().unreadCount ==
                              0
                          ? 'All caught up'
                          : '${context.read<NotificationsController>().unreadCount} unread',
                      tone: SportikaColors.gold,
                      onTap: () => pushRoute(context, AppRoute.notifications),
                    ),
                  ],
                ),
              ),
              if (state.canOrganize || state.hasRole(UserRole.scorer)) ...[
                const SectionTitle('Tools for your roles'),
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      if (state.canOrganize)
                        SheetOption(
                          icon: Icons.dashboard_customize_outlined,
                          title: 'Organizer dashboard',
                          subtitle: 'Events, entries, draws, result review',
                          tone: SportikaColors.mint,
                          onTap: () =>
                              pushRoute(context, AppRoute.organizerDashboard),
                        ),
                      if (state.hasRole(UserRole.scorer))
                        SheetOption(
                          icon: Icons.sports_score,
                          title: 'Scorer workspace',
                          subtitle:
                              '${context.read<FixturesController>().myScoringFixtures.length} fixtures assigned',
                          tone: SportikaColors.blueBright,
                          onTap: () =>
                              pushRoute(context, AppRoute.scorerWorkspace),
                        ),
                    ],
                  ),
                ),
              ],
              const SectionTitle('About'),
              const InfoBanner(
                icon: Icons.info_outline,
                text:
                    'Sportika prototype · Cricket, Padel, Futsal and Badminton. '
                    'Personal scorecards and official results are separate records, '
                    'and everything is stored on this device.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
