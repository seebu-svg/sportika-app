import 'package:flutter/widgets.dart';

/// Global motion intensity.
///
/// Minimal removes decorative movement.
/// Standard is Sportika's recommended default.
/// Expressive is reserved for major branded moments.
enum SportikaMotionIntensity { minimal, standard, expressive }

/// Semantic animation categories.
///
/// Widgets request an intent rather than choosing arbitrary timings.
enum SportikaMotionType {
  instantFeedback,
  microInteraction,
  componentTransition,
  contentReveal,
  navigation,
  heroTransition,
  brandIntroduction,
}

/// Reusable animation recipes.
enum SportikaMotionRecipe {
  pressFeedback,
  fadeReveal,
  slideReveal,
  scoreChange,
  statusTransition,
  heroEntrance,
  tabIndicator,
}

/// Sport-specific motion character.
///
/// These are timing profiles, not separate animation systems.
enum SportikaMotionSport { cricket, padel, futsal, badminton }

/// Standard movement distances.
///
/// Distances are expressed in logical pixels.
abstract final class SportikaMotionDistance {
  SportikaMotionDistance._();

  static const double none = 0;
  static const double icon = 2;
  static const double chip = 4;
  static const double card = 8;
  static const double section = 12;
  static const double hero = 16;
}

/// Resolved animation configuration.
///
/// Shared widgets consume this rather than independently
/// selecting duration, curve, distance and opacity.
@immutable
class SportikaMotionSpec {
  const SportikaMotionSpec({
    required this.duration,
    required this.curve,
    this.distance = 0,
    this.scale = 1,
    this.opacity = 1,
  });

  final Duration duration;
  final Curve curve;

  /// Translation distance in logical pixels.
  final double distance;

  /// Target scale for interactions.
  final double scale;

  /// Target opacity for interactions.
  final double opacity;

  bool get isInstant => duration == Duration.zero;

  SportikaMotionSpec copyWith({
    Duration? duration,
    Curve? curve,
    double? distance,
    double? scale,
    double? opacity,
  }) {
    return SportikaMotionSpec(
      duration: duration ?? this.duration,
      curve: curve ?? this.curve,
      distance: distance ?? this.distance,
      scale: scale ?? this.scale,
      opacity: opacity ?? this.opacity,
    );
  }
}

/// Central Sportika motion design system.
///
/// Motion is:
/// - Fast and responsive for everyday interactions
/// - Restrained for scrolling content
/// - Expressive only for important branded moments
/// - Consistent across all four sports
/// - Accessibility-aware by default
///
/// This file defines motion behavior.
/// Shared widgets implement the actual animations.
abstract final class SportikaMotion {
  SportikaMotion._();

  // --------------------------------------------------
  // LEGACY DURATIONS
  // --------------------------------------------------

  static const Duration press = Duration(milliseconds: 90);

  static const Duration fast = Duration(milliseconds: 120);

  static const Duration field = Duration(milliseconds: 180);

  static const Duration base = Duration(milliseconds: 220);

  static const Duration indicator = Duration(milliseconds: 280);

  static const Duration reveal = Duration(milliseconds: 320);

  static const Duration slow = Duration(milliseconds: 380);

  static const Duration page = Duration(milliseconds: 420);

  static const Duration count = Duration(milliseconds: 520);

  static const Duration splash = Duration(milliseconds: 700);

  // --------------------------------------------------
  // LEGACY CURVES
  // --------------------------------------------------

  static const Curve standard = Curves.easeOutCubic;

  static const Curve enter = Curves.easeOutQuart;

  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  static const Curve decelerate = Curves.decelerate;

  static const Curve exit = Curves.easeInCubic;

  static const Curve overshoot = Curves.easeOutBack;

  // --------------------------------------------------
  // PRESS FEEDBACK
  // --------------------------------------------------

  static const double pressScale = 0.97;
  static const double pressOpacity = 0.92;

  // --------------------------------------------------
  // SEMANTIC DURATIONS
  // --------------------------------------------------

  static Duration durationFor(SportikaMotionType type) {
    return switch (type) {
      SportikaMotionType.instantFeedback => press,

      SportikaMotionType.microInteraction => field,

      SportikaMotionType.componentTransition => base,

      SportikaMotionType.contentReveal => reveal,

      SportikaMotionType.navigation => page,

      SportikaMotionType.heroTransition => count,

      SportikaMotionType.brandIntroduction => splash,
    };
  }

  // --------------------------------------------------
  // SEMANTIC CURVES
  // --------------------------------------------------

  static Curve curveFor(SportikaMotionType type) {
    return switch (type) {
      SportikaMotionType.instantFeedback => standard,

      SportikaMotionType.microInteraction => standard,

      SportikaMotionType.componentTransition => standard,

      SportikaMotionType.contentReveal => enter,

      SportikaMotionType.navigation => emphasized,

      SportikaMotionType.heroTransition => enter,

      SportikaMotionType.brandIntroduction => decelerate,
    };
  }

  // --------------------------------------------------
  // ACCESSIBILITY
  // --------------------------------------------------

  /// True when the platform requests reduced motion.
  static bool prefersReducedMotion(BuildContext context) {
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  /// Existing API preserved.
  ///
  /// Returns zero duration when reduced motion is enabled.
  static Duration resolve(BuildContext context, Duration duration) {
    return prefersReducedMotion(context) ? Duration.zero : duration;
  }

  /// Existing API preserved.
  static Duration pressDuration(BuildContext context) {
    return resolve(context, press);
  }

  // --------------------------------------------------
  // MOTION INTENSITY
  // --------------------------------------------------

  static double intensityMultiplier(SportikaMotionIntensity intensity) {
    return switch (intensity) {
      SportikaMotionIntensity.minimal => 0.0,
      SportikaMotionIntensity.standard => 1.0,
      SportikaMotionIntensity.expressive => 1.15,
    };
  }

  /// Resolves animation duration against accessibility
  /// and the selected global intensity.
  ///
  /// Minimal mode retains essential transitions but
  /// suppresses decorative animation.
  static Duration resolveSemantic(
    BuildContext context, {
    required SportikaMotionType type,
    SportikaMotionIntensity intensity = SportikaMotionIntensity.standard,
    bool decorative = false,
  }) {
    if (prefersReducedMotion(context)) {
      return Duration.zero;
    }

    if (decorative && intensity == SportikaMotionIntensity.minimal) {
      return Duration.zero;
    }

    final duration = durationFor(type);

    if (intensity == SportikaMotionIntensity.minimal) {
      return Duration(microseconds: (duration.inMicroseconds * 0.65).round());
    }

    if (intensity == SportikaMotionIntensity.expressive) {
      final multiplier = switch (type) {
        SportikaMotionType.heroTransition ||
        SportikaMotionType.brandIntroduction => 1.15,
        _ => 1.0,
      };

      return Duration(
        microseconds: (duration.inMicroseconds * multiplier).round(),
      );
    }

    return duration;
  }

  // --------------------------------------------------
  // SPORT-SPECIFIC TIMING
  // --------------------------------------------------

  /// Small timing variations that reflect each sport.
  ///
  /// Never use this to animate official scoring state
  /// before the underlying update is confirmed.
  static double sportMultiplier(SportikaMotionSport sport) {
    return switch (sport) {
      SportikaMotionSport.cricket => 1.05,
      SportikaMotionSport.padel => 0.90,
      SportikaMotionSport.futsal => 0.92,
      SportikaMotionSport.badminton => 0.95,
    };
  }

  static Duration resolveSportDuration(
    BuildContext context, {
    required SportikaMotionType type,
    required SportikaMotionSport sport,
    SportikaMotionIntensity intensity = SportikaMotionIntensity.standard,
    bool decorative = false,
  }) {
    final duration = resolveSemantic(
      context,
      type: type,
      intensity: intensity,
      decorative: decorative,
    );

    if (duration == Duration.zero) {
      return Duration.zero;
    }

    return Duration(
      microseconds: (duration.inMicroseconds * sportMultiplier(sport)).round(),
    );
  }

  // --------------------------------------------------
  // SHARED MOTION RECIPES
  // --------------------------------------------------

  /// Resolve a complete motion specification.
  ///
  /// Shared widgets should consume this configuration
  /// instead of defining their own animation values.
  static SportikaMotionSpec recipe(
    BuildContext context, {
    required SportikaMotionRecipe recipe,
    SportikaMotionIntensity intensity = SportikaMotionIntensity.standard,
    SportikaMotionSport? sport,
  }) {
    final type = switch (recipe) {
      SportikaMotionRecipe.pressFeedback => SportikaMotionType.instantFeedback,

      SportikaMotionRecipe.fadeReveal => SportikaMotionType.contentReveal,

      SportikaMotionRecipe.slideReveal => SportikaMotionType.contentReveal,

      SportikaMotionRecipe.scoreChange =>
        SportikaMotionType.componentTransition,

      SportikaMotionRecipe.statusTransition =>
        SportikaMotionType.microInteraction,

      SportikaMotionRecipe.heroEntrance => SportikaMotionType.heroTransition,

      SportikaMotionRecipe.tabIndicator =>
        SportikaMotionType.componentTransition,
    };

    final decorative = switch (recipe) {
      SportikaMotionRecipe.fadeReveal ||
      SportikaMotionRecipe.slideReveal ||
      SportikaMotionRecipe.heroEntrance => true,
      _ => false,
    };

    final duration = sport == null
        ? resolveSemantic(
            context,
            type: type,
            intensity: intensity,
            decorative: decorative,
          )
        : resolveSportDuration(
            context,
            type: type,
            sport: sport,
            intensity: intensity,
            decorative: decorative,
          );

    final reduced = duration == Duration.zero;

    final distance = switch (recipe) {
      SportikaMotionRecipe.slideReveal => SportikaMotionDistance.card,

      SportikaMotionRecipe.heroEntrance => SportikaMotionDistance.hero,

      _ => SportikaMotionDistance.none,
    };

    final curve = switch (recipe) {
      SportikaMotionRecipe.pressFeedback => standard,

      SportikaMotionRecipe.fadeReveal => enter,

      SportikaMotionRecipe.slideReveal => enter,

      SportikaMotionRecipe.scoreChange => standard,

      SportikaMotionRecipe.statusTransition => standard,

      SportikaMotionRecipe.heroEntrance => emphasized,

      SportikaMotionRecipe.tabIndicator => emphasized,
    };

    return SportikaMotionSpec(
      duration: duration,
      curve: curve,
      distance: reduced ? 0 : distance,
      scale: reduced || recipe != SportikaMotionRecipe.pressFeedback
          ? 1
          : pressScale,
      opacity: reduced || recipe != SportikaMotionRecipe.pressFeedback
          ? 1
          : pressOpacity,
    );
  }

  // --------------------------------------------------
  // STAGGERED CONTENT
  // --------------------------------------------------

  /// Small delay between items in a short featured section.
  ///
  /// Do not apply staggered reveals to long scrolling feeds.
  static Duration staggerDelay(
    BuildContext context, {
    required int index,
    int maxAnimatedItems = 4,
    Duration interval = const Duration(milliseconds: 45),
    SportikaMotionIntensity intensity = SportikaMotionIntensity.standard,
  }) {
    if (prefersReducedMotion(context) ||
        intensity == SportikaMotionIntensity.minimal ||
        index < 0 ||
        index >= maxAnimatedItems) {
      return Duration.zero;
    }

    return Duration(microseconds: interval.inMicroseconds * index);
  }

  // --------------------------------------------------
  // REPEATING / DECORATIVE MOTION
  // --------------------------------------------------

  /// Whether decorative looping animation is allowed.
  ///
  /// Use for ambient glows and similar nonessential effects.
  static bool allowDecorativeMotion(
    BuildContext context, {
    SportikaMotionIntensity intensity = SportikaMotionIntensity.standard,
  }) {
    return !prefersReducedMotion(context) &&
        intensity != SportikaMotionIntensity.minimal;
  }
}
