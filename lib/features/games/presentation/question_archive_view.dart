import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/services/database_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/lovera_theme_background.dart';
import '../data/question_bank.dart';

class QuestionArchiveView extends ConsumerStatefulWidget {
  const QuestionArchiveView({super.key});

  @override
  ConsumerState<QuestionArchiveView> createState() => _QuestionArchiveViewState();
}

class _QuestionArchiveViewState extends ConsumerState<QuestionArchiveView> {
  String _selectedCategory = 'all';
  bool _sortByAnsweredFirst = false;

  void _showAnswerDetailsModal(Map<String, dynamic> item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
    final coupleId = ref.watch(coupleIdProvider) ?? '';
    final myUid = DatabaseService().uid;

    final List<QuestionCard> questions = _selectedCategory == 'all'
        ? QuestionBank.allQuestions
        : QuestionBank.getByCategory(_selectedCategory);

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
              child: const Text('📖', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc('Soru & Cevap Arşivi', 'Question & Answer Archive'),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  Text(
                    loc('Tüm sorular ve mühürlenen anılar', 'All questions and sealed memories'),
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
          child: StreamBuilder(
            stream: coupleId.isNotEmpty ? DatabaseService().gameStream(coupleId, 'love_questions') : null,
            builder: (context, snapshot) {
              final gameData = snapshot.data?.data();
              final Map<String, dynamic> answeredMap = Map<String, dynamic>.from(gameData?['answeredMap'] ?? {});
              final int totalAnsweredCount = answeredMap.length;

              final List<QuestionCard> sortedQuestions = List<QuestionCard>.from(questions);
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

                        List<dynamic> answersList = [];
                        if (answeredData is Map) {
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
                            if (isAnswered && answeredData is Map) {
                              HapticFeedback.selectionClick();
                              _showAnswerDetailsModal(Map<String, dynamic>.from(answeredData));
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(loc('Bu soru henüz cevaplanmamış ✨', 'This question is not answered yet ✨')),
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
                                        : theme.dividerColor),
                                width: isAnswered ? 1.6 : 1.0,
                              ),
                              boxShadow: AppTheme.ambientShadow,
                            ),
                            child: Row(
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
                                        loc(q.questionTr, q.questionEn),
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
                                      : (isAnswered ? Icons.favorite_rounded : Icons.lock_outline_rounded),
                                  color: bothAnswered
                                      ? const Color(0xFF10B981)
                                      : (isAnswered ? LoveraColors.primary : LoveraColors.textMuted),
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? color
              : (isDark ? LoveraColors.darkSurface : LoveraColors.lightSurface),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : (isDark ? Colors.white12 : Colors.grey.withValues(alpha: 0.2)),
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
}
