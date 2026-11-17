import 'package:flutter/material.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';

class MatchReportLegend extends StatelessWidget {
  const MatchReportLegend({super.key, required this.match});
  final SportMatch match;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var side = 0; side < 2; side++)
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: side == 1 ? 12 : 0),
            child: Column(
              crossAxisAlignment: side == 0
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                Container(
                  width: 20,
                  height: 3,
                  color: side == 0
                      ? SportikaColors.blueBright
                      : SportikaColors.mint,
                ),
                const SizedBox(height: 6),
                Text(
                  match.sideLabels[side],
                  textAlign: side == 0 ? TextAlign.left : TextAlign.right,
                  style: SportikaType.caption,
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class MatchStatComparison extends StatelessWidget {
  const MatchStatComparison({
    super.key,
    required this.label,
    required this.home,
    required this.away,
  });
  final String label;
  final int home;
  final int away;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      children: [
        Row(
          children: [
            Text('$home', style: SportikaType.scoreSmall),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: SportikaType.caption,
              ),
            ),
            const SizedBox(width: 12),
            Text('$away', style: SportikaType.scoreSmall),
          ],
        ),
        const SizedBox(height: 7),
        Semantics(
          label: '$label: $home to $away',
          child: ExcludeSemantics(
            child: Row(
              children: [
                if (home + away == 0)
                  Expanded(
                    child: Container(height: 3, color: SportikaColors.border),
                  )
                else ...[
                  if (home > 0)
                    Expanded(
                      flex: home,
                      child: Container(
                        height: 3,
                        color: SportikaColors.blueBright,
                      ),
                    ),
                  if (home > 0 && away > 0) const SizedBox(width: 3),
                  if (away > 0)
                    Expanded(
                      flex: away,
                      child: Container(height: 3, color: SportikaColors.mint),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
