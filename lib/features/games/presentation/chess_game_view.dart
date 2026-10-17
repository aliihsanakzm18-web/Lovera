import 'dart:async';

import 'package:chess/chess.dart' as chess_lib;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../chat/presentation/chat_view.dart';

class ChessGameView extends ConsumerStatefulWidget {
  const ChessGameView({super.key});

  @override
  ConsumerState<ChessGameView> createState() => _ChessGameViewState();
}

class _ChessGameViewState extends ConsumerState<ChessGameView> with WidgetsBindingObserver {
  chess_lib.Chess _chess = chess_lib.Chess();
  String? _selectedSquare;
  List<String> _validMovesForSelected = [];
  String? _lastSyncFen;
  bool _isMoving = false;
  String? _optimisticFen;

  String? _lastVibratedTurnKey;
  final List<String> _files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
  final List<int> _ranks = [8, 7, 6, 5, 4, 3, 2, 1];

  String? _currentCoupleId;
  bool? _currentIsWhite;

  bool _hasActiveGame = false;
  bool _isExitingDueToPartner = false;

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
    ref.read(isChessScreenOpenProvider.notifier).state = false;
    _setOnlineStatus(false);
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
      DatabaseService().setChessOnlineStatus(
        coupleId: coupleId,
        isWhite: isWhite,
        isOnline: isOnline,
      );
    }
  }

  void _autoExitOnLeave() {
    final coupleId = _currentCoupleId ?? ref.read(coupleIdProvider);
    final myUid = DatabaseService().uid;
    if (coupleId != null && coupleId.isNotEmpty && myUid != null) {
      DatabaseService().exitChessGame(
        coupleId: coupleId,
        exitUid: myUid,
        exitReason: 'Partnerin oyundan ayrıldı',
      );
    }
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
              const Text('Oyun Bitti', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ],
          ),
          content: Text(
            reason.isNotEmpty ? reason : 'Partnerin oyundan çıktı.',
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
                if (mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('Tamam', style: TextStyle(fontWeight: FontWeight.w700)),
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
          title: const Text('Satranç'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: Text('Karşılıklı satranç oynamak için önce partnerinizle eşleşmelisiniz 💕'),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: DatabaseService().chessGameStream(coupleId),
      builder: (context, snapshot) {
        final gameData = snapshot.data?.data();

        final status = gameData?['status'] as String?;

        // Eğer aktif veya bekleme aşamasındaki oyundayken partner çıkmışsa (status == ended):
        if (_hasActiveGame && (status == 'ended' || status == null)) {
          final exitReason = gameData?['exitReason'] as String? ?? 'Partnerin oyundan çıktı.';
          final exitUid = gameData?['exitUid'] as String?;
          // Eğer kendimiz çıkmadıysak partnerin çıktığını bildir ve ekrandan at:
          if (exitUid != myUid) {
            _handlePartnerLeft(exitReason);
          }
        }

        // 1. Durum: Oyun hiç açılmamışsa, bitmişse veya reddedilmişse -> Temiz "Oyna" butonu ekranı
        if (gameData == null || !snapshot.hasData || status == null || status == 'rejected' || status == 'ended') {
          _hasActiveGame = false;
          return Scaffold(
            backgroundColor: isDark ? LoveraColors.darkBg : LoveraColors.lightBg,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text('Satranç ♟️', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: isDark ? LoveraColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: isDark ? LoveraColors.darkBorder : Colors.black.withValues(alpha: 0.05),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: LoveraColors.primary.withValues(alpha: 0.15),
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
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6D28D9).withValues(alpha: 0.35),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text('♟️', style: TextStyle(fontSize: 40)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Canlı Satranç',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        status == 'rejected'
                            ? 'Önceki oyun daveti kabul edilmedi. Yeniden istek gönderebilirsin.'
                            : 'Partnerinle karşılıklı, gerçek zamanlı satranç oyunu.',
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
                            backgroundColor: LoveraColors.primary,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                          label: const Text(
                            'Oyna',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
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

        // 2. Durum: İstek gönderildi, partner yanıtı bekleniyor
        if (status == 'invitation_pending') {
          final fromUid = gameData['fromUid'] as String?;
          final isSender = fromUid == myUid;
          return Scaffold(
            backgroundColor: isDark ? LoveraColors.darkBg : LoveraColors.lightBg,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text('Satranç ♟️', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: isDark ? LoveraColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: isDark ? LoveraColors.darkBorder : Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 50,
                        height: 50,
                        child: CircularProgressIndicator(
                          strokeWidth: 3.5,
                          valueColor: AlwaysStoppedAnimation<Color>(LoveraColors.primary),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        isSender ? 'Partnerin Bekleniyor...' : 'Oyun Daveti Alındı',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isSender
                            ? 'Partnerine satranç isteği gönderildi. Yanıt bekleniyor.'
                            : 'Partnerin seni oyuna davet etti. Ekrandaki menüden kabul edebilirsin.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (isSender)
                        OutlinedButton(
                          onPressed: () {
                            DatabaseService().chessGameStream(coupleId);
                            Navigator.pop(context);
                          },
                          child: const Text('İptal Et'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // Oyun verisi var -> Senkronize et
        final fen = gameData['fen'] as String? ?? 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
        if (_optimisticFen == fen) {
          _optimisticFen = null;
        } else if (_lastSyncFen != fen) {
          _lastSyncFen = fen;
          _chess = chess_lib.Chess.fromFEN(fen);
          _selectedSquare = null;
          _validMovesForSelected = [];
        }

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
        final isPaused = status == 'paused';
        final pausedByName = gameData['pausedByName'] as String? ?? 'Oyuncu';

        final turn = gameData['turn'] as String? ?? 'w';
        final winnerUid = gameData['winnerUid'] as String?;
        final winnerReason = gameData['winnerReason'] as String?;
        final lastMove = gameData['lastMove'] as Map<String, dynamic>?;

        final isMyTurn = !isWaitingReady && !isPaused && ((turn == 'w' && isWhite) || (turn == 'b' && !isWhite));
        final isGameOver = status != 'active' && status != 'waiting_ready' && status != 'paused';

        // Ekrandaki oyuncu durumunu (presence) güncelle
        _currentCoupleId = coupleId;
        _currentIsWhite = isWhite;
        _hasActiveGame = true;
        if (status == 'active' || status == 'waiting_ready' || status == 'paused') {
          final myOnlineKey = isWhite ? 'whiteOnline' : 'blackOnline';
          if (gameData[myOnlineKey] != true) {
            DatabaseService().setChessOnlineStatus(coupleId: coupleId, isWhite: isWhite, isOnline: true);
          }
        }

        final partnerOnline = isWhite ? (gameData['blackOnline'] == true) : (gameData['whiteOnline'] == true);

        // Sıra bana geldiğinde titreşim ver (Telefon titresin)
        if (isMyTurn && status == 'active') {
          final turnKey = '$fen-$turn';
          if (_lastVibratedTurnKey != turnKey) {
            _lastVibratedTurnKey = turnKey;
            HapticFeedback.heavyImpact();
            // İkinci bir dokunuş hissi için kısa gecikmeli hafif titreşim
            Future.delayed(const Duration(milliseconds: 150), () {
              HapticFeedback.mediumImpact();
            });
          }
        }

        // SÄ±ra kimde metni
        String turnStatusText;
        if (isGameOver) {
          if (winnerUid == myUid) {
            turnStatusText = '🎉 Kazandın! ($winnerReason)';
          } else if (winnerUid != null) {
            turnStatusText = 'Partnerin Kazandı ($winnerReason)';
          } else {
            turnStatusText = '🤝 Berabere ($status)';
          }
        } else if (isWaitingReady) {
          turnStatusText = myReady
              ? 'Hazırsın! Partnerinin hazır olması bekleniyor... ⏳'
              : 'Oyuna başlamak için "Hazırım" butonuna dokun!';
        } else {
          turnStatusText = isMyTurn ? 'Senin Sıran ⚡' : 'Partnerinin Sırası ⏳';
        }

        return StreamBuilder<List<ChatMessage>>(
          stream: DatabaseService().messagesStream(coupleId),
          builder: (context, chatSnapshot) {
            final messages = chatSnapshot.data ?? [];
            final unreadCount = messages.where((m) => m.senderId != myUid && !m.isRead).length;
            final partnerMsg = messages.where((m) => m.senderId != myUid).firstOrNull;
            final partnerMsgNotification = partnerMsg != null && !partnerMsg.isRead ? partnerMsg.text : null;

            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                _showExitDialog(context, coupleId);
              },
              child: Scaffold(
                backgroundColor: isDark ? LoveraColors.darkBg : LoveraColors.lightBg,
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    onPressed: () => _showExitDialog(context, coupleId),
                  ),
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Satranç ♟️',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                          Text(
                            isWhite ? 'Beyaz Taşlar' : 'Siyah Taşlar',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                actions: [
                  IconButton(
                    tooltip: 'Sohbet 💬',
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: unreadCount > 0
                                ? const Color(0xFFEC4899).withValues(alpha: 0.18)
                                : LoveraColors.primary.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.chat_bubble_rounded,
                            color: unreadCount > 0 ? const Color(0xFFEC4899) : LoveraColors.primary,
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
                                border: Border.all(
                                  color: isDark ? LoveraColors.darkSurface : Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                unreadCount > 9 ? '9+' : '$unreadCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    onPressed: () => _openInGameChatSheet(context),
                  ),
                  IconButton(
                    tooltip: 'Yeni Oyun',
                    icon: const Icon(Icons.refresh_rounded, color: LoveraColors.primary),
                    onPressed: () => _confirmNewGame(context, coupleId, myUid, myName, partner),
                  ),
                  if (!isGameOver)
                    IconButton(
                      tooltip: 'Pes Et',
                      icon: const Icon(Icons.flag_outlined, color: Color(0xFFF43F5E)),
                      onPressed: () => _confirmResign(context, coupleId, myUid, partner?.id),
                    ),
                ],
              ),
              body: SafeArea(
                child: Column(
                  children: [
                    // Rakip / Üst Oyuncu Bilgi Kartı
                    _buildPlayerHeader(
                      name: isWhite ? blackName : whiteName,
                      colorLabel: isWhite ? 'Siyah Taşlar' : 'Beyaz Taşlar',
                      isWhitePiece: !isWhite,
                      isTurn: !isMyTurn && !isGameOver,
                      isTop: true,
                      isDark: isDark,
                      messageNotification: partnerMsgNotification,
                      unreadCount: unreadCount,
                      onChatTap: () => _openInGameChatSheet(context),
                    ),

                // Satranç Tahtası
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E1B2C) : const Color(0xFFE2D9F3),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: LoveraColors.primary.withValues(alpha: 0.35),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: LoveraColors.primary.withValues(alpha: 0.22),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Stack(
                              children: [
                                _buildChessBoard(
                                  isWhitePerspective: isWhite,
                                  lastMove: lastMove,
                                  isMyTurn: isMyTurn,
                                  isGameOver: isGameOver || isWaitingReady,
                                  isDark: isDark,
                                  coupleId: coupleId,
                                  myUid: myUid,
                                  partnerUid: partner?.id,
                                ),
                                if (isWaitingReady)
                                  Container(
                                    color: (isDark ? Colors.black : Colors.black87).withValues(alpha: 0.72),
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: LoveraColors.primary.withValues(alpha: 0.2),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.sports_esports_rounded,
                                              color: Colors.white,
                                              size: 32,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          const Text(
                                            'Hazırlık Aşaması',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'İki taraf da hazır olduğunda tahta açılacaktır.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: 0.8),
                                              fontSize: 12.5,
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Expanded(child: _buildReadyBadge('Sen', myReady)),
                                              const SizedBox(width: 8),
                                              Expanded(child: _buildReadyBadge('Partnerin', partnerReady)),
                                            ],
                                          ),
                                          const SizedBox(height: 20),
                                          SizedBox(
                                            width: 180,
                                            height: 46,
                                            child: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: myReady
                                                    ? const Color(0xFF10B981)
                                                    : LoveraColors.primary,
                                                foregroundColor: Colors.white,
                                                elevation: 0,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(14),
                                                ),
                                              ),
                                              onPressed: () {
                                                DatabaseService().setChessPlayerReady(
                                                  coupleId: coupleId,
                                                  isWhite: isWhite,
                                                  isReady: !myReady,
                                                );
                                              },
                                              child: Text(
                                                myReady ? 'Hazırsın ✅' : 'Hazırım 🚀',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (isPaused)
                                    Container(
                                      color: (isDark ? Colors.black : Colors.black87).withValues(alpha: 0.8),
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                                      child: Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(14),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.pause_circle_filled_rounded,
                                                color: Color(0xFFF59E0B),
                                                size: 40,
                                              ),
                                            ),
                                            const SizedBox(height: 14),
                                            const Text(
                                              'Oyun Duraklatıldı',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 19,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              '$pausedByName oyunu duraklattı.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Colors.white.withValues(alpha: 0.85),
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: partnerOnline
                                                    ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                                    : const Color(0xFFEF4444).withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    partnerOnline ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                                    size: 15,
                                                    color: partnerOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    partnerOnline ? 'Partnerin oyunda' : 'Partnerin oyunda değil',
                                                    style: TextStyle(
                                                      color: partnerOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 18),
                                            SizedBox(
                                              width: 190,
                                              height: 44,
                                              child: ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: partnerOnline ? LoveraColors.primary : Colors.grey.shade700,
                                                  foregroundColor: Colors.white,
                                                  elevation: 0,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(14),
                                                  ),
                                                ),
                                                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                                                label: const Text(
                                                  'Devam Et',
                                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                                ),
                                                onPressed: () async {
                                                  if (!partnerOnline) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: const Text('Partnerin oyunda olmadığı için devam edilemez. Lütfen girmesini bekle 💕'),
                                                        backgroundColor: Colors.red.shade700,
                                                        duration: const Duration(seconds: 2),
                                                      ),
                                                    );
                                                    return;
                                                  }
                                                  final success = await DatabaseService().resumeChessGame(coupleId: coupleId);
                                                  if (!success && context.mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: const Text('Partnerin henüz oyuna dönmedi!'),
                                                        backgroundColor: Colors.red.shade700,
                                                        duration: const Duration(seconds: 2),
                                                      ),
                                                    );
                                                  }
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (isGameOver)
                                    Container(
                                      color: (isDark ? Colors.black : Colors.black87).withValues(alpha: 0.88),
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                                      child: Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(14),
                                              decoration: BoxDecoration(
                                                color: (winnerUid == myUid
                                                        ? const Color(0xFF10B981)
                                                        : (winnerUid != null ? const Color(0xFFEF4444) : LoveraColors.primary))
                                                    .withValues(alpha: 0.2),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                winnerUid == myUid
                                                    ? Icons.emoji_events_rounded
                                                    : (winnerUid != null ? Icons.sentiment_dissatisfied_rounded : Icons.handshake_rounded),
                                                color: winnerUid == myUid
                                                    ? const Color(0xFF10B981)
                                                    : (winnerUid != null ? const Color(0xFFEF4444) : Colors.white),
                                                size: 44,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              winnerUid == myUid
                                                  ? 'Kazandın! 🏆'
                                                  : (winnerUid != null ? 'Kaybettin 💔' : 'Berabere! 🤝'),
                                              style: TextStyle(
                                                color: winnerUid == myUid
                                                    ? const Color(0xFF34D399)
                                                    : (winnerUid != null ? const Color(0xFFF87171) : Colors.white),
                                                fontSize: 22,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              winnerReason != null && winnerReason.isNotEmpty
                                                  ? winnerReason
                                                  : (winnerUid == myUid
                                                      ? 'Tebrikler, harika bir oyundu!'
                                                      : 'Üzülme, bir sonraki oyunda şansını dene!'),
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Colors.white.withValues(alpha: 0.85),
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Expanded(child: _buildReadyBadge('Sen', myRematch)),
                                                const SizedBox(width: 8),
                                                Expanded(child: _buildReadyBadge('Partnerin', partnerRematch)),
                                              ],
                                            ),
                                            const SizedBox(height: 18),
                                            SizedBox(
                                              width: double.infinity,
                                              height: 44,
                                              child: ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: myRematch
                                                      ? const Color(0xFF10B981)
                                                      : LoveraColors.primary,
                                                  foregroundColor: Colors.white,
                                                  elevation: 0,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(14),
                                                  ),
                                                ),
                                                icon: Icon(
                                                  myRematch ? Icons.check_circle_rounded : Icons.replay_rounded,
                                                  size: 20,
                                                ),
                                                label: Text(
                                                  myRematch ? 'İstek Gönderildi ✅' : 'Tekrar Oyna 🔁',
                                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                                ),
                                                onPressed: () {
                                                  DatabaseService().requestChessRematch(
                                                    coupleId: coupleId,
                                                    isWhite: isWhite,
                                                  );
                                                },
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: SizedBox(
                                                    height: 42,
                                                    child: OutlinedButton.icon(
                                                      style: OutlinedButton.styleFrom(
                                                        foregroundColor: Colors.white,
                                                        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(14),
                                                        ),
                                                      ),
                                                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                                                      label: const Text('Mesajlaş', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                                      onPressed: () => _openInGameChatSheet(context),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: SizedBox(
                                                    height: 42,
                                                    child: OutlinedButton.icon(
                                                      style: OutlinedButton.styleFrom(
                                                        foregroundColor: const Color(0xFFF87171),
                                                        side: BorderSide(color: const Color(0xFFF87171).withValues(alpha: 0.5)),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(14),
                                                        ),
                                                      ),
                                                      icon: const Icon(Icons.exit_to_app_rounded, size: 18),
                                                      label: const Text('Çık', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                                      onPressed: () {
                                                        DatabaseService().resetChessGame(coupleId: coupleId);
                                                        Navigator.pop(context);
                                                      },
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Kendi / Alt Oyuncu Bilgi Kartı
                _buildPlayerHeader(
                  name: isWhite ? whiteName : blackName,
                  colorLabel: isWhite ? 'Beyaz Taşlar' : 'Siyah Taşlar',
                  isWhitePiece: isWhite,
                  isTurn: isMyTurn && !isGameOver,
                  isTop: false,
                  isDark: isDark,
                ),

                // Durum / Hamle Bildirimi Çubuğu
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  margin: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                  decoration: BoxDecoration(
                    color: isMyTurn
                        ? LoveraColors.primary.withValues(alpha: isDark ? 0.2 : 0.12)
                        : (isDark ? LoveraColors.darkSurface : Colors.white),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isMyTurn
                          ? LoveraColors.primary
                          : (isDark ? LoveraColors.darkBorder : Colors.black.withValues(alpha: 0.06)),
                      width: isMyTurn ? 1.5 : 1,
                    ),
                    boxShadow: isMyTurn
                        ? [
                            BoxShadow(
                              color: LoveraColors.primary.withValues(alpha: 0.18),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isMyTurn
                              ? LoveraColors.primary
                              : (isGameOver ? const Color(0xFFF59E0B) : Colors.grey.withValues(alpha: 0.2)),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isGameOver
                              ? Icons.emoji_events_rounded
                              : (isMyTurn ? Icons.flash_on_rounded : Icons.hourglass_empty_rounded),
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          turnStatusText,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: isMyTurn
                                ? (isDark ? const Color(0xFFC4B5FD) : LoveraColors.primaryDeep)
                                : (isDark ? LoveraColors.darkText : LoveraColors.textDark),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _openInGameChatSheet(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: LoveraColors.primary.withValues(alpha: isDark ? 0.25 : 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: LoveraColors.primary.withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.chat_bubble_outline_rounded, size: 14, color: LoveraColors.primary),
                                SizedBox(width: 5),
                                Text(
                                  'Mesaj',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: LoveraColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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

  Widget _buildReadyBadge(String label, bool isReady) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isReady
            ? const Color(0xFF10B981).withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isReady ? const Color(0xFF10B981) : Colors.white24,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isReady ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
            size: 15,
            color: isReady ? const Color(0xFF10B981) : Colors.white70,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '$label: ${isReady ? "Hazır" : "Bekleniyor"}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isReady ? const Color(0xFF10B981) : Colors.white70,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Üst ve alt oyuncu kartı
  Widget _buildPlayerHeader({
    required String name,
    required String colorLabel,
    required bool isWhitePiece,
    required bool isTurn,
    required bool isTop,
    required bool isDark,
    String? messageNotification,
    int unreadCount = 0,
    VoidCallback? onChatTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onChatTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          margin: EdgeInsets.fromLTRB(16, isTop ? 10 : 2, 16, isTop ? 2 : 10),
          decoration: BoxDecoration(
            color: (messageNotification != null || unreadCount > 0)
                ? (isDark ? const Color(0xFF2E1C38) : const Color(0xFFFDF2F8))
                : (isTurn
                    ? (isDark ? const Color(0xFF241E33) : const Color(0xFFF6F0FD))
                    : (isDark ? LoveraColors.darkSurface : Colors.white)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: (messageNotification != null || unreadCount > 0)
                  ? const Color(0xFFEC4899)
                  : (isTurn
                      ? LoveraColors.primary
                      : (isDark ? LoveraColors.darkBorder : Colors.black.withValues(alpha: 0.05))),
              width: (isTurn || messageNotification != null || unreadCount > 0) ? 1.5 : 1,
            ),
            boxShadow: (messageNotification != null || unreadCount > 0)
                ? [
                    BoxShadow(
                      color: const Color(0xFFEC4899).withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: isWhitePiece
                          ? const LinearGradient(
                              colors: [Color(0xFFFFFFFF), Color(0xFFE2E8F0)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : const LinearGradient(
                              colors: [Color(0xFF332042), Color(0xFF1E1428)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      border: Border.all(
                        color: isWhitePiece
                            ? const Color(0xFFA78BFA)
                            : const Color(0xFFC084FC).withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isWhitePiece
                              ? Colors.white.withValues(alpha: 0.3)
                              : Colors.black.withValues(alpha: 0.4),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        isWhitePiece ? '♔' : '♚',
                        style: TextStyle(
                          fontSize: 22,
                          color: isWhitePiece ? const Color(0xFF6B21A8) : const Color(0xFFF472B6),
                        ),
                      ),
                    ),
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: -3,
                      top: -3,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFFEC4899),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (messageNotification != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEC4899).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Yeni Mesaj 💬',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFEC4899),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      messageNotification ?? colorLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: messageNotification != null
                            ? (isDark ? const Color(0xFFF472B6) : const Color(0xFFDB2777))
                            : (isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted),
                        fontWeight: messageNotification != null ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (messageNotification != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  margin: const EdgeInsets.only(left: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEC4899), Color(0xFFDB2777)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEC4899).withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Oku',
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                )
              else if (isTurn)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: LoveraColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: LoveraColors.primary.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Hamle Sırası',
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // 8x8 Satranç Tahtası
  Widget _buildChessBoard({
    required bool isWhitePerspective,
    required Map<String, dynamic>? lastMove,
    required bool isMyTurn,
    required bool isGameOver,
    required bool isDark,
    required String coupleId,
    required String? myUid,
    required String? partnerUid,
  }) {
    final ranks = isWhitePerspective ? _ranks : _ranks.reversed.toList();
    final files = isWhitePerspective ? _files : _files.reversed.toList();

    // Romantik Lovera Tahta Renkleri
    // Açık Kare: Zarif İnci & Leylak Dokusu / Koyu Kare: Ametist & Asil Mürdüm Moru
    final lightSquareColor = isDark ? const Color(0xFFE8DEF0) : const Color(0xFFFBF7FD);
    final darkSquareColor = isDark ? const Color(0xFF53396D) : const Color(0xFF865EA6);

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
      itemCount: 64,
      itemBuilder: (context, index) {
        final rankIdx = index ~/ 8;
        final fileIdx = index % 8;

        final rank = ranks[rankIdx];
        final file = files[fileIdx];
        final square = '$file$rank';

        final isLightSquare = (fileIdx + rankIdx) % 2 == 0;
        Color squareColor = isLightSquare ? lightSquareColor : darkSquareColor;

        // Son hamle vurgusu: Sarı yerine Lovera temasına tam uyumlu "Işıltılı Lavanta / Pembe Ametist"
        final isLastMove = lastMove != null && (lastMove['from'] == square || lastMove['to'] == square);
        if (isLastMove) {
          squareColor = isLightSquare
              ? const Color(0xFFE9D5FF) // Yumuşak aydınlık lavanta
              : const Color(0xFF7E429B); // Zengin derin lavanta-mor
        }

        // Seçili kare vurgusu: Canlı Neon Magenta & Pembe
        final isSelected = _selectedSquare == square;
        if (isSelected) {
          squareColor = const Color(0xFFC026D3).withValues(alpha: 0.85);
        }

        final isValidTarget = _validMovesForSelected.contains(square);
        final piece = _chess.get(square);

        return GestureDetector(
          onTap: () => _handleSquareTap(
            square: square,
            isMyTurn: isMyTurn,
            isGameOver: isGameOver,
            isWhitePerspective: isWhitePerspective,
            coupleId: coupleId,
            myUid: myUid,
            partnerUid: partnerUid,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            color: squareColor,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Koordinat etiketleri
                if (fileIdx == 0)
                  Positioned(
                    top: 1,
                    left: 2,
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: isLightSquare
                            ? darkSquareColor.withValues(alpha: 0.5)
                            : lightSquareColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                if (rankIdx == 7)
                  Positioned(
                    bottom: 1,
                    right: 2,
                    child: Text(
                      file,
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: isLightSquare
                            ? darkSquareColor.withValues(alpha: 0.5)
                            : lightSquareColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ),

                // Son hamle bordür ışıltısı
                if (isLastMove)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFFD946EF).withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),

                // Geçerli hamle hedefi göstergesi
                if (isValidTarget)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutBack,
                    width: piece != null ? 36 : 13,
                    height: piece != null ? 36 : 13,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: piece != null
                          ? Colors.transparent
                          : const Color(0xFFEC4899).withValues(alpha: 0.55),
                      border: piece != null
                          ? Border.all(color: const Color(0xFFF43F5E), width: 3.5)
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFEC4899).withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),

                // Satranç Taşı İkonu (Özel Tasarımlı ve Canlı)
                if (piece != null)
                  _buildStyledPiece(
                    piece: piece,
                    isSelected: isSelected,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Lovera Temasına Özel Yüksek Kaliteli Satranç Taşı
  Widget _buildStyledPiece({
    required chess_lib.Piece piece,
    required bool isSelected,
  }) {
    final isWhite = piece.color == chess_lib.Color.WHITE;

    return AnimatedScale(
      scale: isSelected ? 1.15 : 1.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      child: AnimatedSlide(
        offset: isSelected ? const Offset(0, -0.08) : Offset.zero,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: CustomPaint(
          size: const Size(38, 38),
          painter: _ChessPiecePainter(
            pieceType: piece.type,
            isWhite: isWhite,
          ),
        ),
      ),
    );
  }

  // Kareye tıklandığında hamle veya seçim mantığı
  void _handleSquareTap({
    required String square,
    required bool isMyTurn,
    required bool isGameOver,
    required bool isWhitePerspective,
    required String coupleId,
    required String? myUid,
    required String? partnerUid,
  }) async {
    if (isGameOver || !isMyTurn || _isMoving) return;

    final clickedPiece = _chess.get(square);
    final myColor = isWhitePerspective ? chess_lib.Color.WHITE : chess_lib.Color.BLACK;

    // 1. Zaten seçili bir taş varsa ve tıklanan yer geçerli bir hedefse hamleyi yap
    if (_selectedSquare != null && _validMovesForSelected.contains(square)) {
      final from = _selectedSquare!;
      final to = square;

      setState(() => _isMoving = true);
      HapticFeedback.lightImpact();

      // Terfi (Pawn Promotion) kontrolü (Vezir terfisi)
      final moveSuccess = _chess.move({'from': from, 'to': to, 'promotion': 'q'});

      if (moveSuccess) {
        final newFen = _chess.fen;
        final nextTurn = _chess.turn == chess_lib.Color.WHITE ? 'w' : 'b';

        String? status;
        String? winnerUid;
        String? winnerReason;

        if (_chess.in_checkmate) {
          status = 'checkmate';
          winnerUid = myUid;
          winnerReason = 'Şah Mat 🏆';
        } else if (_chess.in_stalemate) {
          status = 'stalemate';
          winnerReason = 'Pat (Berabere)';
        } else if (_chess.in_draw) {
          status = 'draw';
          winnerReason = 'Berabere';
        }

        // Anında ekranı güncelle (Optimistic UI - bekleme sıfır)
        _optimisticFen = newFen;
        setState(() {
          _selectedSquare = null;
          _validMovesForSelected = [];
          _isMoving = false;
        });

        // Arka planda gecikmesiz Firestore'a yaz (unawaited)
        unawaited(
          DatabaseService().makeChessMove(
            coupleId: coupleId,
            newFen: newFen,
            nextTurn: nextTurn,
            moveData: {
              'from': from,
              'to': to,
              'playedBy': myUid,
            },
            status: status,
            winnerUid: winnerUid,
            winnerReason: winnerReason,
          ).catchError((e) {
            debugPrint('[CHESS] Hamle gönderilemedi: $e');
          }),
        );
      } else {
        setState(() {
          _selectedSquare = null;
          _validMovesForSelected = [];
          _isMoving = false;
        });
      }
      return;
    }

    // 2. Kendi rengindeki taşa tıklandıysa seç ve gidebileceği kareleri hesapla
    if (clickedPiece != null && clickedPiece.color == myColor) {
      HapticFeedback.selectionClick();
      final moves = _chess.moves({'square': square, 'verbose': true});
      final validSquares = moves.map((m) => m['to'] as String).toList();

      setState(() {
        _selectedSquare = square;
        _validMovesForSelected = validSquares;
      });
    } else {
      // Boş veya rakip taşa tıklanıp hedef değilse seçimi kaldır
      setState(() {
        _selectedSquare = null;
        _validMovesForSelected = [];
      });
    }
  }


  // Oyun isteği gönder
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

    await DatabaseService().sendChessRequest(
      partnerUid: partnerUid,
      fromName: name,
      coupleId: coupleId,
    );

    NotificationService().sendPushToPartner(
      partnerUid: partnerUid,
      title: 'Satranç Daveti ♟️',
      body: '$name seninle satranç oynamak istiyor!',
      data: {'type': 'game_request', 'game': 'chess'},
    );
  }

  // Yeni oyun onay penceresi
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
        title: const Text('Yeni Oyun Başlat'),
        content: const Text('Mevcut tahta sıfırlanarak yeni bir satranç oyunu başlayacaktır. Devam edilsin mi?'),
        actions: [
          TextButton(
            child: const Text('İptal'),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: LoveraColors.primary),
            child: const Text('Başlat', style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.pop(ctx);
              _initNewGame(coupleId, myUid, myName, partner);
            },
          ),
        ],
      ),
    );
  }

  // Pes etme onay penceresi
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
        title: const Text('Pes Et'),
        content: const Text('Oyundan çekilmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            child: const Text('Vazgeç'),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF43F5E)),
            child: const Text('Pes Et', style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.pop(ctx);
              DatabaseService().resignChessGame(
                coupleId: coupleId,
                resignedUid: myUid,
                winnerUid: partnerUid,
              );
            },
          ),
        ],
      ),
    );
  }

  // Oyundan çıkış onay penceresi (Oyundan çıkılınca oyun sonlanır)
  void _showExitDialog(BuildContext context, String coupleId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Oyundan Çık'),
        content: const Text('Oyundan çıkarsanız oyun sonlanacaktır. Çıkmak istediğinize emin misiniz?'),
        actions: [
          TextButton(
            child: const Text('Vazgeç'),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF43F5E)),
            child: const Text('Çık', style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.pop(ctx);
              DatabaseService().resetChessGame(coupleId: coupleId);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  // Alttan açılan mesaj menüsü (Oyun içi sohbet)
  void _openInGameChatSheet(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.85,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F1015) : const Color(0xFFF7F8FA),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 30,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: Column(
              children: [
                // Tutamaç (Drag Handle)
                Container(
                  width: double.infinity,
                  color: isDark ? const Color(0xFF161822) : Colors.white,
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  alignment: Alignment.center,
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                // Sohbet Görünümü
                Expanded(
                  child: ChatView(
                    isEmbedded: true,
                    onBackToHome: () => Navigator.pop(ctx),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Lovera Temasına Özel Vektörel Satranç Taşı Çizicisi
class _ChessPiecePainter extends CustomPainter {
  final chess_lib.PieceType pieceType;
  final bool isWhite;

  _ChessPiecePainter({
    required this.pieceType,
    required this.isWhite,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Renk paleti
    // Beyaz: İpeksi inci krem gövde, asil lavanta/ametist kontur, ışıltılı tepe
    // Siyah: Derin gece moru-obsidyen gövde, parlak gül kurusu / fuşya pembe kontur
    final baseGradient = isWhite
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), Color(0xFFF3E8FF)],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3B1854), Color(0xFF1E0E2B)],
          );

    final strokeColor = isWhite ? const Color(0xFF7C3AED) : const Color(0xFFF472B6);
    final glowColor = isWhite
        ? const Color(0xFFA855F7).withValues(alpha: 0.35)
        : const Color(0xFFEC4899).withValues(alpha: 0.45);

    // Dış ışıltı (Glow Shadow)
    final glowPaint = Paint()
      ..color = glowColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final fillPaint = Paint()
      ..shader = baseGradient.createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final accentPaint = Paint()
      ..color = isWhite ? const Color(0xFFC084FC) : const Color(0xFFFDA4AF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final path = _getPiecePath(pieceType, w, h);

    // Çizim katmanları
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);

    // İç detay çizgileri / süslemeleri
    _drawPieceAccents(canvas, pieceType, w, h, accentPaint);
  }

  Path _getPiecePath(chess_lib.PieceType type, double w, double h) {
    final path = Path();

    switch (type) {
      case chess_lib.PieceType.PAWN:
        // Piyon: Taban, boyun ve yuvarlak kafa
        path.moveTo(w * 0.22, h * 0.88);
        path.quadraticBezierTo(w * 0.20, h * 0.82, w * 0.26, h * 0.76);
        path.quadraticBezierTo(w * 0.38, h * 0.70, w * 0.38, h * 0.52);
        path.arcToPoint(
          Offset(w * 0.62, h * 0.52),
          radius: Radius.circular(w * 0.18),
          clockwise: true,
        );
        path.quadraticBezierTo(w * 0.62, h * 0.70, w * 0.74, h * 0.76);
        path.quadraticBezierTo(w * 0.80, h * 0.82, w * 0.78, h * 0.88);
        path.close();

        // Kafa küresi
        path.addOval(Rect.fromCircle(center: Offset(w * 0.5, h * 0.34), radius: w * 0.16));
        break;

      case chess_lib.PieceType.KNIGHT:
        // At: Asil at silüeti
        path.moveTo(w * 0.22, h * 0.88);
        path.lineTo(w * 0.78, h * 0.88);
        path.quadraticBezierTo(w * 0.72, h * 0.80, w * 0.72, h * 0.70);
        path.quadraticBezierTo(w * 0.76, h * 0.55, w * 0.70, h * 0.40);
        path.lineTo(w * 0.74, h * 0.24); // Kulak
        path.lineTo(w * 0.60, h * 0.26);
        path.quadraticBezierTo(w * 0.45, h * 0.25, w * 0.32, h * 0.38); // Burun
        path.quadraticBezierTo(w * 0.20, h * 0.48, w * 0.25, h * 0.58);
        path.quadraticBezierTo(w * 0.38, h * 0.60, w * 0.45, h * 0.54); // Çene altı
        path.quadraticBezierTo(w * 0.34, h * 0.70, w * 0.24, h * 0.80);
        path.close();
        break;

      case chess_lib.PieceType.BISHOP:
        // Fil: Sivri mitre şapkası ve haç/yarık
        path.moveTo(w * 0.22, h * 0.88);
        path.lineTo(w * 0.78, h * 0.88);
        path.quadraticBezierTo(w * 0.70, h * 0.78, w * 0.66, h * 0.64);
        path.quadraticBezierTo(w * 0.72, h * 0.45, w * 0.50, h * 0.20);
        path.quadraticBezierTo(w * 0.28, h * 0.45, w * 0.34, h * 0.64);
        path.quadraticBezierTo(w * 0.30, h * 0.78, w * 0.22, h * 0.88);
        path.close();

        // Tepe damlası
        path.addOval(Rect.fromCircle(center: Offset(w * 0.5, h * 0.16), radius: w * 0.055));
        break;

      case chess_lib.PieceType.ROOK:
        // Kale: Güçlü sur dişleri ve sağlam gövde
        path.moveTo(w * 0.20, h * 0.88);
        path.lineTo(w * 0.80, h * 0.88);
        path.quadraticBezierTo(w * 0.74, h * 0.78, w * 0.70, h * 0.48);
        path.lineTo(w * 0.78, h * 0.46);
        path.lineTo(w * 0.78, h * 0.24); // Sağ diş
        path.lineTo(w * 0.66, h * 0.24);
        path.lineTo(w * 0.66, h * 0.34);
        path.lineTo(w * 0.56, h * 0.34);
        path.lineTo(w * 0.56, h * 0.24); // Orta diş boşluğu
        path.lineTo(w * 0.44, h * 0.24);
        path.lineTo(w * 0.44, h * 0.34);
        path.lineTo(w * 0.34, h * 0.34);
        path.lineTo(w * 0.34, h * 0.24); // Sol diş
        path.lineTo(w * 0.22, h * 0.24);
        path.lineTo(w * 0.22, h * 0.46);
        path.lineTo(w * 0.30, h * 0.48);
        path.quadraticBezierTo(w * 0.26, h * 0.78, w * 0.20, h * 0.88);
        path.close();
        break;

      case chess_lib.PieceType.QUEEN:
        // Vezir: 5 uçlu kraliyet tacı ve zarif gövde
        path.moveTo(w * 0.18, h * 0.88);
        path.lineTo(w * 0.82, h * 0.88);
        path.quadraticBezierTo(w * 0.72, h * 0.75, w * 0.66, h * 0.58);
        // Taç uçları
        path.lineTo(w * 0.82, h * 0.30); // Sağ uç
        path.lineTo(w * 0.66, h * 0.42);
        path.lineTo(w * 0.60, h * 0.24); // Sağ-orta uç
        path.lineTo(w * 0.50, h * 0.38);
        path.lineTo(w * 0.50, h * 0.20); // Orta en yüksek uç
        path.lineTo(w * 0.50, h * 0.38);
        path.lineTo(w * 0.40, h * 0.24); // Sol-orta uç
        path.lineTo(w * 0.34, h * 0.42);
        path.lineTo(w * 0.18, h * 0.30); // Sol uç
        path.lineTo(w * 0.34, h * 0.58);
        path.quadraticBezierTo(w * 0.28, h * 0.75, w * 0.18, h * 0.88);
        path.close();

        // Taç tepe incileri
        path.addOval(Rect.fromCircle(center: Offset(w * 0.18, h * 0.28), radius: w * 0.04));
        path.addOval(Rect.fromCircle(center: Offset(w * 0.50, h * 0.18), radius: w * 0.045));
        path.addOval(Rect.fromCircle(center: Offset(w * 0.82, h * 0.28), radius: w * 0.04));
        break;

      case chess_lib.PieceType.KING:
        // Şah: Görkemli haç ve kral tacı
        path.moveTo(w * 0.18, h * 0.88);
        path.lineTo(w * 0.82, h * 0.88);
        path.quadraticBezierTo(w * 0.72, h * 0.76, w * 0.68, h * 0.56);
        path.quadraticBezierTo(w * 0.76, h * 0.38, w * 0.50, h * 0.32);
        path.quadraticBezierTo(w * 0.24, h * 0.38, w * 0.32, h * 0.56);
        path.quadraticBezierTo(w * 0.28, h * 0.76, w * 0.18, h * 0.88);
        path.close();

        // Kral Haçı
        // Dikey direk
        path.addRect(Rect.fromCenter(center: Offset(w * 0.5, h * 0.22), width: w * 0.07, height: h * 0.16));
        // Yatay direk
        path.addRect(Rect.fromCenter(center: Offset(w * 0.5, h * 0.20), width: w * 0.20, height: h * 0.06));
        break;
    }

    return path;
  }

  void _drawPieceAccents(Canvas canvas, chess_lib.PieceType type, double w, double h, Paint paint) {
    // Taban çizgisi
    canvas.drawLine(Offset(w * 0.26, h * 0.83), Offset(w * 0.74, h * 0.83), paint);

    if (type == chess_lib.PieceType.BISHOP) {
      // Fil çapraz kesiği
      canvas.drawLine(Offset(w * 0.44, h * 0.38), Offset(w * 0.58, h * 0.48), paint);
    } else if (type == chess_lib.PieceType.KNIGHT) {
      // At gözü ve yele detayı
      canvas.drawCircle(Offset(w * 0.42, h * 0.42), 1.6, paint);
      canvas.drawLine(Offset(w * 0.56, h * 0.38), Offset(w * 0.64, h * 0.44), paint);
      canvas.drawLine(Offset(w * 0.58, h * 0.50), Offset(w * 0.66, h * 0.58), paint);
    } else if (type == chess_lib.PieceType.ROOK) {
      // Kale gövde çizgisi
      canvas.drawLine(Offset(w * 0.32, h * 0.50), Offset(w * 0.68, h * 0.50), paint);
    } else if (type == chess_lib.PieceType.QUEEN || type == chess_lib.PieceType.KING) {
      // Taç kuşak çizgisi
      canvas.drawLine(Offset(w * 0.32, h * 0.60), Offset(w * 0.68, h * 0.60), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChessPiecePainter oldDelegate) {
    return oldDelegate.pieceType != pieceType || oldDelegate.isWhite != isWhite;
  }
}
