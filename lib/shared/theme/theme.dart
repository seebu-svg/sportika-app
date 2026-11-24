import 'package:flutter/material.dart';

import 'package:sportika/features/personal_games/scoring/engine.dart'
    as scoring;
import 'package:sportika/shared/theme/component_themes.dart';
import 'package:sportika/shared/theme/motion.dart';
import 'package:sportika/shared/theme/theme_extension.dart';
import 'package:sportika/shared/theme/tokens.dart';
import 'package:sportika/shared/theme/typography.dart';

// --------------------------------------------------
// SPORTIKA THEME BARREL
// --------------------------------------------------

export 'package:sportika/shared/theme/effects.dart';
export 'package:sportika/shared/theme/gradients.dart';
export 'package:sportika/shared/theme/imagery.dart';
export 'package:sportika/shared/theme/motion.dart';
export 'package:sportika/shared/theme/sport_identity.dart';
export 'package:sportika/shared/theme/theme_extension.dart';
export 'package:sportika/shared/theme/tokens.dart';
export 'package:sportika/shared/theme/typography.dart';

// --------------------------------------------------
// SCORING ACTION ADAPTER
// --------------------------------------------------

/// Backward-compatible scoring action colors.
@immutable
class ThemeColors {
  const ThemeColors(this.fill, this.border, this.fg);

  final Color fill;
  final Color border;
  final Color fg;

  factory ThemeColors.fromAction(SportikaActionColors colors) {
    return ThemeColors(colors.fill, colors.border, colors.fg);
  }
}

/// Maps scoring engine actions to semantic action roles.
SportikaActionRole _roleFor(scoring.ActionStyle style) {
  return switch (style) {
    scoring.ActionStyle.primary => SportikaActionRole.primary,
    scoring.ActionStyle.highlight => SportikaActionRole.highlight,
    scoring.ActionStyle.danger => SportikaActionRole.danger,
    scoring.ActionStyle.subtle => SportikaActionRole.subtle,
    scoring.ActionStyle.neutral => SportikaActionRole.neutral,
  };
}

/// Existing API preserved.
///
/// This function is brightness-aware but does not
/// require a BuildContext.
ThemeColors styleColors(
  scoring.ActionStyle style, {
  Brightness brightness = Brightness.dark,
}) {
  final theme = SportikaTheme.forBrightness(brightness);

  final colors = theme.action(_roleFor(style));

  return ThemeColors.fromAction(colors);
}

/// Preferred API for scoring widgets.
///
/// Uses the actual active theme, including custom
/// brand palettes and action interaction states.
ThemeColors styleColorsOf(
  BuildContext context,
  scoring.ActionStyle style, {
  SportikaActionState state = SportikaActionState.normal,
}) {
  final colors = context.sportika.action(_roleFor(style), state: state);

  return ThemeColors.fromAction(colors);
}

// --------------------------------------------------
// COLOR SCHEME
// --------------------------------------------------

/// Canonical Sportika Material 3 color scheme.
///
/// All colors come from shared design tokens.
/// Screens and widgets must not redefine colors.
ColorScheme sportikaColorScheme({Brightness brightness = Brightness.dark}) {
  if (brightness == Brightness.light) {
    return const ColorScheme.light(
      primary: SportikaColors.blue,
      onPrimary: SportikaColors.onAccent,
      primaryContainer: SportikaColors.lightBlue,
      onPrimaryContainer: SportikaColors.blueDeep,

      secondary: SportikaColors.mintDeep,
      onSecondary: SportikaColors.onAccent,
      secondaryContainer: SportikaColors.lightMint,
      onSecondaryContainer: SportikaColors.lightMintText,

      tertiary: SportikaColors.goldDeep,
      onTertiary: SportikaColors.onAccent,

      error: SportikaColors.danger,
      onError: SportikaColors.onAccent,

      surface: SportikaColors.lightSurface,
      onSurface: SportikaColors.lightText,

      surfaceDim: SportikaColors.lightSurfaceAlt,
      surfaceBright: SportikaColors.lightSurface,

      surfaceContainerLowest: SportikaColors.lightSurface,
      surfaceContainerLow: SportikaColors.lightSurfaceAlt,
      surfaceContainer: SportikaColors.lightSurfaceAlt,
      surfaceContainerHigh: SportikaColors.lightBorder,
      surfaceContainerHighest: SportikaColors.lightBorder,

      onSurfaceVariant: SportikaColors.lightTextMuted,

      outline: SportikaPalette.slate400,
      outlineVariant: SportikaColors.lightBorder,

      shadow: SportikaPalette.black,
      scrim: SportikaColors.deepest,

      inverseSurface: SportikaColors.lightText,
      onInverseSurface: SportikaColors.lightSurface,
      inversePrimary: SportikaColors.blue,
    );
  }

  return const ColorScheme.dark(
    primary: SportikaColors.blue,
    onPrimary: SportikaColors.onAccent,
    primaryContainer: SportikaColors.surfaceAlt,
    onPrimaryContainer: SportikaColors.text,

    secondary: SportikaColors.mint,
    onSecondary: SportikaColors.onMint,
    secondaryContainer: SportikaColors.surfaceAlt,
    onSecondaryContainer: SportikaColors.mint,

    tertiary: SportikaColors.gold,
    onTertiary: SportikaColors.deepest,
    tertiaryContainer: SportikaColors.surfaceAlt,
    onTertiaryContainer: SportikaColors.gold,

    error: SportikaColors.danger,
    onError: SportikaColors.onAccent,
    errorContainer: SportikaColors.dangerDeep,
    onErrorContainer: SportikaColors.dangerBright,

    surface: SportikaColors.surface,
    onSurface: SportikaColors.text,

    surfaceDim: SportikaColors.page,
    surfaceBright: SportikaColors.surfaceAlt,

    surfaceContainerLowest: SportikaColors.surfaceSunken,
    surfaceContainerLow: SportikaColors.surface,
    surfaceContainer: SportikaColors.surface,
    surfaceContainerHigh: SportikaColors.surfaceAlt,
    surfaceContainerHighest: SportikaColors.surfaceHigh,

    onSurfaceVariant: SportikaColors.textMuted,

    outline: SportikaColors.borderStrong,
    outlineVariant: SportikaColors.border,

    shadow: SportikaColors.shadowBase,
    scrim: SportikaColors.deepest,

    inverseSurface: SportikaColors.text,
    onInverseSurface: SportikaColors.deepest,
    inversePrimary: SportikaColors.blueBright,
  );
}

// --------------------------------------------------
// THEME BUILDER
// --------------------------------------------------

/// Builds the complete Sportika Material 3 theme.
///
/// All screens consume the same global design system.
///
/// Visual profiles control the richness of effects,
/// not the underlying brand identity.
///
/// Standard is the recommended global default.
/// Cinematic should be used selectively for heroes.
/// Minimal is suitable for dense scoring interfaces.
ThemeData buildSportikaTheme({
  Brightness brightness = Brightness.dark,
  SportikaVisualProfile profile = SportikaVisualProfile.standard,
  SportikaDensity density = SportikaDensity.comfortable,
  SportikaMotionIntensity motionIntensity = SportikaMotionIntensity.standard,
  bool reducedEffects = false,
}) {
  // ------------------------------------------------
  // 1. MATERIAL COLOR SCHEME
  // ------------------------------------------------

  final scheme = sportikaColorScheme(brightness: brightness);

  // ------------------------------------------------
  // 2. TYPOGRAPHY
  // ------------------------------------------------

  final textTheme = SportikaType.textTheme(brightness: brightness);

  // ------------------------------------------------
  // 3. RESOLVED SPORTIKA DESIGN SYSTEM
  // ------------------------------------------------

  final sportika = SportikaTheme.fromScheme(
    scheme,
    profile: profile,
    density: density,
    motionIntensity: motionIntensity,
    reducedEffects: reducedEffects,
  );

  // ------------------------------------------------
  // 4. MATERIAL BASE
  // ------------------------------------------------

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,

    scaffoldBackgroundColor: sportika.page,

    fontFamily: SportikaType.bodyFamily,

    visualDensity: switch (density) {
      SportikaDensity.compact => VisualDensity.compact,

      SportikaDensity.comfortable => VisualDensity.standard,

      SportikaDensity.spacious => VisualDensity.comfortable,
    },

    // Consistent, restrained feedback across
    // Android, iOS and other supported platforms.
    splashFactory: InkRipple.splashFactory,

    // Maintain Material accessibility defaults.
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );

  // ------------------------------------------------
  // 5. GLOBAL TYPOGRAPHY AND ICONS
  // ------------------------------------------------

  final styled = base.copyWith(
    textTheme: textTheme,

    primaryTextTheme: textTheme.apply(
      bodyColor: scheme.onPrimary,
      displayColor: scheme.onPrimary,
    ),

    iconTheme: IconThemeData(
      color: sportika.textBody,
      size: SportikaIconSize.lg,
    ),

    primaryIconTheme: IconThemeData(
      color: scheme.onPrimary,
      size: SportikaIconSize.lg,
    ),

    // A single registered extension supplies
    // semantic surfaces, effects, motion, imagery
    // and sport-specific styling.
    extensions: [sportika],
  );

  // ------------------------------------------------
  // 6. MATERIAL COMPONENT THEMES
  // ------------------------------------------------

  // Component themes should read the registered
  // SportikaTheme extension rather than creating
  // their own colors or gradients.
  return SportikaComponentThemes.apply(styled);
}
