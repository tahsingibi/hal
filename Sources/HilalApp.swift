import SwiftUI
import AppKit

@main
struct HilalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(delegate.store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = AppStore()
    var statusBar: StatusBarController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NotificationService.shared.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store.applyPersistedModes()
        statusBar = StatusBarController(store: store)
    }

    func applicationWillTerminate(_ notification: Notification) {
        DeviceModes.shared.shutdown()
        FocusTracker.shared.stop()
        // Bekleyen günlük kaydı diske yaz; son dakikaların odak süresi kaybolmasın.
        DailyLog.shared.flush()
    }
}
