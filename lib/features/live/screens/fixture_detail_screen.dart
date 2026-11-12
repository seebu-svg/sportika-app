import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/shared/widgets/results_actions.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/personal_games/screens/scorecard_screen.dart';
import 'package:sportika/features/discover/screens/tournament_detail_screen.dart';

/// Match page for one official fixture: live score, result, scorers, roster,
/// correction audit trail and every organizer workflow action.
class FixtureDetailScreen extends StatelessWidget {
  const FixtureDetailScreen({super.key, required this.fixtureId});

  final String fixtureId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LocalSportikaRepository>();
    final fixture = state.fixtureById(fixtureId);
    if (fixture == null) {
      return Scaffold(
        appBar: sportikaAppBar('Fixture'),
        body: const Padding(
          padding: EdgeInsets.all(20),
          child: EmptyState(title: 'Fixture not found', icon: Icons.search_off),
        ),
      );
    }

    final tournament = state.tournamentOf(fixture);
    final sport = tournament?.sport ?? Sport.cricket;
    final progress = state.progressOfFixture(fixture);
    final result = fixture.result;
    final sides = state.sideLabelsOf(fixture);
    final me = state.currentAccount;
    final isOrganizer = tournament != null && tournament.organizerId == me?.id;
    final isScorer = me != null && fixture.scorerAccountIds.contains(me.id);
    final locked =
        fixture.status == FixtureStatus.published ||
        fixture.status == FixtureStatus.walkover;

    final scores = result != null && result.sideScores.length >= 2
        ? result.sideScores
        : progress.scoreDisplay;
    final winner =
        result?.winnerIndex ??
        (progress.isComplete ? progress.winnerIndex : -1);
    final headline = result?.headline ?? progress.headline;

    final scorerNames = fixture.scorerAccountIds
        .map((id) => state.accountById(id)?.displayName)
        .whereType<String>()
        .toList();

    return Scaffold(
      appBar: sportikaAppBar(
        '${sides[0]} vs ${sides[1]}',
        subtitle: '${tournament?.name ?? 'Fixture'} · ${fixture.stage}',
        actions: [
          if (isOrganizer)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
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
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'schedule',
                  child: Text('Edit venue & time'),
                ),
                PopupMenuItem(value: 'scorers', child: Text('Assign scorers')),
                PopupMenuItem(
                  value: 'walkover',
                  child: Text('Record walkover'),
                ),
                PopupMenuItem(value: 'dispute', child: Text('Raise a dispute')),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        children: [
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SportTag(sport),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fixture.stage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
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
                const SizedBox(height: 14),
                for (var i = 0; i < 2; i++) ...[
                  _SideScoreRow(
                    label: sides[i],
                    score: i < scores.length ? scores[i] : '',
                    leading: winner == i,
                    tone: i == 0 ? sportColor(sport) : SportikaColors.mint,
                  ),
                  if (i == 0) const SizedBox(height: 8),
                ],
                if (headline.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    headline,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: result != null || progress.isComplete
                          ? SportikaColors.mint
                          : SportikaColors.textBody,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                KeyValueRow('Scheduled', dateShort(fixture.scheduledAt)),
                KeyValueRow(
                  'Venue',
                  fixture.venue.isEmpty ? '-' : fixture.venue,
                ),
                KeyValueRow(
                  'Rules',
                  tournament == null
                      ? SportEngines.describeRules(sport, fixture.rules)
                      : tournament.matchRules,
                ),
                KeyValueRow(
                  'Scorers',
                  scorerNames.isEmpty ? 'Not assigned' : scorerNames.join(', '),
                ),
                KeyValueRow('Entries recorded', '${fixture.events.length}'),
              ],
            ),
          ),
          if (fixture.disputeNote != null) ...[
            const SizedBox(height: 10),
            _DisputeCard(
              fixture: fixture,
              canResolve:
                  state.canOrganize &&
                  state.tournamentOf(fixture)?.organizerId ==
                      state.currentAccount?.id,
              sides: sides,
            ),
          ],
          if (!locked) ...[
            const SizedBox(height: 12),
            if (isScorer || isOrganizer)
              PrimaryButton(
                label: fixture.events.isEmpty
                    ? 'Start scoring'
                    : 'Open scorecard',
                icon: Icons.sports_score,
                tone: sportColor(sport),
                onPressed: () => pushScreen(
                  context,
                  ScorecardScreen(id: fixture.id, mode: ScorecardMode.official),
                ),
              ),
            if (!isScorer && isOrganizer) ...[
              const SizedBox(height: 8),
              InfoBanner(
                icon: Icons.person_add_alt,
                text: scorerNames.isEmpty
                    ? 'No scorer assigned yet. Assign yourself or another scorer '
                          'before the match starts.'
                    : 'You are not assigned to score this fixture. Assign yourself from '
                          'the menu to take over.',
              ),
            ],
            if (isOrganizer) ...[
              const SizedBox(height: 10),
              if (fixture.status == FixtureStatus.submitted ||
                  fixture.result != null ||
                  fixture.events.isNotEmpty)
                PrimaryButton(
                  label: fixture.result == null
                      ? 'Review & publish'
                      : 'Publish correction',
                  icon: Icons.verified_outlined,
                  tone: SportikaColors.mint,
                  onPressed: () => publishFixture(context, fixture),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: GhostButton(
                      label: 'Walkover',
                      icon: Icons.flag_outlined,
                      expand: true,
                      onPressed: () => recordWalkoverFor(context, fixture),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GhostButton(
                      label: 'Scorers',
                      icon: Icons.swap_horiz,
                      expand: true,
                      onPressed: () => assignScorerSheet(context, fixture),
                    ),
                  ),
                ],
              ),
            ],
          ],
          if (locked &&
              me != null &&
              _isParticipant(state, fixture, me.id)) ...[
            const SizedBox(height: 10),
            GhostButton(
              label: 'Dispute this result',
              icon: Icons.gavel,
              tone: SportikaColors.danger,
              expand: true,
              onPressed: () => raiseDisputeFor(context, fixture),
            ),
          ],
          if (result != null) ...[
            const SectionTitle('Official result'),
            SurfaceCard(
              borderColor: SportikaColors.mint.withValues(alpha: 0.3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        result.walkover ? Icons.flag_outlined : Icons.verified,
                        size: 16,
                        color: SportikaColors.mint,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          result.headline,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: SportikaColors.mint,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (result.detail.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      result.detail,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: SportikaColors.textMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  KeyValueRow(
                    'Published',
                    '${timeAgo(result.publishedAt)} by '
                        '${state.accountById(result.publishedById)?.displayName ?? 'organizer'}',
                  ),
                ],
              ),
            ),
          ],
          if (fixture.corrections.isNotEmpty) ...[
            const SectionTitle('Correction history'),
            for (final correction in fixture.corrections.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SurfaceCard(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.edit_note,
                            size: 15,
                            color: SportikaColors.gold,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              correction.reason,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: SportikaColors.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${correction.previous.headline} → ${correction.current.headline}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: SportikaColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${timeAgo(correction.at)} · '
                        '${state.accountById(correction.byAccountId)?.displayName ?? 'organizer'}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: SportikaColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SectionTitle('Roster'),
          _Roster(state: state, fixture: fixture, sides: sides),
          if (tournament != null) ...[
            const SizedBox(height: 16),
            GhostButton(
              label: 'Open ${tournament.name}',
              icon: Icons.emoji_events_outlined,
              expand: true,
              onPressed: () => pushScreen(
                context,
                TournamentDetailScreen(id: tournament.id),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static bool _isParticipant(
    LocalSportikaRepository state,
    Fixture fixture,
    String accountId,
  ) {
    final home = state.entriesById[fixture.home.entryId];
    final away = state.entriesById[fixture.away.entryId];
    return (home?.memberAccountIds.contains(accountId) ?? false) ||
        (away?.memberAccountIds.contains(accountId) ?? false);
  }
}

class _SideScoreRow extends StatelessWidget {
  const _SideScoreRow({
    required this.label,
    required this.score,
    required this.leading,
    required this.tone,
  });

  final String label;
  final String score;
  final bool leading;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 24,
          decoration: BoxDecoration(
            color: leading
                ? tone
                : SportikaColors.textDim.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: leading ? FontWeight.w800 : FontWeight.w600,
              color: leading ? SportikaColors.text : SportikaColors.textBody,
            ),
          ),
        ),
        Text(
          score.isEmpty ? '-' : score,
          style: TextStyle(
            fontSize: 25,
            height: 1,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: leading ? tone : SportikaColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _DisputeCard extends StatelessWidget {
  const _DisputeCard({
    required this.fixture,
    required this.canResolve,
    required this.sides,
  });

  final Fixture fixture;
  final bool canResolve;
  final List<String> sides;

  @override
  Widget build(BuildContext context) {
    final state = context.read<LocalSportikaRepository>();
    final resolved = fixture.disputeResolved;

    return SurfaceCard(
      borderColor: (resolved ? SportikaColors.textMuted : SportikaColors.danger)
          .withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                resolved ? Icons.check_circle_outline : Icons.gavel,
                size: 16,
                color: resolved
                    ? SportikaColors.textMuted
                    : SportikaColors.danger,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  resolved ? 'Dispute closed' : 'Disputed result',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: resolved
                        ? SportikaColors.textMuted
                        : SportikaColors.danger,
                  ),
                ),
              ),
              StatusPill(
                resolved ? 'Resolved' : 'Open',
                color: resolved
                    ? SportikaColors.textMuted
                    : SportikaColors.danger,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            fixture.disputeNote ?? '',
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: SportikaColors.textBody,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Raised by ${state.accountById(fixture.disputeRaisedBy)?.displayName ?? 'player'}',
            style: const TextStyle(
              fontSize: 10.5,
              color: SportikaColors.textDim,
            ),
          ),
          if (canResolve && !resolved) ...[
            const SizedBox(height: 10),
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

class _Roster extends StatelessWidget {
  const _Roster({
    required this.state,
    required this.fixture,
    required this.sides,
  });

  final LocalSportikaRepository state;
  final Fixture fixture;
  final List<String> sides;

  @override
  Widget build(BuildContext context) {
    final home = state.entriesById[fixture.home.entryId];
    final away = state.entriesById[fixture.away.entryId];

    if (home == null && away == null) {
      return const EmptyState(
        title: 'Sides not decided',
        body: 'A knockout slot fills in once the feeder fixture result is published.',
        icon: Icons.help_outline,
      );
    }

    return Column(
      children: [
        _EntryRoster(label: sides[0], entry: home, state: state),
        if (home != null && away != null) const SizedBox(height: 8),
        _EntryRoster(label: sides[1], entry: away, state: state),
      ],
    );
  }
}

class _EntryRoster extends StatelessWidget {
  const _EntryRoster({
    required this.label,
    required this.entry,
    required this.state,
  });

  final String label;
  final Entry? entry;
  final LocalSportikaRepository state;

  @override
  Widget build(BuildContext context) {
    final entry = this.entry;
    return SurfaceCard(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: SportikaColors.text,
                  ),
                ),
              ),
              if (entry != null)
                StatusPill(
                  entry.status.label,
                  color: statusColor(entry.status.key),
                ),
            ],
          ),
          if (entry != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final memberId in entry.memberAccountIds)
                  _MemberChip(
                    name: state.accountById(memberId)?.displayName ?? 'Player',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MemberChip extends StatelessWidget {
  const _MemberChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerAvatar(initials: initialsOf(name), size: 24),
        const SizedBox(width: 6),
        Text(
          name,
          style: const TextStyle(
            fontSize: 11.5,
            color: SportikaColors.textBody,
          ),
        ),
      ],
    );
  }
}
