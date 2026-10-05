import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/device_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/pairing_view.dart';
import '../../couple/presentation/couple_management_view.dart';
import '../../map/presentation/live_map_view.dart';
import '../../memories/presentation/memories_gallery_view.dart';
import '../../milestones/presentation/milestones_view.dart';
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

  @override
  void initState() {
    super.initState();

    // Cihazın gerçek pil ve hava durumunu anında Firebase'e aktar
    DeviceService().syncStatusToFirebase();
    // Her 30 saniyede bir pil ve aktiflik durumunu güncelle
    _statusSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      DeviceService().syncStatusToFirebase();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 1. Kendi profilimizi dinle
      _userSub = DatabaseService().userStream()?.listen((doc) {
        if (!doc.exists || doc.data() == null || !mounted) return;
        final data = doc.data()!;
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
        );
        if (data['coupleId'] != null) {
          final cId = data['coupleId'] as String;
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
            _receiveHeartPulse();
          }
        }

        // Partner UID'sini aldık mı? Partnerin profilini de canlı dinle!
        final partnerUid = data['partnerUid'] as String?;
        if (partnerUid != null && partnerUid != ref.read(partnerUidProvider)) {
          ref.read(partnerUidProvider.notifier).state = partnerUid;
          _listenToPartner(partnerUid);
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
                color: LoveraColors.lightSurfaceAlt,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
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

  void _listenToPartner(String partnerUid) {
    _partnerSub?.cancel();
    _partnerSub = DatabaseService().partnerStream(partnerUid).listen((doc) {
      if (!doc.exists || doc.data() == null || !mounted) return;
      final data = doc.data()!;
      final partnerUser = AppUser(
        id: doc.id,
        name: data['name'] ?? 'Partnerin',
        avatarUrl: data['avatarUrl'],
        batteryLevel: data['batteryLevel'] ?? 88,
        weather: data['weather'] ?? 'Güneşli 22°',
        city: data['city'],
        lat: (data['lat'] as num?)?.toDouble(),
        lng: (data['lng'] as num?)?.toDouble(),
        lastActive: data['lastActive'] != null
            ? (data['lastActive'] as dynamic).toDate?.call() ?? DateTime.now()
            : DateTime.now(),
        coupleId: data['coupleId'],
      );
      ref.read(partnerProvider.notifier).state = partnerUser;
      
      // Eğer partner ilişki tarihini güncellemişse bize de yansısın
      if (data['relationshipStartDate'] != null) {
        ref.read(startDateProvider.notifier).state =
            DateTime.tryParse(data['relationshipStartDate']);
      }
    });
  }

  @override
  void dispose() {
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
    await DatabaseService().sendHeart(partnerUid);
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
                _PartnerCard(partner: partner, onPair: () => _push(const PairingView()))
                    .animate(delay: 120.ms)
                    .fadeIn(duration: 500.ms)
                    .slideY(begin: 0.08),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.map_outlined,
                        title: 'Canlı Harita',
                        subtitle: partner == null ? 'Eşleşme bekleniyor' : 'Konumu gör',
                        color: LoveraColors.secondary,
                        onTap: () => _push(const LiveMapView()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.calendar_month_outlined,
                        title: 'Özel Günler',
                        subtitle: milestones.isEmpty ? 'Henüz eklenmedi' : '${milestones.length} gün',
                        color: LoveraColors.primarySoft,
                        onTap: () => _push(const MilestonesView()),
                      ),
                    ),
                  ],
                ).animate(delay: 180.ms).fadeIn(duration: 500.ms).slideY(begin: 0.08),
                const SizedBox(height: 12),
                _ActionTile(
                  icon: Icons.photo_library_outlined,
                  title: 'Ortak Anı Albümü',
                  subtitle: 'Birlikte biriktirdiğiniz anılar',
                  color: const Color(0xFFC49A76),
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
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 12),
              Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted),
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
    return _BentoCard(
      color: cardColor,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('Birlikte geçen', style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${elapsed.inDays}',
                  style: theme.textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.w800, color: LoveraColors.primary, height: 1)),
              const SizedBox(width: 8),
              Text('gün', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PartnerCard extends StatelessWidget {
  const _PartnerCard({required this.partner, required this.onPair});
  final AppUser? partner;
  final VoidCallback onPair;

  String _lastSeen(AppUser p) {
    if (p.lastActive == null) return '-';
    final d = DateTime.now().difference(p.lastActive!);
    if (d.inMinutes < 1) return 'Şimdi aktif';
    if (d.inMinutes < 60) return '${d.inMinutes} dk önce aktifti';
    if (d.inHours < 24) return '${d.inHours} sa önce aktifti';
    return '${d.inDays} gün önce aktifti';
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
                    const SizedBox(height: 2),
                    Text(_lastSeen(p),
                        style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted)),
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
                  icon: p.batteryLevel != null && p.batteryLevel! <= 20
                      ? Icons.battery_alert_rounded
                      : Icons.battery_5_bar_rounded,
                  label: 'Batarya',
                  value: p.batteryLevel == null ? '-' : '%${p.batteryLevel}',
                  color: LoveraColors.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Stat(
                  icon: (p.weather ?? '').contains('Gece') || (p.weather ?? '').contains('Akşam')
                      ? Icons.nights_stay_rounded
                      : Icons.wb_sunny_rounded,
                  label: p.city != null && p.city!.isNotEmpty ? p.city! : 'Hava Durumu',
                  value: p.weather ?? 'Güneşli 22°',
                  color: LoveraColors.primarySoft,
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
  const _Stat({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted)),
          Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ThinkingButton extends StatelessWidget {
  const _ThinkingButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LoveraColors.primary,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.favorite_rounded, color: Colors.white)
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scale(end: const Offset(1.2, 1.2), duration: 900.ms),
              const SizedBox(width: 10),
              Text('Seni Düşünüyorum',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
