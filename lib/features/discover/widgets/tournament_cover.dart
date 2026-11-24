import 'package:flutter/material.dart';

import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/editorial.dart';

/// Sportika premium tournament cover.
///
/// Image priority:
/// 1. Tournament banner
/// 2. Bundled sport photography
/// 3. Branded sport artwork
///
/// Features:
/// - Cinematic image grading
/// - Smooth image reveal
/// - Sport-specific identity
/// - Responsive image decoding
/// - Reduced-motion support
/// - Silent image fallbacks
///
/// Tournament titles, registration badges and premium
/// indicators belong to the parent TournamentCard.
class TournamentCover extends StatelessWidget {
  const TournamentCover({
    super.key,
    required this.tournament,
    this.height = 152,
    this.radius = 0,
    this.alignment = Alignment.center,
  });

  final Tournament tournament;
  final double height;
  final double radius;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final banner = tournament.bannerUrl?.trim() ?? '';

    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final pixelRatio = MediaQuery.devicePixelRatioOf(context);

    final width = MediaQuery.sizeOf(context).width;

    // Decode near the expected display resolution.
    final cacheWidth = (width * pixelRatio).round().clamp(1, 4096);

    final cacheHeight = (height * pixelRatio).round().clamp(1, 4096);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Persistent branded background prevents
            // flashes while photography loads.
            _CoverArtwork(sport: tournament.sport),

            // Primary tournament image or sport fallback.
            if (banner.isNotEmpty)
              _networkImage(
                context,
                banner,
                cacheWidth,
                cacheHeight,
                reduceMotion,
              )
            else
              _sportImage(context, cacheWidth, cacheHeight, reduceMotion),

            // Consistent cinematic treatment.
            //
            // Keep the image readable without applying
            // heavy glassmorphism or excessive overlays.
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: SportikaGradients.imageFade,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // NETWORK BANNER
  // ============================================================

  Widget _networkImage(
    BuildContext context,
    String url,
    int cacheWidth,
    int cacheHeight,
    bool reduceMotion,
  ) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      alignment: alignment,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      semanticLabel: '${tournament.name} cover',

      // Keep previously decoded frames during updates.
      gaplessPlayback: true,

      // Reveal photography smoothly after decoding.
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (reduceMotion || wasSynchronouslyLoaded) {
          return child;
        }

        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },

      // Show bundled sport photography while loading.
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          return child;
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            _sportImage(context, cacheWidth, cacheHeight, reduceMotion),
            child,
          ],
        );
      },

      // A failed banner falls back to the sport photo.
      errorBuilder: (context, error, stackTrace) {
        return _sportImage(context, cacheWidth, cacheHeight, reduceMotion);
      },
    );
  }

  // ============================================================
  // SPORT PHOTOGRAPHY FALLBACK
  // ============================================================

  Widget _sportImage(
    BuildContext context,
    int cacheWidth,
    int cacheHeight,
    bool reduceMotion,
  ) {
    return Image.asset(
      'assets/images/sports/${tournament.sport.name}.jpg',
      fit: BoxFit.cover,
      alignment: alignment,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      semanticLabel: '${tournament.sport.label} sports photography',
      gaplessPlayback: true,

      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (reduceMotion || wasSynchronouslyLoaded) {
          return child;
        }

        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: child,
        );
      },

      errorBuilder: (context, error, stackTrace) {
        return _CoverArtwork(sport: tournament.sport);
      },
    );
  }
}

// ============================================================
// CINEMATIC BRAND ARTWORK
// ============================================================

/// Sport-specific branded fallback artwork.
///
/// Uses the existing Sportika gradient, sport identity
/// and semantic color tokens.
///
/// No external imagery or new assets required.
class _CoverArtwork extends StatelessWidget {
  const _CoverArtwork({required this.sport});

  final Sport sport;

  @override
  Widget build(BuildContext context) {
    final accent = context.sportika.sport(sport).tone;

    return DecoratedBox(
      decoration: const BoxDecoration(gradient: SportikaGradients.coverSurface),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;

          final shortSide = width < height ? width : height;

          final emblemSize = (shortSide * 0.32).clamp(28.0, 56.0);

          return Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              // ----------------------------------
              // ATMOSPHERIC ACCENT
              // ----------------------------------

              Positioned(
                right: -width * 0.18,
                top: -height * 0.5,
                child: ExcludeSemantics(
                  child: Container(
                    width: width * 0.85,
                    height: width * 0.85,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          accent.withValues(alpha: SportikaOpacity.muted),
                          accent.withValues(alpha: SportikaOpacity.faint),
                          SportikaColors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ----------------------------------
              // OVERSIZED SPORT WATERMARK
              // ----------------------------------
              Positioned(
                right: -width * 0.04,
                bottom: -height * 0.24,
                child: ExcludeSemantics(
                  child: SportGlyph(
                    sport: sport,
                    size: (height * 1.2).clamp(64.0, 240.0),
                    color: accent.withValues(alpha: SportikaOpacity.faint),
                  ),
                ),
              ),

              // ----------------------------------
              // GEOMETRIC STADIUM LINES
              // ----------------------------------
              Positioned.fill(
                child: ExcludeSemantics(
                  child: CustomPaint(
                    painter: _CoverLinesPainter(
                      color: accent.withValues(alpha: SportikaOpacity.muted),
                    ),
                  ),
                ),
              ),

              // ----------------------------------
              // SPORT IDENTITY EMBLEM
              // ----------------------------------
              Align(
                alignment: const Alignment(-0.78, 0),
                child: ExcludeSemantics(
                  child: Container(
                    width: emblemSize * 1.65,
                    height: emblemSize * 1.65,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: SportikaColors.deepest.withValues(
                        alpha: SportikaOpacity.strong,
                      ),
                      borderRadius: BorderRadius.circular(SportikaRadius.lg),
                      border: Border.all(
                        color: accent.withValues(alpha: SportikaOpacity.muted),
                        width: SportikaBorder.hairline,
                      ),
                    ),
                    child: SportGlyph(
                      sport: sport,
                      size: emblemSize,
                      color: accent,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================
// DECORATIVE STADIUM-INSPIRED LINE ART
// ============================================================

/// Lightweight decorative geometry.
///
/// No animation or image assets.
/// Uses only the sport's existing theme accent.
class _CoverLinesPainter extends CustomPainter {
  const _CoverLinesPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = SportikaBorder.hairline;

    final path = Path();

    // Diagonal movement lines.
    path.moveTo(size.width * 0.38, 0);
    path.lineTo(size.width * 0.88, size.height);

    path.moveTo(size.width * 0.58, 0);
    path.lineTo(size.width * 1.08, size.height);

    // Horizontal arena-inspired line.
    path.moveTo(0, size.height * 0.78);
    path.lineTo(size.width, size.height * 0.78);

    canvas.drawPath(path, paint);

    // Partial concentric arcs evoke stadium geometry.
    final arcCenter = Offset(size.width * 0.9, size.height * 0.5);

    final radius = size.height * 0.8;

    for (var index = 0; index < 3; index++) {
      final currentRadius = radius + index * SportikaSpacing.lg;

      canvas.drawCircle(arcCenter, currentRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CoverLinesPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
