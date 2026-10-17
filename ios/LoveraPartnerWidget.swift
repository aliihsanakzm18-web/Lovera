import WidgetKit
import SwiftUI

// MARK: - Widget Veri Modeli
struct LoveraWidgetEntry: TimelineEntry {
    let date: Date
    let partnerName: String
    let daysCount: String
    let batteryLevel: String
    let statusText: String
    let statusEmoji: String
    let lastSeen: String
}

// MARK: - Timeline Provider
struct LoveraTimelineProvider: TimelineProvider {
    private let appGroupId = "group.com.lovera.app.lovera"

    func placeholder(in context: Context) -> LoveraWidgetEntry {
        LoveraWidgetEntry(
            date: Date(),
            partnerName: "Sevgilim",
            daysCount: "365",
            batteryLevel: "%85",
            statusText: "Evde",
            statusEmoji: "🏠",
            lastSeen: "Şimdi aktif"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (LoveraWidgetEntry) -> Void) {
        completion(fetchCurrentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LoveraWidgetEntry>) -> Void) {
        let entry = fetchCurrentEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func fetchCurrentEntry() -> LoveraWidgetEntry {
        let sharedDefaults = UserDefaults(suiteName: appGroupId)
        let partnerName = sharedDefaults?.string(forKey: "partner_name") ?? "Sevgilim"
        let daysCount = sharedDefaults?.string(forKey: "days_count") ?? "0"
        let batteryLevel = sharedDefaults?.string(forKey: "battery_level") ?? "%--"
        let statusText = sharedDefaults?.string(forKey: "status_text") ?? "Dışarıda"
        let statusEmoji = sharedDefaults?.string(forKey: "status_emoji") ?? "📍"
        let lastSeen = sharedDefaults?.string(forKey: "last_seen") ?? "Şimdi aktif"

        return LoveraWidgetEntry(
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

// MARK: - SwiftUI Widget View
struct LoveraWidgetEntryView: View {
    var entry: LoveraTimelineProvider.Entry

    var body: some View {
        ZStack {
            // Lovera Uygulama Teması Koyu Mor-Grafit Degrade
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.10, green: 0.11, blue: 0.15), // #1A1D27
                    Color(red: 0.05, green: 0.05, blue: 0.07)  // #0D0E13
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 6) {
                // Üst Başlık & Partner İsmi & Son Aktif / Canlı Rozeti
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
                            (entry.lastSeen.contains("Şimdi aktif") || entry.lastSeen.contains("Canlı"))
                                ? Color(red: 0.20, green: 0.83, blue: 0.60) // #34D399 Canlı Yeşil
                                : Color(red: 0.80, green: 0.84, blue: 0.88) // Normal Açık Gri
                        )
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }

                // Orta Alan: Birlikte Geçen Gün Sayacı (Lovera Pastel Leylak Moru)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(entry.daysCount)
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(Color(red: 0.65, green: 0.55, blue: 0.98)) // #A78BFA
                        Text("gün")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(red: 0.89, green: 0.91, blue: 0.94))
                    }
                }

                Spacer(minLength: 0)

                // Alt Alan: Batarya & Durum (Evde / Yürüyor / Arabada / Dışarıda)
                HStack(spacing: 6) {
                    // Batarya Çipi
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

                    // Durum Çipi (Evde mi, Dışarıda mı, Yürüyor mu)
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
            return Color(red: 0.20, green: 0.83, blue: 0.60) // Yeşil #34D399
        } else if level >= 20 {
            return Color(red: 0.98, green: 0.75, blue: 0.14) // Amber / Sarı #FBBF24
        } else {
            return Color(red: 0.94, green: 0.27, blue: 0.27) // Kritik Kırmızı #EF4444
        }
    }
}

// MARK: - Widget Konfigürasyonu
@main
struct LoveraPartnerWidget: Widget {
    let kind: String = "LoveraPartnerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LoveraTimelineProvider()) { entry in
            LoveraWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Lovera Partner Durumu")
        .description("Sevgilinin şarjını, anlık durumunu ve aşk gün sayacınızı ana ekranınızda görün.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
