import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/monetization_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/shared/widgets/fixture_tile.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/shared/widgets/results_actions.dart';
import 'package:sportika/features/discover/widgets/tournament_card.dart';
import 'package:sportika/features/monetization/widgets/billing_widgets.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Organizer home (spec §4, §5): what needs a decision now, plus every event
/// the organizer runs.
class OrganizerDashboardScreen extends StatelessWidget {
  const OrganizerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TournamentsController>();
    context.watch<TournamentsController>();
    final billing = context.watch<MonetizationController>();
    final me = context.read<ProfileController>().currentAccount;
    final mine = state.tournamentsForOrganizer(me?.id);
    final pending = <Entry>[
      for (final t in mine) ...state.pendingEntriesFor(t.id),
    ];
    final review = context.read<FixturesController>().fixturesAwaitingReview;
    final disputes = context.read<FixturesController>().myOrganizerDisputes;
    final live = context
        .read<FixturesController>()
        .myOrganizerFixtures
        .where((f) => f.status == FixtureStatus.live)
        .toList();

    return Scaffold(
      appBar: sportikaAppBar(
        'My tournaments',
        subtitle: '${mine.length} events · ${pending.length} entries to review',
        actions: [
          IconButton(
            tooltip: 'Create tournament',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => pushRoute(context, AppRoute.createTournament),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        children: [
          PremiumStatusCard(billing: billing),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value: '${pending.length}',
                  label: 'Entries',
                  tone: SportikaColors.gold,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  value: '${review.length}',
                  label: 'To publish',
                  tone: SportikaColors.mint,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  value: '${live.length}',
                  label: 'Live',
                  tone: SportikaColors.blueBright,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Create a tournament',
            icon: Icons.emoji_events_outlined,
            onPressed: () => pushRoute(context, AppRoute.createTournament),
          ),
          const SectionTitle('Needs your decision'),
          if (pending.isEmpty && review.isEmpty)
            const EmptyState(
              title: 'Nothing waiting',
              body:
                  'New entries and submitted scores land here for confirmation and '
                  'publication.',
              icon: Icons.task_alt,
            )
          else ...[
            for (final entry in pending)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PendingEntryCard(entry: entry),
              ),
            for (final fixture in review)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  children: [
                    officialFixtureTile(context, fixture),
                    const SizedBox(height: 6),
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
          const SectionTitle('Disputed results'),
          if (disputes.isEmpty)
            const EmptyState(
              title: 'No open disputes',
              body:
                  'Players can flag a questionable result from the fixture '
                  'page, and it lands here for you to close.',
              icon: Icons.gavel,
            )
          else
            for (final fixture in disputes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _OrganizerDisputeCard(fixture: fixture),
              ),
          const SectionTitle('Your tournaments'),
          if (mine.isEmpty)
            const EmptyState(
              title: 'No tournaments yet',
              body: 'Create an event, confirm entries, then publish the draw.',
              icon: Icons.emoji_events_outlined,
            )
          else
            for (final tournament in mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _OrganizerTournamentCard(tournament: tournament),
              ),
        ],
      ),
    );
  }
}

class _PendingEntryCard extends StatelessWidget {
  const _PendingEntryCard({required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TournamentsController>();
    final tournament = state.tournamentById(entry.tournamentId);

    return SurfaceCard(
      borderColor: SportikaColors.gold.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: SportikaColors.text,
                  ),
                ),
              ),
              const StatusPill('Pending', color: SportikaColors.gold),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${tournament?.name ?? 'Tournament'} · ${tournament?.entryType.label ?? ''} entry',
            style: const TextStyle(
              fontSize: 11,
              color: SportikaColors.textMuted,
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Confirm',
                  icon: Icons.check,
                  small: true,
                  tone: SportikaColors.mint,
                  onPressed: () {
                    final state = context.read<TournamentsController>();
                    state.decideEntry(entry.id, approve: true);
                    showSnack(context, '${entry.label} confirmed');
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GhostButton(
                  label: 'Reject',
                  tone: SportikaColors.danger,
                  expand: true,
                  onPressed: () {
                    final state = context.read<TournamentsController>();
                    state.decideEntry(
                      entry.id,
                      approve: false,
                      note: 'Entry did not meet the tournament requirements',
                    );
                    showSnack(context, '${entry.label} rejected');
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrganizerTournamentCard extends StatelessWidget {
  const _OrganizerTournamentCard({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TournamentsController>();
    context.watch<TournamentsController>();
    final pending = state.pendingEntriesFor(tournament.id).length;
    final fixtures = context.read<FixturesController>().fixturesFor(
      tournament.id,
    );
    final review = context
        .read<FixturesController>()
        .fixturesAwaitingReview
        .where((f) => f.tournamentId == tournament.id)
        .length;
    final confirmed = state.confirmedCountFor(tournament);

    return Column(
      children: [
        TournamentCard(
          tournament: tournament,
          trailing: pending > 0
              ? StatusPill('$pending pending', color: SportikaColors.gold)
              : null,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: GhostButton(
                label: 'Entries ($confirmed)',
                icon: Icons.people_outline,
                expand: true,
                onPressed: () => pushRoute(
                  context,
                  AppRoute.tournamentDetail,
                  args: TournamentDetailArgs(tournament.id),
                ),
              ),
            ),
            const SizedBox(width: 6),
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
            const SizedBox(width: 6),
            Expanded(
              child: GhostButton(
                label: fixtures.isEmpty ? 'Publish draw' : 'Manage',
                icon: Icons.account_tree_outlined,
                expand: true,
                onPressed: () async {
                  if (fixtures.isEmpty) {
                    final state = context.read<TournamentsController>();
                    final count = await state.generateDraw(tournament.id);
                    if (!context.mounted) return;
                    showSnack(
                      context,
                      count == 0
                          ? 'Confirm at least two entries first'
                          : 'Draw published · $count fixtures created',
                      error: count == 0,
                    );
                  } else {
                    pushRoute(
                      context,
                      AppRoute.tournamentDetail,
                      args: TournamentDetailArgs(tournament.id),
                    );
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _OrganizerDisputeCard extends StatelessWidget {
  const _OrganizerDisputeCard({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    context.watch<TournamentsController>();
    final tournament = context.read<FixturesController>().tournamentOf(fixture);
    final sides = context.read<FixturesController>().sideLabelsOf(fixture);

    return SurfaceCard(
      borderColor: SportikaColors.danger.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gavel, size: 15, color: SportikaColors.danger),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${tournament?.name ?? 'Tournament'} · ${fixture.stage}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: SportikaColors.text,
                  ),
                ),
              ),
              const StatusPill('Open', color: SportikaColors.danger),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${sides[0]} vs ${sides[1]}',
            style: const TextStyle(
              fontSize: 12,
              color: SportikaColors.textBody,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            fixture.disputeNote ?? '',
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: SportikaColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Raised by ${context.read<SessionController>().accountById(fixture.disputeRaisedBy)?.displayName ?? 'player'}'
            '${fixture.result == null ? '' : ' · published: ${fixture.result!.headline}'}',
            style: const TextStyle(
              fontSize: 10.5,
              color: SportikaColors.textDim,
            ),
          ),
          const SizedBox(height: 10),
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
              const SizedBox(width: 8),
              Expanded(
                child: PrimaryButton(
                  label: 'Resolve',
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

/// Whether this organizer's events carry the premium toolkit, and the one tap
/// that changes it.
///
/// The card is worded so the free layer stays named as free, and it never
/// describes the member as a kind of account: one universal account buys tools
/// or does not, and loses nothing it already had either way.
class PremiumStatusCard extends StatelessWidget {
  const PremiumStatusCard({super.key, required this.billing});

  final MonetizationController billing;

  @override
  Widget build(BuildContext context) {
    final pro = billing.isPro;
    final periodEnd = billing.proSubscription?.currentPeriodEnd;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        borderColor: pro
            ? SportikaColors.gold.withValues(alpha: 0.42)
            : SportikaColors.borderSubtle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    pro ? 'Organizer Pro is active' : 'Free tournament tools',
                    style: SportikaType.bodyStrong,
                  ),
                ),
                if (pro) const PremiumBadge(compact: true),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              pro
                  ? 'Premium entry ceilings, group draw controls and rule '
                        'presets are on for every event you organise'
                        '${periodEnd == null ? '.' : ' until ${billingDate(periodEnd)}.'}'
                  : 'Creating matches, scoring officially and publishing '
                        'results stay free. Pro raises the entry ceiling to '
                        '${billing.premiumEntryCap} and unlocks the draw '
                        'controls on your events.',
              style: SportikaType.caption,
            ),
            const SizedBox(height: 12),
            GhostButton(
              label: pro ? 'Manage plan' : 'Go premium',
              icon: pro ? Icons.tune : Icons.workspace_premium_outlined,
              tone: pro ? SportikaColors.textBody : SportikaColors.gold,
              expand: true,
              onPressed: () => pushRoute(
                context,
                pro ? AppRoute.subscription : AppRoute.pricing,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
