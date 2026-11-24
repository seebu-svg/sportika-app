import 'package:flutter/material.dart';

import 'package:sportika/features/matches/widgets/padel_match_center.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Padel's head-to-head roster.
///
/// The pairing itself is rendered by the shared [PadelHeadToHead], so the faces
/// on this tab are the same widget, size and fallback chain as the ones in the
/// hero and in the result panel. What stays here is the roster workflow the
/// organizer needs: invitations per side, everyone outside the starting slots,
/// and the declined/removed history.
class PadelMatchLineup extends StatelessWidget {
  const PadelMatchLineup({
    super.key,
    required this.match,
    required this.progress,
    this.accountId,
    this.onInviteSide,
  });

  final SportMatch match;
  final MatchProgress progress;
  final String? accountId;
  final ValueChanged<int>? onInviteSide;

  /// Inviting is only offered while the organizer still has places to fill and
  /// the match can take players — unchanged from the previous lineup.
  bool get _canInvite {
    if (onInviteSide == null) return false;
    if (!(match.isOrganizer(accountId) &&
        (match.status == FixtureStatus.upcoming || match.isLive))) {
      return false;
    }
    return match.acceptedCount < match.capacity;
  }

  @override
  Widget build(BuildContext context) {
    final slots = match.discipline == MatchDiscipline.doubles ? 2 : 1;
    // Everyone who is on a side but not in its starting pair: extra accepted
    // players, plus anybody still sitting at `invited`.
    final pending = <MatchParticipant>[
      for (var side = 0; side < 2; side++) ...[
        ...match.participantsOnSide(side).skip(slots),
        ...match.participants.where(
          (p) => p.side == side && p.status == MatchParticipantStatus.invited,
        ),
      ],
    ];
    final previous = match.participants
        .where(
          (p) =>
              p.status == MatchParticipantStatus.declined ||
              p.status == MatchParticipantStatus.removed,
        )
        .toList();
    final winner = match.result?.winnerIndex ?? -1;

    return SurfaceCard(
      fillColor: SportikaColors.surfaceSunken,
      padding: const EdgeInsets.all(SportikaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'MATCH LINEUP',
            style: SportikaType.micro.copyWith(color: SportikaColors.textDim),
          ),
          const SizedBox(height: SportikaSpacing.md),
          PadelHeadToHead(
            match: match,
            progress: progress,
            accountId: accountId,
            winnerIndex: winner,
            onInviteSide: _canInvite ? onInviteSide : null,
          ),
          if (pending.isNotEmpty || previous.isNotEmpty) ...[
            const SizedBox(height: SportikaSpacing.sm),
            const Divider(height: 1, color: SportikaColors.borderSubtle),
            for (final player in pending)
              _RosterLine(match: match, player: player, accountId: accountId),
            if (previous.isNotEmpty)
              ExpansionTile(
                key: PageStorageKey('padel-lineup-history-${match.id}'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                shape: const Border(),
                collapsedShape: const Border(),
                iconColor: SportikaColors.textMuted,
                collapsedIconColor: SportikaColors.textMuted,
                title: Text(
                  'Previous invitations (${previous.length})',
                  style: SportikaType.caption,
                ),
                children: [
                  for (final player in previous)
                    _RosterLine(
                      match: match,
                      player: player,
                      accountId: accountId,
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

/// One roster line outside the starting pair: the name, its invitation state,
/// and any role the player also holds in this match.
class _RosterLine extends StatelessWidget {
  const _RosterLine({
    required this.match,
    required this.player,
    required this.accountId,
  });

  final SportMatch match;
  final MatchParticipant player;
  final String? accountId;

  @override
  Widget build(BuildContext context) {
    final roles = <String>[
      player.status.label,
      if (player.profileId == match.organizerId) 'Organizer',
      if (player.profileId == match.scorerId) 'Official Scorer',
      if (player.profileId == accountId) 'You',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SportikaSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              player.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SportikaType.body,
            ),
          ),
          const SizedBox(width: SportikaSpacing.sm),
          Flexible(
            child: Text(
              roles.join(' · '),
              textAlign: TextAlign.end,
              style: SportikaType.caption,
            ),
          ),
        ],
      ),
    );
  }
}
