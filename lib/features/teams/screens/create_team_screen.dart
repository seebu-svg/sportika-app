import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/filter_chip_row.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Squad creation, promoted from a modal to a screen so the roster picker has
/// room to breathe and validation can explain itself before submitting.
class CreateTeamScreen extends StatefulWidget {
  const CreateTeamScreen({super.key, this.sport});

  /// Pre-selects a sport when the flow starts from a sport-specific surface.
  final Sport? sport;

  @override
  State<CreateTeamScreen> createState() => _CreateTeamScreenState();
}

class _CreateTeamScreenState extends State<CreateTeamScreen> {
  final _name = TextEditingController();
  final _search = TextEditingController();
  late Sport _sport = widget.sport ?? Sport.padel;
  late EntryType _type = _entryTypeFor(_sport);
  final _members = <String>{};
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  static EntryType _entryTypeFor(Sport sport) => switch (sport) {
    Sport.cricket || Sport.futsal => EntryType.team,
    Sport.padel || Sport.badminton => EntryType.pair,
  };

  /// A pair needs exactly one partner; a team needs at least one as well, but
  /// may grow. Validation runs before the roster is written.
  String? _validate() {
    if (_name.text.trim().length < 3) {
      return 'Give the squad a name of at least 3 characters.';
    }
    if (_members.isEmpty) {
      return _type == EntryType.pair
          ? 'Pick the partner you will play with.'
          : 'Pick at least one player to start the team.';
    }
    if (_type == EntryType.pair && _members.length > 1) {
      return 'A pair is two players. Remove the extra selection or switch to Team.';
    }
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    final teams = context.read<TeamsController>();
    final squad = teams.createSquad(
      name: _name.text,
      sport: _sport,
      type: _type,
      memberIds: _members.toList(),
    );
    // Members picked here have not answered yet, so they are invitations rather
    // than silent additions to the roster.
    for (final id in _members) {
      teams.invite(squad.id, id);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    showSnack(context, '${squad.name} created');
    pushRoute(context, AppRoute.teamDetail, args: TeamDetailArgs(squad.id));
  }

  @override
  Widget build(BuildContext context) {
    final teams = context.watch<TeamsController>();
    final term = _search.text.trim().toLowerCase();
    final candidates = teams.accounts
        .where((a) => !_members.contains(a.id))
        .where(
          (a) =>
              term.isEmpty ||
              '${a.displayName} ${a.city}'.toLowerCase().contains(term),
        )
        .toList();
    final limit = _type == EntryType.pair ? 1 : null;

    return ScreenScaffold(
      title: 'New squad',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenHeader(
            eyebrow: 'Team',
            title: 'Build your squad',
            subtitle: 'Name it, pick the sport, then invite the players.',
          ),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() => _error = null),
            decoration: const InputDecoration(
              labelText: 'Squad name',
              hintText: 'e.g. Karachi Strikers',
            ),
          ),
          const SectionHeader('Sport'),
          FilterChipRow<Sport>(
            label: 'Sport',
            selected: _sport,
            onChanged: (sport) => setState(() {
              _sport = sport;
              _type = _entryTypeFor(sport);
              if (_members.length > 1 && _type == EntryType.pair) {
                _members.removeAll(_members.skip(1).toList());
              }
            }),
            choices: [
              for (final sport in Sport.values)
                FilterChoice(sport, sport.label),
            ],
          ),
          const SectionHeader('Format'),
          FilterChipRow<EntryType>(
            label: 'Format',
            selected: _type,
            tone: SportikaColors.blueBright,
            onChanged: (type) => setState(() => _type = type),
            choices: const [
              FilterChoice(EntryType.pair, 'Pair'),
              FilterChoice(EntryType.team, 'Team'),
            ],
          ),
          SectionHeader(
            limit == null ? 'Roster' : 'Roster · 1 of 1',
            action: _members.isEmpty ? null : 'Clear',
            onAction: () => setState(_members.clear),
          ),
          if (_members.isNotEmpty)
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final id in _members)
                  _SelectedPlayer(
                    account: teams.accounts.firstWhere(
                      (a) => a.id == id,
                      orElse: () => _placeholderAccount(id),
                    ),
                    onRemove: () => setState(() => _members.remove(id)),
                  ),
              ],
            ),
          const SizedBox(height: SportikaSpacing.md),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search players',
              hintText: 'Name or city',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: SportikaSpacing.sm),
          if (candidates.isEmpty)
            const EmptyState(
              title: 'No players match',
              body: 'Try a different name or city.',
              icon: Icons.person_search_outlined,
            )
          else
            for (final player in candidates)
              _CandidateRow(
                player: player,
                disabled: limit != null && _members.length >= limit,
                onAdd: () => setState(() {
                  _members.add(player.id);
                  _error = null;
                }),
              ),
          if (_error != null) ...[
            const SizedBox(height: SportikaSpacing.md),
            InlineBanner(
              text: _error!,
              tone: SportikaColors.danger,
              icon: Icons.error_outline,
            ),
          ],
          const SizedBox(height: SportikaSpacing.lg),
          PrimaryButton(
            label: 'Create squad',
            icon: Icons.check,
            tone: SportikaColors.mint,
            busy: _saving,
            onPressed: _saving ? null : _submit,
          ),
        ],
      ),
    );
  }

  /// Fallback profile for an id that is no longer in the directory.
  Account _placeholderAccount(String id) => Account(
    id: id,
    displayName: 'Player',
    email: '',
    city: '',
    roles: const [UserRole.player],
  );
}

class _SelectedPlayer extends StatelessWidget {
  const _SelectedPlayer({required this.account, required this.onRemove});

  final Account account;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: SportikaColors.mintSubtle,
        borderRadius: BorderRadius.circular(SportikaRadius.pill),
        border: Border.all(color: SportikaColors.mint.withValues(alpha: .4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            account.displayName,
            style: SportikaType.action.copyWith(fontSize: 12),
          ),
          const SizedBox(width: 2),
          IconAction(
            icon: Icons.close,
            label: 'Remove ${account.displayName}',
            size: 15,
            tone: SportikaColors.mint,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.player,
    required this.disabled,
    required this.onAdd,
  });

  final Account player;
  final bool disabled;
  final VoidCallback onAdd;

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
          IconAction(
            icon: Icons.add_circle_outline,
            label: 'Add ${player.displayName}',
            tone: disabled ? SportikaColors.textDim : SportikaColors.mint,
            onPressed: disabled ? null : onAdd,
          ),
        ],
      ),
    );
  }
}
