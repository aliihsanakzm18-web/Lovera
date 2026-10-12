import 'dart:convert';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class FcmV1Service {
  static final FcmV1Service _instance = FcmV1Service._();
  factory FcmV1Service() => _instance;
  FcmV1Service._();

  static const String _projectId = 'sevgili-app-fb6f4';
  static const String _clientEmail =
      'firebase-adminsdk-fbsvc@sevgili-app-fb6f4.iam.gserviceaccount.com';
  static const String _privateKey =
      '-----BEGIN PRIVATE KEY-----\n'
      'MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQCvw8wdkeEaA2TB\n'
      'eUEV0Mc6lkLh9AYYrmZbKAbyP/+4Gl2F68MbxTlTj6cVHURqm8ApPlIQhbBuDypn\n'
      'K+hFrZJUwvuOcxjnqJ63YU+V7zd2g9J3bUZgRVJXagIHWtDLnLo1OncDEtrRNDLo\n'
      'HEmOTj+xjDHZgo0BDd18opqXOiTz0x/yhM7Q3Sbdc4QHL37HMxlQee2Dn7hSrTRO\n'
      '0kAul7Xjn1MtoM50j8aAEx0NxyeqiKHXZodza+WHAHuEK8t5rZ47ztKx/qaKHyb+\n'
      'dncY+vXKIKvYaaYYMeJAXB6wMzoPE8iH8dI69mrp/anxdwOTK8RyW999khuH0tGY\n'
      'EDs/eMSHAgMBAAECggEARAXXU6RXBV3F2zjFrx83U52+sbritx+bvnCty4hoO8R8\n'
      'aG13e6JnDsdcRwgmJ8oyYuPbF8jdoKKe6wHrqTfFF6fEenth6pnwHxF6nxDPGr9m\n'
      'r1CruWtqtCjzMwx7HSoBSMNhNt/PrsJwZzM3ZmszLFARJNhpILzQeMFnadqXXYM1\n'
      'wabT8mHNFBvIj8p9Grw2XEsIv1Cexi3zpfOoFYtxXs+PdNqPU+xDNWdoZqkA/4Oy\n'
      '24c9UhQa1oeg1MA14RlKpTlQLTSCxtY5Z+K/YfZAHT+J+nMhFDgkDVJ/bumQIha7\n'
      'RV2qgOSBdSbrNP3ViLUEtE4Hos1f08/udsoqTfof0QKBgQDk7+UYpiMD1aQA8gWn\n'
      'FKY6lQz9E/l+g9MZOpeXWar8VD1UjP1UFPA79Jwz22fCSmh0wMg5KiMkamEURRBx\n'
      'LlH1xPxGkM2hThF9KnPqffMY5GHmkNL0ug1i4zPon+6/zVALznirH2KkxutIwnLV\n'
      'UOp+PRFnlMt6gZvl/1VdLpO5EQKBgQDEis0THlcWUajB3zrM3sVHvLVc5QUbQLOU\n'
      '4+t3sNS761pm3ciGAElb05by5+Fioo60F+JUrA1pdfFz47eW+19Vp2qy8WsTtGzm\n'
      'moCM86IGvS8XTCZTECPHNT4qnRk7i8jmvJUlz2X8y511/eWrJvZaXby5eghgBZs4\n'
      'GJrhiWDkFwKBgGFf0/6281+3J+mrB1J4iveR3BNsworYQRqS/FVIs1xd7DQhP8La\n'
      'oQ+vTB0WbjyKb4FxWfhOfuIHSUFY2tR5Ei1J2s+c2YmJbhDh1KnhZlupECcEZGXp\n'
      'GLZ90t9X3zG/fxN2f4axc8CIRx0Mb9FheEu3Z8a52A5EQG4EO2fF3tkxAoGAYV93\n'
      'DJLKiKc6WZrUEe4IhWsL25MnfYIHtqtY3HrCWrvWlQIqN6FqttDUh1G0i16IHtd6\n'
      'bYK0PlyNnGHkcivl5pTEOxV6fE+2aGWBbNPDoV0XOI6kqiBj6W0KeKhOeP7fMNmb\n'
      'dxkSqTTjtTJuF+Z8xPaN6sJ35cLBTQB7s2ORmk8CgYBBC4folrcyngmLJdTfuLHx\n'
      'TcLiDweAOqv+/oPC23Us8QRadcfKNGqj+gB1KX2zm1QerSD/BD8OQk9Wb2C8F1fa\n'
      'Vy9pjIpR0QLnLBF1RCbMav4I/1G7FI+QbjlSENot7mVERNEtXWAXW5NxRD3gCBIr\nsNrg5CVPCWM5VrldXLng6A==\n'
      '-----END PRIVATE KEY-----\n';

  String? _cachedToken;
  DateTime? _tokenExpiry;

  /// Google OAuth2 Bearer token üretir (1 saat geçerli, otomatik yenilenir)
  Future<String?> _getAccessToken() async {
    if (_cachedToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
      return _cachedToken;
    }

    try {
      final now = DateTime.now();
      final jwt = JWT(
        {
          'iss': _clientEmail,
          'scope': 'https://www.googleapis.com/auth/firebase.messaging',
          'aud': 'https://oauth2.googleapis.com/token',
          'exp': (now.millisecondsSinceEpoch ~/ 1000) + 3600,
          'iat': now.millisecondsSinceEpoch ~/ 1000,
        },
      );

      final rsaKey = RSAPrivateKey(_privateKey);
      final signedJwt = jwt.sign(rsaKey, algorithm: JWTAlgorithm.RS256);

      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          'assertion': signedJwt,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _cachedToken = data['access_token'];
        final expiresIn = data['expires_in'] as int? ?? 3600;
        _tokenExpiry = now.add(Duration(seconds: expiresIn));
        return _cachedToken;
      } else {
        debugPrint('[FCM-V1] OAuth2 token alınamadı: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[FCM-V1] OAuth2 hatası: $e');
      return null;
    }
  }

  /// Google FCM HTTP v1 REST API üzerinden kapalı olan cihaza anında push bildirimi yollar
  Future<bool> sendPushNotification({
    required String fcmToken,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    try {
      final accessToken = await _getAccessToken();
      if (accessToken == null) {
        debugPrint('[FCM-V1] Erişim jetonu yok, bildirim gönderilemedi.');
        return false;
      }

      final url = Uri.parse(
        'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send',
      );

      final payload = {
        'message': {
          'token': fcmToken,
          'notification': {
            'title': title,
            'body': body,
          },
          'data': {
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
            'title': title,
            'body': body,
            ...?data,
          },
          'android': {
            'priority': 'HIGH',
            'notification': {
              'channel_id': 'lovera_partner',
              'default_sound': true,
              'default_vibrate_timings': true,
              'notification_priority': 'PRIORITY_MAX',
            },
          },
          'apns': {
            'headers': {
              'apns-priority': '10',
              'apns-push-type': 'alert',
            },
            'payload': {
              'aps': {
                'alert': {
                  'title': title,
                  'body': body,
                },
                'sound': 'default',
                'badge': 1,
                'content-available': 1,
              },
            },
          },
        },
      };

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );

      debugPrint('[FCM-V1] Gönderim Yanıtı: ${response.statusCode} -> ${response.body}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[FCM-V1] Gönderim hatası: $e');
      return false;
    }
  }

  /// Kapalı olan cihaza sessiz (kullanıcıyı rahatsız etmeyen) arka plan uyandırma sinyali gönderir.
  /// Cihaz uyanıp son pil ve GPS konumunu Firestore'a eşitler.
  Future<bool> sendDataOnlyPush({
    required String fcmToken,
    required Map<String, String> data,
  }) async {
    try {
      final accessToken = await _getAccessToken();
      if (accessToken == null) return false;

      final url = Uri.parse(
        'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send',
      );

      final payload = {
        'message': {
          'token': fcmToken,
          'data': data,
          'android': {
            'priority': 'HIGH',
          },
          'apns': {
            'headers': {
              'apns-priority': '5',
              'apns-push-type': 'background',
            },
            'payload': {
              'aps': {
                'content-available': 1,
              },
            },
          },
        },
      };

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );

      debugPrint('[FCM-V1-SILENT] Sessiz uyandırma yanıtı: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[FCM-V1-SILENT] Hata: $e');
      return false;
    }
  }
}
