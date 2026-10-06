import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/state/app_state.dart';
import 'core/theme/app_theme.dart';
import 'features/dashboard/presentation/dashboard_view.dart';
import 'features/onboarding/presentation/onboarding_flow.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }
  
  final prefs = await SharedPreferences.getInstance();
  final onboarded = prefs.getBool('onboarded') ?? false;
  final name = prefs.getString('name') ?? '';
  final themeModeStr = prefs.getString('theme_mode') ?? 'system';
  final initialThemeMode = themeModeStr == 'light'
      ? ThemeMode.light
      : (themeModeStr == 'dark' ? ThemeMode.dark : ThemeMode.system);

  runApp(ProviderScope(
    overrides: [
      userNameProvider.overrideWith((ref) => name),
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
      home: onboarded ? const DashboardView() : const OnboardingFlow(),
    );
  }
}
