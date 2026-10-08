import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../../../core/models/models.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';

class ChatView extends ConsumerStatefulWidget {
  const ChatView({super.key, this.onBackToHome});
  final VoidCallback? onBackToHome;

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();

  ChatMessage? _replyingTo;
  bool _isSending = false;
  bool _isRecordingAudio = false;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  bool _isTyping = false;

  void _onTextChanged(String val, String? coupleId) {
    if (coupleId != null && coupleId.isNotEmpty) {
      final isNowTyping = val.trim().isNotEmpty;
      if (isNowTyping != _isTyping) {
        _isTyping = isNowTyping;
        DatabaseService().setTypingStatus(coupleId, isNowTyping);
      }
    }
  }

  Future<void> _send({String? type, String? mediaBase64}) async {
    final coupleId = ref.read(coupleIdProvider);
    final partnerUid = ref.read(partnerUidProvider);
    final myName = ref.read(userNameProvider);

    if (coupleId == null || coupleId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mesaj gönderebilmek için önce partnerinizle eşleşmeniz gerekir.'),
          backgroundColor: LoveraColors.primary,
        ),
      );
      return;
    }

    final text = _textController.text.trim();
    if (text.isEmpty && mediaBase64 == null && type != 'heart') return;

    final replyText = _replyingTo?.text;
    final replySender = _replyingTo != null
        ? (_replyingTo!.senderId == DatabaseService().uid ? 'Sen' : (ref.read(partnerProvider)?.name ?? 'Partner'))
        : null;

    _textController.clear();
    setState(() {
      _replyingTo = null;
      _isSending = true;
    });

    DatabaseService().setTypingStatus(coupleId, false);

    try {
      final msgId = await DatabaseService().sendMessage(
        coupleId: coupleId,
        text: type == 'heart' ? '❤️' : text,
        mediaBase64: mediaBase64,
        type: type ?? (mediaBase64 != null ? 'image' : 'text'),
        replyToText: replyText,
        replyToSender: replySender,
      );

      // Partnerin telefonuna bildirim gönder
      if (partnerUid != null && partnerUid.isNotEmpty) {
        String pushBody = text.isNotEmpty ? text : (type == 'heart' ? 'Sana bir kalp gönderdi ❤️' : 'Bir fotoğraf gönderdi 📸');
        final dataPayload = <String, String>{
          'type': 'chat_message',
          'coupleId': coupleId,
        };
        if (msgId != null) {
          dataPayload['messageId'] = msgId;
        }
        NotificationService().sendPushToPartner(
          partnerUid: partnerUid,
          title: myName.isNotEmpty ? myName : 'Partnerin',
          body: pushBody,
          data: dataPayload,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mesaj gönderilemedi: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 900,
        maxHeight: 900,
        imageQuality: 65,
      );
      if (picked != null) {
        setState(() => _isSending = true);
        final bytes = await picked.readAsBytes();
        final base64Img = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        await _send(type: 'image', mediaBase64: base64Img);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotoğraf seçilemedi: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picked = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 30),
      );
      if (picked != null) {
        final file = File(picked.path);
        final fileSize = await file.length();
        // Firestore doküman boyutu 1MB sınırına uygunluk kontrolü
        if (fileSize > 850 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Video boyutu çok büyük (en fazla 1 MB / kısa video gönderebilirsiniz).'),
                backgroundColor: LoveraColors.primary,
              ),
            );
          }
          return;
        }

        setState(() => _isSending = true);
        final bytes = await file.readAsBytes();
        final base64Vid = 'data:video/mp4;base64,${base64Encode(bytes)}';
        await _send(type: 'video', mediaBase64: base64Vid);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video seçilemedi: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _toggleAudioRecord() async {
    if (_isRecordingAudio) {
      // Kaydı durdur ve gönder
      try {
        final path = await _audioRecorder.stop();
        setState(() => _isRecordingAudio = false);
        if (path != null) {
          final file = File(path);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final base64Audio = 'data:audio/m4a;base64,${base64Encode(bytes)}';
            await _send(type: 'audio', mediaBase64: base64Audio);
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ses kaydı tamamlanamadı: $e')),
          );
        }
      }
    } else {
      // Kaydı başlat
      try {
        final hasPermission = await _audioRecorder.hasPermission();
        if (!hasPermission) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Mikrofon izni verilmedi.')),
            );
          }
          return;
        }

        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 32000,
            sampleRate: 22050,
          ),
          path: filePath,
        );

        HapticFeedback.heavyImpact();
        setState(() {
          _isRecordingAudio = true;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ses kaydedici başlatılamadı: $e')),
          );
        }
      }
    }
  }

  Future<void> _cancelAudioRecord() async {
    try {
      await _audioRecorder.stop();
    } catch (_) {}
    setState(() => _isRecordingAudio = false);
  }

  void _sendQuickHeart() {
    _send(type: 'heart');
  }

  ImageProvider? _getAvatarProvider(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('data:image')) {
      try {
        final base64String = path.split(',').last;
        return MemoryImage(base64Decode(base64String));
      } catch (_) {
        return null;
      }
    } else if (path.startsWith('http')) {
      return NetworkImage(path);
    } else {
      final f = File(path);
      if (f.existsSync()) return FileImage(f);
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final partner = ref.watch(partnerProvider);
    final partnerUid = ref.watch(partnerUidProvider);
    final coupleId = ref.watch(coupleIdProvider);
    final myUid = DatabaseService().uid;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F1015) : const Color(0xFFF7F8FA),
        appBar: AppBar(
          backgroundColor: isDark ? const Color(0xFF161822) : Colors.white,
          elevation: 0.5,
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () {
              FocusScope.of(context).unfocus();
              if (widget.onBackToHome != null) {
                widget.onBackToHome!();
              } else {
                Navigator.of(context).maybePop();
              }
            },
          ),
          title: partnerUid != null && partnerUid.isNotEmpty
              ? StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: DatabaseService().partnerStream(partnerUid),
                  builder: (context, snapshot) {
                    final pData = snapshot.data?.data();
                    final pName = pData?['name'] as String? ?? partner?.name ?? 'Partneriniz';
                    final pAvatar = pData?['avatarUrl'] as String? ?? partner?.avatarUrl;
                    final pIsOpen = pData?['isAppOpen'] as bool? ?? partner?.isAppOpen ?? false;
                    
                    DateTime? pLastActive;
                    final rawLast = pData?['lastActive'] ?? partner?.lastActive;
                    if (rawLast is DateTime) {
                      pLastActive = rawLast;
                    } else if (rawLast is String) {
                      pLastActive = DateTime.tryParse(rawLast);
                    } else if (rawLast != null) {
                      try {
                        pLastActive = (rawLast as dynamic).toDate?.call();
                      } catch (_) {}
                    }

                    final isLiveOnline = pIsOpen &&
                        (pLastActive == null ||
                            DateTime.now().toUtc().difference(pLastActive.toUtc()).abs().inMinutes < 2);

                    return Row(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: LoveraColors.primarySoft.withValues(alpha: 0.2),
                              backgroundImage: _getAvatarProvider(pAvatar),
                              child: _getAvatarProvider(pAvatar) == null
                                  ? Text(
                                      pName.isNotEmpty ? pName[0].toUpperCase() : '?',
                                      style: const TextStyle(fontWeight: FontWeight.w800, color: LoveraColors.primary),
                                    )
                                  : null,
                            ),
                            if (isLiveOnline)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isDark ? const Color(0xFF161822) : Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pName,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              if (coupleId != null)
                                StreamBuilder<bool>(
                                  stream: DatabaseService().typingStatusStream(coupleId, partnerUid),
                                  builder: (context, snap) {
                                    final isTyping = snap.data == true;
                                    if (isTyping) {
                                      return const Text(
                                        'yazıyor...',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: LoveraColors.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      );
                                    }
                                    String statusSubtitle;
                                    if (isLiveOnline) {
                                      statusSubtitle = 'Çevrimiçi';
                                    } else if (pLastActive != null) {
                                      final diff = DateTime.now().toUtc().difference(pLastActive.toUtc()).abs();
                                      if (diff.inMinutes < 1) {
                                        statusSubtitle = '1 dk önce aktifti';
                                      } else if (diff.inMinutes < 60) {
                                        statusSubtitle = '${diff.inMinutes} dk önce aktifti';
                                      } else if (diff.inHours < 24) {
                                        statusSubtitle = '${diff.inHours} sa önce aktifti';
                                      } else {
                                        statusSubtitle = '${diff.inDays} gün önce aktifti';
                                      }
                                    } else {
                                      statusSubtitle = 'Çevrimdışı';
                                    }

                                    return Text(
                                      statusSubtitle,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isLiveOnline ? const Color(0xFF10B981) : LoveraColors.textMuted,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    );
                                  },
                                )
                              else
                                const Text(
                                  'Eşleşme bekleniyor',
                                  style: TextStyle(fontSize: 12, color: LoveraColors.textMuted),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                )
              : const Text('Partner bekleniyor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              icon: const Icon(Icons.favorite_rounded, color: LoveraColors.primary),
              tooltip: 'Aşk Kalbi Gönder',
              onPressed: _sendQuickHeart,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
        child: Column(
          children: [
            // Mesaj Listesi
            Expanded(
              child: coupleId == null || coupleId.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: LoveraColors.primarySoft.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.chat_bubble_outline_rounded,
                                  size: 48, color: LoveraColors.primary),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Özel Sohbet Alanınız',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Partnerinizle eşleştiğinizde tüm mesajlarınız, fotoğraflarınız ve hisleriniz burada anlık olarak akacaktır.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: LoveraColors.textMuted, height: 1.45),
                            ),
                          ],
                        ),
                      ),
                    )
                  : StreamBuilder<List<ChatMessage>>(
                      stream: DatabaseService().messagesStream(coupleId),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final messages = snapshot.data ?? [];

                        // Karşı tarafın gönderdiği okunmamış mesajlar varsa hemen okundu olarak işaretle
                        final unreadIds = messages
                            .where((m) => m.senderId != myUid && !m.isRead)
                            .map((m) => m.id)
                            .toList();
                        if (unreadIds.isNotEmpty) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            DatabaseService().markMessagesAsRead(coupleId, unreadIds);
                          });
                        }

                        if (messages.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.mark_chat_unread_rounded,
                                    size: 54, color: LoveraColors.primarySoft),
                                const SizedBox(height: 12),
                                Text(
                                  'Henüz mesaj yok',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'İlk mesajı atarak sohbeti başlatın! 💌',
                                  style: TextStyle(color: LoveraColors.textMuted),
                                ),
                              ],
                            ).animate().fadeIn(duration: 400.ms),
                          );
                        }

                        return ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[index];
                            final isMe = msg.senderId == myUid;
                            return _ChatBubble(
                              message: msg,
                              isMe: isMe,
                              onReply: () {
                                setState(() => _replyingTo = msg);
                              },
                              onDelete: isMe
                                  ? () => DatabaseService().deleteMessage(coupleId, msg.id)
                                  : null,
                            );
                          },
                        );
                      },
                    ),
            ),

            // Yanıtlama (Reply) Önizleme Barı
            if (_replyingTo != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: isDark ? const Color(0xFF1B1D28) : const Color(0xFFEEF0F5),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 36,
                      decoration: BoxDecoration(
                        color: LoveraColors.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _replyingTo!.senderId == myUid ? 'Sen' : (partner?.name ?? 'Partner'),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: LoveraColors.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _replyingTo!.type == 'image' ? '📷 Fotoğraf' : _replyingTo!.text,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => setState(() => _replyingTo = null),
                    ),
                  ],
                ),
              ).animate().slideY(begin: 0.2, duration: 200.ms).fadeIn(),

            // Giriş Alanı (Input Bar)
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF161822) : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    offset: const Offset(0, -2),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: _isRecordingAudio
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.mic_rounded, color: Colors.redAccent, size: 24)
                              .animate(onPlay: (c) => c.repeat(reverse: true))
                              .scale(begin: const Offset(1, 1), end: const Offset(1.2, 1.2), duration: 500.ms),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Ses kaydediliyor...',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: LoveraColors.textMuted),
                            tooltip: 'İptal Et',
                            onPressed: _cancelAudioRecord,
                          ),
                          IconButton(
                            icon: const Icon(Icons.send_rounded, color: Colors.redAccent),
                            tooltip: 'Sesli Mesajı Gönder',
                            onPressed: _toggleAudioRecord,
                          ),
                        ],
                      ),
                    )
                  : Row(
                      children: [
                        // Fotoğraf Ekle Butonu
                        IconButton(
                          icon: const Icon(Icons.photo_rounded, color: LoveraColors.secondary, size: 22),
                          onPressed: _pickImage,
                          tooltip: 'Fotoğraf Gönder',
                        ),

                        // Video Ekle Butonu
                        IconButton(
                          icon: const Icon(Icons.videocam_rounded, color: LoveraColors.accentViolet, size: 24),
                          onPressed: _pickVideo,
                          tooltip: 'Video Gönder',
                        ),

                        // Hızlı Kalp Butonu
                        IconButton(
                          icon: const Icon(Icons.favorite_rounded, color: LoveraColors.primary, size: 22),
                          onPressed: _sendQuickHeart,
                          tooltip: 'Kalp Gönder',
                        ),

                        // Metin Alanı
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF232635) : const Color(0xFFF1F3F7),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: TextField(
                              controller: _textController,
                              onChanged: (val) {
                                setState(() {});
                                _onTextChanged(val, coupleId);
                              },
                              textCapitalization: TextCapitalization.sentences,
                              maxLines: 4,
                              minLines: 1,
                              decoration: const InputDecoration(
                                hintText: 'Mesaj yaz...',
                                hintStyle: TextStyle(color: LoveraColors.textMuted, fontSize: 14),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 6),

                        // Metin doluysa Gönder, boşsa Ses Kayıt Butonu
                        _textController.text.trim().isNotEmpty
                            ? GestureDetector(
                                onTap: _isSending ? null : () => _send(),
                                child: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    gradient: LoveraColors.primaryGradient,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: LoveraColors.primary.withValues(alpha: 0.35),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
                                  ),
                                ),
                              )
                            : GestureDetector(
                                onTap: _toggleAudioRecord,
                                child: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: LoveraColors.primary.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.mic_rounded, color: LoveraColors.primary, size: 22),
                                  ),
                                ),
                              ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.isMe,
    required this.onReply,
    this.onDelete,
  });

  final ChatMessage message;
  final bool isMe;
  final VoidCallback onReply;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeStr =
        '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}';

    final bubbleColor = isMe
        ? LoveraColors.primary
        : (isDark ? const Color(0xFF222533) : const Color(0xFFE9ECF2));

    final textColor = isMe
        ? Colors.white
        : (isDark ? Colors.white : const Color(0xFF1E2024));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.76,
            ),
            child: GestureDetector(
              onLongPress: () {
                showModalBottomSheet(
                  context: context,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (ctx) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.reply_rounded),
                          title: const Text('Yanıtla'),
                          onTap: () {
                            Navigator.pop(ctx);
                            onReply();
                          },
                        ),
                        if (onDelete != null)
                          ListTile(
                            leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                            title: const Text('Mesajı Sil', style: TextStyle(color: Colors.redAccent)),
                            onTap: () {
                              Navigator.pop(ctx);
                              onDelete!();
                            },
                          ),
                      ],
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMe ? 18 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    // Yanıtlanan mesaj kutucuğu
                    if (message.replyToText != null && message.replyToText!.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: isMe ? 0.18 : 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message.replyToSender ?? 'Yanıtlanan',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isMe ? Colors.white70 : LoveraColors.primary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              message.replyToText!,
                              style: TextStyle(
                                fontSize: 12,
                                color: isMe ? Colors.white.withValues(alpha: 0.9) : LoveraColors.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                    // Mesaj İçeriği: Görsel, Video, Sesli Mesaj, Kalp veya Metin
                    if (message.type == 'image' && message.mediaBase64 != null) ...[
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => FullScreenImageViewer(
                                imageBase64: message.mediaBase64!,
                              ),
                            ),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Image.memory(
                                base64Decode(message.mediaBase64!.split(',').last),
                                fit: BoxFit.cover,
                                height: 210,
                                width: double.infinity,
                              ),
                              Container(
                                margin: const EdgeInsets.all(8),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.zoom_in_rounded, color: Colors.white, size: 14),
                                    SizedBox(width: 4),
                                    Text('Büyüt', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (message.text.isNotEmpty) const SizedBox(height: 6),
                    ],

                    if (message.type == 'video' && message.mediaBase64 != null) ...[
                      VideoBubblePlayer(
                        videoBase64: message.mediaBase64!,
                        isMe: isMe,
                      ),
                      if (message.text.isNotEmpty) const SizedBox(height: 6),
                    ],

                    if (message.type == 'audio' && message.mediaBase64 != null) ...[
                      VoiceMessagePlayer(
                        audioBase64: message.mediaBase64!,
                        isMe: isMe,
                      ),
                      if (message.text.isNotEmpty) const SizedBox(height: 6),
                    ],

                    if (message.type == 'heart')
                      const Text(
                        '❤️',
                        style: TextStyle(fontSize: 38),
                      )
                    else if (message.text.isNotEmpty)
                      Text(
                        message.text,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.35,
                          color: textColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                    const SizedBox(height: 4),

                    // Zaman ve İletildi Simgesi
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isMe ? Colors.white70 : LoveraColors.textMuted,
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          Icon(
                            (message.isDelivered || message.isRead)
                                ? Icons.done_all_rounded
                                : Icons.done_rounded,
                            size: (message.isDelivered || message.isRead) ? 15 : 13,
                            color: message.isRead
                                ? const Color(0xFF38BDF8)
                                : Colors.white60,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fotoğraf Büyütme ve Galeriye Kaydetme Ekranı
class FullScreenImageViewer extends StatefulWidget {
  const FullScreenImageViewer({super.key, required this.imageBase64});
  final String imageBase64;

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  bool _isSaving = false;

  Future<void> _saveToGallery() async {
    setState(() => _isSaving = true);
    try {
      final raw = widget.imageBase64.split(',').last;
      final bytes = base64Decode(raw);

      // Galeriye kaydet
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        await Gal.requestAccess();
      }

      await Gal.putImageBytes(bytes, name: 'lovera_${DateTime.now().millisecondsSinceEpoch}.jpg');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fotoğraf galeriye kaydedildi! 📸✨'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fotoğraf kaydedilemedi: $e'),
            backgroundColor: LoveraColors.primary,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = base64Decode(widget.imageBase64.split(',').last);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Fotoğraf', style: TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.download_rounded, color: Colors.white),
                  tooltip: 'Cihaza Kaydet',
                  onPressed: _saveToGallery,
                ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4.0,
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

/// Sohbet Baloncuğunda Video Oynatıcı
class VideoBubblePlayer extends StatefulWidget {
  const VideoBubblePlayer({
    super.key,
    required this.videoBase64,
    required this.isMe,
  });

  final String videoBase64;
  final bool isMe;

  @override
  State<VideoBubblePlayer> createState() => _VideoBubblePlayerState();
}

class _VideoBubblePlayerState extends State<VideoBubblePlayer> {
  VideoPlayerController? _controller;
  File? _tempFile;
  bool _isInit = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final raw = widget.videoBase64.split(',').last;
      final bytes = base64Decode(raw);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/temp_vid_${DateTime.now().millisecondsSinceEpoch}.mp4');
      await file.writeAsBytes(bytes);
      _tempFile = file;

      final ctrl = VideoPlayerController.file(file);
      await ctrl.initialize();
      if (mounted) {
        setState(() {
          _controller = ctrl;
          _isInit = true;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller?.dispose();
    _tempFile?.delete().catchError((_) => _tempFile!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInit || _controller == null) {
      return Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: _controller!.value.aspectRatio > 0 ? _controller!.value.aspectRatio : 16 / 9,
            child: VideoPlayer(_controller!),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                if (_controller!.value.isPlaying) {
                  _controller!.pause();
                } else {
                  _controller!.play();
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _controller!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sesli Mesaj Dinleme Widget'ı
class VoiceMessagePlayer extends StatefulWidget {
  const VoiceMessagePlayer({
    super.key,
    required this.audioBase64,
    required this.isMe,
  });

  final String audioBase64;
  final bool isMe;

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  File? _tempFile;

  @override
  void initState() {
    super.initState();
    _setupAudio();
  }

  Future<void> _setupAudio() async {
    try {
      final raw = widget.audioBase64.split(',').last;
      final bytes = base64Decode(raw);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
      await file.writeAsBytes(bytes);
      _tempFile = file;

      _player.onPlayerStateChanged.listen((state) {
        if (mounted) {
          setState(() => _isPlaying = state == PlayerState.playing);
        }
      });

      _player.onDurationChanged.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      });

      _player.onPositionChanged.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _player.dispose();
    _tempFile?.delete().catchError((_) => _tempFile!);
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      if (_tempFile != null && await _tempFile!.exists()) {
        await _player.play(DeviceFileSource(_tempFile!.path));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.isMe ? Colors.white : LoveraColors.primary;
    final textColor = widget.isMe ? Colors.white.withValues(alpha: 0.9) : LoveraColors.textMuted;

    final posSec = _position.inSeconds;
    final durSec = _duration.inSeconds > 0 ? _duration.inSeconds : 0;
    final timeStr = '${(posSec ~/ 60).toString().padLeft(2, '0')}:${(posSec % 60).toString().padLeft(2, '0')} / ${(durSec ~/ 60).toString().padLeft(2, '0')}:${(durSec % 60).toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      width: 220,
      child: Row(
        children: [
          IconButton(
            icon: Icon(_isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
            color: iconColor,
            iconSize: 38,
            onPressed: _togglePlay,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: durSec > 0 ? (posSec / durSec).clamp(0.0, 1.0) : 0.0,
                    backgroundColor: Colors.white24,
                    valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
