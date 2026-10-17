import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../chat/presentation/chat_view.dart';

/// Fiziksel top modeli (Normalize masa koordinatları: [0.0..1.0] x [0.0..2.0])
class _PoolBall {
  final int id; // 0: Beyaz, 1..7: Düz, 8: Siyah, 9..15: Çizgili
  double x;
  double y;
  double vx;
  double vy;
  double rollPhase;
  double moveAngle;
  bool pocketed;
  double pocketScale;
  Offset? fallingPocket;

  _PoolBall({
    required this.id,
    required this.x,
    required this.y,
    this.pocketed = false,
    this.pocketScale = 1.0,
  })  : vx = 0.0,
        vy = 0.0,
        rollPhase = 0.0,
        moveAngle = 0.0;

  bool get isCue => id == 0;
  bool get isEight => id == 8;
  bool get isSolid => id >= 1 && id <= 7;
  bool get isStripe => id >= 9 && id <= 15;

  Map<String, dynamic> toMap() => {
        'id': id,
        'x': double.parse(x.toStringAsFixed(5)),
        'y': double.parse(y.toStringAsFixed(5)),
        'pocketed': pocketed,
      };

  factory _PoolBall.fromMap(Map<String, dynamic> m) {
    final isPock = m['pocketed'] == true;
    return _PoolBall(
      id: (m['id'] as num?)?.toInt() ?? 0,
      x: (m['x'] as num?)?.toDouble() ?? 0.5,
      y: (m['y'] as num?)?.toDouble() ?? 1.0,
      pocketed: isPock,
      pocketScale: isPock ? 0.0 : 1.0,
    );
  }
}

class BilliardsGameView extends ConsumerStatefulWidget {
  const BilliardsGameView({super.key});

  @override
  ConsumerState<BilliardsGameView> createState() => _BilliardsGameViewState();
}

class _BilliardsGameViewState extends ConsumerState<BilliardsGameView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // 8 Ball Pool Standart Masa Geometri Sabitleri (1.0 x 2.0 oran)
  static const double _tableW = 1.0;
  static const double _tableH = 2.0;
  static const double _cushion = 0.064;
  static const double _ballRadius = 0.0285;
  static const double _pocketRadius = 0.054;

  // 6 Delik (Pocket) Merkezleri (Ahşap köşe/orta ceplerin tam yuvası)
  static const List<Offset> _pockets = [
    Offset(0.056, 0.056), // Sol Üst Köşe
    Offset(0.944, 0.056), // Sağ Üst Köşe
    Offset(0.042, 1.000), // Sol Orta Cep
    Offset(0.958, 1.000), // Sağ Orta Cep
    Offset(0.056, 1.944), // Sol Alt Köşe
    Offset(0.944, 1.944), // Sağ Alt Köşe
  ];

  // 12 Delik Ağzı Köşesi (Pocket Jaws / Knuckles) — Gerçek 8 Ball Pool'da delik ağzına çarpan topun sekmesini sağlar
  static const double _jawRadius = 0.012;
  static const List<Offset> _pocketJaws = [
    // Sol Üst Köşe Çeneleri
    Offset(0.118, 0.064),
    Offset(0.064, 0.118),
    // Sağ Üst Köşe Çeneleri
    Offset(0.882, 0.064),
    Offset(0.936, 0.118),
    // Sol Orta Cep Çeneleri
    Offset(0.064, 0.936),
    Offset(0.064, 1.064),
    // Sağ Orta Cep Çeneleri
    Offset(0.936, 0.936),
    Offset(0.936, 1.064),
    // Sol Alt Köşe Çeneleri
    Offset(0.064, 1.882),
    Offset(0.118, 1.936),
    // Sağ Alt Köşe Çeneleri
    Offset(0.936, 1.882),
    Offset(0.882, 1.936),
  ];

  late Ticker _ticker;

  List<_PoolBall> _balls = [];
  bool _isSimulating = false;
  bool _isMyShotSimulation = false;
  int _lastSimulatedShotSeq = 0;

  // 8 Ball Pool Nişan, Falso (Spin / English) ve Çek-Bırak Istaka Mekanikleri
  double _aimAngle = -math.pi / 2; // Yukarı doğru başlangıç açısı
  Offset? _lastTablePanPos; // Açısal delta (8 Ball Pool sürükleme) için son dokunma noktası
  double _fineTunerScrollOffset = 0.0; // Hassas nişan tekerleği (Fine-Tune Wheel) kaydırma fazı

  // Falso (Cue Ball Spin): dx (-1 sol falso .. +1 sağ falso), dy (-1 üst falso/follow .. +1 alt falso/draw)
  Offset _cueSpin = Offset.zero;
  Offset _activeShotSpin = Offset.zero;
  bool _firstObjectCollisionHandled = false;

  // Çek-Bırak Istaka Gücü (0.0 .. 1.0)
  double _pullPower = 0.0;
  bool _isPullingCue = false;
  bool _isMovingCueBall = false;
  double _pullStartY = 0.0;
  Offset? _tablePullStartLocal;
  int _lastHapticTickLevel = 0;
  bool _isStrikingAnimation = false;

  // Atış kuralları takibi
  int? _firstHitBallId;
  final List<int> _pocketedInThisShot = [];

  // Oyun içi durumlar
  String? _currentCoupleId;
  bool? _currentIsWhite;
  bool _hasActiveGame = false;
  bool _isExitingDueToPartner = false;
  String? _lastVibratedTurnKey;
  String? _shotBannerMessage;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _balls = _createInitialRack();
    _ticker = createTicker(_onTick);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(isChessScreenOpenProvider.notifier).state = true;
      }
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _ticker.dispose();
    WidgetsBinding.instance.removeObserver(this);
    ref.read(isChessScreenOpenProvider.notifier).state = false;
    _setOnlineStatus(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _setOnlineStatus(false);
      _autoExitOnLeave();
    } else if (state == AppLifecycleState.paused) {
      _setOnlineStatus(false);
    } else if (state == AppLifecycleState.resumed) {
      _setOnlineStatus(true);
    }
  }

  void _setOnlineStatus(bool isOnline) {
    final coupleId = _currentCoupleId ?? ref.read(coupleIdProvider);
    final isWhite = _currentIsWhite;
    if (coupleId != null && coupleId.isNotEmpty && isWhite != null) {
      DatabaseService().setGameOnlineStatus(
        coupleId: coupleId,
        gameType: 'billiards',
        isPlayer1: isWhite,
        isOnline: isOnline,
      );
    }
  }

  void _autoExitOnLeave() {
    final coupleId = _currentCoupleId ?? ref.read(coupleIdProvider);
    final myUid = DatabaseService().uid;
    if (coupleId != null && coupleId.isNotEmpty && myUid != null) {
      DatabaseService().exitGame(
        coupleId: coupleId,
        gameType: 'billiards',
        exitUid: myUid,
        exitReason: 'Partnerin bilardo masasından ayrıldı.',
      );
    }
  }

  void _showBanner(String msg) {
    _bannerTimer?.cancel();
    if (!mounted) return;
    setState(() => _shotBannerMessage = msg);
    _bannerTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _shotBannerMessage = null);
    });
  }

  /// Standart 8 Ball Pool Sıkı Üçgen Dizilimi (İki telefonda da birebir aynı ve kusursuz simetrik)
  static List<_PoolBall> _createInitialRack() {
    final list = <_PoolBall>[];
    // 0: Beyaz İmpa (Cue Ball) - Head String üzerinde
    list.add(_PoolBall(id: 0, x: 0.5, y: 1.52));

    // Üçgen tepe noktası (Apex / Foot spot)
    const double apexX = 0.5;
    const double apexY = 0.54;
    const double r = _ballRadius * 1.002;
    final double rowDy = r * math.sqrt(3);

    final rackIds = <List<int>>[
      [1],
      [9, 2],
      [10, 8, 3],
      [4, 11, 12, 5],
      [13, 6, 14, 7, 15],
    ];

    for (int row = 0; row < rackIds.length; row++) {
      final rowBalls = rackIds[row];
      final double y = apexY - row * rowDy;
      final double startX = apexX - (row * r);
      for (int col = 0; col < rowBalls.length; col++) {
        final double x = startX + col * (2 * r);
        list.add(_PoolBall(id: rowBalls[col], x: x, y: y));
      }
    }

    list.sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  static Map<String, dynamic> buildInitialGameData() {
    final balls = _createInitialRack().map((b) => b.toMap()).toList();
    return {
      'balls': balls,
      'turn': 'w',
      'whiteGroup': null,
      'blackGroup': null,
      'ballInHand': true, // 8 Ball Pool açılışta beyaz top çizgi gerisinde serbesttir
      'shotSeq': 0,
      'lastShot': null,
      'lastEventText': '8 Ball Pool Başladı! Nişan al ve ıstakayı çekip bırak 🎱',
    };
  }

  /// 16 Alt Adımlı (Sub-stepping) Profesyonel 8 Ball Pool Fizik Motoru
  void _onTick(Duration elapsed) {
    if (!_isSimulating) return;

    // Deterministik fizik adımı (Her iki cihazda da birebir aynı dağılma sonucu vermesi için sabit zaman adımı)
    const double fixedDt = 1.0 / 60.0;
    const int subSteps = 16;
    const double stepDt = fixedDt / subSteps;

    for (int s = 0; s < subSteps; s++) {
      _stepPhysics(stepDt);
    }

    // Deliğe düşen topların yuvaya çekilme animasyonu
    bool anyAnimatingPocket = false;
    for (final b in _balls) {
      if (b.pocketed && b.pocketScale > 0.0) {
        b.pocketScale = math.max(0.0, b.pocketScale - fixedDt * 5.8);
        if (b.fallingPocket != null) {
          b.x += (b.fallingPocket!.dx - b.x) * 0.38;
          b.y += (b.fallingPocket!.dy - b.y) * 0.38;
        }
        if (b.pocketScale > 0.01) anyAnimatingPocket = true;
      }
    }

    bool anyMoving = false;
    for (final b in _balls) {
      if (!b.pocketed) {
        final speed = math.sqrt(b.vx * b.vx + b.vy * b.vy);
        if (speed > 0.004) {
          anyMoving = true;
        } else {
          b.vx = 0.0;
          b.vy = 0.0;
        }
      }
    }

    setState(() {});

    if (!anyMoving && !anyAnimatingPocket) {
      _ticker.stop();
      _isSimulating = false;
      _cueSpin = Offset.zero; // Yeni atış için falsoyu merkeze sıfırla
      if (_isMyShotSimulation) {
        _isMyShotSimulation = false;
        _evaluateShotAndSync();
      }
    }
  }

  void _stepPhysics(double dt) {
    const double minX = _cushion + _ballRadius;
    const double maxX = _tableW - _cushion - _ballRadius;
    const double minY = _cushion + _ballRadius;
    const double maxY = _tableH - _cushion - _ballRadius;

    // 1. Topların hareketi, çuha sürtünmesi, cep çekimi, delik çenesi (jaw) ve bant sekmeleri
    for (final b in _balls) {
      if (b.pocketed) continue;

      b.x += b.vx * dt;
      b.y += b.vy * dt;

      final double speed = math.sqrt(b.vx * b.vx + b.vy * b.vy);
      if (speed > 0.0001) {
        b.moveAngle = math.atan2(b.vy, b.vx);
        b.rollPhase = (b.rollPhase + (speed * dt) / _ballRadius) % (math.pi * 2);

        // 8 Ball Pool Hızlı ve Akıcı Çuha Sürtünmesi
        final double slideDrag = speed * 0.32;
        final double rollingFriction = speed > 0.40 ? 0.22 : 0.28;
        final double totalDecel = (slideDrag + rollingFriction) * dt;

        final double newSpeed = math.max(0.0, speed - totalDecel);
        b.vx = (b.vx / speed) * newSpeed;
        b.vy = (b.vy / speed) * newSpeed;
      }

      // Delik (Pocket) kontrolü
      bool fellInPocket = false;
      for (final p in _pockets) {
        final double dx = p.dx - b.x;
        final double dy = p.dy - b.y;
        final double dist = math.sqrt(dx * dx + dy * dy);

        // Cep ağzı eğimi
        if (dist < _pocketRadius * 1.25 && dist >= _pocketRadius * 0.85) {
          final double pull = 1.75 * (1.0 - dist / (_pocketRadius * 1.25));
          b.vx += (dx / dist) * pull * dt;
          b.vy += (dy / dist) * pull * dt;
        }

        if (dist < _pocketRadius * 0.86) {
          b.pocketed = true;
          b.pocketScale = 1.0;
          b.fallingPocket = p;
          b.vx = 0;
          b.vy = 0;
          if (!_pocketedInThisShot.contains(b.id)) {
            _pocketedInThisShot.add(b.id);
          }
          HapticFeedback.mediumImpact();
          fellInPocket = true;
          break;
        }
      }
      if (fellInPocket) continue;

      // Delik Ağzı Köşeleri (Pocket Jaws / Knuckles) Çarpışması
      for (final jaw in _pocketJaws) {
        final double jdx = b.x - jaw.dx;
        final double jdy = b.y - jaw.dy;
        const double minJawDist = _ballRadius + _jawRadius;
        final double distSq = jdx * jdx + jdy * jdy;
        if (distSq < minJawDist * minJawDist && distSq > 0.000001) {
          final double dist = math.sqrt(distSq);
          final double nx = jdx / dist;
          final double ny = jdy / dist;
          b.x += nx * (minJawDist - dist);
          b.y += ny * (minJawDist - dist);

          final double vn = b.vx * nx + b.vy * ny;
          if (vn < 0) {
            b.vx -= 1.72 * vn * nx;
            b.vy -= 1.72 * vn * ny;
          }
        }
      }

      // Düz Bant (Cushion Rail) Çarpmaları + Yan Falso (Side Spin / English) Etkisi
      final bool inTopCornerGap = b.y < 0.118;
      final bool inBotCornerGap = b.y > 1.882;
      final bool inMidPocketGap = b.y > 0.936 && b.y < 1.064;
      final bool inLeftCornerGap = b.x < 0.118;
      final bool inRightCornerGap = b.x > 0.882;

      const double railRestitution = 0.80;
      const double railTangentHold = 0.95;
      final double sideSpinKick = (b.id == 0) ? (_activeShotSpin.dx * 0.28) : 0.0;

      if (!inTopCornerGap && !inBotCornerGap && !inMidPocketGap) {
        if (b.x < minX) {
          b.x = minX;
          if (b.vx < 0) {
            final impactSpd = b.vx.abs();
            b.vx = -b.vx * railRestitution;
            b.vy = b.vy * railTangentHold + impactSpd * sideSpinKick;
            if (b.id == 0) _activeShotSpin = Offset(_activeShotSpin.dx * 0.4, _activeShotSpin.dy);
          }
        } else if (b.x > maxX) {
          b.x = maxX;
          if (b.vx > 0) {
            final impactSpd = b.vx.abs();
            b.vx = -b.vx * railRestitution;
            b.vy = b.vy * railTangentHold - impactSpd * sideSpinKick;
            if (b.id == 0) _activeShotSpin = Offset(_activeShotSpin.dx * 0.4, _activeShotSpin.dy);
          }
        }
      }

      if (!inLeftCornerGap && !inRightCornerGap) {
        if (b.y < minY) {
          b.y = minY;
          if (b.vy < 0) {
            final impactSpd = b.vy.abs();
            b.vy = -b.vy * railRestitution;
            b.vx = b.vx * railTangentHold + impactSpd * sideSpinKick;
            if (b.id == 0) _activeShotSpin = Offset(_activeShotSpin.dx * 0.4, _activeShotSpin.dy);
          }
        } else if (b.y > maxY) {
          b.y = maxY;
          if (b.vy > 0) {
            final impactSpd = b.vy.abs();
            b.vy = -b.vy * railRestitution;
            b.vx = b.vx * railTangentHold - impactSpd * sideSpinKick;
            if (b.id == 0) _activeShotSpin = Offset(_activeShotSpin.dx * 0.4, _activeShotSpin.dy);
          }
        }
      }
    }

    // 2. Toplar Arası Elastik Çarpışma + Beyaz Top Falso (Top Spin Follow / Back Spin Draw)
    final int n = _balls.length;
    const double minDist = _ballRadius * 2.0;

    for (int iter = 0; iter < 2; iter++) {
      for (int i = 0; i < n; i++) {
        final b1 = _balls[i];
        if (b1.pocketed) continue;

        for (int j = i + 1; j < n; j++) {
          final b2 = _balls[j];
          if (b2.pocketed) continue;

          final double dx = b2.x - b1.x;
          final double dy = b2.y - b1.y;
          final double distSq = dx * dx + dy * dy;

          if (distSq < minDist * minDist && distSq > 0.00000001) {
            final double dist = math.sqrt(distSq);
            final double nx = dx / dist;
            final double ny = dy / dist;

            if (_firstHitBallId == null) {
              if (b1.id == 0) _firstHitBallId = b2.id;
              if (b2.id == 0) _firstHitBallId = b1.id;
            }

            final double overlap = (minDist - dist) * 0.502;
            b1.x -= nx * overlap;
            b1.y -= ny * overlap;
            b2.x += nx * overlap;
            b2.y += ny * overlap;

            final double rvx = b1.vx - b2.vx;
            final double rvy = b1.vy - b2.vy;
            final double velAlongNormal = rvx * nx + rvy * ny;

            if (velAlongNormal > 0) {
              const double ballRestitution = 0.968;
              final double impulse = (1.0 + ballRestitution) * 0.5 * velAlongNormal;

              b1.vx -= impulse * nx;
              b1.vy -= impulse * ny;
              b2.vx += impulse * nx;
              b2.vy += impulse * ny;

              // Beyaz topun ilk çarptığı hedef topta Üst Falso (Follow) / Alt Falso (Backspin / Draw) etkisi
              if (!_firstObjectCollisionHandled && (b1.id == 0 || b2.id == 0)) {
                _firstObjectCollisionHandled = true;
                final _PoolBall cue = (b1.id == 0) ? b1 : b2;
                final double colDirX = (b1.id == 0) ? nx : -nx;
                final double colDirY = (b1.id == 0) ? ny : -ny;
                // _activeShotSpin.dy < 0 ise Üst Falso (İleri takip), > 0 ise Alt Falso (Geri çekme / Sırt)
                final double followOrDraw = -_activeShotSpin.dy;
                if (followOrDraw.abs() > 0.05) {
                  final double spinBoost = impulse * followOrDraw * 0.68;
                  cue.vx += colDirX * spinBoost;
                  cue.vy += colDirY * spinBoost;
                }
              }

              if (velAlongNormal > 0.45 && iter == 0) {
                HapticFeedback.lightImpact();
              }
            }
          }
        }
      }
    }
  }

  /// Vuruş başlat (Hem kendi vuruşumuz hem de partnerden gelen canlı vuruş için)
  void _triggerShotSimulation({
    required double vx,
    required double vy,
    required bool isMyShot,
    double? cueX,
    double? cueY,
    double spinX = 0.0,
    double spinY = 0.0,
  }) {
    final cueBall = _balls.firstWhere((b) => b.id == 0);
    cueBall.pocketed = false;
    cueBall.pocketScale = 1.0;
    if (cueX != null && cueY != null) {
      cueBall.x = cueX;
      cueBall.y = cueY;
    }
    cueBall.vx = vx;
    cueBall.vy = vy;

    _activeShotSpin = Offset(spinX, spinY);
    _firstObjectCollisionHandled = false;
    _firstHitBallId = null;
    _pocketedInThisShot.clear();
    _isSimulating = true;
    _isMyShotSimulation = isMyShot;

    HapticFeedback.heavyImpact();
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  /// Vuruş tamamlandığında 8-Top kurallarını değerlendir ve Firestore'a kaydet
  Future<void> _evaluateShotAndSync() async {
    final coupleId = _currentCoupleId;
    final isWhite = _currentIsWhite;
    final myUid = DatabaseService().uid;
    final partner = ref.read(partnerProvider);
    if (coupleId == null || isWhite == null || myUid == null) return;

    final snap = await DatabaseService().gameStream(coupleId, 'billiards').first;
    final gameData = snap.data();
    if (gameData == null) return;

    String? whiteGroup = gameData['whiteGroup'] as String?;
    String? blackGroup = gameData['blackGroup'] as String?;
    final String myTurnChar = isWhite ? 'w' : 'b';
    final String partnerTurnChar = isWhite ? 'b' : 'w';
    String? myGroup = isWhite ? whiteGroup : blackGroup;

    final bool cuePocketed = _pocketedInThisShot.contains(0);
    final bool eightPocketed = _pocketedInThisShot.contains(8);
    final List<int> objectPocketed =
        _pocketedInThisShot.where((id) => id != 0 && id != 8).toList();

    if (cuePocketed) {
      final cue = _balls.firstWhere((b) => b.id == 0);
      cue.pocketed = false;
      cue.pocketScale = 1.0;
      cue.fallingPocket = null;
      final spot = _findFreeCueSpot(0.5, 1.52);
      cue.x = spot.dx;
      cue.y = spot.dy;
      cue.vx = 0;
      cue.vy = 0;
    }

    String? newStatus;
    String? winnerUid;
    String? winnerReason;
    String nextTurn = partnerTurnChar;
    bool nextBallInHand = false;
    String eventText = '';

    // 1. Siyah 8-Top deliğe girdiyse:
    if (eightPocketed) {
      bool allMyBallsCleared = false;
      if (myGroup != null) {
        final myBallIds = myGroup == 'solids'
            ? [1, 2, 3, 4, 5, 6, 7]
            : [9, 10, 11, 12, 13, 14, 15];
        allMyBallsCleared = _balls
            .where((b) => myBallIds.contains(b.id))
            .every((b) => b.pocketed);
      }

      if (allMyBallsCleared && !cuePocketed) {
        newStatus = 'completed';
        winnerUid = myUid;
        winnerReason = '8 Topu Deliğe Soktu 🎱🏆';
        eventText = 'Muhteşem vuruş! 8 Top delikte, oyunu kazandın! 🎉';
      } else {
        newStatus = 'completed';
        winnerUid = partner?.id ?? '';
        winnerReason = cuePocketed
            ? '8 Topta Beyaz Top Faulü'
            : '8 Topu Erken Soktu (Faul)';
        eventText = 'Eyvah! 8 Top erken düştü veya faul oldu.';
      }
    } else {
      // 2. Henüz grup seçilmemişse ve top girdiyse:
      if (myGroup == null && objectPocketed.isNotEmpty && !cuePocketed) {
        final firstObj = objectPocketed.first;
        final assigned = (firstObj >= 1 && firstObj <= 7) ? 'solids' : 'stripes';
        final oppAssigned = assigned == 'solids' ? 'stripes' : 'solids';
        if (isWhite) {
          whiteGroup = assigned;
          blackGroup = oppAssigned;
        } else {
          blackGroup = assigned;
          whiteGroup = oppAssigned;
        }
        myGroup = assigned;
        final groupName = assigned == 'solids' ? 'Düz (1-7)' : 'Çizgili (9-15)';
        eventText = 'Masada gruplar belirlendi: $groupName! Sıra sende devam ediyor 🔥';
        nextTurn = myTurnChar;
      } else {
        // 3. Faul kontrolü
        bool isFoul = false;
        String foulReason = '';

        if (cuePocketed) {
          isFoul = true;
          foulReason = 'Faul! Beyaz top deliğe düştü.';
        } else if (_firstHitBallId == null) {
          isFoul = true;
          foulReason = 'Faul! Beyaz top hiçbir topa değmedi.';
        } else if (myGroup != null) {
          final myBallIds = myGroup == 'solids'
              ? [1, 2, 3, 4, 5, 6, 7]
              : [9, 10, 11, 12, 13, 14, 15];
          final bool remainingMyBalls = _balls
              .where((b) => myBallIds.contains(b.id))
              .any((b) => !b.pocketed);

          if (remainingMyBalls && !myBallIds.contains(_firstHitBallId)) {
            isFoul = true;
            foulReason = 'Faul! Önce kendi grubundaki topa vurmalısın.';
          } else if (!remainingMyBalls && _firstHitBallId != 8) {
            isFoul = true;
            foulReason = 'Faul! Sadece 8 numaralı siyah topa vurabilirsin.';
          }
        }

        if (isFoul) {
          nextTurn = partnerTurnChar;
          nextBallInHand = true;
          eventText = '$foulReason Rakip beyaz topu istediği yere koyabilir!';
        } else {
          bool pocketedOwn = false;
          if (myGroup == null) {
            pocketedOwn = objectPocketed.isNotEmpty;
          } else {
            final myBallIds = myGroup == 'solids'
                ? [1, 2, 3, 4, 5, 6, 7]
                : [9, 10, 11, 12, 13, 14, 15];
            pocketedOwn = objectPocketed.any((id) => myBallIds.contains(id));
          }

          if (pocketedOwn) {
            nextTurn = myTurnChar;
            eventText = 'Harika isabet! Top delikte, sıra sende devam ediyor 🎯';
          } else {
            nextTurn = partnerTurnChar;
            eventText = 'Sıra partnerine geçti 🎱';
          }
        }
      }
    }

    _showBanner(eventText);

    final updates = <String, dynamic>{
      'balls': _balls.map((b) => b.toMap()).toList(),
      'turn': nextTurn,
      'whiteGroup': whiteGroup,
      'blackGroup': blackGroup,
      'ballInHand': nextBallInHand,
      'lastEventText': eventText,
    };

    if (newStatus != null) {
      updates['status'] = newStatus;
      updates['winnerUid'] = winnerUid;
      updates['winnerReason'] = winnerReason;
    }

    await DatabaseService().updateGameState(
      coupleId: coupleId,
      gameType: 'billiards',
      updates: updates,
    );
  }

  Offset _findFreeCueSpot(double targetX, double targetY) {
    const double minX = _cushion + _ballRadius + 0.01;
    const double maxX = _tableW - _cushion - _ballRadius - 0.01;
    const double minY = _cushion + _ballRadius + 0.01;
    const double maxY = _tableH - _cushion - _ballRadius - 0.01;

    double cx = targetX.clamp(minX, maxX);
    double cy = targetY.clamp(minY, maxY);

    bool overlaps(double x, double y) {
      for (final b in _balls) {
        if (b.id == 0 || b.pocketed) continue;
        final dx = b.x - x;
        final dy = b.y - y;
        if (dx * dx + dy * dy < (_ballRadius * 2.1) * (_ballRadius * 2.1)) {
          return true;
        }
      }
      return false;
    }

    if (!overlaps(cx, cy)) return Offset(cx, cy);

    for (double radius = 0.05; radius < 0.6; radius += 0.04) {
      for (double ang = 0; ang < math.pi * 2; ang += math.pi / 6) {
        final nx = (cx + math.cos(ang) * radius).clamp(minX, maxX);
        final ny = (cy + math.sin(ang) * radius).clamp(minY, maxY);
        if (!overlaps(nx, ny)) return Offset(nx, ny);
      }
    }
    return Offset(cx, cy);
  }

  /// Istaka çekilip bırakıldığında vuruşu ateşle
  Future<void> _releaseAndStrikeCue({
    required String coupleId,
    required int currentShotSeq,
  }) async {
    final double power = _pullPower;
    setState(() {
      _isPullingCue = false;
      _pullPower = 0.0;
    });

    if (power < 0.07 || _isSimulating || _isStrikingAnimation) {
      return;
    }

    setState(() => _isStrikingAnimation = true);
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    setState(() => _isStrikingAnimation = false);

    final cue = _balls.firstWhere((b) => b.id == 0);
    const double maxSpeed = 7.20;
    final double curvedPower = math.pow(power, 1.15).toDouble();
    final double speed = (0.15 + curvedPower * 0.85) * maxSpeed;
    final double vx = math.cos(_aimAngle) * speed;
    final double vy = math.sin(_aimAngle) * speed;

    final double sx = _cueSpin.dx;
    final double sy = _cueSpin.dy;

    final nextSeq = currentShotSeq + 1;
    _lastSimulatedShotSeq = nextSeq;

    _triggerShotSimulation(
      vx: vx,
      vy: vy,
      isMyShot: true,
      cueX: cue.x,
      cueY: cue.y,
      spinX: sx,
      spinY: sy,
    );

    unawaited(
      DatabaseService().updateGameState(
        coupleId: coupleId,
        gameType: 'billiards',
        updates: {
          'shotSeq': nextSeq,
          'lastShot': {
            'seq': nextSeq,
            'cueX': cue.x,
            'cueY': cue.y,
            'vx': vx,
            'vy': vy,
            'spinX': sx,
            'spinY': sy,
            'byUid': DatabaseService().uid,
          },
        },
      ),
    );
  }

  void _updatePullPowerWithHaptics(double newPower) {
    final clamped = newPower.clamp(0.0, 1.0);
    final tickLevel = (clamped * 10).floor();
    if (tickLevel != _lastHapticTickLevel) {
      _lastHapticTickLevel = tickLevel;
      HapticFeedback.selectionClick();
    }
    setState(() {
      _isPullingCue = true;
      _pullPower = clamped;
    });
  }

  /// 8 Ball Pool Falso (Spin / English) Seçim Penceresi
  void _openSpinSelectorModal(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF161922),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
              title: const Text(
                'Falso (Cue Ball Spin) 🎯',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Kırmızı vuruş noktasını sürükleyerek beyaz topa Üst (Follow), Alt (Draw/Sırt) veya Yan falso ver.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 18),
                  GestureDetector(
                    onPanDown: (d) {
                      _updateSpinFromLocal(d.localPosition, 160, setModalState);
                    },
                    onPanUpdate: (d) {
                      _updateSpinFromLocal(d.localPosition, 160, setModalState);
                    },
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          center: Alignment(-0.3, -0.3),
                          radius: 0.9,
                          colors: [Color(0xFFFFFFFF), Color(0xFFE2E8F0), Color(0xFF94A3B8)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                        border: Border.all(color: const Color(0xFF10B981), width: 3),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Artı eksen çizgileri
                          Container(width: 130, height: 1, color: Colors.black26),
                          Container(width: 1, height: 130, color: Colors.black26),
                          // Güvenli falso çemberi
                          Container(
                            width: 112,
                            height: 112,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black12, width: 1.5),
                            ),
                          ),
                          // Kırmızı tebeşir vuruş noktası
                          Transform.translate(
                            offset: Offset(_cueSpin.dx * 52, _cueSpin.dy * 52),
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFEF4444).withValues(alpha: 0.6),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _cueSpin = Offset.zero);
                      setModalState(() {});
                    },
                    icon: const Icon(Icons.center_focus_strong_rounded, color: Color(0xFF34D399), size: 18),
                    label: const Text('Merkeze Sıfırla', style: TextStyle(color: Color(0xFF34D399))),
                  ),
                ],
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Tamam', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _updateSpinFromLocal(Offset local, double size, StateSetter setModalState) {
    final double r = size / 2;
    double nx = (local.dx - r) / (r * 0.68);
    double ny = (local.dy - r) / (r * 0.68);
    final double len = math.sqrt(nx * nx + ny * ny);
    if (len > 1.0) {
      nx /= len;
      ny /= len;
    }
    HapticFeedback.selectionClick();
    setState(() => _cueSpin = Offset(nx, ny));
    setModalState(() {});
  }

  void _handlePartnerLeft(String reason) {
    if (_isExitingDueToPartner || !mounted) return;
    _isExitingDueToPartner = true;
    _hasActiveGame = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.exit_to_app_rounded, color: Color(0xFFEF4444), size: 24),
              ),
              const SizedBox(width: 10),
              const Text('Oyun Bitti', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ],
          ),
          content: Text(
            reason.isNotEmpty ? reason : 'Partnerin oyundan çıktı.',
            style: const TextStyle(fontSize: 14.5, height: 1.4),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: LoveraColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Tamam', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final coupleId = ref.watch(coupleIdProvider);
    final myUid = DatabaseService().uid;
    final partner = ref.watch(partnerProvider);
    final myName = ref.watch(userNameProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (coupleId == null || coupleId.isEmpty) {
      return Scaffold(
        backgroundColor: isDark ? LoveraColors.darkBg : LoveraColors.lightBg,
        appBar: AppBar(
          title: const Text('8 Top Bilardo 🎱'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: Text('Karşılıklı bilardo oynamak için önce partnerinizle eşleşmelisiniz 💕'),
        ),
      );
    }

    return StreamBuilder(
      stream: DatabaseService().gameStream(coupleId, 'billiards'),
      builder: (context, snapshot) {
        final gameData = snapshot.data?.data();
        final status = gameData?['status'] as String?;

        if (_hasActiveGame && (status == 'ended' || status == null)) {
          final exitReason = gameData?['exitReason'] as String? ?? 'Partnerin oyundan çıktı.';
          final exitUid = gameData?['exitUid'] as String?;
          if (exitUid != myUid) {
            _handlePartnerLeft(exitReason);
          }
        }

        if (gameData == null || !snapshot.hasData || status == null || status == 'rejected' || status == 'ended') {
          _hasActiveGame = false;
          return _buildStartLobby(
            context: context,
            isDark: isDark,
            status: status,
            coupleId: coupleId,
            myUid: myUid,
            myName: myName,
            partner: partner,
          );
        }

        if (status == 'invitation_pending') {
          final fromUid = gameData['fromUid'] as String?;
          final isSender = fromUid == myUid;
          return _buildPendingInvitationView(context, isDark, isSender);
        }

        final int shotSeq = (gameData['shotSeq'] as num?)?.toInt() ?? 0;
        final lastShot = gameData['lastShot'] as Map<String, dynamic>?;

        // Partner vuruş yaptığında anında (sıfır gecikmeyle) simülasyonu başlat:
        if (shotSeq > _lastSimulatedShotSeq && lastShot != null) {
          _lastSimulatedShotSeq = shotSeq;
          final shotBy = lastShot['byUid'] as String?;
          if (shotBy != myUid) {
            final vx = (lastShot['vx'] as num?)?.toDouble() ?? 0.0;
            final vy = (lastShot['vy'] as num?)?.toDouble() ?? 0.0;
            final cueX = (lastShot['cueX'] as num?)?.toDouble();
            final cueY = (lastShot['cueY'] as num?)?.toDouble();
            final spinX = (lastShot['spinX'] as num?)?.toDouble() ?? 0.0;
            final spinY = (lastShot['spinY'] as num?)?.toDouble() ?? 0.0;
            _triggerShotSimulation(
              vx: vx,
              vy: vy,
              isMyShot: false,
              cueX: cueX,
              cueY: cueY,
              spinX: spinX,
              spinY: spinY,
            );
          }
        }

        // Top pozisyonlarını sadece simülasyon veya top taşıma yokken güncelle.
        // Ayrıca atış yeni atılmışken vuruş bitmeden gelen eski sunucu snapshot'larının
        // dağılan topları eski dizilime (rack) sıfırlamasını engelle!
        final bool isShotInFlight = _isSimulating || (shotSeq > 0 && shotSeq > _lastSimulatedShotSeq);
        if (!isShotInFlight && !_isMovingCueBall && gameData['balls'] is List) {
          final rawBalls = gameData['balls'] as List;
          final parsed = rawBalls
              .whereType<Map>()
              .map((m) => _PoolBall.fromMap(Map<String, dynamic>.from(m)))
              .toList();
          if (parsed.length == 16) {
            _balls = parsed;
          }
        }

        final whiteUid = gameData['whitePlayerUid'] as String?;
        final whiteName = gameData['whitePlayerName'] as String? ?? '1. Oyuncu';
        final blackName = gameData['blackPlayerName'] as String? ?? '2. Oyuncu';
        final whiteReady = gameData['whiteReady'] == true;
        final blackReady = gameData['blackReady'] == true;
        final isWhite = myUid == whiteUid;
        final myReady = isWhite ? whiteReady : blackReady;
        final partnerReady = isWhite ? blackReady : whiteReady;

        final whiteRematch = gameData['whiteRematch'] == true;
        final blackRematch = gameData['blackRematch'] == true;
        final myRematch = isWhite ? whiteRematch : blackRematch;
        final partnerRematch = isWhite ? blackRematch : whiteRematch;

        final isWaitingReady = status == 'waiting_ready';
        final turn = gameData['turn'] as String? ?? 'w';
        final winnerUid = gameData['winnerUid'] as String?;
        final winnerReason = gameData['winnerReason'] as String?;
        final whiteGroup = gameData['whiteGroup'] as String?;
        final blackGroup = gameData['blackGroup'] as String?;
        final ballInHand = gameData['ballInHand'] == true;
        final lastEventText = gameData['lastEventText'] as String?;

        final myGroup = isWhite ? whiteGroup : blackGroup;
        final partnerGroup = isWhite ? blackGroup : whiteGroup;

        final isMyTurn = !isWaitingReady &&
            !_isSimulating &&
            ((turn == 'w' && isWhite) || (turn == 'b' && !isWhite));
        final isGameOver = status != 'active' && status != 'waiting_ready';

        _currentCoupleId = coupleId;
        _currentIsWhite = isWhite;
        _hasActiveGame = true;

        if (status == 'active' || status == 'waiting_ready') {
          final myOnlineKey = isWhite ? 'whiteOnline' : 'blackOnline';
          if (gameData[myOnlineKey] != true) {
            DatabaseService().setGameOnlineStatus(
              coupleId: coupleId,
              gameType: 'billiards',
              isPlayer1: isWhite,
              isOnline: true,
            );
          }
        }

        if (isMyTurn && status == 'active') {
          final turnKey = '$shotSeq-$turn';
          if (_lastVibratedTurnKey != turnKey) {
            _lastVibratedTurnKey = turnKey;
            HapticFeedback.heavyImpact();
          }
        }

        return StreamBuilder<List<ChatMessage>>(
          stream: DatabaseService().messagesStream(coupleId),
          builder: (context, chatSnapshot) {
            final messages = chatSnapshot.data ?? [];
            final unreadCount = messages.where((m) => m.senderId != myUid && !m.isRead).length;

            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                _showExitDialog(context, coupleId);
              },
              child: Scaffold(
                backgroundColor: isDark ? const Color(0xFF0B0E14) : const Color(0xFFF2F5F8),
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    onPressed: () => _showExitDialog(context, coupleId),
                  ),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '8 Ball Pool 🎱',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      Text(
                        _formatGroupName(myGroup),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark ? const Color(0xFF34D399) : const Color(0xFF0F766E),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    _buildChatActionButton(context, unreadCount, isDark),
                    IconButton(
                      tooltip: 'Yeni Oyun',
                      icon: const Icon(Icons.refresh_rounded, color: Color(0xFF10B981)),
                      onPressed: () => _confirmNewGame(context, coupleId, myUid, myName, partner),
                    ),
                    if (!isGameOver)
                      IconButton(
                        tooltip: 'Pes Et',
                        icon: const Icon(Icons.flag_outlined, color: Color(0xFFF43F5E)),
                        onPressed: () => _confirmResign(context, coupleId, myUid, partner?.id),
                      ),
                  ],
                ),
                body: SafeArea(
                  child: Column(
                    children: [
                      // Üst Oyuncu & Kalan Toplar Barı
                      _buildPlayerScoreBar(
                        myName: isWhite ? whiteName : blackName,
                        partnerName: isWhite ? blackName : whiteName,
                        myGroup: myGroup,
                        partnerGroup: partnerGroup,
                        isMyTurn: isMyTurn,
                        isGameOver: isGameOver,
                        isDark: isDark,
                      ),

                      // Bilgi / Faul / Sıra Durum Şeridi
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isMyTurn
                                ? const Color(0xFF0F766E).withValues(alpha: 0.16)
                                : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isMyTurn
                                  ? const Color(0xFF10B981).withValues(alpha: 0.45)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isSimulating
                                    ? Icons.motion_photos_on_rounded
                                    : (isMyTurn ? Icons.ads_click_rounded : Icons.hourglass_top_rounded),
                                size: 15,
                                color: isMyTurn ? const Color(0xFF10B981) : Colors.amber,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _isPullingCue
                                      ? (_pullPower < 0.07
                                          ? 'İptal için bırak, vurmak için aşağı çek...'
                                          : '🎯 Güç: %${(_pullPower * 100).round()} — Bıraktığında vurur!')
                                      : (_shotBannerMessage ??
                                          (ballInHand && isMyTurn
                                              ? '✋ Beyaz topu istediğin yere sürükleyebilirsin!'
                                              : (lastEventText ??
                                                  (isMyTurn
                                                      ? 'Nişan al ve sağdaki ıstakayı çekip bırak!'
                                                      : 'Partnerin nişan alıyor...')))),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Bilardo Masası + Sağ 8 Ball Pool Kontrol Sütunu (Falso + Hassas Tekerlek + Yaylı Istaka)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          child: Row(
                            children: [
                              // Bilardo Masası
                              Expanded(
                                child: Center(
                                  child: AspectRatio(
                                    aspectRatio: 0.5,
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final boardW = constraints.maxWidth;
                                        final boardH = constraints.maxHeight;
                                        return Stack(
                                          children: [
                                            GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onPanStart: (details) {
                                                if (!isMyTurn || _isSimulating) return;
                                                _onTablePanStart(
                                                  details.localPosition,
                                                  boardW,
                                                  boardH,
                                                  ballInHand,
                                                );
                                              },
                                              onPanUpdate: (details) {
                                                if (!isMyTurn || _isSimulating) return;
                                                _onTablePanUpdate(
                                                  details.localPosition,
                                                  boardW,
                                                  boardH,
                                                  ballInHand,
                                                );
                                              },
                                              onPanEnd: (_) {
                                                if (!isMyTurn || _isSimulating) return;
                                                _onTablePanEnd(
                                                  coupleId: coupleId,
                                                  shotSeq: shotSeq,
                                                );
                                              },
                                              child: CustomPaint(
                                                size: Size(boardW, boardH),
                                                painter: _BilliardsTablePainter(
                                                  balls: _balls,
                                                  aimAngle: _aimAngle,
                                                  pullPower: _pullPower,
                                                  cueSpin: _cueSpin,
                                                  isStriking: _isStrikingAnimation,
                                                  showCueAndAim: isMyTurn && !_isSimulating && !isGameOver,
                                                  ballInHand: ballInHand && isMyTurn,
                                                ),
                                              ),
                                            ),

                                            if (isWaitingReady)
                                              _buildWaitingReadyOverlay(
                                                coupleId: coupleId,
                                                isWhite: isWhite,
                                                myReady: myReady,
                                                partnerReady: partnerReady,
                                              ),

                                            if (isGameOver)
                                              _buildGameOverOverlay(
                                                coupleId: coupleId,
                                                isWhite: isWhite,
                                                myUid: myUid,
                                                winnerUid: winnerUid,
                                                winnerReason: winnerReason,
                                                myRematch: myRematch,
                                                partnerRematch: partnerRematch,
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(width: 8),

                              // Sağ Taraf: 8 Ball Pool Falso + Hassas Nişan Cetveli + Yaylı Çek-Bırak Istaka
                              _buildPullReleaseCueBar(
                                isMyTurn: isMyTurn && !isGameOver,
                                isDark: isDark,
                                coupleId: coupleId,
                                shotSeq: shotSeq,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 8 Ball Pool tarzı masa etkileşimi:
  /// - Beyaz topun üstünden tutup sürüklenirse (Ball-in-hand) topu taşır.
  /// - Istakanın üstünden geriye çekilirse doğrudan çek-bırak vuruş yapar.
  /// - Masanın herhangi bir yerinde sürüklenirse açısal delta (parmak hareket açısı) ile pürüzsüz nişan alır!
  void _onTablePanStart(
    Offset localPos,
    double boardW,
    double boardH,
    bool ballInHand,
  ) {
    final cue = _balls.firstWhere((b) => b.id == 0);
    final double touchNormX = (localPos.dx / boardW).clamp(0.0, 1.0);
    final double touchNormY = (localPos.dy / boardH) * 2.0;

    // 1) Ball-in-hand (Serbest Beyaz Top Yerleştirme):
    // 8 Ball Pool mantığı: Ball-in-hand açıkken masanın herhangi bir yerine dokunulduğunda
    // veya beyaz topa yakın başlandığında beyaz top doğrudan parmağın altına gelir ve taşınabilir
    if (ballInHand) {
      final freeSpot = _findFreeCueSpot(touchNormX, touchNormY);
      setState(() {
        _isMovingCueBall = true;
        cue.x = freeSpot.dx;
        cue.y = freeSpot.dy;
      });
      HapticFeedback.selectionClick();
      return;
    }

    final double dx = touchNormX - cue.x;
    final double dy = touchNormY - cue.y;

    // 2) Istaka üzerinden doğrudan geriye çekme kontrolü
    final double backDirX = -math.cos(_aimAngle);
    final double backDirY = -math.sin(_aimAngle);
    final double projAlongStick = dx * backDirX + dy * backDirY;
    final double perpDist = (dx * (-backDirY) + dy * backDirX).abs();

    if (projAlongStick > 0.03 && projAlongStick < 0.62 && perpDist < 0.08) {
      _tablePullStartLocal = localPos;
      _lastHapticTickLevel = 0;
      setState(() {
        _isPullingCue = true;
        _pullPower = 0.0;
      });
      return;
    }

    // 3) 8 Ball Pool Açısal Delta Nişan Alma başlangıcı
    _tablePullStartLocal = null;
    _isMovingCueBall = false;
    _lastTablePanPos = localPos;
  }

  void _onTablePanUpdate(
    Offset localPos,
    double boardW,
    double boardH,
    bool ballInHand,
  ) {
    final cue = _balls.firstWhere((b) => b.id == 0);
    final double touchNormX = (localPos.dx / boardW).clamp(0.0, 1.0);
    final double touchNormY = (localPos.dy / boardH) * 2.0;

    if (_isMovingCueBall && ballInHand) {
      final freeSpot = _findFreeCueSpot(touchNormX, touchNormY);
      setState(() {
        cue.x = freeSpot.dx;
        cue.y = freeSpot.dy;
      });
      return;
    }

    if (_tablePullStartLocal != null) {
      final double backDirX = -math.cos(_aimAngle);
      final double backDirY = -math.sin(_aimAngle);
      final double dragDx = (localPos.dx - _tablePullStartLocal!.dx) / boardW;
      final double dragDy = ((localPos.dy - _tablePullStartLocal!.dy) / boardH) * 2.0;
      final double pullAmount = (dragDx * backDirX + dragDy * backDirY) / 0.42;
      _updatePullPowerWithHaptics(pullAmount);
      return;
    }

    // 8 Ball Pool Açısal Delta (Parmak beyaz topun etrafında ne kadar döndüyse ıstakayı o kadar döndür, zıplama yapmaz!)
    if (_lastTablePanPos != null) {
      final Offset cuePx = Offset(cue.x * boardW, (cue.y / 2.0) * boardH);
      final double prevAng = math.atan2(
        _lastTablePanPos!.dy - cuePx.dy,
        _lastTablePanPos!.dx - cuePx.dx,
      );
      final double currAng = math.atan2(
        localPos.dy - cuePx.dy,
        localPos.dx - cuePx.dx,
      );
      double delta = currAng - prevAng;
      while (delta > math.pi) {
        delta -= math.pi * 2;
      }
      while (delta < -math.pi) {
        delta += math.pi * 2;
      }
      _lastTablePanPos = localPos;
      setState(() {
        _aimAngle += delta * 0.85;
      });
    }
  }

  void _onTablePanEnd({
    required String coupleId,
    required int shotSeq,
  }) {
    _lastTablePanPos = null;
    if (_isMovingCueBall) {
      setState(() => _isMovingCueBall = false);
      // Beyaz topun yeni yerleştirilen konumunu anında Firestore'a senkronize et:
      DatabaseService().updateGameState(
        coupleId: coupleId,
        gameType: 'billiards',
        updates: {
          'balls': _balls.map((b) => b.toMap()).toList(),
        },
      );
      return;
    }
    if (_tablePullStartLocal != null || _isPullingCue) {
      _tablePullStartLocal = null;
      _releaseAndStrikeCue(coupleId: coupleId, currentShotSeq: shotSeq);
    }
  }

  String _formatGroupName(String? group) {
    if (group == 'solids') return 'Grubun: Düz Toplar (1 - 7)';
    if (group == 'stripes') return 'Grubun: Çizgili Toplar (9 - 15)';
    return 'Grup Seçimi Açık (İlk Giren Top)';
  }

  Widget _buildPlayerScoreBar({
    required String myName,
    required String partnerName,
    required String? myGroup,
    required String? partnerGroup,
    required bool isMyTurn,
    required bool isGameOver,
    required bool isDark,
  }) {
    final solidsRemaining = _balls.where((b) => b.isSolid && !b.pocketed).map((b) => b.id).toList();
    final stripesRemaining = _balls.where((b) => b.isStripe && !b.pocketed).map((b) => b.id).toList();

    List<int> myTargets = [];
    List<int> partnerTargets = [];
    if (myGroup == 'solids') {
      myTargets = solidsRemaining;
      partnerTargets = stripesRemaining;
    } else if (myGroup == 'stripes') {
      myTargets = stripesRemaining;
      partnerTargets = solidsRemaining;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: _buildPlayerMiniCard(
              name: '$myName (Sen)',
              groupLabel: myGroup == null
                  ? 'Açık Masa'
                  : (myGroup == 'solids' ? 'Düz (1-7)' : 'Çizgili (9-15)'),
              remainingIds: myTargets,
              isTurn: isMyTurn && !isGameOver,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildPlayerMiniCard(
              name: partnerName,
              groupLabel: partnerGroup == null
                  ? 'Açık Masa'
                  : (partnerGroup == 'solids' ? 'Düz (1-7)' : 'Çizgili (9-15)'),
              remainingIds: partnerTargets,
              isTurn: !isMyTurn && !isGameOver,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerMiniCard({
    required String name,
    required String groupLabel,
    required List<int> remainingIds,
    required bool isTurn,
    required bool isDark,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: isTurn
            ? const Color(0xFF0F766E).withValues(alpha: isDark ? 0.28 : 0.14)
            : (isDark ? const Color(0xFF161922) : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isTurn ? const Color(0xFF10B981) : Colors.transparent,
          width: 1.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isTurn ? const Color(0xFF10B981) : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            groupLabel,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          if (remainingIds.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 3,
              children: remainingIds.map((id) => _buildMiniBallBadge(id)).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniBallBadge(int id) {
    final color = _BilliardsTablePainter.getBallColor(id);
    final isStripe = id >= 9;
    return Container(
      width: 15,
      height: 15,
      decoration: BoxDecoration(
        color: isStripe ? Colors.white : color,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: isStripe ? 2.5 : 1),
      ),
      child: Center(
        child: Text(
          '$id',
          style: TextStyle(
            fontSize: 7.5,
            fontWeight: FontWeight.w900,
            color: isStripe ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }

  /// Sağ taraftaki Orijinal 8 Ball Pool Kontrol Sütunu:
  /// 1) Falso (Cue Ball Spin) Seçici Yuvarlak Butonu
  /// 2) Hassas Nişan Cetveli (Fine-Tune Aim Wheel - Yukarı/Aşağı kaydırarak milimetrik açı ayarı)
  /// 3) Yaylı Çek-Bırak Istaka Kanalı (Aşağı çekip bırakınca ateşler)
  /// (Taşma / Overflow hatası tamamen giderildi!)
  Widget _buildPullReleaseCueBar({
    required bool isMyTurn,
    required bool isDark,
    required String coupleId,
    required int shotSeq,
  }) {
    final int pct = (_pullPower * 100).round();
    final Color powerColor = _pullPower < 0.35
        ? const Color(0xFF10B981)
        : (_pullPower < 0.75 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));

    return Container(
      width: 66,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161922) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isMyTurn
              ? powerColor.withValues(alpha: 0.55)
              : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // 1. 8 Ball Pool Falso (Spin) Seçici Küre
          GestureDetector(
            onTap: isMyTurn ? () => _openSpinSelectorModal(context) : null,
            child: Column(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      center: Alignment(-0.3, -0.3),
                      colors: [Colors.white, Color(0xFFCBD5E1)],
                    ),
                    border: Border.all(color: const Color(0xFF10B981), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(width: 26, height: 0.8, color: Colors.black26),
                      Container(width: 0.8, height: 26, color: Colors.black26),
                      Transform.translate(
                        offset: Offset(_cueSpin.dx * 10, _cueSpin.dy * 10),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'FALSO',
                    style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // 2. 8 Ball Pool Hassas Nişan Tekerleği (Fine-Tune Aim Ruler)
          const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'HASSAS',
              style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 3),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: isMyTurn
                ? (details) {
                    setState(() {
                      _aimAngle += details.delta.dy * 0.00085;
                      _fineTunerScrollOffset += details.delta.dy;
                    });
                  }
                : null,
            child: Container(
              width: 44,
              height: 62,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0D1017) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.35),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: CustomPaint(
                  painter: _FineTuneWheelPainter(
                    scrollOffset: _fineTunerScrollOffset,
                    isDark: isDark,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // 3. Yaylı Çek-Bırak Istaka Başlığı
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _isPullingCue ? '%$pct' : 'ISTAKA',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: _isPullingCue ? powerColor : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ),
          const SizedBox(height: 4),

          // 4. Yaylı Çek-Bırak Istaka Yuvası
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final trackH = constraints.maxHeight;
                final maxDrag = math.max(1.0, trackH - 54.0);

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: isMyTurn
                      ? (details) {
                          _pullStartY = details.localPosition.dy;
                          _lastHapticTickLevel = 0;
                          setState(() {
                            _isPullingCue = true;
                            _pullPower = 0.0;
                          });
                        }
                      : null,
                  onVerticalDragUpdate: isMyTurn
                      ? (details) {
                          final dy = details.localPosition.dy - _pullStartY;
                          _updatePullPowerWithHaptics(dy / maxDrag);
                        }
                      : null,
                  onVerticalDragEnd: isMyTurn
                      ? (_) {
                          _releaseAndStrikeCue(coupleId: coupleId, currentShotSeq: shotSeq);
                        }
                      : null,
                  onVerticalDragCancel: isMyTurn
                      ? () {
                          setState(() {
                            _isPullingCue = false;
                            _pullPower = 0.0;
                          });
                        }
                      : null,
                  child: Container(
                    width: 44,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0D1017) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        // Güç Doluluk Arka Planı
                        Positioned.fill(
                          child: FractionallySizedBox(
                            alignment: Alignment.topCenter,
                            heightFactor: _pullPower.clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    const Color(0xFF10B981).withValues(alpha: 0.25),
                                    const Color(0xFFF59E0B).withValues(alpha: 0.45),
                                    const Color(0xFFEF4444).withValues(alpha: 0.65),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(22),
                              ),
                            ),
                          ),
                        ),

                        // Aşağı Yön Okları
                        Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(
                            5,
                            (i) => Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 15,
                              color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.16),
                            ),
                          ),
                        ),

                        // Hareketli Istaka Tutamacı
                        Positioned(
                          top: 5 + (_pullPower * math.max(0.0, trackH - 54)),
                          child: Opacity(
                            opacity: isMyTurn ? 1.0 : 0.4,
                            child: Container(
                              width: 34,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xFF38BDF8),
                                    Color(0xFFFDE68A),
                                    Color(0xFFD97706),
                                    Color(0xFF451A03),
                                  ],
                                  stops: [0.0, 0.12, 0.55, 1.0],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: powerColor.withValues(alpha: _isPullingCue ? 0.55 : 0.2),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                                border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.2),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.drag_handle_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingReadyOverlay({
    required String coupleId,
    required bool isWhite,
    required bool myReady,
    required bool partnerReady,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎱', style: TextStyle(fontSize: 42)),
            const SizedBox(height: 10),
            const Text(
              'Bilardo Masası Hazır',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'İki taraf da hazır olduğunda açılış vuruşu başlayacak.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildReadyBadge('Sen', myReady)),
                const SizedBox(width: 8),
                Expanded(child: _buildReadyBadge('Partnerin', partnerReady)),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 180,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: myReady ? const Color(0xFF10B981) : const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  DatabaseService().setGamePlayerReady(
                    coupleId: coupleId,
                    gameType: 'billiards',
                    isPlayer1: isWhite,
                    isReady: !myReady,
                  );
                },
                child: Text(
                  myReady ? 'Hazırsın ✅' : 'Hazırım 🚀',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadyBadge(String label, bool ready) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: ready
            ? const Color(0xFF10B981).withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ready ? const Color(0xFF10B981) : Colors.white24,
        ),
      ),
      child: Column(
        children: [
          Icon(
            ready ? Icons.check_circle_rounded : Icons.hourglass_empty_rounded,
            color: ready ? const Color(0xFF10B981) : Colors.amber,
            size: 18,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildGameOverOverlay({
    required String coupleId,
    required bool isWhite,
    required String? myUid,
    required String? winnerUid,
    required String? winnerReason,
    required bool myRematch,
    required bool partnerRematch,
  }) {
    final isWinner = winnerUid != null && winnerUid == myUid;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(22),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isWinner ? '🏆' : '🎱', style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 10),
            Text(
              isWinner ? 'Tebrikler, Kazandın!' : 'Partnerin Kazandı!',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              winnerReason ?? 'Oyun tamamlandı',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 18),
            if (partnerRematch && !myRematch)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'Partnerin rövanş istiyor! 🔥',
                  style: TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.w800),
                ),
              ),
            SizedBox(
              width: 190,
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: myRematch ? Colors.grey.shade700 : const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: Text(
                  myRematch ? 'Partner Bekleniyor...' : 'Tekrar Oyna',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                onPressed: myRematch
                    ? null
                    : () {
                        DatabaseService().requestGameRematch(
                          coupleId: coupleId,
                          gameType: 'billiards',
                          isPlayer1: isWhite,
                          resetData: buildInitialGameData(),
                        );
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartLobby({
    required BuildContext context,
    required bool isDark,
    required String? status,
    required String coupleId,
    required String? myUid,
    required String myName,
    required dynamic partner,
  }) {
    return Scaffold(
      backgroundColor: isDark ? LoveraColors.darkBg : LoveraColors.lightBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('8 Ball Pool 🎱', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: isDark ? LoveraColors.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.18),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF0F766E)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('🎱', style: TextStyle(fontSize: 40)),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Canlı 8 Ball Pool',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  status == 'rejected'
                      ? 'Önceki bilardo daveti kabul edilmedi. Yeniden davet gönderebilirsin.'
                      : '8 Ball Pool mekanikleri: Çek-bırak yaylı ıstaka, hassas nişan tekerleği, beyaz top falso (Spin) kontrolü ve gerçekçi yansıma kılavuzu!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                  ),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 24),
                    label: const Text(
                      'Oyna',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    onPressed: () => _initNewGame(coupleId, myUid, myName, partner),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPendingInvitationView(BuildContext context, bool isDark, bool isSender) {
    return Scaffold(
      backgroundColor: isDark ? LoveraColors.darkBg : LoveraColors.lightBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('8 Ball Pool 🎱', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: isDark ? LoveraColors.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFF10B981)),
                const SizedBox(height: 24),
                Text(
                  isSender ? 'Partnerin Bekleniyor...' : 'Bilardo Daveti Alındı',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  isSender
                      ? 'Partnerine 8 Ball Pool daveti gönderildi. Kabul ettiğinde masa açılacak.'
                      : 'Partnerin seni bilardo masasına davet etti.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatActionButton(BuildContext context, int unreadCount, bool isDark) {
    return IconButton(
      tooltip: 'Sohbet 💬',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: unreadCount > 0
                  ? const Color(0xFFEC4899).withValues(alpha: 0.18)
                  : const Color(0xFF10B981).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_rounded,
              color: unreadCount > 0 ? const Color(0xFFEC4899) : const Color(0xFF10B981),
              size: 20,
            ),
          ),
          if (unreadCount > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEC4899),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  unreadCount > 9 ? '9+' : '$unreadCount',
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
                ),
              ),
            ),
        ],
      ),
      onPressed: () => _openInGameChatSheet(context),
    );
  }

  Future<void> _initNewGame(
    String coupleId,
    String? myUid,
    String myName,
    dynamic partner,
  ) async {
    if (myUid == null || partner == null) return;
    final partnerUid = partner.id ?? '';
    if (partnerUid.isEmpty) return;
    final name = myName.isNotEmpty ? myName : 'Partnerin';

    await DatabaseService().sendGameRequest(
      gameType: 'billiards',
      gameTitle: '8 Top Bilardo 🎱',
      partnerUid: partnerUid,
      fromName: name,
      coupleId: coupleId,
      initialGameData: buildInitialGameData(),
    );

    NotificationService().sendPushToPartner(
      partnerUid: partnerUid,
      title: 'Bilardo Daveti 🎱',
      body: '$name seninle 8 Top Bilardo oynamak istiyor!',
      data: {'type': 'game_request', 'game': 'billiards'},
    );
  }

  void _confirmNewGame(
    BuildContext context,
    String coupleId,
    String? myUid,
    String myName,
    dynamic partner,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeni Bilardo Oyunu'),
        content: const Text('Mevcut masa sıfırlanarak yeni bir bilardo oyunu başlatılsın mı?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
            onPressed: () {
              Navigator.pop(ctx);
              _initNewGame(coupleId, myUid, myName, partner);
            },
            child: const Text('Başlat', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmResign(
    BuildContext context,
    String coupleId,
    String? myUid,
    String? partnerUid,
  ) {
    if (myUid == null || partnerUid == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pes Et'),
        content: const Text('Bilardo oyunundan çekilmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF43F5E)),
            onPressed: () {
              Navigator.pop(ctx);
              DatabaseService().resignGame(
                coupleId: coupleId,
                gameType: 'billiards',
                resignedUid: myUid,
                winnerUid: partnerUid,
              );
            },
            child: const Text('Pes Et', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showExitDialog(BuildContext context, String coupleId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Masadan Ayrıl'),
        content: const Text('Oyundan çıkarsanız bilardo maçı sonlanacaktır. Çıkmak istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF43F5E)),
            onPressed: () {
              Navigator.pop(ctx);
              DatabaseService().resetGame(coupleId: coupleId, gameType: 'billiards');
              Navigator.pop(context);
            },
            child: const Text('Çık', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openInGameChatSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.85,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F1015) : const Color(0xFFF7F8FA),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: ChatView(
            isEmbedded: true,
            onBackToHome: () => Navigator.pop(ctx),
          ),
        ),
      ),
    );
  }
}

/// 8 Ball Pool Hassas Nişan Tekerleği (Fine-Tune Aim Wheel) Çizicisi
class _FineTuneWheelPainter extends CustomPainter {
  final double scrollOffset;
  final bool isDark;

  _FineTuneWheelPainter({required this.scrollOffset, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const double step = 7.0;
    final double phase = scrollOffset % step;

    for (double y = phase - step; y <= h + step; y += step) {
      final double distFromCenter = (y - h / 2).abs() / (h / 2);
      final double alpha = (1.0 - distFromCenter * 0.75).clamp(0.15, 0.9);
      final bool isMajor = ((y - phase) / step).round() % 2 == 0;
      final double lineW = isMajor ? w * 0.65 : w * 0.38;

      canvas.drawLine(
        Offset((w - lineW) / 2, y),
        Offset((w + lineW) / 2, y),
        Paint()
          ..color = (isMajor ? const Color(0xFF10B981) : (isDark ? Colors.white : Colors.black87))
              .withValues(alpha: alpha)
          ..strokeWidth = isMajor ? 1.8 : 1.1
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FineTuneWheelPainter oldDelegate) =>
      oldDelegate.scrollOffset != scrollOffset || oldDelegate.isDark != isDark;
}

/// 8 Ball Pool Profesyonel Masa, Cep Çeneleri (Jaws), Tam Yansıma Kılavuzu ve 3D Top Çizicisi
class _BilliardsTablePainter extends CustomPainter {
  final List<_PoolBall> balls;
  final double aimAngle;
  final double pullPower;
  final Offset cueSpin;
  final bool isStriking;
  final bool showCueAndAim;
  final bool ballInHand;

  _BilliardsTablePainter({
    required this.balls,
    required this.aimAngle,
    required this.pullPower,
    required this.cueSpin,
    required this.isStriking,
    required this.showCueAndAim,
    required this.ballInHand,
  });

  static Color getBallColor(int id) {
    switch (id) {
      case 0:
        return const Color(0xFFFAF9F6);
      case 1:
      case 9:
        return const Color(0xFFF59E0B);
      case 2:
      case 10:
        return const Color(0xFF2563EB);
      case 3:
      case 11:
        return const Color(0xFFEF4444);
      case 4:
      case 12:
        return const Color(0xFF7C3AED);
      case 5:
      case 13:
        return const Color(0xFFEA580C);
      case 6:
      case 14:
        return const Color(0xFF16A34A);
      case 7:
      case 15:
        return const Color(0xFF881337);
      case 8:
        return const Color(0xFF111827);
      default:
        return Colors.white;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final scale = w;

    final cushionPx = _BilliardsGameViewState._cushion * scale;
    final ballRadiusPx = _BilliardsGameViewState._ballRadius * scale;
    final pocketRadiusPx = _BilliardsGameViewState._pocketRadius * scale;

    // 1. Dış Maun Ahşap Gövde (Kasa)
    final outerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      const Radius.circular(24),
    );
    final woodPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF5C2C16), Color(0xFF3A1809), Color(0xFF522512)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRRect(outerRect, woodPaint);

    // Altın kasa şeridi
    canvas.drawRRect(
      outerRect.deflate(2),
      Paint()
        ..color = const Color(0xFFD97706).withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // 2. Zümrüt Çuha (Felt)
    final feltRect = Rect.fromLTWH(
      cushionPx,
      cushionPx,
      w - cushionPx * 2,
      h - cushionPx * 2,
    );
    canvas.drawRect(
      feltRect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment.center,
          radius: 0.95,
          colors: [Color(0xFF0D9488), Color(0xFF065F46), Color(0xFF064E3B)],
        ).createShader(feltRect),
    );

    // Bant gölgesi
    canvas.drawRect(
      feltRect,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.38)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5,
    );

    // Head String ve Foot Spot
    canvas.drawLine(
      Offset(cushionPx, h * 0.76),
      Offset(w - cushionPx, h * 0.76),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..strokeWidth = 1.2,
    );
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.27),
      3,
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );

    // Elmas nişan noktaları (Diamond Sights)
    final diamondPaint = Paint()..color = const Color(0xFFFDE68A).withValues(alpha: 0.78);
    for (int i = 1; i <= 3; i++) {
      final dyTop = cushionPx + (feltRect.height * 0.5) * (i / 4.0);
      final dyBot = h * 0.5 + (feltRect.height * 0.5) * (i / 4.0);
      canvas.drawCircle(Offset(cushionPx * 0.5, dyTop), 2.2, diamondPaint);
      canvas.drawCircle(Offset(w - cushionPx * 0.5, dyTop), 2.2, diamondPaint);
      canvas.drawCircle(Offset(cushionPx * 0.5, dyBot), 2.2, diamondPaint);
      canvas.drawCircle(Offset(w - cushionPx * 0.5, dyBot), 2.2, diamondPaint);
    }

    // 3. 6 Delik (Pockets)
    for (final p in _BilliardsGameViewState._pockets) {
      final center = Offset(p.dx * scale, p.dy * scale);
      canvas.drawCircle(center, pocketRadiusPx * 1.14, Paint()..color = const Color(0xFF1F2937));
      canvas.drawCircle(center, pocketRadiusPx * 0.94, Paint()..color = const Color(0xFF07080C));
    }

    // 4. 8 Ball Pool Lazer Kılavuz Çizgisi (Bant Yansımalı + Yasak Top Uyarı İşaretli) ve Istaka
    final cueBall = balls.where((b) => b.id == 0 && !b.pocketed).firstOrNull;
    if (cueBall != null && showCueAndAim) {
      final cuePos = Offset(cueBall.x * scale, cueBall.y * scale);

      if (ballInHand) {
        // 8 Ball Pool tarzı belirgin, parlayan "Topu Yerleştir" halkası ve hedef göstergesi:
        canvas.drawCircle(
          cuePos,
          ballRadiusPx * 2.3,
          Paint()
            ..color = const Color(0xFF10B981).withValues(alpha: 0.25)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          cuePos,
          ballRadiusPx * 2.3,
          Paint()
            ..color = const Color(0xFF10B981)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
        // 4 Yönlü Yerleştirme Okları / Çentikleri
        const double markerDist = 18.0;
        final markPaint = Paint()
          ..color = const Color(0xFF10B981)
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(cuePos + const Offset(-markerDist, 0), cuePos + Offset(-ballRadiusPx * 1.5, 0), markPaint);
        canvas.drawLine(cuePos + const Offset(markerDist, 0), cuePos + Offset(ballRadiusPx * 1.5, 0), markPaint);
        canvas.drawLine(cuePos + const Offset(0, -markerDist), cuePos + Offset(0, -ballRadiusPx * 1.5), markPaint);
        canvas.drawLine(cuePos + const Offset(0, markerDist), cuePos + Offset(0, ballRadiusPx * 1.5), markPaint);
      }

      final rayResult = _castAimRay(cueBall, aimAngle);
      final targetPos = Offset(rayResult.hitX * scale, rayResult.hitY * scale);

      // Ana nişan çizgisi (8 Ball Pool düz beyaz kılavuz)
      canvas.drawLine(
        cuePos,
        targetPos,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.90)
          ..strokeWidth = 1.9,
      );

      // Hayalet top (Ghost Ball) çemberi
      canvas.drawCircle(
        targetPos,
        ballRadiusPx,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7,
      );

      if (rayResult.hitBall != null) {
        // Hedef topa çarpıyorsa: Hedef topun gideceği yön + Beyaz topun sapma/falso yönü
        final hb = rayResult.hitBall!;
        final hbPos = Offset(hb.x * scale, hb.y * scale);
        final nx = hb.x - rayResult.hitX;
        final ny = hb.y - rayResult.hitY;
        final nLen = math.sqrt(nx * nx + ny * ny);
        if (nLen > 0.0001) {
          final dirX = nx / nLen;
          final dirY = ny / nLen;
          final aimDirX = math.cos(aimAngle);
          final aimDirY = math.sin(aimAngle);

          final dot = (aimDirX * dirX + aimDirY * dirY).clamp(0.0, 1.0);

          final objGuideEnd = Offset(
            (hb.x + dirX * (0.16 + dot * 0.22)) * scale,
            (hb.y + dirY * (0.16 + dot * 0.22)) * scale,
          );
          canvas.drawLine(
            hbPos,
            objGuideEnd,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.92)
              ..strokeWidth = 2.2
              ..strokeCap = StrokeCap.round,
          );

          // Beyaz topun sapma + Üst/Alt falso yön çizgisi
          final double followOrDraw = -cueSpin.dy * 0.55;
          final double deflectX = (aimDirX - dot * dirX) + dirX * followOrDraw;
          final double deflectY = (aimDirY - dot * dirY) + dirY * followOrDraw;
          final double defLen = math.sqrt(deflectX * deflectX + deflectY * deflectY);
          if (defLen > 0.04) {
            final cueDeflectEnd = Offset(
              (rayResult.hitX + (deflectX / defLen) * 0.16) * scale,
              (rayResult.hitY + (deflectY / defLen) * 0.16) * scale,
            );
            canvas.drawLine(
              targetPos,
              cueDeflectEnd,
              Paint()
                ..color = Colors.white.withValues(alpha: 0.72)
                ..strokeWidth = 1.8
                ..strokeCap = StrokeCap.round,
            );
          }
        }
      } else {
        // Banda çarpıyorsa: Banttan yansıma (Bank Shot Reflection) kılavuz çizgisi!
        double refDx = math.cos(aimAngle);
        double refDy = math.sin(aimAngle);
        if (rayResult.hitVerticalWall) {
          refDx = -refDx;
        } else {
          refDy = -refDy;
        }
        final bounceEnd = Offset(
          (rayResult.hitX + refDx * 0.20) * scale,
          (rayResult.hitY + refDy * 0.20) * scale,
        );
        canvas.drawLine(
          targetPos,
          bounceEnd,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.55)
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round,
        );
      }

      // Istaka (Cue Stick) çizimi
      final double strikeOffset = isStriking ? 0.029 : (0.042 + pullPower * 0.19);
      final double pullOffsetPx = strikeOffset * scale;
      final double cueLength = 0.58 * scale;
      final Offset backDir = Offset(-math.cos(aimAngle), -math.sin(aimAngle));
      final Offset tipPos = cuePos + backDir * pullOffsetPx;
      final Offset buttPos = tipPos + backDir * cueLength;

      canvas.drawLine(
        tipPos + const Offset(3, 5),
        buttPos + const Offset(5, 8),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..strokeWidth = 6.0
          ..strokeCap = StrokeCap.round,
      );

      final cueStickPaint = Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFDE68A), Color(0xFFD97706), Color(0xFF451A03)],
          stops: [0.0, 0.45, 1.0],
        ).createShader(Rect.fromPoints(tipPos, buttPos))
        ..strokeWidth = 5.6
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(tipPos, buttPos, cueStickPaint);
      canvas.drawCircle(tipPos, 3.0, Paint()..color = const Color(0xFF38BDF8));
    }

    // 5. Topların Çizimi
    for (final b in balls) {
      if (b.pocketed && b.pocketScale <= 0.01) continue;
      final double rPx = ballRadiusPx * (b.pocketed ? b.pocketScale : 1.0);
      final center = Offset(b.x * scale, b.y * scale);

      if (!b.pocketed) {
        canvas.drawCircle(
          center + const Offset(2.0, 3.0),
          rPx,
          Paint()..color = Colors.black.withValues(alpha: 0.44),
        );
      }

      final baseColor = getBallColor(b.id);
      final double rollOffset = math.sin(b.rollPhase) * rPx * 0.32;
      final Offset rollShift = Offset(
        math.cos(b.moveAngle) * rollOffset,
        math.sin(b.moveAngle) * rollOffset,
      );

      if (b.isStripe) {
        canvas.drawCircle(center, rPx, Paint()..color = const Color(0xFFFAF9F6));
        canvas.save();
        canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: rPx)));
        canvas.translate(center.dx + rollShift.dx * 0.4, center.dy + rollShift.dy * 0.4);
        canvas.rotate(b.moveAngle * 0.25);
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: rPx * 2.3, height: rPx * 1.15),
          Paint()..color = baseColor,
        );
        canvas.restore();
      } else {
        canvas.drawCircle(center, rPx, Paint()..color = baseColor);
        if (b.id == 0) {
          canvas.drawCircle(
            center + rollShift,
            rPx * 0.16,
            Paint()..color = const Color(0xFFEF4444).withValues(alpha: 0.78),
          );
        }
      }

      if (b.id != 0 && rPx > 4) {
        final badgeCenter = center + rollShift * 0.65;
        canvas.save();
        canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: rPx)));
        canvas.drawCircle(
          badgeCenter,
          rPx * 0.48,
          Paint()..color = Colors.white.withValues(alpha: 0.94),
        );
        final tp = TextPainter(
          text: TextSpan(
            text: '${b.id}',
            style: TextStyle(
              color: Colors.black,
              fontSize: rPx * 0.68,
              fontWeight: FontWeight.w900,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, badgeCenter - Offset(tp.width / 2, tp.height / 2));
        canvas.restore();
      }

      final shadePaint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.35),
          radius: 0.95,
          colors: [
            Colors.white.withValues(alpha: 0.32),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.28),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: rPx));
      canvas.drawCircle(center, rPx, shadePaint);
    }
  }

  ({double hitX, double hitY, _PoolBall? hitBall, bool hitVerticalWall}) _castAimRay(
    _PoolBall cue,
    double angle,
  ) {
    final double dx = math.cos(angle);
    final double dy = math.sin(angle);
    const double r2 = _BilliardsGameViewState._ballRadius * 2.0;

    const double minX = _BilliardsGameViewState._cushion + _BilliardsGameViewState._ballRadius;
    const double maxX = _BilliardsGameViewState._tableW - minX;
    const double minY = _BilliardsGameViewState._cushion + _BilliardsGameViewState._ballRadius;
    const double maxY = _BilliardsGameViewState._tableH - minY;

    double bestT = 3.0;
    bool hitVertical = false;
    _PoolBall? hitBall;

    if (dx < -0.0001) {
      final t = (minX - cue.x) / dx;
      if (t < bestT) {
        bestT = t;
        hitVertical = true;
      }
    }
    if (dx > 0.0001) {
      final t = (maxX - cue.x) / dx;
      if (t < bestT) {
        bestT = t;
        hitVertical = true;
      }
    }
    if (dy < -0.0001) {
      final t = (minY - cue.y) / dy;
      if (t < bestT) {
        bestT = t;
        hitVertical = false;
      }
    }
    if (dy > 0.0001) {
      final t = (maxY - cue.y) / dy;
      if (t < bestT) {
        bestT = t;
        hitVertical = false;
      }
    }

    for (final b in balls) {
      if (b.id == 0 || b.pocketed) continue;
      final double fx = b.x - cue.x;
      final double fy = b.y - cue.y;
      final double proj = fx * dx + fy * dy;
      if (proj <= 0) continue;

      final double perpSq = (fx * fx + fy * fy) - proj * proj;
      if (perpSq < r2 * r2) {
        final double offset = math.sqrt(r2 * r2 - perpSq);
        final double t = proj - offset;
        if (t > 0 && t < bestT) {
          bestT = t;
          hitBall = b;
        }
      }
    }

    return (
      hitX: cue.x + dx * bestT,
      hitY: cue.y + dy * bestT,
      hitBall: hitBall,
      hitVerticalWall: hitVertical,
    );
  }

  @override
  bool shouldRepaint(covariant _BilliardsTablePainter oldDelegate) => true;
}
