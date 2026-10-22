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

  Future<void> _changeRelationshipDate() async {
    final partner = ref.read(partnerProvider);
    final partnerUid = ref.read(partnerUidProvider);
    final coupleId = ref.read(coupleIdProvider);
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
      final effectiveName = myName.isEmpty ? 'Partnerin' : myName;

      await DatabaseService().updateRelationshipDateDirectly(
        newDate: picked,
        partnerUid: partnerUid,
        coupleId: coupleId,
        updaterName: effectiveName,
      );

      // Partnere push bildirim gönder
      NotificationService().sendPushToPartner(
        partnerUid: partnerUid,
        title: '🗓️ Birliktelik Tarihi Güncellendi',
        body: '$effectiveName birliktelik başlangıç tarihinizi ${picked.day}.${picked.month}.${picked.year} olarak güncelledi 💕',
        data: {'type': 'date_updated'},
      );

      ref.read(startDateProvider.notifier).state = picked;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Birliktelik tarihi güncellendi ve ${partner.name} adlı partnere bildirildi! 💕',
          ),
          backgroundColor: LoveraColors.secondary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tarih güncellenemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _blockAndDisconnectImmediately() async {
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

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Partneri Engelle'),
        content: Text(
          '$partnerName adlı kullanıcıyı engellediğinizde eşleşmeniz ve konum paylaşımınız sonlandırılır. Bu kullanıcı size tekrar eşleşme isteği gönderemez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Engelle'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _requesting = true);
    try {
      await DatabaseService().blockAndUnpairPartner(
        partnerUid: partnerUid,
        coupleId: coupleId,
      );
      ref.read(coupleIdProvider.notifier).state = null;
      ref.read(partnerUidProvider.notifier).state = null;
      ref.read(partnerProvider.notifier).state = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kullanıcı engellendi ve tüm bağlantınız anında sonlandırıldı.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İşlem sırasında hata oluştu: $e')),
      );
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _reportPartnerDialog() async {
    final partnerUid = ref.read(partnerUidProvider);
    final coupleId = ref.read(coupleIdProvider);
    final reasonCtrl = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Kullanıcıyı Şikayet Et'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rahatsız edici davranış veya uygunsuz içerik bildirimleriniz güvenlik ekibimiz tarafından en geç 24 saat içinde incelenir.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Şikayet nedeninizi kısaca yazın...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Gönder'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService().reportContent(
        contentType: 'user',
        contentId: partnerUid ?? 'unknown_partner',
        coupleId: coupleId,
        reportedUserId: partnerUid,
        reason: reasonCtrl.text.trim().isEmpty
            ? 'Eş yönetim panelinden kullanıcı şikayeti'
            : reasonCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Şikayetiniz güvenlik ekibimize iletildi. 24 saat içinde incelenecektir.'),
          ),
        );
      }
    }
    reasonCtrl.dispose();
  }

  Future<void> _unpairImmediately() async {
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
                  'Eşleşmeyi Sonlandır',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  '$partnerName ile olan eşleşmeniz anında sonlandırılacak; sayaç ve ortak bağlantı her iki cihazda da kapatılacaktır. Onaylıyor musunuz?',
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
                        child: const Text('Ayrıl 💔', style: TextStyle(fontWeight: FontWeight.w800)),
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
      await DatabaseService().acceptBreakup(
        partnerUid: partnerUid,
        coupleId: coupleId,
      );

      // Partnere anlık bilgi bildirimi
      NotificationService().sendPushToPartner(
        partnerUid: partnerUid,
        title: '💔 Eşleşme Sonlandırıldı',
        body: '${myName.isEmpty ? "Partnerin" : myName} seninle olan eşleşmeyi sonlandırdı.',
        data: {'type': 'breakup_completed'},
      );

      ref.read(coupleIdProvider.notifier).state = null;
      ref.read(partnerUidProvider.notifier).state = null;
      ref.read(partnerProvider.notifier).state = null;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Eşleşmeniz sonlandırıldı.'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ayrılma işlemi sırasında hata oluştu: $e')),
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
                  'Aşk sayacınızın tarihini doğrudan güncelleyebilirsiniz. Güncellediğinizde partnerinize anında bilgilendirme bildirimi iletilir.',
                  style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted, height: 1.4),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: _requesting ? null : _changeRelationshipDate,
                    icon: _requesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.edit_calendar_rounded, size: 20),
                    label: const Text('Birliktelik Tarihini Değiştir'),
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
                  'Eşleşmeden ayrıldığınızda ortak sayaç, anılar ve canlı bağlantı iki tarafta da sonlandırılır. Engellediğinizde ise kullanıcı size tekrar istek gönderemez.',
                  style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted, height: 1.4),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          side: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: _requesting ? null : _unpairImmediately,
                        icon: const Icon(Icons.heart_broken_outlined, size: 20),
                        label: const Text(
                          'Eşleşmeden Ayrıl',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.12),
                          foregroundColor: const Color(0xFFEF4444),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
                          ),
                        ),
                        onPressed: _requesting ? null : _blockAndDisconnectImmediately,
                        icon: const Icon(Icons.block_rounded, size: 20),
                        label: const Text(
                          'Engelle',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFF59E0B),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    ),
                    onPressed: _requesting ? null : _reportPartnerDialog,
                    icon: const Icon(Icons.flag_outlined, size: 16),
                    label: const Text(
                      'Kullanıcıyı Şikayet Et',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
