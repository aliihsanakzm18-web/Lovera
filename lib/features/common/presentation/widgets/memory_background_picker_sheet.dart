import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/models/models.dart';
import '../../../../core/services/background_slideshow_service.dart';
import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/avatar_cache.dart';

/// Hem Mesajlar hem de Widget için Ortak Anı Albümü Seçim Modalı
class MemoryBackgroundPickerSheet extends ConsumerStatefulWidget {
  final String coupleId;
  final String target; // 'chat' veya 'widget'
  final void Function(String base64Image) onSingleImageSelected;
  final void Function(SlideshowConfig config)? onSlideshowConfigured;

  const MemoryBackgroundPickerSheet({
    super.key,
    required this.coupleId,
    required this.target,
    required this.onSingleImageSelected,
    this.onSlideshowConfigured,
  });

  @override
  ConsumerState<MemoryBackgroundPickerSheet> createState() => _MemoryBackgroundPickerSheetState();
}

class _MemoryBackgroundPickerSheetState extends ConsumerState<MemoryBackgroundPickerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedIntervalSeconds = 60; // Varsayılan 1 dakika
  String _selectedSource = 'all'; // 'all' veya 'album:<albumId>'
  String _selectedAlbumTitle = '';

  final List<Map<String, dynamic>> _intervals = [
    {'label': '30 Saniye', 'seconds': 30},
    {'label': '1 Dakika', 'seconds': 60},
    {'label': '5 Dakika', 'seconds': 300},
    {'label': '15 Dakika', 'seconds': 900},
    {'label': '1 Saat', 'seconds': 3600},
    {'label': '6 Saat', 'seconds': 21600},
    {'label': '1 Gün', 'seconds': 86400},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadExistingConfig();
  }

  Future<void> _loadExistingConfig() async {
    final cfg = await BackgroundSlideshowService().getConfig(widget.target);
    if (mounted && cfg.isEnabled) {
      setState(() {
        _selectedIntervalSeconds = cfg.intervalSeconds;
        _selectedSource = cfg.source;
        _selectedAlbumTitle = cfg.albumTitle;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final targetName = widget.target == 'chat'
        ? loc('Sohbet Arka Planı', 'Chat Background')
        : (widget.target == 'profile'
            ? loc('Profil Fotoğrafı', 'Profile Photo')
            : loc('Widget Arka Planı', 'Widget Background'));

    final isProfileTarget = widget.target == 'profile';

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark ? LoveraColors.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Tutamaç & Başlık
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: LoveraColors.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.photo_library_rounded, color: LoveraColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc('Anı Albümünden Seç', 'Choose from Memory Album'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      Text(
                        targetName,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          if (isProfileTarget)
            Expanded(
              child: _buildSinglePhotoTab(isDark),
            )
          else ...[
            // Sekmeler: 1. Tek Fotoğraf | 2. Otomatik Döngü (Slideshow)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? LoveraColors.darkSurfaceAlt : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: LoveraColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: [
                  Tab(
                    icon: const Icon(Icons.image_outlined, size: 18),
                    text: loc('Tek Fotoğraf', 'Single Photo'),
                  ),
                  Tab(
                    icon: const Icon(Icons.autorenew_rounded, size: 18),
                    text: loc('Otomatik Döngü', 'Slideshow'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Sekme İçerikleri
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // 1. Sekme: Tek Fotoğraf Seçimi
                  _buildSinglePhotoTab(isDark),

                  // 2. Sekme: Otomatik Döngü (Klasör / Tüm Albüm)
                  _buildSlideshowTab(isDark),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // TEK FOTOĞRAF SEÇİM SEKME GÖRÜNÜMÜ
  Widget _buildSinglePhotoTab(bool isDark) {
    return StreamBuilder<List<MemoryItem>>(
      stream: DatabaseService().memoriesStream(widget.coupleId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final memories = snapshot.data ?? [];
        if (memories.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_library_outlined, size: 54, color: LoveraColors.primary.withOpacity(0.5)),
                  const SizedBox(height: 12),
                  Text(
                    loc('Henüz kaydedilmiş anı fotoğrafı yok', 'No memories recorded yet'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    loc('Anı albümüne fotoğraf ekledikten sonra buradan seçebilirsiniz.', 'Add photos to memory album to select here.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted),
                  ),
                ],
              ),
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: memories.length,
          itemBuilder: (context, index) {
            final item = memories[index];
            final imageProvider = AvatarCache.getProvider(item.imageUrl);

            return InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                widget.onSingleImageSelected(item.imageUrl);
              },
              borderRadius: BorderRadius.circular(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageProvider != null)
                      Image(image: imageProvider, fit: BoxFit.cover)
                    else
                      Container(color: Colors.grey.shade300),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                          ),
                        ),
                        child: Text(
                          item.caption.isNotEmpty ? item.caption : '${item.date.day}.${item.date.month}.${item.date.year}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // OTOMATİK DÖNGÜ (SLIDESHOW) SEKME GÖRÜNÜMÜ
  Widget _buildSlideshowTab(bool isDark) {
    return StreamBuilder<List<MemoryItem>>(
      stream: DatabaseService().memoriesStream(widget.coupleId),
      builder: (context, memSnap) {
        final memories = memSnap.data ?? [];

        return StreamBuilder<List<MemoryAlbum>>(
          stream: DatabaseService().albumsStream(widget.coupleId),
          builder: (context, albumSnap) {
            final albums = albumSnap.data ?? [];

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bilgilendirme Kartı
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: LoveraColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: LoveraColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.auto_mode_rounded, color: LoveraColors.primary, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            loc(
                              'Seçtiğiniz albümdeki fotoğraflar belirlediğiniz aralıklarla otomatik olarak arka planda sırayla değişir.',
                              'Photos in the selected album will automatically rotate in the background at your set interval.',
                            ),
                            style: const TextStyle(fontSize: 12.5, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 1. Kaynak Seçimi (Tüm Albüm mü, Belirli Bir Klasör mü?)
                  Text(
                    loc('1. Fotoğraf Kaynağı', '1. Photo Source'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),

                  // Tüm Albüm Seçeneği
                  _buildSourceTile(
                    title: loc('Tüm Anı Albümü 🌟', 'All Memories Album 🌟'),
                    subtitle: loc('${memories.length} fotoğraf döngüye dahil edilecek', '${memories.length} photos will be rotated'),
                    isSelected: _selectedSource == 'all',
                    onTap: () {
                      setState(() {
                        _selectedSource = 'all';
                        _selectedAlbumTitle = loc('Tüm Anılar', 'All Memories');
                      });
                    },
                    isDark: isDark,
                  ),

                  // Mevcut Albümler / Klasörler
                  if (albums.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      loc('Veya Belirli Bir Klasör:', 'Or a Specific Folder:'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...albums.map((alb) {
                      final albMemoriesCount = memories.where((m) => m.albumId == alb.id).length;
                      final isSelected = _selectedSource == 'album:${alb.id}';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildSourceTile(
                          title: alb.title,
                          subtitle: loc('$albMemoriesCount fotoğraf', '$albMemoriesCount photos'),
                          isSelected: isSelected,
                          onTap: () {
                            setState(() {
                              _selectedSource = 'album:${alb.id}';
                              _selectedAlbumTitle = alb.title;
                            });
                          },
                          isDark: isDark,
                        ),
                      );
                    }),
                  ],

                  const SizedBox(height: 20),

                  // 2. Değişim Sıklığı / Aralığı
                  Text(
                    loc('2. Değişim Aralığı', '2. Rotation Interval'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _intervals.map((item) {
                      final isSelected = _selectedIntervalSeconds == item['seconds'];
                      return ChoiceChip(
                        label: Text(item['label'] as String),
                        selected: isSelected,
                        selectedColor: LoveraColors.primary,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedIntervalSeconds = item['seconds'] as int;
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 28),

                  // Başlat Butonu
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: memories.isEmpty
                          ? null
                          : () async {
                              HapticFeedback.mediumImpact();
                              final config = SlideshowConfig(
                                isEnabled: true,
                                source: _selectedSource,
                                albumTitle: _selectedAlbumTitle.isEmpty ? loc('Tüm Anılar', 'All Memories') : _selectedAlbumTitle,
                                intervalSeconds: _selectedIntervalSeconds,
                                currentIndex: 0,
                                lastRotatedAt: DateTime.now().millisecondsSinceEpoch,
                              );

                              await BackgroundSlideshowService().saveConfig(widget.target, config);

                              if (widget.onSlideshowConfigured != null) {
                                widget.onSlideshowConfigured!(config);
                              }

                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(loc('Otomatik arka plan döngüsü başlatıldı! 🔄✨', 'Automatic background slideshow started! 🔄✨')),
                                    backgroundColor: LoveraColors.secondary,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: LoveraColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: Text(
                        loc('Otomatik Döngüyü Başlat 🚀', 'Start Automatic Slideshow 🚀'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSourceTile({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? LoveraColors.primary.withValues(alpha: 0.12)
              : (isDark ? LoveraColors.darkSurfaceAlt : Colors.grey.shade50),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? LoveraColors.primary : (isDark ? Colors.white12 : Colors.grey.shade200),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: isSelected ? LoveraColors.primary : Colors.grey,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      fontSize: 14,
                      color: isSelected ? LoveraColors.primary : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
