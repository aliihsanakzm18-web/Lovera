import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/presentation/login_page.dart';
import '../../auth/presentation/pairing_view.dart';
import '../../dashboard/presentation/main_navigation_shell.dart';
import 'permissions_page.dart';
import 'welcome_page.dart';

/// Giriş -> (Gerekliyse Hoş Geldin) -> (Eşleşmemişse Eşleşme) -> (Eksik İzin Varsa İzinler) -> Ana ekran
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _page = PageController();
  List<Widget> _steps = [];
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _steps = [
      LoginPage(onSignedIn: _handleSignedIn),
    ];
    _ready = true;
  }

  Future<void> _next() async {
    // Eğer sıradaki adım PermissionsPage ise ve tüm izinler zaten verilmişse doğrudan _finish() çağır
    final nextPageIndex = (_page.page?.round() ?? 0) + 1;
    if (nextPageIndex < _steps.length && _steps[nextPageIndex] is PermissionsPage) {
      final locWhenInUse = await Permission.locationWhenInUse.isGranted;
      final locAlways = await Permission.locationAlways.isGranted;
      final notif = await Permission.notification.isGranted;
      final cam = await Permission.camera.isGranted;
      final hasMissing = !(locWhenInUse || locAlways) || !notif || !cam;
      if (!hasMissing) {
        await _finish();
        return;
      }
    }

    _page.nextPage(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOutCubic,
    );
  }

  void _back() => _page.previousPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );

  Future<void> _handleSignedIn(bool isNewUser) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _next();
      return;
    }

    String? name;
    String? coupleId;
    String? birthDate;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        name = data['name'] as String?;
        coupleId = data['coupleId'] as String?;
        birthDate = data['birthDate'] as String?;
      }
    } catch (_) {}

    final bool needsWelcome = isNewUser || name == null || name.trim().isEmpty || birthDate == null;
    final bool needsPairing = coupleId == null || coupleId.isEmpty;

    // İzinleri kontrol et
    final locWhenInUse = await Permission.locationWhenInUse.isGranted;
    final locAlways = await Permission.locationAlways.isGranted;
    final notif = await Permission.notification.isGranted;
    final cam = await Permission.camera.isGranted;
    final bool hasMissingPermissions = !(locWhenInUse || locAlways) || !notif || !cam;

    final List<Widget> dynamicSteps = [
      LoginPage(onSignedIn: _handleSignedIn),
    ];

    if (needsWelcome) {
      dynamicSteps.add(WelcomePage(onNext: _next, onBack: _back));
    }

    if (needsPairing) {
      dynamicSteps.add(SafeArea(child: PairingContent(onDone: _next, onBack: _back)));
    }

    if (hasMissingPermissions) {
      dynamicSteps.add(PermissionsPage(onFinish: _finish, onBack: _back));
    }

    // Eğer hiçbir ara adıma ihtiyaç yoksa doğrudan ana ekrana git!
    if (!needsWelcome && !needsPairing && !hasMissingPermissions) {
      await _finish();
      return;
    }

    if (mounted) {
      setState(() {
        _steps = dynamicSteps;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _next();
      });
    }
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => const MainNavigationShell(),
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
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: PageView(
        controller: _page,
        physics: const NeverScrollableScrollPhysics(),
        children: _steps,
      ),
    );
  }
}

