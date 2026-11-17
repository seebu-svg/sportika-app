import 'package:flutter/material.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Match-specific selection; squad membership is never modified here.
class FutsalMatchSetup extends StatefulWidget {
  const FutsalMatchSetup({
    super.key,
    required this.onChanged,
    this.sport = Sport.futsal,
  });
  final Sport sport;
  final void Function(Map<String, dynamic> settings) onChanged;
  @override
  State<FutsalMatchSetup> createState() => _FutsalMatchSetupState();
}

class _FutsalMatchSetupState extends State<FutsalMatchSetup> {
  final List<Squad?> _teams = [null, null];
  final List<Set<String>> _starters = [{}, {}];

  void _emit() => widget.onChanged({
    'teamIds': [for (final t in _teams) t?.id],
    'teamNames': [for (final t in _teams) t?.name],
    'lineups': [for (final group in _starters) group.toList()],
    'rosters': [for (final t in _teams) t?.memberAccountIds ?? <String>[]],
  });

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TeamsController>();
    final squads = controller.squads
        .where((s) => s.sport == widget.sport)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          widget.sport == Sport.cricket
              ? 'Cricket teams & squad'
              : 'Teams & starting five',
          padding: EdgeInsets.zero,
        ),
        HelperText(
          widget.sport == Sport.cricket
              ? 'Choose registered cricket teams. Squad members receive invitations and must accept before scoring selection.'
              : 'Choose existing teams and up to five starters per side. Other squad members are substitutes. Players receive invitations and must accept before appearing in the official lineup.',
        ),
        for (var side = 0; side < 2; side++) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _teams[side]?.id,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: side == 0 ? 'Home team' : 'Away team',
            ),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('Use the team name entered below'),
              ),
              for (final squad in squads.where(
                (s) => s.id != _teams[1 - side]?.id,
              ))
                DropdownMenuItem(
                  value: squad.id,
                  child: Text(squad.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (id) => setState(() {
              _teams[side] = id == null || id.isEmpty
                  ? null
                  : controller.squadById(id);
              _starters[side].clear();
              _emit();
            }),
          ),
          if (_teams[side] != null && widget.sport == Sport.futsal)
            for (final id in _teams[side]!.memberAccountIds)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  controller.accounts
                          .where((a) => a.id == id)
                          .firstOrNull
                          ?.displayName ??
                      'Team member',
                  style: SportikaType.bodyStrong,
                ),
                subtitle: Text(
                  _starters[side].contains(id) ? 'Starting five' : 'Substitute',
                  style: SportikaType.caption,
                ),
                activeColor: SportikaColors.mint,
                value: _starters[side].contains(id),
                onChanged: (selected) => setState(() {
                  if (selected == true && _starters[side].length < 5) {
                    _starters[side].add(id);
                  } else {
                    _starters[side].remove(id);
                  }
                  _emit();
                }),
              ),
        ],
        if (squads.isEmpty)
          const HelperText(
            'No teams available. Enter team names and invite registered players from the Match Center.',
          ),
        const SizedBox(height: 20),
      ],
    );
  }
}
