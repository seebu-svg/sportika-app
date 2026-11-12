import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/personal_games_controller.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/features/personal_games/screens/scorecard_screen.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Shared official fixture card used by Home, Match Center, tournament pages
/// and organizer lists, so a fixture always reads the same way.
Widget officialFixtureTile(
  BuildContext context,
  Fixture fixture, {
  VoidCallback? onTap,
  bool showTournament = true,
}) {
  final state = context.read<FixturesController>();
  final tournament = state.tournamentOf(fixture);
  final sport = tournament?.sport ?? Sport.cricket;

  String? homeScore;
  String? awayScore;
  final result = fixture.result;
  if (result != null && result.sideScores.length >= 2) {
    homeScore = result.sideScores[0];
    awayScore = result.sideScores[1];
  } else if (fixture.events.isNotEmpty) {
    final state = context.read<FixturesController>();
    final progress = state.progressOfFixture(fixture);
    if (progress.scoreDisplay.length >= 2) {
      homeScore = progress.scoreDisplay[0];
      awayScore = progress.scoreDisplay[1];
    }
  }

  return FixtureRow(
    topLeft: Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SportTag(sport, compact: true),
        Text(
          dateShort(fixture.scheduledAt),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: SportikaColors.textMuted,
          ),
        ),
      ],
    ),
    homeLabel: state.sideLabel(fixture, 0),
    awayLabel: state.sideLabel(fixture, 1),
    homeScore: homeScore,
    awayScore: awayScore,
    statusKey: fixture.status.key,
    statusLabel: fixture.stage.isEmpty
        ? fixture.status.label
        : fixture.status.label,
    accent: statusColor(fixture.status.key),
    footer: showTournament
        ? Row(
            children: [
              Expanded(
                child: Text(
                  '${tournament?.name ?? 'Tournament'} · ${fixture.stage}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: SportikaColors.textMuted,
                  ),
                ),
              ),
              if (fixture.disputeNote != null && !fixture.disputeResolved)
                const StatusPill('Disputed', color: SportikaColors.danger),
            ],
          )
        : null,
    onTap:
        onTap ??
        () => pushRoute(
          context,
          AppRoute.fixtureDetail,
          args: FixtureDetailArgs(fixture.id),
        ),
  );
}

/// Private scorecard card used by Home and Match History.
Widget personalScorecardTile(
  BuildContext context,
  PersonalMatch match, {
  VoidCallback? onTap,
}) {
  final progress = context.read<PersonalGamesController>().progressOfPersonal(
    match,
  );
  final completed = match.status == PersonalMatchStatus.completed;

  String? homeScore;
  String? awayScore;
  if (progress.scoreDisplay.length >= 2) {
    homeScore = progress.scoreDisplay[0];
    awayScore = progress.scoreDisplay[1];
  }

  return FixtureRow(
    topLeft: Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SportTag(match.sport, compact: true),
        Text(
          match.formatLabel,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: SportikaColors.textMuted,
          ),
        ),
      ],
    ),
    homeLabel: match.sideNames.isNotEmpty ? match.sideNames[0] : 'Side A',
    awayLabel: match.sideNames.length > 1 ? match.sideNames[1] : 'Side B',
    homeScore: homeScore,
    awayScore: awayScore,
    statusKey: match.status.key,
    statusLabel: completed ? 'Completed' : 'In progress',
    accent: completed ? SportikaColors.textMuted : SportikaColors.mint,
    footer: Row(
      children: [
        const Icon(Icons.lock_outline, size: 11, color: SportikaColors.textDim),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            'Private · ${match.events.length} entries · ${timeAgo(match.updatedAt)}',
            style: const TextStyle(
              fontSize: 11,
              color: SportikaColors.textMuted,
            ),
          ),
        ),
      ],
    ),
    onTap:
        onTap ??
        () => pushRoute(
          context,
          AppRoute.scorecard,
          args: ScorecardArgs(match.id, ScorecardMode.personal),
        ),
  );
}
