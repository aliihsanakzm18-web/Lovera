import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' hide Path;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/models.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/device_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';

class LiveMapView extends ConsumerStatefulWidget {
  const LiveMapView({super.key, this.onBackToHome, this.onOpenChat});
  final VoidCallback? onBackToHome;
  final VoidCallback? onOpenChat;

  @override
  ConsumerState<LiveMapView> createState() => _LiveMapViewState();
}

enum _FollowTarget { none, partner, me, navigation }

class _LiveMapViewState extends ConsumerState<LiveMapView> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  AnimationController? _flightController;
  AnimationController? _navTurnController;

  double? _roadDistanceMeters;
  bool _calculatingRoad = false;
  LatLng? _lastRouteStart;
  LatLng? _lastRouteEnd;
  Timer? _mapSyncTimer;
  StreamSubscription? _partnerSub;

  // Anlık Takip (Kamera Kilitleme): Harita serbest kaydırılınca otomatik kapanır
  _FollowTarget _followTarget = _FollowTarget.partner;
  bool get _isNavigating => _followTarget == _FollowTarget.navigation;

  // 60 FPS Pürüzsüz Snap Konum İnterpolasyonu (Kayarak İlerleme)
  AnimationController? _myAnimController;
  AnimationController? _partnerAnimController;
  LatLng? _animatedMyPos;
  LatLng? _animatedPartnerPos;
  LatLng? _targetMyPos;
  LatLng? _targetPartnerPos;

  // Kalıcı Kayıtlı Yerler (Ev, İş, Okul vb.)
  StreamSubscription? _savedPlacesSub;
  List<SavedPlace> _savedPlaces = [];
  bool _hasInitialPartnerFocused = false;

  // Sohbette veya dışarıdan tıklanarak haritada odaklanılan geçici konum pini
  AttachedLocation? _highlightedTargetLocation;
  /// Haritada basılı tutulan (menü açıkken gösterilen) geçici konum
  LatLng? _pressedPoint;
  Timer? _highlightClearTimer;

  // Buluşma rotaları (Ben -> Buluşma Noktası ve Partner -> Buluşma Noktası)
  List<LatLng> _myMeetingRoute = [];
  List<LatLng> _partnerMeetingRoute = [];
  bool _isMeetingTopBannerVisible = false;
  late final AnimationController _meetingBannerController;
  late final Animation<Offset> _meetingBannerSlideAnimation;

  @override
  void initState() {
    super.initState();
    _meetingBannerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _meetingBannerSlideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2), // Yukarıdan başlar
      end: Offset.zero,             // Tam yerine iner
    ).animate(CurvedAnimation(
      parent: _meetingBannerController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
    // Arka planda güvenli durum senkronizasyonu
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeviceService().syncStatusToFirebase();
      _initInitialRoute();
      final targetLoc = ref.read(targetMapFocusLocationProvider);
      if (targetLoc != null) {
        _hasInitialPartnerFocused = true;
        _onTargetLocationRequested(targetLoc);
        ref.read(targetMapFocusLocationProvider.notifier).state = null;
      } else {
        final partner = ref.read(partnerProvider);
        if (partner?.lat != null && partner?.lng != null) {
          _hasInitialPartnerFocused = true;
          _animatedFlightMove(LatLng(partner!.lat!, partner.lng!), 16.0);
        }
      }
      final partnerUid = ref.read(partnerUidProvider);
      if (partnerUid != null && partnerUid.isNotEmpty) {
        _subscribeToPartnerLive(partnerUid);
        NotificationService().requestPartnerStatusSync(partnerUid);
      }
      final coupleId = ref.read(coupleIdProvider);
      if (coupleId != null && coupleId.isNotEmpty) {
        _subscribeToSavedPlaces(coupleId);
      }
    });

    // Sayfa açıkken veya sonradan gelen hedef koordinat isteklerini dinle
    ref.listenManual(targetMapFocusLocationProvider, (prev, next) {
      if (next != null) {
        _onTargetLocationRequested(next);
        ref.read(targetMapFocusLocationProvider.notifier).state = null;
      }
    });

    // Buluşma noktasını dinle ve rotaları hesapla (Kullanıcı butona basana kadar menü otomatik açılmaz)
    ref.listenManual(activeMeetingLocationProvider, (prev, next) {
      if (next != null) {
        _fetchMeetingRoutes(next);
      } else {
        if (mounted) {
          _closeMeetingBanner(clearRoutes: true);
        }
      }
    });

    // Harita açıkken partnerin kapalı cihazını 6 saniyede bir sessiz uyandır ve konumunu tazelet
    _mapSyncTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      final partnerUid = ref.read(partnerUidProvider);
      if (partnerUid != null && partnerUid.isNotEmpty) {
        if (_partnerSub == null) {
          _subscribeToPartnerLive(partnerUid);
        }
        NotificationService().requestPartnerStatusSync(partnerUid);
      }
      final coupleId = ref.read(coupleIdProvider);
      if (coupleId != null && coupleId.isNotEmpty && _savedPlacesSub == null) {
        _subscribeToSavedPlaces(coupleId);
      }
    });
  }

  void _subscribeToSavedPlaces(String coupleId) {
    _savedPlacesSub?.cancel();
    _savedPlacesSub = DatabaseService().savedPlacesStream(coupleId).listen((places) {
      if (mounted) {
        ref.read(savedPlacesProvider.notifier).state = places;
        setState(() {
          _savedPlaces = places;
        });
      }
    });
  }

  void _subscribeToPartnerLive(String partnerUid) {
    _partnerSub?.cancel();
    _partnerSub = DatabaseService().partnerStream(partnerUid).listen((doc) {
      if (!doc.exists || doc.data() == null || !mounted) return;
      final data = doc.data()!;
      final double? newLat = (data['lat'] as num?)?.toDouble();
      final double? newLng = (data['lng'] as num?)?.toDouble();

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
        name: data['name'] ?? ref.read(partnerProvider)?.name ?? 'Partnerin',
        avatarUrl: data['avatarUrl'] ?? ref.read(partnerProvider)?.avatarUrl,
        batteryLevel: data['batteryLevel'] as int?,
        weather: data['weather'] as String?,
        city: data['city'] as String?,
        lat: newLat,
        lng: newLng,
        lastActive: parsedLastActive ?? DateTime.now(),
        coupleId: data['coupleId'],
        isAppOpen: data['isAppOpen'] as bool?,
        birthDate: data['birthDate'] as String?,
        speed: (data['speed'] as num?)?.toDouble(),
        currentPlaceTitle: data['currentPlaceTitle'] as String?,
        currentPlaceEmoji: data['currentPlaceEmoji'] as String?,
      );

      ref.read(partnerProvider.notifier).state = partnerUser;

      if (newLat != null && newLng != null) {
        final newPartnerLatLng = LatLng(newLat, newLng);
        _smoothAnimatePartnerPos(newPartnerLatLng);
        if (!_hasInitialPartnerFocused && _highlightedTargetLocation == null) {
          _hasInitialPartnerFocused = true;
          _animatedFlightMove(newPartnerLatLng, 16.0);
        }
      }
    });
  }

  void _initInitialRoute() {
    final user = ref.read(currentUserProvider);
    final partner = ref.read(partnerProvider);
    if (user?.lat != null && user?.lng != null && partner?.lat != null && partner?.lng != null) {
      final my = LatLng(user!.lat!, user.lng!);
      final part = LatLng(partner!.lat!, partner.lng!);
      _checkAndFetchRoute(my, part);
    }
  }

  DateTime? _lastPartnerPosTime;
  DateTime? _lastMyPosTime;

  void _smoothAnimateMyPos(LatLng newTarget) {
    final now = DateTime.now();
    if (_animatedMyPos == null) {
      _animatedMyPos = newTarget;
      _targetMyPos = newTarget;
      _lastMyPosTime = now;
      return;
    }
    if (_targetMyPos?.latitude == newTarget.latitude &&
        _targetMyPos?.longitude == newTarget.longitude) {
      return;
    }

    final from = _animatedMyPos!;
    final double elapsedSec = _lastMyPosTime != null
        ? (now.difference(_lastMyPosTime!).inMilliseconds / 1000.0).clamp(0.5, 3.0)
        : 1.0;
    _lastMyPosTime = now;

    // Hedefe giderken duraksamadan sürekli akması için süreyi gelen veri hızına uyarla (800-1200ms)
    final int animDurationMs = (elapsedSec * 1050).round().clamp(600, 1500);

    _targetMyPos = newTarget;
    final ctrl = _myAnimController;
    if (ctrl != null && ctrl.isAnimating) {
      ctrl.stop();
    }
    _myAnimController?.dispose();
    final newCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: animDurationMs),
    );
    _myAnimController = newCtrl;
    newCtrl.addListener(() {
      if (!mounted) return;
      final t = newCtrl.value;
      final currentPos = LatLng(
        from.latitude + (newTarget.latitude - from.latitude) * t,
        from.longitude + (newTarget.longitude - from.longitude) * t,
      );
      setState(() {
        _animatedMyPos = currentPos;
      });

      // Navigasyon Modu (Google Maps): Kamera kullanıcıya kilitli ve gidiş yönüne dönük akar
      if (_followTarget == _FollowTarget.navigation && (_flightController == null || !_flightController!.isAnimating)) {
        final double? roadHeading = _calculateNavigationHeading(currentPos);
        if (roadHeading != null) {
          _animateCameraTurnTo(roadHeading, center: currentPos, zoom: 18.2);
        } else {
          _mapController.move(currentPos, _mapController.camera.zoom);
        }
      } else if (_followTarget == _FollowTarget.me && (_flightController == null || !_flightController!.isAnimating)) {
        // Normal kullanıcı takibi
        _mapController.move(currentPos, _mapController.camera.zoom);
      }
    });
    newCtrl.forward().then((_) {
      if (mounted) {
        setState(() {
          _animatedMyPos = newTarget;
        });
        if (_followTarget == _FollowTarget.navigation && (_flightController == null || !_flightController!.isAnimating)) {
          final double? roadHeading = _calculateNavigationHeading(newTarget);
          if (roadHeading != null) {
            _animateCameraTurnTo(roadHeading, center: newTarget, zoom: 18.2);
          } else {
            _mapController.move(newTarget, _mapController.camera.zoom);
          }
        } else if (_followTarget == _FollowTarget.me && (_flightController == null || !_flightController!.isAnimating)) {
          _mapController.move(newTarget, _mapController.camera.zoom);
        }
      }
    });
  }

  /// Kullanıcının önündeki rota segmentinin açısını (kerteriz/bearing) hesaplar (0-360 derece)
  double _calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * (math.pi / 180.0);
    final lon1 = from.longitude * (math.pi / 180.0);
    final lat2 = to.latitude * (math.pi / 180.0);
    final lon2 = to.longitude * (math.pi / 180.0);
    final dLon = lon2 - lon1;

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final radians = math.atan2(y, x);
    final degrees = (radians * (180.0 / math.pi) + 360.0) % 360.0;
    return degrees;
  }

  /// Navigasyon esnasında kullanıcının rotada ilerlediği yönün açısını bulur
  double? _calculateNavigationHeading(LatLng userPos) {
    if (_myMeetingRoute.length < 2) {
      final activeMeeting = ref.read(activeMeetingLocationProvider);
      if (activeMeeting != null) {
        return _calculateBearing(userPos, LatLng(activeMeeting.lat, activeMeeting.lng));
      }
      return null;
    }

    // Rotadaki en yakın noktayı bul
    int closestIdx = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < _myMeetingRoute.length; i++) {
      final pt = _myMeetingRoute[i];
      final d = Geolocator.distanceBetween(userPos.latitude, userPos.longitude, pt.latitude, pt.longitude);
      if (d < minDistance) {
        minDistance = d;
        closestIdx = i;
      }
    }

    // Önümüzdeki 15-40 metre ilerideki rota noktasını hedef alarak virajları ve açıyı yumuşak süz
    int forwardIdx = closestIdx + 1;
    double accumulatedDist = 0;
    while (forwardIdx < _myMeetingRoute.length) {
      accumulatedDist += Geolocator.distanceBetween(
        _myMeetingRoute[forwardIdx - 1].latitude,
        _myMeetingRoute[forwardIdx - 1].longitude,
        _myMeetingRoute[forwardIdx].latitude,
        _myMeetingRoute[forwardIdx].longitude,
      );
      if (accumulatedDist >= 15.0 || forwardIdx == _myMeetingRoute.length - 1) {
        break;
      }
      forwardIdx++;
    }

    if (forwardIdx < _myMeetingRoute.length) {
      return _calculateBearing(userPos, _myMeetingRoute[forwardIdx]);
    } else {
      return _calculateBearing(_myMeetingRoute[math.max(0, _myMeetingRoute.length - 2)], _myMeetingRoute.last);
    }
  }

  /// Kamerayı Google Maps gibi gidiş yönüne doğru akıcı bir şekilde döndürür
  void _animateCameraTurnTo(double targetHeading, {LatLng? center, double? zoom}) {
    final curHeading = _mapController.camera.rotation;
    final curCenter = center ?? _mapController.camera.center;
    final curZoom = zoom ?? _mapController.camera.zoom;

    // En kısa açı farkını hesapla (-180 ile +180 derece arası)
    double diff = (targetHeading - curHeading) % 360.0;
    if (diff > 180.0) diff -= 360.0;
    if (diff < -180.0) diff += 360.0;

    // Eğer açı farkı 1.5 dereceden azsa gereksiz animasyon tetikleme
    if (diff.abs() < 1.5) {
      _mapController.moveAndRotate(curCenter, curZoom, curHeading);
      return;
    }

    _navTurnController?.stop();
    _navTurnController?.dispose();
    final turnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _navTurnController = turnCtrl;

    final startAngle = curHeading;

    turnCtrl.addListener(() {
      if (!mounted) return;
      final t = Curves.easeOutQuad.transform(turnCtrl.value);
      final angle = (startAngle + diff * t) % 360.0;
      _mapController.moveAndRotate(curCenter, curZoom, angle);
    });

    turnCtrl.forward();
  }

  /// Google Maps Navigasyon Modunu Başlat: Kullanıcıya yakınlaşır, kamerayı gidiş yoluna çevirir
  Future<void> _startGoogleMapsNavigation(AttachedLocation meetingLoc) async {
    HapticFeedback.heavyImpact();
    final dest = LatLng(meetingLoc.lat, meetingLoc.lng);
    final my = _animatedMyPos ?? (ref.read(currentUserProvider)?.lat != null && ref.read(currentUserProvider)?.lng != null
        ? LatLng(ref.read(currentUserProvider)!.lat!, ref.read(currentUserProvider)!.lng!)
        : null);

    if (my == null) return;

    // Eğer rota henüz çekilmediyse önce çek
    if (_myMeetingRoute.isEmpty) {
      await _fetchMeetingRoutes(meetingLoc);
    }

    final double initialHeading = _calculateNavigationHeading(my) ?? _calculateBearing(my, dest);

    setState(() {
      _followTarget = _FollowTarget.navigation;
    });

    // Uçuş ve dönüş animasyonu ile tepe irtifasından Google Maps sürüş bakış açısına (Zoom: 18.2) in
    _flightController?.stop();
    _flightController?.dispose();

    final LatLng startLoc = _mapController.camera.center;
    final double startZoom = _mapController.camera.zoom;
    final double startRotation = _mapController.camera.rotation;

    double diffRot = (initialHeading - startRotation) % 360.0;
    if (diffRot > 180.0) diffRot -= 360.0;
    if (diffRot < -180.0) diffRot += 360.0;

    final navFlightCtrl = AnimationController(
      duration: const Duration(milliseconds: 750),
      vsync: this,
    );
    _flightController = navFlightCtrl;

    navFlightCtrl.addListener(() {
      if (!mounted) return;
      final t = Curves.easeInOutCubicEmphasized.transform(navFlightCtrl.value);
      final curLat = startLoc.latitude + (my.latitude - startLoc.latitude) * t;
      final curLng = startLoc.longitude + (my.longitude - startLoc.longitude) * t;
      final curZoom = startZoom + (18.2 - startZoom) * t;
      final curRot = (startRotation + diffRot * t) % 360.0;

      _mapController.moveAndRotate(LatLng(curLat, curLng), curZoom, curRot);
    });

    navFlightCtrl.forward();
  }

  /// Navigasyon modunu kapatıp pusulayı kuzeye (0 derece) sıfırlar
  void _resetCompassToNorth() {
    HapticFeedback.lightImpact();
    final curCenter = _mapController.camera.center;
    final curZoom = _mapController.camera.zoom;
    _animateCameraTurnTo(0.0, center: curCenter, zoom: curZoom);
    if (_followTarget == _FollowTarget.navigation) {
      setState(() {
        _followTarget = _FollowTarget.me;
      });
    }
  }

  void _smoothAnimatePartnerPos(LatLng newTarget) {
    final now = DateTime.now();
    if (_animatedPartnerPos == null) {
      _animatedPartnerPos = newTarget;
      _targetPartnerPos = newTarget;
      _lastPartnerPosTime = now;
      if (_followTarget == _FollowTarget.partner && _highlightedTargetLocation == null && (_flightController == null || !_flightController!.isAnimating)) {
        _mapController.move(newTarget, _mapController.camera.zoom);
      }
      return;
    }
    if (_targetPartnerPos?.latitude == newTarget.latitude &&
        _targetPartnerPos?.longitude == newTarget.longitude) {
      return;
    }

    final from = _animatedPartnerPos!;
    final double elapsedSec = _lastPartnerPosTime != null
        ? (now.difference(_lastPartnerPosTime!).inMilliseconds / 1000.0).clamp(0.5, 3.0)
        : 1.0;
    _lastPartnerPosTime = now;

    // Gelen iki koordinat arasındaki zamana göre kesintisiz akış süresi belirle
    final int animDurationMs = (elapsedSec * 1100).round().clamp(700, 1600);

    _targetPartnerPos = newTarget;
    final ctrl = _partnerAnimController;
    if (ctrl != null && ctrl.isAnimating) {
      ctrl.stop();
    }
    _partnerAnimController?.dispose();
    final newCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: animDurationMs),
    );
    _partnerAnimController = newCtrl;
    newCtrl.addListener(() {
      if (!mounted) return;
      final t = newCtrl.value;
      final currentPos = LatLng(
        from.latitude + (newTarget.latitude - from.latitude) * t,
        from.longitude + (newTarget.longitude - from.longitude) * t,
      );
      setState(() {
        _animatedPartnerPos = currentPos;
      });
      // Eğer kullanıcı partneri kilitlediyse kamera partner hareket ettikçe onu canlı takip etsin
      if (_followTarget == _FollowTarget.partner && _highlightedTargetLocation == null && (_flightController == null || !_flightController!.isAnimating)) {
        _mapController.move(currentPos, _mapController.camera.zoom);
      }
    });
    newCtrl.forward().then((_) {
      if (mounted) {
        setState(() {
          _animatedPartnerPos = newTarget;
        });
        if (_followTarget == _FollowTarget.partner && _highlightedTargetLocation == null && (_flightController == null || !_flightController!.isAnimating)) {
          _mapController.move(newTarget, _mapController.camera.zoom);
        }
      }
    });
  }

  void _onTargetLocationRequested(AttachedLocation targetLoc) {
    debugPrint('[TARGET-FOCUS] istek: ${targetLoc.lat}, ${targetLoc.lng} (${targetLoc.title})');
    setState(() {
      _hasInitialPartnerFocused = true;
      _followTarget = _FollowTarget.none;
      _highlightedTargetLocation = targetLoc;
    });
    _highlightClearTimer?.cancel();
    _highlightClearTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) {
        setState(() => _highlightedTargetLocation = null);
      }
    });
    final dest = LatLng(targetLoc.lat, targetLoc.lng);
    // Sayfa geçiş animasyonu (380ms) bittikten sonra hedefe uç; partner takibi bu sırada kapalı
    _flightController?.stop();
    Future.delayed(const Duration(milliseconds: 450), () {
      if (!mounted || _highlightedTargetLocation?.lat != targetLoc.lat) return;
      _followTarget = _FollowTarget.none;
      _animatedFlightMove(dest, 17.0);
      // Uçuş sonunda kesin olarak hedefe sabitle
      Future.delayed(const Duration(milliseconds: 750), () {
        if (!mounted || _highlightedTargetLocation?.lat != targetLoc.lat) return;
        if (_followTarget == _FollowTarget.none) {
          _mapController.move(dest, 17.0);
        }
      });
    });
  }

  @override
  void dispose() {
    _highlightClearTimer?.cancel();
    _savedPlacesSub?.cancel();
    _partnerSub?.cancel();
    _mapSyncTimer?.cancel();
    _flightController?.stop();
    _flightController?.dispose();
    _navTurnController?.stop();
    _navTurnController?.dispose();
    _myAnimController?.dispose();
    _partnerAnimController?.dispose();
    _meetingBannerController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _openMeetingBanner() {
    if (!mounted) return;
    setState(() {
      _isMeetingTopBannerVisible = true;
    });
    _meetingBannerController.forward(from: 0.0);
  }

  void _closeMeetingBanner({bool clearRoutes = false}) {
    if (!mounted) return;
    _meetingBannerController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _isMeetingTopBannerVisible = false;
          if (clearRoutes) {
            _myMeetingRoute = [];
            _partnerMeetingRoute = [];
          }
        });
      }
    });
  }

  /// Snap Map Akıcı Uçuş Animasyonu:
  /// Havalanır, tepe irtifasına çıkar, hedefe süzülür ve yumuşakça iniş yapar (60 FPS)
  void _animatedFlightMove(LatLng destLocation, double targetZoom, [int attempt = 0]) {
    _flightController?.stop();
    _flightController?.dispose();
    _flightController = null;

    final LatLng startLoc;
    final double startZoom;
    try {
      startLoc = _mapController.camera.center;
      startZoom = _mapController.camera.zoom;
    } catch (_) {
      // FlutterMap henüz ilk kez çizilmedi: hazır olana kadar bekle ve tekrar dene
      if (attempt < 30 && mounted) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _animatedFlightMove(destLocation, targetZoom, attempt + 1);
        });
      }
      return;
    }

    final distMeters = Geolocator.distanceBetween(
      startLoc.latitude,
      startLoc.longitude,
      destLocation.latitude,
      destLocation.longitude,
    );

    // Mesafeye göre tepe irtifası
    final double apexZoom = distMeters > 50000 ? 7.5 : (startZoom < targetZoom ? startZoom - 1.2 : targetZoom - 1.2);

    final controller = AnimationController(
      duration: Duration(milliseconds: distMeters > 50000 ? 950 : 650),
      vsync: this,
    );
    _flightController = controller;

    final Animation<double> curve = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubicEmphasized,
    );

    controller.addListener(() {
      if (!mounted) return;
      final t = curve.value;
      final currentLat = startLoc.latitude + (destLocation.latitude - startLoc.latitude) * t;
      final currentLng = startLoc.longitude + (destLocation.longitude - startLoc.longitude) * t;

      double currentZoom;
      if (t < 0.5) {
        final upT = t * 2.0;
        currentZoom = startZoom + (apexZoom - startZoom) * Curves.easeOutQuad.transform(upT);
      } else {
        final downT = (t - 0.5) * 2.0;
        currentZoom = apexZoom + (targetZoom - apexZoom) * Curves.easeInQuad.transform(downT);
      }

      _mapController.move(LatLng(currentLat, currentLng), currentZoom);
    });

    controller.forward();
  }

  Future<void> _fetchMeetingRoutes(AttachedLocation meetingLoc) async {
    final dest = LatLng(meetingLoc.lat, meetingLoc.lng);
    final my = _animatedMyPos ?? (ref.read(currentUserProvider)?.lat != null && ref.read(currentUserProvider)?.lng != null
        ? LatLng(ref.read(currentUserProvider)!.lat!, ref.read(currentUserProvider)!.lng!)
        : null);

    if (my != null) {
      final myRoute = await _fetchPolyline(my, dest);
      if (mounted) {
        setState(() {
          _myMeetingRoute = myRoute;
          _partnerMeetingRoute = [];
        });
      }
    }
  }

  /// Kullanıcının kendi konumundan buluşma noktasına olan rotasını ekrana sığdırıp yakınlaştırır
  void _fitBothMeetingRoutes(AttachedLocation meetingLoc) {
    HapticFeedback.selectionClick();
    _fetchMeetingRoutes(meetingLoc);

    final dest = LatLng(meetingLoc.lat, meetingLoc.lng);
    final my = _animatedMyPos ?? (ref.read(currentUserProvider)?.lat != null && ref.read(currentUserProvider)?.lng != null
        ? LatLng(ref.read(currentUserProvider)!.lat!, ref.read(currentUserProvider)!.lng!)
        : null);

    final List<LatLng> pointsToFit = [];
    if (_myMeetingRoute.isNotEmpty) {
      pointsToFit.addAll(_myMeetingRoute);
    } else {
      pointsToFit.add(dest);
      if (my != null) pointsToFit.add(my);
    }

    if (pointsToFit.length > 1) {
      final bounds = LatLngBounds.fromPoints(pointsToFit);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.only(left: 45, right: 45, top: 150, bottom: 200),
        ),
      );
    } else {
      _animatedFlightMove(dest, 16.5);
    }
  }

  Future<List<LatLng>> _fetchPolyline(LatLng start, LatLng end) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final geometry = routes[0]['geometry'];
          if (geometry is Map && geometry['coordinates'] is List) {
            final coords = geometry['coordinates'] as List;
            return coords
                .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
                .toList();
          }
        }
      }
    } catch (_) {}
    return [start, end]; // Fallback düz çizgi
  }

  void _checkAndFetchRoute(LatLng my, LatLng partner) {
    if (_lastRouteStart?.latitude == my.latitude &&
        _lastRouteStart?.longitude == my.longitude &&
        _lastRouteEnd?.latitude == partner.latitude &&
        _lastRouteEnd?.longitude == partner.longitude) {
      return;
    }
    _lastRouteStart = my;
    _lastRouteEnd = partner;
    _fetchRoadDistance(my, partner);
  }

  Future<void> _fetchRoadDistance(LatLng start, LatLng end) async {
    if (_calculatingRoad) return;
    _calculatingRoad = true;

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=false',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final dist = (routes[0]['distance'] as num?)?.toDouble();
          if (dist != null && mounted) {
            setState(() {
              _roadDistanceMeters = dist;
            });
          }
        }
      }
    } catch (_) {
      // Hata olursa fallback düz çizgi çarpanı gösterilmeye devam eder
    } finally {
      if (mounted) {
        _calculatingRoad = false;
      }
    }
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} metre';
    } else {
      final km = meters / 1000;
      return '${km.toStringAsFixed(1)} km';
    }
  }

  /// Partnere belirli bir konum için buluşma talebi gönderir (kapalı olsa da bildirim düşer).
  Future<void> _sendMeetingRequest(LatLng point, String title) async {
    final partnerUid = ref.read(partnerUidProvider);
    if (partnerUid == null || partnerUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Buluşma talebi için partnerinizle eşleşmiş olmanız gerekir.'),
          backgroundColor: LoveraColors.primary,
        ),
      );
      return;
    }
    final myName = ref.read(userNameProvider);
    final name = myName.isNotEmpty ? myName : 'Partnerin';
    try {
      await DatabaseService().sendMeetingRequest(
        partnerUid: partnerUid,
        fromName: name,
        lat: point.latitude,
        lng: point.longitude,
        placeTitle: title,
      );
      NotificationService().sendPushToPartner(
        partnerUid: partnerUid,
        title: 'Buluşma talebi 💕',
        body: '$name seni "$title" konumunda buluşmaya çağırıyor.',
        data: {'type': 'meeting_request'},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Buluşma talebi gönderildi 💌'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Buluşma talebi gönderilemedi, tekrar dene.')),
        );
      }
    }
  }
  // Yeni Konum Etiketleme / Kaydetme Diyaloğu
  void _showAddPlaceDialog(LatLng point) {
    final coupleId = ref.read(coupleIdProvider);
    final myName = ref.read(userNameProvider);

    if (coupleId == null || coupleId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Konum kaydedebilmek için partnerinizle eşleşmiş olmanız gerekir.'),
          backgroundColor: LoveraColors.primary,
        ),
      );
      return;
    }

    final titleController = TextEditingController();
    String selectedCategory = 'home';
    String selectedEmoji = '🏠';

    final categories = [
      {'key': 'home', 'label': 'Evim', 'emoji': '🏠'},
      {'key': 'work', 'label': 'İş / Ofis', 'emoji': '💼'},
      {'key': 'school', 'label': 'Okul', 'emoji': '🏫'},
      {'key': 'campus', 'label': 'Kampüs', 'emoji': '🎓'},
      {'key': 'gym', 'label': 'Spor Salonu', 'emoji': '🏋️'},
      {'key': 'cafe', 'label': 'Favori Kafe', 'emoji': '☕'},
      {'key': 'favorite', 'label': 'Özel Yerimiz', 'emoji': '💖'},
      {'key': 'other', 'label': 'Diğer', 'emoji': '📍'},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E212B) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: LoveraColors.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Text(selectedEmoji, style: const TextStyle(fontSize: 24)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Konum Etiketle',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : const Color(0xFF1E2024),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Bu konum haritanızda kalıcı olarak görünecektir.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white60 : LoveraColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Koordinat Bilgisi & Tek Tıkla Kopyala / Mesajla Yanıtla Kutusu
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF282C3A) : const Color(0xFFF1F3F7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.pin_drop_rounded,
                          size: 18,
                          color: LoveraColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                              color: isDark ? Colors.white70 : const Color(0xFF2C303E),
                            ),
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            final coordStr = '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
                            Clipboard.setData(ClipboardData(text: coordStr));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Koordinatlar panoya kopyalandı: $coordStr'),
                                duration: const Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: LoveraColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.copy_rounded, size: 13, color: LoveraColors.primary),
                                const SizedBox(width: 3),
                                Text(
                                  'Kopyala',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: LoveraColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            Navigator.pop(ctx);
                            HapticFeedback.selectionClick();
                            final chosenTitle = titleController.text.trim().isNotEmpty
                                ? '$selectedEmoji ${titleController.text.trim()}'
                                : '$selectedEmoji Konum';
                            ref.read(pendingChatLocationAttachmentProvider.notifier).state = AttachedLocation(
                              lat: point.latitude,
                              lng: point.longitude,
                              title: chosenTitle,
                            );
                            ref.read(pendingChatInputTextProvider.notifier).state = '';
                            if (widget.onOpenChat != null) {
                              widget.onOpenChat!();
                            } else {
                              ref.read(activeNavigationIndexProvider.notifier).state = 2;
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.chat_bubble_outline_rounded, size: 13, color: Color(0xFF10B981)),
                                SizedBox(width: 3),
                                Text(
                                  'Yanıtla',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Kategori / İkon Seçimi
                  const Text(
                    'Kategori Seçin',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: categories.map((cat) {
                        final isSelected = selectedCategory == cat['key'];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              setSheetState(() {
                                selectedCategory = cat['key']!;
                                selectedEmoji = cat['emoji']!;
                                if (titleController.text.isEmpty ||
                                    categories.any((c) => c['label'] == titleController.text)) {
                                  titleController.text = cat['label']!;
                                }
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? LoveraColors.primary
                                    : (isDark ? const Color(0xFF282C3A) : const Color(0xFFF1F3F7)),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? LoveraColors.primary
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(cat['emoji']!, style: const TextStyle(fontSize: 16)),
                                  const SizedBox(width: 6),
                                  Text(
                                    cat['label']!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: isSelected
                                          ? Colors.white
                                          : (isDark ? Colors.white70 : const Color(0xFF2C303E)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Özel İsim / Başlık
                  TextField(
                    controller: titleController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Konum Adı',
                      hintText: 'Örn: Evim, Aşkımın Evi, Ofisim...',
                      filled: true,
                      fillColor: isDark ? const Color(0xFF282C3A) : const Color(0xFFF6F8FB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.edit_location_alt_rounded),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Kaydet Butonu
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: LoveraColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        final title = titleController.text.trim();
                        final finalTitle = title.isNotEmpty
                            ? title
                            : categories.firstWhere((c) => c['key'] == selectedCategory)['label']!;

                        Navigator.pop(ctx);
                        await DatabaseService().addSavedPlace(
                          coupleId: coupleId,
                          title: finalTitle,
                          category: selectedCategory,
                          iconEmoji: selectedEmoji,
                          lat: point.latitude,
                          lng: point.longitude,
                          createdByName: myName.isNotEmpty ? myName : 'Ben',
                        );

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('"$finalTitle" haritaya kalıcı olarak eklendi! ✨'),
                              backgroundColor: const Color(0xFF10B981),
                            ),
                          );
                        }
                      },
                      child: const Text(
                        'Konumu Haritaya Kaydet',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        side: BorderSide(color: LoveraColors.primary.withValues(alpha: 0.5)),
                      ),
                      icon: Icon(Icons.favorite_rounded, color: LoveraColors.primary, size: 18),
                      label: Text(
                        'Buluşma Talebi Gönder',
                        style: TextStyle(color: LoveraColors.primary, fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                      onPressed: () {
                        final typed = titleController.text.trim();
                        final meetTitle = typed.isNotEmpty ? '$selectedEmoji $typed' : '💖 Buluşma Noktası';
                        Navigator.pop(ctx);
                        HapticFeedback.selectionClick();
                        _sendMeetingRequest(point, meetTitle);
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      if (mounted) setState(() => _pressedPoint = null);
    });
  }

  // Kayıtlı Konumu Düzenleme Penceresi
  void _showEditPlaceDialog(SavedPlace place) {
    final coupleId = ref.read(coupleIdProvider);
    if (coupleId == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final categories = [
      {'key': 'home', 'label': 'Evim', 'emoji': '🏠'},
      {'key': 'partner_home', 'label': 'Aşkımın Evi', 'emoji': '🏡'},
      {'key': 'work', 'label': 'İş / Ofis', 'emoji': '💼'},
      {'key': 'school', 'label': 'Okul', 'emoji': '📚'},
      {'key': 'campus', 'label': 'Kampüs', 'emoji': '🎓'},
      {'key': 'cafe', 'label': 'Kafe / Buluşma', 'emoji': '☕'},
      {'key': 'park', 'label': 'Park / Sahil', 'emoji': '🌳'},
      {'key': 'favorite', 'label': 'Özel Yerimiz', 'emoji': '❤️'},
    ];

    String selectedCategory = place.category;
    String selectedEmoji = place.iconEmoji;
    final titleController = TextEditingController(text: place.title);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E212B) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: LoveraColors.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Text(selectedEmoji, style: const TextStyle(fontSize: 24)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Konumu Düzenle',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : const Color(0xFF1E2024),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'İsmini veya simgesini güncelleyin.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white60 : LoveraColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  const Text(
                    'Kategori Seçin',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: categories.map((cat) {
                        final isSelected = selectedCategory == cat['key'];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              setSheetState(() {
                                selectedCategory = cat['key']!;
                                selectedEmoji = cat['emoji']!;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? LoveraColors.primary
                                    : (isDark ? const Color(0xFF282C3A) : const Color(0xFFF1F3F7)),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected ? LoveraColors.primary : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(cat['emoji']!, style: const TextStyle(fontSize: 16)),
                                  const SizedBox(width: 6),
                                  Text(
                                    cat['label']!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: isSelected
                                          ? Colors.white
                                          : (isDark ? Colors.white70 : const Color(0xFF2C303E)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: titleController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Konum Adı',
                      filled: true,
                      fillColor: isDark ? const Color(0xFF282C3A) : const Color(0xFFF6F8FB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.edit_location_alt_rounded),
                    ),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: LoveraColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        final title = titleController.text.trim();
                        final finalTitle = title.isNotEmpty ? title : place.title;

                        Navigator.pop(ctx);
                        if (place.id == 'active_meeting') {
                          await DatabaseService().updateActiveMeeting(
                            coupleId: coupleId,
                            title: finalTitle,
                            iconEmoji: selectedEmoji,
                          );
                        } else {
                          await DatabaseService().updateSavedPlace(
                            coupleId: coupleId,
                            placeId: place.id,
                            title: finalTitle,
                            category: selectedCategory,
                            iconEmoji: selectedEmoji,
                          );
                        }

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('"$finalTitle" güncellendi! ✨'),
                              backgroundColor: const Color(0xFF10B981),
                            ),
                          );
                        }
                      },
                      child: const Text(
                        'Değişiklikleri Kaydet',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Kayıtlı Konum Detayı ve Silme / Düzenleme / Uçma Penceresi
  void _showPlaceDetailsDialog(SavedPlace place) {
    final coupleId = ref.read(coupleIdProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    setState(() => _pressedPoint = LatLng(place.lat, place.lng));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.only(left: 22, right: 22, top: 16, bottom: 24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E212B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            const SizedBox(height: 18),
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: LoveraColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(child: Text(place.iconEmoji, style: const TextStyle(fontSize: 30))),
            ),
            const SizedBox(height: 12),
            Text(
              place.title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            if (place.createdByName != null && place.createdByName!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Ekleyen: ${place.createdByName}',
                style: const TextStyle(fontSize: 12, color: LoveraColors.textMuted),
              ),
            ],
            const SizedBox(height: 16),
            // Bildirim Tercihleri (Partner ve Kendim İçin Ayrı Ayrı)
            // Canlı Firestore Stream ile her iki tarafın telefonunda ANLIK (Realtime) senkronize olur!
            FutureBuilder<SharedPreferences>(
              future: SharedPreferences.getInstance(),
              builder: (context, prefSnapshot) {
                if (!prefSnapshot.hasData) {
                  return const SizedBox(height: 120);
                }
                final prefs = prefSnapshot.data!;
                final partnerName = ref.watch(partnerProvider)?.name ?? 'Partnerim';
                final coupleId = ref.read(coupleIdProvider);

                final isMeeting = place.id == 'active_meeting';
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: coupleId != null
                      ? (isMeeting
                          ? FirebaseFirestore.instance.collection('couples').doc(coupleId).snapshots()
                          : FirebaseFirestore.instance
                              .collection('couples')
                              .doc(coupleId)
                              .collection('saved_places')
                              .doc(place.id)
                              .snapshots())
                      : null,
                  builder: (context, docSnapshot) {
                    final rawData = docSnapshot.data?.data();
                    final Map<String, dynamic> remoteNotifs = isMeeting
                        ? (rawData?['activeMeeting'] != null && rawData!['activeMeeting'] is Map && rawData['activeMeeting']['notifications'] != null
                            ? Map<String, dynamic>.from(rawData['activeMeeting']['notifications'] as Map)
                            : (place.notifications ?? {}))
                        : (rawData?['notifications'] != null
                            ? Map<String, dynamic>.from(rawData!['notifications'] as Map)
                            : (place.notifications ?? {}));

                    final myUid = DatabaseService().uid ?? '';
                    final partnerUid = ref.watch(partnerProvider)?.id ?? '';

                    // Firestore'da bildirim durumları:
                    // "$myUid_enter": Ben bu mekana gidince bildirim gitsin mi?
                    // "$partnerUid_enter": Partner bu mekana gidince bana bildirim gelsin mi?
                    final bool partnerNotifyEnter = remoteNotifs['${partnerUid}_enter'] as bool? ??
                        remoteNotifs['partner_enter'] as bool? ??
                        prefs.getBool('partner_notify_enter_${place.id}') ??
                        prefs.getBool('notify_enter_${place.id}') ?? true;

                    final bool partnerNotifyExit = remoteNotifs['${partnerUid}_exit'] as bool? ??
                        remoteNotifs['partner_exit'] as bool? ??
                        prefs.getBool('partner_notify_exit_${place.id}') ??
                        prefs.getBool('notify_exit_${place.id}') ?? true;

                    final bool myNotifyEnter = remoteNotifs['${myUid}_enter'] as bool? ??
                        remoteNotifs['my_enter'] as bool? ??
                        prefs.getBool('my_notify_enter_${place.id}') ?? true;

                    final bool myNotifyExit = remoteNotifs['${myUid}_exit'] as bool? ??
                        remoteNotifs['my_exit'] as bool? ??
                        prefs.getBool('my_notify_exit_${place.id}') ?? true;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. PARTNER BÖLÜMÜ
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.favorite_rounded, size: 14, color: LoveraColors.primary),
                              const SizedBox(width: 6),
                              Text(
                                '$partnerName İçin Bildirimler',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white70 : const Color(0xFF475569),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF282B37) : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          child: Column(
                            children: [
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                activeColor: LoveraColors.primary,
                                secondary: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: LoveraColors.primary.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.notifications_active_rounded, color: LoveraColors.primary, size: 18),
                                ),
                                title: Text(
                                  '$partnerName buraya gidince bana haber ver',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                ),
                                value: partnerNotifyEnter,
                                onChanged: (val) async {
                                  await prefs.setBool('partner_notify_enter_${place.id}', val);
                                  await prefs.setBool('notify_enter_${place.id}', val);
                                  if (coupleId != null) {
                                    if (isMeeting) {
                                      DatabaseService().updateActiveMeetingNotificationSettings(
                                        coupleId: coupleId,
                                        notificationUpdates: {
                                          if (partnerUid.isNotEmpty) '${partnerUid}_enter': val,
                                          'partner_enter': val,
                                        },
                                      );
                                    } else {
                                      DatabaseService().updatePlaceNotificationSettings(
                                        coupleId: coupleId,
                                        placeId: place.id,
                                        notificationUpdates: {
                                          if (partnerUid.isNotEmpty) '${partnerUid}_enter': val,
                                          'partner_enter': val,
                                        },
                                      );
                                    }
                                  }
                                },
                              ),
                              Divider(height: 1, thickness: 1, color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                activeColor: LoveraColors.primary,
                                secondary: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: Colors.orangeAccent.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.directions_walk_rounded, color: Colors.orangeAccent, size: 18),
                                ),
                                title: Text(
                                  '$partnerName buradan ayrılınca bana haber ver',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                ),
                                value: partnerNotifyExit,
                                onChanged: (val) async {
                                  await prefs.setBool('partner_notify_exit_${place.id}', val);
                                  await prefs.setBool('notify_exit_${place.id}', val);
                                  if (coupleId != null) {
                                    if (isMeeting) {
                                      DatabaseService().updateActiveMeetingNotificationSettings(
                                        coupleId: coupleId,
                                        notificationUpdates: {
                                          if (partnerUid.isNotEmpty) '${partnerUid}_exit': val,
                                          'partner_exit': val,
                                        },
                                      );
                                    } else {
                                      DatabaseService().updatePlaceNotificationSettings(
                                        coupleId: coupleId,
                                        placeId: place.id,
                                        notificationUpdates: {
                                          if (partnerUid.isNotEmpty) '${partnerUid}_exit': val,
                                          'partner_exit': val,
                                        },
                                      );
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // 2. KENDİM BÖLÜMÜ (BEN GİDİNCE / AYRILINCA PARTNERE HABER VER)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.person_pin_circle_rounded, size: 15, color: Color(0xFF8B5CF6)),
                              const SizedBox(width: 6),
                              Text(
                                'Kendim İçin Bildirimler',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white70 : const Color(0xFF475569),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF282B37) : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          child: Column(
                            children: [
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                activeColor: const Color(0xFF8B5CF6),
                                secondary: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.location_on_rounded, color: Color(0xFF8B5CF6), size: 18),
                                ),
                                title: Text(
                                  'Ben buraya gidince $partnerName\'e haber ver',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                ),
                                value: myNotifyEnter,
                                onChanged: (val) async {
                                  await prefs.setBool('my_notify_enter_${place.id}', val);
                                  if (coupleId != null) {
                                    if (isMeeting) {
                                      DatabaseService().updateActiveMeetingNotificationSettings(
                                        coupleId: coupleId,
                                        notificationUpdates: {
                                          if (myUid.isNotEmpty) '${myUid}_enter': val,
                                          'my_enter': val,
                                        },
                                      );
                                    } else {
                                      DatabaseService().updatePlaceNotificationSettings(
                                        coupleId: coupleId,
                                        placeId: place.id,
                                        notificationUpdates: {
                                          if (myUid.isNotEmpty) '${myUid}_enter': val,
                                          'my_enter': val,
                                        },
                                      );
                                    }
                                  }
                                },
                              ),
                              Divider(height: 1, thickness: 1, color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                activeColor: const Color(0xFF8B5CF6),
                                secondary: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.directions_run_rounded, color: Color(0xFF3B82F6), size: 18),
                                ),
                                title: Text(
                                  'Ben buradan ayrılınca $partnerName\'e haber ver',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                ),
                                value: myNotifyExit,
                                onChanged: (val) async {
                                  await prefs.setBool('my_notify_exit_${place.id}', val);
                                  if (coupleId != null) {
                                    if (isMeeting) {
                                      DatabaseService().updateActiveMeetingNotificationSettings(
                                        coupleId: coupleId,
                                        notificationUpdates: {
                                          if (myUid.isNotEmpty) '${myUid}_exit': val,
                                          'my_exit': val,
                                        },
                                      );
                                    } else {
                                      DatabaseService().updatePlaceNotificationSettings(
                                        coupleId: coupleId,
                                        placeId: place.id,
                                        notificationUpdates: {
                                          if (myUid.isNotEmpty) '${myUid}_exit': val,
                                          'my_exit': val,
                                        },
                                      );
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                    label: const Text('Sil', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700, fontSize: 13)),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      HapticFeedback.mediumImpact();
                      if (place.id == 'active_meeting') {
                        if (coupleId != null) {
                          await DatabaseService().clearActiveMeeting(coupleId);
                        }
                        ref.read(activeMeetingLocationProvider.notifier).state = null;
                        if (mounted) {
                          setState(() {
                            _myMeetingRoute = [];
                            _partnerMeetingRoute = [];
                            _isMeetingTopBannerVisible = false;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Buluşma noktası silindi.')),
                          );
                        }
                      } else {
                        if (coupleId != null) {
                          await DatabaseService().deleteSavedPlace(coupleId, place.id);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('"${place.title}" konumu silindi.')),
                            );
                          }
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      side: BorderSide(color: LoveraColors.primary.withValues(alpha: 0.5)),
                    ),
                    icon: Icon(Icons.edit_rounded, color: LoveraColors.primary, size: 18),
                    label: Text('Düzenle', style: TextStyle(color: LoveraColors.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showEditPlaceDialog(place);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LoveraColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.flight_takeoff_rounded, color: Colors.white, size: 18),
                    label: const Text('Uç', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _animatedFlightMove(LatLng(place.lat, place.lng), 16.5);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Mesajla Yanıtlama / Paylaşma Butonu
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: LoveraColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: const Text(
                  'Bu Konumu Mesajla Yanıtla / Paylaş',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  HapticFeedback.selectionClick();
                  ref.read(pendingChatLocationAttachmentProvider.notifier).state = AttachedLocation(
                    lat: place.lat,
                    lng: place.lng,
                    title: '${place.iconEmoji} ${place.title}',
                  );
                  ref.read(pendingChatInputTextProvider.notifier).state = '';
                  if (widget.onOpenChat != null) {
                    widget.onOpenChat!();
                  } else {
                    ref.read(activeNavigationIndexProvider.notifier).state = 2;
                  }
                },
              ),
            ),
            if (place.id != 'active_meeting') ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    side: BorderSide(color: LoveraColors.primary.withValues(alpha: 0.5)),
                  ),
                  icon: Icon(Icons.favorite_rounded, color: LoveraColors.primary, size: 18),
                  label: Text(
                    'Buluşma Talebi Gönder',
                    style: TextStyle(color: LoveraColors.primary, fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    HapticFeedback.selectionClick();
                    _sendMeetingRequest(LatLng(place.lat, place.lng), '${place.iconEmoji} ${place.title}');
                  },
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  ).whenComplete(() {
    if (mounted) setState(() => _pressedPoint = null);
  });
}

  /// Partnerin konum ikonuna basılı tutunca açılan şık alt menü (Mevcut konum, Kopyalama, Mesajla Yanıtlama)
  void _showPartnerLocationOptionsSheet({
    required AppUser? partner,
    required LatLng? partnerPos,
    required SavedPlace? currentPlace,
    required double? distanceMeters,
  }) {
    if (partnerPos == null) return;
    HapticFeedback.heavyImpact();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final partnerName = partner?.name ?? 'Partnerin';

    // Konum başlığı ve detay metni (Örn: "🏠 Evim" veya "İstanbul · 41.0822, 28.9323")
    final String locationTitle;
    if (currentPlace != null) {
      locationTitle = '${currentPlace.iconEmoji} ${currentPlace.title}';
    } else if (partner?.currentPlaceTitle != null && partner!.currentPlaceTitle!.isNotEmpty) {
      final emoji = partner.currentPlaceEmoji ?? '📍';
      locationTitle = '$emoji ${partner.currentPlaceTitle}';
    } else if (partner?.city != null && partner!.city!.isNotEmpty) {
      locationTitle = '📍 ${partner.city}';
    } else {
      locationTitle = '📍 Canlı Konum';
    }

    final String coordText = '${partnerPos.latitude.toStringAsFixed(5)}, ${partnerPos.longitude.toStringAsFixed(5)}';
    final String fullLocationText = (currentPlace != null)
        ? '${currentPlace.title} ($coordText)'
        : (partner?.city != null && partner!.city!.isNotEmpty)
            ? '${partner.city} ($coordText)'
            : coordText;

    final String distanceInfo = distanceMeters != null
        ? (distanceMeters >= 1000
            ? '${(distanceMeters / 1000).toStringAsFixed(1)} km uzaklıkta'
            : '${distanceMeters.round()} m uzaklıkta')
        : 'Mesafe hesaplanıyor';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 14, bottom: 28),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E212B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sürükleme Çizgisi
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),

            // Üst Başlık & Avatar
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LoveraColors.primaryGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: LoveraColors.primary.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      currentPlace?.iconEmoji ?? '📍',
                      style: const TextStyle(fontSize: 26),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '$partnerName\'in Mevcut Konumu',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : const Color(0xFF1E2022),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (partner?.batteryLevel != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '%${partner!.batteryLevel}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        locationTitle,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: LoveraColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Konum Bilgi Kartı
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF282B37) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.near_me_rounded, size: 14, color: LoveraColors.secondary),
                      const SizedBox(width: 6),
                      Text(
                        'KOORDİNAT VE DETAY',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: isDark ? const Color(0xFFA0A6B2) : const Color(0xFF6B7280),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        distanceInfo,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: LoveraColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    fullLocationText,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : const Color(0xFF374151),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Eylem Butonları: 1. Mesajla Cevapla, 2. Kopyala
            Row(
              children: [
                // 1. Kopyala Butonu
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      side: BorderSide(
                        color: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.1),
                      ),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text(
                      'Kopyala',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: fullLocationText));
                      HapticFeedback.mediumImpact();
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                              const SizedBox(width: 10),
                              Expanded(child: Text('$partnerName\'in konumu panoya kopyalandı! 📋')),
                            ],
                          ),
                          backgroundColor: const Color(0xFF10B981),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),

                // 2. Mesajlar Kısmından Cevapla Butonu
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LoveraColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                    label: const Text(
                      'Mesajla Yanıtla',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      HapticFeedback.selectionClick();

                      // Konumu ek olarak sohbete iliştir (Tıklanabilir konum kartı olarak gidecek)
                      ref.read(pendingChatLocationAttachmentProvider.notifier).state = AttachedLocation(
                        lat: partnerPos.latitude,
                        lng: partnerPos.longitude,
                        title: locationTitle,
                      );
                      // Mesaj giriş alanına hazır metin koymak yerine kullanıcı istediği normal mesajı da yazabilsin
                      ref.read(pendingChatInputTextProvider.notifier).state = '';

                      // Sohbet sayfasına geçiş yap
                      if (widget.onOpenChat != null) {
                        widget.onOpenChat!();
                      } else {
                        ref.read(activeNavigationIndexProvider.notifier).state = 2;
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final partner = ref.watch(partnerProvider);
    final currentUser = ref.watch(currentUserProvider);
    final providerPlaces = ref.watch(savedPlacesProvider);
    final activeMeeting = ref.watch(activeMeetingLocationProvider);
    final currentSavedPlaces = _savedPlaces.isNotEmpty ? _savedPlaces : providerPlaces;

    final LatLng? myLatLng = (currentUser?.lat != null && currentUser?.lng != null)
        ? LatLng(currentUser!.lat!, currentUser.lng!)
        : null;

    final LatLng? partnerLatLng = (partner?.lat != null && partner?.lng != null)
        ? LatLng(partner!.lat!, partner.lng!)
        : null;

    // Konum güncellendiğinde kademe kademe atlamak yerine 60 FPS süzülerek kayması için tetikle
    if (myLatLng != null) {
      _smoothAnimateMyPos(myLatLng);
    }
    if (partnerLatLng != null) {
      _smoothAnimatePartnerPos(partnerLatLng);
    }

    final effectiveMyPos = _animatedMyPos ?? myLatLng;
    final effectivePartnerPos = _animatedPartnerPos ?? partnerLatLng;

    final bool isPartnerOnline = partner?.isAppOpen == true &&
        (partner?.lastActive == null ||
            DateTime.now().toUtc().difference(partner!.lastActive!.toUtc()).abs().inMinutes < 5);

    // Yol mesafesi sorgusunu UI döngüsünden bağımsız post-frame olarak tetikle
    if (myLatLng != null && partnerLatLng != null) {
      if (_lastRouteStart?.latitude != myLatLng.latitude ||
          _lastRouteStart?.longitude != myLatLng.longitude ||
          _lastRouteEnd?.latitude != partnerLatLng.latitude ||
          _lastRouteEnd?.longitude != partnerLatLng.longitude) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _checkAndFetchRoute(myLatLng, partnerLatLng);
          }
        });
      }
    }

    final double? straightDist = (effectiveMyPos != null && effectivePartnerPos != null)
        ? Geolocator.distanceBetween(
            effectiveMyPos.latitude,
            effectiveMyPos.longitude,
            effectivePartnerPos.latitude,
            effectivePartnerPos.longitude,
          )
        : null;

    final double? displayDistance = _roadDistanceMeters ??
        (straightDist != null ? straightDist * 1.25 : null);

    final initialCenter = effectivePartnerPos ?? effectiveMyPos ?? const LatLng(39.0, 35.0);
    final initialZoom = (effectivePartnerPos != null || effectiveMyPos != null) ? 15.0 : 6.0;

    final mapBgColor = isDark ? const Color(0xFF141620) : const Color(0xFFE8EEF3);

    // Kayıtlı bir yerde bulunma kontrolü (45m içi ise yer rozeti avatar rozetiyle birleşir)
    SavedPlace? myCurrentPlace;
    SavedPlace? partnerCurrentPlace;

    if (effectiveMyPos != null) {
      for (final p in currentSavedPlaces) {
        if (Geolocator.distanceBetween(effectiveMyPos.latitude, effectiveMyPos.longitude, p.lat, p.lng) <= 45) {
          myCurrentPlace = p;
          break;
        }
      }
    }

    if (effectivePartnerPos != null) {
      for (final p in currentSavedPlaces) {
        if (Geolocator.distanceBetween(effectivePartnerPos.latitude, effectivePartnerPos.longitude, p.lat, p.lng) <= 45) {
          partnerCurrentPlace = p;
          break;
        }
      }
    }

    // Avatar veya Aktif Buluşma ile birleşen yerleri bağımsız yer pinleri katmanından çıkar (çift pin oluşmasın)
    final standalonePlaces = currentSavedPlaces.where((p) {
      if (p.title.toLowerCase().contains('seçilen')) return false;
      if (p.id == myCurrentPlace?.id || p.id == partnerCurrentPlace?.id) return false;
      if (activeMeeting != null) {
        final distToMeeting = Geolocator.distanceBetween(activeMeeting.lat, activeMeeting.lng, p.lat, p.lng);
        if (distToMeeting <= 30) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: mapBgColor,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: initialZoom,
              minZoom: 3.0,
              maxZoom: 20.0,
              backgroundColor: mapBgColor,
              onLongPress: (tapPosition, point) {
                // Eğer dokunulan yer partnerin avatarının üzerindeyse partner menüsünü aç
                if (effectivePartnerPos != null) {
                  final distMeters = Geolocator.distanceBetween(
                    point.latitude,
                    point.longitude,
                    effectivePartnerPos.latitude,
                    effectivePartnerPos.longitude,
                  );
                  // Ekran koordinatları veya coğrafi mesafe kontrolü (ekranda ~80px veya haritada ~250m)
                  final partnerScreenPoint = _mapController.camera.latLngToScreenPoint(effectivePartnerPos);
                  final tapOffset = tapPosition.relative ?? tapPosition.global;
                  final tapPoint = math.Point(tapOffset.dx, tapOffset.dy);
                  final screenDistance = partnerScreenPoint.distanceTo(tapPoint);

                  if (screenDistance <= 80 || distMeters <= 250) {
                    _showPartnerLocationOptionsSheet(
                      partner: partner,
                      partnerPos: effectivePartnerPos,
                      currentPlace: partnerCurrentPlace,
                      distanceMeters: displayDistance,
                    );
                    return;
                  }
                }
                setState(() => _pressedPoint = point);
                _showAddPlaceDialog(point);
              },
              onPositionChanged: (position, hasGesture) {
                // Kullanıcı haritayı parmağıyla sürüklediğinde / kaydırdığında takipten (fokustan) çık!
                if (hasGesture && _followTarget != _FollowTarget.none) {
                  setState(() {
                    _followTarget = _FollowTarget.none;
                  });
                }
              },
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all, // 60 FPS pan/pinch & Google Maps yön dönüşü
              ),
            ),
            children: [
              // Yüksek Hızlı, Filigransız Google Harita Katmanı (Koyu Modda Snap Gece Matrisi)
              TileLayer(
                urlTemplate: 'https://{s}.google.com/vt/lyrs=m&hl=tr&x={x}&y={y}&z={z}',
                subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
                userAgentPackageName: 'com.lovera.app.lovera',
                maxZoom: 20,
                maxNativeZoom: 20,
                keepBuffer: 3,
                panBuffer: 1,
                tileBuilder: isDark ? _snapMapDarkTileBuilder : null,
              ),

              // Buluşma Rotaları (Her iki kullanıcı için en yakın yol çizgileri)
              if (_myMeetingRoute.isNotEmpty || _partnerMeetingRoute.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    if (_myMeetingRoute.isNotEmpty)
                      Polyline(
                        points: _myMeetingRoute,
                        strokeWidth: 5.0,
                        color: const Color(0xFF388AF6).withValues(alpha: 0.85),
                        borderStrokeWidth: 2.0,
                        borderColor: Colors.white.withValues(alpha: 0.9),
                      ),
                    if (_partnerMeetingRoute.isNotEmpty)
                      Polyline(
                        points: _partnerMeetingRoute,
                        strokeWidth: 5.0,
                        color: LoveraColors.primary.withValues(alpha: 0.85),
                        borderStrokeWidth: 2.0,
                        borderColor: Colors.white.withValues(alpha: 0.9),
                      ),
                  ],
                ),

              // Kalıcı Kayıtlı Özel Konumlar Katmanı (Ev, İş, Okul vb.)
              MarkerLayer(
                markers: standalonePlaces.map((place) {
                  return Marker(
                    point: LatLng(place.lat, place.lng),
                    width: 140,
                    height: 64,
                    alignment: Alignment.topCenter,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: _SavedPlaceMarker(
                        place: place,
                        isDark: isDark,
                        onTap: () => _showPlaceDetailsDialog(place),
                      ),
                    ),
                  );
                }).toList(),
              ),

              // Snap Map Canlı Avatar Pinleri (60 FPS Pürüzsüz Kayan Markerlar)
              MarkerLayer(
                markers: [
                  if (effectiveMyPos != null)
                    Marker(
                      point: effectiveMyPos,
                      width: 220,
                      height: 120,
                      alignment: Alignment.topCenter,
                      child: _SnapAvatarMarker(
                        name: currentUser?.name ?? 'Ben',
                        avatarUrl: currentUser?.avatarUrl,
                        batteryLevel: currentUser?.batteryLevel,
                        borderColor: const Color(0xFF388AF6), // Okyanus Mavisi Rozet
                        glowColor: const Color(0xFF388AF6).withValues(alpha: 0.35),
                        isMe: true,
                        isOnline: true,
                        isDark: isDark,
                        currentPlace: myCurrentPlace,
                        onTap: () {
                          setState(() => _followTarget = _FollowTarget.me);
                          _animatedFlightMove(effectiveMyPos, 16.0);
                        },
                      ),
                    ),
                  if (effectivePartnerPos != null)
                    Marker(
                      point: effectivePartnerPos,
                      width: 220,
                      height: 120,
                      alignment: Alignment.topCenter,
                      child: _SnapAvatarMarker(
                        name: partner?.name ?? 'Partner',
                        avatarUrl: partner?.avatarUrl,
                        batteryLevel: partner?.batteryLevel,
                        borderColor: isPartnerOnline
                            ? const Color(0xFF10B981)
                            : LoveraColors.primary,
                        glowColor: isPartnerOnline
                            ? const Color(0xFF10B981).withValues(alpha: 0.5)
                            : LoveraColors.primary.withValues(alpha: 0.35),
                        isMe: false,
                        isOnline: isPartnerOnline,
                        isDark: isDark,
                        currentPlace: partnerCurrentPlace,
                        onTap: () {
                          setState(() => _followTarget = _FollowTarget.partner);
                          _animatedFlightMove(effectivePartnerPos, 16.0);
                        },
                        onLongPress: () {
                          _showPartnerLocationOptionsSheet(
                            partner: partner,
                            partnerPos: effectivePartnerPos,
                            currentPlace: partnerCurrentPlace,
                            distanceMeters: displayDistance,
                          );
                        },
                      ),
                    ),
                  if (_pressedPoint != null)
                    Marker(
                      point: _pressedPoint!,
                      width: 70,
                      height: 70,
                      alignment: Alignment.topCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: LoveraColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: LoveraColors.primary.withValues(alpha: 0.6),
                                  blurRadius: 16,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.location_on_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          CustomPaint(
                            size: const Size(10, 6),
                            painter: _TrianglePainter(color: LoveraColors.primary),
                          ),
                        ],
                      ),
                    ),
                  if (activeMeeting != null)
                    Marker(
                      point: LatLng(activeMeeting.lat, activeMeeting.lng),
                      width: 150,
                      height: 70,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onTap: () {
                          if (_isMeetingTopBannerVisible) {
                            _closeMeetingBanner();
                          } else {
                            _openMeetingBanner();
                            _fitBothMeetingRoutes(activeMeeting);
                          }
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              constraints: const BoxConstraints(maxWidth: 140),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                gradient: LoveraColors.primaryGradient,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: LoveraColors.primary.withValues(alpha: 0.45),
                                    blurRadius: 12,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('💖', style: TextStyle(fontSize: 13)),
                                  const SizedBox(width: 4),
                                  const Flexible(
                                    child: Text(
                                      'Buluşma',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            const CustomPaint(
                              size: Size(10, 6),
                              painter: _TrianglePainter(color: LoveraColors.primary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_highlightedTargetLocation != null && activeMeeting == null)
                    Marker(
                      point: LatLng(_highlightedTargetLocation!.lat, _highlightedTargetLocation!.lng),
                      width: 140,
                      height: 80,
                      alignment: Alignment.topCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF3B82F6).withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Text(
                              _highlightedTargetLocation!.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Icon(
                            Icons.location_on_rounded,
                            color: Color(0xFF3B82F6),
                            size: 32,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Üst Bar: Geri Dönüş & İkimizi Göster Butonu
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _GlassButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    iconSize: 18,
                    tooltip: 'Geri',
                    isDark: isDark,
                    onTap: () {
                      if (widget.onBackToHome != null) {
                        widget.onBackToHome!();
                      } else {
                        Navigator.of(context).maybePop();
                      }
                    },
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pusula / Kuzey Butonu (Harita dönmüşse veya navigasyondayken görünür)
                      Builder(
                        builder: (context) {
                          final double rot = _mapController.camera.rotation;
                          final bool isRotated = rot.abs() > 2.0 || _isNavigating;
                          if (!isRotated) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _GlassButton(
                              icon: Icons.explore_rounded,
                              iconColor: LoveraColors.primary,
                              tooltip: 'Kuzeyi Göster (Sıfırla)',
                              isDark: isDark,
                              onTap: () {
                                _resetCompassToNorth();
                              },
                            ),
                          );
                        },
                      ),
                      _GlassButton(
                        icon: Icons.add_location_alt_rounded,
                        iconColor: LoveraColors.primary,
                        tooltip: 'Konum Etiketle',
                        isDark: isDark,
                        onTap: () {
                          final targetPoint = myLatLng ?? _mapController.camera.center;
                          _showAddPlaceDialog(targetPoint);
                        },
                      ),
                      if (myLatLng != null && partnerLatLng != null) ...[
                        const SizedBox(width: 8),
                        _GlassButton(
                          icon: Icons.all_inclusive_rounded,
                          iconColor: LoveraColors.primary,
                          tooltip: 'İkimizi Göster',
                          isDark: isDark,
                          onTap: () {
                            if (_isNavigating) {
                              _resetCompassToNorth();
                            }
                            setState(() => _followTarget = _FollowTarget.none);
                            final bounds = LatLngBounds.fromPoints([myLatLng, partnerLatLng]);
                            _mapController.fitCamera(
                              CameraFit.bounds(
                                bounds: bounds,
                                padding: const EdgeInsets.only(left: 70, right: 70, top: 200, bottom: 230),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Aktif Buluşma Bilgi Kartı (Sadece alttaki Buluşma butonuna basınca yukarıdan aşağı animasyonla iner, çarpıya basınca yukarı kayarak kapanır)
          if (activeMeeting != null && _isMeetingTopBannerVisible)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: SlideTransition(
                  position: _meetingBannerSlideAnimation,
                  child: FadeTransition(
                    opacity: _meetingBannerController,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 60, left: 16, right: 16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _fitBothMeetingRoutes(activeMeeting),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E212B) : Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: LoveraColors.primary.withValues(alpha: 0.25),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(
                              color: LoveraColors.primary.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  gradient: LoveraColors.primaryGradient,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 16),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Buluşma Noktası',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: LoveraColors.primary,
                                      ),
                                    ),
                                    Builder(
                                      builder: (context) {
                                        String meetTitle = activeMeeting.title.trim();
                                        if (meetTitle.toLowerCase().contains('seçilen') || meetTitle.isEmpty) {
                                          meetTitle = 'Buluşma';
                                        }
                                        return Text(
                                          meetTitle,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              // Yola Odaklan Butonu (Google Maps stili yol yönüne kilitli navigasyon veya tüm rotayı görme)
                              InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () {
                                  if (_isNavigating) {
                                    _resetCompassToNorth();
                                    _fitBothMeetingRoutes(activeMeeting);
                                  } else {
                                    _startGoogleMapsNavigation(activeMeeting);
                                  }
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _isNavigating
                                        ? LoveraColors.primary
                                        : LoveraColors.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: _isNavigating
                                        ? [
                                            BoxShadow(
                                              color: LoveraColors.primary.withValues(alpha: 0.4),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _isNavigating ? Icons.navigation_rounded : Icons.alt_route_rounded,
                                        color: _isNavigating ? Colors.white : LoveraColors.primary,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _isNavigating ? 'Navigasyondasın' : 'Yola Odaklan',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: _isNavigating ? Colors.white : LoveraColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  _closeMeetingBanner(clearRoutes: true);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 18),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Alt Bölüm: Snap Map Tarzı Hızlı Işınlanma Butonları & Canlı Bilgi Kartı
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Snap Tarzı Hızlı Işınlanma Yüzen Butonları (Sadece Simgeler: Sol Eda Kalp, Yanında Ben Konum, Yanlarında Kayıtlı Yerler)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 1. Partnerin Yanına Uç Butonu (Mor Daire + Beyaz Kalp İkonu)
                        if (partnerLatLng != null)
                          _QuickCircleActionButton(
                            iconWidget: const Icon(Icons.favorite_rounded, color: Colors.white, size: 25),
                            bgColor: LoveraColors.primary,
                            borderColor: Colors.white.withValues(alpha: 0.25),
                            shadowColor: LoveraColors.primary.withValues(alpha: 0.35),
                            isDark: isDark,
                            label: partner?.name ?? 'Partner',
                            tooltip: '${partner?.name ?? "Partner"}\'a Uç',
                            onTap: () {
                              setState(() => _followTarget = _FollowTarget.partner);
                              _animatedFlightMove(partnerLatLng, 16.0);
                            },
                            onLongPress: () {
                              _showPartnerLocationOptionsSheet(
                                partner: partner,
                                partnerPos: effectivePartnerPos,
                                currentPlace: partnerCurrentPlace,
                                distanceMeters: displayDistance,
                              );
                            },
                          ),

                        // 2. Kendi Konumuma Uç Butonu (Mavi Daire + Konum İkonu)
                        if (myLatLng != null) ...[
                          const SizedBox(width: 12),
                          _QuickCircleActionButton(
                            iconWidget: const Icon(Icons.my_location_rounded, color: Colors.white, size: 25),
                            bgColor: const Color(0xFF388AF6),
                            borderColor: Colors.white.withValues(alpha: 0.25),
                            shadowColor: const Color(0xFF388AF6).withValues(alpha: 0.35),
                            isDark: isDark,
                            label: 'Ben',
                            tooltip: 'Bana Dön',
                            onTap: () async {
                              setState(() => _followTarget = _FollowTarget.me);
                              DeviceService().syncStatusToFirebase();
                              _animatedFlightMove(myLatLng, 16.0);
                            },
                          ),
                        ],

                        // 3. Aktif Buluşma Butonu (Buluşma İkonu - Tıklanınca üst menüyü açar ve rotayı çizer, Basılı tutunca seçenekler menüsü)
                        if (activeMeeting != null) ...[
                          const SizedBox(width: 12),
                          _QuickCircleActionButton(
                            iconWidget: const Text('💖', style: TextStyle(fontSize: 24)),
                            bgColor: LoveraColors.primary,
                            borderColor: Colors.white.withValues(alpha: 0.4),
                            shadowColor: LoveraColors.primary.withValues(alpha: 0.45),
                            isDark: isDark,
                            label: 'Buluşma',
                            tooltip: 'Buluşma Noktası',
                            onTap: () {
                              HapticFeedback.selectionClick();
                              if (_isMeetingTopBannerVisible) {
                                _closeMeetingBanner();
                              } else {
                                _openMeetingBanner();
                                _fitBothMeetingRoutes(activeMeeting);
                              }
                            },
                            onLongPress: () {
                              HapticFeedback.mediumImpact();
                              final meetingPlace = SavedPlace(
                                id: 'active_meeting',
                                title: activeMeeting.title.isNotEmpty ? activeMeeting.title : 'Buluşma Noktası',
                                iconEmoji: '💖',
                                lat: activeMeeting.lat,
                                lng: activeMeeting.lng,
                                category: 'meeting',
                                createdBy: currentUser?.id ?? '',
                                createdByName: 'Buluşma Noktası',
                                createdAt: DateTime.now(),
                              );
                              _showPlaceDetailsDialog(meetingPlace);
                            },
                          ),
                        ],

                        // 4+. Kayıtlı Mekanlar (Büyük Emoji Butonları + Net Görünen Rozet + 'Ev' Etiketi)
                        ...currentSavedPlaces.where((place) {
                          if (place.title.toLowerCase().contains('seçilen')) return false;
                          if (activeMeeting != null) {
                            final distToMeeting = Geolocator.distanceBetween(activeMeeting.lat, activeMeeting.lng, place.lat, place.lng);
                            if (distToMeeting <= 30) return false;
                          }
                          return true;
                        }).map((place) {
                          // Bu mekan kullanıcıya mı yoksa partnere mi ait / kim eklemiş?
                          final currentUserId = currentUser?.id ?? DatabaseService().uid;
                          final bool isCreatedByMe = place.createdBy.isNotEmpty && place.createdBy == currentUserId;
                          final bool isPartnerPlace = (partner != null && place.createdBy == partner.id) ||
                              (!isCreatedByMe && place.createdByName != null && place.createdByName!.isNotEmpty);

                          // 'Evim' yazıyorsa doğrudan kullanıcının istediği gibi 'Ev' olarak göster
                          String displayLabel = place.title;
                          if (displayLabel.trim().toLowerCase() == 'evim') {
                            displayLabel = 'Ev';
                          }

                          // Kimin yeri olduğunu gösteren net ve belirgin köşe rozeti (Partner: Mor Kalp 💜, Ben: Mavi Kullanıcı 👤)
                          final Widget? cornerBadge = isPartnerPlace
                              ? Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: LoveraColors.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isDark ? const Color(0xFF1E212B) : Colors.white,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: LoveraColors.primary.withValues(alpha: 0.5),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.favorite_rounded, color: Colors.white, size: 10),
                                  ),
                                )
                              : (isCreatedByMe
                                  ? Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF388AF6),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isDark ? const Color(0xFF1E212B) : Colors.white,
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF388AF6).withValues(alpha: 0.5),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                      child: const Center(
                                        child: Icon(Icons.person_rounded, color: Colors.white, size: 10),
                                      ),
                                    )
                                  : null);

                          return Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: _QuickCircleActionButton(
                              iconWidget: Text(
                                place.iconEmoji,
                                style: const TextStyle(fontSize: 25),
                              ),
                              bgColor: isDark ? const Color(0xFF232734) : Colors.white,
                              borderColor: isPartnerPlace
                                  ? LoveraColors.primary.withValues(alpha: 0.55)
                                  : const Color(0xFF388AF6).withValues(alpha: 0.45),
                              shadowColor: isDark
                                  ? Colors.black.withValues(alpha: 0.4)
                                  : LoveraColors.primary.withValues(alpha: 0.18),
                              isDark: isDark,
                              label: displayLabel,
                              badgeWidget: cornerBadge,
                              tooltip: '${place.title}${place.createdByName != null ? " (${place.createdByName})" : ""}',
                              onTap: () {
                                setState(() => _followTarget = _FollowTarget.none);
                                _animatedFlightMove(LatLng(place.lat, place.lng), 16.5);
                                // Menü sadece uzun basınca açılır.
                              },
                              onLongPress: () => _showPlaceDetailsDialog(place),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),

                // Alt Snap Map Kartı (Partner Durumu & Mesafe)
                _SnapMapBottomCard(
                  partner: partner,
                  displayDistance: displayDistance,
                  distanceText: displayDistance != null ? _formatDistance(displayDistance) : null,
                  isDark: isDark,
                  onTap: () {
                    if (partnerLatLng != null) {
                      setState(() => _followTarget = _FollowTarget.partner);
                      _animatedFlightMove(partnerLatLng, 16.0);
                    }
                  },
                ),
              ],
            ).animate().slideY(begin: 0.15, duration: 300.ms, curve: Curves.easeOut),
          ),
        ],
      ),
    );
  }
}

/// Snap Map Tarzı Avatar Pin Tasarımı (3D zemin gölgesi, canlı rozet ve bilgi hapı)
class _SnapAvatarMarker extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final int? batteryLevel;
  final Color borderColor;
  final Color glowColor;
  final bool isMe;
  final bool isOnline;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final SavedPlace? currentPlace;

  const _SnapAvatarMarker({
    required this.name,
    this.avatarUrl,
    this.batteryLevel,
    required this.borderColor,
    required this.glowColor,
    required this.isMe,
    this.isOnline = false,
    required this.isDark,
    required this.onTap,
    this.onLongPress,
    this.currentPlace,
  });

  static final Map<String, Uint8List> _avatarCache = <String, Uint8List>{};

  Uint8List _getAvatarBytes(String url) {
    if (_avatarCache.containsKey(url)) {
      return _avatarCache[url]!;
    }
    final raw = url.split(',').last;
    final bytes = base64Decode(raw);
    _avatarCache[url] = bytes;
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Üst Snap Bilgi Hapı: Kayıtlı yerdeyse birleşik (örn. 🏠 Eda Evde %94), değilse klasik hap
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E212B) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: currentPlace != null
                      ? const Color(0xFF10B981)
                      : (isOnline
                          ? const Color(0xFF10B981)
                          : (isDark ? Colors.white.withValues(alpha: 0.15) : borderColor.withValues(alpha: 0.3))),
                  width: (currentPlace != null || isOnline) ? 1.8 : 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (currentPlace != null || isOnline)
                        ? const Color(0xFF10B981).withValues(alpha: 0.4)
                        : Colors.black.withValues(alpha: isDark ? 0.35 : 0.14),
                    blurRadius: (currentPlace != null || isOnline) ? 10 : 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (currentPlace != null) ...[
                    // Birleşik Ev / Kayıtlı Yer Emojisi
                    Text(
                      currentPlace!.iconEmoji,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(width: 4),
                  ] else ...[
                    // Parlayan Canlılık / Aktiflik Noktası
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: isOnline
                            ? const Color(0xFF10B981)
                            : (isMe ? const Color(0xFF388AF6) : const Color(0xFF94A3B8)),
                        shape: BoxShape.circle,
                        boxShadow: isOnline
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.8),
                                  blurRadius: 6,
                                  spreadRadius: 1.5,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 125),
                    child: Text(
                      currentPlace != null
                          ? (currentPlace!.category == 'home' || currentPlace!.title.toLowerCase().contains('ev')
                              ? '$name Evde'
                              : '$name ${currentPlace!.title}\'de')
                          : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1E2022),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (batteryLevel != null) ...[
                    const SizedBox(width: 5),
                    Text(
                      '%$batteryLevel',
                      style: TextStyle(
                        color: isDark ? const Color(0xFFA0A6B2) : const Color(0xFF6B7280),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),

            // Yuvarlak Avatar & Hologram / Snapchat Tarzı Canlı Halka & Radarlar
            Stack(
              alignment: Alignment.center,
              children: [
                // 1. Canlı radar dalgası (Snapchat Canlı Konum Efekti)
                if (isOnline)
                  Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                  )
                      .animate(onPlay: (controller) => controller.repeat())
                      .scale(
                        begin: const Offset(0.75, 0.75),
                        end: const Offset(1.28, 1.28),
                        duration: 1600.ms,
                        curve: Curves.easeOut,
                      )
                      .fadeOut(duration: 1600.ms, curve: Curves.easeOut),

                // 2. Snapchat Parlama Halkası (Canlıysa zümrüt yeşili neon, değilse marka rengi)
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: isOnline
                            ? const Color(0xFF10B981).withValues(alpha: 0.65)
                            : glowColor,
                        blurRadius: isOnline ? 18 : 14,
                        spreadRadius: isOnline ? 3 : 2,
                      ),
                    ],
                  ),
                ),

                // 3. Ana Avatar Dairesi
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF22252E) : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isOnline ? const Color(0xFF10B981) : borderColor,
                      width: 3,
                    ),
                  ),
                  child: ClipOval(
                    child: avatarUrl != null && avatarUrl!.isNotEmpty
                        ? () {
                            if (avatarUrl!.startsWith('data:image')) {
                              try {
                                final bytes = _getAvatarBytes(avatarUrl!);
                                return Image.memory(
                                  bytes,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                  cacheWidth: 160,
                                  errorBuilder: (_, __, ___) => _buildFallbackIcon(),
                                );
                              } catch (_) {
                                return _buildFallbackIcon();
                              }
                            } else if (avatarUrl!.startsWith('http')) {
                              return Image.network(
                                avatarUrl!,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                cacheWidth: 160,
                                errorBuilder: (_, __, ___) => _buildFallbackIcon(),
                              );
                            } else {
                              return Image.file(
                                File(avatarUrl!),
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                cacheWidth: 160,
                                errorBuilder: (_, __, ___) => _buildFallbackIcon(),
                              );
                            }
                          }()
                        : _buildFallbackIcon(),
                  ),
                ),

                // 4. Alt köşe minik rozet (Mor zeminli beyaz kalp simgesi)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: isMe ? const Color(0xFF388AF6) : LoveraColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? const Color(0xFF22252E) : Colors.white,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isMe ? const Color(0xFF388AF6) : LoveraColors.primary).withValues(alpha: 0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        isMe ? Icons.near_me_rounded : Icons.favorite_rounded,
                        color: Colors.white,
                        size: 10,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Pin İğnesi Ucu
            CustomPaint(
              size: const Size(10, 5),
              painter: _TrianglePainter(
                color: isOnline ? const Color(0xFF10B981) : borderColor,
              ),
            ),

            // Zemin gölgesi: yerleşimi etkilemez, iğne ucu tam koordinatta kalır
            SizedBox(
              height: 0,
              child: OverflowBox(
                maxHeight: 4,
                alignment: Alignment.topCenter,
                child: Container(
                  width: 20,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isOnline
                        ? const Color(0xFF10B981).withValues(alpha: 0.3)
                        : Colors.black.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackIcon() {
    return Center(
      child: Icon(
        isMe ? Icons.person_rounded : Icons.favorite_rounded,
        color: borderColor,
        size: 24,
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Snap Hızlı Işınlanma Düğmesi (Dairesel İkon Buton + Altta Şık Minik İsim Etiketi - Tıkla Uç, Basılı Tut Düzenle/Sil)
class _QuickCircleActionButton extends StatelessWidget {
  const _QuickCircleActionButton({
    required this.iconWidget,
    required this.bgColor,
    required this.borderColor,
    required this.shadowColor,
    required this.isDark,
    required this.tooltip,
    this.label,
    this.badgeWidget,
    required this.onTap,
    this.onLongPress,
  });

  final Widget iconWidget;
  final Color bgColor;
  final Color borderColor;
  final Color shadowColor;
  final bool isDark;
  final String tooltip;
  final String? label;
  final Widget? badgeWidget;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final textThemeColor = isDark ? Colors.white70 : const Color(0xFF2C303E);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: bgColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: borderColor,
                        width: 1.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: shadowColor,
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(child: iconWidget),
                  ),
                  if (badgeWidget != null)
                    Positioned(
                      bottom: -1,
                      right: -1,
                      child: badgeWidget!,
                    ),
                ],
              ),
              if (label != null && label!.isNotEmpty) ...[
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 62),
                  child: Text(
                    label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: textThemeColor,
                      letterSpacing: -0.2,
                      shadows: [
                        Shadow(
                          color: isDark ? Colors.black87 : Colors.white70,
                          blurRadius: 3,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Snap Map Alt Bilgi & Mesafe Kartı
class _SnapMapBottomCard extends StatelessWidget {
  const _SnapMapBottomCard({
    required this.partner,
    required this.displayDistance,
    required this.distanceText,
    required this.isDark,
    required this.onTap,
  });

  final dynamic partner;
  final double? displayDistance;
  final String? distanceText;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF1E212A).withValues(alpha: 0.96) : Colors.white.withValues(alpha: 0.96);
    final titleColor = isDark ? Colors.white : const Color(0xFF1E2022);
    final subColor = isDark ? const Color(0xFFA0A6B2) : const Color(0xFF6B7280);

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LoveraColors.primaryGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: LoveraColors.primary.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ARANIZDAKİ YOL MESAFESİ',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: subColor,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        distanceText ?? (partner == null ? 'Partner bekleniyor' : 'Mesafe hesaplanıyor...'),
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: titleColor,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (partner != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (partner.city != null) ...[
                              const Icon(Icons.location_on_rounded, size: 12, color: LoveraColors.primary),
                              const SizedBox(width: 2),
                              Text(
                                '${partner.name} · ${partner.city}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: subColor,
                                ),
                              ),
                            ],
                            if (partner.batteryLevel != null) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.battery_std_rounded, size: 12, color: Color(0xFF10B981)),
                              Text(
                                '%${partner.batteryLevel}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: LoveraColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.flight_takeoff_rounded, color: LoveraColors.primary, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Snap Map Buton Stili (Glassmorphism & Hafif Gölge)
class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    this.iconSize = 20,
    this.iconColor,
    this.tooltip,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final double iconSize;
  final Color? iconColor;
  final String? tooltip;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = iconColor ?? (isDark ? Colors.white : const Color(0xFF1E2022));

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2028).withValues(alpha: 0.92) : Colors.white.withValues(alpha: 0.94),
        shape: BoxShape.circle,
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, size: iconSize, color: effectiveColor),
        tooltip: tooltip,
        onPressed: onTap,
      ),
    );
  }
}

/// Snap Map Koyu Mod Renk Matrisi (Suyu gece laciverti, karaları koyu grafit, yazıları beyaz yapar)
Widget _snapMapDarkTileBuilder(BuildContext context, Widget tileWidget, TileImage tile) {
  return ColorFiltered(
    colorFilter: const ColorFilter.matrix(<double>[
      0.0, 0.0, -0.65, 0.0, 180.0,
      0.0, -0.65, 0.0, 0.0, 180.0,
      -0.65, 0.0, 0.0, 0.0, 225.0,
      0.0, 0.0, 0.0, 1.0, 0.0,
    ]),
    child: tileWidget,
  );
}

/// Kaydedilen Konumlar İçin Zenly / Snap Tarzı Özel Pin Rozeti
class _SavedPlaceMarker extends StatelessWidget {
  const _SavedPlaceMarker({
    required this.place,
    required this.isDark,
    required this.onTap,
  });

  final SavedPlace place;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Emoji ve Başlık Hapı
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2028).withValues(alpha: 0.94) : Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: LoveraColors.primary.withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  place.iconEmoji,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 85),
                  child: Text(
                    place.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1E2022),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Minik Pin İğnesi
          const CustomPaint(
            size: Size(10, 6),
            painter: _TrianglePainter(
              color: LoveraColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

