import WidgetKit
import SwiftUI

// MARK: - App Group Tanımı
let loveraAppGroupId = "group.com.lovera.app.lovera"

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
        let sharedDefaults = UserDefaults(suiteName: loveraAppGroupId)
        let partnerName = sharedDefaults?.string(forKey: "partner_name") ?? "Sevgilim"
        let daysCount = sharedDefaults?.string(forKey: "days_count") ?? "0"
        let batteryLevel = sharedDefaults?.string(forKey: "battery_level") ?? "%--"
        let statusText = sharedDefaults?.string(forKey: "status_text") ?? "Dışarıda"
        let statusEmoji = sharedDefaults?.string(forKey: "status_emoji") ?? "📍"
        let lastSeen = sharedDefaults?.string(forKey: "last_seen") ?? "Şimdi aktif"

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
    var entry: LoveraPartnerProvider.Entry

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.10, green: 0.11, blue: 0.15),
                    Color(red: 0.05, green: 0.05, blue: 0.07)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("💜")
                        .font(.system(size: 13))

                    Text(entry.partnerName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 0.95, green: 0.96, blue: 0.97))
                        .lineLimit(1)

                    Spacer()

                    Text(entry.lastSeen)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(
                            (entry.lastSeen.contains("Şimdi") || entry.lastSeen.contains("Canlı"))
                                ? Color(red: 0.20, green: 0.83, blue: 0.60)
                                : Color(red: 0.80, green: 0.84, blue: 0.88)
                        )
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(entry.daysCount)
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(Color(red: 0.65, green: 0.55, blue: 0.98))
                        Text("gün")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(red: 0.89, green: 0.91, blue: 0.94))
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Text("🔋")
                            .font(.system(size: 11))
                        Text(entry.batteryLevel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(batteryColor(for: entry.batteryLevel))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(10)

                    HStack(spacing: 4) {
                        Text(entry.statusEmoji)
                            .font(.system(size: 11))
                        Text(entry.statusText)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(red: 0.95, green: 0.96, blue: 0.97))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(10)
                }
            }
            .padding(12)
        }
        .widgetURL(URL(string: "lovera://home"))
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
        .description("Sevgilinin şarjını, anlık durumunu ve aşk gün sayacınızı ana ekranınızda görün.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - 2. ORTAK ÇİZİM & NOT WİDGET'I
struct LoveraDrawingEntry: TimelineEntry {
    let date: Date
    let senderName: String
    let timeAgo: String
    let imagePath: String?
}

struct LoveraDrawingProvider: TimelineProvider {
    func placeholder(in context: Context) -> LoveraDrawingEntry {
        LoveraDrawingEntry(
            date: Date(),
            senderName: "Sevgilim",
            timeAgo: "Şimdi",
            imagePath: nil
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
        let sharedDefaults = UserDefaults(suiteName: loveraAppGroupId)
        let senderName = sharedDefaults?.string(forKey: "drawing_sender") ?? "Sevgilim"
        let timeAgo = sharedDefaults?.string(forKey: "drawing_time_ago") ?? "Şimdi"
        let imagePath = sharedDefaults?.string(forKey: "drawing_image_path")

        return LoveraDrawingEntry(
            date: Date(),
            senderName: senderName,
            timeAgo: timeAgo,
            imagePath: imagePath
        )
    }
}

struct LoveraDrawingEntryView: View {
    var entry: LoveraDrawingProvider.Entry

    var body: some View {
        ZStack {
            Color(red: 0.09, green: 0.08, blue: 0.15) // Tuval arka planı

            if let path = entry.imagePath, let uiImage = UIImage(contentsOfFile: path) {
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
