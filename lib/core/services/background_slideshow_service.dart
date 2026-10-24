import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'widget_sync_service.dart';

/// Arka plan otomatik döngü yapılandırması
class SlideshowConfig {
  final bool isEnabled;
  final String source; // 'all' veya 'album:<albumId>'
  final String albumTitle;
  final int intervalSeconds;
  final int currentIndex;
  final int lastRotatedAt; // timestamp ms

  const SlideshowConfig({
    this.isEnabled = false,
    this.source = 'all',
    this.albumTitle = '',
    this.intervalSeconds = 60,
    this.currentIndex = 0,
    this.lastRotatedAt = 0,
  });

  Map<String, dynamic> toJson() => {
        'isEnabled': isEnabled,
        'source': source,
        'albumTitle': albumTitle,
        'intervalSeconds': intervalSeconds,
        'currentIndex': currentIndex,
        'lastRotatedAt': lastRotatedAt,
      };

  factory SlideshowConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SlideshowConfig();
    return SlideshowConfig(
      isEnabled: json['isEnabled'] as bool? ?? false,
      source: json['source'] as String? ?? 'all',
      albumTitle: json['albumTitle'] as String? ?? '',
      intervalSeconds: json['intervalSeconds'] as int? ?? 60,
      currentIndex: json['currentIndex'] as int? ?? 0,
      lastRotatedAt: json['lastRotatedAt'] as int? ?? 0,
    );
  }
}

/// Sohbet ve Widget için arkaplan otomatik döngü servisi
class BackgroundSlideshowService {
  static final BackgroundSlideshowService _instance = BackgroundSlideshowService._internal();
  factory BackgroundSlideshowService() => _instance;
  BackgroundSlideshowService._internal();

  Timer? _chatTimer;
  Timer? _widgetTimer;

  // SharedPreferences anahtarları
  static const String _keyChatConfig = 'slideshow_chat_config';
  static const String _keyWidgetConfig = 'slideshow_widget_config';

  // ValueNotifier'lar UI anında tepki versin diye
  final ValueNotifier<String?> currentChatBgUrl = ValueNotifier<String?>(null);
  final ValueNotifier<String?> currentWidgetBgPath = ValueNotifier<String?>(null);

  /// Yapılandırmayı kaydet
  Future<void> saveConfig(String target, SlideshowConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final key = target == 'chat' ? _keyChatConfig : _keyWidgetConfig;
    await prefs.setString(key, jsonEncode(config.toJson()));
  }

  /// Yapılandırmayı oku
  Future<SlideshowConfig> getConfig(String target) async {
    final prefs = await SharedPreferences.getInstance();
    final key = target == 'chat' ? _keyChatConfig : _keyWidgetConfig;
    final str = prefs.getString(key);
    if (str == null || str.isEmpty) return const SlideshowConfig();
    try {
      return SlideshowConfig.fromJson(jsonDecode(str) as Map<String, dynamic>);
    } catch (_) {
      return const SlideshowConfig();
    }
  }

  /// Döngüyü tamamen durdur
  Future<void> stopSlideshow(String target) async {
    if (target == 'chat') {
      _chatTimer?.cancel();
      _chatTimer = null;
    } else {
      _widgetTimer?.cancel();
      _widgetTimer = null;
    }
    await saveConfig(target, const SlideshowConfig(isEnabled: false));
  }

  /// Sohbet döngüsünü başlat
  void startChatSlideshow({
    required String coupleId,
    required List<MemoryItem> memories,
    required SlideshowConfig config,
    required void Function(String newBase64) onBgChanged,
  }) {
    _chatTimer?.cancel();
    if (!config.isEnabled) return;

    final filtered = _filterMemories(memories, config.source);
    if (filtered.isEmpty) return;

    // İlk görseli uygula
    int idx = config.currentIndex % filtered.length;
    onBgChanged(filtered[idx].imageUrl);
    currentChatBgUrl.value = filtered[idx].imageUrl;

    _chatTimer = Timer.periodic(Duration(seconds: config.intervalSeconds), (timer) async {
      final latestConfig = await getConfig('chat');
      if (!latestConfig.isEnabled) {
        timer.cancel();
        return;
      }
      final currentList = _filterMemories(memories, latestConfig.source);
      if (currentList.isEmpty) return;

      int nextIdx = (latestConfig.currentIndex + 1) % currentList.length;
      final nextImg = currentList[nextIdx].imageUrl;

      await saveConfig(
        'chat',
        SlideshowConfig(
          isEnabled: true,
          source: latestConfig.source,
          albumTitle: latestConfig.albumTitle,
          intervalSeconds: latestConfig.intervalSeconds,
          currentIndex: nextIdx,
          lastRotatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      onBgChanged(nextImg);
      currentChatBgUrl.value = nextImg;
    });
  }

  /// Sohbet timer'ını durdur (ekrandan çıkıldığında)
  void stopChatTimerOnly() {
    _chatTimer?.cancel();
    _chatTimer = null;
  }

  /// Widget döngüsünü başlat veya periyodik tetikle
  void startWidgetTimer({
    required String coupleId,
    required List<MemoryItem> memories,
    required SlideshowConfig config,
  }) {
    _widgetTimer?.cancel();
    if (!config.isEnabled) return;

    // Hemen ilk rotasyonu çalıştır
    rotateWidgetSlideshowIfNeeded(memories, force: true);

    // Seçilen aralığa göre periyodik Timer başlat
    final interval = Duration(seconds: config.intervalSeconds < 10 ? 10 : config.intervalSeconds);
    _widgetTimer = Timer.periodic(interval, (_) async {
      final latestConfig = await getConfig('widget');
      if (!latestConfig.isEnabled) {
        _widgetTimer?.cancel();
        return;
      }
      await rotateWidgetSlideshowIfNeeded(memories);
    });
  }

  /// Widget döngüsünü periyodik kontrol et ve gerekiyorsa döndür
  Future<void> rotateWidgetSlideshowIfNeeded(List<MemoryItem> memories, {bool force = false}) async {
    final config = await getConfig('widget');
    if (!config.isEnabled) return;

    final filtered = _filterMemories(memories, config.source);
    if (filtered.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final diffSeconds = (now - config.lastRotatedAt) / 1000;

    // Süre dolmuşsa veya force ise bir sonrakine geç
    if (force || diffSeconds >= config.intervalSeconds || config.lastRotatedAt == 0) {
      int nextIdx = (config.currentIndex + 1) % filtered.length;
      final nextItem = filtered[nextIdx];

      try {
        final appDir = await getApplicationDocumentsDirectory();
        final targetPath = '${appDir.path}/widget_bg_custom.jpg';
        final file = File(targetPath);

        // base64 verisini dosyaya yaz
        String base64Data = nextItem.imageUrl;
        if (base64Data.contains(',')) {
          base64Data = base64Data.split(',').last;
        }
        final bytes = base64Decode(base64Data);
        await file.writeAsBytes(bytes, flush: true);

        // Widget senkronizasyonu
        await WidgetSyncService.setWidgetBackgroundImage(targetPath);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('widget_custom_bg_path', targetPath);

        // Yeni konfigürasyonu kaydet
        await saveConfig(
          'widget',
          SlideshowConfig(
            isEnabled: true,
            source: config.source,
            albumTitle: config.albumTitle,
            intervalSeconds: config.intervalSeconds,
            currentIndex: nextIdx,
            lastRotatedAt: now,
          ),
        );
        currentWidgetBgPath.value = targetPath;
        debugPrint('[BackgroundSlideshow] Widget rotated to index: $nextIdx');
      } catch (e) {
        debugPrint('[BackgroundSlideshow] Error rotating widget bg: $e');
      }
    }
  }

  /// Filtreleme yardımcısı
  List<MemoryItem> _filterMemories(List<MemoryItem> memories, String source) {
    if (source == 'all') {
      return memories;
    }
    if (source.startsWith('album:')) {
      final albumId = source.substring(6);
      return memories.where((m) => m.albumId == albumId).toList();
    }
    return memories;
  }
}
