import 'dart:math' as math;

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

// ============================================================
// SHARED TOURNAMENT PRESENTATION
// ============================================================

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    this.eyebrow,
    this.count,
    this.icon,
  });

  final String title;
  final String? eyebrow;
  final int? count;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 14),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: SportikaColors.mint, size: 22),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!,
                    style: SportikaType.micro.copyWith(
                      color: SportikaColors.mint,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(title, style: SportikaType.title),
              ],
            ),
          ),
          if (count != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: SportikaColors.surfaceElevated,
                borderRadius: BorderRadius.circular(SportikaRadius.badge),
                border: Border.all(color: SportikaColors.borderSubtle),
              ),
              child: Text('$count', style: SportikaType.caption),
            ),
        ],
      ),
    );
  }
}

class _MetricStrip extends StatelessWidget {
  const _MetricStrip({required this.items});

  final List<({String label, String value})> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Container(
              width: 1,
              height: 38,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: SportikaColors.borderSubtle,
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  items[i].value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.scoreSmall,
                ),
                const SizedBox(height: 5),
                Text(
                  items[i].label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.micro,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================
// FIXTURES / MATCH CENTER
// ============================================================

class TournamentFixturesSection extends StatelessWidget {
  const TournamentFixturesSection({
    super.key,
    required this.tournament,
    this.status,
  });

  final Tournament tournament;
  final FixtureStatus? status;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TournamentsController>();
    final fixturesController = context.watch<FixturesController>();

    final fixtures = fixturesController.fixturesFor(tournament.id);

    if (status != null) {
      final filtered = fixtures.where((fixture) {
        return fixture.status == status ||
            (status == FixtureStatus.published &&
                fixture.status == FixtureStatus.walkover);
      }).toList()..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

      if (filtered.isEmpty) {
        return EmptyState(
          title: status == FixtureStatus.live
              ? 'No live matches right now'
              : status == FixtureStatus.published
              ? 'No official results yet'
              : 'No upcoming fixtures',
          body: status == FixtureStatus.published
              ? 'Results appear after the organizer publishes them.'
              : 'Check the competition schedule for the latest fixtures.',
          icon: Icons.sports_outlined,
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MatchSummary(fixtures: filtered),
          const SizedBox(height: 16),
          for (final fixture in filtered)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: officialFixtureTile(context, fixture),
            ),
        ],
      );
    }

    if (fixtures.isEmpty) {
      return EmptyState(
        title: tournament.status == TournamentStatus.open
            ? 'Draw not published'
            : 'No fixtures yet',
        body: tournament.status == TournamentStatus.open
            ? 'The organizer publishes fixtures once enough entries are confirmed.'
            : 'Fixtures appear once the organizer publishes the draw.',
        icon: Icons.account_tree_outlined,
      );
    }

    final live = fixtures.where((f) => f.status == FixtureStatus.live).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    final results = fixtures
        .where(
          (f) =>
              f.status == FixtureStatus.published ||
              f.status == FixtureStatus.walkover,
        )
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SurfaceCard(
          child: _MetricStrip(
            items: [
              (label: 'Total matches', value: '${fixtures.length}'),
              (label: 'Live now', value: '${live.length}'),
              (label: 'Official results', value: '$results'),
            ],
          ),
        ),

        if (live.isNotEmpty) ...[
          _SectionHeading(
            title: 'Live right now',
            eyebrow: 'MATCH CENTER',
            icon: Icons.sensors_rounded,
            count: live.length,
          ),
          for (final fixture in live)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: officialFixtureTile(context, fixture),
            ),
        ],

        if (tournament.format == TournamentFormat.group)
          _GroupFixtures(fixtures: fixtures, excludeLive: live.isNotEmpty)
        else
          _RoundFixtures(
            rounds: state.roundsFor(tournament),
            excludeLive: live.isNotEmpty,
          ),
      ],
    );
  }
}

class _MatchSummary extends StatelessWidget {
  const _MatchSummary({required this.fixtures});

  final List<Fixture> fixtures;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.sports_score_outlined,
          color: SportikaColors.mint,
          size: 18,
        ),
        const SizedBox(width: 8),
        Text(
          '${fixtures.length} ${fixtures.length == 1 ? 'match' : 'matches'}',
          style: SportikaType.bodyStrong,
        ),
      ],
    );
  }
}

class _GroupFixtures extends StatelessWidget {
  const _GroupFixtures({required this.fixtures, required this.excludeLive});

  final List<Fixture> fixtures;
  final bool excludeLive;

  @override
  Widget build(BuildContext context) {
    final byGroup = <String, List<Fixture>>{};

    for (final fixture in fixtures) {
      byGroup.putIfAbsent(fixture.group ?? 'A', () => []).add(fixture);
    }

    final letters = byGroup.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final letter in letters)
          _FixtureCollection(
            title: 'Group $letter',
            eyebrow: 'GROUP STAGE',
            fixtures: byGroup[letter]!,
            excludeLive: excludeLive,
          ),
      ],
    );
  }
}

class _RoundFixtures extends StatelessWidget {
  const _RoundFixtures({required this.rounds, required this.excludeLive});

  final List<List<Fixture>> rounds;
  final bool excludeLive;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final round in rounds)
          if (round.isNotEmpty)
            _FixtureCollection(
              title: round.first.stage,
              eyebrow: 'KNOCKOUT STAGE',
              fixtures: round,
              excludeLive: excludeLive,
            ),
      ],
    );
  }
}

class _FixtureCollection extends StatefulWidget {
  const _FixtureCollection({
    required this.title,
    required this.eyebrow,
    required this.fixtures,
    required this.excludeLive,
  });

  final String title;
  final String eyebrow;
  final List<Fixture> fixtures;
  final bool excludeLive;

  @override
  State<_FixtureCollection> createState() => _FixtureCollectionState();
}

class _FixtureCollectionState extends State<_FixtureCollection> {
  bool expanded = true;

  @override
  Widget build(BuildContext context) {
    final visible = widget.fixtures.where((fixture) {
      return !widget.excludeLive || fixture.status != FixtureStatus.live;
    }).toList()..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    if (visible.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() => expanded = !expanded);
          },
          borderRadius: BorderRadius.circular(SportikaRadius.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 30,
                  decoration: BoxDecoration(
                    color: SportikaColors.mint,
                    borderRadius: BorderRadius.circular(SportikaRadius.badge),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.eyebrow,
                        style: SportikaType.micro.copyWith(
                          color: SportikaColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(widget.title, style: SportikaType.bodyStrong),
                    ],
                  ),
                ),
                Text('${visible.length}', style: SportikaType.caption),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: expanded ? 0 : -0.5,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: SportikaColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Column(
            children: [
              for (final fixture in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: officialFixtureTile(context, fixture),
                ),
            ],
          ),
          crossFadeState: expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}

// ============================================================
// BRACKET / STANDINGS ENTRYPOINT
// ============================================================

class TournamentBracket extends StatelessWidget {
  const TournamentBracket({super.key, required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final fixturesController = context.watch<FixturesController>();

    if (fixturesController.fixturesFor(tournament.id).isEmpty) {
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

// ============================================================
// BROADCAST-STYLE STANDINGS
// ============================================================

class _StandingsTable extends StatelessWidget {
  const _StandingsTable({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TournamentsController>();
    context.watch<FixturesController>();

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
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.leaderboard_outlined,
                    color: SportikaColors.mint,
                    size: 20,
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'OFFICIAL STANDINGS',
                      style: SportikaType.micro,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Team identity remains visible while the numerical
              // columns can scroll on smaller screens.
              LayoutBuilder(
                builder: (context, constraints) {
                  final teamWidth = math.min(
                    150.0,
                    math.max(105.0, constraints.maxWidth * 0.38),
                  );

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: teamWidth,
                        child: Column(
                          children: [
                            const _StandingTeamHeader(),
                            for (final row in rows) _StandingTeamCell(row: row),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Column(
                            children: [
                              const _StandingNumbersHeader(),
                              for (final row in rows)
                                _StandingNumbersRow(row: row),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: SportikaColors.mint,
                borderRadius: BorderRadius.circular(SportikaRadius.badge),
              ),
            ),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                'Mint indicates a qualifying position. '
                'Only published results affect standings.',
                style: SportikaType.caption,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StandingTeamHeader extends StatelessWidget {
  const _StandingTeamHeader();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 36,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text('TEAM', style: SportikaType.micro),
      ),
    );
  }
}

class _StandingTeamCell extends StatelessWidget {
  const _StandingTeamCell({required this.row});

  final StandingRow row;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Container(
            width: 3,
            height: 30,
            decoration: BoxDecoration(
              color: row.qualifies
                  ? SportikaColors.mint
                  : SportikaColors.borderSubtle,
              borderRadius: BorderRadius.circular(SportikaRadius.badge),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${row.position}',
            style: SportikaType.caption.copyWith(
              color: row.qualifies
                  ? SportikaColors.mint
                  : SportikaColors.textMuted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              row.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SportikaType.bodyStrong.copyWith(
                color: row.qualifies
                    ? SportikaColors.text
                    : SportikaColors.textBody,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _StandingNumbersHeader extends StatelessWidget {
  const _StandingNumbersHeader();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 36,
      child: Row(
        children: [
          _StandingNumberCell('P', header: true),
          _StandingNumberCell('W', header: true),
          _StandingNumberCell('D', header: true),
          _StandingNumberCell('L', header: true),
          _StandingNumberCell('DIFF', header: true, wide: true),
          _StandingNumberCell('PTS', header: true, wide: true),
        ],
      ),
    );
  }
}

class _StandingNumbersRow extends StatelessWidget {
  const _StandingNumbersRow({required this.row});

  final StandingRow row;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          _StandingNumberCell('${row.played}'),
          _StandingNumberCell('${row.won}'),
          _StandingNumberCell('${row.drawn}'),
          _StandingNumberCell('${row.lost}'),
          _StandingNumberCell(
            row.diff > 0 ? '+${row.diff}' : '${row.diff}',
            wide: true,
          ),
          _StandingNumberCell(
            '${row.points}',
            wide: true,
            emphasized: true,
            qualified: row.qualifies,
          ),
        ],
      ),
    );
  }
}

class _StandingNumberCell extends StatelessWidget {
  const _StandingNumberCell(
    this.value, {
    this.header = false,
    this.wide = false,
    this.emphasized = false,
    this.qualified = false,
  });

  final String value;
  final bool header;
  final bool wide;
  final bool emphasized;
  final bool qualified;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: wide ? 52 : 36,
      child: Center(
        child: Text(
          value,
          textAlign: TextAlign.center,
          style: header
              ? SportikaType.micro
              : emphasized
              ? SportikaType.bodyStrong.copyWith(
                  color: qualified ? SportikaColors.mint : SportikaColors.text,
                )
              : SportikaType.caption,
        ),
      ),
    );
  }
}

// ============================================================
// CONNECTED KNOCKOUT BRACKET
// ============================================================

class _Bracket extends StatelessWidget {
  const _Bracket({required this.tournament});

  final Tournament tournament;

  static const double _columnWidth = 224;
  static const double _columnGap = 42;
  static const double _cardHeight = 112;
  static const double _baseStep = 138;
  static const double _headerHeight = 62;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TournamentsController>();
    context.watch<FixturesController>();

    final rounds = state
        .roundsFor(tournament)
        .where((round) => round.isNotEmpty)
        .toList();

    if (rounds.isEmpty) {
      return const EmptyState(
        title: 'Bracket unavailable',
        body: 'The organizer has not published a knockout draw.',
        icon: Icons.account_tree_outlined,
      );
    }

    final firstCount = rounds.first.length;

    // Vertical spacing follows the progression of the draw.
    // Only draw connectors when the next round has the
    // expected number of matches.
    double centerFor(int roundIndex, int matchIndex) {
      final scale = math.pow(2, roundIndex).toDouble();

      return _headerHeight +
          (_baseStep * scale * (matchIndex + 0.5)) -
          (_baseStep / 2);
    }

    final totalWidth =
        rounds.length * _columnWidth + (rounds.length - 1) * _columnGap;

    double totalHeight = _headerHeight + _cardHeight;

    for (var r = 0; r < rounds.length; r++) {
      final lastCenter = centerFor(r, rounds[r].length - 1);
      totalHeight = math.max(totalHeight, lastCenter + _cardHeight / 2 + 18);
    }

    totalHeight = math.max(
      totalHeight,
      _headerHeight + firstCount * _baseStep + _cardHeight / 2,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.account_tree_outlined,
              color: SportikaColors.mint,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${rounds.length} knockout rounds',
                style: SportikaType.bodyStrong,
              ),
            ),
            const Icon(
              Icons.swipe_rounded,
              color: SportikaColors.textMuted,
              size: 18,
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Swipe horizontally to explore the draw. '
          'Tap any match for its details.',
          style: SportikaType.caption,
        ),
        const SizedBox(height: 18),

        ClipRRect(
          borderRadius: BorderRadius.circular(SportikaRadius.xl),
          child: Container(
            color: SportikaColors.surface,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth + 24,
                height: totalHeight,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _BracketConnectorPainter(
                          roundSizes: [
                            for (final round in rounds) round.length,
                          ],
                          columnWidth: _columnWidth,
                          columnGap: _columnGap,
                          cardHeight: _cardHeight,
                          centerFor: centerFor,
                          color: SportikaColors.border,
                        ),
                      ),
                    ),
                    for (var r = 0; r < rounds.length; r++) ...[
                      Positioned(
                        left: r * (_columnWidth + _columnGap) + 12,
                        top: 12,
                        width: _columnWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rounds[r].first.stage.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SportikaType.micro.copyWith(
                                color: r == rounds.length - 1
                                    ? SportikaColors.gold
                                    : SportikaColors.textMuted,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${rounds[r].length} '
                              '${rounds[r].length == 1 ? 'match' : 'matches'}',
                              style: SportikaType.caption,
                            ),
                          ],
                        ),
                      ),
                      for (var m = 0; m < rounds[r].length; m++)
                        Positioned(
                          left: r * (_columnWidth + _columnGap) + 12,
                          top: centerFor(r, m) - _cardHeight / 2,
                          width: _columnWidth,
                          height: _cardHeight,
                          child: _BracketCard(
                            fixture: rounds[r][m],
                            isFinal: r == rounds.length - 1,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BracketConnectorPainter extends CustomPainter {
  const _BracketConnectorPainter({
    required this.roundSizes,
    required this.columnWidth,
    required this.columnGap,
    required this.cardHeight,
    required this.centerFor,
    required this.color,
  });

  final List<int> roundSizes;
  final double columnWidth;
  final double columnGap;
  final double cardHeight;
  final double Function(int roundIndex, int matchIndex) centerFor;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (var r = 0; r < roundSizes.length - 1; r++) {
      final currentCount = roundSizes[r];
      final nextCount = roundSizes[r + 1];

      if (currentCount != nextCount * 2) continue;

      final sourceX = 12 + r * (columnWidth + columnGap) + columnWidth;

      final targetX = 12 + (r + 1) * (columnWidth + columnGap);

      final middleX = (sourceX + targetX) / 2;

      for (var next = 0; next < nextCount; next++) {
        final firstY = centerFor(r, next * 2);
        final secondY = centerFor(r, next * 2 + 1);
        final targetY = centerFor(r + 1, next);

        final path = Path()
          ..moveTo(sourceX, firstY)
          ..lineTo(middleX, firstY)
          ..lineTo(middleX, secondY)
          ..lineTo(sourceX, secondY)
          ..moveTo(middleX, targetY)
          ..lineTo(targetX, targetY);

        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BracketConnectorPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.roundSizes.length != roundSizes.length ||
        !oldDelegate.roundSizes.asMap().entries.every(
          (entry) => entry.value == roundSizes[entry.key],
        );
  }
}

class _BracketCard extends StatelessWidget {
  const _BracketCard({required this.fixture, required this.isFinal});

  final Fixture fixture;
  final bool isFinal;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FixturesController>();
    final sides = controller.sideLabelsOf(fixture);
    final result = fixture.result;

    final official =
        fixture.status == FixtureStatus.published ||
        fixture.status == FixtureStatus.walkover;

    final winner = official ? result?.winnerIndex ?? -1 : -1;

    final scores = official
        ? result?.sideScores ?? const <String>[]
        : const <String>[];

    final tone = isFinal
        ? SportikaColors.gold
        : fixture.status == FixtureStatus.live
        ? SportikaColors.mint
        : official
        ? SportikaColors.mint
        : SportikaColors.border;

    final first = sides.isNotEmpty ? sides[0] : 'TBD';
    final second = sides.length > 1 ? sides[1] : 'TBD';

    return Material(
      color: SportikaColors.surfaceElevated,
      borderRadius: BorderRadius.circular(SportikaRadius.control),
      child: InkWell(
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        onTap: () => pushRoute(
          context,
          AppRoute.fixtureDetail,
          args: FixtureDetailArgs(fixture.id),
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SportikaRadius.control),
            border: Border.all(
              color: tone.withValues(alpha: isFinal ? 0.75 : 0.38),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isFinal) ...[
                    const Icon(
                      Icons.emoji_events_outlined,
                      color: SportikaColors.gold,
                      size: 13,
                    ),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: Text(
                      isFinal ? 'CHAMPIONSHIP FINAL' : fixture.stage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SportikaType.micro.copyWith(
                        color: isFinal
                            ? SportikaColors.gold
                            : SportikaColors.textMuted,
                      ),
                    ),
                  ),
                  if (fixture.status == FixtureStatus.live)
                    const Icon(
                      Icons.sensors_rounded,
                      color: SportikaColors.mint,
                      size: 15,
                    ),
                ],
              ),
              const SizedBox(height: 9),
              _BracketSide(
                label: first,
                score: scores.isNotEmpty ? scores[0] : '',
                winner: winner == 0,
              ),
              const SizedBox(height: 5),
              _BracketSide(
                label: second,
                score: scores.length > 1 ? scores[1] : '',
                winner: winner == 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BracketSide extends StatelessWidget {
  const _BracketSide({
    required this.label,
    required this.score,
    required this.winner,
  });

  final String label;
  final String score;
  final bool winner;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 18,
          decoration: BoxDecoration(
            color: winner ? SportikaColors.mint : SportikaColors.borderSubtle,
            borderRadius: BorderRadius.circular(SportikaRadius.badge),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SportikaType.caption.copyWith(
              color: winner ? SportikaColors.text : SportikaColors.textBody,
              fontWeight: winner
                  ? SportikaFontWeight.extraBold
                  : SportikaFontWeight.semibold,
            ),
          ),
        ),
        if (score.isNotEmpty)
          Text(
            score,
            style: SportikaType.bodyStrong.copyWith(
              color: winner ? SportikaColors.mint : SportikaColors.textMuted,
            ),
          ),
      ],
    );
  }
}

// ============================================================
// PARTICIPANT ROSTER
// ============================================================

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
    context.watch<SessionController>();

    final entries = state.entriesFor(tournament.id);

    if (entries.isEmpty) {
      return const EmptyState(
        title: 'No entries yet',
        body: 'Players register individually, as pairs, or as full teams.',
        icon: Icons.person_add_alt,
      );
    }

    final pending = entries
        .where((entry) => entry.status == EntryStatus.pending)
        .toList();

    final confirmed = entries
        .where((entry) => entry.status == EntryStatus.confirmed)
        .toList();

    final other = entries
        .where(
          (entry) =>
              entry.status != EntryStatus.pending &&
              entry.status != EntryStatus.confirmed,
        )
        .toList();

    final limit = tournament.registrationLimit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.groups_2_outlined,
                    color: SportikaColors.mint,
                    size: 22,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('TOURNAMENT ROSTER', style: SportikaType.micro),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _MetricStrip(
                items: [
                  (
                    label: 'Confirmed',
                    value: limit > 0
                        ? '${confirmed.length}/$limit'
                        : '${confirmed.length}',
                  ),
                  (label: 'Pending', value: '${pending.length}'),
                  (label: 'Total entries', value: '${entries.length}'),
                ],
              ),
              if (limit > 0) ...[
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(SportikaRadius.badge),
                  child: LinearProgressIndicator(
                    value: (confirmed.length / limit).clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: SportikaColors.border,
                    color: SportikaColors.mint,
                  ),
                ),
              ],
            ],
          ),
        ),

        if (pending.isNotEmpty) ...[
          _SectionHeading(
            title: canManage
                ? 'Awaiting your decision'
                : 'Awaiting confirmation',
            eyebrow: 'PENDING ENTRIES',
            count: pending.length,
          ),
          _RosterCollection(
            entries: pending,
            tournament: tournament,
            canManage: canManage,
          ),
        ],

        _SectionHeading(
          title: 'Confirmed participants',
          eyebrow: 'OFFICIAL ROSTER',
          count: confirmed.length,
        ),

        if (confirmed.isEmpty)
          const EmptyState(
            title: 'No confirmed entries',
            body: 'Confirmed participants will appear here.',
            icon: Icons.group_off_outlined,
          )
        else
          _RosterCollection(
            entries: confirmed,
            tournament: tournament,
            canManage: canManage,
          ),

        if (other.isNotEmpty) ...[
          _SectionHeading(
            title: 'Other entries',
            eyebrow: 'ENTRY HISTORY',
            count: other.length,
          ),
          _RosterCollection(
            entries: other,
            tournament: tournament,
            canManage: canManage,
          ),
        ],
      ],
    );
  }
}

class _RosterCollection extends StatelessWidget {
  const _RosterCollection({
    required this.entries,
    required this.tournament,
    required this.canManage,
  });

  final List<Entry> entries;
  final Tournament tournament;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0)
              const Divider(color: SportikaColors.borderSubtle, height: 1),
            _EntryCard(
              entry: entries[i],
              tournament: tournament,
              canManage: canManage,
            ),
          ],
        ],
      ),
    );
  }
}

class _EntryCard extends StatefulWidget {
  const _EntryCard({
    required this.entry,
    required this.tournament,
    required this.canManage,
  });

  final Entry entry;
  final Tournament tournament;
  final bool canManage;

  @override
  State<_EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<_EntryCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final session = context.watch<SessionController>();

    final accounts = entry.memberAccountIds
        .map(session.accountById)
        .whereType<Account>()
        .toList();

    final memberNames = accounts
        .map((account) => account.displayName)
        .join(' · ');

    final tone = statusColor(entry.status.key);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RosterAvatarStack(accounts: accounts),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SportikaType.bodyStrong,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.squadId == null
                          ? memberNames.isEmpty
                                ? 'Individual entry'
                                : memberNames
                          : '${widget.tournament.entryType.label}'
                                '${memberNames.isEmpty ? '' : ' · $memberNames'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SportikaType.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(entry.status.label, color: tone),
            ],
          ),
          if (entry.decisionNote != null && entry.decisionNote!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              entry.decisionNote!,
              style: SportikaType.caption.copyWith(color: SportikaColors.gold),
            ),
          ],
          if (widget.canManage && entry.status == EntryStatus.pending) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    label: 'Confirm',
                    icon: Icons.check_rounded,
                    small: true,
                    tone: SportikaColors.mint,
                    busy: _busy,
                    onPressed: _busy ? null : () => _decide(approve: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GhostButton(
                    label: 'Reject',
                    tone: SportikaColors.danger,
                    expand: true,
                    onPressed: _busy ? null : () => _decide(approve: false),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _decide({required bool approve}) async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      await context.read<TournamentsController>().decideEntry(
        widget.entry.id,
        approve: approve,
        note: approve ? null : 'Entry did not meet the tournament requirements',
      );

      if (mounted) {
        showSnack(
          context,
          '${widget.entry.label} '
          '${approve ? 'confirmed' : 'rejected'}',
        );
      }
    } catch (_) {
      if (mounted) {
        showSnack(
          context,
          'The entry could not be updated. Please try again.',
          error: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

class _RosterAvatarStack extends StatelessWidget {
  const _RosterAvatarStack({required this.accounts});

  final List<Account> accounts;

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) {
      return Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: SportikaColors.surfaceElevated,
          borderRadius: BorderRadius.circular(SportikaRadius.control),
        ),
        child: const Icon(
          Icons.person_outline_rounded,
          color: SportikaColors.textMuted,
        ),
      );
    }

    final visible = accounts.take(3).toList();

    if (visible.length == 1) {
      return AccountAvatar(account: visible.first, size: 46);
    }

    return SizedBox(
      width: 66,
      height: 46,
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * 10.0,
              top: 3,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: SportikaColors.surface,
                  shape: BoxShape.circle,
                ),
                child: AccountAvatar(account: visible[i], size: 36),
              ),
            ),
          if (accounts.length > 3)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: SportikaColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(SportikaRadius.badge),
                ),
                child: Text(
                  '+${accounts.length - 3}',
                  style: SportikaType.micro,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
