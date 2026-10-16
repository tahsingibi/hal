import Foundation

/// Kaçırılan günlerin namaz, ilaç/takviye ve antrenman işaretleri.
///
/// Yeni bir pano modülü değil: kendi verisi yok, mevcut günlük kayda yazar.
/// Bilgisayara geçilmeyen günde işaretlenemeyen şeyler burada, son birkaç gün
/// içinden seçilerek tamamlanır. Pencere kısa tutulur — seriyi sonsuza dek
/// geriye doldurmak ölçümü anlamsızlaştırır; uzun bir hafta sonu yeter.
enum DayClose {
    static let lookbackDays = 4

    static var obligatoryPrayers: [(id: String, name: String)] {
        ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"].map { ($0, PrayerCopy.name(id: $0)) }
    }

    struct Item: Identifiable, Equatable, Sendable {
        var title: String
        var detail: String?
        var metric: String
        /// Bugün henüz vakti gelmemiş namaz. Geçmiş günde her şey vaktini doldurmuştur.
        var due: Bool

        var id: String { metric }
    }

    struct Section: Identifiable, Equatable, Sendable {
        var id: String
        var title: String
        var icon: String
        var tintHex: String
        var items: [Item]
        var target: DetailTarget
    }

    static func dates(from now: Date, calendar: Calendar = .current) -> [Date] {
        let origin = calendar.startOfDay(for: now)
        return (0..<lookbackDays).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: origin)
        }
    }

    /// Eksik geçmiş gün varsa en eskisi; yoksa bugün. Dünden kalanı açılışta öne alır.
    static func suggestedDate(
        from dates: [Date],
        now: Date,
        pending: (Date) -> Int,
        calendar: Calendar = .current
    ) -> Date {
        let past = dates.filter { !calendar.isDate($0, inSameDayAs: now) }
        return past.first { pending($0) > 0 } ?? calendar.startOfDay(for: now)
    }
}
