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
    eyebrow: 'DISCOVER GAMES',
    title: 'YOUR NEXT',
    accent: 'GAME AWAITS.',
    body: 'Find a cricket game nearby, explore local fixtures and make time for the sport you love.',
    sport: Sport.cricket,
    alignment: Alignment(0, .1),
  ),
  _Slide(
    number: '02',
    eyebrow: 'CONNECT WITH PLAYERS',
    title: 'FIND YOUR',
    accent: 'PEOPLE.',
    body: 'Meet players who share your passion. Find a padel partner, join a team and build your sporting community.',
    sport: Sport.padel,
    alignment: Alignment(0, 0),
  ),
  _Slide(
    number: '03',
    eyebrow: 'MATCHES & TOURNAMENTS',
    title: 'BRING THE',
    accent: 'GAME TO LIFE.',
    body: 'Create a futsal match or run a tournament. Bring teams together, build the draw and manage your event with one account.',
    sport: Sport.futsal,
    alignment: Alignment(.15, -.1),
  ),
  _Slide(
    number: '04',
    eyebrow: 'SCORES & PERFORMANCE',
    title: 'EVERY POINT.',
    accent: 'YOUR PROGRESS.',
    body: 'Track badminton rallies and scores across all four sports. Keep personal scorecards and follow your official match history.',
    sport: Sport.badminton,
    alignment: Alignment(.2, -.15),
  ),
];

/// Four sport stories over bundled photography, with a persistent action area.
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

  void _goTo(int index, bool reduceMotion) {
    if (reduceMotion) {
      _pages.jumpToPage(index);
    } else {
      _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();
    final index = flow.onboardingIndex.clamp(0, _slides.length - 1);
    final last = index == _slides.length - 1;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final footerInset =
        164.0 +
        (textScale - 1).clamp(0, 2) * 36 +
        (flow.inlineError == null ? 0 : 100);

    return Scaffold(
      backgroundColor: SportikaColors.deepest,
      body: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: SportikaType.bodyFamily),
        child: LayoutBuilder(
          builder: (context, viewport) {
            final sidePadding = viewport.maxWidth > 760
                ? (viewport.maxWidth - 680) / 2
                : 24.0;
            final showCounter =
                viewport.maxWidth - sidePadding * 2 > 176 + 100 * textScale;
            return Stack(
              children: [
                PageView.builder(
                  controller: _pages,
                  itemCount: _slides.length,
                  onPageChanged: flow.setOnboardingIndex,
                  allowImplicitScrolling: true,
                  itemBuilder: (context, i) => AnimatedBuilder(
                    animation: _pages,
                    builder: (context, _) => _SlideView(
                      slide: _slides[i],
                      sidePadding: sidePadding,
                      footerInset: footerInset,
                      distance: reduceMotion
                          ? 0
                          : ((_pages.hasClients ? _pages.page : null) ??
                                    index.toDouble()) -
                                i,
                    ),
                  ),
                ),
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 150,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: SportikaGradients.onboardingTopFade,
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
                      decoration: const BoxDecoration(
                        gradient: SportikaGradients.onboardingBottomFade,
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
                                fontWeight: SportikaFontWeight.black,
                                letterSpacing: 2.6,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: flow.busy
                                  ? null
                                  : flow.finishOnboarding,
                              style: TextButton.styleFrom(
                                foregroundColor: SportikaColors.textMuted,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                minimumSize: const Size(48, 48),
                              ),
                              child: const Text(
                                'SKIP',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: SportikaFontWeight.extraBold,
                                  letterSpacing: 1.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          sidePadding,
                          0,
                          sidePadding,
                          22,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                for (var i = 0; i < _slides.length; i++)
                                  Semantics(
                                    label:
                                        'Slide ${i + 1} of ${_slides.length}: ${_slides[i].sport.label}',
                                    selected: i == index,
                                    button: true,
                                    child: Tooltip(
                                      message:
                                          'Go to ${_slides[i].sport.label}',
                                      child: InkWell(
                                        onTap: flow.busy
                                            ? null
                                            : () => _goTo(i, reduceMotion),
                                        borderRadius: BorderRadius.circular(
                                          SportikaRadius.tag,
                                        ),
                                        child: SizedBox(
                                          width: 44,
                                          height: 48,
                                          child: Center(
                                            child: AnimatedContainer(
                                              duration: reduceMotion
                                                  ? Duration.zero
                                                  : const Duration(
                                                      milliseconds: 280,
                                                    ),
                                              curve: Curves.easeOutCubic,
                                              height: 3,
                                              width: i == index ? 30 : 14,
                                              decoration: BoxDecoration(
                                                color: i == index
                                                    ? SportikaColors.mint
                                                    : SportikaColors
                                                          .borderStrong,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      SportikaRadius.xxs,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                const Spacer(),
                                if (showCounter)
                                  Text(
                                    '${_slides[index].number} / 04',
                                    style: authDisplay(
                                      12,
                                      color: SportikaColors.textDim,
                                      letterSpacing: 1.6,
                                    ),
                                  ),
                              ],
                            ),
                            if (flow.inlineError != null)
                              Semantics(
                                liveRegion: true,
                                child: AuthNotice(
                                  flow.inlineError!,
                                  tone: SportikaColors.danger,
                                ),
                              ),
                            const SizedBox(height: 8),
                            AuthAction(
                              label: last ? 'GET STARTED' : 'NEXT',
                              busy: flow.busy,
                              onPressed: flow.busy
                                  ? null
                                  : () {
                                      if (last) {
                                        flow.finishOnboarding();
                                      } else {
                                        _goTo(index + 1, reduceMotion);
                                      }
                                    },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({
    required this.slide,
    required this.sidePadding,
    required this.footerInset,
    required this.distance,
  });

  final _Slide slide;
  final double sidePadding, footerInset, distance;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          child: Transform.scale(
            scale: 1 + distance.abs().clamp(0, 1) * .045,
            child: AuthPhoto(sport: slide.sport, alignment: slide.alignment),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: SportikaGradients.onboardingSlideScrim,
          ),
        ),
        SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              sidePadding,
              80,
              sidePadding,
              footerInset,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: AuthEyebrow(
                          '${slide.number} · ${slide.sport.label.toUpperCase()}',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        slide.eyebrow,
                        style: authDisplay(
                          16,
                          color: SportikaColors.mint,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      AuthHeadline(
                        slide.title,
                        accent: slide.accent,
                        size: constraints.maxHeight < 300 ? 36 : 48,
                      ),
                      const SizedBox(height: 16),
                      AuthLead(slide.body),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
