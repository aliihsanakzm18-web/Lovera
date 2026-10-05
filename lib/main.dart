import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/state/app_state.dart';
import 'core/theme/app_theme.dart';
import 'features/dashboard/presentation/dashboard_view.dart';
import 'features/onboarding/presentation/onboarding_flow.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final prefs = await SharedPreferences.getInstance();
  final onboarded = prefs.getBool('onboarded') ?? false;
  final name = prefs.getString('name') ?? '';
  runApp(ProviderScope(
    overrides: [userNameProvider.overrideWith((ref) => name)],
    child: LoveraApp(onboarded: onboarded),
  ));
}

class LoveraApp extends StatelessWidget {
  const LoveraApp({super.key, required this.onboarded});
  final bool onboarded;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lovera',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: onboarded ? const DashboardView() : const OnboardingFlow(),
    );
  }
}
