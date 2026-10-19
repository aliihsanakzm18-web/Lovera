import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/database_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/widget_sync_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../drawing/presentation/drawing_screen.dart';
import '../../../core/widgets/lovera_theme_background.dart';

class WidgetSettingsView extends ConsumerStatefulWidget {
  const WidgetSettingsView({super.key});

  @override
  ConsumerState<WidgetSettingsView> createState() => _WidgetSettingsViewState();
}

class _WidgetSettingsViewState extends ConsumerState<WidgetSettingsView> {
  String? _savedImagePath;
  int? _lastUpdated;
  String _widgetTheme = 'app'; // 'app', 'dark', 'light'
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString('widget_custom_bg_path');
      var savedTheme = prefs.getString('widget_theme') ?? 'app';
      if (savedTheme != 'dark' && savedTheme != 'light') {
        savedTheme = 'app';
      }
      final appDir = await getApplicationDocumentsDirectory();
      final targetPath = '${appDir.path}/widget_bg_custom.jpg';

      _widgetTheme = savedTheme;

      // 1. Önce yerel diskte var mı bak
      if (path != null && path.isNotEmpty && File(path).existsSync()) {
        setState(() {
          _savedImagePath = path;
          _lastUpdated = DateTime.now().millisecondsSinceEpoch;
          _isLoading = false;
        });
        return;
      }

      // 2. Kullanıcının kendi hesabından widget fotoğrafını kontrol et
      String? cloudBg;
      final meUser = ref.read(currentUserProvider);
      cloudBg = meUser?.widgetBgUrl;
      if (cloudBg == null || cloudBg.isEmpty) {
        final uid = DatabaseService().uid;
        if (uid != null) {
          final doc = await DatabaseService().db.collection('users').doc(uid).get();
          cloudBg = doc.data()?['widgetBgUrl'] as String?;
        }
      }

      if (cloudBg != null && cloudBg.isNotEmpty) {
        final clean = cloudBg.contains(',') ? cloudBg.split(',').last : cloudBg;
        final bytes = base64Decode(clean);
        final file = File(targetPath);
        await file.writeAsBytes(bytes);
        await prefs.setString('widget_custom_bg_path', targetPath);
        await WidgetSyncService.setWidgetBackgroundImage(targetPath);

        setState(() {
          _savedImagePath = targetPath;
          _lastUpdated = DateTime.now().millisecondsSinceEpoch;
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _savedImagePath = null;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _changeWidgetTheme(String mode) async {
    HapticFeedback.selectionClick();
    setState(() => _widgetTheme = mode);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('widget_theme', mode);

    // Eğer 'app' (otomatik) seçildiyse uygulamanın mevcut temasına göre 'dark' veya 'light' belirle
    String effectiveTheme = mode;
    if (mode == 'app') {
      final currentAppTheme = ref.read(themeModeProvider);
      if (currentAppTheme == ThemeMode.light) {
        effectiveTheme = 'light';
      } else if (currentAppTheme == ThemeMode.dark) {
        effectiveTheme = 'dark';
      } else {
        // Sistem modu ise cihazın o anki parlaklığına bak
        final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
        effectiveTheme = brightness == Brightness.dark ? 'dark' : 'light';
      }
    }

    await WidgetSyncService.setWidgetTheme(effectiveTheme, savedPreferenceMode: mode);

    if (mounted) {
      final label = mode == 'app'
          ? 'Uygulama Temasıyla Senkron'
          : (mode == 'dark' ? 'Koyu Gece Teması' : 'Açık Ferah Tema');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Widget teması "$label" olarak ayarlandı ✨'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickImage() async {
    HapticFeedback.lightImpact();
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
      maxWidth: 800,
      maxHeight: 800,
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

      // Widget'a yerel senkronize et
      await WidgetSyncService.setWidgetBackgroundImage(targetPath);

      // Yalnızca kullanıcının kendi hesabına kaydet (Kişisel widget arka planı)
      final imageBytes = await File(targetPath).readAsBytes();
      final base64Str = 'data:image/jpeg;base64,${base64Encode(imageBytes)}';
      await DatabaseService().updateWidgetBg(base64Str);

      setState(() {
        _savedImagePath = targetPath;
        _lastUpdated = DateTime.now().millisecondsSinceEpoch;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Widget fotoğrafın başarıyla güncellendi! 💕'),
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

      // Yalnızca kendi hesabından kaldır
      await DatabaseService().deleteWidgetBg();

      setState(() {
        _savedImagePath = null;
        _lastUpdated = DateTime.now().millisecondsSinceEpoch;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Widget fotoğrafı kaldırıldı, varsayılan temaya dönüldü.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fotoğraf kaldırılırken bir hata oluştu: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
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

    // Widget teması belirleme (Canlı Önizleme için)
    final bool previewIsDark = _widgetTheme == 'dark'
        ? true
        : (_widgetTheme == 'light' ? false : isDark);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Widget Ayarları'),
        centerTitle: true,
      ),
      body: LoveraThemeBackground(
        child: _isLoading
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
                  'Widget arkasına sevgilinizle olan özel bir anınızı ekleyin veya Lovera temalarını kullanın. Widget\'ların açık/koyu modunu ayrı olarak seçebilir ya da uygulama temanızla eşitleyebilirsiniz.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),

                // Canlı Widget Önizleme Kartı (Simülasyon)
                Center(
                  child: Container(
                    width: 226,
                    height: 226,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: previewIsDark ? 0.35 : 0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                        if (previewIsDark)
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
                          // 1. Arka Plan: Seçilen Fotoğraf VEYA Lovera Özel Teması (Koyu / Açık Desen)
                          if (_savedImagePath != null && File(_savedImagePath!).existsSync())
                            Image.file(
                              File(_savedImagePath!),
                              key: ValueKey(_savedImagePath! + (_lastUpdated?.toString() ?? '')),
                              fit: BoxFit.cover,
                            )
                          else
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: previewIsDark
                                      ? [
                                          const Color(0xFF0F0C1B),
                                          const Color(0xFF1B1530),
                                          const Color(0xFF120E22),
                                        ]
                                      : [
                                          const Color(0xFFFFFFFF),
                                          const Color(0xFFF8FAFC),
                                          const Color(0xFFF1F5F9),
                                        ],
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.favorite_rounded,
                                  size: 64,
                                  color: previewIsDark
                                      ? const Color(0x18A78BFA)
                                      : const Color(0x228B5CF6),
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
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                                        decoration: BoxDecoration(
                                          color: previewIsDark ? const Color(0xD018132A) : const Color(0xF0FFFFFF),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: previewIsDark ? const Color(0x55A78BFA) : const Color(0x358B5CF6),
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Text('💜', style: TextStyle(fontSize: 10)),
                                            const SizedBox(width: 3),
                                            Flexible(
                                              child: Text(
                                                partnerName,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: previewIsDark ? const Color(0xFFF3F4F6) : const Color(0xFF1E1B4B),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                                      decoration: BoxDecoration(
                                        color: previewIsDark ? const Color(0xD018132A) : const Color(0xF0FFFFFF),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: previewIsDark ? const Color(0x55A78BFA) : const Color(0x358B5CF6),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.baseline,
                                        textBaseline: TextBaseline.alphabetic,
                                        children: [
                                          Text(
                                            daysCount,
                                            style: TextStyle(
                                              color: previewIsDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            'gün',
                                            style: TextStyle(
                                              color: previewIsDark ? const Color(0xFFE2E8F0) : const Color(0xFF64748B),
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                                      decoration: BoxDecoration(
                                        color: previewIsDark ? const Color(0xD018132A) : const Color(0xF0FFFFFF),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: previewIsDark ? const Color(0x55A78BFA) : const Color(0x358B5CF6),
                                          width: 1,
                                        ),
                                      ),
                                      child: const Text(
                                        'Şimdi aktif',
                                        style: TextStyle(
                                          color: Color(0xFF10B981),
                                          fontSize: 10,
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
                                          color: previewIsDark ? const Color(0xD018132A) : const Color(0xF0FFFFFF),
                                          borderRadius: BorderRadius.circular(18),
                                          border: Border.all(
                                            color: previewIsDark ? const Color(0x55A78BFA) : const Color(0x358B5CF6),
                                            width: 1.2,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Container(
                                              width: 10,
                                              height: 16,
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: previewIsDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                                  width: 1.2,
                                                ),
                                                borderRadius: BorderRadius.circular(2.5),
                                              ),
                                              padding: const EdgeInsets.all(1.5),
                                              child: Align(
                                                alignment: Alignment.bottomCenter,
                                                child: Container(
                                                  width: double.infinity,
                                                  height: (12.0 * ((partner?.batteryLevel ?? 80).clamp(0, 100) / 100.0)).clamp(2.0, 12.0),
                                                  decoration: BoxDecoration(
                                                    color: (partner?.batteryLevel ?? 80) >= 50
                                                        ? const Color(0xFF10B981)
                                                        : ((partner?.batteryLevel ?? 80) >= 20
                                                            ? const Color(0xFFFBBF24)
                                                            : const Color(0xFFEF4444)),
                                                    borderRadius: BorderRadius.circular(1.2),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              batteryText,
                                              style: const TextStyle(
                                                color: Color(0xFF10B981),
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
                                          color: previewIsDark ? const Color(0xD018132A) : const Color(0xF0FFFFFF),
                                          borderRadius: BorderRadius.circular(18),
                                          border: Border.all(
                                            color: previewIsDark ? const Color(0x55A78BFA) : const Color(0x358B5CF6),
                                            width: 1.2,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Text('🏠', style: TextStyle(fontSize: 12)),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Evim',
                                              style: TextStyle(
                                                color: previewIsDark ? const Color(0xFFF3F4F6) : const Color(0xFF1E1B4B),
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
                const SizedBox(height: 28),

                // Widget Teması Seçici Kartı
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1A162B) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? const Color(0x25A78BFA) : const Color(0x208B5CF6),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.palette_rounded,
                            size: 20,
                            color: LoveraColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Widget Teması',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ana ekran widget\'larının renk stilini ve görünümünü belirleyin:',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _buildThemeOption(
                            context: context,
                            title: 'Otomatik',
                            subtitle: 'Uygulama',
                            icon: Icons.sync_rounded,
                            isSelected: _widgetTheme == 'app',
                            onTap: () => _changeWidgetTheme('app'),
                          ),
                          const SizedBox(width: 8),
                          _buildThemeOption(
                            context: context,
                            title: 'Koyu',
                            subtitle: 'Gece',
                            icon: Icons.dark_mode_rounded,
                            isSelected: _widgetTheme == 'dark',
                            onTap: () => _changeWidgetTheme('dark'),
                          ),
                          const SizedBox(width: 8),
                          _buildThemeOption(
                            context: context,
                            title: 'Açık',
                            subtitle: 'Ferah',
                            icon: Icons.light_mode_rounded,
                            isSelected: _widgetTheme == 'light',
                            onTap: () => _changeWidgetTheme('light'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

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
      ),
    );
  }

  Widget _buildThemeOption({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? LoveraColors.primary.withValues(alpha: isDark ? 0.25 : 0.12)
                : (isDark ? const Color(0xFF130F23) : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? LoveraColors.primary
                  : (isDark ? const Color(0x20FFFFFF) : const Color(0x15000000)),
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 24,
                color: isSelected
                    ? LoveraColors.primary
                    : (isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected
                      ? (isDark ? Colors.white : LoveraColors.primary)
                      : (isDark ? LoveraColors.darkText : LoveraColors.textDark),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: isSelected
                      ? LoveraColors.primary.withValues(alpha: 0.85)
                      : (isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
