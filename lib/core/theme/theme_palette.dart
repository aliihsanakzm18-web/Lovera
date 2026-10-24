import 'package:flutter/material.dart';

/// Lovera Tema Paketleri
enum ThemePalette {
  classic,
  berryCream,
  blushPeach,
  cosmicCyan,
  matchaRose,
  amberHoney,
  midnightOcean,
}

/// Aktif tema paketini global olarak tutar. `LoveraColors` buradan okur;
/// böylece kodun her yerindeki renk kullanımı seçili pakete uyar.
class ActivePalette {
  ActivePalette._();
  static ThemePaletteData current = ThemePaletteData.classic;
}

Color _hsl(double h, double s, double l, [double a = 1]) =>
    HSLColor.fromAHSL(a, h % 360, s.clamp(0.0, 1.0), l.clamp(0.0, 1.0)).toColor();

/// Bir tema paketinin TÜM renk token'ları (açık + koyu mod).
class ThemePaletteData {
  final ThemePalette id;
  final String nameTr;
  final String nameEn;
  final String descriptionTr;
  final String descriptionEn;

  // Vurgu renkleri
  final Color primary;
  final Color primaryDark; // koyu modda okunaklı açık ton
  final Color primaryDeep;
  final Color primarySoft;
  final Color secondary;
  final Color accentGold;
  final Color accentViolet;
  final Color accentPink;

  // Açık mod
  final Color lightBg;
  final Color lightSurface;
  final Color lightSurfaceAlt;
  final Color lightBorder;
  final Color textDark;
  final Color textMuted;

  // Koyu mod
  final Color darkBg;
  final Color darkSurface;
  final Color darkSurfaceAlt;
  final Color darkBorder;
  final Color darkText;
  final Color darkTextMuted;

  const ThemePaletteData({
    required this.id,
    required this.nameTr,
    required this.nameEn,
    required this.descriptionTr,
    required this.descriptionEn,
    required this.primary,
    required this.primaryDark,
    required this.primaryDeep,
    required this.primarySoft,
    required this.secondary,
    required this.accentGold,
    required this.accentViolet,
    required this.accentPink,
    required this.lightBg,
    required this.lightSurface,
    required this.lightSurfaceAlt,
    required this.lightBorder,
    required this.textDark,
    required this.textMuted,
    required this.darkBg,
    required this.darkSurface,
    required this.darkSurfaceAlt,
    required this.darkBorder,
    required this.darkText,
    required this.darkTextMuted,
  });

  /// İki canlı renkten (ana + eşlikçi) tüm token setini türetir.
  factory ThemePaletteData.derive({
    required ThemePalette id,
    required String nameTr,
    required String nameEn,
    required String descriptionTr,
    required String descriptionEn,
    required Color primary,
    required Color secondary,
  }) {
    final p = HSLColor.fromColor(primary);
    final s = HSLColor.fromColor(secondary);
    final h = p.hue;
    return ThemePaletteData(
      id: id,
      nameTr: nameTr,
      nameEn: nameEn,
      descriptionTr: descriptionTr,
      descriptionEn: descriptionEn,
      primary: primary,
      primaryDark: _hsl(h, p.saturation, (p.lightness + 0.14).clamp(0.55, 0.78)),
      primaryDeep: _hsl(h, p.saturation, (p.lightness - 0.08).clamp(0.2, 0.5)),
      primarySoft: _hsl(h, 0.85, 0.84),
      secondary: secondary,
      accentGold: _hsl(s.hue, s.saturation, (s.lightness + 0.05).clamp(0.45, 0.7)),
      accentViolet: _hsl(h, p.saturation, (p.lightness + 0.12).clamp(0.55, 0.78)),
      accentPink: _hsl(s.hue, s.saturation, (s.lightness + 0.12).clamp(0.55, 0.8)),
      // Açık mod: temanın tonuyla hafif renklenmiş zeminler
      lightBg: _hsl(h, 0.40, 0.972),
      lightSurface: Colors.white,
      lightSurfaceAlt: _hsl(h, 0.32, 0.945),
      lightBorder: _hsl(h, 0.26, 0.895),
      textDark: _hsl(h, 0.30, 0.12),
      textMuted: _hsl(h, 0.10, 0.44),
      // Koyu mod: temanın tonuyla derin zeminler
      darkBg: _hsl(h, 0.32, 0.055),
      darkSurface: _hsl(h, 0.28, 0.095),
      darkSurfaceAlt: _hsl(h, 0.26, 0.135),
      darkBorder: _hsl(h, 0.24, 0.185),
      darkText: _hsl(h, 0.20, 0.95),
      darkTextMuted: _hsl(h, 0.14, 0.68),
    );
  }

  LinearGradient get gradient => LinearGradient(
        colors: [primary, secondary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  String name(bool isEn) => isEn ? nameEn : nameTr;
  String description(bool isEn) => isEn ? descriptionEn : descriptionTr;

  // Klasik: mevcut ana tema, değerler birebir korunur
  static const ThemePaletteData classic = ThemePaletteData(
    id: ThemePalette.classic,
    nameTr: 'Lovera Klasik',
    nameEn: 'Lovera Classic',
    descriptionTr: 'Asil leylak ve zarif mor tonları',
    descriptionEn: 'Noble lilac and elegant purple tones',
    primary: Color(0xFF8B5CF6),
    primaryDark: Color(0xFFA78BFA),
    primaryDeep: Color(0xFF7C3AED),
    primarySoft: Color(0xFFC4B5FD),
    secondary: Color(0xFF34D399),
    accentGold: Color(0xFFFBBF24),
    accentViolet: Color(0xFFA78BFA),
    accentPink: Color(0xFFF472B6),
    lightBg: Color(0xFFF8F9FA),
    lightSurface: Color(0xFFFFFFFF),
    lightSurfaceAlt: Color(0xFFF1F3F5),
    lightBorder: Color(0xFFE9ECEF),
    textDark: Color(0xFF1E2024),
    textMuted: Color(0xFF6C757D),
    darkBg: Color(0xFF0C0D12),
    darkSurface: Color(0xFF161820),
    darkSurfaceAlt: Color(0xFF20232E),
    darkBorder: Color(0xFF272A36),
    darkText: Color(0xFFF3F4F6),
    darkTextMuted: Color(0xFF94A3B8),
  );

  static final ThemePaletteData berryCream = ThemePaletteData.derive(
    id: ThemePalette.berryCream,
    nameTr: 'Berry & Cream',
    nameEn: 'Berry & Cream',
    descriptionTr: 'Tatlı pembe ve lavanta moru uyumu',
    descriptionEn: 'Sweet raspberry pink & lavender violet',
    primary: const Color(0xFFEC4899),
    secondary: const Color(0xFF8B5CF6),
  );

  static final ThemePaletteData blushPeach = ThemePaletteData.derive(
    id: ThemePalette.blushPeach,
    nameTr: 'Blush & Peach',
    nameEn: 'Blush & Peach',
    descriptionTr: 'Pudra pembe ve sıcak günbatımı şeftalisi',
    descriptionEn: 'Powder pink & warm sunset peach',
    primary: const Color(0xFFF0689F),
    secondary: const Color(0xFFFB923C),
  );

  static final ThemePaletteData cosmicCyan = ThemePaletteData.derive(
    id: ThemePalette.cosmicCyan,
    nameTr: 'Cosmic Violet',
    nameEn: 'Cosmic Violet',
    descriptionTr: 'Neon kozmik mor ve buz mavisi ışıltısı',
    descriptionEn: 'Neon cosmic violet & glacier cyan glow',
    primary: const Color(0xFF7C3AED),
    secondary: const Color(0xFF06B6D4),
  );

  static final ThemePaletteData matchaRose = ThemePaletteData.derive(
    id: ThemePalette.matchaRose,
    nameTr: 'Matcha & Rose',
    nameEn: 'Matcha & Rose',
    descriptionTr: 'Huzurlu nane zümrütü ve gül kurusu',
    descriptionEn: 'Serene emerald matcha & dusty rose',
    primary: const Color(0xFF10B981),
    secondary: const Color(0xFFF43F5E),
  );

  static final ThemePaletteData amberHoney = ThemePaletteData.derive(
    id: ThemePalette.amberHoney,
    nameTr: 'Amber & Honey',
    nameEn: 'Amber & Honey',
    descriptionTr: 'Sıcak bal sarısı ve karamel esintisi',
    descriptionEn: 'Warm honey amber & caramel cozy tones',
    primary: const Color(0xFFF59E0B),
    secondary: const Color(0xFFD97706),
  );

  static final ThemePaletteData midnightOcean = ThemePaletteData.derive(
    id: ThemePalette.midnightOcean,
    nameTr: 'Midnight Ocean',
    nameEn: 'Midnight Ocean',
    descriptionTr: 'Derin okyanus mavisi ve berrak gökyüzü',
    descriptionEn: 'Deep midnight ocean & azure sky blue',
    primary: const Color(0xFF0284C7),
    secondary: const Color(0xFF38BDF8),
  );

  static final List<ThemePaletteData> all = [
    classic,
    berryCream,
    blushPeach,
    cosmicCyan,
    matchaRose,
    amberHoney,
    midnightOcean,
  ];

  static ThemePaletteData fromId(ThemePalette id) {
    return all.firstWhere((p) => p.id == id, orElse: () => classic);
  }

  static ThemePaletteData fromKey(String? key) {
    if (key == null) return classic;
    return all.firstWhere((p) => p.id.name == key, orElse: () => classic);
  }
}
