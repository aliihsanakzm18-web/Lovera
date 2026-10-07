import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get uid => _auth.currentUser?.uid;

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
      final name = userName ?? _auth.currentUser?.displayName ?? 'Doğum Günü';
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
    return doc.data();
  }

  /// 1. Adım: Karşı tarafa eşleşme isteği gönder
  Future<void> sendPairRequest({
    required String targetUid,
    required String myName,
    required String? myAvatar,
  }) async {
    if (uid == null) return;
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
  }

  /// 2. Adım: Gelen isteği kabul et ve ortak Çift (Couple) oluştur
  Future<String> acceptPairRequest({
    required String requesterUid,
    required DateTime relationshipStartDate,
  }) async {
    if (uid == null) throw Exception('Giriş yapılmamış');

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

    await batch.commit();

    // Otomatik Özel Günler: Yıldönümü ve her iki tarafın doğum günlerini ekle
    await syncDefaultAnniversary(relationshipStartDate, coupleId: coupleId);

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

  // 4. "SENİ DÜŞÜNÜYORUM" KALBİ GÖNDERME
  Future<void> sendHeart(String? partnerUid) async {
    if (uid == null || partnerUid == null) return;
    await _db.collection('users').doc(partnerUid).set({
      'heartPing': {
        'fromUid': uid,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }
    }, SetOptions(merge: true));
  }

  Future<void> clearHeartPing() async {
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'heartPing': FieldValue.delete(),
    }).catchError((_) {});
  }

  /// "Şarjını doldur" hatırlatması gönder
  Future<void> sendChargeReminder(String? partnerUid, {String? fromName}) async {
    if (uid == null || partnerUid == null) return;
    await _db.collection('users').doc(partnerUid).set({
      'chargePing': {
        'fromUid': uid,
        'fromName': fromName ?? '',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }
    }, SetOptions(merge: true));
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

    return collection.orderBy('date').snapshots().map((snap) => snap.docs.map((doc) {
          final data = doc.data();
          return Milestone(
            id: doc.id,
            coupleId: coupleId ?? '',
            title: data['title'] ?? '',
            date: DateTime.parse(data['date']),
          );
        }).toList());
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

  Future<void> sendMessage({
    required String coupleId,
    required String text,
    String? mediaBase64,
    String type = 'text',
    String? replyToText,
    String? replyToSender,
  }) async {
    if (uid == null) return;
    try {
      await _db.collection('couples').doc(coupleId).collection('messages').add({
        'senderId': uid,
        'text': text,
        'mediaBase64': mediaBase64,
        'type': type,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
        'replyToText': replyToText,
        'replyToSender': replyToSender,
      }).timeout(const Duration(seconds: 4));
    } catch (_) {}
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
}
