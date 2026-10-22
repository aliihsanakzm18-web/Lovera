import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import 'core/localization/app_strings.dart';
import 'core/models/models.dart';
import 'core/services/background_tracking_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/widget_sync_service.dart';
import 'core/state/app_state.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/presentation/splash_view.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  // Sayfa geçişlerinde anlık render aksaklıklarında kırmızı hata ekranı (Red Screen of Death)
  // flaşlamasını önle; hatayı sessizce konsola bas ve UI'ı temiz/şeffaf tut
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[FLUTTER-ERROR-CAUGHT] ${details.exceptionAsString()}');
  };
  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('[ERROR-WIDGET-TRIGGERED] ${details.exceptionAsString()}\n${details.stack}');
    return const SizedBox.shrink();
  };

  final prefs = await SharedPreferences.getInstance();
  final currentUid = FirebaseAuth.instance.currentUser?.uid;
  // Not: Bildirim ve Konum izinleri kullanıcı hesaba giriş yaptıktan sonra (DashboardView içinde)
  // zarifçe ve sırayla istenir. Giriş öncesinde izin popup'ı ASLA açılmaz.
  if (currentUid != null && currentUid.isNotEmpty) {
    NotificationService().init(requestPermissions: false).catchError((e) => debugPrint('Notification init error: $e'));
    BackgroundTrackingService().initialize().catchError((e) => debugPrint('BG init error: $e'));
  }
  if (currentUid != null && currentUid.isNotEmpty) {
    await prefs.setString('saved_uid', currentUid);
  } else {
    await prefs.remove('saved_uid');
  }

  final onboarded = prefs.getBool('onboarded') ?? false;
  final name = prefs.getString('name') ?? '';
  final initialAvatar = currentUid != null ? prefs.getString('avatar_$currentUid') : null;
  final themeModeStr = prefs.getString('theme_mode') ?? 'system';
  final initialThemeMode = themeModeStr == 'light'
      ? ThemeMode.light
      : (themeModeStr == 'dark' ? ThemeMode.dark : ThemeMode.system);

  // Önbellekteki partner, coupleId ve sayaç tarihini oku (açılışta sıfır gecikmeli gösterim için)
  final savedCoupleId = prefs.getString('saved_couple_id');
  final savedPartnerUid = prefs.getString('saved_partner_uid');
  final savedStartDateStr = prefs.getString('saved_start_date');
  final initialStartDate = savedStartDateStr != null ? DateTime.tryParse(savedStartDateStr) : null;
  
  AppUser? initialPartner;
  final cachedPartnerJson = prefs.getString('cached_partner_json');
  if (cachedPartnerJson != null && cachedPartnerJson.isNotEmpty) {
    try {
      final decoded = jsonDecode(cachedPartnerJson) as Map<String, dynamic>;
      initialPartner = AppUser.fromJson(decoded);
    } catch (e) {
      debugPrint('Partner cache decode error: $e');
    }
  }

  // iOS App Group'u hemen bağla ve hafızadaki son partner verisini anında Widget'a aktar
  try {
    await HomeWidget.setAppGroupId(WidgetSyncService.appGroupId);
    if (initialPartner != null || initialStartDate != null) {
      List<SavedPlace> cachedPlaces = [];
      final cachedPlacesJson = prefs.getString('cached_saved_places_json');
      if (cachedPlacesJson != null && cachedPlacesJson.isNotEmpty) {
        try {
          final List decoded = jsonDecode(cachedPlacesJson);
          cachedPlaces = decoded.map((e) => SavedPlace.fromJson(Map<String, dynamic>.from(e), e['id']?.toString() ?? '')).toList();
        } catch (_) {}
      }
      WidgetSyncService.syncWidget(
        partner: initialPartner,
        startDate: initialStartDate,
        savedPlaces: cachedPlaces,
      );
    }
    // Uygulama temasına göre widget temasını erkenden doğrula ve senkronize et
    final savedWidgetTheme = prefs.getString('widget_theme') ?? 'app';
    if (savedWidgetTheme != 'dark' && savedWidgetTheme != 'light') {
      String effectiveWidgetTheme;
      if (initialThemeMode == ThemeMode.light) {
        effectiveWidgetTheme = 'light';
      } else if (initialThemeMode == ThemeMode.dark) {
        effectiveWidgetTheme = 'dark';
      } else {
        final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
        effectiveWidgetTheme = brightness == Brightness.dark ? 'dark' : 'light';
      }
      await WidgetSyncService.setWidgetTheme(effectiveWidgetTheme, savedPreferenceMode: 'app');
    }
  } catch (e) {
    debugPrint('[Main] Widget early sync error: $e');
  }

  runApp(ProviderScope(
    overrides: [
      userNameProvider.overrideWith((ref) => name),
      userAvatarProvider.overrideWith((ref) => initialAvatar),
      coupleIdProvider.overrideWith((ref) => savedCoupleId),
      partnerUidProvider.overrideWith((ref) => savedPartnerUid),
      if (initialPartner != null) partnerProvider.overrideWith((ref) => initialPartner),
      if (initialStartDate != null) startDateProvider.overrideWith((ref) => initialStartDate),
      themeModeProvider.overrideWith((ref) => ThemeModeNotifier(initialMode: initialThemeMode)),
    ],
    child: LoveraApp(onboarded: onboarded),
  ));
}

class LoveraApp extends ConsumerWidget {
  const LoveraApp({super.key, required this.onboarded});
  final bool onboarded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final appLanguage = ref.watch(appLanguageProvider);

    return MaterialApp(
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      title: 'Lovera',
      debugShowCheckedModeBanner: false,
      locale: Locale(appLanguage == AppLanguage.en ? 'en' : 'tr'),
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      builder: (context, child) {
        return _OfflineBannerWrapper(child: child ?? const SizedBox());
      },
      home: SplashView(onboarded: onboarded),
    );
  }
}

class _OfflineBannerWrapper extends ConsumerWidget {
  const _OfflineBannerWrapper({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(connectivityProvider);

    return Stack(
      children: [
        child,
        AnimatedPositioned(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          top: isOnline ? -90 : 0,
          left: 0,
          right: 0,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 6,
                bottom: 8,
                left: 16,
                right: 16,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFE11D48),
                    Color(0xFFBE123C),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE11D48).withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.wifi_off_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    ref.watch(stringsProvider).offlineBanner,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: () {
                      ref.read(connectivityProvider.notifier).checkConnection();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.refresh_rounded, color: Colors.white, size: 13),
                          const SizedBox(width: 4),
                          Text(
                            ref.watch(stringsProvider).retry,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
