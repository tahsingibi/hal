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
    @State private var installName = ""
    @State private var cask = false
    @State private var query = ""
    @State private var pending: BrewPackage?
    @State private var stopPending: BrewServiceInfo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if brew.brewPath == nil {
                    Text(L(
                        "Homebrew bu Mac’te yok. Kurulum brew.sh üzerinden yapılır; Hâl kendisi kurmaz.",
                        "Homebrew is not on this Mac. Install it from brew.sh; Hâl does not install it."
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Link("brew.sh", destination: URL(string: "https://brew.sh")!)
                    toolButton(L("Yeniden bak", "Look again")) { brew.reload() }
                } else {
                    labeledBlock(L("Kur", "Install")) {
                        TextField(L("Paket adı", "Package name"), text: $installName)
                            .textFieldStyle(.roundedBorder)
                        Picker(L("Tür", "Kind"), selection: $cask) {
                            Text(L("Formül", "Formula")).tag(false)
                            Text("Cask").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        toolButton(L("Kur", "Install")) {
                            let name = installName
                            Task { await brew.install(name: name, cask: cask) }
                        }
                        .disabled(brew.busy || installName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    labeledBlock(L("Ara", "Search")) {
                        TextField(L("Ara", "Search"), text: $query)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { Task { await brew.search(query, cask: cask) } }
                        if brew.searchResults.isEmpty {
                            Text(L("Sonuç yok.", "No results."))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(brew.searchResults) { item in
                                toolRow(title: item.name, detail: nil) {
                                    toolButton(L("Kur", "Install")) {
                                        installName = item.name
                                        Task { await brew.install(name: item.name, cask: item.cask) }
                                    }
                                    .disabled(brew.busy)
                                }
                            }
                        }
                    }
                    packageSection(L("Formüller", "Formulae"), brew.formulae)
                    packageSection("Cask", brew.casks)
                    labeledBlock(L("Servisler", "Services")) {
                        if brew.services.isEmpty {
                            Text(L("Kayıtlı servis yok.", "No services."))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(brew.services) { service in
                            toolRow(title: service.name, detail: service.status) {
                                toolButton(service.running ? L("Durdur", "Stop") : L("Başlat", "Start")) {
                                    if service.running {
                                        stopPending = service
                                    } else {
                                        Task { await brew.setService(service, running: true) }
                                    }
                                }
                                .disabled(brew.busy)
                            }
                        }
                    }
                    if !brew.log.isEmpty || brew.error != nil {
                        labeledBlock(L("Çıktı", "Output")) {
                            if let error = brew.error {
                                Text(error)
                                    .foregroundStyle(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(brew.log)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
        }
        .task { await brew.refreshInstalled() }
        .alert(L("Paketi kaldır?", "Remove this package?"), isPresented: Binding(
            get: { pending != nil },
            set: { if !$0 { pending = nil } }
        )) {
            Button(L("Vazgeç", "Cancel"), role: .cancel) { pending = nil }
            Button(L("Kaldır", "Remove"), role: .destructive) {
                if let pending { Task { await brew.uninstall(pending, zap: false) } }
                self.pending = nil
            }
            if pending?.cask == true {
                Button(L("Tercihleriyle kaldır", "Remove with preferences"), role: .destructive) {
                    if let pending { Task { await brew.uninstall(pending, zap: true) } }
                    self.pending = nil
                }
            }
        } message: {
            if let pending {
                Text(pending.cask
                     ? Lf("%1$@ kaldırılır. Cask ise tercihler ayrıca silinebilir.", "%1$@ will be removed. A cask can also drop its preferences.", pending.name)
                     : Lf("%1$@ kaldırılır.", "%1$@ will be removed.", pending.name))
            }
        }
        .alert(L("Servisi durdur?", "Stop this service?"), isPresented: Binding(
            get: { stopPending != nil },
            set: { if !$0 { stopPending = nil } }
        )) {
            Button(L("Vazgeç", "Cancel"), role: .cancel) { stopPending = nil }
            Button(L("Durdur", "Stop"), role: .destructive) {
                if let stopPending { Task { await brew.setService(stopPending, running: false) } }
                self.stopPending = nil
            }
        } message: {
            if let stopPending {
                Text(Lf("%1$@ durur.", "%1$@ will stop.", stopPending.name))
            }
        }
    }

    @ViewBuilder
    private func packageSection(_ title: String, _ packages: [BrewPackage]) -> some View {
        labeledBlock(title) {
            if packages.isEmpty {
                Text(L("Yok.", "None."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ForEach(packages) { package in
                toolRow(title: package.name, detail: package.version.nilIfEmpty) {
                    HStack(spacing: 6) {
                        toolButton(L("Yükselt", "Upgrade")) { Task { await brew.upgrade(package) } }
                            .disabled(brew.busy)
                        toolButton(L("Kaldır", "Remove")) { pending = package }
                            .disabled(brew.busy)
                    }
                }
            }
        }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
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
                Divider()
                if mixer.apps.isEmpty {
                    Text(L(
                        "Şu an ses çıkaran uygulama yok.",
                        "No app is playing audio right now."
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(mixer.apps) { app in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            appIcon(app.iconPath)
                            Text(app.name)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(app.playing ? Color.primary : Color.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
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
                Text(L(
                    "100% iken ses doğrudan gider. Altı veya üstü, o uygulamanın sesini seçilen kazançla çalar. Kayıt tutulmaz. Üst sınır 150%’dir.",
                    "At 100% the sound passes straight through. Below or above that, Hâl plays the app at the chosen gain. Nothing is recorded. The upper limit is 150%."
                ))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let level {
                    muteButton(muted: level.muted, helpOn: L("Sesi aç", "Unmute"), helpOff: L("Sessize al", "Mute"), action: level.toggleMute)
                }
            }
            deviceMenu(devices: devices, selection: selection, set: set)
            if let level {
                levelRow(value: level.value, range: level.range, muted: level.muted, set: level.set)
            }
        }
    }

    private func deviceMenu(
        devices: [MixerDevice],
        selection: AudioDeviceID,
        set: @escaping (AudioDeviceID) -> Void
    ) -> some View {
        let selectedName = devices.first { $0.id == selection }?.name ?? mixer.outputName
        return Menu {
            if devices.isEmpty {
                Button(selectedName.isEmpty ? L("Aygıt yok", "No device") : selectedName) {}
                    .disabled(true)
            }
            ForEach(devices) { device in
                Button {
                    set(device.id)
                } label: {
                    if device.id == selection {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedName.isEmpty ? L("Aygıt yok", "No device") : selectedName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .frame(width: 16, height: 16)
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

    private var groups: [UpdateOrigin] {
        var seen: [UpdateOrigin] = []
        for item in updates.items where !seen.contains(item.origin) {
            seen.append(item.origin)
        }
        return seen
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        toolButton(updates.scanning ? L("Denetleniyor…", "Checking…") : L("Denetle", "Check")) {
                            Task { await updates.scan() }
                        }
                        .disabled(updates.scanning || updates.applying)
                        if updates.items.contains(where: { $0.origin == .brew }) {
                            toolButton(L("Homebrew’u yükselt", "Upgrade Homebrew")) { brewAll = true }
                                .disabled(updates.applying || updates.scanning)
                        }
                        Spacer(minLength: 0)
                    }
                    Text(updates.summary.isEmpty ? L("Henüz denetlenmedi.", "Not checked yet.") : updates.summary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(groups, id: \.rawValue) { origin in
                    labeledBlock(origin.title) {
                        ForEach(updates.items.filter { $0.origin == origin }) { item in
                            toolRow(title: item.name, detail: versionLine(item)) {
                                toolButton(actionTitle(item)) { confirm(item) }
                                    .disabled(updates.applying || updates.scanning)
                            }
                        }
                    }
                }
                if !updates.log.isEmpty {
                    labeledBlock(L("Çıktı", "Output")) {
                        Text(updates.log)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
        }
        .alert(alertTitle, isPresented: Binding(
            get: { pending != nil || brewAll },
            set: { if !$0 { pending = nil; brewAll = false } }
        )) {
            Button(L("Vazgeç", "Cancel"), role: .cancel) { pending = nil; brewAll = false }
            Button(L("Sürdür", "Continue")) {
                if brewAll {
                    brewAll = false
                    Task { await updates.upgradeAllBrew() }
                } else if let pending {
                    let item = pending
                    self.pending = nil
                    Task { await updates.apply(item) }
                }
            }
        } message: {
            Text(alertMessage)
        }
    }

    /// Başlık zaten sürümü taşıyorsa (macOS 27.2 / 27.2) ikinci satır eklenmez.
    private func versionLine(_ item: AvailableUpdate) -> String? {
        let line = item.versions.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { return nil }
        if item.name.localizedCaseInsensitiveContains(line) { return nil }
        return line
    }

    private func confirm(_ item: AvailableUpdate) {
        if item.origin == .sparkle || (item.origin == .appStore && item.token == "store") {
            Task { await updates.apply(item) }
            return
        }
        pending = item
    }

    private func actionTitle(_ item: AvailableUpdate) -> String {
        switch item.origin {
        case .sparkle: return L("Aç", "Open")
        case .appStore where item.token == "store": return L("App Store", "App Store")
        default: return L("Kur", "Install")
        }
    }

    private var alertTitle: String {
        if brewAll { return L("Homebrew güncellemeleri kurulsun mu?", "Install Homebrew updates?") }
        return L("Güncelleme kurulsun mu?", "Install this update?")
    }

    private var alertMessage: String {
        if brewAll {
            return L(
                "Eski formüller ve cask’ler yükseltilir. Bazı uygulamalar kapanıp yeniden açılabilir.",
                "Outdated formulae and casks are upgraded. Some apps may quit and reopen."
            )
        }
        if pending?.origin == .system {
            return L(
                "macOS yazılım güncellemesi kurulur. Mac yeniden başlayabilir ve parola sorulabilir.",
                "A macOS software update is installed. The Mac may restart and ask for a password."
            )
        }
        if let pending {
            return Lf("%1$@ kurulur.", "%1$@ will be installed.", pending.name)
        }
        return ""
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
        VStack(alignment: .leading, spacing: 12) {
            Toggle(L("Mac normal enerji kurallarını izler", "Mac follows normal energy rules"), isOn: Binding(
                get: { followsNormalRules },
                set: { follow in
                    showClock = false
                    if follow {
                        arming = false
                        store.setAlwaysWake(false)
                    } else {
                        arming = true
                    }
                }
            ))
            .font(.system(size: 13))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(presets, id: \.id) { chip in
                    chipButton(chip.title, selected: selectedMinutes == chip.minutes) {
                        togglePreset(chip.minutes)
                    }
                }
                chipButton("∞", selected: store.settings.alwaysWake && store.settings.wakeIndefinite) {
                    toggleForever()
                }
                chipButton(L("Şu saate kadar…", "Until a time…"), selected: clockSelected) {
                    toggleClock()
                }
            }

            if showClock || clockSelected {
                DatePicker(
                    L("Saat", "Time"),
                    selection: $untilTime,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .onChange(of: untilTime) { _, value in
                    start(minutes: minutes(until: value))
                }
            }

            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup(L("Seçenekler", "Options")) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(L("Seçili uygulamalar öndeyken", "While selected apps are frontmost"), isOn: $store.settings.wakeWhileApps)
                    if store.settings.wakeWhileApps {
                        Text(store.settings.focusApps.joined(separator: ", "))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Button(L("Listeyi Odak’ta düzenle", "Edit the list in Focus"), action: onEditApps)
                            .controlSize(.small)
                    }
                    Toggle(L("Prizde veya harici ekrandayken", "While on power or an external display"), isOn: $store.settings.wakeWhilePowerOrDisplay)
                    Text(L(
                        "Süre seçilmediyse ve koşul da yoksa uyanık tutma sürekli kalır. Koşullardan biri tutunca da açık kalır.",
                        "With no duration and no condition, keep awake stays on. It also stays on while any chosen condition holds."
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)
            }
            .font(.system(size: 13))

            Divider()

            Toggle(L("Kapak kapalıyken devam et", "Continue while the lid is closed"), isOn: $store.settings.wakeWhileLidClosed)
                .disabled(WakeController.lidClosed() == nil)
                .font(.system(size: 13))
            Text(lidCaption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: store.settings.alwaysWake) { _, on in
            if on { arming = false }
        }
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
