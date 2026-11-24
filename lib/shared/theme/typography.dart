import 'package:flutter/material.dart';

import 'package:sportika/shared/theme/tokens.dart';

/// Centralized font weights.
///
/// Widgets should never introduce arbitrary
/// FontWeight values outside the theme system.
abstract final class SportikaFontWeight {
  SportikaFontWeight._();

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
  static const FontWeight extraBold = FontWeight.w800;
  static const FontWeight black = FontWeight.w900;
}

/// Semantic typography roles.
///
/// Existing roles are preserved. Additional roles
/// support navigation, photography, scoreboards
/// and premium athlete profiles.
enum SportikaTextRole {
  hero,
  title,
  headline,
  scoreHero,
  scoreLarge,
  score,
  scoreSmall,
  label,
  body,
  caption,

  // Extended roles.
  wordmark,
  appBarTitle,
  cardTitle,
  titleMedium,
  tabLabel,
  scoreMicro,
  micro,
  bodyStrong,
  action,
  eyebrow,
  heroDisplay,
  athleteName,
  scoreboardLabel,
  statValue,
  statLabel,
}

/// Responsive typography sizes.
///
/// These are layout guidelines, not text-scale
/// restrictions. Accessibility scaling remains
/// controlled by the operating system.
abstract final class SportikaTypeSize {
  SportikaTypeSize._();

  static const double heroCompact = 28;
  static const double heroPhone = 32;
  static const double heroTablet = 40;

  static const double editorialCompact = 40;
  static const double editorialPhone = 52;
  static const double editorialTablet = 64;

  static const double athleteCompact = 34;
  static const double athletePhone = 42;
  static const double athleteTablet = 52;

  static const double scoreCompact = 40;
  static const double scorePhone = 46;
  static const double scoreTablet = 58;
}

/// Central Sportika typography system.
///
/// Inter:
/// Body text, buttons, forms, navigation,
/// descriptions and metadata.
///
/// Barlow Condensed:
/// Sports editorial headlines, athlete names,
/// match titles and scoring numerals.
///
/// Static styles remain the canonical dark
/// defaults for backward compatibility.
///
/// New widgets should prefer:
///
/// context.sportikaText.of(role)
///
/// This resolves the active brightness and
/// Material theme automatically.
abstract final class SportikaType {
  SportikaType._();

  // --------------------------------------------------
  // FONT FAMILIES
  // --------------------------------------------------

  static const String displayFamily = 'Barlow Condensed';

  static const String bodyFamily = 'Inter';

  // --------------------------------------------------
  // NUMERIC FEATURES
  // --------------------------------------------------

  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
  ];

  // --------------------------------------------------
  // EDITORIAL DISPLAY FACTORY
  // --------------------------------------------------

  /// Flexible display typography for splash,
  /// onboarding and sports editorial headers.
  ///
  /// Existing API preserved.
  static TextStyle display(
    double size, {
    Color color = SportikaColors.text,
    bool italic = false,
    double height = 0.92,
    double letterSpacing = -1,
    FontWeight weight = SportikaFontWeight.black,
    String family = displayFamily,
  }) {
    return TextStyle(
      fontFamily: family,
      fontSize: size,
      height: height,
      fontWeight: weight,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      letterSpacing: letterSpacing,
      color: color,
    );
  }

  // --------------------------------------------------
  // EDITORIAL HEADLINES
  // --------------------------------------------------

  static const TextStyle hero = TextStyle(
    fontFamily: displayFamily,
    fontSize: 32,
    height: 1.05,
    fontWeight: SportikaFontWeight.extraBold,
    letterSpacing: -0.6,
    color: SportikaColors.text,
  );

  static const TextStyle wordmark = TextStyle(
    fontFamily: displayFamily,
    fontSize: 52,
    height: 1,
    fontWeight: SportikaFontWeight.extraBold,
    letterSpacing: 5,
    color: SportikaColors.text,
  );

  static const TextStyle appBarTitle = TextStyle(
    fontFamily: displayFamily,
    fontSize: 21,
    height: 1.1,
    fontWeight: SportikaFontWeight.extraBold,
    letterSpacing: 0.4,
    color: SportikaColors.text,
  );

  static const TextStyle title = TextStyle(
    fontFamily: displayFamily,
    fontSize: 24,
    height: 1.1,
    fontWeight: SportikaFontWeight.extraBold,
    letterSpacing: -0.3,
    color: SportikaColors.text,
  );

  static const TextStyle cardTitle = TextStyle(
    fontFamily: displayFamily,
    fontSize: 21,
    height: 1.1,
    fontWeight: SportikaFontWeight.extraBold,
    letterSpacing: 0.2,
    color: SportikaColors.text,
  );

  /// Cinematic headline for image-backed heroes.
  static const TextStyle heroDisplay = TextStyle(
    fontFamily: displayFamily,
    fontSize: 52,
    height: 0.95,
    fontWeight: SportikaFontWeight.black,
    letterSpacing: -1.1,
    color: SportikaColors.text,
  );

  /// Athlete Passport name and player identity.
  static const TextStyle athleteName = TextStyle(
    fontFamily: displayFamily,
    fontSize: 42,
    height: 0.98,
    fontWeight: SportikaFontWeight.black,
    letterSpacing: -0.8,
    color: SportikaColors.text,
  );

  // --------------------------------------------------
  // INTERFACE HEADINGS
  // --------------------------------------------------

  static const TextStyle headline = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 19,
    height: 1.2,
    fontWeight: SportikaFontWeight.extraBold,
    letterSpacing: 0.2,
    color: SportikaColors.text,
  );

  static const TextStyle titleMedium = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 15.5,
    height: 1.25,
    fontWeight: SportikaFontWeight.bold,
    letterSpacing: 0.2,
    color: SportikaColors.text,
  );

  static const TextStyle tabLabel = TextStyle(
    fontFamily: displayFamily,
    fontSize: 15,
    height: 1.05,
    fontWeight: SportikaFontWeight.bold,
    letterSpacing: 1.1,
    color: SportikaColors.text,
  );

  // --------------------------------------------------
  // SCOREBOARD TYPOGRAPHY
  // --------------------------------------------------

  static const TextStyle scoreHero = TextStyle(
    fontFamily: displayFamily,
    fontSize: 46,
    height: 0.9,
    fontWeight: SportikaFontWeight.black,
    letterSpacing: -1.2,
    fontFeatures: tabularFigures,
    color: SportikaColors.text,
  );

  static const TextStyle scoreLarge = TextStyle(
    fontFamily: displayFamily,
    fontSize: 34,
    height: 0.95,
    fontWeight: SportikaFontWeight.black,
    letterSpacing: -0.8,
    fontFeatures: tabularFigures,
    color: SportikaColors.text,
  );

  static const TextStyle score = TextStyle(
    fontFamily: displayFamily,
    fontSize: 26,
    height: 1,
    fontWeight: SportikaFontWeight.extraBold,
    letterSpacing: -0.5,
    fontFeatures: tabularFigures,
    color: SportikaColors.text,
  );

  static const TextStyle scoreSmall = TextStyle(
    fontFamily: displayFamily,
    fontSize: 20,
    height: 1.05,
    fontWeight: SportikaFontWeight.extraBold,
    letterSpacing: 0.2,
    fontFeatures: tabularFigures,
    color: SportikaColors.text,
  );

  static const TextStyle scoreMicro = TextStyle(
    fontFamily: displayFamily,
    fontSize: 15,
    height: 1.1,
    fontWeight: SportikaFontWeight.bold,
    letterSpacing: 0.3,
    fontFeatures: tabularFigures,
    color: SportikaColors.text,
  );

  static const TextStyle scoreboardLabel = TextStyle(
    fontFamily: displayFamily,
    fontSize: 16,
    height: 1.1,
    fontWeight: SportikaFontWeight.bold,
    letterSpacing: 1,
    color: SportikaColors.textMuted,
  );

  static const TextStyle statValue = TextStyle(
    fontFamily: displayFamily,
    fontSize: 30,
    height: 1,
    fontWeight: SportikaFontWeight.black,
    letterSpacing: -0.5,
    fontFeatures: tabularFigures,
    color: SportikaColors.text,
  );

  static const TextStyle statLabel = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 11,
    height: 1.2,
    fontWeight: SportikaFontWeight.semibold,
    letterSpacing: 0.5,
    color: SportikaColors.textMuted,
  );

  // --------------------------------------------------
  // LABELS
  // --------------------------------------------------

  static const TextStyle label = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 11,
    height: 1.2,
    fontWeight: SportikaFontWeight.extraBold,
    letterSpacing: 1.5,
    color: SportikaColors.textMuted,
  );

  static const TextStyle eyebrow = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 11,
    height: 1.2,
    fontWeight: SportikaFontWeight.bold,
    letterSpacing: 1.8,
    color: SportikaColors.textMuted,
  );

  static const TextStyle micro = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 9.5,
    height: 1.2,
    fontWeight: SportikaFontWeight.extraBold,
    letterSpacing: 0.8,
    color: SportikaColors.textMuted,
  );

  // --------------------------------------------------
  // BODY COPY
  // --------------------------------------------------

  static const TextStyle body = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 13.5,
    height: 1.4,
    fontWeight: SportikaFontWeight.medium,
    color: SportikaColors.textBody,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 13.5,
    height: 1.3,
    fontWeight: SportikaFontWeight.bold,
    letterSpacing: 0.1,
    color: SportikaColors.text,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 11.5,
    height: 1.35,
    fontWeight: SportikaFontWeight.medium,
    color: SportikaColors.textMuted,
  );

  static const TextStyle action = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 12.5,
    height: 1.2,
    fontWeight: SportikaFontWeight.bold,
    letterSpacing: 0.3,
    color: SportikaColors.text,
  );

  // --------------------------------------------------
  // ROLE RESOLUTION
  // --------------------------------------------------

  /// Backward-compatible static role resolver.
  ///
  /// Returns dark brand defaults.
  static TextStyle of(SportikaTextRole role) {
    return switch (role) {
      SportikaTextRole.hero => hero,
      SportikaTextRole.title => title,
      SportikaTextRole.headline => headline,
      SportikaTextRole.scoreHero => scoreHero,
      SportikaTextRole.scoreLarge => scoreLarge,
      SportikaTextRole.score => score,
      SportikaTextRole.scoreSmall => scoreSmall,
      SportikaTextRole.label => label,
      SportikaTextRole.body => body,
      SportikaTextRole.caption => caption,
      SportikaTextRole.wordmark => wordmark,
      SportikaTextRole.appBarTitle => appBarTitle,
      SportikaTextRole.cardTitle => cardTitle,
      SportikaTextRole.titleMedium => titleMedium,
      SportikaTextRole.tabLabel => tabLabel,
      SportikaTextRole.scoreMicro => scoreMicro,
      SportikaTextRole.micro => micro,
      SportikaTextRole.bodyStrong => bodyStrong,
      SportikaTextRole.action => action,
      SportikaTextRole.eyebrow => eyebrow,
      SportikaTextRole.heroDisplay => heroDisplay,
      SportikaTextRole.athleteName => athleteName,
      SportikaTextRole.scoreboardLabel => scoreboardLabel,
      SportikaTextRole.statValue => statValue,
      SportikaTextRole.statLabel => statLabel,
    };
  }

  /// Resolve a semantic role for a specific brightness.
  ///
  /// All roles are brightness-aware, not only the
  /// standard Material TextTheme roles.
  static TextStyle resolve(
    SportikaTextRole role, {
    Brightness brightness = Brightness.dark,
    Color? color,
  }) {
    final base = of(role);

    if (color != null) {
      return base.copyWith(color: color);
    }

    if (brightness == Brightness.dark) {
      return base;
    }

    final resolvedColor = switch (role) {
      SportikaTextRole.body ||
      SportikaTextRole.caption ||
      SportikaTextRole.label ||
      SportikaTextRole.micro ||
      SportikaTextRole.eyebrow ||
      SportikaTextRole.statLabel ||
      SportikaTextRole.scoreboardLabel => SportikaColors.lightTextMuted,

      _ => SportikaColors.lightText,
    };

    return base.copyWith(color: resolvedColor);
  }

  // --------------------------------------------------
  // RESPONSIVE TYPOGRAPHY
  // --------------------------------------------------

  /// Resolve responsive editorial typography.
  ///
  /// Text scaling remains inherited from MediaQuery.
  /// This method adjusts the base size for layout
  /// width without disabling accessibility scaling.
  static TextStyle responsive(
    BuildContext context,
    SportikaTextRole role, {
    Color? color,
  }) {
    final width = MediaQuery.sizeOf(context).width;

    final brightness = Theme.of(context).brightness;

    final base = resolve(role, brightness: brightness, color: color);

    final responsiveSize = switch (role) {
      SportikaTextRole.hero =>
        width < SportikaBreakpoints.phone
            ? SportikaTypeSize.heroCompact
            : width < SportikaBreakpoints.tablet
            ? SportikaTypeSize.heroPhone
            : SportikaTypeSize.heroTablet,

      SportikaTextRole.heroDisplay =>
        width < SportikaBreakpoints.phone
            ? SportikaTypeSize.editorialCompact
            : width < SportikaBreakpoints.tablet
            ? SportikaTypeSize.editorialPhone
            : SportikaTypeSize.editorialTablet,

      SportikaTextRole.athleteName =>
        width < SportikaBreakpoints.phone
            ? SportikaTypeSize.athleteCompact
            : width < SportikaBreakpoints.tablet
            ? SportikaTypeSize.athletePhone
            : SportikaTypeSize.athleteTablet,

      SportikaTextRole.scoreHero =>
        width < SportikaBreakpoints.phone
            ? SportikaTypeSize.scoreCompact
            : width < SportikaBreakpoints.tablet
            ? SportikaTypeSize.scorePhone
            : SportikaTypeSize.scoreTablet,

      _ => base.fontSize,
    };

    return base.copyWith(fontSize: responsiveSize);
  }

  // --------------------------------------------------
  // MATERIAL TEXT THEME
  // --------------------------------------------------

  static TextTheme textTheme({Brightness brightness = Brightness.dark}) {
    if (brightness == Brightness.dark) {
      return _darkTextTheme;
    }

    return TextTheme(
      displayLarge: resolve(SportikaTextRole.hero, brightness: brightness),
      displayMedium: resolve(SportikaTextRole.title, brightness: brightness),
      displaySmall: resolve(SportikaTextRole.headline, brightness: brightness),
      headlineLarge: resolve(SportikaTextRole.headline, brightness: brightness),
      headlineMedium: resolve(
        SportikaTextRole.headline,
        brightness: brightness,
      ),
      headlineSmall: resolve(
        SportikaTextRole.titleMedium,
        brightness: brightness,
      ),
      titleLarge: resolve(SportikaTextRole.headline, brightness: brightness),
      titleMedium: resolve(
        SportikaTextRole.titleMedium,
        brightness: brightness,
      ),
      titleSmall: resolve(SportikaTextRole.action, brightness: brightness),
      bodyLarge: resolve(SportikaTextRole.body, brightness: brightness),
      bodyMedium: resolve(SportikaTextRole.body, brightness: brightness),
      bodySmall: resolve(SportikaTextRole.caption, brightness: brightness),
      labelLarge: resolve(SportikaTextRole.action, brightness: brightness),
      labelMedium: resolve(SportikaTextRole.label, brightness: brightness),
      labelSmall: resolve(SportikaTextRole.micro, brightness: brightness),
    );
  }

  static const TextTheme _darkTextTheme = TextTheme(
    displayLarge: hero,
    displayMedium: title,
    displaySmall: headline,
    headlineLarge: headline,
    headlineMedium: headline,
    headlineSmall: titleMedium,
    titleLarge: headline,
    titleMedium: titleMedium,
    titleSmall: action,
    bodyLarge: body,
    bodyMedium: body,
    bodySmall: caption,
    labelLarge: action,
    labelMedium: label,
    labelSmall: micro,
  );
}

// --------------------------------------------------
// CONTEXT-AWARE TYPOGRAPHY
// --------------------------------------------------

/// Semantic typography resolved from the active theme.
///
/// Usage:
///
/// context.sportikaText.of(SportikaTextRole.hero)
///
/// context.sportikaText.responsive(
///   SportikaTextRole.heroDisplay,
/// )
@immutable
class SportikaTypography {
  const SportikaTypography(this.context);

  final BuildContext context;

  Brightness get brightness => Theme.of(context).brightness;

  TextTheme get material => Theme.of(context).textTheme;

  TextStyle of(SportikaTextRole role, {Color? color}) {
    return SportikaType.resolve(role, brightness: brightness, color: color);
  }

  TextStyle responsive(SportikaTextRole role, {Color? color}) {
    return SportikaType.responsive(context, role, color: color);
  }
}

/// Access the active Sportika typography.
extension SportikaTypographyContext on BuildContext {
  SportikaTypography get sportikaText => SportikaTypography(this);
}

// --------------------------------------------------
// LAYOUT AND ACCESSIBILITY
// --------------------------------------------------

const double sportikaMaxContentWidth = SportikaBreakpoints.maxContent;

/// Legacy compatibility value.
///
/// New screens should not globally restrict the
/// operating system's text scaling.
const double sportikaMaxTextScale = 1.3;

/// Compatibility wrapper.
///
/// Previously this clamped text scaling globally.
/// It now preserves the inherited MediaQuery scaling
/// so users can access larger text sizes.
///
/// Dense scoreboard widgets should handle their
/// own responsive constraints.
class ClampedTextScale extends StatelessWidget {
  const ClampedTextScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
