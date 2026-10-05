import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/services/database_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';

/// Eşleşme içeriği (onboarding ve ayrı ekranda ortak kullanılır).
class PairingContent extends ConsumerStatefulWidget {
  const PairingContent({
    super.key,
    required this.onDone,
    this.onBack,
    this.skipLabel = 'Şimdilik atla',
  });
  final VoidCallback onDone;
  final VoidCallback? onBack;
  final String skipLabel;

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
        if (outReq['status'] == 'accepted') {
          _handlePairSuccess(data['coupleId'], outReq['toUid']);
        } else if (outReq['status'] == 'rejected') {
          setState(() {
            _isLoading = false;
            _waitingMessage = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Eşleşme isteği reddedildi.')),
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

  // Gelen Eşleşme İsteği Onay Penceresi (Fotoğraf ve İsim ile)
  Future<void> _showIncomingRequestDialog(Map<String, dynamic> req) async {
    _dialogOpen = true;
    final requesterUid = req['fromUid'] as String;
    final requesterName = req['fromName'] as String? ?? 'Partnerin';
    final requesterAvatar = req['fromAvatar'] as String?;

    DateTime selectedDate = DateTime.now();

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
          final diff = DateTime.now().difference(selectedDate);
          final days = (diff.inHours / 24).floor() + 1;

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
                  radius: 36,
                  backgroundColor: LoveraColors.primary.withValues(alpha: 0.15),
                  child: requesterAvatar != null
                      ? ClipOval(child: Image.network(requesterAvatar, width: 72, height: 72, fit: BoxFit.cover))
                      : Text(
                          requesterName.isNotEmpty ? requesterName[0].toUpperCase() : '?',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: LoveraColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                Text(
                  '$requesterName Seninle Eşleşmek İstiyor! 💕',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Onayladığında ikinize özel ortak alanınız açılacak. İlişki başlangıç tarihinizi seçebilirsiniz.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: LoveraColors.textMuted, height: 1.3),
                ),
                const SizedBox(height: 20),

                // Tarih Seçici Butonu
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: sheetCtx,
                      initialDate: selectedDate,
                      firstDate: DateTime(1990),
                      lastDate: DateTime.now(),
                      helpText: 'İlişki Başlangıç Tarihi',
                    );
                    if (picked != null) {
                      setSheetState(() => selectedDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: LoveraColors.lightSurfaceAlt,
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                      border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_month_rounded, color: LoveraColors.primary),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('BİRLİKTELİK BAŞLANGICI',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                        color: LoveraColors.textMuted, fontWeight: FontWeight.w700)),
                                Text(
                                  '${selectedDate.day}.${selectedDate.month}.${selectedDate.year}',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: LoveraColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$days Gündür',
                            style: const TextStyle(
                              color: LoveraColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
                        child: const Text('Reddet'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.favorite_rounded, size: 18),
                        label: const Text('Kabul Et ve Bağlan'),
                        onPressed: () async {
                          Navigator.pop(sheetCtx);
                          _dialogOpen = false;
                          setState(() => _isLoading = true);

                          final coupleId = await DatabaseService().acceptPairRequest(
                            requesterUid: requesterUid,
                            relationshipStartDate: selectedDate,
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
              child: const Icon(Icons.favorite_rounded, color: LoveraColors.primary, size: 54),
            ).animate().scale(curve: Curves.elasticOut, duration: 600.ms),
            const SizedBox(height: 20),
            Text(
              'Eşleşme Başarılı! 🎉',
              style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              'Artık Lovera alanınız birbirinize bağlandı. Sonsuz anılar biriktirmeye hazırsınız!',
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
                child: const Text('Hemen Başla'),
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
        const SnackBar(content: Text('Lütfen 6 haneli kodu gir.')),
      );
      return;
    }

    if (code == _myCode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kendi kodunuzu giremezsiniz.')),
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
          const SnackBar(content: Text('Bu koda ait partner bulunamadı. Lütfen kontrol et.')),
        );
        return;
      }

      final targetUid = partnerData['uid'] as String;
      final targetName = partnerData['name'] as String? ?? 'Partnerin';

      // İsteği gönder
      await DatabaseService().sendPairRequest(
        targetUid: targetUid,
        myName: ref.read(userNameProvider),
        myAvatar: ref.read(userAvatarProvider),
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _waitingMessage = '$targetName onaylaması bekleniyor... ⏳';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$targetName kullanıcısına istek gönderildi! Karşı telefon onayladığında bağlanacaksınız.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
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
        Text('Partnerini bağla',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          'QR kodunu partnerine göster ya da kodunu paylaş. İstersen onun kodunu girebilirsin.',
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
                    ? const SizedBox(
                        width: 170,
                        height: 170,
                        child: Center(child: CircularProgressIndicator(color: LoveraColors.primary)),
                      )
                    : QrImageView(
                        data: 'lovera://pair/$_myCode',
                        size: 170,
                        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: LoveraColors.textDark),
                        dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.circle, color: LoveraColors.textDark),
                      ),
              ),
              const SizedBox(height: 16),
              Text(_myCode,
                  style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900, letterSpacing: 6, color: LoveraColors.primary)),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _copy,
                icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 18),
                label: Text(_copied ? 'Kopyalandı' : 'Kodu kopyala'),
              ),
            ],
          ),
        ).animate().fadeIn().slideY(begin: 0.05),
        const SizedBox(height: 20),

        Row(children: [
          Expanded(child: Divider(color: theme.dividerColor)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text('VEYA', style: theme.textTheme.labelSmall?.copyWith(color: LoveraColors.textMuted)),
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
            hintText: 'Partnerin kodu',
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
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: LoveraColors.secondary),
                ),
                const SizedBox(width: 10),
                Text(
                  _waitingMessage!,
                  style: const TextStyle(fontWeight: FontWeight.w600, color: LoveraColors.textDark),
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
              : const Text('Bağlan'),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: widget.onDone,
          child: Text(widget.skipLabel, style: const TextStyle(color: LoveraColors.textMuted)),
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
      appBar: AppBar(title: const Text('Eşleşme')),
      body: SafeArea(
        child: PairingContent(onDone: () => Navigator.of(context).pop(), skipLabel: 'Kapat'),
      ),
    );
  }
}
