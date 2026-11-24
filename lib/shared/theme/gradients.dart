import 'package:flutter/material.dart';

import 'package:sportika/shared/theme/tokens.dart';

/// Visual intensity of a Sportika gradient.
///
/// Subtle: backgrounds and restrained depth.
/// Standard: featured surfaces and sport panels.
/// Strong: premium hero cards and athlete passports.
/// Cinematic: full-bleed photography and onboarding.
enum SportikaGradientIntensity { subtle, standard, strong, cinematic }

/// Shared media overlay treatments.
enum SportikaMediaScrim { card, tile, editorial, hero, immersive }

/// Placement of readable content over an image.
enum SportikaScrimDirection { bottom, top, start, end }

/// Centralized gradient recipes for the Sportika design system.
///
/// Gradients are reserved for:
/// - Hero artwork and featured sports content
/// - Athlete passports and signature surfaces
/// - Primary actions and live states
/// - Image scrims and branded atmosphere
///
/// Everyday cards, lists, forms and controls use flat theme surfaces.
abstract final class SportikaGradients {
  SportikaGradients._();

  // --------------------------------------------------
  // SHARED CONFIGURATION
  // --------------------------------------------------

  static const Alignment _lightSource = Alignment(-0.85, -1.0);

  static const Alignment _actionStart = Alignment.topLeft;

  static const Alignment _actionEnd = Alignment.bottomRight;

  static const Alignment _imageStart = Alignment.topCenter;

  static const Alignment _imageEnd = Alignment.bottomCenter;

  static double _intensity(SportikaGradientIntensity intensity) {
    return switch (intensity) {
      SportikaGradientIntensity.subtle => 0.35,
      SportikaGradientIntensity.standard => 0.60,
      SportikaGradientIntensity.strong => 0.85,
      SportikaGradientIntensity.cinematic => 1.0,
    };
  }

  static Color _blend(Color source, Color target, double amount) {
    return Color.lerp(source, target, amount.clamp(0.0, 1.0))!;
  }

  // --------------------------------------------------
  // BRAND ATMOSPHERE
  // --------------------------------------------------

  /// Original stadium lighting preset.
  static const RadialGradient atmosphere = RadialGradient(
    center: Alignment(.85, -1),
    radius: 1.15,
    colors: [
      SportikaPalette.mintAtmosphere,
      SportikaPalette.indigoAtmosphere,
      SportikaPalette.navyClear,
    ],
    stops: [0, .35, 1],
  );

  /// Original cooler brand atmosphere.
  static const RadialGradient brandAtmosphere = RadialGradient(
    center: Alignment(-.9, -1.05),
    radius: 1.3,
    colors: [SportikaPalette.blueAtmosphere, SportikaPalette.navyClear],
  );

  /// Light mode atmosphere.
  static const LinearGradient lightAtmosphere = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [SportikaColors.lightSurfaceAlt, SportikaColors.lightSurface],
  );

  /// Splash screen illumination.
  static const RadialGradient splashGlow = RadialGradient(
    colors: [SportikaPalette.mintGlow, SportikaPalette.navyClear],
  );

  /// Brightness-aware stadium atmosphere.
  static RadialGradient stadiumAtmosphere({
    required ColorScheme scheme,
    SportikaGradientIntensity intensity = SportikaGradientIntensity.standard,
    bool reducedEffects = false,
  }) {
    final base = scheme.surface;
    final strength = reducedEffects ? 0.0 : _intensity(intensity);

    return RadialGradient(
      center: _lightSource,
      radius: 1.35,
      colors: [
        _blend(base, scheme.primary, strength * 0.28),
        _blend(base, scheme.secondary, strength * 0.12),
        base,
      ],
      stops: const [0, 0.42, 1],
    );
  }

  /// Sport-specific stadium spotlight.
  static RadialGradient heroSpotlight(Color tone) {
    return RadialGradient(
      center: const Alignment(.78, -1),
      radius: 1.35,
      colors: [
        tone.withValues(alpha: SportikaOpacity.medium),
        SportikaPalette.navyClear,
      ],
    );
  }

  /// Configurable spotlight for sport hero artwork.
  static RadialGradient sportSpotlight({
    required ColorScheme scheme,
    required Color sportColor,
    SportikaGradientIntensity intensity = SportikaGradientIntensity.standard,
    Alignment center = const Alignment(.78, -1),
    bool reducedEffects = false,
  }) {
    final strength = reducedEffects ? 0.0 : _intensity(intensity);

    return RadialGradient(
      center: center,
      radius: 1.35,
      colors: [
        sportColor.withValues(alpha: 0.38 * strength),
        scheme.surface.withValues(alpha: 0),
      ],
    );
  }

  /// Legacy photograph duotone.
  static LinearGradient photoDuotone(Color tone) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        tone.withValues(alpha: .55),
        SportikaColors.deepest.withValues(alpha: .88),
      ],
    );
  }

  // --------------------------------------------------
  // SIGNATURE SURFACES
  // --------------------------------------------------

  static const LinearGradient holographicSurface = LinearGradient(
    begin: Alignment(-1, -1),
    end: Alignment(1, 1),
    colors: [
      SportikaPalette.tealAlloy,
      SportikaColors.surface,
      SportikaPalette.indigoAlloy,
      SportikaColors.surfaceSunken,
    ],
    stops: [0, .36, .65, 1],
  );

  static const LinearGradient signatureSurface = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      SportikaPalette.tealAlloy,
      SportikaColors.surfaceAlt,
      SportikaPalette.indigoAlloy,
      SportikaColors.deepest,
    ],
    stops: [0, .32, .68, 1],
  );

  /// Legacy sport-tinted signature surface.
  static LinearGradient signatureSurfaceFor(Color tone) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        _blend(tone, SportikaColors.deepest, .78),
        SportikaColors.surfaceAlt,
        SportikaColors.deepest,
      ],
      stops: const [0, .5, 1],
    );
  }

  /// Brightness-aware signature surface.
  static LinearGradient themedSignatureSurface({
    required ColorScheme scheme,
    Color? sportColor,
    SportikaGradientIntensity intensity = SportikaGradientIntensity.standard,
    bool reducedEffects = false,
  }) {
    final base = scheme.surface;
    final tone = sportColor ?? scheme.primary;

    final strength = reducedEffects ? 0.0 : _intensity(intensity);

    return LinearGradient(
      begin: _actionStart,
      end: _actionEnd,
      colors: [
        _blend(base, tone, strength * 0.34),
        _blend(base, scheme.surfaceContainerHigh, 0.75),
        _blend(base, scheme.tertiary, strength * 0.12),
        scheme.surfaceContainerLowest,
      ],
      stops: const [0, 0.32, 0.68, 1],
    );
  }

  static const LinearGradient elevatedSurface = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [SportikaColors.surfaceAlt, SportikaColors.surface],
  );

  static const LinearGradient lightElevatedSurface = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [SportikaColors.lightSurface, SportikaColors.lightSurfaceAlt],
  );

  static const LinearGradient topSheen = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      SportikaPalette.whiteClear,
      Color(0x26FFFFFF),
      SportikaPalette.whiteClear,
    ],
    stops: [0, .5, 1],
  );

  static const LinearGradient sportPanel = holographicSurface;

  static const LinearGradient mediaSurface = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [SportikaColors.surfaceAlt, SportikaColors.surfaceSunken],
  );

  static const LinearGradient metallicMint = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      SportikaPalette.mintMetal,
      SportikaPalette.mintSpecular,
      SportikaColors.mint,
      SportikaPalette.mintMetal,
    ],
    stops: [0, .32, .62, 1],
  );

  // --------------------------------------------------
  // PRIMARY ACTIONS
  // --------------------------------------------------

  static const LinearGradient primaryAction = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      SportikaColors.blueBright,
      SportikaColors.blue,
      SportikaColors.blueDeep,
    ],
    stops: [0, .52, 1],
  );

  static const LinearGradient liveAction = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      SportikaColors.mintSoft,
      SportikaColors.mint,
      SportikaColors.mintDeep,
    ],
    stops: [0, .55, 1],
  );

  /// Theme-aware primary action gradient.
  static LinearGradient themedAction({
    required ColorScheme scheme,
    Color? tone,
    SportikaGradientIntensity intensity = SportikaGradientIntensity.standard,
    bool reducedEffects = false,
  }) {
    final accent = tone ?? scheme.primary;

    final strength = reducedEffects ? 0.0 : _intensity(intensity);

    return LinearGradient(
      begin: _actionStart,
      end: _actionEnd,
      colors: [
        _blend(accent, scheme.onPrimary, strength * 0.16),
        accent,
        _blend(accent, scheme.surface, strength * 0.30),
      ],
      stops: const [0, 0.52, 1],
    );
  }

  static LinearGradient accentFill(Color tone) {
    return LinearGradient(
      begin: _actionStart,
      end: _actionEnd,
      colors: [tone, _blend(tone, SportikaColors.onAccent, .14)],
    );
  }

  static LinearGradient progressFill(Color tone) {
    return LinearGradient(
      begin: _actionStart,
      end: _actionEnd,
      colors: [_blend(tone, SportikaColors.onAccent, .35), tone],
    );
  }

  static const LinearGradient progressTrack = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      SportikaColors.deepest,
      SportikaColors.surfaceSunken,
      Color(0x1FFFFFFF),
    ],
    stops: [0, .55, 1],
  );

  static LinearGradient sportCoin(Color tone) {
    return LinearGradient(
      begin: _actionStart,
      end: _actionEnd,
      colors: [
        tone.withValues(alpha: SportikaOpacity.muted),
        SportikaColors.surfaceSunken,
      ],
    );
  }

  static LinearGradient tonePanel(Color tone) {
    return LinearGradient(
      begin: _actionStart,
      end: _actionEnd,
      colors: [tone.withValues(alpha: .22), SportikaColors.surfaceSunken],
    );
  }

  static RadialGradient sportFallback(Color tone) {
    return RadialGradient(
      center: const Alignment(-.5, -.4),
      radius: 1.25,
      colors: [tone.withValues(alpha: .34), SportikaColors.deepest],
    );
  }

  static const LinearGradient coverSurface = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [SportikaColors.surfaceAlt, SportikaColors.deepest],
  );

  static const LinearGradient cardCoverFade = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [SportikaPalette.transparent, SportikaColors.surface],
  );

  // --------------------------------------------------
  // MEDIA SCRIM SYSTEM
  // --------------------------------------------------

  /// Shared scrim for image-backed surfaces.
  ///
  /// Direction controls where the strongest contrast appears.
  static LinearGradient mediaScrim({
    required ColorScheme scheme,
    SportikaMediaScrim variant = SportikaMediaScrim.card,
    SportikaScrimDirection direction = SportikaScrimDirection.bottom,
    SportikaGradientIntensity intensity = SportikaGradientIntensity.standard,
    bool reducedEffects = false,
  }) {
    final strength = reducedEffects ? 0.75 : _intensity(intensity);

    final base = scheme.brightness == Brightness.dark
        ? scheme.surfaceContainerLowest
        : scheme.scrim;

    final double density = switch (variant) {
      SportikaMediaScrim.card => 0.70,
      SportikaMediaScrim.tile => 0.82,
      SportikaMediaScrim.editorial => 0.88,
      SportikaMediaScrim.hero => 0.94,
      SportikaMediaScrim.immersive => 1.0,
    };

    final AlignmentGeometry begin;
    final AlignmentGeometry end;

    switch (direction) {
      case SportikaScrimDirection.bottom:
        begin = _imageStart;
        end = _imageEnd;

      case SportikaScrimDirection.top:
        begin = Alignment.bottomCenter;
        end = Alignment.topCenter;

      case SportikaScrimDirection.start:
        begin = AlignmentDirectional.centerEnd;
        end = AlignmentDirectional.centerStart;

      case SportikaScrimDirection.end:
        begin = AlignmentDirectional.centerStart;
        end = AlignmentDirectional.centerEnd;
    }

    final opacity = (density * strength).clamp(0.0, 1.0);

    return LinearGradient(
      begin: begin,
      end: end,
      colors: [
        base.withValues(alpha: 0.02),
        base.withValues(alpha: opacity * 0.50),
        base.withValues(alpha: opacity),
      ],
      stops: const [0, 0.48, 1],
    );
  }

  // --------------------------------------------------
  // GLASS AND HIGHLIGHTS
  // --------------------------------------------------

  static const LinearGradient glassPanel = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x1FFFFFFF), Color(0x00FFFFFF)],
  );

  static const LinearGradient heroWedge = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x1F36D8BD), Color(0x0036D8BD)],
  );

  static const LinearGradient winnerFill = LinearGradient(
    begin: AlignmentDirectional.centerStart,
    end: AlignmentDirectional.centerEnd,
    colors: [Color(0x2BF6B84B), Color(0x00F6B84B)],
  );

  static const LinearGradient winnerRule = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [SportikaColors.gold, SportikaColors.goldDeep],
  );

  static LinearGradient liveEdge(Color tone) {
    return LinearGradient(
      begin: AlignmentDirectional.centerStart,
      end: AlignmentDirectional.centerEnd,
      colors: [tone.withValues(alpha: 0), tone, tone.withValues(alpha: 0)],
    );
  }

  // --------------------------------------------------
  // LEGACY IMAGE TREATMENTS
  // --------------------------------------------------

  static const LinearGradient onboardingTopFade = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x99071426), SportikaPalette.navyClear],
  );

  static const LinearGradient onboardingBottomFade = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      SportikaPalette.midnightClear,
      Color(0xDB061120),
      SportikaColors.deepest,
    ],
    stops: [0, .45, 1],
  );

  static const LinearGradient onboardingSlideScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x40071426),
      Color(0x66071426),
      Color(0xE6071426),
      SportikaColors.deepest,
    ],
    stops: [0, .35, .62, .9],
  );

  static const LinearGradient authPhotoScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x40071426),
      Color(0xCC071426),
      SportikaColors.page,
      SportikaColors.page,
    ],
    stops: [0, .3, .58, .82],
  );

  static const LinearGradient sportCardScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x59071426), Color(0x33071426), Color(0xE6071426)],
    stops: [0, .4, 1],
  );

  static const LinearGradient editorialCard = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x0A071426), Color(0x88061120), Color(0xF5061120)],
    stops: [0, .4, 1],
  );

  static const LinearGradient imageFade = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [SportikaPalette.transparent, SportikaColors.deepest],
  );

  static const LinearGradient imageFadeStrong = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [SportikaPalette.transparent, Color(0xEB061120)],
  );

  static const LinearGradient feedBannerScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x14061120), Color(0xBD061120), Color(0xFF061120)],
    stops: [0, .45, 1],
  );

  static const LinearGradient feedTileScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x5C061120), Color(0xF0061120)],
  );

  static const LinearGradient cinematicHeroScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x0A061120), Color(0x8A061120), SportikaColors.deepest],
    stops: [0, .52, 1],
  );

  static const LinearGradient matchDetailScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x0F071426), Color(0x5C071426), SportikaColors.page],
    stops: [.42, .8, 1],
  );

  static const LinearGradient headerScrim = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [SportikaColors.page, Color(0xD6071426), Color(0x2E071426)],
    stops: [0, .56, 1],
  );

  static const LinearGradient headerSurfaceFade = LinearGradient(
    begin: AlignmentDirectional.centerStart,
    end: AlignmentDirectional.centerEnd,
    colors: [SportikaColors.surface, Color(0xD1102541), Color(0x8C102541)],
  );

  static const LinearGradient passportPortraitScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xB8061120), Color(0xDB061120), SportikaColors.deepest],
  );

  // --------------------------------------------------
  // COLLECTIBLES
  // --------------------------------------------------

  static const LinearGradient passport = signatureSurface;

  static const LinearGradient sheen = LinearGradient(
    colors: [
      SportikaPalette.whiteClear,
      Color(0x33FFFFFF),
      SportikaPalette.whiteClear,
    ],
  );

  static const LinearGradient goldRule = LinearGradient(
    colors: [
      SportikaPalette.goldClear,
      Color(0x40F6B84B),
      SportikaPalette.goldClear,
    ],
  );

  static const LinearGradient medalCabinet = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      SportikaColors.surfaceAlt,
      SportikaColors.surface,
      SportikaColors.surfaceSunken,
    ],
  );

  static const RadialGradient medalCoin = RadialGradient(
    center: Alignment(-.3, -.4),
    radius: 1.15,
    colors: [SportikaColors.surfaceAlt, SportikaColors.deepest],
  );

  static const RadialGradient medalCoinLocked = RadialGradient(
    center: Alignment(-.3, -.4),
    radius: 1.15,
    colors: [SportikaColors.surfaceSunken, SportikaColors.deepest],
  );

  static RadialGradient medalShade(Color tone) {
    return RadialGradient(
      center: const Alignment(-.3, -.4),
      colors: [tone, _blend(tone, SportikaColors.shadowBase, .55)],
    );
  }

  // --------------------------------------------------
  // AVATAR PRESETS
  // --------------------------------------------------

  static const List<Color> avatarMidnight = [
    Color(0xFF3B82FF),
    Color(0xFF102541),
  ];

  static const List<Color> avatarMint = [Color(0xFF36D8BD), Color(0xFF0A6C60)];

  static const List<Color> avatarGold = [Color(0xFFF6B84B), Color(0xFF9A5E0C)];

  static const List<Color> avatarCourt = [Color(0xFF3B82FF), Color(0xFF36D8BD)];

  static const List<Color> avatarEmber = [Color(0xFFFF6B70), Color(0xFF5C1018)];

  static const List<Color> avatarDusk = [Color(0xFFA8B8CF), Color(0xFF24486F)];
}
