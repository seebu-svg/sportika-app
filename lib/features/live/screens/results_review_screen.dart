import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/shared/widgets/fixture_tile.dart';
import 'package:sportika/shared/widgets/results_actions.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// The organizer review queue. Nothing here changes a bracket until the
/// organizer publishes (spec §4.5, §6).
class ResultsReviewScreen extends StatelessWidget {
  const ResultsReviewScreen({super.key, this.tournamentId, this.highlightId});

  final String? tournamentId;
  final String? highlightId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LocalSportikaRepository>();
    final submitted = state.fixturesAwaitingReview
        .where((f) => tournamentId == null || f.tournamentId == tournamentId)
        .toList();
    final published =
        state.fixtures
            .where(
              (f) =>
                  f.status == FixtureStatus.published &&
                  (tournamentId == null || f.tournamentId == tournamentId),
            )
            .toList()
          ..sort(
            (a, b) => (b.completedAt ?? b.scheduledAt).compareTo(
              a.completedAt ?? a.scheduledAt,
            ),
          );

    final tournament = tournamentId == null
        ? null
        : state.tournamentById(tournamentId!);

    return Scaffold(
      appBar: sportikaAppBar(
        'Results review',
        subtitle: tournament?.name ?? 'All your tournaments',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        children: [
          const InfoBanner(
            icon: Icons.account_tree_outlined,
            tone: SportikaColors.mint,
            text:
                'Publishing moves the bracket or table. Scorer submissions stay locked '
                'until you decide.',
          ),
          SectionTitle('Awaiting publication (${submitted.length})'),
          if (submitted.isEmpty)
            const EmptyState(
              title: 'Queue is clear',
              body: 'Fixtures appear here the moment a scorer submits a score.',
              icon: Icons.done_all,
            )
          else
            for (final fixture in submitted)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ReviewItem(
                  fixture: fixture,
                  highlight: fixture.id == highlightId,
                ),
              ),
          const SectionTitle('Published results'),
          if (published.isEmpty)
            const EmptyState(
              title: 'No published results yet',
              body: 'Publish a submitted score to start moving the draw.',
              icon: Icons.verified_outlined,
            )
          else
            for (final fixture in published.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  children: [
                    officialFixtureTile(context, fixture),
                    const SizedBox(height: 6),
                    GhostButton(
                      label: 'Publish a correction',
                      icon: Icons.edit_note,
                      expand: true,
                      tone: SportikaColors.gold,
                      onPressed: () => publishFixture(context, fixture),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _ReviewItem extends StatelessWidget {
  const _ReviewItem({required this.fixture, required this.highlight});

  final Fixture fixture;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final state = context.read<LocalSportikaRepository>();
    final progress = state.progressOfFixture(fixture);
    final sides = state.sideLabelsOf(fixture);
    final tournament = state.tournamentOf(fixture);

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: highlight
                  ? SportikaColors.gold.withValues(alpha: 0.7)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: officialFixtureTile(context, fixture),
        ),
        const SizedBox(height: 6),
        SurfaceCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${tournament?.name ?? 'Tournament'} · ${fixture.stage}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: SportikaColors.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                progress.headline.isEmpty
                    ? '${sides[0]} vs ${sides[1]}'
                    : progress.headline,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: SportikaColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${progress.scoreDisplay.length >= 2 ? progress.scoreDisplay.join('  ·  ') : ''}'
                ' · ${fixture.events.length} entries'
                ' · submitted by ${state.accountById(fixture.submittedByScorerId)?.displayName ?? 'scorer'}',
                style: const TextStyle(
                  fontSize: 11,
                  color: SportikaColors.textMuted,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      label: 'Publish',
                      icon: Icons.verified_outlined,
                      small: true,
                      tone: SportikaColors.mint,
                      onPressed: () => publishFixture(context, fixture),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GhostButton(
                    label: 'Walkover',
                    icon: Icons.flag_outlined,
                    onPressed: () => recordWalkoverFor(context, fixture),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
