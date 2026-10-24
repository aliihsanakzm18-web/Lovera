import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../theme/app_theme.dart';
import 'lovera_theme_background.dart';

enum LegalDocType { privacyPolicy, termsOfUse }

class LegalDocumentView extends StatelessWidget {
  const LegalDocumentView({
    super.key,
    required this.type,
  });

  final LegalDocType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isPrivacy = type == LegalDocType.privacyPolicy;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isPrivacy ? loc('Gizlilik Politikası', 'Privacy Policy') : loc('Kullanım Koşulları (EULA)', 'Terms of Use (EULA)'),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
      ),
      body: LoveraThemeBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? LoveraColors.darkSurface.withValues(alpha: 0.92) : Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                  ),
                  boxShadow: AppTheme.ambientShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: isPrivacy ? _buildPrivacySections(theme) : _buildTermsSections(theme),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPrivacySections(ThemeData theme) {
    return [
      _header(
        theme,
        loc('Lovera Gizlilik Politikası', 'Lovera Privacy Policy'),
        loc('Son Güncelleme: 20 Ekim 2026', 'Last Updated: October 20, 2026'),
      ),
      _section(
        theme,
        loc('1. Veri Sorumlusu ve Kapsam', '1. Data Controller and Scope'),
        loc(
          'Lovera ("Uygulama"), çiftlerin birbirleriyle güvenli ve özel bir dijital alanda iletişim kurmasını, anılarını saklamasını ve canlı konum paylaşmasını sağlayan bir platformdur. Gizliliğiniz bizim için en üst önceliktir.',
          'Lovera (the "App") is a platform that allows couples to communicate with each other in a secure and private digital space, keep their memories, and share their live location. Your privacy is our highest priority.',
        ),
      ),
      _section(
        theme,
        loc('2. Toplanan Veriler ve Kullanım Amaçları', '2. Data Collected and Purposes of Use'),
        loc(
          '• Hesap Bilgileri: Adınız, e-posta adresiniz ve profil fotoğrafınız; hesabınızın oluşturulması ve partnerinizle eşleşebilmeniz amacıyla toplanır.\n'
          '• Konum Verileri (Ön Plan ve Arka Plan): Açık rızanız ve izniniz doğrultusunda, yalnızca eşleştiğiniz partnerinizle canlı harita üzerinde mesafenizi ve konumunuzu paylaşmak için kullanılır. Konum iznini dilediğiniz zaman cihaz ayarlarından veya uygulama içi Gizlilik ayarlarından kapatabilirsiniz.\n'
          '• Fotoğraflar ve Medya: Kamera veya galeri izninizle yüklediğiniz fotoğraflar ve çizimler yalnızca eşleştiğiniz partnerinizle ortak albümünüzde, sohbet ekranınızda ve ana ekran widget\'ınızda görüntülenir.\n'
          '• Cihaz Durum Bilgisi: Batarya yüzdesi ve yerel hava durumu bilgisi yalnızca eşleştiğiniz partnerinize bilgi vermek amacıyla gösterilir.',
          '• Account Information: Your name, email address, and profile photo are collected to create your account and to enable you to be matched with your partner.\n'
          '• Location Data (Foreground and Background): With your explicit consent and permission, this data is used solely to share your distance and location with your matched partner on the live map. You can turn off location permission at any time from your device settings or from the in-app Privacy settings.\n'
          '• Photos and Media: Photos and drawings you upload with your camera or gallery permission are displayed only to your matched partner in your shared album, your chat screen, and your home screen widget.\n'
          '• Device Status Information: Battery percentage and local weather information are shown solely to inform your matched partner.',
        ),
      ),
      _section(
        theme,
        loc('3. Üçüncü Taraflarla Paylaşım ve Reklam Yasağı', '3. Sharing with Third Parties and Advertising Prohibition'),
        loc(
          'Kişisel verileriniz, konum geçmişiniz, mesajlarınız ve fotoğraflarınız hiçbir koşulda üçüncü taraf veri simsarlarına veya reklam ağlarına satılmaz, kiralanmaz ve ticari takip (tracking) amacıyla kullanılmaz. Veriler Google Firebase güvenli bulut altyapısında şifreli olarak barındırılır.',
          'Your personal data, location history, messages, and photos are never sold or rented to third-party data brokers or advertising networks, and are never used for commercial tracking purposes under any circumstances. Data is stored encrypted on Google Firebase\'s secure cloud infrastructure.',
        ),
      ),
      _section(
        theme,
        loc('4. Veri Saklama Süresi ve Hesap Silme Hakkı (Account Deletion)', '4. Data Retention Period and Right to Account Deletion'),
        loc(
          'Verileriniz hesabınız aktif olduğu sürece saklanır. Uygulama içerisindeki "Ayarlar > Hesap Ayarları > Hesabı Sil" adımlarını takip ederek hesabınızı dilediğiniz an tek tıkla ve kalıcı olarak silebilirsiniz. Hesap silme işlemi onaylandığında tüm profil verileriniz, mesajlarınız, ortak anılarınız ve konum kayıtlarınız sunucularımızdan geri döndürülemez biçimde silinir.',
          'Your data is retained for as long as your account is active. You can permanently delete your account at any time with a single tap by following "Settings > Account Settings > Delete Account" within the app. Once account deletion is confirmed, all of your profile data, messages, shared memories, and location records are irreversibly deleted from our servers.',
        ),
      ),
      _section(
        theme,
        loc('5. İletişim', '5. Contact'),
        loc(
          'Gizlilik politikamız ve kişisel verilerinizle ilgili her türlü soru, talep veya bildirim için bize uygulama içi destek bölümünden veya destek@lovera.app e-posta adresinden ulaşabilirsiniz.',
          'For any questions, requests, or notices regarding our privacy policy and your personal data, you can reach us through the in-app support section or at destek@lovera.app.',
        ),
      ),
    ];
  }

  List<Widget> _buildTermsSections(ThemeData theme) {
    return [
      _header(
        theme,
        loc('Kullanım Koşulları ve Son Kullanıcı Lisans Sözleşmesi (EULA)', 'Terms of Use and End User License Agreement (EULA)'),
        loc('Son Güncelleme: 20 Ekim 2026', 'Last Updated: October 20, 2026'),
      ),
      _section(
        theme,
        loc('1. Koşulların Kabulü', '1. Acceptance of Terms'),
        loc(
          'Lovera uygulamasını indirerek, hesap oluşturarak veya kullanarak işbu Kullanım Koşulları ve Son Kullanıcı Lisans Sözleşmesi (EULA) hükümlerini kabul etmiş sayılırsınız.',
          'By downloading, creating an account on, or using the Lovera app, you are deemed to have accepted the provisions of these Terms of Use and End User License Agreement (EULA).',
        ),
      ),
      _section(
        theme,
        loc('2. Kullanıcı Tarafından Oluşturulan İçerik (UGC) ve Sıfır Tolerans Politikası', '2. User-Generated Content (UGC) and Zero Tolerance Policy'),
        loc(
          'Lovera üzerinden paylaşılan mesajlar, fotoğraflar, konum notları ve çizimler tamamen kullanıcının sorumluluğundadır.\n\n'
          '• SIFIR TOLERANS: Lovera; taciz, zorbalık, tehdit, nefret söylemi, rıza dışı mahrem görsel paylaşımı, müstehcenlik veya yasa dışı herhangi bir içeriğe karşı SIFIR TOLERANS politikası uygular.\n'
          '• Bu tür sakıncalı içerikleri paylaşan veya diğer kullanıcıları rahatsız eden hesaplar bildirim üzerine derhal askıya alınır ve kalıcı olarak kapatılır.',
          'Messages, photos, location notes, and drawings shared through Lovera are entirely the responsibility of the user.\n\n'
          '• ZERO TOLERANCE: Lovera enforces a ZERO TOLERANCE policy against harassment, bullying, threats, hate speech, non-consensual sharing of intimate imagery, obscenity, or any illegal content.\n'
          '• Accounts that share such objectionable content or disturb other users will be immediately suspended and permanently closed upon report.',
        ),
      ),
      _section(
        theme,
        loc('3. Şikayet Etme (Report) ve Kullanıcı Engelleme (Block) Mekanizması', '3. Reporting and User Blocking Mechanism'),
        loc(
          '• Şikayet Etme: Sohbet ekranındaki mesajlara uzun basarak veya Ortak Anı Albümündeki fotoğrafların detay menüsünden "Şikayet Et" butonunu kullanarak uygunsuz içerikleri güvenlik ekibimize bildirebilirsiniz. Tüm şikayetler en geç 24 saat içinde incelenir ve ihlal içeren içerikler derhal kaldırılır.\n'
          '• Kullanıcı Engelleme: Sohbet ekranının sağ üst köşesindeki seçenekler menüsünden "Kullanıcıyı Engelle" seçeneğini kullanarak partnerinizle olan eşleşmeyi, mesajlaşmayı ve konum paylaşımını anında ve tek taraflı olarak sonlandırabilirsiniz. Engellenen kullanıcı sizinle tekrar eşleşme isteği gönderemez.',
          '• Reporting: You can report inappropriate content to our safety team by long-pressing messages on the chat screen or by using the "Report" button in the detail menu of photos in the Shared Memory Album. All reports are reviewed within 24 hours at the latest, and content that violates these terms is removed immediately.\n'
          '• Blocking Users: Using the "Block User" option in the options menu at the top right of the chat screen, you can immediately and unilaterally end the match, messaging, and location sharing with your partner. A blocked user cannot send you a match request again.',
        ),
      ),
      _section(
        theme,
        loc('4. Konum ve Güvenlik Sorumluluğu', '4. Location and Safety Responsibility'),
        loc(
          'Canlı konum paylaşımı özelliği tamamen gönüllülük ve karşılıklı rıza esasına dayanır. Kullanıcılar istedikleri an uygulama içinden veya işletim sistemi ayarlarından konum paylaşımını durdurabilir veya eşleşmeyi sonlandırabilir.',
          'The live location sharing feature is based entirely on voluntariness and mutual consent. Users can stop location sharing or end the match at any time from within the app or from their operating system settings.',
        ),
      ),
      _section(
        theme,
        loc('5. İletişim ve Destek', '5. Contact and Support'),
        loc(
          'Kullanım koşulları, içerik bildirimleri ve teknik destek talepleriniz için destek@lovera.app adresinden 7/24 bizimle iletişime geçebilirsiniz.',
          'For questions about the terms of use, content reports, and technical support requests, you can contact us 24/7 at destek@lovera.app.',
        ),
      ),
    ];
  }


  Widget _header(ThemeData theme, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: LoveraColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _section(ThemeData theme, String heading, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}
