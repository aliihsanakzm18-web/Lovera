import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// İnternet bağlantı durumu kontrolcüsü
final connectivityProvider = StateNotifierProvider<ConnectivityNotifier, bool>((ref) {
  return ConnectivityNotifier();
});

class ConnectivityNotifier extends StateNotifier<bool> {
  ConnectivityNotifier() : super(true) {
    _init();
  }

  Timer? _pollingTimer;
  bool _isChecking = false;

  void _init() {
    // İlk kontrol
    checkConnection();
    // Her 4 saniyede bir periyodik kontrol
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      checkConnection();
    });
  }

  Future<void> checkConnection() async {
    if (_isChecking) return;
    _isChecking = true;
    try {
      // 8.8.8.8 veya 1.1.1.1 DNS ping veya socket lookup
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      final hasNet = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      if (mounted && state != hasNet) {
        state = hasNet;
      }
    } on SocketException catch (_) {
      // lookup başarısız olduysa doğrudan IP dene (DNS arızası durumuna karşı)
      try {
        final socket = await Socket.connect('8.8.8.8', 53, timeout: const Duration(seconds: 2));
        socket.destroy();
        if (mounted && state != true) {
          state = true;
        }
      } catch (_) {
        if (mounted && state != false) {
          state = false;
        }
      }
    } on TimeoutException catch (_) {
      if (mounted && state != false) {
        state = false;
      }
    } catch (_) {
      if (mounted && state != false) {
        state = false;
      }
    } finally {
      _isChecking = false;
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }
}
