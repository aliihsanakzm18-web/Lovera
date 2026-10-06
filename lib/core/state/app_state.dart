import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Kullanıcının kendi girdiği adı.
final userNameProvider = StateProvider<String>((ref) => '');

/// Kullanıcının profil fotoğrafı (yerel dosya yolu veya url).
final userAvatarProvider = StateProvider<String?>((ref) => null);

/// Bağlı bulunulan çift ID'si
final coupleIdProvider = StateProvider<String?>((ref) => null);

/// Partner UID
final partnerUidProvider = StateProvider<String?>((ref) => null);

/// Eşleşen partner (eşleşme yoksa null).
final partnerProvider = StateProvider<AppUser?>((ref) => null);

/// İlişki başlangıç tarihi (kullanıcı seçer).
final startDateProvider = StateProvider<DateTime?>((ref) => null);

/// Kullanıcının eklediği özel günler.
final milestonesProvider = StateProvider<List<Milestone>>((ref) => []);

/// Giriş yapmış kullanıcının anlık bilgileri (konum, pil, şehir vb.)
final currentUserProvider = StateProvider<AppUser?>((ref) => null);

/// Tema modu yöneticisi (Açık, Koyu veya Sistem)
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier({ThemeMode initialMode = ThemeMode.system}) : super(initialMode) {
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = prefs.getString('theme_mode');
      if (modeStr == 'light') {
        state = ThemeMode.light;
      } else if (modeStr == 'dark') {
        state = ThemeMode.dark;
      } else if (modeStr == 'system') {
        state = ThemeMode.system;
      }
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = mode == ThemeMode.light
          ? 'light'
          : (mode == ThemeMode.dark ? 'dark' : 'system');
      await prefs.setString('theme_mode', modeStr);
    } catch (_) {}
  }
}
