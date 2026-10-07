import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' hide Path;

import '../../../core/services/device_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';

class LiveMapView extends ConsumerStatefulWidget {
  const LiveMapView({super.key});

  @override
  ConsumerState<LiveMapView> createState() => _LiveMapViewState();
}

class _LiveMapViewState extends ConsumerState<LiveMapView> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  AnimationController? _flightController;

  double? _roadDistanceMeters;
  bool _calculatingRoad = false;
  LatLng? _lastRouteStart;
  LatLng? _lastRouteEnd;
  Timer? _mapSyncTimer;

  // 60 FPS Pürüzsüz Snap Konum İnterpolasyonu (Kayarak İlerleme)
  AnimationController? _myAnimController;
  AnimationController? _partnerAnimController;
  LatLng? _animatedMyPos;
  LatLng? _animatedPartnerPos;
  LatLng? _targetMyPos;
  LatLng? _targetPartnerPos;

  @override
  void initState() {
    super.initState();
    // Arka planda güvenli durum senkronizasyonu
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeviceService().syncStatusToFirebase();
      _initInitialRoute();
      final partnerUid = ref.read(partnerUidProvider);
      if (partnerUid != null && partnerUid.isNotEmpty) {
        NotificationService().requestPartnerStatusSync(partnerUid);
      }
    });

    // Harita açıkken partnerin kapalı cihazını 12 saniyede bir sessiz uyandır ve konumunu tazelet
    _mapSyncTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      final partnerUid = ref.read(partnerUidProvider);
      if (partnerUid != null && partnerUid.isNotEmpty) {
        NotificationService().requestPartnerStatusSync(partnerUid);
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

  void _smoothAnimateMyPos(LatLng newTarget) {
    if (_animatedMyPos == null) {
      _animatedMyPos = newTarget;
      _targetMyPos = newTarget;
      return;
    }
    if (_targetMyPos?.latitude == newTarget.latitude &&
        _targetMyPos?.longitude == newTarget.longitude) {
      return;
    }

    final from = _animatedMyPos!;
    _targetMyPos = newTarget;
    _myAnimController?.dispose();
    _myAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    final anim = CurvedAnimation(parent: _myAnimController!, curve: Curves.easeOutCubic);
    anim.addListener(() {
      if (!mounted) return;
      final t = anim.value;
      setState(() {
        _animatedMyPos = LatLng(
          from.latitude + (newTarget.latitude - from.latitude) * t,
          from.longitude + (newTarget.longitude - from.longitude) * t,
        );
      });
    });
    _myAnimController!.forward();
  }

  void _smoothAnimatePartnerPos(LatLng newTarget) {
    if (_animatedPartnerPos == null) {
      _animatedPartnerPos = newTarget;
      _targetPartnerPos = newTarget;
      return;
    }
    if (_targetPartnerPos?.latitude == newTarget.latitude &&
        _targetPartnerPos?.longitude == newTarget.longitude) {
      return;
    }

    final from = _animatedPartnerPos!;
    _targetPartnerPos = newTarget;
    _partnerAnimController?.dispose();
    _partnerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    final anim = CurvedAnimation(parent: _partnerAnimController!, curve: Curves.easeOutCubic);
    anim.addListener(() {
      if (!mounted) return;
      final t = anim.value;
      setState(() {
        _animatedPartnerPos = LatLng(
          from.latitude + (newTarget.latitude - from.latitude) * t,
          from.longitude + (newTarget.longitude - from.longitude) * t,
        );
      });
    });
    _partnerAnimController!.forward();
  }

  @override
  void dispose() {
    _mapSyncTimer?.cancel();
    _flightController?.stop();
    _flightController?.dispose();
    _myAnimController?.dispose();
    _partnerAnimController?.dispose();
    _mapController.dispose();
    super.dispose();
  }

  /// Snap Map Akıcı Uçuş Animasyonu:
  /// Havalanır, tepe irtifasına çıkar, hedefe süzülür ve yumuşakça iniş yapar (60 FPS)
  void _animatedFlightMove(LatLng destLocation, double targetZoom) {
    _flightController?.stop();
    _flightController?.dispose();
    _flightController = null;

    final startLoc = _mapController.camera.center;
    final startZoom = _mapController.camera.zoom;

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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final partner = ref.watch(partnerProvider);
    final currentUser = ref.watch(currentUserProvider);

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

    final initialCenter = effectiveMyPos ?? effectivePartnerPos ?? const LatLng(39.0, 35.0);
    final initialZoom = (effectiveMyPos != null || effectivePartnerPos != null) ? 14.5 : 6.0;

    final mapBgColor = isDark ? const Color(0xFF141620) : const Color(0xFFE8EEF3);

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
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate, // Silah gibi akıcı 60fps pan/pinch
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

              // Snap Map Canlı Avatar Pinleri (60 FPS Pürüzsüz Kayan Markerlar)
              MarkerLayer(
                markers: [
                  if (effectiveMyPos != null)
                    Marker(
                      point: effectiveMyPos,
                      width: 140,
                      height: 115,
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
                        onTap: () => _animatedFlightMove(effectiveMyPos, 16.0),
                      ),
                    ),
                  if (effectivePartnerPos != null)
                    Marker(
                      point: effectivePartnerPos,
                      width: 140,
                      height: 115,
                      alignment: Alignment.topCenter,
                      child: _SnapAvatarMarker(
                        name: partner?.name ?? 'Partner',
                        avatarUrl: partner?.avatarUrl,
                        batteryLevel: partner?.batteryLevel,
                        borderColor: (partner?.isAppOpen == true &&
                                partner?.lastActive != null &&
                                DateTime.now().difference(partner!.lastActive!).inMinutes < 2)
                            ? const Color(0xFF10B981)
                            : LoveraColors.primary,
                        glowColor: (partner?.isAppOpen == true &&
                                partner?.lastActive != null &&
                                DateTime.now().difference(partner!.lastActive!).inMinutes < 2)
                            ? const Color(0xFF10B981).withValues(alpha: 0.5)
                            : LoveraColors.primary.withValues(alpha: 0.35),
                        isMe: false,
                        isOnline: (partner?.isAppOpen == true &&
                            partner?.lastActive != null &&
                            DateTime.now().difference(partner!.lastActive!).inMinutes < 2),
                        isDark: isDark,
                        onTap: () => _animatedFlightMove(effectivePartnerPos, 16.0),
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
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  if (myLatLng != null && partnerLatLng != null)
                    _GlassButton(
                      icon: Icons.all_inclusive_rounded,
                      iconColor: LoveraColors.primary,
                      tooltip: 'İkimizi Göster',
                      isDark: isDark,
                      onTap: () {
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
                // Snap Tarzı Hızlı Işınlanma Yüzen Butonları (Sol: Partner, Sağ: Ben)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, left: 2, right: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Partnerin Yanına Uç Butonu
                      if (partnerLatLng != null)
                        _SnapQuickActionButton(
                          title: '${partner?.name ?? "Partner"}\'a Uç',
                          subtitle: partner?.city ?? 'Konuma Git',
                          avatarUrl: partner?.avatarUrl,
                          fallbackIcon: Icons.favorite_rounded,
                          accentColor: LoveraColors.primary,
                          isDark: isDark,
                          onTap: () => _animatedFlightMove(partnerLatLng, 16.0),
                        )
                      else
                        const SizedBox.shrink(),

                      // Kendi Konumuma Uç Butonu
                      if (myLatLng != null)
                        _SnapQuickActionButton(
                          title: 'Bana Dön',
                          subtitle: 'Konumum',
                          fallbackIcon: Icons.my_location_rounded,
                          accentColor: const Color(0xFF388AF6),
                          isDark: isDark,
                          onTap: () async {
                            DeviceService().syncStatusToFirebase();
                            _animatedFlightMove(myLatLng, 16.0);
                          },
                        )
                      else
                        const SizedBox.shrink(),
                    ],
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
  });

  final String name;
  final String? avatarUrl;
  final int? batteryLevel;
  final Color borderColor;
  final Color glowColor;
  final bool isMe;
  final bool isOnline;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Üst Snap Bilgi Hapı: İsim + Canlı Durum + Pil Durumu
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E212B) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isOnline
                      ? const Color(0xFF10B981)
                      : (isDark ? Colors.white.withValues(alpha: 0.15) : borderColor.withValues(alpha: 0.3)),
                  width: isOnline ? 1.8 : 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isOnline
                        ? const Color(0xFF10B981).withValues(alpha: 0.4)
                        : Colors.black.withValues(alpha: isDark ? 0.35 : 0.14),
                    blurRadius: isOnline ? 10 : 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 80),
                    child: Text(
                      name,
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
                        ? Image.network(
                            avatarUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildFallbackIcon(),
                          )
                        : _buildFallbackIcon(),
                  ),
                ),

                // 4. Alt köşe minik rozet (Kalp veya Ben simgesi)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 17,
                    height: 17,
                    decoration: BoxDecoration(
                      color: isOnline ? const Color(0xFF10B981) : borderColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? const Color(0xFF22252E) : Colors.white,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        isMe ? Icons.near_me_rounded : Icons.favorite_rounded,
                        color: Colors.white,
                        size: 9.5,
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

/// Snap Hızlı Işınlanma Düğmesi
class _SnapQuickActionButton extends StatelessWidget {
  const _SnapQuickActionButton({
    required this.title,
    required this.subtitle,
    this.avatarUrl,
    required this.fallbackIcon,
    required this.accentColor,
    required this.isDark,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String? avatarUrl;
  final IconData fallbackIcon;
  final Color accentColor;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF1E212A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E2022);

    return InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.1) : accentColor.withValues(alpha: 0.25),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black.withValues(alpha: 0.4) : accentColor.withValues(alpha: 0.2),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: accentColor, width: 2),
              ),
              child: ClipOval(
                child: avatarUrl != null && avatarUrl!.isNotEmpty
                    ? Image.network(avatarUrl!, fit: BoxFit.cover)
                    : Icon(fallbackIcon, color: accentColor, size: 16),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
              ],
            ),
          ],
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

