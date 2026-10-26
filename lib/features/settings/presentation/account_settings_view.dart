import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/models/models.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../common/presentation/widgets/background_source_selection_sheet.dart';
import '../../common/presentation/widgets/memory_background_picker_sheet.dart';
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

  // Profil fotoğrafını kaydet ve senkronize et
  Future<void> _saveAvatar(String base64Str) async {
    try {
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
            content: Text(loc('Profil fotoğrafınız güncellendi!', 'Profile photo updated!')),
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
            content: Text(loc('Fotoğraf yüklenemedi: $e', 'Could not upload photo: $e')),
            backgroundColor: LoveraColors.primary,
          ),
        );
      }
    }
  }

  // Cihazdan fotoğraf seçme
  Future<void> _pickImageFromDevice() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 240,
        maxHeight: 240,
        imageQuality: 60,
      );

      if (picked != null) {
        final bytes = await picked.readAsBytes();
        final base64Str = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        await _saveAvatar(base64Str);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc('Fotoğraf seçilemedi: $e', 'Could not select photo: $e')),
            backgroundColor: LoveraColors.primary,
          ),
        );
      }
    }
  }

  // Ortak anı albümünden fotoğraf seçme
  void _pickImageFromMemoryAlbum() {
    final coupleId = ref.read(coupleIdProvider) ?? '';
    if (coupleId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc('Anı albümünden seçmek için önce partnerinizle eşleşmelisiniz.', 'You must pair with your partner first to choose from memories.')),
          backgroundColor: LoveraColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (mCtx) => MemoryBackgroundPickerSheet(
        coupleId: coupleId,
        target: 'profile',
        onSingleImageSelected: (base64Str) async {
          await _saveAvatar(base64Str);
        },
      ),
    );
  }

  // Profil fotoğrafı kaynağını seçme (Albüm veya Cihaz)
  void _showImageSourcePicker() {
    HapticFeedback.lightImpact();
    BackgroundSourceSelectionSheet.show(
      context: context,
      title: loc('Profil Fotoğrafı Seç', 'Select Profile Photo'),
      onSelectDevice: _pickImageFromDevice,
      onSelectMemoryAlbum: _pickImageFromMemoryAlbum,
      memoryAlbumSubtitle: loc('Birlikte yüklediğiniz anı fotoğraflarından birini seçin', 'Choose from memories you shared together'),
    );
  }

  // İsim ve Soyisim değiştirme diyaloğu
  void _editNameDialog(String currentFullName) async {
    final curUser = ref.read(currentUserProvider);
    final prefs = await SharedPreferences.getInstance();

    String initialFirstName = curUser?.firstName ?? prefs.getString('firstName') ?? '';
    String initialLastName = curUser?.lastName ?? prefs.getString('lastName') ?? '';

    // Eğer daha önce ayrık kaydedilmemişse fallback olarak parçala
    if (initialFirstName.isEmpty && initialLastName.isEmpty) {
      final parts = currentFullName.trim().split(RegExp(r'\s+'));
      if (parts.isNotEmpty) {
        if (parts.length > 1) {
          initialLastName = parts.last;
          initialFirstName = parts.sublist(0, parts.length - 1).join(' ');
        } else {
          initialFirstName = parts.first;
        }
      }
    }

    if (!mounted) return;

    final firstNameController = TextEditingController(text: initialFirstName);
    final lastNameController = TextEditingController(text: initialLastName);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(loc('Ad ve Soyadı Düzenle', 'Edit Name & Surname')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: firstNameController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: loc('Adınız', 'First Name'),
                hintText: loc('Örn: Ali İhsan', 'e.g. Ali Ihsan'),
                prefixIcon: const Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: lastNameController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: loc('Soyadınız', 'Last Name'),
                hintText: loc('Örn: Aküzüm', 'e.g. Akuzum'),
                prefixIcon: const Icon(Icons.badge_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc('Vazgeç', 'Cancel')),
          ),
          FilledButton(
            onPressed: () async {
              final fName = firstNameController.text.trim();
              final lName = lastNameController.text.trim();
              final newName = lName.isNotEmpty ? '$fName $lName' : fName;

              if (fName.isNotEmpty) {
                ref.read(userNameProvider.notifier).state = newName;
                final p = await SharedPreferences.getInstance();
                await p.setString('name', newName);
                await p.setString('firstName', fName);
                await p.setString('lastName', lName);

                try {
                  await FirebaseAuth.instance.currentUser?.updateDisplayName(newName);
                  await DatabaseService().updateUserName(
                    newName,
                    firstName: fName,
                    lastName: lName,
                  );
                } catch (_) {}

                // CurrentUser provider güncelle
                final cur = ref.read(currentUserProvider);
                if (cur != null) {
                  ref.read(currentUserProvider.notifier).state = AppUser(
                    id: cur.id,
                    name: newName,
                    avatarUrl: cur.avatarUrl,
                    batteryLevel: cur.batteryLevel,
                    weather: cur.weather,
                    city: cur.city,
                    lat: cur.lat,
                    lng: cur.lng,
                    lastActive: cur.lastActive,
                    coupleId: cur.coupleId,
                    isAppOpen: cur.isAppOpen,
                    birthDate: cur.birthDate,
                    hometown: cur.hometown,
                    firstName: fName,
                    lastName: lName,
                  );
                }

                if (ctx.mounted) Navigator.pop(ctx);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(loc('Adınız ve soyadınız başarıyla güncellendi!', 'Name and surname updated successfully!')),
                      backgroundColor: LoveraColors.secondary,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  );
                }
              }
            },
            child: Text(loc('Kaydet', 'Save')),
          ),
        ],
      ),
    );
  }

  // Memleket değiştirme diyaloğu
  void _editHometownDialog(String? currentHometown) {
    final controller = TextEditingController(text: currentHometown ?? '');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(loc('Memleketi Düzenle', 'Edit Hometown')),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: loc('Nerelisin? (Memleket)', 'Where are you from? (Hometown)'),
            hintText: loc('Örn: İzmir, İstanbul...', 'e.g. Izmir, Istanbul...'),
            prefixIcon: const Icon(Icons.location_city_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc('Vazgeç', 'Cancel')),
          ),
          FilledButton(
            onPressed: () async {
              final newTown = controller.text.trim();
              if (newTown.isNotEmpty) {
                await DatabaseService().updateHometown(newTown);

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
                    birthDate: cur.birthDate,
                    hometown: newTown,
                    firstName: cur.firstName,
                    lastName: cur.lastName,
                  );
                }

                if (ctx.mounted) Navigator.pop(ctx);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(loc('Memleketiniz başarıyla güncellendi!', 'Hometown updated successfully!')),
                      backgroundColor: LoveraColors.secondary,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  );
                }
              }
            },
            child: Text(loc('Kaydet', 'Save')),
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
      helpText: loc('Doğum Tarihinizi Seçin', 'Select Date of Birth'),
      cancelText: loc('Vazgeç', 'Cancel'),
      confirmText: loc('Kaydet', 'Save'),
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
          hometown: cur.hometown,
          firstName: cur.firstName,
          lastName: cur.lastName,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc('Doğum tarihiniz başarıyla güncellendi! 🎉', 'Date of birth updated successfully! 🎉')),
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
          title: Text(loc('Şifre Değiştir', 'Change Password')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPassword,
                obscureText: obscureCurrent,
                decoration: InputDecoration(
                  hintText: loc('Mevcut Şifre', 'Current Password'),
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
                  hintText: loc('Yeni Şifre (En az 6 karakter)', 'New Password (At least 6 characters)'),
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
              child: Text(loc('Vazgeç', 'Cancel')),
            ),
            FilledButton(
              onPressed: () async {
                final curPass = currentPassword.text.trim();
                final newPass = newPassword.text.trim();

                if (curPass.isEmpty || newPass.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(loc('Lütfen geçerli şifreler girin (en az 6 karakter).', 'Please enter valid passwords (at least 6 characters).'))),
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
                          content: Text(loc('Şifreniz başarıyla güncellendi!', 'Password updated successfully!')),
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
                      content: Text(e.code == 'wrong-password' ? loc('Mevcut şifreniz hatalı.', 'Current password incorrect.') : loc('Hata: ${e.message}', 'Error: ${e.message}')),
                      backgroundColor: LoveraColors.primary,
                    ),
                  );
                }
              },
              child: Text(loc('Güncelle', 'Update')),
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
    final email = AuthService().currentUser?.email ?? loc('Giriş yapılmadı', 'Not logged in');

    return Scaffold(
      appBar: AppBar(
        title: Text(loc('Hesap Bilgileri', 'Account Information')),
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
                GestureDetector(
                  onTap: _showImageSourcePicker,
                  child: Container(
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
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _showImageSourcePicker,
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
            loc('Profil fotoğrafını değiştirmek için dokunun', 'Tap to change profile photo'),
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
                  leading: Icon(Icons.badge_outlined, color: theme.colorScheme.onSurface),
                  title: Text(loc('Ad Soyad', 'Full Name'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(userName.isNotEmpty ? userName : loc('Belirtilmedi', 'Not specified'), style: TextStyle(color: LoveraColors.textMuted)),
                  trailing: Icon(Icons.edit_outlined, size: 20, color: LoveraColors.secondary),
                  onTap: () => _editNameDialog(userName),
                ),
                Divider(height: 1, indent: 56, color: theme.dividerColor),
                ListTile(
                  leading: Icon(Icons.location_city_rounded, color: theme.colorScheme.onSurface),
                  title: Text(loc('Memleket', 'Hometown'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    currentUser?.hometown != null && currentUser!.hometown!.isNotEmpty
                        ? currentUser.hometown!
                        : loc('Belirtilmedi', 'Not specified'),
                    style: TextStyle(color: LoveraColors.textMuted),
                  ),
                  trailing: Icon(Icons.edit_outlined, size: 20, color: LoveraColors.secondary),
                  onTap: () => _editHometownDialog(currentUser?.hometown),
                ),
                Divider(height: 1, indent: 56, color: theme.dividerColor),
                ListTile(
                  leading: Icon(Icons.cake_rounded, color: theme.colorScheme.onSurface),
                  title: Text(loc('Doğum Tarihi', 'Date of Birth'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    currentUser?.birthDate != null && currentUser!.birthDate!.isNotEmpty
                        ? () {
                            final parts = currentUser.birthDate!.split('-');
                            if (parts.length == 3) {
                              return '${parts[2]}.${parts[1]}.${parts[0]}';
                            }
                            return currentUser.birthDate!;
                          }()
                        : loc('Belirtilmedi', 'Not specified'),
                    style: TextStyle(color: LoveraColors.textMuted),
                  ),
                  trailing: Icon(Icons.edit_calendar_rounded, size: 20, color: LoveraColors.primary),
                  onTap: () => _editBirthDateDialog(currentUser?.birthDate),
                ),
                Divider(height: 1, indent: 56, color: theme.dividerColor),
                ListTile(
                  leading: Icon(Icons.email_outlined, color: theme.colorScheme.onSurface),
                  title: Text(loc('E-posta', 'Email'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(email, style: TextStyle(color: LoveraColors.textMuted)),
                ),
                Divider(height: 1, indent: 56, color: theme.dividerColor),
                ListTile(
                  leading: Icon(Icons.lock_reset_rounded, color: theme.colorScheme.onSurface),
                  title: Text(loc('Şifre Değiştir', 'Change Password'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('••••••••', style: TextStyle(color: LoveraColors.textMuted)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: _changePasswordDialog,
                ),
                Divider(height: 1, indent: 56, color: theme.dividerColor),
                ListTile(
                  leading: const Icon(Icons.block_rounded, color: Colors.orangeAccent),
                  title: Text(loc('Engellenen Kullanıcılar', 'Blocked Users'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(loc('Engellediğiniz kişileri yönetin', 'Manage people you blocked'), style: TextStyle(color: LoveraColors.textMuted)),
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
              title: Text(
                loc('Oturumu Kapat', 'Log Out'),
                style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.redAccent),
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
              title: Text(
                loc('Hesabı Sil', 'Delete Account'),
                style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.redAccent),
              ),
              subtitle: Text(
                loc('Hesabınızı ve tüm verilerinizi kalıcı olarak silin', 'Permanently delete your account and all data'),
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
                          loc('Engellenen Kullanıcılar', 'Blocked Users'),
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
                                    loc('Engellenen kimse yok', 'No blocked users'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                      color: isDark ? LoveraColors.darkText : LoveraColors.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    loc('Engellediğiniz kullanıcılar burada listelenir.', 'Users you blocked will be listed here.'),
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
                                      ? Icon(Icons.person_rounded, color: LoveraColors.primary)
                                      : null,
                                ),
                                title: Text(
                                  name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? LoveraColors.darkText : LoveraColors.textDark,
                                  ),
                                ),
                                subtitle: Text(
                                  loc('Engellendi', 'Blocked'),
                                  style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                                ),
                                trailing: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: LoveraColors.primary,
                                    side: BorderSide(color: LoveraColors.primary),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  ),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (dCtx) => AlertDialog(
                                        title: Text(loc('Engeli Kaldır', 'Unblock')),
                                        content: Text(
                                          loc(
                                            '$name adlı kullanıcının engelini kaldırmak istediğinize emin misiniz? Tekrar size istek gönderebilir.',
                                            'Are you sure you want to unblock $name? They will be able to send you requests again.',
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(dCtx, false),
                                            child: Text(loc('Vazgeç', 'Cancel')),
                                          ),
                                          FilledButton(
                                            style: FilledButton.styleFrom(backgroundColor: LoveraColors.primary),
                                            onPressed: () => Navigator.pop(dCtx, true),
                                            child: Text(loc('Engeli Kaldır', 'Unblock')),
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
                                            content: Text(loc('$name kullanıcısının engeli kaldırıldı.', '$name was unblocked.')),
                                            backgroundColor: LoveraColors.secondary,
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  child: Text(loc('Engeli Kaldır', 'Unblock'), style: const TextStyle(fontWeight: FontWeight.w700)),
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
        title: Text(loc('Oturumu Kapat', 'Log Out')),
        content: Text(loc('Hesabınızdan çıkış yapmak istediğinize emin misiniz?', 'Are you sure you want to log out of your account?')),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc('Vazgeç', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: LoveraColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(100, 44),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc('Çıkış Yap', 'Log Out')),
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
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            const SizedBox(width: 10),
            Text(loc('Hesabı Sil', 'Delete Account'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text(
          loc(
            'Emin misiniz? Hesabınız, fotoğraflarınız, özel günleriniz ve partner eşleşmeniz geri alınamaz şekilde kalıcı olarak silinecektir.',
            'Are you sure? Your account, photos, milestones, and partner connection will be permanently deleted and cannot be undone.',
          ),
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc('Vazgeç', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc('Eminim, Sil', 'Yes, Delete')),
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
            title: Text(loc('Güvenlik Doğrulaması', 'Security Verification'), style: const TextStyle(fontWeight: FontWeight.w800)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc('Hesabınızı silmek için lütfen mevcut hesap şifrenizi girin:', 'Please enter your current account password to delete your account:'),
                  style: TextStyle(fontSize: 13, color: LoveraColors.textMuted),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    hintText: loc('Şifreniz', 'Your password'),
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
                child: Text(loc('Vazgeç', 'Cancel')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () {
                  if (passwordController.text.trim().isEmpty) return;
                  Navigator.pop(ctx, true);
                },
                child: Text(loc('Hesabı Kalıcı Olarak Sil', 'Permanently Delete Account')),
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
          content: Text(loc('Hesabınız ve tüm verileriniz başarıyla silindi.', 'Your account and all data have been deleted successfully.')),
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
      String msg = loc('Hesap silinemedi: ${e.message}', 'Could not delete account: ${e.message}');
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        msg = loc('Girdiğiniz şifre hatalı. Lütfen tekrar deneyin.', 'Password is incorrect. Please try again.');
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
          content: Text(loc('Hata oluştu: $e', 'An error occurred: $e')),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
