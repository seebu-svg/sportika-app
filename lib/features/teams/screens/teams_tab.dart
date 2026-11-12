import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/live/screens/notifications_screen.dart';

/// Teams & registration (spec §5): form a pair or team, manage the roster,
/// then enter tournaments with it.
class TeamsTab extends StatelessWidget {
  const TeamsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SessionController>();
    context.watch<SessionController>();
    final squads = context.read<TeamsController>().mySquads;
    final me = context.read<ProfileController>().currentAccount;
    final entries =
        context
            .read<TournamentsController>()
            .entries
            .where(
              (e) =>
                  me != null &&
                  e.memberAccountIds.contains(me.id) &&
                  e.status != EntryStatus.withdrawn,
            )
            .toList()
          ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    final players = state.accounts
        .where((a) => a.has(UserRole.player))
        .toList();
    final invites = context.read<TeamsController>().myInvites;

    return Column(
      children: [
        TabHeader(
          title: 'Team',
          subtitle:
              '${squads.length} squads · ${entries.length} tournament entries',
          actions: const [NotificationBell(), SizedBox(width: 16)],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              if (invites.isNotEmpty) ...[
                const SectionTitle('Invitations'),
                for (final invite in invites)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _InviteCard(squad: invite),
                  ),
              ],
              PrimaryButton(
                label: 'Create a team or pair',
                icon: Icons.group_add_outlined,
                tone: SportikaColors.mint,
                onPressed: () => pushRoute(context, AppRoute.createTeam),
              ),
              const SectionTitle('My squads'),
              if (squads.isEmpty)
                const EmptyState(
                  title: 'No squads yet',
                  body:
                      'Build a pair for padel or badminton, or a team for cricket and '
                      'futsal, then enter a tournament with it.',
                  icon: Icons.groups_outlined,
                )
              else
                for (final squad in squads)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _SquadCard(squad: squad),
                  ),
              const SectionTitle('My entries'),
              if (entries.isEmpty)
                const EmptyState(
                  title: 'No tournament entries',
                  body: 'Registration status and organizer decisions appear here.',
                  icon: Icons.how_to_reg_outlined,
                )
              else
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _EntryRow(entry: entry),
                  ),
              const SectionTitle('Players'),
              for (final player in players)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PlayerRow(player: player),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SquadCard extends StatelessWidget {
  const _SquadCard({required this.squad});

  final Squad squad;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SessionController>();
    final tone = sportColor(squad.sport);
    final memberNames = squad.memberAccountIds
        .map((id) => state.accountById(id)?.displayName)
        .whereType<String>()
        .toList();

    return SurfaceCard(
      onTap: () => pushRoute(
        context,
        AppRoute.teamDetail,
        args: TeamDetailArgs(squad.id),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SportTag(squad.sport, compact: true),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  squad.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: SportikaColors.text,
                  ),
                ),
              ),
              Text(
                '${memberNames.length} ${squad.type.label.toLowerCase()}',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: SportikaColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              for (final member in squad.memberAccountIds)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PlayerAvatar(
                      initials: initialsOf(
                        state.accountById(member)?.displayName ?? '?',
                      ),
                      size: 22,
                      color: tone,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      state.accountById(member)?.displayName.split(' ').first ??
                          'Player',
                      style: const TextStyle(
                        fontSize: 11,
                        color: SportikaColors.textBody,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    context.watch<SessionController>();
    final tournament = context.read<TournamentsController>().tournamentById(
      entry.tournamentId,
    );

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      onTap: tournament == null
          ? null
          : () => pushRoute(
              context,
              AppRoute.tournamentDetail,
              args: TournamentDetailArgs(tournament.id),
            ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tournament?.name ?? 'Tournament',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: SportikaColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.label} · ${tournament?.sport.label ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: SportikaColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          StatusPill(entry.status.label, color: statusColor(entry.status.key)),
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player});

  final Account player;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      child: Row(
        children: [
          AccountAvatar(account: player, size: 34),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  player.displayName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: SportikaColors.text,
                  ),
                ),
                Text(
                  player.roles.map((r) => r.label).join(' · '),
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: SportikaColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            player.city,
            style: const TextStyle(fontSize: 11, color: SportikaColors.textDim),
          ),
        ],
      ),
    );
  }
}

class TeamsScreen extends StatelessWidget {
  const TeamsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My teams')),
    body: const TeamsTab(),
  );
}

/// A squad that invited the current account, with the two answers available
/// straight from the Team tab.
class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.squad});

  final Squad squad;

  @override
  Widget build(BuildContext context) {
    final teams = context.read<TeamsController>();
    final captain = context.read<SessionController>().accountById(
      squad.ownerId,
    );
    return SurfaceCard(
      borderColor: SportikaColors.gold.withValues(alpha: .35),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SportTag(squad.sport, compact: true),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  squad.name,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: SportikaColors.text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            captain == null
                ? 'Invitation pending'
                : '${captain.displayName} invited you',
            style: const TextStyle(
              fontSize: 11.5,
              color: SportikaColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              GhostButton(
                label: 'Decline',
                onPressed: () => teams.respondToInvite(squad.id, accept: false),
              ),
              const SizedBox(width: 8),
              GhostButton(
                label: 'Join squad',
                icon: Icons.check,
                tone: SportikaColors.mint,
                onPressed: () {
                  teams.respondToInvite(squad.id, accept: true);
                  showSnack(context, 'Joined ${squad.name}');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
