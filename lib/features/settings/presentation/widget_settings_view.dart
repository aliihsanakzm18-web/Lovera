import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/widget_sync_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../drawing/presentation/drawing_screen.dart';

class WidgetSettingsView extends ConsumerStatefulWidget {
  const WidgetSettingsView({super.key});

  @override
  ConsumerState<WidgetSettingsView> createState() => _WidgetSettingsViewState();
}

class _WidgetSettingsViewState extends ConsumerState<WidgetSettingsView> {
  String? _savedImagePath;
  int? _lastUpdated;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedImage();
  }

  Future<void> _loadSavedImage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString('widget_custom_bg_path');
      if (path != null && path.isNotEmpty && File(path).existsSync()) {
        setState(() {
          _savedImagePath = path;
          _lastUpdated = DateTime.now().millisecondsSinceEpoch;
          _isLoading = false;
        });
      } else {
        setState(() {
          _savedImagePath = null;
          _isLoading = false;
        });
      }
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    HapticFeedback.lightImpact();
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1080,
    );

    if (pickedFile == null) return;

    try {
      setState(() => _isLoading = true);
      final appDir = await getApplicationDocumentsDirectory();
      final targetPath = '${appDir.path}/widget_bg_custom.jpg';

      final targetFile = File(targetPath);
      if (targetFile.existsSync()) {
        targetFile.deleteSync();
      }
      await File(pickedFile.path).copy(targetPath);

      // Flutter image cache'ini temizle ki eski görsel yerine yenisi hemen görünsün
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await FileImage(File(targetPath)).evict();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('widget_custom_bg_path', targetPath);

      // Widget'a senkronize et
      await WidgetSyncService.setWidgetBackgroundImage(targetPath);

      setState(() {
        _savedImagePath = targetPath;
        _lastUpdated = DateTime.now().millisecondsSinceEpoch;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Widget arka plan fotoğrafı güncellendi! 💕'),
            backgroundColor: LoveraColors.secondary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fotoğraf eklenirken bir hata oluştu: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _removeImage() async {
    HapticFeedback.lightImpact();
    try {
      setState(() => _isLoading = true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('widget_custom_bg_path');

      if (_savedImagePath != null) {
        final f = File(_savedImagePath!);
        if (f.existsSync()) f.deleteSync();
      }

      await WidgetSyncService.removeWidgetBackgroundImage();

      setState(() {
        _savedImagePath = null;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Widget varsayılan Lovera temasına döndürüldü.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final partner = ref.watch(partnerProvider);
    final partnerName = partner?.name.isNotEmpty == true ? partner!.name : 'Eda';
    final batteryText = partner?.batteryLevel != null ? '%${partner!.batteryLevel}' : '%78';
    const daysCount = '868';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Widget Ayarları'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // Başlık Bilgi Metni
                Text(
                  'Ana Ekran Widget Görünümü',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Widget arkasına sevgilinizle olan özel bir anınızı ekleyin. Yazıların ve sayaçların net okunabilmesi için kenarlardan ortaya doğru sinematik karanlık vignette efekti otomatik olarak uygulanır.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),

                // Canlı Widget Önizleme Kartı (Simülasyon)
                Center(
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                        if (isDark)
                          BoxShadow(
                            color: LoveraColors.primary.withValues(alpha: 0.2),
                            blurRadius: 25,
                            spreadRadius: -2,
                          ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(26),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // 1. Arka Plan: Seçilen Fotoğraf VEYA Varsayılan Degrade
                          if (_savedImagePath != null && File(_savedImagePath!).existsSync())
                            Image.file(
                              File(_savedImagePath!),
                              key: ValueKey(_savedImagePath! + (_lastUpdated?.toString() ?? '')),
                              fit: BoxFit.cover,
                            )
                          else
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF2A1B4E),
                                    Color(0xFF1E1938),
                                    Color(0xFF161426),
                                  ],
                                ),
                              ),
                            ),

                          // 2. Kenarlardan Ortaya Doğru Karanlıktan Açığa Radyal Vignette Efekti
                          if (_savedImagePath != null && File(_savedImagePath!).existsSync())
                            Container(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  center: Alignment.center,
                                  radius: 0.95,
                                  colors: [
                                    const Color(0xFF0F1E2E).withValues(alpha: 0.12),
                                    const Color(0xFF0F0C1B).withValues(alpha: 0.55),
                                    const Color(0xFF090814).withValues(alpha: 0.92),
                                  ],
                                  stops: const [0.0, 0.6, 1.0],
                                ),
                              ),
                            ),

                          // Dış Kenarlık (Stroke)
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(26),
                              border: Border.all(
                                color: const Color(0x55A78BFA),
                                width: 1.5,
                              ),
                            ),
                          ),

                          // 3. Widget Bilgileri (Canlı Önizleme)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Üst Satır: Partner Çipi (Sol), Gün Sayacı (Orta), Son Aktif (Sağ)
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xD018132A),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(color: const Color(0x55A78BFA), width: 1.2),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text('💜', style: TextStyle(fontSize: 12)),
                                          const SizedBox(width: 4),
                                          Text(
                                            partnerName,
                                            style: const TextStyle(
                                              color: Color(0xFFF3F4F6),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xD018132A),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(color: const Color(0x55A78BFA), width: 1.2),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.baseline,
                                        textBaseline: TextBaseline.alphabetic,
                                        children: [
                                          Text(
                                            daysCount,
                                            style: const TextStyle(
                                              color: Color(0xFFA78BFA),
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 3),
                                          const Text(
                                            'gün',
                                            style: TextStyle(
                                              color: Color(0xFFE2E8F0),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xD018132A),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(color: const Color(0x55A78BFA), width: 1.2),
                                      ),
                                      child: const Text(
                                        'Şimdi aktif',
                                        style: TextStyle(
                                          color: Color(0xFF34D399),
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                // Orta Kısım: Fotoğrafın (yüzlerin) net görünmesi için serbest alan
                                const Spacer(),

                                // Alt Çipler
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xD018132A),
                                          borderRadius: BorderRadius.circular(18),
                                          border: Border.all(color: const Color(0x55A78BFA), width: 1.2),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Container(width: 10, height: 16, decoration: BoxDecoration(border: Border.all(color: const Color(0xFF94A3B8), width: 1.2), borderRadius: BorderRadius.circular(2.5)), padding: const EdgeInsets.all(1.5), child: Align(alignment: Alignment.bottomCenter, child: Container(width: double.infinity, height: (12.0 * ((partner?.batteryLevel ?? 80).clamp(0, 100) / 100.0)).clamp(2.0, 12.0), decoration: BoxDecoration(color: (partner?.batteryLevel ?? 80) >= 50 ? const Color(0xFF34D399) : ((partner?.batteryLevel ?? 80) >= 20 ? const Color(0xFFFBBF24) : const Color(0xFFEF4444)), borderRadius: BorderRadius.circular(1.2))))),
                                            const SizedBox(width: 4),
                                            Text(
                                              batteryText,
                                              style: const TextStyle(
                                                color: Color(0xFF34D399),
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      flex: 12,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xD018132A),
                                          borderRadius: BorderRadius.circular(18),
                                          border: Border.all(color: const Color(0x55A78BFA), width: 1.2),
                                        ),
                                        child: const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text('🏠', style: TextStyle(fontSize: 12)),
                                            SizedBox(width: 4),
                                            Text(
                                              'Evim',
                                              style: TextStyle(
                                                color: Color(0xFFF3F4F6),
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Aksiyon Butonları
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: LoveraColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.add_photo_alternate_rounded, size: 22),
                    label: Text(
                      _savedImagePath != null ? 'Fotoğrafı Değiştir' : 'Widget Fotoğrafı Seç',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    onPressed: _pickImage,
                  ),
                ),

                if (_savedImagePath != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent, width: 1.2),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      label: const Text(
                        'Fotoğrafı Kaldır (Varsayılan Tema)',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      onPressed: _removeImage,
                    ),
                  ),
                ],

                const SizedBox(height: 36),
                Divider(color: theme.dividerColor),
                const SizedBox(height: 20),

                // 2. Widget: Canlı Çizim & Not Tuvali Bölümü
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFA78BFA).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('🎨', style: TextStyle(fontSize: 20)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Canlı Çizim & Doodle Widget\'ı',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Partnerinizin ana ekranına anlık çizimler ve notlar yollayın.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFA78BFA),
                      side: const BorderSide(color: Color(0xFFA78BFA), width: 1.4),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.brush_rounded, size: 20),
                    label: const Text(
                      'Hemen Bir Çizim Yap & Gönder',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DrawingScreen()),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
