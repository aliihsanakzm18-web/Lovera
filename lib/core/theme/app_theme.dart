import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Lovera Renk Paleti - Spotify, Instagram ve iOS Standartlarında Kusursuz Koyu & Açık Mod
class LoveraColors {
  LoveraColors._();

  // Ana Vurgular (Asil, zarif, göz yormayan romantik leylak & gül kurusu tonu - çiğ kırmızı tamamen kaldırıldı)
  static const primary = Color(0xFF8B5CF6); // Zarif & asil yumuşak leylak/mor (Lüks aşk hissi)
  static const primaryDark = Color(0xFFA78BFA); // Dark modda göz dinlendiren açık pastel leylak
  static const primaryDeep = Color(0xFF7C3AED);
  static const primarySoft = Color(0xFFC4B5FD);

  // İkincil & Aksiyon Renkleri
  static const secondary = Color(0xFF34D399); // Dinlendirici nane zümrütü
  static const accentGold = Color(0xFFFBBF24); // Sıcak pastel altın sarısı
  static const accentViolet = Color(0xFFA78BFA); // Zarif lavanta moru
  static const accentPink = Color(0xFFF472B6); // Pastel pembe

  // Light Tema
  static const lightBg = Color(0xFFF8F9FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceAlt = Color(0xFFF1F3F5);
  static const lightBorder = Color(0xFFE9ECEF);
  static const textDark = Color(0xFF1E2024);
  static const textMuted = Color(0xFF6C757D);

  // Dark Tema - Instagram / Spotify / iOS Gerçek Karanlık Mod Standartları
  // Katman 1: Derin AMOLED Gece Arka Planı
  static const darkBg = Color(0xFF0C0D12); 
  // Katman 2: Kartlar ve Yüzeyler (Arka plandan net ayrışan, lüks mat grafit tonu)
  static const darkSurface = Color(0xFF161820); 
  // Katman 3: Kart içi butonlar ve bölmeler
  static const darkSurfaceAlt = Color(0xFF20232E); 
  // Kenarlıklar: Çok ince, zarif sınır
  static const darkBorder = Color(0xFF272A36); 
  // Metinler: Gözü kamaştırmayan pürüzsüz beyaz ve açık gri
  static const darkText = Color(0xFFF3F4F6); 
  static const darkTextMuted = Color(0xFF94A3B8); 

  // Gradientler
  static const primaryGradient = LinearGradient(
    colors: [Color(0xFF8B5CF6), Color(0xFFA855F7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const darkPrimaryGradient = LinearGradient(
    colors: [Color(0xFF7C3AED), Color(0xFF9333EA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const goldGradient = LinearGradient(
    colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  AppTheme._();

  static const double radius = 24;

  static List<BoxShadow> ambientShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 20,
      offset: const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> primaryGlow = [
    BoxShadow(
      color: LoveraColors.primary.withValues(alpha: 0.22),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];

  static ThemeData get light => _build(
        brightness: Brightness.light,
        bg: LoveraColors.lightBg,
        surface: LoveraColors.lightSurface,
        text: LoveraColors.textDark,
        muted: LoveraColors.textMuted,
        border: LoveraColors.lightBorder,
        primaryColor: LoveraColors.primary,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        bg: LoveraColors.darkBg,
        surface: LoveraColors.darkSurface,
        text: LoveraColors.darkText,
        muted: LoveraColors.darkTextMuted,
        border: LoveraColors.darkBorder,
        primaryColor: LoveraColors.primaryDark,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
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
      listTileTheme: ListTileThemeData(
        textColor: text,
        iconColor: text,
      ),
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
          side: BorderSide(color: border, width: 1.2),
        ),
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
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? LoveraColors.darkSurfaceAlt : surface,
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
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
      ),
    );
  }
}
