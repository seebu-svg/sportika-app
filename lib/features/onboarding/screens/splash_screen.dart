import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

/// 01 · Splash. Brand-first, one photograph, and a finite progress rail so the
/// prototype never leaves the user on an indeterminate spinner.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = context.read<AuthFlowController>();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: flow.continueFromSplash,
      child: Scaffold(
        backgroundColor: SportikaColors.deepest,
        body: Stack(
          children: [
            const Positioned.fill(
              child: AuthPhoto(
                sport: Sport.cricket,
                alignment: Alignment(0, -.2),
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x99061426),
                      Color(0x59061426),
                      Color(0xE6061426),
                      SportikaColors.deepest,
                    ],
                    stops: [0, .3, .62, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              left: -80,
              bottom: 90,
              child: Container(
                height: 220,
                width: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      SportikaColors.mint.withValues(alpha: .13),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 18, 26, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: AuthEyebrow('Karachi · Est. 2026'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'PRE-AUTH',
                          style: authDisplay(
                            11,
                            color: SportikaColors.textDim,
                            letterSpacing: 2.2,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(flex: 3),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) => Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, 16 * (1 - value)),
                          child: child,
                        ),
                      ),
                      child: const BrandMark(size: 62, showWordmark: true),
                    ),
                    const SizedBox(height: 30),
                    const AuthHeadline(
                      'THE GAME',
                      accent: 'CONNECTS US.',
                      size: 50,
                    ),
                    const SizedBox(height: 14),
                    const AuthLead(
                      'Scorecards, tournaments and the people you play with — '
                      'one calm place for four sports.',
                      maxWidth: 300,
                    ),
                    const Spacer(flex: 2),
                    const AuthRule(),
                    const SizedBox(height: 14),
                    Text(
                      'CRICKET  ·  PADEL  ·  FUTSAL  ·  BADMINTON',
                      style: authDisplay(
                        11,
                        color: SportikaColors.textMuted,
                        letterSpacing: 1.7,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 2,
                            color: SportikaColors.border,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: 1),
                                duration: const Duration(milliseconds: 1650),
                                curve: Curves.easeInOutCubic,
                                builder: (context, value, _) =>
                                    FractionallySizedBox(
                                      widthFactor: value,
                                      child: Container(
                                        color: SportikaColors.mint,
                                      ),
                                    ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              'PREPARING YOUR GAME',
                              style: authDisplay(
                                9.5,
                                color: SportikaColors.textDim,
                                letterSpacing: 1.8,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
