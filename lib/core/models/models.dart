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
  });

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        name: j['name'] as String,
        avatarUrl: j['avatar_url'] as String?,
        batteryLevel: j['battery_level'] as int?,
        weather: j['weather'] as String?,
        city: j['city'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        lastActive: j['last_active'] == null ? null : DateTime.parse(j['last_active']),
        coupleId: j['couple_id'] as String?,
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

  const Milestone({
    required this.id,
    required this.coupleId,
    required this.title,
    required this.date,
    this.type = MilestoneType.other,
    this.reminderDaysBefore = const [7, 1, 0],
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
        coupleId: j['couple_id'] as String,
        title: j['title'] as String,
        date: DateTime.parse(j['date']),
        type: MilestoneType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => MilestoneType.other,
        ),
        reminderDaysBefore:
            (j['reminders'] as List?)?.cast<int>() ?? const [7, 1, 0],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'couple_id': coupleId,
        'title': title,
        'date': date.toIso8601String(),
        'type': type.name,
        'reminders': reminderDaysBefore,
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
