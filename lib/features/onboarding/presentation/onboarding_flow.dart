import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/presentation/login_page.dart';
import '../../auth/presentation/pairing_view.dart';
import '../../dashboard/presentation/dashboard_view.dart';
import 'permissions_page.dart';
import 'welcome_page.dart';

/// Giriş -> Hoş geldin -> Eşleşme -> İzinler -> Ana ekran (sola kayarak).
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _page = PageController();

  void _next() => _page.nextPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );

  void _back() => _page.previousPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => const DashboardView(),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero)
              .chain(CurveTween(curve: Curves.easeInOutCubic))
              .animate(anim),
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _page,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          LoginPage(onSignedIn: _next),
          WelcomePage(onNext: _next, onBack: _back),
          SafeArea(child: PairingContent(onDone: _next, onBack: _back)),
          PermissionsPage(onFinish: _finish, onBack: _back),
        ],
      ),
    );
  }
}
