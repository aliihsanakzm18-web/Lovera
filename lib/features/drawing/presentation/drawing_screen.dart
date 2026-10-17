import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/services/database_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/widget_sync_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';

/// Serbest Çizim Noktası
class DrawingPoint {
  final Offset offset;
  final Paint paint;

  DrawingPoint({required this.offset, required this.paint});
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

  // Çizim Araçları
  Color _selectedColor = const Color(0xFFA78BFA);
  double _strokeWidth = 5.0;
  double _fontSize = 24.0;
  bool _isEraser = false;
  bool _isTextMode = false;
  bool _isSending = false;

  final List<Color> _palette = const [
    Color(0xFFA78BFA), // Lovera Moru
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
      if (_texts.isNotEmpty) {
        _texts.removeLast();
      } else if (_lines.isNotEmpty) {
        _lines.removeLast();
      }
    });
  }

  void _clearCanvas() {
    if (_lines.isNotEmpty || _currentLine.isNotEmpty || _texts.isNotEmpty) {
      HapticFeedback.mediumImpact();
      setState(() {
        _lines.clear();
        _currentLine.clear();
        _texts.clear();
        _selectedTextIndex = null;
      });
    }
  }

  void _showAddTextDialog({Offset? defaultPosition, int? editIndex}) {
    final isEditing = editIndex != null && editIndex < _texts.length;
    final initialText = isEditing ? _texts[editIndex].text : '';
    final controller = TextEditingController(text: initialText);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1938),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Text(isEditing ? '✏️ ' : '✍️ ', style: const TextStyle(fontSize: 20)),
              Text(
                isEditing ? 'Yazıyı Düzenle' : 'Yazı Ekle',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (isEditing)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  tooltip: 'Yazıyı Sil',
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
              hintText: 'Mesajını veya notunu yaz...',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 15),
              filled: true,
              fillColor: const Color(0xFF161426),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal', style: TextStyle(color: Colors.white70)),
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
                backgroundColor: const Color(0xFFA78BFA),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(isEditing ? 'Güncelle' : 'Ekle', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendDrawing() async {
    if (_lines.isEmpty && _currentLine.isEmpty && _texts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen göndermeden önce bir şeyler çizin veya yazı ekleyin! 🎨'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final coupleId = ref.read(coupleIdProvider);
    final partnerUid = ref.read(partnerUidProvider);
    final myName = ref.read(userNameProvider).isNotEmpty
        ? ref.read(userNameProvider)
        : 'Partnerin';

    if (coupleId == null || coupleId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Çizim gönderebilmek için eşleşmiş olmanız gerekir 💕'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isSending = true;
      _selectedTextIndex = null;
    });
    HapticFeedback.mediumImpact();

    try {
      // Çerçevenin seçim kutucuksuz çizildiğinden emin olmak için bir frame bekle
      await WidgetsBinding.instance.endOfFrame;

      // 1. RepaintBoundary'den yüksek kaliteli PNG üret
      final boundary = _globalKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Canvas render hatası');
      }

      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Görsel dönüştürülemedi');
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
          senderName: 'Sen',
          timeAgo: 'Şimdi',
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

      // 4. Partnere anında Push Bildirimi yolla (Partnere widget'ı anında güncellensin!)
      if (partnerUid != null && partnerUid.isNotEmpty) {
        NotificationService().sendPushToPartner(
          partnerUid: partnerUid,
          title: '🎨 $myName sana bir çizim gönderdi!',
          body: 'Ana ekranındaki Lovera Çizim Widget\'ına bak 💕',
          data: {
            'type': 'drawing_sent',
            'coupleId': coupleId,
            'senderName': myName,
            'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
          },
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Çizimin $myName tarafından gönderildi! Partnerinin ana ekranında görünecek 💜'),
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
            content: Text('Çizim gönderilemedi: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0C1B) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Canlı Çizim Tuvali', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.undo_rounded),
            tooltip: 'Geri Al',
            onPressed: _lines.isEmpty ? null : _undo,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Tuvali Temizle',
            onPressed: (_lines.isEmpty && _currentLine.isEmpty) ? null : _clearCanvas,
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
                  color: isDark ? const Color(0xD018132A) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x55A78BFA), width: 1.2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('✨', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Çizimin partnerinin ana ekran widget\'ında anında belirir',
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
                        border: Border.all(color: const Color(0x55A78BFA), width: 1.8),
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
                                  for (int i = _texts.length - 1; i >= 0; i--) {
                                    final item = _texts[i];
                                    final estimatedW = (item.text.length * (item.fontSize * 0.62)).clamp(60.0, 320.0);
                                    final estimatedH = item.fontSize * 1.5;
                                    final rect = Rect.fromLTWH(item.offset.dx - 12, item.offset.dy - 10, estimatedW + 24, estimatedH + 20);
                                    if (rect.contains(pos)) {
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        _selectedTextIndex = i;
                                        _isTextMode = true;
                                        _fontSize = item.fontSize;
                                        _selectedColor = item.color;
                                      });
                                      return;
                                    }
                                  }

                                  if (_selectedTextIndex != null) {
                                    setState(() => _selectedTextIndex = null);
                                  } else if (_isTextMode) {
                                    _showAddTextDialog(defaultPosition: pos);
                                  }
                                },
                                onPanStart: (details) {
                                  final pos = details.localPosition;
                                  for (int i = _texts.length - 1; i >= 0; i--) {
                                    final item = _texts[i];
                                    final estimatedW = (item.text.length * (item.fontSize * 0.62)).clamp(60.0, 320.0);
                                    final estimatedH = item.fontSize * 1.5;
                                    final rect = Rect.fromLTWH(item.offset.dx - 12, item.offset.dy - 10, estimatedW + 24, estimatedH + 20);
                                    if (rect.contains(pos)) {
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        _selectedTextIndex = i;
                                        _isTextMode = true;
                                        _fontSize = item.fontSize;
                                        _selectedColor = item.color;
                                      });
                                      return;
                                    }
                                  }

                                  if (_isTextMode) return;

                                  setState(() => _selectedTextIndex = null);
                                  HapticFeedback.selectionClick();
                                  final paint = Paint()
                                    ..color = _isEraser
                                        ? const Color(0xFF161426)
                                        : _selectedColor
                                    ..strokeCap = StrokeCap.round
                                    ..strokeWidth = _isEraser ? _strokeWidth * 2.2 : _strokeWidth;
                                  setState(() {
                                    _currentLine = [DrawingPoint(offset: pos, paint: paint)];
                                  });
                                },
                                onPanUpdate: (details) {
                                  if (_selectedTextIndex != null && _selectedTextIndex! < _texts.length) {
                                    setState(() {
                                      _texts[_selectedTextIndex!].offset += details.delta;
                                    });
                                    return;
                                  }
                                  if (_isTextMode) return;

                                  final offset = details.localPosition;
                                  final paint = Paint()
                                    ..color = _isEraser
                                        ? const Color(0xFF161426)
                                        : _selectedColor
                                    ..strokeCap = StrokeCap.round
                                    ..strokeWidth = _isEraser ? _strokeWidth * 2.2 : _strokeWidth;
                                  setState(() {
                                    _currentLine.add(DrawingPoint(offset: offset, paint: paint));
                                  });
                                },
                                onPanEnd: (details) {
                                  if (_isTextMode) return;

                                  setState(() {
                                    _lines.add(List.from(_currentLine));
                                    _currentLine = [];
                                  });
                                },
                                child: CustomPaint(
                                  painter: _DrawingCanvasPainter(
                                    lines: _lines,
                                    currentLine: _currentLine,
                                    texts: _texts,
                                    selectedIndex: _isSending ? null : _selectedTextIndex,
                                    backgroundColor: isDark ? const Color(0xFF161426) : const Color(0xFF161426),
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
                                          color: const Color(0xFF1E1938),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: const Color(0xFFA78BFA), width: 1.2),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.5),
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
                                              child: const Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.edit_rounded, color: Colors.white, size: 14),
                                                    SizedBox(width: 4),
                                                    Text('Düzenle', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            Container(
                                              width: 1,
                                              height: 14,
                                              color: Colors.white24,
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
                                              child: const Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 14),
                                                    SizedBox(width: 4),
                                                    Text('Sil', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
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
                              color: _isEraser ? const Color(0x55A78BFA) : Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _isEraser ? const Color(0xFFA78BFA) : Colors.grey.withValues(alpha: 0.3),
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.cleaning_services_rounded,
                              size: 22,
                              color: _isEraser ? const Color(0xFFA78BFA) : Colors.grey,
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
                              color: _isTextMode ? const Color(0x55A78BFA) : Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _isTextMode ? const Color(0xFFA78BFA) : Colors.grey.withValues(alpha: 0.3),
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.title_rounded,
                              size: 22,
                              color: _isTextMode ? const Color(0xFFA78BFA) : Colors.grey,
                            ),
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
                                  color: isSelected ? Colors.white : Colors.black12,
                                  width: isSelected ? 3 : 1.5,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: color.withValues(alpha: 0.6),
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

                  // Fırça Kalınlığı veya Metin Boyutu Slider'ı
                  Row(
                    children: [
                      Icon(
                        _isTextMode ? Icons.format_size_rounded : Icons.brush_rounded,
                        size: 20,
                        color: _isTextMode ? const Color(0xFFA78BFA) : LoveraColors.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: const Color(0xFFA78BFA),
                            thumbColor: const Color(0xFFA78BFA),
                            overlayColor: const Color(0x33A78BFA),
                            trackHeight: 3.5,
                          ),
                          child: _isTextMode
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
                                ),
                        ),
                      ),
                      Container(
                        width: 32,
                        alignment: Alignment.center,
                        child: Text(
                          _isTextMode ? '${_fontSize.round()} pt' : '${_strokeWidth.round()}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: _isTextMode ? const Color(0xFFA78BFA) : null,
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
                        backgroundColor: const Color(0xFFA78BFA),
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
                        _isSending ? 'Widget\'a Gönderiliyor...' : 'Partnere Gönder 💜',
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

  _DrawingCanvasPainter({
    required this.lines,
    required this.currentLine,
    required this.texts,
    this.selectedIndex,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Arka planı doldur
    final bgPaint = Paint()..color = backgroundColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Çizilmiş tüm çizgileri render et
    for (final line in lines) {
      _drawLine(canvas, line);
    }
    _drawLine(canvas, currentLine);

    // Eklenen metinleri render et
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
          ..color = const Color(0xFFA78BFA)
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
    if (line.length == 1) {
      canvas.drawCircle(line.first.offset, line.first.paint.strokeWidth / 2, line.first.paint);
      return;
    }

    final path = Path();
    path.moveTo(line.first.offset.dx, line.first.offset.dy);

    for (int i = 1; i < line.length; i++) {
      path.lineTo(line[i].offset.dx, line[i].offset.dy);
    }

    final paint = Paint()
      ..color = line.first.paint.color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = line.first.paint.strokeWidth
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DrawingCanvasPainter oldDelegate) => true;
}
