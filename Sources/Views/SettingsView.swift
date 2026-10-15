import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Hashable, Identifiable {
    // Uygulama
    case general, appearance, notifications
    // Modüller — popover sekmeleriyle aynı sırada
    case focus, quota, worship, calendar, fitness, money, downloader, ports
    case about

    var id: String { rawValue }

    /// Kenar çubuğu grupları: uygulama ayarları ile modül ayarları karışmasın.
    enum Group: String, CaseIterable, Identifiable {
        case app = "Uygulama"
        case modules = "Modüller"
        case tools = "Araçlar"
        case info = ""

        var id: String { rawValue }

        var title: String { rawValue }

        var tabs: [SettingsTab] {
            switch self {
            case .app: return [.general, .appearance, .notifications]
            case .modules: return [.focus, .quota, .worship, .calendar, .fitness, .money]
            case .tools: return [.downloader, .ports]
            case .info: return [.about]
            }
        }
    }

    var title: String {
        switch self {
        case .general: return "Genel"
        case .appearance: return "Görünüm"
        case .notifications: return "Bildirimler"
        case .focus: return "Odak"
        case .quota: return "Kotalar"
        case .worship: return "İbadet"
        case .calendar: return "Takvim"
        case .fitness: return "Sağlık"
        case .money: return "Ödemeler"
        case .downloader: return "İndirici"
        case .ports: return "Portlar"
        case .about: return "Hakkında"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "menubar.rectangle"
        case .notifications: return "bell"
        case .focus: return "scope"
        case .quota: return "gauge"
        case .worship: return "moon.stars"
        case .calendar: return "calendar"
        case .fitness: return "figure.strengthtraining.traditional"
        case .money: return "creditcard"
        case .downloader: return "arrow.down.circle"
        case .ports: return "network"
        case .about: return "info.circle"
        }
    }

    /// Eski çağrı yerleri için: Konum artık İbadet altında.
    static let location = SettingsTab.worship
    static let menuBar = SettingsTab.appearance
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var tab: SettingsTab
    @State private var draft = CustomProvider(name: "")
    @State private var adding = false
    @State private var legacyKeychainCount = 0
    @State private var legacyNote: String?
    @State private var copiedDiagnostics = false
    @State private var newDua = ""
    @State private var calendarAccess = CalendarService.shared.access
    @State private var claudeHint: String?

    /// Belirli bir sekmeyle açılabilir; bildirimden ya da popover'dan doğrudan
    /// ilgili sayfaya götürmek için.
    init(initialTab: SettingsTab = .general) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        // Sekme şeridi yerine kenar çubuğu: bölüm sayısı arttıkça başlıklar
        // kırpılmıyor, yeni bölüm eklemek de genişlik hesabı gerektirmiyor.
        NavigationSplitView {
            List(selection: sidebarSelection) {
                ForEach(SettingsTab.Group.allCases) { group in
                    if group.title.isEmpty {
                        ForEach(group.tabs) { row($0) }
                    } else {
                        Section(group.title) {
                            ForEach(group.tabs) { row($0) }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 172, ideal: 182, max: 210)
        } detail: {
            // Form kendi içinde kayar. Dıştan bir ScrollView'a sarmak iç içe kaydırma
            // doğurup alan tıklamalarını ve metin girişini engelliyordu.
            content
                .navigationTitle(tab.title)
        }
        .frame(width: 700, height: 640)
        .onAppear {
            legacyKeychainCount = SecretStore.legacyItemCount()
        }
    }

    private func row(_ item: SettingsTab) -> some View {
        Label(item.title, systemImage: item.symbol).tag(item)
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
        case .appearance: menuBarTab
        case .notifications: notificationsTab
        case .focus: focusTab
        case .quota: quotaTab
        case .worship: worshipTab
        case .calendar: calendarTab
        case .fitness: fitnessTab
        case .money: moneyTab
        case .downloader: downloaderTab
        case .ports: portsTab
        case .about: aboutTab
        }
    }

    private var worshipTab: some View {
        Form {
            Section("Takip") {
                Toggle("Namaz takibi", isOn: $store.settings.trackPrayers)
                Text("Vakit geçtikten sonra Namaz sekmesinden işaretlersin; pano gün içi sayıyı ve seriyi gösterir. Bilgisayara geçmediğin günleri Bugün > Gün Sonu sayfasından tamamlarısın.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Kur’an takibi", isOn: $store.settings.trackQuran)
                if store.settings.trackQuran {
                    LabeledContent("Günlük hedef") {
                        TextField("", value: $store.settings.quranGoalPages, format: plainNumber)
                            .frame(width: 60).multilineTextAlignment(.trailing)
                        Text("sayfa").foregroundStyle(.secondary)
                    }
                }

                Toggle("Günlük dua listesi", isOn: $store.settings.trackDua)
                if store.settings.trackDua {
                    ForEach(store.settings.duaList) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Button(role: .destructive) { store.removeDua(item.id) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        TextField("Yeni kayıt (ör. Sabah zikri)", text: $newDua)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addDua() }
                        Button("Ekle", action: addDua)
                            .disabled(newDua.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("Listeyi sen tanımlarsın; uygulama metin içermez, yalnızca “bugün okundu mu” bilgisini tutar.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Konum ve hesaplama") {
            Picker("Ülke", selection: countryBinding) {
                Text("Seç").tag("")
                ForEach(store.countries) { country in
                    Text(country.name).tag(country.code)
                }
            }
            Picker("İl / Eyalet", selection: stateBinding) {
                Text("Seç").tag("")
                ForEach(store.regions) { region in
                    Text(region.name).tag(region.name)
                }
            }
            if !store.cities.isEmpty {
                Picker("Şehir / İlçe", selection: cityBinding) {
                    Text("Seç").tag("")
                    ForEach(store.cities) { city in
                        Text(city.name).tag(city.name)
                    }
                }
            } else {
                TextField("Şehir ara", text: $store.cityQuery)
                    .onChange(of: store.cityQuery) { _, value in
                        store.searchCities(value)
                    }
                if !store.cityResults.isEmpty {
                    Picker("Sonuçlar", selection: cityBinding) {
                        Text("Seç").tag("")
                        ForEach(store.cityResults) { city in
                            Text(city.name).tag(city.name)
                        }
                    }
                }
            }
            Picker("Hesap yöntemi", selection: $store.settings.method) {
                ForEach(CalculationMethods.all) { method in
                    Text(method.name).tag(method.id)
                }
            }
            Picker("Mezhep (İkindi)", selection: $store.settings.school) {
                Text("Diyanet / Şafii").tag(0)
                Text("Hanefi").tag(1)
            }
            Text("Türkiye’de Diyanet ikindi için erken (Şafii) hesabı kullanır. Hanefi yaklaşık 1 saat sonradır.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Güneş doğuşunu göster", isOn: $store.settings.showSunrise)
            LabeledContent("Koordinat") {
                Text(store.settings.hasLocation
                     ? String(format: "%.4f, %.4f", store.settings.latitude, store.settings.longitude)
                     : "seçilmedi")
                    .foregroundStyle(.secondary)
            }
            Button("Vakitleri yenile") {
                Task { await store.refresh() }
            }
            }
        }
        .formStyle(.grouped)
    }

    private func addDua() {
        store.addDua(newDua)
        newDua = ""
    }

    private var quotaTab: some View {
        Form {
            Section("Yerleşik") {
                Toggle("Claude", isOn: Binding(
                    get: { store.settings.claudeEnabled },
                    set: { store.toggle(.claude, enabled: $0) }
                ))
                Toggle("Codex", isOn: Binding(
                    get: { store.settings.codexEnabled },
                    set: { store.toggle(.codex, enabled: $0) }
                ))
                Toggle("Grok", isOn: Binding(
                    get: { store.settings.grokEnabled },
                    set: { store.toggle(.grok, enabled: $0) }
                ))
                HStack {
                    Button("Claude’a tekrar giriş") {
                        if let error = ClaudeAuth.openLogin() {
                            claudeHint = error
                        } else {
                            claudeHint = "Terminal açıldı. Giriş bittikten sonra Kotaları yenile’ye bas."
                        }
                    }
                    Button("Kotaları yenile") {
                        claudeHint = nil
                        Task { await store.refresh() }
                    }
                }
                if let claudeHint {
                    Text(claudeHint)
                        .font(.caption)
                        .foregroundStyle(claudeHint.contains("bulunamadı") ? .red : .secondary)
                }
                Text("Claude oturumu Keychain’den okunur. Süre dolduysa Terminal’de claude çalıştır, tarayıcıdan giriş yap, sonra Yenile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if store.settings.grokEnabled {
                    HStack {
                        Button("Terminalde grok login") {
                            if let error = GrokAuth.openLogin() {
                                claudeHint = error
                            } else {
                                claudeHint = "Terminal açıldı. Giriş bittikten sonra Yenile’ye bas."
                            }
                        }
                        Button("Kotaları yenile") {
                            claudeHint = nil
                            Task { await store.refresh() }
                        }
                    }
                    Text("Haftalık sınır ve Grok Build, grok’un kendi fatura ucundan okunur. Oturum ~/.grok/auth.json dosyasıdır; süresi dolunca kendiliğinden yenilenir.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Claude, Claude Code oturumundan; Codex ~/.codex/auth.json dosyasından; Grok, grok login oturumundan okunur. Kota kapalı başlar; görmek için anahtarı sen açarsın.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !installedCLIs.isEmpty {
                    Text("Bu makinede bulundu: \(installedCLIs.joined(separator: ", ")).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Gelişmiş · Özel kota kaynakları") {
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
                    TextField("Ad", text: $draft.name)
                    Picker("Kaynak", selection: $draft.source) {
                        ForEach(CustomSourceKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    switch draft.source {
                    case .manual:
                        HStack {
                            TextField("Kullanılan", value: $draft.used, format: plainNumber)
                            TextField("Limit", value: $draft.limit, format: plainNumber)
                        }
                    case .command:
                        TextField("Komut (JSON yazmalı)", text: $draft.command)
                    case .url:
                        TextField("https://…", text: $draft.url)
                        SecureField("Bearer token (opsiyonel)", text: $draft.token)
                    }
                    ColorPicker("Renk", selection: Binding(
                        get: { Color(hex: draft.accentHex) },
                        set: { draft.accentHex = $0.hexString }
                    ))
                    HStack {
                        Button("Ekle") {
                            guard !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            store.addProvider(draft)
                            draft = CustomProvider(name: "")
                            adding = false
                        }
                        Button("Vazgeç") {
                            adding = false
                            draft = CustomProvider(name: "")
                        }
                    }
                } else {
                    Button("Özel kaynak ekle") {
                        draft = CustomProvider(name: "")
                        adding = true
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var calendarTab: some View {
        Form {
            Section("Takvim") {
                switch calendarAccess {
                case .granted:
                    Label("Takvim bağlı", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Text("Bugünün kalan olayları panoda ve Takvim sekmesinde görünür.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .notDetermined:
                    Button("Takvime bağlan") {
                        Task {
                            await CalendarService.shared.requestAccess()
                            calendarAccess = CalendarService.shared.access
                            await store.refresh()
                        }
                    }
                    Text("İzin yalnızca bu düğmeye bastığında sorulur; uygulama kendiliğinden istemez.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .denied:
                    Text("Takvim erişimi kapalı. Sistem Ayarları > Gizlilik ve Güvenlik > Takvimler içinden açabilirsin.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Gizlilik ayarlarını aç") {
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
            Section("Haftalık program") {
                Toggle("Antrenman takibi", isOn: $store.settings.trackWorkout)
                ForEach(Array(Workout.dayNames.enumerated()), id: \.offset) { index, day in
                    LabeledContent(day) {
                        // Başlık parametresi LabeledContent içinde görünür etikete dönüşüyor;
                        // "Dinlenme" yer tutucu olarak `prompt` ile verilmeli.
                        TextField("", text: planBinding(index), prompt: Text("Dinlenme"))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                    }
                }
                Button("Varsayılana dön") {
                    store.settings.workoutPlan = Workout.defaultPlan
                }
                Text("Boş bıraktığın ya da “Dinlenme” yazdığın günler antrenman sayılmaz; seriyi kırmaz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("İlaç ve takviye") {
                Toggle("İlaç ve takviye takibi", isOn: Binding(
                    get: { store.settings.trackMedication },
                    set: { store.settings.trackMedication = $0
                           Task { await store.refreshMedicationNotifications() } }
                ))
                if store.settings.trackMedication {
                    Toggle("Doz saatinde hatırlat", isOn: Binding(
                        get: { store.settings.notifyMedication },
                        set: { store.settings.notifyMedication = $0
                               Task { await store.refreshMedicationNotifications() } }
                    ))
                    ForEach(store.settings.medications) { item in
                        medicationRow(item)
                    }
                    Button("İlaç veya takviye ekle") { store.addMedication() }
                    Text("Her ilaç veya takviyeye birden çok saat verebilirsin; her saat ayrı bir doz olarak işaretlenir. Alınmış doz için hatırlatma gönderilmez. Bilgisayara geçmediğin günleri Bugün > Gün Sonu sayfasından tamamlarısın.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Su ve protein") {
                Toggle("Takip et", isOn: $store.settings.trackIntake)
                if store.settings.trackIntake {
                    LabeledContent("Su hedefi") {
                        TextField("", value: $store.settings.waterGoalML, format: plainNumber)
                            .frame(width: 70).multilineTextAlignment(.trailing)
                        Text("ml").foregroundStyle(.secondary)
                    }
                    LabeledContent("Su hızlı giriş") {
                        TextField("", value: $store.settings.waterStepML, format: plainNumber)
                            .frame(width: 70).multilineTextAlignment(.trailing)
                        Text("ml").foregroundStyle(.secondary)
                    }
                    LabeledContent("Protein hedefi") {
                        TextField("", value: $store.settings.proteinGoalG, format: plainNumber)
                            .frame(width: 70).multilineTextAlignment(.trailing)
                        Text("g").foregroundStyle(.secondary)
                    }
                    LabeledContent("Protein hızlı giriş") {
                        TextField("", value: $store.settings.proteinStepG, format: plainNumber)
                            .frame(width: 70).multilineTextAlignment(.trailing)
                        Text("g").foregroundStyle(.secondary)
                    }
                }
            }
            if store.settings.trackIntake {
                Section("Bugün") {
                    LabeledContent("Su") {
                        TextField("", value: intakeBinding(Metric.waterML), format: plainNumber)
                            .frame(width: 70).multilineTextAlignment(.trailing)
                        Text("ml").foregroundStyle(.secondary)
                    }
                    LabeledContent("Protein") {
                        TextField("", value: intakeBinding(Metric.proteinG), format: plainNumber)
                            .frame(width: 70).multilineTextAlignment(.trailing)
                        Text("g").foregroundStyle(.secondary)
                    }
                    Text("Panodaki hızlı giriş düğmeleri yukarıdaki adımlarla artırır; günün toplamını buradan elle de düzeltebilirsin.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Text("Set, tekrar ve ağırlık kaydı bilerek yok: menü çubuğu penceresi bunun için dar ve girişi her gün yapmak sürdürülemez. Burada tutulan soru şu — bugün ne var, yaptım mı, kaç gündür sürüyor.")
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
            LabeledContent("İlaç / takviye") {
                HStack(spacing: 4) {
                    // Esnek genişlikli alan satırdan satıra farklı ölçülüp
                    // Form'un sütun hesabını kaydırıyordu; ikisi de sabit.
                    TextField("", text: medBinding(item, \.name), prompt: Text("Ad"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 118)
                    TextField("", text: medBinding(item, \.dose), prompt: Text("Doz"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 58)
                    Toggle("", isOn: medBinding(item, \.enabled))
                        .labelsHidden()
                        .help("Bu ilacı geçici olarak kapat")
                    Button(role: .destructive) { store.removeMedication(item.id) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Sil")
                    Spacer(minLength: 0)
                }
            }
            LabeledContent("Saatler") {
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
                                .help("Bu doz saatini kaldır")
                            }
                        }
                    }
                    Button {
                        var copy = item
                        copy.times.append(item.nextFreeTime())
                        store.updateMedication(copy)
                    } label: { Image(systemName: "plus.circle") }
                    .buttonStyle(.borderless)
                    .help("Doz saati ekle")
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Binlik ayracı olmayan sayı biçimi: hedef alanında "3.000" yerine "3000".
    private var plainNumber: FloatingPointFormatStyle<Double> {
        .number.grouping(.never)
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
        Form {
            Section("Video indir") {
                DownloaderForm()
                Text("Menü çubuğu ikonuna sağ tıklayıp Araçlar > Video indir ile de açılır.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Varsayılanlar") {
                Picker("Biçim", selection: $store.settings.downloadFormat) {
                    ForEach(DownloadService.Format.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                LabeledContent("Klasör") {
                    HStack {
                        Text(store.settings.downloadDestination.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.head)
                        Button("Değiştir") { chooseFolder() }
                        if !store.settings.downloadFolder.isEmpty {
                            Button("Masaüstü") { store.settings.downloadFolder = "" }
                        }
                    }
                }
                Text("Klasör seçmezsen masaüstüne iner.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Güncelleme") {
                Toggle("yt-dlp'yi kendi güncelle", isOn: $store.settings.downloaderAutoUpdate)
                Text("Günde bir kez, ilk indirmeden önce sessizce günceller. Ayrıca indirme “Unable to extract” gibi bir çıkarıcı hatasıyla düşerse zorla güncelleyip bir kez daha dener — YouTube tarafı değiştiğinde takılıp kalmazsın.")
                    .font(.caption).foregroundStyle(.secondary)
                if let tools = Optional(DownloadService.tools()), let path = tools.ytdlp {
                    LabeledContent("Yöntem") {
                        Text(DownloadService.updateStrategy(for: path).describe)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Şimdi güncelle") {
                    Task { await DownloadService.shared.updateTool() }
                }
                if let note = DownloadService.shared.lastUpdateNote {
                    Text(note).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Section("Araçlar") {
                let tools = DownloadService.tools()
                LabeledContent("yt-dlp") {
                    Text(tools.ytdlp ?? "bulunamadı")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(tools.ytdlp == nil ? .red : .secondary)
                }
                LabeledContent("ffmpeg") {
                    Text(tools.ffmpeg ?? "bulunamadı")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(tools.ffmpeg == nil ? .red : .secondary)
                }
                if !tools.ready {
                    Text("brew install \(tools.missing.joined(separator: " "))")
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
                Text("Uygulama kendi başına bir şey kurmaz; araçların kurulumu sana ait.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.settings.downloadDestination
        panel.prompt = "Seç"
        if panel.runModal() == .OK, let url = panel.url {
            store.settings.downloadFolder = url.path
        }
    }

    private var moneyTab: some View {
        Form {
            Section("Düzenli ödemeler") {
                if store.settings.subscriptions.isEmpty {
                    Text("Abonelik, fatura, taksit — bir kez gir, yenileme tarihi kendiliğinden ilerler.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(store.settings.subscriptions) { item in
                    subscriptionRow(item)
                }
                Button("Ödeme ekle") {
                    store.addSubscription(Subscription(name: "Yeni", amount: 0, anchor: Date()))
                }
            }
            Section("Hatırlatma") {
                Picker("Yenilemeden önce", selection: Binding(
                    get: { store.settings.notifyRenewalDays },
                    set: { store.settings.notifyRenewalDays = $0
                           Task { await store.refreshRenewalNotifications() } }
                )) {
                    Text("Kapalı").tag(0)
                    ForEach([1, 3, 7], id: \.self) { Text("\($0) gün önce").tag($0) }
                }
                Text("Bildirim, yenileme gününden geriye sayarak sabah 09:00’da düşer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !store.monthlyTotals.isEmpty {
                Section("Aylık toplam") {
                    ForEach(store.monthlyTotals, id: \.currency) { total in
                        LabeledContent(total.currency) {
                            Text("\(Subscription.symbol(for: total.currency))\(String(format: "%.2f", total.amount))")
                        }
                    }
                    Text("Yıllık ödemeler 12’ye bölünerek eklenir.")
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
                TextField("Ad", text: binding(item, \.name))
                Toggle("", isOn: binding(item, \.enabled)).labelsHidden()
                Button(role: .destructive) {
                    store.removeSubscription(item.id)
                } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
            }
            HStack {
                TextField("Tutar", value: binding(item, \.amount), format: plainNumber)
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
            Text("Sıradaki yenileme: \(TimeFormatters.longDate(item.nextRenewal(after: Date()))) · \(item.daysUntilRenewal()) gün")
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
            Section("Modüller") {
                ForEach(ModuleKind.dashboardCases) { module in
                    Toggle(module.title, isOn: Binding(
                        get: { store.settings.isModuleEnabled(module) },
                        set: { store.setModule(module, enabled: $0) }
                    ))
                    .disabled(!module.canDisable)
                }
                Text("Bugün panosu uygulamanın merkezi olduğu için açık kalır. Diğer modüller kapanınca veri kaynakları ve bildirimleri de durur.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Bugün panosunda göster") {
                if store.summaryCatalog.isEmpty {
                    Text("Pano satırları göründükçe burada listelenir.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(store.summaryCatalog) { line in
                        Toggle(isOn: Binding(
                            get: { store.isSummaryLineVisible(line.id) },
                            set: { store.setSummaryLine(line.id, visible: $0) }
                        )) {
                            Text(line.title)
                            Text(line.module.title)
                        }
                    }
                }
                Text("Modülü kapatmadan yalnızca panodaki satırını kaldırır: sekmesi, ölçümü ve bildirimleri yerinde kalır. Gizlenen satır akşam gün özetinde de görünmez. Bir kez görülen satır, o an üretilmese bile listede kalır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Topbar’da göster") {
                if store.settings.claudeEnabled {
                    visibilityToggle("Claude", id: "claude")
                }
                if store.settings.codexEnabled {
                    visibilityToggle("Codex", id: "codex")
                }
                if store.settings.grokEnabled {
                    visibilityToggle("Grok", id: "grok")
                }
                ForEach(store.settings.customProviders.filter(\.enabled)) { provider in
                    visibilityToggle(provider.name, id: provider.id.uuidString)
                }
                visibilityToggle("Namaz vakitleri", id: "prayer")
                Text("İlk açılışta yalnızca Hâl ikonu durur. Claude, Codex, Grok ve namaz extra’sını buradan tek tek aç. Kapalı olanlar detay kutusunda kalır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Tıklama") {
                Picker("İkona tıklayınca aç", selection: $store.settings.menuBarClickOpens) {
                    ForEach(MenuBarClickTarget.allCases) { Text($0.title).tag($0) }
                }
                Text("Özet ikon ve hiçbir modül görünmezken duran genel ikon her koşulda panoyu açar; ikisi de tek bir şeyi değil genel durumu temsil eder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Yerleşim") {
                Toggle("Kotaları tek ikonda topla", isOn: $store.settings.menuBarCollapsed)
                Text("Açıkken kota ikonları tek bir ikona iner ve yalnızca en dolu kota görünür (ör. Grok %100). Tıklayınca o kotanın detayı açılır, diğerleri sekmelerde durur. Namaz saati ayrı ikon olarak kalır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Ekranlar") {
                Toggle("Diğer ekranların menü çubuğunda da göster", isOn: $store.settings.mirrorToOtherDisplays)
                Text("macOS çoğu ekranda extra’ları zaten kopyalar. Açarsan ikinci satır oluşabilir; kapalı tut.")
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
            Section("Namaz") {
                Toggle("Vakit bildirimi", isOn: notifyBinding(\.notifyPrayer))
                if store.settings.notifyPrayer {
                    Picker("Ne zaman", selection: notifyBinding(\.notifyPrayerMinutes)) {
                        Text("Vakit girince").tag(0)
                        Text("5 dakika önce").tag(5)
                        Text("10 dakika önce").tag(10)
                        Text("15 dakika önce").tag(15)
                        Text("30 dakika önce").tag(30)
                    }
                }
                Text("Güneş vakti yalnızca Genel’de “Güneş’i göster” açıkken bildirilir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Kotalar") {
                Toggle("Kota sıfırlanınca haber ver", isOn: notifyBinding(\.notifyQuotaReset))
                Text("Limit dolduğunda elle kontrol etmek yerine, yeniden kullanılabilir olunca bildirir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Eşik aşılınca uyar", isOn: notifyBinding(\.notifyQuotaThreshold))
                if store.settings.notifyQuotaThreshold {
                    Picker("Eşik", selection: notifyBinding(\.notifyQuotaThresholdPercent)) {
                        ForEach([50, 60, 70, 80, 90], id: \.self) { value in
                            Text("%\(value)").tag(value)
                        }
                    }
                }
                Text("Her olay bir kez bildirilir; aynı pencere için tekrarlamaz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Gün özeti") {
                Toggle("Akşam gün özeti gönder", isOn: notifyBinding(\.notifyDailySummary))
                if store.settings.notifyDailySummary {
                    Picker("Saat", selection: notifyBinding(\.dailySummaryHour)) {
                        ForEach(Array(17...23), id: \.self) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                }
                Text("Günün sonunda derin çalışma, namaz ve hedeflerin özetini bildirir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Gün sonu") {
                Toggle("Gün sonu hatırlatması", isOn: notifyBinding(\.notifyDayClose))
                if store.settings.notifyDayClose {
                    Picker("Saat", selection: notifyBinding(\.dayCloseHour)) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                }
                Text("Seçtiğin saatte bildirim gelir. Tıklayınca Gün Sonu sayfası açılır; kaçırdığın namaz, ilaç ve antrenman işaretlerini oradan düzeltirsin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("İzin, ilk bildirimi açtığında istenir. Sistem Ayarları > Bildirimler > Hâl üzerinden değiştirebilirsin.")
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
            Section("Pano") {
                TextField("Adın", text: $store.settings.displayName, prompt: Text("Panodaki selamlamada kullanılır"))
                LabeledContent("Günlük kayıt") {
                    Text(DailyLog.fileURL.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
            Section("Temizlik modu") {
                Toggle("Temizlik modu", isOn: Binding(
                    get: { store.cleaningMode },
                    set: { store.setCleaningMode($0) }
                ))
                TextField("Başlık", text: $store.settings.cleaningTitle, prompt: Text(AppSettings.defaultCleaningTitle))
                TextField(
                    "Metin",
                    text: $store.settings.cleaningHint,
                    prompt: Text(AppSettings.defaultCleaningHint.replacingOccurrences(of: "\n", with: " ")),
                    axis: .vertical
                )
                .lineLimit(2...5)
                Text("Ekran karartılır; dahili klavye ve trackpad tıklamaları yenilir. Harici mouse çalışır. Boş bırakılan başlık ve metin varsayılana döner.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !DeviceModes.shared.accessibilityTrusted {
                    Text("Ekran kalkanı izin olmadan da çalışır. Sistem kısayollarının (Cmd-Tab gibi) da kilitlenmesi için Hâl’e Erişilebilirlik ve Giriş İzleme izni gerekir.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Klavye kilidi izni iste") {
                        DeviceModes.shared.requestKeyboardLockPermission()
                    }
                    Button("Erişilebilirlik ayarını aç") {
                        DeviceModes.shared.openAccessibilitySettings()
                    }
                    Button("Giriş İzleme ayarını aç") {
                        DeviceModes.shared.openInputMonitoringSettings()
                    }
                }
            }
            if legacyKeychainCount > 0 {
                Section("Eski anahtar zinciri kayıtları") {
                    Text("Gizli değerler artık anahtar zincirinde değil, yalnızca senin okuyabildiğin bir dosyada tutuluyor (\(SecretStore.fileURL.path)). Anahtar zincirinde \(legacyKeychainCount) eski kayıt duruyor; uygulama bunlara dokunmuyor, yani şifre sorusu çıkmıyor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let legacyNote {
                        Text(legacyNote).font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Değerleri taşı ve kayıtları sil") {
                        let result = SecretStore.importLegacyKeychainItems()
                        legacyKeychainCount = SecretStore.legacyItemCount()
                        legacyNote = result.failed > 0
                            ? "\(result.moved) değer taşındı, \(result.failed) kayıt okunamadı."
                            : "\(result.moved) değer taşındı."
                        Task { await store.refresh() }
                    }
                    Text("Bir defalığına kayıt başına şifre sorar; sonrasında kayıtlar silinir ve bir daha sorulmaz.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Okumadan sil", role: .destructive) {
                        let removed = SecretStore.discardLegacyKeychainItems()
                        legacyKeychainCount = SecretStore.legacyItemCount()
                        legacyNote = "\(removed) kayıt silindi."
                    }
                    Text("Silinen kayıtlar geri gelmez. Grok kotası ~/.grok/auth.json oturumundan okunur.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle("Always Wake", isOn: Binding(
                get: { store.settings.alwaysWake },
                set: { store.setAlwaysWake($0) }
            ))
            Text("Açıkken Mac idle uyku ve ekran uykusuna geçmez. Kapak kapanırsa sistem yine uyuyabilir.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Açılışta başlat", isOn: Binding(
                get: { store.settings.launchAtLogin },
                set: { value in
                    store.settings.launchAtLogin = value
                    store.applyLaunchAtLogin()
                }
            ))
            Button("Kotaları yenile") {
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
            Section("Derin çalışma") {
                Toggle("Otomatik ölç", isOn: Binding(
                    get: { store.settings.focusTracking },
                    set: { store.settings.focusTracking = $0; store.applyFocusTracking() }
                ))
                LabeledContent("Günlük hedef") {
                    TextField("", value: $store.settings.focusGoalMinutes, format: .number.grouping(.never))
                        .frame(width: 64)
                        .multilineTextAlignment(.trailing)
                    Text("dk").foregroundStyle(.secondary)
                }
                Text("Öndeki uygulama listedeyse ve Mac iki dakikadır boşta değilse süre kendiliğinden sayılır.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if store.settings.focusTracking {
                Section("Çalışma uygulamaları") {
                    TextField("Uygulamalar", text: focusAppsBinding, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.system(size: 11, design: .monospaced))
                    Text("Virgülle ayır. Uygulama adı veya bundle kimliği bu parçalardan birini içerirse odak sayılır.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Text("Sayaç ve yedi günlük geçmiş yerel daily.json dosyasında tutulur; pomodoro ve görev yönetimi bilerek yok.")
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
            Text("Kişisel durum panosu")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Self.versionText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
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
                Text("Veri kaynakları")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if store.refreshing {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Button("Yenile") { Task { await store.refresh() } }
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
                    copiedDiagnostics ? "Kopyalandı" : "Tanılamayı kopyala",
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
                    name: "Namaz",
                    origin: located
                        ? "aladhan.com · \(store.settings.locationLabel)"
                        : "konum seçilmedi",
                    value: !located
                        ? "konum seç"
                        : (store.nextPrayer.map { "\($0.name) \(TimeFormatters.clock($0.time))" }
                            ?? (ready ? "—" : "yükleniyor")),
                    tint: located && ready ? .green : .orange
                )
            )
        }
        return rows
    }

    private static func origin(for kind: ProviderKind) -> String {
        switch kind {
        case .claude: return "api.anthropic.com"
        case .codex: return "chatgpt.com"
        case .grok: return "grok login"
        case .custom: return "özel kaynak"
        }
    }

    private static func statusValue(_ group: QuotaGroup) -> String {
        switch group.status {
        case .ready:
            return group.menuBarOverride ?? group.headlineWindow.map { "\($0.percentText) · \($0.title)" } ?? "hazır"
        case .loading: return "yükleniyor"
        case .missingAuth: return "oturum yok"
        case .error: return "okunamadı"
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
        return "sürüm \(short) (\(build))"
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
            "Modüller: \(store.modules.map(\.title).joined(separator: ", "))"
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
            lines.append("Sorunlar:")
            lines.append(contentsOf: problems)
        }
        if let error = store.lastError {
            lines.append("")
            lines.append("Son hata: \(error)")
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
