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
import 'dart:async';
import '../../../core/services/database_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/state/app_state.dart';

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

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialPage;
    _pageController = PageController(initialPage: widget.initialPage);

    // Uygulama açık olduğu sürece (ister ana sayfada, ister sohbette, ister oyunda)
    // her 15 saniyede bir partnerin "Şimdi aktif" görmesi için presence heartbeat gönder
    DatabaseService().setAppPresence(true);
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      DatabaseService().setAppPresence(true);
    });

    _lifecycleListener = AppLifecycleListener(
      onResume: () => DatabaseService().setAppPresence(true),
      onPause: () => DatabaseService().setAppPresence(false),
      onDetach: () => DatabaseService().setAppPresence(false),
    );

    // Bildirim servisini bağla:
    // 1) Kullanıcı sohbetteyken bildirimleri sessize al
    // 2) Bildirime tıklandığında doğrudan Sohbet (Sayfa 2) sayfasına uçur
    NotificationService().isChatScreenActive = () => _currentIndex == 2;
    NotificationService().onNotificationTap = () {
      if (mounted) {
        _goToPage(2);
      }
    };

    // Cihaz internete bağlı ve uygulama açık olduğu anda partnerin attığı mesajları
    // "İletildi (Çift gri tik)" olarak işaretle!
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeNavigationIndexProvider.notifier).state = _currentIndex;
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
          });
        }
      }

      setupDeliveryListener(ref.read(coupleIdProvider));
      // coupleId sonradan yüklenirse de dinleyiciyi başlat
      ref.listenManual(coupleIdProvider, (prev, next) {
        if (next != prev && next != null) {
          setupDeliveryListener(next);
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

  @override
  void dispose() {
    NotificationService().isChatScreenActive = null;
    NotificationService().onNotificationTap = null;
    _deliverySub?.cancel();
    _heartbeatTimer?.cancel();
    _lifecycleListener?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    if (index == _currentIndex) return;
    FocusManager.instance.primaryFocus?.unfocus();
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
    ref.read(activeNavigationIndexProvider.notifier).state = index;
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
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() => _currentIndex = idx);
          ref.read(activeNavigationIndexProvider.notifier).state = idx;
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
