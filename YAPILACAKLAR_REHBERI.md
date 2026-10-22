# Lovera - Canlıya Alma, Güvenlik ve Mağaza Yayınlama Rehberi

Bu belge, kod tarafında tamamlanan güvenlik ve uyumluluk geliştirmelerinden sonra projenin **Firebase konsolu**, **Google Play Console** ve **Apple App Store** üzerinde yapılması gereken manuel işlemlerini adım adım içerir. İstediğin zaman bu sırayı takip ederek toplu şekilde tamamlayabilirsin.

---

## 📌 1. Firebase & Güvenlik Kapatmaları

### 1.1. Eski FCM Anahtarını İptal Etmek (Google Cloud Console)
> Kod içerisindeki servis hesabı anahtarı tamamen temizlendi. Ancak eski anahtar geçmişte kaldığı için panelden kapatılması gerekir.
1. [Firebase Console Hizmet Hesapları](https://console.firebase.google.com/project/sevgili-app-fb6f4/settings/serviceaccounts/adminsdk) sayfasına git.
2. Sayfanın altındaki **"Google Cloud Platform konsolunda yönet"** bağlantısına tıkla.
3. `firebase-adminsdk...` ile başlayan servis hesabını seç.
4. Üst menüden **"Anahtarlar" (Keys)** sekmesine geç.
5. Listede yer alan eski anahtarın sağındaki çöp kutusu simgesine basarak **SİL (Delete)**.

### 1.2. Cloud Functions'ı Canlıya Almak (Push Bildirimleri İçin)
> Bildirimlerin istemcide anahtar olmadan güvenli sunucu üzerinden gönderilebilmesi için:
1. Firebase projesini [Blaze Planı](https://console.firebase.google.com/project/sevgili-app-fb6f4/usage/details)na yükselt (Kullandıkça öde - ayda 2 milyon işlem ücretsizdir, limit aşılmadığı sürece ücret çıkmaz).
2. Proje klasöründe terminalden şu komutu çalıştır:
   ```powershell
   firebase.cmd deploy --only functions
   ```

---

## 📌 2. Yasal Belgeler & Gizlilik Sözleşmesi (Store Gereksinimi)

Apple ve Google, uygulamanın içinde gizlilik sözleşmesi olsa dahi web üzerinden herkesin erişebileceği bir URL bağlantısı zorunlu tutar.

1. Projedeki `lib/core/widgets/legal_document_view.dart` dosyasında yer alan **Gizlilik Politikası (Privacy Policy)** metnini kopyala.
2. [Notion](https://www.notion.so) veya [Google Docs](https://docs.google.com) üzerine yapıştır.
3. Sayfayı "Web'de Yayınla / Herkese Açık Paylaş" seçeneğiyle yayınla.
4. Elde ettiğin `https://...` bağlantısını hem **Google Play Console** hem de **App Store Connect** panelindeki "Gizlilik Politikası URL" alanına ekle.

---

## 📌 3. Google Play Store Hazırlığı & Yükleme

### 3.1. Release Keystore Üretmek (İmzalama)
Google Play debug anahtarlı uygulamaları kabul etmez. Kendi bilgisayarında bir kerelik anahtar üret:
```powershell
keytool -genkey -v -keystore c:\Users\aliih\lovera-upload-key.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias lovera -keypass GucluSifreniz123 -storepass GucluSifreniz123
```

### 3.2. `android/key.properties` Dosyasını Oluşturmak
Projenin `android/` klasörü altına `key.properties` adında bir metin dosyası açıp içine şu satırları yaz (bu dosya `.gitignore` korumasındadır, git'e gitmez):
```properties
storePassword=GucluSifreniz123
keyPassword=GucluSifreniz123
keyAlias=lovera
storeFile=C:\\Users\\aliih\\lovera-upload-key.jks
```

### 3.3. Mağaza Paketi Çıkarmak (.aab)
Terminalde proje kök dizininde şu komutu çalıştır:
```powershell
flutter build appbundle --release
```
Oluşan dosya: `build\app\outputs\bundle\release\app-release.aab` dosyasını Google Play Console'a yükleyeceksin.

### 3.4. Play Console Formları (Reddi Önlemek İçin Önemli)
* **Arka Plan Konum İzni:** Play Console'da "Uygulama İçeriği" -> "Konum İzni" formunda uygulamanın sevgililer arasında anlık konum/mesafe paylaşımı yaptığını belirten kısa bir video ve açıklama ekle. (Uygulamaya gerekli "Prominent Disclosure" pop-up'ı kodlandı).
* **Veri Güvenliği (Data Safety):** Konum, e-posta, cihaz kimliği (FCM), pil seviyesi ve kullanıcı fotoğraflarının toplandığını, ancak üçüncü taraflarla paylaşılmadığını beyan et.

---

## 📌 4. Apple App Store Hazırlığı & Yükleme

1. **Apple Developer Hesabı:** [Apple Developer](https://developer.apple.com) üzerinde `com.lovera.app.lovera` Bundle Identifier'ının kayıtlı olduğundan emin ol.
2. **Capabilities:** `Push Notifications`, `Sign in with Apple` ve `Background Modes (Location updates, Remote notifications, Background fetch)` yetkilerinin açık olduğundan emin ol.
3. **App Store Connect:**
   * "Privacy Nutrition Label" formunda konum, fotoğraflar ve kullanıcı kimliğinin uygulama işlevselliği için toplandığını seç.
   * Apple Guideline 1.2 (UGC) gereği uygulamaya eklediğimiz şikayet etme, kullanıcı engelleme ve hesap silme özelliklerini inceleme notlarında (Review Notes) belirt.
4. **Build & Arşiv:** Mac üzerinde Xcode ile `Runner.xcworkspace` açılarak `Product -> Archive` ile App Store Connect'e gönder.
