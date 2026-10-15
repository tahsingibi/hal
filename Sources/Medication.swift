import Foundation

/// Bir ilaç/takviye ve günün hangi saatlerinde alınacağı.
///
/// Doz saatleri gece yarısından itibaren dakika olarak tutulur; böylece
/// sıralama, "sıradaki doz" ve bildirim zamanlaması tek bir sayıdan çıkar.
struct Medication: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// "1 tablet", "2 kapsül" gibi serbest metin.
    var dose: String
    /// Gece yarısından itibaren dakika (0…1439), sıralı.
    var times: [Int]
    var enabled: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        dose: String = "",
        times: [Int] = [9 * 60],
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.dose = dose
        self.times = times.sorted()
        self.enabled = enabled
    }

    /// Bir dozun günlük kaydındaki anahtarı. Saat kaydın parçası: aynı ilacın
    /// sabah dozunu işaretlemek akşam dozunu işaretlemiş saymaz.
    func metric(at minute: Int) -> String {
        "med.\(id.uuidString).\(minute)"
    }

    static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    static func minute(from date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Eklenecek yeni doz için boş bir saat: son dozdan 12 saat sonra, dolu ise
    /// birer saat kaydırarak ilk boş yuvayı bulur. Aynı saate iki doz düşmez.
    func nextFreeTime() -> Int {
        let taken = Set(times)
        var candidate = ((times.max() ?? 9 * 60) + 720) % 1440
        var guardCount = 0
        while taken.contains(candidate), guardCount < 24 {
            candidate = (candidate + 60) % 1440
            guardCount += 1
        }
        return candidate
    }

    static func date(fromMinute minute: Int, calendar: Calendar = .current) -> Date {
        let base = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: minute, to: base) ?? base
    }
}

/// Bugünün tek bir dozu: ilaç + saat.
struct MedicationDose: Identifiable, Equatable, Sendable {
    var medication: Medication
    var minute: Int

    var id: String { medication.metric(at: minute) }
    var clock: String { Medication.clock(minute) }

    /// Saati geçmiş ve hâlâ işaretlenmemiş doz.
    func isOverdue(now: Date, taken: Bool, calendar: Calendar = .current) -> Bool {
        guard !taken else { return false }
        return Medication.minute(from: now, calendar: calendar) > minute
    }
}
