import '../../../core/localization/app_strings.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../chat/presentation/chat_view.dart';

/// Tavla geçerli bir hamle adımı (from: -1 ise Bar'dan giriş, to: 24 ise pul toplama / Bear Off)
class _BgMove {
  final int from; // -1: Bar, 0..23: Haneler
  final int to; // 0..23: Haneler, 24: Toplama (Bear Off)
  final int dieUsed;
  final bool hitsBlot;

  const _BgMove({
    required this.from,
    required this.to,
    required this.dieUsed,
    this.hitsBlot = false,
  });
}

class BackgammonGameView extends ConsumerStatefulWidget {
  const BackgammonGameView({super.key});

  @override
  ConsumerState<BackgammonGameView> createState() => _BackgammonGameViewState();
}

class _BackgammonGameViewState extends ConsumerState<BackgammonGameView>
    with WidgetsBindingObserver {
  // Seçili hane (-1: Bar, 0..23: Hane, null: Seçim yok)
  int? _selectedFrom;
  bool _isRolling = false;

  String? _currentCoupleId;
  bool? _currentIsWhite;
  bool _hasActiveGame = false;
  bool _isExitingDueToPartner = false;
  String? _lastVibratedTurnKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(isChessScreenOpenProvider.notifier).state = true;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final coupleId = _currentCoupleId;
    final isWhite = _currentIsWhite;
    if (coupleId != null && coupleId.isNotEmpty && isWhite != null) {
      DatabaseService().setGameOnlineStatus(
        coupleId: coupleId,
        gameType: 'backgammon',
        isPlayer1: isWhite,
        isOnline: false,
      );
    }
    Future.microtask(() {
      try {
        ref.read(isChessScreenOpenProvider.notifier).state = false;
      } catch (_) {}
    });
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _setOnlineStatus(false);
      _autoExitOnLeave();
    } else if (state == AppLifecycleState.resumed) {
      _setOnlineStatus(true);
    }
  }

  void _setOnlineStatus(bool isOnline) {
    final coupleId = _currentCoupleId ?? ref.read(coupleIdProvider);
    final isWhite = _currentIsWhite;
    if (coupleId != null && coupleId.isNotEmpty && isWhite != null) {
      DatabaseService().setGameOnlineStatus(
        coupleId: coupleId,
        gameType: 'backgammon',
        isPlayer1: isWhite,
        isOnline: isOnline,
      );
    }
  }

  void _autoExitOnLeave() {
    final coupleId = _currentCoupleId ?? ref.read(coupleIdProvider);
    final myUid = DatabaseService().uid;
    if (coupleId != null && coupleId.isNotEmpty && myUid != null) {
      DatabaseService().exitGame(
        coupleId: coupleId,
        gameType: 'backgammon',
        exitUid: myUid,
        exitReason: loc('Partnerin tavla oyunundan ayrıldı.', 'Partner left the backgammon game.'),
      );
    }
  }

  /// Klasik Tavla Başlangıç Dizilimi (24 Hane)
  /// Pozitif (+): Beyaz pullar (0 -> 23 yönünde ilerler, ev bölgesi 18..23)
  /// Negatif (-): Siyah pullar (23 -> 0 yönünde ilerler, ev bölgesi 0..5)
  static List<int> _initialPoints() {
    final pts = List<int>.filled(24, 0);
    // Beyazın 15 pulu:
    pts[0] = 2;
    pts[11] = 5;
    pts[16] = 3;
    pts[18] = 5;
    // Siyahın 15 pulu:
    pts[23] = -2;
    pts[12] = -5;
    pts[7] = -3;
    pts[5] = -5;
    return pts;
  }

  static Map<String, dynamic> buildInitialGameData() {
    return {
      'points': _initialPoints(),
      'barWhite': 0,
      'barBlack': 0,
      'offWhite': 0,
      'offBlack': 0,
      'turn': 'w',
      'dice': <int>[],
      'remainingMoves': <int>[],
      'lastEventText': loc('Tavla başladı! Zar atarak ilk hamleni yap 🎲', 'Backgammon started! Roll dice to make first move 🎲'),
    };
  }

  /// Oyuncunun tüm pulları ev bölgesinde mi? (Bear off yapabilir mi?)
  bool _canBearOff({
    required List<int> points,
    required bool isWhite,
    required int myBar,
  }) {
    if (myBar > 0) return false;
    if (isWhite) {
      // Beyazın evi: 18..23. 0..17 arasında hiç beyaz pul olmamalı.
      for (int i = 0; i <= 17; i++) {
        if (points[i] > 0) return false;
      }
      return true;
    } else {
      // Siyahın evi: 0..5. 6..23 arasında hiç siyah pul olmamalı.
      for (int i = 6; i <= 23; i++) {
        if (points[i] < 0) return false;
      }
      return true;
    }
  }

  /// Belirli bir kaynaktan (`from`: -1 Bar veya 0..23 Hane) mevcut zarlarla yapılabilecek yasal hamleleri hesaplar
  List<_BgMove> _getLegalMovesFrom({
    required int from,
    required List<int> points,
    required bool isWhite,
    required int myBar,
    required List<int> remainingMoves,
  }) {
    final result = <_BgMove>[];
    if (remainingMoves.isEmpty) return result;

    // Eğer Bar'da kırık pul varsa, ZORUNLU olarak sadece Bar'dan (-1) oynanabilir!
    if (myBar > 0 && from != -1) return result;
    if (myBar == 0 && from == -1) return result;

    // Seçilen hanede oyuncunun kendi pulu var mı?
    if (from >= 0) {
      if (isWhite && points[from] <= 0) return result;
      if (!isWhite && points[from] >= 0) return result;
    }

    final uniqueDice = remainingMoves.toSet().toList();
    final canBear = _canBearOff(points: points, isWhite: isWhite, myBar: myBar);

    for (final die in uniqueDice) {
      if (from == -1) {
        // Bar'dan oyuna giriş: Beyaz 0..5'e (die - 1), Siyah 23..18'e (24 - die) girer
        final target = isWhite ? (die - 1) : (24 - die);
        if (_isTargetOpen(points, target, isWhite)) {
          result.add(
            _BgMove(
              from: -1,
              to: target,
              dieUsed: die,
              hitsBlot: _isTargetBlot(points, target, isWhite),
            ),
          );
        }
      } else {
        final target = isWhite ? (from + die) : (from - die);
        if (target >= 0 && target <= 23) {
          if (_isTargetOpen(points, target, isWhite)) {
            result.add(
              _BgMove(
                from: from,
                to: target,
                dieUsed: die,
                hitsBlot: _isTargetBlot(points, target, isWhite),
              ),
            );
          }
        } else if (canBear) {
          // Pul toplama (Bear Off) kontrolü
          if (isWhite && target == 24) {
            result.add(_BgMove(from: from, to: 24, dieUsed: die));
          } else if (!isWhite && target == -1) {
            result.add(_BgMove(from: from, to: 24, dieUsed: die));
          } else if (isWhite && target > 24) {
            // Daha geride (18..from-1) pul yoksa büyük zarla da toplanabilir
            bool anyBehind = false;
            for (int i = 18; i < from; i++) {
              if (points[i] > 0) {
                anyBehind = true;
                break;
              }
            }
            if (!anyBehind) {
              result.add(_BgMove(from: from, to: 24, dieUsed: die));
            }
          } else if (!isWhite && target < -1) {
            // Daha geride (from+1..5) siyah pul yoksa büyük zarla da toplanabilir
            bool anyBehind = false;
            for (int i = from + 1; i <= 5; i++) {
              if (points[i] < 0) {
                anyBehind = true;
                break;
              }
            }
            if (!anyBehind) {
              result.add(_BgMove(from: from, to: 24, dieUsed: die));
            }
          }
        }
      }
    }

    return result;
  }

  /// Oyuncunun tahtadaki herhangi bir puluyla yapabileceği en az 1 yasal hamle var mı?
  bool _hasAnyLegalMove({
    required List<int> points,
    required bool isWhite,
    required int myBar,
    required List<int> remainingMoves,
  }) {
    if (remainingMoves.isEmpty) return false;
    if (myBar > 0) {
      return _getLegalMovesFrom(
        from: -1,
        points: points,
        isWhite: isWhite,
        myBar: myBar,
        remainingMoves: remainingMoves,
      ).isNotEmpty;
    }
    for (int i = 0; i < 24; i++) {
      if ((isWhite && points[i] > 0) || (!isWhite && points[i] < 0)) {
        final m = _getLegalMovesFrom(
          from: i,
          points: points,
          isWhite: isWhite,
          myBar: myBar,
          remainingMoves: remainingMoves,
        );
        if (m.isNotEmpty) return true;
      }
    }
    return false;
  }

  bool _isTargetOpen(List<int> points, int target, bool isWhite) {
    final val = points[target];
    // Rakibin 2 veya daha fazla pulu varsa "Kapı" alınmıştır, girilemez
    if (isWhite) return val >= -1;
    return val <= 1;
  }

  bool _isTargetBlot(List<int> points, int target, bool isWhite) {
    final val = points[target];
    if (isWhite) return val == -1;
    return val == 1;
  }

  /// Zar Atma İşlemi
  Future<void> _rollDice({
    required String coupleId,
    required List<int> points,
    required bool isWhite,
    required int myBar,
  }) async {
    if (_isRolling) return;
    setState(() {
      _isRolling = true;
      _selectedFrom = null;
    });
    HapticFeedback.heavyImpact();

    final rng = math.Random();
    final d1 = rng.nextInt(6) + 1;
    final d2 = rng.nextInt(6) + 1;
    // Çift gelirse 4 hamle hakkı!
    final moves = (d1 == d2) ? [d1, d1, d1, d1] : [d1, d2];

    final canPlay = _hasAnyLegalMove(
      points: points,
      isWhite: isWhite,
      myBar: myBar,
      remainingMoves: moves,
    );

    final nextTurn = canPlay ? (isWhite ? 'w' : 'b') : (isWhite ? 'b' : 'w');
    final eventMsg = canPlay
        ? (d1 == d2
            ? loc('🎲 Çift geldi ($d1-$d2)! 4 hamle hakkın var 🔥', '🎲 Doubles ($d1-$d2)! You have 4 moves 🔥')
            : '🎲 Zarlar: $d1 - $d2. Hamleni yap!')
        : loc('🎲 Zarlar: $d1 - $d2 geldi ancak açık kapı yok! Sıra partnere geçti.', '🎲 Dice: $d1 - $d2 but no legal moves! Turn passed to partner.');

    await Future.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    setState(() => _isRolling = false);

    await DatabaseService().updateGameState(
      coupleId: coupleId,
      gameType: 'backgammon',
      updates: {
        'dice': [d1, d2],
        'remainingMoves': canPlay ? moves : <int>[],
        'turn': nextTurn,
        'lastEventText': eventMsg,
      },
    );
  }

  /// Hamleyi Uygula ve Senkronize Et
  Future<void> _applyMove({
    required String coupleId,
    required _BgMove move,
    required List<int> currentPoints,
    required int barWhite,
    required int barBlack,
    required int offWhite,
    required int offBlack,
    required List<int> remainingMoves,
    required bool isWhite,
    required String? myUid,
  }) async {
    HapticFeedback.mediumImpact();
    final pts = List<int>.from(currentPoints);
    int bW = barWhite;
    int bB = barBlack;
    int oW = offWhite;
    int oB = offBlack;

    // 1. Çıkış noktasından pulu azalt
    if (move.from == -1) {
      if (isWhite) {
        bW = math.max(0, bW - 1);
      } else {
        bB = math.max(0, bB - 1);
      }
    } else {
      if (isWhite) {
        pts[move.from] -= 1;
      } else {
        pts[move.from] += 1;
      }
    }

    // 2. Varış noktasına pulu ekle veya topla
    String actionNote = '';
    if (move.to == 24) {
      if (isWhite) {
        oW += 1;
      } else {
        oB += 1;
      }
      actionNote = loc('Pul toplandı! ✨', 'Checker borne off! ✨');
    } else {
      if (isWhite) {
        if (pts[move.to] == -1) {
          // Rakip pul kırıldı!
          pts[move.to] = 1;
          bB += 1;
          actionNote = loc('Rakibin tek pulunu kırdın! 💥', 'Hit opponent\'s blot! 💥');
        } else {
          pts[move.to] += 1;
        }
      } else {
        if (pts[move.to] == 1) {
          // Rakip pul kırıldı!
          pts[move.to] = -1;
          bW += 1;
          actionNote = loc('Rakibin tek pulunu kırdın! 💥', 'Hit opponent\'s blot! 💥');
        } else {
          pts[move.to] -= 1;
        }
      }
    }

    // 3. Kullanılan zarı düş
    final rem = List<int>.from(remainingMoves);
    rem.remove(move.dieUsed);

    setState(() => _selectedFrom = null);

    // 4. Oyun bitti mi? (15 pul toplandı mı? Mars kontrolü)
    final myOff = isWhite ? oW : oB;
    final oppOff = isWhite ? oB : oW;
    if (myOff >= 15) {
      final isMars = oppOff == 0;
      await DatabaseService().updateGameState(
        coupleId: coupleId,
        gameType: 'backgammon',
        updates: {
          'points': pts,
          'barWhite': bW,
          'barBlack': bB,
          'offWhite': oW,
          'offBlack': oB,
          'remainingMoves': <int>[],
          'status': 'completed',
          'winnerUid': myUid,
          'winnerReason': isMars
              ? loc('MARS! Tüm pulları rakip hiç toplamadan bitirdi 🏆🔥', 'GAMMON! Cleared all checkers before opponent bore off any 🏆🔥')
              : loc('Tüm pulları toplayarak tavlayı kazandı 🎲🏆', 'Won the backgammon game by bearing off all checkers 🎲🏆'),
          'lastEventText': isMars ? loc('MARS! Muhteşem zafer! 🎉', 'GAMMON! Glorious victory! 🎉') : loc('Oyun bitti!', 'Game Over!'),
        },
      );
      return;
    }

    // 5. Kalan zarlarla başka yasal hamle yapılabiliyor mu?
    final myNewBar = isWhite ? bW : bB;
    final stillCanPlay = _hasAnyLegalMove(
      points: pts,
      isWhite: isWhite,
      myBar: myNewBar,
      remainingMoves: rem,
    );

    final bool turnEnded = rem.isEmpty || !stillCanPlay;
    final String nextTurn = turnEnded ? (isWhite ? 'b' : 'w') : (isWhite ? 'w' : 'b');

    String eventText = actionNote.isNotEmpty
        ? actionNote
        : (turnEnded
            ? loc('Hamle tamamlandı, sıra partnerine geçti 🎲', 'Move done, turn passed to partner 🎲')
            : loc('Kalan zarların: ${rem.join(", ")}', 'Remaining dice: ${rem.join(", ")}'));

    if (!turnEnded && myNewBar > 0) {
      setState(() => _selectedFrom = -1);
    }

    await DatabaseService().updateGameState(
      coupleId: coupleId,
      gameType: 'backgammon',
      updates: {
        'points': pts,
        'barWhite': bW,
        'barBlack': bB,
        'offWhite': oW,
        'offBlack': oB,
        'remainingMoves': turnEnded ? <int>[] : rem,
        'turn': nextTurn,
        'lastEventText': eventText,
      },
    );
  }

  void _handlePartnerLeft(String reason) {
    if (_isExitingDueToPartner || !mounted) return;
    _isExitingDueToPartner = true;
    _hasActiveGame = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.exit_to_app_rounded, color: Color(0xFFEF4444), size: 24),
              ),
              const SizedBox(width: 10),
              Text(loc('Oyun Bitti', 'Game Over'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ],
          ),
          content: Text(
            reason.isNotEmpty ? reason : loc('Partnerin oyundan çıktı.', 'Your partner left the game.'),
            style: const TextStyle(fontSize: 14.5, height: 1.4),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: LoveraColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                if (mounted) Navigator.pop(context);
              },
              child: Text(loc('Tamam', 'OK'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final coupleId = ref.watch(coupleIdProvider);
    final myUid = DatabaseService().uid;
    final partner = ref.watch(partnerProvider);
    final myName = ref.watch(userNameProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (coupleId == null || coupleId.isEmpty) {
      return Scaffold(
        backgroundColor: isDark ? LoveraColors.darkBg : LoveraColors.lightBg,
        appBar: AppBar(
          title: Text(loc('Tavla 🎲', 'Backgammon 🎲')),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(child: Text(loc('Karşılıklı tavla oynamak için önce partnerinizle eşleşmelisiniz 💕', 'You must pair with your partner to play backgammon 💕')),
        ),
      );
    }

    return StreamBuilder(
      stream: DatabaseService().gameStream(coupleId, 'backgammon'),
      builder: (context, snapshot) {
        final gameData = snapshot.data?.data();
        final status = gameData?['status'] as String?;

        if (_hasActiveGame && (status == 'ended' || status == null)) {
          final exitReason = gameData?['exitReason'] as String? ?? loc('Partnerin oyundan çıktı.', 'Partner left the game.');
          final exitUid = gameData?['exitUid'] as String?;
          if (exitUid != myUid) {
            _handlePartnerLeft(exitReason);
          }
        }

        if (gameData == null || !snapshot.hasData || status == null || status == 'rejected' || status == 'ended') {
          _hasActiveGame = false;
          return _buildStartLobby(
            context: context,
            isDark: isDark,
            status: status,
            coupleId: coupleId,
            myUid: myUid,
            myName: myName,
            partner: partner,
          );
        }

        if (status == 'invitation_pending') {
          final fromUid = gameData['fromUid'] as String?;
          final isSender = fromUid == myUid;
          return _buildPendingInvitationView(context, isDark, isSender);
        }

        final List<int> points = (gameData['points'] as List?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            _initialPoints();
        final int barWhite = (gameData['barWhite'] as num?)?.toInt() ?? 0;
        final int barBlack = (gameData['barBlack'] as num?)?.toInt() ?? 0;
        final int offWhite = (gameData['offWhite'] as num?)?.toInt() ?? 0;
        final int offBlack = (gameData['offBlack'] as num?)?.toInt() ?? 0;
        final List<int> dice = (gameData['dice'] as List?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            <int>[];
        final List<int> remainingMoves = (gameData['remainingMoves'] as List?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            <int>[];

        final whiteUid = gameData['whitePlayerUid'] as String?;
        final whiteName = gameData['whitePlayerName'] as String? ?? 'Beyaz';
        final blackName = gameData['blackPlayerName'] as String? ?? 'Siyah';
        final whiteReady = gameData['whiteReady'] == true;
        final blackReady = gameData['blackReady'] == true;
        final isWhite = myUid == whiteUid;
        final myReady = isWhite ? whiteReady : blackReady;
        final partnerReady = isWhite ? blackReady : whiteReady;

        final whiteRematch = gameData['whiteRematch'] == true;
        final blackRematch = gameData['blackRematch'] == true;
        final myRematch = isWhite ? whiteRematch : blackRematch;
        final partnerRematch = isWhite ? blackRematch : whiteRematch;

        final isWaitingReady = status == 'waiting_ready';
        final turn = gameData['turn'] as String? ?? 'w';
        final winnerUid = gameData['winnerUid'] as String?;
        final winnerReason = gameData['winnerReason'] as String?;
        final lastEventText = gameData['lastEventText'] as String?;

        final isMyTurn = !isWaitingReady && ((turn == 'w' && isWhite) || (turn == 'b' && !isWhite));
        final isGameOver = status != 'active' && status != 'waiting_ready';

        _currentCoupleId = coupleId;
        _currentIsWhite = isWhite;
        _hasActiveGame = true;

        if (status == 'active' || status == 'waiting_ready') {
          final myOnlineKey = isWhite ? 'whiteOnline' : 'blackOnline';
          if (gameData[myOnlineKey] != true) {
            DatabaseService().setGameOnlineStatus(
              coupleId: coupleId,
              gameType: 'backgammon',
              isPlayer1: isWhite,
              isOnline: true,
            );
          }
        }

        if (isMyTurn && status == 'active') {
          final turnKey = '$turn-${remainingMoves.length}-${points.hashCode}';
          if (_lastVibratedTurnKey != turnKey) {
            _lastVibratedTurnKey = turnKey;
            HapticFeedback.selectionClick();
          }
        }

        final int myBar = isWhite ? barWhite : barBlack;
        // Eğer kırık pul varsa otomatik olarak Bar'ı (-1) seçili tut
        final int? effectiveSelectedFrom = (isMyTurn && myBar > 0 && remainingMoves.isNotEmpty)
            ? -1
            : _selectedFrom;

        final List<_BgMove> legalMoves = (isMyTurn && effectiveSelectedFrom != null)
            ? _getLegalMovesFrom(
                from: effectiveSelectedFrom,
                points: points,
                isWhite: isWhite,
                myBar: myBar,
                remainingMoves: remainingMoves,
              )
            : <_BgMove>[];

        return StreamBuilder<List<ChatMessage>>(
          stream: DatabaseService().messagesStream(coupleId),
          builder: (context, chatSnapshot) {
            final messages = chatSnapshot.data ?? [];
            final unreadCount = messages.where((m) => m.senderId != myUid && !m.isRead).length;

            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                _showExitDialog(context, coupleId);
              },
              child: Scaffold(
                backgroundColor: isDark ? const Color(0xFF100D0B) : const Color(0xFFFDF8F4),
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    onPressed: () => _showExitDialog(context, coupleId),
                  ),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(loc('Klasik Tavla 🎲', 'Classic Backgammon 🎲'),
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      Text(
                        isWhite ? 'Sedef Beyaz Pullar' : 'Kehribar Siyah Pullar',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    _buildChatActionButton(context, unreadCount),
                    IconButton(
                      tooltip: loc('Yeni Oyun', 'New Game'),
                      icon: const Icon(Icons.refresh_rounded, color: Color(0xFFEA580C)),
                      onPressed: () => _confirmNewGame(context, coupleId, myUid, myName, partner),
                    ),
                    if (!isGameOver)
                      IconButton(
                        tooltip: loc('Pes Et', 'Resign'),
                        icon: const Icon(Icons.flag_outlined, color: Color(0xFFF43F5E)),
                        onPressed: () => _confirmResign(context, coupleId, myUid, partner?.id),
                      ),
                  ],
                ),
                body: SafeArea(
                  child: Column(
                    children: [
                      // Oyuncu Skor & Toplanan Pul Kartları
                      _buildScoreHeader(
                        myName: isWhite ? whiteName : blackName,
                        partnerName: isWhite ? blackName : whiteName,
                        myOff: isWhite ? offWhite : offBlack,
                        partnerOff: isWhite ? offBlack : offWhite,
                        myBar: isWhite ? barWhite : barBlack,
                        partnerBar: isWhite ? barBlack : barWhite,
                        isMyTurn: isMyTurn,
                        isGameOver: isGameOver,
                        isDark: isDark,
                      ),

                      // Bilgi Şeridi
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: isMyTurn
                                ? const Color(0xFFEA580C).withValues(alpha: 0.16)
                                : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            myBar > 0 && isMyTurn
                                ? loc('⚠️ Kırık pulun var! Önce ortadaki Bar\'dan oyuna girmelisin.', '⚠️ You have checkers on the bar! You must enter from the bar first.')
                                : (lastEventText ??
                                    (isMyTurn ? loc('Senin sıran! Zar at ve pullarını ilerlet.', 'Your turn! Roll dice and move checkers.') : loc('Partnerin oynuyor...', 'Partner is playing...'))),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),

                      // Tavla Tahtası
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final boardW = constraints.maxWidth;
                              final boardH = constraints.maxHeight;
                              return Stack(
                                children: [
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapUp: (details) {
                                      if (!isMyTurn || isGameOver || remainingMoves.isEmpty) return;
                                      _handleBoardTap(
                                        localPos: details.localPosition,
                                        boardW: boardW,
                                        boardH: boardH,
                                        points: points,
                                        barWhite: barWhite,
                                        barBlack: barBlack,
                                        offWhite: offWhite,
                                        offBlack: offBlack,
                                        remainingMoves: remainingMoves,
                                        legalMoves: legalMoves,
                                        isWhite: isWhite,
                                        coupleId: coupleId,
                                        myUid: myUid,
                                      );
                                    },
                                    child: CustomPaint(
                                      size: Size(boardW, boardH),
                                      painter: _BackgammonBoardPainter(
                                        points: points,
                                        barWhite: barWhite,
                                        barBlack: barBlack,
                                        offWhite: offWhite,
                                        offBlack: offBlack,
                                        selectedFrom: effectiveSelectedFrom,
                                        legalMoves: legalMoves,
                                        isWhitePerspective: isWhite,
                                      ),
                                    ),
                                  ),

                                  if (isWaitingReady)
                                    _buildWaitingReadyOverlay(
                                      coupleId: coupleId,
                                      isWhite: isWhite,
                                      myReady: myReady,
                                      partnerReady: partnerReady,
                                    ),

                                  if (isGameOver)
                                    _buildGameOverOverlay(
                                      coupleId: coupleId,
                                      isWhite: isWhite,
                                      myUid: myUid,
                                      winnerUid: winnerUid,
                                      winnerReason: winnerReason,
                                      myRematch: myRematch,
                                      partnerRematch: partnerRematch,
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),

                      // Alt Kontrol Paneli: Zarlar, Zar At Butonu ve Pul Toplama (Bear Off) Butonu
                      _buildBottomControlBar(
                        coupleId: coupleId,
                        points: points,
                        barWhite: barWhite,
                        barBlack: barBlack,
                        offWhite: offWhite,
                        offBlack: offBlack,
                        dice: dice,
                        remainingMoves: remainingMoves,
                        legalMoves: legalMoves,
                        isMyTurn: isMyTurn && !isGameOver,
                        isWhite: isWhite,
                        myUid: myUid,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Tahta üzerine dokunulduğunda hangi hanenin (0..23) veya Bar'ın (-1) seçildiğini hesaplar
  void _handleBoardTap({
    required Offset localPos,
    required double boardW,
    required double boardH,
    required List<int> points,
    required int barWhite,
    required int barBlack,
    required int offWhite,
    required int offBlack,
    required List<int> remainingMoves,
    required List<_BgMove> legalMoves,
    required bool isWhite,
    required String coupleId,
    required String? myUid,
  }) {
    const double frame = 12.0;
    final double innerW = boardW - frame * 2;
    final double barW = innerW * 0.085;
    final double halfW = (innerW - barW) / 2.0;
    final double pointW = halfW / 6.0;

    final double rx = localPos.dx - frame;
    final double ry = localPos.dy - frame;
    final double innerH = boardH - frame * 2;
    if (rx < 0 || rx > innerW || ry < 0 || ry > innerH) return;

    final bool isTopHalf = ry < innerH / 2.0;
    final bool isBarTap = rx >= halfW && rx <= (halfW + barW);

    final int myBar = isWhite ? barWhite : barBlack;

    if (isBarTap) {
      if (myBar > 0) {
        HapticFeedback.selectionClick();
        setState(() => _selectedFrom = -1);
      }
      return;
    }

    // 0..11 sütun indeksi (Soldan sağa: 0..5 sol yarı, 6..11 sağ yarı)
    int col;
    if (rx < halfW) {
      col = (rx ~/ pointW).clamp(0, 5);
    } else {
      col = (6 + ((rx - halfW - barW) ~/ pointW)).clamp(6, 11);
    }

    // Perspektife göre gerçek hane indeksini (0..23) bul:
    // Beyaz perspektif:
    //   Üst sıra soldan sağa: 11, 10, 9, 8, 7, 6 | BAR | 5, 4, 3, 2, 1, 0
    //   Alt sıra soldan sağa: 12, 13, 14, 15, 16, 17 | BAR | 18, 19, 20, 21, 22, 23
    // Siyah perspektif (ters çevrilmiş):
    //   Üst sıra soldan sağa: 12, 13, 14, 15, 16, 17 | BAR | 18, 19, 20, 21, 22, 23
    //   Alt sıra soldan sağa: 11, 10, 9, 8, 7, 6 | BAR | 5, 4, 3, 2, 1, 0
    int tappedPoint;
    if (isWhite) {
      if (isTopHalf) {
        tappedPoint = 11 - col;
      } else {
        tappedPoint = 12 + col;
      }
    } else {
      if (isTopHalf) {
        tappedPoint = 12 + col;
      } else {
        tappedPoint = 11 - col;
      }
    }

    // 1. Tıklanan hane geçerli bir hedef mi?
    final matchingMove = legalMoves.where((m) => m.to == tappedPoint).firstOrNull;
    if (matchingMove != null) {
      _applyMove(
        coupleId: coupleId,
        move: matchingMove,
        currentPoints: points,
        barWhite: barWhite,
        barBlack: barBlack,
        offWhite: offWhite,
        offBlack: offBlack,
        remainingMoves: remainingMoves,
        isWhite: isWhite,
        myUid: myUid,
      );
      return;
    }

    // 2. Kırık pul varsa başka hane seçilemez
    if (myBar > 0) {
      setState(() => _selectedFrom = -1);
      return;
    }

    // 3. Kendi pulumuzun olduğu bir haneye tıklandıysa onu seç
    final val = points[tappedPoint];
    if ((isWhite && val > 0) || (!isWhite && val < 0)) {
      HapticFeedback.selectionClick();
      setState(() {
        _selectedFrom = (_selectedFrom == tappedPoint) ? null : tappedPoint;
      });
    } else {
      setState(() => _selectedFrom = null);
    }
  }

  Widget _buildScoreHeader({
    required String myName,
    required String partnerName,
    required int myOff,
    required int partnerOff,
    required int myBar,
    required int partnerBar,
    required bool isMyTurn,
    required bool isGameOver,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: _buildPlayerBadge(
              name: '$myName (Sen)',
              offCount: myOff,
              barCount: myBar,
              isTurn: isMyTurn && !isGameOver,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildPlayerBadge(
              name: partnerName,
              offCount: partnerOff,
              barCount: partnerBar,
              isTurn: !isMyTurn && !isGameOver,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerBadge({
    required String name,
    required int offCount,
    required int barCount,
    required bool isTurn,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isTurn
            ? const Color(0xFFEA580C).withValues(alpha: isDark ? 0.25 : 0.14)
            : (isDark ? const Color(0xFF1C1613) : Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isTurn ? const Color(0xFFEA580C) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  barCount > 0
                      ? loc('Toplanan: $offCount/15 • Kırık: $barCount', 'Off: $offCount/15 • Bar: $barCount')
                      : 'Toplanan Pul: $offCount / 15',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: barCount > 0
                        ? const Color(0xFFEF4444)
                        : (isDark ? Colors.white70 : Colors.black54),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEA580C).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$offCount',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: Color(0xFFEA580C),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControlBar({
    required String coupleId,
    required List<int> points,
    required int barWhite,
    required int barBlack,
    required int offWhite,
    required int offBlack,
    required List<int> dice,
    required List<int> remainingMoves,
    required List<_BgMove> legalMoves,
    required bool isMyTurn,
    required bool isWhite,
    required String? myUid,
    required bool isDark,
  }) {
    final bearOffMove = legalMoves.where((m) => m.to == 24).firstOrNull;
    final bool canRollNow = isMyTurn && remainingMoves.isEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1613) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Zar Görünümü
            if (dice.length == 2) ...[
              _buildDieBox(dice[0], remainingMoves.contains(dice[0]), isDark),
              const SizedBox(width: 8),
              _buildDieBox(dice[1], remainingMoves.isNotEmpty, isDark),
            ] else
              Text(loc('🎲 Zar bekleniyor', '🎲 Waiting for roll'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),

            const SizedBox(width: 12),

            // Kalan Hamle Rozetleri
            if (remainingMoves.isNotEmpty)
              Expanded(
                child: Wrap(
                  spacing: 4,
                  children: remainingMoves
                      .map(
                        (m) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '+$m',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              )
            else
              const Spacer(),

            // Pul Toplama (Bear Off) Butonu (Eğer seçili pul dışarı çıkabiliyorsa)
            if (bearOffMove != null) ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.download_done_rounded, size: 18),
                label: Text(loc('Pulu Topla', 'Bear Off'), style: const TextStyle(fontWeight: FontWeight.w800)),
                onPressed: () => _applyMove(
                  coupleId: coupleId,
                  move: bearOffMove,
                  currentPoints: points,
                  barWhite: barWhite,
                  barBlack: barBlack,
                  offWhite: offWhite,
                  offBlack: offBlack,
                  remainingMoves: remainingMoves,
                  isWhite: isWhite,
                  myUid: myUid,
                ),
              ),
              const SizedBox(width: 8),
            ],

            // Zar At Butonu
            SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: canRollNow ? const Color(0xFFEA580C) : Colors.grey.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.casino_rounded, size: 20),
                label: Text(
                  _isRolling ? loc('Atılıyor...', 'Rolling...') : loc('Zar At', 'Roll Dice'),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
                onPressed: canRollNow
                    ? () => _rollDice(
                          coupleId: coupleId,
                          points: points,
                          isWhite: isWhite,
                          myBar: isWhite ? barWhite : barBlack,
                        )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDieBox(int value, bool active, bool isDark) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: active ? 1.0 : 0.45,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? const Color(0xFFD97706) : Colors.grey,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: CustomPaint(
          painter: _DiePipsPainter(value: value),
        ),
      ),
    );
  }

  Widget _buildWaitingReadyOverlay({
    required String coupleId,
    required bool isWhite,
    required bool myReady,
    required bool partnerReady,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎲', style: TextStyle(fontSize: 42)),
            const SizedBox(height: 10),
            Text(loc('Tavla Tahtası Hazır', 'Backgammon Board Ready'),
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              loc('İki taraf da hazır olduğunda zarlar açılacak.', 'Dice will unlock when both sides are ready.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildReadyBadge('Sen', myReady)),
                const SizedBox(width: 8),
                Expanded(child: _buildReadyBadge('Partnerin', partnerReady)),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 180,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: myReady ? const Color(0xFF10B981) : const Color(0xFFEA580C),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  DatabaseService().setGamePlayerReady(
                    coupleId: coupleId,
                    gameType: 'backgammon',
                    isPlayer1: isWhite,
                    isReady: !myReady,
                  );
                },
                child: Text(
                  myReady ? loc('Hazırsın ✅', 'You\'re Ready ✅') : loc('Hazırım 🚀', 'I\'m Ready 🚀'),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadyBadge(String label, bool ready) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: ready
            ? const Color(0xFF10B981).withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ready ? const Color(0xFF10B981) : Colors.white24),
      ),
      child: Column(
        children: [
          Icon(
            ready ? Icons.check_circle_rounded : Icons.hourglass_empty_rounded,
            color: ready ? const Color(0xFF10B981) : Colors.amber,
            size: 18,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildGameOverOverlay({
    required String coupleId,
    required bool isWhite,
    required String? myUid,
    required String? winnerUid,
    required String? winnerReason,
    required bool myRematch,
    required bool partnerRematch,
  }) {
    final isWinner = winnerUid != null && winnerUid == myUid;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(22),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isWinner ? '🏆' : '🎲', style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 10),
            Text(
              isWinner ? loc('Tebrikler, Kazandın!', 'Congratulations, You Won!') : loc('Partnerin Kazandı!', 'Partner Won!'),
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              winnerReason ?? loc('Oyun tamamlandı', 'Game completed'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 18),
            if (partnerRematch && !myRematch)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(loc('Partnerin rövanş istiyor! 🔥', 'Partner wants a rematch! 🔥'),
                  style: TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.w800),
                ),
              ),
            SizedBox(
              width: 190,
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: myRematch ? Colors.grey.shade700 : const Color(0xFFEA580C),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: Text(
                  myRematch ? loc('Partner Bekleniyor...', 'Waiting for partner...') : loc('Tekrar Oyna', 'Play Again'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                onPressed: myRematch
                    ? null
                    : () {
                        DatabaseService().requestGameRematch(
                          coupleId: coupleId,
                          gameType: 'backgammon',
                          isPlayer1: isWhite,
                          resetData: buildInitialGameData(),
                        );
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartLobby({
    required BuildContext context,
    required bool isDark,
    required String? status,
    required String coupleId,
    required String? myUid,
    required String myName,
    required dynamic partner,
  }) {
    return Scaffold(
      backgroundColor: isDark ? LoveraColors.darkBg : LoveraColors.lightBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(loc('Klasik Tavla 🎲', 'Classic Backgammon 🎲'), style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: isDark ? LoveraColors.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFEA580C).withValues(alpha: 0.18),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFEA580C), Color(0xFF9A3412)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('🎲', style: TextStyle(fontSize: 40)),
                  ),
                ),
                const SizedBox(height: 20),
                Text(loc('Canlı Klasik Tavla', 'Live Classic Backgammon'),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  status == 'rejected'
                      ? loc('Önceki tavla daveti kabul edilmedi. Yeniden davet gönderebilirsin.', 'The previous backgammon invitation was declined. You can send a new invitation.')
                      : loc('Gerçek tavla kuralları, çift zar 4 hamle, pul kırma (Bar), kapı alma, pul toplama ve Mars ile karşılıklı tavla heyecanı!', 'Real backgammon rules, double dice 4 moves, hitting, making points, bearing off and gammon excitement!'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                  ),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEA580C),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 24),
                    label: Text(loc('Oyna', 'Play'),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    onPressed: () => _initNewGame(coupleId, myUid, myName, partner),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPendingInvitationView(BuildContext context, bool isDark, bool isSender) {
    return Scaffold(
      backgroundColor: isDark ? LoveraColors.darkBg : LoveraColors.lightBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(loc('Klasik Tavla 🎲', 'Classic Backgammon 🎲'), style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: isDark ? LoveraColors.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFFEA580C)),
                const SizedBox(height: 24),
                Text(
                  isSender ? loc('Partnerin Bekleniyor...', 'Waiting for Partner...') : loc('Tavla Daveti Alındı', 'Backgammon Invite Received'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  isSender
                      ? loc('Partnerine tavla daveti gönderildi. Kabul ettiğinde tahta açılacak.', 'Backgammon invite sent to partner. The board will open when accepted.')
                      : 'Partnerin seni tavla oynamaya davet etti.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatActionButton(BuildContext context, int unreadCount) {
    return IconButton(
      tooltip: loc('Sohbet 💬', 'Chat 💬'),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: unreadCount > 0
                  ? const Color(0xFFEC4899).withValues(alpha: 0.18)
                  : const Color(0xFFEA580C).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_rounded,
              color: unreadCount > 0 ? const Color(0xFFEC4899) : const Color(0xFFEA580C),
              size: 20,
            ),
          ),
          if (unreadCount > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEC4899),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  unreadCount > 9 ? '9+' : '$unreadCount',
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
                ),
              ),
            ),
        ],
      ),
      onPressed: () => _openInGameChatSheet(context),
    );
  }

  Future<void> _initNewGame(
    String coupleId,
    String? myUid,
    String myName,
    dynamic partner,
  ) async {
    if (myUid == null || partner == null) return;
    final partnerUid = partner.id ?? '';
    if (partnerUid.isEmpty) return;
    final name = myName.isNotEmpty ? myName : 'Partnerin';

    final cleanName = AppUser.extractFirstName(name);
    await DatabaseService().sendGameRequest(
      gameType: 'backgammon',
      gameTitle: 'Klasik Tavla 🎲',
      partnerUid: partnerUid,
      fromName: cleanName,
      coupleId: coupleId,
      initialGameData: buildInitialGameData(),
    );

    NotificationService().sendPushToPartner(
      partnerUid: partnerUid,
      title: loc('Tavla Daveti 🎲', 'Backgammon Invitation 🎲'),
      body: loc('$cleanName seninle tavla oynamak istiyor!', '$cleanName wants to play backgammon with you!'),
      titleTr: 'Tavla Daveti 🎲',
      titleEn: 'Backgammon Invitation 🎲',
      bodyTr: '$cleanName seninle tavla oynamak istiyor!',
      bodyEn: '$cleanName wants to play backgammon with you!',
      data: {'type': 'game_request', 'game': 'backgammon'},
    );
  }

  void _confirmNewGame(
    BuildContext context,
    String coupleId,
    String? myUid,
    String myName,
    dynamic partner,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc('Yeni Tavla Oyunu', 'New Backgammon Game')),
        content: Text(loc('Mevcut pullar sıfırlanarak yeni bir tavla oyunu başlatılsın mı?', 'Reset checkers and start a new backgammon game?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(loc('İptal', 'Cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEA580C)),
            onPressed: () {
              Navigator.pop(ctx);
              _initNewGame(coupleId, myUid, myName, partner);
            },
            child: Text(loc('Başlat', 'Start'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmResign(
    BuildContext context,
    String coupleId,
    String? myUid,
    String? partnerUid,
  ) {
    if (myUid == null || partnerUid == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc('Pes Et', 'Resign')),
        content: Text(loc('Tavla oyunundan çekilmek istediğinize emin misiniz?', 'Are you sure you want to resign from backgammon?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(loc('Vazgeç', 'Cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF43F5E)),
            onPressed: () {
              Navigator.pop(ctx);
              DatabaseService().resignGame(
                coupleId: coupleId,
                gameType: 'backgammon',
                resignedUid: myUid,
                winnerUid: partnerUid,
              );
            },
            child: Text(loc('Pes Et', 'Resign'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showExitDialog(BuildContext context, String coupleId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc('Oyundan Çık', 'Leave Game')),
        content: Text(loc('Oyundan çıkarsanız tavla maçı sonlanacaktır. Çıkmak istediğinize emin misiniz?', 'If you exit, the match will end. Are you sure?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(loc('Vazgeç', 'Cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF43F5E)),
            onPressed: () {
              Navigator.pop(ctx);
              DatabaseService().resetGame(coupleId: coupleId, gameType: 'backgammon');
              Navigator.pop(context);
            },
            child: Text(loc('Çık', 'Exit'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openInGameChatSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.85,
        decoration: BoxDecoration(
          color: isDark ? LoveraColors.darkBg : const Color(0xFFF7F8FA),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: ChatView(
            isEmbedded: true,
            onBackToHome: () => Navigator.pop(ctx),
          ),
        ),
      ),
    );
  }
}

/// Ceviz/Sedef İşlemeli Geleneksel Tavla Tahtası, 24 Üçgen Hane, Orta Bar ve Pullar Çizicisi
class _BackgammonBoardPainter extends CustomPainter {
  final List<int> points;
  final int barWhite;
  final int barBlack;
  final int offWhite;
  final int offBlack;
  final int? selectedFrom;
  final List<_BgMove> legalMoves;
  final bool isWhitePerspective;

  _BackgammonBoardPainter({
    required this.points,
    required this.barWhite,
    required this.barBlack,
    required this.offWhite,
    required this.offBlack,
    required this.selectedFrom,
    required this.legalMoves,
    required this.isWhitePerspective,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const double frame = 12.0;

    // 1. Dış Ceviz Ahşap Kasa
    final outerRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      const Radius.circular(18),
    );
    canvas.drawRRect(
      outerRRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF451A03), Color(0xFF290F02), Color(0xFF451A03)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    final innerRect = Rect.fromLTWH(frame, frame, w - frame * 2, h - frame * 2);
    final innerW = innerRect.width;
    final innerH = innerRect.height;
    final barW = innerW * 0.085;
    final halfW = (innerW - barW) / 2.0;
    final pointW = halfW / 6.0;
    final triH = innerH * 0.43;

    // 2. İç Ahşap Zemin
    canvas.drawRect(
      innerRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFDE68A), Color(0xFFF5D0A9), Color(0xFFFDE68A)],
        ).createShader(innerRect),
    );

    // 3. Orta Bar (Kırık Pullar Bölmesi ve Menteşe Detayı)
    final barRect = Rect.fromLTWH(frame + halfW, frame, barW, innerH);
    canvas.drawRect(
      barRect,
      Paint()..color = const Color(0xFF3E1604),
    );

    // 4. 24 Üçgen Hane (Points) ve Pullar
    final targetSet = legalMoves.map((m) => m.to).toSet();

    for (int col = 0; col < 12; col++) {
      final double xLeft = frame +
          (col < 6 ? col * pointW : halfW + barW + (col - 6) * pointW);

      final int topPointIdx = isWhitePerspective ? (11 - col) : (12 + col);
      final int botPointIdx = isWhitePerspective ? (12 + col) : (11 - col);

      _drawTrianglePoint(
        canvas: canvas,
        xLeft: xLeft,
        pointW: pointW,
        baseY: frame,
        tipY: frame + triH,
        pointIdx: topPointIdx,
        isSelected: selectedFrom == topPointIdx,
        isTarget: targetSet.contains(topPointIdx),
      );

      _drawTrianglePoint(
        canvas: canvas,
        xLeft: xLeft,
        pointW: pointW,
        baseY: frame + innerH,
        tipY: frame + innerH - triH,
        pointIdx: botPointIdx,
        isSelected: selectedFrom == botPointIdx,
        isTarget: targetSet.contains(botPointIdx),
      );

      // Üst hanedeki pulları çiz
      _drawCheckersOnPoint(
        canvas: canvas,
        centerX: xLeft + pointW / 2,
        baseY: frame,
        goingDown: true,
        count: points[topPointIdx],
        checkerRadius: math.min(pointW * 0.43, triH / 11),
        isSelected: selectedFrom == topPointIdx,
      );

      // Alt hanedeki pulları çiz
      _drawCheckersOnPoint(
        canvas: canvas,
        centerX: xLeft + pointW / 2,
        baseY: frame + innerH,
        goingDown: false,
        count: points[botPointIdx],
        checkerRadius: math.min(pointW * 0.43, triH / 11),
        isSelected: selectedFrom == botPointIdx,
      );
    }

    // 5. Ortadaki Bar Üzerindeki Kırık Pullar
    final double barCenterX = barRect.center.dx;
    final double checkerR = math.min(pointW * 0.42, barW * 0.42);
    if (barWhite > 0) {
      _drawBarStack(
        canvas: canvas,
        centerX: barCenterX,
        centerY: frame + innerH * 0.32,
        count: barWhite,
        isWhiteChecker: true,
        radius: checkerR,
        isSelected: selectedFrom == -1 && isWhitePerspective,
      );
    }
    if (barBlack > 0) {
      _drawBarStack(
        canvas: canvas,
        centerX: barCenterX,
        centerY: frame + innerH * 0.68,
        count: barBlack,
        isWhiteChecker: false,
        radius: checkerR,
        isSelected: selectedFrom == -1 && !isWhitePerspective,
      );
    }
  }

  void _drawTrianglePoint({
    required Canvas canvas,
    required double xLeft,
    required double pointW,
    required double baseY,
    required double tipY,
    required int pointIdx,
    required bool isSelected,
    required bool isTarget,
  }) {
    final path = Path()
      ..moveTo(xLeft, baseY)
      ..lineTo(xLeft + pointW, baseY)
      ..lineTo(xLeft + pointW / 2.0, tipY)
      ..close();

    final bool isEven = pointIdx % 2 == 0;
    final Color baseColor = isEven ? const Color(0xFF9A3412) : const Color(0xFF78350F);

    canvas.drawPath(path, Paint()..color = baseColor);

    if (isSelected) {
      canvas.drawPath(
        path,
        Paint()..color = const Color(0xFFFBBF24).withValues(alpha: 0.45),
      );
    }

    if (isTarget) {
      canvas.drawPath(
        path,
        Paint()..color = const Color(0xFF10B981).withValues(alpha: 0.50),
      );
      final targetMarkerY = baseY + (tipY - baseY) * 0.65;
      canvas.drawCircle(
        Offset(xLeft + pointW / 2.0, targetMarkerY),
        6.5,
        Paint()..color = const Color(0xFF10B981),
      );
    }
  }

  void _drawCheckersOnPoint({
    required Canvas canvas,
    required double centerX,
    required double baseY,
    required bool goingDown,
    required int count,
    required double checkerRadius,
    required bool isSelected,
  }) {
    if (count == 0) return;
    final bool isWhiteChecker = count > 0;
    final int absCount = count.abs();
    final int visibleCount = math.min(absCount, 5);
    final double step = checkerRadius * 1.92;

    for (int i = 0; i < visibleCount; i++) {
      final double cy = goingDown
          ? (baseY + checkerRadius + 2 + i * step)
          : (baseY - checkerRadius - 2 - i * step);
      final bool isTopChecker = (i == visibleCount - 1);

      _drawSingleChecker(
        canvas: canvas,
        center: Offset(centerX, cy),
        radius: checkerRadius,
        isWhiteChecker: isWhiteChecker,
        highlight: isSelected && isTopChecker,
        badgeCount: (isTopChecker && absCount > 5) ? absCount : null,
      );
    }
  }

  void _drawBarStack({
    required Canvas canvas,
    required double centerX,
    required double centerY,
    required int count,
    required bool isWhiteChecker,
    required double radius,
    required bool isSelected,
  }) {
    _drawSingleChecker(
      canvas: canvas,
      center: Offset(centerX, centerY),
      radius: radius,
      isWhiteChecker: isWhiteChecker,
      highlight: isSelected,
      badgeCount: count > 1 ? count : null,
    );
  }

  void _drawSingleChecker({
    required Canvas canvas,
    required Offset center,
    required double radius,
    required bool isWhiteChecker,
    required bool highlight,
    int? badgeCount,
  }) {
    // Gölge
    canvas.drawCircle(
      center + const Offset(1.5, 2.5),
      radius,
      Paint()..color = Colors.black.withValues(alpha: 0.4),
    );

    // Gövde
    final gradient = isWhiteChecker
        ? const RadialGradient(
            colors: [Color(0xFFFFFFFF), Color(0xFFF3E8D2), Color(0xFFD6C7B2)],
          )
        : const RadialGradient(
            colors: [Color(0xFF4B5563), Color(0xFF1F2937), Color(0xFF090D16)],
          );

    canvas.drawCircle(
      center,
      radius,
      Paint()..shader = gradient.createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    // İç sedef yüzük
    canvas.drawCircle(
      center,
      radius * 0.72,
      Paint()
        ..color = isWhiteChecker
            ? const Color(0xFFB45309).withValues(alpha: 0.35)
            : const Color(0xFFF59E0B).withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Seçili pul ışıltısı
    if (highlight) {
      canvas.drawCircle(
        center,
        radius + 2,
        Paint()
          ..color = const Color(0xFF10B981)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8,
      );
    }

    if (badgeCount != null) {
      final tp = TextPainter(
        text: TextSpan(
          text: '$badgeCount',
          style: TextStyle(
            color: isWhiteChecker ? Colors.black87 : Colors.white,
            fontSize: radius * 0.85,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _BackgammonBoardPainter oldDelegate) => true;
}

/// Zar Noktaları (Pips) Çizicisi
class _DiePipsPainter extends CustomPainter {
  final int value;
  _DiePipsPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = w * 0.085;
    final paint = Paint()..color = value == 1 ? const Color(0xFFDC2626) : const Color(0xFF1F2937);

    final c = Offset(w * 0.5, h * 0.5);
    final tl = Offset(w * 0.26, h * 0.26);
    final tr = Offset(w * 0.74, h * 0.26);
    final bl = Offset(w * 0.26, h * 0.74);
    final br = Offset(w * 0.74, h * 0.74);
    final ml = Offset(w * 0.26, h * 0.5);
    final mr = Offset(w * 0.74, h * 0.5);

    if (value == 1 || value == 3 || value == 5) {
      canvas.drawCircle(c, value == 1 ? r * 1.35 : r, paint);
    }
    if (value >= 2) {
      canvas.drawCircle(tl, r, paint);
      canvas.drawCircle(br, r, paint);
    }
    if (value >= 4) {
      canvas.drawCircle(tr, r, paint);
      canvas.drawCircle(bl, r, paint);
    }
    if (value == 6) {
      canvas.drawCircle(ml, r, paint);
      canvas.drawCircle(mr, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DiePipsPainter oldDelegate) => oldDelegate.value != value;
}
