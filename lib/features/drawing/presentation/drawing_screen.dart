import '../../../core/localization/app_strings.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/models/models.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/widget_sync_service.dart';
import '../../common/presentation/widgets/sticker_picker_sheet.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';

/// Serbest Çizim Noktası
class DrawingPoint {
  final Offset offset;
  final Paint paint;
  final bool isEraser;

  DrawingPoint({
    required this.offset,
    required this.paint,
    this.isEraser = false,
  });
}

/// Çizim Tuvaline Eklenen Metin Öğesi
class TextItem {
  String text;
  Offset offset;
  Color color;
  double fontSize;

  TextItem({
    required this.text,
    required this.offset,
    required this.color,
    this.fontSize = 24.0,
  });
}

/// Çizim Tuvaline Eklenen Çıkartma Öğesi
class StickerCanvasItem {
  final String id;
  Offset offset;
  final String content;
  final bool isEmoji;
  double size;

  StickerCanvasItem({
    required this.id,
    required this.offset,
    required this.content,
    required this.isEmoji,
    this.size = 72.0,
  });
}

class DrawingScreen extends ConsumerStatefulWidget {
  const DrawingScreen({super.key});

  @override
  ConsumerState<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends ConsumerState<DrawingScreen> {
  final GlobalKey _globalKey = GlobalKey();
  final List<List<DrawingPoint>> _lines = [];
  List<DrawingPoint> _currentLine = [];
  final List<TextItem> _texts = [];
  int? _selectedTextIndex;
  final List<StickerCanvasItem> _stickers = [];
  int? _selectedStickerIndex;

  // Çizim Araçları
  Color _selectedColor = LoveraColors.primaryDark;
  double _strokeWidth = 5.0;
  double _fontSize = 24.0;
  bool _isEraser = false;
  bool _isTextMode = false;
  bool _isSending = false;
  bool _isExporting = false;

  final List<Color> _palette = [
    LoveraColors.primaryDark, // Lovera Moru
    Color(0xFFEC4899), // Romantik Pembe
    Color(0xFFEF4444), // Kırmızı / Kalp
    Color(0xFFF59E0B), // Sıcak Turuncu / Sarı
    Color(0xFF10B981), // Canlı Yeşil
    Color(0xFF3B82F6), // Gökyüzü Mavisi
    Color(0xFFFFFFFF), // Beyaz
    Color(0xFF1E293B), // Koyu Mürekkep
  ];

  void _undo() {
    HapticFeedback.lightImpact();
    setState(() {
      if (_stickers.isNotEmpty) {
        _stickers.removeLast();
        _selectedStickerIndex = null;
      } else if (_texts.isNotEmpty) {
        _texts.removeLast();
        _selectedTextIndex = null;
      } else if (_lines.isNotEmpty) {
        _lines.removeLast();
      }
    });
  }

  void _clearCanvas() {
    if (_lines.isNotEmpty || _currentLine.isNotEmpty || _texts.isNotEmpty || _stickers.isNotEmpty) {
      HapticFeedback.mediumImpact();
      setState(() {
        _lines.clear();
        _currentLine.clear();
        _texts.clear();
        _selectedTextIndex = null;
        _stickers.clear();
        _selectedStickerIndex = null;
      });
    }
  }

  void _showAddTextDialog({Offset? defaultPosition, int? editIndex}) {
    final isEditing = editIndex != null && editIndex < _texts.length;
    final initialText = isEditing ? _texts[editIndex].text : '';
    final controller = TextEditingController(text: initialText);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1938) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Text(isEditing ? '✏️ ' : '✍️ ', style: const TextStyle(fontSize: 20)),
              Text(
                isEditing ? ref.read(stringsProvider).editTextTitle : ref.read(stringsProvider).addTextTitle,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1E1B4B),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (isEditing)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  tooltip: ref.read(stringsProvider).delete,
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    setState(() {
                      _texts.removeAt(editIndex);
                      _selectedTextIndex = null;
                    });
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(
              color: isEditing ? _texts[editIndex].color : _selectedColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              hintText: ref.read(stringsProvider).textHint,
              hintStyle: TextStyle(
                color: isDark ? Colors.white.withValues(alpha: 0.4) : LoveraColors.darkTextMuted,
                fontSize: 15,
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF161426) : const Color(0xFFF1F5F9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                ref.read(stringsProvider).cancel,
                style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF64748B)),
              ),
            ),
            FilledButton(
              onPressed: () {
                final txt = controller.text.trim();
                if (txt.isNotEmpty) {
                  setState(() {
                    if (isEditing) {
                      _texts[editIndex].text = txt;
                      _texts[editIndex].color = _selectedColor;
                      _texts[editIndex].fontSize = _fontSize;
                    } else {
                      _texts.add(TextItem(
                        text: txt,
                        offset: defaultPosition ?? const Offset(60, 140),
                        color: _selectedColor,
                        fontSize: _fontSize,
                      ));
                    }
                  });
                }
                Navigator.pop(ctx);
              },
              style: FilledButton.styleFrom(
                backgroundColor: LoveraColors.primaryDark,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(isEditing ? ref.read(stringsProvider).update : ref.read(stringsProvider).add, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendDrawing() async {
    if (_lines.isEmpty && _currentLine.isEmpty && _texts.isEmpty && _stickers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ref.read(stringsProvider).drawSomethingFirst),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final coupleId = ref.read(coupleIdProvider);
    final partnerUid = ref.read(partnerUidProvider);
    final rawUserName = ref.read(userNameProvider);
    final firstOnly = formatFirstNameOnly(rawUserName);
    final myName = firstOnly.isNotEmpty
        ? firstOnly
        : (rawUserName.isNotEmpty ? rawUserName : loc('Partnerin', 'Partner'));

    if (coupleId == null || coupleId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ref.read(stringsProvider).pairToDrawWarning),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isSending = true;
      _isExporting = true;
      _selectedTextIndex = null;
      _selectedStickerIndex = null;
    });
    HapticFeedback.mediumImpact();

    try {
      // Çerçevenin transparan arka plan ve seçim kutucuksuz çizildiğinden emin olmak için bir frame bekle
      await WidgetsBinding.instance.endOfFrame;

      // 1. RepaintBoundary'den yüksek kaliteli şeffaf PNG üret
      final boundary = _globalKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception(loc('Canvas render hatası', 'Canvas render error'));
      }

      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception(loc('Görsel dönüştürülemedi', 'Failed to convert image'));
      }

      final bytes = byteData.buffer.asUint8List();
      final base64Image = base64Encode(bytes);

      // 2. Kendi cihazımızın widget'ına da kaydedelim (yerel dosya)
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final localPath = '${appDir.path}/latest_drawing.png';
        final f = File(localPath);
        await f.writeAsBytes(bytes);
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        await WidgetSyncService.syncDrawingWidget(
          imagePath: localPath,
          imageBase64: base64Image,
          senderName: loc('Sen', 'You'),
          timeAgo: loc('Şimdi', 'Just now'),
          timestampMillis: nowMs,
        );
      } catch (e) {
        debugPrint('[DrawingScreen] Yerel widget yazma hatası: $e');
      }

      // 3. Firestore üzerinden çiftin son çizimine yaz
      await DatabaseService().sendDrawing(
        coupleId: coupleId,
        imageBase64: base64Image,
        senderName: myName,
      );

      // 4. Çizimi otomatik olarak sohbete özel 'drawing' tipiyle gönder
      try {
        await DatabaseService().sendMessage(
          coupleId: coupleId,
          text: '',
          mediaBase64: 'data:image/png;base64,$base64Image',
          type: 'drawing',
        );
      } catch (e) {
        debugPrint('[DrawingScreen] Çizimi sohbete ekleme hatası: $e');
      }

      // 5. Partnere anında Push Bildirimi yolla (Partnere widget'ı anında güncellensin!)
      if (partnerUid != null && partnerUid.isNotEmpty) {
        final cleanMyName = AppUser.extractFirstName(myName);
        NotificationService().sendPushToPartner(
          partnerUid: partnerUid,
          title: loc('🎨 $cleanMyName sana bir çizim gönderdi!', '🎨 $cleanMyName sent you a drawing!'),
          body: loc('Ana ekranındaki Lovera Çizim Widget\'ına bak 💕', 'Check the Lovera Drawing Widget on your home screen 💕'),
          titleTr: '🎨 $cleanMyName sana bir çizim gönderdi!',
          titleEn: '🎨 $cleanMyName sent you a drawing!',
          bodyTr: 'Ana ekranındaki Lovera Çizim Widget\'ına bak 💕',
          bodyEn: 'Check the Lovera Drawing Widget on your home screen 💕',
          data: {
            'type': 'drawing_sent',
            'coupleId': coupleId,
            'senderName': cleanMyName,
            'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
          },
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ref.read(stringsProvider).drawingSentSuccess),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc('Çizim gönderilemedi: $e', 'Could not send drawing: $e')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _isExporting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final canUndo = _stickers.isNotEmpty || _texts.isNotEmpty || _lines.isNotEmpty;
    final canClear = _stickers.isNotEmpty || _texts.isNotEmpty || _lines.isNotEmpty || _currentLine.isNotEmpty;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0C1B) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(ref.watch(stringsProvider).drawingTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.undo_rounded),
            tooltip: ref.watch(stringsProvider).isEn ? 'Undo' : 'Geri Al',
            onPressed: canUndo ? _undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: ref.watch(stringsProvider).clearCanvas,
            onPressed: canClear ? _clearCanvas : null,
          ),
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: ref.watch(stringsProvider).reportDrawing,
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (dCtx) => AlertDialog(
                  title: Text(ref.watch(stringsProvider).reportDrawing),
                  content: Text(ref.watch(stringsProvider).reportDrawingDesc),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dCtx, false),
                      child: Text(ref.watch(stringsProvider).cancel),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                      onPressed: () => Navigator.pop(dCtx, true),
                      child: Text(loc('Şikayet Et', 'Report')),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                final coupleId = ref.read(coupleIdProvider);
                final partnerUid = ref.read(partnerUidProvider);
                await DatabaseService().reportContent(
                  contentType: 'drawing',
                  contentId: coupleId ?? 'shared_canvas',
                  coupleId: coupleId,
                  reportedUserId: partnerUid,
                  reason: loc('Ortak çizim tuvali üzerinden uygunsuz içerik bildirimi', 'Inappropriate content report from shared canvas'),
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ref.read(stringsProvider).reportSubmittedMsg),
                    ),
                  );
                }
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Üst Bilgi Rozeti
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? LoveraColors.darkSurface.withValues(alpha: 0.82) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: LoveraColors.primaryDark.withValues(alpha: 0.33), width: 1.2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('✨', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        ref.watch(stringsProvider).drawingTip,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Çizim Alanı (Kare Canvas)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF161426) : Colors.white,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: LoveraColors.primaryDark.withValues(alpha: 0.33), width: 1.8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: RepaintBoundary(
                          key: _globalKey,
                          child: Stack(
                            children: [
                              GestureDetector(
                                onTapDown: (details) {
                                  final pos = details.localPosition;

                                  // 1. Önce çıkartmalara tıklanıp tıklanmadığını kontrol et (en üsttekiden başlayarak)
                                  for (int i = _stickers.length - 1; i >= 0; i--) {
                                    final sticker = _stickers[i];
                                    final rect = Rect.fromLTWH(sticker.offset.dx, sticker.offset.dy, sticker.size + 16, sticker.size + 16);
                                    if (rect.contains(pos)) {
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        _selectedStickerIndex = i;
                                        _selectedTextIndex = null;
                                        _isTextMode = false;
                                      });
                                      return;
                                    }
                                  }

                                  // 2. Metinlere tıklanıp tıklanmadığını kontrol et
                                  for (int i = _texts.length - 1; i >= 0; i--) {
                                    final item = _texts[i];
                                    final estimatedW = (item.text.length * (item.fontSize * 0.62)).clamp(60.0, 320.0);
                                    final estimatedH = item.fontSize * 1.5;
                                    final rect = Rect.fromLTWH(item.offset.dx - 12, item.offset.dy - 10, estimatedW + 24, estimatedH + 20);
                                    if (rect.contains(pos)) {
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        _selectedTextIndex = i;
                                        _selectedStickerIndex = null;
                                        _isTextMode = true;
                                        _fontSize = item.fontSize;
                                        _selectedColor = item.color;
                                      });
                                      return;
                                    }
                                  }

                                  // Boş alana dokunulduğunda seçimleri temizle veya yazı ekleme dialogunu aç
                                  if (_selectedTextIndex != null || _selectedStickerIndex != null) {
                                    setState(() {
                                      _selectedTextIndex = null;
                                      _selectedStickerIndex = null;
                                    });
                                  } else if (_isTextMode) {
                                    _showAddTextDialog(defaultPosition: pos);
                                  }
                                },
                                onPanStart: (details) {
                                  final pos = details.localPosition;

                                  // Çıkartmaya denk geldiyse çizgi başlatma, o çıkartmayı seç
                                  for (int i = _stickers.length - 1; i >= 0; i--) {
                                    final sticker = _stickers[i];
                                    final rect = Rect.fromLTWH(sticker.offset.dx, sticker.offset.dy, sticker.size + 16, sticker.size + 16);
                                    if (rect.contains(pos)) {
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        _selectedStickerIndex = i;
                                        _selectedTextIndex = null;
                                        _isTextMode = false;
                                      });
                                      return;
                                    }
                                  }

                                  // Metne denk geldiyse çizgi başlatma, o metni seç
                                  for (int i = _texts.length - 1; i >= 0; i--) {
                                    final item = _texts[i];
                                    final estimatedW = (item.text.length * (item.fontSize * 0.62)).clamp(60.0, 320.0);
                                    final estimatedH = item.fontSize * 1.5;
                                    final rect = Rect.fromLTWH(item.offset.dx - 12, item.offset.dy - 10, estimatedW + 24, estimatedH + 20);
                                    if (rect.contains(pos)) {
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        _selectedTextIndex = i;
                                        _selectedStickerIndex = null;
                                        _isTextMode = true;
                                        _fontSize = item.fontSize;
                                        _selectedColor = item.color;
                                      });
                                      return;
                                    }
                                  }

                                  if (_isTextMode) return;

                                  setState(() {
                                    _selectedTextIndex = null;
                                    _selectedStickerIndex = null;
                                  });
                                  HapticFeedback.selectionClick();
                                  final paint = Paint()
                                    ..color = _isEraser
                                        ? Colors.transparent
                                        : _selectedColor
                                    ..strokeCap = StrokeCap.round
                                    ..strokeWidth = _isEraser ? _strokeWidth * 2.2 : _strokeWidth
                                    ..blendMode = _isEraser ? BlendMode.clear : BlendMode.srcOver;
                                  setState(() {
                                    _currentLine = [DrawingPoint(offset: pos, paint: paint, isEraser: _isEraser)];
                                  });
                                },
                                onPanUpdate: (details) {
                                  if (_selectedStickerIndex != null && _selectedStickerIndex! < _stickers.length) {
                                    setState(() {
                                      final item = _stickers[_selectedStickerIndex!];
                                      final newX = (item.offset.dx + details.delta.dx).clamp(0.0, 320.0 - item.size);
                                      final newY = (item.offset.dy + details.delta.dy).clamp(0.0, 320.0 - item.size);
                                      item.offset = Offset(newX, newY);
                                    });
                                    return;
                                  }
                                  if (_selectedTextIndex != null && _selectedTextIndex! < _texts.length) {
                                    setState(() {
                                      final item = _texts[_selectedTextIndex!];
                                      final newX = (item.offset.dx + details.delta.dx).clamp(0.0, 280.0);
                                      final newY = (item.offset.dy + details.delta.dy).clamp(0.0, 320.0);
                                      item.offset = Offset(newX, newY);
                                    });
                                    return;
                                  }
                                  if (_isTextMode) return;

                                  final offset = details.localPosition;
                                  final paint = Paint()
                                    ..color = _isEraser
                                        ? Colors.transparent
                                        : _selectedColor
                                    ..strokeCap = StrokeCap.round
                                    ..strokeWidth = _isEraser ? _strokeWidth * 2.2 : _strokeWidth
                                    ..blendMode = _isEraser ? BlendMode.clear : BlendMode.srcOver;
                                  setState(() {
                                    _currentLine.add(DrawingPoint(offset: offset, paint: paint, isEraser: _isEraser));
                                  });
                                },
                                onPanEnd: (details) {
                                  if (_isTextMode) return;

                                  setState(() {
                                    if (_currentLine.isNotEmpty) {
                                      _lines.add(List.from(_currentLine));
                                      _currentLine = [];
                                    }
                                  });
                                },
                                child: CustomPaint(
                                  painter: _DrawingCanvasPainter(
                                    lines: _lines,
                                    currentLine: _currentLine,
                                    texts: _texts,
                                    selectedIndex: _isSending ? null : _selectedTextIndex,
                                    backgroundColor: isDark ? const Color(0xFF161426) : const Color(0xFFFAF5FF),
                                    isDark: isDark,
                                    isExporting: _isExporting,
                                  ),
                                  size: Size.infinite,
                                ),
                              ),

                              // Seçili Metin İçin Hızlı İşlem Araç Çubuğu (Düzenle & Sil)
                              if (!_isSending && _selectedTextIndex != null && _selectedTextIndex! < _texts.length) ...[
                                Builder(
                                  builder: (context) {
                                    final selItem = _texts[_selectedTextIndex!];
                                    final topPos = (selItem.offset.dy - 44).clamp(8.0, 320.0);
                                    final leftPos = (selItem.offset.dx).clamp(8.0, 240.0);

                                    return Positioned(
                                      top: topPos,
                                      left: leftPos,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF1E1938) : Colors.white,
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: isDark ? LoveraColors.primaryDark : LoveraColors.primary,
                                            width: 1.2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.12),
                                              blurRadius: 10,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Düzenle Butonu
                                            GestureDetector(
                                              onTap: () {
                                                _showAddTextDialog(editIndex: _selectedTextIndex);
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.edit_rounded,
                                                      color: isDark ? Colors.white : const Color(0xFF1E1B4B),
                                                      size: 14,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      ref.watch(stringsProvider).edit,
                                                      style: TextStyle(
                                                        color: isDark ? Colors.white : const Color(0xFF1E1B4B),
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            Container(
                                              width: 1,
                                              height: 14,
                                              color: isDark ? Colors.white24 : Colors.black12,
                                            ),
                                            // Sil Butonu
                                            GestureDetector(
                                              onTap: () {
                                                HapticFeedback.mediumImpact();
                                                setState(() {
                                                  _texts.removeAt(_selectedTextIndex!);
                                                  _selectedTextIndex = null;
                                                });
                                              },
                                              child: Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 14),
                                                    SizedBox(width: 4),
                                                    Text(loc('Sil', 'Delete'), style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],

                              // Seçili Çıkartma İçin Hızlı İşlem Araç Çubuğu (Sil & Büyüt/Küçült)
                              if (!_isSending && _selectedStickerIndex != null && _selectedStickerIndex! < _stickers.length) ...[
                                Builder(
                                  builder: (context) {
                                    final selSticker = _stickers[_selectedStickerIndex!];
                                    final topPos = (selSticker.offset.dy - 44).clamp(8.0, 320.0);
                                    final leftPos = (selSticker.offset.dx).clamp(8.0, 240.0);

                                    return Positioned(
                                      top: topPos,
                                      left: leftPos,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF1E1938) : Colors.white,
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: isDark ? LoveraColors.primaryDark : LoveraColors.primary,
                                            width: 1.2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.12),
                                              blurRadius: 10,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Sil Butonu
                                            GestureDetector(
                                              onTap: () {
                                                HapticFeedback.mediumImpact();
                                                setState(() {
                                                  _stickers.removeAt(_selectedStickerIndex!);
                                                  _selectedStickerIndex = null;
                                                });
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 14),
                                                    const SizedBox(width: 4),
                                                    Text(loc('Sil', 'Delete'), style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],

                              // Tuvaldeki Çıkartmalar
                              for (int i = 0; i < _stickers.length; i++) ...[
                                Builder(
                                  builder: (context) {
                                    final sticker = _stickers[i];
                                    final isSelected = !_isSending && _selectedStickerIndex == i;
                                    return Positioned(
                                      left: sticker.offset.dx,
                                      top: sticker.offset.dy,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          setState(() {
                                            _selectedStickerIndex = i;
                                            _selectedTextIndex = null;
                                          });
                                        },
                                        onPanStart: (details) {
                                          HapticFeedback.selectionClick();
                                          setState(() {
                                            _selectedStickerIndex = i;
                                            _selectedTextIndex = null;
                                          });
                                        },
                                        onPanUpdate: (details) {
                                          setState(() {
                                            final newX = (sticker.offset.dx + details.delta.dx).clamp(0.0, 320.0 - sticker.size);
                                            final newY = (sticker.offset.dy + details.delta.dy).clamp(0.0, 320.0 - sticker.size);
                                            sticker.offset = Offset(newX, newY);
                                            _selectedStickerIndex = i;
                                            _selectedTextIndex = null;
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            border: isSelected
                                                ? Border.all(color: LoveraColors.primaryDark, width: 2)
                                                : null,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: sticker.isEmoji
                                              ? Text(
                                                  sticker.content,
                                                  style: TextStyle(fontSize: sticker.size * 0.7),
                                                )
                                              : (sticker.content.startsWith('data:image') || sticker.content.length > 200)
                                                  ? Image.memory(
                                                      base64Decode(
                                                        sticker.content.contains(',')
                                                            ? sticker.content.split(',').last
                                                            : sticker.content,
                                                      ),
                                                      width: sticker.size,
                                                      height: sticker.size,
                                                      fit: BoxFit.contain,
                                                      gaplessPlayback: true,
                                                    )
                                                  : Container(
                                                      width: sticker.size,
                                                      height: sticker.size,
                                                      color: Colors.grey,
                                                    ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Alt Kontrol Paneli: Renk Paleti, Fırça / Silgi ve Gönder Butonu
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF161426) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Renk Seçici & Silgi
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Silgi Aracı
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() {
                              _isEraser = true;
                              _isTextMode = false;
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _isEraser ? LoveraColors.primaryDark.withValues(alpha: 0.33) : Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _isEraser ? LoveraColors.primaryDark : Colors.grey.withValues(alpha: 0.3),
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.cleaning_services_rounded,
                              size: 22,
                              color: _isEraser ? LoveraColors.primaryDark : Colors.grey,
                            ),
                          ),
                        ),

                        // Yazı Ekleme / Yazı Modu Aracı
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() {
                              _isTextMode = !_isTextMode;
                              _isEraser = false;
                            });
                            if (_isTextMode) {
                              _showAddTextDialog();
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _isTextMode ? LoveraColors.primaryDark.withValues(alpha: 0.33) : Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _isTextMode ? LoveraColors.primaryDark : Colors.grey.withValues(alpha: 0.3),
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.title_rounded,
                              size: 22,
                              color: _isTextMode ? LoveraColors.primaryDark : Colors.grey,
                            ),
                          ),
                        ),

                        // Çıkartma (Sticker) Ekleme Aracı
                        GestureDetector(
                          onTap: () {
                            final coupleId = ref.read(coupleIdProvider);
                            if (coupleId == null || coupleId.isEmpty) return;
                            HapticFeedback.lightImpact();
                            StickerPickerSheet.show(
                              context: context,
                              coupleId: coupleId,
                              onStickerSelected: (content, {required bool isEmoji}) {
                                setState(() {
                                  _stickers.add(
                                    StickerCanvasItem(
                                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                                      offset: const Offset(120, 120),
                                      content: content,
                                      isEmoji: isEmoji,
                                    ),
                                  );
                                  _selectedStickerIndex = _stickers.length - 1;
                                  _selectedTextIndex = null;
                                });
                              },
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _selectedStickerIndex != null ? LoveraColors.primaryDark.withValues(alpha: 0.33) : Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _selectedStickerIndex != null ? LoveraColors.primaryDark : Colors.grey.withValues(alpha: 0.3),
                                width: 2,
                              ),
                            ),
                            child: const Text('🏷️', style: TextStyle(fontSize: 18)),
                          ),
                        ),

                        // Renkler
                        ..._palette.map((color) {
                          final isSelected = !_isEraser && _selectedColor == color;
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _selectedColor = color;
                                _isEraser = false;
                                if (_selectedTextIndex != null && _selectedTextIndex! < _texts.length) {
                                  _texts[_selectedTextIndex!].color = color;
                                }
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? (isDark ? Colors.white : LoveraColors.primaryDeep)
                                      : (isDark ? Colors.white24 : Colors.black26),
                                  width: isSelected ? 3.2 : 1.5,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: color.withValues(alpha: isDark ? 0.6 : 0.4),
                                          blurRadius: 8,
                                          spreadRadius: 1,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Fırça Kalınlığı, Metin Boyutu veya Çıkartma Boyutu Slider'ı
                  Row(
                    children: [
                      Icon(
                        _selectedStickerIndex != null
                            ? Icons.photo_size_select_large_rounded
                            : (_isTextMode ? Icons.format_size_rounded : Icons.brush_rounded),
                        size: 20,
                        color: (_selectedStickerIndex != null || _isTextMode) ? LoveraColors.primaryDark : LoveraColors.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: LoveraColors.primaryDark,
                            thumbColor: LoveraColors.primaryDark,
                            overlayColor: LoveraColors.primaryDark.withValues(alpha: 0.2),
                            trackHeight: 3.5,
                          ),
                          child: _selectedStickerIndex != null && _selectedStickerIndex! < _stickers.length
                              ? Slider(
                                  value: _stickers[_selectedStickerIndex!].size,
                                  min: 36.0,
                                  max: 180.0,
                                  onChanged: (val) {
                                    setState(() {
                                      _stickers[_selectedStickerIndex!].size = val;
                                    });
                                  },
                                )
                              : (_isTextMode
                                  ? Slider(
                                      value: _fontSize,
                                      min: 12.0,
                                      max: 48.0,
                                      onChanged: (val) {
                                        setState(() {
                                          _fontSize = val;
                                          if (_selectedTextIndex != null && _selectedTextIndex! < _texts.length) {
                                            _texts[_selectedTextIndex!].fontSize = val;
                                          }
                                        });
                                      },
                                    )
                                  : Slider(
                                      value: _strokeWidth,
                                      min: 2.0,
                                      max: 18.0,
                                      onChanged: (val) => setState(() => _strokeWidth = val),
                                    )),
                        ),
                      ),
                      Container(
                        width: 40,
                        alignment: Alignment.center,
                        child: Text(
                          _selectedStickerIndex != null && _selectedStickerIndex! < _stickers.length
                              ? '${_stickers[_selectedStickerIndex!].size.round()} px'
                              : (_isTextMode ? '${_fontSize.round()} pt' : '${_strokeWidth.round()}'),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: (_selectedStickerIndex != null || _isTextMode) ? LoveraColors.primaryDark : null,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Partnere Gönder Butonu
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isSending ? null : _sendDrawing,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: LoveraColors.primaryDark,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: _isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, size: 20),
                      label: Text(
                        _isSending ? ref.watch(stringsProvider).sendingToWidget : ref.watch(stringsProvider).sendToPartnerBtn,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
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

class _DrawingCanvasPainter extends CustomPainter {
  final List<List<DrawingPoint>> lines;
  final List<DrawingPoint> currentLine;
  final List<TextItem> texts;
  final int? selectedIndex;
  final Color backgroundColor;
  final bool isDark;
  final bool isExporting;

  _DrawingCanvasPainter({
    required this.lines,
    required this.currentLine,
    required this.texts,
    this.selectedIndex,
    required this.backgroundColor,
    this.isDark = true,
    this.isExporting = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isExporting) {
      // 1. Zemin Rengi (Lovera Teması)
      final bgPaint = Paint()..color = backgroundColor;
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

      // 2. Sol Üst ve Sağ Alt Hafif Aurora Işıltısı (Uygulama Temasına Uygun, Çizimi Gölgelemez)
      final violetPaint = Paint()
        ..shader = RadialGradient(
          colors: isDark
              ? [
                  LoveraColors.primary.withValues(alpha: 0.12),
                  LoveraColors.primaryDeep.withValues(alpha: 0.05),
                  Colors.transparent,
                ]
              : [
                  LoveraColors.primary.withValues(alpha: 0.10),
                  LoveraColors.primarySoft.withValues(alpha: 0.04),
                  Colors.transparent,
                ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.15, size.height * 0.15),
          radius: size.width * 0.65,
        ));
      canvas.drawCircle(Offset(size.width * 0.15, size.height * 0.15), size.width * 0.65, violetPaint);

      final pinkPaint = Paint()
        ..shader = RadialGradient(
          colors: isDark
              ? [
                  const Color(0xFFEC4899).withValues(alpha: 0.08),
                  Colors.transparent,
                ]
              : [
                  const Color(0xFFF472B6).withValues(alpha: 0.08),
                  Colors.transparent,
                ],
        ).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.85, size.height * 0.85),
          radius: size.width * 0.55,
        ));
      canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.85), size.width * 0.55, pinkPaint);

      // 3. Lovera Romantik Doodle Desenleri (Yıldız, Kalp, Hilal, Sonsuzluk vb. - Soluk, Gözü Yormayan Watermark)
      _drawThemePatterns(canvas, size);
    }

    // 4. Çizilmiş tüm çizgileri render et (Ayrı bir çizim katmanında render edilir; böylece silgi deseni değil sadece çizgiyi siler)
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    for (final line in lines) {
      _drawLine(canvas, line);
    }
    _drawLine(canvas, currentLine);
    canvas.restore();

    // 5. Eklenen metinleri render et
    for (int i = 0; i < texts.length; i++) {
      final item = texts[i];
      final isSelected = selectedIndex == i;

      final textSpan = TextSpan(
        text: item.text,
        style: TextStyle(
          color: item.color,
          fontSize: item.fontSize,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 4,
              offset: const Offset(1, 1),
            ),
          ],
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: (size.width - item.offset.dx).clamp(10.0, size.width));

      // Seçili metin etrafına hafif neon seçim çerçevesi çiz
      if (isSelected) {
        final borderPaint = Paint()
          ..color = LoveraColors.primaryDark
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6;
        final rect = Rect.fromLTWH(
          item.offset.dx - 6,
          item.offset.dy - 4,
          tp.width + 12,
          tp.height + 8,
        );
        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
        canvas.drawRRect(rrect, borderPaint);
      }

      tp.paint(canvas, item.offset);
    }
  }

  void _drawLine(Canvas canvas, List<DrawingPoint> line) {
    if (line.isEmpty) return;
    final isEraser = line.first.isEraser;

    final paint = Paint()
      ..color = isEraser ? Colors.transparent : line.first.paint.color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = line.first.paint.strokeWidth
      ..style = PaintingStyle.stroke
      ..blendMode = isEraser ? BlendMode.clear : BlendMode.srcOver;

    if (line.length == 1) {
      final fillPaint = Paint()
        ..color = isEraser ? Colors.transparent : line.first.paint.color
        ..style = PaintingStyle.fill
        ..blendMode = isEraser ? BlendMode.clear : BlendMode.srcOver;
      canvas.drawCircle(line.first.offset, line.first.paint.strokeWidth / 2, fillPaint);
      return;
    }

    final path = Path();
    path.moveTo(line.first.offset.dx, line.first.offset.dy);

    for (int i = 1; i < line.length; i++) {
      path.lineTo(line[i].offset.dx, line[i].offset.dy);
    }

    canvas.drawPath(path, paint);
  }

  void _drawThemePatterns(Canvas canvas, Size size) {
    // Çizilen şeyleri gölgede bırakmayacak şekilde çok soluk, zarif fligran opaklığı
    final strokePaint = Paint()
      ..color = isDark
          ? LoveraColors.primarySoft.withValues(alpha: 0.055)
          : LoveraColors.primary.withValues(alpha: 0.065)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = isDark
          ? LoveraColors.primaryDark.withValues(alpha: 0.035)
          : LoveraColors.primarySoft.withValues(alpha: 0.045)
      ..style = PaintingStyle.fill;

    const cellW = 80.0;
    const cellH = 80.0;

    final cols = (size.width / cellW).ceil() + 1;
    final rows = (size.height / cellH).ceil() + 1;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final x = c * cellW + ((r % 2 == 1) ? cellW * 0.5 : 0.0);
        final y = r * cellH;

        final patternType = (r * 5 + c * 3) % 8;

        canvas.save();
        canvas.translate(x, y);

        switch (patternType) {
          case 0:
            _drawHeart(canvas, strokePaint, fillPaint, 11);
            break;
          case 1:
            _drawArtPalette(canvas, strokePaint, fillPaint, 13);
            break;
          case 2:
            _drawFourPointStar(canvas, fillPaint, strokePaint, 9);
            break;
          case 3:
            _drawArtPencil(canvas, strokePaint, fillPaint, 12);
            break;
          case 4:
            _drawLoveEnvelope(canvas, strokePaint, 13);
            break;
          case 5:
            _drawCrescentMoon(canvas, strokePaint, fillPaint, 9);
            break;
          case 6:
            _drawInfinity(canvas, strokePaint, 12);
            break;
          case 7:
            _drawSparkleCross(canvas, strokePaint, 7);
            break;
        }

        canvas.restore();
      }
    }
  }

  void _drawArtPalette(Canvas canvas, Paint stroke, Paint fill, double r) {
    final path = Path();
    path.addOval(Rect.fromCenter(center: Offset.zero, width: r * 2.0, height: r * 1.5));
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
    // Başparmak deliği
    canvas.drawCircle(Offset(-r * 0.4, 0), r * 0.25, stroke);
    // Minik renk damlaları
    canvas.drawCircle(Offset(r * 0.3, -r * 0.3), 1.2, stroke);
    canvas.drawCircle(Offset(r * 0.5, 0), 1.2, stroke);
    canvas.drawCircle(Offset(r * 0.2, r * 0.35), 1.2, stroke);
  }

  void _drawArtPencil(Canvas canvas, Paint stroke, Paint fill, double s) {
    canvas.save();
    canvas.rotate(-math.pi / 4);
    final rect = Rect.fromCenter(center: Offset.zero, width: s * 0.35, height: s * 1.6);
    canvas.drawRect(rect, fill);
    canvas.drawRect(rect, stroke);
    final tip = Path()
      ..moveTo(-s * 0.175, -s * 0.8)
      ..lineTo(0, -s * 1.25)
      ..lineTo(s * 0.175, -s * 0.8)
      ..close();
    canvas.drawPath(tip, stroke);
    canvas.restore();
  }

  void _drawHeart(Canvas canvas, Paint stroke, Paint fill, double r) {
    final path = Path();
    path.moveTo(0, r * 0.35);
    path.cubicTo(-r, -r * 0.5, -r * 1.2, r * 0.45, 0, r * 1.2);
    path.cubicTo(r * 1.2, r * 0.45, r, -r * 0.5, 0, r * 0.35);
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  void _drawFourPointStar(Canvas canvas, Paint fill, Paint stroke, double r) {
    final path = Path();
    path.moveTo(0, -r);
    path.quadraticBezierTo(0, 0, r, 0);
    path.quadraticBezierTo(0, 0, 0, r);
    path.quadraticBezierTo(0, 0, -r, 0);
    path.quadraticBezierTo(0, 0, 0, -r);
    path.close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  void _drawLoveEnvelope(Canvas canvas, Paint stroke, double w) {
    final h = w * 0.68;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      const Radius.circular(2.0),
    );
    canvas.drawRRect(rrect, stroke);
    final flap = Path()
      ..moveTo(-w / 2, -h / 2)
      ..lineTo(0, h * 0.15)
      ..lineTo(w / 2, -h / 2);
    canvas.drawPath(flap, stroke);
  }

  void _drawCrescentMoon(Canvas canvas, Paint stroke, Paint fill, double r) {
    final path = Path();
    path.addArc(Rect.fromCircle(center: Offset.zero, radius: r), -math.pi / 2, math.pi);
    path.arcTo(Rect.fromCircle(center: Offset(r * 0.35, 0), radius: r * 0.8), math.pi / 2, -math.pi, false);
    path.close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  void _drawInfinity(Canvas canvas, Paint stroke, double w) {
    final r = w * 0.32;
    canvas.drawCircle(Offset(-r, 0), r * 0.72, stroke);
    canvas.drawCircle(Offset(r, 0), r * 0.72, stroke);
  }

  void _drawSparkleCross(Canvas canvas, Paint stroke, double s) {
    canvas.drawLine(Offset(-s, 0), Offset(s, 0), stroke);
    canvas.drawLine(Offset(0, -s), Offset(0, s), stroke);
    canvas.drawCircle(const Offset(6, -6), 1.0, stroke);
    canvas.drawCircle(const Offset(-6, 6), 0.8, stroke);
  }

  @override
  bool shouldRepaint(covariant _DrawingCanvasPainter oldDelegate) => true;
}
