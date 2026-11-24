import 'package:flutter/material.dart';

/// Raw Sportika brand primitives.
///
/// Screens must consume semantic colors through
/// SportikaColors or the active SportikaTheme.
///
/// Raw palette values belong only in the shared
/// theme system.
abstract final class SportikaPalette {
  SportikaPalette._();

  // --------------------------------------------------
  // NAVY DEPTH RAMP
  // --------------------------------------------------

  static const Color ink = Color(0xFF030A14);
  static const Color midnight = Color(0xFF061120);

  static const Color navy1000 = Color(0xFF071426);
  static const Color navy975 = Color(0xFF0A1B31);
  static const Color navy900 = Color(0xFF102541);
  static const Color navy850 = Color(0xFF152B49);
  static const Color navy800 = Color(0xFF16304F);
  static const Color navy750 = Color(0xFF1E3C61);
  static const Color navy700 = Color(0xFF24486F);

  // --------------------------------------------------
  // LINES AND OUTLINES
  // --------------------------------------------------

  static const Color line700 = Color(0xFF1A3453);
  static const Color line600 = Color(0xFF26466A);
  static const Color line500 = Color(0xFF3A6089);
  static const Color line400 = Color(0xFF5B82AB);

  // --------------------------------------------------
  // NEUTRALS
  // --------------------------------------------------

  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);

  static const Color mist100 = Color(0xFFF4F8FF);
  static const Color mist200 = Color(0xFFDCE6F2);

  static const Color slate300 = Color(0xFFC7D8EC);
  static const Color slate400 = Color(0xFF93A9C4);
  static const Color slate500 = Color(0xFF6F87A5);
  static const Color slate600 = Color(0xFF52657C);

  // --------------------------------------------------
  // BRAND BLUE
  // --------------------------------------------------

  static const Color blue600 = Color(0xFF0F4FD8);
  static const Color blue500 = Color(0xFF1769FF);
  static const Color blue400 = Color(0xFF3B82FF);
  static const Color blue300 = Color(0xFF6FA3FF);

  // --------------------------------------------------
  // LIVE MINT
  // --------------------------------------------------

  static const Color mint500 = Color(0xFF36D8BD);
  static const Color mint400 = Color(0xFF81EFCE);

  static const Color mintSpecular = Color(0xFFDAFFF4);

  static const Color mintMetal = Color(0xFF3FC5AE);

  static const Color mint600 = Color(0xFF0E8F79);
  static const Color mint700 = Color(0xFF087D65);
  static const Color mint800 = Color(0xFF0A6C60);

  // --------------------------------------------------
  // ACHIEVEMENT GOLD
  // --------------------------------------------------

  static const Color gold300 = Color(0xFFFFD68F);
  static const Color gold400 = Color(0xFFF6B84B);
  static const Color gold600 = Color(0xFFA6720A);
  static const Color gold700 = Color(0xFF8C5A08);

  static const Color bronze300 = Color(0xFFE1A868);

  static const Color copper500 = Color(0xFFC4894E);

  // --------------------------------------------------
  // BADMINTON VIOLET
  // --------------------------------------------------

  /// Illuminated violet highlight.
  static const Color violet300 = Color(0xFFB2A5FF);

  /// Primary Badminton identity.
  static const Color violet500 = Color(0xFF8375F3);

  /// Deep violet for gradients and pressed states.
  static const Color violet700 = Color(0xFF5143B6);

  /// Atmospheric violet lighting.
  static const Color violetAtmosphere = Color(0x288375F3);

  /// Soft violet selection tint.
  static const Color violetSubtle = Color(0x248375F3);

  // --------------------------------------------------
  // DANGER
  // --------------------------------------------------

  static const Color red500 = Color(0xFFE5484D);
  static const Color red400 = Color(0xFFFF6B70);
  static const Color red900 = Color(0xFF5C1018);

  // --------------------------------------------------
  // ATMOSPHERE AND ALLOY
  // --------------------------------------------------

  static const Color indigoAlloy = Color(0xFF191E38);

  static const Color tealAlloy = Color(0xFF12333C);

  static const Color mintAtmosphere = Color(0x3836D8BD);

  static const Color indigoAtmosphere = Color(0x272E57BD);

  static const Color blueAtmosphere = Color(0x241769FF);

  // --------------------------------------------------
  // TRANSPARENT PRIMITIVES
  // --------------------------------------------------

  static const Color transparent = Color(0x00000000);

  static const Color navyClear = Color(0x00071426);

  static const Color midnightClear = Color(0x00061120);

  static const Color deepestClear = Color(0x00061120);

  static const Color whiteClear = Color(0x00FFFFFF);

  static const Color goldClear = Color(0x00F6B84B);

  static const Color violetClear = Color(0x008375F3);

  // --------------------------------------------------
  // SCRIMS AND OVERLAYS
  // --------------------------------------------------

  static const Color scrim = Color(0x66000000);
  static const Color scrimDeep = Color(0x99000000);

  static const Color surfaceGlass = Color(0xA6102541);

  static const Color surfaceGlassStrong = Color(0xCC0A1B31);

  static const Color overlay = Color(0x33FFFFFF);

  static const Color overlaySoft = Color(0x1FFFFFFF);

  static const Color overlayHairline = Color(0x0FFFFFFF);

  static const Color courtLine = Color(0x0E36D8BD);

  static const Color mintGlow = Color(0x1F36D8BD);

  static const Color mintHighlight = Color(0x0FFFFFFF);
}

/// Semantic colors for the Sportika design system.
///
/// Screens should prefer context.sportika for
/// brightness-aware colors and effects.
///
/// These static tokens remain the canonical dark
/// brand palette and compatibility layer.
abstract final class SportikaColors {
  SportikaColors._();

  // --------------------------------------------------
  // DARK SURFACES
  // --------------------------------------------------

  static const Color deepest = SportikaPalette.midnight;

  static const Color background = SportikaPalette.navy1000;

  static const Color page = SportikaPalette.navy1000;

  static const Color surfaceSunken = SportikaPalette.navy975;

  static const Color surface = SportikaPalette.navy900;

  static const Color surfaceAlt = SportikaPalette.navy800;

  static const Color surfaceHigh = SportikaPalette.navy750;

  static const Color surfaceElevated = SportikaPalette.navy800;

  // --------------------------------------------------
  // SEMANTIC SURFACE ALIASES
  // --------------------------------------------------

  /// Default match, tournament and team cards.
  static const Color cardSurface = surface;

  /// Interactive controls and selectable elements.
  static const Color interactiveSurface = surfaceAlt;

  /// Elevated navigation and floating chrome.
  static const Color navigationSurface = surface;

  /// Overlay panels, sheets and popovers.
  static const Color overlaySurface = surfaceHigh;

  /// Recessed live scoreboard sections.
  static const Color scoreboardSurface = surfaceSunken;

  /// Featured hero surfaces.
  static const Color heroSurface = deepest;

  /// Selected item surface.
  static const Color selectedSurface = surfaceAlt;

  // --------------------------------------------------
  // LIGHT SURFACES
  // --------------------------------------------------

  static const Color lightSurface = SportikaPalette.white;

  static const Color lightSurfaceAlt = SportikaPalette.mist100;

  static const Color lightText = Color(0xFF0B1B2E);

  static const Color lightTextMuted = SportikaPalette.slate600;

  static const Color lightBorder = SportikaPalette.mist200;

  static const Color lightBlue = SportikaPalette.mist100;

  static const Color lightMint = Color(0xFFE0F8F1);

  static const Color lightMintSurface = Color(0xFFE0F8F1);

  static const Color lightMintText = SportikaPalette.mint700;

  static const Color lightGlass = Color(0xB3FFFFFF);

  static const Color lightGlassStrong = Color(0xE6FFFFFF);

  static const Color lightGlassBorder = Color(0x1F0B1B2E);

  // --------------------------------------------------
  // BORDERS
  // --------------------------------------------------

  static const Color border = SportikaPalette.line600;

  static const Color borderSubtle = SportikaPalette.line700;

  static const Color borderStrong = SportikaPalette.line500;

  static const Color outline = SportikaPalette.line400;

  // --------------------------------------------------
  // TYPOGRAPHY COLORS
  // --------------------------------------------------

  static const Color text = SportikaPalette.mist100;

  static const Color textBody = SportikaPalette.slate300;

  static const Color textMuted = SportikaPalette.slate400;

  static const Color textDim = SportikaPalette.slate500;

  // --------------------------------------------------
  // BRAND BLUE
  // --------------------------------------------------

  static const Color blue = SportikaPalette.blue500;

  static const Color blueBright = SportikaPalette.blue400;

  static const Color blueDeep = SportikaPalette.blue600;

  static const Color blueSoft = SportikaPalette.blue300;

  static const Color blueSubtle = Color(0x241769FF);

  // --------------------------------------------------
  // LIVE MINT
  // --------------------------------------------------

  static const Color mint = SportikaPalette.mint500;

  static const Color mintSoft = SportikaPalette.mint400;

  static const Color mintDeep = SportikaPalette.mint700;

  static const Color mintSubtle = Color(0x2436D8BD);

  // --------------------------------------------------
  // ACHIEVEMENT GOLD
  // --------------------------------------------------

  static const Color gold = SportikaPalette.gold400;

  static const Color goldDeep = SportikaPalette.gold600;

  static const Color goldSubtle = Color(0x1FF6B84B);

  static const Color bronze = SportikaPalette.bronze300;

  static const Color copper = SportikaPalette.copper500;

  // --------------------------------------------------
  // BADMINTON VIOLET
  // --------------------------------------------------

  static const Color violet = SportikaPalette.violet500;

  static const Color violetBright = SportikaPalette.violet300;

  static const Color violetDeep = SportikaPalette.violet700;

  static const Color violetSubtle = SportikaPalette.violetSubtle;

  // --------------------------------------------------
  // DANGER
  // --------------------------------------------------

  static const Color danger = SportikaPalette.red500;

  static const Color dangerBright = SportikaPalette.red400;

  static const Color dangerDeep = SportikaPalette.red900;

  static const Color dangerSubtle = Color(0x1FE5484D);

  // --------------------------------------------------
  // FOREGROUND ON ACCENTS
  // --------------------------------------------------

  static const Color onAccent = SportikaPalette.white;

  static const Color onMint = SportikaPalette.midnight;

  static const Color onGold = SportikaPalette.midnight;

  static const Color onViolet = SportikaPalette.white;

  // --------------------------------------------------
  // SPORT IDENTITIES
  // --------------------------------------------------

  static const Color cricket = SportikaPalette.blue500;

  static const Color padel = SportikaPalette.mint500;

  static const Color futsal = SportikaPalette.gold400;

  static const Color badminton = SportikaPalette.violet500;

  static const Color badmintonBright = SportikaPalette.violet300;

  static const Color badmintonDeep = SportikaPalette.violet700;

  // --------------------------------------------------
  // UTILITY
  // --------------------------------------------------

  static const Color transparent = SportikaPalette.transparent;

  static const Color scrim = SportikaPalette.scrim;

  static const Color scrimDeep = SportikaPalette.scrimDeep;

  static const Color glass = SportikaPalette.surfaceGlass;

  static const Color glassStrong = SportikaPalette.surfaceGlassStrong;

  static const Color overlay = SportikaPalette.overlay;

  static const Color overlaySoft = SportikaPalette.overlaySoft;

  static const Color overlayHairline = SportikaPalette.overlayHairline;

  static const Color skeleton = SportikaPalette.navy800;

  static const Color shadowBase = SportikaPalette.ink;

  static const Color courtLine = SportikaPalette.courtLine;
}

/// Shared spacing scale.
///
/// Preserve these values so existing layouts remain
/// visually stable during the theme migration.
abstract final class SportikaSpacing {
  SportikaSpacing._();

  static const double xxs = 2;
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double xxl = 36;
  static const double xxxl = 48;

  static const double page = 24;
  static const double gutter = 16;
}

/// Shared component corner radii.
abstract final class SportikaRadius {
  SportikaRadius._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double chip = 6;
  static const double tag = 8;
  static const double badge = 9;
  static const double sm = 10;
  static const double control = 12;
  static const double md = 14;
  static const double thumbnail = 16;
  static const double lg = 18;
  static const double dialog = 22;
  static const double xl = 24;
  static const double xxl = 28;
  static const double pill = 999;

  // Semantic aliases.
  static const double card = lg;
  static const double button = md;
  static const double field = md;
  static const double sheet = xl;
  static const double passport = 20;
  static const double passportInner = 19;
}

/// Shared border widths.
abstract final class SportikaBorder {
  SportikaBorder._();

  static const double hairline = 1;
  static const double rule = 1.5;
  static const double emphasis = 1.4;
  static const double focused = 1.6;
}

/// Shared opacity ladder.
abstract final class SportikaOpacity {
  SportikaOpacity._();

  static const double whisper = 0.04;
  static const double faint = 0.08;
  static const double soft = 0.12;
  static const double tint = 0.14;
  static const double muted = 0.22;
  static const double medium = 0.35;
  static const double strong = 0.50;
  static const double heavy = 0.72;
  static const double scrim = 0.86;
}

/// Semantic interaction strengths.
///
/// Used by buttons, chips, cards, navigation
/// and live scoring controls.
abstract final class SportikaInteraction {
  SportikaInteraction._();

  static const double hover = SportikaOpacity.faint;

  static const double pressed = SportikaOpacity.soft;

  static const double selected = SportikaOpacity.muted;

  static const double disabled = SportikaOpacity.medium;

  static const double focus = SportikaOpacity.strong;
}

/// Shared icon dimensions.
abstract final class SportikaIconSize {
  SportikaIconSize._();

  static const double xs = 12;
  static const double sm = 15;
  static const double md = 18;
  static const double lg = 22;
  static const double xl = 28;
}

/// Accessible minimum touch targets.
abstract final class SportikaTouchTarget {
  SportikaTouchTarget._();

  static const double minimum = 48;
  static const double comfortable = 52;
  static const double prominent = 56;
}

/// Shared component dimensions.
///
/// These are recommended defaults, not rigid
/// maximums. Widgets must accommodate text scaling.
abstract final class SportikaComponentSize {
  SportikaComponentSize._();

  static const double buttonHeight = 52;
  static const double inputHeight = 56;
  static const double bottomNavHeight = 72;

  static const double avatarSm = 36;
  static const double avatarMd = 48;
  static const double avatarLg = 72;

  static const double heroMinHeight = 220;

  static const double chipHeight = 36;
  static const double compactButtonHeight = 44;

  static const double scoreboardRowHeight = 64;
}

/// Responsive image geometry.
///
/// Image dimensions are layout guidance.
/// Decode budgets remain in SportikaImagery.
abstract final class SportikaImageSize {
  SportikaImageSize._();

  static const double cardAspectRatio = 1.5;
  static const double heroAspectRatio = 1.2;
  static const double bannerAspectRatio = 2.2;

  static const double portraitAspectRatio = 0.8;
  static const double avatarAspectRatio = 1.0;

  static const double teamCoverAspectRatio = 1.8;
}

/// Responsive layout breakpoints.
abstract final class SportikaBreakpoints {
  SportikaBreakpoints._();

  static const double compact = 320;
  static const double phone = 480;
  static const double tablet = 760;
  static const double desktop = 1024;

  static const double maxContent = 640;
}
