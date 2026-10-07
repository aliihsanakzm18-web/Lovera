import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      await DatabaseService().sendMessage(
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
        NotificationService().sendPushToPartner(
          partnerUid: partnerUid,
          title: myName.isNotEmpty ? myName : 'Partnerin',
          body: pushBody,
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
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 70,
    );
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      final base64Img = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      await _send(type: 'image', mediaBase64: base64Img);
    }
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

    final isPartnerOnline = partner != null &&
        partner.isAppOpen == true &&
        partner.lastActive != null &&
        DateTime.now().difference(partner.lastActive!).inMinutes < 2;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F1015) : const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF161822) : Colors.white,
        elevation: 0.5,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: widget.onBackToHome ?? () => Navigator.of(context).maybePop(),
        ),
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: LoveraColors.primarySoft.withValues(alpha: 0.2),
                  backgroundImage: _getAvatarProvider(partner?.avatarUrl),
                  child: _getAvatarProvider(partner?.avatarUrl) == null
                      ? Text(
                          partner?.name.isNotEmpty == true ? partner!.name[0].toUpperCase() : '?',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: LoveraColors.primary),
                        )
                      : null,
                ),
                if (isPartnerOnline)
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
                    partner?.name ?? 'Partneriniz',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  if (coupleId != null && partnerUid != null)
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
                        return Text(
                          isPartnerOnline
                              ? 'Çevrimiçi'
                              : (partner?.lastActive != null
                                  ? '${DateTime.now().difference(partner!.lastActive!).inMinutes} dk önce aktifti'
                                  : 'Çevrimdışı'),
                          style: TextStyle(
                            fontSize: 12,
                            color: isPartnerOnline ? const Color(0xFF10B981) : LoveraColors.textMuted,
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
        ),
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
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
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
                    icon: const Icon(Icons.photo_rounded, color: LoveraColors.secondary),
                    onPressed: _pickImage,
                    tooltip: 'Fotoğraf Gönder',
                  ),

                  // Hızlı Kalp Butonu
                  IconButton(
                    icon: const Icon(Icons.favorite_rounded, color: LoveraColors.primary),
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

                  // Gönder Butonu
                  GestureDetector(
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
                  ),
                ],
              ),
            ),
          ],
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

                    // Mesaj İçeriği: Görsel veya Kalp veya Metin
                    if (message.type == 'image' && message.mediaBase64 != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          base64Decode(message.mediaBase64!.split(',').last),
                          fit: BoxFit.cover,
                          height: 200,
                          width: double.infinity,
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
                            message.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                            size: 13,
                            color: message.isRead ? Colors.lightBlueAccent : Colors.white70,
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
