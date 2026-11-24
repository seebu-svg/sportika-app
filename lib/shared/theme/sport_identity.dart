import 'package:flutter/material.dart';

import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/theme/effects.dart';
import 'package:sportika/shared/theme/gradients.dart';
import 'package:sportika/shared/theme/imagery.dart';
import 'package:sportika/shared/theme/motion.dart';
import 'package:sportika/shared/theme/tokens.dart';

/// Centralized artwork assets for one sport.
///
/// Explicit paths allow each sport to use different image
/// formats without changing consuming widgets.
@immutable
class SportArtwork {
  const SportArtwork({
    required this.hero,
    required this.banner,
    required this.fallback,
    this.portrait,
    this.scoreboard,
  });

  final String hero;
  final String banner;
  final String fallback;
  final String? portrait;
  final String? scoreboard;

  String forRole(SportikaImageRole role) {
    return switch (role) {
      SportikaImageRole.hero => hero,
      SportikaImageRole.banner => banner,
      SportikaImageRole.card => banner,
      SportikaImageRole.tile => fallback,
      SportikaImageRole.portrait => portrait ?? hero,
      SportikaImageRole.avatar => portrait ?? fallback,
      SportikaImageRole.teamCover => banner,
      SportikaImageRole.scoreboard => scoreboard ?? banner,
    };
  }
}

/// Complete visual identity for one Sportika sport.
///
/// Every sport shares the same design language while
/// maintaining a recognizable color, image and motion
/// personality.
///
/// Screen widgets should consume this configuration
/// instead of defining sport-specific styles locally.
@immutable
class SportIdentity {
  const SportIdentity({
    required this.sport,
    required this.tone,
    required this.toneBright,
    required this.toneDeep,
    required this.onTone,
    required this.gradient,
    required this.glyph,
    required this.solidGlyph,
    this.customGlyph = false,
    this.artwork,
    this.photographyStyle = SportikaPhotographyStyle.matchDocumentary,
    this.motionSport,
    this.defaultFocalPoint = SportikaImageFocalPoint.center,
  });

  // --------------------------------------------------
  // CORE IDENTITY
  // --------------------------------------------------

  final Sport sport;

  /// Primary sport identity color.
  final Color tone;

  /// Highlight and illuminated accent.
  final Color toneBright;

  /// Darker identity accent.
  final Color toneDeep;

  /// Preferred foreground over the primary tone.
  final Color onTone;

  /// Signature color sequence.
  final List<Color> gradient;

  /// Outline sport glyph.
  final IconData glyph;

  /// Filled sport glyph.
  final IconData solidGlyph;

  /// True when a custom glyph renderer is required.
  ///
  /// Badminton uses a shuttlecock instead of a
  /// generic tennis racket.
  final bool customGlyph;

  // --------------------------------------------------
  // PHOTOGRAPHY AND MOTION
  // --------------------------------------------------

  /// Optional explicit sport artwork assets.
  final SportArtwork? artwork;

  /// Default photographic treatment.
  final SportikaPhotographyStyle photographyStyle;

  /// Motion profile for the sport.
  final SportikaMotionSport? motionSport;

  /// Default normalized image focal point.
  final SportikaImageFocalPoint defaultFocalPoint;

  // --------------------------------------------------
  // LEGACY COLOR GETTERS
  // --------------------------------------------------

  Color get softSurface => tone.withValues(alpha: SportikaOpacity.tint);

  Color get softBorder => tone.withValues(alpha: 0.38);

  Color get mutedTone => tone.withValues(alpha: SportikaOpacity.medium);

  Color get selectedBorder => tone.withValues(alpha: SportikaOpacity.strong);

  // --------------------------------------------------
  // SEMANTIC SPORT COLORS
  // --------------------------------------------------

  /// Restrained tint for identity backgrounds.
  Color get surfaceTint => softSurface;

  /// Stronger selected background.
  Color get selectedSurface => tone.withValues(alpha: SportikaOpacity.medium);

  /// Default accent border.
  Color get borderColor => softBorder;

  /// Bright accent for icons over dark artwork.
  Color get highlightColor => toneBright;

  /// Resolve a legible foreground for an opaque
  /// sport-colored surface.
  ///
  /// The stored onTone remains the preferred color.
  /// If it does not meet the requested contrast ratio,
  /// a light or dark fallback is selected.
  Color foregroundFor(Color background, {double minimumContrast = 4.5}) {
    final preferredRatio = _contrastRatio(onTone, background);

    if (preferredRatio >= minimumContrast) {
      return onTone;
    }

    final lightRatio = _contrastRatio(SportikaColors.onAccent, background);

    final darkRatio = _contrastRatio(SportikaColors.deepest, background);

    return lightRatio >= darkRatio
        ? SportikaColors.onAccent
        : SportikaColors.deepest;
  }

  /// Foreground over the primary sport tone.
  Color get accessibleOnTone => foregroundFor(tone);

  static double _contrastRatio(Color foreground, Color background) {
    final foregroundLuminance = foreground.computeLuminance();

    final backgroundLuminance = background.computeLuminance();

    final lighter = foregroundLuminance > backgroundLuminance
        ? foregroundLuminance
        : backgroundLuminance;

    final darker = foregroundLuminance < backgroundLuminance
        ? foregroundLuminance
        : backgroundLuminance;

    return (lighter + 0.05) / (darker + 0.05);
  }

  // --------------------------------------------------
  // LEGACY GRADIENTS
  // --------------------------------------------------

  /// Existing identity gradient.
  LinearGradient get fill => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: gradient,
  );

  /// Existing signature surface.
  LinearGradient get signatureSurface =>
      SportikaGradients.signatureSurfaceFor(tone);

  /// Existing image grade.
  LinearGradient get artworkTreatment => SportikaImagery.artworkTreatment(tone);

  // --------------------------------------------------
  // THEMED GRADIENTS
  // --------------------------------------------------

  /// Brightness-aware signature surface.
  LinearGradient themedSignatureSurface(
    ColorScheme scheme, {
    SportikaGradientIntensity intensity = SportikaGradientIntensity.standard,
    bool reducedEffects = false,
  }) {
    return SportikaGradients.themedSignatureSurface(
      scheme: scheme,
      sportColor: tone,
      intensity: intensity,
      reducedEffects: reducedEffects,
    );
  }

  /// Theme-aware identity action.
  LinearGradient themedAction(
    ColorScheme scheme, {
    SportikaGradientIntensity intensity = SportikaGradientIntensity.standard,
    bool reducedEffects = false,
  }) {
    return SportikaGradients.themedAction(
      scheme: scheme,
      tone: tone,
      intensity: intensity,
      reducedEffects: reducedEffects,
    );
  }

  /// Theme-aware sport photography grade.
  LinearGradient themedArtworkTreatment(
    ColorScheme scheme, {
    SportikaImageGrade grade = SportikaImageGrade.subtle,
    bool reducedEffects = false,
  }) {
    return SportikaImagery.themedArtworkTreatment(
      scheme: scheme,
      tone: tone,
      grade: grade,
      reducedEffects: reducedEffects,
    );
  }

  /// Sport-specific atmospheric spotlight.
  RadialGradient spotlight(
    ColorScheme scheme, {
    SportikaGradientIntensity intensity = SportikaGradientIntensity.standard,
    bool reducedEffects = false,
  }) {
    return SportikaGradients.sportSpotlight(
      scheme: scheme,
      sportColor: toneBright,
      intensity: intensity,
      reducedEffects: reducedEffects,
    );
  }

  // --------------------------------------------------
  // LEGACY EFFECTS
  // --------------------------------------------------

  /// Selected control or live badge glow.
  List<BoxShadow> get glow => SportikaShadows.glow(tone, strength: 0.9);

  /// Hero ambient lighting.
  List<BoxShadow> get ambientGlow => SportikaShadows.ambient(tone);

  // --------------------------------------------------
  // THEMED EFFECTS
  // --------------------------------------------------

  /// Configurable identity glow.
  List<BoxShadow> themedGlow({
    SportikaGlowIntensity intensity = SportikaGlowIntensity.standard,
    bool reducedEffects = false,
  }) {
    return SportikaShadows.brandedGlow(
      color: tone,
      intensity: intensity,
      reducedEffects: reducedEffects,
    );
  }

  /// Wide directional hero illumination.
  List<BoxShadow> themedAmbientGlow({
    Alignment direction = Alignment.topLeft,
    bool reducedEffects = false,
  }) {
    return SportikaShadows.directionalAmbient(
      color: toneBright,
      direction: direction,
      reducedEffects: reducedEffects,
    );
  }

  // --------------------------------------------------
  // IMAGE ART DIRECTION
  // --------------------------------------------------

  /// Resolve image configuration for this sport.
  ///
  /// Content-specific focal points override the
  /// sport's default crop preference.
  SportikaImageSpec imageSpec({
    required SportikaImageRole role,
    SportikaImageFocalPoint? subject,
    SportikaImageGrade? grade,
    SportikaImageTextZone? textZone,
  }) {
    return SportikaImagery.specFor(
      role: role,
      style: photographyStyle,
      grade: grade,
      textZone: textZone,
      focalPoint: subject ?? defaultFocalPoint,
    );
  }

  /// Sport-specific fallback surface.
  RadialGradient fallbackGradient(
    ColorScheme scheme, {
    bool reducedEffects = false,
  }) {
    return SportikaImagery.fallbackFor(
      scheme: scheme,
      sportColor: tone,
      reducedEffects: reducedEffects,
    );
  }

  // --------------------------------------------------
  // MOTION
  // --------------------------------------------------

  /// Resolve a motion recipe using this sport's
  /// preferred timing profile.
  SportikaMotionSpec motion(
    BuildContext context, {
    required SportikaMotionRecipe recipe,
    SportikaMotionIntensity intensity = SportikaMotionIntensity.standard,
  }) {
    return SportikaMotion.recipe(
      context,
      recipe: recipe,
      intensity: intensity,
      sport: motionSport,
    );
  }

  // --------------------------------------------------
  // LABELS AND ASSETS
  // --------------------------------------------------

  String get label => sport.label.toUpperCase();

  /// Existing action banner path.
  String get actionPhoto =>
      artwork?.banner ??
      'assets/images/sports/${sport.name}_detail_banner.webp';

  /// Existing fallback image path.
  String get fallbackPhoto =>
      artwork?.fallback ?? 'assets/images/sports/${sport.name}.jpg';

  /// Preferred artwork for a particular image role.
  String imageFor(SportikaImageRole role) {
    final assets = artwork;

    if (assets != null) {
      return assets.forRole(role);
    }

    return switch (role) {
      SportikaImageRole.tile || SportikaImageRole.avatar => fallbackPhoto,

      _ => actionPhoto,
    };
  }
}

/// Canonical Sportika sport identities.
///
/// All four sports share the same design system.
/// Only their semantic colors, photography and motion
/// personalities differ.
abstract final class SportIdentities {
  SportIdentities._();

  // --------------------------------------------------
  // CRICKET
  // --------------------------------------------------

  static const SportIdentity cricket = SportIdentity(
    sport: Sport.cricket,
    tone: SportikaColors.cricket,
    toneBright: SportikaColors.blueBright,
    toneDeep: SportikaColors.blueDeep,
    onTone: SportikaColors.onAccent,
    gradient: [
      SportikaColors.blueBright,
      SportikaColors.blue,
      SportikaColors.blueDeep,
    ],
    glyph: Icons.sports_cricket_outlined,
    solidGlyph: Icons.sports_cricket_rounded,
    photographyStyle: SportikaPhotographyStyle.cinematicAction,
    motionSport: SportikaMotionSport.cricket,
    defaultFocalPoint: SportikaImageFocalPoint.upperCenter,
    artwork: SportArtwork(
      hero: 'assets/images/sports/cricket_detail_banner.webp',
      banner: 'assets/images/sports/cricket_detail_banner.webp',
      fallback: 'assets/images/sports/cricket.jpg',
    ),
  );

  // --------------------------------------------------
  // PADEL
  // --------------------------------------------------

  static const SportIdentity padel = SportIdentity(
    sport: Sport.padel,
    tone: SportikaColors.padel,
    toneBright: SportikaPalette.mintSpecular,
    toneDeep: SportikaColors.mintDeep,
    onTone: SportikaColors.onMint,
    gradient: [
      SportikaColors.mintSoft,
      SportikaColors.mint,
      SportikaColors.mintDeep,
    ],
    glyph: Icons.sports_tennis_outlined,
    solidGlyph: Icons.sports_tennis_rounded,
    photographyStyle: SportikaPhotographyStyle.cinematicAction,
    motionSport: SportikaMotionSport.padel,
    defaultFocalPoint: SportikaImageFocalPoint.center,
    artwork: SportArtwork(
      hero: 'assets/images/sports/padel_detail_banner.webp',
      banner: 'assets/images/sports/padel_detail_banner.webp',
      fallback: 'assets/images/sports/padel.jpg',
    ),
  );

  // --------------------------------------------------
  // FUTSAL
  // --------------------------------------------------

  static const SportIdentity futsal = SportIdentity(
    sport: Sport.futsal,
    tone: SportikaColors.futsal,
    toneBright: SportikaPalette.gold300,
    toneDeep: SportikaColors.goldDeep,
    onTone: SportikaColors.onMint,
    gradient: [
      SportikaPalette.gold300,
      SportikaColors.gold,
      SportikaColors.goldDeep,
    ],
    glyph: Icons.sports_soccer_outlined,
    solidGlyph: Icons.sports_soccer_rounded,
    photographyStyle: SportikaPhotographyStyle.matchDocumentary,
    motionSport: SportikaMotionSport.futsal,
    defaultFocalPoint: SportikaImageFocalPoint.center,
    artwork: SportArtwork(
      hero: 'assets/images/sports/futsal_detail_banner.webp',
      banner: 'assets/images/sports/futsal_detail_banner.webp',
      fallback: 'assets/images/sports/futsal.jpg',
    ),
  );

  // --------------------------------------------------
  // BADMINTON
  // --------------------------------------------------

  static const SportIdentity badminton = SportIdentity(
    sport: Sport.badminton,
    tone: SportikaColors.badminton,
    toneBright: SportikaColors.blueSoft,
    toneDeep: SportikaColors.blueDeep,
    onTone: SportikaColors.onAccent,
    gradient: [
      SportikaColors.blueBright,
      SportikaColors.blueSoft,
      SportikaColors.mint,
    ],
    glyph: Icons.sports_tennis_outlined,
    solidGlyph: Icons.sports_tennis_rounded,
    customGlyph: true,
    photographyStyle: SportikaPhotographyStyle.cinematicAction,
    motionSport: SportikaMotionSport.badminton,
    defaultFocalPoint: SportikaImageFocalPoint.center,
    artwork: SportArtwork(
      hero: 'assets/images/sports/badminton_detail_banner.webp',
      banner: 'assets/images/sports/badminton_detail_banner.webp',
      fallback: 'assets/images/sports/badminton.jpg',
    ),
  );

  // --------------------------------------------------
  // REGISTRY
  // --------------------------------------------------

  static const List<SportIdentity> all = [cricket, padel, futsal, badminton];

  static SportIdentity of(Sport sport) {
    return switch (sport) {
      Sport.cricket => cricket,
      Sport.padel => padel,
      Sport.futsal => futsal,
      Sport.badminton => badminton,
    };
  }
}
