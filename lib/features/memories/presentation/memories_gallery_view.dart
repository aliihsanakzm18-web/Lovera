import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/models/models.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/lovera_theme_background.dart';

final memoriesStreamProvider = StreamProvider.family<List<MemoryItem>, String>((ref, coupleId) {
  if (coupleId.isEmpty) return const Stream.empty();
  return DatabaseService().memoriesStream(coupleId);
});

final albumsStreamProvider = StreamProvider.family<List<MemoryAlbum>, String>((ref, coupleId) {
  if (coupleId.isEmpty) return const Stream.empty();
  return DatabaseService().albumsStream(coupleId);
});

class MemoriesGalleryView extends ConsumerStatefulWidget {
  const MemoriesGalleryView({super.key});

  @override
  ConsumerState<MemoriesGalleryView> createState() => _MemoriesGalleryViewState();
}

class _MemoriesGalleryViewState extends ConsumerState<MemoriesGalleryView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isGridView = true; // true: Galeri Izgarası, false: Zaman Tüneli
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  // Çoklu seçim modu (Mevcut anıları seçip gruba dönüştürme veya silme için)
  bool _isSelectionMode = false;
  final Set<String> _selectedMemoryIds = <String>{};

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

  /// Fotoğrafın EXIF meta verilerinden çekildiği orijinal tarihi okur
  Future<DateTime?> _extractOriginalDateFromImage(XFile file) async {
    try {
      final rawBytes = await file.readAsBytes();
      final data = await readExifFromBytes(rawBytes);

      final dateTags = [
        'EXIF DateTimeOriginal',
        'EXIF DateTimeDigitized',
        'Image DateTime',
      ];

      for (final tag in dateTags) {
        if (data.containsKey(tag)) {
          final dateStr = data[tag]?.toString();
          if (dateStr != null && dateStr.isNotEmpty) {
            final parts = dateStr.trim().split(' ');
            if (parts.isNotEmpty) {
              final dateParts = parts[0].replaceAll(':', '-');
              final timePart = parts.length > 1 ? parts[1] : '12:00:00';
              final parsed = DateTime.tryParse('$dateParts $timePart');
              if (parsed != null) {
                return parsed;
              }
            }
          }
        }
      }

      final lastModified = await file.lastModified();
      if (lastModified.isBefore(DateTime.now().subtract(const Duration(hours: 1)))) {
        return lastModified;
      }
    } catch (e) {
      debugPrint('[MemoriesGallery] EXIF date extraction error: $e');
    }
    return null;
  }

  /// Fotoğrafı optimize edip güvenli base64 string'e dönüştürür (Firestore boyut limiti koruması)
  Future<String> _compressAndEncodeImage(XFile file) async {
    // imagePicker ile zaten max 1440x1440 ve %72 kalite ile optimize edilmiş dosya okunuyor
    final bytes = await file.readAsBytes();
    return 'data:image/jpeg;base64,${base64Encode(bytes)}';
  }

  /// Ana Ekleme Menüsü: Kullanıcıya Tekli veya Çoklu Ekleme Seçenekleri Sunar
  Future<void> _showAddActionSheet() async {
    final coupleId = ref.read(coupleIdProvider);
    if (coupleId == null || coupleId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anı eklemek için önce partnerinle eşleşmelisin! 💕'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E212B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Albüme Fotoğraf Ekle 💕',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Nasıl fotoğraf eklemek istersiniz?',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: LoveraColors.textMuted),
            ),
            const SizedBox(height: 22),
            // Seçenek 1: Fotoğraf Ekle (Tekli veya Çoklu)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              tileColor: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: LoveraColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_photo_alternate_rounded, color: LoveraColors.primary),
              ),
              title: const Text('Fotoğraf Ekle 📸', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Galeriden bir veya birden fazla fotoğraf seçin', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded, color: LoveraColors.textMuted),
              onTap: () {
                Navigator.pop(ctx);
                _openUnifiedPhotoPicker();
              },
            ),
            const SizedBox(height: 12),
            // Seçenek 2: Yeni Klasör Ekle
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              tileColor: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LoveraColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.create_new_folder_rounded, color: Colors.white),
              ),
              title: const Text('Yeni Klasör Ekle 📁', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Yeni bir anı klasörü oluşturun (İsim, hikaye, mekan, tarih)', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded, color: LoveraColors.textMuted),
              onTap: () {
                Navigator.pop(ctx);
                _openCreateFolderDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// TEK VEYA ÇOKLU FOTOĞRAF SEÇİM AKIŞI
  Future<void> _openUnifiedPhotoPicker() async {
    final coupleId = ref.read(coupleIdProvider);
    if (coupleId == null || coupleId.isEmpty) return;

    try {
      final pickedFiles = await _picker.pickMultiImage(
        maxWidth: 1440,
        maxHeight: 1440,
        imageQuality: 72,
        requestFullMetadata: true,
      );

      if (pickedFiles.isEmpty || !mounted) return;

      if (pickedFiles.length == 1) {
        // 1 adet fotoğraf seçilirse konum, hikaye gibi bilgilerin girilebileceği alt menü açılsın
        await _showSinglePhotoDetailsSheet(pickedFiles.first);
      } else {
        // Çoklu fotoğraf seçilirse o menü açılmasın, direkt toplu işlem seçenekleri sunulsun
        _showBatchDestinationDialog(pickedFiles);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotoğraf seçilemedi: $e')),
        );
      }
    }
  }

  /// 1. TEK FOTOĞRAF DETAY VE EKLEME AKIŞI
  Future<void> _showSinglePhotoDetailsSheet(XFile picked) async {
    final coupleId = ref.read(coupleIdProvider);
    if (coupleId == null || coupleId.isEmpty) return;

    try {
      final extractedDate = await _extractOriginalDateFromImage(picked);
      DateTime selectedDate = extractedDate ?? DateTime.now();
      final base64Img = await _compressAndEncodeImage(picked);

      final captionController = TextEditingController();
      final locationController = TextEditingController();
      final bool wasAutoDetected = extractedDate != null;

      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (bCtx) => StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;

            return Container(
              padding: EdgeInsets.fromLTRB(22, 16, 22, MediaQuery.of(context).viewInsets.bottom + 24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E212B) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 25,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Yeni Anı Ekle ✨',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 18),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black26 : Colors.grey.shade100,
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: _buildMemoryImage(base64Img),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: captionController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Bu anının hikayesi / notunuz 💕',
                        hintText: 'Örn: Birlikte gittiğimiz ilk tatil...',
                        filled: true,
                        fillColor: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: locationController,
                      decoration: InputDecoration(
                        labelText: 'Mekan / Şehir (İsteğe bağlı)',
                        hintText: 'Örn: Antalya, Kaş',
                        prefixIcon: const Icon(Icons.location_on_rounded, color: LoveraColors.primary, size: 20),
                        filled: true,
                        fillColor: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                          helpText: 'Anının Gerçekleştiği Tarih',
                        );
                        if (pickedDate != null) {
                          setSheetState(() => selectedDate = pickedDate);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: wasAutoDetected ? LoveraColors.primary.withValues(alpha: 0.5) : theme.dividerColor,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              wasAutoDetected ? Icons.auto_awesome_rounded : Icons.calendar_month_rounded,
                              color: LoveraColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Tarih: ${selectedDate.day}.${selectedDate.month}.${selectedDate.year}',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  if (wasAutoDetected) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      '📸 Fotoğrafın çekildiği tarihten otomatik alındı',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: LoveraColors.primary.withValues(alpha: 0.85),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const Icon(Icons.edit_calendar_rounded, size: 18, color: LoveraColors.textMuted),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () async {
                        Navigator.pop(bCtx);
                        setState(() => _isUploading = true);
                        try {
                          final myName = ref.read(userNameProvider);
                          await DatabaseService().addMemory(
                            coupleId: coupleId,
                            imageBase64: base64Img,
                            caption: captionController.text,
                            locationTitle: locationController.text,
                            date: selectedDate,
                            createdByName: myName.isEmpty ? 'Partnerin' : myName,
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Anınız ortak albüme başarıyla kaydedildi! 💕📸'),
                                backgroundColor: LoveraColors.primary,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Anı eklenirken hata: $e')),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _isUploading = false);
                        }
                      },
                      child: const Text('Anıyı Albüme Ekle', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotoğraf seçilemedi: $e')),
        );
      }
    }
  }

  /// Toplu Seçilen Fotoğrafların Nereye Ekleneceğini Soran Diyalog
  void _showBatchDestinationDialog(List<XFile> files) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E212B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.photo_library_rounded, color: LoveraColors.primary),
                const SizedBox(width: 8),
                Text(
                  '${files.length} Fotoğraf Seçildi',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Bu fotoğrafları ortak anılarınıza nasıl eklemek istersiniz?',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: LoveraColors.textMuted),
            ),
            const SizedBox(height: 24),
            // SEÇENEK 1: Anı Grubu (Klasör) Oluştur
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                Navigator.pop(ctx);
                _openCreateAlbumDialog(files);
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: LoveraColors.primary.withValues(alpha: 0.4), width: 1.5),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LoveraColors.primaryGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.folder_special_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Anı Grubu / Klasör Oluştur ✨',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Bir grup oluşturun: İsim, mekan, ortak hikaye ve tarih belirleyip hepsini bu klasöre toplayın.',
                            style: TextStyle(fontSize: 12, color: LoveraColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: LoveraColors.primary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            // SEÇENEK 2: Direkt Anı Albümüne Ekle
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                Navigator.pop(ctx);
                _uploadDirectToAlbum(files);
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.library_add_check_rounded, color: Color(0xFF10B981), size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Direkt Anı Albümüne Ekle 📸',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Teker teker bilgi girmeden hızlıca albüme aktarır. İstediğiniz zaman fotoğrafa dokunup notunu veya konumunu düzenleyebilirsiniz.',
                            style: TextStyle(fontSize: 12, color: LoveraColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: LoveraColors.textMuted),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hızlıca Direkt Albüme Yükleme
  Future<void> _uploadDirectToAlbum(List<XFile> files) async {
    final coupleId = ref.read(coupleIdProvider);
    if (coupleId == null || coupleId.isEmpty) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      final List<String> encodedImages = [];
      for (int i = 0; i < files.length; i++) {
        final b64 = await _compressAndEncodeImage(files[i]);
        encodedImages.add(b64);
        if (mounted) {
          setState(() => _uploadProgress = (i + 1) / files.length);
        }
      }

      final myName = ref.read(userNameProvider);
      await DatabaseService().addMultipleMemories(
        coupleId: coupleId,
        imagesBase64: encodedImages,
        createdByName: myName.isEmpty ? 'Partnerin' : myName,
        commonDate: DateTime.now(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${files.length} fotoğraf ortak albümünüze başarıyla eklendi! 💕'),
            backgroundColor: LoveraColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yükleme sırasında hata: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0.0;
        });
      }
    }
  }

  /// Yeni Klasör Ekle Formu (Önce isim, hikaye, mekan ve tarih istenir, galeri açılmaz)
  Future<void> _openCreateFolderDialog() async {
    final coupleId = ref.read(coupleIdProvider);
    if (coupleId == null || coupleId.isEmpty) return;

    final titleController = TextEditingController();
    final descController = TextEditingController();
    final locationController = TextEditingController();
    DateTime albumDate = DateTime.now();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;

          return Container(
            padding: EdgeInsets.fromLTRB(22, 16, 22, MediaQuery.of(context).viewInsets.bottom + 24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E212B) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Yeni Klasör Ekle 📁',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Klasör bilgilerini belirleyin (Fotoğrafları klasörün içinden ekleyebilirsiniz):',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: LoveraColors.textMuted),
                  ),
                  const SizedBox(height: 18),
                  // Klasör İsmi
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: 'Klasör İsmi *',
                      hintText: 'Örn: Kapadokya Tatili, Yıldönümümüz',
                      prefixIcon: const Icon(Icons.folder_special_rounded, color: LoveraColors.primary),
                      filled: true,
                      fillColor: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Hikaye / Not (İsteğe bağlı)
                  TextField(
                    controller: descController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Hikaye / Açıklama (İsteğe bağlı)',
                      hintText: 'Bu tatil veya gün hakkında özel bir not...',
                      prefixIcon: const Icon(Icons.edit_note_rounded, color: LoveraColors.primary),
                      filled: true,
                      fillColor: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Mekan / Şehir (İsteğe bağlı)
                  TextField(
                    controller: locationController,
                    decoration: InputDecoration(
                      labelText: 'Mekan / Şehir (İsteğe bağlı)',
                      hintText: 'Örn: Nevşehir, Göreme',
                      prefixIcon: const Icon(Icons.location_on_rounded, color: LoveraColors.primary),
                      filled: true,
                      fillColor: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Tarih Seçici (İsteğe bağlı)
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: albumDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setDialogState(() => albumDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month_rounded, color: LoveraColors.primary, size: 20),
                          const SizedBox(width: 12),
                          Text(
                            'Tarih: ${albumDate.day}.${albumDate.month}.${albumDate.year}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          const Icon(Icons.edit_calendar_rounded, size: 18, color: LoveraColors.textMuted),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () async {
                      final title = titleController.text.trim();
                      if (title.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Lütfen klasör için bir isim girin!')),
                        );
                        return;
                      }

                      Navigator.pop(bCtx);
                      setState(() => _isUploading = true);

                      try {
                        final myName = ref.read(userNameProvider);
                        await DatabaseService().createMemoryAlbum(
                          coupleId: coupleId,
                          title: title,
                          description: descController.text,
                          locationTitle: locationController.text,
                          date: albumDate,
                          coverImageUrl: '',
                          createdByName: myName.isEmpty ? 'Partnerin' : myName,
                          photosBase64: [],
                        );

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('"$title" klasörü başarıyla oluşturuldu! 📁✨'),
                              backgroundColor: LoveraColors.primary,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Klasör oluşturulurken hata: $e')),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _isUploading = false);
                      }
                    },
                    child: const Text('Klasörü Oluştur', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Yeni Anı Grubu (Klasör) Oluşturma Formu (Fotoğraflar seçildikten sonra)
  Future<void> _openCreateAlbumDialog(List<XFile> files) async {
    final coupleId = ref.read(coupleIdProvider);
    if (coupleId == null || coupleId.isEmpty) return;

    final titleController = TextEditingController();
    final descController = TextEditingController();
    final locationController = TextEditingController();
    DateTime albumDate = DateTime.now();

    // İlk fotoğraftan varsa EXIF tarihini çekip varsayılan yap
    if (files.isNotEmpty) {
      final exif = await _extractOriginalDateFromImage(files.first);
      if (exif != null) albumDate = exif;
    }

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;

          return Container(
            padding: EdgeInsets.fromLTRB(22, 16, 22, MediaQuery.of(context).viewInsets.bottom + 24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E212B) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Yeni Klasör Ekle 📁',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Seçtiğiniz ${files.length} fotoğraf bu klasör altında toplanacak.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: LoveraColors.textMuted),
                  ),
                  const SizedBox(height: 18),
                  // Grup İsmi
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: 'Klasör İsmi *',
                      hintText: 'Örn: Kapadokya Tatili, Yıldönümü Yemeği',
                      prefixIcon: const Icon(Icons.folder_special_rounded, color: LoveraColors.primary),
                      filled: true,
                      fillColor: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Ortak Hikaye / Not
                  TextField(
                    controller: descController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Hikaye / Açıklama (İsteğe bağlı)',
                      hintText: 'Bu tatil / gün hakkında bir not...',
                      prefixIcon: const Icon(Icons.edit_note_rounded, color: LoveraColors.primary),
                      filled: true,
                      fillColor: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Mekan / Şehir
                  TextField(
                    controller: locationController,
                    decoration: InputDecoration(
                      labelText: 'Mekan / Şehir (İsteğe bağlı)',
                      hintText: 'Örn: Nevşehir, Göreme',
                      prefixIcon: const Icon(Icons.location_on_rounded, color: LoveraColors.primary),
                      filled: true,
                      fillColor: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Tarih Seçici
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: albumDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setDialogState(() => albumDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month_rounded, color: LoveraColors.primary, size: 20),
                          const SizedBox(width: 12),
                          Text(
                            'Tarih: ${albumDate.day}.${albumDate.month}.${albumDate.year}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          const Icon(Icons.edit_calendar_rounded, size: 18, color: LoveraColors.textMuted),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () async {
                      final title = titleController.text.trim();
                      if (title.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Lütfen klasör için bir isim girin!')),
                        );
                        return;
                      }

                      Navigator.pop(bCtx);
                      setState(() {
                        _isUploading = true;
                        _uploadProgress = 0.0;
                      });

                      try {
                        final List<String> encodedImages = [];
                        for (int i = 0; i < files.length; i++) {
                          final b64 = await _compressAndEncodeImage(files[i]);
                          encodedImages.add(b64);
                          if (mounted) {
                            setState(() => _uploadProgress = (i + 1) / files.length);
                          }
                        }

                        final myName = ref.read(userNameProvider);
                        final coverImg = encodedImages.isNotEmpty ? encodedImages.first : '';

                        await DatabaseService().createMemoryAlbum(
                          coupleId: coupleId,
                          title: title,
                          description: descController.text,
                          locationTitle: locationController.text,
                          date: albumDate,
                          coverImageUrl: coverImg,
                          createdByName: myName.isEmpty ? 'Partnerin' : myName,
                          photosBase64: encodedImages,
                        );

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('"$title" klasörü başarıyla oluşturuldu! ✨📁'),
                              backgroundColor: LoveraColors.primary,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Klasör oluşturulurken hata: $e')),
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() {
                            _isUploading = false;
                            _uploadProgress = 0.0;
                          });
                        }
                      }
                    },
                    child: const Text('Klasörü Oluştur ve Kaydet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Çoklu Seçim Modunda Seçilen Fotoğrafları Yeni Klasör Oluşturarak veya Mevcut Bir Klasöre Ekleme
  Future<void> _groupSelectedMemoriesDialog(List<MemoryItem> allMemories, List<MemoryAlbum> existingAlbums) async {
    final coupleId = ref.read(coupleIdProvider);
    if (coupleId == null || coupleId.isEmpty || _selectedMemoryIds.isEmpty) return;

    final selectedItems = allMemories.where((m) => _selectedMemoryIds.contains(m.id)).toList();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => Container(
        padding: EdgeInsets.fromLTRB(22, 16, 22, MediaQuery.of(context).viewInsets.bottom + 28),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E212B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${_selectedMemoryIds.length} Fotoğrafı Klasöre Ekle 📁',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Mevcut bir klasöre ekleyebilir veya yeni bir klasör oluşturabilirsiniz:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: LoveraColors.textMuted),
            ),
            const SizedBox(height: 20),
            // Seçenek 1: Yeni Klasör Oluştur
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              tileColor: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LoveraColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.create_new_folder_rounded, color: Colors.white, size: 20),
              ),
              title: const Text('Yeni Klasör Oluştur', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Seçilenlerle sıfırdan yeni anı grubu oluşturun', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded, color: LoveraColors.textMuted),
              onTap: () {
                Navigator.pop(bCtx);
                _showCreateFolderWithSelectedMemoriesDialog(selectedItems);
              },
            ),
            const SizedBox(height: 12),
            // Seçenek 2: Mevcut Klasöre Ekle
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              tileColor: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.folder_shared_rounded, color: Color(0xFF8B5CF6), size: 20),
              ),
              title: const Text('Mevcut Bir Klasöre Ekle', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                existingAlbums.isEmpty
                    ? 'Henüz oluşturulmuş klasörünüz yok'
                    : '${existingAlbums.length} mevcut klasörden birini seçin',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right_rounded, color: LoveraColors.textMuted),
              onTap: existingAlbums.isEmpty
                  ? null
                  : () {
                      Navigator.pop(bCtx);
                      _showChooseExistingFolderSheet(
                        existingAlbums: existingAlbums,
                        memoryIds: _selectedMemoryIds.toList(),
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }

  /// Seçili anılarla yeni klasör oluşturma diyaloğu
  Future<void> _showCreateFolderWithSelectedMemoriesDialog(List<MemoryItem> selectedItems) async {
    final coupleId = ref.read(coupleIdProvider);
    if (coupleId == null || coupleId.isEmpty || _selectedMemoryIds.isEmpty) return;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleController = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => Container(
        padding: EdgeInsets.fromLTRB(22, 16, 22, MediaQuery.of(context).viewInsets.bottom + 24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E212B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Yeni Klasör İsmi 📁',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Seçtiğiniz fotoğraflar bu yeni klasöre eklenecek:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: LoveraColors.textMuted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Klasör Adı',
                hintText: 'Örn: Roma Gezisi, Doğum Günü...',
                prefixIcon: const Icon(Icons.folder_special_rounded, color: LoveraColors.primary),
                filled: true,
                fillColor: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isEmpty) return;

                Navigator.pop(bCtx);
                setState(() => _isUploading = true);

                try {
                  final myName = ref.read(userNameProvider);
                  final firstMem = selectedItems.isNotEmpty ? selectedItems.first : null;

                  final albumId = await DatabaseService().createMemoryAlbum(
                    coupleId: coupleId,
                    title: title,
                    description: '',
                    locationTitle: firstMem?.locationTitle ?? '',
                    date: firstMem?.date ?? DateTime.now(),
                    coverImageUrl: firstMem?.imageUrl ?? '',
                    createdByName: myName.isEmpty ? 'Partnerin' : myName,
                    photosBase64: [],
                  );

                  await DatabaseService().groupExistingMemories(
                    coupleId: coupleId,
                    memoryIds: _selectedMemoryIds.toList(),
                    albumId: albumId,
                    albumTitle: title,
                  );

                  if (mounted) {
                    setState(() {
                      _isSelectionMode = false;
                      _selectedMemoryIds.clear();
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Fotoğraflar "$title" klasörüne taşındı! ✨')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Klasör oluşturma hatası: $e')),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isUploading = false);
                }
              },
              child: const Text('Klasörü Oluştur ve Fotoğrafları Ekle', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  /// Mevcut klasörlerden birini seçip fotoğrafları ekleme sheet'i (Tekli veya Çoklu seçim için kullanılabilir)
  Future<void> _showChooseExistingFolderSheet({
    required List<MemoryAlbum> existingAlbums,
    required List<String> memoryIds,
    VoidCallback? onSuccess,
  }) async {
    final coupleId = ref.read(coupleIdProvider);
    if (coupleId == null || coupleId.isEmpty || memoryIds.isEmpty) return;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E212B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Klasör Seçin 📁',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              '${memoryIds.length} fotoğraf hangi klasöre eklensin?',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: LoveraColors.textMuted),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: existingAlbums.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final album = existingAlbums[index];
                  return ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    tileColor: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: LoveraColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: album.coverImageUrl.isNotEmpty
                            ? _buildThumbnail(album.coverImageUrl)
                            : const Icon(Icons.folder_rounded, color: LoveraColors.primary),
                      ),
                    ),
                    title: Text(album.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${album.photoCount} fotoğraf • ${album.date.day}.${album.date.month}.${album.date.year}', style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.add_circle_outline_rounded, color: LoveraColors.primary),
                    onTap: () async {
                      Navigator.pop(bCtx);
                      setState(() => _isUploading = true);
                      try {
                        await DatabaseService().addMemoriesToExistingAlbum(
                          coupleId: coupleId,
                          memoryIds: memoryIds,
                          albumId: album.id,
                          albumTitle: album.title,
                        );
                        if (mounted) {
                          setState(() {
                            _isSelectionMode = false;
                            _selectedMemoryIds.clear();
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Fotoğraflar "${album.title}" klasörüne başarıyla eklendi! 💕'),
                              backgroundColor: LoveraColors.primary,
                            ),
                          );
                          onSuccess?.call();
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Klasöre ekleme hatası: $e')),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _isUploading = false);
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Seçili Anıları Toplu Silme Diyaloğu
  Future<void> _confirmDeleteSelectedMemories(List<MemoryItem> allMemories) async {
    final coupleId = ref.read(coupleIdProvider);
    if (coupleId == null || coupleId.isEmpty || _selectedMemoryIds.isEmpty) return;

    final count = _selectedMemoryIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text('$count Fotoğrafı Sil'),
        content: Text('Seçtiğiniz $count fotoğraf ortak albümünüzden kalıcı olarak silinecek. Bu işlemi onaylıyor musunuz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Tümünü Sil'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isUploading = true);
      try {
        await DatabaseService().deleteMultipleMemories(
          coupleId: coupleId,
          memoryIds: _selectedMemoryIds.toList(),
          allMemories: allMemories,
        );
        if (mounted) {
          setState(() {
            _isSelectionMode = false;
            _selectedMemoryIds.clear();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$count fotoğraf albümden silindi.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Silme işlemi başarısız: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
    }
  }

  /// Fotoğrafı telefona yüksek kalitede indirme (Gal paketi ile)
  Future<bool> _downloadMemoryToDevice(MemoryItem memory) async {
    debugPrint('[MemoriesGallery] Download button pressed for memory: ${memory.id}');
    try {
      Uint8List? bytes;

      if (memory.imageUrl.startsWith('data:image') || !memory.imageUrl.startsWith('http')) {
        bytes = _getOrDecodeBase64(memory.imageUrl);
      } else {
        // HTTP / Cloud Storage URL'si ise indir
        final res = await http.get(Uri.parse(memory.imageUrl)).timeout(const Duration(seconds: 20));
        if (res.statusCode == 200) {
          bytes = res.bodyBytes;
        }
      }

      if (bytes == null || bytes.isEmpty) {
        throw Exception('Görsel verisi çözülemedi.');
      }

      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final request = await Gal.requestAccess();
        if (!request) {
          return false;
        }
      }

      await Gal.putImageBytes(
        bytes,
        name: 'lovera_${DateTime.now().millisecondsSinceEpoch}',
      );

      HapticFeedback.mediumImpact();
      return true;
    } catch (e) {
      debugPrint('[MemoriesGallery] Download error: $e');
      return false;
    }
  }

  /// Fotoğrafı sohbete mesaj olarak gönderme
  Future<bool> _sendMemoryToChat(MemoryItem memory) async {
    debugPrint('[MemoriesGallery] Send to chat button pressed for memory: ${memory.id}');
    final coupleId = ref.read(coupleIdProvider);
    if (coupleId == null || coupleId.isEmpty) {
      return false;
    }

    try {
      final partnerUid = ref.read(partnerUidProvider) ?? ref.read(partnerProvider)?.id;
      final caption = memory.caption.isNotEmpty ? memory.caption : 'Anı albümünden bir hatıra 💕';

      final msgId = await DatabaseService().sendMessage(
        coupleId: coupleId,
        text: caption,
        mediaBase64: memory.imageUrl,
        type: 'image',
      );

      // Partner bildirimi
      if (partnerUid != null && partnerUid.isNotEmpty) {
        final myName = ref.read(userNameProvider);
        NotificationService().sendPushToPartner(
          partnerUid: partnerUid,
          title: myName.isNotEmpty ? myName : 'Partnerin',
          body: 'Albümden bir anı paylaştı 📸: $caption',
          data: {
            'type': 'chat_message',
            'coupleId': coupleId,
            if (msgId != null) 'messageId': msgId,
          },
        );
      }

      HapticFeedback.mediumImpact();
      return true;
    } catch (e) {
      debugPrint('[MemoriesGallery] Send to chat error: $e');
      return false;
    }
  }

  /// Fotoğraf Detayı ve Bireysel Düzenleme Penceresi
  void _showMemoryDetail(MemoryItem memory) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final myUid = DatabaseService().uid;
    final coupleId = ref.read(coupleIdProvider) ?? '';

    bool isSendingToChat = false;
    bool isSentToChat = false;
    bool isDownloading = false;
    bool isDownloaded = false;
    String? inlineBannerText;
    Color inlineBannerColor = LoveraColors.primary;
    IconData inlineBannerIcon = Icons.check_circle_rounded;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDetailState) {
          final currentlyLiked = memory.likedBy.contains(myUid);
          return Container(
            height: MediaQuery.of(context).size.height * 0.90,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161922) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 30,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: Column(
              children: [
                // Başlık & Kapatma Barı
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 14, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.favorite_rounded, color: LoveraColors.primary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '${memory.date.day}.${memory.date.month}.${memory.date.year}',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          if (memory.albumTitle != null && memory.albumTitle!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: LoveraColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '📁 ${memory.albumTitle}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: LoveraColors.primary),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Row(
                        children: [
                          // Bilgileri Düzenle (Tarih, Not, Mekan)
                          IconButton(
                            icon: const Icon(Icons.edit_note_rounded, color: LoveraColors.primary),
                            tooltip: 'Bilgileri Düzenle',
                            onPressed: () {
                              Navigator.pop(ctx);
                              _editMemoryDialog(memory);
                            },
                          ),
                          // Silme Butonu
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (dCtx) => AlertDialog(
                                  title: const Text('Anıyı Sil'),
                                  content: const Text('Bu fotoğraf ortak anı albümünüzden kalıcı olarak silinecek. Emin misiniz?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Vazgeç')),
                                    FilledButton(
                                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                                      onPressed: () => Navigator.pop(dCtx, true),
                                      child: const Text('Sil'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                Navigator.pop(ctx);
                                await DatabaseService().deleteMemory(
                                  coupleId: coupleId,
                                  memoryId: memory.id,
                                  albumId: memory.albumId,
                                );
                                if (mounted) {
                                  ScaffoldMessenger.of(this.context).showSnackBar(
                                    const SnackBar(content: Text('Anı albümden silindi.')),
                                  );
                                }
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Fotoğraf Alanı
                Expanded(
                  child: InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 3.5,
                    child: Center(
                      child: _buildMemoryImage(memory.imageUrl),
                    ),
                  ),
                ),
                // Detay Bilgileri & Not
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E212B) : LoveraColors.lightSurfaceAlt,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Modal İçi Anlık Durum Bildirimi (SnackBar modalın arkasında kaldığı için doğrudan burada gösterilir)
                        if (inlineBannerText != null) ...[
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: inlineBannerColor,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: inlineBannerColor.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(inlineBannerIcon, color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    inlineBannerText!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (memory.caption.isNotEmpty) ...[
                          Text(
                            memory.caption,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          children: [
                            if (memory.locationTitle.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: LoveraColors.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.location_on_rounded, size: 14, color: LoveraColors.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      memory.locationTitle,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: LoveraColors.primary),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              'Ekleyen: ${memory.createdByName}',
                              style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: () async {
                                HapticFeedback.mediumImpact();
                                final newStatus = !currentlyLiked;
                                setDetailState(() {
                                  if (newStatus) {
                                    memory.likedBy.add(myUid!);
                                  } else {
                                    memory.likedBy.remove(myUid);
                                  }
                                });
                                await DatabaseService().toggleMemoryLike(
                                  coupleId: coupleId,
                                  memoryId: memory.id,
                                  isLiked: !newStatus,
                                );
                              },
                              icon: Icon(
                                currentlyLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                color: currentlyLiked ? LoveraColors.primary : LoveraColors.textMuted,
                                size: 28,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Aksiyon Butonları (Sohbete Gönder, Telefona İndir, Klasöre Ekle)
                        Row(
                          children: [
                            // 1. Sohbete Gönder
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: isSentToChat
                                      ? LoveraColors.primary.withValues(alpha: 0.18)
                                      : null,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  side: BorderSide(
                                    color: isSentToChat
                                        ? LoveraColors.primary
                                        : LoveraColors.primary.withValues(alpha: 0.35),
                                    width: isSentToChat ? 1.6 : 1.0,
                                  ),
                                ),
                                icon: isSendingToChat
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: LoveraColors.primary),
                                      )
                                    : Icon(
                                        isSentToChat ? Icons.check_circle_rounded : Icons.send_rounded,
                                        size: 18,
                                        color: LoveraColors.primary,
                                      ),
                                label: Text(
                                  isSendingToChat
                                      ? 'Atılıyor...'
                                      : (isSentToChat ? 'Sohbete Atıldı' : 'Sohbete At'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                    color: LoveraColors.primary,
                                  ),
                                ),
                                onPressed: isSendingToChat
                                    ? null
                                    : () async {
                                        HapticFeedback.selectionClick();
                                        setDetailState(() {
                                          isSendingToChat = true;
                                          inlineBannerText = 'Sohbete gönderiliyor...';
                                          inlineBannerColor = LoveraColors.primary;
                                          inlineBannerIcon = Icons.hourglass_top_rounded;
                                        });
                                        final ok = await _sendMemoryToChat(memory);
                                        if (ctx.mounted) {
                                          setDetailState(() {
                                            isSendingToChat = false;
                                            isSentToChat = ok;
                                            inlineBannerText = ok
                                                ? 'Sohbete atıldı 💕'
                                                : 'Sohbete gönderilemedi!';
                                            inlineBannerColor = ok
                                                ? LoveraColors.primary
                                                : const Color(0xFFEF4444);
                                            inlineBannerIcon = ok
                                                ? Icons.mark_chat_read_rounded
                                                : Icons.error_outline_rounded;
                                          });
                                        }
                                      },
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 2. Telefona Yüksek Kalitede İndir
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: isDownloaded
                                      ? const Color(0xFF10B981).withValues(alpha: 0.18)
                                      : null,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  side: BorderSide(
                                    color: isDownloaded
                                        ? const Color(0xFF10B981)
                                        : Colors.blue.withValues(alpha: 0.35),
                                    width: isDownloaded ? 1.6 : 1.0,
                                  ),
                                ),
                                icon: isDownloading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
                                      )
                                    : Icon(
                                        isDownloaded ? Icons.check_circle_rounded : Icons.download_rounded,
                                        size: 18,
                                        color: isDownloaded ? const Color(0xFF10B981) : Colors.blue,
                                      ),
                                label: Text(
                                  isDownloading
                                      ? 'İndiriliyor...'
                                      : (isDownloaded ? 'İndirildi ✓' : 'İndir'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                    color: isDownloaded ? const Color(0xFF10B981) : Colors.blue,
                                  ),
                                ),
                                onPressed: isDownloading
                                    ? null
                                    : () async {
                                        HapticFeedback.selectionClick();
                                        setDetailState(() {
                                          isDownloading = true;
                                          inlineBannerText = 'Fotoğraf telefona indiriliyor...';
                                          inlineBannerColor = Colors.blue;
                                          inlineBannerIcon = Icons.downloading_rounded;
                                        });
                                        final ok = await _downloadMemoryToDevice(memory);
                                        if (ctx.mounted) {
                                          setDetailState(() {
                                            isDownloading = false;
                                            isDownloaded = ok;
                                            inlineBannerText = ok
                                                ? 'Fotoğraf galeriye kaydedildi! 📲✨'
                                                : 'Fotoğraf kaydedilemedi (İzin kontrol edin)';
                                            inlineBannerColor = ok
                                                ? const Color(0xFF10B981)
                                                : const Color(0xFFEF4444);
                                            inlineBannerIcon = ok
                                                ? Icons.check_circle_rounded
                                                : Icons.error_outline_rounded;
                                          });
                                        }
                                      },
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 3. Tekli Olarak Klasöre Gönder
                            Expanded(
                              child: Consumer(
                                builder: (context, ref, _) {
                                  final albumsAsync = coupleId.isNotEmpty
                                      ? ref.watch(albumsStreamProvider(coupleId))
                                      : const AsyncValue<List<MemoryAlbum>>.data([]);
                                  final existingAlbums = albumsAsync.value ?? [];

                                  return OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      side: BorderSide(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
                                    ),
                                    icon: const Icon(Icons.folder_open_rounded, size: 18, color: Color(0xFF8B5CF6)),
                                    label: const Text('Klasöre', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF8B5CF6))),
                                    onPressed: () {
                                      _showChooseExistingFolderSheet(
                                        existingAlbums: existingAlbums,
                                        memoryIds: [memory.id],
                                        onSuccess: () {
                                          Navigator.pop(ctx);
                                        },
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Tek Anıyı Düzenleme Diyaloğu (Tarih, Konum, Hikaye)
  Future<void> _editMemoryDialog(MemoryItem memory) async {
    final coupleId = ref.read(coupleIdProvider) ?? '';
    final captionController = TextEditingController(text: memory.caption);
    final locationController = TextEditingController(text: memory.locationTitle);
    DateTime editDate = memory.date;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => StatefulBuilder(
        builder: (context, setEditState) {
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;

          return Container(
            padding: EdgeInsets.fromLTRB(22, 16, 22, MediaQuery.of(context).viewInsets.bottom + 24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E212B) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Anı Bilgilerini Düzenle ✏️',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: captionController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Anının Hikayesi / Notu',
                    filled: true,
                    fillColor: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: locationController,
                  decoration: InputDecoration(
                    labelText: 'Mekan / Şehir',
                    prefixIcon: const Icon(Icons.location_on_rounded, color: LoveraColors.primary),
                    filled: true,
                    fillColor: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: editDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setEditState(() => editDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month_rounded, color: LoveraColors.primary, size: 20),
                        const SizedBox(width: 12),
                        Text('Tarih: ${editDate.day}.${editDate.month}.${editDate.year}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        const Icon(Icons.edit_calendar_rounded, size: 18, color: LoveraColors.textMuted),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: () async {
                    Navigator.pop(bCtx);
                    await DatabaseService().updateMemoryDetails(
                      coupleId: coupleId,
                      memoryId: memory.id,
                      caption: captionController.text,
                      locationTitle: locationController.text,
                      date: editDate,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Anı bilgileri güncellendi! ✨')),
                      );
                    }
                  },
                  child: const Text('Değişiklikleri Kaydet', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Anı Grubu (Klasör) Tıklandığında Açılan İçerik Görünümü
  void _openAlbumDetail(MemoryAlbum album, List<MemoryItem> _) {
    final theme = Theme.of(context);
    final coupleId = ref.read(coupleIdProvider) ?? '';
    final isDark = theme.brightness == Brightness.dark;

    final selectedInAlbum = <String>{};
    bool isAlbumSelectionMode = false;

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (detailCtx) => StatefulBuilder(
          builder: (context, setDetailState) {
            return Scaffold(
              appBar: AppBar(
                title: isAlbumSelectionMode
                    ? Text('${selectedInAlbum.length} Seçildi')
                    : Text(album.title),
                leading: isAlbumSelectionMode
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          setDetailState(() {
                            isAlbumSelectionMode = false;
                            selectedInAlbum.clear();
                          });
                        },
                      )
                    : null,
                actions: [
                  if (isAlbumSelectionMode) ...[
                    IconButton(
                      tooltip: 'Seçilenleri Sil',
                      icon: const Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444)),
                      onPressed: selectedInAlbum.isEmpty
                          ? null
                          : () async {
                              final allItems = ref.read(memoriesStreamProvider(coupleId)).value ?? [];
                              final selectedItems = allItems.where((m) => selectedInAlbum.contains(m.id)).toList();
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (dCtx) => AlertDialog(
                                  title: const Text('Fotoğrafları Sil'),
                                  content: Text(
                                    'Seçtiğiniz ${selectedItems.length} adet fotoğrafı silmek istediğinize emin misiniz?',
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Vazgeç')),
                                    FilledButton(
                                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                                      onPressed: () => Navigator.pop(dCtx, true),
                                      child: const Text('Sil'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                final idsToDelete = List<String>.from(selectedInAlbum);
                                setDetailState(() {
                                  selectedInAlbum.clear();
                                  isAlbumSelectionMode = false;
                                });
                                await DatabaseService().deleteMultipleMemories(
                                  coupleId: coupleId,
                                  memoryIds: idsToDelete,
                                  allMemories: allItems,
                                );
                              }
                            },
                    ),
                  ] else ...[
                    IconButton(
                      tooltip: 'Çoklu Seç / Düzenle',
                      icon: const Icon(Icons.checklist_rounded),
                      onPressed: () {
                        setDetailState(() => isAlbumSelectionMode = true);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                      tooltip: 'Klasörü Sil',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (dCtx) => AlertDialog(
                            title: const Text('Klasörü Sil'),
                            content: const Text(
                              'Bu klasörü sildiğinizde içindeki fotoğraflar albümünüzden silinmez, yalnızca klasör bağı kaldırılır. Onaylıyor musunuz?',
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Vazgeç')),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                                onPressed: () => Navigator.pop(dCtx, true),
                                child: const Text('Klasörü Kaldır'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          Navigator.pop(context); // Detail sayfasından çık
                          await DatabaseService().deleteMemoryAlbum(coupleId: coupleId, albumId: album.id);
                        }
                      },
                    ),
                  ],
                ],
              ),
              bottomNavigationBar: null,
              body: LoveraThemeBackground(
                child: Consumer(
                  builder: (context, ref, _) {
                    final allItems = ref.watch(memoriesStreamProvider(coupleId)).value ?? [];
                    final albumMemories = allItems.where((m) => m.albumId == album.id).toList();

                    return CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (album.description.isNotEmpty) ...[
                                  Text(
                                    album.description,
                                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600, height: 1.4),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                Row(
                                  children: [
                                    if (album.locationTitle.isNotEmpty) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: LoveraColors.primary.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.location_on_rounded, size: 14, color: LoveraColors.primary),
                                            const SizedBox(width: 4),
                                            Text(
                                              album.locationTitle,
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: LoveraColors.primary),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                    ],
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.calendar_month_rounded, size: 14, color: LoveraColors.textMuted),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${album.date.day}.${album.date.month}.${album.date.year}',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '${albumMemories.length} Fotoğraf',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (albumMemories.isEmpty)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Text('Bu klasörde henüz fotoğraf yok.', style: TextStyle(color: LoveraColors.textMuted)),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                            sliver: SliverGrid(
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 6,
                                mainAxisSpacing: 6,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final item = albumMemories[index];
                                  final isSelected = selectedInAlbum.contains(item.id);

                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      if (isAlbumSelectionMode) {
                                        HapticFeedback.selectionClick();
                                        setDetailState(() {
                                          if (isSelected) {
                                            selectedInAlbum.remove(item.id);
                                            if (selectedInAlbum.isEmpty) {
                                              isAlbumSelectionMode = false;
                                            }
                                          } else {
                                            selectedInAlbum.add(item.id);
                                          }
                                        });
                                      } else {
                                        _showMemoryDetail(item);
                                      }
                                    },
                                    onLongPress: () {
                                      HapticFeedback.mediumImpact();
                                      setDetailState(() {
                                        isAlbumSelectionMode = true;
                                        if (isSelected) {
                                          selectedInAlbum.remove(item.id);
                                          if (selectedInAlbum.isEmpty) {
                                            isAlbumSelectionMode = false;
                                          }
                                        } else {
                                          selectedInAlbum.add(item.id);
                                        }
                                      });
                                    },
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          _buildThumbnail(item.imageUrl),
                                          if (isSelected)
                                            Container(
                                              color: LoveraColors.primary.withValues(alpha: 0.3),
                                            ),
                                          if (isAlbumSelectionMode)
                                            Positioned(
                                              top: 6,
                                              right: 6,
                                              child: Container(
                                                padding: const EdgeInsets.all(3),
                                                decoration: BoxDecoration(
                                                  color: isSelected ? LoveraColors.primary : Colors.black.withValues(alpha: 0.45),
                                                  shape: BoxShape.circle,
                                                  border: Border.all(color: Colors.white, width: 2),
                                                ),
                                                child: Icon(
                                                  isSelected ? Icons.check_rounded : null,
                                                  color: Colors.white,
                                                  size: 14,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                childCount: albumMemories.length,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () {
                // Klasör içinde "Yeni Anı Ekle" veya "Yeni Klasör Ekle" seçenekleri
                showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (sheetCtx) {
                    final isDark = Theme.of(context).brightness == Brightness.dark;
                    return Container(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E212B) : Colors.white,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            '"${album.title}" Klasörü',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                          ),
                          const SizedBox(height: 18),
                          ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            tileColor: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: LoveraColors.primary.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.add_photo_alternate_rounded, color: LoveraColors.primary),
                            ),
                            title: const Text('Bu Klasöre Fotoğraf Ekle 📸', style: TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: const Text('Klasörün içine yeni fotoğraflar yükleyin', style: TextStyle(fontSize: 12)),
                            onTap: () async {
                              Navigator.pop(sheetCtx);
                              final pickedFiles = await _picker.pickMultiImage(
                                maxWidth: 1280,
                                maxHeight: 1280,
                                imageQuality: 70,
                              );
                              if (pickedFiles.isNotEmpty && mounted) {
                                setState(() {
                                  _isUploading = true;
                                  _uploadProgress = 0.0;
                                });
                                try {
                                  final List<String> encodedImages = [];
                                  for (int i = 0; i < pickedFiles.length; i++) {
                                    final b64 = await _compressAndEncodeImage(pickedFiles[i]);
                                    encodedImages.add(b64);
                                    if (mounted) setState(() => _uploadProgress = (i + 1) / pickedFiles.length);
                                  }
                                  final myName = ref.read(userNameProvider);
                                  await DatabaseService().addMultipleMemories(
                                    coupleId: coupleId,
                                    imagesBase64: encodedImages,
                                    createdByName: myName.isEmpty ? 'Partnerin' : myName,
                                    albumId: album.id,
                                    albumTitle: album.title,
                                    caption: album.description,
                                    locationTitle: album.locationTitle,
                                    commonDate: album.date,
                                  );
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('${encodedImages.length} fotoğraf "${album.title}" klasörüne eklendi! 💕')),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Yükleme hatası: $e')),
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() {
                                      _isUploading = false;
                                      _uploadProgress = 0.0;
                                    });
                                  }
                                }
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            tileColor: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                gradient: LoveraColors.primaryGradient,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.create_new_folder_rounded, color: Colors.white),
                            ),
                            title: const Text('Yeni Klasör Ekle 📁', style: TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: const Text('Yeni bir anı klasörü oluşturun', style: TextStyle(fontSize: 12)),
                            onTap: () {
                              Navigator.pop(sheetCtx);
                              _openCreateFolderDialog();
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
              backgroundColor: LoveraColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ekle', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          );
        },
      ),
    ),
  );
}

  static final Map<String, Uint8List> _base64Cache = <String, Uint8List>{};

  static Uint8List? _getOrDecodeBase64(String imgUrl) {
    if (imgUrl.isEmpty) return null;
    final cached = _base64Cache[imgUrl];
    if (cached != null) return cached;
    try {
      final clean = imgUrl.startsWith('data:image') ? imgUrl.split(',').last : imgUrl;
      final bytes = base64Decode(clean);
      if (_base64Cache.length > 200) {
        _base64Cache.remove(_base64Cache.keys.first);
      }
      _base64Cache[imgUrl] = bytes;
      return bytes;
    } catch (e) {
      debugPrint('[MemoriesGallery] base64 decode error: $e');
      return null;
    }
  }

  Widget _buildMemoryImage(String imgUrl) {
    if (imgUrl.isEmpty) {
      return const Center(child: Icon(Icons.broken_image_rounded, size: 48));
    }
    if (imgUrl.startsWith('data:image')) {
      final bytes = _getOrDecodeBase64(imgUrl);
      if (bytes == null) {
        return const Center(child: Icon(Icons.broken_image_rounded, size: 48));
      }
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded, size: 48)),
      );
    }
    return Image.network(
      imgUrl,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded, size: 48)),
    );
  }

  Widget _buildThumbnail(String imgUrl) {
    if (imgUrl.isEmpty) {
      return Container(
        color: Colors.grey.withValues(alpha: 0.1),
        child: const Icon(Icons.photo_outlined, color: LoveraColors.textMuted, size: 24),
      );
    }
    if (imgUrl.startsWith('data:image')) {
      final bytes = _getOrDecodeBase64(imgUrl);
      if (bytes == null) {
        return Container(
          color: Colors.grey.withValues(alpha: 0.1),
          child: const Icon(Icons.broken_image_rounded, color: LoveraColors.textMuted, size: 24),
        );
      }
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        cacheWidth: 360,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded, size: 24)),
      );
    }
    return Image.network(
      imgUrl,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      cacheWidth: 360,
      filterQuality: FilterQuality.low,
      errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded, size: 24)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final coupleId = ref.watch(coupleIdProvider) ?? '';

    final memoriesAsync = coupleId.isNotEmpty
        ? ref.watch(memoriesStreamProvider(coupleId))
        : const AsyncValue<List<MemoryItem>>.data([]);
    final albumsAsync = coupleId.isNotEmpty
        ? ref.watch(albumsStreamProvider(coupleId))
        : const AsyncValue<List<MemoryAlbum>>.data([]);

    final memories = memoriesAsync.value ?? [];
    final albums = albumsAsync.value ?? [];

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isSelectionMode) {
          setState(() {
            _isSelectionMode = false;
            _selectedMemoryIds.clear();
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: _isSelectionMode
              ? Text('${_selectedMemoryIds.length} Seçildi')
              : const Text('Ortak Anı Albümü'),
          leading: _isSelectionMode
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    setState(() {
                      _isSelectionMode = false;
                      _selectedMemoryIds.clear();
                    });
                  },
                )
              : null,
          bottom: TabBar(
            controller: _tabController,
            labelColor: LoveraColors.primary,
            unselectedLabelColor: LoveraColors.textMuted,
            indicatorColor: LoveraColors.primary,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.photo_library_rounded, size: 20), text: 'Tüm Anılar'),
            Tab(icon: Icon(Icons.folder_special_rounded, size: 20), text: 'Anı Grupları (Klasörler)'),
          ],
        ),
        actions: [
          if (_isSelectionMode) ...[
            // Seçilenleri Klasöre Ekle
            IconButton(
              tooltip: 'Klasöre Ekle',
              icon: const Icon(Icons.drive_file_move_rounded, color: LoveraColors.primary),
              onPressed: _selectedMemoryIds.isEmpty
                  ? null
                  : () {
                      _groupSelectedMemoriesDialog(memories, albums);
                    },
            ),
            // Seçilenleri Toplu Sil
            IconButton(
              tooltip: 'Seçilenleri Sil',
              icon: const Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444)),
              onPressed: _selectedMemoryIds.isEmpty
                  ? null
                  : () {
                      _confirmDeleteSelectedMemories(memories);
                    },
            ),
          ] else ...[
            // Çoklu Seçim Modunu Açma Butonu
            IconButton(
              tooltip: 'Çoklu Seç / Düzenle',
              icon: const Icon(Icons.checklist_rounded),
              onPressed: () {
                setState(() => _isSelectionMode = true);
              },
            ),
            // Galeri Izgara / Zaman Tüneli Geçiş Butonu
            IconButton(
              tooltip: _isGridView ? 'Zaman Tüneli Görünümü' : 'Izgara Galeri Görünümü',
              icon: Icon(_isGridView ? Icons.view_timeline_rounded : Icons.grid_view_rounded),
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() => _isGridView = !_isGridView);
              },
            ),
          ],
          const SizedBox(width: 6),
        ],
      ),
      bottomNavigationBar: null,
      floatingActionButton: _isSelectionMode
          ? null
          : AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) {
                final isFolderTab = _tabController.index == 1;
                return isFolderTab
                    ? FloatingActionButton.extended(
                        onPressed: _openCreateFolderDialog,
                        backgroundColor: LoveraColors.primary,
                        foregroundColor: Colors.white,
                        icon: const Icon(Icons.create_new_folder_rounded),
                        label: const Text('Yeni Klasör Ekle', style: TextStyle(fontWeight: FontWeight.w700)),
                      )
                    : FloatingActionButton.extended(
                        onPressed: _showAddActionSheet,
                        backgroundColor: LoveraColors.primary,
                        foregroundColor: Colors.white,
                        icon: const Icon(Icons.add_photo_alternate_rounded),
                        label: const Text('Anı Ekle', style: TextStyle(fontWeight: FontWeight.w700)),
                      );
              },
            ),
      body: Stack(
        children: [
          LoveraThemeBackground(
            child: coupleId.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: LoveraColors.primary.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.favorite_border_rounded, size: 40, color: LoveraColors.primary),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Henüz Eşleşmediniz',
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ortak anı albümünüzü kullanabilmek için önce partnerinizle eşleşmeniz gerekir.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(color: LoveraColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    physics: _isSelectionMode
                        ? const NeverScrollableScrollPhysics()
                        : const PageScrollPhysics(),
                    children: [
                      // TAB 1: TÜM ANILAR (Klasik Galeri & Zaman Tüneli)
                      _KeepAliveTab(
                        child: memoriesAsync.isLoading && !memoriesAsync.hasValue
                            ? const Center(child: CircularProgressIndicator(color: LoveraColors.primary))
                            : (memories.isEmpty
                                ? _buildEmptyMemoriesView(theme)
                                : (_isGridView ? _buildGridView(memories) : _buildTimelineView(memories))),
                      ),
                      // TAB 2: ANI GRUPLARI / KLASÖRLER
                      _KeepAliveTab(
                        child: (albumsAsync.isLoading && !albumsAsync.hasValue) ||
                                (memoriesAsync.isLoading && !memoriesAsync.hasValue)
                            ? const Center(child: CircularProgressIndicator(color: LoveraColors.primary))
                            : (albums.isEmpty
                                ? _buildEmptyAlbumsView(theme)
                                : _buildAlbumsGridView(albums, memories)),
                      ),
                    ],
                  ),
          ),
          // Yükleme Animasyonu / Overlay
          if (_isUploading)
            Container(
              color: Colors.black.withValues(alpha: 0.55),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(28),
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E212B) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 30),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: LoveraColors.primary),
                      const SizedBox(height: 20),
                      const Text(
                        'Fotoğraflar Yükleniyor...',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      if (_uploadProgress > 0.0) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: _uploadProgress,
                          backgroundColor: Colors.grey.withValues(alpha: 0.2),
                          color: LoveraColors.primary,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '%${(_uploadProgress * 100).toInt()} Tamamlandı',
                          style: const TextStyle(fontSize: 12, color: LoveraColors.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

  // Izgara Galeri Görünümü
  Widget _buildGridView(List<MemoryItem> memories) {
    return GridView.builder(
      key: const PageStorageKey('memories_gallery_grid_view'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1.0,
      ),
      itemCount: memories.length,
      itemBuilder: (context, index) {
        final item = memories[index];
        final isSelected = _selectedMemoryIds.contains(item.id);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_isSelectionMode) {
              HapticFeedback.selectionClick();
              setState(() {
                if (isSelected) {
                  _selectedMemoryIds.remove(item.id);
                  if (_selectedMemoryIds.isEmpty) {
                    _isSelectionMode = false;
                  }
                } else {
                  _selectedMemoryIds.add(item.id);
                }
              });
            } else {
              _showMemoryDetail(item);
            }
          },
          onLongPress: () {
            HapticFeedback.mediumImpact();
            setState(() {
              _isSelectionMode = true;
              if (isSelected) {
                _selectedMemoryIds.remove(item.id);
                if (_selectedMemoryIds.isEmpty) {
                  _isSelectionMode = false;
                }
              } else {
                _selectedMemoryIds.add(item.id);
              }
            });
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildThumbnail(item.imageUrl),
                if (isSelected)
                  Container(
                    color: LoveraColors.primary.withValues(alpha: 0.3),
                  ),
                if (item.likedBy.isNotEmpty && !_isSelectionMode)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.favorite_rounded, color: Color(0xFFEF4444), size: 12),
                    ),
                  ),
                // Çoklu seçim kutucuğu
                if (_isSelectionMode)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: isSelected ? LoveraColors.primary : Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Icon(
                        isSelected ? Icons.check_rounded : null,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Zaman Tüneli (Timeline) Görünümü
  Widget _buildTimelineView(List<MemoryItem> memories) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final myUid = DatabaseService().uid;
    final coupleId = ref.read(coupleIdProvider) ?? '';

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      itemCount: memories.length,
      itemBuilder: (context, index) {
        final item = memories[index];
        final isLiked = item.likedBy.contains(myUid);

        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: theme.dividerColor),
            boxShadow: AppTheme.ambientShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: LoveraColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.calendar_month_rounded, color: LoveraColors.primary, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.date.day}.${item.date.month}.${item.date.year}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                        if (item.locationTitle.isNotEmpty)
                          Row(
                            children: [
                              const Icon(Icons.location_on_rounded, size: 12, color: LoveraColors.textMuted),
                              const SizedBox(width: 2),
                              Text(
                                item.locationTitle,
                                style: const TextStyle(fontSize: 12, color: LoveraColors.textMuted, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        item.createdByName,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: LoveraColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _showMemoryDetail(item),
                child: AspectRatio(
                  aspectRatio: 1.1,
                  child: _buildThumbnail(item.imageUrl),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: item.caption.isNotEmpty
                          ? Text(
                              item.caption,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            )
                          : Text(
                              'Özel bir hatıra 💕',
                              style: TextStyle(fontStyle: FontStyle.italic, color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted),
                            ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () async {
                        HapticFeedback.lightImpact();
                        await DatabaseService().toggleMemoryLike(
                          coupleId: coupleId,
                          memoryId: item.id,
                          isLiked: isLiked,
                        );
                      },
                      icon: Icon(
                        isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: isLiked ? const Color(0xFFEF4444) : LoveraColors.textMuted,
                        size: 26,
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
  }

  // Anı Grupları (Klasörler) Görünümü
  Widget _buildAlbumsGridView(List<MemoryAlbum> albums, List<MemoryItem> allMemories) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 16,
        childAspectRatio: 0.82,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        final count = allMemories.where((m) => m.albumId == album.id).length;

        return GestureDetector(
          onTap: () => _openAlbumDetail(album, allMemories),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.dividerColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        album.coverImageUrl.isNotEmpty
                            ? _buildThumbnail(album.coverImageUrl)
                            : Container(
                                color: LoveraColors.primary.withValues(alpha: 0.1),
                                child: const Icon(Icons.folder_special_rounded, size: 48, color: LoveraColors.primary),
                              ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.photo_library_rounded, size: 12, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  '$count',
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${album.date.day}.${album.date.month}.${album.date.year}',
                        style: const TextStyle(fontSize: 11, color: LoveraColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyMemoriesView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                gradient: LoveraColors.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: LoveraColors.primary.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.photo_library_rounded, size: 44, color: Colors.white),
            ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 24),
            Text(
              'Henüz Bir Anı Eklenmedi',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              'Birlikte çekildiğiniz fotoğrafları tekli veya toplu olarak "Anı Ekle" butonundan albümünüze yükleyin! ✨',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: LoveraColors.textMuted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyAlbumsView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: LoveraColors.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.folder_special_rounded, size: 40, color: LoveraColors.primary),
            ),
            const SizedBox(height: 20),
            Text(
              'Henüz Bir Anı Grubu Yok',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Birlikte olduğunuz özel anları (tatil, gezi, buluşma) düzenlemek için hemen yeni bir klasör oluşturun! 📁💕',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: LoveraColors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.create_new_folder_rounded, size: 20),
              label: const Text('Yeni Klasör Ekle ✨', style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: _openCreateFolderDialog,
            ),
          ],
        ),
      ),
    );
  }
}

class _KeepAliveTab extends StatefulWidget {
  final Widget child;
  const _KeepAliveTab({required this.child});

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
