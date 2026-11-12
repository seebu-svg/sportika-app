import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

class _Slide {
  const _Slide({
    required this.number,
    required this.eyebrow,
    required this.title,
    required this.accent,
    required this.body,
    required this.sport,
    required this.alignment,
  });

  final String number;
  final String eyebrow;
  final String title;
  final String accent;
  final String body;
  final Sport sport;
  final Alignment alignment;
}

const List<_Slide> _slides = [
  _Slide(
    number: '01',
    eyebrow: 'PRIVATE SCORECARDS',
    title: 'EVERY MATCH',
    accent: 'IS A STORY.',
    body:
        'Keep ball-by-ball and rally-by-rally scorecards for cricket, padel, '
        'futsal and badminton. Every tap saves itself.',
    sport: Sport.cricket,
    alignment: Alignment(0, -.15),
  ),
  _Slide(
    number: '02',
    eyebrow: 'TOURNAMENTS',
    title: 'RUN THE',
    accent: 'WHOLE EVENT.',
    body:
        'Draws, fixtures and live scoring in one place. Results stay provisional '
        'until the organizer publishes them.',
    sport: Sport.futsal,
    alignment: Alignment(0, -.1),
  ),
  _Slide(
    number: '03',
    eyebrow: 'COMMUNITY',
    title: 'YOUR GAME.',
    accent: 'YOUR PEOPLE.',
    body:
        'Build squads, join community games and follow the tournaments your city '
        'is playing this week.',
    sport: Sport.padel,
    alignment: Alignment(0, 0),
  ),
];

/// 02 · Three-slide onboarding carousel. Photography carries each slide;
/// navigation stays in the thumb zone and never blocks the swipe.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final PageController _pages;

  @override
  void initState() {
    super.initState();
    final start = context.read<AuthFlowController>().onboardingIndex;
    _pages = PageController(initialPage: start.clamp(0, _slides.length - 1));
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();
    final index = flow.onboardingIndex.clamp(0, _slides.length - 1);
    final last = index == _slides.length - 1;

    return Scaffold(
      backgroundColor: SportikaColors.deepest,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: _slides.length,
            onPageChanged: flow.setOnboardingIndex,
            itemBuilder: (context, i) => _SlideView(slide: _slides[i]),
          ),
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 150,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x99061426), Color(0x00061426)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                height: 260,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      SportikaColors.deepest.withValues(alpha: 0),
                      SportikaColors.deepest.withValues(alpha: .86),
                      SportikaColors.deepest,
                    ],
                    stops: const [0, .45, 1],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 14, 0),
                  child: Row(
                    children: [
                      const BrandMark(size: 26),
                      const SizedBox(width: 10),
                      const Text(
                        'SPORTIKA',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.6,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: flow.finishOnboarding,
                        style: TextButton.styleFrom(
                          foregroundColor: SportikaColors.textMuted,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: const Size(0, 34),
                        ),
                        child: const Text(
                          'SKIP',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (var i = 0; i < _slides.length; i++)
                            GestureDetector(
                              onTap: () => _pages.animateToPage(
                                i,
                                duration: const Duration(milliseconds: 380),
                                curve: Curves.easeOutCubic,
                              ),
                              behavior: HitTestBehavior.opaque,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOutCubic,
                                height: 3,
                                width: i == index ? 30 : 14,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: i == index
                                      ? SportikaColors.mint
                                      : SportikaColors.borderStrong,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          const Spacer(),
                          Text(
                            '${_slides[index].number} / 03',
                            style: authDisplay(
                              12,
                              color: SportikaColors.textDim,
                              letterSpacing: 1.6,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      AuthAction(
                        label: last ? 'GET STARTED' : 'NEXT',
                        onPressed: () {
                          if (last) {
                            flow.finishOnboarding();
                            return;
                          }
                          _pages.nextPage(
                            duration: const Duration(milliseconds: 420),
                            curve: Curves.easeOutCubic,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AuthPhoto(sport: slide.sport, alignment: slide.alignment),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x40061426),
                Color(0x66061426),
                Color(0xE6061426),
                SportikaColors.deepest,
              ],
              stops: [0, .35, .62, .9],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 158),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                AuthEyebrow('${slide.number} — ${slide.eyebrow}'),
                const SizedBox(height: 16),
                AuthHeadline(slide.title, accent: slide.accent, size: 44),
                const SizedBox(height: 16),
                AuthLead(slide.body),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
