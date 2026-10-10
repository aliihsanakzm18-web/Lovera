import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/notification_service.dart';
import '../../dashboard/presentation/main_navigation_shell.dart';
import '../../onboarding/presentation/onboarding_flow.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key, required this.onboarded});

  final bool onboarded;

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      final hasNotifTap = NotificationService().hasPendingNotificationTap;
      if (hasNotifTap) {
        NotificationService().hasPendingNotificationTap = false;
      }
      final initialPage = hasNotifTap ? 2 : 1;

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 650),
          pageBuilder: (context, animation, secondaryAnimation) =>
              widget.onboarded ? MainNavigationShell(initialPage: initialPage) : const OnboardingFlow(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
              child: child,
            );
          },
        ),
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [
                    const Color(0xFF0F0C20),
                    const Color(0xFF1E1338),
                    const Color(0xFF110726),
                  ]
                : [
                    const Color(0xFFFFF0F5),
                    const Color(0xFFFDE2E8),
                    const Color(0xFFF3E8FF),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Arka planda zarif parıltı çemberi
            Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE11D48).withValues(alpha: isDark ? 0.35 : 0.2),
                    blurRadius: 100,
                    spreadRadius: 30,
                  ),
                  BoxShadow(
                    color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.3 : 0.15),
                    blurRadius: 120,
                    spreadRadius: 40,
                  ),
                ],
              ),
            ),

            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // İkon Kutusu
                Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE11D48).withValues(alpha: 0.4),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                      BoxShadow(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: Image.asset(
                      'assets/icons/app_logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                )
                    .animate()
                    .scale(
                      begin: const Offset(0.7, 0.7),
                      end: const Offset(1.0, 1.0),
                      duration: 900.ms,
                      curve: Curves.elasticOut,
                    )
                    .fadeIn(duration: 600.ms)
                    .then()
                    .shimmer(
                      duration: 1200.ms,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),

                const SizedBox(height: 28),

                // Başlık
                Text(
                  'Lovera',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: isDark ? Colors.white : const Color(0xFF1E1B4B),
                  ),
                )
                    .animate()
                    .fadeIn(delay: 350.ms, duration: 600.ms)
                    .slideY(begin: 0.3, end: 0, curve: Curves.easeOutCubic),

                const SizedBox(height: 8),

                // Alt başlık
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'İkiniz İçin Özel Bir Dünya',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.65)
                            : const Color(0xFF64748B),
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.favorite_rounded,
                      size: 14,
                      color: Color(0xFFE11D48),
                    )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scale(
                          begin: const Offset(0.9, 0.9),
                          end: const Offset(1.25, 1.25),
                          duration: 700.ms,
                          curve: Curves.easeInOut,
                        ),
                  ],
                )
                    .animate()
                    .fadeIn(delay: 550.ms, duration: 600.ms)
                    .slideY(begin: 0.3, end: 0, curve: Curves.easeOutCubic),
              ],
            ),

            // Alt Kısım Yükleniyor / Romantik İfade
            Positioned(
              bottom: 48,
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    const Color(0xFFE11D48).withValues(alpha: 0.7),
                  ),
                ),
              ).animate().fadeIn(delay: 800.ms, duration: 400.ms),
            ),
          ],
        ),
      ),
    );
  }
}
