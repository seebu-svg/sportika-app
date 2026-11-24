import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/theme/theme.dart';

/// Edge-to-edge editorial artwork for the Match Details header.
class MatchDetailBanner extends StatelessWidget {
  const MatchDetailBanner({super.key, required this.sport});

  final Sport sport;

  @override
  Widget build(BuildContext context) {
    final identity = SportIdentities.of(sport);
    // Preserve the floodlights, ball, or raised racket in wider crops.
    final alignment = switch (sport) {
      Sport.cricket => const Alignment(0, -0.7),
      Sport.padel => Alignment.center,
      Sport.futsal => const Alignment(0, 0.48),
      Sport.badminton => const Alignment(0, -0.9),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = (width * 0.46).clamp(180.0, 220.0);
        // The bundled banners are 2:1. Round decode widths so small viewport
        // changes can reuse the same cached image.
        final imageWidth = math.max(width, height * 2);
        final pixelWidth = imageWidth * MediaQuery.devicePixelRatioOf(context);
        final decodeWidth = ((pixelWidth / 128).ceil() * 128).clamp(384, 1440);

        return SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                identity.actionPhoto,
                fit: BoxFit.cover,
                alignment: alignment,
                cacheWidth: decodeWidth,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => Image.asset(
                  sport == Sport.padel
                      ? 'assets/images/sports/padel_match_action.jpg'
                      : identity.fallbackPhoto,
                  fit: BoxFit.cover,
                  alignment: alignment,
                  cacheWidth: decodeWidth,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: SportikaColors.surfaceSunken),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: SportikaGradients.matchDetailScrim,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
