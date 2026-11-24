import 'package:flutter/material.dart';

import 'package:sportika/shared/theme/tokens.dart';
import 'package:sportika/shared/theme/typography.dart';

/// Central Material 3 component styling for Sportika.
///
/// All components resolve colors from the active ColorScheme.
/// No screen-specific colors are required.
abstract final class SportikaComponentThemes {
  SportikaComponentThemes._();

  // Shared component dimensions.
  static const double _appBarHeight = 64;
  static const double _navigationHeight = 72;
  static const double _buttonHeight = 52;
  static const double _compactButtonHeight = 44;
  static const double _touchTarget = 48;
  static const double _navigationIconSize = 24;
  static const double _buttonHorizontalPadding = 22;
  static const double _fieldPadding = 16;
  static const double _chipFontSize = 12;
  static const double _navigationFontSize = 11.5;

  // Interaction opacity values.
  static const double _hoverOpacity = 0.06;
  static const double _focusOpacity = 0.12;
  static const double _pressedOpacity = 0.14;
  static const double _selectedOpacity = 0.20;
  static const double _disabledOpacity = 0.38;

  static const Duration _animationDuration = Duration(milliseconds: 220);

  static RoundedRectangleBorder _rect(
    double radius, {
    Color? side,
    double width = 1,
  }) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: side == null
          ? BorderSide.none
          : BorderSide(color: side, width: width),
    );
  }

  static WidgetStateProperty<Color?> _overlay(Color color) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return Colors.transparent;
      }
      if (states.contains(WidgetState.pressed)) {
        return color.withValues(alpha: _pressedOpacity);
      }
      if (states.contains(WidgetState.focused)) {
        return color.withValues(alpha: _focusOpacity);
      }
      if (states.contains(WidgetState.hovered)) {
        return color.withValues(alpha: _hoverOpacity);
      }
      return Colors.transparent;
    });
  }

  static WidgetStateProperty<Color?> _stateColor({
    required Color normal,
    Color? selected,
    Color? disabled,
  }) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return disabled ?? normal.withValues(alpha: _disabledOpacity);
      }
      if (states.contains(WidgetState.selected)) {
        return selected ?? normal;
      }
      return normal;
    });
  }

  static TextStyle _type(TextStyle style, Color color) {
    return style.copyWith(color: color);
  }

  static InputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(SportikaRadius.field),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  /// Applies Sportika's premium athletic design system.
  static ThemeData apply(ThemeData base) {
    final c = base.colorScheme;
    final t = base.textTheme;
    final isDark = base.brightness == Brightness.dark;

    final elevatedSurface = c.surfaceContainerHigh;
    final raisedSurface = c.surfaceContainerHighest;
    final subtleSurface = c.surfaceContainerLow;

    final primaryText = c.onSurface;
    final secondaryText = c.onSurfaceVariant;

    final cardBorder = c.outlineVariant;
    final activeBorder = c.primary.withValues(alpha: 0.65);

    final brandShadow = c.shadow.withValues(alpha: isDark ? 0.28 : 0.12);

    return base.copyWith(
      shadowColor: brandShadow,
      canvasColor: c.surface,
      dividerColor: c.outlineVariant,

      splashColor: c.primary.withValues(alpha: _pressedOpacity),
      highlightColor: c.primary.withValues(alpha: _focusOpacity),
      hoverColor: c.primary.withValues(alpha: _hoverOpacity),
      focusColor: c.primary.withValues(alpha: _focusOpacity),

      // --------------------------------------------------
      // APP BAR
      // --------------------------------------------------
      appBarTheme: AppBarThemeData(
        backgroundColor: c.surface,
        foregroundColor: primaryText,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: _appBarHeight,
        titleSpacing: SportikaSpacing.lg,
        centerTitle: false,
        titleTextStyle: _type(SportikaType.appBarTitle, primaryText),
        iconTheme: IconThemeData(color: primaryText, size: SportikaIconSize.lg),
        actionsIconTheme: IconThemeData(
          color: primaryText,
          size: SportikaIconSize.lg,
        ),
      ),

      // --------------------------------------------------
      // CARDS
      // --------------------------------------------------
      cardTheme: CardThemeData(
        color: subtleSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: brandShadow,
        elevation: isDark ? 1 : 2,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: _rect(SportikaRadius.card, side: cardBorder),
      ),

      // --------------------------------------------------
      // PRIMARY BUTTON
      // --------------------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              backgroundColor: c.primary,
              foregroundColor: c.onPrimary,
              disabledBackgroundColor: c.primary.withValues(alpha: 0.25),
              disabledForegroundColor: c.onPrimary.withValues(alpha: 0.55),
              minimumSize: const Size(_touchTarget, _buttonHeight),
              padding: const EdgeInsets.symmetric(
                horizontal: _buttonHorizontalPadding,
              ),
              elevation: 1,
              textStyle: SportikaType.action.copyWith(
                fontWeight: SportikaFontWeight.extraBold,
                letterSpacing: 0.35,
                fontSize: 13,
              ),
              shape: _rect(SportikaRadius.button),
            ).copyWith(
              overlayColor: _overlay(c.onPrimary),
              animationDuration: _animationDuration,
              elevation: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return 0;
                }
                if (states.contains(WidgetState.pressed)) {
                  return 0;
                }
                if (states.contains(WidgetState.hovered)) {
                  return 3;
                }
                return 1;
              }),
            ),
      ),

      // --------------------------------------------------
      // SECONDARY BUTTON
      // --------------------------------------------------
      elevatedButtonTheme: ElevatedButtonThemeData(
        style:
            ElevatedButton.styleFrom(
              backgroundColor: elevatedSurface,
              foregroundColor: primaryText,
              disabledBackgroundColor: elevatedSurface.withValues(
                alpha: _disabledOpacity,
              ),
              disabledForegroundColor: secondaryText.withValues(
                alpha: _disabledOpacity,
              ),
              minimumSize: const Size(_touchTarget, _buttonHeight),
              padding: const EdgeInsets.symmetric(
                horizontal: _buttonHorizontalPadding,
              ),
              elevation: 1,
              textStyle: SportikaType.action,
              shape: _rect(SportikaRadius.button, side: c.outline),
            ).copyWith(
              overlayColor: _overlay(c.primary),
              animationDuration: _animationDuration,
            ),
      ),

      // --------------------------------------------------
      // OUTLINED BUTTON
      // --------------------------------------------------
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              foregroundColor: c.primary,
              minimumSize: const Size(_touchTarget, _buttonHeight),
              padding: const EdgeInsets.symmetric(
                horizontal: _buttonHorizontalPadding,
              ),
              textStyle: SportikaType.action,
              side: BorderSide(color: activeBorder, width: SportikaBorder.rule),
              shape: _rect(SportikaRadius.button),
            ).copyWith(
              overlayColor: _overlay(c.primary),
              animationDuration: _animationDuration,
            ),
      ),

      // --------------------------------------------------
      // TEXT BUTTON
      // --------------------------------------------------
      textButtonTheme: TextButtonThemeData(
        style:
            TextButton.styleFrom(
              foregroundColor: c.primary,
              minimumSize: const Size(_touchTarget, _compactButtonHeight),
              textStyle: SportikaType.action,
              padding: const EdgeInsets.symmetric(
                horizontal: SportikaSpacing.sm,
              ),
              shape: _rect(SportikaRadius.sm),
            ).copyWith(
              overlayColor: _overlay(c.primary),
              animationDuration: _animationDuration,
            ),
      ),

      // --------------------------------------------------
      // ICON BUTTON
      // --------------------------------------------------
      iconButtonTheme: IconButtonThemeData(
        style:
            IconButton.styleFrom(
              foregroundColor: secondaryText,
              disabledForegroundColor: secondaryText.withValues(
                alpha: _disabledOpacity,
              ),
              minimumSize: const Size(_touchTarget, _touchTarget),
              iconSize: SportikaIconSize.lg,
              shape: _rect(SportikaRadius.control),
            ).copyWith(
              overlayColor: _overlay(c.primary),
              animationDuration: _animationDuration,
            ),
      ),

      // --------------------------------------------------
      // INPUT FIELDS
      // --------------------------------------------------
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: c.surfaceContainerLowest,
        hintStyle: _type(SportikaType.body, secondaryText),
        labelStyle: _type(SportikaType.body, secondaryText),
        floatingLabelStyle: SportikaType.body.copyWith(
          color: c.primary,
          fontWeight: SportikaFontWeight.bold,
          letterSpacing: 0.2,
        ),
        helperStyle: _type(SportikaType.caption, secondaryText),
        errorStyle: _type(SportikaType.caption, c.error),
        prefixIconColor: secondaryText,
        suffixIconColor: secondaryText,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: _fieldPadding,
          vertical: _fieldPadding,
        ),
        border: _inputBorder(cardBorder),
        enabledBorder: _inputBorder(cardBorder),
        focusedBorder: _inputBorder(c.primary, width: SportikaBorder.focused),
        errorBorder: _inputBorder(c.error),
        focusedErrorBorder: _inputBorder(
          c.error,
          width: SportikaBorder.focused,
        ),
        disabledBorder: _inputBorder(
          cardBorder.withValues(alpha: _disabledOpacity),
        ),
      ),

      // --------------------------------------------------
      // CHIPS AND FILTERS
      // --------------------------------------------------
      chipTheme: ChipThemeData(
        backgroundColor: elevatedSurface,
        selectedColor: c.primary.withValues(alpha: _selectedOpacity),
        secondarySelectedColor: c.secondary.withValues(alpha: _selectedOpacity),
        disabledColor: elevatedSurface.withValues(alpha: _disabledOpacity),
        side: BorderSide(color: cardBorder),
        showCheckmark: false,
        labelStyle: TextStyle(
          fontFamily: SportikaType.bodyFamily,
          color: primaryText,
          fontSize: _chipFontSize,
          fontWeight: SportikaFontWeight.semibold,
          letterSpacing: 0.2,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: SportikaType.bodyFamily,
          color: c.primary,
          fontSize: _chipFontSize,
          fontWeight: SportikaFontWeight.bold,
          letterSpacing: 0.2,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: _rect(SportikaRadius.pill),
      ),

      // --------------------------------------------------
      // TABS
      // --------------------------------------------------
      tabBarTheme: TabBarThemeData(
        labelColor: c.primary,
        unselectedLabelColor: secondaryText,
        indicatorColor: c.primary,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: c.primary, width: 3),
        ),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: cardBorder,
        labelStyle: _type(SportikaType.tabLabel, c.primary),
        unselectedLabelStyle: SportikaType.tabLabel.copyWith(
          color: secondaryText,
          fontWeight: SportikaFontWeight.semibold,
        ),
        overlayColor: _overlay(c.primary),
      ),

      // --------------------------------------------------
      // BOTTOM NAVIGATION
      // --------------------------------------------------
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.primary.withValues(alpha: _selectedOpacity),
        indicatorShape: _rect(SportikaRadius.md),
        height: _navigationHeight,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);

          return IconThemeData(
            size: _navigationIconSize,
            color: selected ? c.primary : secondaryText,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);

          return TextStyle(
            fontFamily: SportikaType.displayFamily,
            fontSize: _navigationFontSize,
            fontWeight: selected
                ? SportikaFontWeight.extraBold
                : SportikaFontWeight.semibold,
            letterSpacing: 0.35,
            color: selected ? c.primary : secondaryText,
          );
        }),
      ),

      // --------------------------------------------------
      // NAVIGATION RAIL
      // --------------------------------------------------
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surfaceContainerLowest,
        indicatorColor: c.primary.withValues(alpha: _selectedOpacity),
        selectedIconTheme: IconThemeData(
          color: c.primary,
          size: _navigationIconSize,
        ),
        unselectedIconTheme: IconThemeData(
          color: secondaryText,
          size: _navigationIconSize,
        ),
        selectedLabelTextStyle: SportikaType.action.copyWith(color: c.primary),
        unselectedLabelTextStyle: SportikaType.action.copyWith(
          color: secondaryText,
        ),
        useIndicator: true,
      ),

      // --------------------------------------------------
      // DIALOGS
      // --------------------------------------------------
      dialogTheme: DialogThemeData(
        backgroundColor: raisedSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shadowColor: brandShadow,
        titleTextStyle: _type(SportikaType.headline, primaryText),
        contentTextStyle: _type(SportikaType.body, secondaryText),
        shape: _rect(SportikaRadius.dialog, side: cardBorder),
      ),

      // --------------------------------------------------
      // BOTTOM SHEETS
      // --------------------------------------------------
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: elevatedSurface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: c.scrim.withValues(alpha: 0.65),
        elevation: 4,
        modalElevation: 6,
        showDragHandle: true,
        dragHandleColor: c.outline,
        dragHandleSize: const Size(42, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SportikaRadius.sheet),
          ),
        ),
      ),

      // --------------------------------------------------
      // SNACKBARS
      // --------------------------------------------------
      snackBarTheme: SnackBarThemeData(
        backgroundColor: raisedSurface,
        contentTextStyle: _type(SportikaType.body, primaryText),
        actionTextColor: c.secondary,
        behavior: SnackBarBehavior.floating,
        elevation: 3,
        insetPadding: const EdgeInsets.all(SportikaSpacing.gutter),
        shape: _rect(SportikaRadius.md, side: cardBorder),
      ),

      // --------------------------------------------------
      // DIVIDERS
      // --------------------------------------------------
      dividerTheme: DividerThemeData(
        color: cardBorder,
        thickness: SportikaBorder.hairline,
        space: SportikaBorder.hairline,
      ),

      // --------------------------------------------------
      // LIST TILES
      // --------------------------------------------------
      listTileTheme: ListTileThemeData(
        iconColor: secondaryText,
        textColor: primaryText,
        selectedColor: c.primary,
        selectedTileColor: c.primary.withValues(alpha: _selectedOpacity),
        titleTextStyle: _type(SportikaType.bodyStrong, primaryText),
        subtitleTextStyle: _type(SportikaType.caption, secondaryText),
        minVerticalPadding: SportikaSpacing.sm,
        shape: _rect(SportikaRadius.md),
      ),

      // --------------------------------------------------
      // PROGRESS INDICATORS
      // --------------------------------------------------
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: cardBorder,
        circularTrackColor: cardBorder,
        linearMinHeight: 5,
      ),

      // --------------------------------------------------
      // SEGMENTED BUTTONS
      // --------------------------------------------------
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return subtleSurface.withValues(alpha: _disabledOpacity);
            }

            if (states.contains(WidgetState.selected)) {
              return c.primary.withValues(alpha: _selectedOpacity);
            }

            return c.surfaceContainerLowest;
          }),
          foregroundColor: _stateColor(
            normal: secondaryText,
            selected: c.primary,
          ),
          overlayColor: _overlay(c.primary),
          side: WidgetStateProperty.resolveWith((states) {
            return BorderSide(
              color: states.contains(WidgetState.selected)
                  ? activeBorder
                  : cardBorder,
            );
          }),
          shape: WidgetStatePropertyAll(_rect(SportikaRadius.md)),
          textStyle: const WidgetStatePropertyAll(SportikaType.action),
          animationDuration: _animationDuration,
        ),
      ),

      // --------------------------------------------------
      // CHECKBOX
      // --------------------------------------------------
      checkboxTheme: CheckboxThemeData(
        fillColor: _stateColor(normal: Colors.transparent, selected: c.primary),
        checkColor: WidgetStatePropertyAll(c.onPrimary),
        side: BorderSide(color: c.outline),
        shape: _rect(SportikaRadius.xs),
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),

      // --------------------------------------------------
      // RADIO
      // --------------------------------------------------
      radioTheme: RadioThemeData(
        fillColor: _stateColor(normal: secondaryText, selected: c.primary),
        side: BorderSide(color: c.outline),
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),

      // --------------------------------------------------
      // SWITCH
      // --------------------------------------------------
      switchTheme: SwitchThemeData(
        thumbColor: _stateColor(normal: secondaryText, selected: c.onPrimary),
        trackColor: _stateColor(normal: raisedSurface, selected: c.primary),
        trackOutlineColor: WidgetStatePropertyAll(c.outline),
      ),

      // --------------------------------------------------
      // TOOLTIPS
      // --------------------------------------------------
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: raisedSurface,
          borderRadius: BorderRadius.circular(SportikaRadius.sm),
          border: Border.all(color: c.outline),
        ),
        textStyle: _type(SportikaType.caption, primaryText),
        waitDuration: const Duration(milliseconds: 400),
      ),

      // --------------------------------------------------
      // POPUP MENUS
      // --------------------------------------------------
      popupMenuTheme: PopupMenuThemeData(
        color: elevatedSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shadowColor: brandShadow,
        textStyle: _type(SportikaType.bodyStrong, primaryText),
        shape: _rect(SportikaRadius.md, side: cardBorder),
      ),

      // --------------------------------------------------
      // FLOATING ACTION BUTTON
      // --------------------------------------------------
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        splashColor: c.onPrimary.withValues(alpha: _pressedOpacity),
        elevation: 3,
        focusElevation: 4,
        hoverElevation: 5,
        highlightElevation: 1,
        shape: _rect(SportikaRadius.lg),
      ),

      // --------------------------------------------------
      // BADGES
      // --------------------------------------------------
      badgeTheme: BadgeThemeData(
        backgroundColor: c.error,
        textColor: c.onError,
        textStyle: SportikaType.micro.copyWith(
          color: c.onError,
          fontWeight: SportikaFontWeight.extraBold,
          fontSize: 10,
        ),
      ),

      // --------------------------------------------------
      // SLIDERS
      // --------------------------------------------------
      sliderTheme: SliderThemeData(
        activeTrackColor: c.primary,
        inactiveTrackColor: cardBorder,
        thumbColor: c.primary,
        overlayColor: c.primary.withValues(alpha: _focusOpacity),
      ),

      // --------------------------------------------------
      // TEXT SELECTION
      // --------------------------------------------------
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.primary,
        selectionColor: c.primary.withValues(alpha: 0.25),
        selectionHandleColor: c.primary,
      ),

      // --------------------------------------------------
      // SCROLLBAR
      // --------------------------------------------------
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(3),
        radius: const Radius.circular(SportikaRadius.pill),
        thumbColor: WidgetStatePropertyAll(c.outline.withValues(alpha: 0.7)),
      ),

      // --------------------------------------------------
      // SEARCH BAR
      // --------------------------------------------------
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(subtleSurface),
        hintStyle: WidgetStatePropertyAll(
          _type(SportikaType.body, secondaryText),
        ),
        textStyle: WidgetStatePropertyAll(
          _type(SportikaType.body, primaryText),
        ),
        elevation: const WidgetStatePropertyAll(0),
        side: WidgetStatePropertyAll(BorderSide(color: cardBorder)),
        shape: WidgetStatePropertyAll(_rect(SportikaRadius.field)),
        overlayColor: _overlay(c.primary),
      ),

      // --------------------------------------------------
      // SEARCH VIEW
      // --------------------------------------------------
      searchViewTheme: SearchViewThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        dividerColor: cardBorder,
        headerTextStyle: _type(SportikaType.body, primaryText),
        headerHintStyle: _type(SportikaType.body, secondaryText),
        shape: _rect(SportikaRadius.dialog),
      ),

      // --------------------------------------------------
      // DROPDOWN MENUS
      // --------------------------------------------------
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: _type(SportikaType.body, primaryText),
        inputDecorationTheme: InputDecorationThemeData(
          filled: true,
          fillColor: subtleSurface,
          border: _inputBorder(cardBorder),
          enabledBorder: _inputBorder(cardBorder),
          focusedBorder: _inputBorder(c.primary, width: SportikaBorder.focused),
        ),
      ),

      // --------------------------------------------------
      // EXPANSION TILES
      // --------------------------------------------------
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: subtleSurface,
        collapsedBackgroundColor: c.surface,
        textColor: primaryText,
        collapsedTextColor: primaryText,
        iconColor: c.primary,
        collapsedIconColor: secondaryText,
        shape: _rect(SportikaRadius.md, side: cardBorder),
        collapsedShape: _rect(SportikaRadius.md, side: cardBorder),
        tilePadding: const EdgeInsets.symmetric(horizontal: SportikaSpacing.lg),
      ),

      // --------------------------------------------------
      // DATA TABLES
      // --------------------------------------------------
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(elevatedSurface),
        dataRowColor: WidgetStatePropertyAll(subtleSurface),
        headingTextStyle: _type(SportikaType.bodyStrong, primaryText),
        dataTextStyle: _type(SportikaType.body, secondaryText),
        dividerThickness: SportikaBorder.hairline,
        headingRowHeight: 48,
        dataRowMinHeight: 48,
        dataRowMaxHeight: 60,
        horizontalMargin: SportikaSpacing.lg,
        columnSpacing: SportikaSpacing.lg,
      ),

      // --------------------------------------------------
      // DATE PICKER
      // --------------------------------------------------
      datePickerTheme: DatePickerThemeData(
        backgroundColor: elevatedSurface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: c.primary,
        headerForegroundColor: c.onPrimary,
        dayForegroundColor: WidgetStatePropertyAll(primaryText),
        dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? c.primary
              : Colors.transparent;
        }),
        todayForegroundColor: WidgetStatePropertyAll(c.primary),
        shape: _rect(SportikaRadius.dialog),
      ),

      // --------------------------------------------------
      // TIME PICKER
      // --------------------------------------------------
      timePickerTheme: TimePickerThemeData(
        backgroundColor: elevatedSurface,
        dialBackgroundColor: subtleSurface,
        dialHandColor: c.primary,
        dialTextColor: primaryText,
        hourMinuteColor: raisedSurface,
        hourMinuteTextColor: primaryText,
        entryModeIconColor: c.primary,
        shape: _rect(SportikaRadius.dialog),
      ),

      // --------------------------------------------------
      // TYPOGRAPHY
      // --------------------------------------------------
      textTheme: t,
    );
  }
}
