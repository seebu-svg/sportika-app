import 'package:flutter/material.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';

/// Real editorial photographs. Source pages and photographer credits are in
/// assets/PHOTO_CREDITS.md. Photography never affects local match state.
class SportPhotography {
  SportPhotography._();
  static const cricket =
      'https://images.unsplash.com/photo-1594470117722-de4b9a02ebed?auto=format&fit=crop&w=1200&q=78';
  static const padel =
      'https://images.unsplash.com/photo-1658491830143-72808ca237e3?auto=format&fit=crop&w=1200&q=78';
  static const futsal =
      'https://images.pexels.com/photos/29388472/pexels-photo-29388472.jpeg?auto=compress&cs=tinysrgb&w=1200&q=78';
  static const badminton =
      'https://images.pexels.com/photos/2202685/pexels-photo-2202685.jpeg?auto=compress&cs=tinysrgb&w=1200&q=78';
  static String forSport(Sport sport) => switch (sport) {
    Sport.cricket => cricket,
    Sport.padel => padel,
    Sport.futsal => futsal,
    Sport.badminton => badminton,
  };
}

IconData sportGlyph(Sport sport) => switch (sport) {
  Sport.cricket => Icons.sports_cricket_outlined,
  Sport.padel => Icons.sports_tennis_outlined,
  Sport.futsal => Icons.sports_soccer_outlined,
  Sport.badminton => Icons.sports_tennis_outlined,
};

/// Sport-specific glyph that never repeats a silhouette: Material sport icons
/// for cricket, padel and futsal, and a hand-drawn shuttlecock for badminton
/// (Material has no badminton glyph).
class SportGlyph extends StatelessWidget {
  const SportGlyph({
    super.key,
    required this.sport,
    this.size = 20,
    this.color,
  });
  final Sport sport;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (sport != Sport.badminton) {
      return Icon(sportGlyph(sport), size: size, color: color);
    }
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ShuttlecockPainter(
          color ?? IconTheme.of(context).color ?? Colors.white,
        ),
      ),
    );
  }
}

/// Minimal shuttlecock: a cork circle with a flared skirt of feather lines.
class _ShuttlecockPainter extends CustomPainter {
  const _ShuttlecockPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .075
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = color;
    final w = size.width, h = size.height;
    // Skirt apex (top) down to a flared opening at the cork line.
    final apex = Offset(w * .5, h * .14);
    final skirtLeft = Offset(w * .2, h * .62);
    final skirtRight = Offset(w * .8, h * .62);
    canvas.drawLine(apex, skirtLeft, paint);
    canvas.drawLine(apex, skirtRight, paint);
    for (final t in const [0.34, 0.5, 0.66]) {
      canvas.drawLine(apex, Offset.lerp(skirtLeft, skirtRight, t)!, paint);
    }
    // Feather band across the skirt.
    canvas.drawLine(
      Offset.lerp(apex, skirtLeft, .72)!,
      Offset.lerp(apex, skirtRight, .72)!,
      paint,
    );
    // Cork.
    canvas.drawCircle(Offset(w * .5, h * .74), w * .12, fill);
  }

  @override
  bool shouldRepaint(_ShuttlecockPainter old) => old.color != color;
}

class SportPhoto extends StatelessWidget {
  const SportPhoto({
    super.key,
    this.sport = Sport.cricket,
    this.height = 160,
    this.alignment = Alignment.center,
    this.radius = 16,
  });
  final Sport sport;
  final double height, radius;
  final Alignment alignment;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final decodeWidth =
              (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                  .round()
                  .clamp(1, 1600);
          return Image.asset(
            'assets/images/sports/${sport.name}.jpg',
            fit: BoxFit.cover,
            alignment: alignment,
            cacheWidth: decodeWidth,
            semanticLabel: '${sport.label} sports photography',
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => Image.network(
              SportPhotography.forSport(sport),
              fit: BoxFit.cover,
              alignment: alignment,
              cacheWidth: decodeWidth,
              semanticLabel: '${sport.label} sports photography',
              filterQuality: FilterQuality.medium,
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : _placeholder(loading: true),
              errorBuilder: (_, _, _) => _placeholder(loading: false),
            ),
          );
        },
      ),
    ),
  );
  Widget _placeholder({required bool loading}) => ColoredBox(
    color: SportikaColors.surfaceAlt,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            sportGlyph(sport),
            size: 34,
            color: SportikaColors.mint.withValues(alpha: .6),
          ),
          const SizedBox(height: 10),
          Text(
            loading
                ? 'Loading photography'
                : '${sport.label} · Photo unavailable',
            style: const TextStyle(
              fontSize: 11,
              color: SportikaColors.textMuted,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Shared editorial treatment: genuine photography, a restrained readability
/// scrim, condensed sporting type, and one clear action.
class EditorialBanner extends StatelessWidget {
  const EditorialBanner({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.sport = Sport.cricket,
    this.action,
    this.onAction,
    this.height = 264,
    this.accent = SportikaColors.mint,
  });
  final String eyebrow, title, subtitle;
  final Sport sport;
  final String? action;
  final VoidCallback? onAction;
  final double height;
  final Color accent;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: SizedBox(
      height:
          height +
          (MediaQuery.textScalerOf(context).scale(1).clamp(1, 2) - 1) * 120,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SportPhoto(sport: sport, height: height, radius: 0),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x0A061426),
                  Color(0x8809182D),
                  Color(0xF509182D),
                ],
                stops: [0, .4, 1],
              ),
            ),
          ),
          Positioned(
            top: 20,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: SportikaColors.deepest.withValues(alpha: .85),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accent.withValues(alpha: .5)),
              ),
              child: Text(
                eyebrow.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  color: accent,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    maxLines: 2,
                    softWrap: false,
                    style: const TextStyle(
                      fontFamily: 'Barlow Condensed',
                      fontSize: 40,
                      height: .95,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.4,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: Color(0xFFD4DEEC),
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: SportikaColors.deepest,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          action!,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 20),
                        const Icon(Icons.arrow_forward, size: 17),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class BrandMetricStrip extends StatelessWidget {
  const BrandMetricStrip({
    super.key,
    required this.metrics,
    this.accent = SportikaColors.mint,
  });
  final List<({String value, String label})> metrics;
  final Color accent;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 20),
    decoration: const BoxDecoration(
      border: Border.symmetric(
        horizontal: BorderSide(color: SportikaColors.border),
      ),
    ),
    child: Row(
      children: [
        for (var i = 0; i < metrics.length; i++) ...[
          if (i > 0)
            Container(height: 32, width: 1, color: SportikaColors.border),
          Expanded(
            child: Column(
              children: [
                Text(
                  metrics[i].value,
                  style: TextStyle(
                    fontFamily: 'Barlow Condensed',
                    fontSize: 32,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .3,
                    color: i == 1 ? accent : Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  metrics[i].label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: SportikaColors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}
