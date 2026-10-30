import Foundation
import SwiftUI
import ServiceManagement

@MainActor
final class AppStore: ObservableObject {
    @Published var settings: AppSettings {
        willSet { Language.apply(newValue.language) }
        didSet {
            let languageChanged = oldValue.language != settings.language
            persist()
            if languageChanged {
                Task { await refresh() }
            }
            if oldValue.switcher != settings.switcher { WindowSwitcher.shared.apply(settings.switcher) }
            if oldValue.displayControlsEnabled != settings.displayControlsEnabled { DisplayController.shared.apply(enabled: settings.displayControlsEnabled) }
            if Self.wakeSignature(oldValue) != Self.wakeSignature(settings) {
                WakeController.shared.apply(settings)
            }
        }
    }
    @Published var quotas: [QuotaGroup] = []
    /// Display-only rotation; never changes the Today board’s best-quota metric.
    var menuBarQuotaID: String?
    var rotatingQuota: QuotaGroup? {
        let ids = visibleQuotaIDs
        return quotas.first { $0.id == menuBarQuotaID && ids.contains($0.id) }
            ?? ids.lazy.compactMap { id in self.quotas.first { $0.id == id } }.first
    }
    @Published var prayers: PrayerDay?
    @Published var expanded = false
    @Published var pinned = UserDefaults.standard.bool(forKey: "hal.pinned") {
        didSet { UserDefaults.standard.set(pinned, forKey: "hal.pinned") }
    }
    @Published var isDragging = false
    @Published var selection: DetailTarget?
    /// Menü çubuğu ikonundan her açılışta artar. Pano paneli buna dönünce modül sayfasına iner.
    @Published var boardToken = 0
    @Published var lastQuotaID: String?
    @Published var now = Date()
    @Published var lastError: String?
    @Published var refreshing = false
    @Published var countries: [PlaceCountry] = LocationService.bundledCountries
    @Published var regions: [PlaceRegion] = []
    @Published var cities: [PlaceCity] = []
    @Published var cityQuery = ""
    @Published var cityResults: [PlaceCity] = []
    @Published var cleaningMode = false
    @Published var cleaningMessage: String?

    /// Panoda görülmüş satırların kaydı; ayarlarda hangi satırın gizlenebileceğini
    /// buradan türetiyoruz.
    @Published private(set) var summaryCatalog: [SummaryLineRef] = []

    private var quotaSnapshot: QuotaAlerts.State = [:]
    /// Modül başına en son bakılan sayfa; sekmeye dönünce oradan devam eder.
    private var lastPageByModule: [String: String?] = [:]
    private var hoverCollapseWork: DispatchWorkItem?
    private var tickTimer: Timer?
    private var refreshTimer: Timer?

    init() {
        self.settings = Self.loadSettings()
        if !UserDefaults.standard.bool(forKey: "hal.migrated.quotaTicker.v1") {
            self.settings.menuBarCollapsed = true
            if let data = try? JSONEncoder().encode(self.settings) { UserDefaults.standard.set(data, forKey: "hal.settings") }
            UserDefaults.standard.set(true, forKey: "hal.migrated.quotaTicker.v1")
        }
        self.settings.expandOnHover = false
        self.lastQuotaID = UserDefaults.standard.string(forKey: "hal.lastQuota")
        self.lastPageByModule = Self.loadLastPages().mapValues { Optional($0) }
        self.selection = Self.loadRememberedTarget()
        self.summaryCatalog = Self.loadSummaryCatalog()
        if !UserDefaults.standard.bool(forKey: "hal.migrated.asr.tr"),
           self.settings.countryCode.uppercased() == "TR",
           self.settings.method == 13,
           self.settings.school == 1 {
            self.settings.school = 0
            UserDefaults.standard.set(true, forKey: "hal.migrated.asr.tr")
        }
        Language.apply(settings.language)
        WakeController.shared.onPatch = { [weak self] body in
            guard let self else { return }
            var copy = self.settings
            body(&copy)
            if copy != self.settings { self.settings = copy }
        }
        Task { await bootstrap() }
        startTick()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
        refreshTimer?.tolerance = 20
        NotificationCenter.default.addObserver(
            forName: .halCleaningEnded,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.cleaningMode = false
                self?.cleaningMessage = nil
            }
        }
        NotificationCenter.default.addObserver(
            forName: .halGrokSessionChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    var nextPrayer: PrayerTime? {
        prayers?.next(after: now, includeSunrise: settings.showSunrise)
    }

    var headerText: String { TimeFormatters.header(now) }

    var modules: [ModuleKind] { settings.enabledModules }

    /// Bir modülün popover sayfaları. Yeni modül eklerken buraya bir `case` gelir.
    func pages(for module: ModuleKind) -> [ModulePage] {
        switch module {
        case .today:
            return [
                ModulePage(module: .today, item: nil, title: L("Bugün", "Today"), icon: .app, menuBarID: nil),
                ModulePage(module: .today, item: "week", title: L("Hafta", "Week"), icon: .app, menuBarID: nil),
                ModulePage(module: .today, item: "end", title: L("Gün Sonu", "End of day"), icon: .app, menuBarID: nil)
            ]
        case .focus:
            return [
                ModulePage(module: .focus, item: nil, title: L("Odak", "Focus"), icon: .app, menuBarID: nil)
            ]
        case .usage:
            return quotas.map { group in
                ModulePage(
                    module: .usage,
                    item: group.id,
                    title: group.name,
                    icon: BrandIcon.from(id: group.id),
                    menuBarID: group.id
                )
            }
        case .prayer:
            return [
                ModulePage(module: .prayer, item: nil, title: L("Vakitler", "Prayer times"), icon: .prayer, menuBarID: "prayer")
            ]
        case .calendar:
            return [
                ModulePage(module: .calendar, item: nil, title: L("Takvim", "Calendar"), icon: .app, menuBarID: nil)
            ]
        case .fitness:
            var pages = [ModulePage(module: .fitness, item: nil, title: L("Genel", "Overview"), icon: .app, menuBarID: nil)]
            if settings.trackWorkout {
                pages.append(ModulePage(module: .fitness, item: "workout", title: L("Antrenman", "Workout"), icon: .app, menuBarID: nil))
            }
            if settings.trackMedication, !settings.medications.isEmpty {
                pages.append(
                    ModulePage(module: .fitness, item: "meds", title: L("İlaç & Takviye", "Meds & supplements"), icon: .app, menuBarID: nil)
                )
            }
            if settings.trackIntake {
                pages.append(ModulePage(module: .fitness, item: "nutrition", title: L("Beslenme", "Nutrition"), icon: .app, menuBarID: nil))
            }
            return pages
        case .money:
            return [
                ModulePage(module: .money, item: nil, title: L("Ödemeler", "Payments"), icon: .app, menuBarID: nil)
            ]
        }
    }

    // MARK: - Pano

    /// Bir modülün panoya verdiği satırlar. Yeni modül eklerken buraya bir `case` gelir;
    /// pano ekranında ayrıca kod yazılmaz.
    func summaryLines(for module: ModuleKind) -> [SummaryLine] {
        switch module {
        case .today:
            return []
        case .focus:
            return focusSummaryLines
        case .prayer:
            return worshipSummaryLines
        case .usage:
            return usageSummaryLines
        case .calendar:
            return calendarSummaryLines
        case .fitness:
            return healthSummaryLines
        case .money:
            return moneySummaryLines
        }
    }

    private var focusSummaryLines: [SummaryLine] {
        guard settings.focusTracking else { return [] }
        let seconds = DailyLog.shared.value(Metric.focusSeconds, on: now)
        let goal = Double(settings.focusGoalMinutes * 60)
        return [SummaryLine(
            id: "focus",
            icon: "scope",
            title: L("Derin çalışma", "Deep work"),
            value: TimeFormatters.duration(seconds),
            detail: FocusTracker.shared.currentApp.map { Lf("şu an %1$@", "now %1$@", $0) },
            progress: goal > 0 ? min(seconds / goal, 1) : nil,
            tintHex: "7C5CFF",
            target: DetailTarget(module: .focus)
        )]
    }

    private var worshipSummaryLines: [SummaryLine] {
        var lines: [SummaryLine] = []
        if !settings.hasLocation {
            lines.append(
                SummaryLine(
                    id: "prayer.next",
                    icon: "moon.stars",
                    title: L("Namaz", "Prayer"),
                    value: L("Konum seç", "Choose location"),
                    detail: L("Ayarlar › İbadet", "Settings › Prayer"),
                    progress: nil,
                    tintHex: nil,
                    target: DetailTarget(module: .prayer),
                    catalogTitle: L("Sıradaki vakit", "Next prayer")
                )
            )
        } else if let next = nextPrayer, let day = prayers {
            lines.append(
                SummaryLine(
                    id: "prayer.next",
                    icon: "moon.stars",
                    title: next.localizedName,
                    value: TimeFormatters.clock(next.time),
                    detail: Lf("%1$@ kaldı", "%1$@ left", TimeFormatters.remaining(day.remaining(to: next, now: now))),
                    progress: nil,
                    tintHex: nil,
                    target: DetailTarget(module: .prayer),
                    catalogTitle: L("Sıradaki vakit", "Next prayer")
                )
            )
        }
        if settings.trackPrayers, let day = prayers {
            let obligatory = day.times.filter { !$0.isSunnah }
            let done = obligatory.filter { DailyLog.shared.isSet(Metric.prayer($0.id), on: now) }.count
            lines.append(
                SummaryLine(
                    id: "prayer.done",
                    icon: "checkmark.circle",
                    title: L("Kılınan", "Prayed"),
                    value: "\(done)/\(obligatory.count)",
                    detail: prayerStreak > 1 ? Lf("%1$d gün seri", "%1$d-day streak", prayerStreak) : nil,
                    progress: obligatory.isEmpty ? nil : Double(done) / Double(obligatory.count),
                    tintHex: "5BC48A",
                    target: DetailTarget(module: .prayer)
                )
            )
        }
        return lines
    }

    private var usageSummaryLines: [SummaryLine] {
        var lines: [SummaryLine] = []
        if let best = summaryQuota, let percent = best.headlinePercent {
            lines.append(
                SummaryLine(
                    id: "usage.best",
                    icon: "bolt",
                    title: L("En boş kota", "Most remaining"),
                    value: "\(best.name) \(Int((percent * 100).rounded()))%",
                    detail: best.headlineWindow?.resetText.nilIfEmpty,
                    progress: percent,
                    tintHex: best.accentHex,
                    target: DetailTarget(module: .usage, item: best.id)
                )
            )
        }
        let full = quotas.filter { $0.status == .ready && ($0.headlinePercent ?? 0) >= 0.999 }
        if !full.isEmpty {
            lines.append(
                SummaryLine(
                    id: "usage.full",
                    icon: "exclamationmark.triangle",
                    title: L("Dolu", "Full"),
                    value: full.map(\.name).joined(separator: ", "),
                    detail: full.first?.headlineWindow?.resetText.nilIfEmpty,
                    progress: nil,
                    tintHex: "E85D4C",
                    target: full.first.map { DetailTarget(module: .usage, item: $0.id) }
                )
            )
        }
        let broken = quotas.filter { $0.status != .ready && $0.status != .loading }
        if !broken.isEmpty {
            lines.append(
                SummaryLine(
                    id: "usage.broken",
                    icon: "xmark.circle",
                    title: L("Okunamıyor", "Unreadable"),
                    value: broken.map(\.name).joined(separator: ", "),
                    detail: nil,
                    progress: nil,
                    tintHex: "E8A04A",
                    target: broken.first.map { DetailTarget(module: .usage, item: $0.id) }
                )
            )
        }
        return lines
    }

    private var calendarSummaryLines: [SummaryLine] {
        guard CalendarService.shared.access == .granted,
              let event = CalendarService.shared.next(after: now) else { return [] }
        let running = event.isRunning(at: now)
        return [
            SummaryLine(
                id: "calendar.next",
                icon: "calendar",
                title: running ? L("Şu an", "Now") : L("Sonraki olay", "Next event"),
                value: event.title,
                detail: running
                    ? Lf("%1$@’a kadar", "until %1$@", TimeFormatters.clock(event.end))
                    : Lf(
                        "%1$@ · %2$@ kaldı",
                        "%1$@ · %2$@ left",
                        TimeFormatters.clock(event.start),
                        TimeFormatters.remaining(event.start.timeIntervalSince(now))
                    ),
                progress: nil,
                tintHex: running ? "5BC48A" : nil,
                target: DetailTarget(module: .calendar),
                catalogTitle: L("Sonraki olay", "Next event")
            )
        ]
    }

    private var healthSummaryLines: [SummaryLine] {
        var lines: [SummaryLine] = []
        if settings.trackMedication, !settings.medications.isEmpty {
            let doses = todayDoses
            let taken = doses.filter { isDoseTaken($0) }.count
            let overdue = doses.filter { $0.isOverdue(now: now, taken: isDoseTaken($0)) }
            let next = doses.first { !isDoseTaken($0) && $0.minute >= Medication.minute(from: now) }
            lines.append(
                SummaryLine(
                    id: "medication",
                    icon: "pills",
                    title: L("İlaç & Takviye", "Meds & supplements"),
                    value: "\(taken)/\(doses.count)",
                    detail: overdue.isEmpty
                        ? next.map { Lf("sıradaki %1$@", "next %1$@", $0.clock) }
                        : Lf("%1$d doz geçti", "%1$d doses missed", overdue.count),
                    progress: doses.isEmpty ? nil : Double(taken) / Double(doses.count),
                    tintHex: overdue.isEmpty ? "5BC48A" : "E8A04A",
                    target: DetailTarget(module: .fitness, item: "meds")
                )
            )
        }
        if settings.trackWorkout {
            let label = Workout.plan(settings.workoutPlan, on: now)
            let rest = Workout.isRestDay(label)
            let done = DailyLog.shared.isSet(Metric.workoutDone, on: now)
            lines.append(
                SummaryLine(
                    id: "workout",
                    icon: rest ? "figure.cooldown" : "figure.strengthtraining.traditional",
                    title: L("Antrenman", "Workout"),
                    value: rest ? L("Dinlenme", "Rest") : label,
                    detail: rest ? nil : (done ? L("tamamlandı", "done") : (workoutStreak > 1 ? Lf("%1$d antrenman seri", "%1$d-workout streak", workoutStreak) : L("bekliyor", "waiting"))),
                    progress: nil,
                    tintHex: done ? "5BC48A" : (rest ? nil : "E8A04A"),
                    target: DetailTarget(module: .fitness, item: "workout")
                )
            )
        }
        return lines
    }

    private var moneySummaryLines: [SummaryLine] {
        guard let next = upcomingSubscriptions.first else { return [] }
        let days = next.daysUntilRenewal(from: now)
        return [
            SummaryLine(
                id: "money.next",
                icon: "creditcard",
                title: L("Sıradaki ödeme", "Next payment"),
                value: "\(next.name) \(next.amountText)",
                detail: LInDays(days),
                progress: nil,
                tintHex: days <= 3 ? "E8A04A" : nil,
                target: DetailTarget(module: .money)
            )
        ]
    }

    private var downloaderSummaryLines: [SummaryLine] {
        guard case .running(let progress, _) = DownloadService.shared.state else { return [] }
        return [
            SummaryLine(
                id: "downloader",
                icon: "arrow.down.circle",
                title: L("İndiriliyor", "Downloading"),
                value: "\(Int(progress * 100))%",
                detail: nil,
                progress: progress,
                tintHex: "4AA8E8",
                target: nil
            )
        ]
    }

    // MARK: - İlaç

    /// Bugünün tüm dozları, saate göre sıralı.
    var todayDoses: [MedicationDose] {
        settings.medications
            .filter(\.enabled)
            .flatMap { med in med.times.map { MedicationDose(medication: med, minute: $0) } }
            .sorted { $0.minute < $1.minute }
    }

    func isDoseTaken(_ dose: MedicationDose) -> Bool {
        DailyLog.shared.isSet(dose.medication.metric(at: dose.minute), on: now)
    }

    func toggleDose(_ dose: MedicationDose) {
        DailyLog.shared.toggle(dose.medication.metric(at: dose.minute), on: now)
        objectWillChange.send()
    }

    func addMedication() {
        settings.medications.append(Medication(name: L("Yeni", "New"), times: [9 * 60]))
        Task { await refreshMedicationNotifications() }
    }

    func removeMedication(_ id: UUID) {
        settings.medications.removeAll { $0.id == id }
        Task { await refreshMedicationNotifications() }
    }

    func updateMedication(_ item: Medication) {
        if let index = settings.medications.firstIndex(where: { $0.id == item.id }) {
            var copy = item
            copy.times = Array(Set(item.times)).sorted()
            settings.medications[index] = copy
            Task { await refreshMedicationNotifications() }
        }
    }

    func refreshMedicationNotifications() async {
        guard settings.isModuleEnabled(.fitness), settings.trackMedication,
              settings.notifyMedication, !settings.medications.isEmpty else {
            await NotificationService.shared.cancel(prefix: MedicationAlerts.prefix)
            return
        }
        let alerts = MedicationAlerts.upcoming(doses: todayDoses, now: Date()) { [weak self] dose in
            self?.isDoseTaken(dose) ?? false
        }
        await NotificationService.shared.reschedule(prefix: MedicationAlerts.prefix, alerts: alerts)
    }

    /// Panonun görünen hâli. Gizlenen satırlar hem panodan hem gün özeti
    /// bildiriminden düşer: "panoda istemiyorum" demek "akşam da okumak
    /// istemiyorum" demektir.
    var todayLines: [SummaryLine] {
        guard !settings.hiddenSummaryLines.isEmpty else { return allTodayLines }
        let hidden = Set(settings.hiddenSummaryLines)
        return allTodayLines.filter { !hidden.contains($0.id) }
    }

    /// Panonun tamamı: açık modüllerin satırları + modüle bağlı olmayan ölçümler.
    var allTodayLines: [SummaryLine] {
        var lines: [SummaryLine] = dayCloseSummaryLines
        for module in modules where module.contributesToSummary {
            lines.append(contentsOf: summaryLines(for: module))
        }
        // İndirici bir pano modülü değil; yalnızca gerçekten çalışırken geçici durum verir.
        lines.append(contentsOf: downloaderSummaryLines)
        if settings.trackIntake {
            let water = DailyLog.shared.value(Metric.waterML, on: now)
            lines.append(
                SummaryLine(
                    id: "water",
                    icon: "drop",
                    title: L("Su", "Water"),
                    value: String(format: "%.1f / %.1f L", locale: Language.locale, water / 1000, settings.waterGoalML / 1000),
                    detail: nil,
                    progress: settings.waterGoalML > 0 ? min(water / settings.waterGoalML, 1) : nil,
                    tintHex: "4AA8E8",
                    target: DetailTarget(module: .fitness, item: "nutrition")
                )
            )
            let protein = DailyLog.shared.value(Metric.proteinG, on: now)
            lines.append(
                SummaryLine(
                    id: "protein",
                    icon: "fork.knife",
                    title: "Protein",
                    value: "\(Int(protein)) / \(Int(settings.proteinGoalG)) g",
                    detail: nil,
                    progress: settings.proteinGoalG > 0 ? min(protein / settings.proteinGoalG, 1) : nil,
                    tintHex: "E8A04A",
                    target: DetailTarget(module: .fitness, item: "nutrition")
                )
            )
        }
        return lines
    }

    /// Bugün dahil, beş vaktin tamamının kılındığı kesintisiz gün sayısı.
    var prayerStreak: Int {
        guard let day = prayers else { return 0 }
        let ids = day.times.filter { !$0.isSunnah }.map { Metric.prayer($0.id) }
        guard !ids.isEmpty else { return 0 }
        return DailyLog.shared.streak(on: now) { values in
            ids.allSatisfy { (values[$0] ?? 0) > 0 }
        }
    }

    /// Yenileme sırasına göre, en yakın önce.
    var upcomingSubscriptions: [Subscription] {
        settings.subscriptions
            .filter(\.enabled)
            .sorted { $0.nextRenewal(after: now) < $1.nextRenewal(after: now) }
    }

    /// Aylık toplam sabit gider, para birimi başına.
    var monthlyTotals: [(currency: String, amount: Double)] {
        var totals: [String: Double] = [:]
        for item in settings.subscriptions where item.enabled {
            totals[item.currency, default: 0] += item.monthlyEquivalent
        }
        return totals.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// Programda antrenman olan günlerin kaçırılmadan sürdüğü gün sayısı.
    /// Dinlenme günleri seriyi kırmaz, sayılmaz da.
    var workoutStreak: Int {
        let calendar = Calendar.current
        var count = 0
        var cursor = now
        // Bugün henüz yapılmadıysa seriyi dünden başlat.
        if !Workout.isRestDay(Workout.plan(settings.workoutPlan, on: cursor)),
           !DailyLog.shared.isSet(Metric.workoutDone, on: cursor) {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = previous
        }
        var guardCount = 0
        while guardCount < 365 {
            guardCount += 1
            let label = Workout.plan(settings.workoutPlan, on: cursor)
            if Workout.isRestDay(label) {
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = previous
                continue
            }
            guard DailyLog.shared.isSet(Metric.workoutDone, on: cursor) else { break }
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// Bu hafta tamamlanan antrenman sayısı ve programdaki toplam.
    var weeklyWorkoutProgress: (done: Int, planned: Int) {
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return (0, 0) }
        var done = 0, planned = 0
        var cursor = week.start
        while cursor < week.end {
            let label = Workout.plan(settings.workoutPlan, on: cursor)
            if !Workout.isRestDay(label) {
                planned += 1
                if DailyLog.shared.isSet(Metric.workoutDone, on: cursor) { done += 1 }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return (done, planned)
    }

    func toggleWorkoutDone() {
        DailyLog.shared.toggle(Metric.workoutDone, on: now)
        objectWillChange.send()
    }

    func addSubscription(_ item: Subscription) {
        settings.subscriptions.append(item)
        Task { await refreshRenewalNotifications() }
    }

    func removeSubscription(_ id: UUID) {
        settings.subscriptions.removeAll { $0.id == id }
        Task { await refreshRenewalNotifications() }
    }

    func updateSubscription(_ item: Subscription) {
        if let index = settings.subscriptions.firstIndex(where: { $0.id == item.id }) {
            settings.subscriptions[index] = item
            Task { await refreshRenewalNotifications() }
        }
    }

    func refreshRenewalNotifications() async {
        guard settings.isModuleEnabled(.money), settings.notifyRenewalDays > 0,
              !upcomingSubscriptions.isEmpty else {
            await NotificationService.shared.cancel(prefix: RenewalAlerts.prefix)
            return
        }
        let alerts = RenewalAlerts.upcoming(
            subscriptions: upcomingSubscriptions,
            daysBefore: settings.notifyRenewalDays,
            now: Date()
        )
        await NotificationService.shared.reschedule(prefix: RenewalAlerts.prefix, alerts: alerts)
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: now)
        let base: String
        switch hour {
        case 5..<11: base = L("Günaydın", "Good morning")
        case 11..<18: base = L("İyi günler", "Good afternoon")
        case 18..<22: base = L("İyi akşamlar", "Good evening")
        default: base = L("İyi geceler", "Good night")
        }
        let name = settings.displayName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? base : "\(base) \(name)"
    }

    func togglePrayerDone(_ prayer: PrayerTime) {
        DailyLog.shared.toggle(Metric.prayer(prayer.id), on: now)
        objectWillChange.send()
    }

    // MARK: - Gün sonu

    func dayCloseDates() -> [Date] {
        DayClose.dates(from: now)
    }

    var suggestedDayCloseDate: Date {
        DayClose.suggestedDate(from: dayCloseDates(), now: now) { dayClosePendingCount(on: $0) }
    }

    func dayCloseSections(on date: Date) -> [DayClose.Section] {
        var sections: [DayClose.Section] = []
        let calendar = Calendar.current
        let isToday = calendar.isDate(date, inSameDayAs: now)

        if settings.isModuleEnabled(.prayer), settings.trackPrayers {
            let items = DayClose.obligatoryPrayers.map { prayer in
                let time = prayers?.times.first { $0.id == prayer.id }?.time
                var due = true
                if isToday, let time {
                    due = time <= now
                }
                return DayClose.Item(
                    title: PrayerCopy.name(id: prayer.id),
                    detail: isToday ? time.map(TimeFormatters.clock) : nil,
                    metric: Metric.prayer(prayer.id),
                    due: due
                )
            }
            sections.append(
                DayClose.Section(
                    id: "prayer",
                    title: L("Namaz", "Prayer"),
                    icon: "moon.stars",
                    tintHex: "5BC48A",
                    items: items,
                    target: DetailTarget(module: .prayer)
                )
            )
        }

        if settings.isModuleEnabled(.fitness), settings.trackMedication {
            let doses = settings.medications
                .filter(\.enabled)
                .flatMap { med in med.times.map { MedicationDose(medication: med, minute: $0) } }
                .sorted { $0.minute < $1.minute }
            if !doses.isEmpty {
                sections.append(
                    DayClose.Section(
                        id: "meds",
                        title: L("İlaç & Takviye", "Meds & supplements"),
                        icon: "pills",
                        tintHex: "5BC48A",
                        items: doses.map { dose in
                            let extra = dose.medication.dose.trimmingCharacters(in: .whitespaces)
                            return DayClose.Item(
                                title: dose.medication.name,
                                detail: extra.isEmpty ? dose.clock : "\(dose.clock) · \(extra)",
                                metric: dose.id,
                                due: !isToday || dose.minute <= Medication.minute(from: now, calendar: calendar)
                            )
                        },
                        target: DetailTarget(module: .fitness, item: "meds")
                    )
                )
            }
        }

        if settings.isModuleEnabled(.fitness), settings.trackWorkout {
            let label = Workout.plan(settings.workoutPlan, on: date)
            if !Workout.isRestDay(label) {
                sections.append(
                    DayClose.Section(
                        id: "workout",
                        title: L("Antrenman", "Workout"),
                        icon: "figure.strengthtraining.traditional",
                        tintHex: "E8A04A",
                        items: [
                            DayClose.Item(title: label, detail: nil, metric: Metric.workoutDone, due: true)
                        ],
                        target: DetailTarget(module: .fitness, item: "workout")
                    )
                )
            }
        }

        return sections
    }

    func dayClosePendingCount(on date: Date) -> Int {
        dayCloseSections(on: date)
            .flatMap(\.items)
            .filter { $0.due && !DailyLog.shared.isSet($0.metric, on: date) }
            .count
    }

    func isDayCloseDone(_ item: DayClose.Item, on date: Date) -> Bool {
        DailyLog.shared.isSet(item.metric, on: date)
    }

    func toggleDayClose(_ item: DayClose.Item, on date: Date) {
        guard item.due else { return }
        DailyLog.shared.toggle(item.metric, on: date)
        objectWillChange.send()
        Task { await refreshDayCloseNotification() }
    }

    func markDayCloseRemaining(_ section: DayClose.Section, on date: Date) {
        for item in section.items where item.due && !DailyLog.shared.isSet(item.metric, on: date) {
            DailyLog.shared.set(item.metric, 1, on: date)
        }
        objectWillChange.send()
        Task { await refreshDayCloseNotification() }
    }

    /// Dünden kalan ya da akşam hâlâ açık işaretler. Gündüz bugünün eksiği normaldir,
    /// o yüzden bugün ancak akşam panoya düşer.
    private var dayCloseSummaryLines: [SummaryLine] {
        let dates = dayCloseDates()
        guard dates.contains(where: { !dayCloseSections(on: $0).isEmpty }) else { return [] }

        let calendar = Calendar.current
        let pastHits = dates
            .filter { !calendar.isDate($0, inSameDayAs: now) }
            .compactMap { date -> (Date, Int)? in
                let count = dayClosePendingCount(on: date)
                return count > 0 ? (date, count) : nil
            }
        let todayCount = dayClosePendingCount(on: calendar.startOfDay(for: now))
        let evening = calendar.component(.hour, from: now) >= 20

        let count: Int
        let detail: String
        if !pastHits.isEmpty {
            count = pastHits.reduce(0) { $0 + $1.1 }
            detail = pastHits.count == 1
                ? TimeFormatters.relativeDay(pastHits[0].0, now: now).lowercased()
                : Lf("%1$d gün", "%1$d days", pastHits.count)
        } else if evening, todayCount > 0 {
            count = todayCount
            detail = L("bugün", "today")
        } else {
            return []
        }

        return [
            SummaryLine(
                id: "dayclose",
                icon: "sunset",
                title: L("Gün sonu", "End of day"),
                value: Lf("%1$d açık", "%1$d open", count),
                detail: detail,
                progress: nil,
                tintHex: "E8A04A",
                target: DetailTarget(module: .today, item: "end"),
                catalogTitle: L("Gün sonu", "End of day")
            )
        ]
    }

    func isPrayerDone(_ prayer: PrayerTime) -> Bool {
        DailyLog.shared.isSet(Metric.prayer(prayer.id), on: now)
    }

    func adjustIntake(_ metric: String, _ delta: Double) {
        DailyLog.shared.add(metric, delta, on: now)
        objectWillChange.send()
    }

    /// Tüm açık modüllerin sayfaları, sekme sırasına göre.
    var allPages: [ModulePage] {
        modules.flatMap { pages(for: $0) }
    }

    /// Menü çubuğunda görünür kota kimlikleri (namaz hariç).
    var visibleQuotaIDs: [String] {
        guard settings.isModuleEnabled(.usage) else { return [] }
        var ids: [String] = []
        if settings.claudeEnabled { ids.append("claude") }
        if settings.codexEnabled { ids.append("codex") }
        if settings.grokEnabled { ids.append("grok") }
        ids.append(contentsOf: settings.customProviders.filter(\.enabled).map(\.id.uuidString))
        return ids.filter { settings.isMenuBarVisible($0) }
    }

    var menuBarIDs: [String] {
        var ids = visibleQuotaIDs
        // Toplu modda kotalar tek bir özet ikona iner; diğer modüller ayrı kalır.
        if settings.menuBarCollapsed, !ids.isEmpty {
            ids = [MenuBarSummary.id]
        }
        // Kota dışı modüllerin menü çubuğu ikonları.
        for module in modules where module != .usage {
            for page in pages(for: module) {
                guard let menuBarID = page.menuBarID, settings.isMenuBarVisible(menuBarID) else { continue }
                ids.append(menuBarID)
            }
        }
        return ids
    }

    /// Menü çubuğundaki bir ikona **tıklanınca** açılacak hedef.
    ///
    /// Özet ve genel ikon doğaları gereği panoya gider: ikisi de tek bir şeyi değil,
    /// genel durumu temsil eder. Belirli bir modül ikonu ise ayara bağlıdır —
    /// varsayılan panodur, ama "tıklanan öğe" seçilirse o modüle gider.
    /// Pano modülü kapalıysa her koşulda öğenin kendisine düşer.
    func clickTarget(forMenuBarID id: String) -> DetailTarget? {
        if id == MenuBarSummary.id && settings.menuBarClickOpens == .item { return target(forMenuBarID: id) }
        let generalIcon = id == BrandIcon.appItemID || id == MenuBarSummary.id
        // Pano kapalıysa herkes temsil ettiği şeye gider; özet ikon da
        // gösterdiği kotaya düşer, "son sekme"ye değil.
        guard settings.isModuleEnabled(.today) else {
            return target(forMenuBarID: id)
        }
        if generalIcon || settings.menuBarClickOpens == .today {
            return DetailTarget(module: .today)
        }
        return target(forMenuBarID: id)
    }

    /// Menü çubuğu kimliğinden **temsil ettiği** hedefe. Modül kaydından türetilir.
    func target(forMenuBarID id: String) -> DetailTarget? {
        if id == MenuBarSummary.id {
            return rotatingQuota.map { DetailTarget(module: .usage, item: $0.id) }
        }
        if id == BrandIcon.appItemID { return nil }
        for module in modules {
            if let page = pages(for: module).first(where: { $0.menuBarID == id }) {
                return page.target
            }
        }
        // Kota henüz yüklenmemiş olabilir; kullanıcı yine de o sekmeyi görsün.
        return DetailTarget(module: .usage, item: id)
    }

    /// Özet ikonun temsil ettiği kota: **en çok yeri kalan** sağlayıcı.
    /// Dolmuş bir kotayı göstermenin pratik faydası yok; kullanılabilir olanı öne çıkarır.
    var summaryQuota: QuotaGroup? {
        let visible = Set(visibleQuotaIDs)
        let candidates = quotas.filter { visible.contains($0.id) }
        // Yalnızca gerçekten kullanılabilir olanlar: oturumu sağlam ve ölçülebilir yüzdesi olan.
        let usable = candidates.filter { $0.status == .ready && $0.headlinePercent != nil }
        if let best = usable.min(by: { ($0.headlinePercent ?? 1) < ($1.headlinePercent ?? 1) }) {
            return best
        }
        // Ölçülebilir yüzdesi olan kota yoksa çalışan herhangi biri, o da yoksa ilk kota.
        return candidates.first { $0.status == .ready } ?? candidates.first
    }

    /// Modülü açar/kapatır. Son açık modül kapatılamaz; kapatınca seçim düzeltilir.
    func setModule(_ module: ModuleKind, enabled: Bool) {
        guard module.canDisable else { return }
        var disabled = settings.disabledModules
        if enabled {
            disabled.removeAll { $0 == module.rawValue }
        } else {
            guard modules.count > 1 else { return }
            if !disabled.contains(module.rawValue) { disabled.append(module.rawValue) }
        }
        settings.disabledModules = disabled
        reconcileSelection()
        if module == .focus { applyFocusTracking() }
        Task { await refresh() }
    }

    func applyModules(_ enabled: Set<ModuleKind>) {
        settings.disabledModules = ModuleKind.dashboardCases
            .filter { $0.canDisable && !enabled.contains($0) }.map(\.rawValue)
        reconcileSelection()
        applyFocusTracking()
        Task { await refresh() }
    }

    func moveModule(_ module: ModuleKind, by offset: Int) {
        var order = settings.orderedModules
        guard let index = order.firstIndex(of: module), order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
        settings.moduleOrder = order.map(\.rawValue)
    }

    func isMenuBarVisible(_ id: String) -> Bool {
        settings.isMenuBarVisible(id)
    }

    func setMenuBarVisible(_ id: String, _ visible: Bool) {
        var shown = settings.menuBarVisible
        if visible {
            if !shown.contains(id) { shown.append(id) }
        } else {
            shown.removeAll { $0 == id }
        }
        settings.menuBarVisible = shown
    }

    func select(_ target: DetailTarget) {
        hoverCollapseWork?.cancel()
        selection = target
        persistSelection(target)
        setExpanded(true)
    }

    func restoreSelection() {
        hoverCollapseWork?.cancel()
        selection = resolvedRememberedTarget()
        setExpanded(true)
    }

    /// Menü çubuğunda tıklanan öğenin kendi detayını açar.
    /// Genel ikon (`app`) hiçbir öğe görünür değilken durur; onda son sekmeye dönülür.
    func focus(menuBarID id: String) {
        boardToken += 1
        if let target = clickTarget(forMenuBarID: id) {
            select(target)
        } else {
            restoreSelection()
        }
    }

    var selectedModule: ModuleKind {
        selection?.module ?? modules.first ?? .usage
    }

    /// Sekmeye tıklanınca o modülün en uygun sayfası açılır:
    /// modülde son bakılan sayfa varsa o, yoksa ilk sayfa.
    func selectModule(_ module: ModuleKind) {
        guard selection?.module != module else { return }
        let available = pages(for: module)
        if let remembered = lastPageByModule[module.rawValue],
           available.contains(where: { $0.item == remembered }) {
            select(DetailTarget(module: module, item: remembered))
        } else if let first = available.first {
            select(first.target)
        } else {
            select(DetailTarget(module: module))
        }
    }

    var prayerProgress: Double {
        guard let prayers, let next = nextPrayer else { return 0 }
        let times = prayers.times.filter { settings.showSunrise || !$0.isSunnah }.map(\.time)
        guard let index = times.firstIndex(of: next.time) else { return 0 }
        let previous = index == 0 ? times.last!.addingTimeInterval(-24 * 3600) : times[index - 1]
        let span = next.time.timeIntervalSince(previous)
        guard span > 0 else { return 0 }
        return min(max(now.timeIntervalSince(previous) / span, 0), 1)
    }

    func bootstrap() async {
        if settings.isModuleEnabled(.prayer) { await loadPlaces() }
        await refresh()
    }

    func refresh() async {
        refreshing = true
        defer { refreshing = false }
        async let quotaTask: [QuotaGroup] = settings.isModuleEnabled(.usage)
            ? UsageService.loadGroups(settings: settings) : []
        async let prayerTask: PrayerDay? = settings.isModuleEnabled(.prayer)
            ? fetchPrayers() : nil
        let freshQuotas = await quotaTask
        let freshPrayers = await prayerTask
        // Bildirimleri yeni veriyi yayımlamadan önce hesapla: karşılaştırma bir
        // önceki duruma göre yapılıyor.
        await emitQuotaAlerts(for: freshQuotas)
        quotas = freshQuotas
        prayers = freshPrayers
        if settings.isModuleEnabled(.calendar) {
            CalendarService.shared.reload(now: Date())
        }
        reconcileSelection()
        recordSummaryCatalog()
        await refreshPrayerNotifications()
        await refreshDailySummaryNotification()
        await refreshDayCloseNotification()
        await refreshRenewalNotifications()
        await refreshMedicationNotifications()
    }

    // MARK: - Bildirimler

    private func emitQuotaAlerts(for groups: [QuotaGroup]) async {
        let snapshot = QuotaAlerts.snapshot(groups)
        defer { quotaSnapshot = snapshot }
        guard settings.notifyQuotaReset || settings.notifyQuotaThreshold else { return }
        let alerts = QuotaAlerts.diff(
            previous: quotaSnapshot,
            groups: groups,
            notifyReset: settings.notifyQuotaReset,
            notifyThreshold: settings.notifyQuotaThreshold,
            threshold: Double(settings.notifyQuotaThresholdPercent) / 100
        )
        for alert in alerts {
            await NotificationService.shared.post(alert)
        }
    }

    /// Vakit bildirimleri planlıdır; her yenilemede sil-yeniden kurulur,
    /// böylece konum ya da ayar değişince kendiliğinden düzelir.
    func refreshPrayerNotifications() async {
        guard settings.isModuleEnabled(.prayer), settings.notifyPrayer, let prayers else {
            await NotificationService.shared.cancel(prefix: PrayerAlerts.prefix)
            return
        }
        let alerts = PrayerAlerts.upcoming(
            day: prayers,
            now: Date(),
            minutesBefore: settings.notifyPrayerMinutes,
            includeSunrise: settings.showSunrise
        )
        await NotificationService.shared.reschedule(prefix: PrayerAlerts.prefix, alerts: alerts)
    }

    func refreshDailySummaryNotification() async {
        guard settings.notifyDailySummary,
              let alert = DailySummaryAlerts.alert(hour: settings.dailySummaryHour, lines: todayLines, now: Date()) else {
            await NotificationService.shared.cancel(prefix: DailySummaryAlerts.prefix)
            return
        }
        await NotificationService.shared.reschedule(prefix: DailySummaryAlerts.prefix, alerts: [alert])
    }

    func refreshDayCloseNotification() async {
        guard settings.notifyDayClose,
              let alert = DayCloseAlerts.alert(
                hour: settings.dayCloseHour,
                pending: dayCloseDates().reduce(0) { $0 + dayClosePendingCount(on: $1) }
              ) else {
            await NotificationService.shared.cancel(prefix: DayCloseAlerts.prefix)
            return
        }
        await NotificationService.shared.reschedule(prefix: DayCloseAlerts.prefix, alerts: [alert])
    }

    /// Ayarlardan bir bildirim açıldığında izni o an ister.
    func notificationsChanged() {
        NotificationService.shared.resetAuthorizationCache()
        Task {
            if settings.anyNotificationEnabled {
                _ = await NotificationService.shared.ensureAuthorized()
            }
            await refreshPrayerNotifications()
            await refreshDailySummaryNotification()
            await refreshDayCloseNotification()
        }
    }

    // MARK: - Pano satırı seçimi

    /// Bir satırı panoda göster/gizle.
    func setSummaryLine(_ id: String, visible: Bool) {
        var hidden = settings.hiddenSummaryLines
        if visible {
            hidden.removeAll { $0 == id }
        } else if !hidden.contains(id) {
            hidden.append(id)
        }
        settings.hiddenSummaryLines = hidden
        Task { await refreshDailySummaryNotification() }
    }

    func isSummaryLineVisible(_ id: String) -> Bool {
        !settings.hiddenSummaryLines.contains(id)
    }

    /// Görülen satırları kataloğa işler, kapalı modüllerin satırlarını düşürür.
    /// Görünürde olmayan satır da listede kalır — "Dolu kota" ancak kota dolunca
    /// üretiliyor, gizleme şansı yalnızca o ana sıkışmamalı.
    func recordSummaryCatalog() {
        var known = summaryCatalog.filter { settings.isModuleEnabled($0.module) }
        known.removeAll { $0.id == "quran" || $0.id == "dua" }
        for line in allTodayLines {
            // Kalıcı olmayan satırlar (indirme ilerlemesi) kataloğa girmez.
            guard let module = line.target?.module else { continue }
            let title = line.catalogTitle ?? line.title
            if let index = known.firstIndex(where: { $0.id == line.id }) {
                known[index].title = title
            } else {
                known.append(SummaryLineRef(id: line.id, title: title, module: module))
            }
        }
        // Modül sırasına göre, modül içinde ilk görülme sırası korunarak.
        // Swift'in `sort`'u kararlı değil; sırayı indeksle kendimiz taşıyoruz.
        let order = settings.orderedModules
        known = known.enumerated().sorted { left, right in
            let l = order.firstIndex(of: left.element.module) ?? order.count
            let r = order.firstIndex(of: right.element.module) ?? order.count
            return l == r ? left.offset < right.offset : l < r
        }.map(\.element)
        guard known != summaryCatalog else { return }
        summaryCatalog = known
        if let data = try? JSONEncoder().encode(known) {
            UserDefaults.standard.set(data, forKey: Self.summaryCatalogKey)
        }
    }

    /// Yenilemeden sonra seçili sekmeyi korur; yalnızca artık var olmayan bir hedef
    /// seçiliyse hatırlanan hedefe döner.
    func reconcileSelection() {
        if let selection, settings.isModuleEnabled(selection.module) {
            let pages = allPages
            if pages.isEmpty || pages.contains(where: { $0.target == selection }) { return }
        }
        selection = resolvedRememberedTarget()
    }

    func fetchPrayers() async -> PrayerDay? {
        guard settings.hasLocation else {
            lastError = nil
            return nil
        }
        do {
            return try await PrayerService.fetch(settings: settings, now: now)
        } catch {
            lastError = error.localizedDescription
            return prayers
        }
    }

    func loadPlaces() async {
        countries = await LocationService.shared.countries()
        let code = settings.countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            regions = []
            cities = []
            return
        }
        let country = countries.first(where: { $0.code == code })
            ?? PlaceCountry(name: settings.country.isEmpty ? code : settings.country, code: code)
        regions = await LocationService.shared.regions(for: country)
        if let region = regions.first(where: { $0.name == settings.state }) {
            cities = await LocationService.shared.cities(country: country, region: region)
        } else {
            cities = []
        }
    }

    func clearLocation() {
        settings.country = ""
        settings.countryCode = ""
        settings.state = ""
        settings.city = ""
        settings.latitude = 0
        settings.longitude = 0
        regions = []
        cities = []
        prayers = nil
        lastError = nil
        Task { await refresh() }
    }

    func selectCountry(_ country: PlaceCountry) {
        settings.country = country.name
        settings.countryCode = country.code
        let rec = CalculationMethods.recommended(for: country.code)
        settings.method = rec.method
        settings.school = rec.school
        settings.state = ""
        settings.city = ""
        Task {
            regions = await LocationService.shared.regions(for: country)
            cities = []
            if let first = regions.first {
                await selectRegion(first)
            }
        }
    }

    func selectRegion(_ region: PlaceRegion) async {
        settings.state = region.name
        let country = PlaceCountry(name: settings.country, code: settings.countryCode)
        cities = await LocationService.shared.cities(country: country, region: region)
        if let first = cities.first {
            await selectCity(first)
        } else if let lat = region.latitude, let lon = region.longitude {
            settings.latitude = lat
            settings.longitude = lon
            settings.city = region.name
            await refresh()
        }
    }

    func selectCity(_ city: PlaceCity) async {
        settings.city = city.name
        let country = PlaceCountry(name: settings.country, code: settings.countryCode)
        let region = PlaceRegion(name: settings.state, latitude: nil, longitude: nil)
        if let coords = await LocationService.shared.coordinates(country: country, region: region, city: city) {
            settings.latitude = coords.0
            settings.longitude = coords.1
        } else if let geo = await LocationService.shared.geocode(country: settings.country, state: settings.state, city: city.name) {
            settings.latitude = geo.0
            settings.longitude = geo.1
        }
        await refresh()
    }

    func searchCities(_ query: String) {
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard cityQuery == query else { return }
            cityResults = await LocationService.shared.searchCities(query: query, countryCode: settings.countryCode)
        }
    }

    func toggle(_ kind: ProviderKind, enabled: Bool) {
        switch kind {
        case .claude: settings.claudeEnabled = enabled
        case .codex: settings.codexEnabled = enabled
        case .grok: settings.grokEnabled = enabled
        case .custom: break
        }
        Task { await refresh() }
    }

    func addProvider(_ provider: CustomProvider) {
        settings.customProviders.append(provider)
        Task { await refresh() }
    }

    func removeProvider(_ id: UUID) {
        settings.customProviders.removeAll { $0.id == id }
        Task { await refresh() }
    }

    func updateProvider(_ provider: CustomProvider) {
        if let index = settings.customProviders.firstIndex(where: { $0.id == provider.id }) {
            settings.customProviders[index] = provider
            Task { await refresh() }
        }
    }

    func expand() {
        restoreSelection()
    }

    func requestCollapse() {
        guard !pinned, !isDragging else { return }
        hoverCollapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.pinned, !self.isDragging else { return }
            self.setExpanded(false)
        }
        hoverCollapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    func collapseImmediate() {
        hoverCollapseWork?.cancel()
        setExpanded(false)
    }

    /// Sabitleme: detay penceresi dışarı tıklayınca kapanmaz, açık kalır.
    /// Tercih kalıcıdır ve seçili sekmeyi değiştirmez.
    func togglePinned() {
        pinned.toggle()
    }

    func setCleaningMode(_ on: Bool) {
        let result = DeviceModes.shared.setCleaning(
            on,
            copy: DeviceModes.CleaningCopy(
                title: settings.resolvedCleaningTitle,
                hint: settings.resolvedCleaningHint,
                buttonTitle: settings.resolvedCleaningButtonTitle
            )
        )
        cleaningMode = result.active
        cleaningMessage = result.message
        lastError = result.active ? nil : result.message
    }

    func setAlwaysWake(_ on: Bool) {
        var next = settings
        next.alwaysWake = on
        if !on { next.wakeUntil = nil }
        settings = next
    }

    private static func wakeSignature(_ settings: AppSettings) -> String {
        [
            settings.alwaysWake ? "1" : "0",
            settings.wakeIndefinite ? "1" : "0",
            settings.wakeTimerEnabled ? "1" : "0",
            String(settings.wakeTimerMinutes),
            settings.wakeUntil.map { String($0.timeIntervalSince1970) } ?? "-",
            settings.wakeWhileApps ? "1" : "0",
            settings.wakeWhilePowerOrDisplay ? "1" : "0",
            settings.wakeWhileLidClosed ? "1" : "0",
            settings.focusApps.joined(separator: ",")
        ].joined(separator: "|")
    }

    func applyFocusTracking() {
        FocusTracker.shared.start(
            apps: settings.focusApps,
            enabled: settings.isModuleEnabled(.focus) && settings.focusTracking
        )
    }

    func applyPersistedModes() {
        applyFocusTracking()
        WakeController.shared.apply(settings)
        VolumeMixer.shared.restore()
        WindowSwitcher.shared.apply(settings.switcher)
        DisplayController.shared.apply(enabled: settings.displayControlsEnabled)
        cleaningMode = false
        DeviceModes.shared.setCleaning(false)
    }

    func applyLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if settings.launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = Lf("Açılışta başlatma: %1$@", "Launch at login: %1$@", error.localizedDescription)
        }
    }

    private func setExpanded(_ value: Bool) {
        guard expanded != value else { return }
        expanded = value
        startTick()
    }

    private func startTick() {
        tickTimer?.invalidate()
        let interval: TimeInterval = expanded ? 1 : 20
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
            }
        }
        timer.tolerance = expanded ? 0.2 : 5
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "hal.settings")
        }
    }

    private func persistSelection(_ target: DetailTarget) {
        lastPageByModule[target.module.rawValue] = target.item
        UserDefaults.standard.set(lastPageByModule.compactMapValues { $0 }, forKey: Self.lastPageKey)
        UserDefaults.standard.set(target.id, forKey: Self.lastTargetKey)
        if target.module == .usage, let item = target.item {
            lastQuotaID = item
        }
    }

    /// Hatırlanan hedef hâlâ geçerli mi? Değilse açık modüllerin ilk sayfasına düşer.
    private func resolvedRememberedTarget() -> DetailTarget {
        let pages = allPages
        if let stored = UserDefaults.standard.string(forKey: Self.lastTargetKey),
           let target = DetailTarget(id: stored),
           settings.isModuleEnabled(target.module) {
            // Sayfalar henüz yüklenmediyse hedefi olduğu gibi koru.
            if pages.isEmpty || pages.contains(where: { $0.target == target }) {
                return target
            }
            // Modül duruyor ama o sayfa yok: modülün ilk sayfası.
            if let first = pages.first(where: { $0.module == target.module }) {
                return first.target
            }
        }
        return pages.first?.target ?? DetailTarget(module: modules.first ?? .usage)
    }

    private static let lastTargetKey = "hal.lastTarget"
    private static let lastPageKey = "hal.lastPageByModule"

    private static func loadRememberedTarget() -> DetailTarget? {
        if let stored = UserDefaults.standard.string(forKey: lastTargetKey) {
            // Eski sürümler "prayer" ya da düz kota kimliği yazıyordu; DetailTarget çözer.
            return DetailTarget(id: stored)
        }
        if let last = UserDefaults.standard.string(forKey: "hal.lastQuota") {
            return DetailTarget(module: .usage, item: last)
        }
        return nil
    }

    private static let summaryCatalogKey = "hal.summaryCatalog"

    private static func loadSummaryCatalog() -> [SummaryLineRef] {
        guard let data = UserDefaults.standard.data(forKey: summaryCatalogKey),
              let decoded = try? JSONDecoder().decode([SummaryLineRef].self, from: data) else { return [] }
        return decoded.filter { $0.id != "quran" && $0.id != "dua" }
    }

    private static func loadLastPages() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: lastPageKey) as? [String: String] ?? [:]
    }

    private static func loadSettings() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: "hal.settings"),
              var decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        decoded.fxEnabled = false
        return decoded
    }
}
