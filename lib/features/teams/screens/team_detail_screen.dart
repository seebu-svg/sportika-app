import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/fixture_tile.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/teams/widgets/invite_players_sheet.dart';

/// Team detail: roster, pending invitations, tournament entries, schedule,
/// results and a performance summary, plus the captain-only actions.
class TeamDetailScreen extends StatelessWidget {
  const TeamDetailScreen({super.key, required this.squadId});

  final String squadId;

  @override
  Widget build(BuildContext context) {
    final teams = context.watch<TeamsController>();
    final squad = teams.squadById(squadId);
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

    final accounts = context.watch<TeamsController>().accounts;
    final entries = context.watch<TournamentsController>().entries;
    final fixtures = context.watch<FixturesController>().fixtures;
    final me = teams.currentAccountId;
    final isCaptain = squad.ownerId == me;

    Account? accountOf(String id) =>
        accounts.where((a) => a.id == id).firstOrNull;

    final members = squad.memberAccountIds
        .map(accountOf)
        .whereType<Account>()
        .toList();
    final invited = squad.invitedAccountIds
        .map(accountOf)
        .whereType<Account>()
        .toList();
    final myEntries = entries.where((e) => e.squadId == squad.id).toList();
    final entryIds = myEntries.map((e) => e.id).toSet();
    final squadFixtures = fixtures
        .where(
          (f) =>
              entryIds.contains(f.home.entryId) ||
              entryIds.contains(f.away.entryId),
        )
        .toList();
    final results = squadFixtures.where((f) => f.result != null).toList()
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    final upcoming =
        squadFixtures
            .where(
              (f) => f.result == null && f.status != FixtureStatus.cancelled,
            )
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    var won = 0;
    var drawn = 0;
    for (final f in results) {
      final winner = f.result!.winnerIndex;
      if (winner < 0) {
        drawn++;
        continue;
      }
      final mySide = entryIds.contains(f.home.entryId) ? 0 : 1;
      if (winner == mySide) won++;
    }

    return ScreenScaffold(
      title: squad.name,
      actions: [
        IconAction(
          icon: Icons.person_add_alt_1_outlined,
          label: 'Invite players',
          onPressed: () => showInvitePlayersSheet(context, squad.id),
        ),
        const SizedBox(width: 4),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SportTag(squad.sport),
              const SizedBox(width: SportikaSpacing.xs),
              StatusPill(
                squad.type.label,
                color: SportikaColors.blueBright,
                icon: Icons.groups_2_outlined,
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.sm),
          Text(
            '${squad.name} · ${members.length} '
            '${members.length == 1 ? 'player' : 'players'}',
            style: SportikaType.caption,
          ),
          const SectionHeader('Performance'),
          Row(
            children: [
              Expanded(
                child: StatTile(value: '${results.length}', label: 'Played'),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: StatTile(
                  value: '$won',
                  label: 'Won',
                  tone: SportikaColors.mint,
                ),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: StatTile(value: '$drawn', label: 'Drawn'),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: StatTile(
                  value: '${results.length - won - drawn}',
                  label: 'Lost',
                  tone: SportikaColors.danger,
                ),
              ),
            ],
          ),
          SectionHeader(
            'Roster',
            action: isCaptain ? 'Invite' : null,
            onAction: isCaptain
                ? () => showInvitePlayersSheet(context, squad.id)
                : null,
          ),
          for (final member in members)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MemberRow(
                account: member,
                isCaptain: member.id == squad.ownerId,
                isMe: member.id == me,
                canManage: isCaptain,
                onManage: () => _showMemberActions(
                  context,
                  squad: squad,
                  member: member,
                  isCaptain: isCaptain,
                  isMe: member.id == me,
                ),
              ),
            ),
          if (invited.isNotEmpty) ...[
            const SectionHeader('Pending invites'),
            for (final player in invited)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
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
          const SectionHeader('Tournament entries'),
          if (myEntries.isEmpty)
            EmptyState(
              title: 'Not entered yet',
              body:
                  'Enter a tournament from the Tournaments tab to play with '
                  'this squad.',
              icon: Icons.how_to_reg_outlined,
              action: GhostButton(
                label: 'Browse tournaments',
                icon: Icons.emoji_events_outlined,
                onPressed: () => Navigator.of(context).pop(),
              ),
            )
          else
            for (final entry in myEntries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SurfaceCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.label, style: SportikaType.bodyStrong),
                            const SizedBox(height: 2),
                            Text(
                              '${entry.memberAccountIds.length} players · '
                              '${dayLabel(entry.submittedAt)}',
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
          const SectionHeader('Schedule'),
          if (upcoming.isEmpty)
            const EmptyState(
              title: 'No matches scheduled',
              body:
                  'Fixtures appear here once an organizer generates the draw.',
              icon: Icons.event_busy_outlined,
            )
          else
            for (final fixture in upcoming)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
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
          const SectionHeader('Results'),
          if (results.isEmpty)
            const EmptyState(
              title: 'No results yet',
              body: 'Published results and standings land here.',
              icon: Icons.scoreboard_outlined,
            )
          else
            for (final fixture in results)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
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
          if (isCaptain)
            GhostButton(
              label: 'Delete squad',
              icon: Icons.delete_outline,
              tone: SportikaColors.danger,
              expand: true,
              onPressed: () => _confirmDelete(context, squad),
            )
          else
            GhostButton(
              label: 'Leave squad',
              icon: Icons.logout,
              tone: SportikaColors.danger,
              expand: true,
              onPressed: () => _confirmLeave(context, squad),
            ),
        ],
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
          'The squad and its pending invitations are removed. '
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
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      onTap: canManage ? onManage : null,
      child: Row(
        children: [
          AccountAvatar(account: account, size: 34),
          const SizedBox(width: SportikaSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                      const SizedBox(width: 6),
                      const Text('(you)', style: SportikaType.caption),
                    ],
                  ],
                ),
                Text(account.city, style: SportikaType.caption),
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
            const Icon(
              Icons.more_horiz,
              size: 18,
              color: SportikaColors.textDim,
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      borderColor: SportikaColors.gold.withValues(alpha: .35),
      child: Row(
        children: [
          AccountAvatar(account: account, size: 34),
          const SizedBox(width: SportikaSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  account.displayName,
                  style: SportikaType.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Text('Invitation pending', style: SportikaType.caption),
              ],
            ),
          ),
          if (onAccept != null) ...[
            TextButton(
              onPressed: onAccept,
              style: TextButton.styleFrom(
                foregroundColor: SportikaColors.mint,
                minimumSize: const Size(0, 40),
              ),
              child: const Text('Join'),
            ),
            TextButton(
              onPressed: onDecline,
              style: TextButton.styleFrom(
                foregroundColor: SportikaColors.textMuted,
                minimumSize: const Size(0, 40),
              ),
              child: const Text('Decline'),
            ),
          ] else if (canCancel)
            IconAction(
              icon: Icons.close,
              label: 'Cancel invite for ${account.displayName}',
              onPressed: onCancel,
            ),
        ],
      ),
    );
  }
}
