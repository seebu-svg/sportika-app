import 'package:flutter/material.dart';

import 'package:sportika/features/matches/widgets/cricket_report_projection.dart';
import 'package:sportika/features/matches/widgets/cricket_report_style.dart';
import 'package:sportika/shared/theme/theme.dart';

/// Batting card with fixed numeric columns. The batter column takes the
/// remaining width so a long name truncates instead of squeezing the figures.
class CricketBattingPanel extends StatelessWidget {
  const CricketBattingPanel({super.key, required this.report});

  final CricketInningsReport report;

  @override
  Widget build(BuildContext context) {
    if (report.batting.isEmpty) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CricketSectionHeading('Batting'),
          SizedBox(height: SportikaSpacing.sm),
          CricketReportNote(
            icon: Icons.person_off_outlined,
            text:
                'Player statistics unavailable: the batter was not recorded '
                'with these deliveries.',
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CricketSectionHeading(
          'Batting',
          trailing: report.batting.length == 1
              ? '1 batter'
              : '${report.batting.length} batters',
        ),
        const SizedBox(height: 10),
        const _BattingHeader(),
        const SizedBox(height: 6),
        const CricketRowRule(),
        for (var index = 0; index < report.batting.length; index++) ...[
          if (index > 0) const CricketRowRule(),
          _BattingRow(report.batting[index]),
        ],
      ],
    );
  }
}

class _BattingHeader extends StatelessWidget {
  const _BattingHeader();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Expanded(
        child: Text(
          'BATTER',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: CricketReportType.statLabel,
        ),
      ),
      CricketStatHeading('R', width: CricketStatWidths.runs),
      CricketStatHeading('B', width: CricketStatWidths.balls),
      CricketStatHeading('4s', width: CricketStatWidths.boundaries),
      CricketStatHeading('6s', width: CricketStatWidths.boundaries),
      CricketStatHeading('SR', width: CricketStatWidths.strikeRate),
    ],
  );
}

class _BattingRow extends StatelessWidget {
  const _BattingRow(this.line);

  final CricketBattingLine line;

  @override
  Widget build(BuildContext context) {
    final dismissal = line.notOut ? 'not out' : line.dismissal;
    return Semantics(
      container: true,
      label:
          '${line.name}, $dismissal, ${line.runs} runs off ${line.balls} '
          'balls, strike rate ${line.strikeRate}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      line.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CricketReportType.name,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dismissal,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CricketReportType.meta.copyWith(
                        color: line.notOut
                            ? SportikaColors.mint
                            : SportikaColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              CricketStatCell(
                '${line.runs}',
                width: CricketStatWidths.runs,
                emphasis: true,
              ),
              CricketStatCell('${line.balls}', width: CricketStatWidths.balls),
              CricketStatCell(
                '${line.fours}',
                width: CricketStatWidths.boundaries,
              ),
              CricketStatCell(
                '${line.sixes}',
                width: CricketStatWidths.boundaries,
              ),
              CricketStatCell(
                line.strikeRate,
                width: CricketStatWidths.strikeRate,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bowling card: overs, conceded runs, wickets and economy.
class CricketBowlingPanel extends StatelessWidget {
  const CricketBowlingPanel({super.key, required this.report});

  final CricketInningsReport report;

  @override
  Widget build(BuildContext context) {
    if (report.bowling.isEmpty) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CricketSectionHeading('Bowling'),
          SizedBox(height: SportikaSpacing.sm),
          CricketReportNote(
            icon: Icons.person_off_outlined,
            text: 'No bowler was recorded with these deliveries.',
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CricketSectionHeading(
          'Bowling',
          trailing: report.bowling.length == 1
              ? '1 bowler'
              : '${report.bowling.length} bowlers',
        ),
        const SizedBox(height: 10),
        const Row(
          children: [
            Expanded(
              child: Text(
                'BOWLER',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CricketReportType.statLabel,
              ),
            ),
            CricketStatHeading('O', width: CricketStatWidths.overs),
            CricketStatHeading('R', width: CricketStatWidths.runs),
            CricketStatHeading('W', width: CricketStatWidths.balls),
            CricketStatHeading('ECON', width: CricketStatWidths.economy),
          ],
        ),
        const SizedBox(height: 6),
        const CricketRowRule(),
        for (var index = 0; index < report.bowling.length; index++) ...[
          if (index > 0) const CricketRowRule(),
          _BowlingRow(report.bowling[index]),
        ],
      ],
    );
  }
}

class _BowlingRow extends StatelessWidget {
  const _BowlingRow(this.line);

  final CricketBowlingLine line;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label:
        '${line.name}, ${line.overs} overs, ${line.runs} runs '
        'conceded, ${line.wickets} wickets, economy ${line.economy}',
    child: ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                line.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CricketReportType.name,
              ),
            ),
            CricketStatCell(line.overs, width: CricketStatWidths.overs),
            CricketStatCell('${line.runs}', width: CricketStatWidths.runs),
            CricketStatCell(
              '${line.wickets}',
              width: CricketStatWidths.balls,
              emphasis: line.wickets > 0,
            ),
            CricketStatCell(line.economy, width: CricketStatWidths.economy),
          ],
        ),
      ),
    ),
  );
}

/// Extras breakdown, folded into a single compact line. The total is
/// log-derived, like every other figure here.
class CricketExtrasPanel extends StatelessWidget {
  const CricketExtrasPanel({super.key, required this.report});

  final CricketInningsReport report;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CricketSectionHeading('Extras', trailing: '${report.extrasTotal}'),
      const SizedBox(height: 10),
      Wrap(
        spacing: SportikaSpacing.lg,
        runSpacing: SportikaSpacing.xs,
        children: [
          _ExtraToken(label: 'Wd', value: report.extra('wide')),
          _ExtraToken(label: 'Nb', value: report.extra('noball')),
          _ExtraToken(label: 'B', value: report.extra('bye')),
          _ExtraToken(label: 'Lb', value: report.extra('legbye')),
        ],
      ),
    ],
  );
}

class _ExtraToken extends StatelessWidget {
  const _ExtraToken({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '$label $value',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('$value', style: CricketReportType.stat),
          const SizedBox(width: 4),
          Text(label.toUpperCase(), style: CricketReportType.statLabel),
        ],
      ),
    ),
  );
}

/// Fall of wickets as a readable chronological list, folded by default.
class CricketWicketPanel extends StatelessWidget {
  const CricketWicketPanel({super.key, required this.report});

  final CricketInningsReport report;

  @override
  Widget build(BuildContext context) => CricketCollapsibleSection(
    title: 'Fall of wickets',
    trailing: report.wickets.isEmpty
        ? 'None'
        : report.wickets.length == 1
        ? '1 wicket'
        : '${report.wickets.length} wickets',
    child: report.wickets.isEmpty
        ? const Padding(
            padding: EdgeInsets.only(bottom: SportikaSpacing.sm),
            child: Text(
              'No wickets have fallen in this innings.',
              style: CricketReportType.meta,
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < report.wickets.length; index++) ...[
                if (index > 0) const CricketRowRule(),
                _WicketRow(report.wickets[index]),
              ],
              const SizedBox(height: SportikaSpacing.xs),
            ],
          ),
  );
}

class _WicketRow extends StatelessWidget {
  const _WicketRow(this.wicket);

  final CricketFallOfWicket wicket;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label:
        'Wicket ${wicket.wicket}, ${wicket.score}, ${wicket.batter}, '
        '${wicket.overs} overs',
    child: ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '${wicket.wicket}',
                style: CricketReportType.statStrong.copyWith(
                  color: SportikaColors.danger,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    wicket.batter,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CricketReportType.name,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${wicket.overs} ov',
                    style: CricketReportType.metaFaint,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(wicket.score, style: CricketReportType.stat),
          ],
        ),
      ),
    ),
  );
}

/// Closed and current partnerships, in the order they were built.
class CricketPartnershipPanel extends StatelessWidget {
  const CricketPartnershipPanel({super.key, required this.report});

  final CricketInningsReport report;

  @override
  Widget build(BuildContext context) => CricketCollapsibleSection(
    title: 'Partnerships',
    trailing: report.partnerships.length == 1
        ? '1 stand'
        : '${report.partnerships.length} stands',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < report.partnerships.length; index++) ...[
          if (index > 0) const CricketRowRule(),
          _PartnershipRow(report.partnerships[index]),
        ],
        const SizedBox(height: SportikaSpacing.xs),
      ],
    ),
  );
}

class _PartnershipRow extends StatelessWidget {
  const _PartnershipRow(this.partnership);

  final CricketPartnership partnership;

  @override
  Widget build(BuildContext context) {
    final title = partnership.unbroken
        ? 'Current partnership'
        : 'Wicket ${partnership.wicket}';
    final runs = partnership.runs == 1 ? '1 run' : '${partnership.runs} runs';
    return Semantics(
      container: true,
      label: '$title, $runs',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              if (partnership.unbroken) ...[
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: SportikaColors.mint,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CricketReportType.meta.copyWith(
                    color: partnership.unbroken
                        ? SportikaColors.text
                        : SportikaColors.textMuted,
                    fontWeight: partnership.unbroken
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(runs, style: CricketReportType.stat),
            ],
          ),
        ),
      ),
    );
  }
}

/// Over-by-over run summary for the overs tab.
class CricketOversPanel extends StatelessWidget {
  const CricketOversPanel({super.key, required this.report});

  final CricketInningsReport report;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CricketSectionHeading(
        'Overs',
        trailing: report.overs.length == 1
            ? '1 over'
            : '${report.overs.length} overs',
      ),
      const SizedBox(height: SportikaSpacing.xs),
      for (var index = 0; index < report.overs.length; index++) ...[
        if (index > 0) const CricketRowRule(),
        _OverRow(report.overs[index]),
      ],
    ],
  );
}

class _OverRow extends StatelessWidget {
  const _OverRow(this.over);

  final CricketOverSummary over;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Over ${over.number}', style: CricketReportType.name),
            const SizedBox(width: 8),
            if (over.wickets > 0)
              Text(
                '${over.wickets}W',
                style: CricketReportType.statLabel.copyWith(
                  color: SportikaColors.danger,
                ),
              ),
            const Spacer(),
            Text(over.runsLabel, style: CricketReportType.meta),
          ],
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final delivery in over.deliveries)
              CricketRunBadge(delivery.label, tone: _tone(delivery)),
          ],
        ),
      ],
    ),
  );
}

CricketRunTone _tone(CricketDelivery delivery) {
  if (delivery.isWicket) return CricketRunTone.wicket;
  if (delivery.isBoundary) return CricketRunTone.boundary;
  if (delivery.isExtra) return CricketRunTone.extra;
  return CricketRunTone.neutral;
}

/// Ball-by-ball commentary, newest delivery first, grouped by over.
class CricketCommentaryPanel extends StatelessWidget {
  const CricketCommentaryPanel({super.key, required this.report});

  final CricketInningsReport report;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const CricketSectionHeading('Commentary', trailing: 'Newest first'),
      const SizedBox(height: SportikaSpacing.xs),
      for (var index = 0; index < report.recentOvers.length; index++)
        _CommentaryOver(
          report.recentOvers[index],
          last: index == report.recentOvers.length - 1,
        ),
    ],
  );
}

class _CommentaryOver extends StatelessWidget {
  const _CommentaryOver(this.over, {required this.last});

  final CricketOverSummary over;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final deliveries = over.deliveries.reversed.toList();
    return Padding(
      padding: EdgeInsets.only(top: 16, bottom: last ? 0 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'OVER ${over.number}',
                style: CricketReportType.statLabel.copyWith(
                  color: SportikaColors.textMuted,
                ),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              const Expanded(child: CricketRowRule()),
            ],
          ),
          for (var index = 0; index < deliveries.length; index++) ...[
            if (index > 0) const CricketRowRule(),
            _DeliveryRow(deliveries[index]),
          ],
        ],
      ),
    );
  }
}

class _DeliveryRow extends StatelessWidget {
  const _DeliveryRow(this.delivery);

  final CricketDelivery delivery;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '${delivery.position}, ${delivery.headline}, ${delivery.summary}',
    child: ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 30,
              child: Text(
                delivery.position,
                style: CricketReportType.metaFaint,
              ),
            ),
            CricketRunBadge(delivery.label, tone: _tone(delivery)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    delivery.headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CricketReportType.name.copyWith(fontSize: 12.5),
                  ),
                  const SizedBox(height: 2),
                  Text(delivery.summary, style: CricketReportType.meta),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
