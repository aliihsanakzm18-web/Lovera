import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Lovera Lüks & Modern Aşk Paleti (Rose Quartz, Deep Wine, Warm Cream, Frosted Glass)
class LoveraColors {
  LoveraColors._();

  // Ana Aşk Vurguları (Modern & Asil Gül Kurusu / Şarap / Kırmızı)
  static const primary = Color(0xFFFF4B6E); // Canlı, modern, premium aşk pembesi/mercanı
  static const primaryDeep = Color(0xFFE02B52); // Gradient derinliği için
  static const primarySoft = Color(0xFFFF7E98); // Yumuşak pembe parıltı
  static const primarySubtle = Color(0xFFFFF0F3); // Kart arkaplan hafif pembe tül

  // İkincil Vurgular (Zümrüt Yeşil & Altın Işıltı)
  static const secondary = Color(0xFF10B981); // Ferah ve modern zümrüt yeşil (aktiflik/pil)
  static const accentGold = Color(0xFFF59E0B); // Özel günler, yıldızlar, hatıralar için sıcak kehribar/altın
  static const accentViolet = Color(0xFF8B5CF6); // Harita ve albüm için asil lila/mor

  // Light Tema Renkleri
  static const lightBg = Color(0xFFF8F9FD); // Temiz, modern, havadar iOS arka planı
  static const lightSurface = Color(0xFFFFFFFF); // Kar beyazı kartlar
  static const lightSurfaceAlt = Color(0xFFF1F3FA); // Hafif gölgeli ayrık alanlar
  static const lightBorder = Color(0xFFE5E7EB); // İnce, şık sınır çizgisi

  static const textDark = Color(0xFF111827); // Simsiyah değil, ultra derin lüks gri-siyah
  static const textMuted = Color(0xFF6B7280); // Narin gri alt başlık
  static const textLight = Color(0xFF9CA3AF);

  // Dark Tema Renkleri (OLED Siyah & Koyu Gece Mavisi)
  static const darkBg = Color(0xFF0F1016); // Derin gece gökyüzü
  static const darkSurface = Color(0xFF181A24); // Lüks mat kart yüzeyi
  static const darkSurfaceAlt = Color(0xFF222533);
  static const darkBorder = Color(0xFF2A2E3D);
  static const darkText = Color(0xFFF9FAFB);
  static const darkTextMuted = Color(0xFF9CA3AF);

  // Gradientler
  static const primaryGradient = LinearGradient(
    colors: [Color(0xFFFF4B6E), Color(0xFFFF6584)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const goldGradient = LinearGradient(
    colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const purpleGradient = LinearGradient(
    colors: [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  AppTheme._();

  static const double radius = 24;

  static List<BoxShadow> ambientShadow = [
    BoxShadow(
      color: const Color(0xFF111827).withValues(alpha: 0.04),
      blurRadius: 24,
      spreadRadius: 0,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> primaryGlow = [
    BoxShadow(
      color: LoveraColors.primary.withValues(alpha: 0.28),
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
        border: LoveraColors.lightBorder,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        bg: LoveraColors.darkBg,
        surface: LoveraColors.darkSurface,
        text: LoveraColors.darkText,
        muted: LoveraColors.darkTextMuted,
        border: LoveraColors.darkBorder,
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
      outline: border,
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
        centerTitle: true,
        foregroundColor: text,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: text,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: border, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: LoveraColors.primary,
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
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        hintStyle: TextStyle(color: muted, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: border, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: border, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: LoveraColors.primary, width: 2),
        ),
      ),
    );
  }
}
