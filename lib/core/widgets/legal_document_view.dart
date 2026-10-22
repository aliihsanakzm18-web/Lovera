import 'package:flutter/material.dart';
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
          isPrivacy ? 'Gizlilik Politikası' : 'Kullanım Koşulları (EULA)',
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
                  color: isDark ? const Color(0xFF161822).withValues(alpha: 0.92) : Colors.white.withValues(alpha: 0.95),
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
      _header(theme, 'Lovera Gizlilik Politikası', 'Son Güncelleme: 20 Ekim 2026'),
      _section(
        theme,
        '1. Veri Sorumlusu ve Kapsam',
        'Lovera ("Uygulama"), çiftlerin birbirleriyle güvenli ve özel bir dijital alanda iletişim kurmasını, anılarını saklamasını ve canlı konum paylaşmasını sağlayan bir platformdur. Gizliliğiniz bizim için en üst önceliktir.',
      ),
      _section(
        theme,
        '2. Toplanan Veriler ve Kullanım Amaçları',
        '• Hesap Bilgileri: Adınız, e-posta adresiniz ve profil fotoğrafınız; hesabınızın oluşturulması ve partnerinizle eşleşebilmeniz amacıyla toplanır.\n'
        '• Konum Verileri (Ön Plan ve Arka Plan): Açık rızanız ve izniniz doğrultusunda, yalnızca eşleştiğiniz partnerinizle canlı harita üzerinde mesafenizi ve konumunuzu paylaşmak için kullanılır. Konum iznini dilediğiniz zaman cihaz ayarlarından veya uygulama içi Gizlilik ayarlarından kapatabilirsiniz.\n'
        '• Fotoğraflar ve Medya: Kamera veya galeri izninizle yüklediğiniz fotoğraflar ve çizimler yalnızca eşleştiğiniz partnerinizle ortak albümünüzde, sohbet ekranınızda ve ana ekran widget\'ınızda görüntülenir.\n'
        '• Cihaz Durum Bilgisi: Batarya yüzdesi ve yerel hava durumu bilgisi yalnızca eşleştiğiniz partnerinize bilgi vermek amacıyla gösterilir.',
      ),
      _section(
        theme,
        '3. Üçüncü Taraflarla Paylaşım ve Reklam Yasağı',
        'Kişisel verileriniz, konum geçmişiniz, mesajlarınız ve fotoğraflarınız hiçbir koşulda üçüncü taraf veri simsarlarına veya reklam ağlarına satılmaz, kiralanmaz ve ticari takip (tracking) amacıyla kullanılmaz. Veriler Google Firebase güvenli bulut altyapısında şifreli olarak barındırılır.',
      ),
      _section(
        theme,
        '4. Veri Saklama Süresi ve Hesap Silme Hakkı (Account Deletion)',
        'Verileriniz hesabınız aktif olduğu sürece saklanır. Uygulama içerisindeki "Ayarlar > Hesap Ayarları > Hesabı Sil" adımlarını takip ederek hesabınızı dilediğiniz an tek tıkla ve kalıcı olarak silebilirsiniz. Hesap silme işlemi onaylandığında tüm profil verileriniz, mesajlarınız, ortak anılarınız ve konum kayıtlarınız sunucularımızdan geri döndürülemez biçimde silinir.',
      ),
      _section(
        theme,
        '5. İletişim',
        'Gizlilik politikamız ve kişisel verilerinizle ilgili her türlü soru, talep veya bildirim için bize uygulama içi destek bölümünden veya destek@lovera.app e-posta adresinden ulaşabilirsiniz.',
      ),
    ];
  }

  List<Widget> _buildTermsSections(ThemeData theme) {
    return [
      _header(theme, 'Kullanım Koşulları ve Son Kullanıcı Lisans Sözleşmesi (EULA)', 'Son Güncelleme: 20 Ekim 2026'),
      _section(
        theme,
        '1. Koşulların Kabulü',
        'Lovera uygulamasını indirerek, hesap oluşturarak veya kullanarak işbu Kullanım Koşulları ve Son Kullanıcı Lisans Sözleşmesi (EULA) hükümlerini kabul etmiş sayılırsınız.',
      ),
      _section(
        theme,
        '2. Kullanıcı Tarafından Oluşturulan İçerik (UGC) ve Sıfır Tolerans Politikası',
        'Lovera üzerinden paylaşılan mesajlar, fotoğraflar, konum notları ve çizimler tamamen kullanıcının sorumluluğundadır.\n\n'
        '• SIFIR TOLERANS: Lovera; taciz, zorbalık, tehdit, nefret söylemi, rıza dışı mahrem görsel paylaşımı, müstehcenlik veya yasa dışı herhangi bir içeriğe karşı SIFIR TOLERANS politikası uygular.\n'
        '• Bu tür sakıncalı içerikleri paylaşan veya diğer kullanıcıları rahatsız eden hesaplar bildirim üzerine derhal askıya alınır ve kalıcı olarak kapatılır.',
      ),
      _section(
        theme,
        '3. Şikayet Etme (Report) ve Kullanıcı Engelleme (Block) Mekanizması',
        '• Şikayet Etme: Sohbet ekranındaki mesajlara uzun basarak veya Ortak Anı Albümündeki fotoğrafların detay menüsünden "Şikayet Et" butonunu kullanarak uygunsuz içerikleri güvenlik ekibimize bildirebilirsiniz. Tüm şikayetler en geç 24 saat içinde incelenir ve ihlal içeren içerikler derhal kaldırılır.\n'
        '• Kullanıcı Engelleme: Sohbet ekranının sağ üst köşesindeki seçenekler menüsünden "Kullanıcıyı Engelle" seçeneğini kullanarak partnerinizle olan eşleşmeyi, mesajlaşmayı ve konum paylaşımını anında ve tek taraflı olarak sonlandırabilirsiniz. Engellenen kullanıcı sizinle tekrar eşleşme isteği gönderemez.',
      ),
      _section(
        theme,
        '4. Konum ve Güvenlik Sorumluluğu',
        'Canlı konum paylaşımı özelliği tamamen gönüllülük ve karşılıklı rıza esasına dayanır. Kullanıcılar istedikleri an uygulama içinden veya işletim sistemi ayarlarından konum paylaşımını durdurabilir veya eşleşmeyi sonlandırabilir.',
      ),
      _section(
        theme,
        '5. İletişim ve Destek',
        'Kullanım koşulları, içerik bildirimleri ve teknik destek talepleriniz için destek@lovera.app adresinden 7/24 bizimle iletişime geçebilirsiniz.',
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
