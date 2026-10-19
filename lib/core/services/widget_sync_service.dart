import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// Hem Android hem iOS Ana Ekran Widget'larına partner verilerini ve
/// gün sayacını senkronize eden servis.
class WidgetSyncService {
  static const String appGroupId = 'group.com.lovera.app.lovera';
  static const String androidWidgetName = 'LoveraPartnerWidgetProvider';
  static const String iOSWidgetName = 'LoveraPartnerWidget';

  /// Partner verilerini, sayaç bilgisini ve mekan/hareket durumunu widget'a yazar.
  static Future<void> syncWidget({
    required AppUser? partner,
    required DateTime? startDate,
    List<SavedPlace> savedPlaces = const [],
  }) async {
    try {
      // iOS App Group ayarı
      try {
        await HomeWidget.setAppGroupId(appGroupId);
      } catch (e) {
        debugPrint('[WidgetSyncService] setAppGroupId warning: $e');
      }

      // 1. Gün Sayacı Hesaplama
      String daysCount = '0';
      if (startDate != null) {
        final now = DateTime.now();
        final diff = now.difference(startDate).inDays;
        daysCount = diff >= 0 ? diff.toString() : '0';
      }

      // 2. Partner Adı
      final partnerName = (partner?.name != null && partner!.name.trim().isNotEmpty)
          ? partner.name.trim()
          : 'Sevgilim';

      // 3. Batarya Seviyesi
      final batteryLevel = partner?.batteryLevel != null
          ? '%${partner!.batteryLevel}'
          : '%--';

      // 4. Durum (Evde, Yürüyor, Arabada, Dışarıda vb.) ve Emoji
      final statusInfo = resolveMovementOrPlaceStatus(partner, savedPlaces);
      final statusEmoji = statusInfo['emoji'] ?? '📍';
      final statusText = statusInfo['title'] ?? 'Bilinmiyor';

      // 5. Son Görülme / Canlılık
      String lastSeen = 'Çevrimdışı';
      if (partner?.lastActive != null) {
        // Hem partner.lastActive hem now'ı UTC olarak karşılaştır
        final partnerActiveUtc = partner!.lastActive!.isUtc
            ? partner.lastActive!
            : partner.lastActive!.toUtc();
        final nowUtc = DateTime.now().toUtc();
        final diff = nowUtc.difference(partnerActiveUtc);
        final diffMinutes = diff.inMinutes.abs();

        if (partner.isAppOpen == true && diffMinutes < 3) {
          lastSeen = 'Şimdi aktif';
        } else if (diffMinutes < 1) {
          lastSeen = 'Şimdi';
        } else if (diffMinutes == 1) {
          lastSeen = '1 dk önce';
        } else if (diffMinutes < 60) {
          lastSeen = '$diffMinutes dk önce';
        } else if (diff.inHours.abs() < 24) {
          lastSeen = '${diff.inHours.abs()} sa önce';
        } else {
          lastSeen = '${diff.inDays.abs()} gün önce';
        }
      } else if (partner?.isAppOpen == true) {
        lastSeen = 'Şimdi aktif';
      } else {
        lastSeen = 'Çevrimdışı';
      }

      // Verileri HomeWidget saklama alanına kaydet
      await HomeWidget.saveWidgetData<String>('days_count', daysCount);
      await HomeWidget.saveWidgetData<String>('partner_name', partnerName);
      await HomeWidget.saveWidgetData<String>('battery_level', batteryLevel);
      await HomeWidget.saveWidgetData<String>('status_text', statusText);
      await HomeWidget.saveWidgetData<String>('status_emoji', statusEmoji);
      await HomeWidget.saveWidgetData<String>('last_seen', lastSeen);
      final partnerActiveMillis = partner?.lastActive != null
          ? (partner!.lastActive!.isUtc ? partner.lastActive! : partner.lastActive!.toUtc()).millisecondsSinceEpoch
          : 0;
      await HomeWidget.saveWidgetData<int>('last_active_millis', partnerActiveMillis);
      await HomeWidget.saveWidgetData<bool>('partner_is_app_open', partner?.isAppOpen == true);

      // Her iki platformun widget'larını güncelle
      await HomeWidget.updateWidget(
        name: androidWidgetName,
        androidName: androidWidgetName,
        iOSName: iOSWidgetName,
      );

      debugPrint('[WidgetSyncService] Widget updated successfully: days=$daysCount, partner=$partnerName, battery=$batteryLevel, status=$statusEmoji $statusText');
    } catch (e, stack) {
      debugPrint('[WidgetSyncService] Widget sync error: $e\n$stack');
    }
  }

  /// Partnerin konum, kayıtlı mekan ve hız durumundan metin/emoji çıkarımı
  static Map<String, String> resolveMovementOrPlaceStatus(
    AppUser? p,
    List<SavedPlace> savedPlaces,
  ) {
    if (p == null) {
      return {'emoji': '❤️', 'title': 'Bağlantı bekleniyor'};
    }

    // 1. Kayıtlı mekan kontrolü (Evim, İş, vb. <= 85 metre GPS toleransı)
    if (p.lat != null && p.lng != null && savedPlaces.isNotEmpty) {
      for (final place in savedPlaces) {
        final dist = Geolocator.distanceBetween(p.lat!, p.lng!, place.lat, place.lng);
        if (dist <= 85) {
          return {
            'emoji': place.iconEmoji.isNotEmpty ? place.iconEmoji : '🏠',
            'title': place.title,
          };
        }
      }
    }

    // 2. Hareket tespiti (Araba vs Yürüyor vs Hareketsiz/Dışarıda)
    final speedKmH = (p.speed != null) ? p.speed! * 3.6 : 0.0;
    if (speedKmH >= 20.0) {
      return {
        'emoji': '🚗',
        'title': 'Arabada',
      };
    } else if (speedKmH >= 2.5) {
      return {
        'emoji': '🚶',
        'title': 'Yürüyor',
      };
    }

    // 3. Konum var ama kayıtlı mekan değil ve hareketsiz duruyorsa -> Dışarıda
    if (p.lat != null && p.lng != null) {
      return {
        'emoji': '📍',
        'title': 'Dışarıda',
      };
    }

    // 4. Eskiden kalan mekan bilgisi varsa
    if (p.currentPlaceTitle != null && p.currentPlaceTitle!.isNotEmpty) {
      return {
        'emoji': (p.currentPlaceEmoji != null && p.currentPlaceEmoji!.isNotEmpty)
            ? p.currentPlaceEmoji!
            : '📍',
        'title': p.currentPlaceTitle!,
      };
    }

    return {
      'emoji': '✨',
      'title': 'Haber bekliyor',
    };
  }

  /// Widget arka plan fotoğrafını kaydeder ve widget'ı günceller
  static Future<void> setWidgetBackgroundImage(String imagePath) async {
    try {
      try {
        await HomeWidget.setAppGroupId(appGroupId);
      } catch (_) {}
      await HomeWidget.saveWidgetData<String>('widget_bg_image_path', imagePath);
      await HomeWidget.updateWidget(
        name: androidWidgetName,
        androidName: androidWidgetName,
        iOSName: iOSWidgetName,
      );
      debugPrint('[WidgetSyncService] Widget background image set: $imagePath');
    } catch (e) {
      debugPrint('[WidgetSyncService] setWidgetBackgroundImage error: $e');
    }
  }

  static const String androidDrawingWidgetName = 'LoveraDrawingWidgetProvider';
  static const String iOSDrawingWidgetName = 'LoveraDrawingWidget';

  /// Widget arka plan fotoğrafını kaldırır ve varsayılan temaya döner
  static Future<void> removeWidgetBackgroundImage() async {
    try {
      try {
        await HomeWidget.setAppGroupId(appGroupId);
      } catch (_) {}
      await HomeWidget.saveWidgetData<String>('widget_bg_image_path', '');
      await HomeWidget.updateWidget(
        name: androidWidgetName,
        androidName: androidWidgetName,
        iOSName: iOSWidgetName,
      );
      debugPrint('[WidgetSyncService] Widget background image removed.');
    } catch (e) {
      debugPrint('[WidgetSyncService] removeWidgetBackgroundImage error: $e');
    }
  }

  /// Widget temasını ayarlar ('app', 'dark', 'light') ve widget'ları günceller
  /// [savedPreferenceMode]: Kullanıcının ayarlarda seçtiği tercih ('app', 'dark', 'light')
  /// [effectiveTheme]: Widget'ların native render için kullanacağı somut tema ('dark', 'light')
  static Future<void> setWidgetTheme(String effectiveTheme, {String? savedPreferenceMode}) async {
    try {
      try {
        await HomeWidget.setAppGroupId(appGroupId);
      } catch (_) {}
      
      // Native Kotlin widget'ların okuduğu 'widget_theme' değeri ('dark' veya 'light')
      await HomeWidget.saveWidgetData<String>('widget_theme', effectiveTheme);

      // Ayarlar ekranının ve Riverpod/Main'in okuduğu tercih ('app', 'dark', 'light')
      final prefs = await SharedPreferences.getInstance();
      if (savedPreferenceMode != null) {
        await prefs.setString('widget_theme', savedPreferenceMode);
      }

      await HomeWidget.updateWidget(
        name: androidWidgetName,
        androidName: androidWidgetName,
        iOSName: iOSWidgetName,
      );
      await HomeWidget.updateWidget(
        name: androidDrawingWidgetName,
        androidName: androidDrawingWidgetName,
        iOSName: iOSDrawingWidgetName,
      );
      debugPrint('[WidgetSyncService] Widget theme updated: effective=$effectiveTheme, preference=$savedPreferenceMode');
    } catch (e) {
      debugPrint('[WidgetSyncService] setWidgetTheme error: $e');
    }
  }

  /// Canlı Çizim Widget'ını partnere gelen son çizimle senkronize eder
  static Future<void> syncDrawingWidget({
    required String imagePath,
    required String senderName,
    String? imageBase64,
    String timeAgo = 'Şimdi',
    int? timestampMillis,
  }) async {
    try {
      try {
        await HomeWidget.setAppGroupId(appGroupId);
      } catch (_) {}

      await HomeWidget.saveWidgetData<String>('drawing_image_path', imagePath);
      if (imageBase64 != null && imageBase64.isNotEmpty) {
        // Base64 doğrudan App Group UserDefaults'a kaydedilerek iOS sandbox sınırı aşılır
        await HomeWidget.saveWidgetData<String>('drawing_image_base64', imageBase64);
      }
      await HomeWidget.saveWidgetData<String>('drawing_sender', senderName);
      await HomeWidget.saveWidgetData<String>('drawing_sender_name', senderName);
      await HomeWidget.saveWidgetData<String>('drawing_time_ago', timeAgo);
      if (timestampMillis != null) {
        await HomeWidget.saveWidgetData<int>('drawing_timestamp_millis', timestampMillis);
      } else {
        await HomeWidget.saveWidgetData<int>('drawing_timestamp_millis', DateTime.now().millisecondsSinceEpoch);
      }

      await HomeWidget.updateWidget(
        name: androidDrawingWidgetName,
        androidName: androidDrawingWidgetName,
        iOSName: iOSDrawingWidgetName,
      );
      debugPrint('[WidgetSyncService] Drawing widget updated: path=$imagePath, sender=$senderName, hasBase64=${imageBase64 != null}, ts=$timestampMillis');
    } catch (e) {
      debugPrint('[WidgetSyncService] syncDrawingWidget error: $e');
    }
  }

  /// Partnerden gelen okunmamış mesajları widget üzerinde balon yığını olarak gösterir.
  /// En fazla son 3 mesaj baloncuklarda listelenir; 3'ten fazlaysa "+N" rozeti belirir.
  static Future<void> syncWidgetMessages(List<String> unreadMessages) async {
    try {
      try {
        await HomeWidget.setAppGroupId(appGroupId);
      } catch (_) {}

      // Yerel SharedPreferences önbelleğini de güncelle ki arka plan veya yeniden açılışta eski mesajlar hortlamasın
      try {
        final prefs = await SharedPreferences.getInstance();
        if (unreadMessages.isEmpty) {
          await prefs.remove('widget_unread_messages_cache');
        } else {
          await prefs.setStringList('widget_unread_messages_cache', unreadMessages);
        }
      } catch (_) {}

      final count = unreadMessages.length;
      await HomeWidget.saveWidgetData<int>('widget_unread_count', count);

      if (count == 0) {
        await HomeWidget.saveWidgetData<String>('widget_msg_1', '');
        await HomeWidget.saveWidgetData<String>('widget_msg_2', '');
        await HomeWidget.saveWidgetData<String>('widget_msg_3', '');
      } else if (count == 1) {
        await HomeWidget.saveWidgetData<String>('widget_msg_1', '');
        await HomeWidget.saveWidgetData<String>('widget_msg_2', '');
        await HomeWidget.saveWidgetData<String>('widget_msg_3', unreadMessages.first);
      } else if (count == 2) {
        await HomeWidget.saveWidgetData<String>('widget_msg_1', '');
        await HomeWidget.saveWidgetData<String>('widget_msg_2', unreadMessages[0]);
        await HomeWidget.saveWidgetData<String>('widget_msg_3', unreadMessages[1]);
      } else {
        // 3 veya daha fazla: Son 3 tanesini al (en yeni en önde/altta = msg_3)
        final last3 = unreadMessages.sublist(count - 3);
        await HomeWidget.saveWidgetData<String>('widget_msg_1', last3[0]);
        await HomeWidget.saveWidgetData<String>('widget_msg_2', last3[1]);
        await HomeWidget.saveWidgetData<String>('widget_msg_3', last3[2]);
      }

      await HomeWidget.updateWidget(
        name: androidWidgetName,
        androidName: androidWidgetName,
        iOSName: iOSWidgetName,
      );
      debugPrint('[WidgetSyncService] Widget messages updated: count=$count');
    } catch (e) {
      debugPrint('[WidgetSyncService] syncWidgetMessages error: $e');
    }
  }

  /// Okunmamış mesajlar okunduğunda veya sohbete girildiğinde widget mesaj balonlarını temizler
  static Future<void> clearWidgetMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('widget_unread_messages_cache');
    } catch (_) {}
    await syncWidgetMessages(const []);
  }

  /// Eşleşmeden ayrılma veya hesap çıkışı durumunda tüm masaüstü widget'larını (Partner + Çizim + Mesajlar) tamamen sıfırlar
  static Future<void> resetAllWidgets() async {
    try {
      try {
        await HomeWidget.setAppGroupId(appGroupId);
      } catch (_) {}

      // 1. SharedPreferences üzerindeki eşleşme ve widget önbelleklerini sil
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_partner_uid');
      await prefs.remove('saved_couple_id');
      await prefs.remove('saved_start_date');
      await prefs.remove('cached_partner_json');
      await prefs.remove('cached_saved_places_json');
      await prefs.remove('widget_unread_messages_cache');
      await prefs.remove('widget_custom_bg_path');

      // 2. Partner Widget verilerini sıfırla
      await HomeWidget.saveWidgetData<String>('days_count', '0');
      await HomeWidget.saveWidgetData<String>('partner_name', 'Eşleşme Yok');
      await HomeWidget.saveWidgetData<String>('battery_level', '%--');
      await HomeWidget.saveWidgetData<String>('status_text', 'Bağlantı bekleniyor');
      await HomeWidget.saveWidgetData<String>('status_emoji', '💔');
      await HomeWidget.saveWidgetData<String>('last_seen', 'Çevrimdışı');
      await HomeWidget.saveWidgetData<int>('last_active_millis', 0);
      await HomeWidget.saveWidgetData<bool>('partner_is_app_open', false);
      await HomeWidget.saveWidgetData<String>('widget_bg_image_path', '');

      // 3. Mesaj baloncuklarını sıfırla
      await HomeWidget.saveWidgetData<int>('widget_unread_count', 0);
      await HomeWidget.saveWidgetData<String>('widget_msg_1', '');
      await HomeWidget.saveWidgetData<String>('widget_msg_2', '');
      await HomeWidget.saveWidgetData<String>('widget_msg_3', '');

      // 4. Çizim Widget verilerini sıfırla
      await HomeWidget.saveWidgetData<String>('drawing_image_path', '');
      await HomeWidget.saveWidgetData<String>('drawing_image_base64', '');
      await HomeWidget.saveWidgetData<String>('drawing_sender', '');
      await HomeWidget.saveWidgetData<String>('drawing_sender_name', '');
      await HomeWidget.saveWidgetData<String>('drawing_time_ago', '');
      await HomeWidget.saveWidgetData<int>('drawing_timestamp_millis', 0);

      // 5. Her iki platformda da Partner ve Çizim widget'larını güncelle
      await HomeWidget.updateWidget(
        name: androidWidgetName,
        androidName: androidWidgetName,
        iOSName: iOSWidgetName,
      );
      await HomeWidget.updateWidget(
        name: androidDrawingWidgetName,
        androidName: androidDrawingWidgetName,
        iOSName: iOSDrawingWidgetName,
      );

      debugPrint('[WidgetSyncService] All widgets have been completely reset.');
    } catch (e, stack) {
      debugPrint('[WidgetSyncService] resetAllWidgets error: $e\n$stack');
    }
  }

  /// Veritabanına hiç gitmeden, cihazın yerel SharedPreferences verilerini kullanarak
  /// masaüstü widget'larını yeniden tetikler ve sistem saatine göre zamanı ilerletir.
  static Future<void> updateWidgetFromLocalCache() async {
    try {
      try {
        await HomeWidget.setAppGroupId(appGroupId);
      } catch (_) {}

      // Partner Widget'ını tetikle (Provider onUpdate içinde SharedPreferences'tan okuyup dakika/saat farkını yeniden hesaplar)
      await HomeWidget.updateWidget(
        name: androidWidgetName,
        androidName: androidWidgetName,
        iOSName: iOSWidgetName,
      );

      // Çizim Widget'ını tetikle
      await HomeWidget.updateWidget(
        name: androidDrawingWidgetName,
        androidName: androidDrawingWidgetName,
        iOSName: iOSDrawingWidgetName,
      );
    } catch (_) {}
  }
}


