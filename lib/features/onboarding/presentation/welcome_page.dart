import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/database_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';

class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key, required this.onNext, required this.onBack});
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends ConsumerState<WelcomePage> {
  late final TextEditingController _name =
      TextEditingController(text: ref.read(userNameProvider));

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valid = _name.text.trim().isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: widget.onBack,
                ),
              ),
              const SizedBox(height: 16),
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: LoveraColors.secondary.withValues(alpha: 0.18),
                    ),
                  ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(
                      begin: const Offset(0.9, 0.9), end: const Offset(1.08, 1.08), duration: 2.seconds),
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: LoveraColors.primarySoft.withValues(alpha: 0.22),
                    ),
                  ),
                  const Icon(Icons.favorite_rounded, size: 54, color: LoveraColors.primary),
                ],
              ),
              const SizedBox(height: 28),
              Text('Hoş geldin 💛',
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800))
                  .animate().fadeIn().slideY(begin: 0.2),
              const SizedBox(height: 10),
              Text(
                'Lovera, birlikte geçirdiğiniz her anı, her günü ve her mesafeyi bir arada tutar.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: LoveraColors.textMuted, height: 1.45),
              ).animate(delay: 120.ms).fadeIn(),
              const SizedBox(height: 28),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Sana nasıl hitap edelim?',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ).animate(delay: 220.ms).fadeIn(),
              const SizedBox(height: 36),
              FilledButton(
                onPressed: valid
                    ? () async {
                        final n = _name.text.trim();
                        ref.read(userNameProvider.notifier).state = n;
                        (await SharedPreferences.getInstance()).setString('name', n);
                        await DatabaseService().updateUserName(n);
                        widget.onNext();
                      }
                    : null,
                child: const Text('Devam Et'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
