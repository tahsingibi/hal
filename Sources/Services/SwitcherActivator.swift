import AppKit
import ApplicationServices

/// Seçilen pencereyi öne getirir: gerekirse küçültmeyi kaldırır, tam o pencereyi
/// uygulamanın ana ve odaklı penceresi yapar, pencere sunucusundan o pencereyle
/// öne gelmesini ister. `NSRunningApplication.activate` tek başına uygulamanın
/// kendi seçtiği pencereyi (çoğunlukla en öndekini) çıkarır; seçilen pencere
/// arkada kalırdı. Space değişimi ve bazı uygulamaların ana pencereyi bir tur
/// sonra yerleştirmesi eşzamansız olduğu için odak turu kısa aralıklarla
/// tekrarlanır; hedef odaklandığında ya da kullanıcı başka yere geçtiğinde durur.
@MainActor
enum SwitcherActivator {
    private static var generation: UInt64 = 0
    private static let retryDelays: [TimeInterval] = [0.08, 0.2, 0.45]

    static func activate(_ row: SwitcherWindow, sourcePID: pid_t?) {
        generation &+= 1
        let ticket = generation
        if row.pid == ProcessInfo.processInfo.processIdentifier {
            activateOwn(row)
            return
        }
        guard let app = NSRunningApplication(processIdentifier: row.pid), !app.isTerminated else { return }
        // Gizli olmayan bir uygulamada unhide bile tüm pencereleri öne getirir.
        if app.isHidden { app.unhide() }

        guard let windowID = row.windowID else {
            activateApp(app)
            // Penceresi olmayan uygulama: Dock'a tıklamak gibi yeni pencere açabilsin.
            if let url = app.bundleURL {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                configuration.addsToRecentItems = false
                configuration.promptsUserIfNeeded = false
                NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            }
            return
        }

        let element = row.element ?? SwitcherWindowServer.element(for: windowID, pid: row.pid)
        focus(element: element, pid: row.pid, frontmost: false)
        let fronted = SwitcherWindowServer.front(windowID, pid: row.pid, sendsKeyRecord: !isCompatibilityLayer(app))
        if !fronted { activateApp(app) }
        // Pencere sunucusu isteği bazen yalnızca süreci öne alır; AX yükseltmesi
        // pencereyi kesinleştirir. Aynı turu birkaç kez, durum değişene dek yinele.
        if let element { AXUIElementPerformAction(element, kAXRaiseAction as CFString) }

        for delay in retryDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard ticket == generation else { return }
                let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
                // Kullanıcı bu arada başka bir uygulamaya geçtiyse araya girme.
                if let front, front != row.pid, front != sourcePID { return }
                if front == row.pid, focusedWindowID(pid: row.pid) == windowID { return }
                let element = element ?? SwitcherWindowServer.element(for: windowID, pid: row.pid)
                focus(element: element, pid: row.pid, frontmost: true)
                if !SwitcherWindowServer.front(windowID, pid: row.pid, sendsKeyRecord: false) { activateApp(app) }
            }
        }
    }

    /// Pencereyi uygulamanın ana ve odaklı penceresi yapar ve yükseltir.
    private static func focus(element: AXUIElement?, pid: pid_t, frontmost: Bool) {
        guard let element, AXIsProcessTrusted() else { return }
        AXUIElementSetMessagingTimeout(element, 0.3)
        if SwitcherWindowQuery.value(element, kAXMinimizedAttribute) as? Bool == true {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        if frontmost {
            AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
        AXUIElementSetAttributeValue(app, kAXMainWindowAttribute as CFString, element)
        AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, element)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    private static func activateApp(_ app: NSRunningApplication) {
        if !app.activate(from: .current, options: []) { app.activate(options: []) }
    }

    static func focusedWindowID(pid: pid_t) -> CGWindowID? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let raw = SwitcherWindowQuery.value(app, kAXFocusedWindowAttribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return SwitcherWindowQuery.windowID(unsafeBitCast(raw, to: AXUIElement.self))
    }

    private static func activateOwn(_ row: SwitcherWindow) {
        NSApp.activate(ignoringOtherApps: true)
        guard let id = row.windowID, let window = NSApp.windows.first(where: { $0.windowNumber == Int(id) }) else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Wine/CrossOver gibi katmanlarda çalışan programlar anahtar pencere
    /// basışını gerçek tıklama sayabilir.
    private static func isCompatibilityLayer(_ app: NSRunningApplication) -> Bool {
        let path = (app.executableURL?.path ?? "").lowercased()
        let name = (app.localizedName ?? "").lowercased()
        return ["wine", "crossover", "wineloader", "wine64-preloader"].contains { path.contains($0) || name == $0 }
    }
}
