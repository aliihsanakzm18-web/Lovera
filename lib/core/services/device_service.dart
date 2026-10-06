import 'dart:async';
import 'dart:convert';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'database_service.dart';

class DeviceService {
  static final DeviceService _instance = DeviceService._internal();
  factory DeviceService() => _instance;
  DeviceService._internal();

  final Battery _battery = Battery();
  StreamSubscription<Position>? _positionStreamSub;
  Timer? _periodicSyncTimer;
  bool _isBackgroundTrackingActive = false;

  /// Cihazın gerçek pil seviyesini alır (0-100)
  Future<int?> getBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;
      return level;
    } catch (_) {
      return null;
    }
  }

  /// Koordinatlardan şehir / ilçe adını bulur
  Future<String?> getCityForLocation(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$lat&longitude=$lng&localityLanguage=tr',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final city = data['city'] ?? data['principalSubdivision'] ?? data['locality'];
        if (city != null && city.toString().trim().isNotEmpty) {
          return city.toString().trim();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Günün vaktini belirler: Sabah, Öğlen, İkindi, Akşam, Gece
  String getTimeOfDayPeriod(DateTime now) {
    final hour = now.hour;
    if (hour >= 6 && hour < 11) return 'Sabah';
    if (hour >= 11 && hour < 15) return 'Öğlen';
    if (hour >= 15 && hour < 19) return 'İkindi';
    if (hour >= 19 && hour < 23) return 'Akşam';
    return 'Gece';
  }

  /// Cihazın konumuna göre anlık hava durumunu çeker (Open-Meteo ücretsiz API)
  Future<String?> getWeatherForLocation(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lng&current_weather=true',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final current = data['current_weather'];
        if (current != null) {
          final temp = (current['temperature'] as num).round();
          final code = current['weathercode'] as int? ?? 0;
          final now = DateTime.now();
          final isNightByHour = now.hour >= 20 || now.hour < 6;
          final isDayApi = (current['is_day'] as int? ?? 1) == 1;
          final isDay = isNightByHour ? false : isDayApi;
          final period = getTimeOfDayPeriod(now);
          final desc = _mapWeatherCode(code, isDay: isDay);
          return '$period · $desc $temp°';
        }
      }
    } catch (_) {
      // Şebeke yoksa veya gecikirse varsayılan
    }
    return null;
  }

  String _mapWeatherCode(int code, {required bool isDay}) {
    if (code == 0) return isDay ? 'Güneşli' : 'Açık';
    if (code >= 1 && code <= 3) return isDay ? 'Parçalı Bulutlu' : 'Bulutlu';
    if (code >= 45 && code <= 48) return 'Sisli';
    if (code >= 51 && code <= 67) return 'Yağmurlu';
    if (code >= 71 && code <= 77) return 'Karlı';
    if (code >= 80 && code <= 82) return 'Sağanak Yağışlı';
    if (code >= 95) return 'Gök Gürültülü';
    return isDay ? 'Açık' : 'Yıldızlı';
  }

  /// Snap Map tarzı: Uygulama açıkken veya arka plandayken canlı konum, şarj ve hava durumu servisini başlatır
  Future<void> startContinuousLocationTracking() async {
    if (_isBackgroundTrackingActive) return;

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) return;

      late LocationSettings locationSettings;

      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15, // 15 metre hareket ettiğinde anında tetikler
          intervalDuration: const Duration(seconds: 15), // Arka planda 15 sn periyot
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'Lovera · Canlı Bağlantı Aktif',
            notificationText: 'Partnerinle canlı konum, şarj ve hava durumu eşitleniyor 💕',
            enableWakeLock: true,
            setOngoing: true,
          ),
        );
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.high,
          activityType: ActivityType.fitness,
          distanceFilter: 15,
          allowBackgroundLocationUpdates: true,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15,
        );
      }

      await _positionStreamSub?.cancel();
      _positionStreamSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        (position) async {
          await _onNewPositionReceived(position);
        },
        onError: (e) {
          debugPrint('Geolocator stream error: $e');
        },
      );

      // Ayrıca hareket edilmese dahi şarj ve saati düzenli olarak 30 saniyede bir gönder
      _periodicSyncTimer?.cancel();
      _periodicSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        syncStatusToFirebase();
      });

      _isBackgroundTrackingActive = true;
      // İlk açılışta hemen tetikle
      await syncStatusToFirebase();
    } catch (e) {
      debugPrint('startContinuousLocationTracking error: $e');
    }
  }

  /// Yeni GPS konumu alındığında çalışır
  Future<void> _onNewPositionReceived(Position pos) async {
    try {
      final battery = await getBatteryLevel();
      final weather = await getWeatherForLocation(pos.latitude, pos.longitude);
      final city = await getCityForLocation(pos.latitude, pos.longitude);

      await DatabaseService().updateStatus(
        lat: pos.latitude,
        lng: pos.longitude,
        batteryLevel: battery,
        weather: weather,
        city: city,
      );
    } catch (_) {}
  }

  /// Gerçek cihaz durumunu (Pil, Konum, Şehir, Hava Durumu, Aktiflik) Firebase'e kaydeder
  Future<void> syncStatusToFirebase() async {
    try {
      final battery = await getBatteryLevel();

      double? lat;
      double? lng;
      String? weather;
      String? city;

      try {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
          Position? pos;
          try {
            pos = await Geolocator.getLastKnownPosition();
            pos ??= await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.medium,
              timeLimit: const Duration(seconds: 4),
            );
          } catch (_) {}

          if (pos != null) {
            lat = pos.latitude;
            lng = pos.longitude;
            weather = await getWeatherForLocation(lat, lng);
            city = await getCityForLocation(lat, lng);
          }
        }
      } catch (_) {}

      // Fallback hava durumu, şehir ve vakit
      final now = DateTime.now();
      final period = getTimeOfDayPeriod(now);
      final isNight = now.hour >= 20 || now.hour < 6 || period == 'Gece' || period == 'Akşam';
      weather ??= (isNight ? '$period · Yıldızlı 20°' : '$period · Açık 22°');
      if (city == null || city.isEmpty) {
        city = 'İstanbul';
      }

      await DatabaseService().updateStatus(
        batteryLevel: battery,
        lat: lat,
        lng: lng,
        weather: weather,
        city: city,
      );
    } catch (_) {}
  }

  void stopTracking() {
    _positionStreamSub?.cancel();
    _periodicSyncTimer?.cancel();
    _isBackgroundTrackingActive = false;
  }
}
