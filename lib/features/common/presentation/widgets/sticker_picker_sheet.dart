import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
      imageQuality: 95,
      maxWidth: 1024,
      maxHeight: 1024,
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
        _tabController.animateTo(1);
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

  // Fotoğraftan Çıkartma Üret / Metin Ekle Dialogu
  Future<void> _openPhotoStickerEditor() async {
    HapticFeedback.lightImpact();
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
      maxWidth: 1024,
      maxHeight: 1024,
    );

    if (picked == null || !mounted) return;

    final imageFile = File(picked.path);
    final GlobalKey previewKey = GlobalKey();
    final textController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color textColor = Colors.white;
    Color textBgColor = Colors.black.withValues(alpha: 0.6);
    double fontSize = 18;
    bool hasTextBg = true;
    bool isSavingSticker = false;

    final colorOptions = [
      Colors.white,
      Colors.black,
      LoveraColors.primary,
      const Color(0xFFFACC15), // Sarı
      const Color(0xFF4ADE80), // Yeşil
      const Color(0xFF38BDF8), // Mavi
      const Color(0xFFF43F5E), // Kırmızı/Pembe
    ];

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E212E) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: LoveraColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.auto_awesome_rounded, color: LoveraColors.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    loc('Fotoğraftan Çıkartma Yap', 'Make Photo Sticker'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    // Çıkartma Önizleme & Render Kutusu
                    Center(
                      child: RepaintBoundary(
                        key: previewKey,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Image.file(
                                imageFile,
                                width: 220,
                                height: 220,
                                fit: BoxFit.cover,
                              ),
                              if (textController.text.trim().isNotEmpty)
                                Positioned(
                                  bottom: 16,
                                  left: 12,
                                  right: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: hasTextBg ? textBgColor : Colors.transparent,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: hasTextBg
                                          ? [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.3),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Text(
                                      textController.text.trim(),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: fontSize,
                                        fontWeight: FontWeight.w900,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black.withValues(alpha: 0.8),
                                            blurRadius: 6,
                                            offset: const Offset(1, 1),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Metin Girişi
                    TextField(
                      controller: textController,
                      maxLength: 35,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        hintText: loc('Çıkartmaya yazı ekle (örn: Çok Özledim!)', 'Add text (e.g. Miss you so much!)'),
                        hintStyle: TextStyle(fontSize: 12, color: LoveraColors.textMuted),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        isDense: true,
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Yazı Rengi Seçici
                    Row(
                      children: [
                        Text(loc('Yazı Rengi:', 'Text Color:'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        InkWell(
                          onTap: () => setDialogState(() => hasTextBg = !hasTextBg),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: hasTextBg ? LoveraColors.primary.withValues(alpha: 0.2) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: hasTextBg ? LoveraColors.primary : Colors.grey.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.format_color_fill_rounded, size: 14, color: hasTextBg ? LoveraColors.primary : Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  loc('Arka Plan', 'Background'),
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: hasTextBg ? LoveraColors.primary : Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    SizedBox(
                      height: 36,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: colorOptions.map((c) {
                            final isSel = textColor == c;
                            return GestureDetector(
                              onTap: () => setDialogState(() => textColor = c),
                              child: Container(
                                margin: const EdgeInsets.only(right: 8),
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSel ? LoveraColors.primary : Colors.grey.shade400,
                                    width: isSel ? 3 : 1.5,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              actions: [
                TextButton(
                  onPressed: isSavingSticker ? null : () => Navigator.pop(dCtx),
                  child: Text(loc('Vazgeç', 'Cancel')),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: LoveraColors.primary),
                  onPressed: isSavingSticker
                      ? null
                      : () async {
                          setDialogState(() => isSavingSticker = true);
                          try {
                            await WidgetsBinding.instance.endOfFrame;
                            final boundary = previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
                            if (boundary == null) return;

                            final uiImage = await boundary.toImage(pixelRatio: 2.5);
                            final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
                            if (byteData == null) return;

                            final pngBytes = byteData.buffer.asUint8List();
                            final base64Str = 'data:image/png;base64,${base64Encode(pngBytes)}';
                            final myName = ref.read(userNameProvider);

                            // Firestore özel çıkartmalara ekle
                            await StickerService().addCustomSticker(
                              coupleId: widget.coupleId,
                              imageBase64: base64Str,
                              title: textController.text.trim().isNotEmpty ? textController.text.trim() : 'Özel Foto Çıkartma',
                              createdBy: myName.isNotEmpty ? myName : 'Ben',
                            );

                            if (dCtx.mounted) Navigator.pop(dCtx);
                            if (mounted) {
                              _tabController.animateTo(1);
                              Navigator.pop(context); // Sheet'i kapat
                              widget.onStickerSelected(base64Str, isEmoji: false);
                            }
                          } catch (e) {
                            debugPrint('[StickerStudio] Hata: $e');
                          } finally {
                            if (dCtx.mounted) setDialogState(() => isSavingSticker = false);
                          }
                        },
                  icon: isSavingSticker
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, size: 16),
                  label: Text(loc('Kaydet & Gönder 🚀', 'Save & Send 🚀')),
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

                      // Fotoğraftan Çıkartma Üret Butonu
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          side: BorderSide(color: LoveraColors.primary.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _openPhotoStickerEditor,
                        icon: Icon(Icons.auto_awesome_rounded, size: 16, color: LoveraColors.primary),
                        label: Text(
                          loc('Fotoğraftan Üret ✨', 'From Photo ✨'),
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
