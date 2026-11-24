import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/features/live/widgets/live_clock.dart';
import 'package:sportika/features/personal_games/screens/scorecard_screen.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/results_actions.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Premium official fixture detail screen.
///
/// UI-only redesign. Existing official scoring, publishing,
/// dispute, and tournament workflows remain unchanged.
class FixtureDetailScreen extends StatelessWidget {
  const FixtureDetailScreen({super.key, required this.fixtureId});

  final String fixtureId;

  @override
  Widget build(BuildContext context) {
    final fixtures = context.watch<FixturesController>();
    final fixture = fixtures.fixtureById(fixtureId);

    if (fixture == null) {
      return Scaffold(
        appBar: sportikaAppBar('Fixture'),
        body: const Padding(
          padding: EdgeInsets.all(SportikaSpacing.lg),
          child: EmptyState(
            title: 'Fixture not found',
            icon: Icons.search_off_rounded,
          ),
        ),
      );
    }

    final tournament = fixtures.tournamentOf(fixture);

    if (tournament == null) {
      return Scaffold(
        appBar: sportikaAppBar('Fixture'),
        body: const Padding(
          padding: EdgeInsets.all(SportikaSpacing.lg),
          child: EmptyState(
            title: 'Tournament unavailable',
            body: 'This fixture cannot be displayed until its tournament details are available.',
            icon: Icons.info_outline_rounded,
          ),
        ),
      );
    }

    final sport = tournament.sport;
    final progress = fixtures.progressOfFixture(fixture);
    final result = fixture.result;

    final sides = fixtures.sideLabelsOf(fixture);

    final sideA = sides.isNotEmpty ? sides[0] : 'Side A';
    final sideB = sides.length > 1 ? sides[1] : 'Side B';

    final session = context.watch<SessionController>();
    final tournaments = context.watch<TournamentsController>();
    final me = context.watch<ProfileController>().currentAccount;

    final isOrganizer = tournament.organizerId == me?.id;
    final isScorer = me != null && fixture.scorerAccountIds.contains(me.id);

    final canOrganize = session.canOrganize && isOrganizer;

    final isParticipant =
        me != null && _isParticipant(tournaments, fixture, me.id);

    final linkedMatch = context.watch<MatchController>().matchOfFixture(
      fixture.tournamentId,
      fixture.id,
    );

    final locked =
        fixture.status == FixtureStatus.published ||
        fixture.status == FixtureStatus.walkover;

    final isLive = fixture.status == FixtureStatus.live;

    // One door per sport: futsal, cricket and badminton are scored from their
    // Match Centers. The flags are computed once so the section header and its
    // buttons can never disagree.
    final futsalWorkspace =
        sport == Sport.futsal &&
        (linkedMatch != null ||
            (canOrganize && fixture.events.isEmpty && !locked));
    final cricketWorkspace =
        sport == Sport.cricket &&
        (linkedMatch != null ||
            (canOrganize && fixture.events.isEmpty && !locked));
    final badmintonWorkspace =
        sport == Sport.badminton &&
        (linkedMatch != null ||
            (canOrganize && fixture.events.isEmpty && !locked));
    // A cricket fixture that already carries events but was never linked to a
    // match was scored the old way. It keeps a labelled door so a fixture in
    // flight can be finished where it started.
    final legacyCricket =
        sport == Sport.cricket &&
        !locked &&
        linkedMatch == null &&
        fixture.events.isNotEmpty &&
        (isScorer || canOrganize);
    // The scorecard is badminton's offline/demo surface: it only opens when no
    // match backs the fixture, so there is never a second rule book for the
    // same match.
    final scorecardWorkspace =
        sport == Sport.badminton &&
        !locked &&
        linkedMatch == null &&
        (isScorer || canOrganize);

    final officialResult = locked && result != null;

    // The live event fold is authoritative for an in-progress display.
    // A result becomes official only when the fixture is published.
    final scores = isLive
        ? progress.scoreDisplay
        : result != null
        ? result.sideScores
        : progress.scoreDisplay;

    final scoreA = scores.isNotEmpty ? scores[0] : '';
    final scoreB = scores.length > 1 ? scores[1] : '';

    final winner = officialResult ? result.winnerIndex : null;

    final headline = officialResult ? result.headline : progress.headline;

    final scorerNames = fixture.scorerAccountIds
        .map((id) => session.accountById(id)?.displayName)
        .whereType<String>()
        .toList();

    return LiveClock(
      child: Scaffold(
        appBar: sportikaAppBar(
          tournament.name,
          subtitle: '${sport.label} · ${fixture.stage}',
          actions: [
            if (canOrganize)
              PopupMenuButton<String>(
                tooltip: 'Match management',
                icon: const Icon(Icons.more_vert_rounded),
                color: SportikaColors.surfaceElevated,
                onSelected: (value) async {
                  switch (value) {
                    case 'schedule':
                      await editFixtureSchedule(context, fixture);
                    case 'scorers':
                      await assignScorerSheet(context, fixture);
                    case 'walkover':
                      await recordWalkoverFor(context, fixture);
                    case 'dispute':
                      await raiseDisputeFor(context, fixture);
                  }
                },
                itemBuilder: (_) => [
                  if (!locked)
                    const PopupMenuItem(
                      value: 'schedule',
                      child: Text('Edit venue & time'),
                    ),
                  if (!locked)
                    const PopupMenuItem(
                      value: 'scorers',
                      child: Text('Assign scorers'),
                    ),
                  if (!locked)
                    const PopupMenuItem(
                      value: 'walkover',
                      child: Text('Record walkover'),
                    ),
                  const PopupMenuItem(
                    value: 'dispute',
                    child: Text('Raise a dispute'),
                  ),
                ],
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
            SportikaSpacing.md,
            SportikaSpacing.sm,
            SportikaSpacing.md,
            SportikaSpacing.xxl,
          ),
          children: [
            // ==========================================
            // OFFICIAL MATCH HERO
            // ==========================================

            _FixtureHero(
              sport: sport,
              stage: fixture.stage,
              status: fixture.status,
              sideA: sideA,
              sideB: sideB,
              scoreA: scoreA,
              scoreB: scoreB,
              winner: winner,
              headline: headline,
              startedAt: fixture.startedAt,
              isLive: isLive,
            ),

            const SizedBox(height: SportikaSpacing.md),

            // ==========================================
            // MATCH INFORMATION
            // ==========================================
            _MatchInformation(
              scheduledAt: fixture.scheduledAt,
              venue: fixture.venue,
              rules: tournament.matchRules,
              scorerNames: scorerNames,
              eventCount: fixture.events.length,
            ),

            // ==========================================
            // DISPUTE STATUS
            // ==========================================
            if (fixture.disputeNote != null) ...[
              const SizedBox(height: SportikaSpacing.md),
              _DisputeCard(fixture: fixture, canResolve: canOrganize),
            ],

            // ==========================================
            // MATCH WORKSPACE
            // ==========================================
            // One door per sport. Futsal, cricket and badminton are scored from
            // their Match Centers, so the legacy scorecard button is not offered
            // while a match backs the fixture: two ways in meant two different
            // rule books for the same match. The badminton scorecard survives as
            // the offline/demo door for a fixture with no match, and a cricket
            // fixture that already carries events keeps a clearly labelled legacy
            // door so nothing in flight is stranded.
            if (futsalWorkspace ||
                cricketWorkspace ||
                badmintonWorkspace ||
                scorecardWorkspace ||
                legacyCricket) ...[
              const SectionTitle('Match workspace'),

              if (futsalWorkspace)
                PrimaryButton(
                  label: linkedMatch == null
                      ? 'Set up Futsal Match Center'
                      : 'Open Futsal Match Center',
                  icon: Icons.sports_soccer_rounded,
                  onPressed: () => linkedMatch == null
                      ? pushRoute(
                          context,
                          AppRoute.createMatch,
                          args: CreateMatchArgs(
                            tournamentId: fixture.tournamentId,
                            fixtureId: fixture.id,
                          ),
                        )
                      : pushRoute(
                          context,
                          AppRoute.matchDetail,
                          args: MatchArgs(linkedMatch.id),
                        ),
                ),

              if (cricketWorkspace) ...[
                if (futsalWorkspace) const SizedBox(height: SportikaSpacing.sm),
                PrimaryButton(
                  label: linkedMatch == null
                      ? 'Set up Cricket Match Center'
                      : 'Open Cricket Match Center',
                  icon: Icons.sports_cricket,
                  tone: sportColor(sport),
                  onPressed: () => linkedMatch == null
                      ? pushRoute(
                          context,
                          AppRoute.createMatch,
                          args: CreateMatchArgs(
                            tournamentId: fixture.tournamentId,
                            fixtureId: fixture.id,
                          ),
                        )
                      : pushRoute(
                          context,
                          AppRoute.matchDetail,
                          args: MatchArgs(linkedMatch.id),
                        ),
                ),
              ],

              if (legacyCricket) ...[
                const SizedBox(height: SportikaSpacing.sm),
                GhostButton(
                  label: 'Open legacy scorecard',
                  icon: Icons.sports_score_rounded,
                  expand: true,
                  onPressed: () => pushRoute(
                    context,
                    AppRoute.scorecard,
                    args: ScorecardArgs(fixture.id, ScorecardMode.official),
                  ),
                ),
                const SizedBox(height: SportikaSpacing.xs),
                const Text(
                  'This fixture was scored before the Cricket Match Center '
                  'existed. Finish it here; new fixtures are set up from the '
                  'Match Center.',
                  style: SportikaType.caption,
                ),
              ],

              if (badmintonWorkspace) ...[
                if (futsalWorkspace || cricketWorkspace)
                  const SizedBox(height: SportikaSpacing.sm),
                PrimaryButton(
                  label: linkedMatch == null
                      ? 'Set up Badminton Match Center'
                      : 'Open Badminton Match Center',
                  icon: Icons.sports_tennis,
                  tone: sportColor(sport),
                  onPressed: () => linkedMatch == null
                      ? pushRoute(
                          context,
                          AppRoute.createMatch,
                          args: CreateMatchArgs(
                            tournamentId: fixture.tournamentId,
                            fixtureId: fixture.id,
                          ),
                        )
                      : pushRoute(
                          context,
                          AppRoute.matchDetail,
                          args: MatchArgs(linkedMatch.id),
                        ),
                ),
              ],

              if (scorecardWorkspace) ...[
                const SizedBox(height: SportikaSpacing.sm),
                PrimaryButton(
                  label: !isScorer
                      ? 'View scorecard'
                      : fixture.events.isEmpty
                      ? 'Start scoring'
                      : 'Open scorecard',
                  icon: Icons.sports_score_rounded,
                  tone: sportColor(sport),
                  onPressed: () => pushRoute(
                    context,
                    AppRoute.scorecard,
                    args: ScorecardArgs(fixture.id, ScorecardMode.official),
                  ),
                ),
                const SizedBox(height: SportikaSpacing.xs),
                const Text(
                  'This fixture has no match behind it yet. The organizer sets up '
                  'the Badminton Match Center, which is where an official match '
                  'is scored.',
                  style: SportikaType.caption,
                ),
              ],
            ],

            // A fixture nobody may set up yet: say who does it instead of
            // leaving the section silently absent.
            if ((sport == Sport.cricket || sport == Sport.badminton) &&
                linkedMatch == null &&
                !canOrganize &&
                !legacyCricket &&
                !scorecardWorkspace) ...[
              const SectionTitle('Match workspace'),
              InfoBanner(
                icon: Icons.info_outline,
                text: sport == Sport.cricket
                    ? 'The organizer sets up the Cricket Match Center. You score '
                          'it once the match exists.'
                    : 'The organizer sets up the Badminton Match Center. You '
                          'score it once the match exists.',
              ),
            ],

            // ==========================================
            // ORGANIZER MANAGEMENT
            // ==========================================
            if (canOrganize && !locked) ...[
              const SectionTitle('Match management'),

              if (!isScorer)
                InfoBanner(
                  icon: Icons.person_add_alt_rounded,
                  text: scorerNames.isEmpty
                      ? 'No scorer assigned. Assign yourself or another user before scoring begins.'
                      : 'You are not assigned as a scorer. Assign yourself to take over official scoring.',
                ),

              if (fixture.status == FixtureStatus.submitted ||
                  fixture.result != null ||
                  fixture.events.isNotEmpty) ...[
                const SizedBox(height: SportikaSpacing.sm),
                PrimaryButton(
                  label: fixture.result == null
                      ? 'Review & publish'
                      : 'Publish correction',
                  icon: Icons.verified_outlined,
                  tone: SportikaColors.mint,
                  onPressed: () => publishFixture(context, fixture),
                ),
              ],

              const SizedBox(height: SportikaSpacing.sm),

              Row(
                children: [
                  Expanded(
                    child: GhostButton(
                      label: 'Scorers',
                      icon: Icons.group_add_outlined,
                      expand: true,
                      onPressed: () => assignScorerSheet(context, fixture),
                    ),
                  ),
                  const SizedBox(width: SportikaSpacing.sm),
                  Expanded(
                    child: GhostButton(
                      label: 'Walkover',
                      icon: Icons.flag_outlined,
                      expand: true,
                      onPressed: () => recordWalkoverFor(context, fixture),
                    ),
                  ),
                ],
              ),
            ],

            if (locked && isParticipant) ...[
              const SizedBox(height: SportikaSpacing.md),
              GhostButton(
                label: 'Dispute this result',
                icon: Icons.gavel_rounded,
                tone: SportikaColors.danger,
                expand: true,
                onPressed: () => raiseDisputeFor(context, fixture),
              ),
            ],

            // ==========================================
            // OFFICIAL RESULT
            // ==========================================
            if (officialResult) ...[
              const SectionTitle('Official result'),
              _OfficialResultCard(
                result: result,
                publisherName:
                    session.accountById(result.publishedById)?.displayName ??
                    'Organizer',
              ),
            ],

            // ==========================================
            // CORRECTION AUDIT
            // ==========================================
            if (fixture.corrections.isNotEmpty) ...[
              const SectionTitle('Correction history'),

              for (final correction in fixture.corrections.reversed)
                Padding(
                  padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
                  child: SurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.history_rounded,
                              color: SportikaColors.gold,
                              size: SportikaIconSize.md,
                            ),
                            const SizedBox(width: SportikaSpacing.sm),
                            Expanded(
                              child: Text(
                                correction.reason,
                                style: SportikaType.bodyStrong,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: SportikaSpacing.sm),
                        Text(
                          '${correction.previous.headline} → ${correction.current.headline}',
                          style: SportikaType.caption,
                        ),
                        const SizedBox(height: SportikaSpacing.xs),
                        Text(
                          '${timeAgo(correction.at)} · '
                          '${session.accountById(correction.byAccountId)?.displayName ?? 'Organizer'}',
                          style: SportikaType.micro,
                        ),
                      ],
                    ),
                  ),
                ),
            ],

            // ==========================================
            // TEAM ROSTERS
            // ==========================================
            const SectionTitle('Team rosters'),

            _Roster(
              fixture: fixture,
              sides: [sideA, sideB],
              tournaments: tournaments,
              session: session,
            ),

            const SizedBox(height: SportikaSpacing.lg),

            GhostButton(
              label: 'Open ${tournament.name}',
              icon: Icons.emoji_events_outlined,
              expand: true,
              onPressed: () => pushRoute(
                context,
                AppRoute.tournamentDetail,
                args: TournamentDetailArgs(tournament.id),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _isParticipant(
    TournamentsController tournaments,
    Fixture fixture,
    String accountId,
  ) {
    final home = tournaments.entriesById[fixture.home.entryId];
    final away = tournaments.entriesById[fixture.away.entryId];

    return (home?.memberAccountIds.contains(accountId) ?? false) ||
        (away?.memberAccountIds.contains(accountId) ?? false);
  }
}

// ============================================================
// BROADCAST SCOREBOARD HERO
// ============================================================

class _FixtureHero extends StatelessWidget {
  const _FixtureHero({
    required this.sport,
    required this.stage,
    required this.status,
    required this.sideA,
    required this.sideB,
    required this.scoreA,
    required this.scoreB,
    required this.winner,
    required this.headline,
    required this.startedAt,
    required this.isLive,
  });

  final Sport sport;
  final String stage;
  final FixtureStatus status;
  final String sideA;
  final String sideB;
  final String scoreA;
  final String scoreB;
  final int? winner;
  final String headline;
  final DateTime? startedAt;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return SurfaceCard(
      borderColor: isLive
          ? theme.live.withValues(alpha: SportikaOpacity.medium)
          : theme.borderSubtle,
      child: Column(
        children: [
          Row(
            children: [
              SportTag(sport),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: Text(
                  stage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.micro,
                ),
              ),
              StatusPill(
                status == FixtureStatus.submitted ? 'In review' : status.label,
                color: statusColor(status.key),
                icon: statusIcon(status.key),
              ),
            ],
          ),

          const SizedBox(height: SportikaSpacing.lg),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _HeroSide(
                  label: sideA,
                  score: scoreA,
                  isWinner: winner == 0,
                  tone: sportColor(sport),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SportikaSpacing.sm,
                ),
                child: Column(
                  children: [
                    if (isLive && startedAt != null)
                      LiveElapsed(
                        since: startedAt!,
                        style: LiveElapsedStyle.badge,
                      )
                    else
                      Text(
                        'VS',
                        style: SportikaType.bodyStrong.copyWith(
                          color: theme.textMuted,
                        ),
                      ),
                  ],
                ),
              ),

              Expanded(
                child: _HeroSide(
                  label: sideB,
                  score: scoreB,
                  isWinner: winner == 1,
                  tone: SportikaColors.mint,
                ),
              ),
            ],
          ),

          if (headline.trim().isNotEmpty) ...[
            const SizedBox(height: SportikaSpacing.lg),
            Divider(color: theme.borderSubtle, height: SportikaBorder.hairline),
            const SizedBox(height: SportikaSpacing.sm),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: SportikaType.bodyStrong.copyWith(
                color: winner != null ? theme.live : theme.textBody,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroSide extends StatelessWidget {
  const _HeroSide({
    required this.label,
    required this.score,
    required this.isWinner,
    required this.tone,
  });

  final String label;
  final String score;
  final bool isWinner;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.surfaceSunken,
            borderRadius: BorderRadius.circular(SportikaRadius.control),
            border: Border.all(color: isWinner ? tone : theme.borderSubtle),
          ),
          child: SizedBox.square(
            dimension: SportikaSpacing.xxl,
            child: Icon(
              Icons.shield_outlined,
              color: isWinner ? tone : theme.textMuted,
              size: SportikaIconSize.lg,
            ),
          ),
        ),

        const SizedBox(height: SportikaSpacing.sm),

        Text(
          label,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: SportikaType.bodyStrong.copyWith(
            color: isWinner ? theme.textPrimary : theme.textBody,
          ),
        ),

        const SizedBox(height: SportikaSpacing.sm),

        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            score.trim().isEmpty ? '-' : score,
            maxLines: 1,
            style: SportikaType.scoreSmall.copyWith(
              color: isWinner ? tone : theme.textBody,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// MATCH INFORMATION
// ============================================================

class _MatchInformation extends StatelessWidget {
  const _MatchInformation({
    required this.scheduledAt,
    required this.venue,
    required this.rules,
    required this.scorerNames,
    required this.eventCount,
  });

  final DateTime scheduledAt;
  final String venue;
  final String rules;
  final List<String> scorerNames;
  final int eventCount;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        children: [
          KeyValueRow(
            'Scheduled',
            '${dateShort(scheduledAt)} · ${timeLabel(scheduledAt)}',
          ),
          KeyValueRow('Venue', venue.trim().isEmpty ? 'Not specified' : venue),
          KeyValueRow('Rules', rules),
          KeyValueRow(
            'Scorers',
            scorerNames.isEmpty ? 'Not assigned' : scorerNames.join(', '),
          ),
          KeyValueRow('Scoring events', '$eventCount'),
        ],
      ),
    );
  }
}

// ============================================================
// OFFICIAL RESULT
// ============================================================

class _OfficialResultCard extends StatelessWidget {
  const _OfficialResultCard({
    required this.result,
    required this.publisherName,
  });

  final dynamic result;
  final String publisherName;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return SurfaceCard(
      borderColor: theme.live.withValues(alpha: SportikaOpacity.medium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.walkover ? Icons.flag_outlined : Icons.verified_rounded,
                color: theme.live,
                size: SportikaIconSize.lg,
              ),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: Text(
                  result.headline,
                  style: SportikaType.bodyStrong.copyWith(color: theme.live),
                ),
              ),
            ],
          ),
          if (result.detail.isNotEmpty) ...[
            const SizedBox(height: SportikaSpacing.sm),
            Text(result.detail, style: SportikaType.caption),
          ],
          const SizedBox(height: SportikaSpacing.sm),
          KeyValueRow(
            'Published',
            '${timeAgo(result.publishedAt)} by $publisherName',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DISPUTE
// ============================================================

class _DisputeCard extends StatelessWidget {
  const _DisputeCard({required this.fixture, required this.canResolve});

  final Fixture fixture;
  final bool canResolve;

  @override
  Widget build(BuildContext context) {
    final resolved = fixture.disputeResolved;

    final tone = resolved ? SportikaColors.textMuted : SportikaColors.danger;

    return SurfaceCard(
      borderColor: tone.withValues(alpha: SportikaOpacity.medium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                resolved
                    ? Icons.check_circle_outline_rounded
                    : Icons.gavel_rounded,
                color: tone,
                size: SportikaIconSize.md,
              ),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: Text(
                  resolved ? 'Dispute closed' : 'Disputed result',
                  style: SportikaType.bodyStrong.copyWith(color: tone),
                ),
              ),
              StatusPill(resolved ? 'Resolved' : 'Open', color: tone),
            ],
          ),

          const SizedBox(height: SportikaSpacing.sm),

          Text(fixture.disputeNote ?? '', style: SportikaType.caption),

          const SizedBox(height: SportikaSpacing.xs),

          Text(
            'Raised by ${context.read<SessionController>().accountById(fixture.disputeRaisedBy)?.displayName ?? 'Player'}',
            style: SportikaType.micro,
          ),

          if (canResolve && !resolved) ...[
            const SizedBox(height: SportikaSpacing.md),
            GhostButton(
              label: 'Review dispute',
              icon: Icons.fact_check_outlined,
              expand: true,
              onPressed: () => resolveDisputeFor(context, fixture),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// ROSTER
// ============================================================

class _Roster extends StatelessWidget {
  const _Roster({
    required this.fixture,
    required this.sides,
    required this.tournaments,
    required this.session,
  });

  final Fixture fixture;
  final List<String> sides;
  final TournamentsController tournaments;
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final home = tournaments.entriesById[fixture.home.entryId];
    final away = tournaments.entriesById[fixture.away.entryId];

    if (home == null && away == null) {
      return const EmptyState(
        title: 'Sides not decided',
        body: 'Knockout participants appear once the feeder fixture result is published.',
        icon: Icons.help_outline_rounded,
      );
    }

    return Column(
      children: [
        _EntryRoster(label: sides[0], entry: home, session: session),
        const SizedBox(height: SportikaSpacing.sm),
        _EntryRoster(label: sides[1], entry: away, session: session),
      ],
    );
  }
}

class _EntryRoster extends StatelessWidget {
  const _EntryRoster({
    required this.label,
    required this.entry,
    required this.session,
  });

  final String label;
  final Entry? entry;
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: SportikaType.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (entry != null)
                StatusPill(
                  entry!.status.label,
                  color: statusColor(entry!.status.key),
                ),
            ],
          ),

          if (entry != null) ...[
            const SizedBox(height: SportikaSpacing.md),

            Wrap(
              spacing: SportikaSpacing.sm,
              runSpacing: SportikaSpacing.sm,
              children: [
                for (final memberId in entry!.memberAccountIds)
                  _MemberChip(accountId: memberId, session: session),
              ],
            ),
          ] else ...[
            const SizedBox(height: SportikaSpacing.sm),
            const Text('Awaiting qualification', style: SportikaType.caption),
          ],
        ],
      ),
    );
  }
}

class _MemberChip extends StatelessWidget {
  const _MemberChip({required this.accountId, required this.session});

  final String accountId;
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final account = session.accountById(accountId);
    final name = account?.displayName ?? 'Player';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (account != null)
          AccountAvatar(account: account, size: SportikaSpacing.xl)
        else
          PlayerAvatar(initials: initialsOf(name), size: SportikaSpacing.xl),
        const SizedBox(width: SportikaSpacing.xs),
        Text(name, style: SportikaType.caption),
      ],
    );
  }
}
