import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  tr,
  en,
}

/// Global aktif dil. UI dışı kodda (servisler, bildirimler) da kullanılabilir.
AppLanguage currentAppLanguage = AppLanguage.tr;

/// Global çeviri yardımcısı: seçili dile göre Türkçe veya İngilizce metni döner.
/// Kullanım: Text(loc('Merhaba', 'Hello'))
String loc(String tr, String en) => currentAppLanguage == AppLanguage.en ? en : tr;

/// Kayıtlı mekan başlıklarını (Evim, İş Yeri vb.) seçili dile çevirir.
String localizePlaceTitle(String raw) => AppStrings(currentAppLanguage).translatePlaceTitle(raw);

/// Verilen isim veya soyad içeren tam adı soyadı ayıklayarak yalnızca ön isim(ler)i döner.
/// Örnek: "Eda Nur Doğanoğlu" -> "Eda Nur"
/// "Ali İhsan Aküzüm" -> "Ali İhsan"
/// "Aliihsan" -> "Aliihsan"
String formatFirstNameOnly(String rawName) {
  final clean = rawName.trim();
  if (clean.isEmpty) return '';
  if (!clean.contains(' ')) return clean;
  final parts = clean.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.length <= 1) return clean;
  // Birden fazla isim varsa son parçayı (soyadını) at, geri kalanını birleştir
  return parts.length > 2
      ? parts.sublist(0, parts.length - 1).join(' ')
      : parts.first;
}

/// Arka plan isolate'larında dili SharedPreferences'tan yükler.
Future<void> loadAppLanguageFromPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    currentAppLanguage = prefs.getString('app_language') == 'en' ? AppLanguage.en : AppLanguage.tr;
  } catch (_) {}
}

final appLanguageProvider = StateNotifierProvider<AppLanguageNotifier, AppLanguage>((ref) {
  return AppLanguageNotifier();
});

class AppLanguageNotifier extends StateNotifier<AppLanguage> {
  AppLanguageNotifier() : super(currentAppLanguage) {
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final langCode = prefs.getString('app_language');
      if (langCode == 'en') {
        currentAppLanguage = AppLanguage.en;
        state = AppLanguage.en;
      } else {
        currentAppLanguage = AppLanguage.tr;
        state = AppLanguage.tr;
      }
    } catch (_) {}
  }

  Future<void> setLanguage(AppLanguage language, {bool syncToCloud = true}) async {
    currentAppLanguage = language;
    state = language;
    try {
      final prefs = await SharedPreferences.getInstance();
      final langStr = language == AppLanguage.en ? 'en' : 'tr';
      await prefs.setString('app_language', langStr);
      if (syncToCloud) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          FirebaseFirestore.instance.collection('users').doc(uid).set({
            'language': langStr,
          }, SetOptions(merge: true)).catchError((_) {});
        }
      }
    } catch (_) {}
  }
}

class AppStrings {
  final AppLanguage lang;
  AppStrings(this.lang);

  bool get isEn => lang == AppLanguage.en;

  // General & Common
  String get ok => isEn ? 'OK' : 'Tamam';
  String get cancel => isEn ? 'Cancel' : 'Vazgeç';
  String get save => isEn ? 'Save' : 'Kaydet';
  String get delete => isEn ? 'Delete' : 'Sil';
  String get edit => isEn ? 'Edit' : 'Düzenle';
  String get update => isEn ? 'Update' : 'Güncelle';
  String get create => isEn ? 'Create' : 'Oluştur';
  String get add => isEn ? 'Add' : 'Ekle';
  String get error => isEn ? 'Error' : 'Hata';
  String get retry => isEn ? 'Retry' : 'Tekrar Dene';
  String get success => isEn ? 'Success' : 'Başarılı';
  String get close => isEn ? 'Close' : 'Kapat';
  String get next => isEn ? 'Next' : 'Devam Et';
  String get continueBtn => isEn ? 'Continue' : 'Devam Et';
  String get start => isEn ? 'Get Started' : 'Hemen Başla';
  String get send => isEn ? 'Send' : 'Gönder';
  String get accept => isEn ? 'Accept' : 'Kabul Et';
  String get reject => isEn ? 'Decline' : 'Reddet';
  String get later => isEn ? 'Later' : 'Daha Sonra';
  String get notNow => isEn ? 'Not Now' : 'Şimdi değil';
  String get skipForNow => isEn ? 'Skip for Now' : 'Şimdilik Atla';
  String get yes => isEn ? 'Yes' : 'Evet';
  String get no => isEn ? 'No' : 'Hayır';
  String get partner => isEn ? 'Partner' : 'Partnerin';
  String get offlineBanner => isEn ? 'You are not connected to the internet' : 'İnternete bağlı değilsiniz';
  String get justNow => isEn ? 'Just now' : 'Şimdi';
  String agoMinutes(int m) => isEn ? '${m}m ago' : '$m dk önce';
  String agoHours(int h) => isEn ? '${h}h ago' : '$h sa önce';
  String agoDays(int d) => isEn ? '${d}d ago' : '$d gün önce';

  // Navigation Shell
  String get navMap => isEn ? 'Map' : 'Harita';
  String get navHome => isEn ? 'Home' : 'Ana Sayfa';
  String get navChat => isEn ? 'Chat' : 'Sohbet';
  String get navGames => isEn ? 'Games' : 'Oyunlar';
  String get navMemories => isEn ? 'Memories' : 'Anılar';

  // Settings
  String get settingsTitle => isEn ? 'Settings' : 'Ayarlar';
  String get accountInfo => isEn ? 'Account Information' : 'Hesap Bilgileri';
  String get appSection => isEn ? 'APPLICATION' : 'UYGULAMA';
  String get languageOption => isEn ? 'Language' : 'Dil';
  String get languageSubtitle => isEn ? 'Select application language' : 'Uygulama dilini belirleyin';
  String get selectLanguage => isEn ? 'Select Language' : 'Dil Seçimi';
  String get turkish => isEn ? 'Turkish (Türkçe)' : 'Türkçe';
  String get english => isEn ? 'English' : 'İngilizce (English)';
  String get themeAndAppearance => isEn ? 'Appearance & Theme' : 'Görünüm ve Tema';
  String get themeSubtitle => isEn ? 'Customize the application theme' : 'Uygulama temasını tercihinize göre ayarlayın';
  String get themeLight => isEn ? 'Light Mode' : 'Açık Mod';
  String get themeLightSub => isEn ? 'Bright and fresh appearance' : 'Aydınlık ve ferah görünüm';
  String get themeDark => isEn ? 'Dark Mode' : 'Koyu Mod';
  String get themeDarkSub => isEn ? 'Eye-comforting midnight theme' : 'Göz yormayan asil gece teması';
  String get themeSystem => isEn ? 'System Default' : 'Sistem Varsayılanı';
  String get themeSystemSub => isEn ? 'Follows device system appearance' : 'Telefonunuzun ayarlarına göre otomatik değişir';
  String get colorPalettesTitle => isEn ? 'Color Palette Packages' : 'Renk Paketleri';
  String get colorPalettesSubtitle => isEn ? 'Dual-tone harmonious themes tailored for couples' : 'Çiftlere özel uyumlu çift renkli temalar';
  String get widgetSettings => isEn ? 'Widget Settings' : 'Widget Ayarları';
  String get notifications => isEn ? 'Notifications' : 'Bildirimler';
  String get privacySecurity => isEn ? 'Privacy and Security' : 'Gizlilik ve Güvenlik';
  String get termsOfUse => isEn ? 'Terms of Use (EULA)' : 'Kullanım Koşulları (EULA)';
  String get privacyPolicy => isEn ? 'Privacy Policy' : 'Gizlilik Politikası';
  String get aboutLovera => isEn ? 'About Lovera' : 'Lovera Hakkında';
  String get signOut => isEn ? 'Log Out' : 'Oturumu Kapat';
  String get signOutConfirmTitle => isEn ? 'Log Out' : 'Oturumu Kapat';
  String get signOutConfirmDesc => isEn ? 'Are you sure you want to log out of your account?' : 'Hesabınızdan çıkış yapmak istediğinize emin misiniz?';
  String get notLoggedIn => isEn ? 'Not logged in' : 'Giriş yapılmadı';
  String get defaultUser => isEn ? 'Lovera User' : 'Lovera Kullanıcısı';

  // Notifications BottomSheet
  String get notifSettingsTitle => isEn ? 'Notification Settings' : 'Bildirim Ayarları';
  String get notifHeartTitle => isEn ? '“Thinking of You” Hearts' : '“Seni Düşünüyorum” Kalpleri';
  String get notifHeartSub => isEn ? 'Instant vibrating hearts from your partner' : 'Partnerinizden gelen anlık titreşimli kalpler';
  String get notifChatTitle => isEn ? 'Chat & Message Notifications' : 'Sohbet ve Mesaj Bildirimleri';
  String get notifChatSub => isEn ? 'New messages and photos from your partner' : 'Partnerinizden gelen yeni mesajlar ve fotoğraflar';
  String get notifDrawingTitle => isEn ? 'Live Drawings & Notes' : 'Canlı Çizim ve Notlar';
  String get notifDrawingSub => isEn ? 'New drawings sent to your canvas by partner' : 'Partnerinizin tuvalinize gönderdiği yeni çizimler';
  String get notifBatteryTitle => isEn ? 'Battery & Charge Alerts' : 'Düşük Pil ve Şarj Uyarısı';
  String get notifBatterySub => isEn ? 'When partner battery is low or charge reminder is received' : 'Partnerinizin şarjı azaldığında veya şarj hatırlatması geldiğinde';
  String get notifDistanceTitle => isEn ? 'Distance & Proximity' : 'Mesafe ve Yakınlaşma';
  String get notifDistanceSub => isEn ? 'Notify when you and your partner get close' : 'Partnerinizle birbirinize yaklaştığınızda veya mekana varıldığında';
  String get notifMilestoneTitle => isEn ? 'Special Day Reminders' : 'Özel Gün Hatırlatıcıları';
  String get notifMilestoneSub => isEn ? 'Notify when anniversary or birthdays approach' : 'Yıldönümü ve doğum günleri yaklaşınca haber ver';
  String get notifGamesTitle => isEn ? 'Game & Activity Invites' : 'Oyun ve Etkinlik Davetleri';
  String get notifGamesSub => isEn ? 'Backgammon, chess, or couple game invites' : 'Tavla, satranç veya aşk oyunları davetleri';
  String get notifMemoriesTitle => isEn ? 'New Memories & Photos' : 'Yeni Anı ve Fotoğraflar';
  String get notifMemoriesSub => isEn ? 'When a new memory is added to your shared album' : 'Ortak albüme yeni bir anı veya fotoğraf eklendiğinde';

  // Privacy BottomSheet
  String get privacySettingsTitle => isEn ? 'Privacy and Security' : 'Gizlilik ve Güvenlik';
  String get privacyLocationTitle => isEn ? 'Live Location Sharing' : 'Canlı Konum Paylaşımı';
  String get privacyLocationSub => isEn ? 'Allow your partner to see your location on the map' : 'Partnerinizin harita üzerinde anlık konumunuzu görmesi';
  String get privacyOnlineTitle => isEn ? 'Show Online Status' : 'Çevrimiçi Durumunu Göster';
  String get privacyOnlineSub => isEn ? 'Last seen and real-time active status' : 'Son görülme ve anlık aktiflik bilgisi';
  String get privacyBatteryTitle => isEn ? 'Share Battery Level' : 'Pil Seviyesini Paylaş';
  String get privacyBatterySub => isEn ? 'Allow partner and widget to view your battery percentage' : 'Partnerinizin ve masaüstü widget\'ının şarj yüzdenizi görmesi';
  String get privacySpeedTitle => isEn ? 'Share Speed & Movement' : 'Hız ve Hareket Durumunu Paylaş';
  String get privacySpeedSub => isEn ? 'Show your speed and driving/walking activity on the map' : 'Haritada anlık hızınızı ve sürüş/yürüyüş aktivitenizi gösterme';
  String get privacyPlacesTitle => isEn ? 'Share Custom Place Names' : 'Özel Mekan İsimlerini Paylaş';
  String get privacyPlacesSub => isEn ? 'Share saved place tags like Home, Work with your partner' : 'Evim, İş Yeri gibi kayıtlı konum etiketlerini partnerinizle paylaşma';
  String get privacyAppLockTitle => isEn ? 'App Lock (4-Digit PIN)' : 'Uygulama Kilidi (4 Haneli PIN)';
  String get privacyAppLockSub => isEn ? 'Require security PIN when opening or resuming app' : 'Uygulama açılışında ve arka plandan dönüşte güvenlik PIN kodu sorulur';
  String get privacyChangePinTitle => isEn ? 'Change PIN Code' : 'PIN Kodunu Değiştir';
  String get privacyChangePinSub => isEn ? 'Update your current security PIN' : 'Mevcut güvenlik şifrenizi yenileyin';
  String get privacyNotice => isEn ? 'All your data is strictly accessible only to you and your paired partner.' : 'Tüm verileriniz uçtan uca sadece sizin ve eşleştiğiniz partnerinizin erişimine açıktır.';

  // PIN Dialog
  String get enterPin => isEn ? 'Enter PIN Code' : 'PIN Kodunu Girin';
  String get enterNewPin => isEn ? 'Set New 4-Digit PIN' : 'Yeni 4 Haneli PIN Belirleyin';
  String get confirmNewPin => isEn ? 'Confirm New PIN' : 'PIN Kodunu Tekrar Girin';
  String get enterCurrentPin => isEn ? 'Enter Current PIN' : 'Mevcut PIN Kodunuzu Girin';
  String get pinMismatch => isEn ? 'PIN codes do not match!' : 'PIN kodları birbiriyle eşleşmedi!';
  String get pinIncorrect => isEn ? 'Incorrect PIN, please try again!' : 'Hatalı PIN kodu, lütfen tekrar deneyin!';
  String get pinSetSuccess => isEn ? 'App lock enabled successfully! 🔒' : 'Uygulama kilidi başarıyla aktifleştirildi! 🔒';
  String get pinChangedSuccess => isEn ? 'PIN updated successfully! 🔒' : 'PIN kodunuz başarıyla güncellendi! 🔒';
  String get pinDisabledSuccess => isEn ? 'App lock disabled.' : 'Uygulama kilidi kaldırıldı.';

  // About Dialog
  String get aboutVersion => isEn ? 'Version 1.0.0' : 'Sürüm 1.0.0';
  String get aboutDesc => isEn 
      ? 'A calm, intimate, and secure private digital space designed for couples. Crafted with love to make every shared moment unforgettable.' 
      : 'Çiftler için tasarlanmış sakin, samimi ve güvenli özel dijital alanınız. Birlikte geçirilen her anı ölümsüzleştirmek için sevgiyle geliştirildi.';
  String get copyrightNotice => isEn ? '© 2026 Lovera App • All rights reserved.' : '© 2026 Lovera App • Tüm hakları saklıdır.';

  // Account Settings
  String get profilePhotoUpdated => isEn ? 'Profile photo updated!' : 'Profil fotoğrafınız güncellendi!';
  String get profilePhotoError => isEn ? 'Failed to upload photo' : 'Fotoğraf yüklenemedi';
  String get changeUserName => isEn ? 'Change Name' : 'Kullanıcı Adını Değiştir';
  String get enterName => isEn ? 'Enter your name' : 'Adınızı girin';
  String get nameSaved => isEn ? 'Name saved successfully!' : 'Kullanıcı adınız başarıyla kaydedildi!';
  String get birthdayUpdated => isEn ? 'Birthday updated successfully! 🎉' : 'Doğum tarihiniz başarıyla güncellendi! 🎉';
  String get changePassword => isEn ? 'Change Password' : 'Şifre Değiştir';
  String get currentPassword => isEn ? 'Current Password' : 'Mevcut Şifre';
  String get newPassword => isEn ? 'New Password' : 'Yeni Şifre';
  String get newPasswordConfirm => isEn ? 'Confirm New Password' : 'Yeni Şifre (Tekrar)';
  String get passwordMinLength => isEn ? 'Please enter valid passwords (at least 6 characters).' : 'Lütfen geçerli şifreler girin (en az 6 karakter).';
  String get passwordMismatch => isEn ? 'New passwords do not match.' : 'Yeni şifreler birbiriyle eşleşmiyor.';
  String get passwordUpdated => isEn ? 'Password updated successfully!' : 'Şifreniz başarıyla güncellendi!';
  String get wrongPassword => isEn ? 'Current password is incorrect.' : 'Mevcut şifreniz hatalı.';
  String get profilePhoto => isEn ? 'Profile Photo' : 'Profil Fotoğrafı';
  String get tapToChangePhoto => isEn ? 'Tap to change photo' : 'Fotoğrafı değiştirmek için dokunun';
  String get personalInfo => isEn ? 'PERSONAL INFORMATION' : 'KİŞİSEL BİLGİLER';
  String get userNameLabel => isEn ? 'User Name' : 'Kullanıcı Adı';
  String get notSpecified => isEn ? 'Not specified' : 'Belirtilmedi';
  String get birthdayLabel => isEn ? 'Birthday' : 'Doğum Tarihi';
  String get securitySection => isEn ? 'SECURITY' : 'GÜVENLİK';
  String get emailLabel => isEn ? 'Email' : 'E-posta';
  String get passwordLabel => isEn ? 'Password' : 'Şifre';
  String get manageCouple => isEn ? 'Manage Couple & Connection' : 'Eşleşme ve Çift Yönetimi';
  String get coupleSubtitle => isEn ? 'Anniversary, connection code, and options' : 'Yıldönümü, bağlantı kodu ve seçenekler';
  String get deleteAccount => isEn ? 'Delete Account' : 'Hesabı Sil';
  String get deleteAccountWarning => isEn 
      ? 'Deleting your account permanently wipes your connection, memories, chats, and all data. This action cannot be undone!' 
      : 'Hesabınızı silmek eşleşmenizi, anılarınızı, sohbetlerinizi ve tüm verilerinizi kalıcı olarak yok eder. Bu işlem geri alınamaz!';

  // Dashboard
  String greeting(String name) {
    final firstName = formatFirstNameOnly(name);
    return isEn
        ? (firstName.isEmpty ? 'Hello 👋' : 'Hello $firstName 👋')
        : (firstName.isEmpty ? 'Merhaba 👋' : 'Merhaba $firstName 👋');
  }
  String get distanceTogether => isEn ? 'Together' : 'Yan yanasınız';
  String get distanceAway => isEn ? 'away' : 'uzakta';
  String get dayCounter => isEn ? 'days together' : 'gündür birliktesiniz';
  String get daysSingular => isEn ? 'day' : 'gün';
  String get daysPlural => isEn ? 'days' : 'gün';
  String get hours => isEn ? 'hours' : 'saat';
  String get minutes => isEn ? 'minutes' : 'dakika';
  String get seconds => isEn ? 'seconds' : 'saniye';
  String get sendHeart => isEn ? 'Send Heart' : 'Kalp Gönder';
  String get heartSent => isEn ? 'Heart sent to your love! 💕' : 'Sevgiline kalp gönderildi! 💕';
  String get waitingForPartner => isEn ? 'Waiting for partner...' : 'Partner bekleniyor...';
  String get connectPartnerPrompt => isEn ? 'Connect with your partner to start your journey' : 'Yolculuğa başlamak için partnerinizle eşleşin';
  String get pairNow => isEn ? 'Pair Now' : 'Hemen Eşleş';
  String get chargingBattery => isEn ? 'Charging' : 'Şarj Oluyor';
  String get batteryLevel => isEn ? 'Battery' : 'Pil';
  String get weatherUnknown => isEn ? 'Unknown' : 'Bilinmiyor';
  String get lastSeenJustNow => isEn ? 'Active now' : 'Şimdi aktif';
  String get specialDays => isEn ? 'Special Days' : 'Özel Günler';
  String get viewAll => isEn ? 'View All' : 'Tümünü Gör';
  String get addMilestone => isEn ? 'Add Special Day' : 'Özel Gün Ekle';
  String get quickActions => isEn ? 'Quick Actions' : 'Hızlı İşlemler';
  String get drawTogether => isEn ? 'Drawing Canvas' : 'Çizim Tuvali';
  String get liveMap => isEn ? 'Live Map' : 'Canlı Harita';
  String get memoriesAlbum => isEn ? 'Memories & Photos' : 'Anılar & Fotoğraflar';
  String get gamesArcade => isEn ? 'Games & Fun' : 'Oyunlar & Eğlence';

  // Battery BottomSheet
  String batterySheetTitle(String partnerName) => isEn ? "$partnerName's Battery Status" : "$partnerName'in Şarj Durumu";
  String batteryPercentageDesc(int level, String status) => isEn ? "$level% · $status" : "%$level · $status";
  String get batteryAutoUpdateDesc => isEn 
      ? "Your partner's device battery level updates automatically in the background."
      : "Partnerinizin cihaz şarj seviyesi arka planda otomatik olarak güncellenir.";
  String get sendChargeReminderBtn => isEn ? 'Send Charge Reminder ⚡' : 'Şarjını Doldur Hatırlatması Gönder ⚡';
  String get takeChargerBtn => isEn ? 'Take Your Charger 🔌' : 'Şarjını Yanına Al 🔌';
  String get takePowerbankBtn => isEn ? 'Take Your Powerbank 🔋' : "Powerbank'ini Yanına Al 🔋";
  String chargeReminderSentMsg(String partnerName) => isEn 
      ? 'Charge reminder sent to $partnerName! 🔋⚡' 
      : '$partnerName\'in telefonuna "Şarjını Doldur" hatırlatması gönderildi! 🔋⚡';
  String takeChargerSentMsg(String partnerName) => isEn 
      ? 'Take charger reminder sent to $partnerName! 🔌' 
      : '$partnerName\'in telefonuna "Şarjını Yanına Al" hatırlatması gönderildi! 🔌';
  String takePowerbankSentMsg(String partnerName) => isEn 
      ? 'Powerbank reminder sent to $partnerName! 🔋' 
      : '$partnerName\'in telefonuna "Powerbank\'ini Yanına Al" hatırlatması gönderildi! 🔋';

  // Battery Levels Status Texts
  String get batteryFullText => isEn ? 'Fully Charged' : 'Dopdolu';
  String get batterySufficientText => isEn ? 'Sufficient Level' : 'Yeterli Seviyede';
  String get batteryDrainingText => isEn ? 'Getting Low' : 'Azalıyor';
  String get batteryLowText => isEn ? 'Low Battery' : 'Düşük Pil';
  String get batteryCriticalText => isEn ? 'Critical Level!' : 'Kritik Seviyede!';

  // Weather BottomSheet
  String weatherSheetTitle(String partnerName) => isEn ? "$partnerName's Weather" : "$partnerName'in Hava Durumu";
  String get weatherSheetDesc => isEn 
      ? 'Send a sweet caring reminder to your sweetheart based on their weather:' 
      : 'Partnerine hava durumuna özel tatlı bir ilgi ve bakım hatırlatması gönder:';
  String get weatherColdPrompt => isEn ? 'Dress Warmly Sweetheart ❄️' : 'Hava Soğuk, Sıkı Giyin Birtanem ❄️';
  String get weatherRainPrompt => isEn ? 'Take an Umbrella Darling 🌧️' : 'Yanına Şemsiye Al Aşkım 🌧️';
  String get weatherWaterPrompt => isEn ? 'Stay Hydrated & Drink Water 💧' : 'Güneş Çarpmasın, Bol Su İç 💧';
  String weatherNotifSentMsg(String partnerName) => isEn 
      ? 'Notification sent to $partnerName! 💕' 
      : '$partnerName\'in telefonuna bildirim gönderildi! 💕';

  // Weather Condition Names
  String get weatherClear => isEn ? 'Clear' : 'Açık';
  String get weatherSunny => isEn ? 'Sunny' : 'Güneşli';
  String get weatherCloudy => isEn ? 'Cloudy' : 'Bulutlu';
  String get weatherPartlyCloudy => isEn ? 'Partly Cloudy' : 'Parçalı Bulutlu';
  String get weatherRainy => isEn ? 'Rainy' : 'Yağmurlu';
  String get weatherSnowy => isEn ? 'Snowy' : 'Karlı';

  // Chat
  String get typeMessage => isEn ? 'Type a sweet message...' : 'Tatlı bir mesaj yazın...';
  String get sendPhoto => isEn ? 'Photo' : 'Fotoğraf';
  String get sendLocation => isEn ? 'Send Location' : 'Konum Paylaş';
  String get clearChat => isEn ? 'Clear Chat' : 'Sohbeti Temizle';
  String get clearChatConfirm => isEn ? 'Are you sure you want to delete all messages in this conversation?' : 'Bu sohbetteki tüm mesajları silmek istediğinize emin misiniz?';
  String get chatCleared => isEn ? 'Chat cleared successfully 🧹' : 'Sohbet başarıyla temizlendi 🧹';
  String get changeChatBackground => isEn ? 'Change Chat Background' : 'Sohbet Arka Planı';
  String get resetChatBackground => isEn ? 'Reset Background' : 'Varsayılan Arka Plan';
  String get noMessagesYet => isEn ? 'No messages yet. Send a lovely message to your partner! 💕' : 'Henüz mesaj yok. Sevgiline tatlı bir mesaj yaz! 💕';
  String get pairToChat => isEn ? 'You must pair with your partner before chatting.' : 'Mesaj gönderebilmek için önce partnerinizle eşleşmeniz gerekir.';

  // Map
  String get meetUpRequest => isEn ? 'Meeting Request' : 'Buluşma Talebi';
  String get savePlace => isEn ? 'Save Place' : 'Yeri Kaydet';
  String get placeName => isEn ? 'Place Name' : 'Mekan Adı';
  String get meetHerePrompt => isEn ? 'Meet Here' : 'Burada Buluşalım';
  String get partnerLocation => isEn ? 'Partner\'s Location' : 'Partnerinin Konumu';
  String get myLocation => isEn ? 'My Location' : 'Benim Konumum';
  String get meetingPoint => isEn ? 'Meeting Point' : 'Buluşma Noktası';
  String get navigationRoute => isEn ? 'Get Route' : 'Rota Çiz';
  String get copyCoordinates => isEn ? 'Copy Coordinates' : 'Koordinatları Kopyala';
  String get placeSavedSuccess => isEn ? 'Place saved to map permanently! ✨' : 'Mekan haritaya kalıcı olarak eklendi! ✨';
  String get meetRequestSent => isEn ? 'Meeting request sent 💌' : 'Buluşma talebi gönderildi 💌';

  // Memories & Gallery
  String get memoriesTitle => isEn ? 'Shared Memory Album' : 'Ortak Anı Albümü';
  String get allMemoriesTab => isEn ? 'All Memories' : 'Tüm Anılar';
  String get albumsTab => isEn ? 'Memory Groups (Albums)' : 'Anı Grupları (Klasörler)';
  String get addMemoryBtn => isEn ? 'Add Memory' : 'Anı Ekle';
  String get addMemoryDialogTitle => isEn ? 'Add Photo to Album 💕' : 'Albüme Fotoğraf Ekle 💕';
  String get addMemoryDialogDesc => isEn ? 'How would you like to add photos?' : 'Nasıl fotoğraf eklemek istersiniz?';
  String get addPhotoOption => isEn ? 'Add Photo 📸' : 'Fotoğraf Ekle 📸';
  String get addPhotoOptionSub => isEn ? 'Choose one or multiple photos from gallery' : 'Galeriden bir veya birden fazla fotoğraf seçin';
  String get newAlbumOption => isEn ? 'New Album 📁' : 'Yeni Klasör Ekle 📁';
  String get newAlbumOptionSub => isEn ? 'Create a memory album (Name, story, location, date)' : 'Yeni bir anı klasörü oluşturun (İsim, hikaye, mekan, tarih)';
  String get noMemoriesTitle => isEn ? 'No Memories Added Yet' : 'Henüz Bir Anı Eklenmedi';
  String get noMemoriesDesc => isEn 
      ? 'Upload photos you took together individually or in bulk via the "Add Memory" button! ✨'
      : 'Birlikte çekildiğiniz fotoğrafları tekli veya toplu olarak "Anı Ekle" butonundan albümünüze yükleyin! ✨';
  String get noAlbumsTitle => isEn ? 'No Memory Groups Yet' : 'Henüz Bir Anı Grubu Yok';
  String get noAlbumsDesc => isEn 
      ? 'Create a new album now to organize special moments (trips, dates, getaways)! 📁💕'
      : 'Birlikte olduğunuz özel anları (tatil, gezi, buluşma) düzenlemek için hemen yeni bir klasör oluşturun! 📁💕';
  String get newAlbumBtn => isEn ? 'New Album ✨' : 'Yeni Klasör Ekle ✨';
  String get pairForMemories => isEn ? 'You must pair with your partner before adding memories! 💕' : 'Anı eklemek için önce partnerinle eşleşmelisin! 💕';
  String get sendToChatBtn => isEn ? 'Send to Chat' : 'Sohbete At';
  String get sentToChatBtn => isEn ? 'Sent to Chat ✓' : 'Sohbete Atıldı';
  String get downloadBtn => isEn ? 'Download' : 'İndir';
  String get downloadedBtn => isEn ? 'Downloaded ✓' : 'İndirildi ✓';
  String get editMemoryTitle => isEn ? 'Edit Memory Details ✏️' : 'Anı Bilgilerini Düzenle ✏️';
  String get memoryStoryLabel => isEn ? 'Story / Note of this memory 💕' : 'Bu anının hikayesi / notunuz 💕';
  String get memoryLocationLabel => isEn ? 'Location / City (Optional)' : 'Mekan / Şehir (İsteğe bağlı)';
  String get deleteMemoryTitle => isEn ? 'Delete Memory' : 'Anıyı Sil';
  String get deleteMemoryDesc => isEn 
      ? 'This photo will be permanently deleted from your shared album. Are you sure?'
      : 'Bu fotoğraf ortak anı albümünüzden kalıcı olarak silinecek. Emin misiniz?';
  String get memorySavedSuccess => isEn ? 'Memory saved to shared album! 💕📸' : 'Anınız ortak albüme başarıyla kaydedildi! 💕📸';
  String get memoryDeletedMsg => isEn ? 'Memory deleted from album.' : 'Anı albümden silindi.';

  // Milestones
  String get milestonesTitle => isEn ? 'Special Days' : 'Özel Günler';
  String get addMilestoneBtn => isEn ? 'Add Special Day' : 'Yeni gün ekle';
  String get noMilestonesTitle => isEn ? 'No special days yet' : 'Henüz özel gün yok';
  String get noMilestonesDesc => isEn 
      ? 'Add your anniversary, birthday, or first getaway. Automatically saved to cloud.'
      : 'Yıldönümü, doğum günü ya da ilk tatilinizi ekleyin. Firebase bulutuna anında kaydedilir.';
  String get daysLeftTag => isEn ? 'DAYS LEFT' : 'GÜN KALDI';
  String get specialTag => isEn ? 'Special' : 'Özel';
  String get systemMilestoneTooltip => isEn ? 'This special day is fixed and cannot be deleted.' : 'Bu özel gün sabittir, silinemez veya düzenlenemez.';
  String get deleteMilestoneTitle => isEn ? 'Delete Special Day' : 'Özel Günü Sil';
  String deleteMilestoneDesc(String title) => isEn 
      ? 'Are you sure you want to delete "$title"?' 
      : '"$title" özel gününü silmek istediğinize emin misiniz?';
  String get editMilestoneTitle => isEn ? 'Edit Special Day' : 'Özel Günü Düzenle';
  String get newMilestoneTitle => isEn ? 'New Special Day' : 'Yeni Özel Gün';
  String get milestoneTitleLabel => isEn ? 'Title (e.g. Our Anniversary, First Trip)' : 'Başlık (ör: Yıldönümümüz, İlk Tatil)';
  String get milestoneTitleRequired => isEn ? 'Title is required' : 'Başlık zorunludur';
  String get tapToChangeDate => isEn ? 'Tap to change date' : 'Tarihi değiştirmek için dokunun';

  // Milestone default title translation helper
  String translateMilestoneTitle(String rawTitle) {
    if (!isEn) return rawTitle;
    final lower = rawTitle.toLowerCase();
    if (lower.contains('sevgililer günü') || lower.contains('sevgililer gunu')) return 'Valentine\'s Day 💘';
    if (lower.contains('kadınlar günü') || lower.contains('kadinlar gunu')) return 'Women\'s Day 💐';
    if (lower.contains('erkekler günü') || lower.contains('erkekler gunu')) return 'Men\'s Day 👔';
    if (lower.contains('yıldönüm') || lower.contains('yildonum')) return 'Our Anniversary 💕';
    if (lower.contains('doğum günü') || lower.contains('dogum gunu')) {
      return rawTitle.replaceAll('Doğum Günü', 'Birthday').replaceAll('doğum günü', 'Birthday');
    }
    return rawTitle;
  }

  // Saved place title helper (Evim -> Home, İş / Ofis -> Work, etc.)
  String translatePlaceTitle(String raw) {
    if (!isEn) return raw;
    final map = {
      'Evim': 'Home',
      'Ev': 'Home',
      'Aşkımın Evi': 'Partner\'s Home',
      'İş / Ofis': 'Work / Office',
      'İş Yeri': 'Workplace',
      'Ofis': 'Office',
      'Okul': 'School',
      'Kampüs': 'Campus',
      'Spor Salonu': 'Gym',
      'Favori Kafe': 'Favorite Cafe',
      'Özel Yerimiz': 'Our Special Place',
      'Diğer': 'Other',
    };
    return map[raw] ?? raw;
  }

  // Games
  String get gamesTitle => isEn ? 'Couples Arcade' : 'Oyunlar & Eğlence';
  String get chess => isEn ? 'Chess ♟️' : 'Satranç ♟️';
  String get chessDesc => isEn ? 'Challenge your love to a strategic game of chess' : 'Sevgilinle baş başa tatlı bir zeka savaşı';
  String get backgammon => isEn ? 'Backgammon 🎲' : 'Klasik Tavla 🎲';
  String get backgammonDesc => isEn ? 'Roll the dice and enjoy traditional backgammon' : 'Zarları yuvarla, partnerinle tavla keyfi yaşa';
  String get billiards => isEn ? '8-Ball Pool 🎱' : '8 Top Bilardo 🎱';
  String get billiardsDesc => isEn ? 'Smooth 2D pool physics against your sweetheart' : 'Sevgilinle pürüzsüz 2D bilardo heyecanı';
  String get inviteToPlay => isEn ? 'Invite to Play' : 'Oyuna Davet Et';
  String get waitingForGameResponse => isEn ? 'Waiting for partner to accept...' : 'Partnerin kabul etmesi bekleniyor...';
  String get gameOver => isEn ? 'Game Over' : 'Oyun Bitti';
  String get playAgain => isEn ? 'Play Again' : 'Tekrar Oyna';

  // Drawing Canvas
  String get drawingTitle => isEn ? 'Live Drawing Canvas' : 'Canlı Çizim Tuvali';
  String get drawingTip => isEn 
      ? "Your drawing appears instantly on your partner's home screen widget" 
      : "Çizimin partnerinin ana ekran widget'ında anında belirir";
  String get clearCanvas => isEn ? 'Clear' : 'Temizle';
  String get sendToPartnerBtn => isEn ? 'Send to Partner 💜' : 'Partnere Gönder 💜';
  String get sendingToWidget => isEn ? 'Sending to Widget...' : 'Widget\'a Gönderiliyor...';
  String get drawingSentSuccess => isEn 
      ? 'Drawing sent! It will show up on your partner\'s home screen 💜' 
      : 'Çizimin gönderildi! Partnerinin ana ekranında görünecek 💜';
  String get drawSomethingFirst => isEn 
      ? 'Please draw or type something before sending! 🎨' 
      : 'Lütfen göndermeden önce bir şeyler çizin veya yazı ekleyin! 🎨';
  String get pairToDrawWarning => isEn 
      ? 'You must be paired to send drawings 💕' 
      : 'Çizim gönderebilmek için eşleşmiş olmanız gerekir 💕';
  String get reportDrawing => isEn ? 'Report Drawing' : 'Çizimi Şikayet Et';
  String get reportDrawingDesc => isEn 
      ? 'If you believe inappropriate content was shared on the shared canvas, you can report it. Reported content is reviewed within 24 hours.' 
      : 'Ortak çizim alanında uygunsuz bir içerik paylaşıldığını düşünüyorsanız güvenlik ekibimize bildirebilirsiniz. Bildirilen içerikler 24 saat içinde incelenir.';
  String get reportSubmittedMsg => isEn 
      ? 'Your report has been sent to our security team. It will be reviewed within 24 hours.' 
      : 'Şikayetiniz güvenlik ekibimize iletildi. 24 saat içinde incelenecektir.';
  String get addTextTitle => isEn ? 'Add Text' : 'Yazı Ekle';
  String get editTextTitle => isEn ? 'Edit Text' : 'Yazıyı Düzenle';
  String get textHint => isEn ? 'Type your note or message...' : 'Mesajını veya notunu yaz...';

  // Pairing View
  String get pairingTitle => isEn ? 'Pair with Partner' : 'Partnerinle Eşleş';
  String get yourInviteCode => isEn ? 'Your Invitation Code' : 'Senin Davet Kodun';
  String get shareCodeDesc => isEn ? 'Share this 6-digit code with your partner or scan their QR code.' : 'Bu 6 haneli kodu partnerinle paylaş veya onun QR kodunu okut.';
  String get enterPartnerCode => isEn ? 'Enter Partner\'s Code' : 'Partnerinin Kodunu Gir';
  String get pairButton => isEn ? 'Connect & Pair' : 'Eşleş ve Bağlan';
  String get relationshipStartDate => isEn ? 'Relationship Start Date' : 'Birliktelik Başlangıç Tarihi';
  String get pairingSuccess => isEn ? 'You are connected! Welcome to Lovera 💕' : 'Tebrikler, bağlandınız! Lovera\'ya hoş geldiniz 💕';

  // Widget Settings
  String get widgetSettingsTitle => isEn ? 'Home Screen Widget' : 'Ana Ekran Widget Ayarları';
  String get widgetPreview => isEn ? 'Widget Preview' : 'Widget Önizlemesi';
  String get widgetThemeSelection => isEn ? 'Widget Theme' : 'Widget Teması';
  String get widgetCustomPhoto => isEn ? 'Custom Photo Background' : 'Özel Fotoğraf Arka Planı';
  String get widgetCustomPhotoDesc => isEn ? 'Use a special photo of both of you as the widget background' : 'İkinizin özel bir fotoğrafını widget arka planı yapın';
  String get uploadWidgetPhoto => isEn ? 'Upload Photo' : 'Fotoğraf Yükle';
  String get removeWidgetPhoto => isEn ? 'Remove Photo' : 'Fotoğrafı Kaldır';
  String get widgetPhotoUpdated => isEn ? 'Widget photo updated successfully! 💕' : 'Widget fotoğrafın başarıyla güncellendi! 💕';

  // Breakup & Couple Management
  String get coupleManagementTitle => isEn ? 'Couple Settings' : 'Eşleşme Ayarları';
  String get breakupTitle => isEn ? 'Break Connection' : 'Eşleşmeyi Sonlandır';
  String get breakupWarning => isEn 
      ? 'Breaking the pairing will delete all shared counters, milestones, and mutual spaces for both of you. Are you sure?' 
      : 'Eşleşmeyi sonlandırmak sayaç, ortak anılar ve bağlantınızı her iki cihazda da kaldıracaktır. Emin misiniz?';
  String get breakupRequestSent => isEn ? 'Disconnection request sent to partner.' : 'Ayrılma talebi partnerinize iletildi.';
  String get blockUser => isEn ? 'Block Partner' : 'Partneri Engelle';
  String get reportUser => isEn ? 'Report Partner' : 'Partneri Şikayet Et';
}

final stringsProvider = Provider<AppStrings>((ref) {
  final lang = ref.watch(appLanguageProvider);
  return AppStrings(lang);
});
