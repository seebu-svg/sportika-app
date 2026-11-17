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

/// Scorer home (spec §4.4): every fixture assigned to the account, with a
/// single tap back into the live scorecard.
class ScorerWorkspaceScreen extends StatelessWidget {
  const ScorerWorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FixturesController>();
    final session = context.watch<SessionController>();

    if (!session.ready) {
      return const ScreenScaffold(
        title: 'Scorer workspace',
        child: LoadingSkeleton(rows: 3, label: 'Loading assigned fixtures'),
      );
    }
    final assigned = state.myScoringFixtures;
    final inPlay = assigned
        .where((f) => f.status != FixtureStatus.submitted)
        .toList();
    final awaiting = assigned
        .where((f) => f.status == FixtureStatus.submitted)
        .toList();

    return LiveClock(
      child: Scaffold(
        appBar: sportikaAppBar(
          'Scorer workspace',
          subtitle: '${assigned.length} fixtures assigned',
        ),
        body: RefreshIndicator(
          onRefresh: state.reload,
          color: SportikaColors.mint,
          backgroundColor: SportikaColors.surface,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
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
              const _OfficialMatchesSection(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Official matches where this account is the assigned scorer. A one-off
/// match has no tournament, so it never shows up in the fixture list above and
/// needs its own way in.
class _OfficialMatchesSection extends StatelessWidget {
  const _OfficialMatchesSection();

  @override
  Widget build(BuildContext context) {
    final matches = context.watch<MatchController>().myScoringMatches;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('Official matches you are scoring (${matches.length})'),
        if (matches.isEmpty)
          const EmptyState(
            title: 'No official matches yet',
            body:
                'An organizer can assign you as the official scorer of a '
                'standalone match. It appears here the moment it is assigned.',
            icon: Icons.sports_cricket,
          )
        else
          for (final match in matches)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ScorerMatchCard(match: match),
            ),
      ],
    );
  }
}

class _ScorerMatchCard extends StatelessWidget {
  const _ScorerMatchCard({required this.match});

  final SportMatch match;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MatchController>();
    final progress = controller.progressOf(match);
    final openScoring = match.status == FixtureStatus.live;
    return SurfaceCard(
      padding: const EdgeInsets.all(12),
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
          const SizedBox(height: 8),
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
    final live = fixture.status == FixtureStatus.live;

    return SurfaceCard(
      onTap: () => _openScorecard(context, sides),
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
              // A live card counts up from the first entry instead of showing
              // the kick-off date, so the row keeps the same width.
              if (live && fixture.startedAt != null)
                LiveElapsed(since: fixture.startedAt!)
              else ...[
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
              ],
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

  /// Resuming a card that already has entries is the one tap on this screen
  /// that can add a stray event, so the count is shown before opening it.
  Future<void> _openScorecard(BuildContext context, List<String> sides) async {
    if (fixture.status == FixtureStatus.live && fixture.events.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Resume this scorecard?'),
          content: Text(
            '${fixture.events.length} entries are already recorded for '
            '${sides[0]} vs ${sides[1]}. The card opens where you left it.',
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
      if (proceed != true) return;
      if (!context.mounted) return;
    }
    await pushRoute(
      context,
      AppRoute.scorecard,
      args: ScorecardArgs(fixture.id, ScorecardMode.official),
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
