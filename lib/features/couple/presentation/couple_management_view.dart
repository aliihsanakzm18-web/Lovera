import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/database_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_cache.dart';
import '../../../core/widgets/lovera_theme_background.dart';

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

  Future<void> _confirmAndProposeBreakup() async {
    final partner = ref.read(partnerProvider);
    final partnerUid = ref.read(partnerUidProvider);
    final coupleId = ref.read(coupleIdProvider);
    final partnerName = partner?.name ?? 'Partnerin';

    if (partner == null || partnerUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aktif bir eşleşme bulunamadı.')),
      );
      return;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bCtx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E212B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 25,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.heart_broken_rounded, color: Color(0xFFEF4444), size: 36),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Eşleşmeden Ayrıl',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  '$partnerName adlı partnerine ayrılma isteği gönderilecek. Karşı taraf alt menüden onayladığında eşleşmeniz kalıcı olarak sonlanacaktır.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => Navigator.pop(bCtx, false),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => Navigator.pop(bCtx, true),
                        child: const Text('İstek Gönder 💔', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _requesting = true);

    try {
      final myName = ref.read(userNameProvider);
      await DatabaseService().proposeBreakup(
        partnerUid: partnerUid,
        requesterName: myName.isEmpty ? 'Partnerin' : myName,
        coupleId: coupleId,
      );

      // Partnere anlık push bildirim gönder
      NotificationService().sendPushToPartner(
        partnerUid: partnerUid,
        title: '💔 Eşleşme Ayrılma Talebi',
        body: '${myName.isEmpty ? "Partnerin" : myName} seninle olan eşleşmeyi sonlandırmak istiyor.',
        data: {'type': 'breakup_request'},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ayrılma isteği $partnerName adlı partnere iletildi. Onayladığında eşleşmeniz sonlanacaktır.',
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ayrılma isteği gönderilemedi: $e')),
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

    final myAvatar = ref.watch(userAvatarProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Eş Yönetim Paneli'),
      ),
      body: LoveraThemeBackground(
        child: ListView(
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
                    LoveraAvatar(
                      avatarUrl: myAvatar,
                      fallbackLetter: myName,
                      radius: 34,
                    ),
                    const SizedBox(width: 14),
                    const Icon(Icons.favorite_rounded, color: LoveraColors.primary, size: 28)
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scale(begin: const Offset(0.85, 0.85), end: const Offset(1.15, 1.15)),
                    const SizedBox(width: 14),
                    LoveraAvatar(
                      avatarUrl: partner?.avatarUrl,
                      fallbackLetter: partner?.name ?? 'Partner',
                      radius: 34,
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

          const SizedBox(height: 20),

          // Eşleşmeden Ayrılma Kartı
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(
                color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.heart_broken_rounded, color: Color(0xFFEF4444)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Eşleşmeyi Sonlandır',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFEF4444),
                            ),
                          ),
                          Text(
                            'Partnerinle olan bağlantıyı kopar',
                            style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Ayrılma isteği gönderildiğinde karşı tarafa onaylama için özel bir alt menü çıkar. Eşin onayladığında sayaç ve çift bağlantısı her iki cihazda da sonlandırılır.',
                  style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted, height: 1.4),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _requesting ? null : _confirmAndProposeBreakup,
                    icon: const Icon(Icons.heart_broken_outlined, size: 20),
                    label: const Text(
                      'Eşleşmeden Ayrıl',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
}
