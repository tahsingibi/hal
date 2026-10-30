import AppKit
import SwiftUI

struct DetailPopoverView: View {
    @EnvironmentObject private var store: AppStore
    var onSettings: (SettingsTab) -> Void
    @State private var loginHint: String?
    @State private var pageHeights: [String: CGFloat] = [:]
    @State private var pane: PopoverPane = .board
    @State private var tool: PopoverTool?

    private enum PopoverPane: Hashable {
        case board, wake, sound, tools
    }

    private enum PopoverTool: Hashable {
        case updates, homebrew, downloader, ports
    }

    private var pages: [ModulePage] { store.allPages }
    private var selected: DetailTarget {
        store.selection ?? pages.first?.target ?? DetailTarget(module: .usage)
    }
    private var module: ModuleKind { store.selectedModule }
    private var pageWidth: CGFloat { MenuBarLayout.popoverPageWidth }
    private var panelHeight: CGFloat { min(380, MenuBarLayout.popoverMaxContentHeight) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                BrandMark(icon: .app, size: 22)
                Spacer()
            }
            iconRail
            sectionHeader
            card
            if let loginHint, pane == .board {
                Text(loginHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(12)
        .frame(width: MenuBarLayout.popoverWidth, alignment: .topLeading)
        .onChange(of: store.boardToken) { _, _ in
            pane = .board
            tool = nil
        }
    }

    private var iconRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(store.modules) { item in
                    railButton(item.symbol, help: item.title, selected: pane == .board && module == item) {
                        pane = .board
                        tool = nil
                        store.selectModule(item)
                    }
                }
                railButton("moon.zzz", help: L("Uyanık tut", "Keep awake"), selected: pane == .wake) {
                    pane = .wake
                    tool = nil
                }
                railButton("speaker.wave.2", help: L("Ses", "Sound"), selected: pane == .sound) {
                    pane = .sound
                    tool = nil
                }
                railButton("wrench.and.screwdriver", help: L("Araçlar", "Tools"), selected: pane == .tools) {
                    pane = .tools
                    tool = nil
                }
            }
            .padding(3)
        }
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func railButton(_ symbol: String, help: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 26)
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .background(
                    selected ? Color.accentColor : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            if pane == .tools, tool != nil {
                Button {
                    tool = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Text(sectionTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
            if pane == .board {
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
            }
        }
    }

    private var sectionTitle: String {
        switch pane {
        case .board:
            return headerTitle
        case .wake:
            return L("Uyanık tut", "Keep awake")
        case .sound:
            return L("Ses mikseri", "Volume mixer")
        case .tools:
            return toolTitle ?? L("Araçlar", "Tools")
        }
    }

    private var toolTitle: String? {
        switch tool {
        case .updates: return L("Güncellemeler", "Updates")
        case .homebrew: return "Homebrew"
        case .downloader: return L("İndirici", "Downloader")
        case .ports: return L("Portlar", "Ports")
        case nil: return nil
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch pane {
            case .board:
                if modulePages.count > 1 {
                    pageChips
                }
                pager
            case .wake:
                KeepAwakePanel { onSettings(.focus) }
            case .sound:
                VolumeMixerPanel()
                    .frame(maxHeight: panelHeight)
            case .tools:
                if let tool {
                    if tool == .downloader {
                        toolDetail(tool)
                    } else {
                        toolDetail(tool)
                            .frame(height: panelHeight)
                    }
                } else {
                    toolList
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var toolList: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolRow("arrow.triangle.2.circlepath", L("Uygulama güncellemeleri", "App updates")) { tool = .updates }
            toolDivider
            toolRow("shippingbox", "Homebrew") { tool = .homebrew }
            toolDivider
            toolRow("arrow.down.circle", L("İndirici", "Downloader")) { tool = .downloader }
            toolDivider
            toolRow("network", L("Portlar", "Ports")) { tool = .ports }
            toolDivider
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .frame(width: 18)
                    .foregroundStyle(Color.accentColor)
                Text(store.settings.resolvedCleaningMenuTitle)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { store.cleaningMode },
                    set: { store.setCleaningMode($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(.vertical, 6)
            if let message = store.cleaningMessage, store.cleaningMode || !DeviceModes.shared.accessibilityTrusted {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func toolRow(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 18)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var toolDivider: some View {
        Divider().padding(.leading, 26)
    }

    @ViewBuilder
    private func toolDetail(_ tool: PopoverTool) -> some View {
        switch tool {
        case .updates:
            UpdatesPanel()
        case .homebrew:
            HomebrewPanel()
        case .downloader:
            DownloaderForm(showsFolder: true)
        case .ports:
            PortsPanel(showsTitle: false)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                onSettings(settingsDestination)
            } label: {
                Label(L("Ayarlar", "Settings"), systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            Button {
                NSApp.terminate(nil)
            } label: {
                Label(L("Çık", "Quit"), systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private var settingsDestination: SettingsTab {
        switch pane {
        case .board:
            switch module {
            case .today: return .appearance
            case .focus: return .focus
            case .usage: return .quota
            case .prayer: return .worship
            case .calendar: return .calendar
            case .fitness: return .fitness
            case .money: return .money
            }
        case .wake:
            return .wake
        case .sound:
            return .mixer
        case .tools:
            switch tool {
            case .updates: return .updates
            case .homebrew: return .homebrew
            case .downloader: return .downloader
            case .ports: return .ports
            case nil: return .updates
            }
        }
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
                                on ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04),
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

    private var selectedPageModel: ModulePage? {
        pages.first { $0.target == selected }
    }

    private var headerTitle: String {
        guard let page = selectedPageModel else { return module.title }
        return page.module == .usage ? Lf("%1$@ kotası", "%1$@ quota", page.title) : page.title
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

/// Sayfa başına doğal yükseklik; popover'ı seçili sayfaya göre boyutlandırmak için.
private struct PageHeightKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

