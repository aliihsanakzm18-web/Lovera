import '../../../core/localization/app_strings.dart';
import '../../../core/localization/weather_localizer.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/models.dart';
import '../../../core/services/background_tracking_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/device_service.dart';
import '../../../core/services/heartbeat_haptic_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/pairing_view.dart';
import '../../couple/presentation/couple_management_view.dart';
import '../../map/presentation/live_map_view.dart';
import '../../memories/presentation/memories_gallery_view.dart';
import '../../milestones/presentation/milestones_view.dart';
import '../../onboarding/presentation/onboarding_flow.dart';
import '../../settings/presentation/settings_view.dart';
import '../../drawing/presentation/drawing_screen.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/services/background_slideshow_service.dart';
import '../../../core/services/widget_sync_service.dart';
import '../../../core/widgets/avatar_cache.dart';
import '../../../core/widgets/lovera_theme_background.dart';

class DashboardView extends ConsumerStatefulWidget {
  const DashboardView({super.key, this.onOpenMap, this.onOpenChat});
  final VoidCallback? onOpenMap;
  final VoidCallback? onOpenChat;

  @override
  ConsumerState<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends ConsumerState<DashboardView> with TickerProviderStateMixin {
  late final AnimationController _heartAnimController;
  late final Animation<double> _heartScaleAnim;
  late final Animation<double> _heartOpacityAnim;
  late final Animation<double> _heartSlideAnim;
  bool _showHeart = false;
  DateTime? _lastHeartSentTime;
  StreamSubscription? _userSub;
  StreamSubscription? _partnerSub;
  StreamSubscription? _coupleSub;
  StreamSubscription? _savedPlacesSub;
  String? _listenedCoupleId;
  StreamSubscription? _drawingSub;
  List<SavedPlace> _savedPlaces = [];
  Timer? _statusSyncTimer;
  Timer? _widgetRefreshTimer;
  int? _lastHeartTimestamp;
  int? _lastChargeTimestamp;
  String? _lastPartnerDetectedPlaceId;
  String? _lastMyDetectedPlaceId;
  String? _syncedMyBirthDate;
  String? _syncedPartnerBirthDate;
  AppLifecycleListener? _lifecycleListener;
  bool _isKicked = false;

  void _handleKickedByOtherDevice() async {
    if (_isKicked) return;
    _isKicked = true;

    _userSub?.cancel();
    _partnerSub?.cancel();
    _coupleSub?.cancel();
    _statusSyncTimer?.cancel();

    // Başka bir cihaz oturum açtığı için o cihazın oturumunu bozmadan yerel çıkış yap
    await AuthService().signOut(clearRemoteSession: false);

    if (!mounted) return;

    ref.read(userNameProvider.notifier).state = '';
    ref.read(partnerProvider.notifier).state = null;
    ref.read(currentUserProvider.notifier).state = null;
    ref.read(startDateProvider.notifier).state = null;
    ref.read(coupleIdProvider.notifier).state = null;
    ref.read(milestonesProvider.notifier).state = [];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.devices_rounded, color: Colors.orangeAccent),
            const SizedBox(width: 8),
            Text(loc('Oturum Kapatıldı', 'Session Terminated')),
          ],
        ),
        content: Text(
          loc(
            'Hesabınıza başka bir cihazdan giriş yapıldı. Konum ve bildirim karışıklığını önlemek için bu cihazdaki oturumunuz kapatıldı.',
            'Your account was signed into from another device. To prevent location and notification conflicts, your session on this device has ended.',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const OnboardingFlow()),
                (route) => false,
              );
            },
            child: Text(loc('Tamam', 'OK')),
          ),
        ],
      ),
    );
  }

  bool _isSettingsDialogShowing = false;
  bool _isCheckingPermissions = false;
  bool _waitingForSettingsReturn = false;

  void _showBackgroundLocationGuideDialog() {
    if (_isSettingsDialogShowing || !mounted) return;
    _isSettingsDialogShowing = true;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? LoveraColors.primaryDark : LoveraColors.primary;
    final surfaceColor = isDark ? LoveraColors.darkSurface : LoveraColors.lightSurface;
    final textColor = isDark ? LoveraColors.darkText : LoveraColors.textDark;
    final textMutedColor = isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted;
    final borderColor = isDark ? LoveraColors.darkBorder : LoveraColors.lightBorder;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: borderColor, width: 1),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.location_on_rounded, color: primaryColor, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                loc('Kesintisiz Konum', 'Continuous Location'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loc(
                'Uygulama kapalıyken partnerinizin sizi canlı haritada ve masaüstü widget\'ında görebilmesi için:',
                'For your partner to see you on the live map and home widget when the app is closed:',
              ),
              style: TextStyle(fontSize: 14, height: 1.45, color: textMutedColor),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: primaryColor.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: primaryColor, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      loc(
                        'Açılan sayfada "İzinler > Konum > Her zaman izin ver" seçeneğini işaretleyin.',
                        'On the opened page, select "Permissions > Location > Allow all the time".',
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _isSettingsDialogShowing = false;
            },
            child: Text(loc('Şimdilik Atla', 'Skip for Now'), style: TextStyle(color: textMutedColor)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              _isSettingsDialogShowing = false;
              _waitingForSettingsReturn = true;
              await openAppSettings();
            },
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(loc('İzni Ayarla', 'Set Permission'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showLocationGrantedSuccessSnackbar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: LoveraColors.textDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF34D399), width: 1),
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            const Icon(Icons.favorite_rounded, color: Color(0xFFFF5E7E), size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc('Konum Paylaşımı Aktif 💕', 'Location Sharing Active 💕'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    loc(
                      'Artık partneriniz uygulama kapalı olsa bile sizi haritada ve widget\'ta kesintisiz görebilecek.',
                      'Now your partner can see you on the map and widget seamlessly even when the app is closed.',
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                      height: 1.3,
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

  Future<void> _checkAndRequestPermissionsSequentially() async {
    if (_isCheckingPermissions) return;
    _isCheckingPermissions = true;
    try {
      // 1. Konum İzni Kontrolü
      var locStatus = await Geolocator.checkPermission();

      // Ayarlara gidip geri dönüldüyse ve izin "Her zaman" veya "Uygulama kullanılırken" yapıldıysa bildirim mesajı göster
      if (_waitingForSettingsReturn) {
        _waitingForSettingsReturn = false;
        if (locStatus == LocationPermission.always || locStatus == LocationPermission.whileInUse) {
          _showLocationGrantedSuccessSnackbar();
        }
      }

      if (locStatus == LocationPermission.denied) {
        // Google Play "Prominent Disclosure": sistem izin penceresinden ÖNCE kullanım amacı açıkça gösterilir.
        if (!mounted) return;
        final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text(loc('Konum erişimi', 'Location Access')),
            content: Text(
              loc(
                'Lovera, konumunu ve pil seviyeni yalnızca eşleştiğin partnerinle paylaşmak için '
                'kullanır; uygulama kapalıyken veya arka plandayken de toplanabilir.\n\n'
                'Veri reklam için kullanılmaz ve üçüncü kişilerle paylaşılmaz. '
                'Paylaşımı Ayarlar\'dan kapatabilir veya hesabını silerek tüm verini kaldırabilirsin.',
                'Lovera uses your location and battery level solely to share with your paired partner; '
                'it may also be collected when the app is closed or in the background.\n\n'
                'Data is never used for advertising and is not shared with third parties. '
                'You can turn off sharing from Settings or remove all data by deleting your account.',
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc('Şimdi değil', 'Not now'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(loc('Kabul ediyorum', 'I accept'))),
            ],
          ),
        );
        if (accepted != true) return;
        // İzin henüz hiç verilmemiş: Standart açılır pencere ile sor ("Uygulamayı kullanırken")
        locStatus = await Geolocator.requestPermission();
        if (locStatus == LocationPermission.whileInUse) {
          // Kullanıcı "Uygulama kullanılırken" seçti! Şimdi WhatsApp tarzı açıklayıcı dialog gösterip "Her zaman"a yönlendir
          if (mounted) {
            _showBackgroundLocationGuideDialog();
          }
        }
        if (locStatus == LocationPermission.always || locStatus == LocationPermission.whileInUse) {
          DeviceService().startContinuousLocationTracking();
          BackgroundTrackingService().initialize();
        }
        await Future.delayed(const Duration(milliseconds: 400));
      } else if (locStatus == LocationPermission.whileInUse) {
        // İzin "Uygulama kullanılırken" modunda kalmışsa açıklayıcı dialog ile "Her zaman" seçmesini öner
        if (mounted && !_isSettingsDialogShowing) {
          _showBackgroundLocationGuideDialog();
        }
        DeviceService().startContinuousLocationTracking();
        BackgroundTrackingService().initialize();
      } else if (locStatus == LocationPermission.deniedForever) {
        // Ayarlardan tamamen kapatılmışsa dialog göster
        if (mounted && !_isSettingsDialogShowing) {
          _showLocationSettingsDialog();
        }
      } else {
        // İzin zaten "Always" (Her zaman), servisi sürdür
        DeviceService().startContinuousLocationTracking();
        BackgroundTrackingService().initialize();
      }

      // 2. Bildirim İzni Kontrolü: Yalnızca eksikse iste!
      final notifStatus = await Permission.notification.status;
      if (!notifStatus.isGranted && !notifStatus.isPermanentlyDenied) {
        await NotificationService().requestNotificationPermission();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // Servisleri hazırla
      await NotificationService().init(requestPermissions: false);
      if (locStatus == LocationPermission.always || locStatus == LocationPermission.whileInUse) {
        await BackgroundTrackingService().initialize();
      }
    } catch (e) {
      debugPrint('[PERM-CHECK-ERROR] $e');
    } finally {
      _isCheckingPermissions = false;
    }
  }

  void _showLocationSettingsDialog() {
    _isSettingsDialogShowing = true;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.location_off_rounded, color: Colors.orangeAccent),
            const SizedBox(width: 10),
            Text(
              loc('Konum İzni Gerekli', 'Location Permission Required'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          loc(
            'Partnerinizin haritada konumunuzu görebilmesi ve aranızdaki mesafenin hesaplanabilmesi için konum iznini ayarlardan etkinleştirmeniz gerekmektedir.',
            'To allow your partner to see your location on the map and calculate the distance between you, you need to enable location permission in settings.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _isSettingsDialogShowing = false;
            },
            child: Text(loc('Daha Sonra', 'Later')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _isSettingsDialogShowing = false;
              Geolocator.openAppSettings();
            },
            child: Text(loc('Ayarları Aç', 'Open Settings')),
          ),
        ],
      ),
    ).then((_) => _isSettingsDialogShowing = false);
  }

  @override
  void initState() {
    super.initState();
    _heartAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _heartScaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.2, end: 1.25).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.25, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.8).chain(CurveTween(curve: Curves.easeInBack)),
        weight: 20,
      ),
    ]).animate(_heartAnimController);

    _heartOpacityAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 65,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 20,
      ),
    ]).animate(_heartAnimController);

    _heartSlideAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: ConstantTween<double>(0.0),
        weight: 70,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: -60.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 30,
      ),
    ]).animate(_heartAnimController);

    _heartAnimController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _showHeart = false);
      }
    });

    final startupTime = DateTime.now().millisecondsSinceEpoch;
    _lastHeartTimestamp = startupTime;
    _lastChargeTimestamp = startupTime;

    // Snap Map Modeli: Canlı konum, şarj, şehir ve hava durumu arka planda da kesintisiz çalışsın
    DeviceService().startContinuousLocationTracking();
    NotificationService().updateFcmTokenInFirestore();

    // İlk açılışta veya geri dönüldüğünde aktif widget ve sohbet slideshow varsa buluttan eşitle ve canlandır
    final coupleId = ref.read(coupleIdProvider) ?? ref.read(currentUserProvider)?.coupleId;
    if (coupleId != null && coupleId.isNotEmpty) {
      BackgroundSlideshowService().getConfig('widget', coupleId: coupleId).then((wCfg) {
        if (wCfg.isEnabled) {
          DatabaseService().getMemoriesOnce(coupleId).then((mems) {
            BackgroundSlideshowService().startWidgetTimer(
              coupleId: coupleId,
              memories: mems,
              config: wCfg,
            );
          });
        }
      });
      // Sohbet döngüsünü de buluttan kontrol et
      BackgroundSlideshowService().getConfig('chat', coupleId: coupleId);
    }

    // Periyodik olarak durumu kontrol et (yalnızca pil/konum değiştiyse yazılır)
    _statusSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      DeviceService().syncStatusToFirebase();
    });

    // Her dakika başı masaüstü widget'larını veritabanını hiç yormadan yerel saat ile yeniden tetikle
    _widgetRefreshTimer?.cancel();
    _widgetRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      WidgetSyncService.updateWidgetFromLocalCache();
      final cId = ref.read(coupleIdProvider) ?? ref.read(currentUserProvider)?.coupleId;
      if (cId != null && cId.isNotEmpty) {
        final mems = await DatabaseService().getMemoriesOnce(cId);
        await BackgroundSlideshowService().rotateWidgetSlideshowIfNeeded(mems);
      }
    });

    // Uygulama alta atıldığında veya kapatılmak üzereyken durumu güncelle
    _lifecycleListener = AppLifecycleListener(
      onPause: () {
        _statusSyncTimer?.cancel();
        _widgetRefreshTimer?.cancel();
        DatabaseService().setAppPresence(false);
      },
      onDetach: () {
        _statusSyncTimer?.cancel();
        _widgetRefreshTimer?.cancel();
        DatabaseService().setAppPresence(false);
      },
      onResume: () {
        DatabaseService().setAppPresence(true);
        DeviceService().syncStatusToFirebase();
        _statusSyncTimer?.cancel();
        _statusSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
          DeviceService().syncStatusToFirebase();
        });
        _widgetRefreshTimer?.cancel();
        _widgetRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
          WidgetSyncService.updateWidgetFromLocalCache();
          final cId = ref.read(coupleIdProvider) ?? ref.read(currentUserProvider)?.coupleId;
          if (cId != null && cId.isNotEmpty) {
            final mems = await DatabaseService().getMemoriesOnce(cId);
            await BackgroundSlideshowService().rotateWidgetSlideshowIfNeeded(mems);
          }
        });
        // Ayarlardan izin değiştirilip geri dönüldüyse anında algıla ve gerekirse izin iste
        _checkAndRequestPermissionsSequentially();
      },
    );

    // FCM üzerinden gelen doğrudan sıfır-maliyetli kalp ve şarj bildirimlerini UI'a bağla
    NotificationService().onHeartPingReceived = (senderName) {
      if (mounted) _receiveHeartPulse(senderName: senderName);
    };
    NotificationService().onChargePingReceived = (senderName) {
      if (mounted) _receiveChargeReminder(senderName);
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Uygulama içine girdikten sonra izinleri sırasıyla iste
      _checkAndRequestPermissionsSequentially();
      NotificationService().updateFcmTokenInFirestore();
      // 1. Kendi profilimizi dinle
      _userSub = DatabaseService().userStream()?.listen((doc) async {
        if (!doc.exists || doc.data() == null || !mounted || _isKicked) return;
        final data = doc.data()!;

        // Tek aktif cihaz oturumu kontrolü: Eğer hesaba başka bir cihaz bağlandıysa bu cihazı düşür!
        final remoteDeviceId = data['currentDeviceId'] as String?;
        if (remoteDeviceId != null && remoteDeviceId.isNotEmpty) {
          final myDeviceId = await DeviceService().getOrCreateDeviceId();
          if (!mounted || _isKicked) return;
          if (remoteDeviceId != myDeviceId) {
            _handleKickedByOtherDevice();
            return;
          }
        }

        SharedPreferences.getInstance().then((p) => p.setString('saved_uid', doc.id));

        // Buluttaki dil, tema modu ve tema paketi tercihlerini başka cihazdan giriş yapıldığında senkronize et
        final remoteLang = data['language'] as String?;
        if (remoteLang == 'en' || remoteLang == 'tr') {
          final targetLang = remoteLang == 'en' ? AppLanguage.en : AppLanguage.tr;
          if (ref.read(appLanguageProvider) != targetLang) {
            ref.read(appLanguageProvider.notifier).setLanguage(targetLang, syncToCloud: false);
          }
        }

        final remoteThemeMode = data['themeMode'] as String?;
        if (remoteThemeMode == 'light' || remoteThemeMode == 'dark' || remoteThemeMode == 'system') {
          final targetMode = remoteThemeMode == 'light'
              ? ThemeMode.light
              : (remoteThemeMode == 'dark' ? ThemeMode.dark : ThemeMode.system);
          if (ref.read(themeModeProvider) != targetMode) {
            ref.read(themeModeProvider.notifier).setThemeMode(targetMode, syncToCloud: false);
          }
        }

        final remotePaletteKey = data['themePalette'] as String?;
        if (remotePaletteKey != null && remotePaletteKey.isNotEmpty) {
          final targetPaletteData = ThemePaletteData.fromKey(remotePaletteKey);
          if (ref.read(themePaletteProvider).id != targetPaletteData.id) {
            ref.read(themePaletteProvider.notifier).setPalette(targetPaletteData.id, syncToCloud: false);
          }
        } else {
          // Eğer Firestore'da henüz themePalette/themeMode kayıtlı değilse yerel seçimi buluta yedekle
          final currentPalette = ref.read(themePaletteProvider).id.name;
          final currentMode = ref.read(themeModeProvider);
          final modeStr = currentMode == ThemeMode.light
              ? 'light'
              : (currentMode == ThemeMode.dark ? 'dark' : 'system');
          DatabaseService().updateUserThemePreferences(
            themePalette: currentPalette,
            themeMode: modeStr,
          );
        }

        if (data['name'] != null && data['name'].toString().isNotEmpty) {
          ref.read(userNameProvider.notifier).state = data['name'];
          SharedPreferences.getInstance().then((p) => p.setString('saved_user_name', data['name']));
        } else {
          // Eğer Firestore'daki isim boşsa yerel hafızadaki ismi Firestore'a eşitle
          final currentName = ref.read(userNameProvider);
          if (currentName.isNotEmpty) {
            DatabaseService().updateUserName(currentName);
            SharedPreferences.getInstance().then((p) => p.setString('saved_user_name', currentName));
          }
        }
        if (data['avatarUrl'] != null && (data['avatarUrl'] as String).isNotEmpty) {
          final av = data['avatarUrl'] as String;
          ref.read(userAvatarProvider.notifier).state = av;
          SharedPreferences.getInstance().then((p) => p.setString('avatar_${doc.id}', av));
        } else {
          SharedPreferences.getInstance().then((p) {
            if (!mounted) return;
            final cached = p.getString('avatar_${doc.id}');
            if (cached != null && cached.isNotEmpty) {
              ref.read(userAvatarProvider.notifier).state = cached;
            } else {
              ref.read(userAvatarProvider.notifier).state = null;
            }
          });
        }
        if (data['widgetBgUrl'] != null && (data['widgetBgUrl'] as String).isNotEmpty) {
          final bgBase64 = data['widgetBgUrl'] as String;
          getApplicationDocumentsDirectory().then((appDir) async {
            final targetPath = '${appDir.path}/widget_bg_custom.jpg';
            final file = File(targetPath);
            if (!file.existsSync() || file.lengthSync() == 0) {
              final clean = bgBase64.contains(',') ? bgBase64.split(',').last : bgBase64;
              await file.writeAsBytes(base64Decode(clean));
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('widget_custom_bg_path', targetPath);
              await WidgetSyncService.setWidgetBackgroundImage(targetPath);
            }
          });
        }
        final meUser = AppUser(
          id: doc.id,
          name: data['name'] ?? ref.read(userNameProvider),
          avatarUrl: data['avatarUrl'],
          widgetBgUrl: data['widgetBgUrl'] as String?,
          batteryLevel: data['batteryLevel'] as int?,
          weather: data['weather'] as String?,
          city: data['city'] as String?,
          lat: (data['lat'] as num?)?.toDouble(),
          lng: (data['lng'] as num?)?.toDouble(),
          lastActive: data['lastActive'] != null
              ? (data['lastActive'] as dynamic).toDate?.call() ?? DateTime.now()
              : DateTime.now(),
          coupleId: data['coupleId'],
          isAppOpen: data['isAppOpen'] as bool?,
          birthDate: data['birthDate'] as String?,
          hometown: data['hometown'] as String?,
          firstName: data['firstName'] as String?,
          lastName: data['lastName'] as String?,
          speed: (data['speed'] as num?)?.toDouble(),
          currentPlaceTitle: data['currentPlaceTitle'] as String?,
          currentPlaceEmoji: data['currentPlaceEmoji'] as String?,
          lastNetPing: data['lastNetPing'] != null
              ? (data['lastNetPing'] is DateTime
                  ? data['lastNetPing']
                  : (data['lastNetPing'] is String
                      ? DateTime.tryParse(data['lastNetPing'])
                      : (data['lastNetPing'] as dynamic).toDate?.call()))
              : null,
        );
        ref.read(currentUserProvider.notifier).state = meUser;

        if (meUser.lat != null && meUser.lng != null && _savedPlaces.isNotEmpty) {
          _checkMyPlaceNotifications(meUser);
        }
        if (data['coupleId'] != null) {
          final cId = data['coupleId'] as String;
          SharedPreferences.getInstance().then((p) => p.setString('saved_couple_id', cId));
          if (data['birthDate'] != null && _syncedMyBirthDate != data['birthDate']) {
            _syncedMyBirthDate = data['birthDate'];
            DatabaseService().syncBirthdayMilestone(
              targetUserId: doc.id,
              userName: data['name'] ?? ref.read(userNameProvider),
              birthDateStr: data['birthDate'],
              coupleId: cId,
            );
          }
          ref.read(coupleIdProvider.notifier).state = cId;
          if (_coupleSub == null || _listenedCoupleId != cId) {
            _listenedCoupleId = cId;
            _listenToCouple(cId);
          }
        } else {
          // coupleId yoksa veya ayrılma sonucu silindiyse çift bağlantısını sıfırla
          _coupleSub?.cancel();
          _coupleSub = null;
          _listenedCoupleId = null;
          _drawingSub?.cancel();
          _drawingSub = null;
          _savedPlacesSub?.cancel();
          _savedPlacesSub = null;
          _milestonesSub?.cancel();
          _milestonesSub = null;
          if (ref.read(coupleIdProvider) != null) {
            ref.read(coupleIdProvider.notifier).state = null;
          }
          SharedPreferences.getInstance().then((p) => p.remove('saved_couple_id'));
          if (data['relationshipStartDate'] == null) {
            ref.read(startDateProvider.notifier).state = null;
            SharedPreferences.getInstance().then((p) => p.remove('saved_start_date'));
          }
        }
        
        if (data['relationshipStartDate'] != null) {
          final sDate = DateTime.tryParse(data['relationshipStartDate']);
          ref.read(startDateProvider.notifier).state = sDate;
          if (sDate != null) {
            SharedPreferences.getInstance().then((p) => p.setString('saved_start_date', sDate.toIso8601String()));
          }
        }

        // Partner tarihi doğrudan güncellediyse bilgi mesajı göster
        if (data['dateUpdatedNotice'] != null) {
          final notice = Map<String, dynamic>.from(data['dateUpdatedNotice']);
          DatabaseService().clearDateUpdatedNotice();
          if (mounted) {
            final updater = notice['updaterName'] ?? loc('Partneriniz', 'Your Partner');
            final dStr = notice['newDate'];
            final d = dStr != null ? DateTime.tryParse(dStr) : null;
            final dateText = d != null ? '${d.day}.${d.month}.${d.year}' : '';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(loc('$updater birliktelik başlangıç tarihinizi $dateText olarak güncelledi. 💕', '$updater updated your anniversary date to $dateText. 💕')),
                backgroundColor: LoveraColors.secondary,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }

        // Karşı taraf bize yeni eşleşme isteği attı mı?
        if (data['pendingPairRequest'] != null && !_pairRequestDialogOpen) {
          final req = Map<String, dynamic>.from(data['pendingPairRequest']);
          if (req['status'] == 'pending') {
            _showIncomingPairRequestSheet(req);
          }
        }

        // Bize partnerden tarih değiştirme isteği geldi mi? (Eski sürüm istekleri için)
        if (data['pendingDateChangeRequest'] != null && !_dateDialogOpen) {
          final req = Map<String, dynamic>.from(data['pendingDateChangeRequest']);
          if (req['status'] == 'pending') {
            _showIncomingDateChangeDialog(req, data['coupleId']);
          }
        }

        // Karşı taraf isteğimizi yanıtladı mı?
        if (data['dateChangeResult'] != null) {
          final res = Map<String, dynamic>.from(data['dateChangeResult']);
          // Hemen veritabanından silelim ki her Stream güncellemesinde (pil, konum vs) tekrar fırlatmasın!
          DatabaseService().clearDateChangeResult();
          if (mounted) {
            if (res['status'] == 'accepted') {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(loc('Partneriniz tarih değişikliğini kabul etti! Sayaç güncellendi. 💕', 'Your partner accepted the date change! Counter updated. 💕')),
                  backgroundColor: LoveraColors.secondary,
                ),
              );
            } else if (res['status'] == 'rejected') {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(loc('Partneriniz tarih değişikliğini kabul etmedi.', 'Your partner did not accept the date change.'))),
              );
            }
          }
        }

        // Bize partner kalp gönderdiyse ekranda büyük kalp animasyonu patlat!
        if (data['heartPing'] != null) {
          final ping = Map<String, dynamic>.from(data['heartPing']);
          final ts = ping['timestamp'] as int?;
          if (ts != null && (_lastHeartTimestamp == null || ts > _lastHeartTimestamp!)) {
            _lastHeartTimestamp = ts;
            DatabaseService().clearHeartPing();
            final fromName = ping['fromName']?.toString();
            _receiveHeartPulse(senderName: fromName);
          }
        }

        // Bize partnerden şarjını doldur hatırlatması geldi mi?
        if (data['chargePing'] != null) {
          final ping = Map<String, dynamic>.from(data['chargePing']);
          final ts = ping['timestamp'] as int?;
          if (ts != null && (_lastChargeTimestamp == null || ts > _lastChargeTimestamp!)) {
            _lastChargeTimestamp = ts;
            DatabaseService().clearChargePing();
            final fromName = ping['fromName'] ?? 'Partnerin';
            _receiveChargeReminder(fromName.toString());
          }
        }

        // Partner UID'sini aldık mı? Partnerin profilini de canlı dinle!
        final partnerUid = data['partnerUid'] as String?;
        if (partnerUid != null && partnerUid.isNotEmpty) {
          SharedPreferences.getInstance().then((p) => p.setString('saved_partner_uid', partnerUid));
          if (partnerUid != ref.read(partnerUidProvider)) {
            ref.read(partnerUidProvider.notifier).state = partnerUid;
          }
          if (_partnerSub == null) {
            _listenToPartner(partnerUid);
            // Partnerin telefonu kapalıysa bile arka planda hemen şarj ve konumunu güncellemesi için sessiz uyandır
            NotificationService().requestPartnerStatusSync(partnerUid);
          }
        } else {
          // partnerUid yoksa veya ayrılma sonucu silindiyse partner dinleyicisini ve durumunu sıfırla
          _partnerSub?.cancel();
          _partnerSub = null;
          if (ref.read(partnerUidProvider) != null) {
            ref.read(partnerUidProvider.notifier).state = null;
          }
          if (ref.read(partnerProvider) != null) {
            ref.read(partnerProvider.notifier).state = null;
          }
          WidgetSyncService.resetAllWidgets();
        }
      });
    });
  }

  bool _dateDialogOpen = false;
  bool _pairRequestDialogOpen = false;

  StreamSubscription? _milestonesSub;

  void _listenToMilestones(String? coupleId) {
    _milestonesSub?.cancel();
    _milestonesSub = DatabaseService().milestonesStream(coupleId: coupleId).listen((items) {
      if (!mounted) return;
      ref.read(milestonesProvider.notifier).state = items;
    });
  }

  void _listenToSavedPlaces(String coupleId) {
    _savedPlacesSub?.cancel();
    _savedPlacesSub = DatabaseService().savedPlacesStream(coupleId).listen((places) {
      if (!mounted) return;
      ref.read(savedPlacesProvider.notifier).state = places;
      setState(() {
        _savedPlaces = places;
      });
      try {
        final placesJsonList = places.map((p) {
          final m = p.toJson();
          m['id'] = p.id;
          return m;
        }).toList();
        SharedPreferences.getInstance().then((p) => p.setString('cached_saved_places_json', jsonEncode(placesJsonList)));
      } catch (_) {}
      WidgetSyncService.syncWidget(
        partner: ref.read(partnerProvider),
        startDate: ref.read(startDateProvider),
        savedPlaces: places,
      );
    });
  }

  void _listenToDrawings(String coupleId) {
    _drawingSub?.cancel();
    _drawingSub = DatabaseService().latestDrawingStream(coupleId)?.listen((snap) async {
      if (!mounted || !snap.exists || snap.data() == null) return;
      final data = snap.data()!;
      final imageBase64 = data['imageBase64'] as String?;
      final senderId = data['senderId'] as String?;
      final senderName = data['senderName'] as String? ?? 'Partnerin';
      final myUid = DatabaseService().uid;

      if (imageBase64 != null && imageBase64.isNotEmpty) {
        try {
          final raw = imageBase64.split(',').last;
          final bytes = base64Decode(raw);
          final appDir = await getApplicationDocumentsDirectory();
          final drawingPath = '${appDir.path}/partner_drawing_latest.png';
          final f = File(drawingPath);
          await f.writeAsBytes(bytes);

          final isMe = senderId == myUid;
          DateTime? createdAt;
          final rawCreatedAt = data['createdAt'] ?? data['timestamp'];
          if (rawCreatedAt is int) {
            createdAt = DateTime.fromMillisecondsSinceEpoch(rawCreatedAt);
          } else if (rawCreatedAt is String) {
            final parsed = int.tryParse(rawCreatedAt);
            if (parsed != null) {
              createdAt = DateTime.fromMillisecondsSinceEpoch(parsed);
            } else {
              createdAt = DateTime.tryParse(rawCreatedAt);
            }
          } else if (rawCreatedAt != null) {
            try {
              createdAt = (rawCreatedAt as dynamic).toDate();
            } catch (_) {}
          }

          String timeAgo = loc('Şimdi', 'Just now');
          int? tsMillis = createdAt?.millisecondsSinceEpoch;
          if (createdAt != null) {
            final diff = DateTime.now().difference(createdAt);
            final minutes = diff.inMinutes.abs();
            if (minutes < 1) {
              timeAgo = loc('Şimdi', 'Just now');
            } else if (minutes < 60) {
              timeAgo = loc('$minutes dk önce', '${minutes}m ago');
            } else if (diff.inHours.abs() < 24) {
              timeAgo = loc('${diff.inHours.abs()} sa önce', '${diff.inHours.abs()}h ago');
            } else {
              timeAgo = loc('${diff.inDays.abs()} gün önce', '${diff.inDays.abs()}d ago');
            }
          }

          await WidgetSyncService.syncDrawingWidget(
            imagePath: drawingPath,
            imageBase64: imageBase64,
            senderName: isMe ? loc('Sen', 'You') : senderName,
            timeAgo: timeAgo,
            timestampMillis: tsMillis,
          );
          debugPrint('[DashboardView] Çizim widget senkronize edildi: sender=$senderName, isMe=$isMe, timeAgo=$timeAgo, hasBase64=${imageBase64.isNotEmpty}');
        } catch (e) {
          debugPrint('[DashboardView] Çizim widget sync error: $e');
        }
      }
    });
  }

  void _listenToCouple(String coupleId) {
    _coupleSub?.cancel();
    _listenToMilestones(coupleId);
    _listenToSavedPlaces(coupleId);
    _listenToDrawings(coupleId);
    _coupleSub = DatabaseService().coupleStream(coupleId)?.listen((doc) {
      if (!doc.exists || doc.data() == null || !mounted) return;
      final cData = doc.data()!;
      if (cData['relationshipStartDate'] != null) {
        final date = DateTime.tryParse(cData['relationshipStartDate']);
        ref.read(startDateProvider.notifier).state = date;
        if (date != null) {
          SharedPreferences.getInstance().then((p) => p.setString('saved_start_date', date.toIso8601String()));
          DatabaseService().syncDefaultAnniversary(date, coupleId: coupleId);
        }
        WidgetSyncService.syncWidget(
          partner: ref.read(partnerProvider),
          startDate: date ?? ref.read(startDateProvider),
          savedPlaces: _savedPlaces,
        );
      }
    });
  }

  // Gelen Eşleşme İsteği Onay Penceresi (Dashboard üzerindeyken anında açılır)
  Future<void> _showIncomingPairRequestSheet(Map<String, dynamic> req) async {
    _pairRequestDialogOpen = true;
    final requesterUid = req['fromUid'] as String;
    final requesterName = req['fromName'] as String? ?? 'Partnerin';
    final requesterAvatar = req['fromAvatar'] as String?;

    DateTime? selectedDate;
    bool showErrorBorder = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final theme = Theme.of(sheetCtx);
          final days = selectedDate != null
              ? (DateTime.now().difference(selectedDate!).inHours / 24).floor() + 1
              : null;

          return Padding(
            padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 18),
                CircleAvatar(
                  radius: 38,
                  backgroundColor: LoveraColors.primary.withValues(alpha: 0.15),
                  backgroundImage: AvatarCache.getProvider(requesterAvatar),
                  child: (requesterAvatar == null || AvatarCache.getProvider(requesterAvatar) == null)
                      ? Text(
                          requesterName.isNotEmpty ? requesterName[0].toUpperCase() : '?',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: LoveraColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  loc('$requesterName Seninle Eşleşmek İstiyor! 💕', '$requesterName Wants to Pair with You! 💕'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  loc(
                    'Onayladığında ikinize özel ortak alanınız açılacak. Lütfen birliktelik başlangıç tarihinizi seçin.',
                    'When confirmed, your private shared space will open. Please select your relationship start date.',
                  ),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: LoveraColors.textMuted, height: 1.3),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: sheetCtx,
                      initialDate: selectedDate ?? DateTime.now(),
                      firstDate: DateTime(1990),
                      lastDate: DateTime.now(),
                      helpText: loc('İlişki Başlangıç Tarihi', 'Relationship Start Date'),
                    );
                    if (picked != null) {
                      setSheetState(() {
                        selectedDate = picked;
                        showErrorBorder = false;
                      });
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: Theme.of(sheetCtx).brightness == Brightness.dark
                          ? LoveraColors.darkSurfaceAlt
                          : LoveraColors.lightSurfaceAlt,
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                      border: Border.all(
                        color: showErrorBorder
                            ? Colors.redAccent
                            : (Theme.of(sheetCtx).brightness == Brightness.dark
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.black.withValues(alpha: 0.08)),
                        width: showErrorBorder ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_month_rounded,
                              color: showErrorBorder ? Colors.redAccent : LoveraColors.primary,
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  loc('BİRLİKTELİK BAŞLANGICI *', 'RELATIONSHIP START *'),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: showErrorBorder ? Colors.redAccent : LoveraColors.textMuted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  selectedDate != null
                                      ? '${selectedDate!.day}.${selectedDate!.month}.${selectedDate!.year}'
                                      : loc('Tarih seçmek için dokunun', 'Tap to select date'),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: selectedDate != null
                                        ? null
                                        : (showErrorBorder ? Colors.redAccent : LoveraColors.textMuted),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (selectedDate != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: LoveraColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              loc('$days Gündür', '$days Days'),
                              style: TextStyle(
                                color: LoveraColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          )
                        else
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 16,
                            color: showErrorBorder ? Colors.redAccent : LoveraColors.textMuted,
                          ),
                      ],
                    ),
                  ),
                ),
                if (showErrorBorder) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        loc('⚠️ Devam etmek için birliktelik başlangıç tarihini seçmelisiniz.', '⚠️ You must select a relationship start date to continue.'),
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          Navigator.pop(sheetCtx);
                          _pairRequestDialogOpen = false;
                          await DatabaseService().rejectPairRequest(requesterUid);
                        },
                        child: Text(loc('Reddet', 'Decline')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.favorite_rounded, size: 18),
                        label: Text(loc('Kabul Et ve Bağlan', 'Accept & Connect')),
                        onPressed: () async {
                          if (selectedDate == null) {
                            HapticFeedback.vibrate();
                            setSheetState(() => showErrorBorder = true);
                            ScaffoldMessenger.of(sheetCtx).showSnackBar(
                              SnackBar(
                                content: Text(loc('Lütfen birliktelik başlangıç tarihinizi seçin! 📅', 'Please select your relationship start date! 📅')),
                                backgroundColor: Colors.redAccent,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }

                          Navigator.pop(sheetCtx);
                          _pairRequestDialogOpen = false;

                          final coupleId = await DatabaseService().acceptPairRequest(
                            requesterUid: requesterUid,
                            relationshipStartDate: selectedDate!,
                          );

                          if (coupleId.isNotEmpty && mounted) {
                            HapticFeedback.heavyImpact();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(loc('$requesterName ile başarıyla eşleşildi! 💕', 'Successfully paired with $requesterName! 💕')),
                                backgroundColor: LoveraColors.secondary,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    _pairRequestDialogOpen = false;
  }

  void _showIncomingDateChangeDialog(Map<String, dynamic> req, String? coupleId) {
    _dateDialogOpen = true;
    final partnerUid = req['fromUid'] as String;
    final requesterName = req['fromName'] as String? ?? 'Partnerin';
    final proposedDate = DateTime.parse(req['proposedDate'] as String);
    final diff = DateTime.now().difference(proposedDate);
    final days = (diff.inHours / 24).floor() + 1;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.edit_calendar_rounded, color: LoveraColors.primary),
            const SizedBox(width: 10),
            Text(loc('$requesterName Tarihi Değiştirmek İstiyor', '$requesterName Wants to Change the Date'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loc(
                '$requesterName aşk sayacınızın başlangıç tarihini şu şekilde güncellemek istiyor:',
                '$requesterName wants to update your love counter start date to:',
              ),
              style: const TextStyle(height: 1.4),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.light
                    ? LoveraColors.lightSurfaceAlt
                    : LoveraColors.darkSurfaceAlt,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loc('ÖNERİLEN TARİH', 'PROPOSED DATE'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: LoveraColors.textMuted)),
                      Text('${proposedDate.day}.${proposedDate.month}.${proposedDate.year}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: LoveraColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(loc('$days Gün', '$days Days'), style: TextStyle(color: LoveraColors.primary, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(loc('Onayladığınızda iki telefonun ekranındaki sayaç da bu tarihe göre güncellenecektir.', 'Once accepted, the counter on both phones will update to this date.'), style: TextStyle(fontSize: 12, color: LoveraColors.textMuted)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _dateDialogOpen = false;
              await DatabaseService().rejectDateChange(partnerUid);
            },
            child: Text(loc('Reddet', 'Decline')),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _dateDialogOpen = false;
              await DatabaseService().acceptDateChange(
                partnerUid: partnerUid,
                newDate: proposedDate,
                coupleId: coupleId,
              );
            },
            child: Text(loc('Kabul Et', 'Accept')),
          ),
        ],
      ),
    ).then((_) => _dateDialogOpen = false);
  }

  void _receiveHeartPulse({String? senderName}) {
    HeartbeatHapticService().playHeartbeat(pulses: 3);
    setState(() => _showHeart = true);
    _heartAnimController.forward(from: 0.0);
  }

  void _receiveChargeReminder(String fromName) {
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.battery_charging_full_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                loc('$fromName şarjını doldurmanı hatırlatıyor! 💕🔋', '$fromName reminds you to charge your phone! 💕🔋'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Batarya kartına basıldığında açılan alt menü (BottomSheet)
  void _openBatteryActionsSheet(AppUser partner) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final level = partner.batteryLevel ?? 0;
    final batteryColor = _getBatteryColor(level);
    final pName = () {
      if (partner.firstName != null && partner.firstName!.trim().isNotEmpty) {
        return partner.firstName!.trim();
      }
      final raw = partner.name.trim();
      if (!raw.contains(' ')) return raw;
      final parts = raw.split(RegExp(r'\s+'));
      return parts.length > 2
          ? parts.sublist(0, parts.length - 1).join(' ')
          : parts.first;
    }();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Batarya Durumu Büyük Rozeti
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: batteryColor.withValues(alpha: 0.14),
                  border: Border.all(color: batteryColor.withValues(alpha: 0.35), width: 2),
                ),
                child: Center(
                  child: Icon(
                    _getBatteryIcon(level),
                    size: 38,
                    color: batteryColor,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                ref.watch(stringsProvider).batterySheetTitle(pName),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                ref.watch(stringsProvider).batteryPercentageDesc(level, _getBatteryStatusText(level, ref.watch(stringsProvider))),
                style: TextStyle(
                  color: batteryColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                ref.watch(stringsProvider).batteryAutoUpdateDesc,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              // "Şarjını Doldur" Hatırlatma Butonu
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: batteryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.bolt_rounded, size: 22),
                  label: Text(
                    ref.watch(stringsProvider).sendChargeReminderBtn,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    HapticFeedback.mediumImpact();
                    final partnerUid = ref.read(partnerUidProvider);
                    final myName = ref.read(userNameProvider);
                    final senderName = myName.isEmpty ? 'Partnerin' : myName;
                    await DatabaseService().sendChargeReminder(
                      partnerUid,
                      fromName: senderName,
                    );
                    if (partnerUid != null && partnerUid.isNotEmpty) {
                      NotificationService().sendPushToPartner(
                        partnerUid: partnerUid,
                        title: loc('🔋 Şarj Hatırlatması!', '🔋 Battery Reminder!'),
                        body: loc('$senderName şarjını doldurmanı hatırlatıyor 💕', '$senderName reminds you to charge your phone 💕'),
                        titleTr: '🔋 Şarj Hatırlatması!',
                        titleEn: '🔋 Battery Reminder!',
                        bodyTr: '$senderName şarjını doldurmanı hatırlatıyor 💕',
                        bodyEn: '$senderName reminds you to charge your phone 💕',
                        data: {
                          'type': 'charge_ping',
                          'fromName': senderName,
                        },
                      );
                    }
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ref.read(stringsProvider).chargeReminderSentMsg(pName),
                        ),
                        backgroundColor: batteryColor,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              // "Şarjını Yanına Al" Hatırlatma Butonu
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
                    side: BorderSide(
                      color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                      width: 1.2,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.electrical_services_rounded, size: 20, color: Color(0xFF3B82F6)),
                  label: Text(
                    ref.watch(stringsProvider).takeChargerBtn,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    HapticFeedback.mediumImpact();
                    final partnerUid = ref.read(partnerUidProvider);
                    final myName = ref.read(userNameProvider);
                    final senderName = myName.isEmpty ? loc('Partnerin', 'Partner') : myName;
                    if (partnerUid != null && partnerUid.isNotEmpty) {
                      NotificationService().sendPushToPartner(
                        partnerUid: partnerUid,
                        title: loc('🔌 Şarjını Unutma!', '🔌 Don\'t Forget Your Charger!'),
                        body: loc('$senderName şarj aletini yanına almanı hatırlatıyor 🔌💕', '$senderName reminds you to take your charger 🔌💕'),
                        titleTr: '🔌 Şarjını Unutma!',
                        titleEn: '🔌 Don\'t Forget Your Charger!',
                        bodyTr: '$senderName şarj aletini yanına almanı hatırlatıyor 🔌💕',
                        bodyEn: '$senderName reminds you to take your charger 🔌💕',
                      );
                    }
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ref.read(stringsProvider).takeChargerSentMsg(pName),
                        ),
                        backgroundColor: const Color(0xFF3B82F6),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              // "Powerbank'ini Yanına Al" Hatırlatma Butonu
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
                    side: BorderSide(
                      color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                      width: 1.2,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: Icon(Icons.battery_charging_full_rounded, size: 20, color: LoveraColors.primary),
                  label: Text(
                    ref.watch(stringsProvider).takePowerbankBtn,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    HapticFeedback.mediumImpact();
                    final partnerUid = ref.read(partnerUidProvider);
                    final myName = ref.read(userNameProvider);
                    final senderName = myName.isEmpty ? loc('Partnerin', 'Partner') : myName;
                    if (partnerUid != null && partnerUid.isNotEmpty) {
                      NotificationService().sendPushToPartner(
                        partnerUid: partnerUid,
                        title: loc('🔋 Powerbank Hatırlatması!', '🔋 Power Bank Reminder!'),
                        body: loc('$senderName powerbank\'ini yanına almanı hatırlatıyor 🔋⚡', '$senderName reminds you to take your power bank 🔋⚡'),
                        titleTr: '🔋 Powerbank Hatırlatması!',
                        titleEn: '🔋 Power Bank Reminder!',
                        bodyTr: '$senderName powerbank\'ini yanına almanı hatırlatıyor 🔋⚡',
                        bodyEn: '$senderName reminds you to take your power bank 🔋⚡',
                      );
                    }
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ref.read(stringsProvider).takePowerbankSentMsg(pName),
                        ),
                        backgroundColor: LoveraColors.primary,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              // İptal Butonu
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(ref.watch(stringsProvider).close),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Hava durumu kartına basıldığında açılan alt menü (BottomSheet)
  void _openWeatherActionsSheet(AppUser partner) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final weatherText = localizeWeather(partner.weather);
    final cityText = partner.city ?? loc('İstanbul', 'Istanbul');
    final pName = () {
      if (partner.firstName != null && partner.firstName!.trim().isNotEmpty) {
        return partner.firstName!.trim();
      }
      final raw = partner.name.trim();
      if (!raw.contains(' ')) return raw;
      final parts = raw.split(RegExp(r'\s+'));
      return parts.length > 2
          ? parts.sublist(0, parts.length - 1).join(' ')
          : parts.first;
    }();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: LoveraColors.accentGold.withValues(alpha: 0.14),
                  border: Border.all(color: LoveraColors.accentGold.withValues(alpha: 0.35), width: 2),
                ),
                child: Center(
                  child: Icon(
                    Icons.wb_sunny_rounded,
                    size: 38,
                    color: LoveraColors.accentGold,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '${pName}${loc("\'in Hava Durumu", "\'s Weather")}',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '$cityText · $weatherText',
                style: TextStyle(
                  color: LoveraColors.accentGold,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                ref.watch(stringsProvider).weatherSheetDesc,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              // Hatırlatma Butonu 1: Hava Soğuk, Sıkı Giyin
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: LoveraColors.primary.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Text('🧣', style: TextStyle(fontSize: 20)),
                  label: Text(
                    ref.watch(stringsProvider).weatherColdPrompt,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () {
                    final senderName = ref.read(userNameProvider).isEmpty ? 'Partnerin' : ref.read(userNameProvider);
                    final senderNameEn = ref.read(userNameProvider).isEmpty ? 'Partner' : ref.read(userNameProvider);
                    _sendCareNotification(
                      partner: partner,
                      title: loc('🧣 Hava Soğuk, Sıkı Giyin!', '🧣 Cold Weather, Dress Warm!'),
                      body: loc('$senderName: "Hava soğuk aşkım, sakın üşütme sıkı giyin 💕"', '$senderNameEn: "It\'s cold outside my love, bundle up and stay warm 💕"'),
                      titleTr: '🧣 Hava Soğuk, Sıkı Giyin!',
                      titleEn: '🧣 Cold Weather, Dress Warm!',
                      bodyTr: '$senderName: "Hava soğuk aşkım, sakın üşütme sıkı giyin 💕"',
                      bodyEn: '$senderNameEn: "It\'s cold outside my love, bundle up and stay warm 💕"',
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              // Hatırlatma Butonu 2: Yanına Şemsiye Al
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: LoveraColors.accentViolet.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Text('☂️', style: TextStyle(fontSize: 20)),
                  label: Text(
                    ref.watch(stringsProvider).weatherRainPrompt,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () {
                    final senderName = ref.read(userNameProvider).isEmpty ? 'Partnerin' : ref.read(userNameProvider);
                    final senderNameEn = ref.read(userNameProvider).isEmpty ? 'Partner' : ref.read(userNameProvider);
                    _sendCareNotification(
                      partner: partner,
                      title: loc('☂️ Yanına Şemsiye Al!', '☂️ Take an Umbrella!'),
                      body: loc('$senderName: "Aşkım dışarısı yağışlı olabilir, yanına şemsiye almayı unutma 🌧️"', '$senderNameEn: "It might rain today my love, don\'t forget your umbrella 🌧️"'),
                      titleTr: '☂️ Yanına Şemsiye Al!',
                      titleEn: '☂️ Take an Umbrella!',
                      bodyTr: '$senderName: "Aşkım dışarısı yağışlı olabilir, yanına şemsiye almayı unutma 🌧️"',
                      bodyEn: '$senderNameEn: "It might rain today my love, don\'t forget your umbrella 🌧️"',
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              // Hatırlatma Butonu 3: Bol Su İç & Güneşten Korun
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: LoveraColors.secondary.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Text('☀️', style: TextStyle(fontSize: 20)),
                  label: Text(
                    ref.watch(stringsProvider).weatherWaterPrompt,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () {
                    final senderName = ref.read(userNameProvider).isEmpty ? 'Partnerin' : ref.read(userNameProvider);
                    final senderNameEn = ref.read(userNameProvider).isEmpty ? 'Partner' : ref.read(userNameProvider);
                    _sendCareNotification(
                      partner: partner,
                      title: loc('💧 Bol Su İçmeyi Unutma!', '💧 Remember to Drink Water!'),
                      body: loc('$senderName: "Bugün bol bol su iç aşkım, kendine çok iyi bak ☀️"', '$senderNameEn: "Drink plenty of water today my love, take good care of yourself ☀️"'),
                      titleTr: '💧 Bol Su İçmeyi Unutma!',
                      titleEn: '💧 Remember to Drink Water!',
                      bodyTr: '$senderName: "Bugün bol bol su iç aşkım, kendine çok iyi bak ☀️"',
                      bodyEn: '$senderNameEn: "Drink plenty of water today my love, take good care of yourself ☀️"',
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              // Kapat Butonu
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(loc('Kapat', 'Close')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendCareNotification({
    required AppUser partner,
    required String title,
    required String body,
    String? titleTr,
    String? titleEn,
    String? bodyTr,
    String? bodyEn,
  }) async {
    Navigator.pop(context);
    HapticFeedback.mediumImpact();
    final partnerUid = ref.read(partnerUidProvider);
    if (partnerUid != null && partnerUid.isNotEmpty) {
      await NotificationService().sendPushToPartner(
        partnerUid: partnerUid,
        title: title,
        body: body,
        titleTr: titleTr,
        titleEn: titleEn,
        bodyTr: bodyTr,
        bodyEn: bodyEn,
      );
    }
    if (!mounted) return;
    final pName = () {
      if (partner.firstName != null && partner.firstName!.trim().isNotEmpty) {
        return partner.firstName!.trim();
      }
      final raw = partner.name.trim();
      if (!raw.contains(' ')) return raw;
      final parts = raw.split(RegExp(r'\s+'));
      return parts.length > 2
          ? parts.sublist(0, parts.length - 1).join(' ')
          : parts.first;
    }();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ref.read(stringsProvider).weatherNotifSentMsg(pName)),
        backgroundColor: LoveraColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static Color _getBatteryColor(int? level) {
    if (level == null) return LoveraColors.secondary;
    if (level >= 80) return const Color(0xFF10B981); // Tam dolu: Canlı Zümrüt Yeşili
    if (level >= 50) return const Color(0xFF34D399); // Orta-iyi: Açık Yeşil
    if (level >= 30) return const Color(0xFFFBBF24); // Orta: Amber / Sarı
    if (level >= 15) return const Color(0xFFF97316); // Düşük: Turuncu
    return const Color(0xFFEF4444); // Kritik: Kırmızı
  }

  static IconData _getBatteryIcon(int? level) {
    if (level == null) return Icons.battery_unknown_rounded;
    if (level >= 95) return Icons.battery_full_rounded;
    if (level >= 85) return Icons.battery_6_bar_rounded;
    if (level >= 70) return Icons.battery_5_bar_rounded;
    if (level >= 50) return Icons.battery_4_bar_rounded;
    if (level >= 30) return Icons.battery_3_bar_rounded;
    if (level >= 20) return Icons.battery_2_bar_rounded;
    if (level >= 10) return Icons.battery_1_bar_rounded;
    return Icons.battery_alert_rounded;
  }

  static String _getBatteryStatusText(int? level, AppStrings strings) {
    if (level == null) return strings.weatherUnknown;
    if (level >= 90) return strings.batteryFullText;
    if (level >= 50) return strings.batterySufficientText;
    if (level >= 25) return strings.batteryDrainingText;
    if (level >= 15) return strings.batteryLowText;
    return strings.batteryCriticalText;
  }

  void _listenToPartner(String partnerUid) {
    _partnerSub?.cancel();
    _partnerSub = DatabaseService().partnerStream(partnerUid).listen((doc) {
      if (!doc.exists || doc.data() == null || !mounted) return;
      final data = doc.data()!;
      final rawWeather = data['weather'] as String?;
      String? cleanWeather = rawWeather;
      if (cleanWeather != null) {
        final now = DateTime.now();
        final isNight = now.hour >= 20 || now.hour < 6;
        if (isNight) {
          cleanWeather = cleanWeather.replaceAll('Güneşli', 'Açık');
        }
      }

      DateTime? parsedLastActive;
      final rawLastActive = data['lastActive'];
      if (rawLastActive is DateTime) {
        parsedLastActive = rawLastActive;
      } else if (rawLastActive is String) {
        parsedLastActive = DateTime.tryParse(rawLastActive);
      } else if (rawLastActive != null) {
        try {
          parsedLastActive = (rawLastActive as dynamic).toDate?.call();
        } catch (_) {}
      }

      final partnerUser = AppUser(
        id: doc.id,
        name: data['name'] ?? 'Partnerin',
        avatarUrl: data['avatarUrl'],
        batteryLevel: data['batteryLevel'] as int?,
        weather: cleanWeather,
        city: data['city'],
        lat: (data['lat'] as num?)?.toDouble(),
        lng: (data['lng'] as num?)?.toDouble(),
        lastActive: parsedLastActive,
        coupleId: data['coupleId'],
        isAppOpen: data['isAppOpen'] as bool?,
        birthDate: data['birthDate'] as String?,
        hometown: data['hometown'] as String?,
        firstName: data['firstName'] as String?,
        lastName: data['lastName'] as String?,
        speed: (data['speed'] as num?)?.toDouble(),
        currentPlaceTitle: data['currentPlaceTitle'] as String?,
        currentPlaceEmoji: data['currentPlaceEmoji'] as String?,
        language: data['language'] as String?,
        lastNetPing: data['lastNetPing'] != null
            ? (data['lastNetPing'] is DateTime
                ? data['lastNetPing']
                : (data['lastNetPing'] is String
                    ? DateTime.tryParse(data['lastNetPing'])
                    : (data['lastNetPing'] as dynamic).toDate?.call()))
            : null,
      );
      ref.read(partnerProvider.notifier).state = partnerUser;

      // Partner bilgilerini yerel belleğe JSON olarak önbellekle
      try {
        SharedPreferences.getInstance().then((p) {
          p.setString('cached_partner_json', jsonEncode(partnerUser.toJson()));
          final partnerFcm = data['fcmToken'] as String?;
          if (partnerFcm != null && partnerFcm.isNotEmpty) {
            p.setString('cached_partner_fcm_token_${doc.id}', partnerFcm);
          }
          final partnerLang = data['language'] as String?;
          if (partnerLang != null && partnerLang.isNotEmpty) {
            p.setString('cached_partner_language_${doc.id}', partnerLang);
          }
        });
      } catch (e) {
        debugPrint('Partner caching error: $e');
      }

      // Kayıtlı mekanlara giriş ve ayrılma bildirim kontrolü
      if (partnerUser.lat != null && partnerUser.lng != null && _savedPlaces.isNotEmpty) {
        _checkPartnerPlaceNotifications(partnerUser);
      }

      final coupleId = ref.read(coupleIdProvider) ?? data['coupleId'] as String?;
      if (coupleId != null && data['birthDate'] != null && _syncedPartnerBirthDate != data['birthDate']) {
        _syncedPartnerBirthDate = data['birthDate'];
        DatabaseService().syncBirthdayMilestone(
          targetUserId: doc.id,
          userName: data['name'] ?? 'Partner',
          birthDateStr: data['birthDate'],
          coupleId: coupleId,
        );
      }
      
      // Eğer partner ilişki tarihini güncellemişse bize de yansısın
      if (data['relationshipStartDate'] != null) {
        final rDate = DateTime.tryParse(data['relationshipStartDate']);
        ref.read(startDateProvider.notifier).state = rDate;
        if (rDate != null) {
          SharedPreferences.getInstance().then((p) => p.setString('saved_start_date', rDate.toIso8601String()));
        }
      }

      // Ana Ekran Widget'ını senkronize et
      WidgetSyncService.syncWidget(
        partner: partnerUser,
        startDate: ref.read(startDateProvider),
        savedPlaces: _savedPlaces,
      );
    });
  }

  /// Partner bir kayıtlı konuma girdiğinde veya ayrıldığında kullanıcıya anlık bildirim basar
  void _checkPartnerPlaceNotifications(AppUser partner) async {
    if (partner.lat == null || partner.lng == null) return;
    final partnerLat = partner.lat!;
    final partnerLng = partner.lng!;

    SavedPlace? matchedPlace;
    for (final p in _savedPlaces) {
      final dist = Geolocator.distanceBetween(partnerLat, partnerLng, p.lat, p.lng);
      if (dist <= 80) { // 80 metre: GPS doğruluğu ve bina içi sapmalar için güvenilir menzil
        matchedPlace = p;
        break;
      }
    }

    final newPlaceId = matchedPlace?.id;
    if (newPlaceId == _lastPartnerDetectedPlaceId) {
      return; // Konum mekan durumu değişmedi
    }

    final oldPlaceId = _lastPartnerDetectedPlaceId;
    _lastPartnerDetectedPlaceId = newPlaceId;

    final partnerName = partner.name.isNotEmpty ? partner.name : loc('Partnerin', 'Partner');

    // İlk uygulama açılışında durum henüz oturmamışsa ayrılma spam'i yapma
    if (oldPlaceId == null && matchedPlace != null) {
      debugPrint('[GEOFENCE-PARTNER] İlk tespit: $partnerName "${matchedPlace.title}" konumunda.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    // 1. Yeni bir mekana girdi mi?
    if (matchedPlace != null) {
      final remoteNotifs = matchedPlace.notifications ?? {};
      final myUid = DatabaseService().uid ?? '';
      final partnerUid = partner.id;
      final shouldNotifyEnter = 
          remoteNotifs['${partnerUid}_enter'] as bool? ??
          remoteNotifs['partner_enter'] as bool? ??
          remoteNotifs['${myUid}_enter'] as bool? ??
          remoteNotifs['my_enter'] as bool? ??
          prefs.getBool('partner_notify_enter_${matchedPlace.id}') ??
          prefs.getBool('notify_enter_${matchedPlace.id}') ?? true;
      if (shouldNotifyEnter) {
        NotificationService().show(
          id: matchedPlace.id.hashCode ^ 1,
          title: loc('${matchedPlace.iconEmoji} $partnerName Konuma Ulaştı', '${matchedPlace.iconEmoji} $partnerName Arrived at Location'),
          body: loc('$partnerName "${matchedPlace.title}" konumuna vardı. 💕', '$partnerName arrived at "${matchedPlace.title}". 💕'),
        );
      }
    }

    // 2. Önceki bir mekandan ayrıldı mı?
    if (oldPlaceId != null) {
      final oldPlaceList = _savedPlaces.where((p) => p.id == oldPlaceId);
      if (oldPlaceList.isNotEmpty) {
        final oldPlace = oldPlaceList.first;
        final remoteNotifs = oldPlace.notifications ?? {};
        final myUid = DatabaseService().uid ?? '';
        final partnerUid = partner.id;
        final shouldNotifyExit = 
            remoteNotifs['${partnerUid}_exit'] as bool? ??
            remoteNotifs['partner_exit'] as bool? ??
            remoteNotifs['${myUid}_exit'] as bool? ??
            remoteNotifs['my_exit'] as bool? ??
            prefs.getBool('partner_notify_exit_${oldPlace.id}') ??
            prefs.getBool('notify_exit_${oldPlace.id}') ?? true;
        if (shouldNotifyExit) {
          NotificationService().show(
            id: oldPlace.id.hashCode ^ 2,
            title: loc('🚶 $partnerName Konumdan Ayrıldı', '🚶 $partnerName Left Location'),
            body: loc('$partnerName "${oldPlace.title}" konumundan ayrıldı.', '$partnerName left "${oldPlace.title}".'),
          );
        }
      }
    }
  }

  /// Kullanıcının kendisi bir kayıtlı konuma girdiğinde veya ayrıldığında partnere FCM bildirim gönderir
  void _checkMyPlaceNotifications(AppUser me) async {
    if (me.lat == null || me.lng == null) return;
    final myLat = me.lat!;
    final myLng = me.lng!;

    SavedPlace? matchedPlace;
    for (final p in _savedPlaces) {
      final dist = Geolocator.distanceBetween(myLat, myLng, p.lat, p.lng);
      if (dist <= 80) {
        matchedPlace = p;
        break;
      }
    }

    final newPlaceId = matchedPlace?.id;
    if (newPlaceId == _lastMyDetectedPlaceId) {
      return;
    }

    final oldPlaceId = _lastMyDetectedPlaceId;
    _lastMyDetectedPlaceId = newPlaceId;

    if (oldPlaceId == null && matchedPlace != null) {
      debugPrint('[GEOFENCE-SELF] İlk tespit: "${matchedPlace.title}" konumundasınız.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final partnerUid = ref.read(partnerUidProvider) ?? ref.read(partnerProvider)?.id;
    final myName = ref.read(userNameProvider).isNotEmpty ? ref.read(userNameProvider) : loc('Partnerin', 'Partner');
    final myUid = DatabaseService().uid ?? me.id;

    // 1. Yeni bir mekana vardık mı? (Partnere haber ver)
    if (matchedPlace != null) {
      final remoteNotifs = matchedPlace.notifications ?? {};
      final shouldNotifyEnter = 
          remoteNotifs['${myUid}_enter'] as bool? ??
          (partnerUid != null ? remoteNotifs['${partnerUid}_enter'] as bool? : null) ??
          remoteNotifs['my_enter'] as bool? ??
          remoteNotifs['partner_enter'] as bool? ??
          prefs.getBool('my_notify_enter_${matchedPlace.id}') ??
          prefs.getBool('partner_notify_enter_${matchedPlace.id}') ??
          prefs.getBool('notify_enter_${matchedPlace.id}') ?? true;

      if (shouldNotifyEnter && partnerUid != null && partnerUid.isNotEmpty) {
        final titleTr = '${matchedPlace.iconEmoji} $myName Konuma Ulaştı';
        final titleEn = '${matchedPlace.iconEmoji} $myName Arrived at Location';
        final bodyTr = '$myName "${matchedPlace.title}" konumuna vardı. 💕';
        final bodyEn = '$myName arrived at "${localizePlaceTitle(matchedPlace.title)}". 💕';
        NotificationService().sendPushToPartner(
          partnerUid: partnerUid,
          title: loc(titleTr, titleEn),
          body: loc(bodyTr, bodyEn),
          titleTr: titleTr,
          titleEn: titleEn,
          bodyTr: bodyTr,
          bodyEn: bodyEn,
        );
      }
    }

    // 2. Önceki mekandan ayrıldık mı? (Partnere haber ver)
    if (oldPlaceId != null) {
      final oldPlaceList = _savedPlaces.where((p) => p.id == oldPlaceId);
      if (oldPlaceList.isNotEmpty) {
        final oldPlace = oldPlaceList.first;
        final remoteNotifs = oldPlace.notifications ?? {};
        final shouldNotifyExit = 
            remoteNotifs['${myUid}_exit'] as bool? ??
            (partnerUid != null ? remoteNotifs['${partnerUid}_exit'] as bool? : null) ??
            remoteNotifs['my_exit'] as bool? ??
            remoteNotifs['partner_exit'] as bool? ??
            prefs.getBool('my_notify_exit_${oldPlace.id}') ??
            prefs.getBool('partner_notify_exit_${oldPlace.id}') ??
            prefs.getBool('notify_exit_${oldPlace.id}') ?? true;

        if (shouldNotifyExit && partnerUid != null && partnerUid.isNotEmpty) {
          final titleTr = '🚶 $myName Konumdan Ayrıldı';
          final titleEn = '🚶 $myName Left Location';
          final bodyTr = '$myName "${oldPlace.title}" konumundan ayrıldı.';
          final bodyEn = '$myName left "${localizePlaceTitle(oldPlace.title)}".';
          NotificationService().sendPushToPartner(
            partnerUid: partnerUid,
            title: loc(titleTr, titleEn),
            body: loc(bodyTr, bodyEn),
            titleTr: titleTr,
            titleEn: titleEn,
            bodyTr: bodyTr,
            bodyEn: bodyEn,
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _heartAnimController.dispose();
    _lifecycleListener?.dispose();
    _statusSyncTimer?.cancel();
    _widgetRefreshTimer?.cancel();
    _userSub?.cancel();
    _partnerSub?.cancel();
    _coupleSub?.cancel();
    _savedPlacesSub?.cancel();
    _milestonesSub?.cancel();
    _drawingSub?.cancel();
    super.dispose();
  }

  Future<void> _sendThought() async {
    HeartbeatHapticService().playSinglePulse();

    // 1. Ekrandaki kalbi her basışta anında ve pürüzsüzce yeniden patlat
    setState(() => _showHeart = true);
    _heartAnimController.forward(from: 0.0);

    final partnerUid = ref.read(partnerUidProvider) ?? ref.read(partnerProvider)?.id;
    final myName = ref.read(userNameProvider);

    if (partnerUid == null || partnerUid.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(loc('Henüz biriyle eşleşmedin. Önce partnerinle eşleşmelisin! 💕', 'You haven\'t paired with anyone yet. Pair with your partner first! 💕')),
                ),
              ],
            ),
            backgroundColor: LoveraColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            action: SnackBarAction(
              label: loc('Eşleş', 'Pair'),
              textColor: Colors.white,
              onPressed: () => _push(const PairingView()),
            ),
          ),
        );
      }
      return;
    }

    // 2. Karşı tarafa istek gönderimini 10 saniyede bire sınırla (throttle)
    final now = DateTime.now();
    if (_lastHeartSentTime != null && now.difference(_lastHeartSentTime!).inSeconds < 10) {
      debugPrint('[HEART] İstek 10 saniyelik limit içinde olduğu için bildirim sessizce filtrelendi.');
      return;
    }
    _lastHeartSentTime = now;

    await DatabaseService().sendHeart(partnerUid);
    final senderNameTr = myName.isEmpty ? 'Partnerin' : myName;
    final senderNameEn = myName.isEmpty ? 'Your partner' : myName;
    NotificationService().sendPushToPartner(
      partnerUid: partnerUid,
      title: loc('🥺 Seni Çok Özledim!', '🥺 I Miss You So Much!'),
      body: loc('$senderNameTr şu an seni çok özlediğini hissettirdi 💕', '$senderNameEn just sent you lots of love 💕'),
      titleTr: '🥺 Seni Çok Özledim!',
      titleEn: '🥺 I Miss You So Much!',
      bodyTr: '$senderNameTr şu an seni çok özlediğini hissettirdi 💕',
      bodyEn: '$senderNameEn just sent you lots of love 💕',
      data: {
        'type': 'heart_ping',
        'fromName': myName.isEmpty ? loc('Partnerin', 'Partner') : myName,
      },
    );
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = ref.watch(themePaletteProvider);
    final name = ref.watch(userNameProvider);
    final partner = ref.watch(partnerProvider);
    final start = ref.watch(startDateProvider);
    final milestones = ref.watch(milestonesProvider);

    return Scaffold(
      body: LoveraThemeBackground(
        child: Stack(
          children: [
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ref.watch(stringsProvider).greeting(name),
                            style: theme.textTheme.bodyMedium?.copyWith(color: LoveraColors.textMuted)),
                        const SizedBox(height: 2),
                        Text('Lovera',
                            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          onPressed: () => partner != null
                              ? _push(const CoupleManagementView())
                              : _push(const PairingView()),
                          icon: Icon(
                            partner != null ? Icons.favorite_rounded : Icons.qr_code_rounded,
                            color: partner != null ? palette.primary : null,
                          ),
                          tooltip: partner != null ? loc('Eş Yönetim Paneli', 'Couple Management Panel') : loc('Eşleşme', 'Pairing'),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: () => _push(const SettingsView()),
                          icon: const Icon(Icons.settings_outlined),
                          tooltip: loc('Ayarlar', 'Settings'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _HeroCounter(
                  start: start,
                  isPaired: ref.watch(coupleIdProvider) != null || ref.watch(partnerUidProvider) != null,
                  onPick: () {}, // Ana ekrandan değiştirilemez, Eş Yönetim Paneli'nden onaylı değiştirilir
                ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.08),
                const SizedBox(height: 14),
                _PartnerCard(
                  partner: partner,
                  isPaired: ref.watch(coupleIdProvider) != null || ref.watch(partnerUidProvider) != null,
                  savedPlaces: _savedPlaces,
                  onPair: () => _push(const PairingView()),
                  onBatteryTap: partner != null ? () => _openBatteryActionsSheet(partner) : null,
                  onWeatherTap: partner != null ? () => _openWeatherActionsSheet(partner) : null,
                  onOpenMap: widget.onOpenMap,
                )
                    .animate(delay: 120.ms)
                    .fadeIn(duration: 500.ms)
                    .slideY(begin: 0.08),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.map_rounded,
                        title: ref.watch(stringsProvider).liveMap,
                        subtitle: partner == null ? (ref.watch(stringsProvider).isEn ? 'Waiting for partner' : 'Eşleşme bekleniyor') : (ref.watch(stringsProvider).isEn ? 'View location' : 'Konumu gör'),
                        color: palette.primary,
                        onTap: () {
                          if (widget.onOpenMap != null) {
                            widget.onOpenMap!();
                          } else {
                            _push(const LiveMapView());
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.favorite_border_rounded,
                        title: ref.watch(stringsProvider).specialDays,
                        subtitle: milestones.isEmpty ? (ref.watch(stringsProvider).isEn ? 'None added yet' : 'Henüz eklenmedi') : '${milestones.length} ${ref.watch(stringsProvider).daysPlural}',
                        color: palette.secondary,
                        onTap: () => _push(const MilestonesView()),
                      ),
                    ),
                  ],
                ).animate(delay: 180.ms).fadeIn(duration: 500.ms).slideY(begin: 0.08),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.brush_rounded,
                        title: ref.watch(stringsProvider).drawTogether,
                        subtitle: ref.watch(stringsProvider).isEn ? 'Send drawing to widget' : 'Widget\'a çizim gönder',
                        color: palette.primary,
                        onTap: () => _push(const DrawingScreen()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.photo_library_rounded,
                        title: ref.watch(stringsProvider).memoriesAlbum,
                        subtitle: ref.watch(stringsProvider).isEn ? 'Your memories' : 'Birlikte anılarınız',
                        color: palette.secondary,
                        onTap: () => _push(const MemoriesGalleryView()),
                      ),
                    ),
                  ],
                ).animate(delay: 220.ms).fadeIn(duration: 500.ms).slideY(begin: 0.08),
                const SizedBox(height: 14),
                _ThinkingButton(onPressed: _sendThought)
                    .animate(delay: 260.ms)
                    .fadeIn(duration: 500.ms)
                    .slideY(begin: 0.08),
              ],
            ),
          ),
          if (_showHeart)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _heartAnimController,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _heartSlideAnim.value),
                        child: Transform.scale(
                          scale: _heartScaleAnim.value,
                          child: Opacity(
                            opacity: _heartOpacityAnim.value.clamp(0.0, 1.0),
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: Icon(
                      Icons.favorite_rounded,
                      size: 135,
                      color: LoveraColors.primarySoft,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
}

class _BentoCard extends StatelessWidget {
  const _BentoCard({required this.child, this.color, this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final Color? color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: theme.dividerColor),
        boxShadow: AppTheme.ambientShadow,
      ),
      child: child,
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: theme.dividerColor),
            boxShadow: AppTheme.ambientShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? LoveraColors.darkSurfaceAlt
                      : color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? color.withValues(alpha: 0.3)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 12),
              Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? LoveraColors.darkTextMuted
                        : LoveraColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCounter extends ConsumerStatefulWidget {
  const _HeroCounter({required this.start, required this.onPick, this.isPaired = false});
  final DateTime? start;
  final VoidCallback onPick;
  final bool isPaired;

  @override
  ConsumerState<_HeroCounter> createState() => _HeroCounterState();
}

class _HeroCounterState extends ConsumerState<_HeroCounter> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6);
    final cardColor = theme.brightness == Brightness.light ? LoveraColors.lightSurfaceAlt : null;

    if (widget.start == null) {
      if (widget.isPaired) {
        // Eşleşmiş bir hesap, ilk bağlantı anında boş sayaç butonu flaşlamasın
        return _BentoCard(
          color: cardColor,
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Icon(Icons.favorite_rounded, color: LoveraColors.primary, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(loc('Aşk Sayacı Yükleniyor...', 'Loading Love Counter...'),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(loc('Birlikte geçen süre hesaplanıyor 💕', 'Calculating time together 💕'),
                        style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  ],
                ),
              ),
            ],
          ),
        );
      }
      return InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: widget.onPick,
        child: _BentoCard(
          color: cardColor,
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Icon(Icons.event_available_rounded, color: LoveraColors.primary, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ref.watch(stringsProvider).dayCounter,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(ref.watch(stringsProvider).isEn ? 'Tap to choose your start date.' : 'Başlangıç tarihinizi seçmek için dokunun.',
                        style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final elapsed = DateTime.now().difference(widget.start!);
    final isLight = theme.brightness == Brightness.light;
    final palette = ref.watch(themePaletteProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: isLight
              ? palette.primary.withValues(alpha: 0.22)
              : palette.primary.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: isLight
            ? [
                BoxShadow(
                  color: palette.primary.withValues(alpha: 0.12),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
                ...AppTheme.ambientShadow,
              ]
            : [
                BoxShadow(
                  color: palette.primary.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
                ...AppTheme.ambientShadow,
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: isLight ? 0.12 : 0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite_rounded, size: 14, color: palette.primary),
                const SizedBox(width: 6),
                Text(
                  ref.watch(stringsProvider).isEn ? 'TIME SPENT TOGETHER' : 'BİRLİKTE GEÇEN ZAMAN',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: palette.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              ShaderMask(
                shaderCallback: (bounds) => palette.gradient.createShader(bounds),
                child: Text(
                  '${elapsed.inDays}',
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -1,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                elapsed.inDays == 1
                    ? ref.watch(stringsProvider).daysSingular
                    : ref.watch(stringsProvider).daysPlural,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isLight ? LoveraColors.textDark : LoveraColors.darkText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final _partnerClockProvider = StreamProvider.autoDispose<int>((ref) {
  return Stream.periodic(const Duration(seconds: 5), (count) => count);
});

class _PartnerCard extends ConsumerStatefulWidget {
  const _PartnerCard({
    required this.partner,
    this.isPaired = false,
    this.savedPlaces = const [],
    required this.onPair,
    this.onBatteryTap,
    this.onWeatherTap,
    this.onOpenMap,
  });
  final AppUser? partner;
  final bool isPaired;
  final List<SavedPlace> savedPlaces;
  final VoidCallback onPair;
  final VoidCallback? onBatteryTap;
  final VoidCallback? onWeatherTap;
  final VoidCallback? onOpenMap;

  @override
  ConsumerState<_PartnerCard> createState() => _PartnerCardState();
}

class _PartnerCardState extends ConsumerState<_PartnerCard> with SingleTickerProviderStateMixin {
  late final AnimationController _flipController;
  late final Animation<double> _flipAnimation;
  double _baseAngle = 0.0;
  bool _isBack = false;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _flipAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _flipController,
        curve: Curves.easeInOutCubicEmphasized,
      ),
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _flipCard() {
    if (_flipController.isAnimating) return;
    HapticFeedback.mediumImpact();

    // Kart her basışta sürekli sağ tarafa (saat yönünde, aynı yönde) 180 derece döner
    _baseAngle = _isBack ? math.pi : 0.0;
    _flipController.forward(from: 0.0).then((_) {
      if (mounted) {
        setState(() {
          _isBack = !_isBack;
        });
      }
    });
  }

  void _showEnlargedAvatar(BuildContext context, AppUser p) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.65),
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (ctx, anim, secondaryAnim) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(ctx).pop(),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Center(
                child: Hero(
                  tag: 'partner_avatar_${p.id}',
                  flightShuttleBuilder: (
                    flightContext,
                    animation,
                    flightDirection,
                    fromHeroContext,
                    toHeroContext,
                  ) {
                    final isPush = flightDirection == HeroFlightDirection.push;
                    final srcWidget = isPush ? fromHeroContext.widget : toHeroContext.widget;
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (context, child) {
                        return Material(
                          color: Colors.transparent,
                          child: srcWidget,
                        );
                      },
                    );
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: LoveraColors.primary.withValues(alpha: 0.35),
                            blurRadius: 32,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: LoveraAvatar(
                        avatarUrl: p.avatarUrl,
                        fallbackLetter: p.name,
                        radius: 130, // Ekranda büyük yuvarlak profil fotoğrafı
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        transitionsBuilder: (ctx, anim, secondaryAnim, child) {
          return FadeTransition(
            opacity: anim,
            child: child,
          );
        },
      ),
    );
  }

  bool _isOnline(AppUser p) {
    if (p.isAppOpen != true) return false;
    if (p.lastActive == null) return true;
    final diff = DateTime.now().toUtc().difference(p.lastActive!.toUtc()).abs();
    return diff.inSeconds < 120; // 2 dakikadan uzun süre sinyal yoksa açık kalmış sayılmaz
  }

  /// Partner cihazının interneti açık mı ve Lovera ile bağlantı kurulabiliyor mu?
  bool _hasInternet(AppUser p) {
    if (_isOnline(p)) return true;
    final now = DateTime.now().toUtc();
    if (p.lastNetPing != null) {
      final diff = now.difference(p.lastNetPing!.toUtc()).abs();
      if (diff.inSeconds < 75) return true;
    }
    if (p.lastActive != null) {
      final diff = now.difference(p.lastActive!.toUtc()).abs();
      if (diff.inSeconds < 75) return true;
    }
    return false;
  }

  /// Partnerin anlık durumunu belirler: Kayıtlı yer (Ev, İş vb.) > Arabada > Yürüyor / Koşuyor
  Map<String, dynamic>? _getMovementOrPlaceStatus(AppUser p, WidgetRef ref) {
    // 1. Koordinat kontrolü: Şu an kayıtlı bir yerde mi? (<= 45m)
    if (p.lat != null && p.lng != null && widget.savedPlaces.isNotEmpty) {
      for (final place in widget.savedPlaces) {
        final dist = Geolocator.distanceBetween(p.lat!, p.lng!, place.lat, place.lng);
        if (dist <= 45) {
          final strings = ref.watch(stringsProvider);
          return {
            'emoji': place.iconEmoji,
            'title': strings.translatePlaceTitle(place.title),
            'color': const Color(0xFF10B981),
            'bgColor': const Color(0xFF10B981).withValues(alpha: 0.14),
          };
        }
      }
    }

    // 2. Hareket tespiti: Normal insan yürüyüşü -> Yürüyor, Araba hızı -> Arabada
    final speedKmH = (p.speed != null) ? p.speed! * 3.6 : 0.0;
    if (speedKmH >= 20.0) {
      return {
        'emoji': '🚗',
        'title': ref.watch(stringsProvider).isEn ? 'In Car' : 'Arabada',
        'color': const Color(0xFF388AF6),
        'bgColor': const Color(0xFF388AF6).withValues(alpha: 0.14),
      };
    } else if (speedKmH >= 1.5) {
      return {
        'emoji': '🚶',
        'title': ref.watch(stringsProvider).isEn ? 'Walking' : 'Yürüyor',
        'color': const Color(0xFFF59E0B),
        'bgColor': const Color(0xFFF59E0B).withValues(alpha: 0.14),
      };
    }

    // 3. Eğer hiçbir kayıtlı yerde değilse ve hareket etmiyorsa (Dünya standartlarında "Dışarıda")
    if (p.lat != null && p.lng != null) {
      return {
        'emoji': '📍',
        'title': ref.watch(stringsProvider).isEn ? 'Outdoors' : 'Dışarıda',
        'color': LoveraColors.primary,
        'bgColor': LoveraColors.primary.withValues(alpha: 0.14),
      };
    }

    // 4. Konum koordinatı hiç yoksa (eski veri kalıntısı)
    if (p.currentPlaceTitle != null && p.currentPlaceTitle!.isNotEmpty) {
      final strings = ref.watch(stringsProvider);
      return {
        'emoji': (p.currentPlaceEmoji != null && p.currentPlaceEmoji!.isNotEmpty) ? p.currentPlaceEmoji! : '📍',
        'title': strings.translatePlaceTitle(p.currentPlaceTitle!),
        'color': const Color(0xFF10B981),
        'bgColor': const Color(0xFF10B981).withValues(alpha: 0.14),
      };
    }

    return null;
  }

  String _lastSeen(AppUser p, WidgetRef ref) {
    if (_isOnline(p)) {
      return ref.watch(stringsProvider).lastSeenJustNow;
    }
    if (p.lastActive == null) return ref.watch(stringsProvider).isEn ? 'Offline' : 'Çevrimdışı';
    final diff = DateTime.now().toUtc().difference(p.lastActive!.toUtc()).abs();
    if (diff.inMinutes < 1) return ref.watch(stringsProvider).isEn ? 'Active 1m ago' : '1 dk önce aktifti';
    if (diff.inMinutes < 60) return ref.watch(stringsProvider).isEn ? 'Active ${diff.inMinutes}m ago' : '${diff.inMinutes} dk önce aktifti';
    if (diff.inHours < 24) return ref.watch(stringsProvider).isEn ? 'Active ${diff.inHours}h ago' : '${diff.inHours} sa önce aktifti';
    return ref.watch(stringsProvider).isEn ? 'Active ${diff.inDays}d ago' : '${diff.inDays} gün önce aktifti';
  }

  Color _batteryColor(int? level) {
    if (level == null) return LoveraColors.secondary;
    if (level >= 80) return const Color(0xFF10B981); // Yeşil
    if (level >= 50) return const Color(0xFF34D399); // Açık yeşil
    if (level >= 30) return const Color(0xFFFBBF24); // Sarı / Amber
    if (level >= 15) return const Color(0xFFF97316); // Turuncu
    return const Color(0xFFEF4444); // Kırmızı
  }

  IconData _batteryIcon(int? level) {
    if (level == null) return Icons.battery_unknown_rounded;
    if (level >= 95) return Icons.battery_full_rounded;
    if (level >= 85) return Icons.battery_6_bar_rounded;
    if (level >= 70) return Icons.battery_5_bar_rounded;
    if (level >= 50) return Icons.battery_4_bar_rounded;
    if (level >= 30) return Icons.battery_3_bar_rounded;
    if (level >= 20) return Icons.battery_2_bar_rounded;
    if (level >= 10) return Icons.battery_1_bar_rounded;
    return Icons.battery_alert_rounded;
  }

  @override
  Widget build(BuildContext context) {
    // Kartın internet ve süre durumunu her 5 saniyede bir yerel saat ile canlı hesapla
    ref.watch(_partnerClockProvider);

    final theme = Theme.of(context);
    final p = widget.partner;

    if (p == null) {
      if (widget.isPaired) {
        // Kullanıcı eşleşmiş ama Firestore ilk paketi çekiyor (~200ms); "Bağlı değil" flaşlaması YAPMA!
        return _BentoCard(
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: LoveraColors.primary.withValues(alpha: 0.15),
                child: Icon(Icons.favorite_rounded, color: LoveraColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(loc('Partneriniz bağlanıyor...', 'Connecting to partner...'),
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(loc('Bilgiler güncelleniyor 💕', 'Updating info 💕'),
                        style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        );
      }
      return _BentoCard(
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: LoveraColors.secondary.withValues(alpha: 0.25),
              child: Icon(Icons.person_add_alt_1_rounded, color: LoveraColors.secondary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ref.watch(stringsProvider).waitingForPartner,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(ref.watch(stringsProvider).connectPartnerPrompt,
                      style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted)),
                ],
              ),
            ),
            TextButton(onPressed: widget.onPair, child: Text(ref.watch(stringsProvider).pairNow)),
          ],
        ),
      );
    }

    final batColor = _batteryColor(p.batteryLevel);
    final batIcon = _batteryIcon(p.batteryLevel);
    final dynamicStatus = _getMovementOrPlaceStatus(p, ref);

    final ghostFrontCard = _buildFrontCard(theme, p, batIcon, batColor, dynamicStatus, isGhost: true);
    final frontCard = _buildFrontCard(theme, p, batIcon, batColor, dynamicStatus);
    final backCard = _buildBackCard(theme, p);

    return AnimatedBuilder(
      animation: _flipAnimation,
      builder: (context, child) {
        // Her tıklandığında kesintisiz olarak sağa doğru 180 derece döner
        final currentAngle = _baseAngle + (_flipAnimation.value * math.pi);
        // Normalize açı: 0..pi arası ön yüz, pi..2pi arası arka yüz
        final normalized = currentAngle % (2 * math.pi);
        final isFrontSide = normalized < (math.pi / 2) || normalized > (1.5 * math.pi);

        // Stack ile ön yüzü ağaçta tutup yüksekliği onun belirlemesini sağlıyoruz.
        // Böylece kart dönerken veya arkası açıkken yükseklik 1 piksel dahi değişmez,
        // alttaki butonları asla aşağı itmez veya yukarı çekmez!
        return Stack(
          children: [
            // Boyut sabitleyici (Görünmez ön yüz, tam yüksekliği Layout'a dikte eder)
            Opacity(
              opacity: 0.0,
              child: IgnorePointer(
                child: ghostFrontCard,
              ),
            ),
            // Dönen 3D kart (Positioned.fill ile ön yüzün kapladığı alana sıfıra sıfır oturur)
            Positioned.fill(
              child: Transform(
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0015) // Derinlik / Perspektif efekti
                  ..rotateY(currentAngle),
                alignment: Alignment.center,
                child: isFrontSide
                    ? frontCard
                    : Transform(
                        transform: Matrix4.identity()..rotateY(math.pi),
                        alignment: Alignment.center,
                        child: backCard,
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFrontCard(
    ThemeData theme,
    AppUser p,
    IconData batIcon,
    Color batColor,
    Map<String, dynamic>? dynamicStatus, {
    bool isGhost = false,
  }) {
    final avatarWidget = LoveraAvatar(
      avatarUrl: p.avatarUrl,
      fallbackLetter: p.name,
      radius: 28,
    );

    // Kartın ön yüzünde sadece isim (birden fazla isim varsa adlar, soyadı hariç)
    final displayName = () {
      if (p.firstName != null && p.firstName!.trim().isNotEmpty) {
        return p.firstName!.trim();
      }
      final clean = p.name.trim();
      if (!clean.contains(' ')) return clean;
      final parts = clean.split(RegExp(r'\s+'));
      if (parts.length > 2) {
        return parts.sublist(0, parts.length - 1).join(' ');
      }
      return parts.first;
    }();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _flipCard,
      child: _BentoCard(
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => _showEnlargedAvatar(context, p),
                  child: isGhost
                      ? avatarWidget
                      : Hero(
                          tag: 'partner_avatar_${p.id}',
                          child: avatarWidget,
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
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (p.city != null && p.city!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: LoveraColors.secondary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.location_on_rounded, size: 11, color: LoveraColors.secondary),
                                  const SizedBox(width: 3),
                                  Text(
                                    p.city!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: LoveraColors.secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Builder(
                        builder: (_) {
                          final online = _isOnline(p);
                          final hasNet = _hasInternet(p);
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // İnternet Durum İkonu (Wifi / Mobil Veri / Çevrimdışı)
                              Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: hasNet
                                      ? const Color(0xFF10B981).withValues(alpha: 0.16)
                                      : Colors.grey.withValues(alpha: 0.16),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  hasNet ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                                  size: 16,
                                  color: hasNet ? const Color(0xFF10B981) : LoveraColors.textMuted,
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (online) ...[
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF10B981).withValues(alpha: 0.6),
                                        blurRadius: 6,
                                        spreadRadius: 1.5,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  ref.watch(stringsProvider).lastSeenJustNow,
                                  style: const TextStyle(
                                    color: Color(0xFF10B981),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ] else
                                Text(
                                  _lastSeen(p, ref),
                                  style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted, fontSize: 11.5),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // Sağ Üst Alan: Kayıtlı Yer Rozeti veya Hareket (Yürüyor / Arabada) Rozeti
                if (dynamicStatus != null) ...[
                  const SizedBox(width: 6),
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        ref.read(focusPartnerOnMapProvider.notifier).state++;
                        if (widget.onOpenMap != null) {
                          widget.onOpenMap!();
                        } else {
                          ref.read(activeNavigationIndexProvider.notifier).state = 0;
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: dynamicStatus['bgColor'] as Color,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: (dynamicStatus['color'] as Color).withValues(alpha: 0.35),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              dynamicStatus['emoji'] as String,
                              style: const TextStyle(fontSize: 15),
                            ),
                            const SizedBox(width: 5),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 115),
                              child: Text(
                                dynamicStatus['title'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: dynamicStatus['color'] as Color,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    icon: batIcon,
                    label: ref.watch(stringsProvider).batteryLevel,
                    value: p.batteryLevel == null ? '-' : '%${p.batteryLevel}',
                    color: batColor,
                    onTap: widget.onBatteryTap,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Stat(
                    icon: (p.weather ?? '').contains('Gece') ||
                            (p.weather ?? '').contains('Akşam') ||
                            DateTime.now().hour >= 20 ||
                            DateTime.now().hour < 6
                        ? Icons.nights_stay_rounded
                        : Icons.wb_sunny_rounded,
                    label: p.city != null && p.city!.isNotEmpty ? p.city! : (ref.watch(stringsProvider).isEn ? 'Weather' : 'Hava Durumu'),
                    value: (p.weather != null && p.weather!.isNotEmpty)
                        ? localizeWeather(p.weather)
                        : (ref.watch(stringsProvider).isEn ? 'Fetching weather...' : 'Hava durumu alınıyor...'),
                    color: LoveraColors.accentGold,
                    onTap: widget.onWeatherTap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackCard(ThemeData theme, AppUser p) {
    final isDark = theme.brightness == Brightness.dark;
    final imageProvider = AvatarCache.getProvider(p.avatarUrl);

    // İsim - Soyisim ayrımı (varsa kaydedilmiş firstName & lastName, yoksa akıllı ayrıştırma)
    final String firstName;
    final String lastName;
    if (p.firstName != null && p.firstName!.trim().isNotEmpty) {
      firstName = p.firstName!.trim();
      lastName = (p.lastName != null && p.lastName!.trim().isNotEmpty) ? p.lastName!.trim() : '-';
    } else {
      final nameParts = p.name.trim().split(RegExp(r'\s+'));
      if (nameParts.length > 2) {
        firstName = nameParts.sublist(0, nameParts.length - 1).join(' ');
        lastName = nameParts.last;
      } else if (nameParts.length == 2) {
        firstName = nameParts.first;
        lastName = nameParts.last;
      } else {
        firstName = nameParts.isNotEmpty ? nameParts.first : p.name;
        lastName = '-';
      }
    }

    // Nereli bilgisi (hometown boşsa anlık şehir veya -)
    final hometownText = (p.hometown != null && p.hometown!.trim().isNotEmpty)
        ? p.hometown!.trim()
        : (p.city != null && p.city!.trim().isNotEmpty ? p.city!.trim() : '-');

    // Doğum tarihi formatı (DD.MM.YYYY)
    String birthDateText = '-';
    if (p.birthDate != null && p.birthDate!.isNotEmpty) {
      final parts = p.birthDate!.split('-');
      if (parts.length == 3) {
        birthDateText = '${parts[2]}.${parts[1]}.${parts[0]}';
      } else {
        birthDateText = p.birthDate!;
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _flipCard,
      child: _BentoCard(
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Kare Şeklinde Profil Fotoğrafı
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: isDark ? LoveraColors.darkSurfaceAlt : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: LoveraColors.primary.withValues(alpha: 0.35),
                          width: 2.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: imageProvider != null
                            ? Image(
                                image: imageProvider,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                errorBuilder: (_, __, ___) => _buildSquareFallback(p, isDark),
                              )
                            : _buildSquareFallback(p, isDark),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // 2x2 Grid Düzeninde Kimlik Bilgileri: Adı, Soyadı, Memleket, Doğum Tarihi
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              // ADI
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      loc('ADI', 'FIRST NAME'),
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                        color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      firstName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // SOYADI
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      loc('SOYADI', 'LAST NAME'),
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                        color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      lastName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              // NERELİ
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      loc('MEMLEKET', 'HOMETOWN'),
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                        color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      hometownText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // DOĞUM TARİHİ
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      loc('DOĞUM TARİHİ', 'DATE OF BIRTH'),
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                        color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      birthDateText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 4),
              // Alt Bilgi Notu
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.touch_app_rounded, size: 12, color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    loc('Ön yüze dönmek için dokunun', 'Tap to flip back'),
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSquareFallback(AppUser p, bool isDark) {
    return Container(
      color: LoveraColors.primary.withValues(alpha: 0.15),
      child: Center(
        child: Text(
          p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: LoveraColors.primary,
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value, required this.color, this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? LoveraColors.darkSurfaceAlt : color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? color.withValues(alpha: 0.25) : Colors.transparent,
              width: 1,
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icon, color: color, size: 22),
                    if (onTap != null)
                      Icon(
                        Icons.chevron_right_rounded,
                        color: isDark ? LoveraColors.darkTextMuted.withValues(alpha: 0.6) : color.withValues(alpha: 0.5),
                        size: 18,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(label, style: theme.textTheme.bodySmall?.copyWith(color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted)),
                Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThinkingButton extends ConsumerWidget {
  const _ThinkingButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = ref.watch(themePaletteProvider);

    return Container(
      decoration: BoxDecoration(
        gradient: palette.gradient,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: [
          BoxShadow(
            color: palette.primary.withValues(alpha: isDark ? 0.35 : 0.28),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.favorite_rounded, color: Colors.white, size: 24)
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(end: const Offset(1.25, 1.25), duration: 800.ms),
                const SizedBox(width: 12),
                Text(
                  ref.watch(stringsProvider).isEn ? 'Thinking of You 💕' : 'Özledim 💕',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
