import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';

class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key, required this.onFinish, required this.onBack});
  final VoidCallback onFinish;
  final VoidCallback onBack;

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> with WidgetsBindingObserver {
  final Map<Permission, bool> _granted = {
    Permission.locationAlways: false,
    Permission.notification: false,
  };
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final locWhenInUse = await Permission.locationWhenInUse.isGranted;
    final locAlways = await Permission.locationAlways.isGranted;
    final notif = await Permission.notification.isGranted;

    if (mounted) {
      final locOk = locAlways || locWhenInUse;
      setState(() {
        _granted[Permission.locationAlways] = locOk;
        _granted[Permission.notification] = notif;
        _checking = false;
      });

      // Eğer tüm gerekli izinler verilmişse kullanıcıyı bekletmeden doğrudan devam et
      if (locOk && notif) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            widget.onFinish();
          }
        });
      }
    }
  }

  Future<void> _request(Permission p) async {
    // Android/iOS: Arka plan izni için önce ön plan, ardından her zaman izin istenir
    if (p == Permission.locationAlways) {
      // Google Play "Prominent Disclosure" ve Apple 5.1.1: sistem izin penceresinden ÖNCE
      // arka plan konum kullanımının açıkça anlatılması ve kullanıcının onayı gerekir.
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(loc('Arka plan konum erişimi', 'Background location access')),
          content: Text(
            loc(
              'Lovera, uygulama kapalıyken veya kullanımda değilken bile konumunu ve '
              'pil seviyeni yalnızca eşleştiğin partnerinle paylaşmak için konum verini toplar.\n\n'
              'Bu veri reklam için kullanılmaz, üçüncü kişilerle paylaşılmaz. '
              'Paylaşımı istediğin zaman Ayarlar\'dan kapatabilir veya hesabını silebilirsin.',
              'Lovera collects location data to share your live location and battery level '
              'only with your paired partner even when the app is closed or not in use.\n\n'
              'This data is never used for advertising or shared with third parties. '
              'You can disable location sharing in Settings or delete your account at any time.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(loc('Şimdi değil', 'Not now')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(loc('Kabul ediyorum', 'I agree')),
            ),
          ],
        ),
      );
      if (accepted != true) return;
      final whenInUse = await Permission.locationWhenInUse.request();
      if (whenInUse.isGranted) {
        final status = await Permission.locationAlways.request();
        final locOk = status.isGranted || whenInUse.isGranted;
        if (mounted) {
          setState(() => _granted[p] = locOk);
          if (locOk && (_granted[Permission.notification] ?? false)) {
            widget.onFinish();
          }
        }
        return;
      } else if (whenInUse.isPermanentlyDenied) {
        await openAppSettings();
        return;
      }
    }
    final status = await p.request();
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return;
    }
    if (mounted) {
      setState(() => _granted[p] = status.isGranted);
      if (status.isGranted && (_granted[Permission.locationAlways] ?? false)) {
        widget.onFinish();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allItems = [
      (
        Permission.locationAlways,
        Icons.location_on_rounded,
        loc('Canlı Konum & Ortak Harita', 'Live Location & Shared Map'),
        loc(
          'Uygulama kapalıyken bile partnerinin seni haritada görebilmesi için.',
          'So your partner can see you on the map even when the app is closed.',
        ),
      ),
      (
        Permission.notification,
        Icons.notifications_rounded,
        loc('Bildirimler', 'Notifications'),
        loc(
          '“Seni düşünüyorum” mesajları ve özel gün hatırlatıcıları için.',
          'For "Thinking of you" messages and special date reminders.',
        ),
      ),
    ];

    final missingItems = allItems.where((it) => !(_granted[it.$1] ?? false)).toList();
    final allGranted = !_checking && missingItems.isEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: widget.onBack,
              ),
            ),
            Text(
              allGranted
                  ? loc('Her Şey Hazır! 🎉', 'All Set! 🎉')
                  : loc('Eksik İzinler', 'Missing Permissions'),
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              allGranted
                  ? loc(
                      'Tüm gerekli izinler tanımlı. Lovera\'yı tam performansla kullanabilirsiniz.',
                      'All required permissions are granted. You can use Lovera with full features.',
                    )
                  : loc(
                      'Uygulamanın kesintisiz çalışması için aşağıdaki izinleri tamamlayın.',
                      'Please grant the permissions below for seamless background operation.',
                    ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: LoveraColors.textMuted),
            ),
            const SizedBox(height: 24),
            if (_checking)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (allGranted)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_rounded, size: 68, color: LoveraColors.secondary),
                      const SizedBox(height: 16),
                      Text(
                        loc(
                          'Konum, bildirim ve kamera izinleri aktif.',
                          'Location, notification, and camera permissions are active.',
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(color: LoveraColors.textMuted),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: missingItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final (perm, icon, title, desc) = missingItems[i];
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        border: Border.all(color: theme.dividerColor),
                        boxShadow: AppTheme.ambientShadow,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: LoveraColors.primarySoft.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(icon, color: LoveraColors.primary),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title,
                                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(desc,
                                    style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            onPressed: () => _request(perm),
                            child: Text(loc('İzin Ver', 'Grant')),
                          ),
                        ],
                      ),
                    ).animate(delay: (i * 90).ms).fadeIn().slideY(begin: 0.1);
                  },
                ),
              ),
            FilledButton(
              onPressed: widget.onFinish,
              child: Text(
                allGranted
                    ? loc('Lovera’ya Başla', 'Start Lovera')
                    : loc('Devam Et', 'Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
