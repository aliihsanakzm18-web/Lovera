import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../chat/presentation/chat_view.dart';
import '../../dashboard/presentation/dashboard_view.dart';
import '../../games/presentation/games_view.dart';
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
class MainNavigationShell extends ConsumerStatefulWidget {
  const MainNavigationShell({super.key, this.initialPage = 1});
  final int initialPage;

  @override
  ConsumerState<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends ConsumerState<MainNavigationShell> {
  late final PageController _pageController;
  int _currentIndex = 1;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialPage;
    _pageController = PageController(initialPage: widget.initialPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
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
      body: PageView(
        controller: _pageController,
        physics: const BouncingScrollPhysics(),
        onPageChanged: (idx) {
          setState(() => _currentIndex = idx);
        },
        children: [
          // Sayfa 0: Canlı Harita
          LiveMapView(
            onBackToHome: () => _goToPage(1),
          ),

          // Sayfa 1: Ana Sayfa (Dashboard)
          DashboardView(
            onOpenMap: () => _goToPage(0),
            onOpenChat: () => _goToPage(2),
          ),

          // Sayfa 2: Mesajlaşma (Chat)
          ChatView(
            onBackToHome: () => _goToPage(1),
          ),

          // Sayfa 3: Oyun & Eğlence Odası (Games)
          GamesView(
            onBackToHome: () => _goToPage(1),
          ),
        ],
      ),

      // Ekranın altında sabit kalan (scroll ile kaymayan), temaya uyumlu alt navigasyon barı
      bottomNavigationBar: _buildBottomBar(isDark),
    );
  }

  Widget _buildBottomBar(bool isDark) {
    // Haritadayken (Sayfa 0) harita deneyimini engellememek için veya tam ekran harita için de bar gösterilebilir;
    // Ancak ana sayfa, mesajlar ve oyun butonları her zaman sabit durur.
    final navBgColor = isDark
        ? const Color(0xFF141620).withValues(alpha: 0.96)
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
                activeColor: LoveraColors.primary,
                tooltip: 'Ana Sayfa',
                onTap: () => _goToPage(1),
              ),

              // 2. Mesajlaşma Butonu (index: 2)
              _BottomNavItem(
                icon: Icons.chat_bubble_outline_rounded,
                selectedIcon: Icons.chat_bubble_rounded,
                isSelected: _currentIndex == 2,
                activeColor: LoveraColors.secondary,
                tooltip: 'Sohbet',
                onTap: () => _goToPage(2),
              ),

              // 3. Oyun & Eğlence Butonu (index: 3)
              _BottomNavItem(
                icon: Icons.sports_esports_outlined,
                selectedIcon: Icons.sports_esports_rounded,
                isSelected: _currentIndex == 3,
                activeColor: LoveraColors.accentViolet,
                tooltip: 'Oyun',
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
  });

  final IconData icon;
  final IconData selectedIcon;
  final bool isSelected;
  final Color activeColor;
  final String tooltip;
  final VoidCallback onTap;

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
