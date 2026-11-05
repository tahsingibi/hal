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
    @AppStorage("hal.settings.quotaTab") private var quotaPart = "general"

    /// Belirli bir sekmeyle açılabilir; bildirimden ya da popover'dan doğrudan
    /// ilgili sayfaya götürmek için.
    init(initialTab: SettingsTab = .features) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        // Sekme şeridi yerine kenar çubuğu: bölüm sayısı arttıkça başlıklar
        // kırpılmıyor, yeni bölüm eklemek de genişlik hesabı gerektirmiyor.
        NavigationSplitView {
            List(selection: sidebarSelection) {
                ForEach(filteredGroups, id: \.group.id) { entry in
                    if entry.group.title.isEmpty || !query.isEmpty {
                        ForEach(entry.tabs) { row($0) }
                    } else {
                        Section(isExpanded: groupExpanded(entry.group)) {
                            ForEach(entry.tabs) { row($0) }
                        } header: {
                            Text(entry.group.title)
                        }
                    }
                }
                if filteredGroups.isEmpty {
                    Text(L("Sonuç bulunamadı", "No results"))
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 210, ideal: 228, max: 280)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(L("Ayarlarda ara", "Search settings"), text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(10)
            }
        } detail: {
            // Form kendi içinde kayar. Dıştan bir ScrollView'a sarmak iç içe kaydırma
            // doğurup alan tıklamalarını ve metin girişini engelliyordu.
            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: tab.symbol).font(.system(size: 16)).foregroundStyle(.secondary)
                    Text(tab.title).font(.system(size: 18, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 6)
                if let module = tab.module, !store.settings.isModuleEnabled(module) {
                    HStack {
                        Text(L("Bu modül kapalı. Tercihlerin korunuyor.", "This module is disabled. Your preferences are kept."))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Etkinleştir", "Enable")) { store.setModule(module, enabled: true) }
                    }
                    .padding(14)
                    .background(Color.accentColor.opacity(0.06))
                }
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle(L("Hâl Ayarları", "Hâl Settings"))
        }
        .frame(minWidth: 860, minHeight: 620)
        .environment(\.locale, Language.locale)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { navigateBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(backStack.isEmpty).help(L("Geri", "Back"))
                Button { navigateForward() } label: { Image(systemName: "chevron.right") }
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

    private func groupExpanded(_ group: SettingsTab.Group) -> Binding<Bool> {
        Binding(get: { !collapsedGroups.split(separator: ",").contains(Substring(group.rawValue)) }, set: { expanded in
            var collapsed = Set(collapsedGroups.split(separator: ",").map(String.init))
            if expanded { collapsed.remove(group.rawValue) } else { collapsed.insert(group.rawValue) }
            collapsedGroups = collapsed.sorted().joined(separator: ",")
        })
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
        Label {
            Text(item.title)
        } icon: {
            Image(systemName: item.symbol).foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 3)
        .tag(item)
    }

    private var sidebarSelection: Binding<SettingsTab?> {
        Binding(
            get: { tab },
            set: { selected in
                if let selected { tab = selected }
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .general: generalTab
        case .features: FeatureHubView(onSettings: { tab = $0 })
        case .permissions: PermissionsView(onSettings: { tab = $0 })
        case .appearance: menuBarTab
        case .notifications: notificationsTab
        case .wake: wakeTab
        case .switcher: WindowSwitcherSettingsView()
        case .displays: DisplaySettingsView()
        case .focus: focusTab
        case .quota: quotaTab
        case .worship: worshipTab
        case .calendar: calendarTab
        case .fitness: fitnessTab
        case .money: moneyTab
        case .downloader: downloaderTab
        case .ports: portsTab
        case .homebrew: HomebrewPanel().padding(24)
        case .mixer: VolumeMixerPanel().padding(24)
        case .updates: UpdatesPanel().padding(24)
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
        Form {
            Section(L("İbadet", "Prayer")) {
                Toggle(L("Namaz takibi", "Prayer tracking"), isOn: $store.settings.trackPrayers)
                Text(L(
                    "Vakit geçtikten sonra Namaz sekmesinden işaretlersin; pano gün içi sayıyı ve seriyi gösterir. Bilgisayara geçmediğin günleri Bugün > Gün Sonu sayfasından tamamlarısın.",
                    "After a prayer time passes, mark it on the Prayer tab; the board shows today’s count and streak. Days you weren’t at the computer can be finished from Today > End of day."
                ))
                    .font(.caption).foregroundStyle(.secondary)

                Picker(L("Ülke", "Country"), selection: countryBinding) {
                    Text(L("Seç", "Choose")).tag("")
                    ForEach(store.countries) { country in
                        Text(country.localizedName).tag(country.code)
                    }
                }
                Picker(L("İl / Eyalet", "State / Province"), selection: stateBinding) {
                    Text(L("Seç", "Choose")).tag("")
                    ForEach(store.regions) { region in
                        Text(region.name).tag(region.name)
                    }
                }
                if !store.cities.isEmpty {
                    Picker(L("Şehir / İlçe", "City / District"), selection: cityBinding) {
                        Text(L("Seç", "Choose")).tag("")
                        ForEach(store.cities) { city in
                            Text(city.name).tag(city.name)
                        }
                    }
                } else {
                    TextField(L("Şehir ara", "Search city"), text: $store.cityQuery)
                        .onChange(of: store.cityQuery) { _, value in
                            store.searchCities(value)
                        }
                    if !store.cityResults.isEmpty {
                        Picker(L("Sonuçlar", "Results"), selection: cityBinding) {
                            Text(L("Seç", "Choose")).tag("")
                            ForEach(store.cityResults) { city in
                                Text(city.name).tag(city.name)
                            }
                        }
                    }
                }
                Picker(L("Hesap yöntemi", "Calculation method"), selection: $store.settings.method) {
                    ForEach(CalculationMethods.all) { method in
                        Text(method.name).tag(method.id)
                    }
                }
                Picker(L("Mezhep (İkindi)", "School (Asr)"), selection: $store.settings.school) {
                    Text(L("Diyanet / Şafii", "Diyanet / Shafi'i")).tag(0)
                    Text(L("Hanefi", "Hanafi")).tag(1)
                }
                Text(L(
                    "Türkiye’de Diyanet ikindi için erken (Şafii) hesabı kullanır. Hanefi yaklaşık 1 saat sonradır.",
                    "In Turkey, Diyanet uses the earlier (Shafi'i) Asr calculation. Hanafi is about 1 hour later."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(L("Güneş doğuşunu göster", "Show sunrise"), isOn: $store.settings.showSunrise)
                LabeledContent(L("Koordinat", "Coordinates")) {
                    Text(store.settings.hasLocation
                         ? String(format: "%.4f, %.4f", locale: Language.locale, arguments: [store.settings.latitude, store.settings.longitude])
                         : L("seçilmedi", "not chosen"))
                        .foregroundStyle(.secondary)
                }
                Button(L("Vakitleri yenile", "Refresh times")) {
                    Task { await store.refresh() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var quotaTab: some View {
        VStack(spacing: 0) {
            Picker("", selection: $quotaPart) {
                Text(L("Genel", "General")).tag("general")
                Text("Claude").tag("claude")
                Text("Codex").tag("codex")
                Text("Grok").tag("grok")
                Text(L("Özel", "Custom")).tag("custom")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 480)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            Form {
                switch quotaPart {
                case "claude": claudeQuotaSection
                case "codex": codexQuotaSection
                case "grok": grokQuotaSection
                case "custom": customQuotaSection
                default: generalQuotaSection
                }
            }
            .formStyle(.grouped)
        }
    }

    private var generalQuotaSection: some View {
        Group {
            Section(L("Menü çubuğu", "Menu bar")) {
                Toggle(L("Kotaları tek alanda sırayla göster", "Show quotas in one rotating item"), isOn: $store.settings.menuBarCollapsed)
                Text(L(
                    "Açık sağlayıcıların kalan kotası menü çubuğunda tek bir alanda 3,5 saniyede bir sırayla gösterilir.",
                    "The remaining quota of each enabled provider is shown in one menu bar item, rotating every 3.5 seconds."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if store.settings.claudeEnabled { visibilityToggle("Claude", id: "claude") }
                if store.settings.codexEnabled { visibilityToggle("Codex", id: "codex") }
                if store.settings.grokEnabled { visibilityToggle("Grok", id: "grok") }
                ForEach(store.settings.customProviders.filter(\.enabled)) { provider in
                    visibilityToggle(provider.name, id: provider.id.uuidString)
                }
            }
            Section {
                Button(L("Kotaları yenile", "Refresh quotas")) {
                    claudeHint = nil
                    Task { await store.refresh() }
                }
                if !installedCLIs.isEmpty {
                    Text(Lf("Bu makinede bulundu: %1$@.", "Found on this Mac: %1$@.", installedCLIs.joined(separator: ", ")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var claudeQuotaSection: some View {
        Section("Claude") {
            Toggle(L("Claude kotasını izle", "Track the Claude quota"), isOn: Binding(
                get: { store.settings.claudeEnabled },
                set: { store.toggle(.claude, enabled: $0) }
            ))
            HStack {
                Button(L("Claude’a tekrar giriş", "Sign in to Claude again")) {
                    if let error = ClaudeAuth.openLogin() {
                        claudeHint = error
                    } else {
                        claudeHint = L(
                            "Terminal açıldı. Giriş bittikten sonra Kotaları yenile’ye bas.",
                            "Terminal opened. After you finish signing in, tap Refresh quotas."
                        )
                    }
                }
                Button(L("Kotaları yenile", "Refresh quotas")) {
                    claudeHint = nil
                    Task { await store.refresh() }
                }
            }
            if let claudeHint {
                Text(claudeHint).font(.caption).foregroundStyle(.secondary)
            }
            Text(L(
                "Kota Claude Code’a sorulur; Hâl anahtar zincirini okumaz, oturumu Claude Code kendisi yeniler. Oturum yoksa Terminal’de claude /login çalıştır, sonra Yenile.",
                "Quota is asked of Claude Code; Hâl never reads the Keychain and Claude Code renews its own sign-in. If signed out, run claude /login in Terminal, then Refresh."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var codexQuotaSection: some View {
        Section("Codex") {
            Toggle(L("Codex kotasını izle", "Track the Codex quota"), isOn: Binding(
                get: { store.settings.codexEnabled },
                set: { store.toggle(.codex, enabled: $0) }
            ))
            Button(L("Kotaları yenile", "Refresh quotas")) {
                Task { await store.refresh() }
            }
            Text(L(
                "Kota Codex’in kendi sunucusuna (codex app-server) sorulur; Hâl oturum dosyasını okumaz. Oturum yoksa Terminal’de codex login çalıştır.",
                "Quota is asked of Codex’s own server (codex app-server); Hâl never reads its sign-in file. If signed out, run codex login in Terminal."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var grokQuotaSection: some View {
        Section("Grok") {
            Toggle(L("Grok kotasını izle", "Track the Grok quota"), isOn: Binding(
                get: { store.settings.grokEnabled },
                set: { store.toggle(.grok, enabled: $0) }
            ))
            HStack {
                Button(L("Terminalde grok login", "grok login in Terminal")) {
                    if let error = GrokAuth.openLogin() {
                        claudeHint = error
                    } else {
                        claudeHint = L(
                            "Terminal açıldı. Giriş bittikten sonra Yenile’ye bas.",
                            "Terminal opened. After you finish signing in, tap Refresh."
                        )
                    }
                }
                Button(L("Kotaları yenile", "Refresh quotas")) {
                    claudeHint = nil
                    Task { await store.refresh() }
                }
            }
            if let claudeHint {
                Text(claudeHint).font(.caption).foregroundStyle(.secondary)
            }
            Text(L(
                "Haftalık sınır ve Grok Build, grok’un kendi fatura ucundan okunur. Oturum ~/.grok/auth.json dosyasıdır; süresi dolunca kendiliğinden yenilenir.",
                "Weekly limit and Grok Build are read from grok’s own billing endpoint. The session is ~/.grok/auth.json; it renews itself when it expires."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var customQuotaSection: some View {
            Section(L("Özel kota kaynakları", "Custom quota sources")) {
                ForEach(store.settings.customProviders) { provider in
                    HStack {
                        Circle().fill(Color(hex: provider.accentHex)).frame(width: 8, height: 8)
                        Text(provider.name)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { provider.enabled },
                            set: { value in
                                var next = provider
                                next.enabled = value
                                store.updateProvider(next)
                            }
                        ))
                        .labelsHidden()
                        Button(role: .destructive) {
                            store.removeProvider(provider.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                if adding {
                    TextField(L("Ad", "Name"), text: $draft.name)
                    Picker(L("Kaynak", "Source"), selection: $draft.source) {
                        ForEach(CustomSourceKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    switch draft.source {
                    case .manual:
                        HStack {
                            TextField(L("Kullanılan", "Used"), value: $draft.used, format: plainNumber)
                            TextField(L("Limit", "Limit"), value: $draft.limit, format: plainNumber)
                        }
                    case .command:
                        TextField(L("Komut (JSON yazmalı)", "Command (must print JSON)"), text: $draft.command)
                    case .url:
                        TextField("https://…", text: $draft.url)
                        SecureField(L("Bearer token (opsiyonel)", "Bearer token (optional)"), text: $draft.token)
                    }
                    ColorPicker(L("Renk", "Color"), selection: Binding(
                        get: { Color(hex: draft.accentHex) },
                        set: { draft.accentHex = $0.hexString }
                    ))
                    HStack {
                        Button(L("Ekle", "Add")) {
                            guard !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            store.addProvider(draft)
                            draft = CustomProvider(name: "")
                            adding = false
                        }
                        Button(L("Vazgeç", "Cancel")) {
                            adding = false
                            draft = CustomProvider(name: "")
                        }
                    }
                } else {
                    Button(L("Özel kaynak ekle", "Add custom source")) {
                        draft = CustomProvider(name: "")
                        adding = true
                    }
                }
            }
    }

    private var calendarTab: some View {
        Form {
            Section(L("Takvim", "Calendar")) {
                switch calendarAccess {
                case .granted:
                    Label(L("Takvim bağlı", "Calendar connected"), systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Text(L(
                        "Bugünün kalan olayları panoda ve Takvim sekmesinde görünür.",
                        "Today’s remaining events appear on the board and the Calendar tab."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .notDetermined:
                    Button(L("Takvime bağlan", "Connect Calendar")) {
                        Task {
                            await CalendarService.shared.requestAccess()
                            calendarAccess = CalendarService.shared.access
                            await store.refresh()
                        }
                    }
                    Text(L(
                        "İzin yalnızca bu düğmeye bastığında sorulur; uygulama kendiliğinden istemez.",
                        "Permission is asked only when you tap this button; the app never asks on its own."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .denied:
                    Text(L(
                        "Takvim erişimi kapalı. Sistem Ayarları > Gizlilik ve Güvenlik > Takvimler içinden açabilirsin.",
                        "Calendar access is off. You can enable it in System Settings > Privacy & Security > Calendars."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(L("Gizlilik ayarlarını aç", "Open Privacy settings")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var fitnessTab: some View {
        Form {
            Section(L("Haftalık program", "Weekly plan")) {
                Toggle(L("Antrenman takibi", "Workout tracking"), isOn: $store.settings.trackWorkout)
                ForEach(Array(Workout.dayNames.enumerated()), id: \.offset) { index, day in
                    LabeledContent(day) {
                        // Başlık parametresi LabeledContent içinde görünür etikete dönüşüyor;
                        // "Dinlenme" yer tutucu olarak `prompt` ile verilmeli.
                        TextField("", text: planBinding(index), prompt: Text(L("Dinlenme", "Rest")))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                    }
                }
                Button(L("Varsayılana dön", "Reset to default")) {
                    store.settings.workoutPlan = Workout.defaultPlan
                }
                Text(L(
                    "Boş bıraktığın ya da “Dinlenme” yazdığın günler antrenman sayılmaz; seriyi kırmaz.",
                    "Days you leave blank or mark “Rest” don’t count as workouts and don’t break the streak."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("İlaç ve takviye", "Meds & supplements")) {
                Toggle(L("İlaç ve takviye takibi", "Meds & supplements tracking"), isOn: Binding(
                    get: { store.settings.trackMedication },
                    set: { store.settings.trackMedication = $0
                           Task { await store.refreshMedicationNotifications() } }
                ))
                if store.settings.trackMedication {
                    Toggle(L("Doz saatinde hatırlat", "Remind at dose time"), isOn: Binding(
                        get: { store.settings.notifyMedication },
                        set: { store.settings.notifyMedication = $0
                               Task { await store.refreshMedicationNotifications() } }
                    ))
                    ForEach(store.settings.medications) { item in
                        medicationRow(item)
                    }
                    Button(L("İlaç veya takviye ekle", "Add med or supplement")) { store.addMedication() }
                    Text(L(
                        "Her ilaç veya takviyeye birden çok saat verebilirsin; her saat ayrı bir doz olarak işaretlenir. Alınmış doz için hatırlatma gönderilmez. Bilgisayara geçmediğin günleri Bugün > Gün Sonu sayfasından tamamlarısın.",
                        "You can give each med or supplement several times; each time is marked as its own dose. No reminder is sent for a dose already taken. Days you weren’t at the computer can be finished from Today > End of day."
                    ))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(L("Su ve protein", "Water and protein")) {
                Toggle(L("Takip et", "Track"), isOn: $store.settings.trackIntake)
                if store.settings.trackIntake {
                    LabeledContent(L("Su hedefi", "Water goal")) {
                        TextField("", value: $store.settings.waterGoalML, format: plainNumber)
                            .frame(width: 70).multilineTextAlignment(.trailing)
                        Text("ml").foregroundStyle(.secondary)
                    }
                    LabeledContent(L("Su hızlı giriş", "Water quick add")) {
                        TextField("", value: $store.settings.waterStepML, format: plainNumber)
                            .frame(width: 70).multilineTextAlignment(.trailing)
                        Text("ml").foregroundStyle(.secondary)
                    }
                    LabeledContent(L("Protein hedefi", "Protein goal")) {
                        TextField("", value: $store.settings.proteinGoalG, format: plainNumber)
                            .frame(width: 70).multilineTextAlignment(.trailing)
                        Text("g").foregroundStyle(.secondary)
                    }
                    LabeledContent(L("Protein hızlı giriş", "Protein quick add")) {
                        TextField("", value: $store.settings.proteinStepG, format: plainNumber)
                            .frame(width: 70).multilineTextAlignment(.trailing)
                        Text("g").foregroundStyle(.secondary)
                    }
                }
            }
            if store.settings.trackIntake {
                Section(L("Bugün", "Today")) {
                    LabeledContent(L("Su", "Water")) {
                        TextField("", value: intakeBinding(Metric.waterML), format: plainNumber)
                            .frame(width: 70).multilineTextAlignment(.trailing)
                        Text("ml").foregroundStyle(.secondary)
                    }
                    LabeledContent("Protein") {
                        TextField("", value: intakeBinding(Metric.proteinG), format: plainNumber)
                            .frame(width: 70).multilineTextAlignment(.trailing)
                        Text("g").foregroundStyle(.secondary)
                    }
                    Text(L(
                        "Panodaki hızlı giriş düğmeleri yukarıdaki adımlarla artırır; günün toplamını buradan elle de düzeltebilirsin.",
                        "The board’s quick-add buttons increase by the steps above; you can also edit today’s total here by hand."
                    ))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Text(L(
                    "Set, tekrar ve ağırlık kaydı bilerek yok: menü çubuğu penceresi bunun için dar ve girişi her gün yapmak sürdürülemez. Burada tutulan soru şu — bugün ne var, yaptım mı, kaç gündür sürüyor.",
                    "Sets, reps, and weight logging are intentionally missing: the menu bar window is too narrow for that, and entering it every day isn’t sustainable. The question kept here is — what’s on today, did I do it, how many days has it lasted."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Günün toplamını doğrudan düzenler.
    private func intakeBinding(_ metric: String) -> Binding<Double> {
        Binding(
            get: { DailyLog.shared.value(metric, on: store.now) },
            set: { DailyLog.shared.set(metric, max($0, 0), on: store.now) }
        )
    }

    /// Bir ilaç veya takviyenin iki satırı: künye ve doz saatleri.
    ///
    /// İkisi de `LabeledContent`. Sebebi ölçümle bulundu: elle kurulan `HStack`
    /// satırlarında `Form` künye satırını sütunlara bölüp içeriği sağa itiyor,
    /// saat satırını bölmüyordu — biri x=376'dan, diğeri x=273'ten başlıyordu.
    /// `LabeledContent` ile iki satır da Form'un aynı sütun geometrisini kullanır.
    private func medicationRow(_ item: Medication) -> some View {
        Group {
            LabeledContent(L("İlaç / takviye", "Med / supplement")) {
                HStack(spacing: 4) {
                    // Esnek genişlikli alan satırdan satıra farklı ölçülüp
                    // Form'un sütun hesabını kaydırıyordu; ikisi de sabit.
                    TextField("", text: medBinding(item, \.name), prompt: Text(L("Ad", "Name")))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 118)
                    TextField("", text: medBinding(item, \.dose), prompt: Text(L("Doz", "Dose")))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 58)
                    Toggle("", isOn: medBinding(item, \.enabled))
                        .labelsHidden()
                        .help(L("Bu ilacı geçici olarak kapat", "Temporarily turn off this med"))
                    Button(role: .destructive) { store.removeMedication(item.id) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help(L("Sil", "Delete"))
                    Spacer(minLength: 0)
                }
            }
            LabeledContent(L("Saatler", "Times")) {
                HStack(spacing: 4) {
                    ForEach(Array(item.times.indices), id: \.self) { index in
                        HStack(spacing: 0) {
                            DatePicker(
                                "",
                                selection: timeBinding(item, index: index),
                                displayedComponents: .hourAndMinute
                            )
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
        }
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

    private var portsTab: some View {
        PortsPanel(showsTitle: false, embedsInSettings: true)
    }

    private var downloaderTab: some View {
        DownloaderSettingsForm()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.settings.downloadDestination
        panel.prompt = L("Seç", "Choose")
        if panel.runModal() == .OK, let url = panel.url {
            store.settings.downloadFolder = url.path
        }
    }

    private var moneyTab: some View {
        Form {
            Section(L("Düzenli ödemeler", "Recurring payments")) {
                if store.settings.subscriptions.isEmpty {
                    Text(L(
                        "Abonelik, fatura, taksit — bir kez gir, yenileme tarihi kendiliğinden ilerler.",
                        "Subscription, bill, installment — enter once and the renewal date advances on its own."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(store.settings.subscriptions) { item in
                    subscriptionRow(item)
                }
                Button(L("Ödeme ekle", "Add payment")) {
                    store.addSubscription(Subscription(name: L("Yeni", "New"), amount: 0, anchor: Date()))
                }
            }
            Section(L("Hatırlatma", "Reminder")) {
                Picker(L("Yenilemeden önce", "Before renewal"), selection: Binding(
                    get: { store.settings.notifyRenewalDays },
                    set: { store.settings.notifyRenewalDays = $0
                           Task { await store.refreshRenewalNotifications() } }
                )) {
                    Text(L("Kapalı", "Off")).tag(0)
                    ForEach([1, 3, 7], id: \.self) {
                        Text(Lf("%1$d gün önce", "%1$d days before", $0)).tag($0)
                    }
                }
                Text(L(
                    "Bildirim, yenileme gününden geriye sayarak sabah 09:00’da düşer.",
                    "The notification fires at 09:00 on the morning counted back from the renewal day."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !store.monthlyTotals.isEmpty {
                Section(L("Aylık toplam", "Monthly total")) {
                    ForEach(store.monthlyTotals, id: \.currency) { total in
                        LabeledContent(total.currency) {
                            Text("\(Subscription.symbol(for: total.currency))\(String(format: "%.2f", locale: Language.locale, arguments: [total.amount]))")
                        }
                    }
                    Text(L(
                        "Yıllık ödemeler 12’ye bölünerek eklenir.",
                        "Yearly payments are divided by 12 and added in."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func subscriptionRow(_ item: Subscription) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(L("Ad", "Name"), text: binding(item, \.name))
                Toggle("", isOn: binding(item, \.enabled)).labelsHidden()
                Button(role: .destructive) {
                    store.removeSubscription(item.id)
                } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
            }
            HStack {
                TextField(L("Tutar", "Amount"), value: binding(item, \.amount), format: plainNumber)
                    .frame(width: 80)
                Picker("", selection: binding(item, \.currency)) {
                    ForEach(Subscription.currencies, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 80)
                Picker("", selection: binding(item, \.period)) {
                    ForEach(Subscription.Period.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().frame(width: 90)
                DatePicker("", selection: binding(item, \.anchor), displayedComponents: .date)
                    .labelsHidden()
            }
            Text(Lf(
                "Sıradaki yenileme: %1$@ · %2$d gün",
                "Next renewal: %1$@ · %2$d days",
                TimeFormatters.longDate(item.nextRenewal(after: Date())),
                item.daysUntilRenewal()
            ))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
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
        Form {
            Section(L("Panel sekmeleri", "Panel tabs")) {
                PanelLayoutEditor()
                Text(L("Sıra ve görünürlük menü çubuğu panelindeki sekmelere uygulanır.",
                       "Order and visibility apply to the tabs of the menu bar panel."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L("Özellikleri yönet", "Manage features")) { tab = .features }
            }
            Section(L("Bugün panosunda göster", "Show on Today board")) {
                if store.summaryCatalog.isEmpty {
                    Text(L(
                        "Pano satırları göründükçe burada listelenir.",
                        "Board rows are listed here as they appear."
                    ))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(store.summaryCatalog) { line in
                        Toggle(isOn: Binding(
                            get: { store.isSummaryLineVisible(line.id) },
                            set: { store.setSummaryLine(line.id, visible: $0) }
                        )) {
                            Text(SummaryCatalogCopy.title(id: line.id, fallback: line.title))
                            Text(line.module.title)
                        }
                    }
                }
                Text(L(
                    "Modülü kapatmadan yalnızca panodaki satırını kaldırır: sekmesi, ölçümü ve bildirimleri yerinde kalır. Gizlenen satır akşam gün özetinde de görünmez. Bir kez görülen satır, o an üretilmese bile listede kalır.",
                    "Hides only the board row without turning the module off: its tab, metrics, and notifications stay. A hidden row also stays out of the evening daily summary. Once a row has been seen, it remains in the list even when it isn’t produced right then."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("Menü çubuğunda göster", "Show in menu bar")) {
                visibilityToggle(L("Namaz vakitleri", "Prayer times"), id: "prayer")
                Text(L("Kota ikonları Ayarlar › Kotalar › Genel’den yönetilir.",
                       "Quota icons are managed in Settings › Quotas › General."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("Tıklama", "Click")) {
                Picker(L("İkona tıklayınca aç", "Open on icon click"), selection: $store.settings.menuBarClickOpens) {
                    ForEach(MenuBarClickTarget.allCases) { Text($0.title).tag($0) }
                }
                Text(L(
                    "Özet ikon ve hiçbir modül görünmezken duran genel ikon her koşulda panoyu açar; ikisi de tek bir şeyi değil genel durumu temsil eder.",
                    "The summary icon and the general icon shown when no modules are visible always open the board; both represent overall status, not a single item."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("Ekranlar", "Displays")) {
                Toggle(L("Diğer ekranların menü çubuğunda da göster", "Also show on other displays’ menu bars"), isOn: $store.settings.mirrorToOtherDisplays)
                Text(L(
                    "macOS çoğu ekranda extra’ları zaten kopyalar. Açarsan ikinci satır oluşabilir; kapalı tut.",
                    "macOS already mirrors extras on most displays. Turning this on can create a second row; leave it off."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
        Form {
            Section(L("Namaz", "Prayer")) {
                Toggle(L("Vakit bildirimi", "Prayer-time notification"), isOn: notifyBinding(\.notifyPrayer))
                if store.settings.notifyPrayer {
                    Picker(L("Ne zaman", "When"), selection: notifyBinding(\.notifyPrayerMinutes)) {
                        Text(L("Vakit girince", "When time begins")).tag(0)
                        Text(L("5 dakika önce", "5 minutes before")).tag(5)
                        Text(L("10 dakika önce", "10 minutes before")).tag(10)
                        Text(L("15 dakika önce", "15 minutes before")).tag(15)
                        Text(L("30 dakika önce", "30 minutes before")).tag(30)
                    }
                }
                Text(L(
                    "Güneş vakti yalnızca Genel’de “Güneş’i göster” açıkken bildirilir.",
                    "Sunrise is notified only when “Show sunrise” is on in General."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("Kotalar", "Quotas")) {
                Toggle(L("Kota sıfırlanınca haber ver", "Notify when a quota resets"), isOn: notifyBinding(\.notifyQuotaReset))
                Text(L(
                    "Limit dolduğunda elle kontrol etmek yerine, yeniden kullanılabilir olunca bildirir.",
                    "Instead of checking by hand when a limit is full, it notifies you when it’s usable again."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(L("Eşik aşılınca uyar", "Warn when a threshold is crossed"), isOn: notifyBinding(\.notifyQuotaThreshold))
                if store.settings.notifyQuotaThreshold {
                    Picker(L("Eşik", "Threshold"), selection: notifyBinding(\.notifyQuotaThresholdPercent)) {
                        ForEach([50, 60, 70, 80, 90], id: \.self) { value in
                            Text("%\(value)").tag(value)
                        }
                    }
                }
                Text(L(
                    "Her olay bir kez bildirilir; aynı pencere için tekrarlamaz.",
                    "Each event is notified once; it doesn’t repeat for the same window."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("Gün özeti", "Daily summary")) {
                Toggle(L("Akşam gün özeti gönder", "Send evening daily summary"), isOn: notifyBinding(\.notifyDailySummary))
                if store.settings.notifyDailySummary {
                    Picker(L("Saat", "Time"), selection: notifyBinding(\.dailySummaryHour)) {
                        ForEach(Array(17...23), id: \.self) { hour in
                            Text(String(format: "%02d:00", locale: Language.locale, arguments: [hour])).tag(hour)
                        }
                    }
                }
                Text(L(
                    "Günün sonunda derin çalışma, namaz ve hedeflerin özetini bildirir.",
                    "At the end of the day it notifies a summary of deep work, prayer, and your goals."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("Gün sonu", "End of day")) {
                Toggle(L("Gün sonu hatırlatması", "End-of-day reminder"), isOn: notifyBinding(\.notifyDayClose))
                if store.settings.notifyDayClose {
                    Picker(L("Saat", "Time"), selection: notifyBinding(\.dayCloseHour)) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d:00", locale: Language.locale, arguments: [hour])).tag(hour)
                        }
                    }
                }
                Text(L(
                    "Seçtiğin saatte bildirim gelir. Tıklayınca Gün Sonu sayfası açılır; kaçırdığın namaz, ilaç ve antrenman işaretlerini oradan düzeltirsin.",
                    "A notification arrives at the time you choose. Tapping it opens the End of day page, where you can fix missed prayer, med, and workout marks."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text(L(
                    "İzin, ilk bildirimi açtığında istenir. Sistem Ayarları > Bildirimler > Hâl üzerinden değiştirebilirsin.",
                    "Permission is requested when you turn on the first notification. You can change it in System Settings > Notifications > Hâl."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
        Form {
            Section {
                Picker(L("Dil", "Language"), selection: $store.settings.language) {
                    ForEach(LanguageChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                Text(L(
                    "Başlangıçta Mac’in dili kullanılır. Buradan Türkçe veya English seçebilirsin.",
                    "Starts in your Mac’s language. Choose Türkçe or English here."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section(L("Pano", "Board")) {
                TextField(L("Adın", "Your name"), text: $store.settings.displayName, prompt: Text(L("Panodaki selamlamada kullanılır", "Used in the board greeting")))
                LabeledContent(L("Günlük kayıt", "Daily log")) {
                    Text(DailyLog.fileURL.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
            Section(L("Temizlik modu", "Cleaning mode")) {
                Toggle(L("Temizlik modu", "Cleaning mode"), isOn: Binding(
                    get: { store.cleaningMode },
                    set: { store.setCleaningMode($0) }
                ))
                TextField(L("Başlık", "Title"), text: $store.settings.cleaningTitle,
                          prompt: Text(L("Klavye temizlik için kilitlendi", "Keyboard locked for cleaning")))
                TextField(
                    L("Ekrandaki not", "Note on screen"),
                    text: $store.settings.cleaningHint,
                    prompt: Text(L("İsteğe bağlı; ör. “Dokunmayın, kuruyor”", "Optional, e.g. “Don’t touch, drying”")),
                    axis: .vertical
                )
                .lineLimit(2...5)
                Toggle(L("Ekranı görünür tut", "Keep the screen visible"), isOn: $store.settings.cleaningKeepScreenVisible)
                Text(L(
                    "Klavye, sistem tuşları, kaydırma ve trackpad hareketleri kilitlenir; fare ve trackpad tıklamaları çalışır. Kilidi açmak için Esc’ye 5 kez bas ya da ekrandaki Kilidi aç düğmesine tıkla. Ekranı görünür tutarsan karartma yerine köşede küçük bir gösterge çıkar; başlık ve not iki görünümde de kalır.",
                    "The keyboard, system keys, scrolling and trackpad gestures are locked; mouse and trackpad clicks still work. Press Esc 5 times or click Unlock on screen to stop. If you keep the screen visible, a small indicator appears in the corner instead of the blackout; the title and note show in both."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !DeviceModes.shared.accessibilityTrusted {
                    Text(L(
                        "Klavye kilidi Erişilebilirlik izni ister. İzin olmadan temizlik modu başlamaz; böylece açılamayan bir klavyeyle kalmazsın.",
                        "The keyboard lock needs Accessibility permission. Without it cleaning mode won’t start, so you can’t get stuck with a locked keyboard."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(L("Erişilebilirlik izni iste", "Request Accessibility permission")) {
                        DeviceModes.shared.requestKeyboardLockPermission()
                    }
                    Button(L("Erişilebilirlik ayarını aç", "Open Accessibility settings")) {
                        DeviceModes.shared.openAccessibilitySettings()
                    }
                }
            }
            if legacyKeychainCount > 0 {
                Section(L("Eski anahtar zinciri kayıtları", "Legacy Keychain records")) {
                    Text(Lf(
                        "Gizli değerler artık anahtar zincirinde değil, yalnızca senin okuyabildiğin bir dosyada tutuluyor (%1$@). Anahtar zincirinde %2$d eski kayıt duruyor; uygulama bunlara dokunmuyor, yani şifre sorusu çıkmıyor.",
                        "Secrets are no longer in Keychain; they’re kept only in a file only you can read (%1$@). Keychain still has %2$d legacy records; the app leaves them alone, so no password prompt appears.",
                        SecretStore.fileURL.path,
                        legacyKeychainCount
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let legacyNote {
                        Text(legacyNote).font(.caption).foregroundStyle(.secondary)
                    }
                    Button(L("Değerleri taşı ve kayıtları sil", "Move values and delete records")) {
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
                    Text(L(
                        "Bir defalığına kayıt başına şifre sorar; sonrasında kayıtlar silinir ve bir daha sorulmaz.",
                        "It asks for a password once per record; afterward the records are deleted and it won’t ask again."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(L("Okumadan sil", "Delete without reading"), role: .destructive) {
                        let removed = SecretStore.discardLegacyKeychainItems()
                        legacyKeychainCount = SecretStore.legacyItemCount()
                        legacyNote = Lf("%1$d kayıt silindi.", "%1$d records deleted.", removed)
                    }
                    Text(L(
                        "Silinen kayıtlar geri gelmez. Grok kotası ~/.grok/auth.json oturumundan okunur.",
                        "Deleted records can’t be restored. The Grok quota is read from the ~/.grok/auth.json session."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(L("Açılışta başlat", "Launch at login"), isOn: Binding(
                get: { store.settings.launchAtLogin },
                set: { value in
                    store.settings.launchAtLogin = value
                    store.applyLaunchAtLogin()
                }
            ))
            Button(L("Kotaları yenile", "Refresh quotas")) {
                Task { await store.refresh() }
            }
            if let error = store.lastError {
                Text(error).foregroundStyle(.red).font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private var focusTab: some View {
        Form {
            Section(L("Derin çalışma", "Deep work")) {
                Toggle(L("Otomatik ölç", "Measure automatically"), isOn: Binding(
                    get: { store.settings.focusTracking },
                    set: { store.settings.focusTracking = $0; store.applyFocusTracking() }
                ))
                LabeledContent(L("Günlük hedef", "Daily goal")) {
                    TextField("", value: $store.settings.focusGoalMinutes, format: .number.locale(Language.locale).grouping(.never))
                        .frame(width: 64)
                        .multilineTextAlignment(.trailing)
                    Text(L("dk", "min")).foregroundStyle(.secondary)
                }
                Text(L(
                    "Öndeki uygulama listedeyse ve Mac iki dakikadır boşta değilse süre kendiliğinden sayılır.",
                    "Time counts on its own when the frontmost app is on the list and the Mac hasn’t been idle for two minutes."
                ))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if store.settings.focusTracking {
                Section(L("Çalışma uygulamaları", "Work apps")) {
                    TextField(L("Uygulamalar", "Apps"), text: focusAppsBinding, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.system(size: 11, design: .monospaced))
                    Text(L(
                        "Virgülle ayır. Uygulama adı veya bundle kimliği bu parçalardan birini içerirse odak sayılır.",
                        "Separate with commas. Focus counts if the app name or bundle id contains any of these parts."
                    ))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Text(L(
                    "Sayaç ve yedi günlük geçmiş yerel daily.json dosyasında tutulur; pomodoro ve görev yönetimi bilerek yok.",
                    "The counter and seven-day history live in the local daily.json file; pomodoro and task management are intentionally absent."
                ))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                identityBlock
                authorBlock
                sourcesBlock
                diagnosticsBlock
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 4)
        }
    }

    private var identityBlock: some View {
        VStack(spacing: 8) {
            BrandMark(icon: .app, size: 60)
                .padding(.bottom, 2)
            Text("Hâl")
                .font(.system(size: 24, weight: .semibold))
            Text(L("Kişisel durum panosu", "Personal status board"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Self.versionText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            Button(L("Güncellemeleri denetle", "Check for updates")) { UpdateController.check() }
                .controlSize(.small)
            HStack(spacing: 8) {
                Button(L("Yenilikler", "What's New")) { tab = .changelog }
                Button(L("Tanıtım", "Introduction")) {
                    NotificationCenter.default.post(name: .halShowWelcome, object: nil)
                }
            }
                .controlSize(.small)
            Text(L(
                "Yeni sürüm olunca sorar. Kendiliğinden kurmaz.",
                "It asks when a new version is available. It never installs on its own."
            ))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private var wakeTab: some View {
        ScrollView {
            KeepAwakePanel { tab = .focus }
                .padding(24)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var changelogTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("Yenilikler", "What's New"))
                    .font(.system(size: 20, weight: .semibold))
                ForEach(Changelog.releases) { release in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(release.version)
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Text(release.dateText)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(release.notes, id: \.self) { note in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundStyle(.tertiary)
                                Text(note)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(20)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var authorBlock: some View {
        VStack(spacing: 8) {
            Text("Tahsin Sungur")
                .font(.system(size: 14, weight: .medium))
            HStack(spacing: 14) {
                Link("sungur.dev", destination: URL(string: "https://sungur.dev")!)
                Link("@tahsingibi", destination: URL(string: "https://x.com/tahsingibi")!)
            }
            .font(.system(size: 12))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Verinin nereden geldiğini gösterir ve aynı anda sağlık paneli görevi görür:
    /// hangi kaynak çalışıyor, hangisi oturum bekliyor tek bakışta belli olur.
    private var sourcesBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("Veri kaynakları", "Data sources"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if store.refreshing {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Button(L("Yenile", "Refresh")) { Task { await store.refresh() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ForEach(Array(sourceRows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().padding(.leading, 30) }
                HStack(spacing: 9) {
                    Circle()
                        .fill(row.tint)
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name)
                            .font(.system(size: 12, weight: .medium))
                        Text(row.origin)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 8)
                    Text(row.value)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var diagnosticsBlock: some View {
        VStack(spacing: 8) {
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
            .controlSize(.small)
            Text(Self.systemText)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
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
