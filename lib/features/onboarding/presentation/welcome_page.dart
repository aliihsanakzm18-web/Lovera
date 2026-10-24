import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/localization/app_strings.dart';
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
  DateTime? _selectedBirthDate;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedBirthDate ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1940),
      lastDate: now,
      helpText: loc('Doğum Tarihinizi Seçin', 'Select Your Date of Birth'),
      cancelText: loc('Vazgeç', 'Cancel'),
      confirmText: loc('Seç', 'Select'),
    );
    if (picked != null && mounted) {
      setState(() => _selectedBirthDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Apple Guideline 5.1.1(i)/(ii) Veri Minimizasyonu: Doğum tarihi isteğe bağlıdır, zorunlu tutulamaz.
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
                  Icon(Icons.favorite_rounded, size: 54, color: LoveraColors.primary),
                ],
              ),
              const SizedBox(height: 28),
              Text(loc('Hoş geldin 💛', 'Welcome 💛'),
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800))
                  .animate().fadeIn().slideY(begin: 0.2),
              const SizedBox(height: 10),
              Text(
                loc(
                  'Lovera, birlikte geçirdiğiniz her anı, her günü ve her mesafeyi bir arada tutar.',
                  'Lovera keeps every moment, day, and distance you share close together.',
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: LoveraColors.textMuted, height: 1.45),
              ).animate(delay: 120.ms).fadeIn(),
              const SizedBox(height: 28),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: loc('Sana nasıl hitap edelim?', 'What should we call you?'),
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
              ).animate(delay: 220.ms).fadeIn(),
              const SizedBox(height: 14),
              InkWell(
                onTap: _pickBirthDate,
                borderRadius: BorderRadius.circular(AppTheme.radius),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.cake_rounded, color: LoveraColors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedBirthDate == null
                              ? loc('Doğum Tarihini Seç (İsteğe Bağlı)', 'Select Date of Birth (Optional)')
                              : '${_selectedBirthDate!.day}.${_selectedBirthDate!.month}.${_selectedBirthDate!.year}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: _selectedBirthDate != null ? FontWeight.w600 : FontWeight.normal,
                            color: _selectedBirthDate != null
                                ? theme.colorScheme.onSurface
                                : LoveraColors.textMuted,
                          ),
                        ),
                      ),
                      Icon(Icons.calendar_month_rounded, size: 20, color: LoveraColors.textMuted),
                    ],
                  ),
                ),
              ).animate(delay: 280.ms).fadeIn(),
              const SizedBox(height: 36),
              FilledButton(
                onPressed: valid
                    ? () async {
                        final n = _name.text.trim();
                        ref.read(userNameProvider.notifier).state = n;
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('name', n);
                        await DatabaseService().updateUserName(n);

                        if (_selectedBirthDate != null) {
                          final bDate = _selectedBirthDate!;
                          final bStr = '${bDate.year.toString().padLeft(4, '0')}-${bDate.month.toString().padLeft(2, '0')}-${bDate.day.toString().padLeft(2, '0')}';
                          await DatabaseService().updateBirthDate(bStr, userName: n);
                        }

                        widget.onNext();
                      }
                    : null,
                child: Text(loc('Devam Et', 'Continue')),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
