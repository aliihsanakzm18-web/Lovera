import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/lovera_theme_background.dart';

class GamesView extends ConsumerStatefulWidget {
  const GamesView({super.key, this.onBackToHome});
  final VoidCallback? onBackToHome;

  @override
  ConsumerState<GamesView> createState() => _GamesViewState();
}

class _GamesViewState extends ConsumerState<GamesView> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  int _activeCardIndex = 0;
  final Random _rng = Random();

  final List<GameCategory> _categories = [
    GameCategory(
      title: 'Aşk & Uyum Testi',
      subtitle: 'Birbirinizi ne kadar iyi tanıyorsunuz?',
      icon: Icons.quiz_rounded,
      color: LoveraColors.primary,
      pages: [
        'Birlikte en çok ne yapmayı seversiniz?',
        'Partnerinin en sevdiği yemek ve tatlı nedir?',
        'İlk buluşmanızda seni en çok etkileyen detay neydi?',
        'İlişkinizin en unutulmaz günü hangisiydi?',
        'Partnerinin gizli süper gücü sence ne?',
        'Birlikte yaşlanınca kendinizi nerede hayal ediyorsunuz?',
      ],
    ),
    GameCategory(
      title: 'Doğruluk mu Cesaret mi?',
      subtitle: 'Romantik ve eğlenceli çift görevleri',
      icon: Icons.casino_rounded,
      color: LoveraColors.secondary,
      pages: [
        'Partnerine şu an hissettiğin en tatlı duyguyu sesli söyle.',
        'Birbirinize en son ne zaman sürpriz yaptınız?',
        'Partnerin için 10 saniyelik komik bir yüz ifadesi yap.',
        'Birlikte gitmek istediğiniz hayalinizdeki tatil yeri neresi?',
        'Partnerinin gözlerinin içine bakarak 15 saniye gülümsemeden dur.',
        'Telefonundaki en sevdiğin ortak fotoğrafınızı göster ve nedenini anlat.',
      ],
    ),
    GameCategory(
      title: 'Çift Soru Kartları',
      subtitle: 'Derin sohbet ve kalp kalbe paylaşımlar',
      icon: Icons.style_rounded,
      color: LoveraColors.accentViolet,
      pages: [
        'Bu yıl birlikte mutlaka gerçekleştirmek istediğimiz 3 hayal nedir?',
        'Zor bir gün geçirdiğinde partnerinin sana nasıl destek olması seni en çok rahatlatır?',
        'İlişkimizde seni en çok güvende ve mutlu hissettiren alışkanlığımız hangisi?',
        'Birbirimize daha sık söylememiz gereken güzel söz sence hangisi?',
        'Gelecekteki evimizde mutlaka olmasını istediğin en özel köşe nasıl olmalı?',
      ],
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _drawRandomCard(GameCategory cat) {
    HapticFeedback.mediumImpact();
    if (cat.pages.length <= 1) return;
    int next = _rng.nextInt(cat.pages.length);
    if (next == _activeCardIndex) {
      next = (next + 1) % cat.pages.length;
    }
    setState(() {
      _activeCardIndex = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final partner = ref.watch(partnerProvider);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F1015) : const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF161822) : Colors.white,
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
              child: const Icon(Icons.sports_esports_rounded, color: LoveraColors.primary, size: 22),
            ),
            const SizedBox(width: 10),
            Text(
              'Oyun & Eğlence',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
      body: LoveraThemeBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Kategori Seçim Sekmeleri
              Container(
                height: 54,
                margin: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    final isSelected = _currentPage == index;
                    return InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeInOutCubic,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? cat.color
                              : (isDark ? const Color(0xFF1C1E2A) : Colors.white),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? cat.color
                                : (isDark ? Colors.white12 : Colors.black12),
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: cat.color.withValues(alpha: 0.35),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              cat.icon,
                              size: 18,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : Colors.black87),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              cat.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: isSelected
                                    ? Colors.white
                                    : (isDark ? Colors.white70 : Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Oyun Kategorisi Sayfaları
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                      _activeCardIndex = 0;
                    });
                  },
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    final currentIdx = _activeCardIndex.clamp(0, cat.pages.length - 1);
                    final activeQuestion = cat.pages[currentIdx];

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
                      children: [
                        // Kategori Başlık & Rastgele Kart Çekme Kartı
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                cat.color,
                                cat.color.withValues(alpha: 0.78),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(AppTheme.radius),
                            boxShadow: [
                              BoxShadow(
                                color: cat.color.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
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
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(cat.icon, color: Colors.white, size: 26),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      partner != null ? 'Partner: ${partner.name}' : 'Çift Etkinliği',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                cat.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                cat.subtitle,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'AKTİF KART #${currentIdx + 1}',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.8),
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      activeQuestion,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: cat.color,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onPressed: () => _drawRandomCard(cat),
                                  icon: const Icon(Icons.shuffle_rounded, size: 18),
                                  label: const Text(
                                    'Rastgele Yeni Kart Çek',
                                    style: TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.08),

                        const SizedBox(height: 24),

                        Text(
                          'TÜM SORU & GÖREV KARTLARI',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: LoveraColors.textMuted,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),

                        const SizedBox(height: 12),

                        ...cat.pages.asMap().entries.map((entry) {
                          final pIdx = entry.key;
                          final pageText = entry.value;
                          final isCurrent = pIdx == currentIdx;
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _activeCardIndex = pIdx);
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(AppTheme.radius),
                                border: Border.all(
                                  color: isCurrent ? cat.color : theme.dividerColor,
                                  width: isCurrent ? 1.6 : 1.0,
                                ),
                                boxShadow: AppTheme.ambientShadow,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: cat.color.withValues(alpha: isCurrent ? 0.22 : 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${pIdx + 1}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: cat.color,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      pageText,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    isCurrent ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                                    color: isCurrent ? cat.color : LoveraColors.textMuted,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ).animate(delay: (pIdx * 60).ms).fadeIn().slideY(begin: 0.06),
                          );
                        }),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GameCategory {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<String> pages;

  GameCategory({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.pages,
  });
}
