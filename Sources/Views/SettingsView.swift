import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Hashable, Identifiable {
    // Uygulama
    case general, features, permissions, appearance, notifications, wake, switcher, displays
    // Modüller ve araçlar
    case focus, quota, worship, calendar, fitness, money, downloader, ports, homebrew, mixer, updates
    case about, changelog

    var id: String { rawValue }

    /// Kenar çubuğu grupları: uygulama ayarları ile modül ayarları karışmasın.
    enum Group: String, CaseIterable, Identifiable {
        case app = "Uygulama"
        case modules = "Kişisel"
        case tools = "Araçlar"
        case info = "Bilgi"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .app: return L("Uygulama", "Application")
            case .modules: return L("Kişisel", "Personal")
            case .tools: return L("Araçlar", "Tools")
            case .info: return L("Bilgi", "Information")
            }
        }

        var tabs: [SettingsTab] {
            switch self {
            case .app: return [.general, .features, .permissions, .appearance, .notifications]
            case .modules: return [.focus, .worship, .fitness, .money]
            case .tools: return [.quota, .calendar, .wake, .switcher, .displays, .mixer, .downloader, .ports, .homebrew, .updates]
            case .info: return [.about, .changelog]
            }
        }
    }

    var title: String {
        switch self {
        case .general: return L("Genel", "General")
        case .features: return L("Özellikler", "Features")
        case .permissions: return L("İzinler", "Permissions")
        case .appearance: return L("Menü çubuğu", "Menu bar")
        case .notifications: return L("Bildirimler", "Notifications")
        case .wake: return L("Uyanık tutma", "Keep awake")
        case .switcher: return L("Pencere değiştirici", "Window switcher")
        case .displays: return L("Ekranlar", "Displays")
        case .focus: return L("Odak", "Focus")
        case .quota: return L("Kotalar", "Quotas")
        case .worship: return L("İbadet", "Prayer")
        case .calendar: return L("Takvim", "Calendar")
        case .fitness: return L("Sağlık", "Health")
        case .money: return L("Ödemeler", "Payments")
        case .downloader: return L("Video indirici", "Video downloader")
        case .ports: return L("Portlar", "Ports")
        case .homebrew: return "Homebrew"
        case .mixer: return L("Ses", "Sound")
        case .updates: return L("Güncellemeler", "Updates")
        case .about: return L("Hakkında", "About")
        case .changelog: return L("Yenilikler", "What's New")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .features: return "square.grid.2x2"
        case .permissions: return "hand.raised"
        case .appearance: return "menubar.rectangle"
        case .notifications: return "bell"
        case .wake: return "moon.zzz"
        case .switcher: return "macwindow.on.rectangle"
        case .displays: return "sun.max"
        case .focus: return "scope"
        case .quota: return "gauge"
        case .worship: return "moon.stars"
        case .calendar: return "calendar"
        case .fitness: return "figure.strengthtraining.traditional"
        case .money: return "creditcard"
        case .downloader: return "arrow.down.circle"
        case .ports: return "network"
        case .homebrew: return "shippingbox"
        case .mixer: return "speaker.wave.2"
        case .updates: return "arrow.triangle.2.circlepath"
        case .about: return "info.circle"
        case .changelog: return "sparkles"
        }
    }

    /// Eski çağrı yerleri için: Konum artık İbadet altında.
    static let location = SettingsTab.worship
    static let menuBar = SettingsTab.appearance
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var tab: SettingsTab
    @State private var query = ""
    @AppStorage("hal.settings.collapsedGroups") private var collapsedGroups = ""
    @State private var backStack: [SettingsTab] = []
    @State private var forwardStack: [SettingsTab] = []
    @State private var traversingHistory = false
    @State private var draft = CustomProvider(name: "")
    @State private var adding = false
    @State private var legacyKeychainCount = 0
    @State private var legacyNote: String?
    @State private var copiedDiagnostics = false
    @State private var calendarAccess = CalendarService.shared.access
    @State private var claudeHint: String?

    /// Belirli bir sekmeyle açılabilir; bildirimden ya da popover'dan doğrudan
    /// ilgili sayfaya götürmek için.
    init(initialTab: SettingsTab = .features) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        // Sekme şeridi yerine kenar çubuğu: bölüm sayısı arttıkça başlıklar
        // kırpılmıyor, yeni bölüm eklemek de genişlik hesabı gerektirmiyor.
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 216, max: 250)
        } detail: {
            // Ayrıntı alanı kendi kaydırır. GeometryReader, bölücünün yerleşimi
            // sırasında sayfanın tüm içerik yüksekliğini bildirip pencereyi
            // büyütmesini önler; yalnızca kendisine verilen alanı kullanır.
            GeometryReader { geometry in
                page
                    .id(tab)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle(L("Hâl Ayarları", "Hâl Settings"))
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 820, minHeight: 560)
        .environment(\.locale, Language.locale)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { navigateBack() } label: { Label(L("Geri", "Back"), systemImage: "chevron.backward") }
                    .disabled(backStack.isEmpty).help(L("Geri", "Back"))
                Button { navigateForward() } label: { Label(L("İleri", "Forward"), systemImage: "chevron.forward") }
                    .disabled(forwardStack.isEmpty).help(L("İleri", "Forward"))
            }
        }
        .onChange(of: tab) { old, _ in
            if traversingHistory { traversingHistory = false }
            else { backStack.append(old); forwardStack = [] }
        }
        .onAppear {
            legacyKeychainCount = SecretStore.legacyItemCount()
        }
    }

    // MARK: - Kenar çubuğu

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L("Ayarlarda ara", "Search settings"), text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help(L("Temizle", "Clear"))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)

            List(selection: sidebarSelection) {
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ForEach(filteredGroups.flatMap(\.tabs)) { row($0) }
                    if filteredGroups.isEmpty {
                        Text(L("Sonuç bulunamadı", "No results"))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(filteredGroups, id: \.group.id) { entry in
                        Section {
                            if groupExpanded(entry.group) {
                                ForEach(entry.tabs) { row($0) }
                            }
                        } header: {
                            Button {
                                toggleGroup(entry.group)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: groupExpanded(entry.group) ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 9, weight: .semibold))
                                        .frame(width: 12)
                                    Text(entry.group.title)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func groupExpanded(_ group: SettingsTab.Group) -> Bool {
        !collapsedGroups.split(separator: ",").contains(Substring(group.rawValue))
    }

    private func toggleGroup(_ group: SettingsTab.Group) {
        var collapsed = Set(collapsedGroups.split(separator: ",").map(String.init))
        if collapsed.contains(group.rawValue) { collapsed.remove(group.rawValue) } else { collapsed.insert(group.rawValue) }
        collapsedGroups = collapsed.sorted().joined(separator: ",")
    }

    private func navigateBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(tab); traversingHistory = true; tab = previous
    }

    private func navigateForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(tab); traversingHistory = true; tab = next
    }

    private func row(_ item: SettingsTab) -> some View {
        HStack(spacing: 9) {
            Image(systemName: item.symbol)
                .foregroundStyle(tab == item ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
                .frame(width: 18)
            Text(item.title)
                .lineLimit(1)
        }
        .tag(item)
        .help(item.title)
    }

    private var sidebarSelection: Binding<SettingsTab?> {
        Binding(
            get: { tab },
            set: { selected in
                if let selected { tab = selected }
            }
        )
    }

    // MARK: - Sayfa

    private var page: some View {
        SettingsPage(title: tab.title, subtitle: tab.subtitle) {
            if let module = tab.module, !store.settings.isModuleEnabled(module) {
                SettingsCard {
                    SettingsRow(symbol: "pause.circle",
                                title: L("Bu modül kapalı", "This module is turned off"),
                                caption: L("Tercihlerin korunuyor. Açınca panelde yeniden görünür.",
                                           "Your preferences are kept. Turn it on to show it in the panel again.")) {
                        Button(L("Etkinleştir", "Enable")) { store.setModule(module, enabled: true) }
                    }
                }
            }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .general: generalTab
        case .features: FeatureHubView(onSettings: { tab = $0 })
        case .permissions: PermissionsView(onSettings: { tab = $0 })
        case .appearance: menuBarTab
        case .notifications: notificationsTab
        case .wake: KeepAwakePanel { tab = .focus }
        case .switcher: WindowSwitcherSettingsView()
        case .displays: DisplaySettingsView()
        case .focus: focusTab
        case .quota: quotaTab
        case .worship: worshipTab
        case .calendar: calendarTab
        case .fitness: fitnessTab
        case .money: moneyTab
        case .downloader: DownloaderSettingsForm()
        case .ports: PortsPanel(showsTitle: false, embedsInSettings: true)
        case .homebrew: HomebrewPanel()
        case .mixer: VolumeMixerPanel()
        case .updates: UpdatesPanel()
        case .about: aboutTab
        case .changelog: changelogTab
        }
    }

    private var filteredGroups: [(group: SettingsTab.Group, tabs: [SettingsTab])] {
        SettingsTab.Group.allCases.compactMap { group in
            let tabs = group.tabs.filter { item in
                let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if term.isEmpty {
                    return item.module.map { store.settings.isModuleEnabled($0) } ?? true
                }
                return "\(item.title) \(item.subtitle) \(item.rawValue)".localizedCaseInsensitiveContains(term)
            }
            return tabs.isEmpty ? nil : (group, tabs)
        }
    }

    private var worshipTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard {
                SettingsToggleRow(
                    title: L("Namaz takibi", "Prayer tracking"),
                    detail: L(
                        "Vakit geçtikten sonra Namaz sekmesinden işaretlersin; pano gün içi sayıyı ve seriyi gösterir. Bilgisayara geçmediğin günleri Bugün > Gün Sonu sayfasından tamamlarsın.",
                        "After a prayer time passes, mark it on the Prayer tab; the board shows today’s count and streak. Days you weren’t at the computer can be finished from Today > End of day."
                    ),
                    symbol: "checklist",
                    isOn: $store.settings.trackPrayers
                )
            }

            SettingsCard(title: L("Konum", "Location")) {
                SettingsMenuRow(symbol: "globe", title: L("Ülke", "Country"), selection: countryBinding) {
                    Text(L("Seç", "Choose")).tag("")
                    ForEach(store.countries) { country in
                        Text(country.localizedName).tag(country.code)
                    }
                }
                Divider()
                SettingsMenuRow(symbol: "map", title: L("İl / Eyalet", "State / Province"), selection: stateBinding) {
                    Text(L("Seç", "Choose")).tag("")
                    ForEach(store.regions) { region in
                        Text(region.name).tag(region.name)
                    }
                }
                Divider()
                if !store.cities.isEmpty {
                    SettingsMenuRow(symbol: "mappin.and.ellipse", title: L("Şehir / İlçe", "City / District"), selection: cityBinding) {
                        Text(L("Seç", "Choose")).tag("")
                        ForEach(store.cities) { city in
                            Text(city.name).tag(city.name)
                        }
                    }
                } else {
                    SettingsTextRow(symbol: "magnifyingglass", title: L("Şehir ara", "Search city"),
                                    text: $store.cityQuery, prompt: L("Şehir adı", "City name"))
                        .onChange(of: store.cityQuery) { _, value in
                            store.searchCities(value)
                        }
                    if !store.cityResults.isEmpty {
                        SettingsMenuRow(symbol: nil, title: L("Sonuçlar", "Results"), selection: cityBinding) {
                            Text(L("Seç", "Choose")).tag("")
                            ForEach(store.cityResults) { city in
                                Text(city.name).tag(city.name)
                            }
                        }
                        .padding(.leading, settingsRowTextInset)
                    }
                }
                Divider()
                SettingsRow(symbol: "location", title: L("Koordinat", "Coordinates")) {
                    Text(store.settings.hasLocation
                         ? String(format: "%.4f, %.4f", locale: Language.locale, arguments: [store.settings.latitude, store.settings.longitude])
                         : L("seçilmedi", "not chosen"))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
            }

            SettingsCard(title: L("Hesaplama", "Calculation")) {
                SettingsMenuRow(symbol: "function", title: L("Hesap yöntemi", "Calculation method"), selection: $store.settings.method) {
                    ForEach(CalculationMethods.all) { method in
                        Text(method.name).tag(method.id)
                    }
                }
                Divider()
                SettingsMenuRow(
                    symbol: "sun.max",
                    title: L("Mezhep (İkindi)", "School (Asr)"),
                    caption: L(
                        "Türkiye’de Diyanet ikindi için erken (Şafii) hesabı kullanır. Hanefi yaklaşık 1 saat sonradır.",
                        "In Turkey, Diyanet uses the earlier (Shafi'i) Asr calculation. Hanafi is about 1 hour later."
                    ),
                    selection: $store.settings.school
                ) {
                    Text(L("Diyanet / Şafii", "Diyanet / Shafi'i")).tag(0)
                    Text(L("Hanefi", "Hanafi")).tag(1)
                }
                Divider()
                SettingsToggleRow(title: L("Güneş doğuşunu göster", "Show sunrise"), symbol: "sunrise",
                                  isOn: $store.settings.showSunrise)
            }

            Button(L("Vakitleri yenile", "Refresh times")) {
                Task { await store.refresh() }
            }
        }
    }

    private var quotaTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: L("Sağlayıcılar", "Providers")) {
                providerRow(
                    "Claude", symbol: "sparkle",
                    caption: L("claude CLI’ye sorulur; Hâl anahtar zincirini okumaz.",
                               "Asked of the claude CLI; Hâl never reads the Keychain."),
                    isOn: Binding(get: { store.settings.claudeEnabled }, set: { store.toggle(.claude, enabled: $0) })
                ) {
                    Button(L("Giriş", "Sign in")) {
                        claudeHint = ClaudeAuth.openLogin() ?? L(
                            "Terminal açıldı. Giriş bittikten sonra Kotaları yenile’ye bas.",
                            "Terminal opened. After you finish signing in, tap Refresh quotas."
                        )
                    }
                }
                Divider()
                providerRow(
                    "Codex", symbol: "chevron.left.forwardslash.chevron.right",
                    caption: L("codex app-server’a sorulur; reset hakları da buradan gelir. Oturum yoksa codex login.",
                               "Asked of codex app-server, which also reports banked resets. If signed out, run codex login."),
                    isOn: Binding(get: { store.settings.codexEnabled }, set: { store.toggle(.codex, enabled: $0) })
                ) { EmptyView() }
                Divider()
                providerRow(
                    "Grok", symbol: "xmark",
                    caption: L("grok’un kendi fatura ucundan okunur; oturum ~/.grok/auth.json.",
                               "Read from grok’s own billing endpoint; the session is ~/.grok/auth.json."),
                    isOn: Binding(get: { store.settings.grokEnabled }, set: { store.toggle(.grok, enabled: $0) })
                ) {
                    Button(L("Giriş", "Sign in")) {
                        claudeHint = GrokAuth.openLogin() ?? L(
                            "Terminal açıldı. Giriş bittikten sonra Yenile’ye bas.",
                            "Terminal opened. After you finish signing in, tap Refresh."
                        )
                    }
                }
                if let claudeHint {
                    SettingsFootnote(claudeHint, inset: settingsRowTextInset)
                }
            }

            SettingsCard(title: L("Menü çubuğu", "Menu bar")) {
                SettingsToggleRow(
                    title: L("Kotaları tek alanda sırayla göster", "Show quotas in one rotating item"),
                    detail: L(
                        "Açık sağlayıcıların kalan kotası menü çubuğunda tek bir alanda 3,5 saniyede bir sırayla gösterilir.",
                        "The remaining quota of each enabled provider is shown in one menu bar item, rotating every 3.5 seconds."
                    ),
                    symbol: "rectangle.stack",
                    isOn: $store.settings.menuBarCollapsed
                )
                let visible = quotaVisibilityItems
                if !visible.isEmpty {
                    Divider()
                    SettingsRow(symbol: "menubar.rectangle", title: L("Menü çubuğunda göster", "Show in menu bar"))
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(visible, id: \.id) { item in
                            visibilityToggle(item.title, id: item.id)
                        }
                    }
                    .toggleStyle(TrailingSwitchToggleStyle())
                    .padding(.leading, settingsRowTextInset)
                }
            }

            customQuotaCard

            HStack(spacing: 10) {
                Button(L("Kotaları yenile", "Refresh quotas")) {
                    claudeHint = nil
                    Task { await store.refresh() }
                }
                if store.refreshing { ProgressView().controlSize(.small) }
                Spacer()
                if !installedCLIs.isEmpty {
                    Text(Lf("Bu makinede bulundu: %1$@.", "Found on this Mac: %1$@.", installedCLIs.joined(separator: ", ")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var quotaVisibilityItems: [(id: String, title: String)] {
        var items: [(id: String, title: String)] = []
        if store.settings.claudeEnabled { items.append(("claude", "Claude")) }
        if store.settings.codexEnabled { items.append(("codex", "Codex")) }
        if store.settings.grokEnabled { items.append(("grok", "Grok")) }
        items += store.settings.customProviders.filter(\.enabled).map { ($0.id.uuidString, $0.name) }
        return items
    }

    private func providerRow<Extra: View>(
        _ name: String, symbol: String, caption: String, isOn: Binding<Bool>,
        @ViewBuilder extra: () -> Extra
    ) -> some View {
        let group = store.quotas.first { $0.name == name }
        let extraView = extra()
        return SettingsRow(symbol: symbol, title: name, caption: caption,
                           badge: isOn.wrappedValue ? group.map(Self.statusValue) : nil) {
            HStack(spacing: 8) {
                extraView
                Toggle(name, isOn: isOn).labelsHidden().toggleStyle(.switch)
            }
        }
    }

    private var customQuotaCard: some View {
        SettingsCard(
            title: L("Özel kota kaynakları", "Custom quota sources"),
            footer: L("Komut ya da adres JSON döndürmeli; kullanım yüzdesi ve sıfırlanma zamanı alanlarından okunur.",
                      "The command or address must return JSON; usage percent and reset time are read from its fields.")
        ) {
            ForEach(Array(store.settings.customProviders.enumerated()), id: \.element.id) { index, provider in
                if index > 0 { Divider() }
                HStack(spacing: 12) {
                    Circle().fill(Color(hex: provider.accentHex)).frame(width: 10, height: 10)
                        .frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.name)
                        Text(provider.source.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        store.removeProvider(provider.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help(L("Sil", "Delete"))
                    Toggle(provider.name, isOn: Binding(
                        get: { provider.enabled },
                        set: { value in
                            var next = provider
                            next.enabled = value
                            store.updateProvider(next)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
            if adding {
                if !store.settings.customProviders.isEmpty { Divider() }
                VStack(alignment: .leading, spacing: 10) {
                    SettingsTextRow(symbol: "textformat", title: L("Ad", "Name"), text: $draft.name)
                    SettingsSegmentRow(symbol: "tray.and.arrow.down", title: L("Kaynak", "Source"), selection: $draft.source) {
                        ForEach(CustomSourceKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    switch draft.source {
                    case .manual:
                        SettingsNumberRow(symbol: "number", title: L("Kullanılan", "Used"), value: $draft.used)
                        SettingsNumberRow(symbol: "gauge.with.dots.needle.100percent", title: L("Limit", "Limit"), value: $draft.limit)
                    case .command:
                        SettingsTextRow(symbol: "terminal", title: L("Komut", "Command"), caption: L("JSON yazmalı", "Must print JSON"),
                                        text: $draft.command)
                    case .url:
                        SettingsTextRow(symbol: "link", title: "URL", text: $draft.url, prompt: "https://…")
                        SettingsRow(symbol: "key", title: L("Bearer token", "Bearer token"), caption: L("İsteğe bağlı", "Optional")) {
                            SecureField("", text: $draft.token).textFieldStyle(.roundedBorder).frame(width: 260)
                        }
                    }
                    SettingsRow(symbol: "paintpalette", title: L("Renk", "Color")) {
                        ColorPicker(L("Renk", "Color"), selection: Binding(
                            get: { Color(hex: draft.accentHex) },
                            set: { draft.accentHex = $0.hexString }
                        ))
                        .labelsHidden()
                    }
                    HStack {
                        Spacer()
                        Button(L("Vazgeç", "Cancel")) {
                            adding = false
                            draft = CustomProvider(name: "")
                        }
                        Button(L("Ekle", "Add")) {
                            guard !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            store.addProvider(draft)
                            draft = CustomProvider(name: "")
                            adding = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } else {
                Button {
                    draft = CustomProvider(name: "")
                    adding = true
                } label: {
                    Label(L("Özel kaynak ekle", "Add custom source"), systemImage: "plus")
                }
            }
        }
    }

    private var calendarTab: some View {
        SettingsCard {
            switch calendarAccess {
            case .granted:
                SettingsRow(symbol: "calendar", title: L("Takvim bağlı", "Calendar connected"),
                            caption: L("Bugünün kalan olayları panoda ve Takvim sekmesinde görünür.",
                                       "Today’s remaining events appear on the board and the Calendar tab.")) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            case .notDetermined:
                SettingsRow(symbol: "calendar", title: L("Takvime bağlan", "Connect Calendar"),
                            caption: L("İzin yalnızca bu düğmeye bastığında sorulur; uygulama kendiliğinden istemez.",
                                       "Permission is asked only when you tap this button; the app never asks on its own.")) {
                    Button(L("Bağlan", "Connect")) {
                        Task {
                            await CalendarService.shared.requestAccess()
                            calendarAccess = CalendarService.shared.access
                            await store.refresh()
                        }
                    }
                }
            case .denied:
                SettingsRow(symbol: "calendar.badge.exclamationmark", title: L("Takvim erişimi kapalı", "Calendar access is off"),
                            caption: L("Sistem Ayarları > Gizlilik ve Güvenlik > Takvimler içinden açabilirsin.",
                                       "You can enable it in System Settings > Privacy & Security > Calendars.")) {
                    Button(L("Ayarları aç", "Open Settings")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
    }

    private var fitnessTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(
                title: L("Haftalık program", "Weekly plan"),
                footer: L(
                    "Boş bıraktığın ya da “Dinlenme” yazdığın günler antrenman sayılmaz; seriyi kırmaz.",
                    "Days you leave blank or mark “Rest” don’t count as workouts and don’t break the streak."
                )
            ) {
                SettingsToggleRow(title: L("Antrenman takibi", "Workout tracking"),
                                  symbol: "figure.strengthtraining.traditional",
                                  isOn: $store.settings.trackWorkout)
                if store.settings.trackWorkout {
                    Divider()
                    VStack(spacing: 8) {
                        ForEach(Array(Workout.dayNames.enumerated()), id: \.offset) { index, day in
                            HStack(spacing: 12) {
                                Text(day)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 96, alignment: .leading)
                                TextField(day, text: planBinding(index), prompt: Text(L("Dinlenme", "Rest")))
                                    .labelsHidden()
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    .padding(.leading, settingsRowTextInset)
                    HStack {
                        Spacer()
                        Button(L("Varsayılana dön", "Reset to default")) {
                            store.settings.workoutPlan = Workout.defaultPlan
                        }
                    }
                }
            }

            SettingsCard(
                title: L("İlaç ve takviye", "Meds & supplements"),
                footer: store.settings.trackMedication ? L(
                    "Her ilaç veya takviyeye birden çok saat verebilirsin; her saat ayrı bir doz olarak işaretlenir. Alınmış doz için hatırlatma gönderilmez. Bilgisayara geçmediğin günleri Bugün > Gün Sonu sayfasından tamamlarsın.",
                    "You can give each med or supplement several times; each time is marked as its own dose. No reminder is sent for a dose already taken. Days you weren’t at the computer can be finished from Today > End of day."
                ) : nil
            ) {
                SettingsToggleRow(title: L("İlaç ve takviye takibi", "Meds & supplements tracking"),
                                  symbol: "pills",
                                  isOn: Binding(
                                    get: { store.settings.trackMedication },
                                    set: { store.settings.trackMedication = $0
                                           Task { await store.refreshMedicationNotifications() } }
                                  ))
                if store.settings.trackMedication {
                    Divider()
                    SettingsToggleRow(title: L("Doz saatinde hatırlat", "Remind at dose time"),
                                      symbol: "bell.badge",
                                      isOn: Binding(
                                        get: { store.settings.notifyMedication },
                                        set: { store.settings.notifyMedication = $0
                                               Task { await store.refreshMedicationNotifications() } }
                                      ))
                    ForEach(store.settings.medications) { item in
                        medicationRow(item)
                    }
                    Button {
                        store.addMedication()
                    } label: {
                        Label(L("İlaç veya takviye ekle", "Add med or supplement"), systemImage: "plus")
                    }
                }
            }

            SettingsCard(title: L("Su ve protein", "Water and protein")) {
                SettingsToggleRow(title: L("Takip et", "Track"), symbol: "drop", isOn: $store.settings.trackIntake)
                if store.settings.trackIntake {
                    Divider()
                    SettingsNumberRow(symbol: "target", title: L("Su hedefi", "Water goal"), value: $store.settings.waterGoalML, unit: "ml")
                    SettingsNumberRow(symbol: "plus.circle", title: L("Su hızlı giriş", "Water quick add"), value: $store.settings.waterStepML, unit: "ml")
                    Divider()
                    SettingsNumberRow(symbol: "target", title: L("Protein hedefi", "Protein goal"), value: $store.settings.proteinGoalG, unit: "g")
                    SettingsNumberRow(symbol: "plus.circle", title: L("Protein hızlı giriş", "Protein quick add"), value: $store.settings.proteinStepG, unit: "g")
                }
            }

            if store.settings.trackIntake {
                SettingsCard(
                    title: L("Bugün", "Today"),
                    footer: L(
                        "Panodaki hızlı giriş düğmeleri yukarıdaki adımlarla artırır; günün toplamını buradan elle de düzeltebilirsin.",
                        "The board’s quick-add buttons increase by the steps above; you can also edit today’s total here by hand."
                    )
                ) {
                    SettingsNumberRow(symbol: "drop.fill", title: L("Su", "Water"), value: intakeBinding(Metric.waterML), unit: "ml")
                    SettingsNumberRow(symbol: "fork.knife", title: "Protein", value: intakeBinding(Metric.proteinG), unit: "g")
                }
            }

            SettingsFootnote(L(
                "Set, tekrar ve ağırlık kaydı bilerek yok: menü çubuğu penceresi bunun için dar ve girişi her gün yapmak sürdürülemez. Burada tutulan soru şu — bugün ne var, yaptım mı, kaç gündür sürüyor.",
                "Sets, reps, and weight logging are intentionally missing: the menu bar window is too narrow for that, and entering it every day isn’t sustainable. The question kept here is — what’s on today, did I do it, how many days has it lasted."
            ))
            .padding(.horizontal, 4)
        }
    }

    /// Günün toplamını doğrudan düzenler.
    private func intakeBinding(_ metric: String) -> Binding<Double> {
        Binding(
            get: { DailyLog.shared.value(metric, on: store.now) },
            set: { DailyLog.shared.set(metric, max($0, 0), on: store.now) }
        )
    }

    /// Bir ilaç veya takviye: üstte ad, doz, açık/kapalı ve silme; altta doz saatleri.
    private func medicationRow(_ item: Medication) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(L("Ad", "Name"), text: medBinding(item, \.name), prompt: Text(L("Ad", "Name")))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                TextField(L("Doz", "Dose"), text: medBinding(item, \.dose), prompt: Text(L("Doz", "Dose")))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                Toggle(L("Açık", "On"), isOn: medBinding(item, \.enabled))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help(L("Bu ilacı geçici olarak kapat", "Temporarily turn off this med"))
                Button(role: .destructive) { store.removeMedication(item.id) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(L("Sil", "Delete"))
            }
            HStack(spacing: 6) {
                Image(systemName: "clock").foregroundStyle(.secondary).font(.caption)
                ForEach(Array(item.times.indices), id: \.self) { index in
                    HStack(spacing: 2) {
                        DatePicker("", selection: timeBinding(item, index: index), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .fixedSize()
                        if item.times.count > 1 {
                            Button {
                                var copy = item
                                copy.times.remove(at: index)
                                store.updateMedication(copy)
                            } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.tertiary)
                            .help(L("Bu doz saatini kaldır", "Remove this dose time"))
                        }
                    }
                }
                Button {
                    var copy = item
                    copy.times.append(item.nextFreeTime())
                    store.updateMedication(copy)
                } label: { Image(systemName: "plus.circle") }
                .buttonStyle(.borderless)
                .help(L("Doz saati ekle", "Add dose time"))
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(item.enabled ? 1 : 0.6)
    }

    /// Binlik ayracı olmayan sayı biçimi: hedef alanında "3.000" yerine "3000".
    private var plainNumber: FloatingPointFormatStyle<Double> {
        .number.locale(Language.locale).grouping(.never)
    }

    private func medBinding<Value>(_ item: Medication, _ path: WritableKeyPath<Medication, Value>) -> Binding<Value> {
        Binding(
            get: { item[keyPath: path] },
            set: { newValue in
                var copy = item
                copy[keyPath: path] = newValue
                store.updateMedication(copy)
            }
        )
    }

    private func timeBinding(_ item: Medication, index: Int) -> Binding<Date> {
        Binding(
            get: {
                let minute = item.times.indices.contains(index) ? item.times[index] : 540
                return Medication.date(fromMinute: minute)
            },
            set: { date in
                var copy = item
                guard copy.times.indices.contains(index) else { return }
                copy.times[index] = Medication.minute(from: date)
                store.updateMedication(copy)
            }
        )
    }

    private func planBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                store.settings.workoutPlan.indices.contains(index)
                    ? store.settings.workoutPlan[index] : ""
            },
            set: { value in
                var plan = store.settings.workoutPlan
                while plan.count < 7 { plan.append("") }
                plan[index] = value
                store.settings.workoutPlan = plan
            }
        )
    }

    private var moneyTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: L("Düzenli ödemeler", "Recurring payments")) {
                if store.settings.subscriptions.isEmpty {
                    SettingsFootnote(L(
                        "Abonelik, fatura, taksit — bir kez gir, yenileme tarihi kendiliğinden ilerler.",
                        "Subscription, bill, installment — enter once and the renewal date advances on its own."
                    ))
                }
                ForEach(store.settings.subscriptions) { item in
                    subscriptionRow(item)
                }
                Button {
                    store.addSubscription(Subscription(name: L("Yeni", "New"), amount: 0, anchor: Date()))
                } label: {
                    Label(L("Ödeme ekle", "Add payment"), systemImage: "plus")
                }
            }

            SettingsCard {
                SettingsMenuRow(
                    symbol: "bell",
                    title: L("Yenilemeden önce hatırlat", "Remind before renewal"),
                    caption: L("Bildirim, yenileme gününden geriye sayarak sabah 09:00’da düşer.",
                               "The notification fires at 09:00 on the morning counted back from the renewal day."),
                    selection: Binding(
                        get: { store.settings.notifyRenewalDays },
                        set: { store.settings.notifyRenewalDays = $0
                               Task { await store.refreshRenewalNotifications() } }
                    )
                ) {
                    Text(L("Kapalı", "Off")).tag(0)
                    ForEach([1, 3, 7], id: \.self) {
                        Text(Lf("%1$d gün önce", "%1$d days before", $0)).tag($0)
                    }
                }
            }

            if !store.monthlyTotals.isEmpty {
                SettingsCard(
                    title: L("Aylık toplam", "Monthly total"),
                    footer: L("Yıllık ödemeler 12’ye bölünerek eklenir.", "Yearly payments are divided by 12 and added in.")
                ) {
                    ForEach(store.monthlyTotals, id: \.currency) { total in
                        SettingsRow(symbol: "sum", title: total.currency) {
                            Text("\(Subscription.symbol(for: total.currency))\(String(format: "%.2f", locale: Language.locale, arguments: [total.amount]))")
                                .monospacedDigit()
                                .font(.body.weight(.semibold))
                        }
                    }
                }
            }
        }
    }

    private func subscriptionRow(_ item: Subscription) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(L("Ad", "Name"), text: binding(item, \.name))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                Toggle(L("Açık", "On"), isOn: binding(item, \.enabled))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Button(role: .destructive) {
                    store.removeSubscription(item.id)
                } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help(L("Sil", "Delete"))
            }
            HStack(spacing: 8) {
                TextField(L("Tutar", "Amount"), value: binding(item, \.amount), format: plainNumber)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                Picker(L("Para birimi", "Currency"), selection: binding(item, \.currency)) {
                    ForEach(Subscription.currencies, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().fixedSize()
                Picker(L("Dönem", "Period"), selection: binding(item, \.period)) {
                    ForEach(Subscription.Period.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
                DatePicker(L("Başlangıç", "Start"), selection: binding(item, \.anchor), displayedComponents: .date)
                    .labelsHidden()
                    .fixedSize()
                Spacer(minLength: 0)
            }
            Text(Lf(
                "Sıradaki yenileme: %1$@ · %2$d gün",
                "Next renewal: %1$@ · %2$d days",
                TimeFormatters.longDate(item.nextRenewal(after: Date())),
                item.daysUntilRenewal()
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(item.enabled ? 1 : 0.6)
    }

    private func binding<Value>(_ item: Subscription, _ path: WritableKeyPath<Subscription, Value>) -> Binding<Value> {
        Binding(
            get: { item[keyPath: path] },
            set: { newValue in
                var copy = item
                copy[keyPath: path] = newValue
                store.updateSubscription(copy)
            }
        )
    }

    private var menuBarTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(
                title: L("Panel sekmeleri", "Panel tabs"),
                footer: L("Sıra ve görünürlük menü çubuğu panelindeki sekmelere uygulanır.",
                          "Order and visibility apply to the tabs of the menu bar panel.")
            ) {
                PanelLayoutEditor()
                Button(L("Özellikleri yönet", "Manage features")) { tab = .features }
            }

            SettingsCard(
                title: L("Bugün panosunda göster", "Show on Today board"),
                footer: L(
                    "Modülü kapatmadan yalnızca panodaki satırını kaldırır: sekmesi, ölçümü ve bildirimleri yerinde kalır. Gizlenen satır akşam gün özetinde de görünmez. Bir kez görülen satır, o an üretilmese bile listede kalır.",
                    "Hides only the board row without turning the module off: its tab, metrics, and notifications stay. A hidden row also stays out of the evening daily summary. Once a row has been seen, it remains in the list even when it isn’t produced right then."
                )
            ) {
                if store.summaryCatalog.isEmpty {
                    SettingsFootnote(L("Pano satırları göründükçe burada listelenir.",
                                       "Board rows are listed here as they appear."))
                } else {
                    ForEach(Array(store.summaryCatalog.enumerated()), id: \.element.id) { index, line in
                        if index > 0 { Divider() }
                        SettingsRow(symbol: nil, title: SummaryCatalogCopy.title(id: line.id, fallback: line.title),
                                    caption: line.module.title) {
                            Toggle(line.title, isOn: Binding(
                                get: { store.isSummaryLineVisible(line.id) },
                                set: { store.setSummaryLine(line.id, visible: $0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }
                    }
                }
            }

            SettingsCard(title: L("Menü çubuğu", "Menu bar")) {
                SettingsRow(symbol: "moon.stars", title: L("Namaz vakitleri", "Prayer times"),
                            caption: L("Kota ikonları Ayarlar › Kotalar’dan yönetilir.",
                                       "Quota icons are managed in Settings › Quotas.")) {
                    Toggle(L("Namaz vakitleri", "Prayer times"), isOn: Binding(
                        get: { store.isMenuBarVisible("prayer") },
                        set: { store.setMenuBarVisible("prayer", $0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                Divider()
                SettingsMenuRow(
                    symbol: "cursorarrow.click",
                    title: L("İkona tıklayınca aç", "Open on icon click"),
                    caption: L(
                        "Özet ikon ve hiçbir modül görünmezken duran genel ikon her koşulda panoyu açar; ikisi de tek bir şeyi değil genel durumu temsil eder.",
                        "The summary icon and the general icon shown when no modules are visible always open the board; both represent overall status, not a single item."
                    ),
                    selection: $store.settings.menuBarClickOpens
                ) {
                    ForEach(MenuBarClickTarget.allCases) { Text($0.title).tag($0) }
                }
                Divider()
                SettingsToggleRow(
                    title: L("Diğer ekranların menü çubuğunda da göster", "Also show on other displays’ menu bars"),
                    detail: L(
                        "macOS çoğu ekranda extra’ları zaten kopyalar. Açarsan ikinci satır oluşabilir; kapalı tut.",
                        "macOS already mirrors extras on most displays. Turning this on can create a second row; leave it off."
                    ),
                    symbol: "display.2",
                    isOn: $store.settings.mirrorToOtherDisplays
                )
            }
        }
    }

    private func visibilityToggle(_ title: String, id: String) -> some View {
        Toggle(title, isOn: Binding(
            get: { store.isMenuBarVisible(id) },
            set: { store.setMenuBarVisible(id, $0) }
        ))
    }

    private var focusAppsBinding: Binding<String> {
        Binding(
            get: { store.settings.focusApps.joined(separator: ", ") },
            set: { text in
                store.settings.focusApps = text
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                store.applyFocusTracking()
            }
        )
    }

    private var notificationsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(
                title: L("Namaz", "Prayer"),
                footer: L("Güneş vakti yalnızca İbadet’te “Güneş doğuşunu göster” açıkken bildirilir.",
                          "Sunrise is notified only when “Show sunrise” is on in Prayer.")
            ) {
                SettingsToggleRow(title: L("Vakit bildirimi", "Prayer-time notification"), symbol: "moon.stars",
                                  isOn: notifyBinding(\.notifyPrayer))
                if store.settings.notifyPrayer {
                    Divider()
                    SettingsMenuRow(symbol: "clock", title: L("Ne zaman", "When"), selection: notifyBinding(\.notifyPrayerMinutes)) {
                        Text(L("Vakit girince", "When time begins")).tag(0)
                        Text(L("5 dakika önce", "5 minutes before")).tag(5)
                        Text(L("10 dakika önce", "10 minutes before")).tag(10)
                        Text(L("15 dakika önce", "15 minutes before")).tag(15)
                        Text(L("30 dakika önce", "30 minutes before")).tag(30)
                    }
                }
            }

            SettingsCard(
                title: L("Kotalar", "Quotas"),
                footer: L("Her olay bir kez bildirilir; aynı pencere için tekrarlamaz.",
                          "Each event is notified once; it doesn’t repeat for the same window.")
            ) {
                SettingsToggleRow(
                    title: L("Kota sıfırlanınca haber ver", "Notify when a quota resets"),
                    detail: L("Limit dolduğunda elle kontrol etmek yerine, yeniden kullanılabilir olunca bildirir.",
                              "Instead of checking by hand when a limit is full, it notifies you when it’s usable again."),
                    symbol: "arrow.clockwise",
                    isOn: notifyBinding(\.notifyQuotaReset)
                )
                Divider()
                SettingsToggleRow(title: L("Eşik aşılınca uyar", "Warn when a threshold is crossed"),
                                  symbol: "exclamationmark.triangle",
                                  isOn: notifyBinding(\.notifyQuotaThreshold))
                if store.settings.notifyQuotaThreshold {
                    SettingsMenuRow(symbol: nil, title: L("Eşik", "Threshold"), selection: notifyBinding(\.notifyQuotaThresholdPercent)) {
                        ForEach([50, 60, 70, 80, 90], id: \.self) { value in
                            Text("%\(value)").tag(value)
                        }
                    }
                    .padding(.leading, settingsRowTextInset)
                }
            }

            SettingsCard(title: L("Gün özeti", "Daily summary")) {
                SettingsToggleRow(
                    title: L("Akşam gün özeti gönder", "Send evening daily summary"),
                    detail: L("Günün sonunda derin çalışma, namaz ve hedeflerin özetini bildirir.",
                              "At the end of the day it notifies a summary of deep work, prayer, and your goals."),
                    symbol: "text.badge.checkmark",
                    isOn: notifyBinding(\.notifyDailySummary)
                )
                if store.settings.notifyDailySummary {
                    SettingsMenuRow(symbol: nil, title: L("Saat", "Time"), selection: notifyBinding(\.dailySummaryHour)) {
                        ForEach(Array(17...23), id: \.self) { hour in
                            Text(String(format: "%02d:00", locale: Language.locale, arguments: [hour])).tag(hour)
                        }
                    }
                    .padding(.leading, settingsRowTextInset)
                }
            }

            SettingsCard(title: L("Gün sonu", "End of day")) {
                SettingsToggleRow(
                    title: L("Gün sonu hatırlatması", "End-of-day reminder"),
                    detail: L(
                        "Seçtiğin saatte bildirim gelir. Tıklayınca Gün Sonu sayfası açılır; kaçırdığın namaz, ilaç ve antrenman işaretlerini oradan düzeltirsin.",
                        "A notification arrives at the time you choose. Tapping it opens the End of day page, where you can fix missed prayer, med, and workout marks."
                    ),
                    symbol: "moon.haze",
                    isOn: notifyBinding(\.notifyDayClose)
                )
                if store.settings.notifyDayClose {
                    SettingsMenuRow(symbol: nil, title: L("Saat", "Time"), selection: notifyBinding(\.dayCloseHour)) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d:00", locale: Language.locale, arguments: [hour])).tag(hour)
                        }
                    }
                    .padding(.leading, settingsRowTextInset)
                }
            }

            SettingsFootnote(L(
                "İzin, ilk bildirimi açtığında istenir. Sistem Ayarları > Bildirimler > Hâl üzerinden değiştirebilirsin.",
                "Permission is requested when you turn on the first notification. You can change it in System Settings > Notifications > Hâl."
            ))
            .padding(.horizontal, 4)
        }
    }

    /// Bildirim ayarları değişince izin ve planlama yeniden kurulur.
    private func notifyBinding<Value>(_ path: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings[keyPath: path] },
            set: {
                store.settings[keyPath: path] = $0
                store.notificationsChanged()
            }
        )
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard {
                SettingsMenuRow(
                    symbol: "globe",
                    title: L("Dil", "Language"),
                    caption: L("Başlangıçta Mac’in dili kullanılır.", "Starts in your Mac’s language."),
                    selection: $store.settings.language
                ) {
                    ForEach(LanguageChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                Divider()
                SettingsToggleRow(
                    title: L("Açılışta başlat", "Launch at login"),
                    detail: L("Mac açıldığında Hâl menü çubuğunda hazır olur.", "Hâl is ready in the menu bar when your Mac starts."),
                    symbol: "power",
                    isOn: Binding(
                        get: { store.settings.launchAtLogin },
                        set: { value in
                            store.settings.launchAtLogin = value
                            store.applyLaunchAtLogin()
                        }
                    )
                )
            }

            SettingsCard(title: L("Pano", "Board")) {
                SettingsTextRow(symbol: "person", title: L("Adın", "Your name"),
                                caption: L("Panodaki selamlamada kullanılır.", "Used in the board greeting."),
                                text: $store.settings.displayName, prompt: L("Adın", "Your name"), width: 220)
                Divider()
                SettingsRow(symbol: "doc.text", title: L("Günlük kayıt", "Daily log"), caption: DailyLog.fileURL.path) {
                    Button(L("Finder’da göster", "Show in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([DailyLog.fileURL])
                    }
                }
            }

            cleaningCard

            if legacyKeychainCount > 0 {
                legacyKeychainCard
            }

            if let error = store.lastError {
                Text(error).foregroundStyle(.red).font(.caption)
            }
        }
    }

    private var cleaningCard: some View {
        SettingsCard(
            title: L("Temizlik modu", "Cleaning mode"),
            footer: L(
                "Klavye, sistem tuşları, kaydırma ve trackpad hareketleri kilitlenir; fare ve trackpad tıklamaları çalışır. Kilidi açmak için Esc’ye 5 kez bas ya da ekrandaki Kilidi aç düğmesine tıkla.",
                "The keyboard, system keys, scrolling and trackpad gestures are locked; mouse and trackpad clicks still work. Press Esc 5 times or click Unlock on screen to stop."
            )
        ) {
            SettingsToggleRow(
                title: L("Klavyeyi kilitle", "Lock the keyboard"),
                detail: L("Klavyeyi silerken anlamsız yazı yazılmaz.", "Wipe the keyboard without typing gibberish."),
                symbol: "bubbles.and.sparkles",
                isOn: Binding(get: { store.cleaningMode }, set: { store.setCleaningMode($0) })
            )
            Divider()
            SettingsTextRow(symbol: "textformat", title: L("Başlık", "Title"), text: $store.settings.cleaningTitle,
                            prompt: L("Klavye temizlik için kilitlendi", "Keyboard locked for cleaning"))
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow(symbol: "note.text", title: L("Ekrandaki not", "Note on screen"),
                            caption: L("Kilit boyunca ekranda durur; boşsa gösterilmez.",
                                       "Stays on screen while locked; hidden when empty."))
                TextField(L("Ekrandaki not", "Note on screen"), text: $store.settings.cleaningHint,
                          prompt: Text(L("ör. “Bilgisayar çalışıyor, dokunmayalım.”", "e.g. “Computer at work, please don’t touch.”")),
                          axis: .vertical)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
                    .padding(.leading, settingsRowTextInset)
            }
            Divider()
            SettingsToggleRow(
                title: L("Ekranı görünür tut", "Keep the screen visible"),
                detail: L("Karartma yerine köşede küçük bir gösterge çıkar; başlık ve not yine görünür.",
                          "A small indicator appears in the corner instead of the blackout; the title and note still show."),
                symbol: "eye",
                isOn: $store.settings.cleaningKeepScreenVisible
            )
            if !DeviceModes.shared.accessibilityTrusted {
                Divider()
                SettingsRow(symbol: "hand.raised", title: L("Erişilebilirlik izni gerekli", "Accessibility permission needed"),
                            caption: L("İzin olmadan temizlik modu başlamaz; böylece açılamayan bir klavyeyle kalmazsın.",
                                       "Without it cleaning mode won’t start, so you can’t get stuck with a locked keyboard.")) {
                    HStack(spacing: 8) {
                        Button(L("İzin iste", "Request")) { DeviceModes.shared.requestKeyboardLockPermission() }
                        Button(L("Ayarları aç", "Open Settings")) { DeviceModes.shared.openAccessibilitySettings() }
                    }
                }
            }
        }
    }

    private var legacyKeychainCard: some View {
        SettingsCard(title: L("Eski anahtar zinciri kayıtları", "Legacy Keychain records")) {
            SettingsFootnote(Lf(
                "Gizli değerler artık anahtar zincirinde değil, yalnızca senin okuyabildiğin bir dosyada tutuluyor (%1$@). Anahtar zincirinde %2$d eski kayıt duruyor; uygulama bunlara dokunmuyor, yani şifre sorusu çıkmıyor.",
                "Secrets are no longer in Keychain; they’re kept only in a file only you can read (%1$@). Keychain still has %2$d legacy records; the app leaves them alone, so no password prompt appears.",
                SecretStore.fileURL.path,
                legacyKeychainCount
            ))
            if let legacyNote {
                SettingsFootnote(legacyNote)
            }
            Divider()
            SettingsRow(symbol: "tray.and.arrow.down", title: L("Değerleri taşı ve kayıtları sil", "Move values and delete records"),
                        caption: L("Bir defalığına kayıt başına şifre sorar; sonrasında kayıtlar silinir ve bir daha sorulmaz.",
                                   "It asks for a password once per record; afterward the records are deleted and it won’t ask again.")) {
                Button(L("Taşı", "Move")) {
                    let result = SecretStore.importLegacyKeychainItems()
                    legacyKeychainCount = SecretStore.legacyItemCount()
                    legacyNote = result.failed > 0
                        ? Lf(
                            "%1$d değer taşındı, %2$d kayıt okunamadı.",
                            "%1$d values moved, %2$d records could not be read.",
                            result.moved,
                            result.failed
                        )
                        : Lf("%1$d değer taşındı.", "%1$d values moved.", result.moved)
                    Task { await store.refresh() }
                }
            }
            Divider()
            SettingsRow(symbol: "trash", title: L("Okumadan sil", "Delete without reading"),
                        caption: L("Silinen kayıtlar geri gelmez.", "Deleted records can’t be restored.")) {
                Button(L("Sil", "Delete"), role: .destructive) {
                    let removed = SecretStore.discardLegacyKeychainItems()
                    legacyKeychainCount = SecretStore.legacyItemCount()
                    legacyNote = Lf("%1$d kayıt silindi.", "%1$d records deleted.", removed)
                }
            }
        }
    }

    private var focusTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(
                title: L("Derin çalışma", "Deep work"),
                footer: L(
                    "Öndeki uygulama listedeyse ve Mac iki dakikadır boşta değilse süre kendiliğinden sayılır.",
                    "Time counts on its own when the frontmost app is on the list and the Mac hasn’t been idle for two minutes."
                )
            ) {
                SettingsToggleRow(title: L("Otomatik ölç", "Measure automatically"), symbol: "timer",
                                  isOn: Binding(
                                    get: { store.settings.focusTracking },
                                    set: { store.settings.focusTracking = $0; store.applyFocusTracking() }
                                  ))
                Divider()
                SettingsNumberRow(symbol: "target", title: L("Günlük hedef", "Daily goal"),
                                  value: Binding(
                                    get: { Double(store.settings.focusGoalMinutes) },
                                    set: { store.settings.focusGoalMinutes = max(0, Int($0)) }
                                  ),
                                  unit: L("dk", "min"))
            }
            if store.settings.focusTracking {
                SettingsCard(
                    title: L("Çalışma uygulamaları", "Work apps"),
                    footer: L(
                        "Virgülle ayır. Uygulama adı veya bundle kimliği bu parçalardan birini içerirse odak sayılır.",
                        "Separate with commas. Focus counts if the app name or bundle id contains any of these parts."
                    )
                ) {
                    TextField(L("Uygulamalar", "Apps"), text: focusAppsBinding, axis: .vertical)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                        .font(.system(size: 12, design: .monospaced))
                }
            }
            SettingsFootnote(L(
                "Sayaç ve yedi günlük geçmiş yerel daily.json dosyasında tutulur; pomodoro ve görev yönetimi bilerek yok.",
                "The counter and seven-day history live in the local daily.json file; pomodoro and task management are intentionally absent."
            ))
            .padding(.horizontal, 4)
        }
    }

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard { identityBlock }
            SettingsCard(title: L("Geliştirici", "Developer")) {
                SettingsRow(symbol: "person.crop.circle", title: "Tahsin Sungur") {
                    HStack(spacing: 14) {
                        Link("sungur.dev", destination: URL(string: "https://sungur.dev")!)
                        Link("@tahsingibi", destination: URL(string: "https://x.com/tahsingibi")!)
                    }
                }
            }
            sourcesBlock
            diagnosticsBlock
        }
    }

    private var identityBlock: some View {
        HStack(alignment: .center, spacing: 16) {
            BrandMark(icon: .app, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Hâl").font(.system(size: 22, weight: .semibold))
                Text(L("Kişisel durum panosu", "Personal status board"))
                    .foregroundStyle(.secondary)
                Text(Self.versionText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 8) {
                Button(L("Güncellemeleri denetle", "Check for updates")) { UpdateController.check() }
                HStack(spacing: 8) {
                    Button(L("Yenilikler", "What's New")) { tab = .changelog }
                    Button(L("Tanıtım", "Introduction")) {
                        NotificationCenter.default.post(name: .halShowWelcome, object: nil)
                    }
                }
                Text(L("Yeni sürüm olunca sorar. Kendiliğinden kurmaz.",
                       "It asks when a new version is available. It never installs on its own."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var changelogTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Changelog.releases) { release in
                SettingsCard {
                    HStack {
                        Text(release.version).font(.headline)
                        Spacer()
                        Text(release.dateText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(release.notes, id: \.self) { note in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•").foregroundStyle(.tertiary)
                                Text(note)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// Verinin nereden geldiğini gösterir ve aynı anda sağlık paneli görevi görür:
    /// hangi kaynak çalışıyor, hangisi oturum bekliyor tek bakışta belli olur.
    private var sourcesBlock: some View {
        SettingsCard {
            HStack {
                Text(L("Veri kaynakları", "Data sources")).font(.headline)
                Spacer()
                if store.refreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Button(L("Yenile", "Refresh")) { Task { await store.refresh() } }
                }
            }
            ForEach(Array(sourceRows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider() }
                HStack(spacing: 12) {
                    Circle()
                        .fill(row.tint)
                        .frame(width: 8, height: 8)
                        .frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                        Text(row.origin)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(row.value)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var diagnosticsBlock: some View {
        HStack(spacing: 10) {
            Button {
                let text = diagnosticsText()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copiedDiagnostics = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    copiedDiagnostics = false
                }
            } label: {
                Label(
                    copiedDiagnostics ? L("Kopyalandı", "Copied") : L("Tanılamayı kopyala", "Copy diagnostics"),
                    systemImage: copiedDiagnostics ? "checkmark" : "doc.on.doc"
                )
            }
            Spacer()
            Text(Self.systemText)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Hakkında verileri

    private struct SourceRow: Identifiable {
        var id: String
        var name: String
        var origin: String
        var value: String
        var tint: Color
    }

    private var sourceRows: [SourceRow] {
        var rows: [SourceRow] = []
        if store.settings.isModuleEnabled(.usage) {
            for group in store.quotas {
                rows.append(
                    SourceRow(
                        id: group.id,
                        name: group.name,
                        origin: Self.origin(for: group.kind),
                        value: Self.statusValue(group),
                        tint: Self.statusTint(group.status)
                    )
                )
            }
        }
        if store.settings.isModuleEnabled(.prayer) {
            let located = store.settings.hasLocation
            let ready = store.prayers != nil
            rows.append(
                SourceRow(
                    id: "prayer",
                    name: L("Namaz", "Prayer"),
                    origin: located
                        ? "aladhan.com · \(store.settings.locationLabel)"
                        : L("konum seçilmedi", "location not chosen"),
                    value: !located
                        ? L("konum seç", "choose location")
                        : (store.nextPrayer.map { "\($0.name) \(TimeFormatters.clock($0.time))" }
                            ?? (ready ? "—" : L("yükleniyor", "loading"))),
                    tint: located && ready ? .green : .orange
                )
            )
        }
        return rows
    }

    private static func origin(for kind: ProviderKind) -> String {
        switch kind {
        case .claude: return "claude CLI"
        case .codex: return "codex app-server"
        case .grok: return "grok login"
        case .custom: return L("özel kaynak", "custom source")
        }
    }

    private static func statusValue(_ group: QuotaGroup) -> String {
        switch group.status {
        case .ready:
            return group.menuBarOverride ?? group.headlineWindow.map { "\($0.percentText) · \($0.title)" } ?? L("hazır", "ready")
        case .loading: return L("yükleniyor", "loading")
        case .missingAuth: return L("oturum yok", "no session")
        case .error: return L("okunamadı", "unreadable")
        }
    }

    private static func statusTint(_ status: QuotaStatus) -> Color {
        switch status {
        case .ready: return .green
        case .loading: return .secondary
        case .missingAuth: return .orange
        case .error: return .red
        }
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return Lf("sürüm %1$@ (%2$@)", "version %1$@ (%2$@)", short, build)
    }

    private static var systemText: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        return "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · \(arch)"
    }

    /// Bir şey ters gittiğinde yapıştırılabilecek tek parça özet.
    private func diagnosticsText() -> String {
        var lines = [
            "Hâl \(Self.versionText)",
            Self.systemText,
            Lf("Modüller: %1$@", "Modules: %1$@", store.modules.map(\.title).joined(separator: ", "))
        ]
        lines.append("")
        for row in sourceRows {
            lines.append("- \(row.name) [\(row.origin)]: \(row.value)")
        }
        let problems = store.quotas.compactMap { group -> String? in
            guard let message = group.message, group.status != .ready else { return nil }
            return "- \(group.name): \(message)"
        }
        if !problems.isEmpty {
            lines.append("")
            lines.append(L("Sorunlar:", "Problems:"))
            lines.append(contentsOf: problems)
        }
        if let error = store.lastError {
            lines.append("")
            lines.append(Lf("Son hata: %1$@", "Last error: %1$@", error))
        }
        return lines.joined(separator: "\n")
    }

    private var installedCLIs: [String] {
        [
            ProcessRunner.which("claude") != nil ? "claude" : nil,
            ProcessRunner.which("codex") != nil ? "codex" : nil,
            ProcessRunner.which("grok") != nil ? "grok" : nil
        ].compactMap { $0 }
    }

    private var countryBinding: Binding<String> {
        Binding(
            get: { store.settings.countryCode },
            set: { code in
                if code.isEmpty {
                    store.clearLocation()
                    return
                }
                if let country = store.countries.first(where: { $0.code == code }) {
                    store.selectCountry(country)
                }
            }
        )
    }

    private var stateBinding: Binding<String> {
        Binding(
            get: { store.settings.state },
            set: { name in
                if let region = store.regions.first(where: { $0.name == name }) {
                    Task { await store.selectRegion(region) }
                } else {
                    store.settings.state = name
                }
            }
        )
    }

    private var cityBinding: Binding<String> {
        Binding(
            get: { store.settings.city },
            set: { name in
                let match = store.cities.first(where: { $0.name == name })
                    ?? store.cityResults.first(where: { $0.name == name })
                    ?? PlaceCity(name: name, latitude: nil, longitude: nil)
                Task { await store.selectCity(match) }
            }
        )
    }
}

private extension Color {
    var hexString: String {
        let ns = NSColor(self)
        guard let rgb = ns.usingColorSpace(.sRGB) else { return "E8B84A" }
        return String(format: "%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }
}
