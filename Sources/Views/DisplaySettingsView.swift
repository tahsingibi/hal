import AppKit
import SwiftUI

struct DisplaySettingsView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var controller = DisplayController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
                SettingsCard {
                    SettingsToggleRow(title: L("Ekran parlaklığı kontrolü", "Display brightness control"), detail: L("Her ekranı ayrı ayarla. Değişiklikler uygulama kapanınca veya Mac uyuyunca geri alınır.", "Adjust each display separately. Changes are restored when Hâl quits or your Mac sleeps."), symbol: "sun.max", isOn: $store.settings.displayControlsEnabled)
                }
                if store.settings.displayControlsEnabled {
                    if controller.displays.isEmpty {
                        ToolEmptyState(symbol: "display", title: L("Ekran bulunamadı", "No displays found"), detail: L("Bağlantıları kontrol edip listeyi yenile.", "Check connections and refresh the list."))
                    }
                    ForEach(controller.displays) { display in
                        SettingsCard {
                            HStack(spacing: 10) {
                                Image(systemName: display.builtIn ? "laptopcomputer" : "display").font(.system(size: 23)).foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(display.name).font(.system(size: 14, weight: .semibold))
                                    ToolBadge(title: display.hardware ? L("Donanım parlaklığı", "Hardware brightness") : L("Yazılımsal karartma", "Software dimming"))
                                }
                                Spacer()
                                Text(String(format: "%.0f%%", display.value * 100)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            HStack(spacing: 12) {
                                Image(systemName: "sun.min").foregroundStyle(.secondary)
                                Slider(value: Binding(get: { display.value }, set: { controller.set(display.id, value: $0) }), in: display.hardware ? 0.05...1 : 0.2...1)
                                    .accessibilityLabel(Lf("%1$@ parlaklığı", "%1$@ brightness", display.name))
                                Image(systemName: "sun.max").foregroundStyle(.secondary)
                            }
                            HStack {
                                if !display.hardware {
                                    Text(L("Ekranın kendi parlaklığı desteklenmiyor. Görüntü karartılır; ekranın güç tüketimi değişmez.", "Hardware brightness is unavailable. The image is dimmed; display power use is unchanged."))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(L("Geri al", "Restore")) { controller.reset(display.id) }.controlSize(.small)
                            }
                        }
                    }
                    if let error = controller.error { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                    HStack {
                        Button(L("Ekranları yenile", "Refresh displays")) { controller.refresh() }
                        Spacer()
                        Button(L("Tümünü geri al", "Restore all")) { controller.resetAll() }
                    }
                }
                SettingsCard {
                    HStack {
                        Label(L("macOS ekran ayarları", "macOS Display Settings"), systemImage: "display")
                        Spacer()
                        Button(L("Aç", "Open")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") { NSWorkspace.shared.open(url) }
                        }
                    }
                }
        }
        .onAppear { controller.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in controller.refresh() }
    }
}

struct DisplayQuickPanel: View {
    @ObservedObject private var controller = DisplayController.shared
    var onSettings: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !controller.enabled {
                    Text(L("Ekran kontrolünü Ayarlar’dan etkinleştir.", "Enable display control in Settings.")).font(.callout).foregroundStyle(.secondary)
                }
                ForEach(controller.displays) { display in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(display.name, systemImage: display.builtIn ? "laptopcomputer" : "display").lineLimit(1)
                            Spacer()
                            Text(String(format: "%.0f%%", display.value * 100)).monospacedDigit()
                        }.font(.system(size: 12, weight: .medium))
                        Slider(value: Binding(get: { display.value }, set: { controller.set(display.id, value: $0) }), in: display.hardware ? 0.05...1 : 0.2...1)
                            .accessibilityLabel(display.name)
                        if !display.hardware { Text(L("Yazılımsal karartma", "Software dimming")).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                HStack {
                    Button(L("Ayarlar", "Settings"), action: onSettings)
                    Spacer()
                    if controller.enabled { Button(L("Geri al", "Restore")) { controller.resetAll() } }
                }.controlSize(.small)
            }
        }.onAppear { controller.refresh() }
    }
}
