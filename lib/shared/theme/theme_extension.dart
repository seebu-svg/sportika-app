import 'package:flutter/material.dart';

import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/theme/effects.dart';
import 'package:sportika/shared/theme/gradients.dart';
import 'package:sportika/shared/theme/imagery.dart';
import 'package:sportika/shared/theme/motion.dart';
import 'package:sportika/shared/theme/sport_identity.dart';
import 'package:sportika/shared/theme/tokens.dart';

/// Visual richness of a Sportika surface.
enum SportikaVisualProfile { minimal, standard, cinematic }

/// Semantic surfaces used throughout the app.
enum SportikaSurfaceRole {
  page,
  card,
  hero,
  interactive,
  selected,
  scoreboard,
  navigation,
  overlay,
  sunken,
}

/// Semantic action roles.
enum SportikaActionRole { primary, highlight, danger, subtle, neutral }

/// Visual state of an interactive control.
enum SportikaActionState {
  normal,
  hovered,
  focused,
  pressed,
  disabled,
  loading,
  selected,
}

/// Component density for different UI contexts.
enum SportikaDensity { compact, comfortable, spacious }

/// Resolved colors for a semantic action.
@immutable
class SportikaActionColors {
  const SportikaActionColors({
    required this.fill,
    required this.border,
    required this.fg,
  });

  final Color fill;
  final Color border;
  final Color fg;

  static SportikaActionColors lerp(
    SportikaActionColors a,
    SportikaActionColors b,
    double t,
  ) {
    return SportikaActionColors(
      fill: Color.lerp(a.fill, b.fill, t)!,
      border: Color.lerp(a.border, b.border, t)!,
      fg: Color.lerp(a.fg, b.fg, t)!,
    );
  }

  SportikaActionColors copyWith({Color? fill, Color? border, Color? fg}) {
    return SportikaActionColors(
      fill: fill ?? this.fill,
      border: border ?? this.border,
      fg: fg ?? this.fg,
    );
  }
}

/// Semantic action palette.
@immutable
class SportikaActionPalette {
  const SportikaActionPalette({
    required this.primary,
    required this.highlight,
    required this.danger,
    required this.subtle,
    required this.neutral,
  });

  final SportikaActionColors primary;
  final SportikaActionColors highlight;
  final SportikaActionColors danger;
  final SportikaActionColors subtle;
  final SportikaActionColors neutral;

  SportikaActionColors forRole(SportikaActionRole role) {
    return switch (role) {
      SportikaActionRole.primary => primary,
      SportikaActionRole.highlight => highlight,
      SportikaActionRole.danger => danger,
      SportikaActionRole.subtle => subtle,
      SportikaActionRole.neutral => neutral,
    };
  }

  static SportikaActionPalette lerp(
    SportikaActionPalette a,
    SportikaActionPalette b,
    double t,
  ) {
    return SportikaActionPalette(
      primary: SportikaActionColors.lerp(a.primary, b.primary, t),
      highlight: SportikaActionColors.lerp(a.highlight, b.highlight, t),
      danger: SportikaActionColors.lerp(a.danger, b.danger, t),
      subtle: SportikaActionColors.lerp(a.subtle, b.subtle, t),
      neutral: SportikaActionColors.lerp(a.neutral, b.neutral, t),
    );
  }
}

/// Sportika's context-aware visual design system.
///
/// Existing primitive tokens remain available for
/// backwards compatibility.
///
/// New widgets should prefer semantic accessors:
///
/// context.sportika.surfaceFor(...)
/// context.sportika.action(...)
/// context.sportika.gradientFor(...)
/// context.sportika.sport(...)
///
/// All brand colors originate from shared tokens.
@immutable
class SportikaTheme extends ThemeExtension<SportikaTheme> {
  const SportikaTheme({
    required this.brightness,
    required this.page,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceHigh,
    required this.surfaceSunken,
    required this.textPrimary,
    required this.textBody,
    required this.textMuted,
    required this.textDim,
    required this.border,
    required this.borderSubtle,
    required this.borderStrong,
    required this.brand,
    required this.brandBright,
    required this.brandDeep,
    required this.live,
    required this.achievement,
    required this.danger,
    required this.actions,
    required this.glass,
    required this.glassStrong,
    required this.glassBorder,
    required this.glassBlur,
    required this.actionGradient,
    required this.signatureGradient,
    required this.elevatedGradient,
    required this.atmosphereGradient,
    required this.photoScrim,
    required this.topFade,
    required this.bottomFade,
    required this.imageFade,
    required this.cardShadow,
    required this.liftedShadow,
    required this.elevatedShadow,
    required this.glowShadow,
    required this.ambientShadow,
    this.visualProfile = SportikaVisualProfile.standard,
    this.density = SportikaDensity.comfortable,
    this.motionIntensity = SportikaMotionIntensity.standard,
    this.reducedEffects = false,
  });

  // --------------------------------------------------
  // CONFIGURATION
  // --------------------------------------------------

  final Brightness brightness;
  final SportikaVisualProfile visualProfile;
  final SportikaDensity density;
  final SportikaMotionIntensity motionIntensity;
  final bool reducedEffects;

  bool get isDark => brightness == Brightness.dark;
  bool get isLight => brightness == Brightness.light;

  bool get isCinematic =>
      visualProfile == SportikaVisualProfile.cinematic && !reducedEffects;

  bool get isMinimal =>
      visualProfile == SportikaVisualProfile.minimal || reducedEffects;

  // --------------------------------------------------
  // CORE SURFACES
  // --------------------------------------------------

  final Color page;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceHigh;
  final Color surfaceSunken;

  /// The brightest interactive fill, used for selected / raised tiles.
  ///
  /// Exposed as a derived getter (not a constructor field) so every theme
  /// variant inherits it, it stays adaptive across light and dark, and
  /// `copyWith` remains unchanged.
  Color get surfaceElevated => surfaceAlt;

  // --------------------------------------------------
  // TYPOGRAPHY COLORS
  // --------------------------------------------------

  final Color textPrimary;
  final Color textBody;
  final Color textMuted;
  final Color textDim;

  // --------------------------------------------------
  // BORDERS
  // --------------------------------------------------

  final Color border;
  final Color borderSubtle;
  final Color borderStrong;

  // --------------------------------------------------
  // ACCENTS
  // --------------------------------------------------

  final Color brand;
  final Color brandBright;
  final Color brandDeep;
  final Color live;
  final Color achievement;
  final Color danger;

  final SportikaActionPalette actions;

  // --------------------------------------------------
  // GLASS
  // --------------------------------------------------

  final Color glass;
  final Color glassStrong;
  final Color glassBorder;
  final double glassBlur;

  // --------------------------------------------------
  // GRADIENTS
  // --------------------------------------------------

  final LinearGradient actionGradient;
  final LinearGradient signatureGradient;
  final LinearGradient elevatedGradient;
  final Gradient atmosphereGradient;
  final LinearGradient photoScrim;
  final LinearGradient topFade;
  final LinearGradient bottomFade;
  final LinearGradient imageFade;

  // --------------------------------------------------
  // SHADOWS
  // --------------------------------------------------

  final List<BoxShadow> cardShadow;
  final List<BoxShadow> liftedShadow;
  final List<BoxShadow> elevatedShadow;
  final List<BoxShadow> glowShadow;
  final List<BoxShadow> ambientShadow;

  // --------------------------------------------------
  // SEMANTIC SURFACES
  // --------------------------------------------------

  Color surfaceFor(SportikaSurfaceRole role, {SportikaVisualProfile? profile}) {
    final activeProfile = profile ?? visualProfile;

    return switch (role) {
      SportikaSurfaceRole.page => page,

      SportikaSurfaceRole.card => surface,

      SportikaSurfaceRole.hero =>
        activeProfile == SportikaVisualProfile.cinematic
            ? surfaceHigh
            : surfaceAlt,

      SportikaSurfaceRole.interactive => surfaceAlt,

      SportikaSurfaceRole.selected => Color.alphaBlend(
        brand.withValues(alpha: isDark ? 0.18 : 0.10),
        surfaceAlt,
      ),

      SportikaSurfaceRole.scoreboard => surfaceSunken,

      SportikaSurfaceRole.navigation => surface,

      SportikaSurfaceRole.overlay => surfaceHigh,

      SportikaSurfaceRole.sunken => surfaceSunken,
    };
  }

  Color borderFor(SportikaSurfaceRole role, {bool selected = false}) {
    if (selected) return brandBright;

    return switch (role) {
      SportikaSurfaceRole.hero => borderStrong,
      SportikaSurfaceRole.selected => brand,
      SportikaSurfaceRole.overlay => borderStrong,
      SportikaSurfaceRole.scoreboard => borderSubtle,
      _ => border,
    };
  }

  // --------------------------------------------------
  // SEMANTIC STATUS COLORS
  // --------------------------------------------------

  Color get success => live;

  Color get warning => achievement;

  Color get error => danger;

  Color get selectedSurface => surfaceFor(SportikaSurfaceRole.selected);

  Color get cardSurface => surfaceFor(SportikaSurfaceRole.card);

  Color get heroSurface => surfaceFor(SportikaSurfaceRole.hero);

  Color get scoreboardSurface => surfaceFor(SportikaSurfaceRole.scoreboard);

  Color get navigationSurface => surfaceFor(SportikaSurfaceRole.navigation);

  Color get overlaySurface => surfaceFor(SportikaSurfaceRole.overlay);

  // --------------------------------------------------
  // ACTION STATE RESOLUTION
  // --------------------------------------------------

  /// Resolves an action role and interaction state.
  ///
  /// All state colors are derived from the existing
  /// semantic palette rather than defined per widget.
  SportikaActionColors action(
    SportikaActionRole role, {
    SportikaActionState state = SportikaActionState.normal,
  }) {
    final base = actions.forRole(role);

    switch (state) {
      case SportikaActionState.normal:
        return base;

      case SportikaActionState.hovered:
        return base.copyWith(
          fill: Color.alphaBlend(base.fg.withValues(alpha: 0.06), base.fill),
        );

      case SportikaActionState.focused:
        return base.copyWith(border: brandBright);

      case SportikaActionState.pressed:
        return base.copyWith(
          fill: Color.alphaBlend(
            textPrimary.withValues(alpha: isDark ? 0.08 : 0.04),
            base.fill,
          ),
        );

      case SportikaActionState.disabled:
        return SportikaActionColors(
          fill: surfaceAlt,
          border: borderSubtle,
          fg: textDim,
        );

      case SportikaActionState.loading:
        return base;

      case SportikaActionState.selected:
        return base.copyWith(border: base.fg);
    }
  }

  // --------------------------------------------------
  // VISUAL PROFILE EFFECTS
  // --------------------------------------------------

  /// Select the appropriate surface gradient.
  ///
  /// Minimal uses a flat gradient.
  /// Standard uses a restrained surface.
  /// Cinematic uses the richer signature treatment.
  Gradient gradientFor(
    SportikaSurfaceRole role, {
    SportikaVisualProfile? profile,
  }) {
    final activeProfile = profile ?? visualProfile;

    if (reducedEffects || activeProfile == SportikaVisualProfile.minimal) {
      final color = surfaceFor(role, profile: activeProfile);

      return LinearGradient(colors: [color, color]);
    }

    return switch (role) {
      SportikaSurfaceRole.hero =>
        activeProfile == SportikaVisualProfile.cinematic
            ? atmosphereGradient
            : signatureGradient,

      SportikaSurfaceRole.card => elevatedGradient,

      SportikaSurfaceRole.interactive => actionGradient,

      SportikaSurfaceRole.selected => signatureGradient,

      SportikaSurfaceRole.scoreboard => elevatedGradient,

      SportikaSurfaceRole.navigation => elevatedGradient,

      SportikaSurfaceRole.overlay => elevatedGradient,

      SportikaSurfaceRole.page => atmosphereGradient,

      SportikaSurfaceRole.sunken => LinearGradient(
        colors: [surfaceSunken, surfaceSunken],
      ),
    };
  }

  /// Semantic shadow selection.
  List<BoxShadow> shadowsFor(
    SportikaSurfaceRole role, {
    SportikaVisualProfile? profile,
  }) {
    final activeProfile = profile ?? visualProfile;

    if (reducedEffects || activeProfile == SportikaVisualProfile.minimal) {
      return const [];
    }

    return switch (role) {
      SportikaSurfaceRole.hero =>
        activeProfile == SportikaVisualProfile.cinematic
            ? ambientShadow
            : elevatedShadow,

      SportikaSurfaceRole.card => cardShadow,

      SportikaSurfaceRole.interactive => cardShadow,

      SportikaSurfaceRole.selected => glowShadow,

      SportikaSurfaceRole.overlay => elevatedShadow,

      SportikaSurfaceRole.navigation => liftedShadow,

      _ => const [],
    };
  }

  // --------------------------------------------------
  // GLASS EFFECTS
  // --------------------------------------------------

  Color glassFor({bool strong = false}) {
    if (reducedEffects || isMinimal) {
      return surfaceHigh;
    }

    return strong ? glassStrong : glass;
  }

  double get effectiveGlassBlur => reducedEffects || isMinimal ? 0 : glassBlur;

  // --------------------------------------------------
  // COMPONENT DENSITY
  // --------------------------------------------------

  /// Density multiplier for shared component spacing.
  ///
  /// Apply this to existing spacing tokens rather than
  /// introducing new hardcoded spacing throughout screens.
  double get densityFactor => switch (density) {
    SportikaDensity.compact => 0.85,
    SportikaDensity.comfortable => 1.0,
    SportikaDensity.spacious => 1.15,
  };

  double scaledSpacing(double spacing) => spacing * densityFactor;

  // --------------------------------------------------
  // TYPOGRAPHY ACCESS
  // --------------------------------------------------

  /// Use the app's ThemeData.textTheme as the typography
  /// source of truth. Font families and type roles should
  /// continue to be configured in typography.dart.
  TextTheme typography(BuildContext context) => Theme.of(context).textTheme;

  TextStyle? scoreTextStyle(BuildContext context) => typography(context)
      .displayLarge
      ?.copyWith(
        color: textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  // --------------------------------------------------
  // MOTION INTEGRATION
  // --------------------------------------------------

  SportikaMotionSpec motion(
    BuildContext context,
    SportikaMotionRecipe recipe, {
    SportikaMotionSport? sport,
    SportikaMotionIntensity? intensity,
  }) {
    final effectiveIntensity = reducedEffects
        ? SportikaMotionIntensity.minimal
        : intensity ?? motionIntensity;

    return SportikaMotion.recipe(
      context,
      recipe: recipe,
      sport: sport,
      intensity: effectiveIntensity,
    );
  }

  // --------------------------------------------------
  // IMAGERY INTEGRATION
  // --------------------------------------------------

  SportikaImageSpec imageSpec(
    SportikaImageRole role, {
    SportikaPhotographyStyle? style,
    SportikaImageGrade? grade,
    SportikaImageTextZone? textZone,
    SportikaImageFocalPoint? focalPoint,
  }) {
    final effectiveGrade = reducedEffects ? SportikaImageGrade.natural : grade;

    return SportikaImagery.specFor(
      role: role,
      style: style,
      grade: effectiveGrade,
      textZone: textZone,
      focalPoint: focalPoint,
    );
  }

  // --------------------------------------------------
  // SPORT IDENTITY INTEGRATION
  // --------------------------------------------------

  SportIdentity sport(Sport sport) => SportIdentities.of(sport);

  // --------------------------------------------------
  // DARK THEME
  // --------------------------------------------------

  static const SportikaTheme dark = SportikaTheme(
    brightness: Brightness.dark,

    page: SportikaColors.page,
    surface: SportikaColors.surface,
    surfaceAlt: SportikaColors.surfaceAlt,
    surfaceHigh: SportikaColors.surfaceHigh,
    surfaceSunken: SportikaColors.surfaceSunken,

    textPrimary: SportikaColors.text,
    textBody: SportikaColors.textBody,
    textMuted: SportikaColors.textMuted,
    textDim: SportikaColors.textDim,

    border: SportikaColors.border,
    borderSubtle: SportikaColors.borderSubtle,
    borderStrong: SportikaColors.borderStrong,

    brand: SportikaColors.blue,
    brandBright: SportikaColors.blueBright,
    brandDeep: SportikaColors.blueDeep,

    live: SportikaColors.mint,
    achievement: SportikaColors.gold,
    danger: SportikaColors.danger,

    actions: SportikaActionPalette(
      primary: SportikaActionColors(
        fill: SportikaColors.blue,
        border: SportikaColors.blueBright,
        fg: SportikaColors.onAccent,
      ),
      highlight: SportikaActionColors(
        fill: SportikaColors.mint,
        border: SportikaColors.mint,
        fg: SportikaColors.onMint,
      ),
      danger: SportikaActionColors(
        fill: SportikaColors.danger,
        border: SportikaColors.dangerBright,
        fg: SportikaColors.onAccent,
      ),
      subtle: SportikaActionColors(
        fill: SportikaColors.surfaceAlt,
        border: SportikaColors.borderStrong,
        fg: SportikaColors.textBody,
      ),
      neutral: SportikaActionColors(
        fill: SportikaColors.surface,
        border: SportikaColors.border,
        fg: SportikaColors.text,
      ),
    ),

    glass: SportikaColors.glass,
    glassStrong: SportikaColors.glassStrong,
    glassBorder: SportikaGlass.border,
    glassBlur: SportikaGlass.blurSigma,

    actionGradient: SportikaGradients.primaryAction,
    signatureGradient: SportikaGradients.signatureSurface,
    elevatedGradient: SportikaGradients.elevatedSurface,
    atmosphereGradient: SportikaGradients.atmosphere,
    photoScrim: SportikaGradients.authPhotoScrim,
    topFade: SportikaGradients.onboardingTopFade,
    bottomFade: SportikaGradients.onboardingBottomFade,
    imageFade: SportikaGradients.imageFade,

    cardShadow: SportikaShadows.card,
    liftedShadow: SportikaShadows.lifted,
    elevatedShadow: SportikaShadows.elevated,
    glowShadow: SportikaShadows.brandGlow,
    ambientShadow: SportikaShadows.brandAmbient,
  );

  // --------------------------------------------------
  // LIGHT THEME
  // --------------------------------------------------

  static const SportikaTheme light = SportikaTheme(
    brightness: Brightness.light,

    page: SportikaColors.lightSurface,
    surface: SportikaColors.lightSurface,
    surfaceAlt: SportikaColors.lightSurfaceAlt,
    surfaceHigh: SportikaColors.lightBorder,
    surfaceSunken: SportikaColors.lightSurfaceAlt,

    textPrimary: SportikaColors.lightText,
    textBody: SportikaColors.lightTextMuted,
    textMuted: SportikaColors.lightTextMuted,
    textDim: SportikaPalette.slate500,

    border: SportikaColors.lightBorder,
    borderSubtle: SportikaColors.lightBorder,
    borderStrong: SportikaPalette.slate400,

    brand: SportikaColors.blue,
    brandBright: SportikaColors.blueBright,
    brandDeep: SportikaColors.blueDeep,

    live: SportikaColors.mintDeep,
    achievement: SportikaColors.goldDeep,
    danger: SportikaColors.danger,

    actions: SportikaActionPalette(
      primary: SportikaActionColors(
        fill: SportikaColors.blue,
        border: SportikaColors.blueDeep,
        fg: SportikaColors.onAccent,
      ),
      highlight: SportikaActionColors(
        fill: SportikaColors.lightMint,
        border: SportikaColors.mint,
        fg: SportikaColors.lightMintText,
      ),
      danger: SportikaActionColors(
        fill: SportikaColors.dangerSubtle,
        border: SportikaColors.danger,
        fg: SportikaColors.danger,
      ),
      subtle: SportikaActionColors(
        fill: SportikaColors.lightSurfaceAlt,
        border: SportikaColors.lightBorder,
        fg: SportikaColors.lightText,
      ),
      neutral: SportikaActionColors(
        fill: SportikaColors.lightSurface,
        border: SportikaColors.lightBorder,
        fg: SportikaColors.lightText,
      ),
    ),

    glass: SportikaColors.lightGlass,
    glassStrong: SportikaColors.lightGlassStrong,
    glassBorder: SportikaColors.lightGlassBorder,
    glassBlur: SportikaGlass.blurSigma,

    actionGradient: SportikaGradients.primaryAction,
    signatureGradient: SportikaGradients.signatureSurface,
    elevatedGradient: SportikaGradients.lightElevatedSurface,
    atmosphereGradient: SportikaGradients.lightAtmosphere,
    photoScrim: SportikaGradients.authPhotoScrim,
    topFade: SportikaGradients.onboardingTopFade,
    bottomFade: SportikaGradients.onboardingBottomFade,
    imageFade: SportikaGradients.imageFade,

    cardShadow: SportikaShadows.card,
    liftedShadow: SportikaShadows.lifted,
    elevatedShadow: SportikaShadows.elevated,
    glowShadow: SportikaShadows.brandGlow,
    ambientShadow: SportikaShadows.brandAmbient,
  );

  // --------------------------------------------------
  // THEME FACTORY
  // --------------------------------------------------

  static SportikaTheme forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Construct a resolved theme from a Material ColorScheme.
  ///
  /// Existing brand tokens remain the baseline, while
  /// scheme-dependent surfaces and effects are regenerated.
  static SportikaTheme fromScheme(
    ColorScheme scheme, {
    SportikaVisualProfile profile = SportikaVisualProfile.standard,
    SportikaDensity density = SportikaDensity.comfortable,
    SportikaMotionIntensity motionIntensity = SportikaMotionIntensity.standard,
    bool reducedEffects = false,
  }) {
    final base = forBrightness(scheme.brightness);

    final minimal = profile == SportikaVisualProfile.minimal || reducedEffects;

    final resolvedSurface = scheme.surface;

    final resolvedAlt = scheme.surfaceContainer;

    final resolvedHigh = scheme.surfaceContainerHigh;

    final resolvedSunken = scheme.surfaceContainerLowest;

    final foreground = scheme.onSurface;

    final muted = scheme.onSurfaceVariant;

    final primary = scheme.primary;

    final primaryFg = scheme.onPrimary;

    final secondary = scheme.secondary;

    final secondaryFg = scheme.onSecondary;

    final error = scheme.error;

    final errorFg = scheme.onError;

    final outline = scheme.outline;

    final subtleOutline = scheme.outlineVariant;

    final resolvedActions = SportikaActionPalette(
      primary: SportikaActionColors(
        fill: primary,
        border: primary,
        fg: primaryFg,
      ),
      highlight: SportikaActionColors(
        fill: secondary,
        border: secondary,
        fg: secondaryFg,
      ),
      danger: SportikaActionColors(fill: error, border: error, fg: errorFg),
      subtle: SportikaActionColors(
        fill: resolvedAlt,
        border: outline,
        fg: foreground,
      ),
      neutral: SportikaActionColors(
        fill: resolvedSurface,
        border: subtleOutline,
        fg: foreground,
      ),
    );

    return base.copyWith(
      visualProfile: profile,
      density: density,
      motionIntensity: motionIntensity,
      reducedEffects: reducedEffects,

      page: scheme.surface,
      surface: resolvedSurface,
      surfaceAlt: resolvedAlt,
      surfaceHigh: resolvedHigh,
      surfaceSunken: resolvedSunken,

      textPrimary: foreground,
      textBody: foreground,
      textMuted: muted,
      textDim: muted.withValues(alpha: 0.70),

      border: outline,
      borderSubtle: subtleOutline,
      borderStrong: outline,

      brand: primary,
      brandBright: base.brandBright,
      brandDeep: base.brandDeep,
      live: secondary,
      achievement: base.achievement,
      danger: error,

      actions: resolvedActions,

      glass: minimal ? resolvedHigh : SportikaGlass.tintFor(scheme),

      glassStrong: minimal
          ? resolvedHigh
          : SportikaGlass.tintFor(
              scheme,
              variant: SportikaGlassVariant.immersive,
            ),

      glassBorder: SportikaGlass.borderFor(scheme),

      glassBlur: minimal
          ? 0
          : SportikaGlass.blurFor(SportikaGlassVariant.standard),

      actionGradient: SportikaGradients.themedAction(
        scheme: scheme,
        reducedEffects: minimal,
      ),

      signatureGradient: SportikaGradients.themedSignatureSurface(
        scheme: scheme,
        intensity: profile == SportikaVisualProfile.cinematic
            ? SportikaGradientIntensity.cinematic
            : SportikaGradientIntensity.standard,
        reducedEffects: minimal,
      ),

      atmosphereGradient: SportikaGradients.stadiumAtmosphere(
        scheme: scheme,
        intensity: profile == SportikaVisualProfile.cinematic
            ? SportikaGradientIntensity.cinematic
            : SportikaGradientIntensity.standard,
        reducedEffects: minimal,
      ),

      elevatedGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [resolvedHigh, resolvedSurface],
      ),

      photoScrim: SportikaGradients.mediaScrim(
        scheme: scheme,
        variant: SportikaMediaScrim.hero,
      ),

      cardShadow: SportikaShadows.resolve(
        scheme: scheme,
        level: SportikaElevation.card,
        reducedEffects: minimal,
      ),

      liftedShadow: SportikaShadows.resolve(
        scheme: scheme,
        level: SportikaElevation.elevated,
        reducedEffects: minimal,
      ),

      elevatedShadow: SportikaShadows.resolve(
        scheme: scheme,
        level: SportikaElevation.hero,
        reducedEffects: minimal,
      ),

      glowShadow: SportikaShadows.brandedGlow(
        color: primary,
        reducedEffects: minimal,
      ),

      ambientShadow: SportikaShadows.directionalAmbient(
        color: primary,
        reducedEffects: minimal,
      ),
    );
  }

  // --------------------------------------------------
  // CONTEXT RESOLUTION
  // --------------------------------------------------

  static SportikaTheme of(BuildContext context) {
    final theme = Theme.of(context);

    return theme.extension<SportikaTheme>() ?? forBrightness(theme.brightness);
  }

  // --------------------------------------------------
  // COPY WITH
  // --------------------------------------------------

  @override
  SportikaTheme copyWith({
    Brightness? brightness,
    Color? page,
    Color? surface,
    Color? surfaceAlt,
    Color? surfaceHigh,
    Color? surfaceSunken,
    Color? textPrimary,
    Color? textBody,
    Color? textMuted,
    Color? textDim,
    Color? border,
    Color? borderSubtle,
    Color? borderStrong,
    Color? brand,
    Color? brandBright,
    Color? brandDeep,
    Color? live,
    Color? achievement,
    Color? danger,
    SportikaActionPalette? actions,
    Color? glass,
    Color? glassStrong,
    Color? glassBorder,
    double? glassBlur,
    LinearGradient? actionGradient,
    LinearGradient? signatureGradient,
    LinearGradient? elevatedGradient,
    Gradient? atmosphereGradient,
    LinearGradient? photoScrim,
    LinearGradient? topFade,
    LinearGradient? bottomFade,
    LinearGradient? imageFade,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? liftedShadow,
    List<BoxShadow>? elevatedShadow,
    List<BoxShadow>? glowShadow,
    List<BoxShadow>? ambientShadow,
    SportikaVisualProfile? visualProfile,
    SportikaDensity? density,
    SportikaMotionIntensity? motionIntensity,
    bool? reducedEffects,
  }) {
    return SportikaTheme(
      brightness: brightness ?? this.brightness,
      page: page ?? this.page,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      textPrimary: textPrimary ?? this.textPrimary,
      textBody: textBody ?? this.textBody,
      textMuted: textMuted ?? this.textMuted,
      textDim: textDim ?? this.textDim,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderStrong: borderStrong ?? this.borderStrong,
      brand: brand ?? this.brand,
      brandBright: brandBright ?? this.brandBright,
      brandDeep: brandDeep ?? this.brandDeep,
      live: live ?? this.live,
      achievement: achievement ?? this.achievement,
      danger: danger ?? this.danger,
      actions: actions ?? this.actions,
      glass: glass ?? this.glass,
      glassStrong: glassStrong ?? this.glassStrong,
      glassBorder: glassBorder ?? this.glassBorder,
      glassBlur: glassBlur ?? this.glassBlur,
      actionGradient: actionGradient ?? this.actionGradient,
      signatureGradient: signatureGradient ?? this.signatureGradient,
      elevatedGradient: elevatedGradient ?? this.elevatedGradient,
      atmosphereGradient: atmosphereGradient ?? this.atmosphereGradient,
      photoScrim: photoScrim ?? this.photoScrim,
      topFade: topFade ?? this.topFade,
      bottomFade: bottomFade ?? this.bottomFade,
      imageFade: imageFade ?? this.imageFade,
      cardShadow: cardShadow ?? this.cardShadow,
      liftedShadow: liftedShadow ?? this.liftedShadow,
      elevatedShadow: elevatedShadow ?? this.elevatedShadow,
      glowShadow: glowShadow ?? this.glowShadow,
      ambientShadow: ambientShadow ?? this.ambientShadow,
      visualProfile: visualProfile ?? this.visualProfile,
      density: density ?? this.density,
      motionIntensity: motionIntensity ?? this.motionIntensity,
      reducedEffects: reducedEffects ?? this.reducedEffects,
    );
  }

  // --------------------------------------------------
  // INTERPOLATION
  // --------------------------------------------------

  static LinearGradient _lerpLinear(
    LinearGradient a,
    LinearGradient b,
    double t,
  ) {
    return LinearGradient.lerp(a, b, t) ?? (t < 0.5 ? a : b);
  }

  static Gradient _lerpGradient(Gradient a, Gradient b, double t) {
    // Avoid attempting to morph incompatible
    // gradient geometries.
    if (a.runtimeType != b.runtimeType) {
      return t < 0.5 ? a : b;
    }

    return Gradient.lerp(a, b, t) ?? (t < 0.5 ? a : b);
  }

  @override
  SportikaTheme lerp(covariant SportikaTheme? other, double t) {
    if (other == null) return this;

    if (t <= 0) return this;
    if (t >= 1) return other;

    return SportikaTheme(
      brightness: t < 0.5 ? brightness : other.brightness,

      page: Color.lerp(page, other.page, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,

      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textBody: Color.lerp(textBody, other.textBody, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,

      border: Color.lerp(border, other.border, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,

      brand: Color.lerp(brand, other.brand, t)!,
      brandBright: Color.lerp(brandBright, other.brandBright, t)!,
      brandDeep: Color.lerp(brandDeep, other.brandDeep, t)!,
      live: Color.lerp(live, other.live, t)!,
      achievement: Color.lerp(achievement, other.achievement, t)!,
      danger: Color.lerp(danger, other.danger, t)!,

      actions: SportikaActionPalette.lerp(actions, other.actions, t),

      glass: Color.lerp(glass, other.glass, t)!,
      glassStrong: Color.lerp(glassStrong, other.glassStrong, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      glassBlur: glassBlur + (other.glassBlur - glassBlur) * t,

      actionGradient: _lerpLinear(actionGradient, other.actionGradient, t),
      signatureGradient: _lerpLinear(
        signatureGradient,
        other.signatureGradient,
        t,
      ),
      elevatedGradient: _lerpLinear(
        elevatedGradient,
        other.elevatedGradient,
        t,
      ),
      atmosphereGradient: _lerpGradient(
        atmosphereGradient,
        other.atmosphereGradient,
        t,
      ),
      photoScrim: _lerpLinear(photoScrim, other.photoScrim, t),
      topFade: _lerpLinear(topFade, other.topFade, t),
      bottomFade: _lerpLinear(bottomFade, other.bottomFade, t),
      imageFade: _lerpLinear(imageFade, other.imageFade, t),

      cardShadow:
          BoxShadow.lerpList(cardShadow, other.cardShadow, t) ?? cardShadow,

      liftedShadow:
          BoxShadow.lerpList(liftedShadow, other.liftedShadow, t) ??
          liftedShadow,

      elevatedShadow:
          BoxShadow.lerpList(elevatedShadow, other.elevatedShadow, t) ??
          elevatedShadow,

      glowShadow:
          BoxShadow.lerpList(glowShadow, other.glowShadow, t) ?? glowShadow,

      ambientShadow:
          BoxShadow.lerpList(ambientShadow, other.ambientShadow, t) ??
          ambientShadow,

      visualProfile: t < 0.5 ? visualProfile : other.visualProfile,

      density: t < 0.5 ? density : other.density,

      motionIntensity: t < 0.5 ? motionIntensity : other.motionIntensity,

      reducedEffects: t < 0.5 ? reducedEffects : other.reducedEffects,
    );
  }
}

/// Convenient access to Sportika's design system.
extension SportikaThemeContext on BuildContext {
  SportikaTheme get sportika => SportikaTheme.of(this);
}
