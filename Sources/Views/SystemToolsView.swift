import AppKit
import CoreAudio
import SwiftUI

// Satır yüksekliği düğmeyi içine alır; List hücresi düğmenin çerçevesini kesiyordu.
private func toolButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
}

private func toolRow<Trailing: View>(title: String, detail: String?, @ViewBuilder trailing: () -> Trailing) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .layoutPriority(0)
            HStack(spacing: 6) {
                trailing()
            }
            .fixedSize(horizontal: true, vertical: true)
            .layoutPriority(1)
        }
        .padding(.vertical, 8)
        Divider()
    }
}

private func labeledBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

// MARK: - Homebrew

struct HomebrewUtilityView: View {
    var body: some View {
        HomebrewPanel()
            .padding(20)
            .frame(minWidth: 560, minHeight: 480)
    }
}

struct HomebrewPanel: View {
    @ObservedObject private var brew = HomebrewService.shared
    @State private var query = ""
    @State private var mode = 0
    @State private var kind = 0
    @State private var cask = false
    @State private var showDependencies = false
    @State private var selected: String?
    @State private var pending: BrewPackage?
    @State private var stopPending: BrewServiceInfo?
    @State private var searched = false

    private var installed: [BrewPackage] { brew.formulae + brew.casks }
    private var visible: [BrewPackage] {
        installed.filter { package in
            (kind == 0 || (kind == 1 && !package.cask) || (kind == 2 && package.cask) || (kind == 3 && package.outdated))
            && (showDependencies || !package.isDependency)
            && (query.isEmpty || package.name.localizedCaseInsensitiveContains(query) || package.summary.localizedCaseInsensitiveContains(query))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if brew.brewPath == nil {
                    SettingsCard {
                        ToolEmptyState(symbol: "shippingbox", title: L("Homebrew yüklü değil", "Homebrew is not installed"), detail: L("Paketleri yönetmek için önce Homebrew’u kur.", "Install Homebrew to manage packages."))
                        Link(L("Homebrew web sitesini aç", "Open Homebrew website"), destination: URL(string: "https://brew.sh")!)
                        Button(L("Yeniden denetle", "Check again")) { brew.reload(); Task { await brew.refreshInstalled() } }
                    }
                } else {
                    SettingsCard {
                        HStack {
                            Picker(L("Görünüm", "View"), selection: $mode) {
                                Text(L("Yüklü", "Installed")).tag(0)
                                Text(L("Paket bul", "Find packages")).tag(1)
                                Text(L("Servisler", "Services")).tag(2)
                            }.pickerStyle(.segmented).labelsHidden()
                            Button { Task { await brew.refreshInstalled() } } label: { Image(systemName: "arrow.clockwise") }
                                .help(L("Listeyi yenile", "Refresh list")).disabled(brew.busy)
                        }
                        if mode != 2 {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                                TextField(mode == 0 ? L("Yüklü paketleri filtrele", "Filter installed packages") : L("Paket adıyla ara", "Search by package name"), text: $query)
                                    .textFieldStyle(.plain).onSubmit { search() }
                                if !query.isEmpty {
                                    Button { query = ""; searched = false } label: { Image(systemName: "xmark.circle.fill") }
                                        .buttonStyle(.plain).foregroundStyle(.secondary).help(L("Aramayı temizle", "Clear search"))
                                }
                            }.padding(10).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                            if mode == 0 {
                                ViewThatFits(in: .horizontal) {
                                    HStack { filters; Spacer(); dependencyToggle }
                                    VStack(alignment: .leading, spacing: 10) { filters; dependencyToggle }
                                }
                            } else {
                                HStack {
                                    Picker(L("Paket türü", "Package type"), selection: $cask) {
                                        Text(L("Komut satırı", "Command line")).tag(false)
                                        Text(L("Uygulamalar", "Applications")).tag(true)
                                    }.labelsHidden().frame(maxWidth: 220)
                                    Spacer()
                                    Button(L("Ara", "Search")) { search() }.disabled(brew.busy || query.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                            }
                        }
                        if brew.busy { HStack { ProgressView().controlSize(.small); Text(L("İşlem sürüyor…", "Working…")).font(.caption).foregroundStyle(.secondary) } }
                    }
                    if mode == 2 { services }
                    else if mode == 1 { discovery }
                    else { packages }
                    if let error = brew.error {
                        Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    }
                    if !brew.log.isEmpty {
                        SettingsCard {
                            DisclosureGroup(L("İşlem geçmişi", "Activity log")) {
                                Text(brew.log).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(.top, 8)
                            }
                        }
                    }
                }
            }.padding(.bottom, 12)
        }
        .task { if brew.formulae.isEmpty && brew.casks.isEmpty { await brew.refreshInstalled() } }
        .onChange(of: mode) { _, _ in query = ""; searched = false; selected = nil }
        .onChange(of: cask) { _, _ in searched = false }
        .alert(L("Paketi kaldır?", "Remove this package?"), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button(L("Vazgeç", "Cancel"), role: .cancel) { pending = nil }
            Button(L("Kaldır", "Remove"), role: .destructive) {
                if let package = pending { Task { await brew.uninstall(package, zap: false) } }; pending = nil
            }
        } message: { Text(pending?.name ?? "") }
        .alert(L("Servisi durdur?", "Stop this service?"), isPresented: Binding(get: { stopPending != nil }, set: { if !$0 { stopPending = nil } })) {
            Button(L("Vazgeç", "Cancel"), role: .cancel) { stopPending = nil }
            Button(L("Durdur", "Stop"), role: .destructive) {
                if let service = stopPending { Task { await brew.setService(service, running: false) } }; stopPending = nil
            }
        } message: { Text(stopPending?.name ?? "") }
    }

    private var filters: some View {
        Picker(L("Paketler", "Packages"), selection: $kind) {
            Text(Lf("Tümü %1$d", "All %1$d", installed.count)).tag(0)
            Text(L("Formüller", "Formulae")).tag(1)
            Text(L("Cask’ler", "Casks")).tag(2)
            Text(Lf("Güncel değil %1$d", "Outdated %1$d", installed.filter(\.outdated).count)).tag(3)
        }.labelsHidden().pickerStyle(.menu).fixedSize()
    }

    private var dependencyToggle: some View {
        Toggle(L("Bağımlılıkları göster", "Show dependencies"), isOn: $showDependencies).font(.caption).toggleStyle(.checkbox)
    }

    private var packages: some View {
        SettingsCard {
            HStack {
                Text(L("Yüklü paketler", "Installed packages")).font(.headline)
                ToolBadge(title: String(visible.count))
                Spacer()
            }
            if visible.isEmpty {
                ToolEmptyState(symbol: "line.3.horizontal.decrease.circle", title: L("Eşleşen paket yok", "No matching packages"), detail: L("Filtreyi değiştir veya Paket bul bölümünde ara.", "Change the filter or search in Find packages."))
            }
            LazyVStack(spacing: 0) {
                ForEach(visible) { package in
                    packageRow(package, installed: true)
                    if package.id != visible.last?.id { Divider().padding(.vertical, 10) }
                }
            }
        }
    }

    private var discovery: some View {
        SettingsCard {
            if !searched {
                ToolEmptyState(symbol: "shippingbox", title: L("Yeni bir paket bul", "Find a new package"), detail: L("Bir ad yazıp Ara’ya bas. Sonuçtan paketi kurabilirsin.", "Enter a name and press Search, then install from the results."))
            } else if brew.searchResults.isEmpty && !brew.busy {
                ToolEmptyState(symbol: "magnifyingglass", title: L("Sonuç bulunamadı", "No results"), detail: L("Başka bir ad veya paket türü dene.", "Try another name or package type."))
            } else {
                ForEach(brew.searchResults) { package in
                    packageRow(package, installed: installed.contains { $0.id == package.id })
                    if package.id != brew.searchResults.last?.id { Divider().padding(.vertical, 10) }
                }
            }
        }
    }

    private func packageRow(_ package: BrewPackage, installed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: package.cask ? "app.dashed" : "terminal").foregroundStyle(.tint).frame(width: 26)
                Button { withAnimation { selected = selected == package.id ? nil : package.id } } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(package.name).font(.system(size: 13, weight: .semibold))
                        if !package.version.isEmpty { Text(package.version).font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if package.outdated { ToolBadge(title: L("Güncelleme", "Update"), color: .orange) }
                if !installed {
                    Button(L("Kur", "Install")) { Task { await brew.install(name: package.name, cask: package.cask) } }.disabled(brew.busy)
                } else {
                    Image(systemName: selected == package.id ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.secondary)
                }
            }
            if selected == package.id {
                VStack(alignment: .leading, spacing: 10) {
                    if !package.summary.isEmpty { Text(package.summary).font(.callout).foregroundStyle(.secondary) }
                    HStack {
                        ToolBadge(title: package.cask ? L("Uygulama", "Application") : L("Komut satırı", "Command line"))
                        if package.isDependency { ToolBadge(title: L("Bağımlılık", "Dependency")) }
                        Spacer()
                        if let url = URL(string: package.homepage), ["http", "https"].contains(url.scheme ?? "") { Link(L("Web sitesi", "Website"), destination: url) }
                    }
                    if !package.dependencies.isEmpty {
                        Text(Lf("Bağımlılıklar: %1$@", "Dependencies: %1$@", package.dependencies.joined(separator: ", "))).font(.caption).foregroundStyle(.secondary)
                    }
                    if installed {
                        HStack {
                            if package.outdated { Button(L("Güncelle", "Update")) { Task { await brew.upgrade(package) } }.disabled(brew.busy) }
                            Spacer()
                            Button(L("Paketi kaldır…", "Remove package…"), role: .destructive) { pending = package }.disabled(brew.busy)
                        }
                    }
                }.padding(12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
            }
        }
    }

    private var services: some View {
        SettingsCard(title: L("Arka plan servisleri", "Background services"), symbol: "gearshape.2") {
            if brew.services.isEmpty {
                ToolEmptyState(symbol: "gearshape.2", title: L("Servis yok", "No services"), detail: L("Homebrew servislerin burada görünür.", "Your Homebrew services appear here."))
            }
            ForEach(brew.services) { service in
                HStack {
                    Circle().fill(service.running ? Color.green : Color.secondary).frame(width: 7, height: 7)
                    Text(service.name).font(.system(size: 13, weight: .medium))
                    Spacer()
                    ToolBadge(title: service.running ? L("Çalışıyor", "Running") : L("Durdu", "Stopped"), color: service.running ? .green : .secondary)
                    Button(service.running ? L("Durdur", "Stop") : L("Başlat", "Start")) {
                        if service.running { stopPending = service } else { Task { await brew.setService(service, running: true) } }
                    }.disabled(brew.busy)
                }
                if service.id != brew.services.last?.id { Divider() }
            }
        }
    }

    private func search() {
        guard mode == 1 else { return }
        searched = true
        Task { await brew.search(query, cask: cask) }
    }
}

// MARK: - Ses

struct VolumeMixerUtilityView: View {
    var body: some View {
        VolumeMixerPanel()
            .padding(20)
            .frame(minWidth: 480, minHeight: 420)
    }
}

struct VolumeMixerPanel: View {
    @ObservedObject private var mixer = VolumeMixer.shared
    @Environment(\.toolPresentation) private var presentation

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: presentation == .menu ? 10 : 14) {
                deviceBlock(
                    symbol: "speaker.wave.2",
                    title: L("Çıkış", "Output"),
                    devices: mixer.outputs,
                    selection: mixer.outputID,
                    set: mixer.setOutputDevice,
                    level: Level(
                        value: mixer.outputVolume,
                        range: 0...1,
                        muted: mixer.outputMuted,
                        set: mixer.setOutputVolume,
                        toggleMute: { mixer.setOutputMuted(!mixer.outputMuted) }
                    )
                )
                deviceBlock(
                    symbol: "bell",
                    title: L("Sistem sesleri", "System sounds"),
                    devices: mixer.outputs,
                    selection: mixer.systemOutputID,
                    set: mixer.setSystemOutputDevice,
                    level: nil
                )
                if !mixer.inputs.isEmpty {
                    deviceBlock(
                        symbol: "mic",
                        title: L("Mikrofon", "Microphone"),
                        devices: mixer.inputs,
                        selection: mixer.inputID,
                        set: mixer.setInputDevice,
                        level: Level(
                            value: mixer.inputVolume,
                            range: 0...1,
                            muted: mixer.inputMuted,
                            set: mixer.setInputVolume,
                            toggleMute: { mixer.setInputMuted(!mixer.inputMuted) }
                        )
                    )
                }
                Divider().padding(.vertical, 2)
                HStack {
                    Text(L("Uygulamalar", "Applications")).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    ToolBadge(title: Lf("%1$d uygulama", "%1$d apps", mixer.apps.count))
                }.padding(.top, 4)
                if mixer.apps.isEmpty {
                    SettingsCard {
                        ToolEmptyState(symbol: "speaker.wave.2", title: L("Şu an ses çalan uygulama yok", "No apps playing audio"), detail: L("Ses çalmaya başladığında uygulama burada görünür.", "Apps appear here when they start playing audio."))
                    }
                }
                ForEach(mixer.apps) { app in
                    SettingsCard {
                        HStack(spacing: 8) {
                            appIcon(app.iconPath)
                            Text(app.name)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(app.playing ? Color.primary : Color.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if app.playing { Circle().fill(Color.green).frame(width: 6, height: 6).help(L("Ses çalıyor", "Playing audio")) }
                            Button("100%") { mixer.setVolume(id: app.id, 1) }
                                .controlSize(.small).disabled(abs(app.volume - 1) < 0.005)
                                .help(L("Seviyeyi sıfırla", "Reset level"))
                            muteButton(
                                muted: app.muted,
                                helpOn: L("Sesi aç", "Unmute"),
                                helpOff: L("Sessize al", "Mute")
                            ) {
                                mixer.setMuted(id: app.id, !app.muted)
                            }
                        }
                        levelRow(
                            value: app.volume,
                            range: 0...1.5,
                            muted: app.muted,
                            set: { mixer.setVolume(id: app.id, $0) }
                        )
                    }
                }
                DisclosureGroup(L("Ses mikseri hakkında", "About the mixer")) {
                    Text(L("100% özgün ses seviyesidir. Uygulama sesini 150%’ye kadar artırabilirsin. Ses kaydı saklanmaz; uygulama başına kontrol için macOS ses yakalama izni gerekir.", "100% is the original volume. You can boost apps up to 150%. No recordings are saved; per-app control needs macOS audio capture access."))
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                }.font(.caption)
                if let note = mixer.note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    toolButton(L("Ses kaydı iznini aç", "Open audio recording permission")) {
                        mixer.openCaptureSettings()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
        }
        .onAppear { mixer.setWatching(true) }
        .onDisappear { mixer.setWatching(false) }
    }

    private struct Level {
        var value: Double
        var range: ClosedRange<Double>
        var muted: Bool
        var set: (Double) -> Void
        var toggleMute: () -> Void
    }

    private func deviceBlock(
        symbol: String,
        title: String,
        devices: [MixerDevice],
        selection: AudioDeviceID,
        set: @escaping (AudioDeviceID) -> Void,
        level: Level?
    ) -> some View {
        SettingsCard {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 11)).frame(width: 16).foregroundStyle(.secondary)
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                deviceMenu(title: title, devices: devices, selection: selection, set: set)
                    .frame(width: presentation == .menu ? 168 : 220)
            }
            if let level {
                HStack(spacing: 8) {
                    levelRow(value: level.value, range: level.range, muted: level.muted, set: level.set)
                    muteButton(muted: level.muted, helpOn: L("Sesi aç", "Unmute"), helpOff: L("Sessize al", "Mute"), action: level.toggleMute)
                }
            }
        }
    }

    private func deviceMenu(title: String, devices: [MixerDevice], selection: AudioDeviceID, set: @escaping (AudioDeviceID) -> Void) -> some View {
        Picker(title, selection: Binding(get: { selection }, set: set)) {
            if !devices.contains(where: { $0.id == selection }) {
                Text(L("Aygıt kullanılamıyor", "Device unavailable")).tag(selection)
            }
            ForEach(devices) { device in Text(device.name).tag(device.id) }
        }
        .labelsHidden().pickerStyle(.menu).controlSize(.small)
        .help(L("Ses aygıtını değiştir", "Change audio device"))
        .disabled(devices.isEmpty)
    }

    private func levelRow(
        value: Double,
        range: ClosedRange<Double>,
        muted: Bool,
        set: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Slider(value: Binding(get: { value }, set: set), in: range)
                .disabled(muted)
            Text(percent(value))
                .font(.system(size: 12, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .fixedSize()
        }
    }

    private func muteButton(muted: Bool, helpOn: String, helpOff: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: muted ? "speaker.slash" : "speaker.wave.2")
                .font(.system(size: 12))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(muted ? helpOn : helpOff)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func appIcon(_ path: String?) -> some View {
        let image: NSImage = {
            if let path { return NSWorkspace.shared.icon(forFile: path) }
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }()
        return Image(nsImage: image)
            .resizable()
            .frame(width: 30, height: 30)
    }
}

// MARK: - Güncellemeler

struct UpdatesUtilityView: View {
    var body: some View {
        UpdatesPanel()
            .padding(20)
            .frame(minWidth: 560, minHeight: 480)
    }
}

struct UpdatesPanel: View {
    @ObservedObject private var updates = SystemUpdateService.shared
    @State private var pending: AvailableUpdate?
    @State private var brewAll = false
    @State private var showPackages = false

    private var groups: [UpdateOrigin] { [.sparkle, .appStore, .brew, .system].filter { origin in updates.items.contains { $0.origin == origin } } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsCard {
                    HStack(spacing: 12) {
                        Image(systemName: updates.scanning ? "arrow.triangle.2.circlepath" : "checkmark.shield")
                            .font(.system(size: 23)).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(updates.scanning ? L("Güncellemeler aranıyor", "Checking for updates") : updates.summary.isEmpty ? L("Uygulamalarını güncel tut", "Keep your apps up to date") : updates.summary)
                                .font(.system(size: 14, weight: .semibold))
                            if let date = updates.lastChecked {
                                Text(Lf("Son denetleme: %1$@", "Last checked: %1$@", date.formatted(.dateTime.locale(Language.locale).day().month().hour().minute())))
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(L("Yeni sürümler kendi kaynaklarından yüklenir.", "New versions are installed from their own sources.")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if updates.scanning { ProgressView().controlSize(.small) }
                    }
                    Button { Task { await updates.scan() } } label: {
                        Label(L("Şimdi denetle", "Check now"), systemImage: "arrow.clockwise")
                    }.disabled(updates.scanning || updates.applying || !anySource)
                    if updates.applying { Label(L("Güncelleme sürüyor…", "Updating…"), systemImage: "arrow.down.circle").font(.caption).foregroundStyle(.secondary) }
                    if !updates.scanning, !updates.summary.isEmpty, updates.items.isEmpty, updates.sourceErrors.isEmpty {
                        Label(L("Seçili kaynaklarda yeni sürüm bulunamadı.", "No new versions found in the selected sources."), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                    }
                    if !updates.sourceErrors.isEmpty {
                        Divider()
                        ForEach(updates.sourceErrors, id: \.self) { error in
                            Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                ForEach(groups, id: \.rawValue) { origin in
                    SettingsCard {
                        if origin == .brew {
                            DisclosureGroup(isExpanded: $showPackages) {
                                updateRows(origin).padding(.top, 12)
                            } label: {
                                HStack {
                                    Label(origin.title, systemImage: symbol(origin)).font(.headline)
                                    ToolBadge(title: String(items(origin).count), color: .orange)
                                    Spacer()
                                }
                            }
                            if !items(origin).isEmpty {
                                Button(L("Homebrew paketlerini güncelle…", "Update Homebrew packages…")) { brewAll = true }
                                    .disabled(updates.applying || updates.scanning)
                            }
                        } else {
                            HStack {
                                Label(origin.title, systemImage: symbol(origin)).font(.headline)
                                if origin != .appStore || !items(origin).contains(where: { $0.token == "store" }) { ToolBadge(title: String(items(origin).count)) }
                                Spacer()
                            }
                            updateRows(origin)
                        }
                    }
                }
                SettingsCard(title: L("Denetleme tercihleri", "Check preferences"), symbol: "clock.arrow.circlepath") {
                    HStack {
                        Text(L("Arka planda denetle", "Check in background")).font(.callout)
                        Spacer()
                        Picker(L("Sıklık", "Frequency"), selection: $updates.options.intervalDays) {
                            Text(L("Kapalı", "Off")).tag(0)
                            Text(L("Her gün", "Daily")).tag(1)
                            Text(L("Her hafta", "Weekly")).tag(7)
                        }.labelsHidden().frame(maxWidth: 170)
                    }
                    Text(L("Yalnızca denetler. Kurulumu her zaman sen başlatırsın; uygulama kapalıyken denetleme yapılmaz.", "Checks only. You always start installation; checks run while Hâl is open."))
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    DisclosureGroup(L("Güncelleme kaynakları", "Update sources")) {
                        VStack(spacing: 14) {
                            SettingsToggleRow(title: L("Yüklü uygulamalar", "Installed apps"), detail: L("Desteklenen geliştirici güncelleme akışlarını denetler.", "Checks supported developer update feeds."), symbol: "app", isOn: $updates.options.includeApps)
                            SettingsToggleRow(title: "Homebrew", detail: L("Formülleri ve cask’leri dahil eder.", "Includes formulae and casks."), symbol: "shippingbox", isOn: $updates.options.includeBrew)
                            SettingsToggleRow(title: "App Store", detail: L("Mağaza güncellemelerini denetler veya App Store’u açar.", "Checks store updates or opens the App Store."), symbol: "bag", isOn: $updates.options.includeAppStore)
                            SettingsToggleRow(title: "macOS", detail: L("Sistem yazılımı güncellemelerini dahil eder.", "Includes system software updates."), symbol: "laptopcomputer", isOn: $updates.options.includeSystem)
                        }.padding(.top, 14)
                    }
                    .disabled(updates.scanning || updates.applying)
                    if !anySource { Label(L("Denetlemek için bir kaynak seç.", "Select a source to check."), systemImage: "info.circle").font(.caption).foregroundStyle(.orange) }
                }
                if !updates.log.isEmpty {
                    SettingsCard {
                        DisclosureGroup(L("Denetleme ayrıntıları", "Check details")) {
                            Text(updates.log).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(.top, 8)
                        }
                    }
                }
            }.padding(.bottom, 12)
        }
        .alert(brewAll ? L("Homebrew güncellemeleri kurulsun mu?", "Install Homebrew updates?") : L("Güncelleme kurulsun mu?", "Install this update?"), isPresented: Binding(get: { pending != nil || brewAll }, set: { if !$0 { pending = nil; brewAll = false } })) {
            Button(L("Vazgeç", "Cancel"), role: .cancel) { pending = nil; brewAll = false }
            Button(L("Sürdür", "Continue")) {
                if brewAll { brewAll = false; Task { await updates.upgradeAllBrew() } }
                else if let item = pending { pending = nil; Task { await updates.apply(item) } }
            }
        } message: {
            Text(brewAll ? L("Eski formüller ve cask’ler yükseltilir. Bazı uygulamalar yeniden açılabilir.", "Outdated formulae and casks are upgraded. Some apps may reopen.") : pending?.origin == .system ? L("macOS güncellemesi kurulur. Mac yeniden başlayabilir ve parola sorulabilir.", "A macOS update is installed. Your Mac may restart and ask for a password.") : pending?.name ?? "")
        }
    }

    private var anySource: Bool { updates.options.includeApps || updates.options.includeBrew || updates.options.includeAppStore || updates.options.includeSystem }
    private func items(_ origin: UpdateOrigin) -> [AvailableUpdate] { updates.items.filter { $0.origin == origin } }
    private func symbol(_ origin: UpdateOrigin) -> String {
        switch origin { case .system: return "laptopcomputer"; case .brew: return "shippingbox"; case .appStore: return "bag"; case .sparkle: return "app" }
    }
    private func updateRows(_ origin: UpdateOrigin) -> some View {
        LazyVStack(spacing: 10) {
            ForEach(items(origin)) { item in
                HStack(spacing: 10) {
                    if origin == .sparkle {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.token)).resizable().frame(width: 30, height: 30)
                    } else {
                        Image(systemName: symbol(origin)).foregroundStyle(.tint).frame(width: 30, height: 30)
                            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                        if !item.versions.isEmpty && !item.name.contains(item.versions) {
                            Text(item.versions).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 8)
                    Button(item.origin == .sparkle || item.token == "store" ? L("Aç", "Open") : L("Güncelle", "Update")) {
                        if item.origin == .sparkle || item.token == "store" { Task { await updates.apply(item) } }
                        else { pending = item }
                    }.disabled(updates.applying || updates.scanning)
                }.padding(12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

// MARK: - Uyanık tutma

struct KeepAwakePanel: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var wake = WakeController.shared
    var onEditApps: () -> Void
    @State private var arming = false
    @State private var untilTime = Date()
    @State private var showClock = false

    private var presets: [(id: String, title: String, minutes: Int)] {
        [
            ("15", L("15d", "15m"), 15),
            ("30", L("30d", "30m"), 30),
            ("60", L("1sa", "1h"), 60),
            ("120", L("2sa", "2h"), 120),
            ("240", L("4sa", "4h"), 240),
            ("480", L("8sa", "8h"), 480)
        ]
    }

    private var followsNormalRules: Bool {
        !store.settings.alwaysWake && !arming
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard {
                SettingsToggleRow(title: L("Mac’i uyanık tut", "Keep Mac awake"), detail: store.settings.alwaysWake ? hint : L("Kapalıyken normal enerji ayarların geçerlidir.", "When off, your normal energy settings apply."), symbol: "moon.zzz", isOn: Binding(
                    get: { store.settings.alwaysWake },
                    set: { on in
                        arming = false; showClock = false
                        store.setAlwaysWake(on)
                    }
                ))
                Divider()
                Text(L("Süre", "Duration")).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(presets, id: \.id) { chip in
                        chipButton(chip.title, selected: selectedMinutes == chip.minutes) { togglePreset(chip.minutes) }
                    }
                    chipButton("∞", selected: store.settings.alwaysWake && store.settings.wakeIndefinite) { toggleForever() }
                    chipButton(L("Saate kadar…", "Until…"), selected: clockSelected) { toggleClock() }
                }
                if showClock || clockSelected {
                    HStack {
                        Label(L("Bitiş saati", "End time"), systemImage: "clock")
                        Spacer()
                        DatePicker(L("Saat", "Time"), selection: $untilTime, displayedComponents: .hourAndMinute)
                            .labelsHidden().onChange(of: untilTime) { _, value in start(minutes: minutes(until: value)) }
                    }.font(.callout)
                }
            }
            SettingsCard {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsToggleRow(title: L("Çalışma uygulamaları", "Work apps"), detail: L("Seçili uygulamalardan biri öndeyken uyanık kalır.", "Stays awake while a selected app is in front."), symbol: "app.badge", isOn: $store.settings.wakeWhileApps)
                        if store.settings.wakeWhileApps {
                            Text(store.settings.focusApps.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            Button(L("Uygulama listesini düzenle", "Edit app list"), action: onEditApps).controlSize(.small)
                        }
                        Divider()
                        SettingsToggleRow(title: L("Güç ve harici ekran", "Power and external display"), detail: L("Mac prize takılıyken veya harici ekran bağlıyken uyanık kalır.", "Stays awake on AC power or when an external display is connected."), symbol: "powerplug", isOn: $store.settings.wakeWhilePowerOrDisplay)
                        Text(L("Bu koşullar, sürekli mod kapalıyken süreye ek olarak çalışır. En az biri sağlandığında Mac uyanık kalır.", "These conditions work alongside the timer when Always is off. Your Mac stays awake while at least one is met."))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(.top, 14)
                } label: {
                    HStack {
                        Label(L("Otomatik koşullar", "Automatic conditions"), systemImage: "slider.horizontal.3").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        let count = [store.settings.wakeWhileApps, store.settings.wakeWhilePowerOrDisplay].filter { $0 }.count
                        ToolBadge(title: Lf("%1$d etkin", "%1$d active", count))
                    }
                }
            }
            SettingsCard {
                SettingsToggleRow(title: L("Kapak kapalıyken devam et", "Continue while the lid is closed"), detail: lidCaption, symbol: "laptopcomputer", isOn: $store.settings.wakeWhileLidClosed)
                    .disabled(WakeController.lidClosed() == nil)
            }
        }
        .onChange(of: store.settings.alwaysWake) { _, on in if on { arming = false } }
    }

    private var selectedMinutes: Int? {
        guard store.settings.alwaysWake, !store.settings.wakeIndefinite, store.settings.wakeTimerEnabled else { return nil }
        let minutes = store.settings.wakeTimerMinutes
        return presets.contains(where: { $0.minutes == minutes }) ? minutes : nil
    }

    private var clockSelected: Bool {
        store.settings.alwaysWake
            && !store.settings.wakeIndefinite
            && store.settings.wakeTimerEnabled
            && selectedMinutes == nil
    }

    private var hint: String {
        if store.settings.alwaysWake, !wake.status.isEmpty {
            return wake.status
        }
        return L(
            "Başlatmak için bir çipe tıklayın. Durdurmak için tekrar tıklayın.",
            "Click a chip to start. Click it again to stop."
        )
    }

    private var lidCaption: String {
        if WakeController.lidClosed() == nil {
            return L("Bu Mac’te kapak yok.", "This Mac has no lid.")
        }
        return L(
            "Kapak kapalıyken boşta uykuyu keser. Harici güç ve ekran yoksa macOS kapağı kapatınca yine uyuyabilir.",
            "Blocks idle sleep while the lid is closed. Without external power and a display, macOS can still sleep on lid close."
        )
    }

    private func chipButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .background(
                    selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private func togglePreset(_ minutes: Int) {
        showClock = false
        if selectedMinutes == minutes {
            store.setAlwaysWake(false)
            return
        }
        start(minutes: minutes)
    }

    private func toggleForever() {
        showClock = false
        if store.settings.alwaysWake && store.settings.wakeIndefinite {
            store.setAlwaysWake(false)
            return
        }
        var next = store.settings
        next.alwaysWake = true
        next.wakeIndefinite = true
        next.wakeTimerEnabled = false
        next.wakeUntil = nil
        store.settings = next
        arming = false
    }

    private func toggleClock() {
        if clockSelected {
            showClock = false
            store.setAlwaysWake(false)
            return
        }
        showClock = true
        if untilTime <= Date() {
            untilTime = Date().addingTimeInterval(60 * 60)
        }
        start(minutes: minutes(until: untilTime))
    }

    private func start(minutes: Int) {
        var next = store.settings
        next.alwaysWake = true
        next.wakeIndefinite = false
        next.wakeTimerEnabled = true
        next.wakeTimerMinutes = max(5, minutes)
        next.wakeUntil = nil
        store.settings = next
        arming = false
    }

    private func minutes(until date: Date) -> Int {
        var target = date
        if target <= Date() {
            target = Calendar.current.date(byAdding: .day, value: 1, to: target) ?? target.addingTimeInterval(86_400)
        }
        return max(5, Int(target.timeIntervalSinceNow / 60))
    }
}
