import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_service.dart';
import 'notification_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Bu cihazın kimliğini ve FCM token'ını Firestore'a bağlayıp tek cihaz oturumunu aktif eder
  Future<void> registerDeviceSession(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_uid', uid);

      final deviceId = await DeviceService().getOrCreateDeviceId();
      final fcmToken = await NotificationService().getFcmToken();

      final Map<String, dynamic> updateData = {
        'currentDeviceId': deviceId,
        'isAppOpen': true,
        'lastActive': FieldValue.serverTimestamp(),
      };
      if (fcmToken != null && fcmToken.isNotEmpty) {
        updateData['fcmToken'] = fcmToken;
      }

      await _firestore
          .collection('users')
          .doc(uid)
          .set(updateData, SetOptions(merge: true))
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  // E-posta & Şifre ile Kayıt Ol
  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
    required String username,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    if (cred.user != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_uid', cred.user!.uid);
      await cred.user!.updateDisplayName(username);
      // Firestore'da kullanıcı dokümanı oluştur
      try {
        await _firestore.collection('users').doc(cred.user!.uid).set({
          'id': cred.user!.uid,
          'name': username,
          'email': email,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 4));
      } catch (_) {}

      // Cihaz oturumunu arka planda bağla (UI'ı bekletmez)
      registerDeviceSession(cred.user!.uid);
    }

    return cred;
  }

  // E-posta & Şifre ile Giriş Yap
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (cred.user != null) {
      // Cihaz oturumunu arka planda bağla (Giriş işlemini bloke etmez)
      registerDeviceSession(cred.user!.uid);
    }
    return cred;
  }

  // Google ile Giriş Yap
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // Kullanıcı iptal etti

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final cred = await _auth.signInWithCredential(credential);

      if (cred.user != null) {
        try {
          await _firestore.collection('users').doc(cred.user!.uid).set({
            'id': cred.user!.uid,
            'name': cred.user!.displayName ?? googleUser.displayName ?? 'İsimsiz',
            'email': cred.user!.email ?? googleUser.email,
            'photoUrl': cred.user!.photoURL,
            'lastLogin': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)).timeout(const Duration(seconds: 4));
        } catch (_) {}

        registerDeviceSession(cred.user!.uid);
      }

      return cred;
    } catch (e) {
      rethrow;
    }
  }

  // Tam Kapsamlı ve Güvenli Çıkış Yap
  Future<void> signOut({bool clearRemoteSession = true}) async {
    final uid = _auth.currentUser?.uid;

    // 1. Cihaz takip ve sensörlerini derhal durdur
    DeviceService().stopTracking();

    // 2. Android 7/24 Foreground Arka Plan Servisini durdur
    try {
      final bgService = FlutterBackgroundService();
      if (await bgService.isRunning()) {
        bgService.invoke('stopService');
      }
    } catch (_) {}

    // 3. Uzak oturumu ve bildirim token'ını arka planda sessizce temizle (Asla UI'ı bloke etmez)
    if (uid != null && clearRemoteSession) {
      _clearRemoteSessionSafely(uid).catchError((_) {});
    }
    NotificationService().clearFcmTokenOnSignOut().catchError((_) {});

    // 4. SharedPreferences üzerindeki tüm kullanıcı kimlik verilerini temizle
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_uid');
      await prefs.remove('saved_city');
      await prefs.remove('name');
      await prefs.remove('onboarded');
      await prefs.remove('avatar_path');
    } catch (_) {}

    // 5. Firebase & Google Auth oturumlarını kapat
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    try {
      await _auth.signOut();
    } catch (_) {}
  }

  Future<void> _clearRemoteSessionSafely(String uid) async {
    try {
      final myDeviceId = await DeviceService().getOrCreateDeviceId();
      final userDoc = await _firestore
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 2));
      if (userDoc.exists) {
        final activeDeviceId = userDoc.data()?['currentDeviceId'] as String?;
        if (activeDeviceId == null || activeDeviceId == myDeviceId) {
          await _firestore.collection('users').doc(uid).update({
            'isAppOpen': false,
            'lastActive': FieldValue.serverTimestamp(),
            'currentDeviceId': FieldValue.delete(),
            'fcmToken': FieldValue.delete(),
          }).timeout(const Duration(seconds: 2));
        }
      }
    } catch (_) {}
  }

  /// Hesabı tamamen sil: Şifre doğrulaması -> Veritabanı ve ilişki temizliği -> Auth kullanıcısı silme
  Future<void> deleteAccount(String password) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Oturum açmış kullanıcı bulunamadı.');
    }

    final email = user.email;
    if (email == null || email.isEmpty) {
      throw Exception('Kullanıcı e-posta adresi bulunamadı.');
    }

    final uid = user.uid;

    // 1. Şifre ile yeniden kimlik doğrula (Firebase reauthenticate)
    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    await user.reauthenticateWithCredential(credential);

    // 2. Firestore verilerini temizle
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get().timeout(const Duration(seconds: 4));
      if (userDoc.exists) {
        final data = userDoc.data();
        final coupleId = data?['coupleId'] as String?;
        final inviteCode = data?['inviteCode'] as String?;

        // Varsa davet kodunu sil
        if (inviteCode != null && inviteCode.isNotEmpty) {
          await _firestore.collection('inviteCodes').doc(inviteCode).delete().timeout(const Duration(seconds: 3));
        }

        // Varsa çift ilişkisini ayrıl/sil
        if (coupleId != null && coupleId.isNotEmpty) {
          try {
            final coupleDoc = await _firestore.collection('couples').doc(coupleId).get().timeout(const Duration(seconds: 4));
            if (coupleDoc.exists) {
              final users = List<String>.from(coupleDoc.data()?['users'] ?? []);
              final partnerUid = users.firstWhere((id) => id != uid, orElse: () => '');
              if (partnerUid.isNotEmpty) {
                // Partneri haberdar et ve partnerin coupleId'sini temizle
                await _firestore.collection('users').doc(partnerUid).update({
                  'coupleId': FieldValue.delete(),
                  'partnerUid': FieldValue.delete(),
                }).timeout(const Duration(seconds: 3));
              }
              // Couple dokümanını sil
              await _firestore.collection('couples').doc(coupleId).delete().timeout(const Duration(seconds: 3));
            }
          } catch (_) {}
        }
      }

      // Kullanıcının kendi users dokümanını sil
      await _firestore.collection('users').doc(uid).delete().timeout(const Duration(seconds: 3));
    } catch (_) {}

    // 3. Cihaz takibini durdur & yerel verileri temizle
    DeviceService().stopTracking();
    try {
      final bgService = FlutterBackgroundService();
      if (await bgService.isRunning()) {
        bgService.invoke('stopService');
      }
    } catch (_) {}
    try {
      await NotificationService().clearFcmTokenOnSignOut();
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}

    // 4. Firebase Authentication'dan kullanıcıyı kalıcı olarak sil
    await user.delete();
  }
}

