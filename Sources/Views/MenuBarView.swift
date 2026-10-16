import AppKit
import SwiftUI

struct DetailPopoverView: View {
    @EnvironmentObject private var store: AppStore
    var onSettings: (SettingsTab) -> Void
    @State private var loginHint: String?
    @State private var pageHeights: [String: CGFloat] = [:]

    private var pages: [ModulePage] { store.allPages }
    private var selected: DetailTarget {
        store.selection ?? pages.first?.target ?? DetailTarget(module: .usage)
    }
    private var module: ModuleKind { store.selectedModule }
    private var pageWidth: CGFloat { MenuBarLayout.popoverPageWidth }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if store.modules.count > 1 {
                moduleTabs
            }
            // Modülün birden çok sayfası varsa aralarında geçiş şeridi.
            if modulePages.count > 1 {
                pageChips
            }
            pager
            if let loginHint {
                Text(loginHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(14)
        .frame(width: MenuBarLayout.popoverWidth, alignment: .topLeading)
    }

    private var modulePages: [ModulePage] {
        pages.filter { $0.module == module }
    }

    private var selectedPage: Binding<String> {
        Binding(
            get: {
                let ids = pages.map(\.id)
                return ids.contains(selected.id) ? selected.id : (ids.first ?? selected.id)
            },
            set: { id in
                guard let page = pages.first(where: { $0.id == id }) else { return }
                store.select(page.target)
            }
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            BrandMark(icon: headerBrand, size: 14)
            Text(headerTitle)
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            iconButton(
                store.pinned ? "pin.fill" : "pin",
                help: store.pinned
                    ? L("Sabit: pencere dışarı tıklayınca kapanmaz. Kaldırmak için tıkla.",
                        "Pinned: window stays open when you click outside. Click to unpin.")
                    : L("Sabitle: pencere dışarı tıklayınca kapanmasın",
                        "Pin: keep window open when clicking outside"),
                active: store.pinned,
                action: store.togglePinned
            )
            iconButton("arrow.clockwise", help: L("Kotaları ve vakitleri yenile", "Refresh quotas and prayer times")) {
                loginHint = nil
                Task { await store.refresh() }
            }
            iconButton("gearshape", help: L("Ayarlar", "Settings")) { onSettings(.location) }
        }
    }

    /// Modül sekmeleri; kayıttan türetilir, sabit liste yok.
    private var moduleTabs: some View {
        ModuleTabStrip(modules: store.modules, selected: module) { item in
            store.selectModule(item)
        }
    }

    /// Seçili modülün sayfaları arasında geçiş.
    private var pageChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(modulePages) { page in
                        let on = selected == page.target
                        Button {
                            store.select(page.target)
                        } label: {
                            HStack(spacing: 5) {
                                if page.module != .today && page.module != .fitness {
                                    BrandMark(icon: page.icon, size: 11)
                                }
                                Text(page.title)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                on ? Color(hex: accentHex(for: page)).opacity(0.22) : Color.primary.opacity(0.05),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                        .id(page.id)
                    }
                }
            }
            .onChange(of: store.selection) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(target.id, anchor: .center)
                }
            }
        }
    }

    private func accentHex(for page: ModulePage) -> String {
        guard page.module == .usage, let item = page.item else { return "8A8A8A" }
        return store.quotas.first { $0.id == item }?.accentHex ?? "8A8A8A"
    }

    /// Popover yüksekliği seçili sayfaya göre ayarlanır: kısa sayfa boşluk bırakmaz,
    /// uzun sayfa ekranı taşırmaz — sınırı aşınca sayfa kendi içinde kayar.
    ///
    /// Ölçüm henüz gelmediyse (ilk kare) yükseklik sabitlenmez; dıştaki
    /// `maxHeight` yine de taşmayı engeller. Böylece en kötü durumda eski
    /// davranışa düşeriz, kırpılmış bir pencereye değil.
    private var pagerHeight: CGFloat? {
        guard let natural = pageHeights[selected.id] else { return nil }
        return min(max(natural, MenuBarLayout.popoverMinContentHeight), MenuBarLayout.popoverMaxContentHeight)
    }

    private var pager: some View {
        SwipePager(items: pages.map(\.id), selection: selectedPage, pageWidth: pageWidth) { id in
            Group {
                if let page = pages.first(where: { $0.id == id }) {
                    body(for: page)
                } else {
                    Text(L("İçerik yok", "Nothing here")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            // ScrollView içinde ölçüm doğal yüksekliği verir; dıştaki çerçeveye
            // bağlı olmadığı için döngü oluşmaz.
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: PageHeightKey.self, value: [id: geo.size.height])
                }
            )
        }
        .frame(height: pagerHeight)
        .frame(
            minHeight: MenuBarLayout.popoverMinContentHeight,
            maxHeight: MenuBarLayout.popoverMaxContentHeight
        )
        .onPreferenceChange(PageHeightKey.self) { heights in
            pageHeights.merge(heights) { _, new in new }
        }
    }

    /// Sayfa görünümü. Yeni modül eklerken buraya bir `case` gelir.
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
            if let item = page.item, let group = store.quotas.first(where: { $0.id == item }) {
                quotaBody(group)
            } else {
                Text(L("Kota yok", "No quotas")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
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

    @ViewBuilder
    private func quotaBody(_ group: QuotaGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            switch group.status {
            case .ready:
                ForEach(group.windows) { window in
                    meter(window)
                }
            case .loading:
                ProgressView().controlSize(.small)
            case .missingAuth, .error:
                quotaSetup(group)
            }
        }
    }

    private func quotaSetup(_ group: QuotaGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(setupTitle(group))
                .font(.system(size: 13, weight: .semibold))
            Text(setupDetail(group))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(setupActions(group), id: \.title) { action in
                    Button(action.title, action: action.run)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(.top, 4)
    }

    private var isMissingAuth: (QuotaGroup) -> Bool {
        { $0.status == .missingAuth }
    }

    private func setupTitle(_ group: QuotaGroup) -> String {
        // Oturum yokluğu ile okuma hatası ayrı şeyler; ikisini aynı başlıkla göstermiyoruz.
        if isMissingAuth(group) {
            switch group.kind {
            case .claude: return L("Claude oturumu yok", "No Claude session")
            case .codex: return L("Codex oturumu yok", "No Codex session")
            case .grok: return L("Grok henüz bağlı değil", "Grok is not connected yet")
            case .custom: return Lf("%1$@ için kaynak yok", "No source for %1$@", group.name)
            }
        }
        let message = group.message ?? ""
        if message.localizedCaseInsensitiveContains("süresi dolmuş")
            || message.localizedCaseInsensitiveContains("expired") {
            return Lf("%1$@ oturumu süresi dolmuş", "%1$@ session expired", group.name)
        }
        return Lf("%1$@ kotası okunamadı", "Could not read %1$@ quota", group.name)
    }

    private func setupDetail(_ group: QuotaGroup) -> String {
        // Hata durumunda tahmin yürütmek yerine sunucudan/komuttan gelen gerçek nedeni göster.
        if !isMissingAuth(group), let message = group.message, !message.isEmpty {
            return message + "\n\n" + setupHint(group)
        }
        return setupHint(group)
    }

    private func setupHint(_ group: QuotaGroup) -> String {
        switch group.kind {
        case .claude:
            return L(
                "Kota api.anthropic.com/api/oauth/usage adresinden okunur; oturum Keychain’deki “Claude Code-credentials” kaydından gelir. Terminalde claude /login çalıştır, sonra Yenile’ye bas.",
                "Quota is read from api.anthropic.com/api/oauth/usage; the session comes from the Keychain “Claude Code-credentials” entry. Run claude /login in Terminal, then tap Refresh."
            )
        case .grok:
            return L(
                "Haftalık sınır grok’un kendi fatura ucundan okunur. Oturum ~/.grok/auth.json dosyasıdır. Terminalde grok login çalıştır, sonra Yenile.",
                "The weekly limit is read from grok’s own billing endpoint. The session is ~/.grok/auth.json. Run grok login in Terminal, then Refresh."
            )
        case .codex:
            return L(
                "Kota chatgpt.com/backend-api/wham/usage adresinden okunur; oturum ~/.codex/auth.json dosyasından gelir. Terminalde codex login çalıştır, sonra Yenile’ye bas.",
                "Quota is read from chatgpt.com/backend-api/wham/usage; the session comes from ~/.codex/auth.json. Run codex login in Terminal, then tap Refresh."
            )
        case .custom:
            return L(
                "Bu kaynağın JSON çıktısında kota alanı bulunamadı. Ayarlar’dan komutu veya URL’yi kontrol et.",
                "No quota field found in this source’s JSON output. Check the command or URL in Settings."
            )
        }
    }

    private struct SetupAction {
        var title: String
        var run: () -> Void
    }

    private func setupActions(_ group: QuotaGroup) -> [SetupAction] {
        var actions: [SetupAction] = []
        let openedHint = L("Terminal açıldı. Giriş bittikten sonra Yenile’ye bas.",
                           "Terminal opened. After you finish signing in, tap Refresh.")
        switch group.kind {
        case .claude:
            actions.append(SetupAction(title: L("Terminalde giriş", "Sign in via Terminal")) {
                if let error = ClaudeAuth.openLogin() {
                    loginHint = error
                } else {
                    loginHint = openedHint
                }
            })
        case .grok:
            actions.append(SetupAction(title: L("Terminalde giriş", "Sign in via Terminal")) {
                if let error = GrokAuth.openLogin() {
                    loginHint = error
                } else {
                    loginHint = openedHint
                }
            })
        case .codex, .custom:
            break
        }
        actions.append(SetupAction(title: L("Yenile", "Refresh")) {
            loginHint = nil
            Task { await store.refresh() }
        })
        if group.kind != .grok {
            actions.append(SetupAction(title: L("Ayarlar", "Settings")) { onSettings(.quota) })
        }
        return actions
    }

    private func meter(_ window: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(window.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if !window.resetText.isEmpty {
                    Text(window.resetText)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            if window.hasLimit {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(Theme.barColor(percent: window.clampedPercent))
                            .frame(width: max(6, geo.size.width * window.clampedPercent))
                    }
                }
                .frame(height: 6)
                Text(Lf("%1$@ kullanıldı", "%1$@ used", window.percentText))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                if !window.usedText.isEmpty {
                    Text(window.usedText)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            } else {
                // Sağlayıcının bir kota tavanı yok: yüzde uydurmak yerine ham değeri göster.
                Text(window.usedText.isEmpty ? L("Kota sınırı yok", "No quota limit") : window.usedText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            if let detail = window.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
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

            if store.settings.trackIntake {
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
            Text(line.value)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            if let detail = line.detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
        }
        .padding(.vertical, 5)

        return Group {
            if let target = line.target {
                Button { store.select(target) } label: { content.contentShape(Rectangle()) }
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

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(store.settings.resolvedCleaningMenuTitle, isOn: Binding(
                    get: { store.cleaningMode },
                    set: { store.setCleaningMode($0) }
                ))
                .toggleStyle(.checkbox)
                .controlSize(.small)
                Toggle("Always Wake", isOn: Binding(
                    get: { store.settings.alwaysWake },
                    set: { store.setAlwaysWake($0) }
                ))
                .toggleStyle(.checkbox)
                .controlSize(.small)
                Spacer()
            }
            .font(.system(size: 11))
            if let message = store.cleaningMessage, store.cleaningMode || !DeviceModes.shared.accessibilityTrusted {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var selectedPageModel: ModulePage? {
        pages.first { $0.target == selected }
    }

    private var headerTitle: String {
        guard let page = selectedPageModel else { return module.title }
        return page.module == .usage ? Lf("%1$@ kotası", "%1$@ quota", page.title) : page.title
    }

    private var headerBrand: BrandIcon {
        selectedPageModel?.icon ?? .app
    }

    private func iconButton(
        _ icon: String,
        help: String,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
                .frame(width: 20, height: 20)
                .background(
                    active ? Color.accentColor.opacity(0.15) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

extension Notification.Name {
    static let halOpenSettings = Notification.Name("hal.openSettings")
}


/// Sekme şeridi. Sekmeler sıkışmaz; sığmayanlar trackpad kaydırması ya da
/// sürükleme ile gelir. Seçili sekme yazısı sonradan genişler; yerleşim yeni
/// çerçeveyi verince şerit o yazının tamamını kapsülün içine alır.
private struct ModuleTabStrip: View {
    let modules: [ModuleKind]
    let selected: ModuleKind
    let onSelect: (ModuleKind) -> Void

    @State private var offset: CGFloat = 0
    @State private var drag: CGFloat = 0
    @State private var dragging = false
    @State private var frames: [String: CGRect] = [:]
    @State private var viewport: CGFloat = 0
    /// Seçim değişince artar. Yerleşim, büyümüş çerçeveyi içeri alınca eşitlenir.
    @State private var revealGeneration = 0
    @State private var revealedGeneration = -1
    @State private var revealedWidth: CGFloat = 0

    /// Şeridin ideal genişliği. Arka plan ölçeri kırpılan genişliği verdiği için
    /// sekmelerin kendi çerçevelerinden okunur; sağ boşluk sol boşluğa eşittir.
    private var contentWidth: CGFloat {
        let laid = frames.values.filter { $0.width > 1 }
        guard laid.count == modules.count else { return 0 }
        let maxX = laid.map(\.maxX).max() ?? 0
        let minX = laid.map(\.minX).min() ?? 0
        return maxX + minX
    }

    private var minOffset: CGFloat { min(0, viewport - contentWidth) }

    /// Sürüklerken uçlarda lastik; bırakınca model konumu olduğu gibi durur.
    private var shownOffset: CGFloat {
        dragging || drag != 0 ? resist(offset + drag) : offset
    }

    var body: some View {
        // Görünen alan, şeridin ideal genişliği değil, ebeveynin verdiği genişliktir.
        // Aksi halde kapsül içerikle birlikte büyür ve popover sağ kenarı yazıyı keser.
        GeometryReader { geo in
            strip
                .offset(x: shownOffset)
                .frame(width: geo.size.width, height: 34, alignment: .leading)
                .clipped()
                .preference(key: TabViewportKey.self, value: geo.size.width)
        }
        .frame(height: 34)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .clipShape(Capsule())
        .contentShape(Capsule())
        .simultaneousGesture(pan)
        .background(TabWheelMonitor { applyWheel($0) })
        .onPreferenceChange(TabFramesKey.self) { frames = $0; scheduleRevealIfNeeded() }
        .onPreferenceChange(TabViewportKey.self) { viewport = $0; scheduleRevealIfNeeded() }
        .onChange(of: selected) { _, _ in
            revealGeneration += 1
            revealedWidth = 0
            scheduleRevealIfNeeded()
        }
    }

    private var strip: some View {
        UncompressedHStack(spacing: 4) {
            ForEach(modules) { item in
                tab(item)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .fixedSize(horizontal: true, vertical: false)
        .coordinateSpace(name: "moduleTabs")
    }

    private func tab(_ item: ModuleKind) -> some View {
        let on = selected == item
        let compact = modules.count > 3 && !on
        return Button {
            onSelect(item)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: item.symbol)
                    .frame(width: 16, height: 16)
                if !compact {
                    Text(item.title)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .font(.system(size: 12, weight: on ? .semibold : .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: compact ? 36 : nil)
            .fixedSize(horizontal: true, vertical: false)
            .background(on ? Color.primary.opacity(0.12) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .help(item.title)
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: TabFramesKey.self,
                    value: [item.id: geo.frame(in: .named("moduleTabs"))]
                )
            }
        }
    }

    private var pan: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                dragging = true
                drag = value.translation.width
            }
            .onEnded { value in
                let flick = (value.predictedEndTranslation.width - value.translation.width) * 0.2
                let next = resist(offset + value.translation.width + flick)
                withAnimation(.easeOut(duration: 0.22)) {
                    offset = min(0, max(minOffset, next))
                    drag = 0
                }
                dragging = false
                scheduleRevealIfNeeded()
            }
    }

    private func applyWheel(_ delta: CGFloat) {
        guard !dragging, minOffset < 0 else { return }
        offset = min(0, max(minOffset, offset + delta))
    }

    private func scheduleRevealIfNeeded() {
        DispatchQueue.main.async { revealAfterLayout() }
    }

    /// Seçili sekmenin çerçevesi değişince (ikonken yazı eklenince de) tamamını
    /// görünür alanın içine alır. Kullanıcı daha sonra kaydırırsa geri çekmez.
    private func revealAfterLayout() {
        guard !dragging else { return }
        guard viewport > 1, let frame = frames[selected.id], frame.width > 1 else { return }
        // Genişlik henüz bu sekmeyi kapsamıyorsa ölçüm yarımdır; sonraki geçişi bekle.
        guard contentWidth + 0.5 >= frame.maxX else { return }

        let pending = revealedGeneration != revealGeneration
        let grew = frame.width > revealedWidth + 1
        if !pending && !grew { return }
        if !pending && frameIsInside(frame, at: offset) {
            revealedWidth = frame.width
            return
        }

        let next = clampedOffset(placing: frame)
        if abs(next - offset) > 0.5 {
            withAnimation(.easeInOut(duration: 0.2)) { offset = next }
        } else {
            offset = next
        }
        revealedWidth = frame.width
        if frameIsInside(frame, at: next) || frame.width + 8 >= viewport {
            revealedGeneration = revealGeneration
        }
    }

    /// Çerçeveler şeridin kendi koordinatında; `origin` görünen pencerenin solu.
    private func frameIsInside(_ frame: CGRect, at origin: CGFloat) -> Bool {
        let left = -origin
        let right = left + viewport
        return frame.minX >= left - 0.5 && frame.maxX <= right + 0.5
    }

    /// Seçili sekmeyi kapsül kenarından birkaç punto içeride tutar.
    private func clampedOffset(placing frame: CGRect) -> CGFloat {
        let inset: CGFloat = 4
        let left = -offset
        let right = left + viewport
        var next = offset
        if frame.width + inset * 2 >= viewport {
            next = -(frame.minX - inset)
        } else if frame.minX < left + inset {
            next = -(frame.minX - inset)
        } else if frame.maxX > right - inset {
            next = -(frame.maxX - viewport + inset)
        }
        return min(0, max(minOffset, next))
    }

    private func resist(_ raw: CGFloat) -> CGFloat {
        if raw > 0 { return raw * 0.3 }
        if raw < minOffset { return minOffset + (raw - minOffset) * 0.3 }
        return raw
    }
}

/// Trackpad’in yatay kaydırmasını şeride bağlar. Tıklamayı yutmaz.
private struct TabWheelMonitor: NSViewRepresentable {
    var onDelta: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.start(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onDelta = onDelta
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var onDelta: (CGFloat) -> Void = { _ in }
        var monitor: Any?

        func start(on view: NSView) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak view] event in
                guard let view, let window = view.window, event.window == window else { return event }
                let point = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(point) else { return event }
                let dx = event.scrollingDeltaX
                guard abs(dx) > abs(event.scrollingDeltaY), abs(dx) > 0.01 else { return event }
                let delta = event.hasPreciseScrollingDeltas ? dx : dx * 16
                self.onDelta(delta)
                return nil
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

private struct TabFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct TabViewportKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Sekmeleri ideal genişliklerinde dizer. Dar bir öneri gelse bile çocuklar bölünmez.
private struct UncompressedHStack: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = idealSizes(subviews)
        let width = sizes.reduce(CGFloat(0)) { $0 + $1.width } + spacing * CGFloat(max(sizes.count - 1, 0))
        let height = sizes.map(\.height).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = idealSizes(subviews)
        var x = bounds.minX
        for (subview, size) in zip(subviews, sizes) {
            subview.place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: size.width, height: bounds.height)
            )
            x += size.width + spacing
        }
    }

    private func idealSizes(_ subviews: Subviews) -> [CGSize] {
        subviews.map { $0.sizeThatFits(.unspecified) }
    }
}

/// Sayfa başına doğal yükseklik; popover'ı seçili sayfaya göre boyutlandırmak için.
private struct PageHeightKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
