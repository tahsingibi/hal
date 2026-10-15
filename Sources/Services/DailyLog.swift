import Foundation

/// Gün bazlı sayaçların yerel deposu.
///
/// Her metrik bir `Double` ve bir güne yazılır: `focus.seconds`, `water.ml`,
/// `prayer.fajr` gibi. Bayrak niteliğindeki şeyler 0/1 olarak tutulur, böylece
/// tek bir veri yapısı hem sayacı hem işareti taşır ve seri (streak) hesabı
/// tek yerden yapılır.
///
/// Dosya `~/Library/Application Support/Hal/daily.json`. Yazma geciktirmeli:
/// odak sayacı 30 saniyede bir arttığı için her artışta diske yazmayız.
@MainActor
final class DailyLog: ObservableObject {
    static let shared = DailyLog()

    /// "2026-08-30" → ["focus.seconds": 13320, ...]
    @Published private(set) var days: [String: [String: Double]] = [:]

    private var saveWork: DispatchWorkItem?
    private let retentionDays = 400

    nonisolated private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static var fileURL: URL {
        AppPaths.support.appendingPathComponent("daily.json")
    }

    private init() {
        load()
    }

    nonisolated static func key(_ date: Date) -> String {
        formatter.string(from: date)
    }

    // MARK: - Okuma

    func value(_ metric: String, on date: Date = Date()) -> Double {
        days[Self.key(date)]?[metric] ?? 0
    }

    func isSet(_ metric: String, on date: Date = Date()) -> Bool {
        value(metric, on: date) > 0
    }

    /// Bugünden geriye doğru, koşulu sağlayan kesintisiz gün sayısı.
    /// Bugün henüz sağlanmadıysa seri dünden başlar; gün ortasında seriyi sıfır
    /// göstermek yanıltıcı olurdu.
    func streak(on date: Date = Date(), satisfied: ([String: Double]) -> Bool) -> Int {
        let calendar = Calendar.current
        var count = 0
        var cursor = date
        if !satisfied(days[Self.key(cursor)] ?? [:]) {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = previous
        }
        while satisfied(days[Self.key(cursor)] ?? [:]) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    // MARK: - Yazma

    func set(_ metric: String, _ newValue: Double, on date: Date = Date()) {
        let key = Self.key(date)
        var day = days[key] ?? [:]
        if newValue == 0 {
            day.removeValue(forKey: metric)
        } else {
            day[metric] = newValue
        }
        if day.isEmpty {
            days.removeValue(forKey: key)
        } else {
            days[key] = day
        }
        scheduleSave()
    }

    func add(_ metric: String, _ delta: Double, on date: Date = Date()) {
        set(metric, max(value(metric, on: date) + delta, 0), on: date)
    }

    func toggle(_ metric: String, on date: Date = Date()) {
        set(metric, isSet(metric, on: date) ? 0 : 1, on: date)
    }

    // MARK: - Kalıcılık

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode([String: [String: Double]].self, from: data) else {
            return
        }
        days = decoded
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.save() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    /// Uygulama kapanırken bekleyen yazmayı hemen boşalt.
    func flush() {
        saveWork?.cancel()
        saveWork = nil
        save()
    }

    private func save() {
        prune()
        guard let data = try? JSONEncoder().encode(days) else { return }
        let url = Self.fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func prune() {
        guard days.count > retentionDays else { return }
        for key in days.keys.sorted().prefix(days.count - retentionDays) {
            days.removeValue(forKey: key)
        }
    }
}

/// Metrik adları tek yerde; yazım hatası derleme zamanında yakalanır.
enum Metric {
    static let focusSeconds = "focus.seconds"
    static let waterML = "water.ml"
    static let proteinG = "protein.g"
    static let quranPages = "quran.pages"
    static let workoutDone = "workout.done"

    static func prayer(_ id: String) -> String { "prayer.\(id)" }
}
