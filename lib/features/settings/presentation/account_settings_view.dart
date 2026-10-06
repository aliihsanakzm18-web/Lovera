import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';

class AccountSettingsView extends ConsumerStatefulWidget {
  const AccountSettingsView({super.key});

  @override
  ConsumerState<AccountSettingsView> createState() => _AccountSettingsViewState();
}

class _AccountSettingsViewState extends ConsumerState<AccountSettingsView> {
  final _picker = ImagePicker();

  // Profil fotoğrafı seçme
  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 85,
    );

    if (picked != null) {
      ref.read(userAvatarProvider.notifier).state = picked.path;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('avatar_path', picked.path);

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
    final email = AuthService().currentUser?.email ?? 'Giriş yapılmadı';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hesap Bilgileri'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        children: [
          // Profil Fotoğrafı Alanı
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 54,
                  backgroundColor: LoveraColors.primarySoft.withValues(alpha: 0.2),
                  backgroundImage: avatarPath != null ? FileImage(File(avatarPath)) : null,
                  child: avatarPath == null
                      ? Text(
                          userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: LoveraColors.primary,
                          ),
                        )
                      : null,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
