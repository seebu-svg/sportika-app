import 'package:flutter/material.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';

/// Text roles for the cricket scorecard. Sizes mirror [SportikaType] and every
/// colour resolves to a [SportikaColors] token, so the sheet inherits the app
/// surface instead of owning a palette of its own.
class CricketReportType {
  CricketReportType._();

  static final TextStyle eyebrow = SportikaType.micro.copyWith(
    color: SportikaColors.textDim,
    letterSpacing: 1.6,
  );

  static const TextStyle section = SportikaType.label;

  static const TextStyle name = SportikaType.bodyStrong;

  static const TextStyle meta = SportikaType.caption;

  static final TextStyle metaFaint = SportikaType.caption.copyWith(
    color: SportikaColors.textDim,
  );

  static const TextStyle result = SportikaType.bodyStrong;

  /// The big two-team readout: display family, tight leading.
  static final TextStyle score = SportikaType.title.copyWith(
    fontSize: 30,
    letterSpacing: -0.8,
  );

  static const TextStyle stat = TextStyle(
    fontFamily: SportikaType.displayFamily,
    fontSize: 16.5,
    height: 1.15,
    fontWeight: FontWeight.w700,
    color: SportikaColors.text,
  );

  static const TextStyle statStrong = TextStyle(
    fontFamily: SportikaType.displayFamily,
    fontSize: 18,
    height: 1.15,
    fontWeight: FontWeight.w800,
    color: SportikaColors.text,
  );

  static const TextStyle statLabel = TextStyle(
    fontFamily: SportikaType.bodyFamily,
    fontSize: 9.5,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.9,
    color: SportikaColors.textDim,
  );

  static const TextStyle badge = TextStyle(
    fontFamily: SportikaType.bodyFamily,
    fontSize: 10.5,
    height: 1.1,
    fontWeight: FontWeight.w800,
    color: SportikaColors.text,
  );
}

/// Fixed numeric columns keep every row of a table aligned without a
/// horizontally scrolling grid. The batter and bowler columns take the rest.
class CricketStatWidths {
  CricketStatWidths._();

  static const double runs = 32;
  static const double balls = 30;
  static const double boundaries = 26;
  static const double strikeRate = 42;
  static const double overs = 36;
  static const double economy = 46;
}

/// Uppercase group label with an optional right-aligned value.
class CricketSectionHeading extends StatelessWidget {
  const CricketSectionHeading(this.label, {super.key, this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: CricketReportType.section,
        ),
      ),
      if (trailing != null) ...[
        const SizedBox(width: SportikaSpacing.sm),
        Flexible(
          child: Text(
            trailing!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: CricketReportType.metaFaint,
          ),
        ),
      ],
    ],
  );
}

/// Right-aligned numeric cell. Fitted so a large text scale or a long strike
/// rate shrinks instead of overflowing its column.
class CricketStatCell extends StatelessWidget {
  const CricketStatCell(
    this.text, {
    super.key,
    required this.width,
    this.emphasis = false,
  });

  final String text;
  final double width;
  final bool emphasis;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(
        text,
        maxLines: 1,
        style: emphasis ? CricketReportType.statStrong : CricketReportType.stat,
      ),
    ),
  );
}

/// Column header matching [CricketStatCell].
class CricketStatHeading extends StatelessWidget {
  const CricketStatHeading(this.text, {super.key, required this.width});

  final String text;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(text, maxLines: 1, style: CricketReportType.statLabel),
    ),
  );
}

/// Hairline rule between scorecard groups.
class CricketHairline extends StatelessWidget {
  const CricketHairline({super.key, this.vertical = 16});

  final double vertical;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: vertical),
    child: const CricketRowRule(),
  );
}

/// The single one-pixel rule used inside tables, timelines and section breaks.
class CricketRowRule extends StatelessWidget {
  const CricketRowRule({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 1,
    child: ColoredBox(color: SportikaColors.borderSubtle),
  );
}

/// Collapsible group: the heading carries a live summary so a folded section
/// still answers "how many, how much" without opening.
class CricketCollapsibleSection extends StatefulWidget {
  const CricketCollapsibleSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.initiallyExpanded = false,
  });

  final String title;
  final String? trailing;
  final Widget child;
  final bool initiallyExpanded;

  @override
  State<CricketCollapsibleSection> createState() =>
      _CricketCollapsibleSectionState();
}

class _CricketCollapsibleSectionState extends State<CricketCollapsibleSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          expanded: _expanded,
          label: widget.title,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(SportikaRadius.sm),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CricketReportType.section,
                      ),
                    ),
                    if (widget.trailing != null) ...[
                      const SizedBox(width: SportikaSpacing.sm),
                      Flexible(
                        child: Text(
                          widget.trailing!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: CricketReportType.metaFaint,
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: SportikaMotion.fast,
                      curve: SportikaMotion.standard,
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: SportikaColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        ClipRect(
          child: AnimatedSize(
            duration: SportikaMotion.base,
            curve: SportikaMotion.standard,
            alignment: Alignment.topCenter,
            child: _expanded
                ? widget.child
                : const SizedBox(width: double.infinity),
          ),
        ),
      ],
    );
  }
}

enum CricketRunTone { neutral, boundary, wicket, extra }

/// Compact delivery marker: 0, 4, 6, W, Wd, Nb + 1…
class CricketRunBadge extends StatelessWidget {
  const CricketRunBadge(
    this.text, {
    super.key,
    this.tone = CricketRunTone.neutral,
  });

  final String text;
  final CricketRunTone tone;

  @override
  Widget build(BuildContext context) {
    final (fill, foreground) = switch (tone) {
      CricketRunTone.boundary => (
        SportikaColors.blueSubtle,
        SportikaColors.blueBright,
      ),
      CricketRunTone.wicket => (
        SportikaColors.dangerSubtle,
        SportikaColors.danger,
      ),
      CricketRunTone.extra => (SportikaColors.goldSubtle, SportikaColors.gold),
      CricketRunTone.neutral => (
        SportikaColors.surfaceAlt,
        SportikaColors.textBody,
      ),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          // widthFactor keeps the pill hugging its label instead of filling
          // the row like an aligned Container would.
          child: Center(
            widthFactor: 1,
            child: Text(
              text,
              maxLines: 1,
              style: CricketReportType.badge.copyWith(color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}

/// Borderless note used for correction notices and unavailable statistics.
class CricketReportNote extends StatelessWidget {
  const CricketReportNote({
    super.key,
    required this.text,
    this.icon = Icons.info_outline,
    this.tone = SportikaColors.textDim,
  });

  final String text;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(icon, size: 15, color: tone),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: CricketReportType.meta)),
    ],
  );
}

/// Empty innings / empty section placeholder. Never invents a score.
class CricketEmptyPanel extends StatelessWidget {
  const CricketEmptyPanel({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.sports_cricket,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
    decoration: BoxDecoration(
      color: SportikaColors.surfaceSunken,
      borderRadius: BorderRadius.circular(SportikaRadius.md),
    ),
    child: Column(
      children: [
        Icon(icon, size: 22, color: SportikaColors.textDim),
        const SizedBox(height: 10),
        Text(title, textAlign: TextAlign.center, style: CricketReportType.name),
        const SizedBox(height: 4),
        Text(body, textAlign: TextAlign.center, style: CricketReportType.meta),
      ],
    ),
  );
}
