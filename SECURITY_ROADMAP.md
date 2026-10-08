# Lovera - Güvenlik ve Sertleştirme Yol Haritası (Security & Hardening Backlog)

Bu belge, uygulamanın geliştirme süreci tamamen tamamlandıktan sonra canlıya (Production) geçiş öncesinde uygulanacak güvenlik sıkılaştırma adımlarını içerir.

---

## 1. Firestore Veritabanı Güvenlik Kuralları (`firestore.rules`)
* **Mevcut Durum:** Firestore veritabanı geliştirme aşamasında test modu esnekliğindedir.
* **Gereken İyileştirme:**
  * Zero-Trust (Sıfır Güven) modeline geçilecek.
  * `users/{userId}`: Kullanıcı yalnızca kendi profil belgesine (`request.auth.uid == userId`) yazabilecek.
  * `couples/{coupleId}` ve `messages`: Yalnızca çiftin üyesi olan iki kişi (`request.auth.uid in get(/databases/$(database)/documents/couples/$(coupleId)).data.users`) mesajları ve konumları okuyup yazabilecek.
  * Yabancı kullanıcıların başkalarının mesajlarını veya konumlarını okuması veritabanı çekirdeğinde tamamen engellenecek.

---

## 2. FCM Push Bildirim Servis Hesabı Anahtarının İzolasyonu
* **Mevcut Durum:** `fcm_v1_service.dart` içinde doğrudan HTTP v1 bildirimi için private key bulunuyor.
* **Gereken İyileştirme:**
  * Projede halihazırda hazırlanmış olan `functions/index.js` (Firebase Cloud Functions) aktifleştirilecek.
  * İstemci uygulamasındaki servis hesabı anahtarı kaldırılarak bildirim gönderme yetkisi tamamen sunucu tarafına devredilecek.
  * Tersine mühendislik (Reverse Engineering) ile uygulamanın decompile edilmesi durumunda anahtar sızıntısı riski sıfırlanacak.

---

## 3. Davet Kodu (Brute-Force) Koruması
* **Mevcut Durum:** 6 haneli eşleşme davet kodları rastgele üretiliyor.
* **Gereken İyileştirme:**
  * Eşleşme kodu denemelerine hız sınırı (Rate Limiting) eklenecek (örneğin 5 hatalı denemede 5 dakika bekleme).
  * Rastgele kod taraması yaparak eşleşme denemesi yapılmasının önüne geçilecek.

---

## 4. API & Firebase Servis Kısıtlamaları (Google Cloud Console)
* **Gereken İyileştirme:**
  * Google Maps ve Firebase API anahtarları yalnızca uygulamanın paket adına (`com.lovera.app.lovera`) ve SHA-1 parmak izine kısıtlanacak (API Key Restriction).
