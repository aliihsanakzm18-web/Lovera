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

  // 1. Eğer partner kapalıyken bizden canlı şarj/konum talep ettiyse (ping_request):
  // Cihaz arka planda uyanır, pil ve GPS konumunu okuyup doğrudan Firestore'a günceller!
  if (message.data['type'] == 'ping_request') {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final uid = prefs.getString('saved_uid') ?? FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
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
        city ??= prefs.getString('saved_city') ?? 'İstanbul';

        final Map<String, dynamic> updateData = {};
        if (batteryLevel != null) updateData['batteryLevel'] = batteryLevel;
        if (pos != null) {
          updateData['lat'] = pos.latitude;
          updateData['lng'] = pos.longitude;
        }
        if (weather != null) updateData['weather'] = weather;
        if (city.isNotEmpty) updateData['city'] = city;

        await FirebaseFirestore.instance.collection('users').doc(uid).set(
          updateData,
          SetOptions(merge: true),
        );
        debugPrint('[BG-PING-SUCCESS] Kapalı cihaz uyandı: Pil $batteryLevel, Konum ($pos) kaydedildi!');
      }
    } catch (e) {
      debugPrint('[BG-PING-ERROR] $e');
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

  Future<void> init() async {
    if (_ready) return;

    // 1. Yerel bildirim yöneticisini başlat
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );
      await _localPlugin.initialize(settings);
      await _localPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
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

      // Ön plandayken gelen gerçek kullanıcı bildirimlerini yerel bildirim olarak düşür
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        // Sessiz sistem mesajları (arka plan şarj/konum eşitleme) için ASLA bildirim gösterme!
        if (message.data['type'] == 'ping_request') {
          DeviceService().syncStatusToFirebase();
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

  /// Cihazın tokenını Firestore profilimize yazar
  Future<void> updateFcmTokenInFirestore() async {
    try {
      final token = await _fcm.getToken();
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
      debugPrint('[FCM] Firestore kullanıcısına token kaydediliyor: $uid');
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'fcmToken': token,
          'fcmUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('[FCM] Token Firestore’a başarıyla kaydedildi!');
      }
    } catch (e) {
      debugPrint('[FCM] Token kaydetme hatası: $e');
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
      // 1. Partnerin FCM Token'ını Firestore'dan oku
      final partnerDoc = await FirebaseFirestore.instance.collection('users').doc(partnerUid).get();
      final fcmToken = partnerDoc.data()?['fcmToken'] as String?;
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
      final partnerDoc = await FirebaseFirestore.instance.collection('users').doc(partnerUid).get();
      final fcmToken = partnerDoc.data()?['fcmToken'] as String?;
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
