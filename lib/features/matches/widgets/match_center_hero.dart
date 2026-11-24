import 'package:flutter/material.dart';

import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Cinematic header for the Matches page: one broadcast desk above the feed,
/// carrying stadium light, diagonal court graphics and the live count.
class MatchCenterHero extends StatelessWidget {
  const MatchCenterHero({
    super.key,
    required this.selectedSport,
    this.liveCount = 0,
    this.upcomingCount = 0,
    this.matchCount = 0,
  });

  final Sport? selectedSport;
  final int liveCount;
  final int upcomingCount;
  final int matchCount;

  @override
  Widget build(BuildContext context) {
    final identity = selectedSport == null
        ? null
        : SportIdentities.of(selectedSport!);
    final tone = identity?.tone ?? SportikaColors.mint;
    final stage = selectedSport?.label ?? 'All sports';
    final counts = [
      if (liveCount > 0) '$liveCount live',
      if (upcomingCount > 0) '$upcomingCount upcoming',
    ].join(' · ');

    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SportikaRadius.xl),
        boxShadow: SportikaShadows.hero,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SportikaRadius.xl),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _HeroPhotography(selected: selectedSport),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: SportikaGradients.heroSpotlight(tone),
                ),
              ),
            ),
            BroadcastGraphics(tone: tone),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: SportikaGradients.cinematicHeroScrim,
              ),
            ),
            // A single metallic hairline reads as the lighting rig.
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: SportikaBorder.hairline,
                decoration: const BoxDecoration(
                  gradient: SportikaGradients.sheen,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SportikaSpacing.lg,
                SportikaSpacing.gutter,
                SportikaSpacing.lg,
                SportikaSpacing.gutter,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const BrandMark(size: 22),
                      const SizedBox(width: SportikaSpacing.xs),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'SPORTIKA',
                            maxLines: 1,
                            style: SportikaType.micro.copyWith(
                              color: SportikaColors.textBody,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: SportikaSpacing.sm),
                      _LiveCounter(
                        liveCount: liveCount,
                        matchCount: matchCount,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    stage.toUpperCase(),
                    style: SportikaType.micro.copyWith(
                      color: SportikaColors.mint,
                      letterSpacing: 2.2,
                    ),
                  ),
                  const SizedBox(height: SportikaSpacing.xxs),
                  Semantics(
                    header: true,
                    child: Text(
                      'Match Center',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SportikaType.display(
                        34,
                        height: .96,
                        letterSpacing: -.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: SportikaSpacing.xs),
                  Text(
                    counts.isEmpty ? 'No fixtures in this view' : counts,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SportikaType.caption.copyWith(
                      color: SportikaColors.textBody,
                    ),
                  ),
                  const SizedBox(height: SportikaSpacing.md),
                  ExcludeSemantics(
                    child: Row(
                      children: [
                        for (var i = 0; i < Sport.values.length; i++) ...[
                          if (i > 0) const SizedBox(width: SportikaSpacing.xs),
                          Expanded(
                            child: _SportTick(
                              sport: Sport.values[i],
                              active:
                                  selectedSport == null ||
                                  selectedSport == Sport.values[i],
                            ),
                          ),
                        ],
                      ],
                    ),
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

class _LiveCounter extends StatelessWidget {
  const _LiveCounter({required this.liveCount, required this.matchCount});

  final int liveCount;
  final int matchCount;

  @override
  Widget build(BuildContext context) {
    final live = liveCount > 0;
    final tone = live ? SportikaColors.mint : SportikaColors.textBody;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SportikaSpacing.sm,
        vertical: SportikaSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: SportikaColors.glass,
        borderRadius: BorderRadius.circular(SportikaRadius.pill),
        border: Border.all(color: SportikaColors.overlayHairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 6,
            width: 6,
            decoration: BoxDecoration(
              color: tone,
              shape: BoxShape.circle,
              boxShadow: live ? SportikaShadows.accent(tone) : null,
            ),
          ),
          const SizedBox(width: SportikaSpacing.xs),
          Text(
            live ? '$liveCount LIVE' : '$matchCount MATCHES',
            style: SportikaType.micro.copyWith(color: tone),
          ),
        ],
      ),
    );
  }
}

class _SportTick extends StatelessWidget {
  const _SportTick({required this.sport, required this.active});

  final Sport sport;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final identity = SportIdentities.of(sport);
    return Opacity(
      opacity: active ? 1 : SportikaOpacity.medium,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SportGlyph(
                sport: sport,
                size: SportikaIconSize.xs,
                color: identity.tone,
              ),
              const SizedBox(width: SportikaSpacing.xs),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    identity.label,
                    maxLines: 1,
                    style: SportikaType.micro.copyWith(
                      fontSize: 8.5,
                      letterSpacing: .6,
                      color: active
                          ? SportikaColors.textBody
                          : SportikaColors.textDim,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.xs),
          Container(
            height: 3,
            decoration: BoxDecoration(
              gradient: SportikaGradients.liveEdge(identity.tone),
              borderRadius: BorderRadius.circular(SportikaRadius.pill),
            ),
          ),
        ],
      ),
    );
  }
}

/// Football-programme lighting and court lines drawn over photography.
class BroadcastGraphics extends StatelessWidget {
  const BroadcastGraphics({super.key, required this.tone, this.intensity = 1});

  final Color tone;
  final double intensity;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      painter: _BroadcastGraphicsPainter(tone: tone, intensity: intensity),
    ),
  );
}

class _BroadcastGraphicsPainter extends CustomPainter {
  const _BroadcastGraphicsPainter({
    required this.tone,
    required this.intensity,
  });

  final Color tone;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final width = size.width;
    final height = size.height;

    // Translucent wedge in the top corner, as if a floodlight is clipped.
    final wedge = Path()
      ..moveTo(width * .70, 0)
      ..lineTo(width, 0)
      ..lineTo(width, height * .34)
      ..close();
    canvas.drawPath(
      wedge,
      Paint()
        ..shader = SportikaGradients.heroWedge.createShader(Offset.zero & size),
    );

    // Diagonal mint speed lines rising from the touchline.
    final slash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = SportikaBorder.hairline;
    const strengths = [.45, .24, .13];
    for (var i = 0; i < strengths.length; i++) {
      final offset = i * SportikaSpacing.lg;
      slash.color = SportikaColors.mint.withValues(
        alpha: strengths[i] * intensity,
      );
      canvas.drawLine(
        Offset(width * .62 + offset, height),
        Offset(width * .97 + offset * .5, height * .30 + offset * .3),
        slash,
      );
    }

    // Two court hairlines, kept faint so the photograph still reads.
    final rule = Paint()
      ..color = tone.withValues(alpha: .16 * intensity)
      ..strokeWidth = SportikaBorder.hairline;
    canvas.drawLine(
      Offset(width * .78, height * .54),
      Offset(width, height * .54),
      rule,
    );
    canvas.drawLine(
      Offset(width * .72, height * .72),
      Offset(width, height * .72),
      rule,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BroadcastGraphicsPainter oldDelegate) =>
      oldDelegate.tone != tone || oldDelegate.intensity != intensity;
}

/// Sport photograph with an optional identity duotone, used by the hero and by
/// every match card so imagery and decode sizes stay in one place.
class MatchSportPhoto extends StatelessWidget {
  const MatchSportPhoto({
    super.key,
    required this.sport,
    this.alignment = Alignment.center,
    this.duotone = false,
  });

  final Sport sport;
  final Alignment alignment;
  final bool duotone;

  @override
  Widget build(BuildContext context) {
    final identity = SportIdentities.of(sport);
    return LayoutBuilder(
      builder: (context, constraints) {
        final pixelRatio = MediaQuery.devicePixelRatioOf(context);
        // Decode enough pixels to cover a tall hero crop as well as a wide cover.
        final extent = constraints.maxWidth > constraints.maxHeight * 1.6
            ? constraints.maxWidth
            : constraints.maxHeight * 1.6;
        final decodeWidth = (((extent * pixelRatio) / 128).ceil() * 128).clamp(
          128,
          1200,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              identity.fallbackPhoto,
              width: double.infinity,
              height: double.infinity,
              cacheWidth: decodeWidth,
              alignment: alignment,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: SportikaGradients.sportFallback(identity.tone),
                ),
                child: Center(
                  child: SportGlyph(sport: sport, color: identity.tone),
                ),
              ),
            ),
            if (duotone)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: SportikaGradients.photoDuotone(identity.tone),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Sport filter for the match feed. Each option carries its sport identity so
/// the rail reads as part of the broadcast header rather than a generic filter.
class MatchSportSelector extends StatelessWidget {
  const MatchSportSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Sport? selected;
  final ValueChanged<Sport?> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        _SportChip(
          label: 'All sports',
          tone: SportikaColors.mint,
          icon: Icons.grid_view_rounded,
          selected: selected == null,
          onTap: () => onChanged(null),
        ),
        for (final sport in Sport.values)
          Padding(
            padding: const EdgeInsets.only(left: SportikaSpacing.xs),
            child: _SportChip(
              label: sport.label,
              tone: SportIdentities.of(sport).tone,
              sport: sport,
              selected: selected == sport,
              onTap: () => onChanged(sport),
            ),
          ),
      ],
    ),
  );
}

class _SportChip extends StatelessWidget {
  const _SportChip({
    required this.label,
    required this.tone,
    required this.selected,
    required this.onTap,
    this.icon,
    this.sport,
  });

  final String label;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Sport? sport;

  @override
  Widget build(BuildContext context) {
    final ink = selected ? tone : SportikaColors.textBody;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected
            ? tone.withValues(alpha: SportikaOpacity.tint)
            : SportikaColors.surfaceSunken,
        borderRadius: BorderRadius.circular(SportikaRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: SportikaSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SportikaRadius.md),
              border: Border.all(
                color: selected
                    ? tone.withValues(alpha: .55)
                    : SportikaColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (sport != null)
                  SportGlyph(
                    sport: sport!,
                    size: SportikaIconSize.sm,
                    color: ink,
                  )
                else if (icon != null)
                  Icon(icon, size: SportikaIconSize.sm, color: ink),
                const SizedBox(width: SportikaSpacing.xs),
                Text(label, style: SportikaType.action.copyWith(color: ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroPhotography extends StatelessWidget {
  const _HeroPhotography({required this.selected});

  final Sport? selected;

  static Alignment _alignmentOf(Sport sport) => switch (sport) {
    Sport.cricket => Alignment.centerRight,
    Sport.badminton => const Alignment(-0.3, 0),
    _ => Alignment.center,
  };

  @override
  Widget build(BuildContext context) {
    if (selected != null) {
      return MatchSportPhoto(
        sport: selected!,
        alignment: _alignmentOf(selected!),
        duotone: true,
      );
    }
    // All sports: four columns of photography divided by light seams.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < Sport.values.length; i++) ...[
          if (i > 0)
            Container(
              width: SportikaBorder.hairline,
              color: SportikaColors.overlayHairline,
            ),
          Expanded(
            child: MatchSportPhoto(
              sport: Sport.values[i],
              alignment: _alignmentOf(Sport.values[i]),
              duotone: true,
            ),
          ),
        ],
      ],
    );
  }
}
