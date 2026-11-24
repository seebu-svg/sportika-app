import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Displays the engine's current server without predicting service rotation.
class PadelServingIndicator extends StatelessWidget {
  const PadelServingIndicator({
    super.key,
    required this.match,
    required this.progress,
  });
  final SportMatch match;
  final MatchProgress progress;

  static int? _index(dynamic value) =>
      value is num &&
          value.isFinite &&
          value >= 0 &&
          value == value.truncateToDouble()
      ? value.toInt()
      : null;

  /// Reads the serving player's account, or null when no session is in scope.
  ///
  /// provider 6.1 has no optional lookup, so the absent-provider case is
  /// reported by [ProviderNotFoundException] and caught here.
  static Account? _accountFor(BuildContext context, String profileId) {
    try {
      return context.watch<SessionController>().accountById(profileId);
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (progress.isComplete ||
        match.isFinished ||
        match.result != null ||
        match.awaitingReview) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: SportikaSpacing.sm),
        child: Text('Service concluded', style: SportikaType.caption),
      );
    }
    if (!match.isLive) return const SizedBox.shrink();
    final side = _index(progress.state['servingSide']);
    if (side == null || side > 1) {
      return const Text('Server unavailable', style: SportikaType.caption);
    }
    final doubles = match.discipline == MatchDiscipline.doubles;
    final member = doubles ? _index(progress.state['servingMember']) : 0;
    final members = match.participantsOnSide(side);
    final player =
        member != null && member < (doubles ? 2 : 1) && member < members.length
        ? members[member]
        : null;
    // The photo is a nicety: this workspace renders from `match` + `progress`
    // alone, so a missing session scope falls back to initials instead of
    // taking the scoring screen down with it. In the app SessionController is
    // provided above every route, so the lookup always succeeds there.
    final account = player == null
        ? null
        : _accountFor(context, player.profileId);
    final name = player?.displayName.trim().isNotEmpty == true
        ? player!.displayName
        : 'Server unavailable';
    final team = match.sideLabels.length > side ? match.sideLabels[side] : null;
    final paused = match.isPaused;
    final tieBreak = progress.state['inTiebreak'] == true;
    final label = paused
        ? 'SERVICE PAUSED'
        : tieBreak
        ? 'SERVING · TIE-BREAK'
        : 'SERVING';
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SportikaSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(SportikaSpacing.xs / 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: paused || player == null
                      ? SportikaColors.borderSubtle
                      : SportikaColors.mint,
                ),
              ),
              child: PlayerAvatar(
                initials: player == null ? '—' : initialsOf(name),
                photoUrl: account?.photoUrl,
                photoPath: account?.photoPath,
                size: SportikaSpacing.xl * 2,
                color: SportikaColors.textMuted,
                ring: SportikaColors.surfaceSunken,
              ),
            ),
            const SizedBox(width: SportikaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: SportikaType.micro.copyWith(
                      color: paused
                          ? SportikaColors.textMuted
                          : SportikaColors.mint,
                    ),
                  ),
                  const SizedBox(height: SportikaSpacing.xs),
                  Text(name, style: SportikaType.bodyStrong),
                  if (team != null &&
                      team.trim().isNotEmpty &&
                      team != name) ...[
                    const SizedBox(height: SportikaSpacing.xs),
                    Text(team, style: SportikaType.caption),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
