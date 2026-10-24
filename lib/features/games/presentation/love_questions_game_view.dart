import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/lovera_theme_background.dart';
import '../data/question_bank.dart';
import 'widgets/coin_flip_3d.dart';

class LoveQuestionsGameView extends ConsumerStatefulWidget {
  const LoveQuestionsGameView({super.key});

  @override
  ConsumerState<LoveQuestionsGameView> createState() => _LoveQuestionsGameViewState();
}

class _LoveQuestionsGameViewState extends ConsumerState<LoveQuestionsGameView> {
  final TextEditingController _answerController = TextEditingController();
  String _selectedCategory = 'all';
  bool _isSubmittingAnswer = false;
  bool _isFlippingCoinLocal = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _gameSub;
  Map<String, dynamic>? _lastGameData;

  @override
  void initState() {
    super.initState();
    _initGameStream();
  }

  void _initGameStream() {
    final coupleId = ref.read(coupleIdProvider);
    if (coupleId == null || coupleId.isEmpty) return;

    _gameSub = DatabaseService().gameStream(coupleId, 'love_questions').listen((snap) {
      if (!mounted) return;
      if (snap.exists && snap.data() != null) {
        final data = snap.data()!;
        final oldData = _lastGameData;
        _lastGameData = data;

        // Yazı-tura atışı tetiklendiyse yerel animasyonu oynat
        if (data['step'] == 'flipping_coin' && oldData?['step'] != 'flipping_coin') {
          setState(() {
            _isFlippingCoinLocal = true;
          });
        }

        // Eğer aktif soru değiştiyse textfield'ı temizle
        if (data['activeQuestionId'] != oldData?['activeQuestionId']) {
          _answerController.clear();
        }

        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _gameSub?.cancel();
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _startCoinFlip() async {
    final coupleId = ref.read(coupleIdProvider);
    final myUid = DatabaseService().uid;
    if (coupleId == null || myUid == null) return;

    final gameData = _lastGameData;
    if (gameData == null) return;

    final p1Uid = gameData['player1Uid']?.toString() ?? myUid;
    final p1Name = gameData['player1Name']?.toString() ?? 'Partner 1';
    final p2Uid = gameData['player2Uid']?.toString() ?? '';
    final p2Name = gameData['player2Name']?.toString() ?? 'Partner 2';

    // Rastgele kazanan belirle (yazı tura)
    final bool winnerIsP1 = math.Random().nextBool();
    final winnerUid = winnerIsP1 ? p1Uid : p2Uid;
    final winnerName = winnerIsP1 ? p1Name : p2Name;

    setState(() => _isFlippingCoinLocal = true);

    // 1. ADIM: Para atılıyor aşaması (2.3 saniye boyunca havada döner)
    await DatabaseService().updateGameState(
      coupleId: coupleId,
      gameType: 'love_questions',
      updates: {
        'step': 'flipping_coin',
        'coinWinnerUid': winnerUid,
        'coinWinnerName': winnerName,
        'turnUid': winnerUid,
        'turnName': winnerName,
      },
    );

    // 2. ADIM: Para indiğinde sonucu net bir şekilde ekranda göster (coin_result aşaması)
    Future.delayed(const Duration(milliseconds: 2300), () async {
      if (!mounted) return;
      setState(() => _isFlippingCoinLocal = false);
      await DatabaseService().updateGameState(
        coupleId: coupleId,
        gameType: 'love_questions',
        updates: {
          'step': 'coin_result',
        },
      );
    });
  }

  Future<void> _proceedToQuestionBank() async {
    final coupleId = ref.read(coupleIdProvider);
    if (coupleId == null) return;
    HapticFeedback.mediumImpact();
    await DatabaseService().updateGameState(
      coupleId: coupleId,
      gameType: 'love_questions',
      updates: {
        'step': 'picking_question',
      },
    );
  }

  Future<void> _selectQuestion(QuestionCard q) async {
    final coupleId = ref.read(coupleIdProvider);
    final myUid = DatabaseService().uid;
    final myName = ref.read(userNameProvider);
    final partner = ref.read(partnerProvider);
    if (coupleId == null || myUid == null) return;

    final partnerUid = partner?.id.toString() ?? '';
    final partnerName = partner?.name.toString() ?? 'Partnerin';

    HapticFeedback.heavyImpact();

    await DatabaseService().updateGameState(
      coupleId: coupleId,
      gameType: 'love_questions',
      updates: {
        'step': 'answering_question',
        'activeQuestionId': q.id,
        'activeQuestionCategory': q.category,
        'activeQuestionTr': q.questionTr,
        'activeQuestionEn': q.questionEn,
        'activeQuestionEmoji': q.emoji,
        'askedByUid': myUid,
        'askedByName': myName.isNotEmpty ? myName : 'Ben',
        'answeringUid': partnerUid,
        'answeringName': partnerName,
      },
    );

    // Partnere bildirim gönder
    if (partnerUid.isNotEmpty) {
      NotificationService().sendPushToPartner(
        partnerUid: partnerUid,
        title: loc('Yeni Bir Soru Geldi! 💌', 'New Question Arrived! 💌'),
        body: loc('$myName sana bir soru sordu, yanıtlamanı bekliyor!', '$myName asked you a question, waiting for your answer!'),
        titleTr: 'Yeni Bir Soru Geldi! 💌',
        titleEn: 'New Question Arrived! 💌',
        bodyTr: '$myName sana bir soru sordu, yanıtlamanı bekliyor!',
        bodyEn: '$myName asked you a question, waiting for your answer!',
        data: {'type': 'game_action', 'game': 'love_questions'},
      );
    }
  }

  Future<void> _submitAnswer() async {
    final text = _answerController.text.trim();
    if (text.isEmpty) return;

    final coupleId = ref.read(coupleIdProvider);
    final myUid = DatabaseService().uid;
    final myName = ref.read(userNameProvider);
    final partner = ref.read(partnerProvider);
    final gameData = _lastGameData;
    if (coupleId == null || myUid == null || gameData == null) return;

    final partnerUid = partner?.id.toString() ?? '';
    final partnerName = partner?.name.toString() ?? 'Partnerin';
    final qId = gameData['activeQuestionId']?.toString() ?? '';

    setState(() => _isSubmittingAnswer = true);
    HapticFeedback.mediumImpact();

    final answeredItem = {
      'questionId': qId,
      'questionTr': gameData['activeQuestionTr'] ?? '',
      'questionEn': gameData['activeQuestionEn'] ?? '',
      'category': gameData['activeQuestionCategory'] ?? '',
      'emoji': gameData['activeQuestionEmoji'] ?? '💖',
      'askedByUid': gameData['askedByUid'] ?? '',
      'askedByName': gameData['askedByName'] ?? '',
      'answeredByUid': myUid,
      'answeredByName': myName.isNotEmpty ? myName : 'Ben',
      'answerText': text,
      'timestamp': DateTime.now().toIso8601String(),
    };

    final Map<String, dynamic> answeredMap = Map<String, dynamic>.from(gameData['answeredMap'] ?? {});
    answeredMap[qId] = answeredItem;

    await DatabaseService().updateGameState(
      coupleId: coupleId,
      gameType: 'love_questions',
      updates: {
        'step': 'picking_question', // Sıra soru sorma hakkı olarak diğer tarafa geçer
        'turnUid': partnerUid,
        'turnName': partnerName,
        'activeQuestionId': null,
        'lastAnsweredItem': answeredItem,
        'answeredMap': answeredMap,
      },
    );

    if (mounted) {
      _answerController.clear();
      setState(() => _isSubmittingAnswer = false);
      HapticFeedback.vibrate();
      _showSuccessDialog(answeredItem);
    }
  }

  void _showSuccessDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Row(
          children: [
            const Text('🎉', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                loc('Cevabın Mühürlendi!', 'Answer Sealed!'),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
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
                'Harika! Cevabın soru kartına eklendi ve arşivlendi. Şimdi soru sorma sırası partnerine geçti! 💕',
                'Awesome! Your answer is sealed into the card archive. Now it\'s your partner\'s turn to pick a question! 💕',
              ),
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: LoveraColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(loc('Tamam Devam Et', 'Continue')),
          ),
        ],
      ),
    );
  }

  void _showAnswerDetailsModal(Map<String, dynamic> item) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final qText = loc(item['questionTr'] ?? '', item['questionEn'] ?? '');
    final aText = item['answerText']?.toString() ?? '';
    final askedBy = item['askedByName']?.toString() ?? 'Partner';
    final answeredBy = item['answeredByName']?.toString() ?? 'Partner';
    final emoji = item['emoji']?.toString() ?? '💖';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 34),
        decoration: BoxDecoration(
          color: isDark ? LoveraColors.darkSurface : LoveraColors.lightSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: LoveraColors.textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: LoveraColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          loc('CEVAPLANDI 💖', 'ANSWERED 💖'),
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        loc('$askedBy sordu, $answeredBy yanıtladı', '$askedBy asked, $answeredBy answered'),
                        style: TextStyle(
                          color: LoveraColors.textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              qText,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.35),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: LoveraColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: LoveraColors.primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.format_quote_rounded, color: LoveraColors.primary, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        '$answeredBy yanıtı:',
                        style: TextStyle(
                          color: LoveraColors.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    aText,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: LoveraColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(loc('Kapat', 'Close'), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final myUid = DatabaseService().uid;
    final myName = ref.watch(userNameProvider);
    final partner = ref.watch(partnerProvider);

    final gameData = _lastGameData;
    final String step = gameData?['step'] ?? 'coin_flip';
    final String turnUid = gameData?['turnUid']?.toString() ?? '';
    final String turnName = gameData?['turnName']?.toString() ?? '';
    final String activeQuestionId = gameData?['activeQuestionId']?.toString() ?? '';
    final String answeringUid = gameData?['answeringUid']?.toString() ?? '';
    final String askedByName = gameData?['askedByName']?.toString() ?? '';
    final Map<String, dynamic> answeredMap = Map<String, dynamic>.from(gameData?['answeredMap'] ?? {});

    final bool isMyTurn = turnUid == myUid;
    final bool amIAnswering = answeringUid == myUid && activeQuestionId.isNotEmpty;

    final p1Name = gameData?['player1Name']?.toString() ?? myName;
    final p2Name = gameData?['player2Name']?.toString() ?? (partner?.name ?? 'Partner');
    final coinWinnerName = gameData?['coinWinnerName']?.toString() ?? turnName;

    return Scaffold(
      backgroundColor: isDark ? LoveraColors.darkBg : LoveraColors.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? LoveraColors.darkSurface : LoveraColors.lightSurface,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: LoveraColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('💌', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc('Aşk Sandığı: Kalp Kalbe', 'Love Chest: Heart to Heart'),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  Text(
                    partner != null ? '${partner.name} ile canlı' : loc('Çift Oyunu', 'Couple Game'),
                    style: TextStyle(color: LoveraColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: LoveraThemeBackground(
        child: SafeArea(
          child: Column(
            children: [
              // 1. ÜST BİLGİ & DURUM ÇUBUĞU (Yazı-Tura veya Sıra Kimde)
              _buildTopStatusBanner(
                step: step,
                isMyTurn: isMyTurn,
                amIAnswering: amIAnswering,
                turnName: turnName,
                askedByName: askedByName,
                isDark: isDark,
              ),

              // 2. ANA İÇERİK: AKTİF SORU VARSA BÜYÜYEN KART, YOKSA LİSTE/YAZI-TURA/BEKLEME
              Expanded(
                child: activeQuestionId.isNotEmpty
                    ? _buildActiveHeroQuestionCard(
                        gameData: gameData!,
                        amIAnswering: amIAnswering,
                        isDark: isDark,
                      )
                    : (step == 'coin_flip' || step == 'flipping_coin' || step == 'coin_result')
                        ? _buildCoinFlipSection(
                            p1Name: p1Name,
                            p2Name: p2Name,
                            winnerName: coinWinnerName,
                            isFlipping: _isFlippingCoinLocal || step == 'flipping_coin',
                            isResult: step == 'coin_result',
                            isDark: isDark,
                          )
                        : isMyTurn
                            ? _buildQuestionBankBrowseSection(
                                isMyTurn: isMyTurn,
                                answeredMap: answeredMap,
                                isDark: isDark,
                              )
                            : _buildWaitingForPartnerToPickSection(
                                turnName: turnName,
                                answeredMap: answeredMap,
                                isDark: isDark,
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopStatusBanner({
    required String step,
    required bool isMyTurn,
    required bool amIAnswering,
    required String turnName,
    required String askedByName,
    required bool isDark,
  }) {
    String message = '';
    Color bannerBg = LoveraColors.primary;
    IconData icon = Icons.auto_awesome_rounded;

    if (step == 'coin_flip' || step == 'flipping_coin') {
      message = loc('İlk kim soru soracak? Yazı-tura atılıyor! 🪙', 'Who asks first? Flipping the coin! 🪙');
      bannerBg = const Color(0xFFFB8500);
      icon = Icons.casino_rounded;
    } else if (amIAnswering) {
      message = loc('Soru Sana Geldi! $askedByName cevabını bekliyor ✍️', 'Question for you! $askedByName awaits your answer ✍️');
      bannerBg = const Color(0xFFEC4899);
      icon = Icons.edit_note_rounded;
    } else if (step == 'answering_question') {
      message = loc('Partnerin soruyu cevaplıyor... ⏳', 'Your partner is writing an answer... ⏳');
      bannerBg = const Color(0xFF8B5CF6);
      icon = Icons.hourglass_top_rounded;
    } else if (isMyTurn) {
      message = loc('Sıra Sende! Havuzdan beğendiğin soruyu seç 🎯', 'Your Turn! Pick a question from the bank 🎯');
      bannerBg = const Color(0xFF10B981);
      icon = Icons.touch_app_rounded;
    } else {
      message = loc('Soru seçme sırası: $turnName 💭', 'Picking question: $turnName 💭');
      bannerBg = const Color(0xFF6366F1);
      icon = Icons.person_rounded;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: bannerBg.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: bannerBg.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: bannerBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isDark ? Colors.white : LoveraColors.textDark,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- YAZI TURA BÖLÜMÜ ---
  Widget _buildCoinFlipSection({
    required String p1Name,
    required String p2Name,
    required String winnerName,
    required bool isFlipping,
    required bool isResult,
    required bool isDark,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              loc('İLK SORUYU KİM SORACAK?', 'WHO ASKS THE FIRST QUESTION?'),
              style: TextStyle(
                color: LoveraColors.textMuted,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              loc('İsimli Aşk Parası Atışı ✨', 'Named Couple Coin Flip ✨'),
              style: TextStyle(
                color: isDark ? Colors.white : LoveraColors.textDark,
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 36),

            // 3D Animasyonlu Para
            CoinFlip3D(
              player1Name: p1Name,
              player2Name: p2Name,
              winnerName: winnerName,
              isFlipping: isFlipping,
            ),

            const SizedBox(height: 36),

            if (isResult) ...[
              // YAZI-TURA SONUCU KUTUSU
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFFB8500).withValues(alpha: 0.18),
                      const Color(0xFFF72585).withValues(alpha: 0.14),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: const Color(0xFFFB8500).withValues(alpha: 0.4),
                    width: 1.6,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('👑', style: TextStyle(fontSize: 26)),
                        const SizedBox(width: 8),
                        Text(
                          loc('KAZANAN: $winnerName', 'WINNER: $winnerName'),
                          style: const TextStyle(
                            color: Color(0xFFFB8500),
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      loc(
                        'İlk soruyu $winnerName soruyor! Kart havuzundan soru seçmek için devam edin.',
                        '$winnerName asks the first question! Proceed to the question bank.',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.white70 : LoveraColors.textDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFB8500),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 3,
                        ),
                        onPressed: _proceedToQuestionBank,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                        label: Text(
                          loc('Soru Havuzuna Geç 🚀', 'Go to Question Bank 🚀'),
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.9, 0.9)),
            ] else if (!isFlipping) ...[
              SizedBox(
                width: 220,
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFB8500),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                  ),
                  onPressed: _startCoinFlip,
                  icon: const Icon(Icons.casino_rounded, size: 20),
                  label: Text(
                    loc('Parayı Fırlat! 🪙', 'Flip The Coin! 🪙'),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                ),
              ).animate().fadeIn().scale(),
            ] else ...[
              Text(
                loc('Para havada dönüyor...', 'Coin is flipping in the air...'),
                style: TextStyle(
                  color: isDark ? Colors.white70 : LoveraColors.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ).animate(onPlay: (controller) => controller.repeat(reverse: true)).fadeIn(duration: 500.ms),
            ],
          ],
        ),
      ),
    );
  }

  // --- BÜYÜYEN AKTİF SORU KARTI (HERO KART & CEVAPLAMA) ---
  Widget _buildActiveHeroQuestionCard({
    required Map<String, dynamic> gameData,
    required bool amIAnswering,
    required bool isDark,
  }) {
    final qText = loc(gameData['activeQuestionTr'] ?? '', gameData['activeQuestionEn'] ?? '');
    final emoji = gameData['activeQuestionEmoji'] ?? '💖';
    final askedBy = gameData['askedByName'] ?? 'Partner';
    final answeringBy = gameData['answeringName'] ?? 'Partner';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  LoveraColors.primary,
                  LoveraColors.primaryDeep,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: LoveraColors.primary.withValues(alpha: 0.38),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
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
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 28)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$askedBy sordu 💌',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  loc('AKTİF SORU', 'ACTIVE QUESTION'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  qText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_clock_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          amIAnswering
                              ? loc('Bu soruyu sadece sen cevaplayacaksın ✍️', 'Only you will answer this question ✍️')
                              : loc('$answeringBy şu an yanıtını yazıyor... 💬', '$answeringBy is writing an answer... 💬'),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.92, 0.92)),

          const SizedBox(height: 24),

          // CEVAP ALANI
          if (amIAnswering) ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? LoveraColors.darkSurface : LoveraColors.lightSurface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: LoveraColors.primary.withValues(alpha: 0.3),
                  width: 1.4,
                ),
                boxShadow: AppTheme.ambientShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc('Cevabını Yaz 💖', 'Write Your Answer 💖'),
                    style: TextStyle(
                      color: isDark ? Colors.white : LoveraColors.textDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    loc('Partnerinle kart havuzuna ömürlük bir anı bırakacaksın.', 'You are leaving a lasting memory in the card vault.'),
                    style: TextStyle(color: LoveraColors.textMuted, fontSize: 11.5),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _answerController,
                    maxLines: 4,
                    minLines: 3,
                    style: TextStyle(
                      color: isDark ? Colors.white : LoveraColors.textDark,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: loc('İçinden gelen en samimi cevabı yaz...', 'Write the most heartfelt answer from within...'),
                      hintStyle: TextStyle(color: LoveraColors.textMuted.withValues(alpha: 0.6), fontSize: 13.5),
                      filled: true,
                      fillColor: isDark ? Colors.black26 : Colors.grey.withValues(alpha: 0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: LoveraColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _isSubmittingAnswer ? null : _submitAnswer,
                      icon: _isSubmittingAnswer
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        loc('Cevabı Mühürle & Gönder ✨', 'Seal & Send Answer ✨'),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.08),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? LoveraColors.darkSurface : LoveraColors.lightSurface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: LoveraColors.textMuted.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF8B5CF6)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    loc('$answeringBy cevabını hazırlıyor...', '$answeringBy is preparing the answer...'),
                    style: TextStyle(
                      color: isDark ? Colors.white : LoveraColors.textDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    loc('Partnerin yanıtı gönderdiği an soru mühürlenecek ve sıra sana geçecek!', 'Once answered, it will be sealed and turn switches to you!'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: LoveraColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- DEVAZA SORU HAVUZU VE KART LİSTESİ BÖLÜMÜ ---
  Widget _buildQuestionBankBrowseSection({
    required bool isMyTurn,
    required Map<String, dynamic> answeredMap,
    required bool isDark,
  }) {
    final List<QuestionCard> questions = _selectedCategory == 'all'
        ? QuestionBank.allQuestions
        : QuestionBank.getByCategory(_selectedCategory);

    final int totalAnsweredCount = answeredMap.length;

    return Column(
      children: [
        // KATEGORİ ÇUBUĞU
        Container(
          height: 44,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildCategoryPill(
                id: 'all',
                title: loc('Tümü (${QuestionBank.allQuestions.length})', 'All (${QuestionBank.allQuestions.length})'),
                emoji: '📚',
                isSelected: _selectedCategory == 'all',
                color: LoveraColors.primary,
                isDark: isDark,
              ),
              ...QuestionBank.categories.map((c) {
                final count = QuestionBank.getByCategory(c.id).length;
                final isTr = loc('tr', 'en') == 'tr';
                return _buildCategoryPill(
                  id: c.id,
                  title: '${c.getTitle(isTr)} ($count)',
                  emoji: c.emoji,
                  isSelected: _selectedCategory == c.id,
                  color: Color(c.colorHex),
                  isDark: isDark,
                );
              }),
            ],
          ),
        ),

        // İSTATİSTİK ŞERİDİ
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                loc('${questions.length} Soru Kartı', '${questions.length} Question Cards'),
                style: TextStyle(
                  color: LoveraColors.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  loc('$totalAnsweredCount Cevaplandı 💖', '$totalAnsweredCount Answered 💖'),
                  style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),

        // KART LİSTESİ
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            itemCount: questions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final q = questions[index];
              final isAnswered = answeredMap.containsKey(q.id);
              final answeredData = isAnswered ? answeredMap[q.id] : null;

              return _buildQuestionCardItem(
                q: q,
                isAnswered: isAnswered,
                answeredData: answeredData is Map ? Map<String, dynamic>.from(answeredData) : null,
                isMyTurn: isMyTurn,
                isDark: isDark,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryPill({
    required String id,
    required String title,
    required String emoji,
    required bool isSelected,
    required Color color,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedCategory = id);
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? color
              : (isDark ? LoveraColors.darkSurface : LoveraColors.lightSurface),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? color : (isDark ? LoveraColors.darkBorder : LoveraColors.lightBorder),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : (isDark ? Colors.white : LoveraColors.textDark),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionCardItem({
    required QuestionCard q,
    required bool isAnswered,
    required Map<String, dynamic>? answeredData,
    required bool isMyTurn,
    required bool isDark,
  }) {
    final theme = Theme.of(context);
    final qText = loc(q.questionTr, q.questionEn);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        if (isAnswered && answeredData != null) {
          HapticFeedback.selectionClick();
          _showAnswerDetailsModal(answeredData);
        } else if (isMyTurn) {
          _confirmSelectQuestion(q);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(loc('Şu an soru seçme sırası partnerinde ⏳', 'It is your partner\'s turn to pick ⏳')),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isAnswered
                ? const Color(0xFF10B981).withValues(alpha: 0.5)
                : (isMyTurn ? LoveraColors.primary.withValues(alpha: 0.3) : theme.dividerColor),
            width: isAnswered ? 1.6 : 1.0,
          ),
          boxShadow: AppTheme.ambientShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isAnswered
                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                    : LoveraColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  isAnswered ? '💖' : q.emoji,
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isAnswered) ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            loc('CEVAPLANDI ✨', 'ANSWERED ✨'),
                            style: const TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          loc('(Okumak için tıkla)', '(Tap to read)'),
                          style: TextStyle(color: LoveraColors.textMuted, fontSize: 10),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    qText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white : LoveraColors.textDark,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isAnswered
                  ? Icons.check_circle_rounded
                  : (isMyTurn ? Icons.touch_app_rounded : Icons.chevron_right_rounded),
              color: isAnswered
                  ? const Color(0xFF10B981)
                  : (isMyTurn ? LoveraColors.primary : LoveraColors.textMuted),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  void _confirmSelectQuestion(QuestionCard q) {
    final qText = loc(q.questionTr, q.questionEn);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 34),
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: LoveraColors.textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text(q.emoji, style: const TextStyle(fontSize: 32)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    loc('Bu Soruyu Partnere Sor?', 'Ask This To Your Partner?'),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              qText,
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, height: 1.35),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(loc('Vazgeç', 'Cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: LoveraColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _selectQuestion(q);
                    },
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: Text(loc('Soruyu Seç 🚀', 'Pick Question 🚀'), style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- SORU BEKLEME ALANI (Soru seçme sırası partnerdeyken gösterilen ekran) ---
  Widget _buildWaitingForPartnerToPickSection({
    required String turnName,
    required Map<String, dynamic> answeredMap,
    required bool isDark,
  }) {
    final displayName = turnName.isNotEmpty ? turnName : loc('Partnerin', 'Partner');
    final answeredList = answeredMap.values.toList().reversed.toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
      child: Column(
        children: [
          // ANİMASYONLU BEKLEME KARTI
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [
                        const Color(0xFF1E1B4B),
                        const Color(0xFF311042),
                      ]
                    : [
                        const Color(0xFFFAF5FF),
                        const Color(0xFFFDF2F8),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.35 : 0.25),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.14),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                // Nabız atan kum saati / kalp ikonu
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: const Center(
                    child: Text('⏳', style: TextStyle(fontSize: 40)),
                  ),
                )
                    .animate(onPlay: (controller) => controller.repeat(reverse: true))
                    .scale(begin: const Offset(0.92, 0.92), end: const Offset(1.08, 1.08), duration: 1400.ms),
                const SizedBox(height: 20),
                Text(
                  loc('Soru Bekleme Alanı', 'Question Waiting Room'),
                  style: TextStyle(
                    color: isDark ? Colors.white : LoveraColors.textDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  loc(
                    '$displayName şu anda devasa soru havuzunu inceliyor ve sana sormak için özel bir kart seçiyor... 💭',
                    '$displayName is browsing the question bank and picking a special card for you... 💭',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : LoveraColors.textMuted,
                    fontSize: 14,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF8B5CF6),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        loc('Soru Seçimi Bekleniyor...', 'Awaiting Question Selection...'),
                        style: const TextStyle(
                          color: Color(0xFF8B5CF6),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05),

          const SizedBox(height: 28),

          // ÖNCEKİ CEVAPLANAN SORULAR ARŞİVİ
          if (answeredList.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  const Text('💖', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(
                    loc('Cevaplanan Sorularınız (${answeredList.length})', 'Your Answered Questions (${answeredList.length})'),
                    style: TextStyle(
                      color: isDark ? Colors.white : LoveraColors.textDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: answeredList.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = Map<String, dynamic>.from(answeredList[index] as Map);
                final qText = loc(item['questionTr'] ?? '', item['questionEn'] ?? '');
                final emoji = item['emoji']?.toString() ?? '💖';
                final answeredBy = item['answeredByName']?.toString() ?? 'Partner';

                return InkWell(
                  onTap: () => _showAnswerDetailsModal(item),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? LoveraColors.darkSurface : LoveraColors.lightSurface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.35),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                qText,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 14),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      loc('$answeredBy yanıtladı (okumak için dokun)', '$answeredBy answered (tap to read)'),
                                      style: const TextStyle(
                                        color: Color(0xFF10B981),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: LoveraColors.textMuted, size: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
