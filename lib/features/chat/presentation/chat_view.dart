import '../../../core/localization/app_strings.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/models/models.dart';
import '../../../core/services/background_slideshow_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/widget_sync_service.dart';
import '../../common/presentation/widgets/sticker_picker_sheet.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../common/presentation/widgets/background_source_selection_sheet.dart';
import '../../common/presentation/widgets/memory_background_picker_sheet.dart';
import '../../drawing/presentation/drawing_screen.dart';
import '../../../core/widgets/avatar_cache.dart';
import '../../../core/widgets/lovera_theme_background.dart';
import 'widgets/chat_media_gallery_sheet.dart';

class ChatView extends ConsumerStatefulWidget {
  const ChatView({super.key, this.onBackToHome, this.onOpenMap, this.isEmbedded = false});
  final VoidCallback? onBackToHome;
  final VoidCallback? onOpenMap;
  final bool isEmbedded;

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  ChatMessage? _replyingTo;
  AttachedLocation? _attachedLocation;
  bool _isSending = false;
  final Set<String> _alreadyMarkedReadIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendingText = ref.read(pendingChatInputTextProvider);
      if (pendingText != null && pendingText.isNotEmpty) {
        _textController.text = pendingText;
        _textController.selection = TextSelection.fromPosition(
          TextPosition(offset: pendingText.length),
        );
        ref.read(pendingChatInputTextProvider.notifier).state = null;
      }
      final pendingLoc = ref.read(pendingChatLocationAttachmentProvider);
      if (pendingLoc != null) {
        setState(() {
          _attachedLocation = pendingLoc;
        });
        ref.read(pendingChatLocationAttachmentProvider.notifier).state = null;
      }
    });

    ref.listenManual(pendingChatLocationAttachmentProvider, (prev, next) {
      if (next != null) {
        setState(() {
          _attachedLocation = next;
        });
        ref.read(pendingChatLocationAttachmentProvider.notifier).state = null;
      }
    });

    // Sohbete girildiğinde widget üzerindeki mesajları derhal temizle
    WidgetSyncService.clearWidgetMessages();

    // Eğer aktif bir chat slideshow konfigürasyonu varsa (veya bulutta ayarlandıysa) döngüyü sürdür
    final cId = ref.read(coupleIdProvider) ?? ref.read(currentUserProvider)?.coupleId;
    if (cId != null && cId.isNotEmpty) {
      BackgroundSlideshowService().getConfig('chat', coupleId: cId).then((cfg) {
        if (cfg.isEnabled && mounted) {
          DatabaseService().getMemoriesOnce(cId).then((mems) {
            if (mounted) {
              BackgroundSlideshowService().startChatSlideshow(
                coupleId: cId,
                memories: mems,
                config: cfg,
                onBgChanged: (_) {
                  if (mounted) setState(() {});
                },
              );
            }
          });
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetSyncService.clearWidgetMessages();
    _textController.dispose();
    _scrollController.dispose();
    BackgroundSlideshowService().stopChatTimerOnly();
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

  Future<void> _send({String? type, String? mediaBase64, String? customText}) async {
    final coupleId = ref.read(coupleIdProvider) ??
        ref.read(currentUserProvider)?.coupleId;
    final partnerUid = ref.read(partnerUidProvider) ??
        ref.read(partnerProvider)?.id;
    final myName = ref.read(userNameProvider);

    if (coupleId == null || coupleId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc('Mesaj gönderebilmek için önce partnerinizle eşleşmeniz gerekir.', 'You must pair with your partner before sending messages.')),
          backgroundColor: LoveraColors.primary,
        ),
      );
      return;
    }

    final text = customText ?? _textController.text.trim();
    final sendingLoc = _attachedLocation;
    if (text.isEmpty && mediaBase64 == null && type != 'heart' && sendingLoc == null) return;

    final replyText = _replyingTo?.text;
    final replySender = _replyingTo != null
        ? (_replyingTo!.senderId == DatabaseService().uid ? loc('Sen', 'You') : (ref.read(partnerProvider)?.name ?? loc('Partner', 'Partner')))
        : null;

    _textController.clear();
    setState(() {
      _replyingTo = null;
      _attachedLocation = null;
      _isSending = true;
    });

    DatabaseService().setTypingStatus(coupleId, false);

    try {
      final msgType = sendingLoc != null ? 'location' : (type ?? (mediaBase64 != null ? 'image' : 'text'));
      final msgId = await DatabaseService().sendMessage(
        coupleId: coupleId,
        text: type == 'heart' ? '❤️' : text,
        mediaBase64: mediaBase64,
        type: msgType,
        replyToText: replyText,
        replyToSender: replySender,
        locationLat: sendingLoc?.lat,
        locationLng: sendingLoc?.lng,
        locationTitle: sendingLoc?.title,
      );

      // Partnerin telefonuna bildirim gönder
      if (partnerUid != null && partnerUid.isNotEmpty) {
        String pushBodyTr;
        String pushBodyEn;
        if (text.isNotEmpty) {
          pushBodyTr = sendingLoc != null ? '📍 ${sendingLoc.title}: $text' : text;
          pushBodyEn = sendingLoc != null ? '📍 ${sendingLoc.title}: $text' : text;
        } else if (sendingLoc != null) {
          pushBodyTr = '📍 Konum paylaştı: ${sendingLoc.title}';
          pushBodyEn = '📍 Shared location: ${sendingLoc.title}';
        } else if (type == 'heart') {
          pushBodyTr = 'Sana bir kalp gönderdi ❤️';
          pushBodyEn = 'Sent you a heart ❤️';
        } else if (type == 'sticker') {
          pushBodyTr = 'Sana bir çıkartma gönderdi 🏷️';
          pushBodyEn = 'Sent you a sticker 🏷️';
        } else if (mediaBase64 != null || type == 'image') {
          pushBodyTr = 'Bir fotoğraf gönderdi 📸';
          pushBodyEn = 'Sent a photo 📸';
        } else {
          pushBodyTr = 'Yeni bir mesaj gönderdi 💬';
          pushBodyEn = 'Sent a new message 💬';
        }
        final dataPayload = <String, String>{
          'type': 'chat_message',
          'coupleId': coupleId,
        };
        if (msgId != null) {
          dataPayload['messageId'] = msgId;
        }
        final cleanSenderName = AppUser.extractFirstName(myName);
        final effectiveSenderTr = cleanSenderName.isNotEmpty ? cleanSenderName : 'Partnerin';
        final effectiveSenderEn = cleanSenderName.isNotEmpty ? cleanSenderName : 'Partner';
        NotificationService().sendPushToPartner(
          partnerUid: partnerUid,
          title: loc(effectiveSenderTr, effectiveSenderEn),
          body: loc(pushBodyTr, pushBodyEn),
          titleTr: effectiveSenderTr,
          titleEn: effectiveSenderEn,
          bodyTr: pushBodyTr,
          bodyEn: pushBodyEn,
          data: dataPayload,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc('Mesaj gönderilemedi: $e', 'Could not send message: $e'))),
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
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 50,
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
          SnackBar(content: Text(loc('Fotoğraf seçilemedi: $e', 'Could not select photo: $e'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  ImageProvider? _getAvatarProvider(String? path) {
    return AvatarCache.getProvider(path);
  }

  void _openChatOptionsSheet(String coupleId, {String? currentChatBg}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: LoveraColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.photo_library_rounded, color: LoveraColors.primary, size: 22),
                  ),
                  title: Text(
                    loc('Paylaşılan Fotoğraflar 📸', 'Shared Photos 📸'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    loc('Sohbetteki tüm fotoğrafları gör, indir veya albüme ekle', 'View, save or add all chat photos to album'),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    HapticFeedback.mediumImpact();
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => ChatMediaGallerySheet(
                        coupleId: coupleId,
                        onReplyToMessage: (ChatMessage msg) {
                          setState(() {
                            _replyingTo = msg;
                          });
                        },
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: LoveraColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.wallpaper_rounded, color: LoveraColors.primary, size: 22),
                  ),
                  title: Text(
                    loc('Sohbet Arka Planını Değiştir', 'Change Chat Background'),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    loc('İkiniz için de ortak sohbet arka planı belirler', 'Sets a shared chat background for both of you'),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    HapticFeedback.lightImpact();
                    BackgroundSourceSelectionSheet.show(
                      context: context,
                      title: loc('Sohbet Arka Planı', 'Chat Background'),
                      onSelectDevice: () async {
                        try {
                          final picker = ImagePicker();
                          final picked = await picker.pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 65,
                            maxWidth: 720,
                            maxHeight: 1280,
                          );
                          if (picked != null) {
                            final bytes = await File(picked.path).readAsBytes();
                            final base64Str = 'data:image/jpeg;base64,${base64Encode(bytes)}';
                            final myName = ref.read(userNameProvider);
                            // Cihazdan tekil fotoğraf seçildiğinde varsa slideshow'u durdur
                            await BackgroundSlideshowService().stopSlideshow('chat', coupleId: coupleId);
                            await DatabaseService().updateChatBackground(coupleId, base64Str, myName.isEmpty ? 'Partnerin' : myName);
                            if (mounted) setState(() {});
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(loc('Sohbet arka planı iki taraf için de güncellendi! 💕', 'Chat background updated for both sides! 💕')),
                                  backgroundColor: LoveraColors.secondary,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(loc('Fotoğraf eklenirken bir hata oluştu: $e', 'Error adding photo: $e')),
                                backgroundColor: const Color(0xFFEF4444),
                              ),
                            );
                          }
                        }
                      },
                      onSelectMemoryAlbum: () {
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.transparent,
                          isScrollControlled: true,
                          builder: (mCtx) => MemoryBackgroundPickerSheet(
                            coupleId: coupleId,
                            target: 'chat',
                            onSingleImageSelected: (base64Str) async {
                              final myName = ref.read(userNameProvider);
                              // Tekil anı fotoğrafı seçildiğinde slideshow'u durdur
                              await BackgroundSlideshowService().stopSlideshow('chat', coupleId: coupleId);
                              await DatabaseService().updateChatBackground(coupleId, base64Str, myName.isEmpty ? 'Partnerin' : myName);
                              if (mounted) setState(() {});
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(loc('Sohbet arka planı güncellendi! 💕', 'Chat background updated! 💕')),
                                    backgroundColor: LoveraColors.secondary,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                            onSlideshowConfigured: (config) {
                              // Slideshow başlat
                              DatabaseService().getMemoriesOnce(coupleId).then((mems) {
                                BackgroundSlideshowService().startChatSlideshow(
                                  coupleId: coupleId,
                                  memories: mems,
                                  config: config,
                                  onBgChanged: (newImg) {
                                    // Canlı UI güncellemesi
                                    if (mounted) setState(() {});
                                  },
                                );
                              });
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
                if (currentChatBg != null && currentChatBg.isNotEmpty) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.image_not_supported_rounded, color: Colors.orange, size: 22),
                    ),
                    title: Text(
                      loc('Arka Planı Sıfırla', 'Reset Background'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.orange,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      loc('Özel arka planı kaldırıp varsayılan temaya döner', 'Removes custom background and restores default theme'),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      try {
                        await BackgroundSlideshowService().stopSlideshow('chat', coupleId: coupleId);
                        await DatabaseService().removeChatBackground(coupleId);
                        if (mounted) setState(() {});
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(loc('Sohbet arka planı varsayılana döndürüldü.', 'Chat background restored to default.')),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(loc('Hata oluştu: $e', 'An error occurred: $e')),
                              backgroundColor: const Color(0xFFEF4444),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444), size: 22),
                  ),
                  title: Text(
                    loc('Sohbeti Temizle', 'Clear Chat'),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFEF4444),
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    loc('Tüm mesaj geçmişini iki taraf için de siler', 'Deletes all message history for both sides'),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (dCtx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: Text(loc('Sohbeti Temizle', 'Clear Chat')),
                        content: Text(
                          loc('Bu sohbetteki tüm mesajlar kalıcı olarak silinecek. Emin misiniz?', 'All messages in this chat will be deleted permanently. Are you sure?'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dCtx, false),
                            child: Text(loc('Vazgeç', 'Cancel')),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(dCtx, true),
                            child: Text(loc('Temizle', 'Clear')),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true && mounted) {
                      try {
                        await DatabaseService().clearChat(coupleId);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(loc('Sohbet başarıyla temizlendi 🧹', 'Chat cleared successfully 🧹')),
                              backgroundColor: const Color(0xFF10B981),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(loc('Sohbet temizlenirken hata oluştu: $e', 'Error while clearing chat: $e')),
                              backgroundColor: const Color(0xFFEF4444),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    }
                  },
                ),
                const Divider(height: 1),
                // Guideline 1.2: Kullanıcıyı Engelleme / Eşleşmeyi Sonlandırma (Block User)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.block_rounded, color: Colors.orange, size: 22),
                  ),
                  title: Text(
                    loc('Kullanıcıyı Engelle', 'Block User'),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.orange,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    loc('Partnerinizle eşleşmeyi ve iletişimi sonlandırır', 'Ends pairing and communication with your partner'),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? LoveraColors.darkTextMuted : LoveraColors.textMuted,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (dCtx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: Text(loc('Kullanıcıyı Engelle', 'Block User')),
                        content: Text(
                          loc('Bu kullanıcıyı engellemek ve eşleşmeyi derhal sonlandırmak istediğinize emin misiniz? Karşılıklı konum ve mesajlaşma anında durdurulur.', 'Are you sure you want to block this user and immediately end the connection? Location sharing and messaging will stop.'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dCtx, false),
                            child: Text(loc('Vazgeç', 'Cancel')),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(dCtx, true),
                            child: Text(loc('Engelle ve Ayrıl', 'Block & Leave')),
                          ),
                        ],
                      ),
                    );

                    final pUid = ref.read(partnerUidProvider) ?? ref.read(partnerProvider)?.id;
                    if (confirm == true && mounted && pUid != null) {
                      try {
                        await DatabaseService().blockAndUnpairPartner(
                          partnerUid: pUid,
                          coupleId: coupleId,
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(loc('Kullanıcı engellendi ve eşleşme sonlandırıldı.', 'User blocked and connection ended.')),
                              backgroundColor: Colors.orange,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(loc('İşlem başarısız: $e', 'Operation failed: $e')),
                              backgroundColor: const Color(0xFFEF4444),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final partner = ref.watch(partnerProvider);
    final partnerUid = ref.watch(partnerUidProvider) ??
        partner?.id;
    final coupleId = ref.watch(coupleIdProvider) ??
        ref.watch(currentUserProvider)?.coupleId;
    final myUid = DatabaseService().uid;

    ref.listen<String?>(pendingChatInputTextProvider, (prev, next) {
      if (next != null && next.isNotEmpty) {
        _textController.text = next;
        _textController.selection = TextSelection.fromPosition(
          TextPosition(offset: next.length),
        );
        ref.read(pendingChatInputTextProvider.notifier).state = null;
      }
    });

    ref.listen<AttachedLocation?>(pendingChatLocationAttachmentProvider, (prev, next) {
      if (next != null) {
        setState(() {
          _attachedLocation = next;
        });
        ref.read(pendingChatLocationAttachmentProvider.notifier).state = null;
      }
    });

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: (coupleId != null && coupleId.isNotEmpty)
          ? DatabaseService().coupleStream(coupleId)
          : null,
      builder: (context, coupleSnapshot) {
        final coupleData = coupleSnapshot.data?.data();
        final chatBackgroundUrl = coupleData?['chatBackgroundUrl'] as String?;
        final cloudChatSlideshowMap = coupleData?['chatSlideshowConfig'] as Map<String, dynamic>?;
        final isCloudSlideshowEnabled = cloudChatSlideshowMap != null && (cloudChatSlideshowMap['isEnabled'] as bool? ?? false);

        // Eğer partner tarafında veya bu cihazda döngü kapatılmışsa bellek görselini geçersiz kıl
        if (!isCloudSlideshowEnabled && BackgroundSlideshowService().currentChatBgUrl.value != null) {
          BackgroundSlideshowService().currentChatBgUrl.value = null;
        }

        return ValueListenableBuilder<String?>(
          valueListenable: BackgroundSlideshowService().currentChatBgUrl,
          builder: (context, slideshowBgUrl, _) {
            // Eğer slideshow aktifse onu kullan; tekil bir fotoğraf atanmışsa veya sıfırlanmışsa doğrudan Firestore'daki chatBackgroundUrl'i kullan
            final effectiveChatBg = (isCloudSlideshowEnabled && slideshowBgUrl != null && slideshowBgUrl.isNotEmpty)
                ? slideshowBgUrl
                : chatBackgroundUrl;

            return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.opaque,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              backgroundColor: isDark
                  ? const Color(0xFF0D0E15).withValues(alpha: 0.82)
                  : Colors.white.withValues(alpha: 0.85),
              elevation: 0,
              scrolledUnderElevation: 0,
              flexibleSpace: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(color: Colors.transparent),
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                  height: 1,
                ),
              ),
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
              actions: [
                if (coupleId != null && coupleId.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded),
                    tooltip: loc('Seçenekler', 'Options'),
                    onPressed: () => _openChatOptionsSheet(coupleId, currentChatBg: chatBackgroundUrl),
                  ),
              ],
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
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: LoveraColors.primary.withValues(alpha: 0.35),
                                  width: 1.8,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: CircleAvatar(
                                radius: 20,
                                backgroundColor: LoveraColors.primarySoft.withValues(alpha: 0.2),
                                backgroundImage: _getAvatarProvider(pAvatar),
                                child: _getAvatarProvider(pAvatar) == null
                                    ? Text(
                                        pName.isNotEmpty ? pName[0].toUpperCase() : '?',
                                        style: TextStyle(fontWeight: FontWeight.w800, color: LoveraColors.primary),
                                      )
                                    : null,
                              ),
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
                                      color: isDark ? LoveraColors.darkSurface : Colors.white,
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
                                      return Text(
                                        loc('yazıyor...', 'typing...'),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: LoveraColors.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      );
                                    }
                                    String statusSubtitle;
                                    if (isLiveOnline) {
                                      statusSubtitle = loc('Çevrimiçi', 'Online');
                                    } else if (pLastActive != null) {
                                      final diff = DateTime.now().toUtc().difference(pLastActive.toUtc()).abs();
                                      if (diff.inMinutes < 1) {
                                        statusSubtitle = loc('1 dk önce aktifti', 'Active 1m ago');
                                      } else if (diff.inMinutes < 60) {
                                        statusSubtitle = loc('${diff.inMinutes} dk önce aktifti', 'Active ${diff.inMinutes}m ago');
                                      } else if (diff.inHours < 24) {
                                        statusSubtitle = loc('${diff.inHours} sa önce aktifti', 'Active ${diff.inHours}h ago');
                                      } else {
                                        statusSubtitle = loc('${diff.inDays} gün önce aktifti', 'Active ${diff.inDays}d ago');
                                      }
                                    } else {
                                      statusSubtitle = loc('Çevrimdışı', 'Offline');
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
                                Text(
                                  loc('Eşleşme bekleniyor', 'Waiting for pairing'),
                                  style: TextStyle(fontSize: 12, color: LoveraColors.textMuted),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                )
              : Text(loc('Partner bekleniyor', 'Waiting for partner'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        body: Stack(
          children: [
            // Her zaman en altta Lovera'nın özel aurora & desen teması yer alır
            const Positioned.fill(
              child: LoveraThemeBackground(),
            ),

            // Ortak Sohbet Fotoğrafı (Eğer ayarlandıysa tema üzerinde şık bir şekilde durur)
            if (effectiveChatBg != null && effectiveChatBg.isNotEmpty) ...[
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 900),
                  layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                    return Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                    );
                  },
                  switchInCurve: Curves.easeInOutCubic,
                  switchOutCurve: Curves.easeInOutCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 1.04, end: 1.0).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: SizedBox.expand(
                    key: ValueKey<String>(effectiveChatBg),
                    child: Image(
                      image: AvatarCache.getProvider(effectiveChatBg)!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      alignment: Alignment.center,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
              // Fotoğrafı asla matlaştırmayan, sadece hafif derinlik katan minimal degrade
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: isDark
                          ? [
                              Colors.black.withValues(alpha: 0.25),
                              Colors.black.withValues(alpha: 0.35),
                              LoveraColors.darkBg.withValues(alpha: 0.50),
                            ]
                          : [
                              Colors.black.withValues(alpha: 0.04),
                              Colors.white.withValues(alpha: 0.08),
                              Colors.white.withValues(alpha: 0.18),
                            ],
                    ),
                  ),
                ),
              ),
            ],
            SafeArea(
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
                              child: Icon(Icons.chat_bubble_outline_rounded,
                                  size: 48, color: LoveraColors.primary),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              loc('Özel Sohbet Alanınız', 'Your Private Chat Space'),
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              loc('Partnerinizle eşleştiğinizde tüm mesajlarınız, fotoğraflarınız ve hisleriniz burada anlık olarak akacaktır.', 'Once paired with your partner, all your messages, photos, and feelings will flow here in real time.'),
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

                        // Karşı tarafın gönderdiği okunmamış mesajlar varsa hemen okundu olarak işaretle (Tekrarlayan çağrıları engelle)
                        final unreadIds = messages
                            .where((m) => m.senderId != myUid && !m.isRead && !_alreadyMarkedReadIds.contains(m.id))
                            .map((m) => m.id)
                            .toList();
                        if (unreadIds.isNotEmpty) {
                          _alreadyMarkedReadIds.addAll(unreadIds);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            DatabaseService().markMessagesAsRead(coupleId, unreadIds);
                            WidgetSyncService.clearWidgetMessages();
                          });
                        }

                        if (messages.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.mark_chat_unread_rounded,
                                    size: 54, color: LoveraColors.primarySoft),
                                const SizedBox(height: 12),
                                Text(
                                  loc('Henüz mesaj yok', 'No messages yet'),
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  loc('İlk mesajı atarak sohbeti başlatın! 💌', 'Send the first message to start the conversation! 💌'),
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
                              hasCustomBg: effectiveChatBg != null && effectiveChatBg.isNotEmpty,
                              onReply: () {
                                setState(() => _replyingTo = msg);
                              },
                              onDelete: isMe
                                  ? () => DatabaseService().deleteMessage(coupleId, msg.id)
                                  : null,
                              onLocationTap: (lat, lng, title) {
                                HapticFeedback.mediumImpact();
                                ref.read(targetMapFocusLocationProvider.notifier).state = AttachedLocation(
                                  lat: lat,
                                  lng: lng,
                                  title: title,
                                );
                                if (widget.onOpenMap != null) {
                                  widget.onOpenMap!();
                                } else {
                                  ref.read(activeNavigationIndexProvider.notifier).state = 0;
                                }
                              },
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
                            _replyingTo!.senderId == myUid ? loc('Sen', 'You') : (partner?.name ?? loc('Partner', 'Partner')),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: LoveraColors.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _replyingTo!.type == 'image' ? loc('📷 Fotoğraf', '📷 Photo') : _replyingTo!.text,
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

            // Konum İliştirme Önizleme Barı
            if (_attachedLocation != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E2130) : const Color(0xFFEFF6FF),
                  border: Border(
                    bottom: BorderSide(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.location_on_rounded, color: Color(0xFF3B82F6), size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            loc('İliştirilen Konum', 'Attached Location'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF3B82F6),
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            _attachedLocation!.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : const Color(0xFF1E293B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => setState(() => _attachedLocation = null),
                    ),
                  ],
                ),
              ).animate().slideY(begin: 0.2, duration: 200.ms).fadeIn(),

            // Giriş Alanı (Input Bar - Temaya uyumlu hafif cam/translucent tasarım)
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0D0E15).withValues(alpha: 0.90)
                    : Colors.white.withValues(alpha: 0.92),
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                    width: 1,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.05),
                    offset: const Offset(0, -2),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Fotoğraf Ekle Butonu
                  IconButton(
                    icon: Icon(Icons.photo_rounded, color: LoveraColors.secondary, size: 24),
                    onPressed: _pickImage,
                    tooltip: loc('Fotoğraf Gönder', 'Send Photo'),
                  ),

                  // Çıkartma (Sticker) Butonu
                  IconButton(
                    icon: const Text('🏷️', style: TextStyle(fontSize: 20)),
                    onPressed: () {
                      if (coupleId == null || coupleId.isEmpty) return;
                      StickerPickerSheet.show(
                        context: context,
                        coupleId: coupleId,
                        onStickerSelected: (content, {required bool isEmoji}) {
                          _send(
                            type: 'sticker',
                            customText: isEmoji ? content : '',
                            mediaBase64: isEmoji ? null : content,
                          );
                        },
                      );
                    },
                    tooltip: loc('Çıkartma Gönder', 'Send Sticker'),
                  ),

                  // Canlı Çizim Tuvali Butonu
                  IconButton(
                    icon: Icon(Icons.brush_rounded, color: LoveraColors.primaryDark, size: 24),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DrawingScreen()),
                      );
                    },
                    tooltip: loc('Çizim Yap ve Gönder', 'Draw & Send'),
                  ),

                  // Metin Alanı
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1B1D28)
                            : LoveraColors.lightSurfaceAlt,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.05),
                          width: 0.8,
                        ),
                      ),
                      child: TextField(
                        controller: _textController,
                        keyboardAppearance: isDark ? Brightness.dark : Brightness.light,
                        onChanged: (val) => _onTextChanged(val, coupleId),
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: 4,
                        minLines: 1,
                        decoration: InputDecoration(
                          filled: false,
                          hintText: _attachedLocation != null ? loc('Konum hakkında mesaj yaz...', 'Type a note about location...') : loc('Mesaj yaz...', 'Type a message...'),
                          hintStyle: TextStyle(color: LoveraColors.textMuted, fontSize: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(color: LoveraColors.primary, width: 1.5),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Gönder Butonu (ValueListenableBuilder ile dinlenir)
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _textController,
                    builder: (context, val, _) {
                      final hasText = val.text.trim().isNotEmpty || _attachedLocation != null;
                      final palette = ref.watch(themePaletteProvider);
                      return GestureDetector(
                        onTap: (hasText && !_isSending) ? () => _send() : null,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: hasText ? 1.0 : 0.4,
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              gradient: palette.gradient,
                              shape: BoxShape.circle,
                              boxShadow: hasText
                                  ? [
                                      BoxShadow(
                                        color: palette.primary.withValues(alpha: 0.35),
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
    ],
  ),
),
);
              },
            );
          },
        );
      }
}

class _ChatBubble extends ConsumerWidget {
  const _ChatBubble({
    required this.message,
    required this.isMe,
    required this.onReply,
    this.hasCustomBg = false,
    this.onDelete,
    this.onLocationTap,
  });

  final ChatMessage message;
  final bool isMe;
  final bool hasCustomBg;
  final VoidCallback onReply;
  final VoidCallback? onDelete;
  final void Function(double lat, double lng, String title)? onLocationTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = ref.watch(themePaletteProvider);
    final timeStr =
        '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}';

    // WhatsApp / Telegram / iMessage tarzı dünya standartlarında mesaj balonları:
    final Color bubbleColor;
    final Color textColor;
    final Border? bubbleBorder;

    if (isMe) {
      if (hasCustomBg) {
        // Fotoğraf varken gönderilen mesaj: Temanın canlı rengi
        bubbleColor = palette.primary;
        textColor = Colors.white;
        bubbleBorder = Border.all(color: Colors.white.withValues(alpha: 0.2), width: 0.8);
      } else {
        bubbleColor = palette.primary;
        textColor = Colors.white;
        bubbleBorder = null;
      }
    } else {
      if (hasCustomBg) {
        // Fotoğraf varken gelen mesaj:
        // WhatsApp'taki gibi net, sağlam, asla arkadaki fotoğrafla karışmayan pürüzsüz kart
        bubbleColor = isDark
            ? const Color(0xFF1E212E)
            : Colors.white;
        textColor = isDark ? Colors.white : const Color(0xFF111827);
        bubbleBorder = Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08),
          width: 0.8,
        );
      } else {
        bubbleColor = isDark ? LoveraColors.darkSurfaceAlt : const Color(0xFFE9ECF2);
        textColor = isDark ? Colors.white : LoveraColors.textDark;
        bubbleBorder = null;
      }
    }

    final bool hasLocation = (message.locationLat != null && message.locationLng != null) ||
        (message.type == 'location');

    final bool isSticker = message.type == 'sticker';
    final bool isPureSticker = isSticker && message.text.isEmpty;

    // Tek veya birkaç emojiden oluşan mesajlar için WhatsApp tarzı şeffaf arka plan
    final trimmedText = message.text.trim();
    final bool isOnlyEmoji = (message.type == 'text' || message.type == 'heart') &&
        message.mediaBase64 == null &&
        message.replyToText == null &&
        !hasLocation &&
        trimmedText.isNotEmpty &&
        trimmedText.characters.length <= 3 &&
        trimmedText.characters.every((c) =>
            RegExp(r'(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])').hasMatch(c));

    final bool isTransparentBubble = isPureSticker || isOnlyEmoji;

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
              onTap: hasLocation
                  ? () {
                      if (message.locationLat != null && message.locationLng != null) {
                        onLocationTap?.call(
                          message.locationLat!,
                          message.locationLng!,
                          message.locationTitle ?? loc('Konum', 'Location'),
                        );
                      }
                    }
                  : null,
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
                          title: Text(loc('Yanıtla', 'Reply')),
                          onTap: () {
                            Navigator.pop(ctx);
                            onReply();
                          },
                        ),
                        // Guideline 1.2: Sakıncalı içerik şikayet etme (UGC Moderation)
                        if (!isMe)
                          ListTile(
                            leading: const Icon(Icons.flag_outlined, color: Colors.amber),
                            title: Text(loc('Mesajı Şikayet Et', 'Report Message'), style: const TextStyle(color: Colors.amber)),
                            onTap: () async {
                              Navigator.pop(ctx);
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (dCtx) => AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  title: Text(loc('Mesajı Şikayet Et', 'Report Message')),
                                  content: Text(
                                    loc('Bu mesajı sakıncalı, taciz veya uygunsuz içerik nedeniyle Lovera inceleme ekibine bildirmek istiyor musunuz? İnceleme 24 saat içinde tamamlanacaktır.', 'Do you want to report this message to the Lovera review team for inappropriate content? Review will be completed within 24 hours.'),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(dCtx, false),
                                      child: Text(loc('Vazgeç', 'Cancel')),
                                    ),
                                    FilledButton(
                                      style: FilledButton.styleFrom(backgroundColor: Colors.amber[800]),
                                      onPressed: () => Navigator.pop(dCtx, true),
                                      child: Text(loc('Şikayet Et', 'Report'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              );

                              if (confirmed == true) {
                                await DatabaseService().reportContent(
                                  contentType: 'message',
                                  contentId: message.id,
                                  reportedUserId: message.senderId,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(loc('Şikayetiniz alındı. İçerik güvenlik ekibimize iletildi.', 'Your report has been received. Content forwarded to our safety team.')),
                                      backgroundColor: const Color(0xFF10B981),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        if (onDelete != null)
                          ListTile(
                            leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                            title: Text(loc('Mesajı Sil', 'Delete Message'), style: const TextStyle(color: Colors.redAccent)),
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
                padding: isTransparentBubble ? EdgeInsets.zero : const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isTransparentBubble ? Colors.transparent : bubbleColor,
                  border: isTransparentBubble ? null : bubbleBorder,
                  borderRadius: isTransparentBubble
                      ? BorderRadius.circular(16)
                      : BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(isMe ? 18 : 4),
                          bottomRight: Radius.circular(isMe ? 4 : 18),
                        ),
                  boxShadow: isTransparentBubble
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: hasCustomBg ? 0.12 : 0.04),
                            blurRadius: hasCustomBg ? 8 : 6,
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
                              message.replyToSender ?? loc('Yanıtlanan', 'Replying to'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isMe ? Colors.white70 : palette.primary,
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

                    if (hasLocation) ...[
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (message.locationLat != null && message.locationLng != null) {
                            onLocationTap?.call(
                              message.locationLat!,
                              message.locationLng!,
                              message.locationTitle ?? loc('Konum', 'Location'),
                            );
                          }
                        },
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              if (message.locationLat != null && message.locationLng != null) {
                                onLocationTap?.call(
                                  message.locationLat!,
                                  message.locationLng!,
                                  message.locationTitle ?? loc('Konum', 'Location'),
                                );
                              }
                            },
                            child: Ink(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? Colors.white.withValues(alpha: 0.18)
                                  : (isDark ? LoveraColors.darkSurface : Colors.white),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isMe
                                    ? Colors.white.withValues(alpha: 0.25)
                                    : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.06)),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: (isMe ? Colors.white : palette.primary).withValues(alpha: 0.18),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.map_rounded,
                                    size: 20,
                                    color: isMe ? Colors.white : palette.primary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              message.locationTitle ?? loc('Konum Paylaşımı', 'Location Share'),
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                color: textColor,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.open_in_new_rounded,
                                            size: 13,
                                            color: textColor.withValues(alpha: 0.7),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        loc('Haritada Gör 📍', 'View on Map 📍'),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: textColor.withValues(alpha: 0.8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (message.text.isNotEmpty) const SizedBox(height: 8),
                  ],

                    // Mesaj İçeriği: Görsel veya Metin veya Çizim Widget'ı
                    if (message.type == 'drawing' && message.mediaBase64 != null) ...[
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => FullScreenImageViewer(
                                imageBase64: message.mediaBase64!,
                                messageId: message.id,
                                timestamp: message.createdAt,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF141724) : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: palette.primary.withValues(alpha: 0.35),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: palette.primary.withValues(alpha: 0.15),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.brush_rounded, size: 14, color: LoveraColors.primary),
                                  const SizedBox(width: 5),
                                  Text(
                                    loc('Canlı Widget Çizimi 🎨', 'Live Widget Drawing 🎨'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white70 : LoveraColors.primaryDark,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  width: MediaQuery.of(context).size.width * 0.70,
                                  height: MediaQuery.of(context).size.width * 0.70,
                                  color: isDark ? const Color(0xFF1E212E) : const Color(0xFFF3F4F6),
                                  child: Image.memory(
                                    base64Decode(message.mediaBase64!.split(',').last),
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (message.text.isNotEmpty) const SizedBox(height: 6),
                    ] else if (message.type == 'image' && message.mediaBase64 != null) ...[
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => FullScreenImageViewer(
                                imageBase64: message.mediaBase64!,
                                messageId: message.id,
                                timestamp: message.createdAt,
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
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.zoom_in_rounded, color: Colors.white, size: 14),
                                    const SizedBox(width: 4),
                                    Text(loc('Büyüt', 'Expand'), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (message.text.isNotEmpty) const SizedBox(height: 6),
                    ],

                    if (message.type == 'sticker') ...[
                      if (message.mediaBase64 != null && message.mediaBase64!.isNotEmpty)
                        _ChatStickerBubble(
                          messageId: message.id,
                          mediaBase64: message.mediaBase64!,
                        )
                      else
                        Text(
                          message.text.isNotEmpty ? message.text : '🏷️',
                          style: const TextStyle(fontSize: 48),
                        ),
                      if (message.text.isNotEmpty && message.mediaBase64 != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          message.text,
                          style: TextStyle(
                            fontSize: 14,
                            color: textColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ] else if (message.type == 'heart')
                      const Text(
                        '❤️',
                        style: TextStyle(fontSize: 48),
                      )
                    else if (message.text.isNotEmpty)
                      Text(
                        message.text,
                        style: TextStyle(
                          fontSize: isOnlyEmoji ? 42 : 15,
                          height: isOnlyEmoji ? 1.15 : 1.35,
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
                            fontWeight: FontWeight.w500,
                            color: isMe
                                ? Colors.white70
                                : (hasCustomBg
                                    ? (isDark ? Colors.white60 : const Color(0xFF6B7280))
                                    : LoveraColors.textMuted),
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

/// Şeffaf ve Çerçevesiz Özel Çıkartma Görseli Widget'ı
class _ChatStickerBubble extends StatelessWidget {
  const _ChatStickerBubble({
    required this.messageId,
    required this.mediaBase64,
  });

  final String messageId;
  final String mediaBase64;

  static final Map<String, Uint8List> _stickerCache = <String, Uint8List>{};

  Uint8List _getBytes() {
    if (_stickerCache.containsKey(messageId)) {
      return _stickerCache[messageId]!;
    }
    final raw = mediaBase64.split(',').last;
    final bytes = base64Decode(raw);
    _stickerCache[messageId] = bytes;
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _getBytes();
    return SizedBox(
      width: 155,
      height: 155,
      child: Image.memory(
        bytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
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
class FullScreenImageViewer extends ConsumerStatefulWidget {
  const FullScreenImageViewer({
    super.key,
    required this.imageBase64,
    this.messageId,
    this.timestamp,
  });
  final String imageBase64;
  final String? messageId;
  final DateTime? timestamp;

  @override
  ConsumerState<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends ConsumerState<FullScreenImageViewer> {
  bool _isSaving = false;
  bool _isAddingToAlbum = false;

  Future<void> _saveToMemoriesAlbum() async {
    final coupleId = ref.read(coupleIdProvider) ?? ref.read(currentUserProvider)?.coupleId;
    if (coupleId == null || coupleId.isEmpty) return;

    setState(() => _isAddingToAlbum = true);
    HapticFeedback.heavyImpact();

    try {
      final myName = ref.read(userNameProvider);
      await DatabaseService().addMemory(
        coupleId: coupleId,
        imageBase64: widget.imageBase64,
        caption: loc('Sohbetten kaydedilen anı 💌', 'Memory saved from chat 💌'),
        locationTitle: '',
        date: widget.timestamp ?? DateTime.now(),
        createdByName: myName.isNotEmpty ? myName : 'Partnerin',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc('Ortak Anı Albümüne mühürlendi! 💖✨', 'Saved to Shared Memories! 💖✨')),
            backgroundColor: LoveraColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc('Albüme eklenirken hata: $e', 'Error adding to album: $e')),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAddingToAlbum = false);
    }
  }

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
          SnackBar(
            content: Text(loc('Fotoğraf galeriye kaydedildi! 📸✨', 'Photo saved to gallery! 📸✨')),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc('Fotoğraf kaydedilemedi: $e', 'Could not save photo: $e')),
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
        title: Text(loc('Fotoğraf', 'Photo'), style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          _isAddingToAlbum
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.favorite_rounded, color: Colors.white),
                  tooltip: loc('Ortak Anı Albümüne Kaydet 💖', 'Save to Shared Memories 💖'),
                  onPressed: _saveToMemoriesAlbum,
                ),
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
                  tooltip: loc('Cihaza Kaydet', 'Save to Device'),
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

