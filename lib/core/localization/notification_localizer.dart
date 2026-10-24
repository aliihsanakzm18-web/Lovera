class NotificationLocalizer {
  static const Map<String, String> _trToEnMap = {
    // Titles
    '🔌 Şarjını Unutma!': '🔌 Don\'t Forget Your Charger!',
    '🔋 Şarj Hatırlatması!': '🔋 Battery Reminder!',
    '🔋 Powerbank Hatırlatması!': '🔋 Power Bank Reminder!',
    '⚠️ Düşük Pil Uyarısı!': '⚠️ Low Battery Warning!',
    '💕 Seni Düşünüyor': '💕 Thinking of You',
    '💖 Seni Düşünüyor!': '💖 Thinking of You!',
    '🥺 Seni Çok Özledim!': '🥺 I Miss You So Much!',
    '👉 Dürtme!': '👉 Poke!',
    '📍 Konum İsteği': '📍 Location Request',
    '💕 Yeni Eşleşme İsteği!': '💕 New Pairing Request!',
    '🗓️ Birliktelik Tarihi Güncellendi': '🗓️ Relationship Date Updated',
    '💔 Eşleşme Sonlandırıldı': '💔 Pairing Ended',
    'Buluşma talebi 💕': 'Meetup request 💕',
    'Buluşma talebi': 'Meetup request',
    'Buluşma kabul edildi 💕': 'Meetup accepted 💕',
    'Oyun Daveti': 'Game Invitation',
    'Oyun Daveti Kabul Edildi 🎉': 'Game Invitation Accepted 🎉',
    'Tavla Daveti 🎲': 'Backgammon Invitation 🎲',
    'Bilardo Daveti 🎱': 'Billiards Invitation 🎱',
    'Satranç Daveti ♟️': 'Chess Invitation ♟️',
    '💕 Özel Not': '💕 Special Note',
    'Partner Mesajları': 'Partner Messages',
    'Partnerin': 'Partner',
    'Yeni bir mesaj gönderdi 💬': 'Sent a new message 💬',
    'Bir fotoğraf gönderdi 📷': 'Sent a photo 📷',
    'Fotoğraf gönderdi 📷': 'Sent a photo 📷',
    'Bir sesli mesaj gönderdi 🎙️': 'Sent a voice message 🎙️',
    'Bir konum paylaştı 📍': 'Shared a location 📍',
    'Ana ekranındaki Lovera Çizim Widget\'ına bak 💕': 'Check the Lovera Drawing Widget on your home screen 💕',
    'Partnerin şu an seni düşünüyor ve sana kalp gönderdi 💕': 'Your partner is thinking of you and sent you a heart 💕',
    '🧣 Hava Soğuk, Sıkı Giyin!': '🧣 Cold Weather, Dress Warm!',
    '☂️ Yanına Şemsiye Al!': '☂️ Take an Umbrella!',
    '💧 Bol Su İçmeyi Unutma!': '💧 Remember to Drink Water!',
  };

  static final Map<String, String> _enToTrMap = {
    for (final entry in _trToEnMap.entries) entry.value: entry.key,
  };

  static final List<({RegExp tr, String enTemplate, RegExp en, String trTemplate})> _patterns = [
    // Dynamic titles
    (
      tr: RegExp(r'^(.+?) Konuma Ulaştı$'),
      enTemplate: r'$1 Arrived at Location',
      en: RegExp(r'^(.+?) Arrived at Location$'),
      trTemplate: r'$1 Konuma Ulaştı',
    ),
    (
      tr: RegExp(r'^(.+?) Konumdan Ayrıldı$'),
      enTemplate: r'$1 Left Location',
      en: RegExp(r'^(.+?) Left Location$'),
      trTemplate: r'$1 Konumdan Ayrıldı',
    ),
    (
      tr: RegExp(r'^🎨 (.+?) sana bir çizim gönderdi!$'),
      enTemplate: r'🎨 $1 sent you a drawing!',
      en: RegExp(r'^🎨 (.+?) sent you a drawing!$'),
      trTemplate: r'🎨 $1 sana bir çizim gönderdi!',
    ),

    // Dynamic bodies
    (
      tr: RegExp(r'^(.+?) şarj aletini yanına almanı hatırlatıyor 🔌💕$'),
      enTemplate: r'$1 reminds you to take your charger 🔌💕',
      en: RegExp(r'^(.+?) reminds you to take your charger 🔌💕$'),
      trTemplate: r'$1 şarj aletini yanına almanı hatırlatıyor 🔌💕',
    ),
    (
      tr: RegExp(r'^(.+?) şarjını doldurmanı hatırlatıyor 💕$'),
      enTemplate: r'$1 reminds you to charge your phone 💕',
      en: RegExp(r'^(.+?) reminds you to charge your phone 💕$'),
      trTemplate: r'$1 şarjını doldurmanı hatırlatıyor 💕',
    ),
    (
      tr: RegExp(r"^(.+?) powerbank'ini yanına almanı hatırlatıyor 🔋⚡$"),
      enTemplate: r'$1 reminds you to take your power bank 🔋⚡',
      en: RegExp(r"^(.+?) reminds you to take your power bank 🔋⚡$"),
      trTemplate: r"$1 powerbank'ini yanına almanı hatırlatıyor 🔋⚡",
    ),
    (
      tr: RegExp(r'^(.+?) cihazının şarjı %(\d+) seviyesine indi\.$'),
      enTemplate: r"$1's battery dropped to $2%.",
      en: RegExp(r"^(.+?)'s battery dropped to (\d+)%\.$"),
      trTemplate: r'$1 cihazının şarjı %$2 seviyesine indi.',
    ),
    (
      tr: RegExp(r'^(.+?) sana bir kalp gönderdi!$'),
      enTemplate: r'$1 sent you a heart!',
      en: RegExp(r'^(.+?) sent you a heart!$'),
      trTemplate: r'$1 sana bir kalp gönderdi!',
    ),
    (
      tr: RegExp(r'^(.+?) şu an seni çok özlediğini hissettirdi 💕$'),
      enTemplate: r'$1 just sent you lots of love 💕',
      en: RegExp(r'^(.+?) just sent you lots of love 💕$'),
      trTemplate: r'$1 şu an seni çok özlediğini hissettirdi 💕',
    ),
    (
      tr: RegExp(r'^(.+?) seni dürttü! Hey, oradasın değil mi\? 😊$'),
      enTemplate: r'$1 poked you! Hey, you there? 😊',
      en: RegExp(r'^(.+?) poked you! Hey, you there\? 😊$'),
      trTemplate: r'$1 seni dürttü! Hey, oradasın değil mi? 😊',
    ),
    (
      tr: RegExp(r'^(.+?) anlık konumunu görmek istiyor$'),
      enTemplate: r'$1 wants to see your live location',
      en: RegExp(r'^(.+?) wants to see your live location$'),
      trTemplate: r'$1 anlık konumunu görmek istiyor',
    ),
    (
      tr: RegExp(r'^(.+?) "(.+?)" konumuna vardı\. 💕$'),
      enTemplate: r'$1 arrived at "$2". 💕',
      en: RegExp(r'^(.+?) arrived at "(.+?)"\. 💕$'),
      trTemplate: r'$1 "$2" konumuna vardı. 💕',
    ),
    (
      tr: RegExp(r'^(.+?) "(.+?)" konumundan ayrıldı\.$'),
      enTemplate: r'$1 left "$2".',
      en: RegExp(r'^(.+?) left "(.+?)"\.$'),
      trTemplate: r'$1 "$2" konumundan ayrıldı.',
    ),
    (
      tr: RegExp(r'^(.+?) seninle eşleşmek istiyor! Bağlantıyı onaylamak için dokun\.$'),
      enTemplate: r'$1 wants to pair with you! Tap to confirm connection.',
      en: RegExp(r'^(.+?) wants to pair with you! Tap to confirm connection\.$'),
      trTemplate: r'$1 seninle eşleşmek istiyor! Bağlantıyı onaylamak için dokun.',
    ),
    (
      tr: RegExp(r'^(.+?) birliktelik başlangıç tarihinizi (.+?) olarak güncelledi 💕$'),
      enTemplate: r'$1 updated your relationship start date to $2 💕',
      en: RegExp(r'^(.+?) updated your relationship start date to (.+?) 💕$'),
      trTemplate: r'$1 birliktelik başlangıç tarihinizi $2 olarak güncelledi 💕',
    ),
    (
      tr: RegExp(r'^(.+?) seninle olan eşleşmeyi sonlandırdı\.$'),
      enTemplate: r'$1 ended the pairing with you.',
      en: RegExp(r'^(.+?) ended the pairing with you\.$'),
      trTemplate: r'$1 seninle olan eşleşmeyi sonlandırdı.',
    ),
    (
      tr: RegExp(r'^(.+?) "(.+?)" buluşmasını kabul etti!$'),
      enTemplate: r'$1 accepted the "$2" meetup!',
      en: RegExp(r'^(.+?) accepted the "(.+?)" meetup!$'),
      trTemplate: r'$1 "$2" buluşmasını kabul etti!',
    ),
    (
      tr: RegExp(r'^(.+?) bu sefer buluşamayacağını söyledi\.$'),
      enTemplate: r"$1 said they can't make it this time.",
      en: RegExp(r"^(.+?) said they can't make it this time\.$"),
      trTemplate: r'$1 bu sefer buluşamayacağını söyledi.',
    ),
    (
      tr: RegExp(r'^(.+?) (.+?) davetini kabul etti! Hazırlan\.\.\.$'),
      enTemplate: r'$1 accepted the $2 invitation! Get ready...',
      en: RegExp(r'^(.+?) accepted the (.+?) invitation! Get ready\.\.\.$'),
      trTemplate: r'$1 $2 davetini kabul etti! Hazırlan...',
    ),
    (
      tr: RegExp(r'^(.+?) davetini reddetti\.$'),
      enTemplate: r'$1 declined your invitation.',
      en: RegExp(r'^(.+?) declined your invitation\.$'),
      trTemplate: r'$1 davetini reddetti.',
    ),
    (
      tr: RegExp(r'^(.+?) seninle tavla oynamak istiyor!$'),
      enTemplate: r'$1 wants to play backgammon with you!',
      en: RegExp(r'^(.+?) wants to play backgammon with you!$'),
      trTemplate: r'$1 seninle tavla oynamak istiyor!',
    ),
    (
      tr: RegExp(r'^(.+?) seninle 8 Top Bilardo oynamak istiyor!$'),
      enTemplate: r'$1 wants to play 8 Ball Billiards with you!',
      en: RegExp(r'^(.+?) wants to play 8 Ball Billiards with you!$'),
      trTemplate: r'$1 seninle 8 Top Bilardo oynamak istiyor!',
    ),
    (
      tr: RegExp(r'^(.+?) seninle satranç oynamak istiyor!$'),
      enTemplate: r'$1 wants to play chess with you!',
      en: RegExp(r'^(.+?) wants to play chess with you!$'),
      trTemplate: r'$1 seninle satranç oynamak istiyor!',
    ),
    (
      tr: RegExp(r'^Albümden bir anı paylaştı 📸: (.+?)$'),
      enTemplate: r'Shared a memory from album 📸: $1',
      en: RegExp(r'^Shared a memory from album 📸: (.+?)$'),
      trTemplate: r'Albümden bir anı paylaştı 📸: $1',
    ),
  ];

  /// Verilen metni İngilizceye çevirir (zaten İngilizce veya eşleşmeyen metinleri korur)
  static String toEn(String? input) {
    if (input == null || input.isEmpty) return '';
    final direct = _trToEnMap[input];
    if (direct != null) return direct;

    for (final p in _patterns) {
      final match = p.tr.firstMatch(input);
      if (match != null) {
        String res = p.enTemplate;
        for (int i = 1; i <= match.groupCount; i++) {
          res = res.replaceAll('\$$i', match.group(i) ?? '');
        }
        return res;
      }
    }
    return input;
  }

  /// Verilen metni Türkçeye çevirir (zaten Türkçe veya eşleşmeyen metinleri korur)
  static String toTr(String? input) {
    if (input == null || input.isEmpty) return '';
    final direct = _enToTrMap[input];
    if (direct != null) return direct;

    for (final p in _patterns) {
      final match = p.en.firstMatch(input);
      if (match != null) {
        String res = p.trTemplate;
        for (int i = 1; i <= match.groupCount; i++) {
          res = res.replaceAll('\$$i', match.group(i) ?? '');
        }
        return res;
      }
    }
    return input;
  }

  /// Hedef dil koduna ('en' veya 'tr') göre metni yerelleştirir
  static String localize(String? input, String targetLang) {
    if (targetLang.toLowerCase() == 'en') {
      return toEn(input);
    } else {
      return toTr(input);
    }
  }
}
