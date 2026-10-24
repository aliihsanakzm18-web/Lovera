import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/services/sticker_service.dart';
import '../../../../core/state/app_state.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/avatar_cache.dart';
import '../../../../core/widgets/lovera_theme_background.dart';

/// Hem mesajlaşma hem de widget tuvali için ortak Çıkartma Seçim & Üretim Modalı
class StickerPickerSheet extends ConsumerStatefulWidget {
  final String coupleId;
  final void Function(String stickerContent, {required bool isEmoji}) onStickerSelected;

  const StickerPickerSheet({
    super.key,
    required this.coupleId,
    required this.onStickerSelected,
  });

  static Future<void> show({
    required BuildContext context,
    required String coupleId,
    required void Function(String stickerContent, {required bool isEmoji}) onStickerSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StickerPickerSheet(
        coupleId: coupleId,
        onStickerSelected: onStickerSelected,
      ),
    );
  }

  @override
  ConsumerState<StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends ConsumerState<StickerPickerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Cihazdan Çıkartma Ekle
  Future<void> _pickStickerFromGallery() async {
    HapticFeedback.lightImpact();
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
      maxWidth: 400,
      maxHeight: 400,
    );

    if (picked == null) return;

    try {
      setState(() => _isUploading = true);
      final bytes = await File(picked.path).readAsBytes();
      final base64Str = 'data:image/png;base64,${base64Encode(bytes)}';
      final myName = ref.read(userNameProvider);

      await StickerService().addCustomSticker(
        coupleId: widget.coupleId,
        imageBase64: base64Str,
        title: 'Özel Çıkartma',
        createdBy: myName.isNotEmpty ? myName : 'Ben',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc('Çıkartma koleksiyonuna eklendi! ✨', 'Sticker added to collection! ✨')),
            backgroundColor: LoveraColors.secondary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc('Çıkartma eklenirken hata: $e', 'Error adding sticker: $e')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // Çıkartma Üret / Oluştur Dialogu
  void _openStickerStudioDialog() {
    HapticFeedback.lightImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textController = TextEditingController();
    String selectedEmoji = '💖';
    Color stickerBgColor = LoveraColors.primary;

    final emojiList = ['💖', '🧸', '🥰', '😘', '💍', '💌', '🌸', '🐰', '✨', '🔥', '👑', '🐣'];
    final colorList = [
      LoveraColors.primary,
      const Color(0xFFEC4899),
      const Color(0xFF8B5CF6),
      const Color(0xFFF59E0B),
      const Color(0xFF10B981),
      const Color(0xFF3B82F6),
      const Color(0xFF1E293B),
    ];

    showDialog<void>(
      context: context,
      builder: (dCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? LoveraColors.darkSurfaceAlt : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: LoveraColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Text('🎨', style: TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    loc('Çıkartma Üret', 'Create Sticker'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Canlı Önizleme Kartı
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: stickerBgColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: stickerBgColor, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: stickerBgColor.withValues(alpha: 0.25),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(selectedEmoji, style: const TextStyle(fontSize: 44)),
                          if (textController.text.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Text(
                                textController.text.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Metin Girişi
                    TextField(
                      controller: textController,
                      maxLength: 15,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        hintText: loc('Çıkartma yazısı (örn: Seni Seviyorum)', 'Sticker text (e.g. Love You)'),
                        hintStyle: TextStyle(fontSize: 12, color: LoveraColors.textMuted),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Emoji Seçici
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(loc('İkon Seç:', 'Choose Icon:'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: emojiList.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final em = emojiList[i];
                          final isSel = selectedEmoji == em;
                          return GestureDetector(
                            onTap: () => setDialogState(() => selectedEmoji = em),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSel ? LoveraColors.primary.withValues(alpha: 0.2) : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isSel ? LoveraColors.primary : Colors.grey.withValues(alpha: 0.3)),
                              ),
                              child: Center(child: Text(em, style: const TextStyle(fontSize: 20))),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Renk Seçici
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(loc('Tema Rengi:', 'Theme Color:'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 34,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: colorList.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final col = colorList[i];
                          final isSel = stickerBgColor == col;
                          return GestureDetector(
                            onTap: () => setDialogState(() => stickerBgColor = col),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: col,
                                shape: BoxShape.circle,
                                border: Border.all(color: isSel ? Colors.white : Colors.transparent, width: 2.5),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dCtx),
                  child: Text(loc('Vazgeç', 'Cancel')),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: LoveraColors.primary),
                  onPressed: () {
                    Navigator.pop(dCtx);
                    Navigator.pop(context); // Sheet'i kapat
                    final fullText = textController.text.trim();
                    final stickerContent = fullText.isNotEmpty ? '$selectedEmoji $fullText' : selectedEmoji;
                    widget.onStickerSelected(stickerContent, isEmoji: true);
                  },
                  child: Text(loc('Kullan ve Gönder 🚀', 'Use & Send 🚀')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.70,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0D0E15) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Stack(
          children: [
            // Lovera Aurora Teması
            const Positioned.fill(
              child: LoveraThemeBackground(),
            ),

            Column(
              children: [
                // Tutamaç
                const SizedBox(height: 12),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 12),

                // Başlık & Hızlı Eylemler (Cihazdan Ekle & Çıkartma Üret)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: LoveraColors.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Text('🏷️', style: TextStyle(fontSize: 20)),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        loc('Çıkartmalar', 'Stickers'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      const Spacer(),

                      // Çıkartma Üret Butonu
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          side: BorderSide(color: LoveraColors.primary.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _openStickerStudioDialog,
                        icon: Icon(Icons.auto_awesome_rounded, size: 16, color: LoveraColors.primary),
                        label: Text(
                          loc('Üret ✨', 'Create ✨'),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: LoveraColors.primary),
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Cihazdan Ekle Butonu
                      IconButton(
                        tooltip: loc('Cihazdan Çıkartma Ekle', 'Add Sticker from Device'),
                        onPressed: _isUploading ? null : _pickStickerFromGallery,
                        icon: _isUploading
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(Icons.add_photo_alternate_rounded, color: LoveraColors.primary),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Sekmeler: 1. Hazır Çıkartmalar | 2. Özel Koleksiyon
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
                      Tab(text: loc('Hazır Çıkartmalar 💖', 'Default Stickers 💖')),
                      Tab(text: loc('Özel Çıkartmalar ⭐', 'Custom Stickers ⭐')),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Sekme İçerikleri
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // 1. Hazır Romantik Çıkartmalar
                      _buildDefaultStickersGrid(),

                      // 2. Özel Çıkartmalar (Cihazdan eklenenler)
                      _buildCustomStickersGrid(isDark),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // HAZIR ÇIKARTMALAR GRID
  Widget _buildDefaultStickersGrid() {
    final stickers = StickerService.defaultRomanticStickers;

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: stickers.length,
      itemBuilder: (context, index) {
        final st = stickers[index];
        return InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
            widget.onStickerSelected(st, isEmoji: true);
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Center(
              child: Text(st, style: const TextStyle(fontSize: 38)),
            ),
          ),
        );
      },
    );
  }

  // ÖZEL ÇIKARTMALAR GRID (CİHAZDAN EKLENENLER)
  Widget _buildCustomStickersGrid(bool isDark) {
    return StreamBuilder<List<CustomSticker>>(
      stream: StickerService().customStickersStream(widget.coupleId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snapshot.data ?? [];
        if (list.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.stars_rounded, size: 54, color: LoveraColors.primary.withValues(alpha: 0.4)),
                  const SizedBox(height: 12),
                  Text(
                    loc('Henüz özel çıkartma eklenmemiş', 'No custom stickers yet'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    loc('Yukarıdaki "+" butonuna basarak galerinizden şeffaf/özel çıkartmalar ekleyebilirsiniz.', 'Tap "+" above to add custom stickers from your gallery.'),
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
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: list.length,
          itemBuilder: (context, index) {
            final st = list[index];
            final imageProvider = AvatarCache.getProvider(st.imageUrl);

            return InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                widget.onStickerSelected(st.imageUrl, isEmoji: false);
              },
              borderRadius: BorderRadius.circular(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: imageProvider != null
                      ? Image(image: imageProvider, fit: BoxFit.contain)
                      : const Center(child: Icon(Icons.image)),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
