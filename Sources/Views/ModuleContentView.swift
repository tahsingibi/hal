import AppKit
import SwiftUI

/// A tab the panel adds to a module's own tab row.
struct HostPage {
    let id: String
    let title: String
    let content: AnyView
}

/// One module's content, embedded in a panel section. The panel owns the
/// navigation, the section header and the settings button.
struct DetailPopoverView: View {
    @EnvironmentObject private var store: AppStore
    let embeddedModule: ModuleKind
    var hostPages: [HostPage] = []
    var onSettings: (SettingsTab) -> Void
    var onNavigate: (String) -> Void = { _ in }
    @State private var pageID = ""

    var body: some View {
        let pages = store.pages(for: embeddedModule)
        let tabs = hostPages.map { (id: $0.id, title: $0.title) } + pages.map { (id: $0.id, title: $0.title) }
        let selected = tabs.contains(where: { $0.id == pageID }) ? pageID : (tabs.first?.id ?? "")
        VStack(alignment: .leading, spacing: 12) {
            if tabs.count > 1 {
                PersonalTabBar(items: tabs.map { PersonalTabBar<String>.Item(id: $0.id, title: $0.title) },
                               selection: Binding(get: { selected }, set: { pageID = $0 }))
            }
            if let host = hostPages.first(where: { $0.id == selected }) {
                host.content
            } else if let page = pages.first(where: { $0.id == selected }) ?? pages.first {
                body(for: page)
            } else if embeddedModule == .usage {
                Text(L("Gösterilecek kota yok. Ayarlar > Kotalar’dan bir sağlayıcı aç.",
                       "No quotas to show. Turn on a provider in Settings > Quotas."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            if let selection = store.selection, selection.module == embeddedModule,
               tabs.contains(where: { $0.id == selection.id }) { pageID = selection.id }
            else if pageID.isEmpty { pageID = tabs.first?.id ?? "" }
        }
        .onChange(of: store.selection) { _, selection in
            if let selection, selection.module == embeddedModule { pageID = selection.id }
        }
    }
    @ViewBuilder
    private func body(for page: ModulePage) -> some View {
        switch page.module {
        case .today:
            switch page.item {
            case "week": WeeklyInsightsView()
            case "end": DayCloseView()
            default: todayBody
            }
        case .focus:
            FocusModuleView()
        case .usage:
            QuotaOverviewView(onSettings: onSettings)
        case .prayer:
            prayerBody
        case .calendar:
            calendarBody
        case .fitness:
            switch page.item {
            case "workout": fitnessBody
            case "meds": medicationBody
            case "nutrition": NutritionView()
            default: HealthOverviewView()
            }
        case .money:
            moneyBody
        }
    }

    // MARK: - Bugün

    private var todayBody: some View {
        let lines = store.todayLines
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(store.greeting)
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 5) {
                    Text(TimeFormatters.longDate(store.now))
                    if let hijri = store.prayers?.hijri, !hijri.isEmpty {
                        Text("·")
                        Text(hijri)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            }

            if lines.isEmpty {
                // Satırların hepsi gizlenmişse sorun modüllerde değil; kullanıcıyı
                // yanlış yere göndermeyelim.
                Text(store.allTodayLines.isEmpty
                     ? L("Gösterilecek bir şey yok. Ayarlar’dan modülleri aç.",
                         "Nothing to show. Turn on modules in Settings.")
                     : L("Bütün satırlar gizli. Ayarlar > Görünüm’den geri açabilirsin.",
                         "All rows are hidden. You can turn them back on in Settings > Appearance."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        if index > 0 {
                            Divider().opacity(0.35)
                        }
                        summaryRow(line)
                    }
                }
            }

            if store.settings.isModuleEnabled(.fitness), store.settings.trackIntake {
                intakeControls
            }
        }
    }

    /// Sade satır: ikon, başlık, değer, gerekirse tek satır açıklama.
    ///
    /// İlerleme çubuğu bilerek yok. Değerlerin kendisi zaten oranı söylüyor
    /// ("3 / 5 sayfa", "2/5", "1.4 / 3.0 L"); altına bir de çubuk koymak aynı
    /// bilgiyi ikinci kez, renkli ve gürültülü biçimde tekrarlıyordu.
    private func summaryRow(_ line: SummaryLine) -> some View {
        let content = HStack(spacing: 9) {
            Image(systemName: line.icon)
                .font(.system(size: 11))
                .foregroundStyle(line.tint ?? .secondary)
                .frame(width: 15)
            Text(line.title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            RowValue(value: line.value, detail: line.detail)
        }
        .padding(.vertical, 5)

        return Group {
            if let target = line.target {
                Button {
                    store.select(target)
                    if target.module == embeddedModule { pageID = target.id } else { onNavigate(target.id) }
                } label: { content.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    /// Su ve protein için tek dokunuşluk artırma; günlük girdi ancak bu kadar ucuzsa sürer.
    private var intakeControls: some View {
        HStack(spacing: 6) {
            stepButton("+\(Int(store.settings.waterStepML)) ml", tint: "4AA8E8") { store.adjustIntake(Metric.waterML, store.settings.waterStepML) }
            stepButton("−\(Int(store.settings.waterStepML))", tint: "4AA8E8") { store.adjustIntake(Metric.waterML, -store.settings.waterStepML) }
            Spacer(minLength: 4)
            stepButton("+\(Int(store.settings.proteinStepG)) g", tint: "E8A04A") { store.adjustIntake(Metric.proteinG, store.settings.proteinStepG) }
            stepButton("−\(Int(store.settings.proteinStepG))", tint: "E8A04A") { store.adjustIntake(Metric.proteinG, -store.settings.proteinStepG) }
        }
    }

    private func stepButton(_ title: String, tint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color(hex: tint).opacity(0.18), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var calendarBody: some View {
        let service = CalendarService.shared
        return VStack(alignment: .leading, spacing: 10) {
            switch service.access {
            case .notDetermined:
                Text(L("Takvim bağlı değil", "Calendar not connected"))
                    .font(.system(size: 13, weight: .semibold))
                Text(L(
                    "Yaklaşan toplantıları burada görmek için takvim erişimi gerekiyor. İzin yalnızca sen istediğinde sorulur.",
                    "Calendar access is needed to show upcoming meetings here. Permission is asked only when you choose."
                ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("Takvime bağlan", "Connect calendar")) {
                    Task { await service.requestAccess() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .denied:
                Text(L("Takvim erişimi kapalı", "Calendar access is off"))
                    .font(.system(size: 13, weight: .semibold))
                Text(L(
                    "Sistem Ayarları > Gizlilik ve Güvenlik > Takvimler içinden Hâl’e izin verebilirsin.",
                    "Allow Hâl in System Settings > Privacy & Security > Calendars."
                ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .granted:
                if service.events.isEmpty {
                    Text(L("Bugün için kalan olay yok.", "No remaining events today."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(service.events) { event in
                        let running = event.isRunning(at: store.now)
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(TimeFormatters.clock(event.start))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                Text(TimeFormatters.clock(event.end))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                            }
                            .frame(width: 40, alignment: .trailing)
                            Rectangle()
                                .fill(running ? Color(hex: "5BC48A") : Color.primary.opacity(0.18))
                                .frame(width: 2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title)
                                    .font(.system(size: 12, weight: running ? .semibold : .regular))
                                    .lineLimit(2)
                                if !event.calendarName.isEmpty {
                                    Text(event.calendarName)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var medicationBody: some View {
        let doses = store.todayDoses
        let taken = doses.filter { store.isDoseTaken($0) }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(taken)")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text(Lf("/ %1$d doz", "/ %1$d doses", doses.count))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
            }
            VStack(spacing: 2) {
                ForEach(doses) { dose in
                    let isTaken = store.isDoseTaken(dose)
                    let overdue = dose.isOverdue(now: store.now, taken: isTaken)
                    Button { store.toggleDose(dose) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isTaken ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12))
                                .foregroundStyle(isTaken ? Color(hex: "5BC48A")
                                                 : (overdue ? Color(hex: "E8A04A") : Color.secondary.opacity(0.5)))
                            Text(dose.clock)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 38, alignment: .leading)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(dose.medication.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(isTaken ? Color.secondary : Color.primary)
                                    .strikethrough(isTaken, color: .secondary)
                                if !dose.medication.dose.isEmpty {
                                    Text(dose.medication.dose)
                                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                                }
                            }
                            Spacer(minLength: 0)
                            if overdue {
                                Text(L("geçti", "missed")).font(.system(size: 10)).foregroundStyle(Color(hex: "E8A04A"))
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var fitnessBody: some View {
        let label = Workout.plan(store.settings.workoutPlan, on: store.now)
        let rest = Workout.isRestDay(label)
        let done = DailyLog.shared.isSet(Metric.workoutDone, on: store.now)
        let week = store.weeklyWorkoutProgress
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Workout.dayNames[Workout.index(for: store.now)])
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text(rest ? L("Dinlenme", "Rest") : label)
                    .font(.system(size: 20, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !rest {
                Button {
                    store.toggleWorkoutDone()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        Text(done ? L("Tamamlandı", "Done") : L("Tamamlandı olarak işaretle", "Mark as done"))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Color(hex: done ? "5BC48A" : "8A8A8A").opacity(done ? 0.22 : 0.12),
                        in: Capsule()
                    )
                    .foregroundStyle(done ? Color(hex: "5BC48A") : Color.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                if week.planned > 0 {
                    Text(Lf("Bu hafta %1$d/%2$d", "This week %1$d/%2$d", week.done, week.planned))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if store.workoutStreak > 1 {
                    Text(Lf("%1$d antrenman üst üste", "%1$d workouts in a row", store.workoutStreak))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            weekPlanGrid
        }
    }

    /// Haftanın programı: bugün vurgulu, yapılanlar dolu.
    private var weekPlanGrid: some View {
        let calendar = Calendar.current
        let todayIndex = Workout.index(for: store.now)
        let week = calendar.dateInterval(of: .weekOfYear, for: store.now)
        return VStack(alignment: .leading, spacing: 5) {
            Text(L("Bu hafta", "This week"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            ForEach(Array(store.settings.workoutPlan.enumerated()), id: \.offset) { index, plan in
                let date = week.flatMap { calendar.date(byAdding: .day, value: index, to: $0.start) }
                let rest = Workout.isRestDay(plan)
                let done = date.map { DailyLog.shared.isSet(Metric.workoutDone, on: $0) } ?? false
                HStack(spacing: 8) {
                    Text(Workout.shortNames[index])
                        .font(.system(size: 10, weight: index == todayIndex ? .semibold : .regular))
                        .foregroundStyle(index == todayIndex ? Color.primary : Color.secondary)
                        .frame(width: 26, alignment: .leading)
                    Circle()
                        .fill(rest ? Color.primary.opacity(0.12)
                              : (done ? Color(hex: "5BC48A") : Color.primary.opacity(0.22)))
                        .frame(width: 6, height: 6)
                    Text(rest ? "—" : plan)
                        .font(.system(size: 11, weight: index == todayIndex ? .medium : .regular))
                        .foregroundStyle(rest ? .tertiary : (index == todayIndex ? .primary : .secondary))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var moneyBody: some View {
        let items = store.upcomingSubscriptions
        return VStack(alignment: .leading, spacing: 10) {
            if store.monthlyTotals.isEmpty {
                Text(L("Henüz düzenli ödeme yok. Ayarlar > Ödemeler’den ekle.",
                       "No recurring payments yet. Add them in Settings > Payments."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    ForEach(store.monthlyTotals, id: \.currency) { total in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(Subscription.symbol(for: total.currency))\(String(format: "%.0f", locale: Language.locale, total.amount))")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                            Text(L("aylık", "monthly"))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                }
                VStack(spacing: 6) {
                    ForEach(items) { item in
                        let days = item.daysUntilRenewal(from: store.now)
                        HStack(spacing: 8) {
                            Circle()
                                .fill(days <= 3 ? Color(hex: "E8A04A") : Color.secondary.opacity(0.4))
                                .frame(width: 6, height: 6)
                            Text(item.name)
                                .font(.system(size: 12, weight: .medium))
                            Spacer(minLength: 6)
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(item.amountText)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                Text(days == 0 ? L("bugün", "today") : Lf("%1$d gün", "%1$d days", days))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var prayerBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !store.settings.hasLocation {
                Text(L("Konum seçilmedi", "No location chosen"))
                    .font(.system(size: 13, weight: .medium))
                Text(L("Vakitler için Ayarlar › İbadet’ten bir şehir seç.",
                       "Choose a city in Settings › Prayer for times."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
            HStack {
                Text(store.settings.locationLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            if let hijri = store.prayers?.hijri, !hijri.isEmpty {
                Text(hijri).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            if let prayers = store.prayers {
                ForEach(prayers.times.filter { store.settings.showSunrise || !$0.isSunnah }) { item in
                    let isNext = store.nextPrayer?.id == item.id
                    HStack(spacing: 6) {
                        // İşaret yalnızca farz vakitler için ve vakit girdikten sonra.
                        if store.settings.trackPrayers, !item.isSunnah, item.time <= store.now {
                            Button { store.togglePrayerDone(item) } label: {
                                Image(systemName: store.isPrayerDone(item) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(store.isPrayerDone(item) ? Color(hex: "5BC48A") : Color.secondary.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                            .help(store.isPrayerDone(item)
                                  ? L("Kılındı olarak işaretlendi", "Marked as prayed")
                                  : L("Kıldım olarak işaretle", "Mark as prayed"))
                        } else if store.settings.trackPrayers {
                            // Güneş dahil tüm satırlar aynı hizada dursun.
                            Color.clear.frame(width: 12, height: 12)
                        }
                        Text(item.localizedName)
                            .font(.system(size: 13, weight: isNext ? .semibold : .regular))
                        Spacer()
                        if isNext {
                            Text(TimeFormatters.remaining(prayers.remaining(to: item, now: store.now)))
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Text(TimeFormatters.clock(item.time))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(item.isSunnah ? Color.secondary.opacity(0.7) : (isNext ? Color.primary : Color.secondary))
                    .padding(.vertical, 1)
                }
                if store.settings.trackPrayers, store.prayerStreak > 1 {
                    Text(Lf("%1$d gün üst üste tam", "%1$d days in a row complete", store.prayerStreak))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            } else {
                Text(store.lastError ?? L("Vakitler yükleniyor…", "Loading prayer times…"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            }
        }
    }


}

/// A row's value with its note: side by side when both fit, otherwise the
/// note goes under the value and a long value wraps instead of being cut.
struct RowValue: View {
    let value: String
    let detail: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                valueText.lineLimit(1)
                if let detail { detailText(detail).lineLimit(1) }
            }
            .fixedSize()
            VStack(alignment: .trailing, spacing: 1) {
                valueText
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail { detailText(detail).lineLimit(1) }
            }
        }
    }

    private var valueText: some View {
        Text(value).font(.system(size: 12, weight: .medium))
    }

    private func detailText(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).foregroundStyle(.tertiary)
    }
}
