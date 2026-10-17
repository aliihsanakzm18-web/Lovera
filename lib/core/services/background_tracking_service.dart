import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../firebase_options.dart';
import '../models/models.dart';
import 'device_service.dart';
import 'notification_service.dart';
import 'widget_sync_service.dart';

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

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final uid = prefs.getString('saved_uid') ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      int? batteryLevel;
      try {
        batteryLevel = await Battery().batteryLevel;
      } catch (_) {}

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 4),
        );
      } catch (_) {
        try {
          pos = await Geolocator.getLastKnownPosition();
        } catch (_) {}
      }

      final Map<String, dynamic> updateData = {};
      if (batteryLevel != null) updateData['batteryLevel'] = batteryLevel;
      if (pos != null) {
        updateData['lat'] = pos.latitude;
        updateData['lng'] = pos.longitude;
        updateData['speed'] = (pos.speed >= 0) ? pos.speed : 0.0;
        final city = await DeviceService().getCityForLocation(pos.latitude, pos.longitude);
        final weather = await DeviceService().getWeatherForLocation(pos.latitude, pos.longitude);
        if (city != null) updateData['city'] = city;
        if (weather != null) updateData['weather'] = weather;
      }

      if (updateData.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set(
          updateData,
          SetOptions(merge: true),
        );
        debugPrint('[IOS-BG-SYNC-SUCCESS] Pil: $batteryLevel, Konum: ${pos?.latitude}, ${pos?.longitude}');
      }
    }
  } catch (e) {
    debugPrint('[IOS-BG-SYNC-ERR] $e');
  }

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
    service.setAsForegroundService();

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

  int? lastBgBattery;
  double? lastBgLat;
  double? lastBgLng;
  DateTime? lastBgWriteTime;
  String? lastBgMatchedPlaceId;

  // Senkronizasyon fonksiyonu (Gerçek zamanlı GPS koordinatları)
  Future<void> performLiveSync({Position? customPos}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final uid = prefs.getString('saved_uid') ?? FirebaseAuth.instance.currentUser?.uid;

      // Eğer kullanıcı oturum açmamışsa veya çıkış yapmışsa arka plan servisini derhal durdur!
      if (uid == null || uid.isEmpty) {
        debugPrint('[BG-SERVICE] Oturum kapalı, servis sonlandırılıyor.');
        service.stopSelf();
        return;
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

      final now = DateTime.now();

      // Akıllı Değişim Kontrolü: Pil, konum veya hareket/duruş durumu değişti mi?
      bool hasMeaningfulChange = false;
      if (batteryLevel != null && batteryLevel != lastBgBattery) {
        hasMeaningfulChange = true;
      }
      if (lat != null && lng != null) {
        if (lastBgLat == null || lastBgLng == null) {
          hasMeaningfulChange = true;
        } else {
          final dist = Geolocator.distanceBetween(lastBgLat!, lastBgLng!, lat, lng);
          if (dist >= 15) { // 15 metreden fazla konum hareketi
            hasMeaningfulChange = true;
          }
        }
      }

      // Hız 0'a düştüyse (hareket durduysa) veya duruştan harekete geçildiyse hemen güncelle
      final wasMoving = prefs.getBool('bg_was_moving') ?? false;
      final isNowMoving = (pos?.speed != null && pos!.speed >= 0.7);
      if (wasMoving != isNowMoving) {
        hasMeaningfulChange = true;
        await prefs.setBool('bg_was_moving', isNowMoving);
      }

      final isPeriodicFallback = lastBgWriteTime == null || now.difference(lastBgWriteTime!).inSeconds >= 45;

      // Değişiklik yoksa ve periyodik süre dolmadıysa Firestore yazma hakkını harcama!
      if (!hasMeaningfulChange && !isPeriodicFallback) {
        return;
      }

      if (lat != null && lng != null) {
        city = await DeviceService().getCityForLocation(lat, lng);
        weather = await DeviceService().getWeatherForLocation(lat, lng);
      }

      city ??= prefs.getString('saved_city');
      if (city != null && city.isNotEmpty) {
        prefs.setString('saved_city', city);
      }

      double calculatedSpeed = (pos?.speed != null && pos!.speed >= 0) ? pos.speed : 0.0;
      if (lat != null && lng != null && lastBgLat != null && lastBgLng != null && lastBgWriteTime != null) {
        final sec = now.difference(lastBgWriteTime!).inSeconds;
        if (sec > 0 && sec < 180) {
          final dist = Geolocator.distanceBetween(lastBgLat!, lastBgLng!, lat, lng);
          if (dist < 10) {
            // Cihaz hareket etmiyor / duruyor (GPS sapması toleransı)
            calculatedSpeed = 0.0;
          } else if (calculatedSpeed <= 0) {
            calculatedSpeed = dist / sec;
          }
        }
      }

      SavedPlace? currentMatchedPlace;
      String? currentPlaceId;
      String? previousPlaceId;
      List<SavedPlace> placesList = [];
      final coupleId = prefs.getString('saved_couple_id');
      final partnerUid = prefs.getString('saved_partner_uid');
      final myName = prefs.getString('saved_user_name') ?? 'Partnerin';

      if (lat != null && lng != null && coupleId != null && coupleId.isNotEmpty) {
        try {
          final cachedPlacesJson = prefs.getString('cached_saved_places_json');
          if (cachedPlacesJson != null && cachedPlacesJson.isNotEmpty) {
            try {
              final List decoded = jsonDecode(cachedPlacesJson);
              placesList = decoded.map((e) => SavedPlace.fromJson(Map<String, dynamic>.from(e), e['id']?.toString() ?? '')).toList();
            } catch (_) {}
          }

          if (placesList.isEmpty) {
            final placesSnap = await FirebaseFirestore.instance
                .collection('couples')
                .doc(coupleId)
                .collection('saved_places')
                .get();
            placesList = placesSnap.docs.map((d) => SavedPlace.fromJson(d.data(), d.id)).toList();
            if (placesList.isNotEmpty) {
              try {
                final placesJsonList = placesList.map((p) {
                  final m = p.toJson();
                  m['id'] = p.id;
                  return m;
                }).toList();
                await prefs.setString('cached_saved_places_json', jsonEncode(placesJsonList));
              } catch (_) {}
            }
          }

          for (final p in placesList) {
            final dist = Geolocator.distanceBetween(lat, lng, p.lat, p.lng);
            if (dist <= 85) { // 85 metre güvenilir menzil
              currentMatchedPlace = p;
              break;
            }
          }

          currentPlaceId = currentMatchedPlace?.id;
          previousPlaceId = lastBgMatchedPlaceId ?? prefs.getString('bg_last_matched_place_id');
        } catch (e) {
          debugPrint('[BG-PLACE-MATCH-ERR] $e');
        }
      }

      final Map<String, dynamic> updateData = {};
      if (batteryLevel != null) {
        updateData['batteryLevel'] = batteryLevel;
      }
      if (lat != null && lng != null) {
        updateData['lat'] = lat;
        updateData['lng'] = lng;
      }
      updateData['speed'] = calculatedSpeed >= 0 ? calculatedSpeed : 0.0;
      if (weather != null && weather.isNotEmpty) {
        updateData['weather'] = weather;
      }
      if (city != null && city.isNotEmpty) {
        updateData['city'] = city;
      }
      updateData['currentPlaceTitle'] = currentMatchedPlace?.title ?? '';
      updateData['currentPlaceEmoji'] = currentMatchedPlace?.iconEmoji ?? '';
      updateData['lastActive'] = FieldValue.serverTimestamp();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(updateData, SetOptions(merge: true))
          .timeout(const Duration(seconds: 4));

      lastBgWriteTime = now;
      if (batteryLevel != null) lastBgBattery = batteryLevel;
      if (lat != null && lng != null) {
        lastBgLat = lat;
        lastBgLng = lng;
      }

      // 4. Arka Plan Geofence (Mekan Giriş / Çıkış) Kontrolü (Uygulama tamamen kapalıyken de çalışır)
      if (lat != null && lng != null && coupleId != null && coupleId.isNotEmpty) {
        try {
          // Eğer mekan durumu değiştiyse bildirimleri ateşle!
          if (currentPlaceId != previousPlaceId) {
            lastBgMatchedPlaceId = currentPlaceId;
            if (currentPlaceId != null) {
              await prefs.setString('bg_last_matched_place_id', currentPlaceId);
            } else {
              await prefs.remove('bg_last_matched_place_id');
            }

            // İlk açılışta veya ilk tespitte spam olmaması için previousPlaceId null değilse veya yer değiştiyse
            if (previousPlaceId != null || currentPlaceId != null) {
              final myUid = prefs.getString('saved_uid') ?? uid;

              // Ortak gönderilecek data yükü (Widget anında güncellensin diye)
              final Map<String, String> syncDataPayload = {
                'partnerUid': uid,
                'lat': lat.toString(),
                'lng': lng.toString(),
                'speed': calculatedSpeed.toString(),
                if (batteryLevel != null) 'batteryLevel': batteryLevel.toString(),
                'currentPlaceTitle': currentMatchedPlace?.title ?? '',
                'currentPlaceEmoji': currentMatchedPlace?.iconEmoji ?? '',
              };

              // A) Ben yeni bir mekana girdim mi?
              if (currentMatchedPlace != null) {
                final placeTitle = currentMatchedPlace.title;
                final placeEmoji = currentMatchedPlace.iconEmoji;
                final remoteNotifs = currentMatchedPlace.notifications ?? {};

                // İki taraftan herhangi biri bildirim istemişse gönder!
                // 1. Ben "ben gidince haber ver" demiş miyim? (${myUid}_enter / my_enter)
                // 2. Partner "o gelince bana haber ver" demiş mi? (${partnerUid}_enter / partner_enter)
                final bool shouldNotifyEnter = 
                    remoteNotifs['${myUid}_enter'] as bool? ??
                    (partnerUid != null ? remoteNotifs['${partnerUid}_enter'] as bool? : null) ??
                    remoteNotifs['my_enter'] as bool? ??
                    remoteNotifs['partner_enter'] as bool? ??
                    prefs.getBool('my_notify_enter_${currentMatchedPlace.id}') ??
                    prefs.getBool('partner_notify_enter_${currentMatchedPlace.id}') ??
                    prefs.getBool('notify_enter_${currentMatchedPlace.id}') ?? true;

                if (shouldNotifyEnter && partnerUid != null && partnerUid.isNotEmpty) {
                  NotificationService().sendPushToPartner(
                    partnerUid: partnerUid,
                    title: '$placeEmoji $myName Konuma Ulaştı',
                    body: '$myName "$placeTitle" konumuna vardı. 💕',
                    data: {
                      'type': 'place_enter',
                      ...syncDataPayload,
                    },
                  );
                }
              }

              // B) Ben önceki mekandan ayrıldım mı?
              if (previousPlaceId != null) {
                SavedPlace? oldPlace;
                for (final p in placesList) {
                  if (p.id == previousPlaceId) {
                    oldPlace = p;
                    break;
                  }
                }

                if (oldPlace != null) {
                  final oldTitle = oldPlace.title;
                  final remoteNotifs = oldPlace.notifications ?? {};

                  // İki taraftan herhangi biri bildirim istemişse gönder!
                  // 1. Ben "ben ayrılınca haber ver" demiş miyim? (${myUid}_exit / my_exit)
                  // 2. Partner "o ayrılınca bana haber ver" demiş mi? (${partnerUid}_exit / partner_exit)
                  final bool shouldNotifyExit = 
                      remoteNotifs['${myUid}_exit'] as bool? ??
                      (partnerUid != null ? remoteNotifs['${partnerUid}_exit'] as bool? : null) ??
                      remoteNotifs['my_exit'] as bool? ??
                      remoteNotifs['partner_exit'] as bool? ??
                      prefs.getBool('my_notify_exit_${oldPlace.id}') ??
                      prefs.getBool('partner_notify_exit_${oldPlace.id}') ??
                      prefs.getBool('notify_exit_${oldPlace.id}') ?? true;

                  if (shouldNotifyExit && partnerUid != null && partnerUid.isNotEmpty) {
                    NotificationService().sendPushToPartner(
                      partnerUid: partnerUid,
                      title: '🚶 $myName Konumdan Ayrıldı',
                      body: '$myName "$oldTitle" konumundan ayrıldı.',
                      data: {
                        'type': 'place_exit',
                        ...syncDataPayload,
                      },
                    );
                  }
                }
              }
            }
          }
        } catch (e) {
          debugPrint('[BG-GEOFENCE-ERR] $e');
        }
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
    }
  }

  // 1. İlk açılışta anında senkronize et
  await performLiveSync();

  // 2. Anlık GPS Hareket Dinleyicisi (Snapchat / Zenly Tarzı):
  try {
    final LocationSettings locationSettings = defaultTargetPlatform == TargetPlatform.iOS
        ? AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 15,
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: false,
            activityType: ActivityType.fitness,
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 15, // 15 metre: Canlı rota ve yürüyüş hareketlerinde anında tetiklenme
          );

    Geolocator.getPositionStream(
      locationSettings: locationSettings,
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

  // 3. Şarj durumu her değiştiğinde anında güncelle (kablo takma/çıkarma)
  battery.onBatteryStateChanged.listen((_) async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('saved_uid');
    if (uid == null || uid.isEmpty) {
      service.stopSelf();
      return;
    }
    performLiveSync();
  });

  // 4. Periyodik olarak 15 saniyede bir saati, şarjı ve konumu canlı tut (Pil değiştiğinde anında tetiklenir)
  Timer.periodic(const Duration(seconds: 15), (timer) async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('saved_uid');
    if (uid == null || uid.isEmpty) {
      timer.cancel();
      service.stopSelf();
      return;
    }
    await performLiveSync();
  });

  // 5. 7/24 Kesintisiz Partner Dinleyicisi (Uygulama tamamen kapalı olsa dahi Widget'ı canlı tutar)
  try {
    final prefs = await SharedPreferences.getInstance();
    final partnerUid = prefs.getString('saved_partner_uid');
    final savedStartDateStr = prefs.getString('saved_start_date');
    final startDate = savedStartDateStr != null ? DateTime.tryParse(savedStartDateStr) : null;

    if (partnerUid != null && partnerUid.isNotEmpty) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(partnerUid)
          .snapshots()
          .listen((doc) async {
        if (!doc.exists || doc.data() == null) return;
        final data = doc.data()!;

        DateTime? parsedLastActive;
        final rawLastActive = data['lastActive'];
        if (rawLastActive is DateTime) {
          parsedLastActive = rawLastActive;
        } else if (rawLastActive is String) {
          parsedLastActive = DateTime.tryParse(rawLastActive);
        } else if (rawLastActive != null) {
          try {
            parsedLastActive = (rawLastActive as dynamic).toDate?.call();
          } catch (_) {}
        }

        final partnerUser = AppUser(
          id: doc.id,
          name: data['name'] ?? 'Partnerin',
          avatarUrl: data['avatarUrl'],
          batteryLevel: data['batteryLevel'] as int?,
          weather: data['weather'] as String?,
          city: data['city'] as String?,
          lat: (data['lat'] as num?)?.toDouble(),
          lng: (data['lng'] as num?)?.toDouble(),
          lastActive: parsedLastActive,
          coupleId: data['coupleId'],
          isAppOpen: data['isAppOpen'] as bool?,
          birthDate: data['birthDate'] as String?,
          speed: (data['speed'] as num?)?.toDouble(),
          currentPlaceTitle: data['currentPlaceTitle'] as String?,
          currentPlaceEmoji: data['currentPlaceEmoji'] as String?,
        );

        // Kayıtlı mekanları önbellekten al
        List<SavedPlace> places = [];
        final cachedPlacesJson = prefs.getString('cached_saved_places_json');
        if (cachedPlacesJson != null && cachedPlacesJson.isNotEmpty) {
          try {
            final List decoded = jsonDecode(cachedPlacesJson);
            places = decoded.map((e) => SavedPlace.fromJson(Map<String, dynamic>.from(e), e['id']?.toString() ?? '')).toList();
          } catch (_) {}
        }

        // Widget'a anında canlı veriyi bas (Arka planda uygulama kapalıyken bile çalışır!)
        await WidgetSyncService.syncWidget(
          partner: partnerUser,
          startDate: startDate,
          savedPlaces: places,
        );
        debugPrint('[BG-WIDGET-SYNC] Partner (${partnerUser.name}) widget verisi arka planda güncellendi: Pil=${partnerUser.batteryLevel}, Hız=${partnerUser.speed}');
      }, onError: (e) {
        debugPrint('[BG-PARTNER-STREAM-ERR] $e');
      });
    }
  } catch (e) {
    debugPrint('[BG-PARTNER-SETUP-ERR] $e');
  }
}
