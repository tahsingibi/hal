import Foundation

enum PrayerService {
    static func fetch(settings: AppSettings, now: Date = Date()) async throws -> PrayerDay {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MM-yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let date = formatter.string(from: now)
        let timezoneName = settings.countryCode.uppercased() == "TR" ? "Europe/Istanbul" : TimeZone.current.identifier
        var components = URLComponents(string: "https://api.aladhan.com/v1/timings/\(date)")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(settings.latitude)),
            URLQueryItem(name: "longitude", value: String(settings.longitude)),
            URLQueryItem(name: "method", value: String(settings.method)),
            URLQueryItem(name: "school", value: String(settings.school)),
            URLQueryItem(name: "timezonestring", value: timezoneName),
            URLQueryItem(name: "iso8601", value: "true")
        ]
        guard let url = components?.url else {
            throw HalError.message(L("Namaz vakti adresi oluşturulamadı", "Could not build the prayer times address"))
        }
        let (data, response) = try await NetworkClient.get(url)
        guard (200..<300).contains(response.statusCode) else {
            throw HalError.message(Lf("Namaz vakitleri alınamadı (HTTP %1$d)", "Could not load prayer times (HTTP %1$d)", response.statusCode))
        }
        let json = try NetworkClient.json(data)
        guard let root = JSONValue.object(json),
              let payload = JSONValue.object(root["data"]),
              let timings = JSONValue.object(payload["timings"]) else {
            throw HalError.message(L("Namaz vakitleri okunamadı", "Could not read prayer times"))
        }
        let timezone = JSONValue.string(JSONValue.object(payload["meta"])?["timezone"]) ?? TimeZone.current.identifier
        let tz = TimeZone(identifier: timezone) ?? .current
        let gregorian = JSONValue.string(JSONValue.object(JSONValue.object(payload["date"])?["gregorian"])?["date"]) ?? date
        let hijriObject = JSONValue.object(JSONValue.object(payload["date"])?["hijri"])
        let hijri = [
            JSONValue.string(hijriObject?["day"]),
            JSONValue.string(JSONValue.object(hijriObject?["month"])?["en"]),
            JSONValue.string(hijriObject?["year"])
        ].compactMap { $0 }.joined(separator: " ")

        let sequence: [(key: String, sunnah: Bool)] = [
            ("Fajr", false),
            ("Sunrise", true),
            ("Dhuhr", false),
            ("Asr", false),
            ("Maghrib", false),
            ("Isha", false)
        ]
        let times: [PrayerTime] = sequence.compactMap { item in
            guard let raw = JSONValue.string(timings[item.key]) else { return nil }
            guard let date = parseTime(raw, timezone: tz, day: now) else { return nil }
            return PrayerTime(id: item.key, name: PrayerCopy.name(id: item.key), time: date, isSunnah: item.sunnah)
        }
        return PrayerDay(
            gregorian: gregorian,
            hijri: hijri,
            timezone: timezone,
            times: times,
            fetchedAt: Date()
        )
    }

    private static func parseTime(_ raw: String, timezone: TimeZone, day: Date) -> Date? {
        let cleaned = raw.replacingOccurrences(of: " (.*)$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        if let parsed = iso.date(from: cleaned) ?? ISO8601DateFormatter().date(from: cleaned) {
            return parsed
        }
        let parts = cleaned.split(separator: "T").last?.split(separator: ":") ?? cleaned.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(String(parts[1]).prefix(2)) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}
