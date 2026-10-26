import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/services/app_settings_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_palette.dart';
import '../../onboarding/presentation/onboarding_flow.dart';
import 'account_settings_view.dart';
import 'widget_settings_view.dart';
import '../../../core/widgets/app_lock_screen.dart';
import '../../../core/widgets/avatar_cache.dart';
import '../../../core/widgets/legal_document_view.dart';
import '../../../core/widgets/lovera_theme_background.dart';

class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  ImageProvider? _getAvatarProvider(String? path) {
    return AvatarCache.getProvider(path);
  }

  // Bildirim ayarları durumları
  bool _notifHeart = true;
  bool _notifChat = true;
  bool _notifDrawing = true;
  bool _notifBattery = true;
  bool _notifDistance = true;
  bool _notifMilestones = true;
  bool _notifGames = true;
  bool _notifMemories = true;

  // Gizlilik ve Güvenlik ayarları durumları
  bool _shareLiveLocation = true;
  bool _showOnlineStatus = true;
  bool _shareBattery = true;
  bool _shareSpeed = true;
  bool _sharePlaces = true;
  bool _appLockEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    _notifHeart = AppSettingsService.notifHeart;
    _notifChat = AppSettingsService.notifChat;
    _notifDrawing = AppSettingsService.notifDrawing;
    _notifBattery = AppSettingsService.notifBattery;
    _notifDistance = AppSettingsService.notifDistance;
    _notifMilestones = AppSettingsService.notifMilestones;
    _notifGames = AppSettingsService.notifGames;
    _notifMemories = AppSettingsService.notifMemories;

    _shareLiveLocation = AppSettingsService.shareLocation;
    _showOnlineStatus = AppSettingsService.showOnline;
    _shareBattery = AppSettingsService.shareBattery;
    _shareSpeed = AppSettingsService.shareSpeed;
    _sharePlaces = AppSettingsService.sharePlaces;
    _appLockEnabled = AppSettingsService.appLockEnabled;
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.signOutConfirmTitle),
        content: Text(s.signOutConfirmDesc),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: LoveraColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(100, 44),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.signOut),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    ref.read(userNameProvider.notifier).state = '';
    ref.read(userAvatarProvider.notifier).state = null;
    ref.read(currentUserProvider.notifier).state = null;
    ref.read(partnerProvider.notifier).state = null;
    ref.read(partnerUidProvider.notifier).state = null;
    ref.read(coupleIdProvider.notifier).state = null;
    ref.read(startDateProvider.notifier).state = null;
    ref.read(milestonesProvider.notifier).state = [];

    await AuthService().signOut(clearRemoteSession: true);

    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingFlow()),
        (route) => false,
      );
    }
  }

  Widget _buildSettingTile({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: isDark ? 0.2 : 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: value,
            activeColor: iconColor,
            activeTrackColor: iconColor.withValues(alpha: 0.4),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  // 1. Bildirimler Ekranı / BottomSheet (8 Fonksiyonel Ayar)
  void _openNotificationsSettings() {
    final s = ref.read(stringsProvider);
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
          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) => ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
              children: [
                Center(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: LoveraColors.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.notifications_active_rounded, color: LoveraColors.primary, size: 28),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        s.notifSettingsTitle,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        loc('Uygulamadan almak istediğiniz bildirimleri özelleştirin', 'Customize which alerts you want to receive'),
                        style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                // 1. Kalpler
                _buildSettingTile(
                  context: ctx,
                  icon: Icons.favorite_rounded,
                  iconColor: LoveraColors.primary,
                  title: s.notifHeartTitle,
                  subtitle: s.notifHeartSub,
                  value: _notifHeart,
                  onChanged: (val) async {
                    HapticFeedback.selectionClick();
                    await AppSettingsService.setNotificationSetting(AppSettingsService.keyNotifHeart, val);
                    setState(() => _notifHeart = val);
                    setModalState(() => _notifHeart = val);
                  },
                ),
                Divider(color: theme.dividerColor.withValues(alpha: 0.6), height: 16),

                // 2. Sohbet ve Mesajlar
                _buildSettingTile(
                  context: ctx,
                  icon: Icons.chat_bubble_rounded,
                  iconColor: const Color(0xFF3B82F6),
                  title: s.notifChatTitle,
                  subtitle: s.notifChatSub,
                  value: _notifChat,
                  onChanged: (val) async {
                    HapticFeedback.selectionClick();
                    await AppSettingsService.setNotificationSetting(AppSettingsService.keyNotifChat, val);
                    setState(() => _notifChat = val);
                    setModalState(() => _notifChat = val);
                  },
                ),
                Divider(color: theme.dividerColor.withValues(alpha: 0.6), height: 16),

                // 3. Canlı Çizim ve Notlar
                _buildSettingTile(
                  context: ctx,
                  icon: Icons.brush_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  title: s.notifDrawingTitle,
                  subtitle: s.notifDrawingSub,
                  value: _notifDrawing,
                  onChanged: (val) async {
                    HapticFeedback.selectionClick();
                    await AppSettingsService.setNotificationSetting(AppSettingsService.keyNotifDrawing, val);
                    setState(() => _notifDrawing = val);
                    setModalState(() => _notifDrawing = val);
                  },
                ),
                Divider(color: theme.dividerColor.withValues(alpha: 0.6), height: 16),

                // 4. Pil ve Şarj Uyarısı
                _buildSettingTile(
                  context: ctx,
                  icon: Icons.battery_alert_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  title: s.notifBatteryTitle,
                  subtitle: s.notifBatterySub,
                  value: _notifBattery,
                  onChanged: (val) async {
                    HapticFeedback.selectionClick();
                    await AppSettingsService.setNotificationSetting(AppSettingsService.keyNotifBattery, val);
                    setState(() => _notifBattery = val);
                    setModalState(() => _notifBattery = val);
                  },
                ),
                Divider(color: theme.dividerColor.withValues(alpha: 0.6), height: 16),

                // 5. Mesafe ve Yakınlaşma
                _buildSettingTile(
                  context: ctx,
                  icon: Icons.near_me_rounded,
                  iconColor: const Color(0xFF10B981),
                  title: s.notifDistanceTitle,
                  subtitle: s.notifDistanceSub,
                  value: _notifDistance,
                  onChanged: (val) async {
                    HapticFeedback.selectionClick();
                    await AppSettingsService.setNotificationSetting(AppSettingsService.keyNotifDistance, val);
                    setState(() => _notifDistance = val);
                    setModalState(() => _notifDistance = val);
                  },
                ),
                Divider(color: theme.dividerColor.withValues(alpha: 0.6), height: 16),

                // 6. Özel Gün Hatırlatıcıları
                _buildSettingTile(
                  context: ctx,
                  icon: Icons.celebration_rounded,
                  iconColor: const Color(0xFFF97316),
                  title: s.notifMilestoneTitle,
                  subtitle: s.notifMilestoneSub,
                  value: _notifMilestones,
                  onChanged: (val) async {
                    HapticFeedback.selectionClick();
                    await AppSettingsService.setNotificationSetting(AppSettingsService.keyNotifMilestones, val);
                    setState(() => _notifMilestones = val);
                    setModalState(() => _notifMilestones = val);
                  },
                ),
                Divider(color: theme.dividerColor.withValues(alpha: 0.6), height: 16),

                // 7. Oyun ve Etkinlik Davetleri
                _buildSettingTile(
                  context: ctx,
                  icon: Icons.sports_esports_rounded,
                  iconColor: const Color(0xFF6366F1),
                  title: s.notifGamesTitle,
                  subtitle: s.notifGamesSub,
                  value: _notifGames,
                  onChanged: (val) async {
                    HapticFeedback.selectionClick();
                    await AppSettingsService.setNotificationSetting(AppSettingsService.keyNotifGames, val);
                    setState(() => _notifGames = val);
                    setModalState(() => _notifGames = val);
                  },
                ),
                Divider(color: theme.dividerColor.withValues(alpha: 0.6), height: 16),

                // 8. Yeni Anı ve Fotoğraflar
                _buildSettingTile(
                  context: ctx,
                  icon: Icons.photo_library_rounded,
                  iconColor: const Color(0xFFEC4899),
                  title: s.notifMemoriesTitle,
                  subtitle: s.notifMemoriesSub,
                  value: _notifMemories,
                  onChanged: (val) async {
                    HapticFeedback.selectionClick();
                    await AppSettingsService.setNotificationSetting(AppSettingsService.keyNotifMemories, val);
                    setState(() => _notifMemories = val);
                    setModalState(() => _notifMemories = val);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // 2. Gizlilik ve Güvenlik Ekranı / BottomSheet (6 Fonksiyonel Ayar + PIN Kilidi)
  void _openPrivacySettings() {
    final s = ref.read(stringsProvider);
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
          final isDark = theme.brightness == Brightness.dark;

          return DraggableScrollableSheet(
            initialChildSize: 0.88,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) => ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
              children: [
                Center(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: LoveraColors.secondary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.shield_rounded, color: LoveraColors.secondary, size: 28),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        s.privacySettingsTitle,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        loc('Partnerinizle neleri paylaşmak istediğinizi yönetin', 'Manage what you want to share with your partner'),
                        style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                // 1. Canlı Konum Paylaşımı
                _buildSettingTile(
                  context: ctx,
                  icon: Icons.location_on_rounded,
                  iconColor: LoveraColors.primary,
                  title: s.privacyLocationTitle,
                  subtitle: s.privacyLocationSub,
                  value: _shareLiveLocation,
                  onChanged: (val) async {
                    HapticFeedback.selectionClick();
                    await AppSettingsService.setPrivacySetting(AppSettingsService.keyShareLocation, val);
                    if (!val) {
                      DatabaseService().updateStatus(lat: null, lng: null);
                    }
                    setState(() => _shareLiveLocation = val);
                    setModalState(() => _shareLiveLocation = val);
                  },
                ),
                Divider(color: theme.dividerColor.withValues(alpha: 0.6), height: 16),

                // 2. Çevrimiçi Durumunu Göster
                _buildSettingTile(
                  context: ctx,
                  icon: Icons.visibility_rounded,
                  iconColor: const Color(0xFF10B981),
                  title: s.privacyOnlineTitle,
                  subtitle: s.privacyOnlineSub,
                  value: _showOnlineStatus,
                  onChanged: (val) async {
                    HapticFeedback.selectionClick();
                    await AppSettingsService.setPrivacySetting(AppSettingsService.keyShowOnline, val);
                    DatabaseService().setAppPresence(val);
                    setState(() => _showOnlineStatus = val);
                    setModalState(() => _showOnlineStatus = val);
                  },
                ),
                Divider(color: theme.dividerColor.withValues(alpha: 0.6), height: 16),

                // 3. Pil Seviyesini Paylaş
                _buildSettingTile(
                  context: ctx,
                  icon: Icons.battery_charging_full_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  title: s.privacyBatteryTitle,
                  subtitle: s.privacyBatterySub,
                  value: _shareBattery,
                  onChanged: (val) async {
                    HapticFeedback.selectionClick();
                    await AppSettingsService.setPrivacySetting(AppSettingsService.keyShareBattery, val);
                    setState(() => _shareBattery = val);
                    setModalState(() => _shareBattery = val);
                  },
                ),
                Divider(color: theme.dividerColor.withValues(alpha: 0.6), height: 16),

                // 4. Hız ve Hareket Durumunu Paylaş
                _buildSettingTile(
                  context: ctx,
                  icon: Icons.speed_rounded,
                  iconColor: const Color(0xFF3B82F6),
                  title: s.privacySpeedTitle,
                  subtitle: s.privacySpeedSub,
                  value: _shareSpeed,
                  onChanged: (val) async {
                    HapticFeedback.selectionClick();
                    await AppSettingsService.setPrivacySetting(AppSettingsService.keyShareSpeed, val);
                    setState(() => _shareSpeed = val);
                    setModalState(() => _shareSpeed = val);
                  },
                ),
                Divider(color: theme.dividerColor.withValues(alpha: 0.6), height: 16),

                // 5. Özel Mekan İsimlerini Paylaş
                _buildSettingTile(
                  context: ctx,
                  icon: Icons.place_rounded,
                  iconColor: const Color(0xFF06B6D4),
                  title: s.privacyPlacesTitle,
                  subtitle: s.privacyPlacesSub,
                  value: _sharePlaces,
                  onChanged: (val) async {
                    HapticFeedback.selectionClick();
                    await AppSettingsService.setPrivacySetting(AppSettingsService.keySharePlaces, val);
                    setState(() => _sharePlaces = val);
                    setModalState(() => _sharePlaces = val);
                  },
                ),
                Divider(color: theme.dividerColor.withValues(alpha: 0.6), height: 16),

                // 6. Uygulama Kilidi (4 Haneli PIN)
                _buildSettingTile(
                  context: ctx,
                  icon: Icons.lock_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  title: s.privacyAppLockTitle,
                  subtitle: s.privacyAppLockSub,
                  value: _appLockEnabled,
                  onChanged: (val) async {
                    if (val) {
                      // PIN oluşturma ekranını aç
                      final success = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => const AppLockScreen(
                            mode: AppLockMode.create,
                            isDismissible: true,
                          ),
                        ),
                      );
                      if (success == true) {
                        setState(() => _appLockEnabled = true);
                        setModalState(() => _appLockEnabled = true);
                      }
                    } else {
                      // PIN kilidini kaldır
                      await AppSettingsService.disableAppLock();
                      setState(() => _appLockEnabled = false);
                      setModalState(() => _appLockEnabled = false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(s.pinDisabledSuccess),
                            backgroundColor: LoveraColors.primary,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    }
                  },
                ),

                // PIN Kodunu Değiştir Butonu (Kilit aktifse gösterilir)
                if (_appLockEnabled) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 56),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF8B5CF6),
                        side: const BorderSide(color: Color(0xFF8B5CF6)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      icon: const Icon(Icons.password_rounded, size: 18),
                      label: Text(s.privacyChangePinTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
                      onPressed: () {
                        Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => const AppLockScreen(
                              mode: AppLockMode.change,
                              isDismissible: true,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Uçtan uca güvenlik ve gizlilik bildirimi
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.06) : LoveraColors.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: LoveraColors.secondary.withValues(alpha: isDark ? 0.2 : 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.verified_user_rounded, color: LoveraColors.secondary, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          s.privacyNotice,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
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
    final s = ref.read(stringsProvider);
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
                child: Icon(Icons.favorite_rounded, color: LoveraColors.primary, size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                'Lovera',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                s.aboutVersion,
                style: TextStyle(color: LoveraColors.textMuted, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Text(
                s.aboutDesc,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: LoveraColors.textMuted, height: 1.45),
              ),
              const SizedBox(height: 20),
              const Divider(),
              Text(
                s.copyrightNotice,
                style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted, fontSize: 11),
              ),
            ],
          ),
          actions: [
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(s.ok, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
          ],
        );
      },
    );
  }

  // Dil Seçimi BottomSheet
  void _openLanguageSettings() {
    final s = ref.read(stringsProvider);
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
            final currentLang = ref.watch(appLanguageProvider);

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Text(
                      s.selectLanguage,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      s.languageSubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted),
                    ),
                  ),
                  const SizedBox(height: 24),

                  _ThemeOptionTile(
                    icon: Icons.language_rounded,
                    iconColor: const Color(0xFFE11D48),
                    title: loc('Türkçe', 'Turkish'),
                    subtitle: loc('Türkçe (TR)', 'Turkish (TR)'),
                    isSelected: currentLang == AppLanguage.tr,
                    onTap: () {
                      ref.read(appLanguageProvider.notifier).setLanguage(AppLanguage.tr);
                      Navigator.pop(ctx);
                    },
                  ),
                  const SizedBox(height: 12),
                  _ThemeOptionTile(
                    icon: Icons.language_rounded,
                    iconColor: const Color(0xFF2563EB),
                    title: 'English',
                    subtitle: 'English (US/UK)',
                    isSelected: currentLang == AppLanguage.en,
                    onTap: () {
                      ref.read(appLanguageProvider.notifier).setLanguage(AppLanguage.en);
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

  // 4. Görünüm ve Tema Seçimi
  void _openThemeSettings() {
    final s = ref.read(stringsProvider);
    final isEn = ref.read(appLanguageProvider) == AppLanguage.en;
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
            final activePalette = ref.watch(themePaletteProvider);

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        s.themeAndAppearance,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        s.themeSubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Mod Seçenekleri (Açık / Koyu / Sistem)
                    Row(
                      children: [
                        Expanded(
                          child: _ThemeModePill(
                            icon: Icons.light_mode_rounded,
                            iconColor: const Color(0xFFF59E0B),
                            title: s.themeLight,
                            isSelected: activeMode == ThemeMode.light,
                            onTap: () {
                              ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ThemeModePill(
                            icon: Icons.dark_mode_rounded,
                            iconColor: activePalette.primary,
                            title: s.themeDark,
                            isSelected: activeMode == ThemeMode.dark,
                            onTap: () {
                              ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ThemeModePill(
                            icon: Icons.settings_brightness_rounded,
                            iconColor: const Color(0xFF388AF6),
                            title: s.themeSystem,
                            isSelected: activeMode == ThemeMode.system,
                            onTap: () {
                              ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.system);
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    Divider(color: theme.dividerColor, height: 1),
                    const SizedBox(height: 18),

                    // Çift Renkli Tema Paketleri
                    Text(
                      s.colorPalettesTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.colorPalettesSubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted),
                    ),
                    const SizedBox(height: 16),

                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: ThemePaletteData.all.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final palette = ThemePaletteData.all[index];
                        final isSelected = activePalette.id == palette.id;
                        return _PaletteOptionTile(
                          palette: palette,
                          isSelected: isSelected,
                          isEn: isEn,
                          onTap: () {
                            ref.read(themePaletteProvider.notifier).setPalette(palette.id);
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final theme = Theme.of(context);
    final userName = ref.watch(userNameProvider);
    final avatarPath = ref.watch(userAvatarProvider);
    final currentThemeMode = ref.watch(themeModeProvider);
    final currentPalette = ref.watch(themePaletteProvider);
    final currentLang = ref.watch(appLanguageProvider);
    final isEn = currentLang == AppLanguage.en;
    final auth = AuthService();
    final String themeModeLabel = currentThemeMode == ThemeMode.light
        ? s.themeLight
        : (currentThemeMode == ThemeMode.dark ? s.themeDark : s.themeSystem);
    final String languageLabel = isEn ? 'English' : loc('Türkçe', 'Turkish');
    final email = auth.currentUser?.email ?? s.notLoggedIn;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.settingsTitle),
        centerTitle: true,
      ),
      body: LoveraThemeBackground(
        child: ListView(
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
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: LoveraColors.primary.withValues(alpha: 0.4),
                          width: 2.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 32,
                        backgroundColor: LoveraColors.primarySoft.withValues(alpha: 0.18),
                        backgroundImage: _getAvatarProvider(avatarPath),
                        child: _getAvatarProvider(avatarPath) == null
                            ? Text(
                                userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: LoveraColors.primary,
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            () {
                              final user = ref.watch(currentUserProvider);
                              if (user?.firstName != null && user!.firstName!.trim().isNotEmpty) {
                                return user.firstName!.trim();
                              }
                              if (userName.isNotEmpty) {
                                final parts = userName.trim().split(' ');
                                if (parts.length > 2) {
                                  return parts.sublist(0, parts.length - 1).join(' ');
                                } else if (parts.length == 2) {
                                  return parts.first;
                                }
                                return userName;
                              }
                              return s.defaultUser;
                            }(),
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
                    Icon(Icons.arrow_forward_ios_rounded, size: 16, color: LoveraColors.textMuted),
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
              s.appSection,
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
                  icon: Icons.language_rounded,
                  title: s.languageOption,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        languageLabel,
                        style: TextStyle(
                          color: LoveraColors.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                    ],
                  ),
                  onTap: _openLanguageSettings,
                ),
                Divider(height: 1, indent: 56, color: theme.dividerColor),
                _SettingsTile(
                  icon: Icons.palette_outlined,
                  title: s.themeAndAppearance,
                  subtitle: '$themeModeLabel · ${currentPalette.name(isEn)}',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: currentPalette.gradient,
                          border: Border.all(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
                            width: 1,
                          ),
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
                  icon: Icons.widgets_outlined,
                  title: s.widgetSettings,
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WidgetSettingsView()),
                    );
                  },
                ),
                Divider(height: 1, indent: 56, color: theme.dividerColor),
                _SettingsTile(
                  icon: Icons.notifications_none_rounded,
                  title: s.notifications,
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: _openNotificationsSettings,
                ),
                Divider(height: 1, indent: 56, color: theme.dividerColor),
                _SettingsTile(
                  icon: Icons.shield_outlined,
                  title: s.privacySecurity,
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: _openPrivacySettings,
                ),
                Divider(height: 1, indent: 56, color: theme.dividerColor),
                _SettingsTile(
                  icon: Icons.description_outlined,
                  title: s.termsOfUse,
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LegalDocumentView(type: LegalDocType.termsOfUse),
                      ),
                    );
                  },
                ),
                Divider(height: 1, indent: 56, color: theme.dividerColor),
                _SettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  title: s.privacyPolicy,
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LegalDocumentView(type: LegalDocType.privacyPolicy),
                      ),
                    );
                  },
                ),
                Divider(height: 1, indent: 56, color: theme.dividerColor),
                _SettingsTile(
                  icon: Icons.info_outline_rounded,
                  title: s.aboutLovera,
                  trailing: Text('v1.0.0', style: TextStyle(color: LoveraColors.textMuted)),
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
              title: s.signOut,
              titleColor: Colors.redAccent,
              iconColor: Colors.redAccent,
              onTap: () => _signOut(context, ref),
            ),
          ),
        ],
      ),
    ),
  );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
    this.titleColor,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: titleColor ?? defaultColor,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: LoveraColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              )
            : null,
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
                    style: TextStyle(
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
                decoration: BoxDecoration(
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

class _ThemeModePill extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeModePill({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? iconColor.withValues(alpha: isDark ? 0.18 : 0.1)
                : (isDark ? theme.colorScheme.surface : LoveraColors.lightBg),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? iconColor : (isDark ? theme.dividerColor : LoveraColors.lightBorder),
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? iconColor : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaletteOptionTile extends StatelessWidget {
  final ThemePaletteData palette;
  final bool isSelected;
  final bool isEn;
  final VoidCallback onTap;

  const _PaletteOptionTile({
    required this.palette,
    required this.isSelected,
    required this.isEn,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? palette.primary.withValues(alpha: isDark ? 0.16 : 0.08)
                : (isDark ? theme.colorScheme.surface : LoveraColors.lightBg),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected
                  ? palette.primary
                  : (isDark ? theme.dividerColor : LoveraColors.lightBorder),
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Row(
            children: [
              // İkili renk rozeti: yarısı primary, yarısı secondary
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: palette.gradient,
                  boxShadow: [
                    BoxShadow(
                      color: palette.primary.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            palette.name(isEn),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isSelected ? palette.primary : null,
                            ),
                          ),
                        ),
                        if (palette.id == ThemePalette.classic) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: palette.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isEn ? 'DEFAULT' : 'ANA TEMA',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: palette.primary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      palette.description(isEn),
                      style: TextStyle(
                        fontSize: 12,
                        color: LoveraColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isSelected)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: palette.primary,
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
      ),
    );
  }
}


