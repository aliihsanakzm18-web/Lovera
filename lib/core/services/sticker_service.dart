import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class CustomSticker {
  final String id;
  final String imageUrl; // base64 veya url
  final String title;
  final String createdBy;
  final DateTime createdAt;

  const CustomSticker({
    required this.id,
    required this.imageUrl,
    required this.title,
    required this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'imageUrl': imageUrl,
        'title': title,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
      };

  factory CustomSticker.fromJson(Map<String, dynamic> json, String docId) {
    DateTime parseDate(dynamic val) {
      if (val is DateTime) return val;
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return CustomSticker(
      id: docId,
      imageUrl: json['imageUrl'] as String? ?? '',
      title: json['title'] as String? ?? 'Çıkartma',
      createdBy: json['createdBy'] as String? ?? '',
      createdAt: parseDate(json['createdAt']),
    );
  }
}

class StickerService {
  static final StickerService _instance = StickerService._internal();
  factory StickerService() => _instance;
  StickerService._internal();

  /// Hazır romantik, sevimli ve ifadeli emoji çıkartmaları (Yüksek kaliteli büyük SVG/Emoji illüstrasyonları)
  static final List<String> defaultRomanticStickers = [
    '💖', '❤️', '💕', '🥰', '😘', '😍', '💋', '💌', 
    '🌹', '🧸', '👩‍❤️‍👨', '💍', '✨', '💐', '💓', '💞',
    '🐣', '🐰', '🐼', '🐱', '🐾', '🦋', '🍓', '🍰',
    '🥺', '🤗', '🥳', '😴', '🤤', '🤫', '😇', '👑',
  ];

  /// Çiftin ortak özel çıkartmalar stream'i
  Stream<List<CustomSticker>> customStickersStream(String coupleId) {
    if (coupleId.isEmpty) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('couples')
        .doc(coupleId)
        .collection('stickers')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => CustomSticker.fromJson(d.data(), d.id)).toList());
  }

  /// Özel çıkartma ekle
  Future<void> addCustomSticker({
    required String coupleId,
    required String imageBase64,
    required String title,
    required String createdBy,
  }) async {
    if (coupleId.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('couples')
          .doc(coupleId)
          .collection('stickers')
          .add({
        'imageUrl': imageBase64,
        'title': title.trim(),
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[StickerService] addCustomSticker error: $e');
      rethrow;
    }
  }

  /// Özel çıkartma sil
  Future<void> deleteCustomSticker({
    required String coupleId,
    required String stickerId,
  }) async {
    if (coupleId.isEmpty || stickerId.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('couples')
          .doc(coupleId)
          .collection('stickers')
          .doc(stickerId)
          .delete();
    } catch (e) {
      debugPrint('[StickerService] deleteCustomSticker error: $e');
    }
  }
}
