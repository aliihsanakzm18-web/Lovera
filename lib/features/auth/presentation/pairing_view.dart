import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/services/database_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_cache.dart';
import '../../../core/widgets/lovera_theme_background.dart';

/// Eşleşme içeriği (onboarding ve ayrı ekranda ortak kullanılır).
class PairingContent extends ConsumerStatefulWidget {
  const PairingContent({
    super.key,
    required this.onDone,
    this.onBack,
    this.skipLabel,
  });
  final VoidCallback onDone;
  final VoidCallback? onBack;
  final String? skipLabel;

  @override
  ConsumerState<PairingContent> createState() => _PairingContentState();
}

class _PairingContentState extends ConsumerState<PairingContent> {
  final _controller = TextEditingController();
  String _myCode = '...';
  bool _copied = false;
  bool _isLoading = false;
  String? _waitingMessage;
  StreamSubscription? _userSub;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    _initCodeAndListeners();
  }

  Future<void> _initCodeAndListeners() async {
    final myName = ref.read(userNameProvider);
    final myAvatar = ref.read(userAvatarProvider);

    // Kendi benzersiz kodumuzu al veya oluştur
    final code = await DatabaseService().getOrCreateInviteCode(myName, myAvatar);
    if (mounted) {
      setState(() => _myCode = code);
    }

    // Kullanıcının Firestore belgesini canlı dinle:
    // 1) Biri bize istek attı mı? (pendingPairRequest) -> Onay Penceresi Aç
    // 2) Attığımız istek karşı tarafça kabul edildi mi? (outgoingPairRequest.status == 'accepted') -> Başarılı De!
    _userSub = DatabaseService().userStream()?.listen((doc) {
      if (!doc.exists || doc.data() == null || !mounted) return;
      final data = doc.data()!;

      // 0. Durum: Kullanıcı zaten bir partnerle eşleşmiş durumdaysa (ve yeni bir giden istek sonucu beklenmiyorsa)
      // doğrudan eşleşme ekranını geç!
      final existingCoupleId = data['coupleId'] as String?;
      if (existingCoupleId != null &&
          existingCoupleId.isNotEmpty &&
          data['outgoingPairRequest'] == null &&
          !_dialogOpen) {
        ref.read(coupleIdProvider.notifier).state = existingCoupleId;
        final existingPartnerUid = data['partnerUid'] as String?;
        if (existingPartnerUid != null && existingPartnerUid.isNotEmpty) {
          ref.read(partnerUidProvider.notifier).state = existingPartnerUid;
        }
        widget.onDone();
        return;
      }

      // 1. Durum: Bize gelen bir eşleşme isteği var mı?
      if (data['pendingPairRequest'] != null && !_dialogOpen) {
        final req = Map<String, dynamic>.from(data['pendingPairRequest']);
        if (req['status'] == 'pending') {
          _showIncomingRequestDialog(req);
        }
      }

      // 2. Durum: Gönderdiğimiz istek kabul edildi mi?
      if (data['outgoingPairRequest'] != null) {
        final outReq = Map<String, dynamic>.from(data['outgoingPairRequest']);
        final coupleId = data['coupleId'] as String?;
        if (outReq['status'] == 'accepted') {
          // Eğer eşleşme gerçekten aktifse (coupleId doluysa) başarılı göster ve isteği tüket
          if (coupleId != null && coupleId.isNotEmpty && !_dialogOpen) {
            _dialogOpen = true;
            DatabaseService().clearOutgoingPairRequest();
            _handlePairSuccess(coupleId, outReq['toUid']);
          } else if (coupleId == null || coupleId.isEmpty) {
            // Eski/geçersiz accepted isteği kalmışsa sessizce temizle
            DatabaseService().clearOutgoingPairRequest();
          }
        } else if (outReq['status'] == 'rejected') {
          DatabaseService().clearOutgoingPairRequest();
          setState(() {
            _isLoading = false;
            _waitingMessage = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc('Eşleşme isteği reddedildi.', 'Pairing request was declined.'))),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _myCode));
    HapticFeedback.lightImpact();
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  bool _isRefreshingCode = false;
  Future<void> _refreshCode() async {
    if (_isRefreshingCode) return;
    setState(() => _isRefreshingCode = true);
    HapticFeedback.mediumImpact();
    try {
      final myName = ref.read(userNameProvider);
      final myAvatar = ref.read(userAvatarProvider);
      final newCode = await DatabaseService().refreshInviteCode(myName, myAvatar);
      if (mounted) {
        setState(() {
          _myCode = newCode;
          _isRefreshingCode = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc('Eski kod iptal edildi ve yepyeni tek seferlik bir kod üretildi! 🔐', 'Old code was invalidated and a brand new one-time code was generated! 🔐')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRefreshingCode = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc('Kod yenilenemedi: $e', 'Could not refresh code: $e'))),
        );
      }
    }
  }

  // Gelen Eşleşme İsteği Onay Penceresi (Fotoğraf ve İsim ile)
  Future<void> _showIncomingRequestDialog(Map<String, dynamic> req) async {
    _dialogOpen = true;
    final requesterUid = req['fromUid'] as String;
    final requesterName = req['fromName'] as String? ?? 'Partnerin';
    final requesterAvatar = req['fromAvatar'] as String?;

    DateTime? selectedDate;
    bool showErrorBorder = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final theme = Theme.of(sheetCtx);
          final days = selectedDate != null
              ? (DateTime.now().difference(selectedDate!).inHours / 24).floor() + 1
              : null;

          return Padding(
            padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 18),
                // Profil Fotoğrafı ve Eşleşme Bildirimi
                CircleAvatar(
                  radius: 38,
                  backgroundColor: LoveraColors.primary.withValues(alpha: 0.15),
                  backgroundImage: AvatarCache.getProvider(requesterAvatar),
                  child: (requesterAvatar == null || AvatarCache.getProvider(requesterAvatar) == null)
                      ? Text(
                          requesterName.isNotEmpty ? requesterName[0].toUpperCase() : '?',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: LoveraColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  loc('$requesterName Seninle Eşleşmek İstiyor! 💕', '$requesterName wants to pair with you! 💕'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  loc(
                    'Onayladığında ikinize özel ortak alanınız açılacak. Lütfen birliktelik başlangıç tarihinizi seçin.',
                    'When approved, your private shared space will open. Please select your relationship start date.',
                  ),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: LoveraColors.textMuted, height: 1.3),
                ),
                const SizedBox(height: 20),

                // Tarih Seçici Butonu
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: sheetCtx,
                      initialDate: selectedDate ?? DateTime.now(),
                      firstDate: DateTime(1990),
                      lastDate: DateTime.now(),
                      helpText: loc('İlişki Başlangıç Tarihi', 'Relationship Start Date'),
                    );
                    if (picked != null) {
                      setSheetState(() {
                        selectedDate = picked;
                        showErrorBorder = false;
                      });
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: Theme.of(sheetCtx).brightness == Brightness.dark
                          ? LoveraColors.darkSurfaceAlt
                          : LoveraColors.lightSurfaceAlt,
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                      border: Border.all(
                        color: showErrorBorder
                            ? Colors.redAccent
                            : (Theme.of(sheetCtx).brightness == Brightness.dark
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.black.withValues(alpha: 0.08)),
                        width: showErrorBorder ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_month_rounded,
                              color: showErrorBorder ? Colors.redAccent : LoveraColors.primary,
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  loc('BİRLİKTELİK BAŞLANGICI *', 'RELATIONSHIP START *'),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: showErrorBorder ? Colors.redAccent : LoveraColors.textMuted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  selectedDate != null
                                      ? '${selectedDate!.day}.${selectedDate!.month}.${selectedDate!.year}'
                                      : loc('Tarih seçmek için dokunun', 'Tap to select date'),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: selectedDate != null
                                        ? null
                                        : (showErrorBorder ? Colors.redAccent : LoveraColors.textMuted),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (selectedDate != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: LoveraColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              loc('$days Gündür', 'For $days days'),
                              style: TextStyle(
                                color: LoveraColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          )
                        else
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 16,
                            color: showErrorBorder ? Colors.redAccent : LoveraColors.textMuted,
                          ),
                      ],
                    ),
                  ),
                ),
                if (showErrorBorder) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        loc('⚠️ Devam etmek için birliktelik başlangıç tarihini seçmelisiniz.', '⚠️ You must select relationship start date to continue.'),
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),

                // Onayla & Reddet Butonları
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          Navigator.pop(sheetCtx);
                          _dialogOpen = false;
                          await DatabaseService().rejectPairRequest(requesterUid);
                        },
                        child: Text(loc('Reddet', 'Decline')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.favorite_rounded, size: 18),
                        label: Text(loc('Kabul Et ve Bağlan', 'Accept & Connect')),
                        onPressed: () async {
                          if (selectedDate == null) {
                            HapticFeedback.vibrate();
                            setSheetState(() => showErrorBorder = true);
                            ScaffoldMessenger.of(sheetCtx).showSnackBar(
                              SnackBar(
                                content: Text(loc('Lütfen birliktelik başlangıç tarihinizi seçin! 📅', 'Please select your relationship start date! 📅')),
                                backgroundColor: Colors.redAccent,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }

                          Navigator.pop(sheetCtx);
                          _dialogOpen = false;
                          setState(() => _isLoading = true);

                          final coupleId = await DatabaseService().acceptPairRequest(
                            requesterUid: requesterUid,
                            relationshipStartDate: selectedDate!,
                          );

                          _handlePairSuccess(coupleId, requesterUid);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    _dialogOpen = false;
  }

  // Başarılı Eşleşme Ekranı Kutlaması
  void _handlePairSuccess(String? coupleId, String? partnerUid) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: LoveraColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.favorite_rounded, color: LoveraColors.primary, size: 54),
            ).animate().scale(curve: Curves.elasticOut, duration: 600.ms),
            const SizedBox(height: 20),
            Text(
              loc('Eşleşme Başarılı! 🎉', 'Paired Successfully! 🎉'),
              style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              loc(
                'Artık Lovera alanınız birbirinize bağlandı. Sonsuz anılar biriktirmeye hazırsınız!',
                'Your Lovera space is now connected. You are ready to create timeless memories!',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: LoveraColors.textMuted),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  widget.onDone();
                },
                child: Text(loc('Hemen Başla', 'Get Started')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Kod Girildiğinde Karşı Tarafa İstek Gönder
  Future<void> _connect() async {
    final code = _controller.text.trim().toUpperCase();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc('Lütfen 6 haneli kodu gir.', 'Please enter the 6-character code.'))),
      );
      return;
    }

    if (code == _myCode) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc('Kendi kodunuzu giremezsiniz.', 'You cannot enter your own code.'))),
      );
      return;
    }

    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();

    try {
      final partnerData = await DatabaseService().lookupInviteCode(code);
      if (partnerData == null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc('Bu koda ait partner bulunamadı. Lütfen kontrol et.', 'No partner found with this code. Please check again.'))),
        );
        return;
      }

      final targetUid = partnerData['uid'] as String;
      final targetName = partnerData['name'] as String? ?? loc('Partnerin', 'Your Partner');

      // İsteği gönder
      await DatabaseService().sendPairRequest(
        targetUid: targetUid,
        myName: ref.read(userNameProvider),
        myAvatar: ref.read(userAvatarProvider),
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _waitingMessage = loc('$targetName onaylaması bekleniyor... ⏳', 'Waiting for $targetName to approve... ⏳');
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc('$targetName kullanıcısına istek gönderildi! Karşı telefon onayladığında bağlanacaksınız.', 'Request sent to $targetName! You will connect once confirmed.'))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      String errorMsg = e.toString().replaceAll('Exception: ', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  errorMsg,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: (errorMsg.contains('engelledi') || errorMsg.toLowerCase().contains('block')) ? const Color(0xFFEF4444) : const Color(0xFF333333),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        if (widget.onBack != null)
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: widget.onBack,
            ),
          ),
        Text(loc('Partnerini bağla', 'Connect your partner'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          loc(
            'QR kodunu partnerine göster ya da kodunu paylaş. İstersen onun kodunu girebilirsin.',
            'Show the QR code to your partner or share your code. You can also enter their code below.',
          ),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: LoveraColors.textMuted, height: 1.4),
        ),
        const SizedBox(height: 24),

        // QR Kartı
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: theme.dividerColor),
            boxShadow: AppTheme.ambientShadow,
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: _myCode == '...'
                    ? SizedBox(
                        width: 170,
                        height: 170,
                        child: Center(child: CircularProgressIndicator(color: LoveraColors.primary)),
                      )
                    : QrImageView(
                        data: 'lovera://pair/$_myCode',
                        size: 170,
                        eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.circle, color: LoveraColors.textDark),
                        dataModuleStyle: QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.circle, color: LoveraColors.textDark),
                      ),
              ),
              const SizedBox(height: 16),
              Text(_myCode,
                  style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900, letterSpacing: 6, color: LoveraColors.primary)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _copy,
                    icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 18),
                    label: Text(_copied ? loc('Kopyalandı', 'Copied') : loc('Kodu kopyala', 'Copy code')),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _isRefreshingCode ? null : _refreshCode,
                    icon: _isRefreshingCode
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: LoveraColors.primary),
                          )
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(loc('Kodu Yenile', 'Refresh Code')),
                  ),
                ],
              ),
            ],
          ),
        ).animate().fadeIn().slideY(begin: 0.05),
        const SizedBox(height: 20),

        Row(children: [
          Expanded(child: Divider(color: theme.dividerColor)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(loc('VEYA', 'OR'), style: theme.textTheme.labelSmall?.copyWith(color: LoveraColors.textMuted)),
          ),
          Expanded(child: Divider(color: theme.dividerColor)),
        ]),
        const SizedBox(height: 20),

        TextField(
          controller: _controller,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          maxLength: 6,
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 6, color: isDark ? null : LoveraColors.textDark),
          decoration: InputDecoration(
            hintText: loc('Partnerin kodu', 'Partner\'s code'),
            counterText: '',
            hintStyle: const TextStyle(letterSpacing: 0, fontWeight: FontWeight.w400),
          ),
        ),
        const SizedBox(height: 14),

        if (_waitingMessage != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: LoveraColors.secondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: LoveraColors.secondary),
                ),
                const SizedBox(width: 10),
                Text(
                  _waitingMessage!,
                  style: TextStyle(fontWeight: FontWeight.w600, color: LoveraColors.textDark),
                ),
              ],
            ),
          ),

        FilledButton(
          onPressed: _isLoading ? null : _connect,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(loc('Bağlan', 'Connect')),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: widget.onDone,
          child: Text(widget.skipLabel ?? loc('Şimdilik atla', 'Skip for now'), style: TextStyle(color: LoveraColors.textMuted)),
        ),
      ],
    );
  }
}

/// Dashboard'dan açılan bağımsız eşleşme ekranı.
class PairingView extends StatelessWidget {
  const PairingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(loc('Eşleşme', 'Pairing'))),
      body: LoveraThemeBackground(
        child: SafeArea(
          child: PairingContent(onDone: () => Navigator.of(context).pop(), skipLabel: loc('Kapat', 'Close')),
        ),
      ),
    );
  }
}
