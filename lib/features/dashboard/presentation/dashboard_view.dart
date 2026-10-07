import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/models.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/device_service.dart';
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

class DashboardView extends ConsumerStatefulWidget {
  const DashboardView({super.key});

  @override
  ConsumerState<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends ConsumerState<DashboardView> {
  bool _showHeart = false;
  StreamSubscription? _userSub;
  StreamSubscription? _partnerSub;
  StreamSubscription? _coupleSub;
  Timer? _statusSyncTimer;
  int? _lastHeartTimestamp;
  int? _lastChargeTimestamp;
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
        title: const Row(
          children: [
            Icon(Icons.phone_android_rounded, color: Colors.orangeAccent),
            SizedBox(width: 8),
            Text('Oturum Kapatıldı'),
          ],
        ),
        content: const Text(
          'Hesabınıza başka bir cihazdan giriş yapıldı. Konum ve bildirim karışıklığını önlemek için bu cihazdaki oturumunuz kapatıldı.',
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
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final startupTime = DateTime.now().millisecondsSinceEpoch;
    _lastHeartTimestamp = startupTime;
    _lastChargeTimestamp = startupTime;

    // Snap Map Modeli: Canlı konum, şarj, şehir ve hava durumu arka planda da kesintisiz çalışsın
    DeviceService().startContinuousLocationTracking();
    NotificationService().updateFcmTokenInFirestore();

    // İlk açılışta uygulamada olduğumuzu bildir
    DatabaseService().setAppPresence(true);

    // Periyodik olarak hem uygulamada olduğumuzu bildir hem de partnerin durumunu tazele
    _statusSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      DatabaseService().setAppPresence(true);
      final pUid = ref.read(partnerUidProvider);
      if (pUid != null && pUid.isNotEmpty) {
        NotificationService().requestPartnerStatusSync(pUid);
      }
      DeviceService().syncStatusToFirebase();
    });

    // Uygulama alta atıldığında veya kapatılmak üzereyken durumu güncelle
    _lifecycleListener = AppLifecycleListener(
      onPause: () {
        DatabaseService().setAppPresence(false);
        DeviceService().syncStatusToFirebase();
      },
      onInactive: () {
        DatabaseService().setAppPresence(false);
        DeviceService().syncStatusToFirebase();
      },
      onHide: () {
        DatabaseService().setAppPresence(false);
        DeviceService().syncStatusToFirebase();
      },
      onResume: () {
        DatabaseService().setAppPresence(true);
        DeviceService().syncStatusToFirebase();
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 1. Kendi profilimizi dinle
      _userSub = DatabaseService().userStream()?.listen((doc) async {
        if (!doc.exists || doc.data() == null || !mounted || _isKicked) return;
        final data = doc.data()!;

        // Tek aktif cihaz oturumu kontrolü: Eğer hesaba başka bir cihaz bağlandıysa bu cihazı düşür!
        final remoteDeviceId = data['currentDeviceId'] as String?;
        if (remoteDeviceId != null && remoteDeviceId.isNotEmpty) {
          final myDeviceId = await DeviceService().getOrCreateDeviceId();
          if (remoteDeviceId != myDeviceId) {
            _handleKickedByOtherDevice();
            return;
          }
        }

        SharedPreferences.getInstance().then((p) => p.setString('saved_uid', doc.id));
        if (data['name'] != null && data['name'].toString().isNotEmpty) {
          ref.read(userNameProvider.notifier).state = data['name'];
        } else {
          // Eğer Firestore'daki isim boşsa yerel hafızadaki ismi Firestore'a eşitle
          final currentName = ref.read(userNameProvider);
          if (currentName.isNotEmpty) {
            DatabaseService().updateUserName(currentName);
          }
        }
        if (data['avatarUrl'] != null) {
          ref.read(userAvatarProvider.notifier).state = data['avatarUrl'];
        }
        ref.read(currentUserProvider.notifier).state = AppUser(
          id: doc.id,
          name: data['name'] ?? ref.read(userNameProvider),
          avatarUrl: data['avatarUrl'],
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
        );
        if (data['coupleId'] != null) {
          final cId = data['coupleId'] as String;
          if (data['birthDate'] != null) {
            DatabaseService().syncBirthdayMilestone(
              targetUserId: doc.id,
              userName: data['name'] ?? ref.read(userNameProvider),
              birthDateStr: data['birthDate'],
              coupleId: cId,
            );
          }
          if (cId != ref.read(coupleIdProvider)) {
            ref.read(coupleIdProvider.notifier).state = cId;
            _listenToCouple(cId);
          }
        } else if (data['relationshipStartDate'] != null) {
          ref.read(startDateProvider.notifier).state =
              DateTime.tryParse(data['relationshipStartDate']);
        }

        // Bize partnerden tarih değiştirme isteği geldi mi?
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
          if (res['status'] == 'accepted') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Partneriniz tarih değişikliğini kabul etti! Sayaç güncellendi. 💕'),
                backgroundColor: LoveraColors.secondary,
              ),
            );
          } else if (res['status'] == 'rejected') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Partneriniz tarih değişikliğini kabul etmedi.')),
            );
          }
        }

        // Bize partner kalp gönderdiyse ekranda büyük kalp animasyonu patlat!
        if (data['heartPing'] != null) {
          final ping = Map<String, dynamic>.from(data['heartPing']);
          final ts = ping['timestamp'] as int?;
          if (ts != null && (_lastHeartTimestamp == null || ts > _lastHeartTimestamp!)) {
            _lastHeartTimestamp = ts;
            DatabaseService().clearHeartPing();
            _receiveHeartPulse();
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
        if (partnerUid != null && partnerUid != ref.read(partnerUidProvider)) {
          ref.read(partnerUidProvider.notifier).state = partnerUid;
          _listenToPartner(partnerUid);
          // Partnerin telefonu kapalıysa bile arka planda hemen şarj ve konumunu güncellemesi için sessiz uyandır
          NotificationService().requestPartnerStatusSync(partnerUid);
        }
      });
    });
  }

  bool _dateDialogOpen = false;

  StreamSubscription? _milestonesSub;

  void _listenToMilestones(String? coupleId) {
    _milestonesSub?.cancel();
    _milestonesSub = DatabaseService().milestonesStream(coupleId: coupleId).listen((items) {
      if (!mounted) return;
      ref.read(milestonesProvider.notifier).state = items;
    });
  }

  void _listenToCouple(String coupleId) {
    _coupleSub?.cancel();
    _listenToMilestones(coupleId);
    _coupleSub = DatabaseService().coupleStream(coupleId)?.listen((doc) {
      if (!doc.exists || doc.data() == null || !mounted) return;
      final cData = doc.data()!;
      if (cData['relationshipStartDate'] != null) {
        final date = DateTime.tryParse(cData['relationshipStartDate']);
        ref.read(startDateProvider.notifier).state = date;
        if (date != null) {
          DatabaseService().syncDefaultAnniversary(date, coupleId: coupleId);
        }
      }
    });
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
            const Icon(Icons.edit_calendar_rounded, color: LoveraColors.primary),
            const SizedBox(width: 10),
            Text('$requesterName Tarihi Değiştirmek İstiyor', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$requesterName aşk sayacınızın başlangıç tarihini şu şekilde güncellemek istiyor:',
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
                      const Text('ÖNERİLEN TARİH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: LoveraColors.textMuted)),
                      Text('${proposedDate.day}.${proposedDate.month}.${proposedDate.year}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: LoveraColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('$days Gün', style: const TextStyle(color: LoveraColors.primary, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('Onayladığınızda iki telefonun ekranındaki sayaç da bu tarihe göre güncellenecektir.', style: TextStyle(fontSize: 12, color: LoveraColors.textMuted)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _dateDialogOpen = false;
              await DatabaseService().rejectDateChange(partnerUid);
            },
            child: const Text('Reddet'),
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
            child: const Text('Kabul Et'),
          ),
        ],
      ),
    ).then((_) => _dateDialogOpen = false);
  }

  void _receiveHeartPulse() {
    HapticFeedback.heavyImpact();
    setState(() => _showHeart = true);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _showHeart = false);
    });
  }

  void _receiveChargeReminder(String fromName) {
    HapticFeedback.mediumImpact();
    NotificationService().show(
      id: 101,
      title: '🔋 Şarj Hatırlatması!',
      body: '$fromName şarjını doldurmanı hatırlatıyor 💕',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.battery_charging_full_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$fromName şarjını doldurmanı hatırlatıyor! 💕🔋',
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
                '${partner.name}\'in Şarj Durumu',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '%$level · ${_getBatteryStatusText(level)}',
                style: TextStyle(
                  color: batteryColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Partnerinizin cihaz şarj seviyesi arka planda otomatik olarak güncellenir.',
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
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.bolt_rounded, size: 22),
                  label: const Text(
                    'Şarjını Doldur Hatırlatması Gönder ⚡',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
                        title: '🔋 Şarj Hatırlatması!',
                        body: '$senderName şarjını doldurmanı hatırlatıyor 💕',
                      );
                    }
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${partner.name}\'in telefonuna "Şarjını Doldur" hatırlatması gönderildi! 🔋⚡',
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
              // İptal Butonu
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Kapat'),
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
    final weatherText = partner.weather ?? 'Açık';
    final cityText = partner.city ?? 'İstanbul';

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
                child: const Center(
                  child: Icon(
                    Icons.wb_sunny_rounded,
                    size: 38,
                    color: LoveraColors.accentGold,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '${partner.name}\'in Hava Durumu',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '$cityText · $weatherText',
                style: const TextStyle(
                  color: LoveraColors.accentGold,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Partnerine hava durumuna özel tatlı bir ilgi ve bakım hatırlatması gönder:',
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
                  label: const Text(
                    'Hava Soğuk, Sıkı Giyin Bitirtanem ❄️',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () => _sendCareNotification(
                    partner: partner,
                    title: '🧣 Hava Soğuk, Sıkı Giyin!',
                    body: '${ref.read(userNameProvider).isEmpty ? 'Partnerin' : ref.read(userNameProvider)}: "Hava soğuk aşkım, sakın üşütme sıkı giyin 💕"',
                  ),
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
                  label: const Text(
                    'Yanına Şemsiye Al Aşkım 🌧️',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () => _sendCareNotification(
                    partner: partner,
                    title: '☂️ Yanına Şemsiye Al!',
                    body: '${ref.read(userNameProvider).isEmpty ? 'Partnerin' : ref.read(userNameProvider)}: "Aşkım dışarısı yağışlı olabilir, yanına şemsiye almayı unutma 🌧️"',
                  ),
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
                  label: const Text(
                    'Güneş Çarpmasın, Bol Su İç 💧',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () => _sendCareNotification(
                    partner: partner,
                    title: '💧 Bol Su İçmeyi Unutma!',
                    body: '${ref.read(userNameProvider).isEmpty ? 'Partnerin' : ref.read(userNameProvider)}: "Bugün bol bol su iç aşkım, kendine çok iyi bak ☀️"',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Kapat Butonu
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Kapat'),
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
  }) async {
    Navigator.pop(context);
    HapticFeedback.mediumImpact();
    final partnerUid = ref.read(partnerUidProvider);
    if (partnerUid != null && partnerUid.isNotEmpty) {
      await NotificationService().sendPushToPartner(
        partnerUid: partnerUid,
        title: title,
        body: body,
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${partner.name}\'in telefonuna bildirim gönderildi! 💕'),
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

  static String _getBatteryStatusText(int? level) {
    if (level == null) return 'Bilinmiyor';
    if (level >= 90) return 'Dopdolu';
    if (level >= 50) return 'Yeterli Seviyede';
    if (level >= 25) return 'Azalıyor';
    if (level >= 15) return 'Düşük Pil';
    return 'Kritik Seviyede!';
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

      final partnerUser = AppUser(
        id: doc.id,
        name: data['name'] ?? 'Partnerin',
        avatarUrl: data['avatarUrl'],
        batteryLevel: data['batteryLevel'] as int?,
        weather: cleanWeather,
        city: data['city'],
        lat: (data['lat'] as num?)?.toDouble(),
        lng: (data['lng'] as num?)?.toDouble(),
        lastActive: data['lastActive'] != null
            ? (data['lastActive'] as dynamic).toDate?.call() ?? DateTime.now()
            : DateTime.now(),
        coupleId: data['coupleId'],
        isAppOpen: data['isAppOpen'] as bool?,
        birthDate: data['birthDate'] as String?,
      );
      ref.read(partnerProvider.notifier).state = partnerUser;

      final coupleId = ref.read(coupleIdProvider) ?? data['coupleId'] as String?;
      if (coupleId != null && data['birthDate'] != null) {
        DatabaseService().syncBirthdayMilestone(
          targetUserId: doc.id,
          userName: data['name'] ?? 'Partner',
          birthDateStr: data['birthDate'],
          coupleId: coupleId,
        );
      }
      
      // Eğer partner ilişki tarihini güncellemişse bize de yansısın
      if (data['relationshipStartDate'] != null) {
        ref.read(startDateProvider.notifier).state =
            DateTime.tryParse(data['relationshipStartDate']);
      }
    });
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    _statusSyncTimer?.cancel();
    _userSub?.cancel();
    _partnerSub?.cancel();
    _coupleSub?.cancel();
    _milestonesSub?.cancel();
    super.dispose();
  }

  Future<void> _sendThought() async {
    HapticFeedback.mediumImpact();
    final partnerUid = ref.read(partnerUidProvider);
    final myName = ref.read(userNameProvider);
    await DatabaseService().sendHeart(partnerUid);
    if (partnerUid != null && partnerUid.isNotEmpty) {
      NotificationService().sendPushToPartner(
        partnerUid: partnerUid,
        title: '🥺 Seni Çok Özledim!',
        body: '${myName.isEmpty ? 'Partnerin' : myName} şu an seni çok özlediğini hissettirdi 💕',
      );
    }
    setState(() => _showHeart = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _showHeart = false);
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = ref.watch(userNameProvider);
    final partner = ref.watch(partnerProvider);
    final start = ref.watch(startDateProvider);
    final milestones = ref.watch(milestonesProvider);

    return Scaffold(
      body: Stack(
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
                        Text(name.isEmpty ? 'Merhaba 👋' : 'Merhaba $name 👋',
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
                            color: partner != null ? LoveraColors.primary : null,
                          ),
                          tooltip: partner != null ? 'Eş Yönetim Paneli' : 'Eşleşme',
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: () => _push(const SettingsView()),
                          icon: const Icon(Icons.settings_outlined),
                          tooltip: 'Ayarlar',
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _HeroCounter(
                  start: start,
                  onPick: () {}, // Ana ekrandan değiştirilemez, Eş Yönetim Paneli'nden onaylı değiştirilir
                ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.08),
                const SizedBox(height: 14),
                _PartnerCard(
                  partner: partner,
                  onPair: () => _push(const PairingView()),
                  onBatteryTap: partner != null ? () => _openBatteryActionsSheet(partner) : null,
                  onWeatherTap: partner != null ? () => _openWeatherActionsSheet(partner) : null,
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
                        title: 'Canlı Harita',
                        subtitle: partner == null ? 'Eşleşme bekleniyor' : 'Konumu gör',
                        color: LoveraColors.accentViolet,
                        onTap: () => _push(const LiveMapView()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.favorite_border_rounded,
                        title: 'Özel Günler',
                        subtitle: milestones.isEmpty ? 'Henüz eklenmedi' : '${milestones.length} gün',
                        color: LoveraColors.accentGold,
                        onTap: () => _push(const MilestonesView()),
                      ),
                    ),
                  ],
                ).animate(delay: 180.ms).fadeIn(duration: 500.ms).slideY(begin: 0.08),
                const SizedBox(height: 12),
                _ActionTile(
                  icon: Icons.photo_library_rounded,
                  title: 'Ortak Anı Albümü',
                  subtitle: 'Birlikte biriktirdiğiniz eşsiz anılar',
                  color: LoveraColors.secondary,
                  onTap: () => _push(const MemoriesGalleryView()),
                ).animate(delay: 220.ms).fadeIn(duration: 500.ms).slideY(begin: 0.08),
                const SizedBox(height: 20),
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
                  child: const Icon(Icons.favorite_rounded, size: 120, color: LoveraColors.primarySoft)
                      .animate()
                      .scale(
                          begin: const Offset(0.3, 0.3),
                          end: const Offset(1.1, 1.1),
                          duration: 500.ms,
                          curve: Curves.elasticOut)
                      .fadeIn(duration: 200.ms)
                      .then(delay: 500.ms)
                      .fadeOut(duration: 400.ms)
                      .moveY(end: -60, duration: 400.ms),
                ),
              ),
            ),
        ],
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

class _HeroCounter extends StatefulWidget {
  const _HeroCounter({required this.start, required this.onPick});
  final DateTime? start;
  final VoidCallback onPick;

  @override
  State<_HeroCounter> createState() => _HeroCounterState();
}

class _HeroCounterState extends State<_HeroCounter> {
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
      return InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: widget.onPick,
        child: _BentoCard(
          color: cardColor,
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              const Icon(Icons.event_available_rounded, color: LoveraColors.primary, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Birlikte geçen süre',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Başlangıç tarihinizi seçmek için dokunun.',
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: isLight
              ? LoveraColors.primary.withValues(alpha: 0.15)
              : LoveraColors.primary.withValues(alpha: 0.2),
          width: 1.2,
        ),
        boxShadow: isLight
            ? [
                BoxShadow(
                  color: LoveraColors.primary.withValues(alpha: 0.06),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
                ...AppTheme.ambientShadow,
              ]
            : AppTheme.ambientShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: LoveraColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.favorite_rounded, size: 14, color: LoveraColors.primary),
                const SizedBox(width: 6),
                Text(
                  'BİRLİKTE GEÇEN ZAMAN',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: LoveraColors.primary,
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
              Text(
                '${elapsed.inDays}',
                style: theme.textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: LoveraColors.primary,
                  letterSpacing: -1,
                  height: 1,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'gün',
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

class _PartnerCard extends StatelessWidget {
  const _PartnerCard({
    required this.partner,
    required this.onPair,
    this.onBatteryTap,
    this.onWeatherTap,
  });
  final AppUser? partner;
  final VoidCallback onPair;
  final VoidCallback? onBatteryTap;
  final VoidCallback? onWeatherTap;

  bool _isOnline(AppUser p) {
    if (p.isAppOpen != true) return false;
    if (p.lastActive == null) return false;
    final d = DateTime.now().difference(p.lastActive!);
    return d.inMinutes < 2;
  }

  String _lastSeen(AppUser p) {
    if (p.lastActive == null) return '-';
    if (_isOnline(p)) {
      return 'Şimdi aktif';
    }
    final d = DateTime.now().difference(p.lastActive!);
    if (d.inMinutes < 1) return '1 dk önce aktifti';
    if (d.inMinutes < 60) return '${d.inMinutes} dk önce aktifti';
    if (d.inHours < 24) return '${d.inHours} sa önce aktifti';
    return '${d.inDays} gün önce aktifti';
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
    final theme = Theme.of(context);
    final p = partner;

    if (p == null) {
      return _BentoCard(
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: LoveraColors.secondary.withValues(alpha: 0.25),
              child: const Icon(Icons.person_add_alt_1_rounded, color: LoveraColors.secondary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Partnerin henüz bağlı değil',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Bağlanınca durumu burada görünür.',
                      style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted)),
                ],
              ),
            ),
            TextButton(onPressed: onPair, child: const Text('Bağlan')),
          ],
        ),
      );
    }

    final batColor = _batteryColor(p.batteryLevel);
    final batIcon = _batteryIcon(p.batteryLevel);

    return _BentoCard(
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: LoveraColors.secondary.withValues(alpha: 0.3),
                backgroundImage:
                    p.avatarUrl != null ? CachedNetworkImageProvider(p.avatarUrl!) : null,
                child: p.avatarUrl == null
                    ? Text(p.name.isEmpty ? '?' : p.name[0],
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(p.name,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
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
                                const Icon(Icons.location_on_rounded, size: 11, color: LoveraColors.secondary),
                                const SizedBox(width: 3),
                                Text(
                                  p.city!,
                                  style: const TextStyle(
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
                        if (online) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
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
                              const Text(
                                'Şimdi aktif',
                                style: TextStyle(
                                  color: Color(0xFF10B981),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          );
                        }
                        return Text(
                          _lastSeen(p),
                          style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  icon: batIcon,
                  label: 'Batarya',
                  value: p.batteryLevel == null ? '-' : '%${p.batteryLevel}',
                  color: batColor,
                  onTap: onBatteryTap,
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
                  label: p.city != null && p.city!.isNotEmpty ? p.city! : 'Hava Durumu',
                  value: (p.weather != null && p.weather!.isNotEmpty)
                      ? p.weather!
                      : 'Hava durumu alınıyor...',
                  color: LoveraColors.accentGold,
                  onTap: onWeatherTap,
                ),
              ),
            ],
          ),
        ],
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
                Icon(icon, color: color, size: 22),
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

class _ThinkingButton extends StatelessWidget {
  const _ThinkingButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: isDark ? LoveraColors.darkPrimaryGradient : LoveraColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: LoveraColors.primaryDark.withValues(alpha: 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : AppTheme.primaryGlow,
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
                Text('Özledim 💕',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
