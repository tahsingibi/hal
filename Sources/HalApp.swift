import SwiftUI
import AppKit

@main
struct HalApp: App {
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
    private var terminationSignal: DispatchSourceSignal?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NotificationService.shared.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGTERM, SIG_IGN)
        let terminationSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        terminationSignal.setEventHandler { NSApp.terminate(nil) }
        terminationSignal.resume()
        self.terminationSignal = terminationSignal
        NSApp.setActivationPolicy(.accessory)
        store.applyPersistedModes()
        statusBar = StatusBarController(store: store)
        statusBar?.showWelcomeIfNeeded()
        UpdateController.start()
        SystemUpdateService.shared.startBackgroundChecks()
    }

    /// Opening the .app again should offer a window even though Hâl has no Dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBar?.openSettings(tab: .features)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        WindowSwitcher.shared.shutdown()
        DisplayController.shared.shutdown()
        VolumeMixer.shared.shutdown()
        WakeController.shared.stop()
        DeviceModes.shared.shutdown()
        FocusTracker.shared.stop()
        // Bekleyen günlük kaydı diske yaz; son dakikaların odak süresi kaybolmasın.
        DailyLog.shared.flush()
    }
}
