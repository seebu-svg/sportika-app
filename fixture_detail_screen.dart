import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/state/app_state.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/shared/widgets/results_actions.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/personal_games/screens/scorecard_screen.dart';
import 'package:sportika/features/discover/screens/tournament_detail_screen.dart';

/// Official match center. Presentation-only redesign: all actions continue to
/// use the existing application state, authorization and workflow functions.
class FixtureDetailScreen extends StatelessWidget {
  const FixtureDetailScreen({super.key, required this.fixtureId});

  final String fixtureId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
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
    final locked = fixture.status == FixtureStatus.published ||
        fixture.status == FixtureStatus.walkover;
    final scores = result != null && result.sideScores.length >= 2
        ? result.sideScores
        : progress.scoreDisplay;
    final winner = result?.winnerIndex ??
        (progress.isComplete ? progress.winnerIndex : -1);
    final headline = result?.headline ?? progress.headline;
    final scorerNames = fixture.scorerAccountIds
        .map((id) => state.accountById(id)?.displayName)
        .whereType<String>()
        .toList();
    final rules = tournament == null
        ? SportEngines.describeRules(sport, fixture.rules)
        : tournament.matchRules;

    return Scaffold(
      appBar: sportikaAppBar(
        'Match center',
        subtitle: tournament?.name ?? 'Official fixture',
        actions: [
          if (isOrganizer)
            PopupMenuButton<String>(
              tooltip: 'Manage fixture',
              icon: const Icon(Icons.more_horiz_rounded),
              color: SportikaColors.surfaceElevated,
              onSelected: (value) async {
                switch (value) {
                  case 'schedule':
                    await editFixtureSchedule(context, fixture);
                    break;
                  case 'scorers':
                    await assignScorerSheet(context, fixture);
                    break;
                  case 'walkover':
                    await recordWalkoverFor(context, fixture);
                    break;
                  case 'dispute':
                    await raiseDisputeFor(context, fixture);
                    break;
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'schedule', child: Text('Edit venue & time')),
                PopupMenuItem(value: 'scorers', child: Text('Assign scorers')),
                PopupMenuItem(value: 'walkover', child: Text('Record walkover')),
                PopupMenuItem(value: 'dispute', child: Text('Raise a dispute')),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _MatchScoreboard(
            sport: sport,
            stage: fixture.stage,
            status: fixture.status,
            sides: sides,
            scores: scores,
            winner: winner,
            headline: headline,
            statusDetail: progress.statusLabel,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 22),
                const _SectionHeading('MATCH INFORMATION', icon: Icons.info_outline),
                const SizedBox(height: 12),
                _MatchInformation(
                  fixture: fixture,
                  rules: rules,
                  scorerNames: scorerNames,
                ),
                if (fixture.disputeNote != null) ...[
                  const SizedBox(height: 20),
                  _DisputeCard(
                    fixture: fixture,
                    canResolve: isOrganizer,
                  ),
                ],
                if (!locked && (isScorer || isOrganizer)) ...[
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: fixture.events.isEmpty ? 'Start scoring' : 'Open scorecard',
                    icon: Icons.sports_score,
                    tone: sportColor(sport),
                    onPressed: () => pushScreen(
                      context,
                      ScorecardScreen(id: fixture.id, mode: ScorecardMode.official),
                    ),
                  ),
                ],
                if (!locked && isOrganizer && !isScorer) ...[
                  const SizedBox(height: 10),
                  InfoBanner(
                    icon: Icons.person_add_alt,
                    text: scorerNames.isEmpty
                        ? 'No scorer assigned yet. Assign yourself or another scorer before the match starts.'
                        : 'You are not assigned to score this fixture. Assign yourself from the menu to take over.',
                  ),
                ],
                if (!locked && isOrganizer) ...[
                  const SizedBox(height: 18),
                  const _SectionHeading('ORGANIZER CONTROLS', icon: Icons.tune_rounded),
                  const SizedBox(height: 12),
                  if (fixture.status == FixtureStatus.submitted ||
                      fixture.result != null ||
                      fixture.events.isNotEmpty) ...[
                    PrimaryButton(
                      label: fixture.result == null ? 'Review & publish' : 'Publish correction',
                      icon: Icons.verified_outlined,
                      tone: SportikaColors.mint,
                      onPressed: () => publishFixture(context, fixture),
                    ),
                    const SizedBox(height: 10),
                  ],
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
                      const SizedBox(width: 10),
                      Expanded(
                        child: GhostButton(
                          label: 'Scorers',
                          icon: Icons.people_outline,
                          expand: true,
                          onPressed: () => assignScorerSheet(context, fixture),
                        ),
                      ),
                    ],
                  ),
                ],
                if (locked && me != null && _isParticipant(state, fixture, me.id)) ...[
                  const SizedBox(height: 18),
                  GhostButton(
                    label: 'Dispute this result',
                    icon: Icons.gavel,
                    tone: SportikaColors.danger,
                    expand: true,
                    onPressed: () => raiseDisputeFor(context, fixture),
                  ),
                ],
                if (result != null) ...[
                  const SizedBox(height: 26),
                  const _SectionHeading('OFFICIAL RESULT', icon: Icons.verified_outlined),
                  const SizedBox(height: 12),
                  _OfficialResult(
                    headline: result.headline,
                    detail: result.detail,
                    walkover: result.walkover,
                    published: '${timeAgo(result.publishedAt)} by '
                        '${state.accountById(result.publishedById)?.displayName ?? 'organizer'}',
                  ),
                ],
                if (fixture.corrections.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  const _SectionHeading('CORRECTION HISTORY', icon: Icons.history_rounded),
                  const SizedBox(height: 12),
                  for (final correction in fixture.corrections.reversed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TimelineItem(
                        title: correction.reason,
                        detail: '${correction.previous.headline} → ${correction.current.headline}',
                        footer: '${timeAgo(correction.at)} · '
                            '${state.accountById(correction.byAccountId)?.displayName ?? 'organizer'}',
                      ),
                    ),
                ],
                const SizedBox(height: 26),
                const _SectionHeading('TEAM ROSTERS', icon: Icons.groups_outlined),
                const SizedBox(height: 12),
                _Roster(state: state, fixture: fixture, sides: sides),
                if (tournament != null) ...[
                  const SizedBox(height: 24),
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
          ),
        ],
      ),
    );
  }

  static bool _isParticipant(AppState state, Fixture fixture, String accountId) {
    final home = state.entriesById[fixture.home.entryId];
    final away = state.entriesById[fixture.away.entryId];
    return (home?.memberAccountIds.contains(accountId) ?? false) ||
        (away?.memberAccountIds.contains(accountId) ?? false);
  }
}

class _MatchScoreboard extends StatelessWidget {
  const _MatchScoreboard({
    required this.sport,
    required this.stage,
    required this.status,
    required this.sides,
    required this.scores,
    required this.winner,
    required this.headline,
    required this.statusDetail,
  });

  final Sport sport;
  final String stage;
  final FixtureStatus status;
  final List<String> sides;
  final List<String> scores;
  final int winner;
  final String headline;
  final String? statusDetail;

  @override
  Widget build(BuildContext context) {
    final accent = sportColor(sport);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 26),
      decoration: const BoxDecoration(
        color: SportikaColors.deepest,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                sport.label.toUpperCase(),
                style: const TextStyle(
                  color: SportikaColors.mintSoft,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  stage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
              StatusPill(
                status.label,
                color: statusColor(status.key),
                icon: statusIcon(status.key),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _ScoreSide(
                  name: sides[0],
                  score: scores.isNotEmpty ? scores[0] : '-',
                  isWinner: winner == 0,
                  accent: accent,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    Text(
                      winner >= 0 ? 'FINAL' : 'VS',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(height: 2, width: 20, color: SportikaColors.mint),
                  ],
                ),
              ),
              Expanded(
                child: _ScoreSide(
                  name: sides[1],
                  score: scores.length > 1 ? scores[1] : '-',
                  isWinner: winner == 1,
                  accent: SportikaColors.mintSoft,
                ),
              ),
            ],
          ),
          if (statusDetail != null && statusDetail!.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(
              statusDetail!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          if (headline.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                headline,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScoreSide extends StatelessWidget {
  const _ScoreSide({
    required this.name,
    required this.score,
    required this.isWinner,
    required this.accent,
  });

  final String name;
  final String score;
  final bool isWinner;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 54,
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            initialsOf(name),
            maxLines: 1,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
          ),
        ),
        const SizedBox(height: 11),
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            score.isEmpty ? '-' : score,
            maxLines: 1,
            style: TextStyle(
              color: isWinner ? accent : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 32,
              letterSpacing: -1,
            ),
          ),
        ),
        if (isWinner) ...[
          const SizedBox(height: 5),
          const Text(
            'WINNER',
            style: TextStyle(
              color: SportikaColors.mintSoft,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.label, {required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: SportikaColors.blue, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                color: SportikaColors.text,
              ),
            ),
          ),
        ],
      );
}

class _MatchInformation extends StatelessWidget {
  const _MatchInformation({
    required this.fixture,
    required this.rules,
    required this.scorerNames,
  });

  final Fixture fixture;
  final String rules;
  final List<String> scorerNames;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        child: Column(
          children: [
            KeyValueRow('Scheduled', dateShort(fixture.scheduledAt)),
            const Divider(height: 22),
            KeyValueRow('Venue', fixture.venue.isEmpty ? '-' : fixture.venue),
            const Divider(height: 22),
            KeyValueRow('Rules', rules),
            const Divider(height: 22),
            KeyValueRow('Official scorers', scorerNames.isEmpty ? 'Not assigned' : scorerNames.join(', ')),
            const Divider(height: 22),
            KeyValueRow('Entries recorded', '${fixture.events.length}'),
          ],
        ),
      );
}

class _OfficialResult extends StatelessWidget {
  const _OfficialResult({
    required this.headline,
    required this.detail,
    required this.walkover,
    required this.published,
  });
  final String headline;
  final String detail;
  final bool walkover;
  final String published;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        borderColor: SportikaColors.mint.withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(walkover ? Icons.flag_outlined : Icons.verified_rounded,
                    color: SportikaColors.mint, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    headline,
                    style: const TextStyle(
                      color: SportikaColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(detail, style: const TextStyle(color: SportikaColors.textBody, height: 1.5)),
            ],
            const SizedBox(height: 12),
            Text('Published $published',
                style: const TextStyle(color: SportikaColors.textMuted, fontSize: 11)),
          ],
        ),
      );
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.title, required this.detail, required this.footer});
  final String title;
  final String detail;
  final String footer;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 15, right: 12),
            child: Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(color: SportikaColors.gold, shape: BoxShape.circle),
            ),
          ),
          Expanded(
            child: SurfaceCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 5),
                  Text(detail, style: const TextStyle(color: SportikaColors.textBody, fontSize: 12)),
                  const SizedBox(height: 7),
                  Text(footer, style: const TextStyle(color: SportikaColors.textMuted, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      );
}

class _DisputeCard extends StatelessWidget {
  const _DisputeCard({required this.fixture, required this.canResolve});
  final Fixture fixture;
  final bool canResolve;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final resolved = fixture.disputeResolved;
    final tone = resolved ? SportikaColors.textMuted : SportikaColors.danger;
    return SurfaceCard(
      borderColor: tone.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(resolved ? Icons.check_circle_outline : Icons.gavel, color: tone, size: 18),
              const SizedBox(width: 9),
              Expanded(
                child: Text(resolved ? 'Dispute closed' : 'Result under dispute',
                    style: TextStyle(color: tone, fontSize: 13, fontWeight: FontWeight.w800)),
              ),
              StatusPill(resolved ? 'Resolved' : 'Open', color: tone),
            ],
          ),
          const SizedBox(height: 12),
          Text(fixture.disputeNote ?? '',
              style: const TextStyle(color: SportikaColors.textBody, height: 1.5, fontSize: 12)),
          const SizedBox(height: 8),
          Text('Raised by ${state.accountById(fixture.disputeRaisedBy)?.displayName ?? 'player'}',
              style: const TextStyle(color: SportikaColors.textMuted, fontSize: 11)),
          if (canResolve && !resolved) ...[
            const SizedBox(height: 14),
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
  const _Roster({required this.state, required this.fixture, required this.sides});
  final AppState state;
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
        const SizedBox(height: 10),
        _EntryRoster(label: sides[1], entry: away, state: state),
      ],
    );
  }
}

class _EntryRoster extends StatelessWidget {
  const _EntryRoster({required this.label, required this.entry, required this.state});
  final String label;
  final Entry? entry;
  final AppState state;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                ),
                if (entry != null)
                  StatusPill(entry!.status.label, color: statusColor(entry!.status.key)),
              ],
            ),
            if (entry != null) ...[
              const SizedBox(height: 14),
              for (final memberId in entry!.memberAccountIds) ...[
                _MemberRow(name: state.accountById(memberId)?.displayName ?? 'Player'),
                const SizedBox(height: 10),
              ],
            ] else ...[
              const SizedBox(height: 8),
              const Text('Awaiting qualification',
                  style: TextStyle(color: SportikaColors.textMuted, fontSize: 12)),
            ],
          ],
        ),
      );
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          PlayerAvatar(initials: initialsOf(name), size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: SportikaColors.textBody)),
          ),
        ],
      );
}
