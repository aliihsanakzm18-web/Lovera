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

/// Kalıcı ve anlık paylaşılan kayıtlı yerler (Ev, Okul vb.)
final savedPlacesProvider = StateProvider<List<SavedPlace>>((ref) => []);

/// Aktif sayfa indeksi (0: Harita, 1: Ana Sayfa, 2: Sohbet, 3: Oyunlar)
final activeNavigationIndexProvider = StateProvider<int>((ref) => 1);

/// Haritadan veya diğer sayfalardan sohbete gönderilen hazır mesaj metni (örn: konum cevabı)
final pendingChatInputTextProvider = StateProvider<String?>((ref) => null);

/// Haritadan sohbete iliştirilen tıklanabilir konum bilgisi
class AttachedLocation {
  final double lat;
  final double lng;
  final String title;

  const AttachedLocation({
    required this.lat,
    required this.lng,
    required this.title,
  });
}

final pendingChatLocationAttachmentProvider = StateProvider<AttachedLocation?>((ref) => null);

/// Sohbetteki konuma tıklandığında haritanın odaklanacağı hedef koordinat
final targetMapFocusLocationProvider = StateProvider<AttachedLocation?>((ref) => null);

/// Onaylanmış aktif buluşma konumu (haritada buluşma rotası çizmek için)
final activeMeetingLocationProvider = StateProvider<AttachedLocation?>((ref) => null);

/// Kullanıcı şu an sohbet sayfasında mı?
final isChatActiveProvider = Provider<bool>((ref) {
  return ref.watch(activeNavigationIndexProvider) == 2;
});

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

/// Kullanıcının satranç oyun ekranında olup olmadığını belirten provider
final isChessScreenOpenProvider = StateProvider<bool>((ref) => false);

