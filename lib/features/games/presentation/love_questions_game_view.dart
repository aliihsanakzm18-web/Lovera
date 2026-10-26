import 'dart:async';
import 'dart:math' as math;

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
import '../../chat/presentation/chat_view.dart';
import '../data/question_bank.dart';
import 'widgets/coin_flip_3d.dart';

class LoveQuestionsGameView extends ConsumerStatefulWidget {
  const LoveQuestionsGameView({super.key});

  @override
  ConsumerState<LoveQuestionsGameView> createState() => _LoveQuestionsGameViewState();
}

class _LoveQuestionsGameViewState extends ConsumerState<LoveQuestionsGameView> with WidgetsBindingObserver {
  final TextEditingController _answerController = TextEditingController();
  String _selectedCategory = 'all';
  bool _sortByAnsweredFirst = false;
  bool _isSubmittingAnswer = false;
  bool _isFlippingCoinLocal = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _gameSub;
  Map<String, dynamic>? _lastGameData;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initGameStream();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // SADECE kullanıcı uygulamayı tamamen kapattığında (detached / kill)
    // Oyun durumunu ve cevaplanan tüm soruları (answeredMap) koruyoruz.
    // Tekrar girildiğinde sırayı belirlemek için oyunu zar/yazı-tura (coin_flip) aşamasına alıyoruz.
    // Oyun status'u ASLA iptal edilmez veya 'partner_left' yapılmaz; böylece partner oyundan zorla atılmaz.
    if (state == AppLifecycleState.detached) {
      final coupleId = ref.read(coupleIdProvider);
      if (coupleId != null && coupleId.isNotEmpty) {
        DatabaseService().updateGameState(
          coupleId: coupleId,
          gameType: 'love_questions',
          updates: {
            'step': 'coin_flip',
            'activeQuestionId': null,
            'answeringUid': null,
            'isReturnedQuestion': false,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        ).catchError((_) {});
      }
    }
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
    WidgetsBinding.instance.removeObserver(this);
    // Uygulama içinde geri çıkıldığında oyun durumunu sıfırlama, kullanıcı istediği zaman kaldığı yerden geri dönebilir
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
        'player1Uid': p1Uid,
        'player1Name': p1Name,
        'player2Uid': p2Uid,
        'player2Name': p2Name,
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
    final gameData = _lastGameData;
    if (coupleId == null || myUid == null || gameData == null) return;

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
    final existingAnswerEntry = answeredMap[qId];
    List<dynamic> answersList = [];
    if (existingAnswerEntry is Map && existingAnswerEntry['answers'] is List) {
      answersList = List<dynamic>.from(existingAnswerEntry['answers'] as List);
    } else if (existingAnswerEntry is Map && existingAnswerEntry['answerText'] != null) {
      answersList.add({
        'answeredByUid': existingAnswerEntry['answeredByUid'],
        'answeredByName': existingAnswerEntry['answeredByName'],
        'answerText': existingAnswerEntry['answerText'],
        'timestamp': existingAnswerEntry['timestamp'],
      });
    }

    answersList.add({
      'answeredByUid': myUid,
      'answeredByName': myName.isNotEmpty ? myName : 'Ben',
      'answerText': text,
      'timestamp': DateTime.now().toIso8601String(),
    });

    final completeAnswerEntry = {
      ...answeredItem,
      'answers': answersList,
    };

    answeredMap[qId] = completeAnswerEntry;

    // Soruyu ben cevapladığıma göre, sıradaki yeni soruyu havuzdan seçme hakkı BANA (myUid) geçmeli!
    await DatabaseService().updateGameState(
      coupleId: coupleId,
      gameType: 'love_questions',
      updates: {
        'step': 'answering_question', // Cevap ekranda kalsın, iki taraf da okuyabilsin
        'turnUid': myUid,             // Sıradaki soruyu havuzdan seçme sırası cevaplayan kişide (Bende)
        'turnName': myName.isNotEmpty ? myName : 'Ben',
        'activeQuestionId': qId,
        'lastAnsweredItem': completeAnswerEntry,
        'answeredMap': answeredMap,
        'answeringUid': null,         // Kullanıcı cevap verdi, tekrar cevap yazamasın
        'isReturnedQuestion': false,  // Yanıtlandı, iade durumu sıfırlandı
        'lastAnsweredByUid': myUid,   // En son kimin cevapladığı kaydedilir
      },
    );

    if (mounted) {
      _answerController.clear();
      setState(() => _isSubmittingAnswer = false);
      HapticFeedback.vibrate();
      _showSuccessDialog(completeAnswerEntry);
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
                loc('Cevabın Gönderildi!', 'Answer Sent!'),
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
                'Harika! Cevabın sorunun altına mühürlendi ve partnerin ekranında belirdi. Sıra partnerine geçti! 💕',
                'Awesome! Your answer is sealed below the question and appeared on your partner\'s screen. Turn passed to your partner! 💕',
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
            child: Text(loc('Harika ✨', 'Awesome ✨')),
          ),
        ],
      ),
    );
  }

  Future<void> _askBackSameQuestion(Map<String, dynamic> gameData) async {
    final coupleId = ref.read(coupleIdProvider);
    final myUid = DatabaseService().uid;
    final myName = ref.read(userNameProvider);
    final partner = ref.read(partnerProvider);
    if (coupleId == null || myUid == null || partner == null) return;

    final partnerUid = partner.id.toString();
    final partnerName = partner.name.toString();
    final qId = gameData['activeQuestionId']?.toString() ?? '';
    if (qId.isEmpty) return;

    HapticFeedback.heavyImpact();

    await DatabaseService().updateGameState(
      coupleId: coupleId,
      gameType: 'love_questions',
      updates: {
        'step': 'answering_question',
        'activeQuestionId': qId,
        'askedByUid': myUid,
        'askedByName': myName.isNotEmpty ? myName : 'Ben',
        'answeringUid': partnerUid,
        'answeringName': partnerName,
        'turnUid': partnerUid,
        'isReturnedQuestion': true,
      },
    );

    NotificationService().sendPushToPartner(
      partnerUid: partnerUid,
      title: loc('Aynı Soruyu Partnerin Sana Sordu! 💌', 'Partner Asked You The Same Question! 💌'),
      body: loc('$myName bu sorunun cevabını senin için de merak ediyor!', '$myName wants to know your answer to this question too!'),
      titleTr: 'Aynı Soruyu Partnerin Sana Sordu! 💌',
      titleEn: 'Partner Asked You The Same Question! 💌',
      bodyTr: '$myName bu sorunun cevabını senin için de merak ediyor!',
      bodyEn: '$myName wants to know your answer to this question too!',
      data: {'type': 'game_action', 'game': 'love_questions'},
    );
  }

  Future<void> _finishQuestionAndProceed() async {
    final coupleId = ref.read(coupleIdProvider);
    final myUid = DatabaseService().uid;
    final myName = ref.read(userNameProvider);
    final gameData = _lastGameData;
    if (coupleId == null || gameData == null) return;

    HapticFeedback.mediumImpact();
    await DatabaseService().updateGameState(
      coupleId: coupleId,
      gameType: 'love_questions',
      updates: {
        'step': 'picking_question',
        'activeQuestionId': null,
        'turnUid': myUid,
        'turnName': myName.isNotEmpty ? myName : 'Ben',
      },
    );
  }

  void _showAnswerDetailsModal(Map<String, dynamic> item) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final qText = loc(item['questionTr'] ?? '', item['questionEn'] ?? '');
    final emoji = item['emoji']?.toString() ?? '💖';

    List<Map<String, dynamic>> answersList = [];
    if (item['answers'] is List) {
      answersList = (item['answers'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else if (item['answerText'] != null) {
      answersList.add({
        'answeredByName': item['answeredByName'] ?? 'Partner',
        'answerText': item['answerText'],
        'timestamp': item['timestamp'],
      });
    }

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
        child: SingleChildScrollView(
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
                            loc('MÜHÜRLENMİŞ ANILAR 💖', 'SEALED MEMORIES 💖'),
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
                          loc('${answersList.length} yanıt kaydedildi', '${answersList.length} answers saved'),
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
              ...answersList.map((ans) {
                final aName = ans['answeredByName']?.toString() ?? 'Partner';
                final aContent = ans['answerText']?.toString() ?? '';
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
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
                            loc('$aName yanıtı:', '$aName\'s answer:'),
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
                        aContent,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 14),
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
    final bool isReturnedQuestion = gameData?['isReturnedQuestion'] == true;
    final bool amIAnswering = answeringUid == myUid && activeQuestionId.isNotEmpty;

    final String p1Uid = gameData?['player1Uid']?.toString() ?? (myUid ?? '');
    final String p1Name = gameData?['player1Name']?.toString() ?? myName;
    final String p2Uid = gameData?['player2Uid']?.toString() ?? (partner?.id ?? '');
    final String p2Name = gameData?['player2Name']?.toString() ?? (partner?.name ?? 'Partner');
    final coinWinnerUid = gameData?['coinWinnerUid']?.toString() ?? turnUid;
    final coinWinnerName = gameData?['coinWinnerName']?.toString() ?? turnName;
    final coupleId = ref.watch(coupleIdProvider) ?? '';
    final isRoomCreator = p1Uid == myUid;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        // Kullanıcı oyun ekranından geri tuşuyla uygulama içinde başka yere gittiğinde oyunu sonlandırmıyoruz.
        // Partner oyundan atılmaz, veriler korunur. İki taraf da istediği an "Oyuna Devam Et" ile devam edebilir.
      },
      child: Scaffold(
        backgroundColor: isDark ? LoveraColors.darkBg : LoveraColors.lightBg,
        appBar: AppBar(
          backgroundColor: isDark ? LoveraColors.darkSurface : LoveraColors.lightSurface,
          elevation: 0.5,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () {
              Navigator.of(context).maybePop();
            },
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
        actions: [
          if (coupleId.isNotEmpty)
            StreamBuilder<List<ChatMessage>>(
              stream: DatabaseService().messagesStream(coupleId),
              builder: (context, snapshot) {
                final messages = snapshot.data ?? [];
                final unreadCount = messages.where((m) => m.senderId != myUid && !m.isRead).length;
                return _buildChatActionButton(context, unreadCount);
              },
            ),
          const SizedBox(width: 6),
        ],
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
                isReturnedQuestion: isReturnedQuestion,
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
                        isMyTurn: isMyTurn,
                        isDark: isDark,
                      )
                    : (step == 'coin_flip' || step == 'flipping_coin' || step == 'coin_result')
                        ? _buildCoinFlipSection(
                            p1Uid: p1Uid,
                            p1Name: p1Name,
                            p2Uid: p2Uid,
                            p2Name: p2Name,
                            winnerUid: coinWinnerUid,
                            winnerName: coinWinnerName,
                            isRoomCreator: isRoomCreator,
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
    ),
  );
}

  Widget _buildTopStatusBanner({
    required String step,
    required bool isMyTurn,
    required bool amIAnswering,
    required bool isReturnedQuestion,
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
    } else if (isReturnedQuestion && amIAnswering) {
      message = loc('Aynı soruyu partnerin sana sordu! 💌', 'Partner asked you the same question! 💌');
      bannerBg = const Color(0xFFEC4899);
      icon = Icons.swap_calls_rounded;
    } else if (isReturnedQuestion && !amIAnswering) {
      message = loc('Aynı soruyu partnerine sordun! Yanıtı bekleniyor... ⏳', 'You asked partner the same question! Awaiting answer... ⏳');
      bannerBg = const Color(0xFF8B5CF6);
      icon = Icons.hourglass_top_rounded;
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

  Widget _buildChatActionButton(BuildContext context, int unreadCount) {
    return IconButton(
      tooltip: loc('Sohbet 💬', 'Chat 💬'),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: unreadCount > 0
                  ? LoveraColors.primary.withValues(alpha: 0.18)
                  : LoveraColors.primarySoft.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_rounded,
              color: unreadCount > 0 ? LoveraColors.primary : LoveraColors.primaryDeep,
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
                  color: LoveraColors.primary,
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

  // --- YAZI TURA BÖLÜMÜ ---
  Widget _buildCoinFlipSection({
    required String p1Uid,
    required String p1Name,
    required String p2Uid,
    required String p2Name,
    required String winnerUid,
    required String winnerName,
    required bool isRoomCreator,
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

            // 3D Animasyonlu Para (İki tarafta %100 aynı sonucu ve aynı yüzü göstermesi için UID'ler bağlandı)
            CoinFlip3D(
              player1Name: p1Name,
              player2Name: p2Name,
              player1Uid: p1Uid,
              player2Uid: p2Uid,
              winnerUid: winnerUid,
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
                      LoveraColors.primary.withValues(alpha: 0.18),
                      LoveraColors.primarySoft.withValues(alpha: 0.14),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: LoveraColors.primary.withValues(alpha: 0.4),
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
                          style: TextStyle(
                            color: LoveraColors.primary,
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
                          backgroundColor: LoveraColors.primary,
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
                width: 240,
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: LoveraColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                  ),
                  onPressed: _startCoinFlip,
                  icon: const Icon(Icons.casino_rounded, size: 22),
                  label: Text(
                    loc('Zarı / Parayı Fırlat! 🎲🪙', 'Roll / Flip The Coin! 🎲🪙'),
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
    required bool isMyTurn,
    required bool isDark,
  }) {
    final qText = loc(gameData['activeQuestionTr'] ?? '', gameData['activeQuestionEn'] ?? '');
    final emoji = gameData['activeQuestionEmoji'] ?? '💖';
    final askedBy = gameData['askedByName'] ?? 'Partner';
    final answeringBy = gameData['answeringName'] ?? 'Partner';
    final myUid = DatabaseService().uid;
    final partner = ref.watch(partnerProvider);
    final partnerUid = partner?.id.toString() ?? '';

    final qId = gameData['activeQuestionId']?.toString() ?? '';
    final Map<String, dynamic> answeredMap = Map<String, dynamic>.from(gameData['answeredMap'] ?? {});
    final currentAnsweredEntry = answeredMap[qId];

    List<Map<String, dynamic>> answersList = [];
    if (currentAnsweredEntry is Map && currentAnsweredEntry['answers'] is List) {
      answersList = (currentAnsweredEntry['answers'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else if (currentAnsweredEntry is Map && currentAnsweredEntry['answerText'] != null) {
      answersList.add({
        'answeredByUid': currentAnsweredEntry['answeredByUid'],
        'answeredByName': currentAnsweredEntry['answeredByName'],
        'answerText': currentAnsweredEntry['answerText'],
        'timestamp': currentAnsweredEntry['timestamp'],
      });
    }

    final bool hasMyAnswer = answersList.any((a) => a['answeredByUid'] == myUid);
    final bool hasPartnerAnswer = answersList.any((a) => a['answeredByUid'] == partnerUid);

    // Sıradaki soruya geçebilme hakkı kuralları:
    // 1. Eğer bir taraf henüz soruyu cevaplamadıysa (yani cevap süreci devam ediyorsa veya iade edilmiş soru bekleniyorsa)
    //    "Sıradaki Soruya Geç" kutusu HİÇ KİMSEYE gösterilmez!
    // 2. Ancak aktif soru üzerinde cevaplama süreci tamamlandığında:
    //    - Eğer "Aynı soruyu partnerine sor" yapıldıysa veya normal cevaplandıysa:
    //      Soruyu EN SON cevaplayan kişi (lastAnsweredByUid) sıradaki yeni soruyu seçme hakkına sahiptir!
    final bool isReturnedQuestion = gameData['isReturnedQuestion'] == true;
    final bool isStillWaitingForAnswer = (gameData['answeringUid'] != null && gameData['answeringUid'].toString().isNotEmpty) || isReturnedQuestion;

    final String lastAnsweredByUid = gameData['lastAnsweredByUid']?.toString() ?? (
      answersList.isNotEmpty ? answersList.last['answeredByUid']?.toString() ?? '' : ''
    );

    final bool canIProceedToNext = !isStillWaitingForAnswer && (
        lastAnsweredByUid.isNotEmpty
            ? (lastAnsweredByUid == myUid) // Soruyu en son ben cevapladım -> sıradaki soruyu seçme hakkı BENDE
            : isMyTurn
    );

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
                        gameData['isReturnedQuestion'] == true
                            ? loc('Aynı soru partnerinden döndü 🔄', 'Same question returned 🔄')
                            : '$askedBy sordu 💌',
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
                          amIAnswering && !hasMyAnswer
                              ? (gameData['isReturnedQuestion'] == true
                                  ? loc('Aynı soruyu partnerin sana sordu! Cevabını yaz ✍️', 'Partner asked you the same question! Write your answer ✍️')
                                  : loc('Bu soruyu sen cevaplıyorsun ✍️', 'You are answering this question ✍️'))
                              : (!hasPartnerAnswer && answersList.isNotEmpty
                                  ? loc('$answeringBy şu an yanıtını yazıyor... ⏳', '$answeringBy is writing their answer... ⏳')
                                  : loc('Cevaplar sorunun altında mühürlendi 💖', 'Answers sealed below 💖')),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.92, 0.92)),

          const SizedBox(height: 20),

          // 1. SORUNUN ALTINDAKİ CANLI CEVAPLAR (İki tarafın da hemen okuyabilmesi için)
          if (answersList.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  const Text('💬', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(
                    loc('Verilen Cevaplar (${answersList.length})', 'Given Answers (${answersList.length})'),
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
            ...answersList.map((ans) {
              final aName = ans['answeredByName']?.toString() ?? 'Partner';
              final aContent = ans['answerText']?.toString() ?? '';
              final isMyAns = ans['answeredByUid'] == myUid;
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? LoveraColors.darkSurface : LoveraColors.lightSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isMyAns
                        ? LoveraColors.primary.withValues(alpha: 0.35)
                        : const Color(0xFF10B981).withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                  boxShadow: AppTheme.ambientShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: (isMyAns ? LoveraColors.primary : const Color(0xFF10B981)).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isMyAns ? Icons.person_rounded : Icons.favorite_rounded,
                            color: isMyAns ? LoveraColors.primary : const Color(0xFF10B981),
                            size: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          loc('$aName yanıtı:', '$aName\'s answer:'),
                          style: TextStyle(
                            color: isMyAns ? LoveraColors.primary : const Color(0xFF10B981),
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      aContent,
                      style: TextStyle(
                        color: isDark ? Colors.white : LoveraColors.textDark,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn().slideY(begin: 0.05);
            }),
            const SizedBox(height: 14),

            // SIRA SIRASI VE AYNI SORUYU PARTNERE SORMA BUTONLARI
            if (answersList.isNotEmpty && (!isStillWaitingForAnswer || (hasMyAnswer && !hasPartnerAnswer && !isReturnedQuestion)))
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: LoveraColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: LoveraColors.primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  // "Aynı soruyu sende ona sor" butonu (Eğer ben cevapladıysam ve partner henüz cevaplamadıysa ve şu an birine iade edilmediyse)
                  if (hasMyAnswer && !hasPartnerAnswer && !isReturnedQuestion) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFEC4899),
                          elevation: 3,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () => _askBackSameQuestion(gameData),
                        icon: const Icon(Icons.swap_calls_rounded, size: 20),
                        label: Text(
                          loc('Aynı Soruyu Sen de Ona Sor! 💌', 'Ask Back The Same Question! 💌'),
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                        ),
                      ),
                    ).animate(onPlay: (controller) => controller.repeat(reverse: true))
                     .shimmer(duration: 1800.ms, color: Colors.white24)
                     .scale(begin: const Offset(0.98, 0.98), end: const Offset(1.02, 1.02), duration: 1200.ms),
                    const SizedBox(height: 8),
                  ],

                  // Soruyu tamamlama ve havuzdan yeni soru seçme butonları
                  // SADECE aktif soruya cevap beklenmiyorken ve sıra kendine geçmişken gösterilir
                  if (canIProceedToNext)
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: LoveraColors.primary,
                          side: BorderSide(color: LoveraColors.primary.withValues(alpha: 0.5), width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _finishQuestionAndProceed,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: Text(
                          loc('Sıradaki Soruya Geç 🚀', 'Proceed to Next Question 🚀'),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                        ),
                      ),
                    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.1)
                  else if (!isStillWaitingForAnswer)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.hourglass_empty_rounded, size: 16, color: LoveraColors.textMuted),
                          const SizedBox(width: 6),
                          Text(
                            loc('Sıradaki soruyu partnerin seçecek...', 'Your partner will pick the next question...'),
                            style: TextStyle(
                              color: LoveraColors.textMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ).animate(onPlay: (controller) => controller.repeat(reverse: true)).fadeIn(duration: 800.ms),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // 2. CEVAP YAZMA FORMU (Kullanıcı zaten cevap vermediyse ve cevaplama sırası ondaysa)
          if (amIAnswering && !hasMyAnswer) ...[
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
                    gameData['isReturnedQuestion'] == true
                        ? loc('Aynı Soruyu Partnerin Sana Sordu! 💖', 'Partner Asked You The Same Question! 💖')
                        : loc('Cevabını Yaz 💖', 'Write Your Answer 💖'),
                    style: TextStyle(
                      color: isDark ? Colors.white : LoveraColors.textDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    loc('Cevabın sorunun altına eklenecek ve partnerin anında okuyabilecek.', 'Your answer will be sealed below and partner can read instantly.'),
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
          ] else if (answersList.isEmpty || (!hasPartnerAnswer && hasMyAnswer)) ...[
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

    final List<QuestionCard> sortedQuestions = List<QuestionCard>.from(questions);
    final myUid = DatabaseService().uid;
    if (_sortByAnsweredFirst) {
      int getScore(QuestionCard q) {
        if (!answeredMap.containsKey(q.id)) return 0;
        final entry = answeredMap[q.id];
        List<dynamic> answers = [];
        if (entry is Map) {
          if (entry['answers'] is List) {
            answers = entry['answers'] as List;
          } else if (entry['answerText'] != null) {
            answers.add(entry);
          }
        }
        final bool hasMy = answers.any((a) => (a is Map) && a['answeredByUid'] == myUid);
        final bool hasPartner = answers.any((a) => (a is Map) && a['answeredByUid'] != myUid);
        if (hasMy && hasPartner) return 2; // İkiniz de cevapladınız -> En üstte (2)
        return 1; // Tek kişi cevapladı -> Ortada (1)
      }

      sortedQuestions.sort((a, b) {
        final aScore = getScore(a);
        final bScore = getScore(b);
        return bScore.compareTo(aScore); // 2 > 1 > 0
      });
    }

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
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _sortByAnsweredFirst = !_sortByAnsweredFirst;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _sortByAnsweredFirst
                        ? const Color(0xFF10B981)
                        : const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: _sortByAnsweredFirst ? 1.0 : 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _sortByAnsweredFirst ? Icons.arrow_upward_rounded : Icons.sort_rounded,
                        size: 13,
                        color: _sortByAnsweredFirst ? Colors.white : const Color(0xFF10B981),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        loc('$totalAnsweredCount Cevaplandı 💖', '$totalAnsweredCount Answered 💖'),
                        style: TextStyle(
                          color: _sortByAnsweredFirst ? Colors.white : const Color(0xFF10B981),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
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
            itemCount: sortedQuestions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final q = sortedQuestions[index];
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
    final myUid = DatabaseService().uid;

    List<dynamic> answersList = [];
    if (answeredData != null) {
      if (answeredData['answers'] is List) {
        answersList = answeredData['answers'] as List;
      } else if (answeredData['answerText'] != null) {
        answersList.add(answeredData);
      }
    }

    final bool hasMyAnswer = answersList.any((a) => (a is Map) && a['answeredByUid'] == myUid);
    final bool hasPartnerAnswer = answersList.any((a) => (a is Map) && a['answeredByUid'] != myUid);
    final bool bothAnswered = hasMyAnswer && hasPartnerAnswer;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        if (isAnswered && answeredData != null) {
          // Eğer sıra bendeyse ve ben cevaplamışsam ama partner henüz cevaplamamışsa, hem okuma hem de "Ona Sor" opsiyonu sunulur
          if (isMyTurn && !hasPartnerAnswer) {
            _showAskOrReadBottomSheet(q, answeredData);
          } else {
            HapticFeedback.selectionClick();
            _showAnswerDetailsModal(answeredData);
          }
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
            color: bothAnswered
                ? const Color(0xFF10B981).withValues(alpha: 0.6)
                : (isAnswered
                    ? LoveraColors.primary.withValues(alpha: 0.5)
                    : (isMyTurn ? LoveraColors.primary.withValues(alpha: 0.3) : theme.dividerColor)),
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
                color: bothAnswered
                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                    : (isAnswered
                        ? LoveraColors.primary.withValues(alpha: 0.15)
                        : LoveraColors.primary.withValues(alpha: 0.12)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  bothAnswered ? '💑' : (isAnswered ? '💖' : q.emoji),
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
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: (bothAnswered ? const Color(0xFF10B981) : LoveraColors.primary).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            bothAnswered
                                ? loc('İKİNİZ DE CEVAPLADINIZ 💑', 'BOTH ANSWERED 💑')
                                : (hasMyAnswer
                                    ? loc('SEN CEVAPLADIN 💌', 'YOU ANSWERED 💌')
                                    : loc('PARTNERİN CEVAPLADI ✨', 'PARTNER ANSWERED ✨')),
                            style: TextStyle(
                              color: bothAnswered ? const Color(0xFF10B981) : LoveraColors.primary,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        Text(
                          loc('(Detay için tıkla)', '(Tap for details)'),
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
              bothAnswered
                  ? Icons.verified_rounded
                  : (isAnswered
                      ? Icons.favorite_rounded
                      : (isMyTurn ? Icons.touch_app_rounded : Icons.chevron_right_rounded)),
              color: bothAnswered
                  ? const Color(0xFF10B981)
                  : (isAnswered ? LoveraColors.primary : (isMyTurn ? LoveraColors.primary : LoveraColors.textMuted)),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  void _showAskOrReadBottomSheet(QuestionCard q, Map<String, dynamic> answeredData) {
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
            const SizedBox(height: 18),
            Row(
              children: [
                Text(q.emoji, style: const TextStyle(fontSize: 32)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    loc('Bu Soruyu Partnere Sor?', 'Ask This Question To Partner?'),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              qText,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.35),
            ),
            const SizedBox(height: 8),
            Text(
              loc(
                'Bu soruyu daha önce sen cevaplamıştın. Şimdi sıra sende ve aynı soruyu partnerine sorup onun da cevabını alabilirsin!',
                'You already answered this question before. Now it\'s your turn and you can ask it to your partner to hear their answer!',
              ),
              style: TextStyle(color: LoveraColors.textMuted, fontSize: 12.5),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showAnswerDetailsModal(answeredData);
                    },
                    icon: const Icon(Icons.menu_book_rounded, size: 18),
                    label: Text(loc('Cevabımı Oku', 'Read My Answer')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: LoveraColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _selectQuestion(q);
                    },
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: Text(
                      loc('Partnere Sor! 💌', 'Ask Partner! 💌'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
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
