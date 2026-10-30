import AppKit
import SwiftUI

/// Odak, geçmiş ve sağlık sayfaları ana popover'ın gezinme kabuğundan bağımsızdır.
/// Böylece kişisel modüller büyürken `MenuBarView` tek bir dev görünüm hâline gelmez.
struct FocusModuleView: View {
    @EnvironmentObject private var store: AppStore

    private var today: Double { DailyLog.shared.value(Metric.focusSeconds, on: store.now) }
    private var goal: Double { Double(store.settings.focusGoalMinutes * 60) }
    private var days: [(date: Date, seconds: Double)] { history(metric: Metric.focusSeconds) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(TimeFormatters.duration(today))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                if goal > 0 {
                    Text("/ \(TimeFormatters.duration(goal))")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }

            if goal > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(Color(hex: "7C5CFF"))
                            .frame(width: max(4, geo.size.width * min(today / goal, 1)))
                    }
                }
                .frame(height: 6)
            }

            HStack(spacing: 7) {
                Image(systemName: FocusTracker.shared.currentApp == nil ? "pause.circle" : "scope")
                    .foregroundStyle(Color(hex: "7C5CFF"))
                Text(FocusTracker.shared.currentApp.map { Lf("Şu an %1$@ sayılıyor", "Counting %1$@ now", $0) }
                    ?? L("Şu an odak sayılmıyor", "Not counting focus right now"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            SevenDayBars(
                title: L("Son 7 gün", "Last 7 days"),
                values: days.map { $0.seconds },
                labels: days.map { TimeFormatters.weekdayInitial($0.date) },
                target: max(goal, days.map(\.seconds).max() ?? 1),
                tint: Color(hex: "7C5CFF")
            )

            let weekly = days.reduce(0) { $0 + $1.seconds }
            let best = days.max { $0.seconds < $1.seconds }
            HStack {
                metric(L("Bu hafta", "This week"), TimeFormatters.duration(weekly))
                Spacer()
                metric(L("En iyi gün", "Best day"), best.map {
                    "\(TimeFormatters.weekdayInitial($0.date)) · \(TimeFormatters.duration($0.seconds))"
                } ?? "—")
            }
        }
    }

    private func history(metric: String) -> [(date: Date, seconds: Double)] {
        (0..<7).reversed().compactMap { back in
            Calendar.current.date(byAdding: .day, value: -back, to: store.now).map {
                ($0, DailyLog.shared.value(metric, on: $0))
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 12, weight: .medium))
        }
    }
}

struct WeeklyInsightsView: View {
    @EnvironmentObject private var store: AppStore

    private var dates: [Date] {
        (0..<7).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: store.now) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Son yedi gün", "Last seven days"))
                .font(.system(size: 15, weight: .semibold))

            if store.settings.isModuleEnabled(.focus), store.settings.focusTracking {
                insightRow(
                    icon: "scope", title: L("Derin çalışma", "Deep work"),
                    value: TimeFormatters.duration(dates.reduce(0) { $0 + DailyLog.shared.value(Metric.focusSeconds, on: $1) }),
                    detail: Lf("günlük ortalama %1$@", "daily average %1$@", TimeFormatters.duration(focusAverage)), tint: "7C5CFF"
                )
            }

            if store.settings.isModuleEnabled(.fitness), store.settings.trackWorkout {
                let count = dates.filter { DailyLog.shared.isSet(Metric.workoutDone, on: $0) }.count
                insightRow(icon: "figure.strengthtraining.traditional", title: L("Antrenman", "Workout"),
                           value: Lf("%1$d gün", "%1$d days", count),
                           detail: store.workoutStreak > 1 ? Lf("%1$d antrenman seri", "%1$d-workout streak", store.workoutStreak) : nil,
                           tint: "E8A04A")
            }

            if store.settings.isModuleEnabled(.prayer), store.settings.trackPrayers, let prayerDay = store.prayers {
                let metrics = prayerDay.times.filter { !$0.isSunnah }.map { Metric.prayer($0.id) }
                let complete = dates.filter { date in metrics.allSatisfy { DailyLog.shared.isSet($0, on: date) } }.count
                insightRow(icon: "moon.stars", title: L("Beş vakit", "Five prayers"), value: Lf("%1$d gün", "%1$d days", complete),
                           detail: store.prayerStreak > 1 ? Lf("%1$d gün seri", "%1$d-day streak", store.prayerStreak) : nil, tint: "5BC48A")
            }

            if store.settings.isModuleEnabled(.fitness), store.settings.trackIntake {
                let waterDays = dates.filter { DailyLog.shared.value(Metric.waterML, on: $0) >= store.settings.waterGoalML }.count
                let proteinDays = dates.filter { DailyLog.shared.value(Metric.proteinG, on: $0) >= store.settings.proteinGoalG }.count
                insightRow(icon: "fork.knife", title: L("Beslenme hedefi", "Nutrition goal"),
                           value: Lf("Su %1$d/7", "Water %1$d/7", waterDays),
                           detail: Lf("Protein %1$d/7", "Protein %1$d/7", proteinDays), tint: "4AA8E8")
            }
        }
    }

    private var focusAverage: Double {
        guard !dates.isEmpty else { return 0 }
        return dates.reduce(0) { $0 + DailyLog.shared.value(Metric.focusSeconds, on: $1) } / Double(dates.count)
    }

    private func insightRow(icon: String, title: String, value: String, detail: String?, tint: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(Color(hex: tint)).frame(width: 16)
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium))
            if let detail { Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary) }
        }
        .padding(.vertical, 4)
    }
}

/// Bilgisayara geçilmeyen günlerin namaz, ilaç/takviye ve antrenman işaretleri.
/// Kendi verisi yok; seçilen güne mevcut günlük kaydı yazar.
struct DayCloseView: View {
    @EnvironmentObject private var store: AppStore
    @State private var picked: Date?

    private var date: Date { picked ?? store.suggestedDayCloseDate }

    var body: some View {
        let dates = store.dayCloseDates()
        let sections = store.dayCloseSections(on: date)
        VStack(alignment: .leading, spacing: 12) {
            dateChips(dates)
            if sections.isEmpty {
                Text(L("İşaretlenecek bir şey yok. Namaz veya ilaç/takviye takibini Ayarlar’dan aç.",
                       "Nothing to mark. Turn on prayer or meds & supplements tracking in Settings."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(Lf(
                    "Dışarıdayken kıldığın namazı, aldığın ilaç veya takviyeyi burada işaretle. Son %1$d gün.",
                    "Mark prayers you prayed and meds or supplements you took while away. Last %1$d days.",
                    DayClose.lookbackDays
                ))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(sections) { section in
                    sectionBlock(section)
                }
            }
        }
    }

    private func dateChips(_ dates: [Date]) -> some View {
        HStack(spacing: 6) {
            ForEach(dates, id: \.self) { day in
                let on = Calendar.current.isDate(day, inSameDayAs: date)
                let pending = store.dayClosePendingCount(on: day)
                Button {
                    picked = day
                } label: {
                    HStack(spacing: 4) {
                        Text(TimeFormatters.relativeDay(day, now: store.now))
                            .font(.system(size: 11, weight: .medium))
                        if pending > 0 {
                            Text("\(pending)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color(hex: "E8A04A"))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        on ? Color.primary.opacity(0.12) : Color.primary.opacity(0.05),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func sectionBlock(_ section: DayClose.Section) -> some View {
        let remaining = section.items.filter { $0.due && !store.isDayCloseDone($0, on: date) }.count
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: section.tintHex))
                    .frame(width: 14)
                Text(section.title)
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 6)
                if remaining > 0 {
                    Button(remaining == 1
                           ? L("Kalanı işaretle", "Mark remaining")
                           : L("Kalanları işaretle", "Mark remaining")) {
                        store.markDayCloseRemaining(section, on: date)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(hex: section.tintHex))
                    .buttonStyle(.plain)
                }
            }
            VStack(spacing: 1) {
                ForEach(section.items) { item in
                    row(item, tint: section.tintHex)
                }
            }
        }
    }

    private func row(_ item: DayClose.Item, tint: String) -> some View {
        let done = store.isDayCloseDone(item, on: date)
        return Button {
            store.toggleDayClose(item, on: date)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(
                        done ? Color(hex: tint)
                             : (item.due ? Color.secondary.opacity(0.5) : Color.secondary.opacity(0.28))
                    )
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title)
                        .font(.system(size: 12))
                        .foregroundStyle(done || !item.due ? Color.secondary : Color.primary)
                        .strikethrough(done, color: .secondary)
                    if let detail = item.detail {
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
                if !item.due, !done {
                    Text(L("bekliyor", "waiting"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .disabled(!item.due)
    }
}

struct HealthOverviewView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !store.settings.trackWorkout && !store.settings.trackMedication && !store.settings.trackIntake {
                Text(L("Antrenman, ilaç/takviye veya beslenme takibini Ayarlar > Sağlık’tan aç.",
                       "Turn on workout, meds & supplements, or nutrition tracking in Settings > Health."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if store.settings.trackWorkout {
                let plan = Workout.plan(store.settings.workoutPlan, on: store.now)
                let rest = Workout.isRestDay(plan)
                statusRow("figure.strengthtraining.traditional", L("Antrenman", "Workout"),
                          rest ? L("Dinlenme", "Rest") : plan,
                          DailyLog.shared.isSet(Metric.workoutDone, on: store.now) ? L("tamamlandı", "done") : nil, "E8A04A")
            }
            if store.settings.trackMedication, !store.todayDoses.isEmpty {
                let taken = store.todayDoses.filter { store.isDoseTaken($0) }.count
                statusRow("pills", L("İlaç & Takviye", "Meds & supplements"),
                          Lf("%1$d/%2$d doz", "%1$d/%2$d doses", taken, store.todayDoses.count), nil, "5BC48A")
            }
            if store.settings.trackIntake {
                statusRow("drop", L("Su", "Water"), liters(DailyLog.shared.value(Metric.waterML, on: store.now)),
                          Lf("hedef %1$@", "goal %1$@", liters(store.settings.waterGoalML)), "4AA8E8")
                statusRow("fork.knife", "Protein", "\(Int(DailyLog.shared.value(Metric.proteinG, on: store.now))) g",
                          Lf("hedef %1$d g", "goal %1$d g", Int(store.settings.proteinGoalG)), "E8A04A")
            }
        }
    }

    private func liters(_ ml: Double) -> String { String(format: "%.1f L", locale: Language.locale, ml / 1000) }

    private func statusRow(_ icon: String, _ title: String, _ value: String, _ detail: String?, _ tint: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(Color(hex: tint)).frame(width: 16)
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium))
            if let detail { Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary) }
        }
        .padding(.vertical, 4)
    }
}

struct NutritionView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            nutrient(L("Su", "Water"), metric: Metric.waterML, goal: store.settings.waterGoalML,
                     unit: "ml", step: store.settings.waterStepML, tint: "4AA8E8")
            nutrient("Protein", metric: Metric.proteinG, goal: store.settings.proteinGoalG,
                     unit: "g", step: store.settings.proteinStepG, tint: "E8A04A")
        }
    }

    private func nutrient(_ title: String, metric: String, goal: Double, unit: String, step: Double, tint: String) -> some View {
        let value = DailyLog.shared.value(metric, on: store.now)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(Int(value)) / \(Int(goal)) \(unit)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(Color(hex: tint)).frame(width: goal > 0 ? max(4, geo.size.width * min(value / goal, 1)) : 0)
                }
            }.frame(height: 5)
            HStack(spacing: 6) {
                smallButton("+\(Int(step)) \(unit)", tint: tint) { store.adjustIntake(metric, step) }
                smallButton("−\(Int(step))", tint: tint) { store.adjustIntake(metric, -step) }
                Spacer()
            }
        }
    }

    private func smallButton(_ title: String, tint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(hex: tint).opacity(0.18), in: Capsule())
        }.buttonStyle(.plain)
    }
}

struct SevenDayBars: View {
    var title: String
    var values: [Double]
    var labels: [String]
    var target: Double
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10)).foregroundStyle(.tertiary)
            HStack(alignment: .bottom, spacing: 7) {
                ForEach(values.indices, id: \.self) { index in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(values[index] > 0 ? tint : Color.primary.opacity(0.12))
                            .frame(height: max(3, min(values[index] / max(target, 1), 1) * 38))
                        Text(labels.indices.contains(index) ? labels[index] : "")
                            .font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 54, alignment: .bottom)
        }
    }
}

/// İndirici pano sekmesi değil; Ayarlar > Araçlar’da durur, sağ tık menüsünden de açılır.
struct DownloaderUtilityView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Video indir", "Download video")).font(.system(size: 18, weight: .semibold))
            DownloaderForm(showsFolder: true)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(minWidth: 420, minHeight: 260)
    }
}

struct DownloaderForm: View {
    @EnvironmentObject private var store: AppStore
    @State private var link = ""
    @ObservedObject private var service = DownloadService.shared
    var showsFolder: Bool = false

    var body: some View {
        let tools = DownloadService.tools()
        VStack(alignment: .leading, spacing: 10) {
            if !tools.ready {
                Text(Lf("%1$@ bulunamadı.", "%1$@ not found.", tools.missing.joined(separator: L(" ve ", " and "))))
                    .fixedSize(horizontal: false, vertical: true)
                Text("brew install \(tools.missing.joined(separator: " "))")
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    TextField(L("Video bağlantısı", "Video link"), text: $link).onSubmit(start)
                    Button { link = NSPasteboard.general.string(forType: .string) ?? "" } label: {
                        Image(systemName: "doc.on.clipboard")
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .help(L("Panodan yapıştır", "Paste from clipboard"))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Biçim", "Format"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Picker(L("Biçim", "Format"), selection: $store.settings.downloadFormat) {
                        ForEach(DownloadService.Format.allCases) { format in
                            Text(format == .mp3 ? "MP3" : "MP4").tag(format)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    Text(store.settings.downloadFormat == .mp3
                         ? L("Yüksek kalite ses", "High quality audio")
                         : L("En iyi video", "Best video"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if showsFolder {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(store.settings.downloadDestination.path)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(L("Değiştir", "Change"), action: chooseFolder)
                            .controlSize(.small)
                            .fixedSize()
                    }
                }
                stateView
                if !service.isRunning {
                    Button(action: start) {
                        Label(L("İndir", "Download"), systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var stateView: some View {
        switch service.state {
        case .running(let progress, let note):
            VStack(alignment: .leading) {
                ProgressView(value: progress)
                Text(note).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                Button(L("İptal", "Cancel")) { service.cancel() }
            }
        case .updating(let note): ProgressView(note)
        case .finished(let path):
            Button(L("Tamamlandı · Finder’da göster", "Done · Show in Finder")) { service.revealInFinder(path) }
        case .failed(let reason): Text(reason).foregroundStyle(.red)
        case .cancelled: Text(L("İptal edildi.", "Cancelled.")).foregroundStyle(.secondary)
        case .idle: EmptyView()
        }
    }

    private func start() {
        service.startManaged(link: link, format: store.settings.downloadFormat,
                             destination: store.settings.downloadDestination,
                             autoUpdate: store.settings.downloaderAutoUpdate)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = store.settings.downloadDestination
        if panel.runModal() == .OK, let url = panel.url { store.settings.downloadFolder = url.path }
    }
}
