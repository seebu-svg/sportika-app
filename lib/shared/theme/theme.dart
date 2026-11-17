import 'package:flutter/material.dart';

import 'package:sportika/features/personal_games/scoring/engine.dart'
    as scoring;
import 'package:sportika/shared/theme/typography.dart';

/// Sportika design tokens - layered navy surfaces with athletic accents. Accent roles stay disciplined: blue for action, mint for
/// live/active, gold for achievement, and navy for hero surfaces.
class SportikaColors {
  SportikaColors._();

  // Layered surfaces.
  static const Color deepest = Color(0xFF09182D);
  static const Color background = Color(0xFF061426);
  static const Color page = Color(0xFF061426);
  static const Color surface = Color(0xFF10243D);
  static const Color surfaceAlt = Color(0xFF142C48);
  static const Color surfaceSunken = Color(0xFF0B1D33);
  static const Color surfaceElevated = Color(0xFF10243D);

  // Light surfaces used by match lineup components.
  static const Color lightSurface = Colors.white;
  static const Color lightText = surface;
  static const Color lightTextMuted = Color(0xFF617087);
  static const Color lightBorder = Color(0xFFE5EBF2);
  static const Color lightBlue = Color(0xFFF0F5FF);
  static const Color lightMint = Color(0xFFE0F8F1);
  static const Color lightMintText = Color(0xFF087D65);

  // Borders.
  static const Color border = Color(0xFF233A54);
  static const Color borderSubtle = Color(0xFF1A3049);
  static const Color borderStrong = Color(0xFF36506D);

  // Text.
  static const Color text = Color(0xFFFFFFFF);
  static const Color textBody = Color(0xFFD4DEEC);
  static const Color textMuted = Color(0xFFA8B8CF);
  static const Color textDim = Color(0xFF8399B5);

  // Accents.
  static const Color blue = Color(0xFF1769FF);
  static const Color blueBright = Color(0xFF2E7DFF);
  static const Color blueSubtle = Color(0x141769FF);
  static const Color mint = Color(0xFF36D8BD);
  static const Color mintSoft = Color(0xFF36D8BD);
  static const Color mintSubtle = Color(0x140A8B78);
  static const Color gold = Color(0xFFF6B84B);
  static const Color goldSubtle = Color(0x1AA6720A);
  static const Color danger = Color(0xFFD92D3B);
  static const Color dangerSubtle = Color(0x14D92D3B);

  // Sport identity tints (used on chips and cards).
  static const Color cricket = Color(0xFF1769FF);
  static const Color padel = Color(0xFF36D8BD);
  static const Color futsal = gold;
  static const Color badminton = blueBright;
}

class SportikaSpacing {
  SportikaSpacing._();
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
}

/// Corner radii. Anything below [pill] must match a real container; [pill] is
/// the fully rounded chip/avatar shape.
class SportikaRadius {
  SportikaRadius._();
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double pill = 999;
}

/// Shared motion vocabulary so transitions feel like one product.
class SportikaMotion {
  SportikaMotion._();
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 380);
  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
  static const Curve exit = Curves.easeInCubic;
}

/// Maps a scoring engine action style onto brand colours.
ThemeColors styleColors(scoring.ActionStyle style) => switch (style) {
  scoring.ActionStyle.primary => const ThemeColors(
    SportikaColors.blue,
    SportikaColors.blueBright,
    Colors.white,
  ),
  scoring.ActionStyle.highlight => const ThemeColors(
    SportikaColors.mint,
    SportikaColors.mint,
    Colors.white,
  ),
  scoring.ActionStyle.danger => const ThemeColors(
    SportikaColors.danger,
    Color(0xFFE85A66),
    Colors.white,
  ),
  scoring.ActionStyle.subtle => const ThemeColors(
    SportikaColors.surfaceAlt,
    SportikaColors.borderStrong,
    SportikaColors.textBody,
  ),
  scoring.ActionStyle.neutral => const ThemeColors(
    SportikaColors.surface,
    SportikaColors.border,
    SportikaColors.text,
  ),
};

class ThemeColors {
  final Color fill;
  final Color border;
  final Color fg;
  const ThemeColors(this.fill, this.border, this.fg);
}

ThemeData buildSportikaTheme() {
  const scheme = ColorScheme.dark(
    primary: SportikaColors.blue,
    onPrimary: Colors.white,
    primaryContainer: SportikaColors.surfaceAlt,
    onPrimaryContainer: SportikaColors.text,
    secondary: SportikaColors.mint,
    onSecondary: SportikaColors.deepest,
    secondaryContainer: SportikaColors.blueSubtle,
    onSecondaryContainer: SportikaColors.blue,
    tertiary: SportikaColors.gold,
    onTertiary: SportikaColors.deepest,
    error: SportikaColors.danger,
    onError: Colors.white,
    surface: SportikaColors.surface,
    onSurface: SportikaColors.text,
    onSurfaceVariant: SportikaColors.textMuted,
    outline: SportikaColors.borderStrong,
    outlineVariant: SportikaColors.border,
    scrim: Colors.black,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: SportikaColors.background,
    splashFactory: InkSparkle.splashFactory,
    fontFamily: 'Inter',
    visualDensity: VisualDensity.standard,
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: SportikaColors.surface,
      foregroundColor: SportikaColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.6,
        color: SportikaColors.text,
      ),
    ),
    cardTheme: CardThemeData(
      color: SportikaColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: SportikaColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 46),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: SportikaColors.borderSubtle,
      thickness: 1,
      space: 1,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: SportikaColors.surfaceAlt,
      side: const BorderSide(color: SportikaColors.border),
      labelStyle: const TextStyle(
        color: SportikaColors.textBody,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SportikaColors.surfaceSunken,
      hintStyle: const TextStyle(color: SportikaColors.textDim),
      labelStyle: const TextStyle(color: SportikaColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SportikaColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SportikaColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SportikaColors.blue, width: 1.6),
      ),
    ),
    textTheme: base.textTheme
        .apply(
          bodyColor: SportikaColors.text,
          displayColor: SportikaColors.text,
        )
        .copyWith(
          displaySmall: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: SportikaColors.text,
          ),
          titleLarge: SportikaType.headline,
          titleMedium: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15.5,
            letterSpacing: 0.2,
            color: SportikaColors.text,
          ),
          bodyMedium: const TextStyle(
            color: SportikaColors.textBody,
            height: 1.35,
          ),
          bodySmall: const TextStyle(
            color: SportikaColors.textMuted,
            height: 1.3,
          ),
          labelSmall: SportikaType.label,
        ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: SportikaColors.deepest,
      contentTextStyle: TextStyle(color: Colors.white),
      actionTextColor: SportikaColors.mintSoft,
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: SportikaColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: SportikaColors.border),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: SportikaColors.surface,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Color(0x6609182D),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: SportikaColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: SportikaColors.mintSubtle,
      height: 68,
      elevation: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 23,
          color: states.contains(WidgetState.selected)
              ? SportikaColors.mint
              : SportikaColors.textMuted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: states.contains(WidgetState.selected)
              ? SportikaColors.mint
              : SportikaColors.textMuted,
        ),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: SportikaColors.textMuted,
      textColor: SportikaColors.text,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: SportikaColors.blue,
      linearTrackColor: SportikaColors.borderSubtle,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? SportikaColors.blueSubtle
              : SportikaColors.surfaceSunken,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? SportikaColors.blue
              : SportikaColors.textBody,
        ),
        side: WidgetStateProperty.all(
          const BorderSide(color: SportikaColors.border),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ),
  );
}
