import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/services/background_tracking_service.dart';
import 'core/services/notification_service.dart';
import 'core/state/app_state.dart';
import 'core/theme/app_theme.dart';
import 'features/dashboard/presentation/main_navigation_shell.dart';
import 'features/onboarding/presentation/onboarding_flow.dart';

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

  // Arka plan ve bildirim servislerini UI render'ı bloke etmeden asenkron başlat
  NotificationService().init().catchError((e) => debugPrint('Notification init error: $e'));
  BackgroundTrackingService().initialize().catchError((e) => debugPrint('BG init error: $e'));
  
  final prefs = await SharedPreferences.getInstance();
  final currentUid = FirebaseAuth.instance.currentUser?.uid;
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

  runApp(ProviderScope(
    overrides: [
      userNameProvider.overrideWith((ref) => name),
      userAvatarProvider.overrideWith((ref) => initialAvatar),
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

    return MaterialApp(
      title: 'Lovera',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: onboarded ? const MainNavigationShell() : const OnboardingFlow(),
    );
  }
}
