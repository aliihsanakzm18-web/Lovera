import '../../../core/localization/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../chat/presentation/chat_view.dart';
import '../../dashboard/presentation/dashboard_view.dart';
import '../../games/presentation/games_view.dart';
import '../../games/presentation/love_questions_game_view.dart';
import '../../map/presentation/live_map_view.dart';

/// Lovera Ana Kabuk (Shell):
/// Sayfalar:
/// 0: Canlı Harita (Ana sayfadan sağa kaydırınca açılır)
/// 1: Ana Ekran (Dashboard - merkez sayfa)
/// 2: Mesajlaşma (Ana ekrandan sola çekince açılır)
/// 3: Oyun & Eğlence (Mesajlaşmadan sonra tekrar sola çekince açılır)
/// 
/// Sabit Alt Gezinti Çubuğu (Bottom Navigation Bar):
/// Sadece [Ana Sayfa (1), Mesajlar (2), Oyun (3)] için sabit, temaya özgü şık ikonlar barındırır.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:home_widget/home_widget.dart';
import '../../../core/services/app_settings_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/widget_sync_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/widgets/app_lock_screen.dart';
import '../../drawing/presentation/drawing_screen.dart';

class MainNavigationShell extends ConsumerStatefulWidget {
  const MainNavigationShell({super.key, this.initialPage = 1});
  final int initialPage;

  @override
  ConsumerState<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends ConsumerState<MainNavigationShell> {
  late final PageController _pageController;
  int _currentIndex = 1;
  Timer? _heartbeatTimer;
  AppLifecycleListener? _lifecycleListener;
  StreamSubscription? _deliverySub;
  StreamSubscription? _meetingSub;
  StreamSubscription? _coupleSub;
  StreamSubscription? _drawingSub;
  StreamSubscription? _chessInviteSub;
  StreamSubscription? _billiardsInviteSub;
  StreamSubscription? _gameInviteSub;
  String? _lastHandledGameStatusKey;
  String? _shownMeetingId;
  bool _meetingSheetOpen = false;
  Map<String, dynamic>? _activeReviewMeetingRequest;
  String? _shownGameRequestId;
  bool _gameSheetOpen = false;
  int _unreadCount = 0;
  String? _shownBreakupId;
  bool _breakupSheetOpen = false;
  bool _isLockShowing = false;

  void _checkAppLock() {
    if (!AppSettingsService.appLockEnabled || AppSettingsService.isAppUnlocked || _isLockShowing) {
      return;
    }
    _isLockShowing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder(
          opaque: true,
          pageBuilder: (_, __, ___) => AppLockScreen(
            mode: AppLockMode.unlock,
            isDismissible: false,
            onSuccess: () {
              Navigator.of(context, rootNavigator: true).pop();
              _isLockShowing = false;
            },
          ),
        ),
      ).then((_) {
        _isLockShowing = false;
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialPage;
    _pageController = PageController(initialPage: widget.initialPage);

    // Uygulama kilidi (PIN) kontrolü
    _checkAppLock();

    // Widget'a tıklanarak uygulama açıldıysa yakala
    _checkWidgetLaunch();

    // Uygulama açık olduğu sürece (ister ana sayfada, ister sohbette, ister oyunda)
    // her 20 saniyede bir partnerin "Şimdi aktif" görmesi için presence heartbeat gönder
    _startHeartbeat();

    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        if (AppSettingsService.showOnline) {
          DatabaseService().setAppPresence(true);
        }
        _startHeartbeat();
        final bgTime = AppSettingsService.lastBackgroundTime;
        if (AppSettingsService.appLockEnabled && bgTime != null) {
          if (DateTime.now().difference(bgTime).inSeconds >= 15) {
            AppSettingsService.isAppUnlocked = false;
            _checkAppLock();
          }
        }
      },
      onPause: () {
        _stopHeartbeat();
        DatabaseService().setAppPresence(false);
        AppSettingsService.lastBackgroundTime = DateTime.now();
      },
      onDetach: () {
        _stopHeartbeat();
        DatabaseService().setAppPresence(false);
      },
    );

    // Bildirim servisini bağla:
    // 1) Kullanıcı sohbetteyken bildirimleri sessize al
    // 2) Kullanıcı satrançtayken oyun bildirimlerini sessize al
    // 3) Bildirime tıklandığında (eğer satrançta değilse) Sohbet (Sayfa 2) sayfasına uçur
    NotificationService().isChatScreenActive = () => _currentIndex == 2;
    NotificationService().isChessScreenActive = () => ref.read(isChessScreenOpenProvider);
    NotificationService().onNotificationTap = () {
      if (mounted) {
        if (ref.read(isChessScreenOpenProvider)) {
          debugPrint('[NOTIFICATION-TAP] Kullanıcı zaten satranç ekranında, sayfa değişimi engellendi.');
          return;
        }
        _goToPage(2);
      }
    };

    // Cihaz internete bağlı ve uygulama açık olduğu anda partnerin attığı mesajları
    // "İletildi (Çift gri tik)" olarak işaretle!
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeNavigationIndexProvider.notifier).state = _currentIndex;
      _listenMeetingRequests();
      void setupDeliveryListener(String? coupleId) {
        _deliverySub?.cancel();
        final myUid = DatabaseService().uid;
        if (coupleId != null && coupleId.isNotEmpty && myUid != null) {
          _deliverySub = DatabaseService().messagesStream(coupleId).listen((messages) {
            final undeliveredIds = messages
                .where((m) => m.senderId != myUid && !m.isDelivered && !m.isRead)
                .map((m) => m.id)
                .toList();
            if (undeliveredIds.isNotEmpty) {
              DatabaseService().markMessagesAsDelivered(coupleId, undeliveredIds);
            }

            final partnerUnreadMessages = messages
                .where((m) => m.senderId != myUid && !m.isRead)
                .toList();

            if (mounted) {
              setState(() {
                _unreadCount = (_currentIndex == 2) ? 0 : partnerUnreadMessages.length;
              });
            }

            // Partnerden gelen okunmamış mesajları widget'a yansıt
            // Eğer kullanıcı şu anda Sohbet ekranındaysa (_currentIndex == 2) veya bildirim servisi sohbetin açık olduğunu bildiriyorsa
            // widget'ı her zaman temiz tut!
            final isChatActive = (_currentIndex == 2) || (NotificationService().isChatScreenActive?.call() == true);
            if (isChatActive) {
              WidgetSyncService.clearWidgetMessages();
            } else {
              // messagesStream descending: true ile geldiği için kronolojik sıraya çevir
              partnerUnreadMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
              final unreadTexts = partnerUnreadMessages.map((m) {
                if (m.type == 'heart') return '❤️';
                if (m.type == 'image' || m.mediaBase64 != null) return loc('📸 Fotoğraf', '📸 Photo');
                if (m.locationTitle != null && m.locationTitle!.isNotEmpty) {
                  return '📍 ${m.locationTitle}';
                }
                return m.text;
              }).toList();
              WidgetSyncService.syncWidgetMessages(unreadTexts);
            }
          });
        }
      }

      void setupCoupleListener(String? coupleId) {
        _coupleSub?.cancel();
        if (coupleId != null && coupleId.isNotEmpty) {
          final cStream = DatabaseService().coupleStream(coupleId);
          if (cStream != null) {
            _coupleSub = cStream.listen((snap) {
              if (!mounted) return;
              final data = snap.data();
              if (data != null && data['activeMeeting'] is Map) {
                final m = Map<String, dynamic>.from(data['activeMeeting'] as Map);
                final lat = (m['lat'] as num?)?.toDouble();
                final lng = (m['lng'] as num?)?.toDouble();
                final title = m['title']?.toString() ?? loc('Buluşma Noktası', 'Meetup Point');
                if (lat != null && lng != null) {
                  ref.read(activeMeetingLocationProvider.notifier).state =
                      AttachedLocation(lat: lat, lng: lng, title: title);
                }
              } else {
                ref.read(activeMeetingLocationProvider.notifier).state = null;
              }
            });
          }
        }
      }

      void setupDrawingListener(String? coupleId) {
        _drawingSub?.cancel();
        if (coupleId != null && coupleId.isNotEmpty) {
          final dStream = DatabaseService().latestDrawingStream(coupleId);
          if (dStream != null) {
            _drawingSub = dStream.listen((snap) async {
              if (!mounted || !snap.exists || snap.data() == null) return;
              final data = snap.data()!;
              final imageBase64 = data['imageBase64'] as String?;
              final senderId = data['senderId'] as String?;
              final senderName = data['senderName'] as String? ?? loc('Partnerin', 'Partner');
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
                } catch (e) {
                  debugPrint('[MainNavigationShell] Drawing widget sync error: $e');
                }
              }
            });
          }
        }
      }

      void setupGameInviteListener(String? coupleId) {
        _gameInviteSub?.cancel();
        if (coupleId != null && coupleId.isNotEmpty) {
          _gameInviteSub = DatabaseService().gameStream(coupleId, 'love_questions').listen((snap) {
            if (!mounted || !snap.exists || snap.data() == null) return;
            final data = snap.data()!;
            final status = data['status'] as String?;
            final fromUid = (data['fromUid'] ?? data['requestedBy']) as String?;
            final toUid = data['toUid'] as String?;
            final reqId = data['id']?.toString() ?? 'love_questions_${fromUid}_$status';
            final myUid = DatabaseService().uid;
            if (myUid == null) return;

            // 1. Bana gelen bekleyen oyun daveti varsa alttan onay menüsünü aç
            if (status == 'invitation_pending' && fromUid != myUid && (toUid == null || toUid == myUid)) {
              if (reqId != _shownGameRequestId && !_gameSheetOpen) {
                _shownGameRequestId = reqId;
                final fromName = data['fromName']?.toString() ??
                    data['player1Name']?.toString() ??
                    loc('Partnerin', 'Partner');
                _showGameRequestSheet({
                  'id': reqId,
                  'game': 'love_questions',
                  'gameTitle': data['gameTitle']?.toString() ?? loc('Aşk Sandığı: Kalp Kalbe', 'Love Chest: Heart to Heart'),
                  'fromUid': fromUid,
                  'fromName': fromName,
                  'status': 'pending',
                });
              }
            }

            // 2. Ben davet göndermişim ve partnerim kabul ettiyse oyuna otomatik uçur
            final statusKey = '${reqId}_$status';
            if (fromUid == myUid && _lastHandledGameStatusKey != statusKey) {
              if (status == 'active' && _lastHandledGameStatusKey != null && _lastHandledGameStatusKey!.endsWith('_invitation_pending')) {
                _lastHandledGameStatusKey = statusKey;
                final by = data['responderName']?.toString() ??
                    data['player2Name']?.toString() ??
                    loc('Partnerin', 'Partner');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(loc('🎉 $by davetini kabul etti! Aşk Sandığı açılıyor...', '🎉 $by accepted your invite! Opening game...')),
                    backgroundColor: const Color(0xFF10B981),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                ref.read(loveQuestionsEnteredThisSessionProvider.notifier).state = true;
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoveQuestionsGameView()),
                );
              } else if (status == 'rejected' && _lastHandledGameStatusKey != null && _lastHandledGameStatusKey!.endsWith('_invitation_pending')) {
                _lastHandledGameStatusKey = statusKey;
                final by = data['responderName']?.toString() ?? loc('Partnerin', 'Partner');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(loc('$by şimdilik oyuna katılamadı.', '$by didn\'t join the game right now.')),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } else {
                _lastHandledGameStatusKey = statusKey;
              }
            }
          });
        }
      }

      setupDeliveryListener(ref.read(coupleIdProvider));
      setupCoupleListener(ref.read(coupleIdProvider));
      setupDrawingListener(ref.read(coupleIdProvider));
      setupGameInviteListener(ref.read(coupleIdProvider));
      // coupleId sonradan yüklenirse de dinleyiciyi başlat
      ref.listenManual(coupleIdProvider, (prev, next) {
        if (next != prev && next != null) {
          setupDeliveryListener(next);
          setupCoupleListener(next);
          setupDrawingListener(next);
          setupGameInviteListener(next);
        }
      });

      // activeNavigationIndexProvider değiştiğinde (harita veya başka yerden yönlendirilince) o sayfaya kaydır
      ref.listenManual(activeNavigationIndexProvider, (prev, next) {
        if (next != _currentIndex) {
          _goToPage(next);
        }
      });
    });
  }

  Future<void> _checkWidgetLaunch() async {
    try {
      final uri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (uri != null && uri.host == 'open_drawing') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DrawingScreen()),
            );
          }
        });
      } else if (uri != null && uri.host == 'open_chat') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _goToPage(2);
          }
        });
      }
      HomeWidget.widgetClicked.listen((uri) {
        if (uri != null && uri.host == 'open_drawing') {
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DrawingScreen()),
            );
          }
        } else if (uri != null && uri.host == 'open_chat') {
          if (mounted) {
            _goToPage(2);
          }
        }
      });
    } catch (e) {
      debugPrint('[MainNavigationShell] widgetClicked error: $e');
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    DatabaseService().setAppPresence(true);
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      DatabaseService().setAppPresence(true);
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  @override
  void dispose() {
    NotificationService().isChatScreenActive = null;
    NotificationService().isChessScreenActive = null;
    NotificationService().onNotificationTap = null;
    _deliverySub?.cancel();
    _coupleSub?.cancel();
    _drawingSub?.cancel();
    _chessInviteSub?.cancel();
    _billiardsInviteSub?.cancel();
    _gameInviteSub?.cancel();
    _meetingSub?.cancel();
    _stopHeartbeat();
    _lifecycleListener?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// Partnerden gelen buluşma taleplerini ve verdiğimiz taleplerin yanıtlarını dinler.
  /// Uygulama kapalıyken gelen talep, uygulama açılınca (veya bildirime dokununca) burada yakalanır.
  void _listenMeetingRequests() {
    _meetingSub?.cancel();
    final stream = DatabaseService().userStream();
    if (stream == null) return;
    _meetingSub = stream.listen((snap) {
      if (!mounted) return;
      final data = snap.data();
      if (data == null) return;

      final res = data['meetingResult'];
      if (res is Map) {
        DatabaseService().clearMeetingResult();
        final accepted = res['status'] == 'accepted';
        final title = res['title']?.toString() ?? loc('konum', 'location');
        final by = res['byName']?.toString() ?? loc('Partnerin', 'Partner');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(accepted
                ? loc('$by "$title" buluşmasını kabul etti 💕', '$by accepted the meetup "$title" 💕')
                : loc('$by bu sefer buluşamayacağını söyledi.', '$by said they can\'t make it this time.')),
            backgroundColor: accepted ? const Color(0xFF10B981) : null,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // Oyun isteği yanıt bildirimi (Kabul / Ret)
      final gameRes = data['gameResult'];
      if (gameRes is Map) {
        DatabaseService().clearGameResult();
        final rawGame = gameRes['game']?.toString() ?? 'chess';
        // Satranç yanıtları doğrudan setupChessInviteListener üzerinden işlenir, çift bildirim/ekran açılmasını önle
        if (rawGame != 'chess') {
          final accepted = gameRes['status'] == 'accepted';
          final game = rawGame == 'billiards'
              ? loc('bilardo', 'billiards')
              : loc('tavla', 'backgammon');
          final by = gameRes['byName']?.toString() ?? loc('Partnerin', 'Partner');
          if (accepted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(loc('🎉 $by $game isteğini kabul etti! Oyun başlıyor...', '🎉 $by accepted the $game invitation! Starting game...')),
                backgroundColor: const Color(0xFF10B981),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(loc('$by şimdilik $game oynamak istemedi.', '$by didn\'t want to play $game right now.')),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }

      // Gelen Ayrılma İsteği Yanıtı (breakupResult)
      final breakupRes = data['breakupResult'];
      if (breakupRes is Map) {
        DatabaseService().clearBreakupResult();
        final accepted = breakupRes['status'] == 'accepted';
        if (accepted) {
          // Sayaç, partner ve widgetları tamamen sıfırla
          ref.read(partnerProvider.notifier).state = null;
          ref.read(partnerUidProvider.notifier).state = null;
          ref.read(coupleIdProvider.notifier).state = null;
          ref.read(startDateProvider.notifier).state = null;
          WidgetSyncService.resetAllWidgets();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(loc('Eşleşmeniz karşı tarafça onaylanarak sonlandırıldı. 💔', 'Your pairing has been terminated by partner approval. 💔')),
              backgroundColor: const Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(loc('Partnerin ayrılma isteğini reddetti.', 'Partner rejected the disconnect request.')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }

      // Gelen Ayrılma Talebi (pendingBreakupRequest)
      final breakupReq = data['pendingBreakupRequest'];
      if (breakupReq is Map && breakupReq['status'] == 'pending') {
        final id = breakupReq['fromUid']?.toString();
        if (id != null && id != _shownBreakupId && !_breakupSheetOpen) {
          _shownBreakupId = id;
          _showBreakupRequestSheet(Map<String, dynamic>.from(breakupReq));
        }
      }

      // Gelen Oyun Daveti (pendingGameRequest - bilardo/tavla için)
      final gameReq = data['pendingGameRequest'];
      if (gameReq is Map && gameReq['status'] == 'pending' && gameReq['game'] != 'chess') {
        final id = gameReq['id']?.toString() ?? gameReq['fromUid']?.toString();
        if (id != null && id != _shownGameRequestId && !_gameSheetOpen && !ref.read(isChessScreenOpenProvider)) {
          _shownGameRequestId = id;
          _showGameRequestSheet(Map<String, dynamic>.from(gameReq));
        }
      }

      final req = data['pendingMeetingRequest'];
      if (req is Map && req['status'] == 'pending') {
        final id = req['id']?.toString();
        if (id != null && id != _shownMeetingId && !_meetingSheetOpen && _activeReviewMeetingRequest == null) {
          _shownMeetingId = id;
          _showMeetingRequestSheet(Map<String, dynamic>.from(req));
        }
      }
    });
  }

  void _showBreakupRequestSheet(Map<String, dynamic> req) {
    final fromName = req['fromName']?.toString() ?? loc('Partnerin', 'Partner');
    final fromUid = req['fromUid']?.toString() ?? '';
    final coupleId = req['coupleId']?.toString() ?? ref.read(coupleIdProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _breakupSheetOpen = true;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        decoration: BoxDecoration(
          color: isDark ? LoveraColors.darkSurfaceAlt : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 25,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(Icons.heart_broken_rounded, color: Color(0xFFEF4444), size: 38),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                loc('Eşleşmeyi Sonlandırma Talebi', 'Disconnect Request'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                loc('$fromName seninle olan çift eşleşmesini sonlandırmak istiyor. Bu talebi kabul ederseniz sayaç, ortak alan ve eşleşmeniz her iki cihazda da kaldırılacaktır.',
                    '$fromName wants to end your pairing. If you accept this, the counter, shared space, and pairing will be removed on both devices.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        _breakupSheetOpen = false;
                        await DatabaseService().rejectBreakup(fromUid);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(loc('Ayrılma talebini reddettiniz.', 'You declined the disconnect request.')),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      child: Text(loc('Reddet', 'Decline')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        _breakupSheetOpen = false;
                        await DatabaseService().acceptBreakup(partnerUid: fromUid, coupleId: coupleId);
                        ref.read(partnerProvider.notifier).state = null;
                        ref.read(partnerUidProvider.notifier).state = null;
                        ref.read(coupleIdProvider.notifier).state = null;
                        ref.read(startDateProvider.notifier).state = null;
                        WidgetSyncService.resetAllWidgets();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(loc('Eşleşme başarıyla sonlandırıldı. 💔', 'Pairing ended successfully. 💔')),
                              backgroundColor: const Color(0xFFEF4444),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      child: Text(loc('Kabul Et (Ayrıl)', 'Accept (Disconnect)'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() => _breakupSheetOpen = false);
  }

  Future<void> _answerMeeting(Map<String, dynamic> req, bool accepted) async {
    final fromUid = req['fromUid']?.toString() ?? '';
    final title = req['title']?.toString() ?? loc('konum', 'location');
    final lat = (req['lat'] as num?)?.toDouble();
    final lng = (req['lng'] as num?)?.toDouble();
    final meetingTime = req['meetingTime']?.toString();
    final note = req['note']?.toString();
    final coupleId = ref.read(coupleIdProvider);
    final myName = ref.read(userNameProvider);
    final name = myName.isNotEmpty ? myName : loc('Partnerin', 'Partner');
    setState(() => _activeReviewMeetingRequest = null);
    try {
      if (fromUid.isNotEmpty) {
        await DatabaseService().respondMeetingRequest(
          fromUid: fromUid,
          accepted: accepted,
          placeTitle: title,
          responderName: name,
          coupleId: coupleId,
          lat: lat,
          lng: lng,
          meetingTime: meetingTime,
          note: note,
        );
        final titleTr = accepted ? 'Buluşma kabul edildi 💕' : 'Buluşma talebi';
        final titleEn = accepted ? 'Meetup accepted 💕' : 'Meetup request';
        final bodyTr = accepted ? '$name "$title" buluşmasını kabul etti!' : '$name bu sefer buluşamayacağını söyledi.';
        final bodyEn = accepted ? '$name accepted the "$title" meetup!' : '$name said they can\'t make it this time.';
        NotificationService().sendPushToPartner(
          partnerUid: fromUid,
          title: loc(titleTr, titleEn),
          body: loc(bodyTr, bodyEn),
          titleTr: titleTr,
          titleEn: titleEn,
          bodyTr: bodyTr,
          bodyEn: bodyEn,
          data: {'type': 'meeting_result'},
        );
      }
    } catch (_) {}
  }

  void _showMeetingRequestSheet(Map<String, dynamic> req) {
    final fromName = req['fromName']?.toString() ?? loc('Partnerin', 'Partner');
    String title = req['title']?.toString() ?? loc('Buluşma Noktası', 'Meetup Point');
    if (title.toLowerCase().contains('seçilen') || title.toLowerCase().contains('selected')) {
      title = loc('Buluşma Noktası', 'Meetup Point');
    }
    final lat = (req['lat'] as num?)?.toDouble();
    final lng = (req['lng'] as num?)?.toDouble();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _meetingSheetOpen = true;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        decoration: BoxDecoration(
          color: isDark ? LoveraColors.darkSurfaceAlt : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              const Text('💕', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 8),
              Text(
                loc('Buluşma Talebi', 'Meetup Request'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                loc('$fromName seni "$title" konumunda buluşmaya çağırıyor.', '$fromName invites you to meet up at "$title".'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: isDark ? Colors.white70 : LoveraColors.textMuted,
                ),
              ),
              if (req['meetingTime'] != null && req['meetingTime'].toString().trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: LoveraColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: LoveraColors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time_rounded, size: 16, color: LoveraColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        loc('Saat: ${req['meetingTime']}', 'Time: ${req['meetingTime']}'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: LoveraColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (req['note'] != null && req['note'].toString().trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? LoveraColors.darkBorder : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.edit_note_rounded, size: 18, color: isDark ? Colors.white70 : Colors.black54),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '"${req['note']}"',
                          style: TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : LoveraColors.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (lat != null && lng != null)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.map_rounded),
                    label: Text(loc('Haritada Göster', 'Show on Map')),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _activeReviewMeetingRequest = req;
                      });
                      ref.read(targetMapFocusLocationProvider.notifier).state =
                          AttachedLocation(lat: lat, lng: lng, title: title);
                      _goToPage(0);
                    },
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _answerMeeting(req, false);
                      },
                      child: Text(loc('Şimdilik Olmaz', 'Not Now')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: LoveraColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _answerMeeting(req, true);
                      },
                      child: Text(loc('Kabul Et', 'Accept')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() => _meetingSheetOpen = false);
  }

  void _showGameRequestSheet(Map<String, dynamic> req) {
    final fromName = req['fromName']?.toString() ?? loc('Partnerin', 'Partner');
    final gameType = req['game']?.toString() ?? 'love_questions';
    final gameTitle = req['gameTitle']?.toString() ?? loc('Aşk Sandığı: Kalp Kalbe', 'Love Chest: Heart to Heart');
    final gameEmoji = gameType == 'love_questions' ? '💌' : '🎮';
    final gradientColors = [LoveraColors.primary, LoveraColors.primaryDeep];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    _gameSheetOpen = true;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        decoration: BoxDecoration(
          color: isDark ? LoveraColors.darkSurfaceAlt : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 25,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: gradientColors.last.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(gameEmoji, style: const TextStyle(fontSize: 34)),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                loc('$gameTitle Daveti', '$gameTitle Invitation'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                loc('$fromName seninle $gameTitle oynamak istiyor! Kabul ettiğinde oyun ekranı açılacak ve birlikte oynayabileceksiniz.',
                    '$fromName wants to play $gameTitle with you! When accepted, the game screen will open and you can play together.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _answerGameRequest(req, false);
                      },
                      child: Text(loc('Reddet', 'Decline')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: gradientColors.first,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _answerGameRequest(req, true);
                      },
                      child: Text(loc('Oyna 🚀', 'Play 🚀'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() => _gameSheetOpen = false);
  }

  Future<void> _answerGameRequest(Map<String, dynamic> req, bool accepted) async {
    final fromUid = req['fromUid']?.toString() ?? '';
    final gameType = req['game']?.toString() ?? 'game';
    final gameLabel = req['gameTitle']?.toString() ?? loc('Oyun', 'Game');
    final coupleId = ref.read(coupleIdProvider);
    final myName = ref.read(userNameProvider);
    final name = myName.isNotEmpty ? myName : loc('Partnerin', 'Partner');

    if (coupleId == null || coupleId.isEmpty || fromUid.isEmpty) return;

    if (accepted && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(loveQuestionsEnteredThisSessionProvider.notifier).state = true;
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const LoveQuestionsGameView(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              const begin = Offset(1.0, 0.0);
              const end = Offset.zero;
              const curve = Curves.easeInOutCubic;
              final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
              return SlideTransition(
                position: animation.drive(tween),
                child: child,
              );
            },
          ),
        );
      });
    }

    try {
      await DatabaseService().respondGameRequest(
        coupleId: coupleId,
        gameType: gameType,
        fromUid: fromUid,
        accepted: accepted,
        responderName: name,
      );

      final titleTr = accepted ? 'Oyun Daveti Kabul Edildi 🎉' : 'Oyun Daveti';
      final titleEn = accepted ? 'Game Invitation Accepted 🎉' : 'Game Invitation';
      final bodyTr = accepted ? '$name $gameLabel davetini kabul etti! Hazırlan...' : '$name davetini reddetti.';
      final bodyEn = accepted ? '$name accepted the $gameLabel invitation! Get ready...' : '$name declined your invitation.';
      NotificationService().sendPushToPartner(
        partnerUid: fromUid,
        title: loc(titleTr, titleEn),
        body: loc(bodyTr, bodyEn),
        titleTr: titleTr,
        titleEn: titleEn,
        bodyTr: bodyTr,
        bodyEn: bodyEn,
        data: {'type': 'game_result', 'game': gameType},
      );
    } catch (e) {
      debugPrint('[GAME_REQUEST] Error answering game request: $e');
    }
  }

  void _goToPage(int index) {
    if (index == _currentIndex) return;
    FocusManager.instance.primaryFocus?.unfocus();
    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex = index;
      if (index == 2) _unreadCount = 0;
    });
    ref.read(activeNavigationIndexProvider.notifier).state = index;
    if (index == 2) {
      WidgetSyncService.clearWidgetMessages();
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (idx) {
              FocusManager.instance.primaryFocus?.unfocus();
              setState(() {
                _currentIndex = idx;
                if (idx == 2) _unreadCount = 0;
              });
              ref.read(activeNavigationIndexProvider.notifier).state = idx;
              if (idx == 2) {
                WidgetSyncService.clearWidgetMessages();
              }
            },
            children: [
              // Sayfa 0: Canlı Harita
              LiveMapView(
                onBackToHome: () => _goToPage(1),
                onOpenChat: () => _goToPage(2),
              ),

              // Sayfa 1: Ana Sayfa (Dashboard)
              DashboardView(
                onOpenMap: () => _goToPage(0),
                onOpenChat: () => _goToPage(2),
              ),

              // Sayfa 2: Mesajlaşma (Chat)
              ChatView(
                onBackToHome: () => _goToPage(1),
                onOpenMap: () => _goToPage(0),
              ),

              // Sayfa 3: Oyun & Eğlence Odası (Games)
              GamesView(
                onBackToHome: () => _goToPage(1),
              ),
            ],
          ),

          // Haritada incelerken kaybolmayan Şık Yüzen Buluşma Karar Kartı (Top Floating Banner)
          if (_activeReviewMeetingRequest != null)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? LoveraColors.darkSurfaceAlt : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                      border: Border.all(
                        color: LoveraColors.primary.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: LoveraColors.primary.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Text('💕', style: TextStyle(fontSize: 18)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    loc('${_activeReviewMeetingRequest!['fromName'] ?? loc("Partnerin", "Partner")} Buluşmaya Çağırıyor',
                                        '${_activeReviewMeetingRequest!['fromName'] ?? loc("Partnerin", "Partner")} Invites You to Meet Up'),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                   Builder(
                                    builder: (context) {
                                      String cardTitle = _activeReviewMeetingRequest!['title']?.toString() ?? loc('Buluşma Noktası', 'Meetup Point');
                                      if (cardTitle.toLowerCase().contains('seçilen') || cardTitle.toLowerCase().contains('selected')) {
                                        cardTitle = loc('Buluşma Noktası', 'Meetup Point');
                                      }
                                      final time = _activeReviewMeetingRequest!['meetingTime']?.toString();
                                      final note = _activeReviewMeetingRequest!['note']?.toString();
                                      String subtitle = cardTitle;
                                      if (time != null && time.trim().isNotEmpty) {
                                        subtitle += loc(' · Saat: $time', ' · Time: $time');
                                      }
                                      if (note != null && note.trim().isNotEmpty) {
                                        subtitle += ' ("$note")';
                                      }
                                      return Text(
                                        subtitle,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark ? Colors.white70 : LoveraColors.textMuted,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () {
                                  _answerMeeting(_activeReviewMeetingRequest!, false);
                                },
                                child: Text(loc('Reddet', 'Decline'), style: const TextStyle(fontSize: 12)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: LoveraColors.primary,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () {
                                  _answerMeeting(_activeReviewMeetingRequest!, true);
                                },
                                child: Text(loc('Kabul Et', 'Accept'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),

      // Ekranın altında sabit kalan (scroll ile kaymayan), temaya uyumlu alt navigasyon barı
      bottomNavigationBar: _buildBottomBar(isDark),
    );
  }

  Widget _buildBottomBar(bool isDark) {
    final palette = ref.watch(themePaletteProvider);
    final navBgColor = isDark
        ? palette.darkSurface.withValues(alpha: 0.96)
        : Colors.white.withValues(alpha: 0.96);

    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return Container(
      decoration: BoxDecoration(
        color: navBgColor,
        border: Border(top: BorderSide(color: borderColor, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // 1. Ana Sayfa Butonu (index: 1)
              _BottomNavItem(
                icon: Icons.home_rounded,
                selectedIcon: Icons.home_rounded,
                isSelected: _currentIndex == 1,
                activeColor: palette.primary,
                tooltip: ref.watch(stringsProvider).navHome,
                onTap: () => _goToPage(1),
              ),

              // 2. Mesajlaşma Butonu (index: 2)
              _BottomNavItem(
                icon: Icons.chat_bubble_outline_rounded,
                selectedIcon: Icons.chat_bubble_rounded,
                isSelected: _currentIndex == 2,
                badgeCount: _unreadCount,
                activeColor: palette.secondary,
                badgeGradient: palette.gradient,
                badgeShadowColor: palette.primary,
                tooltip: ref.watch(stringsProvider).navChat,
                onTap: () => _goToPage(2),
              ),

              // 3. Oyun & Eğlence Butonu (index: 3)
              _BottomNavItem(
                icon: Icons.sports_esports_outlined,
                selectedIcon: Icons.sports_esports_rounded,
                isSelected: _currentIndex == 3,
                activeColor: palette.primary,
                tooltip: ref.watch(stringsProvider).navGames,
                onTap: () => _goToPage(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.isSelected,
    required this.activeColor,
    required this.tooltip,
    required this.onTap,
    this.badgeCount = 0,
    this.badgeGradient,
    this.badgeShadowColor,
  });

  final IconData icon;
  final IconData selectedIcon;
  final bool isSelected;
  final Color activeColor;
  final String tooltip;
  final VoidCallback onTap;
  final int badgeCount;
  final LinearGradient? badgeGradient;
  final Color? badgeShadowColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor = isDark
        ? const Color(0xFF7A8090)
        : const Color(0xFF9CA3AF);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        splashColor: activeColor.withValues(alpha: 0.15),
        highlightColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedScale(
                    scale: isSelected ? 1.15 : 1.0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    child: Icon(
                      isSelected ? selectedIcon : icon,
                      color: isSelected ? activeColor : inactiveColor,
                      size: 26,
                    ),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      top: -4,
                      right: -7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: badgeGradient ?? LinearGradient(
                            colors: [LoveraColors.gradientEndDeep, LoveraColors.primaryDeep],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark ? LoveraColors.darkSurface : Colors.white,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (badgeShadowColor ?? LoveraColors.primary).withValues(alpha: 0.5),
                              blurRadius: 6,
                              offset: const Offset(0, 1.5),
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Center(
                          child: Text(
                            badgeCount > 99 ? '99+' : badgeCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: isSelected ? 5 : 0,
                height: 5,
                decoration: BoxDecoration(
                  color: activeColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
