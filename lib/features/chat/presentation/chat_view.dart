import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';

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

  ChatMessage? _replyingTo;
  bool _isSending = false;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
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
    final coupleId = ref.read(coupleIdProvider) ??
        ref.read(currentUserProvider)?.coupleId;
    final partnerUid = ref.read(partnerUidProvider) ??
        ref.read(partnerProvider)?.id ??
        ref.read(currentUserProvider)?.partnerUid;
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
    final partnerUid = ref.watch(partnerUidProvider) ??
        partner?.id ??
        ref.watch(currentUserProvider)?.partnerUid;
    final coupleId = ref.watch(coupleIdProvider) ??
        ref.watch(currentUserProvider)?.coupleId;
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
              child: Row(
                children: [
                  // Fotoğraf Ekle Butonu
                  IconButton(
                    icon: const Icon(Icons.photo_rounded, color: LoveraColors.secondary, size: 24),
                    onPressed: _pickImage,
                    tooltip: 'Fotoğraf Gönder',
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
                        onChanged: (val) => _onTextChanged(val, coupleId),
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

                  const SizedBox(width: 8),

                  // Gönder Butonu (ValueListenableBuilder ile sadece buton dinlenir, tüm sayfa rebuild olmaz)
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _textController,
                    builder: (context, val, _) {
                      final hasText = val.text.trim().isNotEmpty;
                      return GestureDetector(
                        onTap: (hasText && !_isSending) ? () => _send() : null,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: hasText ? 1.0 : 0.4,
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              gradient: LoveraColors.primaryGradient,
                              shape: BoxShape.circle,
                              boxShadow: hasText
                                  ? [
                                      BoxShadow(
                                        color: LoveraColors.primary.withValues(alpha: 0.35),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: const Center(
                              child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      );
                    },
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

                    // Mesaj İçeriği: Görsel veya Metin
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
                              _ChatImageBubble(
                                messageId: message.id,
                                mediaBase64: message.mediaBase64!,
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

/// Önbellekli ve Flaşlamayan Sohbet Görseli Widget'ı
class _ChatImageBubble extends StatelessWidget {
  const _ChatImageBubble({
    required this.messageId,
    required this.mediaBase64,
  });

  final String messageId;
  final String mediaBase64;

  // Ayrıştırılmış baytları hafızada tutarak her klavye tuşunda tekrar decode ve flaşlamayı önler
  static final Map<String, Uint8List> _imageCache = <String, Uint8List>{};

  Uint8List _getBytes() {
    if (_imageCache.containsKey(messageId)) {
      return _imageCache[messageId]!;
    }
    final raw = mediaBase64.split(',').last;
    final bytes = base64Decode(raw);
    _imageCache[messageId] = bytes;
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _getBytes();
    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      height: 210,
      width: double.infinity,
      gaplessPlayback: true,
      cacheWidth: 800,
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
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}

