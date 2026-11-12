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
              const SectionTitle('Achievements'),
              SurfaceCard(
                child: Row(
                  children: [
                    const Icon(
                      Icons.emoji_events_outlined,
                      color: SportikaColors.gold,
                      size: 32,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        official.isEmpty
                            ? 'Your story starts here. Play an official match to unlock your first milestone.'
                            : '${official.length} official matches · $wins victories. Keep chasing your next milestone.',
                      ),
                    ),
                  ],
                ),
              ),
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
              const SectionTitle('Preferences'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Match reminders'),
                subtitle: const Text('Local demo preference'),
                value: context.read<PreferencesController>().preference(
                  'reminders',
                ),
                onChanged: (v) => context
                    .read<PreferencesController>()
                    .setPreference('reminders', v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Community invitations'),
                value: context.read<PreferencesController>().preference(
                  'invites',
                ),
                onChanged: (v) => context
                    .read<PreferencesController>()
                    .setPreference('invites', v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show sports profile'),
                subtitle: const Text(
                  'Demo visibility preference; personal scores always stay private.',
                ),
                value: context.read<PreferencesController>().preference(
                  'publicProfile',
                ),
                onChanged: (v) => context
                    .read<PreferencesController>()
                    .setPreference('publicProfile', v),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.badge_outlined),
                title: const Text('My roles'),
                subtitle: Text(me.roles.map((r) => r.label).join(' · ')),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Your Sportika roles'),
                    content: Text(
                      'Active roles: ${me.roles.map((r) => r.label).join(', ')}. Use Switch account to try another demo role. Official scoring requires an assignment, and organizer tools unlock with the organizer role.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('Got it'),
                      ),
                    ],
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.help_outline),
                title: const Text('Help and support'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Get into the game'),
                    content: const Text(
                      'Games: discover a match and reserve your spot. Events: enter competitions and follow fixtures. Scores: follow official results or keep private scorecards. All data is fictional and stored on this device. Reset demo data restores the original world.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ),
              const SectionTitle('Session'),
              GhostButton(
                label: 'Switch account',
                icon: Icons.logout,
                expand: true,
                onPressed: state.signOut,
              ),
              const SizedBox(height: 8),
              GhostButton(
                label: 'Reset demo data',
                icon: Icons.restart_alt,
                tone: SportikaColors.danger,
                expand: true,
                onPressed: () => _resetDemo(context, state),
              ),
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

  Future<void> _resetDemo(BuildContext context, SessionController state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset demo data?'),
        content: const Text(
          'Every scorecard, entry and result recorded in this prototype is replaced '
          'with the original demo world.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Reset',
              style: TextStyle(color: SportikaColors.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await state.resetDemoData();
    if (context.mounted) showSnack(context, 'Demo data restored');
  }
}
