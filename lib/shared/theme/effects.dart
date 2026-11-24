import 'package:flutter/material.dart';

import 'package:sportika/shared/theme/tokens.dart';

/// Unified elevation levels for the Sportika design system.
enum SportikaElevation { flat, soft, card, elevated, hero }

/// Glow intensity for branded and sport-specific elements.
enum SportikaGlowIntensity { subtle, standard, strong, ambient }

/// Controlled glass variants.
enum SportikaGlassVariant { subtle, standard, immersive }

/// Centralized shadow, elevation and glow recipes.
///
/// Existing static shadow presets are preserved for compatibility.
/// New screens should prefer [resolve] with the active ColorScheme.
abstract final class SportikaShadows {
  SportikaShadows._();

  static const List<BoxShadow> none = <BoxShadow>[];

  // --------------------------------------------------
  // LEGACY PRESETS
  // --------------------------------------------------

  static const List<BoxShadow> soft = [
    BoxShadow(color: Color(0x29030A14), blurRadius: 8, offset: Offset(0, 3)),
  ];

  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x47030A14), blurRadius: 16, offset: Offset(0, 8)),
  ];

  static const List<BoxShadow> lifted = [
    BoxShadow(color: Color(0x5C030A14), blurRadius: 26, offset: Offset(0, 14)),
  ];

  static const List<BoxShadow> elevated = [
    BoxShadow(color: Color(0x52030A14), blurRadius: 22, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x141769FF), blurRadius: 2, spreadRadius: 1),
  ];

  static const List<BoxShadow> panel = [
    BoxShadow(color: Color(0x4D030A14), blurRadius: 18, offset: Offset(0, 10)),
  ];

  static const List<BoxShadow> passport = [
    BoxShadow(color: Color(0x66030A14), blurRadius: 30, offset: Offset(0, 16)),
    BoxShadow(color: Color(0x145B82AB), blurRadius: 2, spreadRadius: 1),
  ];

  static const List<BoxShadow> hero = [
    BoxShadow(color: Color(0x73030A14), blurRadius: 38, offset: Offset(0, 20)),
  ];

  static const List<BoxShadow> brandGlow = [
    BoxShadow(
      color: Color(0x591769FF),
      blurRadius: 18,
      spreadRadius: -4,
      offset: Offset(0, 8),
    ),
  ];

  static const List<BoxShadow> brandAmbient = [
    BoxShadow(
      color: Color(0x381769FF),
      blurRadius: 56,
      spreadRadius: 2,
      offset: Offset(0, 18),
    ),
  ];

  // --------------------------------------------------
  // BRIGHTNESS-AWARE ELEVATION
  // --------------------------------------------------

  /// Resolves shadows based on the current theme.
  ///
  /// Reduced effects disables decorative shadows.
  static List<BoxShadow> resolve({
    required ColorScheme scheme,
    SportikaElevation level = SportikaElevation.card,
    bool reducedEffects = false,
  }) {
    if (reducedEffects || level == SportikaElevation.flat) {
      return none;
    }

    final isDark = scheme.brightness == Brightness.dark;

    final shadowColor = scheme.shadow;

    final opacity = isDark ? 1.0 : 0.55;

    switch (level) {
      case SportikaElevation.flat:
        return none;

      case SportikaElevation.soft:
        return [
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.12 * opacity),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ];

      case SportikaElevation.card:
        return [
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.20 * opacity),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ];

      case SportikaElevation.elevated:
        return [
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.26 * opacity),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.07),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ];

      case SportikaElevation.hero:
        return [
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.34 * opacity),
            blurRadius: 38,
            offset: const Offset(0, 20),
          ),
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.08),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ];
    }
  }

  // --------------------------------------------------
  // BRAND GLOW
  // --------------------------------------------------

  /// Modern glow with centralized intensity.
  static List<BoxShadow> brandedGlow({
    required Color color,
    SportikaGlowIntensity intensity = SportikaGlowIntensity.standard,
    bool reducedEffects = false,
  }) {
    if (reducedEffects) return none;

    final double alpha;
    final double blur;
    final double spread;
    final Offset offset;

    switch (intensity) {
      case SportikaGlowIntensity.subtle:
        alpha = 0.12;
        blur = 10;
        spread = -3;
        offset = const Offset(0, 4);

      case SportikaGlowIntensity.standard:
        alpha = 0.22;
        blur = 18;
        spread = -4;
        offset = const Offset(0, 8);

      case SportikaGlowIntensity.strong:
        alpha = 0.34;
        blur = 28;
        spread = -2;
        offset = const Offset(0, 10);

      case SportikaGlowIntensity.ambient:
        alpha = 0.14;
        blur = 56;
        spread = 2;
        offset = const Offset(0, 18);
    }

    return [
      BoxShadow(
        color: color.withValues(alpha: alpha),
        blurRadius: blur,
        spreadRadius: spread,
        offset: offset,
      ),
    ];
  }

  /// Brand glow from the current ColorScheme.
  static List<BoxShadow> primaryGlow(
    ColorScheme scheme, {
    SportikaGlowIntensity intensity = SportikaGlowIntensity.standard,
    bool reducedEffects = false,
  }) {
    return brandedGlow(
      color: scheme.primary,
      intensity: intensity,
      reducedEffects: reducedEffects,
    );
  }

  /// Live match glow, using the theme's secondary accent.
  static List<BoxShadow> liveGlow(
    ColorScheme scheme, {
    bool reducedEffects = false,
  }) {
    return brandedGlow(
      color: scheme.secondary,
      intensity: SportikaGlowIntensity.subtle,
      reducedEffects: reducedEffects,
    );
  }

  /// Achievement glow using the tertiary accent.
  static List<BoxShadow> achievementGlow(
    ColorScheme scheme, {
    bool reducedEffects = false,
  }) {
    return brandedGlow(
      color: scheme.tertiary,
      intensity: SportikaGlowIntensity.standard,
      reducedEffects: reducedEffects,
    );
  }

  /// Sport-specific glow. Pass a color from
  /// the existing Sportika sport identity system.
  static List<BoxShadow> sportGlow(
    Color sportColor, {
    SportikaGlowIntensity intensity = SportikaGlowIntensity.subtle,
    bool reducedEffects = false,
  }) {
    return brandedGlow(
      color: sportColor,
      intensity: intensity,
      reducedEffects: reducedEffects,
    );
  }

  // --------------------------------------------------
  // DIRECTIONAL LIGHTING
  // --------------------------------------------------

  /// Directional ambient light for hero surfaces.
  static List<BoxShadow> directionalAmbient({
    required Color color,
    Alignment direction = Alignment.topLeft,
    bool reducedEffects = false,
  }) {
    if (reducedEffects) return none;

    return [
      BoxShadow(
        color: color.withValues(alpha: 0.16),
        blurRadius: 48,
        spreadRadius: -4,
        offset: Offset(-direction.x * 12, -direction.y * 12),
      ),
    ];
  }

  // --------------------------------------------------
  // LEGACY METHODS
  // --------------------------------------------------

  /// Preserved for existing screens.
  static List<BoxShadow> glow(Color tone, {double strength = 1}) {
    final safeStrength = strength.clamp(0.0, 3.0);

    return [
      BoxShadow(
        color: tone.withValues(
          alpha: (SportikaOpacity.medium * safeStrength).clamp(0.0, 1.0),
        ),
        blurRadius: 18 * safeStrength,
        spreadRadius: -4,
        offset: Offset(0, 8 * safeStrength),
      ),
    ];
  }

  /// Preserved for existing hero surfaces.
  static List<BoxShadow> ambient(Color tone, {double strength = 1}) {
    final safeStrength = strength.clamp(0.0, 3.0);

    return [
      BoxShadow(
        color: tone.withValues(
          alpha: (SportikaOpacity.muted * safeStrength).clamp(0.0, 1.0),
        ),
        blurRadius: 56 * safeStrength,
        spreadRadius: 2,
        offset: const Offset(0, 18),
      ),
    ];
  }

  /// Legacy accent glow for scoring controls.
  static List<BoxShadow> accent(Color tone) {
    return [
      BoxShadow(
        color: tone.withValues(alpha: SportikaOpacity.medium),
        blurRadius: 6,
        offset: const Offset(0, 1),
      ),
    ];
  }
}

/// Centralized glassmorphism recipes.
///
/// The decoration controls tint, borders and shadows.
/// Actual backdrop blur must be applied by a BackdropFilter.
abstract final class SportikaGlass {
  SportikaGlass._();

  // --------------------------------------------------
  // LEGACY CONSTANTS
  // --------------------------------------------------

  static const double blurSigma = 18;
  static const double heavyBlurSigma = 26;

  static const Color tint = Color(0xA60F2340);
  static const Color strongTint = Color(0xCC0A1B31);
  static const Color border = Color(0x29FFFFFF);
  static const Color highlight = Color(0x1AFFFFFF);

  // --------------------------------------------------
  // VARIANT RESOLUTION
  // --------------------------------------------------

  static double blurFor(
    SportikaGlassVariant variant, {
    bool reducedEffects = false,
  }) {
    if (reducedEffects) return 0;

    switch (variant) {
      case SportikaGlassVariant.subtle:
        return 10;
      case SportikaGlassVariant.standard:
        return blurSigma;
      case SportikaGlassVariant.immersive:
        return heavyBlurSigma;
    }
  }

  /// Resolves a semantic glass tint.
  static Color tintFor(
    ColorScheme scheme, {
    SportikaGlassVariant variant = SportikaGlassVariant.standard,
    bool reducedEffects = false,
  }) {
    if (reducedEffects) {
      return scheme.surfaceContainerHigh;
    }

    final isDark = scheme.brightness == Brightness.dark;

    final base = isDark
        ? scheme.surfaceContainerLowest
        : scheme.surfaceContainerHighest;

    final double opacity;

    switch (variant) {
      case SportikaGlassVariant.subtle:
        opacity = isDark ? 0.58 : 0.70;
      case SportikaGlassVariant.standard:
        opacity = isDark ? 0.76 : 0.82;
      case SportikaGlassVariant.immersive:
        opacity = isDark ? 0.90 : 0.94;
    }

    return base.withValues(alpha: opacity);
  }

  /// Glass edge color adapted to the current theme.
  static Color borderFor(
    ColorScheme scheme, {
    SportikaGlassVariant variant = SportikaGlassVariant.standard,
  }) {
    final alpha = switch (variant) {
      SportikaGlassVariant.subtle => 0.10,
      SportikaGlassVariant.standard => 0.16,
      SportikaGlassVariant.immersive => 0.22,
    };

    return scheme.onSurface.withValues(alpha: alpha);
  }

  /// Top-edge illumination for premium glass panels.
  static Color highlightFor(ColorScheme scheme) {
    return scheme.onSurface.withValues(
      alpha: scheme.brightness == Brightness.dark ? 0.12 : 0.08,
    );
  }

  // --------------------------------------------------
  // SEMANTIC GLASS DECORATION
  // --------------------------------------------------

  static BoxDecoration themedDecoration({
    required ColorScheme scheme,
    SportikaGlassVariant variant = SportikaGlassVariant.standard,
    double radius = SportikaRadius.xl,
    List<BoxShadow>? shadow,
    bool reducedEffects = false,
  }) {
    return BoxDecoration(
      color: tintFor(scheme, variant: variant, reducedEffects: reducedEffects),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderFor(scheme, variant: variant)),
      boxShadow: reducedEffects ? null : shadow,
    );
  }

  // --------------------------------------------------
  // LEGACY DECORATION
  // --------------------------------------------------

  /// Existing API preserved for compatibility.
  static BoxDecoration decoration({
    double radius = SportikaRadius.xl,
    Color? color,
    Color? borderColor,
    List<BoxShadow>? shadow,
  }) {
    return BoxDecoration(
      color: color ?? tint,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? border),
      boxShadow: shadow,
    );
  }
}
