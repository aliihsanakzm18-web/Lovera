import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/services/database_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';

class CoupleManagementView extends ConsumerStatefulWidget {
  const CoupleManagementView({super.key});

  @override
  ConsumerState<CoupleManagementView> createState() => _CoupleManagementViewState();
}

class _CoupleManagementViewState extends ConsumerState<CoupleManagementView> {
  bool _requesting = false;

  Future<void> _proposeNewDate() async {
    final partner = ref.read(partnerProvider);
    final partnerUid = ref.read(partnerUidProvider);
    final currentStart = ref.read(startDateProvider) ?? DateTime.now();

    if (partner == null || partnerUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce partnerin ile eşleşmiş olmalısın.')),
      );
      return;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: currentStart,
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
      helpText: 'Yeni Birliktelik Başlangıç Tarihi',
    );

    if (picked == null || !mounted) return;

    setState(() => _requesting = true);

    try {
      final myName = ref.read(userNameProvider);
      await DatabaseService().proposeDateChange(
        partnerUid: partnerUid,
        newDate: picked,
        requesterName: myName.isEmpty ? 'Partnerin' : myName,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tarih değişikliği isteği ${partner.name} adlı partnere iletildi! Onayladığında iki telefonda da güncellenecektir. 💌',
          ),
          backgroundColor: LoveraColors.secondary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İstek gönderilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final partner = ref.watch(partnerProvider);
    final myName = ref.watch(userNameProvider);
    final startDate = ref.watch(startDateProvider);
    final days = startDate != null
        ? (DateTime.now().difference(startDate).inHours / 24).floor() + 1
        : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Eş Yönetim Paneli'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Çift Başlık Kartı
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: theme.dividerColor),
              boxShadow: AppTheme.ambientShadow,
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: LoveraColors.primary.withValues(alpha: 0.15),
                      child: Text(
                        myName.isNotEmpty ? myName[0].toUpperCase() : '?',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: LoveraColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Icon(Icons.favorite_rounded, color: LoveraColors.primary, size: 28)
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scale(begin: const Offset(0.85, 0.85), end: const Offset(1.15, 1.15)),
                    const SizedBox(width: 14),
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: LoveraColors.secondary.withValues(alpha: 0.2),
                      child: Text(
                        partner != null && partner.name.isNotEmpty
                            ? partner.name[0].toUpperCase()
                            : '?',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: LoveraColors.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '$myName & ${partner?.name ?? "Partner"}',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: LoveraColors.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Aktif Eşleşme Bağlantısı',
                    style: TextStyle(
                      color: LoveraColors.secondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn().slideY(begin: 0.05),

          const SizedBox(height: 20),

          // Birlikte Geçen Zaman Ayarı Kartı
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: LoveraColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.calendar_month_rounded, color: LoveraColors.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Birlikte Geçen Süre',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          Text(
                            startDate != null
                                ? '${startDate.day}.${startDate.month}.${startDate.year} ($days Gündür)'
                                : 'Henüz belirlenmedi',
                            style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Aşk sayacınızın tarihi ana ekrandan doğrudan değiştirilemez. Değişiklik yaptığınızda eşinizin onaylaması gerekir.',
                  style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted, height: 1.4),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: _requesting ? null : _proposeNewDate,
                    icon: _requesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.edit_calendar_rounded, size: 20),
                    label: const Text('Tarih Değiştirme İsteği Gönder'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
