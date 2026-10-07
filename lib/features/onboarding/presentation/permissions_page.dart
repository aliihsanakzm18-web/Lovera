import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';

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
    Permission.camera: false,
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
    final cam = await Permission.camera.isGranted;

    if (mounted) {
      setState(() {
        _granted[Permission.locationAlways] = locAlways || locWhenInUse;
        _granted[Permission.notification] = notif;
        _granted[Permission.camera] = cam;
        _checking = false;
      });
    }
  }

  Future<void> _request(Permission p) async {
    // Android/iOS: Arka plan izni için önce ön plan, ardından her zaman izin istenir
    if (p == Permission.locationAlways) {
      final whenInUse = await Permission.locationWhenInUse.request();
      if (whenInUse.isGranted) {
        final status = await Permission.locationAlways.request();
        if (mounted) setState(() => _granted[p] = status.isGranted || whenInUse.isGranted);
        return;
      }
    }
    final status = await p.request();
    if (mounted) setState(() => _granted[p] = status.isGranted);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allItems = [
      (Permission.locationAlways, Icons.location_on_rounded, 'Canlı Konum & Snap Map',
          'Uygulama kapalıyken bile partnerinin seni haritada görebilmesi için.'),
      (Permission.notification, Icons.notifications_rounded, 'Bildirimler',
          '“Seni düşünüyorum” mesajları ve özel gün hatırlatıcıları için.'),
      (Permission.camera, Icons.photo_camera_rounded, 'Kamera',
          'Anı fotoğrafı çekmek ve QR kod okutmak için.'),
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
            Text(allGranted ? 'Her Şey Hazır! 🎉' : 'Eksik İzinler',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
                allGranted
                    ? 'Tüm gerekli izinler tanımlı. Lovera\'yı tam performansla kullanabilirsiniz.'
                    : 'Uygulamanın kesintisiz çalışması için aşağıdaki izinleri tamamlayın.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: LoveraColors.textMuted)),
            const SizedBox(height: 24),
            if (_checking)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (allGranted)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_rounded, size: 68, color: LoveraColors.secondary),
                      const SizedBox(height: 16),
                      Text(
                        'Konum, bildirim ve kamera izinleri aktif.',
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
                            child: const Text('İzin Ver'),
                          ),
                        ],
                      ),
                    ).animate(delay: (i * 90).ms).fadeIn().slideY(begin: 0.1);
                  },
                ),
              ),
            FilledButton(
              onPressed: widget.onFinish,
              child: Text(allGranted ? 'Lovera’ya Başla' : 'Devam Et'),
            ),
          ],
        ),
      ),
    );
  }
}
