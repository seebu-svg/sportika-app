import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/live/screens/notifications_screen.dart';
import 'package:sportika/features/discover/screens/tournament_detail_screen.dart';

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
              PrimaryButton(
                label: 'Create a team or pair',
                icon: Icons.group_add_outlined,
                tone: SportikaColors.mint,
                onPressed: () => _createSquad(context, state),
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

  Future<void> _createSquad(
    BuildContext context,
    SessionController state,
  ) async {
    final name = TextEditingController();
    var sport = Sport.padel;
    var type = SportEngines.defaultEntryType(sport);
    final members = <String>{};

    final created = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: SportikaColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => AppSheet(
          title: 'New squad',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Squad name',
                  hintText: 'e.g. Karachi Strikers',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final s in Sport.values)
                    _PickChip(
                      label: s.label,
                      active: s == sport,
                      tone: sportColor(s),
                      onTap: () => setSheetState(() {
                        sport = s;
                        type = SportEngines.defaultEntryType(s);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                children: [
                  for (final t in EntryType.values)
                    _PickChip(
                      label: t.label,
                      active: t == type,
                      tone: SportikaColors.blueBright,
                      onTap: () => setSheetState(() => type = t),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'INVITE PLAYERS',
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                  color: SportikaColors.textDim,
                ),
              ),
              const SizedBox(height: 6),
              for (final player in context.read<TeamsController>().otherPlayers)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: members.contains(player.id),
                  activeColor: SportikaColors.mint,
                  title: Text(
                    player.displayName,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: SportikaColors.text,
                    ),
                  ),
                  subtitle: Text(
                    player.city,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: SportikaColors.textDim,
                    ),
                  ),
                  onChanged: (checked) => setSheetState(() {
                    if (checked == true) {
                      members.add(player.id);
                    } else {
                      members.remove(player.id);
                    }
                  }),
                ),
              const SizedBox(height: 12),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: name,
                builder: (_, value, _) => PrimaryButton(
                  label: 'Create squad',
                  icon: Icons.check,
                  tone: SportikaColors.mint,
                  onPressed: value.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(sheetContext, true),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!context.mounted) return;
    if (created == true && name.text.trim().isNotEmpty) {
      context.read<TeamsController>().createSquad(
        name: name.text,
        sport: sport,
        type: type,
        memberIds: members.toList(),
      );
      if (context.mounted) showSnack(context, '${name.text.trim()} created');
    }
    name.dispose();
  }
}

class _PickChip extends StatelessWidget {
  const _PickChip({
    required this.label,
    required this.active,
    required this.tone,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? tone.withValues(alpha: 0.16)
              : SportikaColors.surfaceSunken,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? tone : SportikaColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: active ? tone : SportikaColors.textBody,
          ),
        ),
      ),
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
      onTap: () => _showSquad(context, state, squad),
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

  void _showSquad(BuildContext context, SessionController state, Squad squad) {
    showAppSheet(
      context,
      AppSheet(
        title: squad.name,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SportTag(squad.sport),
                const SizedBox(width: 8),
                Text(
                  squad.type.label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: SportikaColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final member in squad.memberAccountIds)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    AccountAvatar(
                      account:
                          state.accountById(member) ??
                          Account(
                            id: member,
                            displayName: 'Player',
                            email: '',
                            city: '',
                            roles: const [],
                          ),
                      size: 30,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        state.accountById(member)?.displayName ?? 'Player',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: SportikaColors.text,
                        ),
                      ),
                    ),
                    if (member != squad.ownerId)
                      IconButton(
                        icon: const Icon(
                          Icons.person_remove_outlined,
                          size: 17,
                          color: SportikaColors.danger,
                        ),
                        onPressed: () => context
                            .read<TeamsController>()
                            .removeSquadMember(squad.id, member),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            InfoBanner(
              text:
                  'Enter a ${squad.sport.label} tournament from the Tournaments tab and '
                  'pick ${squad.name} as your entry.',
            ),
          ],
        ),
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
          : () =>
                pushScreen(context, TournamentDetailScreen(id: tournament.id)),
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
