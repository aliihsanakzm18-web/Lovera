import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/widget_sync_service.dart';
import '../../../core/state/app_state.dart';
import '../../auth/presentation/login_page.dart';
import '../../auth/presentation/pairing_view.dart';
import '../../dashboard/presentation/main_navigation_shell.dart';
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
    final nextPageIndex = (_page.page?.round() ?? 0) + 1;
    // Son adımdaysak (ör. eşleşmeyi 'Şimdilik atla' ile geçmek) doğrudan ana ekrana geç.
    if (nextPageIndex >= _steps.length) {
      await _finish();
      return;
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
    String? partnerUid;
    String? relationshipStartDate;
    String? avatarUrl;
    String? widgetBgUrl;
    String? birthDate;

    DocumentSnapshot<Map<String, dynamic>>? doc;
    // Taze kurulum sonrasında Android'de Google Play Services SSL (ProviderInstaller)
    // ilk birkaç yüz milisaniye içinde hazırlandığı için doğrudan sunucudan (Source.server)
    // yeniden denemeli (retry) olarak oku; böylece eksik yerel önbelleğe düşülmez!
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 4));
        break;
      } catch (_) {
        if (attempt < 2) {
          await Future.delayed(const Duration(milliseconds: 400));
        }
      }
    }
    if (doc == null) {
      try {
        doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get()
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    if (doc != null && doc.exists && doc.data() != null) {
      final data = doc.data()!;
      name = data['name'] as String?;
      coupleId = data['coupleId'] as String?;
      partnerUid = data['partnerUid'] as String?;
      relationshipStartDate = data['relationshipStartDate'] as String?;
      avatarUrl = data['avatarUrl'] as String?;
      widgetBgUrl = data['widgetBgUrl'] as String?;
      birthDate = data['birthDate'] as String?;

      // Hesaba kayıtlı dil, tema modu ve tema paketini başka cihazda giriş yapılır yapılmaz uygula
      final remoteLang = data['language'] as String?;
      if (remoteLang == 'en' || remoteLang == 'tr') {
        final targetLang = remoteLang == 'en' ? AppLanguage.en : AppLanguage.tr;
        await ref.read(appLanguageProvider.notifier).setLanguage(targetLang, syncToCloud: false);
      }

      final remoteThemeMode = data['themeMode'] as String?;
      if (remoteThemeMode == 'light' || remoteThemeMode == 'dark' || remoteThemeMode == 'system') {
        final targetMode = remoteThemeMode == 'light'
            ? ThemeMode.light
            : (remoteThemeMode == 'dark' ? ThemeMode.dark : ThemeMode.system);
        await ref.read(themeModeProvider.notifier).setThemeMode(targetMode, syncToCloud: false);
      }

      final remotePaletteKey = data['themePalette'] as String?;
      if (remotePaletteKey != null && remotePaletteKey.isNotEmpty) {
        final targetPalette = ThemePaletteData.fromKey(remotePaletteKey);
        await ref.read(themePaletteProvider.notifier).setPalette(targetPalette.id, syncToCloud: false);
      }
    }

    // Ekstra güvenlik ağı: Eğer kullanıcı belgesinde coupleId herhangi bir sebeple boş görünüyorsa,
    // couples koleksiyonunda bu kullanıcının aktif bir eşleşmesi var mı diye kontrol et!
    if (coupleId == null || coupleId.isEmpty) {
      try {
        var q = await FirebaseFirestore.instance
            .collection('couples')
            .where('user1', isEqualTo: uid)
            .where('status', isEqualTo: 'active')
            .limit(1)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 3));
        if (q.docs.isEmpty) {
          q = await FirebaseFirestore.instance
              .collection('couples')
              .where('user2', isEqualTo: uid)
              .where('status', isEqualTo: 'active')
              .limit(1)
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 3));
        }
        if (q.docs.isNotEmpty) {
          final cDoc = q.docs.first;
          final cData = cDoc.data();
          coupleId = cDoc.id;
          final u1 = cData['user1'] as String?;
          final u2 = cData['user2'] as String?;
          partnerUid = (u1 == uid) ? u2 : u1;
          relationshipStartDate ??= cData['relationshipStartDate'] as String?;
          // Kullanıcı belgesine de geri senkronize et
          FirebaseFirestore.instance.collection('users').doc(uid).set({
            'coupleId': coupleId,
            if (partnerUid != null) 'partnerUid': partnerUid,
            if (relationshipStartDate != null) 'relationshipStartDate': relationshipStartDate,
          }, SetOptions(merge: true));
        }
      } catch (_) {}
    }

    // Sunucudan tam profil okunduktan sonra cihaz oturumunu bağla
    AuthService().registerDeviceSession(uid);

    final prefs = await SharedPreferences.getInstance();
    name ??= prefs.getString('name') ?? FirebaseAuth.instance.currentUser?.displayName;
    if (birthDate != null && birthDate.isNotEmpty) {
      await prefs.setString('birthDate', birthDate);
    }
    if (coupleId != null && coupleId.isNotEmpty) {
      await prefs.setString('saved_couple_id', coupleId);
      ref.read(coupleIdProvider.notifier).state = coupleId;
    }
    if (partnerUid != null && partnerUid.isNotEmpty) {
      await prefs.setString('saved_partner_uid', partnerUid);
      ref.read(partnerUidProvider.notifier).state = partnerUid;
    }
    if (relationshipStartDate != null && relationshipStartDate.isNotEmpty) {
      await prefs.setString('saved_start_date', relationshipStartDate);
      final parsedStart = DateTime.tryParse(relationshipStartDate);
      if (parsedStart != null) {
        ref.read(startDateProvider.notifier).state = parsedStart;
      }
    }

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

    // Hoş geldin ekranı: SADECE Firestore'da veya yerel hafızada ismi hiç bulunmayan yeni kullanıcılara gösterilir.
    // Eğer kullanıcının daha önceden kayıtlı bir ismi varsa ASLA tekrar sorulmaz!
    final bool hasExistingName = (name != null && name.trim().isNotEmpty) ||
        (FirebaseAuth.instance.currentUser?.displayName != null &&
            FirebaseAuth.instance.currentUser!.displayName!.trim().isNotEmpty);

    final bool needsWelcome = !hasExistingName;

    // Eşleşme ekranı: Sadece henüz bir çifte bağlı olmayanlara sorulur.
    final bool needsPairing = coupleId == null || coupleId.isEmpty;

    final List<Widget> dynamicSteps = [
      LoginPage(onSignedIn: _handleSignedIn),
    ];

    if (needsWelcome) {
      dynamicSteps.add(WelcomePage(onNext: _next, onBack: _back));
    }

    if (needsPairing) {
      dynamicSteps.add(SafeArea(child: PairingContent(onDone: _next, onBack: _back)));
    }

    // Kullanıcı isteği: Eksik izinler sayfası giriş akışından tamamen kaldırıldı!
    // İzinler uygulama içine girdikten sonra teker teker ve zarifçe istenecek.

    // Eğer hiçbir ara adıma ihtiyaç yoksa doğrudan ana ekrana git!
    if (!needsWelcome && !needsPairing) {
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

