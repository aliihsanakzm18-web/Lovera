import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/models/models.dart';
import '../../../../core/services/database_service.dart';
import '../../../../core/state/app_state.dart';
import '../../../../core/theme/app_theme.dart';

/// Mesajlaşma kısmından paylaşılan tüm fotoğrafların tarih sıralı listelendiği,
/// toplu seçim (indirme, albüme kaydetme, silme) ve tekil detay modallarına sahip alt menü bileşeni.
class ChatMediaGallerySheet extends ConsumerStatefulWidget {
  const ChatMediaGallerySheet({
    super.key,
    required this.coupleId,
    required this.onReplyToMessage,
  });

  final String coupleId;
  final void Function(ChatMessage message) onReplyToMessage;

  @override
  ConsumerState<ChatMediaGallerySheet> createState() => _ChatMediaGallerySheetState();
}

class _ChatMediaGallerySheetState extends ConsumerState<ChatMediaGallerySheet> {
  bool _isSelectionMode = false;
  final Set<String> _selectedMessageIds = <String>{};
  bool _isPerformingAction = false;

  void _toggleSelection(String messageId) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
        if (_selectedMessageIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  Future<void> _downloadSelected(List<ChatMessage> photoMessages) async {
    final targets = photoMessages.where((m) => _selectedMessageIds.contains(m.id)).toList();
    if (targets.isEmpty) return;

    setState(() => _isPerformingAction = true);
    HapticFeedback.mediumImpact();

    int successCount = 0;
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        await Gal.requestAccess();
      }

      for (final msg in targets) {
        if (msg.mediaBase64 == null) continue;
        try {
          final raw = msg.mediaBase64!.split(',').last;
          final bytes = base64Decode(raw);
          await Gal.putImageBytes(
            bytes,
            name: 'lovera_${msg.id}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
          successCount++;
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc('$successCount fotoğraf galeriye kaydedildi! 📸✨', '$successCount photos saved to gallery! 📸✨')),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {
          _isSelectionMode = false;
          _selectedMessageIds.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc('İndirme sırasında hata: $e', 'Download error: $e')),
            backgroundColor: LoveraColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPerformingAction = false);
    }
  }

  Future<void> _saveSelectedToMemories(List<ChatMessage> photoMessages) async {
    final targets = photoMessages.where((m) => _selectedMessageIds.contains(m.id)).toList();
    if (targets.isEmpty) return;

    setState(() => _isPerformingAction = true);
    HapticFeedback.heavyImpact();

    try {
      final myName = ref.read(userNameProvider);
      final images = targets
          .where((m) => m.mediaBase64 != null)
          .map((m) => m.mediaBase64!)
          .toList();

      if (images.isNotEmpty) {
        await DatabaseService().addMultipleMemories(
          coupleId: widget.coupleId,
          imagesBase64: images,
          createdByName: myName.isNotEmpty ? myName : 'Partnerin',
          caption: loc('Sohbetten kaydedilen anılar 💌', 'Memories saved from chat 💌'),
          commonDate: DateTime.now(),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(loc('${images.length} fotoğraf Ortak Anı Albümüne mühürlendi! 💖✨', '${images.length} photos saved to Shared Memories! 💖✨')),
              backgroundColor: LoveraColors.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
          setState(() {
            _isSelectionMode = false;
            _selectedMessageIds.clear();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc('Albüme kaydedilemedi: $e', 'Could not save to album: $e')),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPerformingAction = false);
    }
  }

  Future<void> _deleteSelected(List<ChatMessage> photoMessages) async {
    final count = _selectedMessageIds.length;
    if (count == 0) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444), size: 24),
            const SizedBox(width: 8),
            Text(loc('$count Fotoğrafı Sil', 'Delete $count Photos')),
          ],
        ),
        content: Text(
          loc(
            'Seçtiğiniz bu fotoğraflar her iki tarafın mesaj geçmişinden kalıcı olarak silinecek. Emin misiniz?',
            'These selected photos will be deleted permanently for both sides. Are you sure?',
          ),
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(loc('Vazgeç', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(loc('Sil', 'Delete'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isPerformingAction = true);
    HapticFeedback.heavyImpact();

    try {
      for (final id in _selectedMessageIds) {
        await DatabaseService().deleteMessage(widget.coupleId, id);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc('$count fotoğraf silindi 🗑️', '$count photos deleted 🗑️')),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {
          _isSelectionMode = false;
          _selectedMessageIds.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc('Silinirken hata oluştu: $e', 'Error while deleting: $e')),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPerformingAction = false);
    }
  }

  void _showSinglePhotoDetailModal(ChatMessage message) {
    HapticFeedback.lightImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bytes = base64Decode(message.mediaBase64!.split(',').last);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (mCtx) {
        bool isSavingSingle = false;

        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Container(
              height: MediaQuery.of(modalCtx).size.height * 0.88,
              decoration: BoxDecoration(
                color: isDark ? LoveraColors.darkSurface : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 25,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Sürükleme Tutamacı & Üst Bar
                  const SizedBox(height: 12),
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text('📸', style: TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Text(
                              '${message.createdAt.day}.${message.createdAt.month}.${message.createdAt.year} ${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                color: isDark ? Colors.white70 : LoveraColors.textDark,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 22),
                          onPressed: () => Navigator.pop(mCtx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // BÜYÜTÜLEBİLİR FOTOĞRAF
                  Expanded(
                    child: Container(
                      color: Colors.black,
                      width: double.infinity,
                      child: InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 4.0,
                        child: Center(
                          child: Image.memory(
                            bytes,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ALT AKSİYON BUTONLARI (İndir, Mesajda Yanıtla, Ortak Anı Albümüne Kaydet)
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    decoration: BoxDecoration(
                      color: isDark ? LoveraColors.darkBg : LoveraColors.lightBg,
                      border: Border(
                        top: BorderSide(
                          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        // 1. Cihaza İndir
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(color: LoveraColors.primary.withValues(alpha: 0.4)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: isSavingSingle
                                ? null
                                : () async {
                                    setModalState(() => isSavingSingle = true);
                                    HapticFeedback.lightImpact();
                                    try {
                                      final hasAccess = await Gal.hasAccess();
                                      if (!hasAccess) await Gal.requestAccess();
                                      await Gal.putImageBytes(
                                        bytes,
                                        name: 'lovera_${message.id}_${DateTime.now().millisecondsSinceEpoch}.jpg',
                                      );
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(loc('Fotoğraf galeriye kaydedildi! 📸✨', 'Photo saved to gallery! 📸✨')),
                                            backgroundColor: const Color(0xFF10B981),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(loc('Kaydedilemedi: $e', 'Could not save: $e')),
                                            backgroundColor: const Color(0xFFEF4444),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    } finally {
                                      setModalState(() => isSavingSingle = false);
                                    }
                                  },
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: Text(
                              loc('İndir', 'Save'),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // 2. Mesajda Yanıtla
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(color: const Color(0xFF6366F1).withValues(alpha: 0.4)),
                              foregroundColor: const Color(0xFF6366F1),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: () {
                              Navigator.pop(mCtx); // Detay modalını kapat
                              Navigator.pop(context); // Galeri sheetini kapat
                              widget.onReplyToMessage(message); // Mesaj giriş alanına alıntı ekle
                            },
                            icon: const Icon(Icons.reply_rounded, size: 18),
                            label: Text(
                              loc('Yanıtla', 'Reply'),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // 3. Ortak Anı Albümüne Kaydet
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: LoveraColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: isSavingSingle
                                ? null
                                : () async {
                                    setModalState(() => isSavingSingle = true);
                                    HapticFeedback.heavyImpact();
                                    try {
                                      final myName = ref.read(userNameProvider);
                                      await DatabaseService().addMemory(
                                        coupleId: widget.coupleId,
                                        imageBase64: message.mediaBase64!,
                                        caption: loc('Sohbetten kaydedilen anı 💌', 'Memory saved from chat 💌'),
                                        locationTitle: '',
                                        date: message.createdAt,
                                        createdByName: myName.isNotEmpty ? myName : 'Partnerin',
                                      );
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(loc('Ortak Anı Albümüne mühürlendi! 💖✨', 'Saved to Shared Memories! 💖✨')),
                                            backgroundColor: LoveraColors.primary,
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(loc('Albüme eklenemedi: $e', 'Could not add to album: $e')),
                                            backgroundColor: const Color(0xFFEF4444),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    } finally {
                                      setModalState(() => isSavingSingle = false);
                                    }
                                  },
                            icon: const Icon(Icons.favorite_rounded, size: 18),
                            label: Text(
                              loc('Albüme Kaydet', 'Save to Album'),
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark ? LoveraColors.darkSurface : LoveraColors.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: StreamBuilder<List<ChatMessage>>(
        stream: DatabaseService().messagesStream(widget.coupleId),
        builder: (context, snapshot) {
          final allMessages = snapshot.data ?? [];
          // Sadece görsel içeren mesajları filtrele ve kronolojik olarak (en yeniden eskiye) sırala
          final photoMessages = allMessages
              .where((m) => m.type == 'image' && m.mediaBase64 != null && m.mediaBase64!.isNotEmpty)
              .toList();

          photoMessages.sort((a, b) => b.createdAt.compareTo(a.createdAt));

          return Column(
            children: [
              // Üst Sürükleme Çubuğu
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              // Başlık & Çoklu Seçim Aksiyonları
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: LoveraColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('📸', style: TextStyle(fontSize: 18)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isSelectionMode
                                ? loc('${_selectedMessageIds.length} Fotoğraf Seçildi', '${_selectedMessageIds.length} Photos Selected')
                                : loc('Sohbet Fotoğrafları', 'Chat Photos'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            loc('${photoMessages.length} fotoğraf paylaşıldı', '${photoMessages.length} photos shared'),
                            style: TextStyle(
                              color: LoveraColors.textMuted,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (photoMessages.isNotEmpty)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: _isSelectionMode ? const Color(0xFFEF4444) : LoveraColors.primary,
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _isSelectionMode = !_isSelectionMode;
                            _selectedMessageIds.clear();
                          });
                        },
                        icon: Icon(
                          _isSelectionMode ? Icons.close_rounded : Icons.checklist_rounded,
                          size: 18,
                        ),
                        label: Text(
                          _isSelectionMode ? loc('İptal', 'Cancel') : loc('Seç', 'Select'),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // FOTOĞRAF LİSTESİ / IZGARASI
              Expanded(
                child: photoMessages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('🖼️', style: TextStyle(fontSize: 44)),
                            const SizedBox(height: 12),
                            Text(
                              loc('Henüz paylaşılan fotoğraf yok', 'No shared photos yet'),
                              style: TextStyle(
                                color: isDark ? Colors.white70 : LoveraColors.textDark,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              loc('Sohbette birbirinize gönderdiğiniz tüm fotoğraflar burada toplanır.', 'All photos you send to each other in chat appear here.'),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: LoveraColors.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1.0,
                        ),
                        itemCount: photoMessages.length,
                        itemBuilder: (context, index) {
                          final msg = photoMessages[index];
                          final isSelected = _selectedMessageIds.contains(msg.id);
                          final rawBytes = base64Decode(msg.mediaBase64!.split(',').last);

                          return InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              if (_isSelectionMode) {
                                _toggleSelection(msg.id);
                              } else {
                                _showSinglePhotoDetailModal(msg);
                              }
                            },
                            onLongPress: () {
                              if (!_isSelectionMode) {
                                setState(() {
                                  _isSelectionMode = true;
                                  _selectedMessageIds.add(msg.id);
                                });
                                HapticFeedback.heavyImpact();
                              }
                            },
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.memory(
                                    rawBytes,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  ),
                                ),

                                // Seçim Çerçevesi ve İkonu
                                if (_isSelectionMode)
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      color: isSelected
                                          ? LoveraColors.primary.withValues(alpha: 0.35)
                                          : Colors.black.withValues(alpha: 0.15),
                                      border: Border.all(
                                        color: isSelected ? LoveraColors.primary : Colors.white70,
                                        width: isSelected ? 2.5 : 1.2,
                                      ),
                                    ),
                                    child: Align(
                                      alignment: Alignment.topRight,
                                      child: Padding(
                                        padding: const EdgeInsets.all(6),
                                        child: CircleAvatar(
                                          radius: 11,
                                          backgroundColor: isSelected ? LoveraColors.primary : Colors.black45,
                                          child: Icon(
                                            isSelected ? Icons.check_rounded : null,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                // Tarih Etiketi
                                Align(
                                  alignment: Alignment.bottomLeft,
                                  child: Container(
                                    margin: const EdgeInsets.all(4),
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${msg.createdAt.day}.${msg.createdAt.month}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),

              // TOPLU AKSİYON ÇUBUĞU (Seçim Modunda En Altta Çıkar)
              if (_isSelectionMode && _selectedMessageIds.isNotEmpty)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  decoration: BoxDecoration(
                    color: isDark ? LoveraColors.darkBg : LoveraColors.lightBg,
                    border: Border(
                      top: BorderSide(
                        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Toplu İndir
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: LoveraColors.primary.withValues(alpha: 0.4)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _isPerformingAction ? null : () => _downloadSelected(photoMessages),
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: Text(
                            loc('İndir', 'Save'),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Toplu Sil
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                            foregroundColor: const Color(0xFFEF4444),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _isPerformingAction ? null : () => _deleteSelected(photoMessages),
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          label: Text(
                            loc('Sil', 'Delete'),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Toplu Ortak Anı Albümüne Kaydet
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: LoveraColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _isPerformingAction ? null : () => _saveSelectedToMemories(photoMessages),
                          icon: const Icon(Icons.favorite_rounded, size: 18),
                          label: Text(
                            loc('Albüme Kaydet', 'Save to Album'),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
