import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/features/matches/widgets/match_vs_card.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/live/widgets/live_clock.dart';
import 'package:sportika/features/personal_games/screens/scorecard_screen.dart';

/// Official scoring workspace.
///
/// Shows tournament fixtures assigned to the current scorer and
/// standalone official matches assigned through MatchController.
///
/// All scoring and submission behavior remains in existing routes.
class ScorerWorkspaceScreen extends StatelessWidget {
  const ScorerWorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fixtures = context.watch<FixturesController>();
    final session = context.watch<SessionController>();
    final matches = context.watch<MatchController>();

    if (!session.ready) {
      return const ScreenScaffold(
        title: 'Scorer workspace',
        child: LoadingSkeleton(rows: 3, label: 'Loading assigned fixtures'),
      );
    }

    final assigned = fixtures.myScoringFixtures;

    final live = assigned.where((f) => f.status == FixtureStatus.live).toList();

    final upcoming =
        assigned.where((f) => f.status == FixtureStatus.upcoming).toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    final submitted = assigned
        .where((f) => f.status == FixtureStatus.submitted)
        .toList();

    final officialMatches = matches.myScoringMatches;

    final actionableCount = live.length + upcoming.length;

    final width = MediaQuery.sizeOf(context).width;
    final inset = width > sportikaMaxContentWidth
        ? (width - sportikaMaxContentWidth) / 2 + SportikaSpacing.md
        : SportikaSpacing.md;

    return LiveClock(
      child: Scaffold(
        appBar: sportikaAppBar(
          'Scorer workspace',
          subtitle: '${assigned.length + officialMatches.length} assignments',
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
              // ==========================================
              // BRANDED HEADER
              // ==========================================

              const _ScorerHeader(),

              const SizedBox(height: SportikaSpacing.md),

              // ==========================================
              // SCORING METRICS
              // ==========================================
              Row(
                children: [
                  Expanded(
                    child: _ScorerMetric(
                      icon: Icons.assignment_outlined,
                      label: 'To score',
                      value: actionableCount,
                      tone: SportikaColors.blueBright,
                    ),
                  ),
                  const SizedBox(width: SportikaSpacing.sm),
                  Expanded(
                    child: _ScorerMetric(
                      icon: Icons.radio_button_checked,
                      label: 'Live now',
                      value: live.length,
                      tone: SportikaColors.mint,
                    ),
                  ),
                  const SizedBox(width: SportikaSpacing.sm),
                  Expanded(
                    child: _ScorerMetric(
                      icon: Icons.pending_actions_outlined,
                      label: 'In review',
                      value: submitted.length,
                      tone: SportikaColors.gold,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: SportikaSpacing.md),

              // ==========================================
              // SCORING INFORMATION
              // ==========================================
              const InfoBanner(
                icon: Icons.verified_user_outlined,
                tone: SportikaColors.blueBright,
                text:
                    'Your scoring log is saved after every entry. '
                    'If an organizer reassigns a fixture, the '
                    'recorded score stays with that fixture.',
              ),

              // ==========================================
              // LIVE SCORING
              // ==========================================
              if (live.isNotEmpty) ...[
                SectionTitle('Live scoring (${live.length})'),
                for (final fixture in live)
                  Padding(
                    padding: const EdgeInsets.only(bottom: SportikaSpacing.md),
                    child: _ScorerFixtureCard(fixture: fixture, featured: true),
                  ),
              ],

              // ==========================================
              // UPCOMING ASSIGNMENTS
              // ==========================================
              SectionTitle('Upcoming assignments (${upcoming.length})'),

              if (upcoming.isEmpty)
                const _ScorerEmptyCard(
                  icon: Icons.event_available_outlined,
                  title: 'No upcoming fixtures',
                  body: 'New tournament scoring assignments will appear here.',
                )
              else
                for (final fixture in upcoming)
                  Padding(
                    padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
                    child: _ScorerFixtureCard(fixture: fixture),
                  ),

              // ==========================================
              // SUBMITTED RESULTS
              // ==========================================
              if (submitted.isNotEmpty) ...[
                SectionTitle('Submitted for review (${submitted.length})'),
                for (final fixture in submitted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
                    child: _ScorerFixtureCard(fixture: fixture),
                  ),
              ],

              // ==========================================
              // STANDALONE MATCHES
              // ==========================================
              const _OfficialMatchesSection(),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// BRANDED SCORER HEADER
// ============================================================

class _ScorerHeader extends StatelessWidget {
  const _ScorerHeader();

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
              Icons.sports_score_rounded,
              color: SportikaColors.blueBright,
              size: 28,
            ),
          ),
          const SizedBox(width: SportikaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SPORTIKA OFFICIALS',
                  style: SportikaType.micro.copyWith(
                    color: SportikaColors.mint,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: SportikaSpacing.xs),
                const Text(
                  'Your scoring command center',
                  style: SportikaType.bodyStrong,
                ),
                const SizedBox(height: SportikaSpacing.xs),
                const Text(
                  'Manage assignments, track live scores and review submitted results.',
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
// SCORING METRIC
// ============================================================

class _ScorerMetric extends StatelessWidget {
  const _ScorerMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(SportikaSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tone, size: 20),
          const SizedBox(height: SportikaSpacing.sm),
          Text('$value', style: SportikaType.display(25)),
          const SizedBox(height: SportikaSpacing.xs),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SportikaType.micro,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// EMPTY STATE
// ============================================================

class _ScorerEmptyCard extends StatelessWidget {
  const _ScorerEmptyCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        children: [
          Icon(icon, color: SportikaColors.textMuted, size: 30),
          const SizedBox(height: SportikaSpacing.sm),
          Text(title, style: SportikaType.bodyStrong),
          const SizedBox(height: SportikaSpacing.xs),
          Text(body, textAlign: TextAlign.center, style: SportikaType.caption),
        ],
      ),
    );
  }
}

// ============================================================
// TOURNAMENT FIXTURE CARD
// ============================================================

class _ScorerFixtureCard extends StatelessWidget {
  const _ScorerFixtureCard({required this.fixture, this.featured = false});

  final Fixture fixture;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FixturesController>();

    final tournament = controller.tournamentOf(fixture);
    final sport = tournament?.sport;
    final sides = controller.sideLabelsOf(fixture);
    final progress = controller.progressOfFixture(fixture);

    final live = fixture.status == FixtureStatus.live;
    final submitted = fixture.status == FixtureStatus.submitted;

    final notStarted =
        fixture.status == FixtureStatus.upcoming && fixture.events.isEmpty;

    final firstSide = sides.isNotEmpty ? sides[0] : 'Side A';

    final secondSide = sides.length > 1 ? sides[1] : 'Side B';

    final scores = progress.scoreDisplay;

    final firstScore = scores.isNotEmpty ? scores[0] : '';

    final secondScore = scores.length > 1 ? scores[1] : '';

    final actionLabel = submitted
        ? 'View submitted'
        : notStarted
        ? 'Start scoring'
        : live
        ? 'Resume scoring'
        : 'Open scorecard';

    return SurfaceCard(
      borderColor: featured
          ? SportikaColors.mint.withValues(alpha: 0.5)
          : SportikaColors.border,
      padding: const EdgeInsets.all(SportikaSpacing.md),
      onTap: () => _openScorecard(context, firstSide, secondSide),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER
          Row(
            children: [
              if (sport != null) ...[
                SportTag(sport, compact: true),
                const SizedBox(width: SportikaSpacing.sm),
              ],
              Expanded(
                child: Text(
                  '${tournament?.name ?? 'Tournament fixture'} · ${fixture.stage}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.caption,
                ),
              ),
              StatusPill(
                fixture.status.label,
                color: statusColor(fixture.status.key),
                icon: statusIcon(fixture.status.key),
              ),
            ],
          ),

          const SizedBox(height: SportikaSpacing.md),

          // SCOREBOARD
          _FixtureScoreRow(
            name: firstSide,
            score: firstScore,
            featured: featured,
          ),

          const SizedBox(height: SportikaSpacing.sm),

          _FixtureScoreRow(
            name: secondSide,
            score: secondScore,
            featured: featured,
          ),

          if (progress.headline.isNotEmpty) ...[
            const SizedBox(height: SportikaSpacing.sm),
            Text(
              progress.headline,
              style: SportikaType.caption.copyWith(
                color: SportikaColors.textBody,
              ),
            ),
          ],

          const SizedBox(height: SportikaSpacing.md),

          const Divider(height: 1, color: SportikaColors.border),

          const SizedBox(height: SportikaSpacing.sm),

          // METADATA
          Row(
            children: [
              if (live && fixture.startedAt != null)
                LiveElapsed(since: fixture.startedAt!)
              else ...[
                const Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: SportikaColors.textDim,
                ),
                const SizedBox(width: SportikaSpacing.xs),
                Text(
                  dateShort(fixture.scheduledAt),
                  style: SportikaType.caption,
                ),
              ],
              const SizedBox(width: SportikaSpacing.sm),
              Text(
                '${fixture.events.length} entries',
                style: SportikaType.micro,
              ),
            ],
          ),

          const SizedBox(height: SportikaSpacing.md),

          // PRIMARY ACTION
          if (featured)
            PrimaryButton(
              label: actionLabel,
              icon: Icons.play_arrow_rounded,
              tone: SportikaColors.mint,
              onPressed: () => _openScorecard(context, firstSide, secondSide),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    submitted
                        ? 'Awaiting organizer publication'
                        : 'Official scoring assignment',
                    style: SportikaType.caption,
                  ),
                ),
                Text(
                  actionLabel,
                  style: SportikaType.caption.copyWith(
                    color: submitted
                        ? SportikaColors.gold
                        : SportikaColors.blueBright,
                    fontWeight: SportikaFontWeight.bold,
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: SportikaColors.blueBright,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _openScorecard(
    BuildContext context,
    String firstSide,
    String secondSide,
  ) async {
    if (fixture.status == FixtureStatus.live && fixture.events.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Resume scoring?'),
          content: Text(
            '${fixture.events.length} entries have already '
            'been recorded for $firstSide vs $secondSide. '
            'You will return to the existing scorecard.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Resume'),
            ),
          ],
        ),
      );

      if (proceed != true || !context.mounted) return;
    }

    await pushRoute(
      context,
      AppRoute.scorecard,
      args: ScorecardArgs(fixture.id, ScorecardMode.official),
    );
  }
}

// ============================================================
// FIXTURE SCORE ROW
// ============================================================

class _FixtureScoreRow extends StatelessWidget {
  const _FixtureScoreRow({
    required this.name,
    required this.score,
    required this.featured,
  });

  final String name;
  final String score;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SportikaType.bodyStrong,
          ),
        ),
        if (score.isNotEmpty)
          Text(
            score,
            style: featured
                ? SportikaType.scoreSmall
                : SportikaType.bodyStrong.copyWith(
                    color: SportikaColors.blueBright,
                  ),
          ),
      ],
    );
  }
}

// ============================================================
// STANDALONE OFFICIAL MATCHES
// ============================================================

class _OfficialMatchesSection extends StatelessWidget {
  const _OfficialMatchesSection();

  @override
  Widget build(BuildContext context) {
    final matches = context.watch<MatchController>().myScoringMatches;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('Official matches (${matches.length})'),

        if (matches.isEmpty)
          const _ScorerEmptyCard(
            icon: Icons.sports_score_outlined,
            title: 'No standalone matches',
            body: 'Official standalone match assignments will appear here.',
          )
        else
          for (final match in matches)
            Padding(
              padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
              child: _ScorerMatchCard(match: match),
            ),
      ],
    );
  }
}

// ============================================================
// STANDALONE MATCH CARD
// ============================================================

class _ScorerMatchCard extends StatelessWidget {
  const _ScorerMatchCard({required this.match});

  final SportMatch match;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MatchController>();
    final progress = controller.progressOf(match);

    final openScoring = match.status == FixtureStatus.live;

    return SurfaceCard(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      onTap: () =>
          pushRoute(context, AppRoute.matchDetail, args: MatchArgs(match.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MatchVsCard(
            match: match,
            progress: progress,
            showScore: match.status != FixtureStatus.upcoming,
            dense: true,
          ),

          const SizedBox(height: SportikaSpacing.sm),

          Row(
            children: [
              StatusPill(
                match.status.label,
                color: statusColor(match.status.key),
                icon: statusIcon(match.status.key),
              ),

              const Spacer(),

              if (openScoring)
                GhostButton(
                  label: 'Open scoring',
                  icon: Icons.scoreboard_outlined,
                  onPressed: () => pushRoute(
                    context,
                    AppRoute.matchScoring,
                    args: MatchArgs(match.id),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
