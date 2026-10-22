import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

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
      await prefs.setString('name', username);
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
    // Not: registerDeviceSession, OnboardingFlow._handleSignedIn içinde
    // sunucudan gerçek profil (coupleId, name vb.) okunduktan hemen sonra çağrılır.
    // Böylece yerel Firestore önbelleğinin eksik veriyle ezilmesi önlenir.
    return cred;
  }

  // Google ile Giriş Yap
  Future<UserCredential?> signInWithGoogle() async {
    try {
      UserCredential cred;
      String? fallbackName;
      String? fallbackEmail;

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // iOS'ta GoogleService-Info.plist içinde CLIENT_ID yoksa yerel SDK çökmesini önlemek için OAuth sağlayıcısını kullan
        final googleProvider = GoogleAuthProvider()
          ..addScope('email')
          ..addScope('profile');
        cred = await _auth.signInWithProvider(googleProvider);
      } else {
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) return null; // Kullanıcı iptal etti
        fallbackName = googleUser.displayName;
        fallbackEmail = googleUser.email;

        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final OAuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        cred = await _auth.signInWithCredential(credential);
      }

      if (cred.user != null) {
        try {
          final docRef = _firestore.collection('users').doc(cred.user!.uid);
          String? existingName;
          try {
            final existingDoc = await docRef
                .get(const GetOptions(source: Source.server))
                .timeout(const Duration(seconds: 4));
            existingName = existingDoc.data()?['name'] as String?;
          } catch (_) {}

          await docRef.set({
            'id': cred.user!.uid,
            'name': (existingName != null && existingName.trim().isNotEmpty)
                ? existingName
                : (cred.user!.displayName ?? fallbackName ?? 'İsimsiz'),
            'email': cred.user!.email ?? fallbackEmail,
            'photoUrl': cred.user!.photoURL,
            'lastLogin': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)).timeout(const Duration(seconds: 4));
        } catch (_) {}
      }

      return cred;
    } catch (e) {
      rethrow;
    }
  }

  // Apple ile Giriş Yap (Guideline 4.8 gereksinimi - hem iOS hem Android destekli)
  Future<UserCredential?> signInWithApple() async {
    try {
      UserCredential cred;
      String? formattedName;
      String? appleEmail;

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // 1. Apple nonce güvenliği için rastgele bir dize üret
        final rawNonce = _generateNonce();
        final nonce = sha256.convert(utf8.encode(rawNonce)).toString();

        // 2. Apple kimlik doğrulama isteğinde bulun
        final appleCredential = await SignInWithApple.getAppleIDCredential(
          scopes: [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
          nonce: nonce,
        );
        appleEmail = appleCredential.email;

        if (appleCredential.givenName != null || appleCredential.familyName != null) {
          final parts = [appleCredential.givenName, appleCredential.familyName]
              .where((p) => p != null && p.isNotEmpty);
          if (parts.isNotEmpty) {
            formattedName = parts.join(' ');
          }
        }

        // 3. Firebase OAuthCredential oluştur
        final OAuthCredential credential = OAuthProvider('apple.com').credential(
          idToken: appleCredential.identityToken,
          rawNonce: rawNonce,
        );

        // 4. Firebase'de oturum aç
        cred = await _auth.signInWithCredential(credential);
      } else {
        // Android'de Firebase OAuth web akışı ile Apple girişi
        final appleProvider = AppleAuthProvider()
          ..addScope('email')
          ..addScope('name');
        cred = await _auth.signInWithProvider(appleProvider);
      }

      if (cred.user != null) {
        try {
          if (formattedName != null && formattedName.isNotEmpty) {
            try {
              await cred.user!.updateDisplayName(formattedName);
            } catch (_) {}
          }

          final docRef = _firestore.collection('users').doc(cred.user!.uid);
          String? existingName;
          try {
            final existingDoc = await docRef
                .get(const GetOptions(source: Source.server))
                .timeout(const Duration(seconds: 4));
            existingName = existingDoc.data()?['name'] as String?;
          } catch (_) {}

          final Map<String, dynamic> userData = {
            'id': cred.user!.uid,
            'email': cred.user!.email ?? appleEmail,
            'lastLogin': FieldValue.serverTimestamp(),
          };
          if (formattedName != null && formattedName.isNotEmpty) {
            userData['name'] = formattedName;
          } else if (existingName != null && existingName.trim().isNotEmpty) {
            userData['name'] = existingName;
          } else if (cred.user!.displayName != null && cred.user!.displayName!.trim().isNotEmpty) {
            userData['name'] = cred.user!.displayName;
          } else {
            // Apple Guideline 4.0: Apple ile giriş sonrasında kullanıcıdan tekrar zorunlu isim istenmemelidir
            userData['name'] = 'Lovera Kullanıcısı';
          }

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('name', userData['name'] as String);

          await docRef.set(
            userData,
            SetOptions(merge: true),
          ).timeout(const Duration(seconds: 4));
        } catch (_) {}
      }

      return cred;
    } catch (e) {
      rethrow;
    }
  }

  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
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

  /// Kullanıcının oturum açma yöntemini döndürür ('password', 'google.com', 'apple.com')
  String getSignInProvider() {
    final user = _auth.currentUser;
    if (user == null || user.providerData.isEmpty) return 'password';
    final providerId = user.providerData.first.providerId;
    return providerId;
  }

  /// Hesabı tamamen sil: Doğrulama (Şifre veya Sosyal Giriş) -> Veritabanı ve ilişki temizliği -> Auth kullanıcısı silme
  Future<void> deleteAccount({String? password}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Oturum açmış kullanıcı bulunamadı.');
    }

    final uid = user.uid;
    final providerId = getSignInProvider();

    // 1. Sağlayıcıya göre yeniden kimlik doğrula (Apple Guideline 5.1.1(v) uyumlu)
    if (providerId == 'password') {
      final email = user.email;
      if (email == null || email.isEmpty) {
        throw Exception('Kullanıcı e-posta adresi bulunamadı.');
      }
      if (password == null || password.isEmpty) {
        throw Exception('Hesabınızı silmek için mevcut şifrenizi girmelisiniz.');
      }
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
    } else if (providerId == 'google.com') {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser != null) {
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final OAuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await user.reauthenticateWithCredential(credential);
      } else {
        throw Exception('Google doğrulaması iptal edildi. Hesap silinmedi.');
      }
    } else if (providerId == 'apple.com') {
      try {
        final rawNonce = _generateNonce();
        final nonce = sha256.convert(utf8.encode(rawNonce)).toString();
        final appleCredential = await SignInWithApple.getAppleIDCredential(
          scopes: [AppleIDAuthorizationScopes.email],
          nonce: nonce,
        );
        final OAuthCredential credential = OAuthProvider('apple.com').credential(
          idToken: appleCredential.identityToken,
          rawNonce: rawNonce,
        );
        await user.reauthenticateWithCredential(credential);
      } catch (e) {
        // Kimlik doğrulanamadıysa hesap silinmez; hata kullanıcıya gösterilir.
        throw Exception('Apple kimlik doğrulaması tamamlanamadı. Hesap silinmedi.');
      }
    }

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
              final cd = coupleDoc.data() ?? <String, dynamic>{};
              final users = <String>{
                ...List<String>.from(cd['users'] ?? const []),
                if (cd['user1'] is String) cd['user1'] as String,
                if (cd['user2'] is String) cd['user2'] as String,
              }.toList();
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

