import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/tournament_engine.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/shared/widgets/fixture_tile.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Fixtures for a tournament, grouped by bracket round or by group letter.
class TournamentFixturesSection extends StatelessWidget {
  const TournamentFixturesSection({super.key, required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TournamentsController>();
    context.watch<TournamentsController>();
    final fixtures = context.read<FixturesController>().fixturesFor(
      tournament.id,
    );
    if (fixtures.isEmpty) {
      return EmptyState(
        title: tournament.status == TournamentStatus.open
            ? 'Draw not published'
            : 'No fixtures yet',
        body: tournament.status == TournamentStatus.open
            ? 'The organizer publishes fixtures once enough entries are confirmed.'
            : 'Generate the draw from the organizer tools to create fixtures.',
        icon: Icons.account_tree_outlined,
      );
    }

    if (tournament.format == TournamentFormat.group) {
      final byGroup = <String, List<Fixture>>{};
      for (final f in fixtures) {
        byGroup.putIfAbsent(f.group ?? 'A', () => []).add(f);
      }
      final letters = byGroup.keys.toList()..sort();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final letter in letters) ...[
            SectionTitle('Group $letter'),
            for (final fixture in byGroup[letter]!)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: officialFixtureTile(context, fixture),
              ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final round in state.roundsFor(tournament)) ...[
          SectionTitle(round.first.stage),
          for (final fixture in round)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: officialFixtureTile(context, fixture),
            ),
        ],
      ],
    );
  }
}

/// Standings for group play, or a round-by-round bracket for knockout events.
class TournamentBracket extends StatelessWidget {
  const TournamentBracket({super.key, required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    context.watch<TournamentsController>();
    if (context.read<FixturesController>().fixturesFor(tournament.id).isEmpty) {
      return const EmptyState(
        title: 'Nothing to show yet',
        body: 'The bracket or table fills in as soon as the draw is published.',
        icon: Icons.grid_view_outlined,
      );
    }

    if (tournament.format == TournamentFormat.group) {
      return _StandingsTable(tournament: tournament);
    }
    return _Bracket(tournament: tournament);
  }
}

class _StandingsTable extends StatelessWidget {
  const _StandingsTable({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TournamentsController>();
    context.watch<TournamentsController>();
    final rows = state.standingsFor(tournament);
    if (rows.isEmpty) {
      return const EmptyState(
        title: 'Table is empty',
        body: 'Standings only move when an organizer publishes a result.',
        icon: Icons.table_chart_outlined,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SurfaceCard(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            children: [
              const _StandingHeader(),
              const SizedBox(height: 6),
              for (final row in rows) _StandingLine(row: row),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const InfoBanner(
          icon: Icons.verified_outlined,
          tone: SportikaColors.mint,
          text:
              'Only published results count towards the table. The top two in each '
              'group are marked as qualifiers.',
        ),
      ],
    );
  }
}

class _StandingHeader extends StatelessWidget {
  const _StandingHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
      color: SportikaColors.textDim,
    );
    return const Row(
      children: [
        SizedBox(width: 20, child: Text('#', style: style)),
        Expanded(child: Text('TEAM', style: style)),
        _HeadCell('P'),
        _HeadCell('W'),
        _HeadCell('D'),
        _HeadCell('L'),
        _HeadCell('DIFF'),
        _HeadCell('PTS', wide: true),
      ],
    );
  }
}

class _HeadCell extends StatelessWidget {
  const _HeadCell(this.label, {this.wide = false});

  final String label;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: wide ? 34 : 24,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: SportikaColors.textDim,
        ),
      ),
    );
  }
}

class _StandingLine extends StatelessWidget {
  const _StandingLine({required this.row});

  final StandingRow row;

  @override
  Widget build(BuildContext context) {
    final tone = row.qualifies ? SportikaColors.mint : SportikaColors.textBody;
    const cell = TextStyle(fontSize: 11.5, color: SportikaColors.textMuted);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      decoration: BoxDecoration(
        color: row.qualifies ? SportikaColors.mintSubtle : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '${row.position}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: tone,
              ),
            ),
          ),
          Expanded(
            child: Text(
              row.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: row.qualifies ? FontWeight.w700 : FontWeight.w600,
                color: row.qualifies
                    ? SportikaColors.text
                    : SportikaColors.textBody,
              ),
            ),
          ),
          _cell('${row.played}', cell),
          _cell('${row.won}', cell),
          _cell('${row.drawn}', cell),
          _cell('${row.lost}', cell),
          _cell(row.diff > 0 ? '+${row.diff}' : '${row.diff}', cell),
          SizedBox(
            width: 34,
            child: Text(
              '${row.points}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: tone,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(String text, TextStyle style) => SizedBox(
    width: 24,
    child: Text(text, textAlign: TextAlign.center, style: style),
  );
}

class _Bracket extends StatelessWidget {
  const _Bracket({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TournamentsController>();
    context.watch<TournamentsController>();
    final rounds = state.roundsFor(tournament);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final round in rounds)
            SizedBox(
              width: 208,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        round.first.stage.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: SportikaColors.textMuted,
                        ),
                      ),
                    ),
                    for (final fixture in round)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _BracketCard(fixture: fixture),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BracketCard extends StatelessWidget {
  const _BracketCard({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    context.watch<TournamentsController>();
    final sides = context.read<FixturesController>().sideLabelsOf(fixture);
    final result = fixture.result;
    final winner = result?.winnerIndex ?? -1;
    final scores = result?.sideScores ?? const <String>[];

    return SurfaceCard(
      onTap: () => pushRoute(
        context,
        AppRoute.fixtureDetail,
        args: FixtureDetailArgs(fixture.id),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      borderColor: fixture.status == FixtureStatus.published
          ? SportikaColors.mint.withValues(alpha: 0.35)
          : SportikaColors.border,
      child: Column(
        children: [
          _bracketSide(
            sides[0],
            scores.isNotEmpty ? scores[0] : '',
            winner == 0,
          ),
          const SizedBox(height: 5),
          _bracketSide(
            sides[1],
            scores.length > 1 ? scores[1] : '',
            winner == 1,
          ),
          if (fixture.status == FixtureStatus.live) ...[
            const SizedBox(height: 6),
            const Row(
              children: [
                Icon(Icons.sensors, size: 10, color: SportikaColors.mint),
                SizedBox(width: 4),
                Text(
                  'LIVE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: SportikaColors.mint,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _bracketSide(String label, String score, bool winner) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: winner ? FontWeight.w800 : FontWeight.w600,
            color: winner ? SportikaColors.text : SportikaColors.textBody,
          ),
        ),
      ),
      if (score.isNotEmpty)
        Text(
          score,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: winner ? SportikaColors.mint : SportikaColors.textMuted,
          ),
        ),
    ],
  );
}

/// Entry list with organizer approve/reject controls.
class TournamentEntriesSection extends StatelessWidget {
  const TournamentEntriesSection({
    super.key,
    required this.tournament,
    this.canManage = false,
  });

  final Tournament tournament;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TournamentsController>();
    context.watch<TournamentsController>();
    final entries = state.entriesFor(tournament.id);
    if (entries.isEmpty) {
      return const EmptyState(
        title: 'No entries yet',
        body: 'Players register individually, as pairs, or as full teams.',
        icon: Icons.person_add_alt,
      );
    }

    final pending = entries
        .where((e) => e.status == EntryStatus.pending)
        .toList();
    final confirmed = entries
        .where((e) => e.status == EntryStatus.confirmed)
        .toList();
    final other = entries
        .where(
          (e) =>
              e.status != EntryStatus.pending &&
              e.status != EntryStatus.confirmed,
        )
        .toList();
    final limit = tournament.registrationLimit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                value: '${confirmed.length}/$limit',
                label: 'Confirmed',
                tone: SportikaColors.mint,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatTile(
                value: '${pending.length}',
                label: 'Awaiting review',
                tone: SportikaColors.gold,
              ),
            ),
          ],
        ),
        if (pending.isNotEmpty) ...[
          const SectionTitle('Awaiting decision'),
          for (final entry in pending)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _EntryCard(
                entry: entry,
                tournament: tournament,
                canManage: canManage,
              ),
            ),
        ],
        SectionTitle('Confirmed ($limit max)'),
        if (confirmed.isEmpty)
          const EmptyState(
            title: 'No confirmed entries',
            body: 'Confirm entries to enable the draw.',
            icon: Icons.group_off_outlined,
          )
        else
          for (final entry in confirmed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _EntryCard(
                entry: entry,
                tournament: tournament,
                canManage: canManage,
              ),
            ),
        if (other.isNotEmpty) ...[
          const SectionTitle('Not playing'),
          for (final entry in other)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _EntryCard(
                entry: entry,
                tournament: tournament,
                canManage: canManage,
              ),
            ),
        ],
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.tournament,
    required this.canManage,
  });

  final Entry entry;
  final Tournament tournament;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final members = entry.memberAccountIds
        .map(
          (id) =>
              context.read<SessionController>().accountById(id)?.displayName,
        )
        .whereType<String>()
        .toList();

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
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
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: SportikaColors.text,
                  ),
                ),
              ),
              StatusPill(
                entry.status.label,
                color: statusColor(entry.status.key),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            entry.squadId == null
                ? 'Individual · ${members.join(', ')}'
                : '${tournament.entryType.label} · ${members.join(', ')}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              color: SportikaColors.textMuted,
            ),
          ),
          if (entry.decisionNote != null && entry.decisionNote!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              entry.decisionNote!,
              style: const TextStyle(fontSize: 11, color: SportikaColors.gold),
            ),
          ],
          if (canManage && entry.status == EntryStatus.pending) ...[
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
        ],
      ),
    );
  }
}
