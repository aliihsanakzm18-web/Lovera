import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';

class GamesView extends ConsumerStatefulWidget {
  const GamesView({super.key, this.onBackToHome});
  final VoidCallback? onBackToHome;

  @override
  ConsumerState<GamesView> createState() => _GamesViewState();
}

class _GamesViewState extends ConsumerState<GamesView> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<GameCategory> _categories = [
    GameCategory(
      title: 'Aşk & Uyum Testi',
      subtitle: 'Birbirinizi ne kadar iyi tanıyorsunuz?',
      icon: Icons.quiz_rounded,
      color: LoveraColors.primary,
      pages: [
        'Birlikte En Çok Ne Yapmayı Seversiniz?',
        'Partnerinin En Sevdiği Yemek Nedir?',
        'İlk Buluşmanız Neredeydi?',
        'İlişkinizin En Unutulmaz Günü Hangisiydi?',
      ],
    ),
    GameCategory(
      title: 'Doğruluk mu Cesaret mi?',
      subtitle: 'Romantik ve eğlenceli görevler',
      icon: Icons.casino_rounded,
      color: LoveraColors.secondary,
      pages: [
        'Partnerine şu an hissettiğin en tatlı duyguyu sesli söyle.',
        'Birbirinize en son ne zaman hediye aldınız?',
        'Partnerin için 10 saniyelik komik bir yüz ifadesi yap.',
        'Birlikte gitmek istediğiniz hayalinizdeki tatil yeri neresi?',
      ],
    ),
    GameCategory(
      title: 'Çift Kart Eşleştirme',
      subtitle: 'Görsel hafıza ve eğlence odası',
      icon: Icons.style_rounded,
      color: LoveraColors.accentViolet,
      pages: [
        'Kalp Kartları & Hatıra Puanı',
        'Zaman Tüneli Eşleşmesi',
        'Ortak Sır Kutusu',
      ],
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
      body: SafeArea(
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
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
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
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
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

            // Sayfalar Arası Swipe & İçerik Alanı
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                itemCount: _categories.length,
                itemBuilder: (context, catIdx) {
                  final cat = _categories[catIdx];
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                    children: [
                      // Başlık Kartı
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              cat.color.withValues(alpha: 0.85),
                              cat.color,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(AppTheme.radius),
                          boxShadow: [
                            BoxShadow(
                              color: cat.color.withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Icon(cat.icon, size: 36, color: Colors.white),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    partner != null ? 'Partner: ${partner.name}' : 'Eşleşme Bekleniyor',
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
                            const SizedBox(height: 6),
                            Text(
                              cat.subtitle,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.08),

                      const SizedBox(height: 24),

                      // Kategoriye ait sayfalar/sorular/kartlar
                      Text(
                        'ETKİNLİK LİSTESİ',
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
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(AppTheme.radius),
                            border: Border.all(color: theme.dividerColor),
                            boxShadow: AppTheme.ambientShadow,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: cat.color.withValues(alpha: 0.12),
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
                                Icons.chevron_right_rounded,
                                color: LoveraColors.textMuted,
                                size: 20,
                              ),
                            ],
                          ),
                        ).animate(delay: (pIdx * 80).ms).fadeIn().slideY(begin: 0.06);
                      }),
                    ],
                  );
                },
              ),
            ),
          ],
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
