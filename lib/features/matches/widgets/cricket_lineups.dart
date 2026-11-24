import 'package:flutter/material.dart';

import 'package:sportika/features/matches/scoring/cricket_roster.dart';
import 'package:sportika/features/matches/scoring/match_scoring_validator.dart';
import 'package:sportika/features/personal_games/scoring/cricket/cricket.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// The two XIs, in batting order, editable only before the first ball.
///
/// A cricket XI is an order, not a squad: the scorer picks who opens and who
/// comes in at seven, and the workspace installs the next name after a wicket.
/// The order therefore lives in a `lineup` event and this widget only writes
/// and paints it.
class CricketLineups extends StatefulWidget {
  const CricketLineups({super.key, required this.match, this.onRecord});

  final SportMatch match;

  /// Null makes both cards read-only, which is what a spectator, a review stage
  /// and a started match all need.
  final RecordMatchEvent? onRecord;

  @override
  State<CricketLineups> createState() => _CricketLineupsState();
}

class _CricketLineupsState extends State<CricketLineups> {
  static const int _minXi = 2;
  static const int _maxXi = 11;

  bool _editing = false;

  Future<void> _edit(int side) async {
    if (_editing || widget.onRecord == null) return;
    _editing = true;
    final matchId = widget.match.id;
    final players = CricketRoster.playersOn(widget.match, side);
    final initial = CricketRoster.lineupIds(widget.match, side);
    try {
      final result = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: SportikaColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SportikaRadius.xl),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        builder: (_) => CricketLineupSheet(
          teamName: widget.match.sideNames[side],
          players: players,
          initialSelection: initial,
        ),
      );
      if (result == null ||
          !mounted ||
          widget.onRecord == null ||
          widget.match.id != matchId) {
        return;
      }
      if (result.length < _minXi || result.length > _maxXi) return;
      widget.onRecord!(CricketEngine.kLineup, side, {'players': result});
    } finally {
      _editing = false;
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var side = 0; side < 2; side++) ...[
        CricketLineupCard(
          teamName: widget.match.sideNames[side],
          order: CricketRoster.namesOn(widget.match, side),
          named: CricketRoster.hasLineup(widget.match, side),
          onEdit: widget.onRecord == null ? null : () => _edit(side),
        ),
        if (side == 0) const SizedBox(height: SportikaSpacing.lg),
      ],
    ],
  );
}

/// One side's batting order: 1..n with names, or the empty state.
class CricketLineupCard extends StatelessWidget {
  const CricketLineupCard({
    super.key,
    required this.teamName,
    required this.order,
    required this.named,
    this.onEdit,
  });

  final String teamName;
  final List<String> order;
  final bool named;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: SportikaColors.surface,
      borderRadius: BorderRadius.circular(SportikaRadius.xl),
      border: Border.all(color: SportikaColors.borderSubtle),
    ),
    padding: const EdgeInsets.all(SportikaSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'PLAYING XI',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SportikaType.micro.copyWith(
                      color: SportikaColors.textDim,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    teamName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SportikaType.headline.copyWith(height: 1.15),
                  ),
                ],
              ),
            ),
            const SizedBox(width: SportikaSpacing.sm),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: SportikaSpacing.sm,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: named
                      ? SportikaColors.mintSubtle
                      : SportikaColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(SportikaRadius.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      named
                          ? Icons.check_circle_outline
                          : Icons.schedule_outlined,
                      size: 14,
                      color: named
                          ? SportikaColors.mint
                          : SportikaColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        named
                            ? 'XI named · ${order.length}'
                            : 'XI not recorded',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SportikaType.action.copyWith(
                          fontSize: 11.5,
                          height: 1.25,
                          color: named
                              ? SportikaColors.mint
                              : SportikaColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: SportikaSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Expanded(
              child: Text(
                'BATTING ORDER',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SportikaType.label,
              ),
            ),
            if (onEdit != null) ...[
              const SizedBox(width: SportikaSpacing.xs),
              Flexible(
                child: _EditXi(teamName: teamName, onPressed: onEdit!),
              ),
            ],
          ],
        ),
        const SizedBox(height: SportikaSpacing.sm),
        // A projected roster is not an XI: until the scorer names one, the card
        // says so rather than showing an order nobody recorded.
        if (!named || order.isEmpty)
          Text(
            'No XI yet. Name between two and eleven accepted players in '
            'batting order before the first ball.',
            style: SportikaType.caption.copyWith(
              color: SportikaColors.textMuted,
            ),
          )
        else
          for (var index = 0; index < order.length; index++)
            _XiRow(position: index + 1, name: order[index]),
      ],
    ),
  );
}

class _XiRow extends StatelessWidget {
  const _XiRow({required this.position, required this.name});

  final int position;
  final String name;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(
          width: 22,
          child: Text(
            '$position',
            style: SportikaType.micro.copyWith(color: SportikaColors.textDim),
          ),
        ),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SportikaType.bodyStrong.copyWith(fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

/// The one action on the card. The label lives inside a FittedBox so the
/// tightest layout the roster allows scales it down instead of overflowing.
class _EditXi extends StatelessWidget {
  const _EditXi({required this.teamName, required this.onPressed});

  final String teamName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Edit the XI for $teamName',
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: SportikaColors.blueBright,
        minimumSize: const Size(0, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: SportikaSpacing.xs),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SportikaRadius.sm),
        ),
      ),
      child: const FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_outlined, size: 15),
            SizedBox(width: 6),
            Text(
              'Edit XI',
              maxLines: 1,
              softWrap: false,
              style: SportikaType.action,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Owns a defensive draft: dismissing the sheet never changes the XI.
///
/// Taps append to an ordered list, so the batting order is the order the scorer
/// tapped. Tapping a picked player again removes them.
class CricketLineupSheet extends StatefulWidget {
  const CricketLineupSheet({
    super.key,
    required this.teamName,
    required this.players,
    this.initialSelection = const [],
  });

  final String teamName;
  final List<CricketPlayer> players;

  /// The recorded XI, in batting order.
  final List<String> initialSelection;

  @override
  State<CricketLineupSheet> createState() => _CricketLineupSheetState();
}

class _CricketLineupSheetState extends State<CricketLineupSheet> {
  static const int _minXi = 2;
  static const int _maxXi = 11;

  late final List<String> _selected = [
    for (final id in widget.initialSelection)
      if (widget.players.any((p) => p.id == id)) id,
  ];
  bool _submitted = false;

  void _toggle(String id) {
    if (_submitted) return;
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else if (_selected.length < _maxXi) {
        _selected.add(id);
      }
    });
  }

  void _confirm() {
    if (_submitted || _selected.length < _minXi) return;
    _submitted = true;
    Navigator.pop(context, List<String>.of(_selected));
  }

  @override
  Widget build(BuildContext context) {
    final canSave = !_submitted && _selected.length >= _minXi;
    return AppSheet(
      title: 'Name the XI',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.teamName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SportikaType.bodyStrong,
            ),
            const SizedBox(height: 4),
            Text(
              'Tap in batting order. Tap again to remove.',
              style: SportikaType.caption.copyWith(
                color: SportikaColors.textMuted,
              ),
            ),
            const SizedBox(height: SportikaSpacing.md),
            if (widget.players.isEmpty)
              Text(
                'No accepted players yet. Players appear here once they accept '
                'their invitations.',
                style: SportikaType.caption.copyWith(
                  color: SportikaColors.textMuted,
                ),
              ),
            for (final player in widget.players) _row(player),
            const SizedBox(height: SportikaSpacing.sm),
            Text(
              '${_selected.length} of $_maxXi picked'
              '${_selected.length < _minXi ? ' · pick at least $_minXi' : ''}',
              style: SportikaType.caption,
            ),
            const SizedBox(height: SportikaSpacing.sm),
            PrimaryButton(
              label: 'Save XI',
              icon: Icons.check,
              onPressed: canSave ? _confirm : null,
            ),
            const SizedBox(height: SportikaSpacing.sm),
          ],
        ),
      ),
    );
  }

  Widget _row(CricketPlayer player) {
    final position = _selected.indexOf(player.id);
    final selected = position >= 0;
    final enabled = !_submitted && (selected || _selected.length < _maxXi);
    return Padding(
      padding: const EdgeInsets.only(bottom: SportikaSpacing.xs),
      child: Semantics(
        label: player.name,
        checked: selected,
        enabled: enabled,
        button: true,
        excludeSemantics: true,
        onTap: enabled ? () => _toggle(player.id) : null,
        child: Material(
          color: selected ? SportikaColors.surfaceAlt : SportikaColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SportikaRadius.md),
            side: BorderSide(
              color: selected
                  ? SportikaColors.blueBright
                  : SportikaColors.borderSubtle,
              width: selected ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: !enabled ? null : () => _toggle(player.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SportikaSpacing.md,
                vertical: 12,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      selected ? '${position + 1}' : '·',
                      style: SportikaType.bodyStrong.copyWith(
                        color: selected
                            ? SportikaColors.blueBright
                            : SportikaColors.textDim,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      player.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SportikaType.bodyStrong.copyWith(fontSize: 13),
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.check_circle_outline
                        : Icons.add_circle_outline,
                    size: 18,
                    color: enabled
                        ? (selected
                              ? SportikaColors.blueBright
                              : SportikaColors.textMuted)
                        : SportikaColors.textDim,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
