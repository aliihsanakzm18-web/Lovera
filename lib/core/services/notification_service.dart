import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../firebase_options.dart';
import 'device_service.dart';
import 'fcm_v1_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}

  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final uid = prefs.getString('saved_uid');
  final myDeviceId = prefs.getString('device_session_id');

  // 0. Oturum kapalıysa hiçbir işlem yapma ve bildirim basma
  if (uid == null || uid.isEmpty) {
    return;
  }

  // 0.1 Eğer hesap başka bir telefona taşındıysa bu cihazda sessiz kal
  try {
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final activeDeviceId = userDoc.data()?['currentDeviceId'] as String?;
    if (activeDeviceId != null && myDeviceId != null && activeDeviceId != myDeviceId) {
      debugPrint('[FCM-BG] Hesap başka cihazda aktif ($activeDeviceId != $myDeviceId), mesaj yoksayıldı.');
      return;
    }
  } catch (_) {}

  // 1. Eğer partner kapalıyken bizden canlı şarj/konum talep ettiyse (ping_request):
  // Cihaz arka planda uyanır, pil ve GPS konumunu okuyup doğrudan Firestore'a günceller!
  if (message.data['type'] == 'ping_request') {
    try {
      int? batteryLevel;
      try {
        batteryLevel = await Battery().batteryLevel;
      } catch (_) {}

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (_) {
        try {
          pos = await Geolocator.getLastKnownPosition();
        } catch (_) {}
      }

      String? city;
      String? weather;
      if (pos != null) {
        city = await DeviceService().getCityForLocation(pos.latitude, pos.longitude);
        weather = await DeviceService().getWeatherForLocation(pos.latitude, pos.longitude);
      }
      city ??= prefs.getString('saved_city');
      if (city != null && city.isNotEmpty) {
        prefs.setString('saved_city', city);
      }

      final Map<String, dynamic> updateData = {};
      if (batteryLevel != null) updateData['batteryLevel'] = batteryLevel;
      if (pos != null) {
        updateData['lat'] = pos.latitude;
        updateData['lng'] = pos.longitude;
      }
      if (weather != null && weather.isNotEmpty) updateData['weather'] = weather;
      if (city != null && city.isNotEmpty) updateData['city'] = city;

      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        updateData,
        SetOptions(merge: true),
      );
      debugPrint('[BG-PING-SUCCESS] Kapalı cihaz uyandı: Pil $batteryLevel, Konum ($pos) kaydedildi!');
    } catch (e) {
      debugPrint('[BG-PING-ERROR] $e');
    }
  }

  // 1.5. Eğer yeni sohbet mesajı bildirimi ulaştıysa mesajı anında iletildi (isDelivered: true - Çift Gri Tik) olarak işaretle!
  if (message.data['type'] == 'chat_message') {
    try {
      final cId = message.data['coupleId'] as String?;
      final mId = message.data['messageId'] as String?;
      if (cId != null && cId.isNotEmpty && mId != null && mId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('couples')
            .doc(cId)
            .collection('messages')
            .doc(mId)
            .update({'isDelivered': true});
        debugPrint('[FCM-DELIVERY-ACK] Mesaj arka planda cihaza ulaştı ve çift tike güncellendi: $mId');
      }
    } catch (e) {
      debugPrint('[FCM-DELIVERY-ACK-ERR] $e');
    }
  }

  // 2. Normal kullanıcı bildirimi gösterimi (sadece gerçek başlığı olan bildirimler)
  if (message.notification == null &&
      message.data.isNotEmpty &&
      message.data['type'] != 'ping_request' &&
      message.data['title'] != null &&
      message.data['title'].toString().trim().isNotEmpty) {
    final title = message.data['title']!.toString();
    final body = message.data['body']?.toString() ?? '';
    await NotificationService().show(
      id: message.messageId.hashCode,
      title: title,
      body: body,
    );
  }
}

/// Dünya standardında FCM Push Bildirim Servisi (Uygulama Kapalıyken de Çalışır)
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _localPlugin = FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  bool _ready = false;

  /// Kullanıcı şu an sohbet ekranında mı kontrolü (sohbetteyken bildirim sesi/penceresi basmamak için)
  bool Function()? isChatScreenActive;

  /// Bildirime tıklandığında sohbet ekranına yönlendirme callback'i
  void Function()? onNotificationTap;

  /// Soğuk başlatmada (Cold start) bildirime tıklandığında uygulamanın doğrudan sohbete geçmesini sağlayan bayrak
  bool hasPendingNotificationTap = false;

  Future<void> init() async {
    if (_ready) return;

    // 1. Yerel bildirim yöneticisini başlat
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );
      await _localPlugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('[NOTIFICATION-TAP] Yerel bildirime tıklandı: ${response.payload}');
          hasPendingNotificationTap = true;
          onNotificationTap?.call();
        },
      );
      await _localPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}

    // Bildirime tıklanarak uygulama kapalıyken veya arka plandayken açıldıysa:
    try {
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('[FCM-OPEN] Bildirime tıklanarak açıldı: ${message.data}');
        if (message.data['type'] == 'meeting_request') return; // Buluşma talebi: sohbete değil, talep penceresine düşer
        hasPendingNotificationTap = true;
        onNotificationTap?.call();
      });

      _fcm.getInitialMessage().then((RemoteMessage? message) {
        if (message != null) {
          debugPrint('[FCM-INITIAL] Uygulama bildirimle başlatıldı: ${message.data}');
          if (message.data['type'] == 'meeting_request') return;
          hasPendingNotificationTap = true;
          onNotificationTap?.call();
        }
      });
    } catch (_) {}

    // 2. FCM İzinleri (iOS & Android 13+)
    try {
      await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Cihazın FCM Token'ını al ve Firestore'a kaydet
      await updateFcmTokenInFirestore();

      // Token yenilendiğinde otomatik güncelle
      _fcm.onTokenRefresh.listen((newToken) {
        _saveTokenToFirestore(newToken);
      });

      // Kullanıcı oturum açtığında veya oturduğunda da token'ı hemen kaydet
      FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null) {
          updateFcmTokenInFirestore();
        }
      });

      // Ön plandayken gelen gerçek kullanıcı bildirimlerini yerel bildirim olarak düşür
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        final prefs = await SharedPreferences.getInstance();
        final uid = prefs.getString('saved_uid') ?? FirebaseAuth.instance.currentUser?.uid;
        final myDeviceId = prefs.getString('device_session_id');
        if (uid == null || uid.isEmpty) return;

        try {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
          final activeDeviceId = userDoc.data()?['currentDeviceId'] as String?;
          if (activeDeviceId != null && myDeviceId != null && activeDeviceId != myDeviceId) {
            return;
          }
        } catch (_) {}

        // Sessiz sistem mesajları (arka plan şarj/konum eşitleme) için ASLA bildirim gösterme!
        if (message.data['type'] == 'ping_request') {
          DeviceService().syncStatusToFirebase();
          return;
        }

        // Eğer kullanıcı şu an zaten sohbet ekranındaysa sohbet bildirimini gösterme (Zaten görüyor!)
        final isChatActive = isChatScreenActive?.call() ?? false;
        if (isChatActive && message.data['type'] == 'chat_message') {
          debugPrint('[NOTIFICATION-MUTE] Kullanıcı sohbette olduğu için bildirim sesi/penceresi bastırıldı.');
          return;
        }

        final notif = message.notification;
        if (notif != null && ((notif.title != null && notif.title!.trim().isNotEmpty) || (notif.body != null && notif.body!.trim().isNotEmpty))) {
          show(
            id: message.messageId.hashCode,
            title: notif.title ?? 'Lovera 💕',
            body: notif.body ?? '',
          );
        } else if (message.data['title'] != null &&
            message.data['title'].toString().trim().isNotEmpty) {
          show(
            id: message.messageId.hashCode,
            title: message.data['title'].toString(),
            body: message.data['body']?.toString() ?? '',
          );
        }
      });
    } catch (e) {
      debugPrint('FCM init error: $e');
    }

    _ready = true;
  }

  /// Aktif FCM tokenını döner
  Future<String?> getFcmToken() async {
    try {
      return await _fcm.getToken().timeout(const Duration(seconds: 10), onTimeout: () => null);
    } catch (e) {
      debugPrint('[FCM] getFcmToken error: $e');
      return null;
    }
  }

  /// Oturum kapatıldığında FCM token'ını iptal eder ve tüm bildirimleri temizler
  Future<void> clearFcmTokenOnSignOut() async {
    try {
      await _fcm.deleteToken().timeout(const Duration(seconds: 4), onTimeout: () => null);
      await _localPlugin.cancelAll();
      _ready = false;
      debugPrint('[FCM] Token silindi ve yerel bildirimler temizlendi.');
    } catch (e) {
      debugPrint('[FCM] clearFcmTokenOnSignOut error: $e');
    }
  }

  /// Cihazın tokenını Firestore profilimize yazar
  Future<void> updateFcmTokenInFirestore() async {
    try {
      String? token = await getFcmToken();
      if (token == null) {
        // İlk seferde Google Play Services hazır değilse 2.5 saniye sonra tekrar dene
        await Future.delayed(const Duration(milliseconds: 2500));
        token = await getFcmToken();
      }
      debugPrint('[FCM] Aldığımız cihaz FCM Token: $token');
      if (token != null) {
        await _saveTokenToFirestore(token);
      }
    } catch (e) {
      debugPrint('[FCM] Token alma hatası: $e');
    }
  }

  Future<void> _saveTokenToFirestore(String token) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final deviceId = await DeviceService().getOrCreateDeviceId();
      final prefs = await SharedPreferences.getInstance();
      final cachedToken = prefs.getString('cached_fcm_token_$uid');
      final cachedDeviceId = prefs.getString('cached_fcm_dev_$uid');

      // Eğer token ve cihaz ID zaten Firebase'e başarıyla yazılmışsa tekrar yazıp kota harcama!
      if (cachedToken == token && cachedDeviceId == deviceId) {
        debugPrint('[FCM] Token ve Cihaz ID zaten güncel, Firestore yazması atlandı.');
        return;
      }

      debugPrint('[FCM] Firestore kullanıcısına token kaydediliyor: $uid');
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fcmToken': token,
        'currentDeviceId': deviceId,
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 4));

      await prefs.setString('cached_fcm_token_$uid', token);
      await prefs.setString('cached_fcm_dev_$uid', deviceId);
      debugPrint('[FCM] Token ve Cihaz ID ($deviceId) Firestore’a başarıyla kaydedildi!');
    } catch (e) {
      debugPrint('[FCM] Token kaydetme hatası (veya zaman aşımı): $e');
    }
  }

  /// Partnerin kapalı olan telefonuna doğrudan Google FCM HTTP v1 üzerinden push bildirimi gönderir
  Future<void> sendPushToPartner({
    required String partnerUid,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    try {
      debugPrint('[FCM-SEND] Partner FCM aranıyor: $partnerUid');
      final prefs = await SharedPreferences.getInstance();
      String? fcmToken = prefs.getString('cached_partner_fcm_token_$partnerUid');

      // 1. Eğer yerelde token önbelleği yoksa Firestore'dan oku
      if (fcmToken == null || fcmToken.isEmpty) {
        try {
          final partnerDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(partnerUid)
              .get()
              .timeout(const Duration(seconds: 4));
          fcmToken = partnerDoc.data()?['fcmToken'] as String?;
          if (fcmToken != null && fcmToken.isNotEmpty) {
            await prefs.setString('cached_partner_fcm_token_$partnerUid', fcmToken);
          }
        } catch (_) {}
      }

      debugPrint('[FCM-SEND] Bulunan partner token: $fcmToken');
      if (fcmToken == null || fcmToken.isEmpty) {
        debugPrint('[FCM-SEND] HATA: Partner FCM token bulunamadı: $partnerUid');
        return;
      }

      // 2. Google FCM HTTP v1 ile kapalı olan telefona anında ulaştır
      final success = await FcmV1Service().sendPushNotification(
        fcmToken: fcmToken,
        title: title,
        body: body,
        data: data,
      );
      debugPrint('[FCM-SEND] FCM v1 Gönderim sonucu: $success');
    } catch (e) {
      debugPrint('[FCM-SEND] sendPushToPartner error: $e');
    }
  }

  /// Kapalı olan partner cihazına sessiz ping atarak arka planda anlık şarj ve konumunu almasını ister
  Future<void> requestPartnerStatusSync(String partnerUid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? fcmToken = prefs.getString('cached_partner_fcm_token_$partnerUid');

      if (fcmToken == null || fcmToken.isEmpty) {
        try {
          final partnerDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(partnerUid)
              .get()
              .timeout(const Duration(seconds: 4));
          fcmToken = partnerDoc.data()?['fcmToken'] as String?;
          if (fcmToken != null && fcmToken.isNotEmpty) {
            await prefs.setString('cached_partner_fcm_token_$partnerUid', fcmToken);
          }
        } catch (_) {}
      }

      if (fcmToken != null && fcmToken.isNotEmpty) {
        await FcmV1Service().sendDataOnlyPush(
          fcmToken: fcmToken,
          data: {'type': 'ping_request'},
        );
      }
    } catch (_) {}
  }

  /// Yerel bildirim gösterici
  Future<void> show({required int id, required String title, required String body}) async {
    if (title.trim().isEmpty && body.trim().isEmpty) return;
    try {
      await _localPlugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'lovera_partner',
            'Partner Mesajları',
            channelDescription: 'Partnerinden gelen mesajlar',
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
        ),
      );
    } catch (_) {}
  }
}
