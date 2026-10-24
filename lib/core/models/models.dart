import '../localization/app_strings.dart';

class AppUser {
  final String id;
  final String name;
  final String? avatarUrl;
  final int? batteryLevel;
  final String? weather; // örn. "Güneşli 24°"
  final double? lat;
  final double? lng;
  final String? city;
  final DateTime? lastActive;
  final String? coupleId;
  final bool? isAppOpen;
  final String? birthDate; // 'YYYY-MM-DD'

  final double? speed; // m/s cinsinden anlık hız (hız * 3.6 = km/s)
  final String? currentPlaceTitle; // Örn. "Evim", "İş Yeri"
  final String? currentPlaceEmoji; // Örn. "🏠", "💼"
  final String? widgetBgUrl; // Hesaba kalıcı kayıtlı widget arka plan görseli (base64)
  final String? language; // 'tr' veya 'en'

  const AppUser({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.batteryLevel,
    this.weather,
    this.city,
    this.lat,
    this.lng,
    this.lastActive,
    this.coupleId,
    this.isAppOpen,
    this.birthDate,
    this.speed,
    this.currentPlaceTitle,
    this.currentPlaceEmoji,
    this.widgetBgUrl,
    this.language,
  });

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        avatarUrl: (j['avatarUrl'] ?? j['avatar_url']) as String?,
        widgetBgUrl: (j['widgetBgUrl'] ?? j['widget_bg_url']) as String?,
        batteryLevel: (j['batteryLevel'] ?? j['battery_level']) as int?,
        weather: j['weather'] as String?,
        city: j['city'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        lastActive: () {
          final raw = j['lastActive'] ?? j['last_active'];
          if (raw == null) return null;
          if (raw is DateTime) return raw;
          if (raw is String) return DateTime.tryParse(raw);
          try {
            return (raw as dynamic).toDate();
          } catch (_) {
            return DateTime.tryParse(raw.toString());
          }
        }(),
        coupleId: (j['coupleId'] ?? j['couple_id']) as String?,
        isAppOpen: (j['isAppOpen'] ?? j['is_app_open']) as bool?,
        birthDate: (j['birthDate'] ?? j['birth_date']) as String?,
        speed: (j['speed'] as num?)?.toDouble(),
        currentPlaceTitle: j['currentPlaceTitle'] as String?,
        currentPlaceEmoji: j['currentPlaceEmoji'] as String?,
        language: j['language'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatar_url': avatarUrl,
        'battery_level': batteryLevel,
        'weather': weather,
        'city': city,
        'lat': lat,
        'lng': lng,
        'last_active': lastActive?.toIso8601String(),
        'couple_id': coupleId,
        'is_app_open': isAppOpen,
        'birth_date': birthDate,
        'speed': speed,
        'currentPlaceTitle': currentPlaceTitle,
        'currentPlaceEmoji': currentPlaceEmoji,
        'widget_bg_url': widgetBgUrl,
        'language': language,
      };
}

class Couple {
  final String id;
  final String user1Id;
  final String? user2Id;
  final String inviteCode; // 6 haneli
  final DateTime? startedAt;

  const Couple({
    required this.id,
    required this.user1Id,
    this.user2Id,
    required this.inviteCode,
    this.startedAt,
  });

  bool get isPaired => user2Id != null;

  factory Couple.fromJson(Map<String, dynamic> j) => Couple(
        id: j['id'] as String,
        user1Id: j['user1_id'] as String,
        user2Id: j['user2_id'] as String?,
        inviteCode: j['invite_code'] as String,
        startedAt: j['started_at'] == null ? null : DateTime.parse(j['started_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user1_id': user1Id,
        'user2_id': user2Id,
        'invite_code': inviteCode,
        'started_at': startedAt?.toIso8601String(),
      };
}

enum MilestoneType { anniversary, birthday, trip, other }

class Milestone {
  final String id;
  final String coupleId;
  final String title;
  final DateTime date;
  final MilestoneType type;
  /// Hatırlatıcı kuralları: gün cinsinden önce (7, 1, 0).
  final List<int> reminderDaysBefore;
  final bool isSystem;

  const Milestone({
    required this.id,
    required this.coupleId,
    required this.title,
    required this.date,
    this.type = MilestoneType.other,
    this.reminderDaysBefore = const [7, 1, 0],
    this.isSystem = false,
  });

  int get daysLeft {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var target = DateTime(now.year, date.month, date.day);
    if (target.isBefore(today)) {
      target = DateTime(now.year + 1, date.month, date.day);
    }
    return target.difference(today).inDays;
  }

  factory Milestone.fromJson(Map<String, dynamic> j) => Milestone(
        id: j['id'] as String,
        coupleId: j['couple_id'] as String? ?? '',
        title: j['title'] as String,
        date: DateTime.parse(j['date']),
        type: MilestoneType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => MilestoneType.other,
        ),
        reminderDaysBefore:
            (j['reminders'] as List?)?.cast<int>() ?? const [7, 1, 0],
        isSystem: (j['is_system'] ?? j['isSystem']) as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'couple_id': coupleId,
        'title': title,
        'date': date.toIso8601String(),
        'type': type.name,
        'reminders': reminderDaysBefore,
        'is_system': isSystem,
      };
}

class Memory {
  final String id;
  final String coupleId;
  final String authorId;
  final String photoUrl;
  final String? locationLabel;
  final String? note;
  final DateTime createdAt;

  const Memory({
    required this.id,
    required this.coupleId,
    required this.authorId,
    required this.photoUrl,
    this.locationLabel,
    this.note,
    required this.createdAt,
  });

  factory Memory.fromJson(Map<String, dynamic> j) => Memory(
        id: j['id'] as String,
        coupleId: j['couple_id'] as String,
        authorId: j['author_id'] as String,
        photoUrl: j['photo_url'] as String,
        locationLabel: j['location_label'] as String?,
        note: j['note'] as String?,
        createdAt: DateTime.parse(j['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'couple_id': coupleId,
        'author_id': authorId,
        'photo_url': photoUrl,
        'location_label': locationLabel,
        'note': note,
        'created_at': createdAt.toIso8601String(),
      };
}

class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final String? mediaBase64;
  final String? type; // 'text', 'image', 'heart'
  final DateTime createdAt;
  final bool isDelivered;
  final bool isRead;
  final String? replyToText;
  final String? replyToSender;
  final double? locationLat;
  final double? locationLng;
  final String? locationTitle;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    this.mediaBase64,
    this.type = 'text',
    required this.createdAt,
    this.isDelivered = false,
    this.isRead = false,
    this.replyToText,
    this.replyToSender,
    this.locationLat,
    this.locationLng,
    this.locationTitle,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json, String docId) {
    DateTime time;
    if (json['createdAt'] != null) {
      if (json['createdAt'] is DateTime) {
        time = json['createdAt'] as DateTime;
      } else if (json['createdAt'] is String) {
        time = DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now();
      } else {
        time = (json['createdAt'] as dynamic).toDate?.call() ?? DateTime.now();
      }
    } else {
      time = DateTime.now();
    }

    final isReadVal = json['isRead'] as bool? ?? false;
    final isDeliveredVal = (json['isDelivered'] as bool? ?? false) || isReadVal;

    return ChatMessage(
      id: docId,
      senderId: json['senderId'] as String? ?? '',
      text: json['text'] as String? ?? '',
      mediaBase64: json['mediaBase64'] as String?,
      type: json['type'] as String? ?? 'text',
      createdAt: time,
      isDelivered: isDeliveredVal,
      isRead: isReadVal,
      replyToText: json['replyToText'] as String?,
      replyToSender: json['replyToSender'] as String?,
      locationLat: (json['locationLat'] as num?)?.toDouble(),
      locationLng: (json['locationLng'] as num?)?.toDouble(),
      locationTitle: json['locationTitle'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'senderId': senderId,
        'text': text,
        'mediaBase64': mediaBase64,
        'type': type,
        'createdAt': createdAt.toIso8601String(),
        'isDelivered': isDelivered,
        'isRead': isRead,
        'replyToText': replyToText,
        'replyToSender': replyToSender,
        'locationLat': locationLat,
        'locationLng': locationLng,
        'locationTitle': locationTitle,
      };
}

/// Haritada Kalıcı Olarak Etiketlenen Özel Konum (Ev, İş, Okul vb.)
class SavedPlace {
  final String id;
  final String title;
  final String category; // 'home', 'work', 'school', 'gym', 'cafe', 'favorite', 'other'
  final String iconEmoji;
  final double lat;
  final double lng;
  final String createdBy;
  final String? createdByName;
  final DateTime createdAt;

  final Map<String, dynamic>? notifications;

  const SavedPlace({
    required this.id,
    required this.title,
    required this.category,
    required this.iconEmoji,
    required this.lat,
    required this.lng,
    required this.createdBy,
    this.createdByName,
    required this.createdAt,
    this.notifications,
  });

  factory SavedPlace.fromJson(Map<String, dynamic> json, String docId) {
    DateTime time;
    if (json['createdAt'] != null) {
      if (json['createdAt'] is DateTime) {
        time = json['createdAt'] as DateTime;
      } else if (json['createdAt'] is String) {
        time = DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now();
      } else {
        time = (json['createdAt'] as dynamic).toDate?.call() ?? DateTime.now();
      }
    } else {
      time = DateTime.now();
    }

    return SavedPlace(
      id: docId,
      title: json['title'] as String? ?? loc('Özel Konum', 'Custom Location'),
      category: json['category'] as String? ?? 'favorite',
      iconEmoji: json['iconEmoji'] as String? ?? '📍',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      createdBy: json['createdBy'] as String? ?? '',
      createdByName: json['createdByName'] as String?,
      createdAt: time,
      notifications: json['notifications'] != null ? Map<String, dynamic>.from(json['notifications'] as Map) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'category': category,
        'iconEmoji': iconEmoji,
        'lat': lat,
        'lng': lng,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'createdAt': createdAt.toIso8601String(),
        if (notifications != null) 'notifications': notifications,
      };
}

/// Ortak Anı Albümü Modeli
class MemoryItem {
  final String id;
  final String coupleId;
  final String imageUrl; // base64 veya url
  final String caption;
  final String locationTitle;
  final DateTime date;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final List<String> likedBy; // Kalp bırakanların UID listesi
  final String? albumId; // Anı Grubu / Klasör ID'si (Eğer bir gruba aitse)
  final String? albumTitle; // Anı Grubu / Klasör Başlığı

  const MemoryItem({
    required this.id,
    required this.coupleId,
    required this.imageUrl,
    required this.caption,
    required this.locationTitle,
    required this.date,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    this.likedBy = const [],
    this.albumId,
    this.albumTitle,
  });

  factory MemoryItem.fromJson(Map<String, dynamic> json, String docId) {
    DateTime parseDate(dynamic val) {
      if (val is DateTime) return val;
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      if (val != null) {
        try {
          return (val as dynamic).toDate?.call() ?? DateTime.now();
        } catch (_) {}
      }
      return DateTime.now();
    }

    return MemoryItem(
      id: docId,
      coupleId: json['coupleId'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      caption: json['caption'] as String? ?? '',
      locationTitle: json['locationTitle'] as String? ?? '',
      date: parseDate(json['date']),
      createdBy: json['createdBy'] as String? ?? '',
      createdByName: json['createdByName'] as String? ?? '',
      createdAt: parseDate(json['createdAt']),
      likedBy: (json['likedBy'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      albumId: json['albumId'] as String?,
      albumTitle: json['albumTitle'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'coupleId': coupleId,
        'imageUrl': imageUrl,
        'caption': caption,
        'locationTitle': locationTitle,
        'date': date.toIso8601String(),
        'createdBy': createdBy,
        'createdByName': createdByName,
        'createdAt': createdAt.toIso8601String(),
        'likedBy': likedBy,
        if (albumId != null) 'albumId': albumId,
        if (albumTitle != null) 'albumTitle': albumTitle,
      };
}

/// Anı Grubu / Klasör Modeli
class MemoryAlbum {
  final String id;
  final String coupleId;
  final String title;
  final String description;
  final String locationTitle;
  final DateTime date;
  final String coverImageUrl;
  final int photoCount;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;

  const MemoryAlbum({
    required this.id,
    required this.coupleId,
    required this.title,
    required this.description,
    required this.locationTitle,
    required this.date,
    required this.coverImageUrl,
    this.photoCount = 0,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
  });

  factory MemoryAlbum.fromJson(Map<String, dynamic> json, String docId) {
    DateTime parseDate(dynamic val) {
      if (val is DateTime) return val;
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      if (val != null) {
        try {
          return (val as dynamic).toDate?.call() ?? DateTime.now();
        } catch (_) {}
      }
      return DateTime.now();
    }

    return MemoryAlbum(
      id: docId,
      coupleId: json['coupleId'] as String? ?? '',
      title: json['title'] as String? ?? loc('Anı Grubu', 'Memory Album'),
      description: json['description'] as String? ?? '',
      locationTitle: json['locationTitle'] as String? ?? '',
      date: parseDate(json['date']),
      coverImageUrl: json['coverImageUrl'] as String? ?? '',
      photoCount: (json['photoCount'] as num?)?.toInt() ?? 0,
      createdBy: json['createdBy'] as String? ?? '',
      createdByName: json['createdByName'] as String? ?? '',
      createdAt: parseDate(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'coupleId': coupleId,
        'title': title,
        'description': description,
        'locationTitle': locationTitle,
        'date': date.toIso8601String(),
        'coverImageUrl': coverImageUrl,
        'photoCount': photoCount,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'createdAt': createdAt.toIso8601String(),
      };
}

