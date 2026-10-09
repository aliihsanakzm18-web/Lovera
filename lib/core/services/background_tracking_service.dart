import 'dart:async';
import 'dart:ui';
import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../firebase_options.dart';
import 'device_service.dart';

/// 7/24 Kesintisiz Arka Plan Canlı Şarj ve Konum Servisi (Snapchat / Life360 Modeli)
/// Uygulama görev yöneticisinden kapatılsa dahi Android Foreground Service olarak
/// arka planda yaşamaya devam eder ve partnerin ekranındaki bilgileri sürekli canlı tutar.
class BackgroundTrackingService {
  static final BackgroundTrackingService _instance = BackgroundTrackingService._();
  factory BackgroundTrackingService() => _instance;
  BackgroundTrackingService._();

  static bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final service = FlutterBackgroundService();

      // 1. Bildirim kanalını oluştur
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'lovera_live_sync',
        'Lovera Canlı Eşleşme',
        description: 'Canlı konum ve pil seviyesi arka plan senkronizasyonu',
        importance: Importance.low,
      );

      final FlutterLocalNotificationsPlugin localPlugin = FlutterLocalNotificationsPlugin();
      await localPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      // 2. Servisi yapılandır
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onBackgroundTrackingStart,
          autoStart: true,
          autoStartOnBoot: true,
          isForegroundMode: true,
          notificationChannelId: 'lovera_live_sync',
          initialNotificationTitle: 'Lovera · Canlı Bağlantı Aktif 💕',
          initialNotificationContent: 'Partnerinle canlı şarj ve konum eşitleniyor',
          foregroundServiceNotificationId: 998877,
          foregroundServiceTypes: [
            AndroidForegroundType.location,
            AndroidForegroundType.dataSync,
          ],
        ),
        iosConfiguration: IosConfiguration(
          autoStart: true,
          onForeground: onBackgroundTrackingStart,
          onBackground: onIosBackground,
        ),
      );

      _initialized = true;
    } catch (e) {
      debugPrint('[BackgroundTrackingService] initialize skipped or error: $e');
    }
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onBackgroundTrackingStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}

  final battery = Battery();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((_) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((_) {
    service.stopSelf();
  });

  // Senkronizasyon durumu ve akıllı kota/pil koruma değişkenleri
  bool isSyncing = false;
  DateTime? lastSyncTime;
  double? lastSyncedLat;
  double? lastSyncedLng;
  DateTime? lastDeviceCheck;

  // Senkronizasyon fonksiyonu (Gerçek zamanlı GPS koordinatları)
  Future<void> performLiveSync({Position? customPos, bool force = false}) async {
    if (isSyncing) return;

    final now = DateTime.now();
    // 25 saniye içinde 30 metreden az oynadıysa gereksiz yere Firestore yazma
    if (!force && lastSyncTime != null && now.difference(lastSyncTime!) < const Duration(seconds: 25)) {
      if (customPos != null && lastSyncedLat != null && lastSyncedLng != null) {
        final d = Geolocator.distanceBetween(lastSyncedLat!, lastSyncedLng!, customPos.latitude, customPos.longitude);
        if (d < 30) return;
      } else {
        return;
      }
    }

    isSyncing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final uid = prefs.getString('saved_uid') ?? FirebaseAuth.instance.currentUser?.uid;
      final myDeviceId = prefs.getString('device_session_id');

      // Eğer kullanıcı oturum açmamışsa veya çıkış yapmışsa arka plan servisini derhal durdur!
      if (uid == null || uid.isEmpty) {
        debugPrint('[BG-SERVICE] Oturum kapalı, servis sonlandırılıyor.');
        service.stopSelf();
        return;
      }

      // Sadece 5 dakikada bir aktif cihaz kontrolü yap (Her GPS güncellemesinde read yakma!)
      if (lastDeviceCheck == null || now.difference(lastDeviceCheck!) > const Duration(minutes: 5)) {
        lastDeviceCheck = now;
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get(const GetOptions(source: Source.serverAndCache))
              .timeout(const Duration(seconds: 8));
          if (userDoc.exists) {
            final activeDeviceId = userDoc.data()?['currentDeviceId'] as String?;
            if (activeDeviceId != null && myDeviceId != null && activeDeviceId != myDeviceId) {
              debugPrint('[BG-SERVICE] Başka cihaz ($activeDeviceId) aktif oldu. Bu cihaz ($myDeviceId) durduruluyor.');
              await prefs.remove('saved_uid');
              service.stopSelf();
              return;
            }
          }
        } catch (_) {}
      }

      int? batteryLevel;
      try {
        batteryLevel = await battery.batteryLevel;
      } catch (_) {}

      double? lat;
      double? lng;
      String? city;
      String? weather;

      Position? pos = customPos;
      if (pos == null) {
        try {
          pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 5),
          );
        } catch (_) {
          try {
            pos = await Geolocator.getLastKnownPosition();
          } catch (_) {}
        }
      }

      if (pos != null) {
        lat = pos.latitude;
        lng = pos.longitude;
      }

      if (lat != null && lng != null) {
        city = await DeviceService().getCityForLocation(lat, lng);
        weather = await DeviceService().getWeatherForLocation(lat, lng);
      }

      city ??= prefs.getString('saved_city');
      if (city != null && city.isNotEmpty) {
        prefs.setString('saved_city', city);
      }

      final Map<String, dynamic> updateData = {};
      if (batteryLevel != null) {
        updateData['batteryLevel'] = batteryLevel;
      }
      if (lat != null && lng != null) {
        updateData['lat'] = lat;
        updateData['lng'] = lng;

        try {
          final coupleId = prefs.getString('saved_couple_id');
          if (coupleId != null && coupleId.isNotEmpty) {
            final placesSnap = await FirebaseFirestore.instance
                .collection('couples')
                .doc(coupleId)
                .collection('saved_places')
                .get(const GetOptions(source: Source.serverAndCache))
                .timeout(const Duration(seconds: 4));
            bool matched = false;
            for (final doc in placesSnap.docs) {
              final d = doc.data();
              final pLat = (d['lat'] as num?)?.toDouble();
              final pLng = (d['lng'] as num?)?.toDouble();
              if (pLat != null && pLng != null) {
                final dist = Geolocator.distanceBetween(lat, lng, pLat, pLng);
                if (dist <= 150) {
                  updateData['currentPlaceTitle'] = d['title'] ?? 'Evim';
                  updateData['currentPlaceEmoji'] = d['iconEmoji'] ?? d['emoji'] ?? '🏠';
                  matched = true;
                  break;
                }
              }
            }
            if (!matched && placesSnap.docs.isNotEmpty) {
              final allFar = placesSnap.docs.every((doc) {
                final d = doc.data();
                final pLat = (d['lat'] as num?)?.toDouble();
                final pLng = (d['lng'] as num?)?.toDouble();
                if (pLat == null || pLng == null) return true;
                return Geolocator.distanceBetween(lat!, lng!, pLat, pLng) > 250;
              });
              if (allFar) {
                updateData['currentPlaceTitle'] = '';
                updateData['currentPlaceEmoji'] = '';
              }
            }
          }
        } catch (_) {}
      }
      if (weather != null && weather.isNotEmpty) {
        updateData['weather'] = weather;
      }
      if (city != null && city.isNotEmpty) {
        updateData['city'] = city;
      }
      updateData['lastActive'] = FieldValue.serverTimestamp();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(updateData, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));

      lastSyncTime = DateTime.now();
      if (lat != null && lng != null) {
        lastSyncedLat = lat;
        lastSyncedLng = lng;
      }

      if (service is AndroidServiceInstance) {
        final batText = batteryLevel != null ? '%$batteryLevel' : '';
        service.setForegroundNotificationInfo(
          title: 'Lovera · Canlı Bağlantı Aktif 💕',
          content: 'Şarj: $batText · $city · Canlı eşitleniyor',
        );
      }
      debugPrint('[BG-SERVICE-SYNC-SUCCESS] Pil: $batteryLevel, Konum: $lat, $lng ($city)');
    } catch (e) {
      debugPrint('[BG-TRACKING-ERROR] $e');
    } finally {
      isSyncing = false;
    }
  }

  // 1. İlk açılışta anında senkronize et
  await performLiveSync(force: true);

  // 2. Anlık GPS Hareket Dinleyicisi (Snapchat / Zenly Tarzı):
  try {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20, // 20 metre: Titreşimsiz ve stabil rota takibi
      ),
    ).listen(
      (newPosition) async {
        final prefs = await SharedPreferences.getInstance();
        final uid = prefs.getString('saved_uid');
        if (uid == null || uid.isEmpty) {
          service.stopSelf();
          return;
        }
        await performLiveSync(customPos: newPosition);
      },
      onError: (err) {
        debugPrint('[BG-POS-STREAM-ERR] $err');
      },
    );
  } catch (_) {}

  // 3. Şarj durumu her değiştiğinde güncelle
  battery.onBatteryStateChanged.listen((_) async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('saved_uid');
    if (uid == null || uid.isEmpty) {
      service.stopSelf();
      return;
    }
    performLiveSync();
  });

  // 4. Periyodik olarak 90 saniyede bir saati, şarjı ve konumu canlı tut
  Timer.periodic(const Duration(seconds: 90), (timer) async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('saved_uid');
    if (uid == null || uid.isEmpty) {
      timer.cancel();
      service.stopSelf();
      return;
    }
    await performLiveSync();
  });
}
