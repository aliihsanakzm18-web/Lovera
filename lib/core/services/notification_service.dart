import 'dart:convert';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../firebase_options.dart';
import '../models/models.dart';
import 'device_service.dart';
import 'fcm_v1_service.dart';
import 'heartbeat_haptic_service.dart';
import 'widget_sync_service.dart';
import '../localization/app_strings.dart';
import '../localization/notification_localizer.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}
  await loadAppLanguageFromPrefs();

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

      // Widget üzerine mesaj baloncuğu ekle
      final msgBody = message.notification?.body ?? message.data['body']?.toString();
      if (msgBody != null && msgBody.isNotEmpty) {
        final cachedMsgs = prefs.getStringList('widget_unread_messages_cache') ?? [];
        cachedMsgs.add(msgBody);
        await prefs.setStringList('widget_unread_messages_cache', cachedMsgs);
        await WidgetSyncService.syncWidgetMessages(cachedMsgs);
      }
    } catch (e) {
      debugPrint('[FCM-DELIVERY-ACK-ERR] $e');
    }
  }

  // 1.8. Eğer partnerden mekan giriş/çıkış veya durum güncellemesi geldiyse Widget'ı anında senkronize et!
  final msgType = message.data['type'];
  if (msgType == 'place_enter' || msgType == 'place_exit' || msgType == 'status_update') {
    try {
      final partnerUid = message.data['partnerUid'] ?? prefs.getString('saved_partner_uid');
      final latStr = message.data['lat'];
      final lngStr = message.data['lng'];
      final speedStr = message.data['speed'];
      final batteryStr = message.data['batteryLevel'];
      final placeTitle = message.data['currentPlaceTitle'];
      final placeEmoji = message.data['currentPlaceEmoji'];

      // Kayıtlı mekanları ve başlangıç tarihini al
      List<SavedPlace> placesList = [];
      final cachedPlacesJson = prefs.getString('cached_saved_places_json');
      if (cachedPlacesJson != null && cachedPlacesJson.isNotEmpty) {
        try {
          final List decoded = jsonDecode(cachedPlacesJson);
          placesList = decoded.map((e) => SavedPlace.fromJson(Map<String, dynamic>.from(e), e['id']?.toString() ?? '')).toList();
        } catch (_) {}
      }

      final savedStartDateStr = prefs.getString('saved_start_date');
      final startDate = savedStartDateStr != null ? DateTime.tryParse(savedStartDateStr) : null;

      // Önbellekteki partner verisi
      AppUser? partner;
      final cachedPartnerJson = prefs.getString('cached_partner_json');
      if (cachedPartnerJson != null && cachedPartnerJson.isNotEmpty) {
        try {
          partner = AppUser.fromJson(jsonDecode(cachedPartnerJson));
        } catch (_) {}
      }

      // Yeni gelen konum ve hız verileriyle harmanla
      final double? parsedLat = latStr != null ? double.tryParse(latStr) : partner?.lat;
      final double? parsedLng = lngStr != null ? double.tryParse(lngStr) : partner?.lng;
      final double? parsedSpeed = speedStr != null ? double.tryParse(speedStr) : partner?.speed;
      final int? parsedBattery = batteryStr != null ? int.tryParse(batteryStr) : partner?.batteryLevel;

      final updatedPartner = AppUser(
        id: partnerUid ?? partner?.id ?? '',
        name: partner?.name ?? 'Eda',
        avatarUrl: partner?.avatarUrl,
        batteryLevel: parsedBattery,
        weather: partner?.weather,
        city: partner?.city,
        lat: parsedLat,
        lng: parsedLng,
        lastActive: DateTime.now(),
        coupleId: partner?.coupleId,
        isAppOpen: partner?.isAppOpen,
        birthDate: partner?.birthDate,
        speed: parsedSpeed,
        currentPlaceTitle: placeTitle ?? partner?.currentPlaceTitle,
        currentPlaceEmoji: placeEmoji ?? partner?.currentPlaceEmoji,
        language: partner?.language,
      );

      // Yeni partner halini önbelleğe yaz
      await prefs.setString('cached_partner_json', jsonEncode(updatedPartner.toJson()));

      // Widget'ı derhal güncelle!
      await WidgetSyncService.syncWidget(
        partner: updatedPartner,
        startDate: startDate,
        savedPlaces: placesList,
      );
      debugPrint('[FCM-BG-WIDGET-SYNC] Arka planda partner widget güncellendi: ${updatedPartner.name} -> $placeEmoji $placeTitle (Hız: $parsedSpeed, Pil: $parsedBattery)');
    } catch (e) {
      debugPrint('[FCM-BG-WIDGET-SYNC-ERR] $e');
    }
  }

  // 1.9. Eğer yeni çizim bildirimi ulaştıysa (Uygulama arka planda/tamamen kapalı olsa bile) Çizim Widget'ını derhal güncelle!
  if (msgType == 'drawing_sent') {
    try {
      final cId = message.data['coupleId'] ?? prefs.getString('saved_couple_id');
      final senderName = message.data['senderName'] ?? 'Partnerin';
      final tsStr = message.data['timestamp'];
      final tsMillis = tsStr != null ? int.tryParse(tsStr) : DateTime.now().millisecondsSinceEpoch;

      if (cId != null && cId.isNotEmpty) {
        final doc = await FirebaseFirestore.instance
            .collection('couples')
            .doc(cId)
            .collection('drawings')
            .doc('latest')
            .get();

        if (doc.exists && doc.data() != null) {
          final imageBase64 = doc.data()!['imageBase64'] as String?;
          if (imageBase64 != null && imageBase64.isNotEmpty) {
            final raw = imageBase64.split(',').last;
            final bytes = base64Decode(raw);
            // Standart Android/iOS dosya dizini
            final dir = await getApplicationDocumentsDirectory();
            final drawingPath = '${dir.path}/partner_drawing_latest.png';
            final f = File(drawingPath);
            await f.writeAsBytes(bytes);

            await WidgetSyncService.syncDrawingWidget(
              imagePath: drawingPath,
              imageBase64: imageBase64,
              senderName: senderName,
              timeAgo: loc('Şimdi', 'Just now'),
              timestampMillis: tsMillis,
            );
            debugPrint('[FCM-BG-DRAWING-SYNC] Uygulama kapalıyken yeni çizim widget\'a başarıyla yazıldı: $senderName (base64 dahil)');
          }
        }
      }
    } catch (e) {
      debugPrint('[FCM-BG-DRAWING-SYNC-ERR] $e');
    }
  }



  // 2. Normal kullanıcı bildirimi gösterimi (sadece gerçek başlığı olan bildirimler)
  if (message.notification == null &&
      message.data.isNotEmpty &&
      message.data['type'] != 'ping_request' &&
      ((message.data['title'] != null && message.data['title'].toString().trim().isNotEmpty) ||
       (message.data['title_tr'] != null && message.data['title_tr'].toString().trim().isNotEmpty) ||
       (message.data['title_en'] != null && message.data['title_en'].toString().trim().isNotEmpty))) {
    final isEn = currentAppLanguage == AppLanguage.en;
    final targetLang = isEn ? 'en' : 'tr';
    final rawTitle = (isEn ? message.data['title_en'] : message.data['title_tr'])?.toString() ??
        message.data['title']?.toString() ?? '';
    final rawBody = (isEn ? message.data['body_en'] : message.data['body_tr'])?.toString() ??
        message.data['body']?.toString() ?? '';
    final title = NotificationLocalizer.localize(rawTitle, targetLang);
    final body = NotificationLocalizer.localize(rawBody, targetLang);
    final notifId = NotificationService.getDeterministicNotificationId(
      message.data['type']?.toString(),
      message.messageId,
    );
    await NotificationService().show(
      id: notifId,
      title: title,
      body: body,
      payload: message.data['type']?.toString(),
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

  /// Kullanıcı şu an satranç oyun ekranında mı kontrolü (satrançtayken oyun bildirimi basmamak ve yönlendirmemek için)
  bool Function()? isChessScreenActive;

  /// Bildirime tıklandığında sohbet ekranına yönlendirme callback'i
  void Function()? onNotificationTap;

  /// Doğrudan gelen kalp (özledim) push mesajını UI'da canlandırmak için callback
  void Function(String fromName)? onHeartPingReceived;

  /// Doğrudan gelen şarj hatırlatma push mesajını UI'da canlandırmak için callback
  void Function(String fromName)? onChargePingReceived;

  /// Soğuk başlatmada (Cold start) bildirime tıklandığında uygulamanın doğrudan sohbete geçmesini sağlayan bayrak
  bool hasPendingNotificationTap = false;

  /// Bildirim iznini kontrollü ve tek seferlik istemek için fonksiyon
  Future<bool> requestNotificationPermission() async {
    try {
      final androidPlugin = _localPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final localGranted = await androidPlugin?.requestNotificationsPermission() ?? true;

      final fcmSettings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      final fcmGranted = fcmSettings.authorizationStatus == AuthorizationStatus.authorized ||
          fcmSettings.authorizationStatus == AuthorizationStatus.provisional;

      return localGranted && fcmGranted;
    } catch (e) {
      debugPrint('[NOTIFICATION-PERM-ERR] $e');
      return false;
    }
  }

  Future<void> init({bool requestPermissions = false}) async {
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
          final payload = response.payload;
          if (payload != null &&
              (payload.contains('game_result') ||
                  payload.contains('game_request') ||
                  payload.contains('meeting_request') ||
                  payload.contains('meeting_result') ||
                  payload.contains('pair_request') ||
                  payload.contains('breakup_completed'))) {
            return;
          }
          hasPendingNotificationTap = true;
          onNotificationTap?.call();
        },
      );
      if (requestPermissions) {
        await _localPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }

      // Android için özel Kalp Atışı bildirim kanalını oluştur
      try {
        final androidPlugin = _localPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        if (androidPlugin != null) {
          final heartbeatChannel = AndroidNotificationChannel(
            'lovera_heartbeat',
            loc('Kalp Atışı (Özledim)', 'Heartbeat (Thinking of You)'),
            description: loc('Partnerinin kalp atışı ve özlem bildirimleri', 'Heartbeat and thinking of you alerts from partner'),
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
            vibrationPattern: Int64List.fromList([0, 100, 100, 140, 650, 100, 100, 140]),
          );
          await androidPlugin.createNotificationChannel(heartbeatChannel);
        }
      } catch (_) {}
    } catch (_) {}

    // Bildirime tıklanarak uygulama kapalıyken veya arka plandayken açıldıysa:
    try {
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('[FCM-OPEN] Bildirime tıklanarak açıldı: ${message.data}');
        final type = message.data['type'];
        if (type == 'meeting_request' ||
            type == 'meeting_result' ||
            type == 'game_result' ||
            type == 'game_request' ||
            type == 'pair_request' ||
            type == 'breakup_completed') {
          return;
        }
        hasPendingNotificationTap = true;
        onNotificationTap?.call();
      });

      _fcm.getInitialMessage().then((RemoteMessage? message) {
        if (message != null) {
          debugPrint('[FCM-INITIAL] Uygulama bildirimle başlatıldı: ${message.data}');
          final type = message.data['type'];
          if (type == 'meeting_request' ||
              type == 'meeting_result' ||
              type == 'game_result' ||
              type == 'game_request' ||
              type == 'pair_request' ||
              type == 'breakup_completed') {
            return;
          }
          hasPendingNotificationTap = true;
          onNotificationTap?.call();
        }
      });
    } catch (_) {}

    // 2. FCM İzinleri (iOS & Android 13+)
    try {
      if (requestPermissions) {
      await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      }
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

        // Anlık Kalp (Özledim) push bildirimi geldiyse doğrudan ekranda patlat ve kalp ritminde titret
        if (message.data['type'] == 'heart_ping') {
          HeartbeatHapticService().playHeartbeat(pulses: 3);
          final senderName = message.data['fromName']?.toString() ?? 'Partnerin';
          onHeartPingReceived?.call(senderName);
        }

        // Anlık Şarj hatırlatması push bildirimi geldiyse UI'da göster
        if (message.data['type'] == 'charge_ping') {
          final senderName = message.data['fromName']?.toString() ?? 'Partnerin';
          onChargePingReceived?.call(senderName);
        }



        // Eğer kullanıcı şu an zaten sohbet ekranındaysa sohbet bildirimini gösterme (Zaten görüyor!)
        final isChatActive = isChatScreenActive?.call() ?? false;
        if (isChatActive && message.data['type'] == 'chat_message') {
          debugPrint('[NOTIFICATION-MUTE] Kullanıcı sohbette olduğu için bildirim sesi/penceresi bastırıldı.');
          return;
        }

        // Eğer kullanıcı şu an satranç oyun ekranındaysa oyun bildirimlerini (kabul edildi, davet vs.) gösterme
        final isChessActive = isChessScreenActive?.call() ?? false;
        if (isChessActive && (message.data['type'] == 'game_result' || message.data['type'] == 'game_request')) {
          debugPrint('[NOTIFICATION-MUTE] Kullanıcı zaten satrançta olduğu için oyun bildirimi bastırıldı.');
          return;
        }

        final notif = message.notification;
        final payloadType = message.data['type']?.toString();
        final isEn = currentAppLanguage == AppLanguage.en;
        final targetLang = isEn ? 'en' : 'tr';

        String? rawTitle = (isEn ? message.data['title_en'] : message.data['title_tr'])?.toString();
        rawTitle ??= notif?.title ?? message.data['title']?.toString();

        String? rawBody = (isEn ? message.data['body_en'] : message.data['body_tr'])?.toString();
        rawBody ??= notif?.body ?? message.data['body']?.toString();

        if ((rawTitle != null && rawTitle.trim().isNotEmpty) || (rawBody != null && rawBody.trim().isNotEmpty)) {
          final title = NotificationLocalizer.localize(rawTitle ?? 'Lovera 💕', targetLang);
          final body = NotificationLocalizer.localize(rawBody ?? '', targetLang);
          final notifId = getDeterministicNotificationId(payloadType, message.messageId);
          show(
            id: notifId,
            title: title,
            body: body,
            payload: payloadType,
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

      final currentLang = currentAppLanguage == AppLanguage.en ? 'en' : 'tr';
      final cachedLang = prefs.getString('cached_user_lang_$uid');

      // Eğer token, cihaz ID ve dil zaten Firebase'e başarıyla yazılmışsa tekrar yazıp kota harcama!
      if (cachedToken == token && cachedDeviceId == deviceId && cachedLang == currentLang) {
        debugPrint('[FCM] Token, Cihaz ID ve Dil zaten güncel, Firestore yazması atlandı.');
        return;
      }

      debugPrint('[FCM] Firestore kullanıcısına token kaydediliyor: $uid (Dil: $currentLang)');
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fcmToken': token,
        'currentDeviceId': deviceId,
        'language': currentLang,
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 4));

      await prefs.setString('cached_fcm_token_$uid', token);
      await prefs.setString('cached_fcm_dev_$uid', deviceId);
      await prefs.setString('cached_user_lang_$uid', currentLang);
      debugPrint('[FCM] Token, Cihaz ID ($deviceId) ve Dil ($currentLang) Firestore’a başarıyla kaydedildi!');
    } catch (e) {
      debugPrint('[FCM] Token kaydetme hatası (veya zaman aşımı): $e');
    }
  }

  /// Partnerin telefonuna Google FCM HTTP v1 üzerinden push bildirimi gönderir.
  /// Bildirim metnini partnerin telefon diline ('en' veya 'tr') otomatik uyarlar.
  Future<void> sendPushToPartner({
    required String partnerUid,
    required String title,
    required String body,
    String? titleTr,
    String? titleEn,
    String? bodyTr,
    String? bodyEn,
    Map<String, String>? data,
  }) async {
    try {
      debugPrint('[FCM-SEND] Partner FCM aranıyor: $partnerUid');
      final prefs = await SharedPreferences.getInstance();
      String? fcmToken = prefs.getString('cached_partner_fcm_token_$partnerUid');
      String? partnerLanguage = prefs.getString('cached_partner_language_$partnerUid');

      // 1. Önce yerel bellekteki token ve dile bak, eksikse Firestore'dan çek
      if (fcmToken == null || fcmToken.isEmpty || partnerLanguage == null || partnerLanguage.isEmpty) {
        try {
          final partnerDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(partnerUid)
              .get(const GetOptions(source: Source.serverAndCache))
              .timeout(const Duration(seconds: 5));
          if (partnerDoc.exists && partnerDoc.data() != null) {
            final docData = partnerDoc.data()!;
            final fetchedToken = docData['fcmToken'] as String?;
            if (fetchedToken != null && fetchedToken.isNotEmpty) {
              fcmToken = fetchedToken;
              await prefs.setString('cached_partner_fcm_token_$partnerUid', fcmToken);
            }
            final fetchedLang = docData['language'] as String?;
            if (fetchedLang != null && fetchedLang.isNotEmpty) {
              partnerLanguage = fetchedLang;
              await prefs.setString('cached_partner_language_$partnerUid', partnerLanguage);
            }
          }
        } catch (e) {
          debugPrint('[FCM-SEND] Partner dokümanı okunurken hata oluştu: $e');
        }
      }

      partnerLanguage ??= 'tr'; // Varsayılan Türkçe
      final bool isPartnerEn = partnerLanguage.toLowerCase() == 'en';

      // İki dil için başlık ve gövdeyi belirle
      final effectiveTitleTr = titleTr ?? NotificationLocalizer.toTr(title);
      final effectiveTitleEn = titleEn ?? NotificationLocalizer.toEn(title);
      final effectiveBodyTr = bodyTr ?? NotificationLocalizer.toTr(body);
      final effectiveBodyEn = bodyEn ?? NotificationLocalizer.toEn(body);

      // Partnerin telefon diline göre gönderilecek nihai metin
      final finalTitle = isPartnerEn ? effectiveTitleEn : effectiveTitleTr;
      final finalBody = isPartnerEn ? effectiveBodyEn : effectiveBodyTr;

      debugPrint('[FCM-SEND] Partner dili: $partnerLanguage -> Gönderilen Başlık: "$finalTitle", Gövde: "$finalBody"');

      if (fcmToken == null || fcmToken.isEmpty) {
        debugPrint('[FCM-SEND] HATA: Partner ($partnerUid) kullanıcısının fcmToken alanı boş veya henüz oluşturulmamış!');
        return;
      }

      // Veri yüküne iki dili de ekle
      final extendedData = <String, String>{
        'title_tr': effectiveTitleTr,
        'title_en': effectiveTitleEn,
        'body_tr': effectiveBodyTr,
        'body_en': effectiveBodyEn,
        'title': finalTitle,
        'body': finalBody,
        ...?data,
      };

      // 2. Google FCM HTTP v1 ile kapalı olan telefona anında ulaştır
      final success = await FcmV1Service().sendPushNotification(
        fcmToken: fcmToken,
        title: finalTitle,
        body: finalBody,
        data: extendedData,
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

  static final Map<String, int> _recentNotificationDedup = {};

  static bool isDuplicate(String title, String body, [String? type]) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _recentNotificationDedup.removeWhere((_, time) => now - time > 30000);

    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    final key = '${type ?? ""}_${cleanTitle}_$cleanBody';
    final lastTime = _recentNotificationDedup[key];
    if (lastTime != null && (now - lastTime) < 8000) {
      debugPrint('[NOTIFICATION-DEDUP] Mükerrer bildirim engellendi: "$cleanTitle" - "$cleanBody"');
      return true;
    }
    _recentNotificationDedup[key] = now;
    return false;
  }

  static int getDeterministicNotificationId(String? type, [String? messageId]) {
    switch (type) {
      case 'charge_ping':
      case 'chargePing':
        return 1001;
      case 'heart_ping':
      case 'heartPing':
        return 1002;
      case 'lowBattery':
      case 'low_battery':
        return 1003;
      case 'place_enter':
        return 1004;
      case 'place_exit':
        return 1005;
      case 'drawing_sent':
        return 1006;
      case 'meeting_request':
      case 'meeting_result':
        return 1007;
      case 'game_request':
      case 'game_result':
        return 1008;
      case 'chat_message':
      case 'chatMessage':
        if (messageId != null && messageId.isNotEmpty) {
          return messageId.hashCode;
        }
        return 1010;
      default:
        if (messageId != null && messageId.isNotEmpty) {
          return messageId.hashCode;
        }
        return 1000;
    }
  }

  /// Yerel bildirim gösterici
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (title.trim().isEmpty && body.trim().isEmpty) return;
    if (isDuplicate(title, body, payload)) return;
    try {
      final isHeartPing = payload == 'heart_ping';

      await _localPlugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: isHeartPing
              ? AndroidNotificationDetails(
                  'lovera_heartbeat',
                  loc('Kalp Atışı (Özledim)', 'Heartbeat (Thinking of You)'),
                  channelDescription: loc('Partnerinin kalp atışı ve özlem bildirimleri', 'Heartbeat and thinking of you alerts from partner'),
                  importance: Importance.max,
                  priority: Priority.max,
                  playSound: true,
                  enableVibration: true,
                  vibrationPattern: Int64List.fromList([0, 100, 100, 140, 650, 100, 100, 140]),
                  tag: payload,
                )
              : AndroidNotificationDetails(
                  'lovera_partner',
                  loc('Partner Mesajları', 'Partner Messages'),
                  channelDescription: loc('Partnerinden gelen mesajlar', 'Messages from your partner'),
                  importance: Importance.max,
                  priority: Priority.max,
                  playSound: true,
                  enableVibration: true,
                  tag: payload,
                ),
          iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
        ),
        payload: payload,
      );
    } catch (_) {}
  }
}