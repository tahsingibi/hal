import AppKit
import SwiftUI

extension SettingsTab {
    var subtitle: String {
        switch self {
        case .general: return L("Dil, başlangıç ve kişisel tercihler.", "Language, startup and personal preferences.")
        case .features: return L("Yalnızca kullandığın özellikleri aç.", "Enable only the features you use.")
        case .permissions: return L("Hangi özellik hangi erişimi kullanıyor?", "See which features use each permission.")
        case .appearance: return L("Panelini ve menü çubuğunu düzenle.", "Arrange your panel and menu bar.")
        case .notifications: return L("Neyin, ne zaman haber vereceğini seç.", "Choose what to hear about and when.")
        case .switcher: return L("Pencereler arasında klavyeyle geçiş yap.", "Switch between windows with your keyboard.")
        case .displays: return L("Her ekranın parlaklığını ayrı ayarla.", "Adjust the brightness of each display.")
        case .wake: return L("Mac’ini gerektiği kadar uyanık tut.", "Keep your Mac awake for as long as you need.")
        case .focus: return L("Çalışma süreni ve günlük hedefini takip et.", "Track work time and your daily goal.")
        case .quota: return L("Claude, Codex ve Grok limitlerini izle.", "Follow your Claude, Codex and Grok limits.")
        case .worship: return L("Vakitler, konum ve günlük namaz takibi.", "Prayer times, location and daily tracking.")
        case .calendar: return L("Yaklaşan toplantılarını tek bakışta gör.", "See your upcoming meetings at a glance.")
        case .fitness: return L("Antrenman, ilaç, su ve beslenme takibi.", "Workouts, medication, water and nutrition.")
        case .money: return L("Aboneliklerini ve yaklaşan ödemelerini izle.", "Track subscriptions and upcoming payments.")
        case .downloader: return L("Bağlantılardan video veya ses indir.", "Download video or audio from links.")
        case .ports: return L("Ağ portlarını kullanan işlemleri bul.", "Find processes listening on network ports.")
        case .homebrew: return L("Paketlerini ve güncellemelerini yönet.", "Manage packages and their updates.")
        case .mixer: return L("Uygulamaların sesini ayrı ayrı ayarla.", "Adjust volume separately for each app.")
        case .updates: return L("Mac’indeki uygulamaların güncellemelerini denetle.", "Check updates for apps on your Mac.")
        case .about: return L("Sürüm, veri kaynakları ve tanılama.", "Version, data sources and diagnostics.")
        case .changelog: return L("Hâl’deki son değişiklikler.", "The latest changes in Hâl.")
        }
    }

    var module: ModuleKind? {
        switch self {
        case .focus: return .focus
        case .quota: return .usage
        case .worship: return .prayer
        case .calendar: return .calendar
        case .fitness: return .fitness
        case .money: return .money
        default: return nil
        }
    }
}

struct FeatureHubView: View {
    @EnvironmentObject private var store: AppStore
    var onSettings: (SettingsTab) -> Void
    @State private var collapsedSections: Set<Int> = []
    private let sections: [[SettingsTab]] = [[.focus, .quota], [.worship, .calendar, .fitness, .money]]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(L("Özellikler", "Features")).font(.headline)
                        Spacer()
                        Button(L("İzinleri incele", "Review permissions")) { onSettings(.permissions) }
                    }
                    Text(L("Kapattığın modüller panelden kaldırılır; veri kaynakları ve bildirimleri durur. Ayarları saklanır.", "Disabled modules disappear from the panel and stop their data sources and notifications. Their settings are kept."))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    HStack {
                        Text(Lf("%1$d / %2$d modül açık", "%1$d of %2$d modules enabled", store.modules.count, ModuleKind.dashboardCases.count))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Tümünü aç", "Enable all")) { store.applyModules(Set(ModuleKind.dashboardCases)) }
                            .disabled(store.modules.count == ModuleKind.dashboardCases.count)
                        Button(L("Yalnızca Bugün", "Only Today")) { store.applyModules([.today]) }
                            .disabled(store.modules.count == 1)
                    }
                }
                .hubCard()

                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Hazır bir grupla başla", "Start with a preset")).font(.headline)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 10) { presets }
                        VStack(spacing: 10) { presets }
                    }
                    Text(L("Hazır gruplar açık modülleri değiştirir. Mevcut kayıtların ve tercihlerin korunur.", "Presets change the enabled modules. Your records and preferences are preserved."))
                        .font(.caption).foregroundStyle(.secondary)
                }

                ForEach(Array(sections.enumerated()), id: \.offset) { index, tabs in
                    DisclosureGroup(isExpanded: Binding(get: { !collapsedSections.contains(index) }, set: { expanded in
                        if expanded { collapsedSections.remove(index) } else { collapsedSections.insert(index) }
                    })) {
                        VStack(spacing: 0) {
                            ForEach(tabs) { tab in
                                featureRow(tab)
                                if tab != tabs.last { Divider().padding(.leading, 52) }
                            }
                        }.hubCard().padding(.top, 10)
                    } label: {
                        Text(index == 0 ? L("Çalışma", "Work") : L("Kişisel", "Personal")).font(.headline)
                    }
                }
                SettingsCard(title: L("Pencereler ve ekranlar", "Windows and displays"), symbol: "display") {
                    SettingsToggleRow(title: SettingsTab.switcher.title, detail: SettingsTab.switcher.subtitle, symbol: SettingsTab.switcher.symbol, isOn: $store.settings.switcher.enabled)
                    Button(L("Pencere değiştiriciyi yapılandır", "Configure window switcher")) { onSettings(.switcher) }.controlSize(.small)
                    Divider()
                    SettingsToggleRow(title: L("Ekran parlaklığı", "Display brightness"), detail: SettingsTab.displays.subtitle, symbol: SettingsTab.displays.symbol, isOn: $store.settings.displayControlsEnabled)
                    Button(L("Ekranları yapılandır", "Configure displays")) { onSettings(.displays) }.controlSize(.small)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Her zaman elinin altında", "Always within reach")).font(.headline)
                    Text(L("Ses, uyanık tutma, indirici, portlar, Homebrew ve güncellemeler Araçlar ve Çalışma bölümlerinde. Yalnızca açtığında yüklenirler.", "Sound, keep awake, downloader, ports, Homebrew and updates are in the Work and Tools sections. Their panels load when opened."))
                        .font(.callout).foregroundStyle(.secondary)
                    Button(L("Panel düzenini değiştir", "Customize panel layout")) { onSettings(.appearance) }
                }.hubCard()
            }
            .padding(24)
            .frame(maxWidth: 850, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var presets: some View {
        preset(L("Çalışma", "Work"), symbol: "laptopcomputer", detail: L("Odak, kotalar ve takvim.", "Focus, quotas and calendar."), modules: [.today, .focus, .usage, .calendar])
        preset(L("Günlük yaşam", "Daily life"), symbol: "sun.max", detail: L("İbadet, sağlık ve ödemeler.", "Prayer, health and payments."), modules: [.today, .prayer, .fitness, .money])
        preset(L("Sade", "Minimal"), symbol: "leaf", detail: L("Bugün panosu ve odak.", "Today board and focus."), modules: [.today, .focus])
    }

    private func preset(_ title: String, symbol: String, detail: String, modules: Set<ModuleKind>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(detail).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
            Button(L("Uygula", "Apply")) { store.applyModules(modules) }
                .disabled(Set(store.modules) == modules)
        }
        .hubCard()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func featureRow(_ tab: SettingsTab) -> some View {
        let enabled = tab.module.map { store.settings.isModuleEnabled($0) } ?? true
        return HStack(spacing: 12) {
            Image(systemName: tab.symbol)
                .font(.system(size: 18)).foregroundStyle(enabled ? Color.accentColor : Color.secondary)
                .frame(width: 38, height: 38)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(tab.title).font(.system(size: 13, weight: .semibold))
                    Text(enabled ? L("Açık", "Enabled") : L("Kapalı", "Disabled"))
                        .font(.system(size: 10)).foregroundStyle(enabled ? Color.accentColor : Color.secondary)
                }
                Text(tab.subtitle).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button { onSettings(tab) } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(.borderless).help(L("Yapılandır", "Configure"))
            Toggle(tab.title, isOn: Binding(
                get: { enabled },
                set: { if let module = tab.module { store.setModule(module, enabled: $0) } }
            ))
            .labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.vertical, 10)
    }
}

struct PermissionsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var calendarGranted = CalendarService.shared.access == .granted
    @State private var accessibilityGranted = DeviceModes.shared.accessibilityTrusted
    var onSettings: (SettingsTab) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("İzinler isteğe bağlıdır. Erişim yalnızca ilgili özelliğin düğmesine bastığında istenir.", "Permissions are optional. Access is requested only when you use the relevant feature’s button."))
                    .font(.callout).foregroundStyle(.secondary)
                permission("calendar", title: L("Takvim", "Calendar"),
                           detail: L("Yaklaşan olayları okur. Takvim modülü kullanır.", "Reads upcoming events. Used by the Calendar module."),
                           status: calendarGranted ? L("İzin verildi", "Granted") : L("Bağlı değil", "Not connected"),
                           unused: calendarGranted && !store.settings.isModuleEnabled(.calendar), tab: .calendar)
                permission("bell", title: L("Bildirimler", "Notifications"),
                           detail: L("Vakit, kota, ilaç ve gün özeti hatırlatmaları için kullanılır.", "Used for prayer, quota, medication and daily summary reminders."),
                           status: L("Bildirim ayarları", "Notification settings"), unused: false, tab: .notifications)
                permission("hand.raised", title: L("Erişilebilirlik", "Accessibility"),
                           detail: L("Temizlik modunda girişleri engellemek ve pencere değiştiricide pencereleri listeleyip öne getirmek için kullanılır.", "Used to block input during Cleaning mode and to list and focus individual windows in the switcher."),
                           status: accessibilityGranted ? L("İzin verildi", "Granted") : L("İzin verilmedi", "Not granted"),
                           unused: false, tab: .general)
                permission("rectangle.inset.filled", title: L("Ekran kaydı", "Screen Recording"),
                           detail: L("Pencere değiştiricinin görsel önizlemeleri için kullanılır. Görüntüler diske kaydedilmez.", "Used for window switcher previews. Images are never saved to disk."),
                           status: WindowSwitcher.shared.captureGranted ? L("İzin verildi", "Granted") : L("İzin verilmedi", "Not granted"),
                           unused: false, tab: .switcher)
                permission("speaker.wave.2", title: L("Ses yakalama", "Audio capture"),
                           detail: L("Uygulama bazında ses ayarı için kullanılır. Ses kaydı saklanmaz. İzin, mikserde yakalamayı başlattığında istenir.", "Used for per-app volume control. Audio recordings are never saved. Access is requested when you start capture in the mixer."),
                           status: L("Ses mikseri", "Volume mixer"), unused: false, tab: .mixer)
                Label(L("Konum elle seçilir. Namaz vakitleri için sistem konum izni gerekmez.", "Location is chosen manually. Prayer times do not require system location access."), systemImage: "location.slash")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }.padding(24).frame(maxWidth: 850, alignment: .leading).frame(maxWidth: .infinity)
        }
        .onAppear(perform: reload)
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
    }

    private func reload() {
        calendarGranted = CalendarService.shared.access == .granted
        accessibilityGranted = DeviceModes.shared.accessibilityTrusted
    }

    private func permission(_ symbol: String, title: String, detail: String, status: String, unused: Bool, tab: SettingsTab) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(.tint).frame(width: 30)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(status).font(.caption).foregroundStyle(.secondary)
                if unused {
                    Label(L("Bu izni kullanan modül kapalı. Sistem Ayarları’ndan izni kaldırabilirsin.", "The module using this permission is off. You can revoke access in System Settings."), systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button(L("Yapılandır", "Configure")) { onSettings(tab) }
                    Button(L("Sistem Ayarları", "System Settings")) {
                        let pane = tab == .calendar ? "Privacy_Calendars" : tab == .notifications ? nil : tab == .mixer ? "Privacy_AudioCapture" : tab == .switcher ? "Privacy_ScreenCapture" : "Privacy_Accessibility"
                        let url = pane.map { "x-apple.systempreferences:com.apple.preference.security?\($0)" }
                            ?? "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
                        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
                    }
                }.controlSize(.small)
            }
            Spacer(minLength: 0)
        }.hubCard()
    }
}

private extension View {
    func hubCard() -> some View {
        padding(16)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.primary.opacity(0.06)))
    }
}
