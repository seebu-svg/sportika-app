import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/personal_games/screens/scorecard_screen.dart';

/// Scorer home (spec §4.4): every fixture assigned to the account, with a
/// single tap back into the live scorecard.
class ScorerWorkspaceScreen extends StatelessWidget {
  const ScorerWorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FixturesController>();
    final assigned = state.myScoringFixtures;
    final inPlay = assigned
        .where((f) => f.status != FixtureStatus.submitted)
        .toList();
    final awaiting = assigned
        .where((f) => f.status == FixtureStatus.submitted)
        .toList();

    return Scaffold(
      appBar: sportikaAppBar(
        'Scorer workspace',
        subtitle: '${assigned.length} fixtures assigned',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        children: [
          const InfoBanner(
            icon: Icons.swap_horiz,
            tone: SportikaColors.blueBright,
            text:
                'If an organizer transfers this fixture to another scorer, everything '
                'recorded so far carries over. Your log is saved after every entry.',
          ),
          SectionTitle('To score (${inPlay.length})'),
          if (inPlay.isEmpty)
            const EmptyState(
              title: 'No fixtures assigned',
              body:
                  'Organizers assign scorers when they publish the draw. You will get '
                  'a notification when one lands.',
              icon: Icons.sports_score,
            )
          else
            for (final fixture in inPlay)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ScorerFixtureCard(fixture: fixture),
              ),
          if (awaiting.isNotEmpty) ...[
            SectionTitle('Submitted, in review (${awaiting.length})'),
            for (final fixture in awaiting)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ScorerFixtureCard(fixture: fixture),
              ),
          ],
        ],
      ),
    );
  }
}

class _ScorerFixtureCard extends StatelessWidget {
  const _ScorerFixtureCard({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FixturesController>();
    final tournament = state.tournamentOf(fixture);
    final sport = tournament?.sport ?? Sport.cricket;
    final sides = state.sideLabelsOf(fixture);
    final progress = state.progressOfFixture(fixture);
    final submitted = fixture.status == FixtureStatus.submitted;
    final notStarted =
        fixture.status == FixtureStatus.upcoming && fixture.events.isEmpty;

    return SurfaceCard(
      onTap: () => pushRoute(
        context,
        AppRoute.scorecard,
        args: ScorecardArgs(fixture.id, ScorecardMode.official),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SportTag(sport, compact: true),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${tournament?.name ?? 'Fixture'} · ${fixture.stage}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: SportikaColors.textMuted,
                  ),
                ),
              ),
              StatusPill(
                fixture.status.label,
                color: statusColor(fixture.status.key),
                icon: statusIcon(fixture.status.key),
              ),
            ],
          ),
          const SizedBox(height: 9),
          _side(
            sides[0],
            progress.scoreDisplay.isNotEmpty ? progress.scoreDisplay[0] : '',
          ),
          const SizedBox(height: 4),
          _side(
            sides[1],
            progress.scoreDisplay.length > 1 ? progress.scoreDisplay[1] : '',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.schedule,
                size: 12,
                color: SportikaColors.textDim,
              ),
              const SizedBox(width: 4),
              Text(
                dateShort(fixture.scheduledAt),
                style: const TextStyle(
                  fontSize: 11,
                  color: SportikaColors.textMuted,
                ),
              ),
              const Dot(),
              Text(
                '${fixture.events.length} entries',
                style: const TextStyle(
                  fontSize: 11,
                  color: SportikaColors.textMuted,
                ),
              ),
              const Spacer(),
              Text(
                submitted
                    ? 'View submitted'
                    : notStarted
                    ? 'Start scoring'
                    : 'Resume',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: submitted
                      ? SportikaColors.gold
                      : SportikaColors.blueBright,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: submitted
                    ? SportikaColors.gold
                    : SportikaColors.blueBright,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _side(String label, String score) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: SportikaColors.text,
          ),
        ),
      ),
      if (score.isNotEmpty)
        Text(
          score,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: SportikaColors.blueBright,
          ),
        ),
    ],
  );
}
