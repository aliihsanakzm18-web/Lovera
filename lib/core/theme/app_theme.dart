import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme_palette.dart';

/// Lovera Renk Paleti. Tüm değerler SEÇİLİ TEMA PAKETİNDEN okunur
/// (varsayılan paket "Lovera Klasik" ile birebir aynı değerleri verir).
class LoveraColors {
  LoveraColors._();

  static ThemePaletteData get _p => ActivePalette.current;

  // Ana vurgular
  static Color get primary => _p.primary;
  static Color get primaryDark => _p.primaryDark;
  static Color get primaryDeep => _p.primaryDeep;
  static Color get primarySoft => _p.primarySoft;

  // İkincil & aksiyon renkleri
  static Color get secondary => _p.secondary;
  static Color get accentGold => _p.accentGold;
  static Color get accentViolet => _p.accentViolet;
  static Color get accentPink => _p.accentPink;

  // Açık tema
  static Color get lightBg => _p.lightBg;
  static Color get lightSurface => _p.lightSurface;
  static Color get lightSurfaceAlt => _p.lightSurfaceAlt;
  static Color get lightBorder => _p.lightBorder;
  static Color get textDark => _p.textDark;
  static Color get textMuted => _p.textMuted;

  // Koyu tema
  static Color get darkBg => _p.darkBg;
  static Color get darkSurface => _p.darkSurface;
  static Color get darkSurfaceAlt => _p.darkSurfaceAlt;
  static Color get darkBorder => _p.darkBorder;
  static Color get darkText => _p.darkText;
  static Color get darkTextMuted => _p.darkTextMuted;

  // Gradientler
  static Color get gradientEnd => _p.id == ThemePalette.classic ? const Color(0xFFA855F7) : _p.secondary;
  static Color get gradientEndDeep => _p.id == ThemePalette.classic ? const Color(0xFF9333EA) : _p.secondary;
  static LinearGradient get primaryGradient => LinearGradient(
        colors: [_p.primary, _p.id == ThemePalette.classic ? const Color(0xFFA855F7) : _p.secondary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient get darkPrimaryGradient => LinearGradient(
        colors: [_p.primaryDeep, _p.id == ThemePalette.classic ? const Color(0xFF9333EA) : _p.secondary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient get goldGradient => LinearGradient(
        colors: [_p.accentGold, _p.accentGold.withValues(alpha: 0.85)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

class AppTheme {
  AppTheme._();

  static const double radius = 24;

  static List<BoxShadow> get ambientShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get primaryGlow => [
        BoxShadow(
          color: LoveraColors.primary.withValues(alpha: 0.22),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];

  static ThemeData get light => buildLight(ThemePaletteData.classic);
  static ThemeData get dark => buildDark(ThemePaletteData.classic);

  static ThemeData buildLight(ThemePaletteData p) => _build(
        brightness: Brightness.light,
        p: p,
        bg: p.lightBg,
        surface: p.lightSurface,
        surfaceAlt: p.lightSurfaceAlt,
        text: p.textDark,
        muted: p.textMuted,
        border: p.lightBorder,
        primaryColor: p.primary,
      );

  static ThemeData buildDark(ThemePaletteData p) => _build(
        brightness: Brightness.dark,
        p: p,
        bg: p.darkBg,
        surface: p.darkSurface,
        surfaceAlt: p.darkSurfaceAlt,
        text: p.darkText,
        muted: p.darkTextMuted,
        border: p.darkBorder,
        primaryColor: p.primaryDark,
      );

  static ThemeData _build({
    required Brightness brightness,
    required ThemePaletteData p,
    required Color bg,
    required Color surface,
    required Color surfaceAlt,
    required Color text,
    required Color muted,
    required Color border,
    required Color primaryColor,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: brightness,
    ).copyWith(
      primary: primaryColor,
      onPrimary: Colors.white,
      secondary: p.secondary,
      tertiary: p.accentPink,
      surface: surface,
      onSurface: text,
      surfaceContainerLowest: bg,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceAlt,
      surfaceContainerHighest: surfaceAlt,
      onSurfaceVariant: muted,
      outline: border,
      outlineVariant: border,
      primaryContainer: primaryColor.withValues(alpha: isDark ? 0.22 : 0.14),
      onPrimaryContainer: isDark ? p.primarySoft : p.primaryDeep,
      secondaryContainer: p.secondary.withValues(alpha: isDark ? 0.22 : 0.14),
      onSecondaryContainer: isDark ? p.secondary : text,
    );
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .apply(bodyColor: text, displayColor: text);

    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: border, width: 1.2),
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: surface,
      textTheme: textTheme,
      primaryColor: primaryColor,
      dividerColor: border,
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      iconTheme: IconThemeData(color: text),
      primaryIconTheme: const IconThemeData(color: Colors.white),
      splashColor: primaryColor.withValues(alpha: 0.10),
      highlightColor: primaryColor.withValues(alpha: 0.06),
      listTileTheme: ListTileThemeData(
        textColor: text,
        iconColor: text,
        selectedColor: primaryColor,
        selectedTileColor: primaryColor.withValues(alpha: 0.10),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        foregroundColor: text,
        iconTheme: IconThemeData(color: text),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: bg,
                systemNavigationBarIconBrightness: Brightness.light,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: bg,
                systemNavigationBarIconBrightness: Brightness.dark,
              ),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: text,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: border, width: 1.2),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: text),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: muted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
        textStyle: textTheme.bodyMedium?.copyWith(color: text),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? surfaceAlt : p.textDark,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: p.primarySoft,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          textStyle: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: BorderSide(color: primaryColor.withValues(alpha: 0.6)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primaryColor),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: text,
          highlightColor: primaryColor.withValues(alpha: 0.12),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primaryColor : surfaceAlt,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primaryColor : border,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primaryColor : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: BorderSide(color: border, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primaryColor : muted,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primaryColor,
        inactiveTrackColor: primaryColor.withValues(alpha: 0.2),
        thumbColor: primaryColor,
        overlayColor: primaryColor.withValues(alpha: 0.15),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primaryColor,
        linearTrackColor: primaryColor.withValues(alpha: 0.18),
        circularTrackColor: primaryColor.withValues(alpha: 0.12),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        selectedColor: primaryColor.withValues(alpha: 0.2),
        side: BorderSide(color: border),
        labelStyle: textTheme.labelLarge?.copyWith(color: text),
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(color: primaryColor),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primaryColor,
        unselectedLabelColor: muted,
        indicatorColor: primaryColor,
        dividerColor: border,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryColor.withValues(alpha: 0.2),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: primaryColor.withValues(alpha: 0.2),
          selectedForegroundColor: primaryColor,
          foregroundColor: muted,
          side: BorderSide(color: border),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primaryColor,
        selectionColor: primaryColor.withValues(alpha: 0.28),
        selectionHandleColor: primaryColor,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: primaryColor,
        headerForegroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: surface,
        dialBackgroundColor: surfaceAlt,
        hourMinuteColor: surfaceAlt,
        dayPeriodColor: surfaceAlt,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? surfaceAlt : p.textDark,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? surfaceAlt : surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        hintStyle: TextStyle(color: muted, fontSize: 14),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
      ),
    );
  }
}
