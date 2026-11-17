import 'package:flutter/material.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/shared/widgets/match_scoreboard.dart';
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

  final progress = fixture.events.isEmpty
      ? null
      : state.progressOfFixture(fixture);
  final entries = context.read<TournamentsController>().entriesById;
  final session = context.read<SessionController>();
  final players = [
    for (final side in [fixture.home, fixture.away])
      [
        for (final id in entries[side.entryId]?.memberAccountIds ?? <String>[])
          if (session.accountById(id) case final Account account) account,
      ],
  ];

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
    scoreboard: MatchScoreboard(
      sport: sport,
      labels: state.sideLabelsOf(fixture),
      progress: progress,
      result: fixture.result,
      players: players,
      finished: fixture.result != null,
      discipline: tournament?.entryType == EntryType.individual
          ? 'Singles'
          : tournament?.entryType == EntryType.pair
          ? 'Doubles'
          : null,
    ),
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
    scoreboard: MatchScoreboard(
      sport: match.sport,
      labels: [
        match.sideNames.isNotEmpty ? match.sideNames[0] : 'Side A',
        match.sideNames.length > 1 ? match.sideNames[1] : 'Side B',
      ],
      progress: match.events.isEmpty ? null : progress,
      finished: completed,
      discipline: switch (match.rules['discipline']) {
        'singles' => 'Singles',
        'doubles' => 'Doubles',
        _ => null,
      },
    ),
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
