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

  // Senkronizasyon fonksiyonu (Gerçek zamanlı GPS koordinatları)
  Future<void> performLiveSync({Position? customPos}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final uid = prefs.getString('saved_uid') ?? FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;

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
      if (city == null || city.isEmpty) {
        city = 'İstanbul';
      } else {
        prefs.setString('saved_city', city);
      }

      final now = DateTime.now();
      final period = DeviceService().getTimeOfDayPeriod(now);
      final isNight = now.hour >= 20 || now.hour < 6;
      weather ??= (isNight ? '$period · Yıldızlı 20°' : '$period · Açık 22°');

      final Map<String, dynamic> updateData = {
        'lastActive': FieldValue.serverTimestamp(),
      };
      if (batteryLevel != null) {
        updateData['batteryLevel'] = batteryLevel;
      }
      if (lat != null && lng != null) {
        updateData['lat'] = lat;
        updateData['lng'] = lng;
      }
      if (weather.isNotEmpty) {
        updateData['weather'] = weather;
      }
      if (city.isNotEmpty) {
        updateData['city'] = city;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(updateData, SetOptions(merge: true));

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
    }
  }

  // 1. İlk açılışta anında senkronize et
  await performLiveSync();

  // 2. Anlık GPS Hareket Dinleyicisi (Snapchat / Zenly Tarzı):
  // Cihaz 5 metre dahi hareket ettiğinde anında tetiklenir ve yeni konumu partnerin ekranına basar
  try {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      ),
    ).listen(
      (newPosition) async {
        await performLiveSync(customPos: newPosition);
      },
      onError: (err) {
        debugPrint('[BG-POS-STREAM-ERR] $err');
      },
    );
  } catch (_) {}

  // 3. Şarj durumu her değiştiğinde anında güncelle (kablo takma/çıkarma)
  battery.onBatteryStateChanged.listen((_) {
    performLiveSync();
  });

  // 4. Periyodik olarak 15 saniyede bir saati, şarjı ve konumu canlı tut
  Timer.periodic(const Duration(seconds: 15), (_) async {
    await performLiveSync();
  });
}
