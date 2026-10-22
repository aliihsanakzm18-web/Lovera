import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  tr,
  en,
}

final appLanguageProvider = StateNotifierProvider<AppLanguageNotifier, AppLanguage>((ref) {
  return AppLanguageNotifier();
});

class AppLanguageNotifier extends StateNotifier<AppLanguage> {
  AppLanguageNotifier() : super(AppLanguage.tr) {
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final langCode = prefs.getString('app_language');
      if (langCode == 'en') {
        state = AppLanguage.en;
      } else {
        state = AppLanguage.tr;
      }
    } catch (_) {}
  }

  Future<void> setLanguage(AppLanguage language) async {
    state = language;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_language', language == AppLanguage.en ? 'en' : 'tr');
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
  String get notifMilestoneTitle => isEn ? 'Special Day Reminders' : 'Özel Gün Hatırlatıcıları';
  String get notifMilestoneSub => isEn ? 'Notify when anniversary or birthdays approach' : 'Yıldönümü ve doğum günleri yaklaşınca haber ver';
  String get notifDistanceTitle => isEn ? 'Distance & Proximity' : 'Mesafe ve Yakınlaşma';
  String get notifDistanceSub => isEn ? 'Notify when you and your partner get close' : 'Partnerinizle birbirinize yaklaştığınızda bildir';

  // Privacy BottomSheet
  String get privacySettingsTitle => isEn ? 'Privacy and Security' : 'Gizlilik ve Güvenlik';
  String get privacyLocationTitle => isEn ? 'Live Location Sharing' : 'Canlı Konum Paylaşımı';
  String get privacyLocationSub => isEn ? 'Allow your partner to see your location on the map' : 'Partnerinizin harita üzerinde anlık konumunuzu görmesi';
  String get privacyOnlineTitle => isEn ? 'Show Online Status' : 'Çevrimiçi Durumunu Göster';
  String get privacyOnlineSub => isEn ? 'Last seen and real-time active status' : 'Son görülme ve anlık aktiflik bilgisi';
  String get privacyNotice => isEn ? 'All your data is strictly accessible only to you and your paired partner.' : 'Tüm verileriniz uçtan uca sadece sizin ve eşleştiğiniz partnerinizin erişimine açıktır.';

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
  String get chargeReminderTitle => isEn ? '🔋 Battery Reminder!' : '🔋 Şarj Hatırlatması!';
  String chargeReminderBody(String name) => isEn ? '$name reminds you to charge your phone 💕' : '$name şarjını doldurmanı hatırlatıyor 💕';
  String get takeChargerTitle => isEn ? '🔌 Don\'t Forget Your Charger!' : '🔌 Şarjını Unutma!';
  String takeChargerBody(String name) => isEn ? '$name reminds you to take your charger along 🔌💕' : '$name şarj aletini yanına almanı hatırlatıyor 🔌💕';
  String get weatherColdPrompt => isEn ? 'Dress Warmly Sweetheart ❄️' : 'Hava Soğuk, Sıkı Giyin Birtanem ❄️';
  String get weatherRainPrompt => isEn ? 'Take an Umbrella Darling 🌧️' : 'Yanına Şemsiye Al Aşkım 🌧️';
  String get weatherWaterPrompt => isEn ? 'Stay Hydrated & Drink Water 💧' : 'Güneş Çarpmasın, Bol Su İç 💧';

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

  // Memories
  String get addMemory => isEn ? 'Add Memory 📸' : 'Fotoğraf Ekle 📸';
  String get createAlbum => isEn ? 'New Album 📁' : 'Yeni Klasör Ekle 📁';
  String get noMemoriesYet => isEn ? 'No memories saved yet. Capture and store your precious moments together! 📷' : 'Henüz anı eklenmedi. Birlikte geçirdiğiniz güzel anları burada ölümsüzleştirin! 📷';
  String get selectPhotos => isEn ? 'Select Photos' : 'Fotoğrafları Seç';
  String get albumTitle => isEn ? 'Album Name' : 'Albüm Başlığı';
  String get albumDescription => isEn ? 'Description / Story' : 'Açıklama / Hikaye';
  String get deleteMemoryConfirm => isEn ? 'Are you sure you want to delete this memory?' : 'Bu anıyı silmek istediğinize emin misiniz?';

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
  String get clearCanvas => isEn ? 'Clear' : 'Temizle';
  String get sendToPartner => isEn ? 'Send to Partner 💜' : 'Partnere Gönder 💜';
  String get drawingSent => isEn ? 'Drawing sent to your partner\'s home screen! 💜' : 'Çizimin gönderildi! Partnerinin ana ekranında görünecek 💜';
  String get reportDrawing => isEn ? 'Report Content' : 'Çizimi Şikayet Et';

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
