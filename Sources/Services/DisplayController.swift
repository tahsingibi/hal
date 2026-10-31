import AppKit
import CoreGraphics
import Darwin

struct DisplayBrightness: Identifiable {
    var id: CGDirectDisplayID
    var name: String
    var builtIn: Bool
    var hardware: Bool
    var value: Double
}

/// Hardware control is discovered at runtime; other displays use a click-through
/// dimming panel. Dimming panels are transient and never restored on app launch.
@MainActor
final class DisplayController: ObservableObject {
    static let shared = DisplayController()
    @Published private(set) var displays: [DisplayBrightness] = []
    @Published private(set) var enabled = false
    @Published var error: String?
    private var overlays: [CGDirectDisplayID: NSPanel] = [:]
    private var originals: [CGDirectDisplayID: Float] = [:]
    private var lastWritten: [CGDirectDisplayID: Float] = [:]
    private var observer: Any?
    private var wakeObserver: Any?
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
    private typealias CanChange = @convention(c) (UInt32) -> Bool
    private let handle: UnsafeMutableRawPointer?
    private let readBrightness: GetBrightness?
    private let writeBrightness: SetBrightness?
    private let canChangeBrightness: CanChange?
    /// External monitors driven over DDC/CI, and their last known level.
    private var ddc: [CGDirectDisplayID: DDCControl] = [:]
    private var ddcDisplays: Set<CGDirectDisplayID> = []
    private var ddcLevels: [CGDirectDisplayID: Double] = [:]

    private init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        self.handle = handle
        readBrightness = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetBrightness.self) }
        writeBrightness = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetBrightness.self) }
        canChangeBrightness = handle.flatMap { dlsym($0, "DisplayServicesCanChangeBrightness") }.map { unsafeBitCast($0, to: CanChange.self) }
    }

    /// Whether the system itself can set this display's brightness. Monitors
    /// the system cannot drive still answer a read with a made-up value, which
    /// is how an external display used to show 50% at launch.
    private func systemControls(_ id: CGDirectDisplayID) -> Bool {
        guard writeBrightness != nil else { return false }
        if let canChangeBrightness { return canChangeBrightness(id) }
        return CGDisplayIsBuiltin(id) != 0
    }

    func apply(enabled: Bool) {
        self.enabled = enabled
        if enabled {
            if observer == nil {
                observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.refresh() }
                }
                wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.resetAll() }
                }
            }
            refresh()
        } else {
            resetAll()
            if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
            if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver); self.wakeObserver = nil }
            displays = []
        }
    }

    func refresh() {
        guard enabled else { return }
        let active = Set(NSScreen.screens.map(\.displayID))
        for id in Array(overlays.keys) where !active.contains(id) { overlays.removeValue(forKey: id)?.orderOut(nil) }
        for id in Array(originals.keys) where !active.contains(id) { originals.removeValue(forKey: id); lastWritten.removeValue(forKey: id) }
        let externals = NSScreen.screens.map(\.displayID).filter { !systemControls($0) }
        if Set(externals) != ddcDisplays {
            ddcDisplays = Set(externals)
            ddc = DDCControl.controls(forExternalDisplays: externals)
            ddcLevels = ddcLevels.filter { ddc[$0.key] != nil }
        }
        displays = NSScreen.screens.map { screen in
            let id = screen.displayID
            let name = screen.localizedName
            let builtIn = CGDisplayIsBuiltin(id) != 0
            if systemControls(id) {
                var brightness: Float = 1
                let read = readBrightness?(id, &brightness) == 0
                return DisplayBrightness(id: id, name: name, builtIn: builtIn, hardware: true,
                                         value: read ? Double(brightness) : 1)
            }
            if ddc[id] != nil {
                if ddcLevels[id] == nil { readDDC(id) }
                return DisplayBrightness(id: id, name: name, builtIn: builtIn, hardware: true, value: ddcLevels[id] ?? 1)
            }
            return DisplayBrightness(id: id, name: name, builtIn: builtIn, hardware: false,
                                     value: 1 - Double(overlays[id]?.alphaValue ?? 0))
        }
    }

    /// The monitor answers in tens of milliseconds, so the reading happens off
    /// the main thread and the slider follows once it arrives.
    private func readDDC(_ id: CGDirectDisplayID) {
        guard let control = ddc[id] else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let level = control.readBrightness()
            Task { @MainActor [weak self] in
                guard let self, let level else { return }
                self.ddcLevels[id] = level
                if let index = self.displays.firstIndex(where: { $0.id == id }) { self.displays[index].value = level }
            }
        }
    }

    static func clampedLevel(_ raw: Double, hardware: Bool) -> Double {
        guard raw.isFinite else { return 1 }
        return min(1, max(hardware ? 0.05 : 0.2, raw))
    }

    func set(_ id: CGDirectDisplayID, value: Double) {
        guard enabled, let index = displays.firstIndex(where: { $0.id == id }) else { return }
        let display = displays[index]
        let level = Self.clampedLevel(value, hardware: display.hardware)
        error = nil
        if let control = ddc[id] {
            control.setBrightness(level)
            ddcLevels[id] = level
        } else if display.hardware {
            if originals[id] == nil {
                var current: Float = Float(display.value)
                if readBrightness?(id, &current) == 0 { originals[id] = current }
            }
            guard writeBrightness?(id, Float(level)) == 0 else {
                error = L("Bu ekranın parlaklığı değiştirilemedi. Ekran ayarlarından tekrar dene.", "Could not change this display’s brightness. Try Display Settings.")
                return
            }
            lastWritten[id] = Float(level)
        } else {
            guard let screen = NSScreen.matching(displayID: id) else { return }
            let overlay = overlays[id] ?? makeOverlay(screen)
            overlays[id] = overlay
            overlay.setFrame(screen.frame, display: false)
            overlay.alphaValue = 1 - level
            if level >= 0.999 { overlay.orderOut(nil) } else { overlay.orderFrontRegardless() }
        }
        displays[index].value = level
    }

    func reset(_ id: CGDirectDisplayID) {
        overlays.removeValue(forKey: id)?.orderOut(nil)
        if let original = originals.removeValue(forKey: id), let last = lastWritten.removeValue(forKey: id) {
            var current: Float = 0
            // Do not undo a change made since then with brightness keys or another app.
            if readBrightness?(id, &current) == 0, abs(current - last) < 0.025 { _ = writeBrightness?(id, original) }
        }
        refresh()
    }

    func resetAll() {
        for panel in overlays.values { panel.orderOut(nil) }
        overlays = [:]
        for id in Array(originals.keys) { reset(id) }
        refresh()
    }

    func shutdown() {
        apply(enabled: false)
    }

    private func makeOverlay(_ screen: NSScreen) -> NSPanel {
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .black; panel.isOpaque = false; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}
