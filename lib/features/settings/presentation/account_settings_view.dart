import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/models.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../onboarding/presentation/onboarding_flow.dart';
import '../../../core/widgets/avatar_cache.dart';
import '../../../core/widgets/lovera_theme_background.dart';

class AccountSettingsView extends ConsumerStatefulWidget {
  const AccountSettingsView({super.key});

  @override
  ConsumerState<AccountSettingsView> createState() => _AccountSettingsViewState();
}

class _AccountSettingsViewState extends ConsumerState<AccountSettingsView> {
  final _picker = ImagePicker();
  bool _isDeleting = false;

  ImageProvider? _getAvatarProvider(String? path) {
    return AvatarCache.getProvider(path);
  }

  // Profil fotoğrafı seçme
  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 240,
      maxHeight: 240,
      imageQuality: 60,
    );

    if (picked != null) {
      try {
        final bytes = await picked.readAsBytes();
        final base64Str = 'data:image/jpeg;base64,${base64Encode(bytes)}';

        // State ve SharedPreferences güncelle
        ref.read(userAvatarProvider.notifier).state = base64Str;
        final prefs = await SharedPreferences.getInstance();
        final currentUid = DatabaseService().uid;
        if (currentUid != null) {
          await prefs.setString('avatar_$currentUid', base64Str);
        }

        // Firestore'a kalıcı olarak kaydet (hem partner görsün hem yeniden girince korunsun)
        await DatabaseService().updateAvatar(base64Str);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Profil fotoğrafınız güncellendi!'),
              backgroundColor: LoveraColors.secondary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Fotoğraf yüklenemedi: $e'),
              backgroundColor: LoveraColors.primary,
            ),
          );
        }
      }
    }
  }

  // İsim değiştirme diyaloğu
  void _editNameDialog(String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Kullanıcı Adını Değiştir'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Yeni kullanıcı adınız',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                ref.read(userNameProvider.notifier).state = newName;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('name', newName);

                try {
                  await FirebaseAuth.instance.currentUser?.updateDisplayName(newName);
                  await DatabaseService().updateUserName(newName);
                } catch (_) {}

                if (ctx.mounted) Navigator.pop(ctx);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Kullanıcı adınız başarıyla kaydedildi!'),
                      backgroundColor: LoveraColors.secondary,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  );
                }
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  // Doğum tarihi belirleme / değiştirme diyaloğu
  Future<void> _editBirthDateDialog(String? currentBirthDate) async {
    DateTime initial = DateTime(2000, 1, 1);
    if (currentBirthDate != null && currentBirthDate.isNotEmpty) {
      final parsed = DateTime.tryParse(currentBirthDate);
      if (parsed != null) initial = parsed;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      helpText: 'Doğum Tarihinizi Seçin',
      cancelText: 'Vazgeç',
      confirmText: 'Kaydet',
    );

    if (picked != null && mounted) {
      final bStr = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      final coupleId = ref.read(coupleIdProvider);
      final userName = ref.read(userNameProvider);

      await DatabaseService().updateBirthDate(
        bStr,
        coupleId: coupleId,
        userName: userName,
      );

      // CurrentUser provider güncelle
      final cur = ref.read(currentUserProvider);
      if (cur != null) {
        ref.read(currentUserProvider.notifier).state = AppUser(
          id: cur.id,
          name: cur.name,
          avatarUrl: cur.avatarUrl,
          batteryLevel: cur.batteryLevel,
          weather: cur.weather,
          city: cur.city,
          lat: cur.lat,
          lng: cur.lng,
          lastActive: cur.lastActive,
          coupleId: cur.coupleId,
          isAppOpen: cur.isAppOpen,
          birthDate: bStr,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Doğum tarihiniz başarıyla güncellendi! 🎉'),
            backgroundColor: LoveraColors.secondary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      }
    }
  }

  // Şifre değiştirme diyaloğu
  void _changePasswordDialog() {
    final currentPassword = TextEditingController();
    final newPassword = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text('Şifre Değiştir'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPassword,
                obscureText: obscureCurrent,
                decoration: InputDecoration(
                  hintText: 'Mevcut Şifre',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(obscureCurrent ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setDialogState(() => obscureCurrent = !obscureCurrent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPassword,
                obscureText: obscureNew,
                decoration: InputDecoration(
                  hintText: 'Yeni Şifre (En az 6 karakter)',
                  prefixIcon: const Icon(Icons.lock_reset_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () async {
                final curPass = currentPassword.text.trim();
                final newPass = newPassword.text.trim();

                if (curPass.isEmpty || newPass.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lütfen geçerli şifreler girin (en az 6 karakter).')),
                  );
                  return;
                }

                try {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user != null && user.email != null) {
                    final cred = EmailAuthProvider.credential(
                      email: user.email!,
                      password: curPass,
                    );
                    await user.reauthenticateWithCredential(cred);
                    await user.updatePassword(newPass);

                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Şifreniz başarıyla güncellendi!'),
                          backgroundColor: LoveraColors.secondary,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      );
                    }
                  }
                } on FirebaseAuthException catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.code == 'wrong-password' ? 'Mevcut şifreniz hatalı.' : 'Hata: ${e.message}'),
                      backgroundColor: LoveraColors.primary,
                    ),
                  );
                }
              },
              child: const Text('Güncelle'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userName = ref.watch(userNameProvider);
    final avatarPath = ref.watch(userAvatarProvider);
    final currentUser = ref.watch(currentUserProvider);
    final email = AuthService().currentUser?.email ?? 'Giriş yapılmadı';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hesap Bilgileri'),
        centerTitle: true,
      ),
      body: LoveraThemeBackground(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          children: [
          // Profil Fotoğrafı Alanı
          Center(
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: LoveraColors.primary.withValues(alpha: 0.45),
                      width: 3.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 54,
                    backgroundColor: LoveraColors.primarySoft.withValues(alpha: 0.2),
                    backgroundImage: _getAvatarProvider(avatarPath),
                    child: _getAvatarProvider(avatarPath) == null
                        ? Text(
                            userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: LoveraColors.primary,
                            ),
                          )
                        : null,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: LoveraColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: AppTheme.ambientShadow,
                      ),
                      child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Profil fotoğrafını değiştirmek için dokunun',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted),
          ),
          const SizedBox(height: 32),

          // Bilgi Kartları
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: theme.dividerColor),
              boxShadow: AppTheme.ambientShadow,
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.person_outline_rounded, color: theme.colorScheme.onSurface),
                  title: const Text('Kullanıcı Adı', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(userName.isNotEmpty ? userName : 'Belirtilmedi', style: const TextStyle(color: LoveraColors.textMuted)),
                  trailing: const Icon(Icons.edit_outlined, size: 20, color: LoveraColors.secondary),
                  onTap: () => _editNameDialog(userName),
                ),
                Divider(height: 1, indent: 56, color: theme.dividerColor),
                ListTile(
                  leading: Icon(Icons.cake_rounded, color: theme.colorScheme.onSurface),
                  title: const Text('Doğum Tarihi', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    currentUser?.birthDate != null && currentUser!.birthDate!.isNotEmpty
                        ? () {
                            final parts = currentUser.birthDate!.split('-');
                            if (parts.length == 3) {
                              return '${parts[2]}.${parts[1]}.${parts[0]}';
                            }
                            return currentUser.birthDate!;
                          }()
                        : 'Belirtilmedi',
                    style: const TextStyle(color: LoveraColors.textMuted),
                  ),
                  trailing: const Icon(Icons.edit_calendar_rounded, size: 20, color: LoveraColors.primary),
                  onTap: () => _editBirthDateDialog(currentUser?.birthDate),
                ),
                Divider(height: 1, indent: 56, color: theme.dividerColor),
                ListTile(
                  leading: Icon(Icons.email_outlined, color: theme.colorScheme.onSurface),
                  title: const Text('E-posta', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(email, style: const TextStyle(color: LoveraColors.textMuted)),
                ),
                Divider(height: 1, indent: 56, color: theme.dividerColor),
                ListTile(
                  leading: Icon(Icons.lock_reset_rounded, color: theme.colorScheme.onSurface),
                  title: const Text('Şifre Değiştir', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('••••••••', style: TextStyle(color: LoveraColors.textMuted)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: _changePasswordDialog,
                ),
                Divider(height: 1, indent: 56, color: theme.dividerColor),
                ListTile(
                  leading: const Icon(Icons.block_rounded, color: Colors.orangeAccent),
                  title: const Text('Engellenen Kullanıcılar', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Engellediğiniz kişileri yönetin', style: TextStyle(color: LoveraColors.textMuted)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: _showBlockedUsersSheet,
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),

          // Oturumu Kapat Alanı
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: theme.dividerColor),
              boxShadow: AppTheme.ambientShadow,
            ),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 22),
              ),
              title: const Text(
                'Oturumu Kapat',
                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.redAccent),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              onTap: _confirmSignOut,
            ),
          ),
          const SizedBox(height: 16),

          // Hesabı Sil Alanı
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              boxShadow: AppTheme.ambientShadow,
            ),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 22),
              ),
              title: const Text(
                'Hesabı Sil',
                style: TextStyle(fontWeight: FontWeight.w700, color: Colors.redAccent),
              ),
              subtitle: const Text(
                'Hesabınızı ve tüm verilerinizi kalıcı olarak silin',
                style: TextStyle(fontSize: 12, color: LoveraColors.textMuted),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.redAccent),
              onTap: _isDeleting ? null : _confirmDeleteAccount,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
  }

  // Engellenen Kullanıcıları Görme ve Engel Kaldırma Menüsü
  Future<void> _showBlockedUsersSheet() async {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF161820) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(
                  color: isDark ? LoveraColors.darkBorder : LoveraColors.lightBorder,
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.block_rounded, color: Colors.orangeAccent, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Engellenen Kullanıcılar',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? LoveraColors.darkText : LoveraColors.textDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: DatabaseService().getBlockedUsersProfiles(),
                        builder: (ctx, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final blockedList = snapshot.data ?? [];
                          if (blockedList.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_outline_rounded,
                                      size: 52, color: LoveraColors.secondary.withOpacity(0.7)),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Engellenen kimse yok',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                      color: isDark ? LoveraColors.darkText : LoveraColors.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Engellediğiniz kullanıcılar burada listelenir.',
                                    style: TextStyle(fontSize: 13, color: LoveraColors.textMuted),
                                  ),
                                ],
                              ),
                            );
                          }

                          return ListView.separated(
                            itemCount: blockedList.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: isDark ? LoveraColors.darkBorder : LoveraColors.lightBorder,
                            ),
                            itemBuilder: (ctx, i) {
                              final user = blockedList[i];
                              final uid = user['uid'] as String;
                              final name = user['name'] as String;
                              final avatar = user['avatarUrl'] as String?;

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                leading: CircleAvatar(
                                  radius: 22,
                                  backgroundColor: LoveraColors.primary.withOpacity(0.12),
                                  backgroundImage: _getAvatarProvider(avatar),
                                  child: avatar == null
                                      ? const Icon(Icons.person_rounded, color: LoveraColors.primary)
                                      : null,
                                ),
                                title: Text(
                                  name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? LoveraColors.darkText : LoveraColors.textDark,
                                  ),
                                ),
                                subtitle: const Text(
                                  'Engellendi',
                                  style: TextStyle(fontSize: 12, color: Colors.redAccent),
                                ),
                                trailing: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: LoveraColors.primary,
                                    side: const BorderSide(color: LoveraColors.primary),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  ),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (dCtx) => AlertDialog(
                                        title: const Text('Engeli Kaldır'),
                                        content: Text(
                                          '$name adlı kullanıcının engelini kaldırmak istediğinize emin misiniz? Tekrar size istek gönderebilir.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(dCtx, false),
                                            child: const Text('Vazgeç'),
                                          ),
                                          FilledButton(
                                            style: FilledButton.styleFrom(backgroundColor: LoveraColors.primary),
                                            onPressed: () => Navigator.pop(dCtx, true),
                                            child: const Text('Engeli Kaldır'),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirm == true) {
                                      await DatabaseService().unblockUser(uid);
                                      setSheetState(() {});
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('$name kullanıcısının engeli kaldırıldı.'),
                                            backgroundColor: LoveraColors.secondary,
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  child: const Text('Engeli Kaldır', style: TextStyle(fontWeight: FontWeight.w700)),
                                ),
                              );
                            },
                          );
                        },
                      ),
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

  // Oturumu Kapatma Akışı
  Future<void> _confirmSignOut() async {
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

    ref.read(userNameProvider.notifier).state = '';
    ref.read(userAvatarProvider.notifier).state = null;
    ref.read(currentUserProvider.notifier).state = null;
    ref.read(partnerProvider.notifier).state = null;
    ref.read(partnerUidProvider.notifier).state = null;
    ref.read(coupleIdProvider.notifier).state = null;
    ref.read(startDateProvider.notifier).state = null;
    ref.read(milestonesProvider.notifier).state = [];

    await AuthService().signOut(clearRemoteSession: true);

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingFlow()),
        (route) => false,
      );
    }
  }

  // Hesabı Silme Akışı
  Future<void> _confirmDeleteAccount() async {
    // 1. Emin misiniz uyarısı
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 10),
            Text('Hesabı Sil', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Text(
          'Emin misiniz? Hesabınız, fotoğraflarınız, özel günleriniz ve partner eşleşmeniz geri alınamaz şekilde kalıcı olarak silinecektir.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eminim, Sil'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final providerId = AuthService().getSignInProvider();
    String? password;

    // Eğer kullanıcı klasik e-posta/şifre ile giriş yaptıysa şifre sor.
    // Google veya Apple ile giriş yaptıysa şifre sormadan doğrudan devam et (Guideline 5.1.1(v) uyumlu).
    if (providerId == 'password') {
      final passwordController = TextEditingController();
      bool obscure = true;

      final shouldProceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: const Text('Güvenlik Doğrulaması', style: TextStyle(fontWeight: FontWeight.w800)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hesabınızı silmek için lütfen mevcut hesap şifrenizi girin:',
                  style: TextStyle(fontSize: 13, color: LoveraColors.textMuted),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    hintText: 'Şifreniz',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setDialogState(() => obscure = !obscure),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () {
                  if (passwordController.text.trim().isEmpty) return;
                  Navigator.pop(ctx, true);
                },
                child: const Text('Hesabı Kalıcı Olarak Sil'),
              ),
            ],
          ),
        ),
      );

      if (shouldProceed != true || !mounted) return;
      password = passwordController.text.trim();
      if (password.isEmpty) return;
    }

    setState(() => _isDeleting = true);

    try {
      // AuthService ile hesabı sil (Sosyal giriş veya şifre ile)
      await AuthService().deleteAccount(password: password);

      // Riverpod durumlarını sıfırla
      ref.read(userNameProvider.notifier).state = '';
      ref.read(userAvatarProvider.notifier).state = null;
      ref.read(currentUserProvider.notifier).state = null;
      ref.read(partnerProvider.notifier).state = null;
      ref.read(partnerUidProvider.notifier).state = null;
      ref.read(coupleIdProvider.notifier).state = null;
      ref.read(startDateProvider.notifier).state = null;
      ref.read(milestonesProvider.notifier).state = [];

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Hesabınız ve tüm verileriniz başarıyla silindi.'),
          backgroundColor: LoveraColors.secondary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );

      // Giriş / Onboarding sayfasına yönlendir
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingFlow()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      String msg = 'Hesap silinemedi: ${e.message}';
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        msg = 'Girdiğiniz şifre hatalı. Lütfen tekrar deneyin.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata oluştu: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
