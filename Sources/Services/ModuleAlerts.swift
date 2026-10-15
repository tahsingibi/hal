import Foundation

/// Namaz modülünün ürettiği uyarılar.
enum PrayerAlerts {
    static let prefix = "prayer."

    /// Bugünün kalan vakitleri için planlı uyarılar.
    /// `minutesBefore` 0 ise vaktin tam saatinde bildirir.
    static func upcoming(
        day: PrayerDay,
        now: Date,
        minutesBefore: Int,
        includeSunrise: Bool
    ) -> [Alert] {
        let offset = TimeInterval(max(minutesBefore, 0) * 60)
        return day.times
            .filter { includeSunrise || !$0.isSunnah }
            .compactMap { prayer in
                let fireAt = prayer.time.addingTimeInterval(-offset)
                guard fireAt > now else { return nil }
                let clock = TimeFormatters.clock(prayer.time)
                let body = minutesBefore > 0
                    ? "\(prayer.name) vaktine \(minutesBefore) dakika kaldı. (\(clock))"
                    : "\(prayer.name) vakti girdi. (\(clock))"
                return Alert(
                    id: "\(dayKey(prayer.time))-\(prayer.id)",
                    title: prayer.name,
                    body: body,
                    fireAt: fireAt
                )
            }
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}

/// Kota modülünün ürettiği uyarılar.
///
/// İki olay var: **sıfırlandı** (artık kullanabilirsin) ve **eşik aşıldı** (yavaşla).
/// İkisi de iki yenileme arasındaki geçişe bakar; anlık duruma değil. Böylece
/// uygulama açık kaldığı sürece aynı olay bir kez bildirilir.
enum QuotaAlerts {
    struct Snapshot: Codable, Equatable {
        var percent: Double
        var resetsAt: Date?
    }

    /// Pencere kimliği → son görülen durum.
    typealias State = [String: Snapshot]

    static func snapshot(_ groups: [QuotaGroup]) -> State {
        var state: State = [:]
        for group in groups where group.status == .ready {
            for window in group.windows where window.hasLimit {
                state[key(group, window)] = Snapshot(
                    percent: window.clampedPercent,
                    resetsAt: window.resetsAt
                )
            }
        }
        return state
    }

    static func key(_ group: QuotaGroup, _ window: QuotaWindow) -> String {
        "\(group.id)|\(window.id)"
    }

    /// `previous` boşsa (uygulama yeni açıldı) uyarı üretilmez; geçmişi olmayan
    /// bir duruma bakıp "sıfırlandı" demek yanlış olur.
    static func diff(
        previous: State,
        groups: [QuotaGroup],
        notifyReset: Bool,
        notifyThreshold: Bool,
        threshold: Double
    ) -> [Alert] {
        guard !previous.isEmpty else { return [] }
        var alerts: [Alert] = []

        for group in groups where group.status == .ready {
            for window in group.windows where window.hasLimit {
                let id = key(group, window)
                guard let before = previous[id] else { continue }
                let now = window.clampedPercent

                if notifyReset, didReset(before: before, after: window) {
                    alerts.append(
                        Alert(
                            id: "reset-\(id)-\(stamp(before.resetsAt))",
                            title: "\(group.name) kotası sıfırlandı",
                            body: "\(window.title) yeniden kullanılabilir."
                        )
                    )
                    continue
                }

                if notifyThreshold, before.percent < threshold, now >= threshold {
                    let percentText = "\(Int((now * 100).rounded()))%"
                    let reset = window.resetText.isEmpty ? "" : " \(window.resetText)."
                    alerts.append(
                        Alert(
                            id: "threshold-\(id)-\(stamp(window.resetsAt))-\(Int(threshold * 100))",
                            title: "\(group.name) \(percentText)",
                            body: "\(window.title) eşiği aştı.\(reset)"
                        )
                    )
                }
            }
        }
        return alerts
    }

    /// Sıfırlanma iki şekilde anlaşılır: beklenen sıfırlanma anı geçmiştir,
    /// ya da kullanım gözle görülür biçimde düşmüştür.
    private static func didReset(before: Snapshot, after: QuotaWindow) -> Bool {
        let now = after.clampedPercent
        guard before.percent > 0.2 else { return false }
        if now <= 0.05 { return true }
        // Yeni pencere açıldıysa sıfırlanma tarihi ileri kaymıştır.
        if let old = before.resetsAt, let new = after.resetsAt, new > old, now < before.percent {
            return true
        }
        return false
    }

    private static func stamp(_ date: Date?) -> String {
        guard let date else { return "0" }
        return String(Int(date.timeIntervalSince1970))
    }
}


/// Gün sonu özeti. Panodaki satırların bildirim hâli.
enum DailySummaryAlerts {
    static let prefix = "daily."

    static func alert(hour: Int, lines: [SummaryLine], now: Date = Date()) -> Alert? {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = 0
        guard let fireAt = Calendar.current.date(from: components), fireAt > now else { return nil }
        let body = lines
            .prefix(6)
            .map { "\($0.title): \($0.value)" }
            .joined(separator: "\n")
        guard !body.isEmpty else { return nil }
        return Alert(
            id: DailyLog.key(now),
            title: "Bugün",
            body: body,
            fireAt: fireAt
        )
    }
}

/// Gün sonu hatırlatması. Tıklanınca Gün Sonu sayfası açılır.
enum DayCloseAlerts {
    static let prefix = "dayclose."
    static let targetID = "today/end"

    static func alert(hour: Int, pending: Int, now: Date = Date()) -> Alert? {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        components.hour = max(0, min(hour, 23))
        components.minute = 0
        components.second = 0
        guard var fireAt = Calendar.current.date(from: components) else { return nil }
        if fireAt.timeIntervalSinceNow <= 5 {
            fireAt = Calendar.current.date(byAdding: .day, value: 1, to: fireAt) ?? fireAt
        }
        let body: String
        if pending == 1 {
            body = "1 açık işaret var. Düzeltmek için tıkla."
        } else if pending > 1 {
            body = "\(pending) açık işaret var. Düzeltmek için tıkla."
        } else {
            body = "Namaz, ilaç ve antrenman işaretlerini gözden geçir."
        }
        return Alert(
            id: DailyLog.key(fireAt),
            title: "Gün sonu",
            body: body,
            fireAt: fireAt,
            target: targetID
        )
    }
}

/// Abonelik yenileme uyarıları.
enum RenewalAlerts {
    static let prefix = "renewal."

    static func upcoming(subscriptions: [Subscription], daysBefore: Int, now: Date = Date()) -> [Alert] {
        let calendar = Calendar.current
        return subscriptions.compactMap { item in
            let renewal = item.nextRenewal(after: now)
            guard let fireAt = calendar.date(byAdding: .day, value: -daysBefore, to: calendar.startOfDay(for: renewal)),
                  let atNine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: fireAt),
                  atNine > now else { return nil }
            return Alert(
                id: "\(item.id.uuidString)-\(Int(renewal.timeIntervalSince1970))",
                title: "\(item.name) yenilenecek",
                body: "\(item.amountText) · \(daysBefore) gün sonra",
                fireAt: atNine
            )
        }
    }
}

/// İlaç/takviye doz hatırlatmaları. Alınmış dozlar için bildirim kurulmaz.
enum MedicationAlerts {
    static let prefix = "med."

    static func upcoming(
        doses: [MedicationDose],
        now: Date = Date(),
        taken: (MedicationDose) -> Bool
    ) -> [Alert] {
        let calendar = Calendar.current
        return doses.compactMap { dose in
            guard !taken(dose) else { return nil }
            let fireAt = calendar.date(
                byAdding: .minute,
                value: dose.minute,
                to: calendar.startOfDay(for: now)
            )
            guard let fireAt, fireAt > now else { return nil }
            let dose_ = dose.medication.dose.trimmingCharacters(in: .whitespaces)
            return Alert(
                id: "\(DailyLog.key(now))-\(dose.id)",
                title: dose.medication.name,
                body: dose_.isEmpty ? "\(dose.clock) dozu" : "\(dose_) · \(dose.clock)",
                fireAt: fireAt
            )
        }
    }
}
