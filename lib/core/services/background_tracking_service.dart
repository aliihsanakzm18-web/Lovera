import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../firebase_options.dart';
import '../models/models.dart';
import 'app_settings_service.dart';
import 'device_service.dart';
import 'notification_service.dart';
import 'widget_sync_service.dart';
import 'background_slideshow_service.dart';
import '../localization/app_strings.dart';

/// 7/24 Kesintisiz Arka Plan Canlı Şarj ve Konum Servisi (Snapchat / Life360 Modeli)
/// Uygulama görev yöneticisinden kapatılsa dahi Android Foreground Service olarak
/// arka planda yaşamaya devam eder ve partnerin ekranındaki bilgileri sürekli canlı tutar.
class BackgroundTrackingService {
  static final BackgroundTrackingService _instance = BackgroundTrackingService._();
  factory BackgroundTrackingService() => _instance;
  BackgroundTrackingService._();

  static bool _initialized = false;

  Future<void> initialize() async {
    try {
      final locPerm = await Geolocator.checkPermission();
      if (locPerm != LocationPermission.always && locPerm != LocationPermission.whileInUse) {
        // Konum izni henüz verilmeden location tipinde Foreground Service başlatılamaz (Android 14 kuralı)
        return;
      }

      final service = FlutterBackgroundService();
      if (_initialized) {
        final running = await service.isRunning();
        if (!running) {
          await service.startService();
        }
        return;
      }

      // 1. Bildirim kanalını oluştur
      final AndroidNotificationChannel channel = AndroidNotificationChannel(
        'lovera_live_sync',
        loc('Lovera Canlı Eşleşme', 'Lovera Live Pairing'),
        description: loc('Canlı konum ve pil seviyesi arka plan senkronizasyonu', 'Background live location and battery sync'),
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
          initialNotificationTitle: loc('Lovera · Canlı Bağlantı Aktif 💕', 'Lovera · Live Connection Active 💕'),
          initialNotificationContent: loc('Partnerinle canlı şarj ve konum eşitleniyor', 'Live battery and location syncing with partner'),
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

      final running = await service.isRunning();
      if (!running) {
        await service.startService();
      }

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

      final canShareLocation = prefs.getBool(AppSettingsService.keyShareLocation) ?? true;
      final canShareBattery = prefs.getBool(AppSettingsService.keyShareBattery) ?? true;
      final canShareSpeed = prefs.getBool(AppSettingsService.keyShareSpeed) ?? true;

      final Map<String, dynamic> updateData = {};
      if (canShareBattery && batteryLevel != null) updateData['batteryLevel'] = batteryLevel;
      if (canShareLocation && pos != null) {
        updateData['lat'] = pos.latitude;
        updateData['lng'] = pos.longitude;
        final city = await DeviceService().getCityForLocation(pos.latitude, pos.longitude);
        final weather = await DeviceService().getWeatherForLocation(pos.latitude, pos.longitude);
        if (city != null) updateData['city'] = city;
        if (weather != null) updateData['weather'] = weather;
      }
      if (canShareSpeed && pos != null) {
        updateData['speed'] = (pos.speed >= 0) ? pos.speed : 0.0;
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
  await loadAppLanguageFromPrefs();

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

      final canShareLocation = prefs.getBool(AppSettingsService.keyShareLocation) ?? true;
      final canShareBattery = prefs.getBool(AppSettingsService.keyShareBattery) ?? true;
      final canShareSpeed = prefs.getBool(AppSettingsService.keyShareSpeed) ?? true;
      final canSharePlaces = prefs.getBool(AppSettingsService.keySharePlaces) ?? true;

      final Map<String, dynamic> updateData = {};
      if (canShareBattery && batteryLevel != null) {
        updateData['batteryLevel'] = batteryLevel;
      }
      if (canShareLocation && lat != null && lng != null) {
        updateData['lat'] = lat;
        updateData['lng'] = lng;
      }
      if (canShareSpeed) {
        updateData['speed'] = calculatedSpeed >= 0 ? calculatedSpeed : 0.0;
      }
      if (canShareLocation && weather != null && weather.isNotEmpty) {
        updateData['weather'] = weather;
      }
      if (canShareLocation && city != null && city.isNotEmpty) {
        updateData['city'] = city;
      }
      if (canSharePlaces) {
        updateData['currentPlaceTitle'] = currentMatchedPlace?.title ?? '';
        updateData['currentPlaceEmoji'] = currentMatchedPlace?.iconEmoji ?? '';
      }
      // Arka planda sunucuya ulaşıp veri eşitlediğimiz anı damgalıyoruz (lastActive'i bozmadan internet varlığını doğrular)
      updateData['lastNetPing'] = FieldValue.serverTimestamp();
      // NOT: lastActive burada güncellenmemeli! Kullanıcı uygulamayı açmadığı veya ekran başında olmadığı sürece
      // arka plan GPS veya şarj kontrolleri partnerin son aktiflik saatini 'şimdi aktif' veya '1 dk önce' yapmamalıdır.

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
      if (canSharePlaces && canShareLocation && lat != null && lng != null && coupleId != null && coupleId.isNotEmpty) {
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
                  final titleTr = '$placeEmoji $myName Konuma Ulaştı';
                  final titleEn = '$placeEmoji $myName Arrived at Location';
                  final bodyTr = '$myName "$placeTitle" konumuna vardı. 💕';
                  final bodyEn = '$myName arrived at "${localizePlaceTitle(placeTitle)}". 💕';
                  NotificationService().sendPushToPartner(
                    partnerUid: partnerUid,
                    title: loc(titleTr, titleEn),
                    body: loc(bodyTr, bodyEn),
                    titleTr: titleTr,
                    titleEn: titleEn,
                    bodyTr: bodyTr,
                    bodyEn: bodyEn,
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
                    final titleTr = '🚶 $myName Konumdan Ayrıldı';
                    final titleEn = '🚶 $myName Left Location';
                    final bodyTr = '$myName "$oldTitle" konumundan ayrıldı.';
                    final bodyEn = '$myName left "${localizePlaceTitle(oldTitle)}".';
                    NotificationService().sendPushToPartner(
                      partnerUid: partnerUid,
                      title: loc(titleTr, titleEn),
                      body: loc(bodyTr, bodyEn),
                      titleTr: titleTr,
                      titleEn: titleEn,
                      bodyTr: bodyTr,
                      bodyEn: bodyEn,
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
          title: loc('Lovera · Canlı Bağlantı Aktif 💕', 'Lovera · Live Connection Active 💕'),
          content: '${loc("Şarj", "Battery")}: $batText · $city · ${loc("Canlı eşitleniyor", "Syncing live")}',
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
  int bgTickCounter = 0;
  Timer.periodic(const Duration(seconds: 15), (timer) async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('saved_uid');
    if (uid == null || uid.isEmpty) {
      timer.cancel();
      service.stopSelf();
      return;
    }
    await performLiveSync();

    // Her 30 saniyede bir (2 x 15 sn) veritabanına HİÇ gitmeden yerel saat ile widget sürelerini ilerlet
    bgTickCounter++;
    if (bgTickCounter >= 2) {
      bgTickCounter = 0;
      await WidgetSyncService.updateWidgetFromLocalCache();
    }

    // Uygulama tamamen kapalı olsa bile Widget Slideshow (Otomatik Arka Plan Değişimi) kontrolü:
    try {
      final wCfg = await BackgroundSlideshowService().getConfig('widget');
      if (wCfg.isEnabled) {
        final cId = prefs.getString('saved_couple_id');
        if (cId != null && cId.isNotEmpty) {
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final diffSec = (nowMs - wCfg.lastRotatedAt) / 1000;
          if (diffSec >= wCfg.intervalSeconds || wCfg.lastRotatedAt == 0) {
            // Anıları çekip sıradaki fotoğrafa geçir
            final memsSnap = await FirebaseFirestore.instance
                .collection('couples')
                .doc(cId)
                .collection('memories')
                .orderBy('date', descending: true)
                .get();
            final mems = memsSnap.docs.map((d) => MemoryItem.fromJson(d.data(), d.id)).toList();
            await BackgroundSlideshowService().rotateWidgetSlideshowIfNeeded(mems, force: true);
          }
        }
      }
    } catch (e) {
      debugPrint('[BG-WIDGET-SLIDESHOW-ERR] $e');
    }
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
          language: data['language'] as String?,
        );
        if (data['language'] != null) {
          prefs.setString('cached_partner_language_${doc.id}', data['language'].toString());
        }

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

    // 6. 7/24 Kesintisiz Çizim Dinleyicisi (Uygulama tamamen kapalı olsa dahi Çizim Widget'ını anında günceller)
    final coupleId = prefs.getString('saved_couple_id');
    if (coupleId != null && coupleId.isNotEmpty) {
      FirebaseFirestore.instance
          .collection('couples')
          .doc(coupleId)
          .collection('drawings')
          .doc('latest')
          .snapshots()
          .listen((doc) async {
        if (!doc.exists || doc.data() == null) return;
        try {
          final data = doc.data()!;
          final imageBase64 = data['imageBase64'] as String?;
          final senderName = data['senderName'] as String? ?? 'Partnerin';
          final myName = prefs.getString('saved_user_name') ?? '';
          final isMe = (myName.isNotEmpty && senderName.toLowerCase() == myName.toLowerCase());

          if (imageBase64 != null && imageBase64.isNotEmpty) {
            final raw = imageBase64.split(',').last;
            final bytes = base64Decode(raw);
            final dir = await getApplicationDocumentsDirectory();
            final drawingPath = '${dir.path}/partner_drawing_latest.png';
            final f = File(drawingPath);
            await f.writeAsBytes(bytes);

            int tsMillis = DateTime.now().millisecondsSinceEpoch;
            final rawTs = data['createdAt'] ?? data['timestamp'];
            if (rawTs != null) {
              try {
                if (rawTs is int) {
                  tsMillis = rawTs;
                } else if (rawTs is DateTime) {
                  tsMillis = rawTs.millisecondsSinceEpoch;
                } else if (rawTs is String) {
                  tsMillis = int.tryParse(rawTs) ?? DateTime.tryParse(rawTs)?.millisecondsSinceEpoch ?? tsMillis;
                } else {
                  tsMillis = (rawTs as dynamic).toDate().millisecondsSinceEpoch;
                }
              } catch (_) {}
            } else {
              final existingTs = prefs.getInt('drawing_timestamp_millis');
              if (existingTs != null && existingTs > 0) {
                tsMillis = existingTs;
              }
            }

            final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(tsMillis));
            final minutes = diff.inMinutes.abs();
            final timeAgo = minutes < 1
                ? loc('Şimdi', 'Just now')
                : (minutes < 60 ? loc('$minutes dk önce', '${minutes}m ago') : loc('${diff.inHours.abs()} sa önce', '${diff.inHours.abs()}h ago'));

            await WidgetSyncService.syncDrawingWidget(
              imagePath: drawingPath,
              imageBase64: imageBase64,
              senderName: isMe ? loc('Sen', 'You') : senderName,
              timeAgo: timeAgo,
              timestampMillis: tsMillis,
            );
            debugPrint('[BG-DRAWING-WIDGET-SYNC] Uygulama kapalıyken yeni çizim widget\'a yazıldı: $senderName (isMe=$isMe)');
          }
        } catch (e) {
          debugPrint('[BG-DRAWING-WIDGET-SYNC-ERR] $e');
        }
      }, onError: (e) {
        debugPrint('[BG-DRAWING-STREAM-ERR] $e');
      });
    }
  } catch (e) {
    debugPrint('[BG-PARTNER-SETUP-ERR] $e');
  }
}
