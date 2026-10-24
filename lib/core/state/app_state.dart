import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/widget_sync_service.dart';
import '../theme/theme_palette.dart';
export '../theme/theme_palette.dart';

/// Global ScaffoldMessengerKey for toasts and SnackBars across all bottom sheets and dialogs
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

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

  Future<void> setThemeMode(ThemeMode mode, {bool syncToCloud = true}) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = mode == ThemeMode.light
          ? 'light'
          : (mode == ThemeMode.dark ? 'dark' : 'system');
      await prefs.setString('theme_mode', modeStr);

      if (syncToCloud) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          FirebaseFirestore.instance.collection('users').doc(uid).set({
            'themeMode': modeStr,
          }, SetOptions(merge: true)).catchError((_) {});
        }
      }

      // Eğer widget teması özel olarak 'dark' veya 'light' kilitlenmemişse ('app' ise)
      // uygulamanın temasıyla birlikte anında widget temasını da senkronize et!
      final customWidgetTheme = prefs.getString('widget_theme') ?? 'app';
      if (customWidgetTheme != 'dark' && customWidgetTheme != 'light') {
        String targetWidgetTheme;
        if (mode == ThemeMode.light) {
          targetWidgetTheme = 'light';
        } else if (mode == ThemeMode.dark) {
          targetWidgetTheme = 'dark';
        } else {
          // Sistem varsayılanı ise telefonun o anki parlaklığını al
          final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
          targetWidgetTheme = brightness == Brightness.dark ? 'dark' : 'light';
        }
        await WidgetSyncService.setWidgetTheme(targetWidgetTheme, savedPreferenceMode: 'app');
      }
    } catch (_) {}
  }
}

/// Kullanıcının satranç oyun ekranında olup olmadığını belirten provider
final isChessScreenOpenProvider = StateProvider<bool>((ref) => false);

/// Aktif Çift Renkli Tema Paketi Yöneticisi
final themePaletteProvider = StateNotifierProvider<ThemePaletteNotifier, ThemePaletteData>((ref) {
  return ThemePaletteNotifier();
});

class ThemePaletteNotifier extends StateNotifier<ThemePaletteData> {
  ThemePaletteNotifier({ThemePaletteData? initialPalette})
      : super(initialPalette ?? ThemePaletteData.classic) {
    ActivePalette.current = state;
    if (initialPalette == null) {
      _loadThemePalette();
    }
  }

  Future<void> _loadThemePalette() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getString('theme_palette');
      _apply(ThemePaletteData.fromKey(key));
    } catch (_) {}
  }

  /// Paleti global olarak uygular ve açık tüm ekranları (menüler, sheet'ler dahil)
  /// durumlarını kaybetmeden yeniden çizer.
  void _apply(ThemePaletteData data) {
    ActivePalette.current = data;
    state = data;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      void rebuild(Element el) {
        el.markNeedsBuild();
        el.visitChildren(rebuild);
      }

      final root = WidgetsBinding.instance.rootElement;
      if (root != null) rebuild(root);
    });
  }

  Future<void> setPalette(ThemePalette palette, {bool syncToCloud = true}) async {
    final data = ThemePaletteData.fromId(palette);
    _apply(data);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('theme_palette', palette.name);
      await WidgetSyncService.syncWidgetPalette(data);
      if (syncToCloud) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          FirebaseFirestore.instance.collection('users').doc(uid).set({
            'themePalette': palette.name,
          }, SetOptions(merge: true)).catchError((_) {});
        }
      }
    } catch (_) {}
  }
}