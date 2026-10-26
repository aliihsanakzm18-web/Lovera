import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/models/models.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/lovera_theme_background.dart';
import 'love_questions_game_view.dart';
import 'question_archive_view.dart';

class GamesView extends ConsumerStatefulWidget {
  const GamesView({super.key, this.onBackToHome});
  final VoidCallback? onBackToHome;

  @override
  ConsumerState<GamesView> createState() => _GamesViewState();
}

class _GamesViewState extends ConsumerState<GamesView> {
  bool _isSendingInvite = false;

  Future<void> _startOrJoinGame({
    required String? coupleId,
    required dynamic partner,
    required String myName,
    required String? currentStatus,
    required bool isIncomingInvite,
    required bool isActive,
    required bool isMyPendingInvite,
  }) async {
    HapticFeedback.mediumImpact();
    if (coupleId == null || coupleId.isEmpty || partner == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc('Oynamak için önce partnerinle eşleşmelisin 💕', 'Pair with your partner first to play 💕')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final partnerUid = (partner.id ?? '').toString();

    // 1. Zaten aktif bir oyun varsa doğrudan oyuna gir
    if (isActive) {
      final hasEnteredThisSession = ref.read(loveQuestionsEnteredThisSessionProvider);
      if (!hasEnteredThisSession) {
        // Kullanıcı uygulamayı tamamen kapatıp yeniden açmış ve "Oyuna Devam Et"e basmış!
        // Oyunun tüm ilerlemesi ve cevaplanan soruları (answeredMap) aynen korunur.
        // Sıranın kimde olduğunu belirlemek için tekrardan zar/yazı-tura (coin_flip) atılır.
        ref.read(loveQuestionsEnteredThisSessionProvider.notifier).state = true;
        await DatabaseService().updateGameState(
          coupleId: coupleId,
          gameType: 'love_questions',
          updates: {
            'step': 'coin_flip',
            'activeQuestionId': null,
            'answeringUid': null,
            'isReturnedQuestion': false,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
      }

      if (mounted) {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const LoveQuestionsGameView(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              const begin = Offset(1.0, 0.0);
              const end = Offset.zero;
              const curve = Curves.easeInOutCubic;
              final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
              return SlideTransition(position: animation.drive(tween), child: child);
            },
          ),
        );
      }
      return;
    }

    // 2. Partnerden gelen bir davet varsa kabul edip oyuna gir
    if (isIncomingInvite) {
      ref.read(loveQuestionsEnteredThisSessionProvider.notifier).state = true;
      final name = myName.isNotEmpty ? myName : loc('Partnerin', 'Partner');
      await DatabaseService().respondGameRequest(
        coupleId: coupleId,
        gameType: 'love_questions',
        fromUid: partnerUid,
        accepted: true,
        responderName: name,
      );
      if (mounted) {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const LoveQuestionsGameView(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              const begin = Offset(1.0, 0.0);
              const end = Offset.zero;
              const curve = Curves.easeInOutCubic;
              final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
              return SlideTransition(position: animation.drive(tween), child: child);
            },
          ),
        );
      }
      return;
    }

    // 3. Karşı taraftan yanıt bekleniyorsa kullanıcıya bilgi ver
    if (isMyPendingInvite) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc('Davet gönderildi, partnerinin kabul etmesi bekleniyor... ⏳', 'Invite sent, waiting for partner to accept... ⏳')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFFB8500),
        ),
      );
      return;
    }

    // 4. Yeni oyun başlatma isteği gönder (Henüz oyuna GİRMİYOR, bekleme durumunda kalıyor)
    if (partnerUid.isNotEmpty && !_isSendingInvite) {
      setState(() => _isSendingInvite = true);
      try {
        final cleanMyName = AppUser.extractFirstName(myName);
        final senderName = cleanMyName.isNotEmpty ? cleanMyName : loc('Partnerin', 'Your Partner');
        await DatabaseService().sendGameRequest(
          gameType: 'love_questions',
          gameTitle: loc('Aşk Sandığı: Kalp Kalbe', 'Love Chest: Heart to Heart'),
          partnerUid: partnerUid,
          fromName: senderName,
          coupleId: coupleId,
          initialGameData: {
            'step': 'coin_flip',
            'player1Uid': DatabaseService().uid,
            'player1Name': senderName,
            'player2Uid': partnerUid,
            'player2Name': partner.displayName.isNotEmpty ? partner.displayName : 'Partner',
            'activeQuestionId': null,
            'answeredMap': {},
          },
        );

        NotificationService().sendPushToPartner(
          partnerUid: partnerUid,
          title: loc('Aşk Sandığı Daveti! 💌', 'Love Chest Invitation! 💌'),
          body: loc('$senderName seninle Kalp Kalbe oynamak istiyor!', '$senderName wants to play Heart to Heart with you!'),
          titleTr: 'Aşk Sandığı Daveti! 💌',
          titleEn: 'Love Chest Invitation! 💌',
          bodyTr: '$senderName seninle Kalp Kalbe oynamak istiyor!',
          bodyEn: '$senderName wants to play Heart to Heart with you!',
          data: {'type': 'game_request', 'game': 'love_questions'},
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(loc('Davet partnerine iletildi! Kabul edince oyun otomatik açılacak 💕', 'Invite sent! The game will launch once accepted 💕')),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
      } catch (e) {
        debugPrint('[LOVE_QUESTIONS] sendGameRequest error: $e');
      } finally {
        if (mounted) {
          setState(() => _isSendingInvite = false);
        }
      }
    }
  }

  Future<void> _cancelInvite({
    required String? coupleId,
    required dynamic partner,
  }) async {
    if (coupleId == null || partner == null) return;
    final partnerUid = (partner.id ?? '').toString();
    HapticFeedback.mediumImpact();
    await DatabaseService().cancelGameRequest(
      coupleId: coupleId,
      gameType: 'love_questions',
      partnerUid: partnerUid,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc('Oyun daveti iptal edildi.', 'Game invite cancelled.')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final partner = ref.watch(partnerProvider);
    final coupleId = ref.watch(coupleIdProvider);
    final myName = ref.watch(userNameProvider);
    final myUid = DatabaseService().uid;

    return Scaffold(
      backgroundColor: isDark ? LoveraColors.darkBg : LoveraColors.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? LoveraColors.darkSurface : LoveraColors.lightSurface,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: widget.onBackToHome ?? () => Navigator.of(context).maybePop(),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: LoveraColors.primarySoft.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.sports_esports_rounded, color: LoveraColors.primary, size: 22),
            ),
            const SizedBox(width: 10),
            Text(
              loc('Oyun & Eğlence', 'Games & Fun'),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
      body: LoveraThemeBackground(
        child: SafeArea(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: (coupleId != null && coupleId.isNotEmpty)
                ? DatabaseService().gameStream(coupleId, 'love_questions')
                : const Stream.empty(),
            builder: (context, snapshot) {
              final data = snapshot.data?.data();
              final status = data?['status'] as String?;
              final fromUid = (data?['fromUid'] ?? data?['requestedBy']) as String?;
              final isInvitePending = status == 'invitation_pending';
              final isIncomingInvite = isInvitePending && fromUid != null && fromUid != myUid;
              final isMyPendingInvite = isInvitePending && fromUid == myUid;
              final isActive = status == 'active';
              final answeredCount = (data?['answeredMap'] as Map?)?.length ?? 0;

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
                children: [
                  // ANA OYUN KARTI (Lovera Özel: Aşk Sandığı)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          LoveraColors.primary,
                          LoveraColors.primaryDeep,
                          const Color(0xFF9D174D),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: LoveraColors.primary.withValues(alpha: 0.38),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                              ),
                              child: const Center(
                                child: Text('💌', style: TextStyle(fontSize: 26)),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isIncomingInvite
                                    ? const Color(0xFF10B981)
                                    : (isActive
                                        ? const Color(0xFF10B981)
                                        : (isMyPendingInvite
                                            ? const Color(0xFFFB8500)
                                            : Colors.white.withValues(alpha: 0.22))),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                isIncomingInvite
                                    ? loc('DAVET VAR 🔔', 'INVITATION 🔔')
                                    : (isActive
                                        ? loc('CANLI OYUN 🔥', 'LIVE GAME 🔥')
                                        : (isMyPendingInvite
                                            ? loc('DAVET BEKLENİYOR ⏳', 'WAITING PARTNER ⏳')
                                            : loc('ÇİFT DÜELLOSU ✨', 'COUPLE DUEL ✨'))),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          loc('Aşk Sandığı: Kalp Kalbe', 'Love Chest: Heart to Heart'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          loc(
                            'Yazı-tura ile ilk kimin soru soracağı belirlenir. Beğendiğin kartı seç, partnerin karta cevabını yazsın ve ilişkinizin ömürlük albümüne mühürlensin! 💕',
                            'Flip the named coin to decide who asks first. Pick a card, let your partner write the answer, and seal it into your eternal memory chest! 💕',
                          ),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 18),

                        // ÖZELLİK ROZETLERİ
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildBadge('🪙 ' + loc('İsimli Yazı-Tura', 'Named Coin Flip')),
                            _buildBadge('📚 60+ ' + loc('Özel Soru Kartı', 'Curated Cards')),
                            _buildBadge('💖 $answeredCount ' + loc('Cevaplandı', 'Answered')),
                          ],
                        ),

                        const SizedBox(height: 22),

                        // OYNA / KATIL BUTONU
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: LoveraColors.primaryDeep,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _isSendingInvite
                                ? null
                                : () => _startOrJoinGame(
                                      coupleId: coupleId,
                                      partner: partner,
                                      myName: myName,
                                      currentStatus: status,
                                      isIncomingInvite: isIncomingInvite,
                                      isActive: isActive,
                                      isMyPendingInvite: isMyPendingInvite,
                                    ),
                            icon: _isSendingInvite
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: LoveraColors.primaryDeep,
                                    ),
                                  )
                                : Icon(
                                    isIncomingInvite
                                        ? Icons.notifications_active_rounded
                                        : (isActive
                                            ? Icons.play_arrow_rounded
                                            : (isMyPendingInvite ? Icons.hourglass_top_rounded : Icons.rocket_launch_rounded)),
                                    size: 20,
                                  ),
                            label: Text(
                              isIncomingInvite
                                  ? loc('Daveti Kabul Et & Oyna 🚀', 'Accept & Play 🚀')
                                  : (isActive
                                      ? loc('Oyuna Devam Et 🔥', 'Resume Game 🔥')
                                      : (isMyPendingInvite
                                          ? loc('Davet Bekleniyor... ⏳', 'Waiting for Partner... ⏳')
                                          : loc('Oyuna Başla 🚀', 'Start Game 🚀'))),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        if (isMyPendingInvite) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.6), width: 1.4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () => _cancelInvite(coupleId: coupleId, partner: partner),
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: Text(
                                loc('Daveti İptal Et', 'Cancel Invite'),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.4), width: 1.2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              backgroundColor: Colors.black.withValues(alpha: 0.15),
                            ),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const QuestionArchiveView(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.menu_book_rounded, size: 18),
                            label: Text(
                              loc('Soru & Cevap Arşivi 📖', 'Question Archive 📖'),
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.08),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
