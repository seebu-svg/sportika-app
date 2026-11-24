import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/shared/widgets/fixture_tile.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/results_actions.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Organizer Results Control Center.
///
/// Submitted scores remain provisional until the organizer completes
/// the existing publishFixture flow. No bracket changes occur here
/// independently of the controller's publication workflow.
class ResultsReviewScreen extends StatelessWidget {
  const ResultsReviewScreen({super.key, this.tournamentId, this.highlightId});

  final String? tournamentId;
  final String? highlightId;

  @override
  Widget build(BuildContext context) {
    final fixtures = context.watch<FixturesController>();
    final session = context.watch<SessionController>();

    if (!session.ready) {
      return const ScreenScaffold(
        title: 'Results review',
        child: LoadingSkeleton(rows: 2, label: 'Loading the review queue'),
      );
    }

    if (!session.canOrganize) {
      return ScreenScaffold(
        title: 'Results review',
        child: ErrorState(
          title: 'Sign in to review',
          message:
              'Only the organizer of a tournament can publish its results. '
              'Ask them to review the submission.',
          icon: Icons.verified_outlined,
          retryLabel: 'Go back',
          onRetry: () => Navigator.of(context).maybePop(),
        ),
      );
    }

    final submitted = fixtures.fixturesAwaitingReview
        .where(
          (fixture) =>
              tournamentId == null || fixture.tournamentId == tournamentId,
        )
        .toList();

    final published =
        fixtures.myOrganizerFixtures
            .where(
              (fixture) =>
                  fixture.status == FixtureStatus.published &&
                  (tournamentId == null ||
                      fixture.tournamentId == tournamentId),
            )
            .toList()
          ..sort(
            (a, b) => (b.completedAt ?? b.scheduledAt).compareTo(
              a.completedAt ?? a.scheduledAt,
            ),
          );

    final tournament = tournamentId == null
        ? null
        : context.watch<TournamentsController>().tournamentById(tournamentId!);

    if (tournamentId != null && tournament == null) {
      return ScreenScaffold(
        title: 'Results review',
        child: ErrorState(
          title: 'Tournament not found',
          message: 'This event is no longer in your organizer list.',
          retryLabel: 'Go back',
          onRetry: () => Navigator.of(context).maybePop(),
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;

    final inset = width > sportikaMaxContentWidth
        ? (width - sportikaMaxContentWidth) / 2 + SportikaSpacing.md
        : SportikaSpacing.md;

    return Scaffold(
      appBar: sportikaAppBar(
        'Results review',
        subtitle: tournament?.name ?? 'All your tournaments',
      ),
      body: RefreshIndicator(
        onRefresh: fixtures.reload,
        color: SportikaColors.mint,
        backgroundColor: SportikaColors.surface,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            inset,
            SportikaSpacing.sm,
            inset,
            SportikaSpacing.xxl,
          ),
          children: [
            // ============================================
            // ORGANIZER HEADER
            // ============================================

            const _ReviewHeader(),

            const SizedBox(height: SportikaSpacing.md),

            // ============================================
            // REVIEW METRICS
            // ============================================
            Row(
              children: [
                Expanded(
                  child: _ReviewMetric(
                    icon: Icons.pending_actions_rounded,
                    label: 'Awaiting review',
                    count: submitted.length,
                    tone: SportikaColors.gold,
                  ),
                ),
                const SizedBox(width: SportikaSpacing.sm),
                Expanded(
                  child: _ReviewMetric(
                    icon: Icons.verified_outlined,
                    label: 'Published',
                    count: published.length,
                    tone: SportikaColors.mint,
                  ),
                ),
              ],
            ),

            const SizedBox(height: SportikaSpacing.md),

            // ============================================
            // PUBLICATION INFORMATION
            // ============================================
            const InfoBanner(
              icon: Icons.account_tree_outlined,
              tone: SportikaColors.mint,
              text:
                  'Publishing makes a result official and advances the '
                  'bracket or standings. Submitted scores remain locked '
                  'until you review them.',
            ),

            // ============================================
            // PENDING REVIEW QUEUE
            // ============================================
            SectionTitle('Awaiting publication (${submitted.length})'),

            if (submitted.isEmpty)
              const _QueueClearState()
            else
              for (final fixture in submitted)
                Padding(
                  padding: const EdgeInsets.only(bottom: SportikaSpacing.md),
                  child: _ReviewItem(
                    fixture: fixture,
                    highlight: fixture.id == highlightId,
                  ),
                ),

            // ============================================
            // PUBLISHED RESULTS
            // ============================================
            const SectionTitle('Published results'),

            if (published.isEmpty)
              const EmptyState(
                title: 'No published results yet',
                body:
                    'Official results will appear here after you '
                    'review and publish a submitted score.',
                icon: Icons.verified_outlined,
              )
            else
              for (final fixture in published.take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: SportikaSpacing.md),
                  child: _PublishedResultItem(fixture: fixture),
                ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ORGANIZER HEADER
// ============================================================

class _ReviewHeader extends StatelessWidget {
  const _ReviewHeader();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: SportikaColors.blueBright.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(SportikaRadius.md),
            ),
            child: const Icon(
              Icons.fact_check_outlined,
              color: SportikaColors.blueBright,
              size: 27,
            ),
          ),

          const SizedBox(width: SportikaSpacing.md),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ORGANIZER WORKSPACE',
                  style: SportikaType.micro.copyWith(
                    color: SportikaColors.mint,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: SportikaSpacing.xs),
                const Text(
                  'Official results control',
                  style: SportikaType.bodyStrong,
                ),
                const SizedBox(height: SportikaSpacing.xs),
                const Text(
                  'Review scorer submissions and verify results before publication.',
                  style: SportikaType.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// REVIEW METRIC
// ============================================================

class _ReviewMetric extends StatelessWidget {
  const _ReviewMetric({
    required this.icon,
    required this.label,
    required this.count,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: tone),
          const SizedBox(height: SportikaSpacing.sm),
          Text(
            '$count',
            style: SportikaType.display(28)
                .copyWith(color: SportikaColors.text),
          ),
          const SizedBox(height: SportikaSpacing.xs),
          Text(
            label,
            style: SportikaType.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// QUEUE CLEAR STATE
// ============================================================

class _QueueClearState extends StatelessWidget {
  const _QueueClearState();

  @override
  Widget build(BuildContext context) {
    return const SurfaceCard(
      child: Column(
        children: [
          Icon(Icons.task_alt_rounded, color: SportikaColors.mint, size: 34),
          SizedBox(height: SportikaSpacing.sm),
          Text('Review queue clear', style: SportikaType.bodyStrong),
          SizedBox(height: SportikaSpacing.xs),
          Text(
            'New submissions will appear here when an official scorer submits a result.',
            style: SportikaType.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PENDING REVIEW CARD
// ============================================================

class _ReviewItem extends StatelessWidget {
  const _ReviewItem({required this.fixture, required this.highlight});

  final Fixture fixture;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final fixtures = context.read<FixturesController>();
    final session = context.read<SessionController>();

    final progress = fixtures.progressOfFixture(fixture);
    final sides = fixtures.sideLabelsOf(fixture);
    final tournament = fixtures.tournamentOf(fixture);

    final scorerName =
        session.accountById(fixture.submittedByScorerId)?.displayName ??
        'Official scorer';

    final scores = progress.scoreDisplay;

    return SurfaceCard(
      borderColor: highlight ? SportikaColors.gold : SportikaColors.border,
      padding: const EdgeInsets.all(SportikaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ----------------------------------------
          // COMPETITION / STATUS
          // ----------------------------------------

          Row(
            children: [
              Expanded(
                child: Text(
                  '${tournament?.name ?? 'Tournament'} · ${fixture.stage}',
                  style: SportikaType.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              _ReviewStatus(highlighted: highlight),
            ],
          ),

          const SizedBox(height: SportikaSpacing.md),

          // ----------------------------------------
          // SUBMITTED SCOREBOARD
          // ----------------------------------------
          Row(
            children: [
              Expanded(
                child: _ScoreSide(
                  name: sides.isNotEmpty ? sides[0] : 'Side A',
                  score: scores.isNotEmpty ? scores[0] : '—',
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SportikaSpacing.sm,
                ),
                child: Text(
                  'VS',
                  style: SportikaType.label.copyWith(
                    color: SportikaColors.textDim,
                  ),
                ),
              ),

              Expanded(
                child: _ScoreSide(
                  name: sides.length > 1 ? sides[1] : 'Side B',
                  score: scores.length > 1 ? scores[1] : '—',
                  alignRight: true,
                ),
              ),
            ],
          ),

          if (progress.headline.isNotEmpty) ...[
            const SizedBox(height: SportikaSpacing.md),
            Text(progress.headline, style: SportikaType.bodyStrong),
          ],

          const SizedBox(height: SportikaSpacing.md),

          const Divider(color: SportikaColors.border, height: 1),

          const SizedBox(height: SportikaSpacing.sm),

          // ----------------------------------------
          // SUBMISSION METADATA
          // ----------------------------------------
          Row(
            children: [
              const Icon(
                Icons.assignment_turned_in_outlined,
                color: SportikaColors.textMuted,
                size: 16,
              ),
              const SizedBox(width: SportikaSpacing.xs),
              Expanded(
                child: Text(
                  'Submitted by $scorerName',
                  style: SportikaType.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${fixture.events.length} entries',
                style: SportikaType.micro,
              ),
            ],
          ),

          const SizedBox(height: SportikaSpacing.md),

          // ----------------------------------------
          // ACTIONS
          // ----------------------------------------
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Review & publish',
                  icon: Icons.verified_outlined,
                  small: true,
                  tone: SportikaColors.mint,
                  onPressed: () => publishFixture(context, fixture),
                ),
              ),

              const SizedBox(width: SportikaSpacing.sm),

              PopupMenuButton<String>(
                tooltip: 'More result actions',
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: SportikaColors.textBody,
                ),
                onSelected: (value) {
                  if (value == 'walkover') {
                    recordWalkoverFor(context, fixture);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'walkover',
                    child: Row(
                      children: [
                        Icon(Icons.flag_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Record walkover'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SCORE SIDE
// ============================================================

class _ScoreSide extends StatelessWidget {
  const _ScoreSide({
    required this.name,
    required this.score,
    this.alignRight = false,
  });

  final String name;
  final String score;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignRight
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: SportikaType.bodyStrong,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: alignRight ? TextAlign.right : TextAlign.left,
        ),
        const SizedBox(height: SportikaSpacing.sm),
        Text(
          score,
          style: SportikaType.scoreSmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: alignRight ? TextAlign.right : TextAlign.left,
        ),
      ],
    );
  }
}

// ============================================================
// REVIEW STATUS
// ============================================================

class _ReviewStatus extends StatelessWidget {
  const _ReviewStatus({required this.highlighted});

  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SportikaSpacing.sm,
        vertical: SportikaSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: SportikaColors.gold.withValues(alpha: highlighted ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(SportikaRadius.pill),
      ),
      child: Text(
        highlighted ? 'REVIEW REQUIRED' : 'PENDING',
        style: SportikaType.micro.copyWith(
          color: SportikaColors.gold,
          fontWeight: SportikaFontWeight.bold,
        ),
      ),
    );
  }
}

// ============================================================
// PUBLISHED RESULT
// ============================================================

class _PublishedResultItem extends StatelessWidget {
  const _PublishedResultItem({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Reuse the existing official, sport-aware fixture tile.
        officialFixtureTile(context, fixture),

        const SizedBox(height: SportikaSpacing.xs),

        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => publishFixture(context, fixture),
            icon: const Icon(
              Icons.edit_note_rounded,
              size: 18,
              color: SportikaColors.gold,
            ),
            label: Text(
              'Publish correction',
              style: SportikaType.caption.copyWith(
                color: SportikaColors.gold,
                fontWeight: SportikaFontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
