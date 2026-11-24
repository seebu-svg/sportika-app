import 'package:flutter/material.dart';
import 'package:sportika/features/matches/widgets/match_management_widgets.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/core/state/profile_module_controller.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/profile_module.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Roster and invitations for one match.
///
/// The organizer picks a side, searches registered members and invites them.
/// The database decides whether the invitation is allowed (capacity, an
/// existing member, the organizer themselves), so this sheet only mirrors the
/// obvious cases and reports the refusal it gets back.
Future<void> showMatchParticipantsSheet(
  BuildContext context, {
  required SportMatch match,
  int initialSide = 1,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: SportikaColors.surfaceElevated,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(SportikaRadius.xl),
      ),
    ),
    builder: (_) => SingleChildScrollView(
      child: _MatchParticipantsSheet(
        matchId: match.id,
        initialSide: initialSide,
      ),
    ),
  );
}

class _MatchParticipantsSheet extends StatefulWidget {
  const _MatchParticipantsSheet({
    required this.matchId,
    required this.initialSide,
  });

  final String matchId;
  final int initialSide;

  @override
  State<_MatchParticipantsSheet> createState() =>
      _MatchParticipantsSheetState();
}

class _MatchParticipantsSheetState extends State<_MatchParticipantsSheet> {
  final TextEditingController _search = TextEditingController();
  late int _side = widget.initialSide;
  List<ProfileSummary>? _results;
  bool _searching = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    if (_busy || _searching) return;
    final profiles = context.read<ProfileModuleController>();
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final found = await profiles.searchPlayers(_search.text);
      if (!mounted) return;
      setState(() => _results = found);
    } on ProfileModuleException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _invite(ProfileSummary player) async {
    final matches = context.read<MatchController>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final sent = await matches.inviteParticipant(
      widget.matchId,
      player.id,
      side: _side,
      displayName: player.label,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (sent) {
        _results = null;
        _search.clear();
      } else {
        _error = matches.lastError;
      }
    });
    if (sent && mounted) {
      showSnack(context, '${player.label} was invited');
    }
  }

  /// Invites a whole squad in one call: the server writes one invitation per
  /// accepted member, so a four- or five-a-side roster does not have to be
  /// rebuilt player by player.
  Future<void> _addSquad(Squad squad) async {
    final matches = context.read<MatchController>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final added = await matches.addSquadToMatch(
      widget.matchId,
      squad.id,
      side: _side,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (added == null) _error = matches.lastError;
    });
    if (added != null && mounted) {
      showSnack(
        context,
        added == 1
            ? '1 player from ${squad.name} was invited'
            : '$added players from ${squad.name} were invited',
      );
    }
  }

  /// A squad can only be added to the side that still has room, and only by the
  /// organizer or the official scorer, which is what `add_match_squad` checks.
  bool _canAddSquad(SportMatch match, String? me) =>
      match.canScore(me) &&
      match.status == FixtureStatus.upcoming &&
      match.startedAt == null &&
      match.acceptedCount < match.capacity;

  /// The squad type that matches the match's discipline: a team squad for a
  /// team match, a pair for doubles, a single-player entry for singles.
  EntryType _entryTypeFor(MatchDiscipline discipline) => switch (discipline) {
    MatchDiscipline.team => EntryType.team,
    MatchDiscipline.doubles => EntryType.pair,
    MatchDiscipline.singles => EntryType.individual,
  };

  Future<void> _remove(MatchParticipant participant) async {
    final matches = context.read<MatchController>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final removed = await matches.removeParticipant(
      widget.matchId,
      participant.profileId,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!removed) _error = matches.lastError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final match = context.watch<MatchController>().matchById(widget.matchId);
    if (match == null) {
      return const AppSheet(
        title: 'Players',
        child: Text('This match is no longer available.'),
      );
    }
    final sides = match.sideNames;
    final organizerId = match.organizerId;
    final me = context.watch<SessionController>().currentAccount;
    final canManage =
        match.isOrganizer(me?.id) &&
        (match.status == FixtureStatus.upcoming ||
            match.status == FixtureStatus.live);
    final full = match.acceptedCount >= match.capacity;
    final canAddSquad = _canAddSquad(match, me?.id);
    final squads = canAddSquad
        ? context
              .watch<TeamsController>()
              .mySquads
              .where(
                (s) =>
                    s.sport == match.sport &&
                    s.type == _entryTypeFor(match.discipline),
              )
              .toList()
        : const <Squad>[];
    final sideName = _side < sides.length ? sides[_side] : 'side ${_side + 1}';

    return AppSheet(
      title: 'Players',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MatchSheetIntro(
            icon: Icons.groups_outlined,
            title: '${match.acceptedCount} of ${match.capacity} places filled',
            body: !canManage
                ? 'The roster is read-only. Changes require an organizer and an open match.'
                : full
                ? 'All places are filled. Manage existing players below.'
                : 'Choose a side, find a member, and send an invitation. They join after accepting.',
          ),
          const SizedBox(height: SportikaSpacing.md),
          for (var side = 0; side < 2; side++) ...[
            Text(
              (side < sides.length ? sides[side] : 'Side ${side + 1}')
                  .toUpperCase(),
              style: SportikaType.label,
            ),
            const SizedBox(height: 6),
            if (match.participants.where((p) => p.side == side).isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text('No players yet.', style: SportikaType.caption),
              )
            else
              for (final participant in match.participants.where(
                (p) => p.side == side,
              ))
                _ParticipantRow(
                  participant: participant,
                  isOrganizer: participant.profileId == organizerId,
                  canRemove:
                      canManage &&
                      !_busy &&
                      participant.profileId != organizerId &&
                      (participant.status == MatchParticipantStatus.accepted ||
                          participant.status == MatchParticipantStatus.invited),
                  onRemove: () => _remove(participant),
                ),
            const SizedBox(height: SportikaSpacing.sm),
          ],
          const SizedBox(height: SportikaSpacing.md),
          if ((canManage && !full) || canAddSquad) ...[
            const Text('INVITE TO', style: SportikaType.label),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var side = 0; side < 2; side++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _SideChoice(
                        label: side < sides.length
                            ? sides[side]
                            : 'Side ${side + 1}',
                        selected: _side == side,
                        onTap: _busy
                            ? null
                            : () => setState(() => _side = side),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: SportikaSpacing.md),
            if (canAddSquad) ...[
              const Text('ADD A SQUAD', style: SportikaType.label),
              const SizedBox(height: 6),
              HelperText(
                squads.isEmpty
                    ? 'You have no ${match.sport.label} squad of the right '
                          'size for this match. Create one on the Teams tab.'
                    : 'Invites every accepted member of a squad to $sideName. '
                          'They join once they accept.',
              ),
              const SizedBox(height: SportikaSpacing.sm),
              for (final squad in squads)
                Padding(
                  padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
                  child: SurfaceCard(
                    padding: const EdgeInsets.all(SportikaSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(squad.name, style: SportikaType.bodyStrong),
                              Text(
                                '${squad.size} '
                                '${squad.size == 1 ? 'member' : 'members'}',
                                style: SportikaType.caption,
                              ),
                            ],
                          ),
                        ),
                        GhostButton(
                          label: 'Add to $sideName',
                          onPressed: _busy ? null : () => _addSquad(squad),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            if (canManage && !full) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      enabled: !_busy,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _runSearch(),
                      decoration: const InputDecoration(
                        labelText: 'Find a registered player',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: SportikaSpacing.sm),
                  GhostButton(
                    label: 'Search',
                    onPressed: _searching || _busy ? null : _runSearch,
                  ),
                ],
              ),
              if (_searching) const LinearProgressIndicator(),
              if (_results != null) ...[
                const SizedBox(height: SportikaSpacing.sm),
                if (_results!.isEmpty)
                  const HelperText('No member matched that search.')
                else
                  SurfaceCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        for (final player in _results!)
                          MatchMemberSearchTile(
                            player: player,
                            inviting: true,
                            note:
                                match.participantOf(player.id)?.status ==
                                    MatchParticipantStatus.accepted
                                ? 'Already joined'
                                : match.participantOf(player.id)?.status ==
                                      MatchParticipantStatus.invited
                                ? 'Invitation pending'
                                : null,
                            onTap:
                                _busy ||
                                    const {
                                      MatchParticipantStatus.accepted,
                                      MatchParticipantStatus.invited,
                                    }.contains(
                                      match.participantOf(player.id)?.status,
                                    )
                                ? null
                                : () => _invite(player),
                          ),
                      ],
                    ),
                  ),
              ],
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: SportikaSpacing.md),
            InlineBanner(text: _error!, tone: SportikaColors.danger),
          ],
        ],
      ),
    );
  }
}

class _SideChoice extends StatelessWidget {
  const _SideChoice({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = selected
        ? SportikaColors.blueBright
        : SportikaColors.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SportikaRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        constraints: const BoxConstraints(maxWidth: 140),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: selected ? 0.16 : 0.06),
          borderRadius: BorderRadius.circular(SportikaRadius.sm),
          border: Border.all(color: tone.withValues(alpha: 0.45)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SportikaType.action.copyWith(color: tone),
        ),
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.participant,
    required this.isOrganizer,
    required this.canRemove,
    required this.onRemove,
  });

  final MatchParticipant participant;
  final bool isOrganizer;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tone = switch (participant.status) {
      MatchParticipantStatus.accepted => SportikaColors.mint,
      MatchParticipantStatus.invited => SportikaColors.gold,
      MatchParticipantStatus.declined => SportikaColors.danger,
      MatchParticipantStatus.removed => SportikaColors.textDim,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          PlayerAvatar(
            initials: initialsOf(participant.displayName),
            size: 30,
            color: SportikaColors.blueBright,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  participant.displayName.isEmpty
                      ? 'Player'
                      : participant.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.bodyStrong,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusPill(participant.status.label, color: tone),
                    if (isOrganizer)
                      const StatusPill(
                        'Organizer',
                        color: SportikaColors.blueBright,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (canRemove)
            IconButton(
              onPressed: onRemove,
              tooltip: 'Remove ${participant.displayName}',
              icon: const Icon(
                Icons.close,
                size: 17,
                color: SportikaColors.textDim,
              ),
            ),
        ],
      ),
    );
  }
}
