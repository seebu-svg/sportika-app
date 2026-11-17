import 'package:flutter/material.dart';

import 'package:sportika/features/matches/widgets/cricket_report_panels.dart';
import 'package:sportika/features/matches/widgets/cricket_report_projection.dart';
import 'package:sportika/features/matches/widgets/cricket_report_style.dart';
import 'package:sportika/features/personal_games/scoring/cricket/cricket.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/widgets.dart';

export 'package:sportika/features/matches/widgets/cricket_report_projection.dart';

/// The cricket match centre: a two-team scoreboard, the official result and
/// three views of one innings.
///
/// Presentation only. The official scores, result and status come from
/// [MatchProgress] and the published [SportMatch.result]; every player figure
/// is projected from the recorded deliveries, so the two are never mixed up.
class CricketMatchReport extends StatefulWidget {
  const CricketMatchReport({
    super.key,
    required this.match,
    required this.progress,
  });

  final SportMatch match;
  final MatchProgress progress;

  @override
  State<CricketMatchReport> createState() => _CricketMatchReportState();
}

enum _ReportView { scorecard, overs, commentary }

extension on _ReportView {
  String get label => switch (this) {
    _ReportView.scorecard => 'Scorecard',
    _ReportView.overs => 'Overs',
    _ReportView.commentary => 'Commentary',
  };
}

class _CricketMatchReportState extends State<CricketMatchReport> {
  _ReportView _view = _ReportView.scorecard;
  late int _side;
  late int _batSide;

  @override
  void initState() {
    super.initState();
    _batSide = _currentBatSide();
    _side = _batSide;
  }

  @override
  void didUpdateWidget(covariant CricketMatchReport oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new innings opens while the scorer keeps working: follow it instead of
    // leaving the reader on a finished one.
    final batSide = _currentBatSide();
    if (batSide != _batSide) {
      _batSide = batSide;
      _side = batSide;
    }
  }

  int _currentBatSide() {
    final side = widget.progress.state['batSide'];
    return side == 1 ? 1 : 0;
  }

  /// Innings order follows the first delivery in the log, not the side index.
  List<int> get _inningsOrder {
    final deliveries =
        widget.match.events
            .where((e) => !e.voided && e.kind == CricketEngine.kBall)
            .toList()
          ..sort((a, b) => a.seq.compareTo(b.seq));
    if (deliveries.isEmpty) return const [0, 1];
    final first = deliveries.first.side == 1 ? 1 : 0;
    return [first, 1 - first];
  }

  String _sideName(int side) =>
      side < widget.match.sideNames.length &&
          widget.match.sideNames[side].isNotEmpty
      ? widget.match.sideNames[side]
      : (side == 0 ? 'Side A' : 'Side B');

  /// Published results win; otherwise the engine fold is the official read.
  String _officialScore(int side, List<String> lines) {
    final result = widget.match.result;
    if (result != null &&
        side < result.sideScores.length &&
        result.sideScores[side].trim().isNotEmpty) {
      return _display(result.sideScores[side]);
    }
    if (side < lines.length) return _display(lines[side]);
    return '—';
  }

  static String _display(String raw) {
    final text = raw.trim();
    return text.isEmpty || text == '-' ? '—' : text;
  }

  /// Overs and close reason are delivery-log facts. They are only shown while
  /// the fold still agrees with the official result.
  String? _scoreDetail(int side) {
    final result = widget.match.result;
    final foldAgrees =
        result == null ||
        (!result.walkover &&
            result.sideScores.join('|') ==
                widget.progress.scoreDisplay.join('|'));
    if (!foldAgrees || side >= widget.progress.lines.length) return null;
    final sub = widget.progress.lines[side].sub?.trim();
    return sub == null || sub.isEmpty ? null : sub;
  }

  /// True while the fold marks this side as the one batting.
  bool _isBatting(int side) =>
      widget.progress.lines.length > side &&
      widget.progress.lines[side].leading;

  String? get _resultText {
    final result = widget.match.result;
    if (result != null && result.headline.trim().isNotEmpty) {
      return result.headline.trim();
    }
    if (widget.progress.isComplete &&
        widget.progress.resultLabel.trim().isNotEmpty) {
      return widget.progress.resultLabel.trim();
    }
    return null;
  }

  void _select(_ReportView view) {
    if (_view == view) return;
    setState(() => _view = view);
  }

  void _selectSide(int side) {
    if (_side == side) return;
    setState(() => _side = side);
  }

  @override
  Widget build(BuildContext context) {
    final order = _inningsOrder;
    final side = order.contains(_side) ? _side : order.first;
    final report = CricketInningsReport(
      CricketInningsReport.deliveries(widget.match, side),
    );
    final lines = [for (final l in widget.progress.lines) l.value];
    return ClampedTextScale(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ScoreHeader(
            match: widget.match,
            rows: [
              for (var index = 0; index < 2; index++)
                _ScoreLineData(
                  name: _sideName(index),
                  score: _officialScore(index, lines),
                  detail: _scoreDetail(index),
                  batting: _isBatting(index),
                ),
            ],
            result: _resultText,
            official: widget.match.result != null,
            corrected: widget.match.corrections.isNotEmpty,
          ),
          const SizedBox(height: SportikaSpacing.md),
          _InningsSelector(
            options: [
              for (var index = 0; index < order.length; index++)
                _InningsOption(
                  label: index == 0 ? '1st innings' : '2nd innings',
                  side: _sideName(order[index]),
                  score: _officialScore(order[index], lines),
                  batting: _isBatting(order[index]),
                  selected: order[index] == side,
                  onTap: () => _selectSide(order[index]),
                ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.xs),
          _ReportNavigation(selected: _view, onSelect: _select),
          const SizedBox(height: SportikaSpacing.md + 2),
          if (report.isEmpty)
            const CricketEmptyPanel(
              title: 'Nothing recorded yet',
              body:
                  'No deliveries have been logged in this innings. '
                  'The card fills in as the innings is scored.',
            )
          else
            switch (_view) {
              _ReportView.scorecard => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  CricketBattingPanel(report: report),
                  const CricketHairline(),
                  CricketBowlingPanel(report: report),
                  const CricketHairline(),
                  CricketExtrasPanel(report: report),
                  const CricketHairline(vertical: 12),
                  CricketWicketPanel(report: report),
                  const CricketHairline(vertical: 12),
                  CricketPartnershipPanel(report: report),
                ],
              ),
              _ReportView.overs => CricketOversPanel(report: report),
              _ReportView.commentary => CricketCommentaryPanel(report: report),
            },
        ],
      ),
    );
  }
}

/// The hero block: compact status, both scores at display size and the
/// official result. The only raised surface in the sheet.
class _ScoreHeader extends StatelessWidget {
  const _ScoreHeader({
    required this.match,
    required this.rows,
    required this.result,
    required this.official,
    required this.corrected,
  });

  final SportMatch match;
  final List<_ScoreLineData> rows;
  final String? result;
  final bool official;
  final bool corrected;

  @override
  Widget build(BuildContext context) {
    final paused = match.isLive && match.isPaused;
    final tone = paused ? SportikaColors.gold : statusColor(match.status.key);
    // Only dim a side once another side is actually batting on it.
    final batting = rows.any((row) => row.batting);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: SportikaColors.surface,
        borderRadius: BorderRadius.circular(SportikaRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'SCORECARD',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CricketReportType.eyebrow,
                ),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              StatusPill(
                paused ? 'Paused' : match.status.label,
                color: tone,
                icon: paused
                    ? Icons.pause_rounded
                    : statusIcon(match.status.key),
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.sm),
          for (final row in rows) _ScoreLine(data: row, dimUnbatting: batting),
          if (result != null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: CricketRowRule(),
            ),
            _ResultLine(text: result!, official: official),
          ],
          if (corrected) ...[
            const SizedBox(height: 10),
            const CricketReportNote(
              icon: Icons.history_rounded,
              tone: SportikaColors.gold,
              text:
                  'The official result was corrected. Every figure below '
                  'comes from the delivery log.',
            ),
          ],
        ],
      ),
    );
  }
}

class _ScoreLineData {
  const _ScoreLineData({
    required this.name,
    required this.score,
    required this.batting,
    this.detail,
  });

  final String name;
  final String score;
  final String? detail;
  final bool batting;
}

/// One side of the scoreboard. The batting side carries a mint rule, matching
/// the live/active meaning of that accent everywhere else in the app.
class _ScoreLine extends StatelessWidget {
  const _ScoreLine({required this.data, required this.dimUnbatting});

  final _ScoreLineData data;
  final bool dimUnbatting;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label:
        '${data.name}, ${data.score}'
        '${data.detail == null ? '' : ', ${data.detail}'}',
    child: ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3,
              height: 22,
              margin: const EdgeInsets.only(top: 3),
              decoration: BoxDecoration(
                color: data.batting ? SportikaColors.mint : Colors.transparent,
                borderRadius: BorderRadius.circular(SportikaRadius.pill),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    data.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CricketReportType.name.copyWith(
                      fontSize: 14.5,
                      color: data.batting || !dimUnbatting
                          ? SportikaColors.text
                          : SportikaColors.textMuted,
                    ),
                  ),
                  if (data.detail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      data.detail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: CricketReportType.metaFaint,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              flex: 4,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  data.score,
                  maxLines: 1,
                  style: CricketReportType.score,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The official result, or the engine result while the match is unpublished.
class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.text, required this.official});

  final String text;
  final bool official;

  @override
  Widget build(BuildContext context) {
    final tone = official ? SportikaColors.gold : SportikaColors.textDim;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            official ? Icons.verified_rounded : Icons.sports_score_outlined,
            size: 15,
            color: tone,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                official ? 'OFFICIAL RESULT' : 'RESULT',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CricketReportType.statLabel.copyWith(color: tone),
              ),
              const SizedBox(height: 3),
              Text(text, style: CricketReportType.result),
            ],
          ),
        ),
      ],
    );
  }
}

class _InningsOption {
  const _InningsOption({
    required this.label,
    required this.side,
    required this.score,
    required this.batting,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String side;
  final String score;
  final bool batting;
  final bool selected;
  final VoidCallback onTap;
}

/// Compact innings switch: the selected innings lifts onto a raised segment
/// and the batting side carries a mint dot.
class _InningsSelector extends StatelessWidget {
  const _InningsSelector({required this.options});

  final List<_InningsOption> options;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: SportikaColors.surfaceSunken,
      borderRadius: BorderRadius.circular(SportikaRadius.md),
    ),
    child: Row(
      children: [
        for (var index = 0; index < options.length; index++) ...[
          if (index > 0) const SizedBox(width: 3),
          Expanded(child: _InningsSegment(option: options[index])),
        ],
      ],
    ),
  );
}

class _InningsSegment extends StatelessWidget {
  const _InningsSegment({required this.option});

  final _InningsOption option;

  @override
  Widget build(BuildContext context) {
    final selected = option.selected;
    return Semantics(
      button: true,
      selected: selected,
      label: '${option.label}, ${option.side}, ${option.score}',
      child: Material(
        color: selected ? SportikaColors.surfaceAlt : Colors.transparent,
        borderRadius: BorderRadius.circular(SportikaRadius.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: option.onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (option.batting) ...[
                      Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: SportikaColors.mint,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Flexible(
                      child: Text(
                        option.label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CricketReportType.statLabel.copyWith(
                          color: selected
                              ? SportikaColors.textMuted
                              : SportikaColors.textDim,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${option.side}  ${option.score}',
                    maxLines: 1,
                    style: CricketReportType.name.copyWith(
                      fontSize: 12.5,
                      color: selected
                          ? SportikaColors.text
                          : SportikaColors.textBody,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Minimal underline navigation: Scorecard | Overs | Commentary.
class _ReportNavigation extends StatelessWidget {
  const _ReportNavigation({required this.selected, required this.onSelect});

  final _ReportView selected;
  final ValueChanged<_ReportView> onSelect;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          for (final view in _ReportView.values)
            Expanded(
              child: _NavTab(
                label: view.label,
                selected: view == selected,
                onTap: () => onSelect(view),
              ),
            ),
        ],
      ),
      const CricketRowRule(),
    ],
  );
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 12, 6, 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: SportikaType.action.copyWith(
                    fontSize: 12.5,
                    color: selected
                        ? SportikaColors.text
                        : SportikaColors.textDim,
                  ),
                ),
              ),
            ),
            AnimatedContainer(
              duration: SportikaMotion.fast,
              curve: SportikaMotion.standard,
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected
                    ? SportikaColors.blueBright
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(SportikaRadius.pill),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
