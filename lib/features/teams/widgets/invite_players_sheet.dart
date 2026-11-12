import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Search-and-send sheet for squad invitations. Every send persists through the
/// repository, so the pending list survives a restart and the captain can see
/// who has not answered yet.
Future<void> showInvitePlayersSheet(BuildContext context, String squadId) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: SportikaColors.surfaceElevated,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _InvitePlayersSheet(squadId: squadId),
  );
}

class _InvitePlayersSheet extends StatefulWidget {
  const _InvitePlayersSheet({required this.squadId});

  final String squadId;

  @override
  State<_InvitePlayersSheet> createState() => _InvitePlayersSheetState();
}

class _InvitePlayersSheetState extends State<_InvitePlayersSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final teams = context.watch<TeamsController>();
    final squad = teams.squadById(widget.squadId);
    final candidates = teams.inviteCandidates(widget.squadId, _search.text);
    final invited = (squad?.invitedAccountIds ?? [])
        .map((id) => teams.accounts.where((a) => a.id == id).firstOrNull)
        .whereType<Account>()
        .toList();

    return AppSheet(
      title: 'Invite players',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              labelText: 'Search players',
              hintText: 'Name or city',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          if (invited.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('PENDING INVITES', style: SportikaType.label),
            const SizedBox(height: 4),
            for (final player in invited)
              _InviteRow(
                player: player,
                trailing: IconAction(
                  icon: Icons.close,
                  label: 'Cancel invite for ${player.displayName}',
                  onPressed: () =>
                      teams.cancelInvite(widget.squadId, player.id),
                ),
              ),
          ],
          const SizedBox(height: 16),
          if (squad == null)
            const EmptyState(
              title: 'Squad removed',
              body: 'This squad no longer exists.',
            )
          else if (candidates.isEmpty)
            const EmptyState(
              title: 'Nobody left to invite',
              body:
                  'Every player matching this search is already on the squad '
                  'or has a pending invitation.',
              icon: Icons.group_add_outlined,
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: candidates.length,
                itemBuilder: (context, index) {
                  final player = candidates[index];
                  return _InviteRow(
                    player: player,
                    trailing: TextButton(
                      onPressed: () {
                        teams.invite(widget.squadId, player.id);
                        showSnack(
                          context,
                          'Invite sent to ${player.displayName}',
                        );
                      },
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        foregroundColor: SportikaColors.mint,
                      ),
                      child: const Text('Invite', style: SportikaType.action),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _InviteRow extends StatelessWidget {
  const _InviteRow({required this.player, required this.trailing});

  final Account player;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          AccountAvatar(account: player, size: 32),
          const SizedBox(width: SportikaSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  player.displayName,
                  style: SportikaType.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(player.city, style: SportikaType.caption),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
