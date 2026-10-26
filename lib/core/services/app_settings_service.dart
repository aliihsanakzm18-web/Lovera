import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lovera Bildirim, Gizlilik ve Güvenlik Ayarları Yöneticisi
/// Hem yerel SharedPreferences'ta anlık erişim sağlar hem de kullanıcının
/// Firestore hesabına otomatik yedekler.
class AppSettingsService {
  static final AppSettingsService _instance = AppSettingsService._();
  factory AppSettingsService() => _instance;
  AppSettingsService._();

  // --- BİLDİRİM AYARLARI ANAHTARLARI ---
  static const String keyNotifHeart = 'notif_heart';
  static const String keyNotifChat = 'notif_chat_messages';
  static const String keyNotifDrawing = 'notif_drawings';
  static const String keyNotifBattery = 'notif_battery';
  static const String keyNotifDistance = 'notif_distance';
  static const String keyNotifMilestones = 'notif_milestones';
  static const String keyNotifGames = 'notif_games';
  static const String keyNotifMemories = 'notif_memories';

  // --- GİZLİLİK VE GÜVENLİK AYARLARI ANAHTARLARI ---
  static const String keyShareLocation = 'privacy_share_location';
  static const String keyShowOnline = 'privacy_show_online';
  static const String keyShareBattery = 'privacy_share_battery';
  static const String keyShareSpeed = 'privacy_share_speed';
  static const String keySharePlaces = 'privacy_share_places';
  static const String keyAppLockEnabled = 'privacy_app_lock_enabled';
  static const String keyAppLockPinHash = 'privacy_app_lock_pin_hash';

  // Bellek içi hızlı önbellek (UI ve servisler senkron erişebilsin diye)
  static bool notifHeart = true;
  static bool notifChat = true;
  static bool notifDrawing = true;
  static bool notifBattery = true;
  static bool notifDistance = true;
  static bool notifMilestones = true;
  static bool notifGames = true;
  static bool notifMemories = true;

  static bool shareLocation = true;
  static bool showOnline = true;
  static bool shareBattery = true;
  static bool shareSpeed = true;
  static bool sharePlaces = true;
  static bool appLockEnabled = false;

  static bool _initialized = false;
  static bool isAppUnlocked = false; // Oturum başına PIN doğrulandı mı?
  static DateTime? lastBackgroundTime;

  /// Servisi başlatır ve yerel SharedPreferences'tan ayarları belleğe yükler
  static Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      notifHeart = prefs.getBool(keyNotifHeart) ?? true;
      notifChat = prefs.getBool(keyNotifChat) ?? true;
      notifDrawing = prefs.getBool(keyNotifDrawing) ?? true;
      notifBattery = prefs.getBool(keyNotifBattery) ?? true;
      notifDistance = prefs.getBool(keyNotifDistance) ?? true;
      notifMilestones = prefs.getBool(keyNotifMilestones) ?? true;
      notifGames = prefs.getBool(keyNotifGames) ?? true;
      notifMemories = prefs.getBool(keyNotifMemories) ?? true;

      shareLocation = prefs.getBool(keyShareLocation) ?? true;
      showOnline = prefs.getBool(keyShowOnline) ?? true;
      shareBattery = prefs.getBool(keyShareBattery) ?? true;
      shareSpeed = prefs.getBool(keyShareSpeed) ?? true;
      sharePlaces = prefs.getBool(keySharePlaces) ?? true;
      final savedPinHash = prefs.getString(keyAppLockPinHash);
      appLockEnabled = (prefs.getBool(keyAppLockEnabled) ?? false) && (savedPinHash != null && savedPinHash.isNotEmpty);

      _initialized = true;
      debugPrint('[AppSettingsService] Ayarlar başarıyla yüklendi.');
    } catch (e) {
      debugPrint('[AppSettingsService] init error: $e');
    }
  }

  /// Firestore'daki kullanıcı belgesinden ayarları çeker ve senkronize eder
  static Future<void> syncFromCloud(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!doc.exists || doc.data() == null) return;
      final data = doc.data()!;

      final notifs = data['notificationSettings'] as Map<String, dynamic>?;
      final privacy = data['privacySettings'] as Map<String, dynamic>?;
      final prefs = await SharedPreferences.getInstance();

      if (notifs != null) {
        if (notifs.containsKey('notif_heart')) {
          notifHeart = notifs['notif_heart'] as bool? ?? true;
          await prefs.setBool(keyNotifHeart, notifHeart);
        }
        if (notifs.containsKey('notif_chat_messages')) {
          notifChat = notifs['notif_chat_messages'] as bool? ?? true;
          await prefs.setBool(keyNotifChat, notifChat);
        }
        if (notifs.containsKey('notif_drawings')) {
          notifDrawing = notifs['notif_drawings'] as bool? ?? true;
          await prefs.setBool(keyNotifDrawing, notifDrawing);
        }
        if (notifs.containsKey('notif_battery')) {
          notifBattery = notifs['notif_battery'] as bool? ?? true;
          await prefs.setBool(keyNotifBattery, notifBattery);
        }
        if (notifs.containsKey('notif_distance')) {
          notifDistance = notifs['notif_distance'] as bool? ?? true;
          await prefs.setBool(keyNotifDistance, notifDistance);
        }
        if (notifs.containsKey('notif_milestones')) {
          notifMilestones = notifs['notif_milestones'] as bool? ?? true;
          await prefs.setBool(keyNotifMilestones, notifMilestones);
        }
        if (notifs.containsKey('notif_games')) {
          notifGames = notifs['notif_games'] as bool? ?? true;
          await prefs.setBool(keyNotifGames, notifGames);
        }
        if (notifs.containsKey('notif_memories')) {
          notifMemories = notifs['notif_memories'] as bool? ?? true;
          await prefs.setBool(keyNotifMemories, notifMemories);
        }
      }

      if (privacy != null) {
        if (privacy.containsKey('shareLocation')) {
          shareLocation = privacy['shareLocation'] as bool? ?? true;
          await prefs.setBool(keyShareLocation, shareLocation);
        }
        if (privacy.containsKey('showOnline')) {
          showOnline = privacy['showOnline'] as bool? ?? true;
          await prefs.setBool(keyShowOnline, showOnline);
        }
        if (privacy.containsKey('shareBattery')) {
          shareBattery = privacy['shareBattery'] as bool? ?? true;
          await prefs.setBool(keyShareBattery, shareBattery);
        }
        if (privacy.containsKey('shareSpeed')) {
          shareSpeed = privacy['shareSpeed'] as bool? ?? true;
          await prefs.setBool(keyShareSpeed, shareSpeed);
        }
        if (privacy.containsKey('sharePlaces')) {
          sharePlaces = privacy['sharePlaces'] as bool? ?? true;
          await prefs.setBool(keySharePlaces, sharePlaces);
        }
      }
      debugPrint('[AppSettingsService] Cloud senkronizasyonu tamamlandı.');
    } catch (e) {
      debugPrint('[AppSettingsService] syncFromCloud error: $e');
    }
  }

  // --- BİLDİRİM AYARLARI GÜNCELLEME ---

  static Future<void> setNotificationSetting(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);

      switch (key) {
        case keyNotifHeart:
          notifHeart = value;
          break;
        case keyNotifChat:
          notifChat = value;
          break;
        case keyNotifDrawing:
          notifDrawing = value;
          break;
        case keyNotifBattery:
          notifBattery = value;
          break;
        case keyNotifDistance:
          notifDistance = value;
          break;
        case keyNotifMilestones:
          notifMilestones = value;
          break;
        case keyNotifGames:
          notifGames = value;
          break;
        case keyNotifMemories:
          notifMemories = value;
          break;
      }

      _syncNotifSettingsToCloud();
    } catch (e) {
      debugPrint('[AppSettingsService] setNotificationSetting error: $e');
    }
  }

  static Future<void> _syncNotifSettingsToCloud() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'notificationSettings': {
          'notif_heart': notifHeart,
          'notif_chat_messages': notifChat,
          'notif_drawings': notifDrawing,
          'notif_battery': notifBattery,
          'notif_distance': notifDistance,
          'notif_milestones': notifMilestones,
          'notif_games': notifGames,
          'notif_memories': notifMemories,
        },
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // --- GİZLİLİK AYARLARI GÜNCELLEME ---

  static Future<void> setPrivacySetting(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);

      switch (key) {
        case keyShareLocation:
          shareLocation = value;
          break;
        case keyShowOnline:
          showOnline = value;
          break;
        case keyShareBattery:
          shareBattery = value;
          break;
        case keyShareSpeed:
          shareSpeed = value;
          break;
        case keySharePlaces:
          sharePlaces = value;
          break;
      }

      _syncPrivacySettingsToCloud();
    } catch (e) {
      debugPrint('[AppSettingsService] setPrivacySetting error: $e');
    }
  }

  static Future<void> _syncPrivacySettingsToCloud() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'privacySettings': {
          'shareLocation': shareLocation,
          'showOnline': showOnline,
          'shareBattery': shareBattery,
          'shareSpeed': shareSpeed,
          'sharePlaces': sharePlaces,
        },
        // Partner sorguları ve doğrudan okumalar için root alanları da güncelle:
        'shareLocation': shareLocation,
        'showOnline': showOnline,
        'shareBattery': shareBattery,
        'shareSpeed': shareSpeed,
        'sharePlaces': sharePlaces,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // --- BİLDİRİM FİLTRELEME MANTIĞI ---

  /// Gelen bir bildirim türünün kullanıcının ayarlarına göre izinli olup olmadığını döner
  static bool isNotificationTypeEnabledSync(String? type) {
    if (type == null || type.isEmpty) return true;
    switch (type) {
      case 'heart_ping':
      case 'heartPing':
      case 'heart_pulse':
        return notifHeart;
      case 'chat_message':
      case 'chatMessage':
      case 'chat':
        return notifChat;
      case 'drawing_sent':
      case 'drawing':
        return notifDrawing;
      case 'charge_ping':
      case 'chargePing':
      case 'lowBattery':
      case 'low_battery':
      case 'battery_ping':
        return notifBattery;
      case 'proximity':
      case 'place_enter':
      case 'place_exit':
      case 'status_update':
        return notifDistance;
      case 'milestone':
      case 'anniversary':
      case 'birthday':
        return notifMilestones;
      case 'game_request':
      case 'game_result':
        return notifGames;
      case 'memory_added':
      case 'memory':
        return notifMemories;
      default:
        return true;
    }
  }

  /// Arka plan izole isolate'leri için SharedPreferences üzerinden async kontrol
  static Future<bool> isNotificationTypeEnabled(String? type) async {
    if (type == null || type.isEmpty) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      switch (type) {
        case 'heart_ping':
        case 'heartPing':
        case 'heart_pulse':
          return prefs.getBool(keyNotifHeart) ?? true;
        case 'chat_message':
        case 'chatMessage':
        case 'chat':
          return prefs.getBool(keyNotifChat) ?? true;
        case 'drawing_sent':
        case 'drawing':
          return prefs.getBool(keyNotifDrawing) ?? true;
        case 'charge_ping':
        case 'chargePing':
        case 'lowBattery':
        case 'low_battery':
        case 'battery_ping':
          return prefs.getBool(keyNotifBattery) ?? true;
        case 'proximity':
        case 'place_enter':
        case 'place_exit':
        case 'status_update':
          return prefs.getBool(keyNotifDistance) ?? true;
        case 'milestone':
        case 'anniversary':
        case 'birthday':
          return prefs.getBool(keyNotifMilestones) ?? true;
        case 'game_request':
        case 'game_result':
          return prefs.getBool(keyNotifGames) ?? true;
        case 'memory_added':
        case 'memory':
          return prefs.getBool(keyNotifMemories) ?? true;
        default:
          return true;
      }
    } catch (_) {
      return true;
    }
  }

  // --- UYGULAMA KİLİDİ (PIN) YÖNETİMİ ---

  static String _hashPin(String pin) {
    const salt = 'Lovera_Secure_Pin_Salt_2026';
    final bytes = utf8.encode(pin + salt);
    return sha256.convert(bytes).toString();
  }

  static Future<bool> verifyPin(String enteredPin) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedHash = prefs.getString(keyAppLockPinHash);
      if (savedHash == null || savedHash.isEmpty) return true;
      return savedHash == _hashPin(enteredPin);
    } catch (_) {
      return false;
    }
  }

  static Future<void> setAppLockPin(String newPin) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hash = _hashPin(newPin);
      await prefs.setString(keyAppLockPinHash, hash);
      await prefs.setBool(keyAppLockEnabled, true);
      appLockEnabled = true;
      isAppUnlocked = true;
    } catch (e) {
      debugPrint('[AppSettingsService] setAppLockPin error: $e');
    }
  }

  static Future<void> disableAppLock() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyAppLockEnabled, false);
      await prefs.remove(keyAppLockPinHash);
      appLockEnabled = false;
      isAppUnlocked = true;
    } catch (e) {
      debugPrint('[AppSettingsService] disableAppLock error: $e');
    }
  }
}
