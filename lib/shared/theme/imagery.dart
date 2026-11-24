import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:sportika/shared/theme/gradients.dart';
import 'package:sportika/shared/theme/tokens.dart';

/// The layout purpose of an image.
///
/// Roles control framing, cropping and decode budgets.
/// They do not determine the photograph's visual style.
enum SportikaImageRole {
  hero,
  banner,
  card,
  tile,
  portrait,
  avatar,
  teamCover,
  scoreboard,
}

/// Photography direction for Sportika imagery.
///
/// Use natural photography for athletes and community content.
/// Reserve cinematic grading for major branded surfaces.
enum SportikaPhotographyStyle {
  cinematicAction,
  athleteEditorial,
  matchDocumentary,
  atmosphericEnvironment,
}

/// Brand color treatment applied over photography.
enum SportikaImageGrade { natural, subtle, branded, cinematic }

/// Where text or interface elements sit over an image.
///
/// The strongest scrim should appear behind the content,
/// not automatically across the entire photograph.
enum SportikaImageTextZone { none, top, bottom, start, end }

/// A normalized focal point within an image.
///
/// Coordinates range from 0 to 1.
/// (0, 0) is top-left; (1, 1) is bottom-right.
///
/// This is a crop preference, not subject detection.
@immutable
class SportikaImageFocalPoint {
  const SportikaImageFocalPoint({required this.x, required this.y})
    : assert(x >= 0 && x <= 1),
      assert(y >= 0 && y <= 1);

  final double x;
  final double y;

  Alignment get alignment => Alignment(x * 2 - 1, y * 2 - 1);

  static const center = SportikaImageFocalPoint(x: 0.5, y: 0.5);

  static const upperCenter = SportikaImageFocalPoint(x: 0.5, y: 0.225);

  static const lowerCenter = SportikaImageFocalPoint(x: 0.5, y: 0.775);

  static const leftCenter = SportikaImageFocalPoint(x: 0.225, y: 0.5);

  static const rightCenter = SportikaImageFocalPoint(x: 0.775, y: 0.5);
}

/// Decoded bitmap dimensions.
///
/// Pass these values to Image.network's cacheWidth/cacheHeight
/// or the equivalent image provider when supported.
@immutable
class SportikaImageDecodeSize {
  const SportikaImageDecodeSize({required this.width, required this.height});

  final int width;
  final int height;
}

/// A complete art-direction configuration.
///
/// Widgets can consume one configuration rather than
/// independently selecting ratios, crop positions and grades.
@immutable
class SportikaImageSpec {
  const SportikaImageSpec({
    required this.role,
    required this.style,
    required this.grade,
    required this.textZone,
    required this.focalPoint,
    required this.aspectRatio,
  });

  final SportikaImageRole role;
  final SportikaPhotographyStyle style;
  final SportikaImageGrade grade;
  final SportikaImageTextZone textZone;
  final SportikaImageFocalPoint focalPoint;
  final double aspectRatio;

  Alignment get alignment => focalPoint.alignment;

  SportikaImageSpec copyWith({
    SportikaImageRole? role,
    SportikaPhotographyStyle? style,
    SportikaImageGrade? grade,
    SportikaImageTextZone? textZone,
    SportikaImageFocalPoint? focalPoint,
    double? aspectRatio,
  }) {
    return SportikaImageSpec(
      role: role ?? this.role,
      style: style ?? this.style,
      grade: grade ?? this.grade,
      textZone: textZone ?? this.textZone,
      focalPoint: focalPoint ?? this.focalPoint,
      aspectRatio: aspectRatio ?? this.aspectRatio,
    );
  }
}

/// Central Sportika photography and image art direction.
///
/// This class owns:
/// - Image roles and frame ratios
/// - Photography style defaults
/// - Focal points and crop preferences
/// - Responsive image decode budgets
/// - Selection of shared gradient recipes
/// - Branded image fallback treatments
///
/// Actual image loading, clipping, caching and rendering
/// belong in shared image widgets.
abstract final class SportikaImagery {
  SportikaImagery._();

  // --------------------------------------------------
  // ASPECT RATIOS
  // --------------------------------------------------

  static const double heroAspect = 4 / 5;
  static const double bannerAspect = 16 / 9;
  static const double cardAspect = 3 / 2;
  static const double tileAspect = 4 / 3;
  static const double portraitAspect = 3 / 4;
  static const double squareAspect = 1;

  static const double teamCoverAspect = 16 / 9;
  static const double scoreboardAspect = 21 / 9;

  static double aspectFor(SportikaImageRole role) {
    return switch (role) {
      SportikaImageRole.hero => heroAspect,
      SportikaImageRole.banner => bannerAspect,
      SportikaImageRole.card => cardAspect,
      SportikaImageRole.tile => tileAspect,
      SportikaImageRole.portrait => portraitAspect,
      SportikaImageRole.avatar => squareAspect,
      SportikaImageRole.teamCover => teamCoverAspect,
      SportikaImageRole.scoreboard => scoreboardAspect,
    };
  }

  // --------------------------------------------------
  // IMAGE DECODE BUDGETS
  // --------------------------------------------------

  static const int decodeWidthHero = 1600;
  static const int decodeWidthBanner = 1200;
  static const int decodeWidthCard = 960;
  static const int decodeWidthTile = 640;

  /// Retained for existing callers.
  static const int decodeWidthAvatar = 256;

  static const int decodeWidthPortrait = 800;
  static const int decodeWidthTeamCover = 1200;
  static const int decodeWidthScoreboard = 1400;

  static int decodeWidthFor(SportikaImageRole role) {
    return switch (role) {
      SportikaImageRole.hero => decodeWidthHero,
      SportikaImageRole.banner => decodeWidthBanner,
      SportikaImageRole.card => decodeWidthCard,
      SportikaImageRole.tile => decodeWidthTile,
      SportikaImageRole.portrait => decodeWidthAvatar,
      SportikaImageRole.avatar => decodeWidthAvatar,
      SportikaImageRole.teamCover => decodeWidthTeamCover,
      SportikaImageRole.scoreboard => decodeWidthScoreboard,
    };
  }

  /// Calculate decode dimensions using the actual rendered size.
  ///
  /// The result is capped by the role's maximum decode width.
  /// Width and height are both calculated to avoid oversized
  /// bitmap allocations in feeds.
  ///
  /// [logicalSize] must contain positive finite dimensions.
  /// [devicePixelRatio] must be positive and finite.
  ///
  /// For unknown layout dimensions, use [decodeWidthFor].
  static SportikaImageDecodeSize decodeSizeFor({
    required SportikaImageRole role,
    required Size logicalSize,
    required double devicePixelRatio,
  }) {
    assert(
      logicalSize.width.isFinite &&
          logicalSize.height.isFinite &&
          logicalSize.width > 0 &&
          logicalSize.height > 0,
    );

    assert(devicePixelRatio.isFinite && devicePixelRatio > 0);

    final safeWidth = logicalSize.width.isFinite && logicalSize.width > 0
        ? logicalSize.width
        : 1.0;

    final safeHeight = logicalSize.height.isFinite && logicalSize.height > 0
        ? logicalSize.height
        : 1.0;

    final safeDpr = devicePixelRatio.isFinite && devicePixelRatio > 0
        ? devicePixelRatio.clamp(1.0, 4.0)
        : 1.0;

    final maxWidth = decodeWidthFor(role);

    final requestedWidth = (safeWidth * safeDpr).ceil();

    final requestedHeight = (safeHeight * safeDpr).ceil();

    final scale = math.min(1.0, maxWidth / requestedWidth);

    return SportikaImageDecodeSize(
      width: math.max(1, (requestedWidth * scale).ceil()),
      height: math.max(1, (requestedHeight * scale).ceil()),
    );
  }

  // --------------------------------------------------
  // FOCAL POINTS
  // --------------------------------------------------

  static const Alignment focalTop = Alignment(0, -.55);

  static const Alignment focalCenter = Alignment.center;

  static const Alignment focalBottom = Alignment(0, .55);

  static const Alignment focalLeft = Alignment(-.55, 0);

  static const Alignment focalRight = Alignment(.55, 0);

  /// Existing role-based crop defaults.
  static Alignment focalFor(SportikaImageRole role) {
    return switch (role) {
      SportikaImageRole.hero => focalTop,
      SportikaImageRole.banner => focalLeft,
      SportikaImageRole.card => focalCenter,
      SportikaImageRole.tile => focalCenter,
      SportikaImageRole.portrait => focalTop,
      SportikaImageRole.avatar => focalCenter,
      SportikaImageRole.teamCover => focalCenter,
      SportikaImageRole.scoreboard => focalCenter,
    };
  }

  /// Focal alignment with an optional content-specific override.
  ///
  /// Example: a photograph can provide the athlete's face
  /// position rather than relying on the default crop.
  static Alignment resolveFocal({
    required SportikaImageRole role,
    SportikaImageFocalPoint? subject,
    bool mirrorHorizontally = false,
  }) {
    final alignment = subject?.alignment ?? focalFor(role);

    if (!mirrorHorizontally) {
      return alignment;
    }

    return Alignment(-alignment.x, alignment.y);
  }

  // --------------------------------------------------
  // PHOTOGRAPHY STYLE DEFAULTS
  // --------------------------------------------------

  static SportikaPhotographyStyle styleFor(SportikaImageRole role) {
    return switch (role) {
      SportikaImageRole.hero => SportikaPhotographyStyle.cinematicAction,

      SportikaImageRole.banner => SportikaPhotographyStyle.cinematicAction,

      SportikaImageRole.card => SportikaPhotographyStyle.matchDocumentary,

      SportikaImageRole.tile => SportikaPhotographyStyle.matchDocumentary,

      SportikaImageRole.portrait => SportikaPhotographyStyle.athleteEditorial,

      SportikaImageRole.avatar => SportikaPhotographyStyle.athleteEditorial,

      SportikaImageRole.teamCover => SportikaPhotographyStyle.matchDocumentary,

      SportikaImageRole.scoreboard =>
        SportikaPhotographyStyle.atmosphericEnvironment,
    };
  }

  // --------------------------------------------------
  // IMAGE GRADING
  // --------------------------------------------------

  static SportikaImageGrade gradeFor(SportikaImageRole role) {
    return switch (role) {
      SportikaImageRole.hero => SportikaImageGrade.cinematic,

      SportikaImageRole.banner => SportikaImageGrade.branded,

      SportikaImageRole.card => SportikaImageGrade.subtle,

      SportikaImageRole.tile => SportikaImageGrade.subtle,

      SportikaImageRole.portrait => SportikaImageGrade.natural,

      SportikaImageRole.avatar => SportikaImageGrade.natural,

      SportikaImageRole.teamCover => SportikaImageGrade.subtle,

      SportikaImageRole.scoreboard => SportikaImageGrade.branded,
    };
  }

  static double gradeStrength(SportikaImageGrade grade) {
    return switch (grade) {
      SportikaImageGrade.natural => 0.0,
      SportikaImageGrade.subtle => 0.30,
      SportikaImageGrade.branded => 0.65,
      SportikaImageGrade.cinematic => 1.0,
    };
  }

  // --------------------------------------------------
  // TEXT PLACEMENT
  // --------------------------------------------------

  static SportikaImageTextZone textZoneFor(SportikaImageRole role) {
    return switch (role) {
      SportikaImageRole.hero => SportikaImageTextZone.bottom,

      SportikaImageRole.banner => SportikaImageTextZone.start,

      SportikaImageRole.card => SportikaImageTextZone.bottom,

      SportikaImageRole.tile => SportikaImageTextZone.bottom,

      SportikaImageRole.portrait => SportikaImageTextZone.none,

      SportikaImageRole.avatar => SportikaImageTextZone.none,

      SportikaImageRole.teamCover => SportikaImageTextZone.bottom,

      SportikaImageRole.scoreboard => SportikaImageTextZone.start,
    };
  }

  // --------------------------------------------------
  // COMPLETE IMAGE CONFIGURATION
  // --------------------------------------------------

  /// Resolve default art direction for an image role.
  ///
  /// Any field may be overridden for a particular image.
  static SportikaImageSpec specFor({
    required SportikaImageRole role,
    SportikaPhotographyStyle? style,
    SportikaImageGrade? grade,
    SportikaImageTextZone? textZone,
    SportikaImageFocalPoint? focalPoint,
    double? aspectRatio,
  }) {
    final defaultAlignment = focalFor(role);

    return SportikaImageSpec(
      role: role,
      style: style ?? styleFor(role),
      grade: grade ?? gradeFor(role),
      textZone: textZone ?? textZoneFor(role),
      focalPoint:
          focalPoint ??
          SportikaImageFocalPoint(
            x: (defaultAlignment.x + 1) / 2,
            y: (defaultAlignment.y + 1) / 2,
          ),
      aspectRatio: aspectRatio ?? aspectFor(role),
    );
  }

  // --------------------------------------------------
  // LEGACY CONTRAST GRADIENTS
  // --------------------------------------------------

  /// Existing constants preserved for compatibility.
  static const LinearGradient footerContrast = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00061120), Color(0x8A061120), Color(0xF2061120)],
    stops: [0, .52, 1],
  );

  static const LinearGradient posterContrast = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x40071426),
      Color(0x8C071426),
      Color(0xE6071426),
      Color(0xFF071426),
    ],
    stops: [0, .42, .74, 1],
  );

  static const LinearGradient topContrast = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xA6071426), Color(0x00071426)],
    stops: [0, 1],
  );

  static LinearGradient contrastFor(SportikaImageRole role) {
    return switch (role) {
      SportikaImageRole.hero => footerContrast,
      SportikaImageRole.banner => posterContrast,
      SportikaImageRole.card => footerContrast,
      SportikaImageRole.tile => posterContrast,
      SportikaImageRole.portrait => footerContrast,
      SportikaImageRole.avatar => footerContrast,
      SportikaImageRole.teamCover => posterContrast,
      SportikaImageRole.scoreboard => posterContrast,
    };
  }

  // --------------------------------------------------
  // THEMED CONTRAST OVERLAYS
  // --------------------------------------------------

  /// Resolve an image scrim through the centralized gradient system.
  ///
  /// For portraits and avatars without overlaid text, no
  /// contrast scrim is applied.
  static LinearGradient? themedContrastFor({
    required SportikaImageRole role,
    required ColorScheme scheme,
    SportikaImageTextZone? textZone,
    bool reducedEffects = false,
  }) {
    final zone = textZone ?? textZoneFor(role);

    if (zone == SportikaImageTextZone.none) {
      return null;
    }

    final direction = switch (zone) {
      SportikaImageTextZone.none => SportikaScrimDirection.bottom,

      SportikaImageTextZone.top => SportikaScrimDirection.top,

      SportikaImageTextZone.bottom => SportikaScrimDirection.bottom,

      SportikaImageTextZone.start => SportikaScrimDirection.start,

      SportikaImageTextZone.end => SportikaScrimDirection.end,
    };

    final variant = switch (role) {
      SportikaImageRole.hero => SportikaMediaScrim.hero,

      SportikaImageRole.banner => SportikaMediaScrim.editorial,

      SportikaImageRole.card => SportikaMediaScrim.card,

      SportikaImageRole.tile => SportikaMediaScrim.tile,

      SportikaImageRole.portrait => SportikaMediaScrim.card,

      SportikaImageRole.avatar => SportikaMediaScrim.card,

      SportikaImageRole.teamCover => SportikaMediaScrim.editorial,

      SportikaImageRole.scoreboard => SportikaMediaScrim.hero,
    };

    return SportikaGradients.mediaScrim(
      scheme: scheme,
      variant: variant,
      direction: direction,
      intensity: SportikaGradientIntensity.cinematic,
      reducedEffects: reducedEffects,
    );
  }

  // --------------------------------------------------
  // BRANDED ARTWORK TREATMENT
  // --------------------------------------------------

  /// Existing API preserved for older screens.
  static LinearGradient artworkTreatment(Color tone, {double intensity = 1}) {
    final safeIntensity = intensity.isFinite ? intensity.clamp(0.0, 1.0) : 1.0;

    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        tone.withValues(alpha: 0.34 * safeIntensity),
        tone.withValues(alpha: 0.12 * safeIntensity),
        SportikaColors.deepest.withValues(alpha: 0.92),
      ],
      stops: const [0, .45, 1],
    );
  }

  /// New themed artwork treatment.
  ///
  /// Uses the selected grade rather than arbitrary intensity.
  /// Natural grade returns a transparent overlay.
  static LinearGradient themedArtworkTreatment({
    required ColorScheme scheme,
    required Color tone,
    SportikaImageGrade grade = SportikaImageGrade.subtle,
    bool reducedEffects = false,
  }) {
    final strength = reducedEffects ? 0.0 : gradeStrength(grade);

    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        tone.withValues(alpha: 0.30 * strength),
        tone.withValues(alpha: 0.10 * strength),
        scheme.surface.withValues(alpha: 0.18 * strength),
      ],
      stops: const [0, 0.45, 1],
    );
  }

  // --------------------------------------------------
  // PLACEHOLDERS AND FALLBACKS
  // --------------------------------------------------

  static const Color placeholderTint = SportikaColors.surfaceAlt;

  static const LinearGradient neutralTreatment = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [SportikaColors.surfaceAlt, SportikaColors.deepest],
  );

  /// Theme-aware fallback when an image is unavailable.
  ///
  /// A sport color may be supplied from sport_identity.dart.
  static RadialGradient fallbackFor({
    required ColorScheme scheme,
    Color? sportColor,
    bool reducedEffects = false,
  }) {
    final base = scheme.surfaceContainerHigh;

    if (reducedEffects) {
      return RadialGradient(colors: [base, base]);
    }

    final tone = sportColor ?? scheme.primary;

    return RadialGradient(
      center: const Alignment(-0.5, -0.4),
      radius: 1.25,
      colors: [Color.lerp(base, tone, 0.28)!, scheme.surfaceContainerLowest],
    );
  }
}
