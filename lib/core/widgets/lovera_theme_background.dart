import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Lovera Özel Karma Arka Plan Deseni & Atmosferik Işık Havuzu (Ambient Aurora + Romantic Doodle)
/// Hem derin mor/pembe/leylak aurora ışık harelerini hem de yıldız, kalp, mektup, gezegen ve ışıltı sembollerini harmanlar.
/// RepaintBoundary ile donatılmıştır; kaydırma esnasında sıfır pil ve GPU yükü oluşturur.
class LoveraThemeBackground extends StatelessWidget {
  final Widget? child;
  final bool showPatterns;

  const LoveraThemeBackground({
    super.key,
    this.child,
    this.showPatterns = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Zemin Degrade & Taban Rengi (Daha zengin derinlik)
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? const [
                      Color(0xFF0D0E15),
                      Color(0xFF090A0F),
                      Color(0xFF07070B),
                    ]
                  : const [
                      Color(0xFFFCFCFE),
                      Color(0xFFF6F7FA),
                      Color(0xFFEDEFF5),
                    ],
            ),
          ),
        ),

        // 2. Atmosferik Aurora Işık Hareleri (Ambient Mesh Glow - iOS / Linear Tarzı Zengin Işık)
        RepaintBoundary(
          child: CustomPaint(
            painter: _AuroraGlowPainter(isDark: isDark),
            size: Size.infinite,
          ),
        ),

        // 3. Lovera Özel Aşk, Yıldız & Gece Çizim Deseni (Subtle Romantic Doodle)
        if (showPatterns)
          RepaintBoundary(
            child: CustomPaint(
              painter: _LoveraDoodlePatternPainter(isDark: isDark),
              size: Size.infinite,
            ),
          ),

        // 4. Ana İçerik
        if (child != null) child!,
      ],
    );
  }
}

/// Atmosferik Işık Hareleri (Üstte romantik violet/indigo, ortada gül pembesi, altta nane/aurora)
class _AuroraGlowPainter extends CustomPainter {
  final bool isDark;

  const _AuroraGlowPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Sol Üst Derin Leylak / Violet Işığı
    final violetPaint = Paint()
      ..shader = RadialGradient(
        colors: isDark
            ? [
                const Color(0xFF8B5CF6).withValues(alpha: 0.18),
                const Color(0xFF6D28D9).withValues(alpha: 0.08),
                Colors.transparent,
              ]
            : [
                const Color(0xFFA78BFA).withValues(alpha: 0.12),
                const Color(0xFFC4B5FD).withValues(alpha: 0.04),
                Colors.transparent,
              ],
        stops: const [0.0, 0.50, 1.0],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.12, size.height * 0.10),
        radius: size.width * 0.90,
      ));

    canvas.drawCircle(
      Offset(size.width * 0.12, size.height * 0.10),
      size.width * 0.90,
      violetPaint,
    );

    // 2. Sağ Üst/Orta Romantik Pembe / Gül Işıltısı
    final pinkPaint = Paint()
      ..shader = RadialGradient(
        colors: isDark
            ? [
                const Color(0xFFEC4899).withValues(alpha: 0.10),
                const Color(0xFFBE185D).withValues(alpha: 0.03),
                Colors.transparent,
              ]
            : [
                const Color(0xFFF472B6).withValues(alpha: 0.08),
                const Color(0xFFFBCFE8).withValues(alpha: 0.03),
                Colors.transparent,
              ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.92, size.height * 0.38),
        radius: size.width * 0.75,
      ));

    canvas.drawCircle(
      Offset(size.width * 0.92, size.height * 0.38),
      size.width * 0.75,
      pinkPaint,
    );

    // 3. Sol Alt Dingin Nane / Zümrüt Işıltısı (Lovera Canlılığı)
    final mintPaint = Paint()
      ..shader = RadialGradient(
        colors: isDark
            ? [
                const Color(0xFF10B981).withValues(alpha: 0.06),
                Colors.transparent,
              ]
            : [
                const Color(0xFF34D399).withValues(alpha: 0.04),
                Colors.transparent,
              ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.08, size.height * 0.85),
        radius: size.width * 0.70,
      ));

    canvas.drawCircle(
      Offset(size.width * 0.08, size.height * 0.85),
      size.width * 0.70,
      mintPaint,
    );

    // 4. Sağ Alt Sıcak Altın / Gece Işıltısı
    final amberPaint = Paint()
      ..shader = RadialGradient(
        colors: isDark
            ? [
                const Color(0xFFF59E0B).withValues(alpha: 0.04),
                Colors.transparent,
              ]
            : [
                const Color(0xFFFBBF24).withValues(alpha: 0.03),
                Colors.transparent,
              ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.85, size.height * 0.92),
        radius: size.width * 0.60,
      ));

    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.92),
      size.width * 0.60,
      amberPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _AuroraGlowPainter oldDelegate) => oldDelegate.isDark != isDark;
}

/// Gözü Yormayan (%5-%8 Opaklık) Dünya Standartlarında Romantik İllüstratif Desen
class _LoveraDoodlePatternPainter extends CustomPainter {
  final bool isDark;

  const _LoveraDoodlePatternPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    // Çizgi ve dolgu boyaları: Açık modda zarif lavanta fligranı, koyu modda gece parıltısı
    final strokeColor = isDark
        ? Colors.white.withValues(alpha: 0.065)
        : const Color(0xFF6D28D9).withValues(alpha: 0.075);

    final fillColor = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : const Color(0xFF7C3AED).withValues(alpha: 0.045);

    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = isDark ? 1.25 : 1.35
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    const cellW = 82.0;
    const cellH = 88.0;

    final cols = (size.width / cellW).ceil() + 1;
    final rows = (size.height / cellH).ceil() + 1;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        // Çapraz şaşırtmalı grid ve hafif açı varyasyonu (tamamen canlı & doğal tasarım)
        final x = c * cellW + ((r % 2 == 1) ? cellW * 0.5 : 0.0);
        final y = r * cellH;

        final patternType = (r * 7 + c * 5) % 8;
        final rotation = ((r + c) % 4 == 1) ? 0.08 : (((r + c) % 4 == 3) ? -0.08 : 0.0);

        canvas.save();
        canvas.translate(x, y);
        if (rotation != 0.0) {
          canvas.rotate(rotation);
        }

        switch (patternType) {
          case 0:
            _drawHeart(canvas, strokePaint, fillPaint, 13);
            break;
          case 1:
            _drawFourPointStar(canvas, fillPaint, strokePaint, 11);
            break;
          case 2:
            _drawLoveEnvelope(canvas, strokePaint, 15);
            break;
          case 3:
            _drawCrescentMoon(canvas, strokePaint, fillPaint, 11);
            break;
          case 4:
            _drawInfinityHeart(canvas, strokePaint, 15);
            break;
          case 5:
            _drawSparkleCluster(canvas, strokePaint, 9);
            break;
          case 6:
            _drawPlanetWithRings(canvas, strokePaint, 13);
            break;
          case 7:
            _drawDoubleHearts(canvas, strokePaint, fillPaint, 10);
            break;
        }

        canvas.restore();
      }
    }
  }

  // 1. Minik Aşk Kalbi
  void _drawHeart(Canvas canvas, Paint stroke, Paint fill, double r) {
    final path = Path();
    path.moveTo(0, r * 0.35);
    path.cubicTo(-r, -r * 0.5, -r * 1.2, r * 0.45, 0, r * 1.25);
    path.cubicTo(r * 1.2, r * 0.45, r, -r * 0.5, 0, r * 0.35);
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  // 2. 4 Köşeli Parlak Işıltı Yıldızı (✦)
  void _drawFourPointStar(Canvas canvas, Paint fill, Paint stroke, double r) {
    final path = Path();
    path.moveTo(0, -r);
    path.quadraticBezierTo(0, 0, r, 0);
    path.quadraticBezierTo(0, 0, 0, r);
    path.quadraticBezierTo(0, 0, -r, 0);
    path.quadraticBezierTo(0, 0, 0, -r);
    path.close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
    // Merkezine minik nokta
    canvas.drawCircle(Offset.zero, 1.2, stroke);
  }

  // 3. Aşk Mektubu Zarfı (✉️)
  void _drawLoveEnvelope(Canvas canvas, Paint stroke, double w) {
    final h = w * 0.68;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      const Radius.circular(3),
    );
    canvas.drawRRect(rrect, stroke);

    // Zarf kapağı çizgileri
    final flap = Path()
      ..moveTo(-w / 2, -h / 2)
      ..lineTo(0, h * 0.16)
      ..lineTo(w / 2, -h / 2);
    canvas.drawPath(flap, stroke);

    // Kalp mühür noktası
    canvas.drawCircle(Offset(0, h * 0.05), 1.5, stroke);
  }

  // 4. Romantik Gece Hilali (🌙)
  void _drawCrescentMoon(Canvas canvas, Paint stroke, Paint fill, double r) {
    final path = Path();
    path.addArc(Rect.fromCircle(center: Offset.zero, radius: r), -math.pi / 2, math.pi);
    path.arcTo(Rect.fromCircle(center: Offset(r * 0.38, 0), radius: r * 0.78), math.pi / 2, -math.pi, false);
    path.close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);

    // Hilal yanında minik yıldız
    canvas.drawCircle(Offset(r * 0.6, -r * 0.3), 1.2, stroke);
  }

  // 5. Sonsuz Aşk (Sonsuzluk döngüsü ile kalbin birleşimi)
  void _drawInfinityHeart(Canvas canvas, Paint stroke, double w) {
    final r = w * 0.34;
    canvas.drawCircle(Offset(-r, 0), r * 0.72, stroke);
    canvas.drawCircle(Offset(r, 0), r * 0.72, stroke);
    // Merkezde minik artı
    canvas.drawLine(const Offset(-2, 0), const Offset(2, 0), stroke);
    canvas.drawLine(const Offset(0, -2), const Offset(0, 2), stroke);
  }

  // 6. Işıltı Kümesi (Sparkle Cluster)
  void _drawSparkleCluster(Canvas canvas, Paint stroke, double s) {
    canvas.drawLine(Offset(-s, 0), Offset(s, 0), stroke);
    canvas.drawLine(Offset(0, -s), Offset(0, s), stroke);
    canvas.drawCircle(const Offset(7, -7), 1.4, stroke);
    canvas.drawCircle(const Offset(-7, 7), 1.2, stroke);
    canvas.drawCircle(const Offset(6, 6), 0.9, stroke);
  }

  // 7. Yörüngeli Aşk Gezegeni (🪐)
  void _drawPlanetWithRings(Canvas canvas, Paint stroke, double r) {
    canvas.drawCircle(Offset.zero, r * 0.48, stroke);
    final ovalRect = Rect.fromCenter(center: Offset.zero, width: r * 1.6, height: r * 0.55);
    canvas.save();
    canvas.rotate(-0.25);
    canvas.drawOval(ovalRect, stroke);
    canvas.restore();
  }

  // 8. İç İçe Geçmiş Çift Kalp (💕)
  void _drawDoubleHearts(Canvas canvas, Paint stroke, Paint fill, double r) {
    // Sol kalp
    canvas.save();
    canvas.translate(-4, -2);
    _drawHeart(canvas, stroke, fill, r * 0.85);
    canvas.restore();

    // Sağ üst küçük kalp
    canvas.save();
    canvas.translate(5, 3);
    _drawHeart(canvas, stroke, fill, r * 0.65);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LoveraDoodlePatternPainter oldDelegate) => oldDelegate.isDark != isDark;
}
