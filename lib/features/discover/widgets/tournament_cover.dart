import 'package:flutter/material.dart';

import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/editorial.dart';

/// The tournament's one cover image.
///
/// The record's own `bannerUrl` wins, then the bundled sport photograph, then
/// brand artwork. Every failure is silent: a cover that is missing, uses an
/// unsupported format or cannot be fetched degrades to the next layer instead of
/// printing an error into the page.
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: banner.isEmpty ? _sportArt() : _banner(banner),
      ),
    );
  }

  Widget _banner(String url) => Image.network(
    url,
    fit: BoxFit.cover,
    alignment: alignment,
    semanticLabel: '${tournament.name} cover',
    // No spinner copy and no retry text: the artwork below stands in while the
    // picture is in flight or when it never arrives.
    loadingBuilder: (_, child, progress) =>
        progress == null ? child : _artwork(),
    errorBuilder: (_, _, _) => _sportArt(),
  );

  Widget _sportArt() => Image.asset(
    'assets/images/sports/${tournament.sport.name}.jpg',
    fit: BoxFit.cover,
    alignment: alignment,
    semanticLabel: '${tournament.sport.label} sports photography',
    errorBuilder: (_, _, _) => _artwork(),
  );

  Widget _artwork() => _CoverArtwork(sport: tournament.sport);
}

/// Brand artwork for a cover with no usable picture: layered navy and the sport
/// glyph, so the header keeps its shape without explaining what is missing.
class _CoverArtwork extends StatelessWidget {
  const _CoverArtwork({required this.sport});

  final Sport sport;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [SportikaColors.surfaceAlt, SportikaColors.deepest],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -18,
            bottom: -26,
            child: ExcludeSemantics(
              child: SportGlyph(
                sport: sport,
                size: 132,
                color: SportikaColors.mint.withValues(alpha: 0.10),
              ),
            ),
          ),
          Align(
            alignment: const Alignment(-0.82, 0),
            child: ExcludeSemantics(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: SportikaColors.deepest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(SportikaRadius.sm + 2),
                  border: Border.all(
                    color: SportikaColors.mint.withValues(alpha: 0.28),
                  ),
                ),
                child: Center(
                  child: SportGlyph(
                    sport: sport,
                    size: 20,
                    color: SportikaColors.mint,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
