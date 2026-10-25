import 'dart:async';
import 'package:flutter/services.dart';

/// Kalp atışı ritminde (Lub-Dub / Güm-Güm) titreşim motoru yöneticisi
class HeartbeatHapticService {
  static final HeartbeatHapticService _instance = HeartbeatHapticService._internal();
  factory HeartbeatHapticService() => _instance;
  HeartbeatHapticService._internal();

  bool _isPlaying = false;

  /// Gerçek insan kalp atışı ritminde titreşim çalar
  /// [pulses]: Kaç kez "güm-güm" atacağını belirler (varsayılan: 3 kez)
  Future<void> playHeartbeat({int pulses = 3}) async {
    if (_isPlaying) return;
    _isPlaying = true;

    try {
      for (int i = 0; i < pulses; i++) {
        // 1. Vuruş (Lub / Güm): Hafif/Orta vuruş
        await HapticFeedback.mediumImpact();
        await Future.delayed(const Duration(milliseconds: 110));

        // 2. Vuruş (Dub / GÜM): Güçlü ve tok vuruş
        await HapticFeedback.heavyImpact();

        // İki kalp atışı arası doğal biyolojik dinlenme süresi (yaklaşık 700ms)
        if (i < pulses - 1) {
          await Future.delayed(const Duration(milliseconds: 650));
        }
      }
    } catch (_) {
      // Platform titreşimi desteklemiyorsa sessizce devam et
    } finally {
      _isPlaying = false;
    }
  }

  /// Butona basıldığında gönderen kişinin parmak ucuna tek bir zarif kalp vuruşu hissi verir
  Future<void> playSinglePulse() async {
    try {
      await HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }
}
