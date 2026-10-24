import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'notification_service.dart';
import '../localization/app_strings.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get uid => _auth.currentUser?.uid;
  FirebaseFirestore get db => _db;

  // 1. KULLANICI BİLGİLERİNİ CANLI DİNLEME
  Stream<DocumentSnapshot<Map<String, dynamic>>>? userStream() {
    if (uid == null) return null;
    return _db.collection('users').doc(uid).snapshots();
  }

  // Başka bir kullanıcının bilgilerini canlı dinleme (Partner için)
  Stream<DocumentSnapshot<Map<String, dynamic>>> partnerStream(String partnerUid) {
    return _db.collection('users').doc(partnerUid).snapshots();
  }

  // Ortak Çift (Couple) belgesini canlı dinleme
  Stream<DocumentSnapshot<Map<String, dynamic>>>? coupleStream(String coupleId) {
    return _db.collection('couples').doc(coupleId).snapshots();
  }

  // Kullanıcı adı güncelle
  Future<void> updateUserName(String newName) async {
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).set({
        'name': newName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  // Kullanıcının tema paketi ve tema modu tercihini buluta yedekle
  Future<void> updateUserThemePreferences({
    String? themePalette,
    String? themeMode,
  }) async {
    if (uid == null) return;
    try {
      final data = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (themePalette != null) data['themePalette'] = themePalette;
      if (themeMode != null) data['themeMode'] = themeMode;
      await _db.collection('users').doc(uid).set(
        data,
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  // Doğum tarihi güncelle ('YYYY-MM-DD')
  Future<void> updateBirthDate(String birthDateStr, {String? coupleId, String? userName}) async {
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).set({
        'birthDate': birthDateStr,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 4));
    } catch (_) {}

    // Eğer bağlı bir couple varsa, doğum gününü özel günlere otomatik senkronize et
    if (coupleId != null && coupleId.isNotEmpty) {
      final name = userName ?? _auth.currentUser?.displayName ?? loc('Doğum Günü', 'Birthday');
      await syncBirthdayMilestone(
        targetUserId: uid!,
        userName: name,
        birthDateStr: birthDateStr,
        coupleId: coupleId,
      );
    }
  }

  // Profil fotoğrafı güncelle
  Future<void> updateAvatar(String avatarPath) async {
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).set({
        'avatarUrl': avatarPath,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  // Widget arka plan fotoğrafı güncelle (Yalnızca kullanıcının kendi profiline kaydeder, kişiseldir)
  Future<void> updateWidgetBg(String base64Str) async {
    if (uid == null) return;
    try {
      final userRef = _db.collection('users').doc(uid);
      await userRef.set({
        'widgetBgUrl': base64Str,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('updateWidgetBg error: $e');
    }
  }

  // Widget arka plan fotoğrafını kullanıcının hesabından sil
  Future<void> deleteWidgetBg() async {
    if (uid == null) return;
    try {
      final userRef = _db.collection('users').doc(uid);
      await userRef.update({
        'widgetBgUrl': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  // 2. DAVET KODU & EŞLEŞME YÖNETİMİ
  /// Kullanıcı için 6 haneli benzersiz davet kodu oluşturur veya var olanı döner.
  Future<String> getOrCreateInviteCode(String myName, String? myAvatar) async {
    if (uid == null) return 'LOVERA';
    
    // Önce kullanıcının kendi profilinde davet kodu var mı kontrol et
    final userDoc = await _db.collection('users').doc(uid).get();
    if (userDoc.exists && userDoc.data()?['inviteCode'] != null) {
      final code = userDoc.data()!['inviteCode'] as String;
      // Kod tablosunu da güncelle
      await _db.collection('inviteCodes').doc(code).set({
        'uid': uid,
        'name': myName,
        'avatarUrl': myAvatar,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return code;
    }

    // Yeni benzersiz kod üret: Daha önce hiç oluşturulmamış ve hiç kullanılmamış kod olmalı
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    String newCode;
    while (true) {
      newCode = List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
      final codeDoc = await _db.collection('inviteCodes').doc(newCode).get();
      // Kod inviteCodes tablosunda yoksa veya kullanılmışsa ASLA tekrar üretilemez!
      if (!codeDoc.exists) break;
    }

    await _db.collection('inviteCodes').doc(newCode).set({
      'uid': uid,
      'name': myName,
      'avatarUrl': myAvatar,
      'isUsed': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _db.collection('users').doc(uid).set({
      'inviteCode': newCode,
    }, SetOptions(merge: true));

    return newCode;
  }

  /// Kullanıcı isterse mevcut kodunu iptal edip tek seferlik yepyeni bir kod üretir
  Future<String> refreshInviteCode(String myName, String? myAvatar) async {
    if (uid == null) return 'LOVERA';

    // Eski kodu 'used' (kullanılmış/iptal) olarak işaretle ki bir daha asla üretilmesin
    final userDoc = await _db.collection('users').doc(uid).get();
    if (userDoc.exists && userDoc.data()?['inviteCode'] != null) {
      final oldCode = userDoc.data()!['inviteCode'] as String;
      await _db.collection('inviteCodes').doc(oldCode).set({
        'isUsed': true,
        'revokedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    // Yeni benzersiz kod üret
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    String newCode;
    while (true) {
      newCode = List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
      final codeDoc = await _db.collection('inviteCodes').doc(newCode).get();
      if (!codeDoc.exists) break;
    }

    await _db.collection('inviteCodes').doc(newCode).set({
      'uid': uid,
      'name': myName,
      'avatarUrl': myAvatar,
      'isUsed': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _db.collection('users').doc(uid).set({
      'inviteCode': newCode,
    }, SetOptions(merge: true));

    return newCode;
  }

  /// Karşı tarafın kodunu sorgula ve partner bilgilerini getir
  Future<Map<String, dynamic>?> lookupInviteCode(String code) async {
    final cleanCode = code.trim().toUpperCase();
    final doc = await _db.collection('inviteCodes').doc(cleanCode).get();
    if (!doc.exists) return null;
    final data = doc.data();
    // Eğer kod daha önce kullanılmışsa veya iptal edilmişse geçersiz say
    if (data == null || data['isUsed'] == true) {
      return null;
    }
    return data;
  }

  /// 1. Adım: Karşı tarafa eşleşme isteği gönder
  Future<void> sendPairRequest({
    required String targetUid,
    required String myName,
    required String? myAvatar,
  }) async {
    if (uid == null) return;

    // Engellenen kullanıcı kontrolü (Guideline 1.2)
    try {
      final targetDoc = await _db.collection('users').doc(targetUid).get();
      final blockedList = List<String>.from(targetDoc.data()?['blockedUsers'] ?? []);
      if (blockedList.contains(uid)) {
        throw Exception(loc('Bu kullanıcı sizi engellediği için eşleşme isteği gönderilemiyor.', 'Cannot send pairing request because this user has blocked you.'));
      }
    } catch (e) {
      if (e.toString().contains('engellediği') || e.toString().contains('blocked')) rethrow;
    }

    // Hedef kullanıcının gelen isteklerine ve kendi kullanıcımıza yaz
    final batch = _db.batch();

    // Hedef kullanıcının gelen isteği
    final targetRef = _db.collection('users').doc(targetUid);
    batch.set(targetRef, {
      'pendingPairRequest': {
        'fromUid': uid,
        'fromName': myName,
        'fromAvatar': myAvatar,
        'status': 'pending', // 'pending', 'accepted', 'rejected'
        'createdAt': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));

    // Gönderenin de durumunu 'waiting' yapalım
    final myRef = _db.collection('users').doc(uid);
    batch.set(myRef, {
      'outgoingPairRequest': {
        'toUid': targetUid,
        'status': 'waiting',
      }
    }, SetOptions(merge: true));

    await batch.commit();

    // Hedef kullanıcıya anlık Push Bildirim gönder (Uygulama kapalı olsa bile!)
    try {
      NotificationService().sendPushToPartner(
        partnerUid: targetUid,
        title: loc('💕 Yeni Eşleşme İsteği!', '💕 New Pairing Request!'),
        body: loc('$myName seninle eşleşmek istiyor! Bağlantıyı onaylamak için dokun.', '$myName wants to pair with you! Tap to confirm connection.'),
        titleTr: '💕 Yeni Eşleşme İsteği!',
        titleEn: '💕 New Pairing Request!',
        bodyTr: '$myName seninle eşleşmek istiyor! Bağlantıyı onaylamak için dokun.',
        bodyEn: '$myName wants to pair with you! Tap to confirm connection.',
        data: {
          'type': 'pair_request',
          'fromUid': uid ?? '',
          'fromName': myName,
        },
      );
    } catch (_) {}
  }

  /// 2. Adım: Gelen isteği kabul et ve ortak Çift (Couple) oluştur
  Future<String> acceptPairRequest({
    required String requesterUid,
    required DateTime relationshipStartDate,
  }) async {
    if (uid == null) throw Exception(loc('Giriş yapılmamış', 'Not logged in'));

    final coupleRef = _db.collection('couples').doc();
    final coupleId = coupleRef.id;

    // Ortak Çift belgesi
    await coupleRef.set({
      'id': coupleId,
      'user1': requesterUid,
      'user2': uid,
      'relationshipStartDate': relationshipStartDate.toIso8601String(),
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    });

    final batch = _db.batch();

    // Kendi profilini güncelle
    final myRef = _db.collection('users').doc(uid);
    batch.set(myRef, {
      'coupleId': coupleId,
      'partnerUid': requesterUid,
      'relationshipStartDate': relationshipStartDate.toIso8601String(),
      'pendingPairRequest': FieldValue.delete(),
    }, SetOptions(merge: true));

    // İstek gönderenin profilini güncelle (Kabul edildi)
    final reqRef = _db.collection('users').doc(requesterUid);
    batch.set(reqRef, {
      'coupleId': coupleId,
      'partnerUid': uid,
      'relationshipStartDate': relationshipStartDate.toIso8601String(),
      'outgoingPairRequest': {
        'toUid': uid,
        'status': 'accepted',
        'coupleId': coupleId,
      },
    }, SetOptions(merge: true));

    // İki kullanıcının da davet kodunu 'kullanıldı (isUsed: true)' olarak yak ve profillerinden temizle
    try {
      final u1Snap = await _db.collection('users').doc(requesterUid).get();
      final code1 = u1Snap.data()?['inviteCode'] as String?;
      if (code1 != null && code1.isNotEmpty) {
        batch.set(_db.collection('inviteCodes').doc(code1), {
          'isUsed': true,
          'usedAt': FieldValue.serverTimestamp(),
          'usedByCoupleId': coupleId,
        }, SetOptions(merge: true));
        batch.update(_db.collection('users').doc(requesterUid), {
          'inviteCode': FieldValue.delete(),
        });
      }

      final u2Snap = await _db.collection('users').doc(uid).get();
      final code2 = u2Snap.data()?['inviteCode'] as String?;
      if (code2 != null && code2.isNotEmpty) {
        batch.set(_db.collection('inviteCodes').doc(code2), {
          'isUsed': true,
          'usedAt': FieldValue.serverTimestamp(),
          'usedByCoupleId': coupleId,
        }, SetOptions(merge: true));
        batch.update(_db.collection('users').doc(uid), {
          'inviteCode': FieldValue.delete(),
        });
      }
    } catch (_) {}

    await batch.commit();

    // Otomatik Özel Günler: Yıldönümü, Doğum Günleri ve Kültürel Özel Günler (Sevgililer Günü, Kadınlar Günü, Erkekler Günü)
    await syncDefaultAnniversary(relationshipStartDate, coupleId: coupleId);
    await syncDefaultCulturalMilestones(coupleId: coupleId);

    try {
      final user1Doc = await _db.collection('users').doc(requesterUid).get();
      final user2Doc = await _db.collection('users').doc(uid).get();

      if (user1Doc.exists && user1Doc.data()?['birthDate'] != null) {
        await syncBirthdayMilestone(
          targetUserId: requesterUid,
          userName: user1Doc.data()?['name'] ?? 'Partner',
          birthDateStr: user1Doc.data()!['birthDate'],
          coupleId: coupleId,
        );
      }

      if (user2Doc.exists && user2Doc.data()?['birthDate'] != null) {
        await syncBirthdayMilestone(
          targetUserId: uid!,
          userName: user2Doc.data()?['name'] ?? 'Ben',
          birthDateStr: user2Doc.data()!['birthDate'],
          coupleId: coupleId,
        );
      }
    } catch (_) {}

    return coupleId;
  }

  /// İsteği reddet
  Future<void> rejectPairRequest(String requesterUid) async {
    if (uid == null) return;
    final batch = _db.batch();
    batch.set(_db.collection('users').doc(uid), {
      'pendingPairRequest': FieldValue.delete(),
    }, SetOptions(merge: true));

    batch.set(_db.collection('users').doc(requesterUid), {
      'outgoingPairRequest': {
        'status': 'rejected',
      }
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// Tüketilen outgoingPairRequest'i temizle
  Future<void> clearOutgoingPairRequest() async {
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'outgoingPairRequest': FieldValue.delete(),
    }).catchError((_) {});
  }

  /// Tüketilen pendingPairRequest'i temizle
  Future<void> clearPendingPairRequest() async {
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'pendingPairRequest': FieldValue.delete(),
    }).catchError((_) {});
  }

  // 3. İLİŞKİ BAŞLANGIÇ TARİHİ (SAYAÇ) KAYDI
  Future<void> saveRelationshipStartDate(DateTime date, {String? coupleId}) async {
    if (uid == null) return;
    await _db.collection('users').doc(uid).set({
      'relationshipStartDate': date.toIso8601String(),
    }, SetOptions(merge: true));

    if (coupleId != null && coupleId.isNotEmpty) {
      await _db.collection('couples').doc(coupleId).set({
        'relationshipStartDate': date.toIso8601String(),
      }, SetOptions(merge: true));
    }

    await syncDefaultAnniversary(date, coupleId: coupleId);
  }

  /// Eş yönetim panelinden tarih değiştirme isteği gönder
  Future<void> proposeDateChange({
    required String partnerUid,
    required DateTime newDate,
    required String requesterName,
  }) async {
    if (uid == null) return;
    await _db.collection('users').doc(partnerUid).set({
      'pendingDateChangeRequest': {
        'fromUid': uid,
        'fromName': requesterName,
        'proposedDate': newDate.toIso8601String(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));
  }

  /// Tarih değişikliğini kabul et ve her iki taraf ile ortak çift belgesini güncelle
  Future<void> acceptDateChange({
    required String partnerUid,
    required DateTime newDate,
    String? coupleId,
  }) async {
    if (uid == null) return;
    final batch = _db.batch();
    
    // Kendi kullanıcımız
    final myRef = _db.collection('users').doc(uid);
    batch.set(myRef, {
      'relationshipStartDate': newDate.toIso8601String(),
      'pendingDateChangeRequest': FieldValue.delete(),
    }, SetOptions(merge: true));

    // Partner
    final partnerRef = _db.collection('users').doc(partnerUid);
    batch.set(partnerRef, {
      'relationshipStartDate': newDate.toIso8601String(),
      'dateChangeResult': {
        'status': 'accepted',
        'date': newDate.toIso8601String(),
      }
    }, SetOptions(merge: true));

    // Ortak çift
    if (coupleId != null && coupleId.isNotEmpty) {
      final cRef = _db.collection('couples').doc(coupleId);
      batch.set(cRef, {
        'relationshipStartDate': newDate.toIso8601String(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
    await syncDefaultAnniversary(newDate, coupleId: coupleId);
  }

  /// Tarih değişikliğini reddet
  Future<void> rejectDateChange(String partnerUid) async {
    if (uid == null) return;
    final batch = _db.batch();
    batch.set(_db.collection('users').doc(uid), {
      'pendingDateChangeRequest': FieldValue.delete(),
    }, SetOptions(merge: true));

    batch.set(_db.collection('users').doc(partnerUid), {
      'dateChangeResult': {
        'status': 'rejected',
      }
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// Tarih değişiklik yanıtını tüketildikten sonra temizle
  Future<void> clearDateChangeResult() async {
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'dateChangeResult': FieldValue.delete(),
    }).catchError((_) {});
  }

  // ==========================================
  // EŞ AYRILMA / BAĞLANTI KOPARMA (UNPAIR) SİSTEMİ
  // ==========================================

  /// Eş yönetim panelinden ayrılma isteği gönderir
  Future<void> proposeBreakup({
    required String partnerUid,
    required String requesterName,
    String? coupleId,
  }) async {
    if (uid == null) return;
    final batch = _db.batch();

    // Partnere gelen istek
    batch.set(_db.collection('users').doc(partnerUid), {
      'pendingBreakupRequest': {
        'fromUid': uid,
        'fromName': requesterName,
        'coupleId': coupleId ?? '',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));

    // Kendisine bekleme durumu
    batch.set(_db.collection('users').doc(uid), {
      'outgoingBreakupRequest': {
        'toUid': partnerUid,
        'status': 'waiting',
        'createdAt': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// Ayrılma isteğini kabul et ve iki tarafın da eşleşmesini kalıcı olarak sonlandır
  Future<void> acceptBreakup({
    required String partnerUid,
    String? coupleId,
  }) async {
    if (uid == null) return;
    final batch = _db.batch();

    // 1. Kendi kullanıcımızın profilini eşleşmeden arındır
    final myRef = _db.collection('users').doc(uid);
    batch.update(myRef, {
      'coupleId': FieldValue.delete(),
      'partnerUid': FieldValue.delete(),
      'relationshipStartDate': FieldValue.delete(),
      'pendingBreakupRequest': FieldValue.delete(),
      'outgoingBreakupRequest': FieldValue.delete(),
      'pendingPairRequest': FieldValue.delete(),
      'outgoingPairRequest': FieldValue.delete(),
      'breakupResult': {
        'status': 'accepted',
        'timestamp': FieldValue.serverTimestamp(),
      },
    });

    // 2. Partnerin profilini eşleşmeden arındır ve sonuca bağla
    final partnerRef = _db.collection('users').doc(partnerUid);
    batch.update(partnerRef, {
      'coupleId': FieldValue.delete(),
      'partnerUid': FieldValue.delete(),
      'relationshipStartDate': FieldValue.delete(),
      'pendingBreakupRequest': FieldValue.delete(),
      'outgoingBreakupRequest': FieldValue.delete(),
      'pendingPairRequest': FieldValue.delete(),
      'outgoingPairRequest': FieldValue.delete(),
      'breakupResult': {
        'status': 'accepted',
        'timestamp': FieldValue.serverTimestamp(),
      },
    });

    // 3. Ortak çift (couple) belgesini pasife çek
    if (coupleId != null && coupleId.isNotEmpty) {
      final cRef = _db.collection('couples').doc(coupleId);
      batch.update(cRef, {
        'status': 'separated',
        'endedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  /// Ayrılma isteğini reddet
  Future<void> rejectBreakup(String partnerUid) async {
    if (uid == null) return;
    final batch = _db.batch();
    batch.set(_db.collection('users').doc(uid), {
      'pendingBreakupRequest': FieldValue.delete(),
    }, SetOptions(merge: true));

    batch.set(_db.collection('users').doc(partnerUid), {
      'outgoingBreakupRequest': FieldValue.delete(),
      'breakupResult': {
        'status': 'rejected',
        'timestamp': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// Ayrılma sonucunu tüketildikten sonra temizle
  Future<void> clearBreakupResult() async {
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'breakupResult': FieldValue.delete(),
      'outgoingBreakupRequest': FieldValue.delete(),
    }).catchError((_) {});
  }

  /// Kullanıcıyı engelle ve eşleşmeyi derhal sonlandır (Apple Guideline 1.2 UGC)
  Future<void> blockAndUnpairPartner({
    required String partnerUid,
    String? coupleId,
  }) async {
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).set({
        'blockedUsers': FieldValue.arrayUnion([partnerUid]),
      }, SetOptions(merge: true));
    } catch (_) {}
    await acceptBreakup(partnerUid: partnerUid, coupleId: coupleId);
  }

  /// Kullanıcı engelini kaldır
  Future<void> unblockUser(String targetUid) async {
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).set({
        'blockedUsers': FieldValue.arrayRemove([targetUid]),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Engellenen kullanıcıların ID listesini al
  Future<List<String>> getBlockedUserIds() async {
    if (uid == null) return [];
    try {
      final doc = await _db.collection('users').doc(uid).get();
      return List<String>.from(doc.data()?['blockedUsers'] ?? []);
    } catch (_) {
      return [];
    }
  }

  /// Engellenen kullanıcıların profil bilgilerini getir
  Future<List<Map<String, dynamic>>> getBlockedUsersProfiles() async {
    final ids = await getBlockedUserIds();
    if (ids.isEmpty) return [];
    final List<Map<String, dynamic>> list = [];
    for (final id in ids) {
      try {
        final doc = await _db.collection('users').doc(id).get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          list.add({
            'uid': id,
            'name': data['name'] ?? loc('Kullanıcı', 'User'),
            'avatarUrl': data['avatarUrl'],
            'email': data['email'] ?? '',
          });
        } else {
          list.add({
            'uid': id,
            'name': '${loc("Kullanıcı", "User")} ($id)',
            'avatarUrl': null,
            'email': '',
          });
        }
      } catch (_) {
        list.add({
          'uid': id,
          'name': '${loc("Kullanıcı", "User")} ($id)',
          'avatarUrl': null,
          'email': '',
        });
      }
    }
    return list;
  }

  /// Sakıncalı içerik veya kullanıcı şikayetini Firestore'a kaydet (Apple Guideline 1.2 UGC)
  Future<void> reportContent({
    required String contentType,
    required String contentId,
    String? coupleId,
    String? reportedUserId,
    String? reason,
  }) async {
    if (uid == null) return;
    try {
      await _db.collection('reports').add({
        'reporterUid': uid,
        'reportedUserId': reportedUserId ?? '',
        'coupleId': coupleId ?? '',
        'contentType': contentType, // 'message', 'memory', 'user'
        'contentId': contentId,
        'reason': reason ?? loc('Sakıncalı veya uygunsuz içerik', 'Objectionable or inappropriate content'),
        'status': 'pending_review',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Doğrudan birliktelik başlangıç tarihini güncelle ve partneri anında haberdar et
  Future<void> updateRelationshipDateDirectly({
    required DateTime newDate,
    required String partnerUid,
    String? coupleId,
    required String updaterName,
  }) async {
    if (uid == null) return;
    final batch = _db.batch();

    // 1. Kendi kullanıcımız
    final myRef = _db.collection('users').doc(uid);
    batch.set(myRef, {
      'relationshipStartDate': newDate.toIso8601String(),
      'pendingDateChangeRequest': FieldValue.delete(),
    }, SetOptions(merge: true));

    // 2. Partner (bilgilendirme bayrağı ile)
    final partnerRef = _db.collection('users').doc(partnerUid);
    batch.set(partnerRef, {
      'relationshipStartDate': newDate.toIso8601String(),
      'pendingDateChangeRequest': FieldValue.delete(),
      'dateUpdatedNotice': {
        'updaterName': updaterName,
        'newDate': newDate.toIso8601String(),
        'timestamp': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));

    // 3. Ortak çift (couple)
    if (coupleId != null && coupleId.isNotEmpty) {
      final cRef = _db.collection('couples').doc(coupleId);
      batch.set(cRef, {
        'relationshipStartDate': newDate.toIso8601String(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
    await syncDefaultAnniversary(newDate, coupleId: coupleId);
  }

  /// Tarih güncellendi bildirimini temizle
  Future<void> clearDateUpdatedNotice() async {
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'dateUpdatedNotice': FieldValue.delete(),
    }).catchError((_) {});
  }

  // ---------------------------------------------------------------------------
  // BULUŞMA TALEBİ (Partnerin kullanıcı belgesi üzerinden, tarih değişikliği ile aynı kanıtlanmış yöntem)
  // ---------------------------------------------------------------------------

  /// Partnere belirli bir konum için buluşma talebi gönderir.
  Future<void> sendMeetingRequest({
    required String partnerUid,
    required String fromName,
    required double lat,
    required double lng,
    required String placeTitle,
    String? meetingTime,
    String? note,
  }) async {
    if (uid == null) return;
    await _db.collection('users').doc(partnerUid).set({
      'pendingMeetingRequest': {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'fromUid': uid,
        'fromName': fromName,
        'lat': lat,
        'lng': lng,
        'title': placeTitle,
        'status': 'pending',
        if (meetingTime != null && meetingTime.isNotEmpty) 'meetingTime': meetingTime,
        if (note != null && note.isNotEmpty) 'note': note,
        'createdAt': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));
  }

  /// Gelen buluşma talebini yanıtlar; talebi temizler ve gönderene sonucu bildirir.
  Future<void> respondMeetingRequest({
    required String fromUid,
    required bool accepted,
    required String placeTitle,
    required String responderName,
    String? coupleId,
    double? lat,
    double? lng,
    String? meetingTime,
    String? note,
  }) async {
    if (uid == null) return;
    final batch = _db.batch();
    batch.set(_db.collection('users').doc(uid), {
      'pendingMeetingRequest': FieldValue.delete(),
    }, SetOptions(merge: true));
    batch.set(_db.collection('users').doc(fromUid), {
      'meetingResult': {
        'status': accepted ? 'accepted' : 'rejected',
        'title': placeTitle,
        'byName': responderName,
        'lat': lat,
        'lng': lng,
        if (meetingTime != null && meetingTime.isNotEmpty) 'meetingTime': meetingTime,
        if (note != null && note.isNotEmpty) 'note': note,
        'at': DateTime.now().millisecondsSinceEpoch,
      }
    }, SetOptions(merge: true));
    if (accepted && coupleId != null && coupleId.isNotEmpty && lat != null && lng != null) {
      batch.set(_db.collection('couples').doc(coupleId), {
        'activeMeeting': {
          'title': placeTitle,
          'lat': lat,
          'lng': lng,
          if (meetingTime != null && meetingTime.isNotEmpty) 'meetingTime': meetingTime,
          if (note != null && note.isNotEmpty) 'note': note,
          'acceptedAt': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  /// Aktif buluşmayı temizler / sonlandırır
  Future<void> clearActiveMeeting(String coupleId) async {
    try {
      await _db.collection('couples').doc(coupleId).update({
        'activeMeeting': FieldValue.delete(),
      });
    } catch (_) {}
  }

  /// Aktif buluşmanın başlığını veya ikonunu günceller
  Future<void> updateActiveMeeting({
    required String coupleId,
    required String title,
    String? iconEmoji,
  }) async {
    try {
      final Map<String, dynamic> updates = {
        'activeMeeting.title': title,
      };
      if (iconEmoji != null) {
        updates['activeMeeting.iconEmoji'] = iconEmoji;
      }
      await _db.collection('couples').doc(coupleId).update(updates);
    } catch (_) {}
  }

  /// Aktif buluşmanın bildirim ayarlarını günceller
  Future<void> updateActiveMeetingNotificationSettings({
    required String coupleId,
    required Map<String, dynamic> notificationUpdates,
  }) async {
    try {
      final Map<String, dynamic> updates = {};
      notificationUpdates.forEach((key, value) {
        updates['activeMeeting.notifications.$key'] = value;
      });
      await _db.collection('couples').doc(coupleId).update(updates);
    } catch (_) {}
  }

  /// Buluşma talebi yanıtı gösterildikten sonra temizler.
  Future<void> clearMeetingResult() async {
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'meetingResult': FieldValue.delete(),
    }).catchError((_) {});
  }
  // 4. "SENİ DÜŞÜNÜYORUM" KALBİ GÖNDERME
  Future<void> sendHeart(String? partnerUid) async {
    if (uid == null || partnerUid == null) return;
    try {
      await _db.collection('users').doc(partnerUid).set({
        'heartPing': {
          'fromUid': uid,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[DATABASE] sendHeart error (likely quota/network): $e');
    }
  }

  Future<void> clearHeartPing() async {
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).update({
        'heartPing': FieldValue.delete(),
      }).timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  /// "Şarjını doldur" hatırlatması gönder
  Future<void> sendChargeReminder(String? partnerUid, {String? fromName}) async {
    if (uid == null || partnerUid == null) return;
    try {
      await _db.collection('users').doc(partnerUid).set({
        'chargePing': {
          'fromUid': uid,
          'fromName': fromName ?? '',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[DATABASE] sendChargeReminder error: $e');
    }
  }

  Future<void> clearChargePing() async {
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'chargePing': FieldValue.delete(),
    }).catchError((_) {});
  }

  // 5. ÖZEL GÜNLER (MILESTONES) CRUD
  Stream<List<Milestone>> milestonesStream({String? coupleId}) {
    // Eğer çift varsa ortak havuzdan, yoksa kişisel alandan çek
    final collection = (coupleId != null && coupleId.isNotEmpty)
        ? _db.collection('couples').doc(coupleId).collection('milestones')
        : (uid != null ? _db.collection('users').doc(uid).collection('milestones') : null);

    if (collection == null) return const Stream.empty();

    return collection.snapshots().map((snap) {
      final list = snap.docs.map((doc) {
        final data = doc.data();
        final docId = doc.id;
        final isSys = (data['isSystem'] ?? data['is_system']) as bool? ??
            (docId == 'valentines_day' || docId == 'womens_day' || docId == 'mens_day');
        return Milestone(
          id: doc.id,
          coupleId: coupleId ?? '',
          title: data['title'] ?? '',
          date: DateTime.parse(data['date']),
          isSystem: isSys,
        );
      }).toList();

      // Tüm özel günleri kalan güne (en yakından en uzağa) göre otomatik sırala
      list.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
      return list;
    });
  }

  Future<void> addMilestone({required String title, required DateTime date, String? coupleId}) async {
    if (coupleId != null && coupleId.isNotEmpty) {
      await _db.collection('couples').doc(coupleId).collection('milestones').add({
        'title': title,
        'date': date.toIso8601String(),
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else if (uid != null) {
      await _db.collection('users').doc(uid).collection('milestones').add({
        'title': title,
        'date': date.toIso8601String(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> updateMilestone({
    required String milestoneId,
    required String title,
    required DateTime date,
    String? coupleId,
  }) async {
    final data = {
      'title': title,
      'date': date.toIso8601String(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (coupleId != null && coupleId.isNotEmpty) {
      await _db.collection('couples').doc(coupleId).collection('milestones').doc(milestoneId).update(data);
    } else if (uid != null) {
      await _db.collection('users').doc(uid).collection('milestones').doc(milestoneId).update(data);
    }
  }

  Future<void> deleteMilestone(String milestoneId, {String? coupleId}) async {
    if (coupleId != null && coupleId.isNotEmpty) {
      await _db.collection('couples').doc(coupleId).collection('milestones').doc(milestoneId).delete();
    } else if (uid != null) {
      await _db.collection('users').doc(uid).collection('milestones').doc(milestoneId).delete();
    }
  }

  /// Birliktelik tarihi girildiğinde veya güncellendiğinde 'Yıldönümümüz' özel gününü otomatik ekler/günceller
  Future<void> syncDefaultAnniversary(DateTime startDate, {String? coupleId}) async {
    try {
      final collection = (coupleId != null && coupleId.isNotEmpty)
          ? _db.collection('couples').doc(coupleId).collection('milestones')
          : (uid != null ? _db.collection('users').doc(uid).collection('milestones') : null);

      if (collection == null) return;

      // Özel bir sabit ID ile saklayalım ki kullanıcı dilerse silsin veya düzenlesin, mükerrer oluşmasın
      final anniversaryDoc = await collection.doc('anniversary_default').get();
      if (!anniversaryDoc.exists) {
        await collection.doc('anniversary_default').set({
          'title': 'Yıldönümümüz 💕',
          'date': startDate.toIso8601String(),
          'isDefault': true,
          'createdBy': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {}
  }

  /// Sevgililer Günü, Kadınlar Günü ve Erkekler Günü gibi evrensel özel günleri çiftin havuzuna ekler
  Future<void> syncDefaultCulturalMilestones({String? coupleId}) async {
    try {
      final collection = (coupleId != null && coupleId.isNotEmpty)
          ? _db.collection('couples').doc(coupleId).collection('milestones')
          : (uid != null ? _db.collection('users').doc(uid).collection('milestones') : null);

      if (collection == null) return;

      final currentYear = DateTime.now().year;

      final defaults = [
        {
          'id': 'valentines_day',
          'title': 'Sevgililer Günü 💘',
          'date': DateTime(currentYear, 2, 14).toIso8601String(),
        },
        {
          'id': 'womens_day',
          'title': 'Kadınlar Günü 💐',
          'date': DateTime(currentYear, 3, 8).toIso8601String(),
        },
        {
          'id': 'mens_day',
          'title': 'Erkekler Günü 👔',
          'date': DateTime(currentYear, 11, 19).toIso8601String(),
        },
      ];

      for (final item in defaults) {
        final docRef = collection.doc(item['id'] as String);
        final doc = await docRef.get();
        if (!doc.exists) {
          await docRef.set({
            'title': item['title'],
            'date': item['date'],
            'isDefault': true,
            'isSystem': true,
            'createdBy': uid,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (_) {}
  }

  /// Doğum gününü çiftin özel günlerine otomatik ekler/günceller
  Future<void> syncBirthdayMilestone({
    required String targetUserId,
    required String userName,
    required String birthDateStr,
    required String coupleId,
  }) async {
    try {
      final bDate = DateTime.tryParse(birthDateStr);
      if (bDate == null) return;

      final collection = _db.collection('couples').doc(coupleId).collection('milestones');
      final docId = 'birthday_$targetUserId';

      final displayName = userName.isNotEmpty ? userName : 'Partner';
      await collection.doc(docId).set({
        'title': '$displayName Doğum Günü 🎂',
        'date': bDate.toIso8601String(),
        'type': 'birthday',
        'isDefault': true,
        'userId': targetUserId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // 6. CANLI KONUM, HAVA, ŞEHİR VE PİL GÜNCELLEME
  Future<void> updateStatus({
    double? lat,
    double? lng,
    int? batteryLevel,
    String? weather,
    String? city,
    double? speed,
    String? currentPlaceTitle,
    String? currentPlaceEmoji,
    bool updateLastActive = false,
  }) async {
    String? targetUid = uid;
    if (targetUid == null) {
      final prefs = await SharedPreferences.getInstance();
      targetUid = prefs.getString('saved_uid');
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_uid', targetUid);
    }
    if (targetUid == null || targetUid.isEmpty) return;

    final Map<String, dynamic> data = {};
    if (updateLastActive) {
      data['lastActive'] = FieldValue.serverTimestamp();
    }
    if (lat != null && lng != null) {
      data['lat'] = lat;
      data['lng'] = lng;
    }
    if (batteryLevel != null) {
      data['batteryLevel'] = batteryLevel;
    }
    if (weather != null && weather.isNotEmpty) {
      data['weather'] = weather;
    }
    if (city != null && city.isNotEmpty) {
      data['city'] = city;
    }
    if (speed != null) {
      data['speed'] = speed;
    }
    if (currentPlaceTitle != null) {
      data['currentPlaceTitle'] = currentPlaceTitle;
      data['currentPlaceEmoji'] = currentPlaceEmoji ?? '';
    }
    if (data.isNotEmpty) {
      try {
        await _db.collection('users').doc(targetUid).set(data, SetOptions(merge: true)).timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
  }

  // 7. UYGULAMA AÇIK / KAPALI AKTİFLİK DURUMU (PRESENCE)
  Future<void> setAppPresence(bool isOpen) async {
    String? targetUid = uid;
    if (targetUid == null) {
      final prefs = await SharedPreferences.getInstance();
      targetUid = prefs.getString('saved_uid');
    }
    if (targetUid == null || targetUid.isEmpty) return;

    try {
      await _db.collection('users').doc(targetUid).set({
        'isAppOpen': isOpen,
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  // 8. MESAJLAŞMA (CHAT) SİSTEMİ
  Stream<List<ChatMessage>> messagesStream(String coupleId) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => ChatMessage.fromJson(doc.data(), doc.id)).toList());
  }

  /// Mesajları okundu olarak işaretle (Çift tik -> Mavi/renkli tik geçişi)
  Future<void> markMessagesAsRead(String coupleId, [List<String>? messageIds]) async {
    if (uid == null) return;
    try {
      if (messageIds != null && messageIds.isNotEmpty) {
        final batch = _db.batch();
        for (final id in messageIds) {
          final docRef = _db.collection('couples').doc(coupleId).collection('messages').doc(id);
          batch.update(docRef, {'isRead': true});
        }
        await batch.commit();
        return;
      }

      // İndeks gerektirmeyen tek alanlı filtre: Sadece 'isRead == false' sorgula,
      // senderId kontrolünü istemci tarafında yap.
      final unreadQuery = await _db
          .collection('couples')
          .doc(coupleId)
          .collection('messages')
          .where('isRead', isEqualTo: false)
          .limit(30)
          .get();

      if (unreadQuery.docs.isEmpty) return;

      final batch = _db.batch();
      bool hasUpdates = false;
      for (final doc in unreadQuery.docs) {
        final data = doc.data();
        if (data['senderId'] != uid) {
          batch.update(doc.reference, {'isRead': true});
          hasUpdates = true;
        }
      }
      if (hasUpdates) {
        await batch.commit();
      }
    } catch (_) {}
  }

  /// Sohbeti temizle (Tüm mesajları siler)
  Future<void> clearChat(String coupleId) async {
    try {
      final messagesSnap = await _db
          .collection('couples')
          .doc(coupleId)
          .collection('messages')
          .limit(300)
          .get();

      if (messagesSnap.docs.isEmpty) return;

      final batch = _db.batch();
      for (final doc in messagesSnap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('[CLEAR-CHAT-ERR] $e');
      rethrow;
    }
  }

  /// Mesajları iletildi olarak işaretle (Tek tik -> Çift tik gri geçişi)
  Future<void> markMessagesAsDelivered(String coupleId, [List<String>? messageIds]) async {
    if (uid == null) return;
    try {
      if (messageIds != null && messageIds.isNotEmpty) {
        final batch = _db.batch();
        for (final id in messageIds) {
          final docRef = _db.collection('couples').doc(coupleId).collection('messages').doc(id);
          batch.update(docRef, {'isDelivered': true});
        }
        await batch.commit();
        return;
      }

      final undeliveredQuery = await _db
          .collection('couples')
          .doc(coupleId)
          .collection('messages')
          .where('isDelivered', isEqualTo: false)
          .limit(30)
          .get();

      if (undeliveredQuery.docs.isEmpty) return;

      final batch = _db.batch();
      bool hasUpdates = false;
      for (final doc in undeliveredQuery.docs) {
        final data = doc.data();
        if (data['senderId'] != uid) {
          batch.update(doc.reference, {'isDelivered': true});
          hasUpdates = true;
        }
      }
      if (hasUpdates) {
        await batch.commit();
      }
    } catch (_) {}
  }

  Future<String?> sendMessage({
    required String coupleId,
    required String text,
    String? mediaBase64,
    String type = 'text',
    String? replyToText,
    String? replyToSender,
    double? locationLat,
    double? locationLng,
    String? locationTitle,
  }) async {
    if (uid == null) return null;
    try {
      final docRef = await _db.collection('couples').doc(coupleId).collection('messages').add({
        'senderId': uid,
        'text': text,
        'mediaBase64': mediaBase64,
        'type': type,
        'createdAt': FieldValue.serverTimestamp(),
        'isDelivered': false,
        'isRead': false,
        'replyToText': replyToText,
        'replyToSender': replyToSender,
        if (locationLat != null) 'locationLat': locationLat,
        if (locationLng != null) 'locationLng': locationLng,
        if (locationTitle != null) 'locationTitle': locationTitle,
      }).timeout(const Duration(seconds: 15));
      return docRef.id;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteMessage(String coupleId, String messageId) async {
    try {
      await _db
          .collection('couples')
          .doc(coupleId)
          .collection('messages')
          .doc(messageId)
          .delete()
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  Future<void> setTypingStatus(String coupleId, bool isTyping) async {
    if (uid == null) return;
    try {
      await _db.collection('couples').doc(coupleId).set({
        'typingStatus': {
          uid: isTyping,
        }
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Stream<bool> typingStatusStream(String coupleId, String partnerUid) {
    return _db.collection('couples').doc(coupleId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return false;
      final typingMap = snap.data()!['typingStatus'] as Map<String, dynamic>?;
      if (typingMap == null) return false;
      return typingMap[partnerUid] == true;
    });
  }

  // 9. HARİTADA KAYITLI / ETİKETLİ ÖZEL YERLER (Ev, İş, Okul vb.)
  Stream<List<SavedPlace>> savedPlacesStream(String coupleId) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('saved_places')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => SavedPlace.fromJson(doc.data(), doc.id)).toList());
  }

  Future<List<SavedPlace>> getSavedPlaces(String coupleId) async {
    try {
      final snap = await _db
          .collection('couples')
          .doc(coupleId)
          .collection('saved_places')
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 4));
      return snap.docs.map((doc) => SavedPlace.fromJson(doc.data(), doc.id)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addSavedPlace({
    required String coupleId,
    required String title,
    required String category,
    required String iconEmoji,
    required double lat,
    required double lng,
    String? createdByName,
  }) async {
    if (uid == null) return;
    try {
      await _db.collection('couples').doc(coupleId).collection('saved_places').add({
        'title': title,
        'category': category,
        'iconEmoji': iconEmoji,
        'lat': lat,
        'lng': lng,
        'createdBy': uid,
        'createdByName': createdByName,
        'createdAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[SAVED_PLACES] addSavedPlace error: $e');
      rethrow;
    }
  }

  Future<void> updateSavedPlace({
    required String coupleId,
    required String placeId,
    required String title,
    required String category,
    required String iconEmoji,
  }) async {
    try {
      await _db
          .collection('couples')
          .doc(coupleId)
          .collection('saved_places')
          .doc(placeId)
          .update({
        'title': title,
        'category': category,
        'iconEmoji': iconEmoji,
      }).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[SAVED_PLACES] updateSavedPlace error: $e');
      rethrow;
    }
  }

  Future<void> updatePlaceNotificationSettings({
    required String coupleId,
    required String placeId,
    required Map<String, dynamic> notificationUpdates,
  }) async {
    try {
      final Map<String, dynamic> updates = {};
      notificationUpdates.forEach((key, value) {
        updates['notifications.$key'] = value;
      });
      await _db
          .collection('couples')
          .doc(coupleId)
          .collection('saved_places')
          .doc(placeId)
          .update(updates)
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[SAVED_PLACES] updatePlaceNotificationSettings error: $e');
    }
  }


  Future<void> deleteSavedPlace(String coupleId, String placeId) async {
    try {
      await _db
          .collection('couples')
          .doc(coupleId)
          .collection('saved_places')
          .doc(placeId)
          .delete()
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  // ==========================================
  // CANLI SATRANÇ METOTLARI
  // ==========================================

  /// Satranç oyunu canlı veri akışı (Stream)
  Stream<DocumentSnapshot<Map<String, dynamic>>> chessGameStream(String coupleId) {
    return _db.collection('couples').doc(coupleId).collection('games').doc('chess').snapshots();
  }

  /// Satranç oyununu başlat (veya yeniden başlat)
  Future<void> startChessGame({
    required String coupleId,
    required String whitePlayerUid,
    required String whitePlayerName,
    required String blackPlayerUid,
    required String blackPlayerName,
  }) async {
    try {
      await _db.collection('couples').doc(coupleId).collection('games').doc('chess').set({
        'status': 'active', // active, checkmate, stalemate, resigned, draw, ended
        'fen': 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        'whitePlayerUid': whitePlayerUid,
        'whitePlayerName': whitePlayerName,
        'blackPlayerUid': blackPlayerUid,
        'blackPlayerName': blackPlayerName,
        'turn': 'w', // 'w' (Beyaz) veya 'b' (Siyah)
        'lastMove': null,
        'winnerUid': null,
        'winnerReason': null,
        'moveHistory': [],
        'whiteReady': false,
        'blackReady': false,
        'whiteOnline': true,
        'blackOnline': true,
        'whiteRematch': false,
        'blackRematch': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[CHESS] startChessGame error: $e');
      rethrow;
    }
  }

  /// Satranç hamlesini kaydet
  Future<void> makeChessMove({
    required String coupleId,
    required String newFen,
    required String nextTurn,
    required Map<String, dynamic> moveData,
    String? status,
    String? winnerUid,
    String? winnerReason,
  }) async {
    try {
      final updates = <String, dynamic>{
        'fen': newFen,
        'turn': nextTurn,
        'lastMove': moveData,
        'moveHistory': FieldValue.arrayUnion([moveData]),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (status != null) updates['status'] = status;
      if (winnerUid != null) updates['winnerUid'] = winnerUid;
      if (winnerReason != null) updates['winnerReason'] = winnerReason;

      await _db.collection('couples').doc(coupleId).collection('games').doc('chess').update(updates);
    } catch (e) {
      debugPrint('[CHESS] makeChessMove error: $e');
      rethrow;
    }
  }

  /// Satranç oyun ekranında olup olmadığını günceller (presence)
  Future<void> setChessOnlineStatus({
    required String coupleId,
    required bool isWhite,
    required bool isOnline,
  }) async {
    try {
      final docRef = _db.collection('couples').doc(coupleId).collection('games').doc('chess');
      final field = isWhite ? 'whiteOnline' : 'blackOnline';
      await docRef.set({
        field: isOnline,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[CHESS] setChessOnlineStatus error: $e');
    }
  }

  /// Satranç oyununu duraklat
  Future<void> pauseChessGame({
    required String coupleId,
    required String pausedByUid,
    required String pausedByName,
  }) async {
    try {
      final docRef = _db.collection('couples').doc(coupleId).collection('games').doc('chess');
      final snap = await docRef.get();
      if (!snap.exists) return;
      final currentStatus = snap.data()?['status'] as String?;
      if (currentStatus == 'active') {
        await docRef.update({
          'status': 'paused',
          'pausedByUid': pausedByUid,
          'pausedByName': pausedByName,
          'pausedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('[CHESS] pauseChessGame error: $e');
    }
  }

  /// Satranç oyununu devam ettir
  Future<bool> resumeChessGame({
    required String coupleId,
  }) async {
    try {
      final docRef = _db.collection('couples').doc(coupleId).collection('games').doc('chess');
      final snap = await docRef.get();
      if (!snap.exists) return false;
      final data = snap.data();
      if (data == null) return false;

      final currentStatus = data['status'] as String?;
      final whiteOnline = data['whiteOnline'] == true;
      final blackOnline = data['blackOnline'] == true;

      if (!whiteOnline || !blackOnline) {
        return false;
      }

      if (currentStatus == 'paused') {
        await docRef.update({
          'status': 'active',
          'pausedByUid': null,
          'pausedByName': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[CHESS] resumeChessGame error: $e');
      return false;
    }
  }

  /// Oyundan tamamen çıkınca oyunu sonlandır ve sıfırla
  Future<void> exitChessGame({
    required String coupleId,
    required String exitUid,
    String? exitReason,
  }) async {
    try {
      final docRef = _db.collection('couples').doc(coupleId).collection('games').doc('chess');
      final snap = await docRef.get();
      if (!snap.exists) return;
      final currentStatus = snap.data()?['status'] as String?;
      if (currentStatus == 'active' || currentStatus == 'waiting_ready' || currentStatus == 'paused') {
        await docRef.update({
          'status': 'ended',
          'exitReason': exitReason ?? loc('Partnerin oyundan çıktı', 'Partner left the game'),
          'exitUid': exitUid,
          'whiteOnline': false,
          'blackOnline': false,
          'whiteRematch': false,
          'blackRematch': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('[CHESS] exitChessGame error: $e');
    }
  }

  /// Satranç oyununu sıfırla (Tekrar 'Oyna' ekranına dönmek için)
  Future<void> resetChessGame({
    required String coupleId,
    String? exitReason,
    String? exitUid,
  }) async {
    try {
      await _db.collection('couples').doc(coupleId).collection('games').doc('chess').set({
        'status': 'ended',
        'exitReason': exitReason ?? loc('Partnerin oyundan çıktı', 'Partner left the game'),
        'exitUid': exitUid ?? uid,
        'whiteOnline': false,
        'blackOnline': false,
        'whiteRematch': false,
        'blackRematch': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[CHESS] resetChessGame error: $e');
    }
  }

  /// Oyun bittikten sonra 'Tekrar Oyna' isteği
  /// Her iki taraf da bastığında oyun waiting_ready aşamasına geçer
  Future<void> requestChessRematch({
    required String coupleId,
    required bool isWhite,
  }) async {
    try {
      final docRef = _db.collection('couples').doc(coupleId).collection('games').doc('chess');
      await _db.runTransaction((transaction) async {
        final snap = await transaction.get(docRef);
        if (!snap.exists) return;
        final data = snap.data();
        if (data == null) return;

        final myKey = isWhite ? 'whiteRematch' : 'blackRematch';
        final otherKey = isWhite ? 'blackRematch' : 'whiteRematch';
        final otherWantsRematch = data[otherKey] == true;

        if (otherWantsRematch) {
          transaction.update(docRef, {
            'status': 'active',
            'fen': 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
            'turn': 'w',
            'lastMove': null,
            'winnerUid': null,
            'winnerReason': null,
            'moveHistory': [],
            'whiteReady': true,
            'blackReady': true,
            'whiteRematch': false,
            'blackRematch': false,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          transaction.update(docRef, {
            myKey: true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (e) {
      debugPrint('[CHESS] requestChessRematch error: $e');
    }
  }

  /// Oyundan çekil / Pes et
  Future<void> resignChessGame({
    required String coupleId,
    required String resignedUid,
    required String winnerUid,
  }) async {
    try {
      await _db.collection('couples').doc(coupleId).collection('games').doc('chess').update({
        'status': 'resigned',
        'winnerUid': winnerUid,
        'winnerReason': loc('Partner oyundan çekildi', 'Partner resigned'),
        'whiteRematch': false,
        'blackRematch': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[CHESS] resignChessGame error: $e');
    }
  }

  /// Partnere satranç oynama isteği gönderir
  Future<void> sendChessRequest({
    required String partnerUid,
    required String fromName,
    required String coupleId,
  }) async {
    final myUid = uid;
    if (myUid == null) return;
    final reqId = 'chess_${DateTime.now().millisecondsSinceEpoch}';

    // 1. Önce doğrudan couples/{coupleId}/games/chess dökümanına yaz (her iki partnerin de tam yetkisi var)
    await _db.collection('couples').doc(coupleId).collection('games').doc('chess').set({
      'id': reqId,
      'game': 'chess',
      'gameTitle': loc('Satranç', 'Chess'),
      'status': 'invitation_pending',
      'fromUid': myUid,
      'fromName': fromName,
      'toUid': partnerUid,
      'whitePlayerUid': myUid,
      'whitePlayerName': fromName,
      'blackPlayerUid': partnerUid,
      'whiteReady': true,
      'blackReady': false,
      'whiteOnline': true,
      'blackOnline': false,
      'fen': 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      'turn': 'w',
      'lastMove': null,
      'winnerUid': null,
      'winnerReason': null,
      'moveHistory': [],
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2. Opsiyonel olarak users/{partnerUid} dökümanına da yazmayı dene (hata verirse yut)
    try {
      await _db.collection('users').doc(partnerUid).set({
        'pendingGameRequest': {
          'id': reqId,
          'game': 'chess',
          'gameTitle': loc('Satranç', 'Chess'),
          'fromUid': myUid,
          'fromName': fromName,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[CHESS] Optional user doc pendingGameRequest write skipped: $e');
    }
  }

  /// Partnere giden oyun isteğini yanıtla (kabul / ret)
  Future<void> respondChessRequest({
    required String coupleId,
    required String fromUid,
    required bool accepted,
    required String responderName,
  }) async {
    final myUid = uid;
    if (myUid == null) return;
    try {
      if (accepted) {
        await _db.collection('couples').doc(coupleId).collection('games').doc('chess').update({
          'status': 'active',
          'blackPlayerName': responderName,
          'responderName': responderName,
          'whiteReady': true,
          'blackReady': true,
          'whiteOnline': true,
          'blackOnline': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _db.collection('couples').doc(coupleId).collection('games').doc('chess').update({
          'status': 'rejected',
          'responderName': responderName,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('[CHESS] respondChessRequest error: $e');
    }

    try {
      await _db.collection('users').doc(myUid).set({
        'pendingGameRequest': FieldValue.delete(),
      }, SetOptions(merge: true));
    } catch (_) {}

    try {
      await _db.collection('users').doc(fromUid).set({
        'gameResult': {
          'game': 'chess',
          'status': accepted ? 'accepted' : 'rejected',
          'byName': responderName,
          'timestamp': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Oyun sonuç bildirimini temizle
  Future<void> clearGameResult() async {
    final myUid = uid;
    if (myUid == null) return;
    try {
      await _db.collection('users').doc(myUid).update({'gameResult': FieldValue.delete()});
    } catch (_) {}
  }

  /// Oyuncu hazır durumunu ayarla (whiteReady veya blackReady)
  Future<void> setChessPlayerReady({
    required String coupleId,
    required bool isWhite,
    required bool isReady,
  }) async {
    try {
      final docRef = _db.collection('couples').doc(coupleId).collection('games').doc('chess');
      await _db.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) return;
        final data = snapshot.data();
        if (data == null) return;

        final myKey = isWhite ? 'whiteReady' : 'blackReady';
        final otherKey = isWhite ? 'blackReady' : 'whiteReady';
        final otherReady = data[otherKey] == true;

        final updates = <String, dynamic>{
          myKey: isReady,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (isReady && otherReady) {
          updates['status'] = 'active';
        }

        transaction.update(docRef, updates);
      });
    } catch (e) {
      debugPrint('[CHESS] setChessPlayerReady error: $e');
    }
  }

  // ==========================================
  // GENEL ÇOKLU OYUN METOTLARI (BİLARDO & TAVLA)
  // ==========================================

  /// Belirtilen oyun için canlı veri akışı ('billiards', 'backgammon', 'chess')
  Stream<DocumentSnapshot<Map<String, dynamic>>> gameStream(String coupleId, String gameType) {
    return _db.collection('couples').doc(coupleId).collection('games').doc(gameType).snapshots();
  }

  /// Oyuncu ekran içi online durumunu günceller
  Future<void> setGameOnlineStatus({
    required String coupleId,
    required String gameType,
    required bool isPlayer1,
    required bool isOnline,
  }) async {
    try {
      final docRef = _db.collection('couples').doc(coupleId).collection('games').doc(gameType);
      final field = isPlayer1 ? 'whiteOnline' : 'blackOnline';
      await docRef.set({
        field: isOnline,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[$gameType] setGameOnlineStatus error: $e');
    }
  }

  /// Oyundan tamamen çıkınca oyunu sonlandır
  Future<void> exitGame({
    required String coupleId,
    required String gameType,
    required String exitUid,
    String? exitReason,
  }) async {
    try {
      final docRef = _db.collection('couples').doc(coupleId).collection('games').doc(gameType);
      final snap = await docRef.get();
      if (!snap.exists) return;
      final currentStatus = snap.data()?['status'] as String?;
      if (currentStatus == 'active' || currentStatus == 'waiting_ready' || currentStatus == 'paused') {
        await docRef.update({
          'status': 'ended',
          'exitReason': exitReason ?? loc('Partnerin oyundan çıktı', 'Partner left the game'),
          'exitUid': exitUid,
          'whiteOnline': false,
          'blackOnline': false,
          'whiteRematch': false,
          'blackRematch': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('[$gameType] exitGame error: $e');
    }
  }

  /// Oyunu sıfırla ('Oyna' ekranına dönmek için)
  Future<void> resetGame({
    required String coupleId,
    required String gameType,
    String? exitReason,
    String? exitUid,
  }) async {
    try {
      await _db.collection('couples').doc(coupleId).collection('games').doc(gameType).set({
        'status': 'ended',
        'exitReason': exitReason ?? loc('Partnerin oyundan çıktı', 'Partner left the game'),
        'exitUid': exitUid ?? uid,
        'whiteOnline': false,
        'blackOnline': false,
        'whiteRematch': false,
        'blackRematch': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[$gameType] resetGame error: $e');
    }
  }

  /// Oyundan çekil / Pes et
  Future<void> resignGame({
    required String coupleId,
    required String gameType,
    required String resignedUid,
    required String winnerUid,
  }) async {
    try {
      await _db.collection('couples').doc(coupleId).collection('games').doc(gameType).update({
        'status': 'resigned',
        'winnerUid': winnerUid,
        'winnerReason': loc('Partner oyundan çekildi', 'Partner resigned'),
        'whiteRematch': false,
        'blackRematch': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[$gameType] resignGame error: $e');
    }
  }

  /// Oyuncu hazır durumunu ayarla
  Future<void> setGamePlayerReady({
    required String coupleId,
    required String gameType,
    required bool isPlayer1,
    required bool isReady,
  }) async {
    try {
      final docRef = _db.collection('couples').doc(coupleId).collection('games').doc(gameType);
      await _db.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) return;
        final data = snapshot.data();
        if (data == null) return;

        final myKey = isPlayer1 ? 'whiteReady' : 'blackReady';
        final otherKey = isPlayer1 ? 'blackReady' : 'whiteReady';
        final otherReady = data[otherKey] == true;

        final updates = <String, dynamic>{
          myKey: isReady,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (isReady && otherReady) {
          updates['status'] = 'active';
        }

        transaction.update(docRef, updates);
      });
    } catch (e) {
      debugPrint('[$gameType] setGamePlayerReady error: $e');
    }
  }

  /// Partnere oyun oynama isteği gönderir (chess, billiards, backgammon)
  Future<void> sendGameRequest({
    required String gameType,
    required String gameTitle,
    required String partnerUid,
    required String fromName,
    required String coupleId,
    required Map<String, dynamic> initialGameData,
  }) async {
    final myUid = uid;
    if (myUid == null) return;
    final reqId = '${gameType}_${DateTime.now().millisecondsSinceEpoch}';

    // Var olan oyun dokümanını kontrol et: Önceden cevaplanmış sorular varsa (answeredMap) koru
    Map<String, dynamic> existingAnswered = {};
    try {
      final existingDoc = await _db.collection('couples').doc(coupleId).collection('games').doc(gameType).get();
      if (existingDoc.exists && existingDoc.data() != null) {
        final data = existingDoc.data()!;
        if (data['answeredMap'] is Map) {
          existingAnswered = Map<String, dynamic>.from(data['answeredMap'] as Map);
        }
      }
    } catch (_) {}

    final mergedData = Map<String, dynamic>.from(initialGameData);
    if (existingAnswered.isNotEmpty) {
      final initialMap = (mergedData['answeredMap'] as Map?) ?? {};
      mergedData['answeredMap'] = {
        ...existingAnswered,
        ...initialMap,
      };
    }

    await _db.collection('couples').doc(coupleId).collection('games').doc(gameType).set({
      'id': reqId,
      'game': gameType,
      'gameTitle': gameTitle,
      'status': 'invitation_pending',
      'fromUid': myUid,
      'fromName': fromName,
      'toUid': partnerUid,
      'whitePlayerUid': myUid,
      'whitePlayerName': fromName,
      'blackPlayerUid': partnerUid,
      'whiteReady': true,
      'blackReady': false,
      'whiteOnline': true,
      'blackOnline': false,
      'whiteRematch': false,
      'blackRematch': false,
      'winnerUid': null,
      'winnerReason': null,
      ...mergedData,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    try {
      await _db.collection('users').doc(partnerUid).set({
        'pendingGameRequest': {
          'id': reqId,
          'game': gameType,
          'gameTitle': gameTitle,
          'fromUid': myUid,
          'fromName': fromName,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[$gameType] Optional user doc pendingGameRequest write skipped: $e');
    }
  }

  /// Gönderilen bekleyen oyun davetini iptal et
  Future<void> cancelGameRequest({
    required String coupleId,
    required String gameType,
    required String partnerUid,
  }) async {
    final myUid = uid;
    if (myUid == null) return;
    try {
      await _db.collection('couples').doc(coupleId).collection('games').doc(gameType).update({
        'status': 'cancelled',
        'cancelledByUid': myUid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[$gameType] cancelGameRequest error: $e');
    }

    try {
      await _db.collection('users').doc(partnerUid).set({
        'pendingGameRequest': FieldValue.delete(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Partnere giden genel oyun isteğini yanıtla (kabul / ret)
  Future<void> respondGameRequest({
    required String coupleId,
    required String gameType,
    required String fromUid,
    required bool accepted,
    required String responderName,
  }) async {
    final myUid = uid;
    if (myUid == null) return;
    try {
      if (accepted) {
        await _db.collection('couples').doc(coupleId).collection('games').doc(gameType).update({
          'status': 'active',
          'blackPlayerName': responderName,
          'responderName': responderName,
          'whiteReady': true,
          'blackReady': true,
          'whiteOnline': true,
          'blackOnline': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _db.collection('couples').doc(coupleId).collection('games').doc(gameType).update({
          'status': 'rejected',
          'responderName': responderName,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('[$gameType] respondGameRequest error: $e');
    }

    try {
      await _db.collection('users').doc(myUid).set({
        'pendingGameRequest': FieldValue.delete(),
      }, SetOptions(merge: true));
    } catch (_) {}

    try {
      await _db.collection('users').doc(fromUid).set({
        'gameResult': {
          'game': gameType,
          'status': accepted ? 'accepted' : 'rejected',
          'byName': responderName,
          'timestamp': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Oyun bittikten sonra 'Tekrar Oyna' isteği (Genel)
  Future<void> requestGameRematch({
    required String coupleId,
    required String gameType,
    required bool isPlayer1,
    required Map<String, dynamic> resetData,
  }) async {
    try {
      final docRef = _db.collection('couples').doc(coupleId).collection('games').doc(gameType);
      await _db.runTransaction((transaction) async {
        final snap = await transaction.get(docRef);
        if (!snap.exists) return;
        final data = snap.data();
        if (data == null) return;

        final myKey = isPlayer1 ? 'whiteRematch' : 'blackRematch';
        final otherKey = isPlayer1 ? 'blackRematch' : 'whiteRematch';
        final otherWantsRematch = data[otherKey] == true;

        if (otherWantsRematch) {
          transaction.update(docRef, {
            'status': 'active',
            'winnerUid': null,
            'winnerReason': null,
            'whiteReady': true,
            'blackReady': true,
            'whiteRematch': false,
            'blackRematch': false,
            ...resetData,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          transaction.update(docRef, {
            myKey: true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (e) {
      debugPrint('[$gameType] requestGameRematch error: $e');
    }
  }

  /// Oyun durumunu güncelle (Bilardo atışı veya Tavla hamlesi / zar atışı)
  Future<void> updateGameState({
    required String coupleId,
    required String gameType,
    required Map<String, dynamic> updates,
  }) async {
    try {
      await _db.collection('couples').doc(coupleId).collection('games').doc(gameType).update({
        ...updates,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[$gameType] updateGameState error: $e');
      rethrow;
    }
  }

  /// Çizim Gönder (Canlı Çizim Tuvali / Noteit Modeli)
  Future<void> sendDrawing({
    required String coupleId,
    required String imageBase64,
    required String senderName,
    String? note,
  }) async {
    if (uid == null) return;
    try {
      final drawingDoc = {
        'senderId': uid,
        'senderName': senderName,
        'imageBase64': imageBase64,
        'note': note,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // 1. Son çizimi anında partnerin erişebileceği ana referansa yaz
      await _db.collection('couples').doc(coupleId).collection('drawings').doc('latest').set(
        drawingDoc,
        SetOptions(merge: true),
      );

      // 2. Geçmiş albümüne de ekle
      await _db.collection('couples').doc(coupleId).collection('drawings_history').add(drawingDoc);
      debugPrint('[DatabaseService] Drawing sent successfully: sender=$senderName');
    } catch (e) {
      debugPrint('[DatabaseService] sendDrawing error: $e');
      rethrow;
    }
  }

  /// Çiftin son canlı çizimini dinle
  Stream<DocumentSnapshot<Map<String, dynamic>>>? latestDrawingStream(String coupleId) {
    if (coupleId.isEmpty) return null;
    return _db.collection('couples').doc(coupleId).collection('drawings').doc('latest').snapshots();
  }

  /// Ortak Sohbet Arka Planı Güncelle (Her iki taraf için de anlık ve kalıcı olur)
  Future<void> updateChatBackground(String coupleId, String base64Str, String senderName) async {
    if (coupleId.isEmpty) return;
    try {
      await _db.collection('couples').doc(coupleId).set({
        'chatBackgroundUrl': base64Str,
        'chatBackgroundSetBy': senderName,
        'chatBackgroundUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[DatabaseService] updateChatBackground error: $e');
      rethrow;
    }
  }

  /// Ortak Sohbet Arka Planını Kaldır (Varsayılan Lovera temasına döner)
  Future<void> removeChatBackground(String coupleId) async {
    if (coupleId.isEmpty) return;
    try {
      await _db.collection('couples').doc(coupleId).set({
        'chatBackgroundUrl': '',
        'chatBackgroundSetBy': '',
        'chatBackgroundUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('[DatabaseService] removeChatBackground error: $e');
      rethrow;
    }
  }

  // 10. ORTAK ANI ALBÜMÜ (MEMORIES) CRUD
  Stream<List<MemoryItem>> memoriesStream(String coupleId) {
    if (coupleId.isEmpty) return const Stream.empty();
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('memories')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => MemoryItem.fromJson(d.data(), d.id)).toList())
        .asBroadcastStream();
  }

  Stream<List<MemoryAlbum>> albumsStream(String coupleId) {
    if (coupleId.isEmpty) return const Stream.empty();
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('memory_albums')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => MemoryAlbum.fromJson(d.data(), d.id)).toList())
        .asBroadcastStream();
  }

  Future<void> addMemory({
    required String coupleId,
    required String imageBase64,
    required String caption,
    required String locationTitle,
    required DateTime date,
    required String createdByName,
    String? albumId,
    String? albumTitle,
  }) async {
    if (coupleId.isEmpty || uid == null) return;
    await _db.collection('couples').doc(coupleId).collection('memories').add({
      'coupleId': coupleId,
      'imageUrl': imageBase64,
      'caption': caption.trim(),
      'locationTitle': locationTitle.trim(),
      'date': date.toIso8601String(),
      'createdBy': uid,
      'createdByName': createdByName,
      'createdAt': FieldValue.serverTimestamp(),
      'likedBy': [],
      if (albumId != null) 'albumId': albumId,
      if (albumTitle != null) 'albumTitle': albumTitle,
    });
  }

  /// Birden fazla fotoğrafı ortak anı albümüne ekler
  Future<void> addMultipleMemories({
    required String coupleId,
    required List<String> imagesBase64,
    required String createdByName,
    String caption = '',
    String locationTitle = '',
    DateTime? commonDate,
    String? albumId,
    String? albumTitle,
  }) async {
    if (coupleId.isEmpty || uid == null || imagesBase64.isEmpty) return;
    final now = commonDate ?? DateTime.now();

    final batch = _db.batch();
    for (final img in imagesBase64) {
      final docRef = _db.collection('couples').doc(coupleId).collection('memories').doc();
      batch.set(docRef, {
        'coupleId': coupleId,
        'imageUrl': img,
        'caption': caption.trim(),
        'locationTitle': locationTitle.trim(),
        'date': now.toIso8601String(),
        'createdBy': uid,
        'createdByName': createdByName,
        'createdAt': FieldValue.serverTimestamp(),
        'likedBy': [],
        if (albumId != null) 'albumId': albumId,
        if (albumTitle != null) 'albumTitle': albumTitle,
      });
    }

    // Eğer bir anı grubuna ekleniyorsa, anı grubunun fotoğraf sayısını ve kapak fotosunu güncelle
    if (albumId != null && albumId.isNotEmpty) {
      final albumRef = _db.collection('couples').doc(coupleId).collection('memory_albums').doc(albumId);
      String currentCover = '';
      try {
        final albumDoc = await albumRef.get();
        if (albumDoc.exists) {
          currentCover = albumDoc.data()?['coverImageUrl'] as String? ?? '';
        }
      } catch (_) {}
      batch.update(albumRef, {
        'photoCount': FieldValue.increment(imagesBase64.length),
        if (currentCover.isEmpty && imagesBase64.isNotEmpty) 'coverImageUrl': imagesBase64.first,
      });
    }

    await batch.commit();
  }

  /// Yeni Anı Grubu (Klasör) oluşturur ve seçilen fotoğrafları bu gruba bağlar
  Future<String> createMemoryAlbum({
    required String coupleId,
    required String title,
    required String description,
    required String locationTitle,
    required DateTime date,
    required String coverImageUrl,
    required String createdByName,
    required List<String> photosBase64,
  }) async {
    if (coupleId.isEmpty || uid == null) return '';

    final albumRef = _db.collection('couples').doc(coupleId).collection('memory_albums').doc();
    final albumId = albumRef.id;

    final batch = _db.batch();
    batch.set(albumRef, {
      'coupleId': coupleId,
      'title': title.trim(),
      'description': description.trim(),
      'locationTitle': locationTitle.trim(),
      'date': date.toIso8601String(),
      'coverImageUrl': coverImageUrl,
      'photoCount': photosBase64.length,
      'createdBy': uid,
      'createdByName': createdByName,
      'createdAt': FieldValue.serverTimestamp(),
    });

    for (final img in photosBase64) {
      final memRef = _db.collection('couples').doc(coupleId).collection('memories').doc();
      batch.set(memRef, {
        'coupleId': coupleId,
        'imageUrl': img,
        'caption': description.trim(),
        'locationTitle': locationTitle.trim(),
        'date': date.toIso8601String(),
        'createdBy': uid,
        'createdByName': createdByName,
        'createdAt': FieldValue.serverTimestamp(),
        'likedBy': [],
        'albumId': albumId,
        'albumTitle': title.trim(),
      });
    }

    await batch.commit();
    return albumId;
  }

  /// Var olan anıları seçip yeni veya mevcut bir anı grubuna taşır/gruplar
  Future<void> groupExistingMemories({
    required String coupleId,
    required List<String> memoryIds,
    required String albumId,
    required String albumTitle,
  }) async {
    if (coupleId.isEmpty || memoryIds.isEmpty) return;

    final batch = _db.batch();
    for (final id in memoryIds) {
      final docRef = _db.collection('couples').doc(coupleId).collection('memories').doc(id);
      batch.update(docRef, {
        'albumId': albumId,
        'albumTitle': albumTitle,
      });
    }

    final albumRef = _db.collection('couples').doc(coupleId).collection('memory_albums').doc(albumId);
    String currentCover = '';
    try {
      final albumDoc = await albumRef.get();
      if (albumDoc.exists) {
        currentCover = albumDoc.data()?['coverImageUrl'] as String? ?? '';
      }
    } catch (_) {}

    String firstCover = '';
    if (currentCover.isEmpty) {
      try {
        final firstMemDoc = await _db.collection('couples').doc(coupleId).collection('memories').doc(memoryIds.first).get();
        if (firstMemDoc.exists) {
          firstCover = firstMemDoc.data()?['imageUrl'] as String? ?? '';
        }
      } catch (_) {}
    }

    batch.update(albumRef, {
      'photoCount': FieldValue.increment(memoryIds.length),
      if (currentCover.isEmpty && firstCover.isNotEmpty) 'coverImageUrl': firstCover,
    });

    await batch.commit();
  }

  /// Tek bir anının bilgilerini (not, mekan, tarih, albüm) günceller
  Future<void> updateMemoryDetails({
    required String coupleId,
    required String memoryId,
    required String caption,
    required String locationTitle,
    required DateTime date,
  }) async {
    if (coupleId.isEmpty || memoryId.isEmpty) return;
    await _db.collection('couples').doc(coupleId).collection('memories').doc(memoryId).update({
      'caption': caption.trim(),
      'locationTitle': locationTitle.trim(),
      'date': date.toIso8601String(),
    });
  }

  /// Anı grubu (klasör) bilgilerini günceller
  Future<void> updateMemoryAlbum({
    required String coupleId,
    required String albumId,
    required String title,
    required String description,
    required String locationTitle,
    required DateTime date,
  }) async {
    if (coupleId.isEmpty || albumId.isEmpty) return;
    await _db.collection('couples').doc(coupleId).collection('memory_albums').doc(albumId).update({
      'title': title.trim(),
      'description': description.trim(),
      'locationTitle': locationTitle.trim(),
      'date': date.toIso8601String(),
    });

    // Bu klasöre bağlı anıların albumTitle bilgisini de senkronize güncelle
    final snap = await _db
        .collection('couples')
        .doc(coupleId)
        .collection('memories')
        .where('albumId', isEqualTo: albumId)
        .get();

    if (snap.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {
          'albumTitle': title.trim(),
        });
      }
      await batch.commit();
    }
  }

  /// Anı grubunu ve içindeki anıların grup bağını siler
  Future<void> deleteMemoryAlbum({
    required String coupleId,
    required String albumId,
  }) async {
    if (coupleId.isEmpty || albumId.isEmpty) return;
    await _db.collection('couples').doc(coupleId).collection('memory_albums').doc(albumId).delete();

    // Gruptaki anıların albumId bağını kaldır (fotoğraflar albümde kalsın ama gruptan çıksın)
    final snap = await _db
        .collection('couples')
        .doc(coupleId)
        .collection('memories')
        .where('albumId', isEqualTo: albumId)
        .get();

    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {
        'albumId': FieldValue.delete(),
        'albumTitle': FieldValue.delete(),
      });
    }
    await batch.commit();
  }

  Future<void> toggleMemoryLike({
    required String coupleId,
    required String memoryId,
    required bool isLiked,
  }) async {
    if (coupleId.isEmpty || uid == null) return;
    final ref = _db.collection('couples').doc(coupleId).collection('memories').doc(memoryId);
    if (isLiked) {
      await ref.update({
        'likedBy': FieldValue.arrayRemove([uid]),
      });
    } else {
      await ref.update({
        'likedBy': FieldValue.arrayUnion([uid]),
      });
    }
  }

  Future<void> deleteMemory({
    required String coupleId,
    required String memoryId,
    String? albumId,
  }) async {
    if (coupleId.isEmpty) return;
    await _db.collection('couples').doc(coupleId).collection('memories').doc(memoryId).delete();
    if (albumId != null && albumId.isNotEmpty) {
      await _db
          .collection('couples')
          .doc(coupleId)
          .collection('memory_albums')
          .doc(albumId)
          .update({'photoCount': FieldValue.increment(-1)})
          .catchError((_) {});
    }
  }

  /// Toplu olarak anıları siler ve bağlı oldukları albüm sayılarını günceller
  Future<void> deleteMultipleMemories({
    required String coupleId,
    required List<String> memoryIds,
    required List<MemoryItem> allMemories,
  }) async {
    if (coupleId.isEmpty || memoryIds.isEmpty) return;
    final batch = _db.batch();
    final Map<String, int> albumDecrementMap = {};

    for (final id in memoryIds) {
      final docRef = _db.collection('couples').doc(coupleId).collection('memories').doc(id);
      batch.delete(docRef);

      final match = allMemories.where((m) => m.id == id).firstOrNull;
      if (match != null && match.albumId != null && match.albumId!.isNotEmpty) {
        albumDecrementMap[match.albumId!] = (albumDecrementMap[match.albumId!] ?? 0) + 1;
      }
    }

    for (final entry in albumDecrementMap.entries) {
      final albumRef = _db.collection('couples').doc(coupleId).collection('memory_albums').doc(entry.key);
      batch.update(albumRef, {'photoCount': FieldValue.increment(-entry.value)});
    }

    await batch.commit();
  }

  /// Tekli veya toplu anıları mevcut bir albüme ekler/ilişkilendirir
  Future<void> addMemoriesToExistingAlbum({
    required String coupleId,
    required List<String> memoryIds,
    required String albumId,
    required String albumTitle,
  }) async {
    await groupExistingMemories(
      coupleId: coupleId,
      memoryIds: memoryIds,
      albumId: albumId,
      albumTitle: albumTitle,
    );
  }
}



