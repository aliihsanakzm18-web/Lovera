import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/database_service.dart';
import '../../../core/services/widget_sync_service.dart';
import '../../../core/state/app_state.dart';
import '../../auth/presentation/login_page.dart';
import '../../auth/presentation/pairing_view.dart';
import '../../dashboard/presentation/main_navigation_shell.dart';
import 'permissions_page.dart';
import 'welcome_page.dart';

/// Giriş -> (Gerekliyse Hoş Geldin) -> (Eşleşmemişse Eşleşme) -> (Eksik İzin Varsa İzinler) -> Ana ekran
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
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
    if (!_page.hasClients) return;
    // Eğer sıradaki adım PermissionsPage ise ve tüm izinler zaten verilmişse doğrudan _finish() çağır
    final nextPageIndex = (_page.page?.round() ?? 0) + 1;
    // Son adımdaysak (ör. eşleşmeyi 'Şimdilik atla' ile geçmek) doğrudan ana ekrana geç.
    if (nextPageIndex >= _steps.length) {
      await _finish();
      return;
    }
    if (nextPageIndex < _steps.length && _steps[nextPageIndex] is PermissionsPage) {
      final locWhenInUse = await Permission.locationWhenInUse.isGranted;
      final locAlways = await Permission.locationAlways.isGranted;
      final notif = await Permission.notification.isGranted;
      final hasMissing = !(locWhenInUse || locAlways) || !notif;
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

  void _back() {
    if (_page.hasClients) {
      _page.previousPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  Future<void> _handleSignedIn(bool isNewUser) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _next();
      return;
    }

    // Her hesap değişiminde önceki oturumun durumunu tamamen sıfırla
    ref.read(userNameProvider.notifier).state = '';
    ref.read(userAvatarProvider.notifier).state = null;

    String? name;
    String? coupleId;
    String? avatarUrl;
    String? widgetBgUrl;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 4));
      if (doc.exists) {
        final data = doc.data()!;
        name = data['name'] as String?;
        coupleId = data['coupleId'] as String?;
        avatarUrl = data['avatarUrl'] as String?;
        widgetBgUrl = data['widgetBgUrl'] as String?;
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    name ??= prefs.getString('name');

    // Kullanıcı adı ve profil fotoğrafını Riverpod ve SharedPreferences'a hemen yükle
    if (name != null && name.trim().isNotEmpty) {
      await prefs.setString('name', name);
      ref.read(userNameProvider.notifier).state = name;
    }
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      await prefs.setString('avatar_$uid', avatarUrl);
      ref.read(userAvatarProvider.notifier).state = avatarUrl;
    } else {
      // Eğer Firestore'da avatar henüz yoksa bu kullanıcının yerel önbelleğindeki fotoğrafı kontrol et
      final cachedAvatar = prefs.getString('avatar_$uid');
      if (cachedAvatar != null && cachedAvatar.isNotEmpty) {
        ref.read(userAvatarProvider.notifier).state = cachedAvatar;
        DatabaseService().updateAvatar(cachedAvatar);
      } else {
        ref.read(userAvatarProvider.notifier).state = null;
      }
    }

    // Hesaba kayıtlı widget arka plan fotoğrafı varsa yeni cihaza otomatik geri yükle
    if (widgetBgUrl != null && widgetBgUrl.isNotEmpty) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final targetPath = '${appDir.path}/widget_bg_custom.jpg';
        final clean = widgetBgUrl.contains(',') ? widgetBgUrl.split(',').last : widgetBgUrl;
        await File(targetPath).writeAsBytes(base64Decode(clean));
        await prefs.setString('widget_custom_bg_path', targetPath);
        await WidgetSyncService.setWidgetBackgroundImage(targetPath);
      } catch (_) {}
    }

    // Hoş geldin ekranı: Sadece ilk kez kayıt olan ya da henüz ismi hiç girilmemiş kullanıcıya sorulur.
    // Giriş yapan mevcut kullanıcılara ASLA tekrar sorulmaz!
    final bool needsWelcome = isNewUser || name == null || name.trim().isEmpty;
    // Eşleşme ekranı: Sadece henüz bir çifte bağlı olmayanlara sorulur.
    final bool needsPairing = coupleId == null || coupleId.isEmpty;

    // İzinleri kontrol et: Eksik izin yoksa ASLA izin ekranını gösterme!
    final locWhenInUse = await Permission.locationWhenInUse.isGranted;
    final locAlways = await Permission.locationAlways.isGranted;
    final notif = await Permission.notification.isGranted;
    final bool hasMissingPermissions = !(locWhenInUse || locAlways) || !notif;

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

