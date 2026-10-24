import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/services/background_slideshow_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/widget_sync_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../common/presentation/widgets/background_source_selection_sheet.dart';
import '../../common/presentation/widgets/memory_background_picker_sheet.dart';
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
          ? loc('Uygulama Temasıyla Senkron', 'Sync with App Theme')
          : (mode == 'dark' ? loc('Koyu Gece Teması', 'Dark Night Theme') : loc('Açık Ferah Tema', 'Light Fresh Theme'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc('Widget teması "$label" olarak ayarlandı ✨', 'Widget theme set to "$label" ✨')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickImage() async {
    HapticFeedback.lightImpact();
    final coupleId = ref.read(coupleIdProvider) ?? ref.read(currentUserProvider)?.coupleId ?? '';

    BackgroundSourceSelectionSheet.show(
      context: context,
      title: loc('Widget Arka Planı', 'Widget Background'),
      onSelectDevice: () async {
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
          // Cihazdan tekil fotoğraf seçilirse var olan slideshow'u durdur
          await BackgroundSlideshowService().stopSlideshow('widget');

          final appDir = await getApplicationDocumentsDirectory();
          final targetPath = '${appDir.path}/widget_bg_custom.jpg';

          final targetFile = File(targetPath);
          if (targetFile.existsSync()) {
            targetFile.deleteSync();
          }
          await File(pickedFile.path).copy(targetPath);

          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
          await FileImage(File(targetPath)).evict();

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('widget_custom_bg_path', targetPath);

          // Widget'a yerel senkronize et
          await WidgetSyncService.setWidgetBackgroundImage(targetPath);

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
              SnackBar(
                content: Text(loc('Widget fotoğrafın başarıyla güncellendi! 💕', 'Widget photo updated successfully! 💕')),
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
                content: Text(loc('Fotoğraf eklenirken bir hata oluştu: $e', 'An error occurred while adding photo: $e')),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        }
      },
      onSelectMemoryAlbum: () {
        if (coupleId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(loc('Anı albümünü kullanmak için eşleşmeniz gerekir.', 'You must pair to use the memory album.')),
              backgroundColor: LoveraColors.primary,
            ),
          );
          return;
        }

        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (mCtx) => MemoryBackgroundPickerSheet(
            coupleId: coupleId,
            target: 'widget',
            onSingleImageSelected: (base64Str) async {
              try {
                setState(() => _isLoading = true);
                await BackgroundSlideshowService().stopSlideshow('widget');

                final appDir = await getApplicationDocumentsDirectory();
                final targetPath = '${appDir.path}/widget_bg_custom.jpg';
                final targetFile = File(targetPath);

                String raw = base64Str;
                if (raw.contains(',')) raw = raw.split(',').last;
                final bytes = base64Decode(raw);
                await targetFile.writeAsBytes(bytes, flush: true);

                PaintingBinding.instance.imageCache.clear();
                PaintingBinding.instance.imageCache.clearLiveImages();
                await FileImage(File(targetPath)).evict();

                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('widget_custom_bg_path', targetPath);

                await WidgetSyncService.setWidgetBackgroundImage(targetPath);
                await DatabaseService().updateWidgetBg(base64Str);

                setState(() {
                  _savedImagePath = targetPath;
                  _lastUpdated = DateTime.now().millisecondsSinceEpoch;
                  _isLoading = false;
                });

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(loc('Widget fotoğrafı anı albümünden güncellendi! 💕', 'Widget photo updated from memory album! 💕')),
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
                      content: Text(loc('Hata oluştu: $e', 'An error occurred: $e')),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
            onSlideshowConfigured: (config) async {
              // Timer'ı ve ilk rotasyonu hemen başlat
              final mems = await DatabaseService().getMemoriesOnce(coupleId);
              BackgroundSlideshowService().startWidgetTimer(
                coupleId: coupleId,
                memories: mems,
                config: config,
              );
              final appDir = await getApplicationDocumentsDirectory();
              final targetPath = '${appDir.path}/widget_bg_custom.jpg';
              if (mounted) {
                setState(() {
                  _savedImagePath = targetPath;
                  _lastUpdated = DateTime.now().millisecondsSinceEpoch;
                });
              }
            },
          ),
        );
      },
    );
  }

  Future<void> _removeImage() async {
    HapticFeedback.lightImpact();
    try {
      setState(() => _isLoading = true);
      await BackgroundSlideshowService().stopSlideshow('widget');
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
          SnackBar(
            content: Text(loc('Widget fotoğrafı kaldırıldı, varsayılan temaya dönüldü.', 'Widget photo removed, restored to default theme.')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc('Fotoğraf kaldırılırken bir hata oluştu: $e', 'An error occurred while removing photo: $e')),
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
    final palette = ref.watch(themePaletteProvider);

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
        title: Text(loc('Widget Ayarları', 'Widget Settings')),
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
                  loc('Ana Ekran Widget Görünümü', 'Home Screen Widget Appearance'),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  loc(
                    'Widget arkasına sevgilinizle olan özel bir anınızı ekleyin veya Lovera temalarını kullanın. Widget\'ların açık/koyu modunu ayrı olarak seçebilir ya da uygulama temanızla eşitleyebilirsiniz.',
                    'Add a special memory behind your widget or use Lovera themes. Choose light/dark mode independently or sync with your app theme.',
                  ),
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
                                          palette.darkBg,
                                          palette.darkSurface,
                                          palette.darkSurfaceAlt,
                                        ]
                                      : [
                                          palette.lightSurface,
                                          palette.lightBg,
                                          palette.lightSurfaceAlt,
                                        ],
                                ),
                              ),
                              child: CustomPaint(
                                painter: _WidgetDoodlePreviewPainter(
                                  primary: previewIsDark ? palette.primaryDark : palette.primary,
                                  secondary: palette.secondary,
                                  isDark: previewIsDark,
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
                                color: LoveraColors.primaryDark.withValues(alpha: 0.33),
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
                                          color: previewIsDark ? palette.darkSurface.withValues(alpha: 0.85) : palette.lightSurface.withValues(alpha: 0.94),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: previewIsDark ? palette.primaryDark.withValues(alpha: 0.38) : palette.primary.withValues(alpha: 0.28),
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.favorite_rounded, size: 11, color: previewIsDark ? palette.primaryDark : palette.primary),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                partnerName,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: previewIsDark ? palette.darkText : palette.textDark,
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
                                        color: previewIsDark ? palette.darkSurface.withValues(alpha: 0.85) : palette.lightSurface.withValues(alpha: 0.94),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: previewIsDark ? palette.primaryDark.withValues(alpha: 0.38) : palette.primary.withValues(alpha: 0.28),
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
                                              color: previewIsDark ? palette.primaryDark : palette.primaryDeep,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            loc('gün', 'days'),
                                            style: TextStyle(
                                              color: previewIsDark ? palette.darkTextMuted : palette.textMuted,
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
                                        color: previewIsDark ? palette.darkSurface.withValues(alpha: 0.85) : palette.lightSurface.withValues(alpha: 0.94),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: previewIsDark ? palette.primaryDark.withValues(alpha: 0.38) : palette.primary.withValues(alpha: 0.28),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        loc('Şimdi aktif', 'Active now'),
                                        style: const TextStyle(
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
                                          color: previewIsDark ? palette.darkSurface.withValues(alpha: 0.85) : palette.lightSurface.withValues(alpha: 0.94),
                                          borderRadius: BorderRadius.circular(18),
                                          border: Border.all(
                                            color: previewIsDark ? palette.primaryDark.withValues(alpha: 0.38) : palette.primary.withValues(alpha: 0.28),
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
                                                  color: previewIsDark ? palette.darkTextMuted : palette.textMuted,
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
                                          color: previewIsDark ? palette.darkSurface.withValues(alpha: 0.85) : palette.lightSurface.withValues(alpha: 0.94),
                                          borderRadius: BorderRadius.circular(18),
                                          border: Border.all(
                                            color: previewIsDark ? palette.primaryDark.withValues(alpha: 0.38) : palette.primary.withValues(alpha: 0.28),
                                            width: 1.2,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Text('🏠', style: TextStyle(fontSize: 12)),
                                            const SizedBox(width: 4),
                                            Text(loc('Evim', 'Home'),
                                              style: TextStyle(
                                                color: previewIsDark ? palette.darkText : palette.textDark,
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
                    color: isDark ? palette.darkSurface : palette.lightSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? LoveraColors.primaryDark.withValues(alpha: 0.15) : LoveraColors.primary.withValues(alpha: 0.13),
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
                            loc('Widget Teması', 'Widget Theme'),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        loc(
                          'Ana ekran widget\'larının renk stilini ve görünümünü belirleyin:',
                          'Select the color style and appearance of home screen widgets:',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _buildThemeOption(
                            context: context,
                            title: loc('Otomatik', 'Auto'),
                            subtitle: loc('Uygulama', 'App'),
                            icon: Icons.sync_rounded,
                            isSelected: _widgetTheme == 'app',
                            onTap: () => _changeWidgetTheme('app'),
                          ),
                          const SizedBox(width: 8),
                          _buildThemeOption(
                            context: context,
                            title: loc('Koyu', 'Dark'),
                            subtitle: loc('Gece', 'Night'),
                            icon: Icons.dark_mode_rounded,
                            isSelected: _widgetTheme == 'dark',
                            onTap: () => _changeWidgetTheme('dark'),
                          ),
                          const SizedBox(width: 8),
                          _buildThemeOption(
                            context: context,
                            title: loc('Açık', 'Light'),
                            subtitle: loc('Ferah', 'Fresh'),
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
                      _savedImagePath != null
                          ? loc('Fotoğrafı Değiştir', 'Change Photo')
                          : loc('Widget Fotoğrafı Seç', 'Select Widget Photo'),
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
                      label: Text(
                        loc('Fotoğrafı Kaldır (Varsayılan Tema)', 'Remove Photo (Default Theme)'),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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
                        color: LoveraColors.primaryDark.withValues(alpha: 0.15),
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
                            loc('Canlı Çizim & Doodle Widget\'ı', 'Live Drawing & Doodle Widget'),
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            loc('Partnerinizin ana ekranına anlık çizimler ve notlar yollayın.', 'Send instant drawings and notes directly to your partner\'s home screen.'),
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
                      foregroundColor: LoveraColors.primaryDark,
                      side: BorderSide(color: LoveraColors.primaryDark, width: 1.4),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.brush_rounded, size: 20),
                    label: Text(
                      loc('Hemen Bir Çizim Yap & Gönder', 'Create & Send Drawing Now'),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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
                : (isDark ? LoveraColors.darkSurfaceAlt : LoveraColors.lightSurfaceAlt),
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

class _WidgetDoodlePreviewPainter extends CustomPainter {
  final Color primary;
  final Color secondary;
  final bool isDark;

  const _WidgetDoodlePreviewPainter({
    required this.primary,
    required this.secondary,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 200.0;
    canvas.save();
    canvas.scale(s, s);

    // Sol üst ve sağ alt aurora halesi
    final glowPaint = Paint()..style = PaintingStyle.fill;
    glowPaint.shader = RadialGradient(
      colors: [primary.withValues(alpha: isDark ? 0.24 : 0.18), primary.withValues(alpha: 0)],
    ).createShader(Rect.fromCircle(center: const Offset(20, 20), radius: 90));
    canvas.drawRect(const Rect.fromLTWH(0, 0, 200, 200), glowPaint);

    glowPaint.shader = RadialGradient(
      colors: [secondary.withValues(alpha: isDark ? 0.20 : 0.15), secondary.withValues(alpha: 0)],
    ).createShader(Rect.fromCircle(center: const Offset(170, 170), radius: 90));
    canvas.drawRect(const Rect.fromLTWH(0, 0, 200, 200), glowPaint);

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = primary.withValues(alpha: isDark ? 0.12 : 0.10);
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = primary.withValues(alpha: isDark ? 0.26 : 0.22);

    // Kalp 1 (Sol Üst)
    final heart = Path()
      ..moveTo(46, 62)
      ..cubicTo(40, 54, 30, 56, 28, 66)
      ..cubicTo(26, 76, 46, 90, 46, 90)
      ..cubicTo(46, 90, 66, 76, 64, 66)
      ..cubicTo(62, 56, 52, 54, 46, 62)
      ..close();
    canvas.drawPath(heart, fillPaint);
    canvas.drawPath(heart, strokePaint);

    // Parlak Yıldız ✦ (Sağ Üst)
    final star = Path()
      ..moveTo(152, 48)
      ..quadraticBezierTo(152, 56, 160, 56)
      ..quadraticBezierTo(152, 56, 152, 64)
      ..quadraticBezierTo(152, 56, 144, 56)
      ..quadraticBezierTo(152, 56, 152, 48)
      ..close();
    canvas.drawPath(star, fillPaint..color = secondary.withValues(alpha: isDark ? 0.16 : 0.14));
    canvas.drawPath(star, strokePaint..color = secondary.withValues(alpha: isDark ? 0.30 : 0.25));

    // Hilal Ay 🌙 (Sol Orta/Alt)
    final moon = Path()
      ..moveTo(38, 124)
      ..cubicTo(44, 124, 50, 129, 50, 136)
      ..cubicTo(50, 143, 44, 148, 38, 148)
      ..cubicTo(42, 146, 45, 141, 45, 136)
      ..cubicTo(45, 131, 42, 126, 38, 124)
      ..close();
    fillPaint.color = primary.withValues(alpha: isDark ? 0.12 : 0.10);
    strokePaint.color = primary.withValues(alpha: isDark ? 0.24 : 0.20);
    canvas.drawPath(moon, fillPaint);
    canvas.drawPath(moon, strokePaint);

    // Mektup Zarfı ✉️ (Merkez Sağ)
    final env = Path()
      ..addRect(const Rect.fromLTRB(142, 106, 168, 124))
      ..moveTo(142, 106)
      ..lineTo(155, 116)
      ..lineTo(168, 106);
    canvas.drawPath(env, strokePaint);

    // Sonsuzluk Sembolü ∞ (Sağ Alt)
    final inf = Path()
      ..moveTo(132, 156)
      ..cubicTo(127, 151, 120, 151, 115, 156)
      ..cubicTo(110, 161, 117, 166, 122, 161)
      ..cubicTo(127, 156, 134, 151, 139, 156)
      ..cubicTo(144, 161, 137, 166, 132, 161)
      ..close();
    canvas.drawPath(inf, strokePaint..color = secondary.withValues(alpha: isDark ? 0.26 : 0.22));

    // Yörüngeli Gezegen 🪐 (Sol Merkez)
    strokePaint.color = primary.withValues(alpha: isDark ? 0.22 : 0.18);
    canvas.drawCircle(const Offset(48, 100), 7, fillPaint);
    canvas.drawCircle(const Offset(48, 100), 7, strokePaint);
    final orbit = Path()
      ..moveTo(36, 102)
      ..quadraticBezierTo(48, 96, 60, 102)
      ..quadraticBezierTo(48, 108, 36, 102);
    canvas.drawPath(orbit, strokePaint);

    // Yıldız tozu noktaları
    fillPaint.color = primary.withValues(alpha: isDark ? 0.24 : 0.20);
    for (final pt in const [
      Offset(98, 46),
      Offset(106, 146),
      Offset(86, 112),
      Offset(122, 82),
      Offset(166, 142),
      Offset(32, 86),
    ]) {
      canvas.drawCircle(pt, 1.3, fillPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WidgetDoodlePreviewPainter oldDelegate) =>
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary ||
      oldDelegate.isDark != isDark;
}
