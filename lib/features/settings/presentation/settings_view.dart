import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../onboarding/presentation/onboarding_flow.dart';
import 'account_settings_view.dart';

class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  // Bildirim ayarları durumları
  bool _notifHeart = true;
  bool _notifMilestones = true;
  bool _notifDistance = true;

  // Gizlilik ayarları durumları
  bool _shareLiveLocation = true;
  bool _showOnlineStatus = true;

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Oturumu Kapat'),
        content: const Text('Hesabınızdan çıkış yapmak istediğinize emin misiniz?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: LoveraColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(100, 44),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await AuthService().signOut();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('onboarded');
    await prefs.remove('name');

    ref.read(userNameProvider.notifier).state = '';
    ref.read(partnerProvider.notifier).state = null;
    ref.read(startDateProvider.notifier).state = null;
    ref.read(milestonesProvider.notifier).state = [];

    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingFlow()),
        (route) => false,
      );
    }
  }

  // 1. Bildirimler Ekranı / BottomSheet
  void _openNotificationsSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final theme = Theme.of(ctx);
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    'Bildirim Ayarları',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('“Seni Düşünüyorum” Kalpleri', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Partnerinizden gelen anlık titreşimli kalpler', style: TextStyle(color: LoveraColors.textMuted)),
                  activeColor: LoveraColors.primary,
                  value: _notifHeart,
                  onChanged: (val) {
                    setState(() => _notifHeart = val);
                    setModalState(() => _notifHeart = val);
                  },
                ),
                Divider(color: theme.dividerColor),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Özel Gün Hatırlatıcıları', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Yıldönümü ve doğum günleri yaklaşınca haber ver', style: TextStyle(color: LoveraColors.textMuted)),
                  activeColor: LoveraColors.primary,
                  value: _notifMilestones,
                  onChanged: (val) {
                    setState(() => _notifMilestones = val);
                    setModalState(() => _notifMilestones = val);
                  },
                ),
                Divider(color: theme.dividerColor),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mesafe ve Yakınlaşma', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Partnerinizle birbirinize yaklaştığınızda bildir', style: TextStyle(color: LoveraColors.textMuted)),
                  activeColor: LoveraColors.primary,
                  value: _notifDistance,
                  onChanged: (val) {
                    setState(() => _notifDistance = val);
                    setModalState(() => _notifDistance = val);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // 2. Gizlilik ve Güvenlik Ekranı / BottomSheet
  void _openPrivacySettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final theme = Theme.of(ctx);
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    'Gizlilik ve Güvenlik',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Canlı Konum Paylaşımı', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Partnerinizin harita üzerinde anlık konumunuzu görmesi', style: TextStyle(color: LoveraColors.textMuted)),
                  activeColor: LoveraColors.secondary,
                  value: _shareLiveLocation,
                  onChanged: (val) {
                    setState(() => _shareLiveLocation = val);
                    setModalState(() => _shareLiveLocation = val);
                  },
                ),
                Divider(color: theme.dividerColor),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Çevrimiçi Durumunu Göster', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Son görülme ve anlık aktiflik bilgisi', style: TextStyle(color: LoveraColors.textMuted)),
                  activeColor: LoveraColors.secondary,
                  value: _showOnlineStatus,
                  onChanged: (val) {
                    setState(() => _showOnlineStatus = val);
                    setModalState(() => _showOnlineStatus = val);
                  },
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: LoveraColors.secondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_rounded, color: LoveraColors.secondary, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Tüm verileriniz uçtan uca sadece sizin ve eşleştiğiniz partnerinizin erişimine açıktır.',
                          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // 3. Lovera Hakkında Penceresi
  void _openAboutDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: LoveraColors.primarySoft.withValues(alpha: 0.18),
                ),
                child: const Icon(Icons.favorite_rounded, color: LoveraColors.primary, size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                'Lovera',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Sürüm 1.0.0 (Beta)',
                style: TextStyle(color: LoveraColors.textMuted, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Text(
                'Çiftler için tasarlanmış sakin, samimi ve güvenli özel dijital alanınız. Birlikte geçirilen her anı ölümsüzleştirmek için sevgiyle geliştirildi.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: LoveraColors.textMuted, height: 1.45),
              ),
              const SizedBox(height: 20),
              const Divider(),
              Text(
                '© 2026 Lovera App • Tüm hakları saklıdır.',
                style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted, fontSize: 11),
              ),
            ],
          ),
          actions: [
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Tamam', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
          ],
        );
      },
    );
  }

  // 4. Görünüm ve Tema Seçimi
  void _openThemeSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final theme = Theme.of(context);
            final activeMode = ref.watch(themeModeProvider);

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Text(
                      'Görünüm ve Tema',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Uygulama temasını tercihinize göre ayarlayın',
                      style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted),
                    ),
                  ),
                  const SizedBox(height: 24),

                  _ThemeOptionTile(
                    icon: Icons.light_mode_rounded,
                    iconColor: const Color(0xFFF59E0B),
                    title: 'Açık Mod',
                    subtitle: 'Aydınlık ve ferah görünüm',
                    isSelected: activeMode == ThemeMode.light,
                    onTap: () {
                      ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light);
                      Navigator.pop(ctx);
                    },
                  ),
                  const SizedBox(height: 12),
                  _ThemeOptionTile(
                    icon: Icons.dark_mode_rounded,
                    iconColor: LoveraColors.primary,
                    title: 'Koyu Mod',
                    subtitle: 'Göz yormayan asil gece teması',
                    isSelected: activeMode == ThemeMode.dark,
                    onTap: () {
                      ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
                      Navigator.pop(ctx);
                    },
                  ),
                  const SizedBox(height: 12),
                  _ThemeOptionTile(
                    icon: Icons.settings_brightness_rounded,
                    iconColor: const Color(0xFF388AF6),
                    title: 'Sistem Varsayılanı',
                    subtitle: 'Telefonunuzun ayarlarına göre otomatik değişir',
                    isSelected: activeMode == ThemeMode.system,
                    onTap: () {
                      ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.system);
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userName = ref.watch(userNameProvider);
    final avatarPath = ref.watch(userAvatarProvider);
    final currentThemeMode = ref.watch(themeModeProvider);
    final auth = AuthService();
    final String themeModeLabel = currentThemeMode == ThemeMode.light
        ? 'Açık Mod'
        : (currentThemeMode == ThemeMode.dark ? 'Koyu Mod' : 'Sistem');
    final email = auth.currentUser?.email ?? 'Giriş yapılmadı';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // Profil Özeti Kartı - Tıklanabilir
          Material(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountSettingsView()),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  border: Border.all(color: theme.dividerColor),
                  boxShadow: AppTheme.ambientShadow,
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: LoveraColors.primarySoft.withValues(alpha: 0.18),
                      backgroundImage: avatarPath != null ? FileImage(File(avatarPath)) : null,
                      child: avatarPath == null
                          ? Text(
                              userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: LoveraColors.primary,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName.isNotEmpty ? userName : 'Lovera Kullanıcısı',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            email,
                            style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: LoveraColors.textMuted),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Uygulama Tercihleri Başlığı
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'UYGULAMA',
              style: theme.textTheme.labelMedium?.copyWith(
                color: LoveraColors.textMuted,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: theme.dividerColor),
              boxShadow: AppTheme.ambientShadow,
            ),
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.palette_outlined,
                  title: 'Görünüm ve Tema',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        themeModeLabel,
                        style: const TextStyle(
                          color: LoveraColors.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                    ],
                  ),
                  onTap: _openThemeSettings,
                ),
                Divider(height: 1, indent: 56, color: theme.dividerColor),
                _SettingsTile(
                  icon: Icons.notifications_none_rounded,
                  title: 'Bildirimler',
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: _openNotificationsSettings,
                ),
                Divider(height: 1, indent: 56, color: theme.dividerColor),
                _SettingsTile(
                  icon: Icons.shield_outlined,
                  title: 'Gizlilik ve Güvenlik',
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: _openPrivacySettings,
                ),
                Divider(height: 1, indent: 56, color: theme.dividerColor),
                _SettingsTile(
                  icon: Icons.info_outline_rounded,
                  title: 'Lovera Hakkında',
                  trailing: const Text('v1.0.0', style: TextStyle(color: LoveraColors.textMuted)),
                  onTap: _openAboutDialog,
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // Oturumu Kapat Butonu
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: theme.dividerColor),
              boxShadow: AppTheme.ambientShadow,
            ),
            child: _SettingsTile(
              icon: Icons.logout_rounded,
              title: 'Oturumu Kapat',
              titleColor: Colors.redAccent,
              iconColor: Colors.redAccent,
              onTap: () => _signOut(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.trailing,
    required this.onTap,
    this.titleColor,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback onTap;
  final Color? titleColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultColor = theme.colorScheme.onSurface;

    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: Icon(icon, color: iconColor ?? defaultColor),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: titleColor ?? defaultColor,
          ),
        ),
        trailing: trailing,
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radius)),
      ),
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? LoveraColors.primary.withValues(alpha: 0.08)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? LoveraColors.primary : theme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: isSelected ? LoveraColors.primary : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: LoveraColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: LoveraColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
              )
            else
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.dividerColor, width: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

