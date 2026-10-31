import AppKit
import SwiftUI

/// The sections of the menu bar panel, one icon tab each.
enum PanelSection: String, CaseIterable, Identifiable {
    case personal, quotas, calendar, downloader, keepAwake, displays, sound, power, tools, controls

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: return L("Kişisel", "Personal")
        case .quotas: return L("Kotalar", "Quotas")
        case .calendar: return L("Takvim", "Calendar")
        case .downloader: return L("Video indirici", "Video downloader")
        case .keepAwake: return L("Uyanık tut", "Keep awake")
        case .displays: return L("Ekranlar", "Displays")
        case .sound: return L("Ses", "Sound")
        case .power: return L("Güç", "Power")
        case .tools: return L("Araçlar", "Tools")
        case .controls: return L("Kontroller", "Controls")
        }
    }

    var symbol: String {
        switch self {
        case .personal: return "person.crop.circle"
        case .quotas: return "gauge.with.dots.needle.67percent"
        case .calendar: return "calendar"
        case .downloader: return "arrow.down.circle"
        case .keepAwake: return "moon.zzz.fill"
        case .displays: return "display.2"
        case .sound: return "speaker.wave.2"
        case .power: return "bolt.fill"
        case .tools: return "wrench.and.screwdriver.fill"
        case .controls: return "switch.2"
        }
    }

    /// Modules shown inside the Personal section.
    static let personalModules: [ModuleKind] = [.today, .focus, .prayer, .fitness, .money]
}

/// The menu bar panel: the app's name, a row of section icons that always
/// fits, the selected section in a card, and Settings / Keep awake / Quit.
struct HalPanelView: View {
    @EnvironmentObject private var store: AppStore
    var onSettings: (SettingsTab) -> Void
    @AppStorage("hal.panel.section") private var sectionRaw = PanelSection.personal.rawValue
    @AppStorage("hal.panel.personal") private var personalRaw = ModuleKind.today.rawValue
    @AppStorage(PanelLayout.orderKey) private var orderRaw = ""
    @AppStorage(PanelLayout.hiddenKey) private var hiddenRaw = ""
    @State private var tool: PanelTool?
    @State private var contentHeight: CGFloat = 0

    static let width: CGFloat = 332
    private static let contentWidth: CGFloat = 308

    private var sections: [PanelSection] {
        let hidden = PanelLayout.hidden(hiddenRaw)
        return PanelLayout.order(orderRaw).filter { section in
            guard !hidden.contains(section) else { return false }
            switch section {
            case .personal: return !personalModules.isEmpty
            case .quotas: return store.settings.isModuleEnabled(.usage)
            case .calendar: return store.settings.isModuleEnabled(.calendar)
            default: return true
            }
        }
    }

    private var section: PanelSection {
        let wanted = PanelSection(rawValue: sectionRaw) ?? .personal
        return sections.contains(wanted) ? wanted : (sections.first ?? .keepAwake)
    }

    private var personalModules: [ModuleKind] {
        PanelSection.personalModules.filter(store.settings.isModuleEnabled)
    }

    private var personalModule: ModuleKind {
        let wanted = ModuleKind(rawValue: personalRaw) ?? .today
        return personalModules.contains(wanted) ? wanted : (personalModules.first ?? .today)
    }

    private var maxContentHeight: CGFloat {
        max(220, MenuBarLayout.popoverMaxContentHeight - 150)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hâl")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .accessibilityAddTraits(.isHeader)
            tabBar
            header
            ScrollView {
                content
                    .frame(width: Self.contentWidth, alignment: .topLeading)
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: PanelContentHeightKey.self, value: geo.size.height)
                    })
            }
            .scrollIndicators(.never)
            .id(section)
            .frame(width: Self.contentWidth,
                   height: min(max(contentHeight, 80), maxContentHeight))
            .onPreferenceChange(PanelContentHeightKey.self) { contentHeight = $0 }
            footer
        }
        .padding(12)
        .frame(width: Self.width, alignment: .topLeading)
        .environment(\.locale, Language.locale)
        .environment(\.toolPresentation, .menu)
        .onChange(of: store.selection) { _, target in follow(target) }
        .onChange(of: store.boardToken) { _, _ in tool = nil }
    }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(sections) { item in
                let active = item == section
                Button {
                    sectionRaw = item.rawValue
                    tool = nil
                } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 13.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(active ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .help(item.title)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7))
    }

    private var header: some View {
        HStack(spacing: 6) {
            if section == .tools, tool != nil {
                Button { tool = nil } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Text((tool?.title ?? section.title).uppercased(with: Language.locale))
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Spacer()
            Button { onSettings(settingsDestination) } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L("Bölüm ayarları", "Section settings"))
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch section {
        case .personal:
            card {
                VStack(alignment: .leading, spacing: 12) {
                    if personalModules.count > 1 {
                        PersonalTabBar(items: personalModules.map {
                            PersonalTabBar<ModuleKind>.Item(id: $0, title: $0.title, symbol: $0.symbol)
                        }, selection: Binding(get: { personalModule }, set: { personalRaw = $0.rawValue }))
                    }
                    DetailPopoverView(embeddedModule: personalModule, onSettings: onSettings,
                                      onNavigate: navigate)
                        .id(personalModule)
                }
            }
        case .quotas:
            card {
                DetailPopoverView(embeddedModule: .usage, onSettings: onSettings, onNavigate: navigate)
            }
        case .calendar:
            card {
                DetailPopoverView(embeddedModule: .calendar, onSettings: onSettings, onNavigate: navigate)
            }
        case .downloader:
            card { DownloaderForm(showsFolder: true) }
        case .keepAwake:
            KeepAwakePanel { onSettings(.wake) }
        case .displays:
            DisplayQuickPanel { onSettings(.displays) }
        case .sound:
            VolumeMixerPanel()
        case .power:
            card(bottomPadding: 4) { PowerPanel() }
        case .tools:
            if let tool {
                toolDetail(tool)
            } else {
                ToolsList(open: { tool = $0 })
            }
        case .controls:
            card { ControlsPanel() }
        }
    }

    private func card<Content: View>(bottomPadding: CGFloat = 12, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, bottomPadding)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7))
    }

    @ViewBuilder
    private func toolDetail(_ tool: PanelTool) -> some View {
        switch tool {
        case .homebrew: HomebrewPanel()
        case .updates: UpdatesPanel()
        case .ports: PortsPanel(showsTitle: false)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            footerButton(L("Ayarlar", "Settings"), symbol: "gearshape") { onSettings(settingsDestination) }
            footerButton(L("Uyanık tut", "Keep awake"),
                         symbol: store.settings.alwaysWake ? "sun.max.fill" : "sun.max",
                         highlighted: store.settings.alwaysWake) {
                store.setAlwaysWake(!store.settings.alwaysWake)
            }
            footerButton(L("Çık", "Quit"), symbol: "power") { NSApp.terminate(nil) }
        }
    }

    private func footerButton(_ title: String, symbol: String, highlighted: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(highlighted ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(highlighted ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.09), lineWidth: 0.8))
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(highlighted ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    // MARK: - Navigation

    private var settingsDestination: SettingsTab {
        switch section {
        case .personal:
            switch personalModule {
            case .focus: return .focus
            case .prayer: return .worship
            case .fitness: return .fitness
            case .money: return .money
            default: return .features
            }
        case .quotas: return .quota
        case .calendar: return .calendar
        case .downloader: return .downloader
        case .keepAwake: return .wake
        case .displays: return .displays
        case .sound: return .mixer
        case .power: return .general
        case .tools:
            switch tool {
            case .homebrew: return .homebrew
            case .updates: return .updates
            case .ports: return .ports
            case nil: return .features
            }
        case .controls: return .switcher
        }
    }

    /// A row on Today, a notification or a menu bar icon names a module page;
    /// the panel follows it to the section that shows that module.
    private func follow(_ target: DetailTarget?) {
        guard let target else { return }
        switch target.module {
        case .usage: sectionRaw = PanelSection.quotas.rawValue
        case .calendar: sectionRaw = PanelSection.calendar.rawValue
        default:
            sectionRaw = PanelSection.personal.rawValue
            personalRaw = target.module.rawValue
        }
        tool = nil
    }

    private func navigate(_ id: String) {
        guard let target = DetailTarget(id: id) else { return }
        store.select(target)
        follow(target)
    }
}

enum PanelTool: Hashable {
    case homebrew, updates, ports

    var title: String {
        switch self {
        case .homebrew: return "Homebrew"
        case .updates: return L("Güncellemeler", "Updates")
        case .ports: return L("Portlar", "Ports")
        }
    }
}

private struct PanelContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Tools

/// Homebrew, updates and ports open in place; cleaning mode switches here.
private struct ToolsList: View {
    @EnvironmentObject private var store: AppStore
    var open: (PanelTool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("shippingbox", "Homebrew", L("Paketleri ara, kur ve güncelle.", "Search, install and upgrade packages.")) { open(.homebrew) }
            row("arrow.triangle.2.circlepath", L("Güncellemeler", "Updates"),
                L("macOS, Homebrew ve uygulama güncellemeleri.", "macOS, Homebrew and app updates.")) { open(.updates) }
            row("network", L("Portlar", "Ports"), L("Dinleyen portlar ve süreçleri.", "Listening ports and their processes.")) { open(.ports) }
            HStack(spacing: 10) {
                Image(systemName: "bubbles.and.sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.settings.resolvedCleaningMenuTitle).font(.system(size: 13, weight: .medium))
                    Text(L("Klavyeyi temizlemek için kilitler.", "Locks the keyboard so you can wipe it."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Toggle("", isOn: Binding(get: { store.cleaningMode }, set: { store.setCleaningMode($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7))
            if let message = store.cleaningMessage, store.cleaningMode || !DeviceModes.shared.accessibilityTrusted {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ symbol: String, _ title: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Controls

private struct ControlsPanel: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toggle("rectangle.on.rectangle", L("Pencere değiştirici", "Window switcher"),
                   L("⌥⇥ ile uygulamalar ve pencereler arasında geç.", "Switch apps and windows with ⌥⇥."),
                   isOn: $store.settings.switcher.enabled)
            Divider().opacity(0.5)
            toggle("scope", L("Odak ölçümü", "Focus tracking"),
                   L("Çalışma uygulamalarında geçen süreyi say.", "Count time spent in work apps."),
                   isOn: Binding(get: { store.settings.isModuleEnabled(.focus) },
                                 set: { store.setModule(.focus, enabled: $0) }))
        }
    }

    private func toggle(_ symbol: String, _ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

// MARK: - Power

struct PowerPanel: View {
    @ObservedObject private var power = PowerService.shared

    var body: some View {
        PowerOverview(reading: power.reading, history: power.systemHistory, chargeHistory: power.chargeHistory)
            .onAppear { power.beginObserving() }
            .onDisappear { power.endObserving() }
    }
}

struct PowerOverview: View {
    let reading: PowerReading
    let history: [Double]
    let chargeHistory: [Double]
    @State private var showsDetails = false

    var body: some View {
        VStack(spacing: 0) {
            if reading.hasBattery {
                VStack(spacing: 3) {
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.fill").frame(width: 16).foregroundStyle(.secondary)
                        Text(L("Pil", "Battery")).foregroundStyle(.secondary)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.08))
                                Capsule().fill(chargeColor)
                                    .frame(width: geo.size.width * Double(reading.chargePercent ?? 0) / 100)
                            }
                        }
                        .frame(height: 5)
                        Text(reading.chargePercent.map { "\($0)%" } ?? "—")
                            .fontWeight(.semibold).monospacedDigit()
                    }
                    .font(.system(size: 12))
                    .frame(height: 22)
                    PowerSparkline(values: chargeHistory.isEmpty ? reading.chargePercent.map { [Double($0)] } ?? [] : chargeHistory,
                                   tint: chargeColor, ceiling: 100,
                                   caption: reading.chargePercent.map { "\($0)%" } ?? "—")
                        .frame(height: 24)
                }
                .padding(.bottom, 7)
                divider
                row("thermometer.medium", L("Pil sıcaklığı", "Battery temperature"),
                    reading.temperatureCelsius.map { String(format: "%.0f °C", $0) } ?? "—")
                    .help(reading.temperatureCelsius == nil ? L("Sistem bildirmiyor", "Not reported by system") : "")
                divider
            }
            if let watts = systemWatts {
                VStack(spacing: 0) {
                    row("bolt.fill", L("Sistem", "System"), String(format: "%.0f W", watts), tint: .orange)
                    PowerSparkline(values: history.isEmpty ? [watts] : history,
                                   tint: .orange, ceiling: ceiling,
                                   caption: String(format: "%.0f W", ceiling))
                        .frame(height: 27)
                }
                .padding(.bottom, 7)
                divider
            }
            if reading.onAdapter {
                row("powerplug.fill", L("Adaptör", "Adapter"),
                    reading.adapterInputWatts.map { String(format: "%.0f W", $0) } ?? "—",
                    detail: reading.adapterWatts.map { Lf("%1$d W maks.", "%1$d W max.", $0) }, tint: .blue)
                if reading.hasBattery { divider }
            }
            if reading.hasBattery {
                Button { showsDetails = true } label: {
                    row("heart.fill", L("Pil sağlığı", "Battery health"),
                        reading.healthPercent.map { "\($0)%" } ?? "—",
                        detail: reading.cycleCount.map { Lf("%1$d döngü", "%1$d cycles", $0) }, tint: .pink)
                }
                .buttonStyle(.plain)
                .help(L("Pil ayrıntıları", "Battery details"))
                .popover(isPresented: $showsDetails, arrowEdge: .trailing) { details }
            }
            if !reading.hasBattery && systemWatts == nil {
                Text(L("Bu Mac güç bilgisi vermiyor.", "This Mac doesn’t report power readings."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private var divider: some View { Divider().opacity(0.5) }

    private func row(_ symbol: String, _ title: String, _ value: String,
                     detail: String? = nil, tint: Color = .secondary) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(tint).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12))
                if let detail { Text(detail).font(.system(size: 10.5)) }
            }
            .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).font(.system(size: 13, weight: .semibold)).monospacedDigit()
        }
        .frame(height: 40)
        .contentShape(Rectangle())
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Pil ayrıntıları", "Battery details")).font(.system(size: 12, weight: .semibold))
            if let full = reading.fullChargeCapacity {
                detailRow(L("Tam şarj kapasitesi", "Full charge capacity"), "\(full) mAh")
            }
            if let design = reading.designCapacity {
                detailRow(L("Tasarım kapasitesi", "Design capacity"), "\(design) mAh")
            }
            if let watts = reading.batteryWatts {
                detailRow(reading.isCharging ? L("Şarj oluyor", "Charging")
                          : reading.onAdapter ? L("Bekliyor", "Idle") : L("Pilde", "On battery"),
                          String(format: "%.0f W", abs(watts)))
            }
            if let minutes = reading.minutesRemaining {
                detailRow(reading.isCharging ? L("Dolmasına", "Until full") : L("Kalan pil süresi", "Time remaining"),
                          Lf("%1$dsa %2$02ddk", "%1$dh %2$02dm", minutes / 60, minutes % 60))
            }
        }
        .padding(14).frame(width: 260)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: 11))
    }

    private var systemWatts: Double? {
        reading.systemWatts ?? reading.batteryWatts.flatMap { $0 < -0.5 ? -$0 : nil }
    }
    private var ceiling: Double { max(25, (max(history.max() ?? 0, systemWatts ?? 0) / 25).rounded(.up) * 25) }
    private var chargeColor: Color {
        (reading.chargePercent ?? 100) <= 10 ? .red : (reading.chargePercent ?? 100) <= 20 ? .orange : .green
    }
}

private struct PowerSparkline: View {
    let values: [Double]
    let tint: Color
    let ceiling: Double
    let caption: String

    var body: some View {
        GeometryReader { geo in
            let samples = values.count == 1 ? [values[0], values[0]] : values
            let points = samples.enumerated().map { index, value in
                CGPoint(x: geo.size.width * CGFloat(index) / CGFloat(max(samples.count - 1, 1)),
                        y: 7 + (geo.size.height - 7) * (1 - CGFloat(min(max(value / ceiling, 0), 1))))
            }
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 7))
                    path.addLine(to: CGPoint(x: geo.size.width, y: 7))
                }
                .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 0.7, dash: [2, 3]))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geo.size.height))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
                Text(caption).font(.system(size: 8.5, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 3)
                    .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
            }
        }
        .accessibilityHidden(true)
    }
}

extension Notification.Name {
    static let halOpenSettings = Notification.Name("hal.openSettings")
    static let halShowWelcome = Notification.Name("hal.showWelcome")
}

// MARK: - Layout

/// The order and visibility of the panel's tabs, kept as comma-joined ids.
enum PanelLayout {
    static let orderKey = "hal.panel.order"
    static let hiddenKey = "hal.panel.hidden"

    static func order(_ raw: String) -> [PanelSection] {
        var seen = Set<PanelSection>()
        let saved = raw.split(separator: ",").compactMap { PanelSection(rawValue: String($0)) }
        return (saved + PanelSection.allCases).filter { seen.insert($0).inserted }
    }

    static func hidden(_ raw: String) -> Set<PanelSection> {
        Set(raw.split(separator: ",").compactMap { PanelSection(rawValue: String($0)) })
    }

    static func encode(_ sections: [PanelSection]) -> String {
        sections.map(\.rawValue).joined(separator: ",")
    }
}

/// Settings rows that order the panel's tabs and show or hide each one.
struct PanelLayoutEditor: View {
    @AppStorage(PanelLayout.orderKey) private var orderRaw = ""
    @AppStorage(PanelLayout.hiddenKey) private var hiddenRaw = ""

    var body: some View {
        let order = PanelLayout.order(orderRaw)
        let hidden = PanelLayout.hidden(hiddenRaw)
        ForEach(Array(order.enumerated()), id: \.element) { index, section in
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .frame(width: 20)
                    .foregroundStyle(hidden.contains(section) ? Color.secondary : Color.accentColor)
                Text(section.title)
                    .foregroundStyle(hidden.contains(section) ? .secondary : .primary)
                Spacer()
                Button { move(section, by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    .help(L("Yukarı taşı", "Move up"))
                Button { move(section, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless)
                    .disabled(index == order.count - 1)
                    .help(L("Aşağı taşı", "Move down"))
                Toggle("", isOn: Binding(
                    get: { !hidden.contains(section) },
                    set: { shown in setShown(section, shown) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!hidden.contains(section) && order.count - hidden.count <= 1)
            }
        }
    }

    private func move(_ section: PanelSection, by offset: Int) {
        var order = PanelLayout.order(orderRaw)
        guard let index = order.firstIndex(of: section), order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
        orderRaw = PanelLayout.encode(order)
    }

    private func setShown(_ section: PanelSection, _ shown: Bool) {
        var hidden = PanelLayout.hidden(hiddenRaw)
        if shown { hidden.remove(section) } else { hidden.insert(section) }
        hiddenRaw = PanelLayout.encode(PanelSection.allCases.filter(hidden.contains))
    }
}
