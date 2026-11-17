import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/matches/scoring/futsal_roster.dart';
import 'package:sportika/features/matches/widgets/team_match_logo.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Match membership, with accepted places and invitations counted separately.
class MatchRosterCard extends StatelessWidget {
  const MatchRosterCard({
    super.key,
    required this.match,
    this.accountId,
    this.onInviteSide,
  });

  final SportMatch match;
  final String? accountId;
  final ValueChanged<int>? onInviteSide;

  @override
  Widget build(BuildContext context) {
    final pending = match.participants
        .where((p) => p.status == MatchParticipantStatus.invited)
        .length;
    final open = (match.capacity - match.acceptedCount).clamp(
      0,
      match.capacity,
    );
    final canInvite =
        match.isOrganizer(accountId) &&
        onInviteSide != null &&
        (match.status == FixtureStatus.upcoming ||
            match.status == FixtureStatus.live) &&
        open > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(SportikaSpacing.lg),
          decoration: BoxDecoration(
            color: SportikaColors.surface,
            borderRadius: BorderRadius.circular(SportikaRadius.lg),
            border: Border.all(color: SportikaColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('MATCH SQUAD', style: SportikaType.label),
              const SizedBox(height: SportikaSpacing.sm),
              Wrap(
                spacing: SportikaSpacing.lg,
                runSpacing: SportikaSpacing.sm,
                children: [
                  _RosterMetric(
                    value: '${match.acceptedCount}/${match.capacity}',
                    label: 'Confirmed',
                    tone: SportikaColors.mint,
                  ),
                  _RosterMetric(
                    value: '$pending',
                    label: 'Pending',
                    tone: SportikaColors.gold,
                  ),
                  _RosterMetric(
                    value: '$open',
                    label: 'Open places',
                    tone: SportikaColors.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: SportikaSpacing.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(SportikaRadius.pill),
                child: LinearProgressIndicator(
                  value: match.capacity > 0
                      ? (match.acceptedCount / match.capacity).clamp(0, 1)
                      : 0,
                  minHeight: SportikaSpacing.xs,
                  color: SportikaColors.mint,
                  backgroundColor: SportikaColors.border,
                  semanticsLabel:
                      '${match.acceptedCount} of ${match.capacity} roster places confirmed',
                ),
              ),
              if (pending > 0) ...[
                const SizedBox(height: SportikaSpacing.sm),
                const Text(
                  'Pending invitations count as open places until accepted.',
                  style: SportikaType.caption,
                ),
              ],
            ],
          ),
        ),
        for (var side = 0; side < 2; side++) ...[
          const SizedBox(height: SportikaSpacing.md),
          _RosterSide(
            match: match,
            side: side,
            accountId: accountId,
            onInvite: canInvite ? () => onInviteSide!(side) : null,
          ),
        ],
      ],
    );
  }
}

class _RosterMetric extends StatelessWidget {
  const _RosterMetric({
    required this.value,
    required this.label,
    required this.tone,
  });
  final String value;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: SportikaType.score.copyWith(color: tone)),
      const SizedBox(height: SportikaSpacing.xs),
      Text(label, style: SportikaType.caption),
    ],
  );
}

class _RosterSide extends StatelessWidget {
  const _RosterSide({
    required this.match,
    required this.side,
    this.accountId,
    this.onInvite,
  });
  final SportMatch match;
  final int side;
  final String? accountId;
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    final tone = side == 0 ? SportikaColors.blueBright : SportikaColors.mint;
    final members = match.participants.where((p) => p.side == side).toList();
    final accepted = members
        .where((p) => p.status == MatchParticipantStatus.accepted)
        .toList();
    final invited = members
        .where((p) => p.status == MatchParticipantStatus.invited)
        .toList();
    final previous = members
        .where(
          (p) =>
              p.status == MatchParticipantStatus.declined ||
              p.status == MatchParticipantStatus.removed,
        )
        .toList();
    final names = match.sideLabels;
    final name = names.length > side
        ? names[side]
        : 'Side ${side == 0 ? 'A' : 'B'}';
    final ids = match.rules['teamIds'];
    final teamId = ids is List && ids.length > side
        ? ids[side] as String?
        : null;
    final starters = match.sport == Sport.futsal
        ? FutsalRoster.starters(match, side)
        : <String>{};
    return Container(
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SportikaColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TeamMatchLogo(teamId: teamId, name: name, color: tone, size: 48),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      side == 0 ? 'SIDE A' : 'SIDE B',
                      style: SportikaType.micro.copyWith(color: tone),
                    ),
                    const SizedBox(height: SportikaSpacing.xs),
                    Text(
                      name,
                      style: SportikaType.bodyStrong,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: SportikaSpacing.xs),
                    Text(
                      '${accepted.length} confirmed · ${invited.length} pending',
                      style: SportikaType.caption,
                    ),
                  ],
                ),
              ),
              if (onInvite != null) ...[
                const SizedBox(width: SportikaSpacing.sm),
                GhostButton(
                  label: 'Invite',
                  icon: Icons.person_add_alt,
                  onPressed: onInvite,
                ),
              ],
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: SportikaSpacing.md),
            child: Divider(height: 1, color: SportikaColors.borderSubtle),
          ),
          if (accepted.isEmpty && invited.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.person_add_alt_1_outlined, color: tone, size: 20),
                  const SizedBox(width: SportikaSpacing.sm),
                  const Expanded(
                    child: Text(
                      'The lineup starts here. No confirmed players or pending invitations yet.',
                      style: SportikaType.caption,
                    ),
                  ),
                ],
              ),
            ),
          // Counts and team identity stay visible when a large squad is folded.
          for (final player in [...accepted, ...invited].take(5))
            _player(player, starters, tone),
          if (accepted.length + invited.length > 5)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                'Show remaining players (${accepted.length + invited.length - 5})',
                style: SportikaType.bodyStrong,
              ),
              children: [
                for (final player in [...accepted, ...invited].skip(5))
                  _player(player, starters, tone),
              ],
            ),
          if (previous.isNotEmpty)
            Material(
              color: SportikaColors.surface,
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  'Previous invitations (${previous.length})',
                  style: SportikaType.caption,
                ),
                children: [
                  for (final player in previous)
                    _RosterPlayer(
                      player: player,
                      match: match,
                      accountId: accountId,
                      tone: SportikaColors.textDim,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _player(MatchParticipant player, Set<String> starters, Color tone) =>
      _RosterPlayer(
        player: player,
        match: match,
        accountId: accountId,
        tone: tone,
        lineup:
            match.sport == Sport.futsal &&
                player.status == MatchParticipantStatus.accepted
            ? starters.contains(player.profileId)
                  ? 'Starter'
                  : 'Substitute'
            : null,
      );
}

class _RosterPlayer extends StatelessWidget {
  const _RosterPlayer({
    required this.player,
    required this.match,
    required this.tone,
    this.accountId,
    this.lineup,
  });
  final MatchParticipant player;
  final SportMatch match;
  final Color tone;
  final String? accountId;
  final String? lineup;

  @override
  Widget build(BuildContext context) {
    final account = context.watch<SessionController>().accountById(
      player.profileId,
    );
    final stateTone = switch (player.status) {
      MatchParticipantStatus.accepted => SportikaColors.mint,
      MatchParticipantStatus.invited => SportikaColors.gold,
      MatchParticipantStatus.declined => SportikaColors.danger,
      MatchParticipantStatus.removed => SportikaColors.textDim,
    };
    final metadata = [
      if (player.profileId == match.organizerId) 'Organizer',
      if (player.profileId == match.scorerId) 'Official Scorer',
      ?lineup,
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: SportikaSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SportikaColors.borderSubtle)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlayerAvatar(
            initials: initialsOf(player.displayName),
            size: 48,
            color: tone,
            photoUrl: account?.photoUrl,
            photoPath: account?.photoPath,
          ),
          const SizedBox(width: SportikaSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${player.displayName.isEmpty ? 'Player' : player.displayName}${player.profileId == accountId ? ' (You)' : ''}',
                  style: SportikaType.bodyStrong,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: SportikaSpacing.xs),
                Text(
                  player.status == MatchParticipantStatus.invited
                      ? 'Pending invitation'
                      : player.status.label,
                  style: SportikaType.caption.copyWith(color: stateTone),
                ),
                if (metadata.isNotEmpty) ...[
                  const SizedBox(height: SportikaSpacing.xs),
                  Text(metadata.join(' · '), style: SportikaType.caption),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
