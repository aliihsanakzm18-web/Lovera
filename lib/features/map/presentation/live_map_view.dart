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
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';

class LiveMapView extends ConsumerStatefulWidget {
  const LiveMapView({super.key});

  @override
  ConsumerState<LiveMapView> createState() => _LiveMapViewState();
}

class _LiveMapViewState extends ConsumerState<LiveMapView> with TickerProviderStateMixin {
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    DeviceService().syncStatusToFirebase();
  }

  /// Snap Map Uçuş Animasyonu (Flight Animation):
  /// Önce yukarı doğru zoom-out yapar, havalanır, hedef koordinata kayar ve hedefe yumuşakça zoom-in yapar
  void _animatedFlightMove(LatLng destLocation, double targetZoom) {
    final startLoc = _mapController.camera.center;
    final startZoom = _mapController.camera.zoom;

    // Aradaki mesafeye göre tepe noktası (uçuş irtifası) zoom seviyesi belirle
    final distMeters = Geolocator.distanceBetween(
      startLoc.latitude,
      startLoc.longitude,
      destLocation.latitude,
      destLocation.longitude,
    );
    
    // Kısa mesafede az, şehirlerarası mesafede daha yüksekten uç
    final double apexZoom = distMeters > 50000 ? 7.5 : (startZoom < targetZoom ? startZoom - 1.5 : targetZoom - 1.5);

    final controller = AnimationController(
      duration: Duration(milliseconds: distMeters > 50000 ? 1100 : 750),
      vsync: this,
    );

    final Animation<double> curve = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubicEmphasized,
    );

    controller.addListener(() {
      final t = curve.value;
      // Konum doğrusal geçişi
      final currentLat = startLoc.latitude + (destLocation.latitude - startLoc.latitude) * t;
      final currentLng = startLoc.longitude + (destLocation.longitude - startLoc.longitude) * t;

      // Parabolik zoom eğrisi: Başlangıç -> Tepe (uçuş irtifası) -> Hedef zoom
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

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    controller.forward();
  }

  double? _roadDistanceMeters;
  bool _calculatingRoad = false;
  LatLng? _lastRouteStart;
  LatLng? _lastRouteEnd;

  Future<void> _fetchRoadDistance(LatLng start, LatLng end) async {
    if (_calculatingRoad) return;
    if (_lastRouteStart == start && _lastRouteEnd == end) return;
    _calculatingRoad = true;
    _lastRouteStart = start;
    _lastRouteEnd = end;

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=false',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final dist = (routes[0]['distance'] as num?)?.toDouble();
          if (dist != null && mounted) {
            setState(() {
              _roadDistanceMeters = dist;
            });
            return;
          }
        }
      }
    } catch (_) {} finally {
      _calculatingRoad = false;
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
    final theme = Theme.of(context);
    final partner = ref.watch(partnerProvider);
    final currentUser = ref.watch(currentUserProvider);

    final LatLng? myLatLng = (currentUser?.lat != null && currentUser?.lng != null)
        ? LatLng(currentUser!.lat!, currentUser.lng!)
        : null;

    final LatLng? partnerLatLng = (partner?.lat != null && partner?.lng != null)
        ? LatLng(partner!.lat!, partner.lng!)
        : null;

    if (myLatLng != null && partnerLatLng != null) {
      if (_lastRouteStart != myLatLng || _lastRouteEnd != partnerLatLng) {
        _fetchRoadDistance(myLatLng, partnerLatLng);
      }
    }

    final double? displayDistance = _roadDistanceMeters ??
        ((myLatLng != null && partnerLatLng != null)
            ? Geolocator.distanceBetween(
                myLatLng.latitude,
                myLatLng.longitude,
                partnerLatLng.latitude,
                partnerLatLng.longitude,
              ) * 1.25 // Yol viraj payı yaklaşık çarpanı
            : null);

    final initialCenter = myLatLng ?? partnerLatLng ?? const LatLng(39.0, 35.0);
    final initialZoom = (myLatLng != null || partnerLatLng != null) ? 14.5 : 6.0;

    return Scaffold(
      backgroundColor: const Color(0xFFE5E9EC),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: initialZoom,
              minZoom: 3.0,
              maxZoom: 19.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate, // Stabil 60fps pan & pinch zoom
              ),
            ),
            children: [
              // Google Maps ultra-hızlı CDN tile katmanı (Snap Map akıcılığı, sıfır takılma, Türkçe etiketler)
              TileLayer(
                urlTemplate: 'https://{s}.google.com/vt/lyrs=m&hl=tr&x={x}&y={y}&z={z}',
                subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
                userAgentPackageName: 'com.lovera.app.lovera',
                maxZoom: 20,
                maxNativeZoom: 20,
                keepBuffer: 4,
                panBuffer: 2,
              ),
              // Snap Map avatar pinleri
              MarkerLayer(
                markers: [
                  if (myLatLng != null)
                    Marker(
                      point: myLatLng,
                      width: 90,
                      height: 95,
                      alignment: Alignment.topCenter,
                      child: _SnapAvatarMarker(
                        name: currentUser?.name ?? 'Ben',
                        avatarUrl: currentUser?.avatarUrl,
                        borderColor: const Color(0xFF388AF6), // Canlı mavi rozet
                        isMe: true,
                        onTap: () => _animatedFlightMove(myLatLng, 16.0),
                      ),
                    ),
                  if (partnerLatLng != null)
                    Marker(
                      point: partnerLatLng,
                      width: 90,
                      height: 95,
                      alignment: Alignment.topCenter,
                      child: _SnapAvatarMarker(
                        name: partner?.name ?? 'Partner',
                        avatarUrl: partner?.avatarUrl,
                        borderColor: const Color(0xFFFF2A6D), // Canlı pembe kalp rozet
                        isMe: false,
                        onTap: () => _animatedFlightMove(partnerLatLng, 16.0),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Üst Bar: Geri Dönüş & İkimiz Tuşu
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _GlassButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    iconSize: 18,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  if (myLatLng != null && partnerLatLng != null)
                    _GlassButton(
                      icon: Icons.favorite_rounded,
                      iconColor: const Color(0xFFFF2A6D),
                      tooltip: 'İkimizi Göster',
                      onTap: () {
                        final bounds = LatLngBounds.fromPoints([myLatLng, partnerLatLng]);
                        _mapController.fitCamera(
                          CameraFit.bounds(
                            bounds: bounds,
                            padding: const EdgeInsets.symmetric(horizontal: 65, vertical: 160),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),

          // Alt Bölüm: Snap Map Tarzı Hızlı Işınlanma Butonları (Partnerime Uç & Konumuma Uç) + Bilgi Kartı
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Snap Tarzı Hızlı Işınlanma Yüzen Butonları (Sol: Partner, Sağ: Ben)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, left: 4, right: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Partnerin Yanına Uç Butonu (Snap Arkadaş Rozeti)
                      if (partnerLatLng != null)
                        InkWell(
                          borderRadius: BorderRadius.circular(30),
                          onTap: () => _animatedFlightMove(partnerLatLng, 16.0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: const Color(0xFFFF2A6D).withValues(alpha: 0.3), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF2A6D).withValues(alpha: 0.25),
                                  blurRadius: 16,
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
                                    color: const Color(0xFFFF2A6D).withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: const Color(0xFFFF2A6D), width: 2),
                                  ),
                                  child: ClipOval(
                                    child: partner?.avatarUrl != null && partner!.avatarUrl!.isNotEmpty
                                        ? Image.network(partner.avatarUrl!, fit: BoxFit.cover)
                                        : const Icon(Icons.favorite_rounded, color: Color(0xFFFF2A6D), size: 16),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${partner?.name ?? "Partner"}\'a Uç',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF1E2022),
                                      ),
                                    ),
                                    Text(
                                      partner?.city ?? 'Konumu gör',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFFF2A6D),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        const SizedBox.shrink(),

                      // Kendi Konumuma Uç Butonu (Snap Hedef Butonu)
                      if (myLatLng != null)
                        InkWell(
                          borderRadius: BorderRadius.circular(30),
                          onTap: () async {
                            DeviceService().syncStatusToFirebase();
                            _animatedFlightMove(myLatLng, 16.0);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: const Color(0xFF388AF6).withValues(alpha: 0.3), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF388AF6).withValues(alpha: 0.25),
                                  blurRadius: 16,
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
                                    color: const Color(0xFF388AF6).withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: const Color(0xFF388AF6), width: 2),
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.my_location_rounded, color: Color(0xFF388AF6), size: 16),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Bana Dön',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF1E2022),
                                      ),
                                    ),
                                    Text(
                                      'Konumum',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF388AF6),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
                ),

                // Alt Mesafe ve Durum Kartı (Dokunulduğunda da Partner'a Uçar)
                Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(26),
                      onTap: () {
                        if (partnerLatLng != null) {
                          _animatedFlightMove(partnerLatLng, 16.0);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFF5376), Color(0xFFFF2A6D)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF2A6D).withValues(alpha: 0.35),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 24),
                            ),
                            const SizedBox(width: 12),
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
                                      color: Colors.black.withValues(alpha: 0.45),
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    displayDistance != null
                                        ? _formatDistance(displayDistance)
                                        : (partner == null ? 'Partner bekleniyor' : 'Yol hesaplanıyor...'),
                                    style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF1E2022),
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  if (partner?.city != null) ...[
                                    const SizedBox(height: 1),
                                    Text(
                                      '📍 ${partner!.name} şu an ${partner.city}\'de',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF2A6D).withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.flight_takeoff_rounded, color: Color(0xFFFF2A6D), size: 18),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ).animate().slideY(begin: 0.2, duration: 350.ms, curve: Curves.easeOut),
          ),
        ],
      ),
    );
  }
}

/// Snap Map Tarzı Avatar Pin Tasarımı (Bitmoji hissi, parlak gölge ve isim etiketi)
class _SnapAvatarMarker extends StatelessWidget {
  const _SnapAvatarMarker({
    required this.name,
    this.avatarUrl,
    required this.borderColor,
    required this.isMe,
    required this.onTap,
  });

  final String name;
  final String? avatarUrl;
  final Color borderColor;
  final bool isMe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // İsim Rozeti (Snap Map hap tasarımı)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor.withValues(alpha: 0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isMe ? const Color(0xFF388AF6) : const Color(0xFFFF2A6D),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  name,
                  style: const TextStyle(
                    color: Color(0xFF1E2022),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          // Yuvarlak Avatar & Gölge
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: borderColor.withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 3.5),
                ),
                child: ClipOval(
                  child: avatarUrl != null && avatarUrl!.isNotEmpty
                      ? Image.network(avatarUrl!, fit: BoxFit.cover)
                      : Center(
                          child: Icon(
                            isMe ? Icons.person_rounded : Icons.favorite_rounded,
                            color: borderColor,
                            size: 24,
                          ),
                        ),
                ),
              ),
            ],
          ),
          // Pin İğnesi Ucu
          CustomPaint(
            size: const Size(12, 6),
            painter: _TrianglePainter(color: borderColor),
          ),
        ],
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

/// Snap Map Buton Stili (Glassmorphism & Hafif Gölge)
class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    this.iconSize = 20,
    this.iconColor = const Color(0xFF1E2022),
    this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final double iconSize;
  final Color iconColor;
  final String? tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, size: iconSize, color: iconColor),
        tooltip: tooltip,
        onPressed: onTap,
      ),
    );
  }
}

