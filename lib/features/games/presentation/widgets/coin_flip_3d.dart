import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CoinFlip3D extends StatefulWidget {
  final String player1Name;
  final String player2Name;
  final String? player1Uid;
  final String? player2Uid;
  final String? winnerUid;
  final String? winnerName;
  final bool isFlipping;
  final VoidCallback? onFlipComplete;

  const CoinFlip3D({
    super.key,
    required this.player1Name,
    required this.player2Name,
    this.player1Uid,
    this.player2Uid,
    this.winnerUid,
    this.winnerName,
    this.isFlipping = false,
    this.onFlipComplete,
  });

  @override
  State<CoinFlip3D> createState() => _CoinFlip3DState();
}

class _CoinFlip3DState extends State<CoinFlip3D> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _verticalAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _setupAnimations();

    if (widget.isFlipping) {
      _setupAnimations();
      _startFlip();
    } else {
      // Eğer dönmüyorsa ama kazanan zaten belliyse doğrudan kazanan yüzü göster
      final bool winnerIsPlayer2 = widget.winnerUid != null && widget.player2Uid != null
          ? (widget.winnerUid == widget.player2Uid)
          : (widget.winnerName != null && widget.winnerName == widget.player2Name);
      _controller.value = 1.0;
      final double targetAngle = winnerIsPlayer2 ? (11 * math.pi) : (12 * math.pi);
      _rotationAnimation = AlwaysStoppedAnimation(targetAngle);
      _verticalAnimation = const AlwaysStoppedAnimation(0.0);
      _scaleAnimation = const AlwaysStoppedAnimation(1.0);
    }
  }

  void _setupAnimations() {
    // Kazanan player2 ise açı tek (pi) radyan katı (örn: 11 * pi) olmalı -> cos(11*pi) = -1 -> Player 2
    // Kazanan player1 ise açı çift (2*pi) radyan katı (örn: 12 * pi) olmalı -> cos(12*pi) = +1 -> Player 1
    final bool winnerIsPlayer2 = widget.winnerUid != null && widget.player2Uid != null
        ? (widget.winnerUid == widget.player2Uid)
        : (widget.winnerName != null && widget.winnerName == widget.player2Name);
    final double targetAngle = winnerIsPlayer2 ? (11 * math.pi) : (12 * math.pi);

    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: targetAngle,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    // Para havaya fırlatılırken yukarı yükselir ve geri düşer
    _verticalAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: -120).chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -120, end: 0).chain(CurveTween(curve: Curves.bounceOut)),
        weight: 60,
      ),
    ]).animate(_controller);

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.35).chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.35, end: 1.0).chain(CurveTween(curve: Curves.easeInQuad)),
        weight: 60,
      ),
    ]).animate(_controller);

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        widget.onFlipComplete?.call();
      }
    });
  }

  @override
  void didUpdateWidget(covariant CoinFlip3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFlipping && !oldWidget.isFlipping) {
      _setupAnimations();
      _startFlip();
    } else if (widget.isFlipping && oldWidget.isFlipping) {
      // Eğer dönmeye devam ederken winnerUid gecikmeli olarak Firestore'dan geldiyse animasyonu güncelle
      if (widget.winnerUid != oldWidget.winnerUid || widget.winnerName != oldWidget.winnerName) {
        _setupAnimations();
      }
    } else if (!widget.isFlipping &&
        (widget.winnerUid != oldWidget.winnerUid || widget.winnerName != oldWidget.winnerName) &&
        (widget.winnerUid != null || widget.winnerName != null)) {
      final bool winnerIsPlayer2 = widget.winnerUid != null && widget.player2Uid != null
          ? (widget.winnerUid == widget.player2Uid)
          : (widget.winnerName == widget.player2Name);
      final double targetAngle = winnerIsPlayer2 ? (11 * math.pi) : (12 * math.pi);
      setState(() {
        _rotationAnimation = AlwaysStoppedAnimation(targetAngle);
      });
    }
  }

  void _startFlip() {
    HapticFeedback.mediumImpact();
    _controller.forward(from: 0.0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final angle = _rotationAnimation.value;
        // cos(angle) < 0 ise arka yüz (Player 2), >= 0 ise ön yüz (Player 1)
        final bool showPlayer2 = math.cos(angle) < 0;

        return Transform.translate(
          offset: Offset(0, _verticalAnimation.value),
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.002) // 3D perspektif
                ..rotateX(angle),
              child: Transform(
                alignment: Alignment.center,
                // Arka yüz gösterilirken metinlerin ters (ayna) durmaması için rotateX(pi) uyguluyoruz
                transform: showPlayer2 ? Matrix4.rotationX(math.pi) : Matrix4.identity(),
                child: _buildCoinFace(showPlayer2),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCoinFace(bool isPlayer2) {
    final String currentName = isPlayer2 ? widget.player2Name : widget.player1Name;
    final List<Color> gradientColors = isPlayer2
        ? const [Color(0xFFFFB703), Color(0xFFFB8500), Color(0xFFD47000)]
        : const [Color(0xFFFFD166), Color(0xFFEF476F), Color(0xFFBE123C)];

    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.3),
          radius: 0.9,
          colors: [
            Colors.white.withValues(alpha: 0.8),
            ...gradientColors,
            Colors.black.withValues(alpha: 0.4),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: gradientColors[1].withValues(alpha: 0.45),
            blurRadius: 24,
            spreadRadius: 4,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFFFF1C5),
          width: 4.5,
        ),
      ),
      child: Center(
        child: Container(
          width: 116,
          height: 116,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.6),
              width: 1.8,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                isPlayer2 ? '👑' : '💖',
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  currentName.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 1.2,
                    shadows: [
                      Shadow(
                        color: Colors.black45,
                        blurRadius: 4,
                        offset: Offset(1, 1),
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
  }
}
