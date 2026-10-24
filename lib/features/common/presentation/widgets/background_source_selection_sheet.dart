import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';

enum BackgroundSourceType {
  device,
  memoryAlbum,
}

/// "Cihazdan mı, Albümden mi?" Seçim Modalı
class BackgroundSourceSelectionSheet extends StatelessWidget {
  final String title;
  final VoidCallback onSelectDevice;
  final VoidCallback onSelectMemoryAlbum;

  const BackgroundSourceSelectionSheet({
    super.key,
    required this.title,
    required this.onSelectDevice,
    required this.onSelectMemoryAlbum,
  });

  static Future<void> show({
    required BuildContext context,
    required String title,
    required VoidCallback onSelectDevice,
    required VoidCallback onSelectMemoryAlbum,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BackgroundSourceSelectionSheet(
        title: title,
        onSelectDevice: onSelectDevice,
        onSelectMemoryAlbum: onSelectMemoryAlbum,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.only(bottom: 28, top: 12, left: 20, right: 20),
      decoration: BoxDecoration(
        color: isDark ? LoveraColors.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tutamaç
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 18),

          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            loc('Fotoğrafı nereden seçmek istersiniz?', 'Where would you like to select the photo from?'),
            style: TextStyle(
              fontSize: 13,
              color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
            ),
          ),
          const SizedBox(height: 20),

          // Seçenek 1: Cihaz Galerisi
          InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
              onSelectDevice();
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? LoveraColors.darkSurfaceAlt : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.phone_android_rounded, color: Colors.blue, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc('Cihazımdan Seç 📱', 'Choose from My Device 📱'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          loc('Telefonunuzun yerel fotoğraf galerisinden seçin', 'Select from your phone\'s local gallery'),
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Seçenek 2: Ortak Anı Albümü
          InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
              onSelectMemoryAlbum();
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: LoveraColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: LoveraColors.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: LoveraColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.auto_awesome_rounded, color: LoveraColors.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc('Ortak Anı Albümünden Seç 💖', 'Choose from Memory Album 💖'),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: LoveraColors.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          loc('Tek fotoğraf veya otomatik değişen klasör/döngü', 'Single photo or automatic rotating folder/slideshow'),
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: LoveraColors.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
