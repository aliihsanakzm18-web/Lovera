import WidgetKit
import SwiftUI

// MARK: - App Group Tanımı
let loveraAppGroupId = "group.com.lovera.app.lovera"

// MARK: - iOS 17+ containerBackground uyumlu arka plan
extension View {
    @ViewBuilder
    func loveraWidgetBackground<S: ShapeStyle>(_ style: S) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) { Rectangle().fill(style) }
        } else {
            self.background(Rectangle().fill(style))
        }
    }
}

// MARK: - 1. PARTNER BİLGİ & DURUM WİDGET'I
struct LoveraPartnerEntry: TimelineEntry {
    let date: Date
    let partnerName: String
    let daysCount: String
    let batteryLevel: String
    let statusText: String
    let statusEmoji: String
    let lastSeen: String
}

struct LoveraPartnerProvider: TimelineProvider {
    func placeholder(in context: Context) -> LoveraPartnerEntry {
        LoveraPartnerEntry(
            date: Date(),
            partnerName: "Sevgilim",
            daysCount: "365",
            batteryLevel: "%85",
            statusText: "Evde",
            statusEmoji: "🏠",
            lastSeen: "Şimdi aktif"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (LoveraPartnerEntry) -> Void) {
        completion(fetchCurrentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LoveraPartnerEntry>) -> Void) {
        let entry = fetchCurrentEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func fetchCurrentEntry() -> LoveraPartnerEntry {
        let sharedDefaults = UserDefaults(suiteName: loveraAppGroupId) ?? UserDefaults.standard
        let partnerName = sharedDefaults.string(forKey: "partner_name") ?? "Sevgilim"
        let daysCount = sharedDefaults.string(forKey: "days_count") ?? "0"
        let batteryLevel = sharedDefaults.string(forKey: "battery_level") ?? "%--"
        let statusText = sharedDefaults.string(forKey: "status_text") ?? "Dışarıda"
        let statusEmoji = sharedDefaults.string(forKey: "status_emoji") ?? "📍"
        let lastSeen = sharedDefaults.string(forKey: "last_seen") ?? "Şimdi aktif"

        return LoveraPartnerEntry(
            date: Date(),
            partnerName: partnerName,
            daysCount: daysCount,
            batteryLevel: batteryLevel,
            statusText: statusText,
            statusEmoji: statusEmoji,
            lastSeen: lastSeen
        )
    }
}

struct LoveraPartnerEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: LoveraPartnerProvider.Entry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumView
            case .systemLarge:
                largeView
            default:
                smallView
            }
        }
        .loveraWidgetBackground(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.12, green: 0.13, blue: 0.19),
                    Color(red: 0.06, green: 0.07, blue: 0.10)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .widgetURL(URL(string: "lovera://home"))
    }

    // KÜÇÜK KARE GÖRÜNÜMÜ (.systemSmall)
    var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("💜")
                    .font(.system(size: 12))

                Text(entry.partnerName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color.white)
                    .lineLimit(1)

                Spacer()
            }

            VStack(alignment: .leading, spacing: -2) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(entry.daysCount)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(Color(red: 0.72, green: 0.62, blue: 1.0))
                    Text("gün")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.85))
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                HStack(spacing: 3) {
                    Text("🔋")
                        .font(.system(size: 10))
                    Text(entry.batteryLevel)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(batteryColor(for: entry.batteryLevel))
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.12))
                .cornerRadius(8)

                HStack(spacing: 3) {
                    Text(entry.statusEmoji)
                        .font(.system(size: 10))
                    Text(entry.statusText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.12))
                .cornerRadius(8)
            }
        }
        .padding(10)
    }

    // ORTA DİKDÖRTGEN GÖRÜNÜMÜ (.systemMedium)
    var mediumView: some View {
        HStack(spacing: 12) {
            // Sol Taraf: Gün Sayacı
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("💜")
                        .font(.system(size: 13))
                    Text(entry.partnerName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Spacer()
                Text(entry.daysCount)
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundColor(Color(red: 0.72, green: 0.62, blue: 1.0))
                Text("birlikte geçen gün")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.7))
            }

            Spacer()

            // Sağ Taraf: Durum Kartları
            VStack(alignment: .trailing, spacing: 8) {
                Text(entry.lastSeen)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(red: 0.20, green: 0.83, blue: 0.60))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.10))
                    .clipShape(Capsule())

                Spacer()

                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Text("🔋")
                            .font(.system(size: 11))
                        Text(entry.batteryLevel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(batteryColor(for: entry.batteryLevel))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.10))
                    .cornerRadius(10)

                    HStack(spacing: 4) {
                        Text(entry.statusEmoji)
                            .font(.system(size: 11))
                        Text(entry.statusText)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.10))
                    .cornerRadius(10)
                }
            }
        }
        .padding(14)
    }

    // BÜYÜK KARE GÖRÜNÜMÜ (.systemLarge)
    var largeView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("💜")
                    .font(.system(size: 18))
                Text(entry.partnerName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text(entry.lastSeen)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(red: 0.20, green: 0.83, blue: 0.60))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.10))
                    .clipShape(Capsule())
            }

            Spacer()

            VStack(alignment: .center, spacing: 4) {
                Text(entry.daysCount)
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .foregroundColor(Color(red: 0.72, green: 0.62, blue: 1.0))
                Text("Gündür Birlikteyiz 💕")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)

            Spacer()

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Text("🔋")
                        .font(.system(size: 14))
                    Text(entry.batteryLevel)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(batteryColor(for: entry.batteryLevel))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.10))
                .cornerRadius(12)

                HStack(spacing: 6) {
                    Text(entry.statusEmoji)
                        .font(.system(size: 14))
                    Text(entry.statusText)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.10))
                .cornerRadius(12)
            }
        }
        .padding(16)
    }

    private func batteryColor(for text: String) -> Color {
        let clean = text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        guard let level = Int(clean) else {
            return Color(red: 0.20, green: 0.83, blue: 0.60)
        }
        if level >= 50 {
            return Color(red: 0.20, green: 0.83, blue: 0.60)
        } else if level >= 20 {
            return Color(red: 0.98, green: 0.75, blue: 0.14)
        } else {
            return Color(red: 0.94, green: 0.27, blue: 0.27)
        }
    }
}

struct LoveraPartnerWidget: Widget {
    let kind: String = "LoveraPartnerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LoveraPartnerProvider()) { entry in
            LoveraPartnerEntryView(entry: entry)
        }
        .configurationDisplayName("Lovera Partner Durumu")
        .description("Sevgilinizin şarjını, anlık durumunu ve aşk gün sayacınızı ana ekranınızda görün.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - 2. ORTAK ÇİZİM & NOT WİDGET'I
struct LoveraDrawingEntry: TimelineEntry {
    let date: Date
    let senderName: String
    let timeAgo: String
    let imagePath: String?
    let imageBase64: String?
}

struct LoveraDrawingProvider: TimelineProvider {
    func placeholder(in context: Context) -> LoveraDrawingEntry {
        LoveraDrawingEntry(
            date: Date(),
            senderName: "Sevgilim",
            timeAgo: "Şimdi",
            imagePath: nil,
            imageBase64: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (LoveraDrawingEntry) -> Void) {
        completion(fetchCurrentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LoveraDrawingEntry>) -> Void) {
        let entry = fetchCurrentEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func fetchCurrentEntry() -> LoveraDrawingEntry {
        let sharedDefaults = UserDefaults(suiteName: loveraAppGroupId) ?? UserDefaults.standard
        let senderName = sharedDefaults.string(forKey: "drawing_sender") 
            ?? sharedDefaults.string(forKey: "drawing_sender_name") 
            ?? "Sevgilim"
        let timeAgo = sharedDefaults.string(forKey: "drawing_time_ago") ?? "Şimdi"
        let imagePath = sharedDefaults.string(forKey: "drawing_image_path")
        let imageBase64 = sharedDefaults.string(forKey: "drawing_image_base64")

        return LoveraDrawingEntry(
            date: Date(),
            senderName: senderName,
            timeAgo: timeAgo,
            imagePath: imagePath,
            imageBase64: imageBase64
        )
    }
}

struct LoveraDrawingEntryView: View {
    var entry: LoveraDrawingProvider.Entry

    private var drawingImage: UIImage? {
        // 1. Önce doğrudan UserDefaults App Group'a yazılan Base64 kontrolü (Kum havuzu sınırını aşar)
        if let b64 = entry.imageBase64, !b64.isEmpty {
            let clean = b64.contains(",") ? String(b64.split(separator: ",").last ?? "") : b64
            if let data = Data(base64Encoded: clean, options: .ignoreUnknownCharacters),
               let img = UIImage(data: data) {
                return img
            }
        }

        // 2. Eğer dosya yolu verilmişse doğrudan oku
        if let path = entry.imagePath, !path.isEmpty {
            if let img = UIImage(contentsOfFile: path) {
                return img
            }
            // App Group paylaşımlı klasöründe mi kontrol et
            if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: loveraAppGroupId) {
                let fileName = (path as NSString).lastPathComponent
                let groupFile = containerURL.appendingPathComponent(fileName).path
                if let img = UIImage(contentsOfFile: groupFile) {
                    return img
                }
            }
        }

        return nil
    }

    var body: some View {
        ZStack {
            if let uiImage = drawingImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                VStack(spacing: 8) {
                    Text("🎨")
                        .font(.system(size: 32))
                    Text("Henüz bir çizim yok")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.6))
                }
            }

            // Üst Bilgi Rozeti
            VStack {
                HStack {
                    HStack(spacing: 4) {
                        Text("✏️")
                            .font(.system(size: 10))
                        Text(entry.senderName)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.6))
                        Text(entry.timeAgo)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Capsule())

                    Spacer()
                }
                .padding(8)

                Spacer()

                // Sağ alt köşe Çiz butonu rozeti
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Text("🖌️ Çiz")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.65, green: 0.55, blue: 0.98).opacity(0.85))
                    .clipShape(Capsule())
                }
                .padding(8)
            }
        }
        .loveraWidgetBackground(Color(red: 0.09, green: 0.08, blue: 0.15))
        .widgetURL(URL(string: "lovera://drawing"))
    }
}

struct LoveraDrawingWidget: Widget {
    let kind: String = "LoveraDrawingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LoveraDrawingProvider()) { entry in
            LoveraDrawingEntryView(entry: entry)
        }
        .configurationDisplayName("Lovera Ortak Çizim")
        .description("Sevgilinizin size çizdiği resmi veya aşk notunu anında ana ekranınızda görün.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - WIDGET BUNDLE (iOS Ana Ekranında Birden Fazla Widget Seçeneği)
@main
struct LoveraWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        LoveraPartnerWidget()
        LoveraDrawingWidget()
    }
}
