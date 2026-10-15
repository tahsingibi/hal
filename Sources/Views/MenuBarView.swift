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
                    ? "Sabit: pencere dışarı tıklayınca kapanmaz. Kaldırmak için tıkla."
                    : "Sabitle: pencere dışarı tıklayınca kapanmasın",
                active: store.pinned,
                action: store.togglePinned
            )
            iconButton("arrow.clockwise", help: "Kotaları ve vakitleri yenile") {
                loginHint = nil
                Task { await store.refresh() }
            }
            iconButton("gearshape", help: "Ayarlar") { onSettings(.location) }
        }
    }

    /// Modül sekmeleri; kayıttan türetilir, sabit liste yok.
    private var moduleTabs: some View {
        HStack(spacing: 4) {
            ForEach(store.modules) { item in
                let on = module == item
                Button {
                    store.selectModule(item)
                } label: {
                    // Dört ve üzeri modülde yazı yalnızca seçili sekmede kalır;
                    // 336 piksele dört başlık sığmıyor.
                    // Dört ve üzeri modülde seçili olmayanlar yalnızca ikon olur ve
                    // sabit dar bir yer kaplar; başlık seçili sekmeye kalır, kırılmaz.
                    let compact = store.modules.count > 3 && !on
                    Group {
                        if compact {
                            Image(systemName: item.symbol)
                        } else {
                            Label(item.title, systemImage: item.symbol)
                                .labelStyle(.titleAndIcon)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .font(.system(size: 12, weight: on ? .semibold : .medium))
                    .frame(maxWidth: compact ? 34 : .infinity)
                    .padding(.vertical, 6)
                    .background(on ? Color.primary.opacity(0.12) : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .help(item.title)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.05), in: Capsule())
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
                    Text("İçerik yok").font(.system(size: 12)).foregroundStyle(.secondary)
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
                Text("Kota yok").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case .prayer:
            switch page.item {
            case "quran": quranBody
            case "dua": duaBody
            default: prayerBody
            }
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
            case .claude: return "Claude oturumu yok"
            case .codex: return "Codex oturumu yok"
            case .grok: return "Grok henüz bağlı değil"
            case .custom: return "\(group.name) için kaynak yok"
            }
        }
        let message = group.message ?? ""
        if message.localizedCaseInsensitiveContains("süresi dolmuş") {
            return "\(group.name) oturumu süresi dolmuş"
        }
        return "\(group.name) kotası okunamadı"
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
            return "Kota api.anthropic.com/api/oauth/usage adresinden okunur; oturum Keychain’deki “Claude Code-credentials” kaydından gelir. Terminalde claude /login çalıştır, sonra Yenile’ye bas."
        case .grok:
            return "Haftalık sınır grok’un kendi fatura ucundan okunur. Oturum ~/.grok/auth.json dosyasıdır. Terminalde grok login çalıştır, sonra Yenile."
        case .codex:
            return "Kota chatgpt.com/backend-api/wham/usage adresinden okunur; oturum ~/.codex/auth.json dosyasından gelir. Terminalde codex login çalıştır, sonra Yenile’ye bas."
        case .custom:
            return "Bu kaynağın JSON çıktısında kota alanı bulunamadı. Ayarlar’dan komutu veya URL’yi kontrol et."
        }
    }

    private struct SetupAction {
        var title: String
        var run: () -> Void
    }

    private func setupActions(_ group: QuotaGroup) -> [SetupAction] {
        var actions: [SetupAction] = []
        switch group.kind {
        case .claude:
            actions.append(SetupAction(title: "Terminalde giriş") {
                if let error = ClaudeAuth.openLogin() {
                    loginHint = error
                } else {
                    loginHint = "Terminal açıldı. Giriş bittikten sonra Yenile’ye bas."
                }
            })
        case .grok:
            actions.append(SetupAction(title: "Terminalde giriş") {
                if let error = GrokAuth.openLogin() {
                    loginHint = error
                } else {
                    loginHint = "Terminal açıldı. Giriş bittikten sonra Yenile’ye bas."
                }
            })
        case .codex, .custom:
            break
        }
        actions.append(SetupAction(title: "Yenile") {
            loginHint = nil
            Task { await store.refresh() }
        })
        if group.kind != .grok {
            actions.append(SetupAction(title: "Ayarlar") { onSettings(.quota) })
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
                Text("\(window.percentText) kullanıldı")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                if !window.usedText.isEmpty {
                    Text(window.usedText)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            } else {
                // Sağlayıcının bir kota tavanı yok: yüzde uydurmak yerine ham değeri göster.
                Text(window.usedText.isEmpty ? "Kota sınırı yok" : window.usedText)
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
                     ? "Gösterilecek bir şey yok. Ayarlar’dan modülleri aç."
                     : "Bütün satırlar gizli. Ayarlar > Görünüm’den geri açabilirsin.")
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

    private var duaBody: some View {
        let items = store.settings.duaList
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(store.duaDoneCount)")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("/ \(items.count)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                if store.duaStreak > 1 {
                    Text("\(store.duaStreak) gün seri")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            VStack(spacing: 3) {
                ForEach(items) { item in
                    let done = store.isDuaDone(item)
                    Button { store.toggleDua(item) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12))
                                .foregroundStyle(done ? Color(hex: "5BC48A") : Color.secondary.opacity(0.5))
                            Text(item.name)
                                .font(.system(size: 12))
                                .foregroundStyle(done ? Color.secondary : Color.primary)
                                .strikethrough(done, color: .secondary)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var quranBody: some View {
        let read = DailyLog.shared.value(Metric.quranPages, on: store.now)
        let goal = store.settings.quranGoalPages
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(read))")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("/ \(Int(goal)) sayfa")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(Color(hex: "5BC48A"))
                            .frame(width: goal > 0 ? max(4, geo.size.width * min(read / goal, 1)) : 0)
                    }
                }
                .frame(height: 5)
                if store.quranStreak > 1 {
                    Text("\(store.quranStreak) gün üst üste hedefe ulaşıldı")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            HStack(spacing: 6) {
                stepButton("+1 sayfa", tint: "5BC48A") { store.adjustIntake(Metric.quranPages, 1) }
                stepButton("+5", tint: "5BC48A") { store.adjustIntake(Metric.quranPages, 5) }
                stepButton("−1", tint: "5BC48A") { store.adjustIntake(Metric.quranPages, -1) }
                Spacer()
            }
            weekBars
        }
    }

    /// Son yedi günün sayfa grafiği; seriyi tek bakışta gösterir.
    private var weekBars: some View {
        let calendar = Calendar.current
        let goal = max(store.settings.quranGoalPages, 1)
        let days: [(String, Double)] = (0..<7).reversed().compactMap { back in
            guard let date = calendar.date(byAdding: .day, value: -back, to: store.now) else { return nil }
            return (TimeFormatters.weekdayInitial(date), DailyLog.shared.value(Metric.quranPages, on: date))
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text("Son 7 gün")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(day.1 >= goal ? Color(hex: "5BC48A") : Color.primary.opacity(0.18))
                            .frame(width: 16, height: max(3, min(day.1 / goal, 1.2) * 34))
                        Text(day.0)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 50, alignment: .bottom)
        }
    }

    private var calendarBody: some View {
        let service = CalendarService.shared
        return VStack(alignment: .leading, spacing: 10) {
            switch service.access {
            case .notDetermined:
                Text("Takvim bağlı değil")
                    .font(.system(size: 13, weight: .semibold))
                Text("Yaklaşan toplantıları burada görmek için takvim erişimi gerekiyor. İzin yalnızca sen istediğinde sorulur.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Takvime bağlan") {
                    Task { await service.requestAccess() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .denied:
                Text("Takvim erişimi kapalı")
                    .font(.system(size: 13, weight: .semibold))
                Text("Sistem Ayarları > Gizlilik ve Güvenlik > Takvimler içinden Hâl’e izin verebilirsin.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .granted:
                if service.events.isEmpty {
                    Text("Bugün için kalan olay yok.")
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
                Text("/ \(doses.count) doz")
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
                                Text("geçti").font(.system(size: 10)).foregroundStyle(Color(hex: "E8A04A"))
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
                Text(rest ? "Dinlenme" : label)
                    .font(.system(size: 20, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !rest {
                Button {
                    store.toggleWorkoutDone()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        Text(done ? "Tamamlandı" : "Tamamlandı olarak işaretle")
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
                    Text("Bu hafta \(week.done)/\(week.planned)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if store.workoutStreak > 1 {
                    Text("\(store.workoutStreak) antrenman üst üste")
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
            Text("Bu hafta")
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
                Text("Henüz düzenli ödeme yok. Ayarlar > Ödemeler’den ekle.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    ForEach(store.monthlyTotals, id: \.currency) { total in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(Subscription.symbol(for: total.currency))\(String(format: "%.0f", total.amount))")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                            Text("aylık")
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
                                Text(days == 0 ? "bugün" : "\(days) gün")
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
                Text("Konum seçilmedi")
                    .font(.system(size: 13, weight: .medium))
                Text("Vakitler için Ayarlar › İbadet’ten bir şehir seç.")
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
                            .help(store.isPrayerDone(item) ? "Kılındı olarak işaretlendi" : "Kıldım olarak işaretle")
                        } else if store.settings.trackPrayers {
                            // Güneş dahil tüm satırlar aynı hizada dursun.
                            Color.clear.frame(width: 12, height: 12)
                        }
                        Text(item.name)
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
                    Text("\(store.prayerStreak) gün üst üste tam")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            } else {
                Text(store.lastError ?? "Vakitler yükleniyor…")
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
        return page.module == .usage ? "\(page.title) kotası" : page.title
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
    static let hilalOpenSettings = Notification.Name("hilal.openSettings")
}


/// Sayfa başına doğal yükseklik; popover'ı seçili sayfaya göre boyutlandırmak için.
private struct PageHeightKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
