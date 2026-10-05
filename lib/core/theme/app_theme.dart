import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Lovera renk token'ları.
class LoveraColors {
  LoveraColors._();
  // Light
  static const lightBg = Color(0xFFFAF8F5);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceAlt = Color(0xFFF4EFEB);
  static const primary = Color(0xFFC97A7E);
  static const primarySoft = Color(0xFFD98880);
  static const secondary = Color(0xFF9DB5A6);
  static const textDark = Color(0xFF232326);
  static const textMuted = Color(0xFF76767A);
  // Dark
  static const darkBg = Color(0xFF121214);
  static const darkSurface = Color(0xFF1E1E22);
  static const darkText = Color(0xFFEAEAEA);
}

class AppTheme {
  AppTheme._();

  static const double radius = 22;

  static List<BoxShadow> ambientShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.03),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  static ThemeData get light => _build(
        brightness: Brightness.light,
        bg: LoveraColors.lightBg,
        surface: LoveraColors.lightSurface,
        text: LoveraColors.textDark,
        muted: LoveraColors.textMuted,
        border: Colors.black.withValues(alpha: 0.04),
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        bg: LoveraColors.darkBg,
        surface: LoveraColors.darkSurface,
        text: LoveraColors.darkText,
        muted: const Color(0xFF9A9AA0),
        border: Colors.white.withValues(alpha: 0.06),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color text,
    required Color muted,
    required Color border,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: LoveraColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: LoveraColors.primary,
      secondary: LoveraColors.secondary,
      surface: surface,
      onSurface: text,
    );
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .apply(bodyColor: text, displayColor: text);

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      textTheme: textTheme,
      dividerColor: border,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: text,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: LoveraColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: border),
        ),
      ),
    );
  }
}
