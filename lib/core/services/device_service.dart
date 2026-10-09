import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'database_service.dart';

class DeviceService {
  static final DeviceService _instance = DeviceService._internal();
  factory DeviceService() => _instance;
  DeviceService._internal();

  /// Bu cihaz kurulumuna özel benzersiz oturum / donanım kimliği
  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString('device_session_id');
    if (id == null || id.isEmpty) {
      final rand = Random().nextInt(999999);
      id = 'dev_${DateTime.now().millisecondsSinceEpoch}_$rand';
      await prefs.setString('device_session_id', id);
    }
    return id;
  }

  final Battery _battery = Battery();
  StreamSubscription<Position>? _positionStreamSub;
  StreamSubscription<BatteryState>? _batteryStateSub;
  Timer? _periodicSyncTimer;
  bool _isBackgroundTrackingActive = false;

  // Bellek İçi Akıllı Önbellek (Flicker & Yarış Durumlarını Önler)
  String? _lastCity;
  double? _lastCityLat;
  double? _lastCityLng;

  String? _lastWeather;
  DateTime? _lastWeatherTime;
  double? _lastWeatherLat;
  double? _lastWeatherLng;

  double? _lastSyncedLat;
  double? _lastSyncedLng;

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
    // Eğer önceki konumla mesafe 2 km'den azsa ve kayıtlı şehir varsa önbellekten dön
    if (_lastCity != null && _lastCityLat != null && _lastCityLng != null) {
      final dist = Geolocator.distanceBetween(_lastCityLat!, _lastCityLng!, lat, lng);
      if (dist < 2000) {
        return _lastCity;
      }
    }

    // 1. OpenStreetMap Nominatim
    try {
      final osmUrl = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=10&accept-language=tr',
      );
      final res = await http.get(osmUrl, headers: {
        'User-Agent': 'LoveraCoupleApp/1.0 (contact@lovera.app)',
      }).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final addr = data['address'];
        if (addr != null) {
          final city = addr['province'] ?? addr['city'] ?? addr['state'] ?? addr['town'];
          if (city != null && city.toString().trim().isNotEmpty) {
            final cleanedCity = city.toString().replaceAll(' İli', '').trim();
            _lastCity = cleanedCity;
            _lastCityLat = lat;
            _lastCityLng = lng;
            return cleanedCity;
          }
        }
      }
    } catch (_) {}

    // 2. Fallback (BigDataCloud)
    try {
      final url = Uri.parse(
        'https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$lat&longitude=$lng&localityLanguage=tr',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final city = data['city'] ?? data['principalSubdivision'] ?? data['locality'];
        if (city != null && city.toString().trim().isNotEmpty) {
          final cleanedCity = city.toString().trim();
          _lastCity = cleanedCity;
          _lastCityLat = lat;
          _lastCityLng = lng;
          return cleanedCity;
        }
      }
    } catch (_) {}

    // Servis geçici olarak cevap veremediyse eski şehri koru
    return _lastCity;
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

  /// Cihazın konumuna göre anlık hava durumunu çeker (Open-Meteo ücretsiz API - 20 dk önbellekli)
  Future<String?> getWeatherForLocation(double lat, double lng) async {
    final now = DateTime.now();
    // 20 dakika içinde ve 5 km mesafe değişmemişse API'yi yormadan önbellekten ver
    if (_lastWeather != null &&
        _lastWeatherTime != null &&
        now.difference(_lastWeatherTime!) < const Duration(minutes: 20) &&
        _lastWeatherLat != null &&
        _lastWeatherLng != null) {
      final dist = Geolocator.distanceBetween(_lastWeatherLat!, _lastWeatherLng!, lat, lng);
      if (dist < 5000) {
        return _lastWeather;
      }
    }

    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lng&current=temperature_2m,weather_code,precipitation,is_day&timezone=auto',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final current = data['current'] ?? data['current_weather'];
        if (current != null) {
          final tempVal = current['temperature_2m'] ?? current['temperature'];
          final temp = (tempVal as num).round();
          final code = (current['weather_code'] ?? current['weathercode']) as int? ?? 0;
          final precip = (current['precipitation'] as num?)?.toDouble() ?? 0.0;
          final isNightByHour = now.hour >= 20 || now.hour < 6;
          final isDayApi = (current['is_day'] as int? ?? 1) == 1;
          final isDay = isNightByHour ? false : isDayApi;
          final period = getTimeOfDayPeriod(now);
          final desc = _mapWeatherCode(code, precip: precip, isDay: isDay);
          final weatherStr = '$period · $desc $temp°';

          _lastWeather = weatherStr;
          _lastWeatherTime = now;
          _lastWeatherLat = lat;
          _lastWeatherLng = lng;
          return weatherStr;
        }
      }
    } catch (_) {
      // Şebeke yoksa veya API sınırladıysa eski hava durumunu koru
    }
    return _lastWeather;
  }

  String _mapWeatherCode(int code, {required double precip, required bool isDay}) {
    // Hafif nem/çisenti (0.1 - 0.4 mm) durumunda gökyüzü açıksa doğrudan Sağanak deme!
    if (code >= 80 && code <= 82 && precip < 0.5) {
      return isDay ? 'Parçalı Bulutlu' : 'Açık';
    }
    if (code == 0) return isDay ? 'Güneşli' : 'Açık';
    if (code >= 1 && code <= 3) return isDay ? 'Parçalı Bulutlu' : 'Bulutlu';
    if (code >= 45 && code <= 48) return 'Sisli';
    if (code >= 51 && code <= 55) return 'Çisenti';
    if (code >= 56 && code <= 67) return 'Yağmurlu';
    if (code >= 71 && code <= 77) return 'Karlı';
    if (code >= 80 && code <= 82) return precip > 1.5 ? 'Sağanak Yağışlı' : 'Hafif Yağmurlu';
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
          distanceFilter: 10, // 10 metre: Gereksiz quota tüketimini ve titremeyi önler
          intervalDuration: const Duration(seconds: 5),
        );
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.high,
          activityType: ActivityType.other,
          distanceFilter: 10,
          allowBackgroundLocationUpdates: true,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 25,
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

      // Pil durumu (şarja takma, çıkarma) değiştiğinde hemen Firebase'e aktar
      await _batteryStateSub?.cancel();
      _batteryStateSub = _battery.onBatteryStateChanged.listen((_) {
        syncStatusToFirebase();
      });

      // Ayrıca düzenli olarak 90 saniyede bir gönder
      _periodicSyncTimer?.cancel();
      _periodicSyncTimer = Timer.periodic(const Duration(seconds: 90), (_) {
        syncStatusToFirebase();
      });

      _isBackgroundTrackingActive = true;
      // İlk açılışta hemen tetikle
      await syncStatusToFirebase();
    } catch (e) {
      debugPrint('startContinuousLocationTracking error: $e');
    }
  }

  DateTime? _lastPosWriteTime;
  double? _lastPosLat;
  double? _lastPosLng;

  List<SavedPlace>? _cachedSavedPlaces;
  DateTime? _cachedSavedPlacesTime;

  /// Kullanıcının o an kayıtlı bir yerde (Ev, İş vb.) olup olmadığını kontrol eder (<= 150m)
  Future<Map<String, String>?> _checkSavedPlaceMatch(double lat, double lng) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? coupleId = prefs.getString('saved_couple_id');
      if (coupleId == null || coupleId.isEmpty) {
        final uid = DatabaseService().uid;
        if (uid != null) {
          final uDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get(const GetOptions(source: Source.serverAndCache))
              .timeout(const Duration(seconds: 4));
          coupleId = uDoc.data()?['coupleId'] as String?;
          if (coupleId != null && coupleId.isNotEmpty) {
            await prefs.setString('saved_couple_id', coupleId);
          }
        }
      }
      if (coupleId == null || coupleId.isEmpty) return null;

      final now = DateTime.now();
      if (_cachedSavedPlaces == null ||
          _cachedSavedPlacesTime == null ||
          now.difference(_cachedSavedPlacesTime!) > const Duration(minutes: 1)) {
        _cachedSavedPlaces = await DatabaseService().getSavedPlaces(coupleId);
        _cachedSavedPlacesTime = now;
      }

      for (final p in (_cachedSavedPlaces ?? [])) {
        final d = Geolocator.distanceBetween(lat, lng, p.lat, p.lng);
        if (d <= 150) { // 150 metre yarıçap içindeyse o mekandadır
          return {
            'title': p.title,
            'emoji': p.iconEmoji,
          };
        }
      }
    } catch (_) {}
    return null;
  }

  /// Yeni GPS konumu alındığında akıllı throttling ile Firebase'e aktarır
  Future<void> _onNewPositionReceived(Position pos) async {
    try {
      final now = DateTime.now();
      if (_lastPosWriteTime != null && now.difference(_lastPosWriteTime!) < const Duration(seconds: 25)) {
        if (_lastSyncedLat != null && _lastSyncedLng != null) {
          final d = Geolocator.distanceBetween(_lastSyncedLat!, _lastSyncedLng!, pos.latitude, pos.longitude);
          if (d < 25) return; // 25 saniye içinde 25 metreden az oynadıysa yazma (Kota koruması)
        }
      }

      // Hız hesaplama veya alma (pos.speed m/s -> pos.speed * 3.6 km/s)
      double calculatedSpeed = pos.speed;
      if (calculatedSpeed <= 0 && _lastPosLat != null && _lastPosLng != null && _lastPosWriteTime != null) {
        final seconds = now.difference(_lastPosWriteTime!).inSeconds;
        if (seconds > 0 && seconds < 60) {
          final distMeters = Geolocator.distanceBetween(_lastPosLat!, _lastPosLng!, pos.latitude, pos.longitude);
          calculatedSpeed = distMeters / seconds;
        }
      }
      _lastPosLat = pos.latitude;
      _lastPosLng = pos.longitude;
      _lastPosWriteTime = now;

      // Kayıtlı bir konumda mı?
      final matchedPlace = await _checkSavedPlaceMatch(pos.latitude, pos.longitude);

      String? placeTitleToSet;
      String? placeEmojiToSet;
      if (matchedPlace != null) {
        placeTitleToSet = matchedPlace['title'];
        placeEmojiToSet = matchedPlace['emoji'];
      } else if (_cachedSavedPlaces != null && _cachedSavedPlaces!.isNotEmpty) {
        final allFar = _cachedSavedPlaces!.every((p) => Geolocator.distanceBetween(pos.latitude, pos.longitude, p.lat, p.lng) > 250);
        if (allFar) {
          placeTitleToSet = '';
          placeEmojiToSet = '';
        }
      }

      await DatabaseService().updateStatus(
        lat: pos.latitude,
        lng: pos.longitude,
        speed: calculatedSpeed >= 0 ? calculatedSpeed : 0.0,
        currentPlaceTitle: placeTitleToSet,
        currentPlaceEmoji: placeEmojiToSet,
        weather: _lastWeather,
        city: _lastCity,
        updateLastActive: true,
      );

      _lastSyncedLat = pos.latitude;
      _lastSyncedLng = pos.longitude;

      // Arka planda sessizce şehir/hava durumunu güncelle
      getCityForLocation(pos.latitude, pos.longitude);
      getWeatherForLocation(pos.latitude, pos.longitude);
    } catch (_) {}
  }

  /// Gerçek cihaz durumunu (Pil, Konum, Şehir, Hava Durumu, Aktiflik) Firebase'e kaydeder
  Future<void> syncStatusToFirebase({bool? isOnline}) async {
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
            pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 5),
            );
          } catch (_) {
            try {
              pos = await Geolocator.getLastKnownPosition();
            } catch (_) {}
          }

          if (pos != null) {
            lat = pos.latitude;
            lng = pos.longitude;
            city = await getCityForLocation(lat, lng);
            weather = await getWeatherForLocation(lat, lng);
          }
        }
      } catch (_) {}

      // Eğer konum alınamadıysa önbellekteki son bilinen değerleri koru, ASLA sabit değer uydurma!
      city ??= _lastCity;
      weather ??= _lastWeather;

      Map<String, String>? matchedPlace;
      if (lat != null && lng != null) {
        matchedPlace = await _checkSavedPlaceMatch(lat, lng);
      }

      String? placeTitleToSet;
      String? placeEmojiToSet;
      if (matchedPlace != null) {
        placeTitleToSet = matchedPlace['title'];
        placeEmojiToSet = matchedPlace['emoji'];
      } else if (_cachedSavedPlaces != null && _cachedSavedPlaces!.isNotEmpty && lat != null && lng != null) {
        final allFar = _cachedSavedPlaces!.every((p) => Geolocator.distanceBetween(lat!, lng!, p.lat, p.lng) > 250);
        if (allFar) {
          placeTitleToSet = '';
          placeEmojiToSet = '';
        }
      }

      await DatabaseService().updateStatus(
        batteryLevel: battery,
        lat: lat,
        lng: lng,
        currentPlaceTitle: placeTitleToSet,
        currentPlaceEmoji: placeEmojiToSet,
        weather: weather,
        city: city,
        isAppOpen: isOnline,
        updateLastActive: true,
      );

      if (lat != null && lng != null) {
        _lastSyncedLat = lat;
        _lastSyncedLng = lng;
      }
    } catch (_) {}
  }

  void stopTracking() {
    _positionStreamSub?.cancel();
    _batteryStateSub?.cancel();
    _periodicSyncTimer?.cancel();
    _positionStreamSub = null;
    _batteryStateSub = null;
    _periodicSyncTimer = null;
    _isBackgroundTrackingActive = false;
    _lastSyncedLat = null;
    _lastSyncedLng = null;
  }
}
