import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../localization/app_strings.dart';
import '../services/app_settings_service.dart';
import '../theme/app_theme.dart';

enum AppLockMode {
  unlock, // Uygulamayı açmak için PIN gir
  create, // Yeni PIN oluştur (2 adımlı: gir + onayla)
  change, // Mevcut PIN'i değiştir (3 adımlı: eski gir + yeni gir + onayla)
}

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({
    super.key,
    this.mode = AppLockMode.unlock,
    this.onSuccess,
    this.isDismissible = false,
  });

  final AppLockMode mode;
  final VoidCallback? onSuccess;
  final bool isDismissible;

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> with SingleTickerProviderStateMixin {
  String _enteredPin = '';
  String _firstEnteredPin = ''; // create/change modunda ilk girilen yeni PIN
  int _step = 0; // 0: initial, 1: confirm
  String? _errorMessage;
  late AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onNumberPressed(String number) {
    if (_enteredPin.length >= 4) return;
    HapticFeedback.lightImpact();
    setState(() {
      _enteredPin += number;
      _errorMessage = null;
    });

    if (_enteredPin.length == 4) {
      _handlePinCompleted(_enteredPin);
    }
  }

  void _onBackspacePressed() {
    if (_enteredPin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _errorMessage = null;
    });
  }

  Future<void> _handlePinCompleted(String pin) async {
    switch (widget.mode) {
      case AppLockMode.unlock:
        final isValid = await AppSettingsService.verifyPin(pin);
        if (isValid) {
          HapticFeedback.mediumImpact();
          AppSettingsService.isAppUnlocked = true;
          if (widget.onSuccess != null) {
            widget.onSuccess!();
          } else if (mounted) {
            Navigator.of(context).maybePop(true);
          }
        } else {
          _triggerError(loc('Hatalı PIN kodu, tekrar deneyin!', 'Incorrect PIN, please try again!'));
        }
        break;

      case AppLockMode.create:
        if (_step == 0) {
          // İlk adım: PIN belirlendi, onay adımı için sakla
          HapticFeedback.selectionClick();
          setState(() {
            _firstEnteredPin = pin;
            _enteredPin = '';
            _step = 1;
          });
        } else {
          // İkinci adım: Onay PIN'i
          if (pin == _firstEnteredPin) {
            HapticFeedback.heavyImpact();
            await AppSettingsService.setAppLockPin(pin);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(loc('Uygulama kilidi başarıyla aktifleştirildi! 🔒', 'App lock enabled successfully! 🔒')),
                  backgroundColor: LoveraColors.primary,
                  behavior: SnackBarBehavior.floating,
                ),
              );
              Navigator.of(context).pop(true);
              widget.onSuccess?.call();
            }
          } else {
            _triggerError(loc('PIN kodları eşleşmedi, baştan deneyin!', 'PIN codes did not match, try again!'));
            setState(() {
              _firstEnteredPin = '';
              _step = 0;
            });
          }
        }
        break;

      case AppLockMode.change:
        if (_step == 0) {
          // Mevcut PIN'i doğrula
          final isValid = await AppSettingsService.verifyPin(pin);
          if (isValid) {
            HapticFeedback.selectionClick();
            setState(() {
              _enteredPin = '';
              _step = 1;
            });
          } else {
            _triggerError(loc('Mevcut PIN hatalı!', 'Current PIN is incorrect!'));
          }
        } else if (_step == 1) {
          // Yeni PIN
          HapticFeedback.selectionClick();
          setState(() {
            _firstEnteredPin = pin;
            _enteredPin = '';
            _step = 2;
          });
        } else {
          // Yeni PIN onayı
          if (pin == _firstEnteredPin) {
            HapticFeedback.heavyImpact();
            await AppSettingsService.setAppLockPin(pin);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(loc('PIN kodunuz güncellendi! 🔒', 'PIN updated successfully! 🔒')),
                  backgroundColor: LoveraColors.primary,
                  behavior: SnackBarBehavior.floating,
                ),
              );
              Navigator.of(context).pop(true);
              widget.onSuccess?.call();
            }
          } else {
            _triggerError(loc('Yeni PIN kodları eşleşmedi!', 'New PIN codes did not match!'));
            setState(() {
              _firstEnteredPin = '';
              _step = 1;
            });
          }
        }
        break;
    }
  }

  void _triggerError(String msg) {
    HapticFeedback.heavyImpact();
    _shakeController.forward(from: 0.0);
    setState(() {
      _errorMessage = msg;
      _enteredPin = '';
    });
  }

  String _getTitle() {
    switch (widget.mode) {
      case AppLockMode.unlock:
        return loc('Lovera Güvenlik Kilidi', 'Lovera Security Lock');
      case AppLockMode.create:
        return _step == 0
            ? loc('Yeni PIN Belirleyin', 'Set New PIN')
            : loc('PIN Kodunu Onaylayın', 'Confirm PIN');
      case AppLockMode.change:
        if (_step == 0) return loc('Mevcut PIN Kodunuzu Girin', 'Enter Current PIN');
        if (_step == 1) return loc('Yeni PIN Kodunuzu Girin', 'Enter New PIN');
        return loc('Yeni PIN Kodunu Onaylayın', 'Confirm New PIN');
    }
  }

  String _getSubtitle() {
    switch (widget.mode) {
      case AppLockMode.unlock:
        return loc('Devam etmek için 4 haneli PIN kodunuzu girin', 'Enter your 4-digit PIN to continue');
      case AppLockMode.create:
        return _step == 0
            ? loc('4 haneli bir güvenlik şifresi oluşturun', 'Create a 4-digit security PIN')
            : loc('Lütfen aynı şifreyi tekrar yazın', 'Please re-enter the same PIN');
      case AppLockMode.change:
        if (_step == 0) return loc('Güvenliğiniz için mevcut şifrenizi girin', 'Enter current PIN for verification');
        if (_step == 1) return loc('Yeni 4 haneli şifrenizi belirleyin', 'Choose a new 4-digit PIN');
        return loc('Yeni şifrenizi doğrulamak için tekrar girin', 'Re-enter your new PIN to confirm');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: widget.isDismissible,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [
                      const Color(0xFF0F0C20),
                      const Color(0xFF1E1338),
                      const Color(0xFF110726),
                    ]
                  : [
                      const Color(0xFFFFF0F5),
                      const Color(0xFFFDE2E8),
                      const Color(0xFFF3E8FF),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Kapat butonu (Eğer izin verildiyse)
                Align(
                  alignment: Alignment.topLeft,
                  child: widget.isDismissible
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(context).maybePop(false),
                        )
                      : const SizedBox(height: 48),
                ),

                const Spacer(),

                // Kilit İkonu ve Romantik Işıltı
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        LoveraColors.primary,
                        LoveraColors.secondary,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: LoveraColors.primary.withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    size: 38,
                    color: Colors.white,
                  ),
                ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),

                const SizedBox(height: 24),

                // Başlık
                Text(
                  _getTitle(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: isDark ? Colors.white : const Color(0xFF1E1B4B),
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 8),

                // Alt Başlık
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _getSubtitle(),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white70 : const Color(0xFF64748B),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                const SizedBox(height: 36),

                // PIN Noktaları (Shake animasyonu ile)
                AnimatedBuilder(
                  animation: _shakeController,
                  builder: (context, child) {
                    final offset = 12 * (1 - _shakeController.value) *
                        (1 - _shakeController.value) *
                        (0.5 - ((_shakeController.value * 6) % 1));
                    return Transform.translate(
                      offset: Offset(offset, 0),
                      child: child,
                    );
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (index) {
                      final isFilled = index < _enteredPin.length;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        width: isFilled ? 18 : 16,
                        height: isFilled ? 18 : 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isFilled
                              ? LoveraColors.primary
                              : (isDark ? Colors.white24 : Colors.black12),
                          boxShadow: isFilled
                              ? [
                                  BoxShadow(
                                    color: LoveraColors.primary.withValues(alpha: 0.5),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        ),
                      );
                    }),
                  ),
                ),

                // Hata Mesajı
                Container(
                  height: 36,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.only(top: 10),
                  child: _errorMessage != null
                      ? Text(
                          _errorMessage!,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.redAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ).animate().fadeIn(duration: 200.ms)
                      : const SizedBox.shrink(),
                ),

                const Spacer(),

                // Özel Nümerik Tuş Takımı
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    children: [
                      _buildKeyRow(['1', '2', '3'], isDark),
                      const SizedBox(height: 18),
                      _buildKeyRow(['4', '5', '6'], isDark),
                      const SizedBox(height: 18),
                      _buildKeyRow(['7', '8', '9'], isDark),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          const SizedBox(width: 72, height: 72),
                          _buildNumberKey('0', isDark),
                          _buildBackspaceKey(isDark),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeyRow(List<String> numbers, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: numbers.map((n) => _buildNumberKey(n, isDark)).toList(),
    );
  }

  Widget _buildNumberKey(String number, bool isDark) {
    return InkWell(
      onTap: () => _onNumberPressed(number),
      borderRadius: BorderRadius.circular(36),
      splashColor: LoveraColors.primary.withValues(alpha: 0.2),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          number,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1E1B4B),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceKey(bool isDark) {
    return InkWell(
      onTap: _onBackspacePressed,
      borderRadius: BorderRadius.circular(36),
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        child: Icon(
          Icons.backspace_outlined,
          size: 26,
          color: isDark ? Colors.white70 : const Color(0xFF64748B),
        ),
      ),
    );
  }
}
