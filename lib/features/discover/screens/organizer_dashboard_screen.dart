import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/features/discover/widgets/tournament_card.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/fixture_tile.dart';
import 'package:sportika/shared/widgets/results_actions.dart';
import 'package:sportika/shared/widgets/widgets.dart';

// ============================================================
// ORGANIZER COMMAND CENTER
// ============================================================

class OrganizerDashboardScreen extends StatelessWidget {
  const OrganizerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tournaments = context.watch<TournamentsController>();
    final fixtures = context.watch<FixturesController>();
    final profile = context.watch<ProfileController>();

    final mine = tournaments.tournamentsForOrganizer(
      profile.currentAccount?.id,
    );

    final pending = <Entry>[
      for (final tournament in mine)
        ...tournaments.pendingEntriesFor(tournament.id),
    ];

    final review = fixtures.fixturesAwaitingReview;
    final disputes = fixtures.myOrganizerDisputes;
    final live = fixtures.myOrganizerFixtures
        .where((fixture) => fixture.status == FixtureStatus.live)
        .toList();

    final attentionCount = pending.length + review.length + disputes.length;

    return Scaffold(
      appBar: sportikaAppBar(
        'Organizer',
        subtitle: 'Tournament command center',
        actions: [
          IconButton(
            tooltip: 'Create tournament',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => pushRoute(context, AppRoute.createTournament),
          ),
          const SizedBox(width: SportikaSpacing.sm),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          SportikaSpacing.lg,
          SportikaSpacing.sm,
          SportikaSpacing.lg,
          SportikaSpacing.xxl,
        ),
        children: [
          // --------------------------------------------------
          // BRANDED HERO
          // --------------------------------------------------

          _OrganizerHero(
            eventCount: mine.length,
            onCreate: () => pushRoute(context, AppRoute.createTournament),
          ),

          const SizedBox(height: SportikaSpacing.lg),

          // --------------------------------------------------
          // OPERATIONAL KPIS
          // --------------------------------------------------
          Row(
            children: [
              Expanded(
                child: _OrganizerMetric(
                  value: '${pending.length}',
                  label: 'Entries',
                  icon: Icons.group_add_outlined,
                  tone: SportikaColors.gold,
                ),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: _OrganizerMetric(
                  value: '${review.length}',
                  label: 'To review',
                  icon: Icons.fact_check_outlined,
                  tone: SportikaColors.mint,
                ),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: _OrganizerMetric(
                  value: '${live.length}',
                  label: 'Live',
                  icon: Icons.sensors_outlined,
                  tone: SportikaColors.blueBright,
                ),
              ),
            ],
          ),

          const SizedBox(height: SportikaSpacing.xl),

          // --------------------------------------------------
          // ACTION REQUIRED
          // --------------------------------------------------
          _OrganizerSectionHeader(
            title: 'Needs attention',
            subtitle: attentionCount == 0
                ? 'Everything is up to date'
                : '$attentionCount items need your attention',
            icon: Icons.assignment_turned_in_outlined,
          ),

          const SizedBox(height: SportikaSpacing.md),

          if (attentionCount == 0)
            const _OrganizerCompactEmpty(
              icon: Icons.check_circle_outline,
              title: 'All caught up',
              description:
                  'New registrations, results and disputes will appear here.',
            )
          else ...[
            // Disputes first because they require resolution.
            for (final fixture in disputes) ...[
              _OrganizerDisputeCard(fixture: fixture),
              const SizedBox(height: SportikaSpacing.sm),
            ],

            for (final entry in pending) ...[
              _PendingEntryCard(entry: entry),
              const SizedBox(height: SportikaSpacing.sm),
            ],

            for (final fixture in review) ...[
              _OrganizerReviewCard(fixture: fixture),
              const SizedBox(height: SportikaSpacing.sm),
            ],
          ],

          const SizedBox(height: SportikaSpacing.xl),

          // --------------------------------------------------
          // TOURNAMENTS
          // --------------------------------------------------
          _OrganizerSectionHeader(
            title: 'Your tournaments',
            subtitle: '${mine.length} events under your management',
            icon: Icons.emoji_events_outlined,
          ),

          const SizedBox(height: SportikaSpacing.md),

          if (mine.isEmpty)
            _OrganizerCompactEmpty(
              icon: Icons.emoji_events_outlined,
              title: 'Your arena is waiting',
              description: 'Create a tournament to manage entries, fixtures and results.',
              action: PrimaryButton(
                label: 'Create tournament',
                icon: Icons.add,
                onPressed: () => pushRoute(context, AppRoute.createTournament),
              ),
            )
          else
            for (final tournament in mine) ...[
              _OrganizerTournamentCard(tournament: tournament),
              const SizedBox(height: SportikaSpacing.md),
            ],
        ],
      ),
    );
  }
}

// ============================================================
// CINEMATIC ORGANIZER HERO
// ============================================================

class _OrganizerHero extends StatelessWidget {
  const _OrganizerHero({required this.eventCount, required this.onCreate});

  final int eventCount;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(SportikaRadius.card),
      child: Container(
        decoration: const BoxDecoration(gradient: SportikaGradients.sportPanel),
        child: Stack(
          children: [
            Positioned(
              right: -SportikaSpacing.xl,
              top: -SportikaSpacing.xl,
              child: Icon(
                Icons.emoji_events_outlined,
                size: SportikaSpacing.xxl * 5,
                color: SportikaColors.mint.withValues(
                  alpha: SportikaOpacity.faint,
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(SportikaSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SPORTIKA / ORGANIZER',
                    style: SportikaType.micro.copyWith(
                      color: SportikaColors.mint,
                    ),
                  ),

                  const SizedBox(height: SportikaSpacing.md),

                  const Text(
                    'Your events.\nYour arena.',
                    style: SportikaType.hero,
                  ),

                  const SizedBox(height: SportikaSpacing.sm),

                  const Text(
                    'Create tournaments, manage entries '
                    'and publish official results.',
                    style: SportikaType.caption,
                  ),

                  const SizedBox(height: SportikaSpacing.md),

                  Row(
                    children: [
                      const Icon(
                        Icons.emoji_events_outlined,
                        size: SportikaIconSize.sm,
                        color: SportikaColors.mint,
                      ),
                      const SizedBox(width: SportikaSpacing.xs),
                      Text(
                        '$eventCount tournaments',
                        style: SportikaType.label.copyWith(
                          color: SportikaColors.mint,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: SportikaSpacing.lg),

                  PrimaryButton(
                    label: 'Create tournament',
                    icon: Icons.add_circle_outline,
                    onPressed: onCreate,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// METRIC CARD
// ============================================================

class _OrganizerMetric extends StatelessWidget {
  const _OrganizerMetric({
    required this.value,
    required this.label,
    required this.icon,
    required this.tone,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: SportikaIconSize.lg, color: tone),

          const SizedBox(height: SportikaSpacing.md),

          Text(value, style: SportikaType.titleMedium),

          const SizedBox(height: SportikaSpacing.xs),

          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SportikaType.caption,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SECTION HEADING
// ============================================================

class _OrganizerSectionHeader extends StatelessWidget {
  const _OrganizerSectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: SportikaIconSize.lg, color: SportikaColors.mint),

        const SizedBox(width: SportikaSpacing.sm),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: SportikaType.titleMedium),
              const SizedBox(height: SportikaSpacing.xs),
              Text(subtitle, style: SportikaType.caption),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// COMPACT EMPTY STATE
// ============================================================

class _OrganizerCompactEmpty extends StatelessWidget {
  const _OrganizerCompactEmpty({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: SportikaColors.mint, size: SportikaIconSize.lg),

          const SizedBox(height: SportikaSpacing.sm),

          Text(title, style: SportikaType.bodyStrong),

          const SizedBox(height: SportikaSpacing.xs),

          Text(description, style: SportikaType.caption),

          if (action != null) ...[
            const SizedBox(height: SportikaSpacing.md),
            action!,
          ],
        ],
      ),
    );
  }
}

// ============================================================
// PENDING ENTRY
// ============================================================

class _PendingEntryCard extends StatelessWidget {
  const _PendingEntryCard({required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final tournaments = context.watch<TournamentsController>();
    final tournament = tournaments.tournamentById(entry.tournamentId);

    return SurfaceCard(
      borderColor: SportikaColors.gold.withValues(alpha: SportikaOpacity.muted),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.person_add_alt_1_outlined,
                color: SportikaColors.gold,
                size: SportikaIconSize.lg,
              ),

              const SizedBox(width: SportikaSpacing.sm),

              Expanded(
                child: Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.bodyStrong,
                ),
              ),

              const StatusPill('Pending', color: SportikaColors.gold),
            ],
          ),

          const SizedBox(height: SportikaSpacing.sm),

          Text(
            '${tournament?.name ?? 'Tournament'} · '
            '${tournament?.entryType.label ?? ''} entry',
            style: SportikaType.caption,
          ),

          const SizedBox(height: SportikaSpacing.md),

          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Confirm',
                  icon: Icons.check_rounded,
                  small: true,
                  tone: SportikaColors.mint,
                  onPressed: () {
                    context.read<TournamentsController>().decideEntry(
                      entry.id,
                      approve: true,
                    );

                    showSnack(context, '${entry.label} confirmed');
                  },
                ),
              ),

              const SizedBox(width: SportikaSpacing.sm),

              Expanded(
                child: GhostButton(
                  label: 'Reject',
                  icon: Icons.close_rounded,
                  tone: SportikaColors.danger,
                  expand: true,
                  onPressed: () => _confirmRejection(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRejection(BuildContext context) async {
    final reject = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject entry?'),
        content: Text('Reject ${entry.label} from this tournament?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reject entry'),
          ),
        ],
      ),
    );

    if (reject != true || !context.mounted) return;

    context.read<TournamentsController>().decideEntry(
      entry.id,
      approve: false,
      note: 'Entry did not meet the tournament requirements',
    );

    showSnack(context, '${entry.label} rejected');
  }
}

// ============================================================
// RESULT REVIEW
// ============================================================

class _OrganizerReviewCard extends StatelessWidget {
  const _OrganizerReviewCard({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        officialFixtureTile(context, fixture),

        const SizedBox(height: SportikaSpacing.sm),

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

            GhostButton(
              label: 'Walkover',
              icon: Icons.flag_outlined,
              onPressed: () => recordWalkoverFor(context, fixture),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================
// DISPUTED RESULT
// ============================================================

class _OrganizerDisputeCard extends StatelessWidget {
  const _OrganizerDisputeCard({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final fixtures = context.watch<FixturesController>();
    final tournament = fixtures.tournamentOf(fixture);
    final sides = fixtures.sideLabelsOf(fixture);

    final reporter = context.watch<SessionController>().accountById(
      fixture.disputeRaisedBy,
    );

    return SurfaceCard(
      borderColor: SportikaColors.danger.withValues(
        alpha: SportikaOpacity.muted,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.gavel_outlined,
                color: SportikaColors.danger,
                size: SportikaIconSize.lg,
              ),

              const SizedBox(width: SportikaSpacing.sm),

              Expanded(
                child: Text(
                  '${tournament?.name ?? 'Tournament'} · '
                  '${fixture.stage}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.bodyStrong,
                ),
              ),

              const StatusPill('Disputed', color: SportikaColors.danger),
            ],
          ),

          const SizedBox(height: SportikaSpacing.md),

          Text('${sides[0]} vs ${sides[1]}', style: SportikaType.bodyStrong),

          if ((fixture.disputeNote ?? '').isNotEmpty) ...[
            const SizedBox(height: SportikaSpacing.sm),
            Text(fixture.disputeNote!, style: SportikaType.caption),
          ],

          const SizedBox(height: SportikaSpacing.sm),

          Text(
            'Raised by ${reporter?.displayName ?? 'player'}'
            '${fixture.result == null ? '' : ' · Published: ${fixture.result!.headline}'}',
            style: SportikaType.caption,
          ),

          const SizedBox(height: SportikaSpacing.md),

          Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: 'Open fixture',
                  icon: Icons.open_in_new,
                  expand: true,
                  onPressed: () => pushRoute(
                    context,
                    AppRoute.fixtureDetail,
                    args: FixtureDetailArgs(fixture.id),
                  ),
                ),
              ),

              const SizedBox(width: SportikaSpacing.sm),

              Expanded(
                child: PrimaryButton(
                  label: 'Resolve',
                  icon: Icons.gavel_outlined,
                  small: true,
                  tone: SportikaColors.danger,
                  onPressed: () => resolveDisputeFor(context, fixture),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// TOURNAMENT MANAGEMENT CARD
// ============================================================

class _OrganizerTournamentCard extends StatelessWidget {
  const _OrganizerTournamentCard({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final tournaments = context.watch<TournamentsController>();
    final fixtureController = context.watch<FixturesController>();

    final pending = tournaments.pendingEntriesFor(tournament.id).length;

    final fixtures = fixtureController.fixturesFor(tournament.id);

    final review = fixtureController.fixturesAwaitingReview
        .where((fixture) => fixture.tournamentId == tournament.id)
        .length;

    final confirmed = tournaments.confirmedCountFor(tournament);

    return Column(
      children: [
        TournamentCard(
          tournament: tournament,
          trailing: pending > 0
              ? StatusPill('$pending pending', color: SportikaColors.gold)
              : null,
        ),

        const SizedBox(height: SportikaSpacing.sm),

        SurfaceCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _TournamentMetricLabel(
                      icon: Icons.people_outline,
                      value: '$confirmed',
                      label: 'Entries',
                    ),
                  ),
                  Expanded(
                    child: _TournamentMetricLabel(
                      icon: Icons.fact_check_outlined,
                      value: '$review',
                      label: 'Review',
                    ),
                  ),
                  Expanded(
                    child: _TournamentMetricLabel(
                      icon: Icons.account_tree_outlined,
                      value: '${fixtures.length}',
                      label: 'Fixtures',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: SportikaSpacing.md),

              PrimaryButton(
                label: 'Manage tournament',
                icon: Icons.arrow_forward_rounded,
                onPressed: () => pushRoute(
                  context,
                  AppRoute.tournamentDetail,
                  args: TournamentDetailArgs(tournament.id),
                ),
              ),

              const SizedBox(height: SportikaSpacing.sm),

              Row(
                children: [
                  Expanded(
                    child: GhostButton(
                      label: review > 0 ? 'Review ($review)' : 'Results',
                      icon: Icons.fact_check_outlined,
                      expand: true,
                      tone: review > 0
                          ? SportikaColors.mint
                          : SportikaColors.textBody,
                      onPressed: () => pushRoute(
                        context,
                        AppRoute.resultsReview,
                        args: ResultsReviewArgs(tournamentId: tournament.id),
                      ),
                    ),
                  ),

                  if (fixtures.isEmpty) ...[
                    const SizedBox(width: SportikaSpacing.sm),
                    Expanded(
                      child: GhostButton(
                        label: 'Publish draw',
                        icon: Icons.account_tree_outlined,
                        expand: true,
                        onPressed: () => _confirmDraw(context),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDraw(BuildContext context) async {
    final confirmed = context.read<TournamentsController>().confirmedCountFor(
      tournament,
    );

    if (confirmed < 2) {
      showSnack(context, 'Confirm at least two entries first', error: true);
      return;
    }

    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Publish tournament draw?'),
        content: Text(
          'Generate fixtures for $confirmed confirmed entries? '
          'Review the tournament setup before continuing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Generate draw'),
          ),
        ],
      ),
    );

    if (approved != true || !context.mounted) return;

    final count = await context.read<TournamentsController>().generateDraw(
      tournament.id,
    );

    if (!context.mounted) return;

    showSnack(
      context,
      count == 0
          ? 'Unable to generate draw'
          : 'Draw published · $count fixtures created',
      error: count == 0,
    );
  }
}

// ============================================================
// TOURNAMENT METRIC
// ============================================================

class _TournamentMetricLabel extends StatelessWidget {
  const _TournamentMetricLabel({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: SportikaColors.textMuted, size: SportikaIconSize.sm),
        const SizedBox(height: SportikaSpacing.xs),
        Text(value, style: SportikaType.bodyStrong),
        Text(label, style: SportikaType.caption),
      ],
    );
  }
}
