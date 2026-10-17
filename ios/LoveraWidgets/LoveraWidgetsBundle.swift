import WidgetKit
import SwiftUI
import UIKit

// MARK: - Sabitler
let loveraAppGroupId = "group.com.lovera.app.lovera"
let loveraFirebaseProjectId = "sevgili-app-fb6f4"
let loveraDefaultIphoneUserId = "0XYm70awVCUDu3ymlGWLIttaHah2" // Eda (iPhone)
let loveraDefaultPartnerUserId = "oFMoj6korCWhw3C8EpWneZ903G62" // Ali_ihsan
let loveraDefaultCoupleId = "Hibrst2JU439l0t41NsL"

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

// MARK: - Doğrudan Firebase Firestore REST İstemcisi (Uygulama Kapalıyken & App Group Olmasa Bile Çalışır)
struct LoveraFirestoreClient {
    static var baseUrl: String {
        return "https://firestore.googleapis.com/v1/projects/\(loveraFirebaseProjectId)/databases/(default)/documents"
    }

    static func stringField(_ fields: [String: Any]?, _ key: String) -> String? {
        guard let field = fields?[key] as? [String: Any] else { return nil }
        if let s = field["stringValue"] as? String { return s }
        if let i = field["integerValue"] as? String { return i }
        if let d = field["doubleValue"] as? NSNumber { return d.stringValue }
        return nil
    }

    static func doubleField(_ fields: [String: Any]?, _ key: String) -> Double? {
        guard let field = fields?[key] as? [String: Any] else { return nil }
        if let d = field["doubleValue"] as? NSNumber { return d.doubleValue }
        if let s = field["doubleValue"] as? String { return Double(s) }
        if let i = field["integerValue"] as? String { return Double(i) }
        if let n = field["integerValue"] as? NSNumber { return n.doubleValue }
        return nil
    }

    static func boolField(_ fields: [String: Any]?, _ key: String) -> Bool? {
        guard let field = fields?[key] as? [String: Any] else { return nil }
        return field["booleanValue"] as? Bool
    }

    static func timestampField(_ fields: [String: Any]?, _ key: String) -> Date? {
        guard let field = fields?[key] as? [String: Any] else { return nil }
        if let ts = field["timestampValue"] as? String {
            let isoFrac = ISO8601DateFormatter()
            isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = isoFrac.date(from: ts) { return d }
            let isoPlain = ISO8601DateFormatter()
            isoPlain.formatOptions = [.withInternetDateTime]
            if let d = isoPlain.date(from: ts) { return d }
        }
        if let iStr = field["integerValue"] as? String, let ms = Double(iStr) {
            return Date(timeIntervalSince1970: ms / 1000.0)
        }
        return nil
    }

    static func calculateDays(from startDateStr: String?) -> String? {
        guard let raw = startDateStr, raw.count >= 10 else { return nil }
        let prefix10 = String(raw.prefix(10))
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        guard let startDate = df.date(from: prefix10) else { return nil }
        let diffDays = Int(Date().timeIntervalSince(startDate) / 86400.0)
        return "\(max(0, diffDays))"
    }

    static func formatLastSeen(isAppOpen: Bool?, lastActive: Date?) -> String {
        if let activeDate = lastActive {
            let diffMinutes = Int(abs(Date().timeIntervalSince(activeDate)) / 60.0)
            if isAppOpen == true && diffMinutes < 3 {
                return "Şimdi aktif"
            } else if diffMinutes <= 1 {
                return "1 dk önce"
            } else if diffMinutes < 60 {
                return "\(diffMinutes) dk önce"
            } else if diffMinutes < 1440 {
                return "\(diffMinutes / 60) sa önce"
            } else {
                return "\(diffMinutes / 1440) gün önce"
            }
        }
        return isAppOpen == true ? "Şimdi aktif" : "Çevrimdışı"
    }

    static func formatTimeAgo(from date: Date?) -> String {
        guard let d = date else { return "Şimdi" }
        let diffMinutes = Int(max(0, Date().timeIntervalSince(d)) / 60.0)
        if diffMinutes < 1 {
            return "Şimdi"
        } else if diffMinutes < 60 {
            return "\(diffMinutes) dk önce"
        } else if diffMinutes < 1440 {
            return "\(diffMinutes / 60) sa önce"
        } else {
            return "\(diffMinutes / 1440) gün önce"
        }
    }

    /// Hem App Group hem yerel önbellekten mevcut Partner Entry'sini okur
    static func cachedPartnerEntry() -> LoveraPartnerEntry {
        let groupDefaults = UserDefaults(suiteName: loveraAppGroupId)
        let stdDefaults = UserDefaults.standard

        let partnerName = groupDefaults?.string(forKey: "partner_name")
            ?? stdDefaults.string(forKey: "cached_partner_name")
            ?? "Sevgilim"
        let daysCount = groupDefaults?.string(forKey: "days_count")
            ?? stdDefaults.string(forKey: "cached_days_count")
            ?? "0"
        let batteryLevel = groupDefaults?.string(forKey: "battery_level")
            ?? stdDefaults.string(forKey: "cached_battery_level")
            ?? "%--"
        let statusText = groupDefaults?.string(forKey: "status_text")
            ?? stdDefaults.string(forKey: "cached_status_text")
            ?? "Dışarıda"
        let statusEmoji = groupDefaults?.string(forKey: "status_emoji")
            ?? stdDefaults.string(forKey: "cached_status_emoji")
            ?? "📍"
        let lastSeen = groupDefaults?.string(forKey: "last_seen")
            ?? stdDefaults.string(forKey: "cached_last_seen")
            ?? "Şimdi aktif"

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

    /// Doğrudan Firestore'dan Partner durumunu ve gün sayacını çeker (Uygulama tamamen kapalıyken bile çalışır)
    static func fetchPartnerEntryFromCloud(completion: @escaping (LoveraPartnerEntry) -> Void) {
        guard let url = URL(string: "\(baseUrl)/users") else {
            completion(cachedPartnerEntry())
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 7.0
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let docs = json["documents"] as? [[String: Any]] else {
                completion(cachedPartnerEntry())
                return
            }

            let vendorId = UIDevice.current.identifierForVendor?.uuidString ?? ""
            let groupDefaults = UserDefaults(suiteName: loveraAppGroupId)
            let stdDefaults = UserDefaults.standard

            // 1. Kullanıcı eşleştirmesi: Önce iosVendorId, yoksa varsayılan iPhone kullanıcısı (Eda)
            var usersById: [String: [String: Any]] = [:]
            var matchedMeId: String? = nil

            for doc in docs {
                guard let fullName = doc["name"] as? String,
                      let docId = fullName.split(separator: "/").last.map(String.init),
                      let fields = doc["fields"] as? [String: Any] else { continue }
                usersById[docId] = fields

                if !vendorId.isEmpty, stringField(fields, "iosVendorId") == vendorId {
                    matchedMeId = docId
                }
            }

            let meId = matchedMeId
                ?? groupDefaults?.string(forKey: "saved_uid")
                ?? stdDefaults.string(forKey: "cached_me_uid")
                ?? loveraDefaultIphoneUserId

            let meFields = usersById[meId]
            let partnerId = stringField(meFields, "partnerUid")
                ?? groupDefaults?.string(forKey: "saved_partner_uid")
                ?? stdDefaults.string(forKey: "cached_partner_uid")
                ?? loveraDefaultPartnerUserId

            let coupleId = stringField(meFields, "coupleId")
                ?? groupDefaults?.string(forKey: "saved_couple_id")
                ?? stdDefaults.string(forKey: "cached_couple_id")
                ?? loveraDefaultCoupleId

            stdDefaults.set(meId, forKey: "cached_me_uid")
            stdDefaults.set(partnerId, forKey: "cached_partner_uid")
            stdDefaults.set(coupleId, forKey: "cached_couple_id")

            guard let partnerFields = usersById[partnerId] else {
                completion(cachedPartnerEntry())
                return
            }

            // Partner adı
            let rawName = stringField(partnerFields, "name")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let partnerName = rawName.isEmpty ? "Sevgilim" : rawName

            // Batarya
            var batteryLevel = "%--"
            if let bat = doubleField(partnerFields, "batteryLevel") {
                batteryLevel = "%\(Int(bat))"
            }

            // Konum & Mekan / Hareket durumu
            let placeTitle = stringField(partnerFields, "currentPlaceTitle")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let placeEmoji = stringField(partnerFields, "currentPlaceEmoji")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let speed = doubleField(partnerFields, "speed") ?? 0.0
            let speedKmH = speed * 3.6
            let hasCoords = doubleField(partnerFields, "lat") != nil && doubleField(partnerFields, "lng") != nil

            var statusEmoji = "📍"
            var statusText = "Dışarıda"

            if !placeTitle.isEmpty {
                statusEmoji = placeEmoji.isEmpty ? "🏠" : placeEmoji
                statusText = placeTitle
            } else if speedKmH >= 20.0 {
                statusEmoji = "🚗"
                statusText = "Arabada"
            } else if speedKmH >= 2.5 {
                statusEmoji = "🚶"
                statusText = "Yürüyor"
            } else if hasCoords {
                statusEmoji = "📍"
                statusText = "Dışarıda"
            } else {
                statusEmoji = "✨"
                statusText = "Aktif"
            }

            // Son görülme
            let isAppOpen = boolField(partnerFields, "isAppOpen")
            let lastActive = timestampField(partnerFields, "lastActive")
            let lastSeen = formatLastSeen(isAppOpen: isAppOpen, lastActive: lastActive)

            // Gün sayacı
            let startStr = stringField(partnerFields, "relationshipStartDate")
                ?? stringField(meFields, "relationshipStartDate")
                ?? "2024-05-31T00:00:00.000"
            let daysCount = calculateDays(from: startStr)
                ?? stdDefaults.string(forKey: "cached_days_count")
                ?? "0"

            // Yerel önbelleğe kaydet
            stdDefaults.set(partnerName, forKey: "cached_partner_name")
            stdDefaults.set(daysCount, forKey: "cached_days_count")
            stdDefaults.set(batteryLevel, forKey: "cached_battery_level")
            stdDefaults.set(statusText, forKey: "cached_status_text")
            stdDefaults.set(statusEmoji, forKey: "cached_status_emoji")
            stdDefaults.set(lastSeen, forKey: "cached_last_seen")

            let entry = LoveraPartnerEntry(
                date: Date(),
                partnerName: partnerName,
                daysCount: daysCount,
                batteryLevel: batteryLevel,
                statusText: statusText,
                statusEmoji: statusEmoji,
                lastSeen: lastSeen
            )
            completion(entry)
        }.resume()
    }

    /// Görseli WidgetKit bellek sınırına (maks 500px) uygun şekilde küçültür
    static func decodeAndResizeImage(from base64Str: String?) -> UIImage? {
        guard let b64 = base64Str, !b64.isEmpty else { return nil }
        let clean = b64.contains(",") ? String(b64.split(separator: ",").last ?? "") : b64
        guard let data = Data(base64Encoded: clean, options: .ignoreUnknownCharacters),
              let image = UIImage(data: data) else { return nil }

        let maxDimension: CGFloat = 500.0
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension, maxSide > 0 else { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Önbellekteki Çizim Entry'sini okur
    static func cachedDrawingEntry() -> LoveraDrawingEntry {
        let groupDefaults = UserDefaults(suiteName: loveraAppGroupId)
        let stdDefaults = UserDefaults.standard

        let senderName = groupDefaults?.string(forKey: "drawing_sender")
            ?? groupDefaults?.string(forKey: "drawing_sender_name")
            ?? stdDefaults.string(forKey: "cached_drawing_sender")
            ?? "Sevgilim"
        let timeAgo = groupDefaults?.string(forKey: "drawing_time_ago")
            ?? stdDefaults.string(forKey: "cached_drawing_time_ago")
            ?? "Şimdi"
        let imagePath = groupDefaults?.string(forKey: "drawing_image_path")
        let imageBase64 = groupDefaults?.string(forKey: "drawing_image_base64")
            ?? stdDefaults.string(forKey: "cached_drawing_base64")

        return LoveraDrawingEntry(
            date: Date(),
            senderName: senderName,
            timeAgo: timeAgo,
            imagePath: imagePath,
            imageBase64: imageBase64
        )
    }

    /// Doğrudan Firestore'dan son çizimi çeker (Uygulama tamamen kapalıyken bile çalışır)
    static func fetchDrawingEntryFromCloud(completion: @escaping (LoveraDrawingEntry) -> Void) {
        let groupDefaults = UserDefaults(suiteName: loveraAppGroupId)
        let stdDefaults = UserDefaults.standard

        let coupleId = groupDefaults?.string(forKey: "saved_couple_id")
            ?? stdDefaults.string(forKey: "cached_couple_id")
            ?? loveraDefaultCoupleId
        let meId = groupDefaults?.string(forKey: "saved_uid")
            ?? stdDefaults.string(forKey: "cached_me_uid")
            ?? loveraDefaultIphoneUserId

        guard let url = URL(string: "\(baseUrl)/couples/\(coupleId)/drawings/latest") else {
            completion(cachedDrawingEntry())
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 7.0
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let fields = json["fields"] as? [String: Any] else {
                completion(cachedDrawingEntry())
                return
            }

            let imageBase64 = stringField(fields, "imageBase64")
            let rawSender = stringField(fields, "senderName") ?? "Sevgilim"
            let senderId = stringField(fields, "senderId") ?? ""
            let createdAt = timestampField(fields, "createdAt")

            let senderName = (!meId.isEmpty && senderId == meId) ? "Sen" : rawSender
            let timeAgo = formatTimeAgo(from: createdAt)

            if let b64 = imageBase64, !b64.isEmpty {
                stdDefaults.set(b64, forKey: "cached_drawing_base64")
            }
            stdDefaults.set(senderName, forKey: "cached_drawing_sender")
            stdDefaults.set(timeAgo, forKey: "cached_drawing_time_ago")

            let entry = LoveraDrawingEntry(
                date: Date(),
                senderName: senderName,
                timeAgo: timeAgo,
                imagePath: nil,
                imageBase64: imageBase64 ?? stdDefaults.string(forKey: "cached_drawing_base64")
            )
            completion(entry)
        }.resume()
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
        LoveraFirestoreClient.cachedPartnerEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (LoveraPartnerEntry) -> Void) {
        LoveraFirestoreClient.fetchPartnerEntryFromCloud { entry in
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LoveraPartnerEntry>) -> Void) {
        LoveraFirestoreClient.fetchPartnerEntryFromCloud { entry in
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 2, to: Date()) ?? Date().addingTimeInterval(120)
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
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
        LoveraFirestoreClient.cachedDrawingEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (LoveraDrawingEntry) -> Void) {
        LoveraFirestoreClient.fetchDrawingEntryFromCloud { entry in
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LoveraDrawingEntry>) -> Void) {
        LoveraFirestoreClient.fetchDrawingEntryFromCloud { entry in
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 2, to: Date()) ?? Date().addingTimeInterval(120)
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }
}

struct LoveraDrawingEntryView: View {
    var entry: LoveraDrawingProvider.Entry

    private var drawingImage: UIImage? {
        if let img = LoveraFirestoreClient.decodeAndResizeImage(from: entry.imageBase64) {
            return img
        }

        if let path = entry.imagePath, !path.isEmpty {
            if let img = UIImage(contentsOfFile: path) {
                return img
            }
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
                    .padding(4)
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

// MARK: - WIDGET BUNDLE
@main
struct LoveraWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        LoveraPartnerWidget()
        LoveraDrawingWidget()
    }
}
