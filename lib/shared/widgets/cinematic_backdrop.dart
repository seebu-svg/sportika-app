import 'package:flutter/material.dart';

import 'package:sportika/shared/theme/theme.dart';

/// Stadium lighting behind the content of a screen.
class CinematicBackdrop extends StatelessWidget {
  const CinematicBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (context.sportika.brightness != Brightness.dark) return child;
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: SportikaGradients.atmosphere),
      child: child,
    );
  }
}

/// Broadcast graphics layered over bundled sports photography.
class SportMotionGraphic extends StatelessWidget {
  const SportMotionGraphic({super.key, required this.tone});

  final Color tone;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _SportMotionPainter(tone)),
    );
  }
}

class _SportMotionPainter extends CustomPainter {
  const _SportMotionPainter(this.tone);

  final Color tone;

  @override
  void paint(Canvas canvas, Size size) {
    final field = Offset.zero & size;
    final light = Paint()
      ..shader = RadialGradient(
        center: const Alignment(.84, -.78),
        radius: .75,
        colors: [
          tone.withValues(alpha: SportikaOpacity.muted),
          SportikaColors.transparent,
        ],
      ).createShader(field);
    canvas.drawRect(field, light);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = SportikaBorder.hairline
      ..color = tone.withValues(alpha: SportikaOpacity.medium);
    final width = size.width;
    final height = size.height;

    canvas.save();
    canvas.clipRect(field);
    // A perspective crop of court markings along the edge of the photograph.
    final court = Path()
      ..moveTo(width * .59, height)
      ..lineTo(width * .91, height * .17)
      ..lineTo(width * 1.10, height * .17)
      ..moveTo(width * .76, height)
      ..lineTo(width * .99, height * .22)
      ..moveTo(width * .75, height * .59)
      ..lineTo(width, height * .59)
      ..moveTo(width * .66, height * .82)
      ..lineTo(width, height * .82);
    canvas.drawPath(court, line);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SportMotionPainter oldDelegate) =>
      oldDelegate.tone != tone;
}
