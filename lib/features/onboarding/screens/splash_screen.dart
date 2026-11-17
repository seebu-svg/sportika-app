import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Brand introduction. Startup timing and destination belong to the auth flow.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: SportikaColors.deepest,
      ),
      child: Scaffold(
        backgroundColor: SportikaColors.deepest,
        body: DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: SportikaType.bodyFamily),
          child: Stack(
            children: [
              const Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: CustomPaint(painter: _SplashCourtPainter()),
                  ),
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxHeight < 600;
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 24,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'PLAY. CONNECT. COMPETE.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2.4,
                                  color: SportikaColors.textMuted,
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: compact ? 28 : 56,
                                ),
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0, end: 1),
                                  duration: reduceMotion
                                      ? Duration.zero
                                      : const Duration(milliseconds: 700),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, value, child) => Opacity(
                                    opacity: value,
                                    child: Transform.translate(
                                      offset: Offset(0, 12 * (1 - value)),
                                      child: Transform.scale(
                                        scale: .94 + .06 * value,
                                        child: child,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      BrandMark(size: compact ? 84 : 104),
                                      const SizedBox(height: 24),
                                      const FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          'SPORTIKA',
                                          style: TextStyle(
                                            fontFamily: 'Barlow Condensed',
                                            fontSize: 52,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 5,
                                            height: 1,
                                            color: SportikaColors.text,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      Container(
                                        width: 32,
                                        height: 3,
                                        decoration: BoxDecoration(
                                          color: SportikaColors.mint,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      const Text(
                                        'The game connects us.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                          height: 1.3,
                                          color: SportikaColors.text,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      const Text(
                                        'Your people. Your next game.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 13,
                                          height: 1.5,
                                          color: SportikaColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 14,
                                    runSpacing: 8,
                                    children: [
                                      _SportLabel('CRICKET'),
                                      _SportLabel('PADEL'),
                                      _SportLabel('FUTSAL'),
                                      _SportLabel('BADMINTON'),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  TextButton(
                                    onPressed: context
                                        .read<AuthFlowController>()
                                        .continueFromSplash,
                                    style: TextButton.styleFrom(
                                      foregroundColor: SportikaColors.mint,
                                      minimumSize: const Size(160, 48),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text('Tap to continue'),
                                        ),
                                        SizedBox(width: 8),
                                        Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 16,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SportLabel extends StatelessWidget {
  const _SportLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.5,
      color: SportikaColors.textMuted,
    ),
  );
}

/// Quiet court geometry keeps the introduction independent of image loading.
class _SplashCourtPainter extends CustomPainter {
  const _SplashCourtPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              SportikaColors.mint.withValues(alpha: .09),
              SportikaColors.deepest.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * .5, size.height * .4),
              radius: size.longestSide * .48,
            ),
          );
    canvas.drawRect(Offset.zero & size, glow);

    final lines = Paint()
      ..color = SportikaColors.mint.withValues(alpha: .055)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.save();
    canvas.translate(size.width * .5, size.height * .45);
    canvas.rotate(-.22);
    final court = Rect.fromCenter(
      center: Offset.zero,
      width: size.width * 1.35,
      height: size.height * .62,
    );
    canvas.drawRect(court, lines);
    canvas.drawLine(Offset(court.left, 0), Offset(court.right, 0), lines);
    canvas.drawLine(Offset(0, court.top), Offset(0, court.bottom), lines);
    canvas.drawCircle(Offset.zero, size.width * .28, lines);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SplashCourtPainter oldDelegate) => false;
}
