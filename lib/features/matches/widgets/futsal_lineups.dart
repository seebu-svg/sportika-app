import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/matches/scoring/futsal_roster.dart';
import 'package:sportika/features/matches/scoring/match_scoring_validator.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Preserve roster order while excluding stale invitations and duplicate IDs.
List<MatchParticipant> _acceptedPlayers(Iterable<MatchParticipant> players) {
  final seen = <String>{};
  return players
      .where(
        (p) =>
            p.status == MatchParticipantStatus.accepted &&
            seen.add(p.profileId),
      )
      .toList();
}

class FutsalLineups extends StatefulWidget {
  const FutsalLineups({super.key, required this.match, this.onRecord});
  final SportMatch match;
  final RecordMatchEvent? onRecord;

  @override
  State<FutsalLineups> createState() => _FutsalLineupsState();
}

class _FutsalLineupsState extends State<FutsalLineups> {
  bool _editing = false;
  SportMatch get match => widget.match;

  Future<void> _edit(BuildContext context, int side) async {
    if (_editing || widget.onRecord == null) return;
    _editing = true;
    final matchId = match.id;
    final players = _acceptedPlayers(match.participantsOnSide(side));
    final original = FutsalRoster.starters(match, side);
    try {
      final session = context.read<SessionController>();
      final result = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: SportikaColors.lightSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SportikaRadius.xl),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        builder: (_) => FutsalLineupSelectionSheet(
          teamName: match.sideNames[side],
          players: players,
          initialSelection: original,
          session: session,
          currentPlayers: () =>
              match.id == matchId ? match.participantsOnSide(side) : [],
        ),
      );
      if (result == null ||
          !mounted ||
          !context.mounted ||
          widget.onRecord == null) {
        return;
      }
      final accepted = _acceptedPlayers(match.participantsOnSide(side));
      final ids = result.toSet();
      final latest = FutsalRoster.starters(match, side);
      if (match.id != matchId ||
          ids.length != 5 ||
          !accepted.map((p) => p.profileId).toSet().containsAll(ids) ||
          !setEquals(original, latest)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The roster changed. Review the lineup and try again.',
            ),
          ),
        );
        return;
      }
      if (setEquals(ids, latest)) return;
      widget.onRecord?.call('lineup', side, {
        'players': accepted
            .where((p) => ids.contains(p.profileId))
            .map((p) => p.profileId)
            .toList(),
      });
    } finally {
      _editing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var side = 0; side < 2; side++) ...[
          Builder(
            builder: (context) {
              final players = _acceptedPlayers(match.participantsOnSide(side));
              final ids = FutsalRoster.starters(match, side);
              return FutsalLineupSection(
                teamName: match.sideNames[side],
                session: session,
                starters: players
                    .where((p) => ids.contains(p.profileId))
                    .toList(),
                substitutes: players
                    .where((p) => !ids.contains(p.profileId))
                    .toList(),
                onEdit: widget.onRecord == null
                    ? null
                    : () => _edit(context, side),
              );
            },
          ),
          if (side == 0) const SizedBox(height: SportikaSpacing.lg),
        ],
      ],
    );
  }
}

/// A team lineup, shared by editable and read-only match views.
class FutsalLineupSection extends StatelessWidget {
  const FutsalLineupSection({
    super.key,
    required this.teamName,
    required this.session,
    required this.starters,
    required this.substitutes,
    this.onEdit,
  });
  final String teamName;
  final SessionController session;
  final List<MatchParticipant> starters;
  final List<MatchParticipant> substitutes;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final confirmed = starters.length == 5;
    return Container(
      decoration: BoxDecoration(
        color: SportikaColors.lightSurface,
        borderRadius: BorderRadius.circular(SportikaRadius.xl),
        border: Border.all(color: SportikaColors.lightBorder),
      ),
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TeamHeader(
            teamName: teamName,
            confirmed: confirmed,
            selected: starters.length,
          ),
          const SizedBox(height: SportikaSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(
                child: Text(
                  'STARTING FIVE',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.label,
                ),
              ),
              if (onEdit != null)
                _EditLineup(teamName: teamName, onPressed: onEdit!),
            ],
          ),
          const SizedBox(height: SportikaSpacing.sm),
          _StartingFive(
            starters: starters,
            substitutes: substitutes,
            session: session,
          ),
          const SizedBox(height: SportikaSpacing.md),
          const Divider(
            color: SportikaColors.lightBorder,
            height: 1,
            thickness: 1,
          ),
          _Substitutes(substitutes: substitutes, session: session),
        ],
      ),
    );
  }
}

/// Compact team header: eyebrow, team name and the lineup status at a glance.
class _TeamHeader extends StatelessWidget {
  const _TeamHeader({
    required this.teamName,
    required this.confirmed,
    required this.selected,
  });

  final String teamName;
  final bool confirmed;
  final int selected;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Semantics(
          header: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'TEAM LINEUP',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SportikaType.micro.copyWith(
                  color: SportikaColors.lightTextMuted,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                teamName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SportikaType.headline.copyWith(
                  color: SportikaColors.lightText,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(width: SportikaSpacing.sm),
      Flexible(
        child: _StatusChip(confirmed: confirmed, selected: selected),
      ),
    ],
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.confirmed, required this.selected});

  final bool confirmed;
  final int selected;

  @override
  Widget build(BuildContext context) {
    final tone = confirmed
        ? SportikaColors.lightMintText
        : SportikaColors.lightTextMuted;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SportikaSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: confirmed ? SportikaColors.lightMint : SportikaColors.lightBlue,
        borderRadius: BorderRadius.circular(SportikaRadius.sm),
      ),
      child: Semantics(
        liveRegion: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              confirmed ? Icons.check_circle_outline : Icons.schedule_outlined,
              size: 14,
              color: tone,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                confirmed
                    ? 'Starting five confirmed'
                    : '$selected/5 · Awaiting confirmation',
                style: SportikaType.action.copyWith(
                  fontSize: 11.5,
                  height: 1.25,
                  color: tone,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one action on the card. Kept overflow-safe at large text scales.
class _EditLineup extends StatelessWidget {
  const _EditLineup({required this.teamName, required this.onPressed});

  final String teamName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Edit starting five for $teamName',
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: SportikaColors.blue,
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: SportikaSpacing.sm),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SportikaRadius.sm),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_outlined, size: 15),
          SizedBox(width: 6),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Edit Lineup',
                maxLines: 1,
                style: SportikaType.action,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A starter slot is a face plus a two-line name, so it needs a fixed footprint
/// for the layout to decide how many of them fit across.
const double _slotSize = 66;
const double _slotGap = 10;

/// The starting five on a soft court panel: one row of five where the width
/// allows, a two or three column grid on narrow screens, and a single list
/// when the text scale pushes everything down.
class _StartingFive extends StatelessWidget {
  const _StartingFive({
    required this.starters,
    required this.substitutes,
    required this.session,
  });

  final List<MatchParticipant> starters;
  final List<MatchParticipant> substitutes;
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    if (starters.isEmpty && substitutes.isEmpty) {
      return const _EmptyLineup(
        message:
            'No accepted players yet. Players will appear here once they '
            'accept their invitations.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (starters.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: SportikaSpacing.sm),
            child: Text(
              'Starting five not confirmed. Choose five accepted players for '
              'this team.',
              style: SportikaType.caption,
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final columns = math.max(
              1,
              math.min(
                5,
                ((constraints.maxWidth + _slotGap) /
                        (_slotSize * scale + _slotGap))
                    .floor(),
              ),
            );
            return _Court(
              starters: starters,
              substitutes: substitutes,
              session: session,
              columns: columns,
              slotWidth:
                  (constraints.maxWidth - (columns - 1) * _slotGap) / columns,
              singleColumn: columns == 1,
            );
          },
        ),
      ],
    );
  }
}

class _Court extends StatelessWidget {
  const _Court({
    required this.starters,
    required this.substitutes,
    required this.session,
    required this.columns,
    required this.slotWidth,
    required this.singleColumn,
  });

  final List<MatchParticipant> starters;
  final List<MatchParticipant> substitutes;
  final SessionController session;
  final int columns;
  final double slotWidth;
  final bool singleColumn;

  /// Open slots are only drawn when the team can actually be completed.
  List<MatchParticipant?> get _slots {
    final open = 5 - starters.length;
    return [
      ...starters.map((p) => p as MatchParticipant?),
      if (substitutes.isNotEmpty && open > 0)
        for (var index = 0; index < open; index++) null,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final slots = _slots;
    if (singleColumn) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < slots.length; index++) ...[
              if (index > 0) const SizedBox(height: SportikaSpacing.sm),
              _LineupSlot(
                player: slots[index],
                session: session,
                layout: _SlotLayout.row,
                width: slotWidth,
              ),
            ],
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SportikaSpacing.md,
        vertical: SportikaSpacing.md + 2,
      ),
      decoration: BoxDecoration(
        color: SportikaColors.lightBlue,
        borderRadius: BorderRadius.circular(SportikaRadius.lg),
        border: Border.all(color: SportikaColors.lightBorder),
      ),
      child: Stack(
        children: [
          if (columns == 5)
            Positioned(
              top: 0,
              bottom: 0,
              left:
                  (slotWidth * 5 + 4 * _slotGap) / 2 + SportikaSpacing.md - 0.5,
              child: const SizedBox(
                width: 1,
                child: ColoredBox(color: SportikaColors.lightBorder),
              ),
            ),
          Wrap(
            spacing: _slotGap,
            runSpacing: SportikaSpacing.md,
            children: [
              for (final player in slots)
                SizedBox(
                  width: slotWidth,
                  child: _LineupSlot(
                    player: player,
                    session: session,
                    layout: _SlotLayout.column,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _SlotLayout { column, row }

/// One starting slot: a face on a light disc with the name under it, or beside
/// it when the slot is full width. Empty slots stay visibly open.
class _LineupSlot extends StatelessWidget {
  const _LineupSlot({
    required this.player,
    required this.session,
    required this.layout,
    this.width,
  });

  final MatchParticipant? player;
  final SessionController session;
  final _SlotLayout layout;
  final double? width;

  @override
  Widget build(BuildContext context) {
    if (player == null) return const _OpenSlot();
    final name = Text(
      player!.displayName,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      semanticsLabel: player!.displayName,
      textAlign: layout == _SlotLayout.column
          ? TextAlign.center
          : TextAlign.start,
      style: SportikaType.bodyStrong.copyWith(
        fontSize: 12.5,
        color: SportikaColors.lightText,
      ),
    );
    final face = _PlayerFace(
      player: player!,
      session: session,
      size: 46,
      lifted: true,
    );
    if (layout == _SlotLayout.row) {
      return Row(
        children: [
          face,
          const SizedBox(width: SportikaSpacing.sm),
          Expanded(
            child: Tooltip(message: player!.displayName, child: name),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        face,
        const SizedBox(height: SportikaSpacing.xs),
        Tooltip(message: player!.displayName, child: name),
      ],
    );
  }
}

class _OpenSlot extends StatelessWidget {
  const _OpenSlot();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: SportikaColors.lightBorder, width: 1.5),
        ),
        child: const Icon(
          Icons.person_outline_rounded,
          size: 20,
          color: SportikaColors.lightTextMuted,
        ),
      ),
      const SizedBox(height: SportikaSpacing.xs),
      Text(
        'Open slot',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: SportikaType.caption.copyWith(
          color: SportikaColors.lightTextMuted,
        ),
      ),
    ],
  );
}

class _Substitutes extends StatelessWidget {
  const _Substitutes({required this.substitutes, required this.session});

  final List<MatchParticipant> substitutes;
  final SessionController session;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: Material(
      color: SportikaColors.lightSurface,
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 2),
        iconColor: SportikaColors.lightTextMuted,
        collapsedIconColor: SportikaColors.lightTextMuted,
        title: Text(
          'Substitutes (${substitutes.length})',
          style: SportikaType.bodyStrong.copyWith(
            color: SportikaColors.lightText,
          ),
        ),
        children: [
          if (substitutes.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: SportikaSpacing.sm),
              child: Text(
                'No accepted substitutes',
                style: SportikaType.caption,
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < substitutes.length; index++) ...[
                  if (index > 0)
                    const Divider(
                      color: SportikaColors.lightBorder,
                      height: 1,
                      thickness: 1,
                    ),
                  _PlayerRow(player: substitutes[index], session: session),
                ],
              ],
            ),
        ],
      ),
    ),
  );
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.player,
    required this.session,
    this.trailing,
  });
  final MatchParticipant player;
  final SessionController session;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        _PlayerFace(player: player, session: session),
        const SizedBox(width: SportikaSpacing.sm),
        Expanded(
          child: Tooltip(
            message: player.displayName,
            child: Text(
              player.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              semanticsLabel: player.displayName,
              style: SportikaType.bodyStrong.copyWith(
                fontSize: 13,
                color: SportikaColors.lightText,
              ),
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: SportikaSpacing.sm),
          trailing!,
        ],
      ],
    ),
  );
}

class _EmptyLineup extends StatelessWidget {
  const _EmptyLineup({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: SportikaSpacing.sm),
    child: Text(
      message,
      style: SportikaType.caption.copyWith(
        color: SportikaColors.lightTextMuted,
      ),
    ),
  );
}

/// Every face in the lineup, so starters and substitutes stay visibly alike.
/// [lifted] puts the starter on a light disc, which keeps the five readable on
/// the court panel; rows keep the flat form with a ring.
class _PlayerFace extends StatelessWidget {
  const _PlayerFace({
    required this.player,
    required this.session,
    this.size = 36,
    this.lifted = false,
  });

  final MatchParticipant player;
  final SessionController session;
  final double size;
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final account = session.accountById(player.profileId);
    final face = ExcludeSemantics(
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.2,
        child: PlayerAvatar(
          initials: initialsOf(player.displayName),
          size: size,
          color: SportikaColors.blue,
          ring: lifted ? null : SportikaColors.blue,
          photoUrl: account?.photoUrl,
          photoPath: account?.photoPath,
        ),
      ),
    );
    if (!lifted) return face;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        color: SportikaColors.lightSurface,
        shape: BoxShape.circle,
      ),
      child: face,
    );
  }
}

/// Owns a defensive draft: dismissing the sheet never changes the roster.
class FutsalLineupSelectionSheet extends StatefulWidget {
  const FutsalLineupSelectionSheet({
    super.key,
    required this.teamName,
    required this.players,
    required this.initialSelection,
    required this.session,
    this.currentPlayers,
  });
  final List<MatchParticipant> Function()? currentPlayers;
  final String teamName;
  final List<MatchParticipant> players;
  final Set<String> initialSelection;
  final SessionController session;
  @override
  State<FutsalLineupSelectionSheet> createState() =>
      _FutsalLineupSelectionSheetState();
}

class _FutsalLineupSelectionSheetState
    extends State<FutsalLineupSelectionSheet> {
  late final Set<String> _selected;
  late List<MatchParticipant> _players;
  bool _submitted = false;
  @override
  void initState() {
    super.initState();
    _players = _acceptedPlayers(
      widget.currentPlayers?.call() ?? widget.players,
    );
    _selected = widget.initialSelection.intersection(
      _players.map((p) => p.profileId).toSet(),
    );
  }

  void _refreshRoster() {
    _players = _acceptedPlayers(
      widget.currentPlayers?.call() ?? widget.players,
    );
    _selected.retainAll(_players.map((p) => p.profileId));
  }

  void _confirm() {
    if (_submitted) return;
    setState(_refreshRoster);
    if (_selected.length != 5) return;
    _submitted = true;
    Navigator.pop(
      context,
      _players
          .where((p) => _selected.contains(p.profileId))
          .map((p) => p.profileId)
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    _refreshRoster();
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        // Keep space for the fixed controls when the sheet is dragged down.
        final controlsHeight =
            scaler.scale(13) * 1.4 +
            scaler.scale(46) +
            MediaQuery.paddingOf(context).bottom +
            118;
        final minimum = (controlsHeight / constraints.maxHeight).clamp(
          .45,
          .96,
        );
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: math.max(.86, minimum),
          minChildSize: minimum,
          maxChildSize: .96,
          builder: (context, controller) => Column(
            children: [
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: SportikaColors.lightBorder,
                          borderRadius: BorderRadius.circular(
                            SportikaRadius.pill,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: SportikaSpacing.sm),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'STARTING LINEUP',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SportikaType.micro,
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: SportikaColors.lightTextMuted,
                            minimumSize: const Size(48, 44),
                            padding: const EdgeInsets.symmetric(
                              horizontal: SportikaSpacing.sm,
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            maxLines: 1,
                            style: SportikaType.action,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: SportikaSpacing.xs),
                    Semantics(
                      header: true,
                      child: Text(
                        'Choose your starting five',
                        style: SportikaType.title.copyWith(
                          color: SportikaColors.lightText,
                          height: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.teamName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SportikaType.bodyStrong.copyWith(
                        color: SportikaColors.lightTextMuted,
                      ),
                    ),
                    const SizedBox(height: SportikaSpacing.md),
                    Text(
                      _players.length < 5
                          ? 'At least five players must accept their invitations before the lineup can be confirmed.'
                          : _selected.length >= 5
                          ? 'Five selected. Deselect a player to make a change.'
                          : 'Select five accepted players to start the match.',
                      style: SportikaType.caption.copyWith(
                        color: SportikaColors.lightTextMuted,
                      ),
                    ),
                    const SizedBox(height: SportikaSpacing.md),
                    if (_players.isEmpty)
                      const _EmptyLineup(message: 'No accepted players yet.'),
                    for (final player in _players) _selectionRow(player),
                  ],
                ),
              ),
              _ConfirmationBar(
                selected: _selected.length,
                canConfirm: !_submitted && _selected.length == 5,
                onConfirm: _confirm,
              ),
            ],
          ),
        );
      },
    );
  }

  void _toggle(String id) {
    if (_submitted) return;
    setState(() {
      _refreshRoster();
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else if (_selected.length < 5 &&
          _players.any((p) => p.profileId == id)) {
        _selected.add(id);
      }
    });
  }

  Widget _selectionRow(MatchParticipant player) {
    final selected = _selected.contains(player.profileId);
    final enabled = !_submitted && (selected || _selected.length < 5);
    return Padding(
      padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
      child: Semantics(
        label: player.displayName,
        checked: selected,
        enabled: enabled,
        button: true,
        excludeSemantics: true,
        onTap: enabled ? () => _toggle(player.profileId) : null,
        child: Material(
          color: selected
              ? SportikaColors.lightBlue
              : SportikaColors.lightSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SportikaRadius.md),
            side: BorderSide(
              color: selected
                  ? SportikaColors.blue
                  : SportikaColors.lightBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: AnimatedContainer(
            duration: SportikaMotion.fast,
            curve: SportikaMotion.standard,
            color: Colors.transparent,
            child: InkWell(
              onTap: !enabled ? null : () => _toggle(player.profileId),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SportikaSpacing.md,
                  vertical: 2,
                ),
                child: _PlayerRow(
                  player: player,
                  session: widget.session,
                  trailing: _SelectTick(selected: selected, enabled: enabled),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectTick extends StatelessWidget {
  const _SelectTick({required this.selected, required this.enabled});

  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: SportikaMotion.fast,
    curve: SportikaMotion.standard,
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: selected ? SportikaColors.blue : Colors.transparent,
      border: Border.all(
        color: selected ? SportikaColors.blue : SportikaColors.lightBorder,
        width: 1.5,
      ),
    ),
    child: selected
        ? const Icon(
            Icons.check_rounded,
            size: 15,
            color: SportikaColors.lightSurface,
          )
        : Icon(
            Icons.add_rounded,
            size: 15,
            color: enabled
                ? SportikaColors.lightTextMuted
                : SportikaColors.lightBorder,
          ),
  );
}

/// Fixed footer: five-slot progress plus the only commit action on the sheet.
class _ConfirmationBar extends StatelessWidget {
  const _ConfirmationBar({
    required this.selected,
    required this.canConfirm,
    required this.onConfirm,
  });

  final int selected;
  final bool canConfirm;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: SportikaColors.lightSurface,
      border: Border(top: BorderSide(color: SportikaColors.lightBorder)),
    ),
    padding: const EdgeInsets.fromLTRB(
      24,
      SportikaSpacing.md,
      24,
      SportikaSpacing.md,
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label: '$selected of 5 players selected',
                  excludeSemantics: true,
                  child: Text(
                    '$selected/5 selected',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SportikaType.bodyStrong.copyWith(
                      fontSize: 13,
                      color: SportikaColors.blue,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              ExcludeSemantics(
                child: Text(
                  selected == 5 ? 'Ready' : 'Pick ${5 - selected} more',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.caption.copyWith(
                    color: SportikaColors.lightTextMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.sm),
          _SlotProgress(filled: selected),
          const SizedBox(height: SportikaSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: SportikaColors.blue,
                foregroundColor: SportikaColors.lightSurface,
                disabledBackgroundColor: SportikaColors.lightBorder,
                disabledForegroundColor: SportikaColors.lightTextMuted,
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(
                  horizontal: SportikaSpacing.md,
                ),
                textStyle: SportikaType.action,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(SportikaRadius.md),
                ),
              ),
              onPressed: canConfirm ? onConfirm : null,
              child: const Text(
                'Confirm starting five',
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: SportikaType.bodyFamily),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Five segments, one per starter slot — the progress a lineup is measured in.
class _SlotProgress extends StatelessWidget {
  const _SlotProgress({required this.filled});

  final int filled;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Starting five selection progress',
    child: ExcludeSemantics(
      child: Row(
        children: [
          for (var slot = 0; slot < 5; slot++) ...[
            if (slot > 0) const SizedBox(width: 6),
            Expanded(
              child: AnimatedContainer(
                duration: SportikaMotion.base,
                curve: SportikaMotion.standard,
                height: 5,
                decoration: BoxDecoration(
                  color: slot < filled
                      ? SportikaColors.blue
                      : SportikaColors.lightBorder,
                  borderRadius: BorderRadius.circular(SportikaRadius.pill),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
