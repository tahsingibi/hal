import AppKit
import ApplicationServices
import ScreenCaptureKit

struct SwitcherWindow: Identifiable, @unchecked Sendable {
    var id: String
    var pid: pid_t
    var bundleID: String
    var appName: String
    var title: String
    var icon: NSImage
    var element: AXUIElement?
    var windowID: CGWindowID?
    var minimized: Bool
    var fullscreen: Bool
    var frame: CGRect?
    var order: Int
}
struct SwitcherAppSnapshot: @unchecked Sendable {
    var pid: pid_t
    var bundleID: String
    var name: String
    var icon: NSImage
    var hidden: Bool
}

enum SwitcherWindowQuery {
    typealias WindowIDFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32
    private static let idFunction: WindowIDFunction? = symbol("_AXUIElementGetWindow").map { unsafeBitCast($0, to: WindowIDFunction.self) }
    static func symbol(_ name: String) -> UnsafeMutableRawPointer? { dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) }
    static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }
    static func windowID(_ element: AXUIElement) -> UInt32? {
        var id: UInt32 = 0
        guard idFunction?(element, &id) == 0, id != 0 else { return nil }; return id
    }
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = value(element, kAXPositionAttribute), let s = value(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    /// Runs on one serial worker, with a per-app IPC timeout and total deadline.
    static func scan(apps: [SwitcherAppSnapshot], preferences: SwitcherPreferences, accessibility: Bool, screen: CGRect, cancelled: () -> Bool) -> [SwitcherWindow] {
        let records = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], 0) as? [[String: Any]] ?? []
        var order: [UInt32: Int] = [:], onScreen = Set<UInt32>(), auxiliary = Set<UInt32>()
        for (index, record) in records.enumerated() {
            guard let number = record[kCGWindowNumber as String] as? NSNumber else { continue }
            order[number.uint32Value] = index
            if (record[kCGWindowLayer as String] as? NSNumber)?.intValue != 0 { auxiliary.insert(number.uint32Value) }
            if record[kCGWindowIsOnscreen as String] as? Bool == true { onScreen.insert(number.uint32Value) }
        }
        let visibleSpaces = SwitcherSpaces.visible()
        var windows: [SwitcherWindow] = []
        for app in apps {
            if cancelled() { return [] }
            if preferences.excludedApps.contains(app.bundleID) { continue }
            let ax = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(ax, 0.12)
            var hasRealWindow = false
            if accessibility, let elements = value(ax, kAXWindowsAttribute) as? [AXUIElement] {
                let deadline = ProcessInfo.processInfo.systemUptime + 0.4
                for element in elements.prefix(80) {
                    if cancelled() { return [] }
                    if ProcessInfo.processInfo.systemUptime > deadline { break }
                    AXUIElementSetMessagingTimeout(element, 0.035)
                    let subrole = value(element, kAXSubroleAttribute) as? String
                    if let subrole, ![kAXStandardWindowSubrole, kAXDialogSubrole, kAXSystemDialogSubrole].contains(subrole) { continue }
                    let bounds = frame(element)
                    if let bounds, bounds.width < 80 || bounds.height < 50 { continue }
                    let title = value(element, kAXTitleAttribute) as? String ?? ""
                    if title.hasPrefix("Hâl · ") && title.contains(L("Pencere değiştirici", "Window switcher")) { continue }
                    let id = windowID(element)
                    if let id, auxiliary.contains(id) { continue }
                    // Non-visible helper windows with no title are not switch targets.
                    if title.isEmpty && (id == nil || !onScreen.contains(id!)) { continue }
                    hasRealWindow = true
                    let minimized = (value(element, kAXMinimizedAttribute) as? Bool ?? false) || app.hidden
                    let fullscreen = value(element, "AXFullScreen") as? Bool ?? false
                    if minimized && preferences.minimized == .hidden { continue }
                    if fullscreen && !preferences.showFullscreen { continue }
                    if preferences.currentScreenOnly, let bounds, !screen.intersects(bounds) { continue }
                    if preferences.currentSpaceOnly, let id {
                        if let memberships = SwitcherSpaces.spaces(id), !visibleSpaces.isEmpty {
                            if memberships.isDisjoint(with: visibleSpaces) { continue }
                        } else if !onScreen.contains(id) { continue }
                    }
                    let stableID = id.map { "w:\($0)" } ?? "ax:\(app.pid):\(CFHash(element))"
                    windows.append(SwitcherWindow(id: stableID, pid: app.pid, bundleID: app.bundleID, appName: app.name,
                        title: title.isEmpty ? app.name : title, icon: app.icon, element: element, windowID: id,
                        minimized: minimized, fullscreen: fullscreen, frame: bounds, order: id.flatMap { order[$0] } ?? 10000))
                }
            }
            let includeEmpty = !accessibility || preferences.windowless == .all || (preferences.windowless == .finder && app.bundleID == "com.apple.finder")
            if !hasRealWindow && includeEmpty && (!preferences.currentScreenOnly || !accessibility) {
                windows.append(SwitcherWindow(id: "app:\(app.pid)", pid: app.pid, bundleID: app.bundleID, appName: app.name,
                    title: app.name, icon: app.icon, element: nil, windowID: nil, minimized: app.hidden,
                    fullscreen: false, frame: nil, order: 20000))
            }
        }
        var seen = Set<String>()
        return windows.sorted { $0.order < $1.order }.filter { seen.insert($0.id).inserted }
    }
}

/// Read-only Space membership; no desktop is moved or reconfigured.
enum SwitcherSpaces {
    private typealias Connection = @convention(c) () -> UInt32
    private typealias CopySpaces = @convention(c) (UInt32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias CopyDisplays = @convention(c) (UInt32) -> Unmanaged<CFArray>?
    private static let connection = SwitcherWindowQuery.symbol("CGSMainConnectionID").map { unsafeBitCast($0, to: Connection.self)() } ?? 0
    private static let copySpaces = SwitcherWindowQuery.symbol("CGSCopySpacesForWindows").map { unsafeBitCast($0, to: CopySpaces.self) }
    private static let copyDisplays = SwitcherWindowQuery.symbol("CGSCopyManagedDisplaySpaces").map { unsafeBitCast($0, to: CopyDisplays.self) }
    static func spaces(_ id: UInt32) -> Set<UInt64>? {
        guard connection != 0, let array = copySpaces?(connection, 7, [NSNumber(value: id)] as CFArray)?.takeRetainedValue() as? [NSNumber] else { return nil }
        return Set(array.map(\.uint64Value))
    }
    static func visible() -> Set<UInt64> {
        guard connection != 0, let displays = copyDisplays?(connection)?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return Set(displays.compactMap { (($0["Current Space"] as? [String: Any])?["id64"] as? NSNumber)?.uint64Value })
    }
}

@MainActor
final class SwitcherThumbnails {
    private typealias Capture = @convention(c) (UInt32, UnsafeMutablePointer<UInt32>, Int, UInt32) -> Unmanaged<CFArray>?
    private typealias Connection = @convention(c) () -> UInt32
    private static let capture = SwitcherWindowQuery.symbol("CGSHWCaptureWindowList").map { unsafeBitCast($0, to: Capture.self) }
    private static let connection = SwitcherWindowQuery.symbol("CGSMainConnectionID").map { unsafeBitCast($0, to: Connection.self)() } ?? 0
    private let queue = DispatchQueue(label: "dev.sungur.Hal.thumbnails", qos: .userInitiated)
    private var cache: [UInt32: NSImage] = [:]
    private var order: [UInt32] = []
    private var task: Task<Void, Never>?
    private var generation = 0
    private var pressure: DispatchSourceMemoryPressure?
    init() {
        pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        pressure?.setEventHandler { [weak self] in self?.clear() }; pressure?.resume()
    }
    func existing(_ id: UInt32?) -> NSImage? { id.flatMap { cache[$0] } }
    func cancel() { generation += 1; task?.cancel(); task = nil }
    func clear() { cancel(); cache = [:]; order = [] }
    func refresh(_ rows: [SwitcherWindow], excluded: [String], onUpdate: @escaping (UInt32, NSImage) -> Void) {
        cancel()
        guard CGPreflightScreenCaptureAccess() else { clear(); return }
        let ticket = generation
        let targets = rows.filter { $0.windowID != nil && !excluded.contains($0.bundleID) }.prefix(48)
        task = Task {
            var shareable: SCShareableContent?
            for row in targets {
                guard ticket == generation, !Task.isCancelled, let id = row.windowID else { return }
                if let cached = cache[id] { onUpdate(id, cached) }
                let connection = Self.connection, capture = Self.capture
                let image: CGImage? = await withCheckedContinuation { continuation in
                    queue.async {
                        var windowID = id
                        var result: CGImage?
                        if connection != 0, let list = capture?(connection, &windowID, 1, (1 << 8) | (1 << 11))?.takeRetainedValue(), CFArrayGetCount(list) > 0,
                           let raw = CFArrayGetValueAtIndex(list, 0) {
                            let object = unsafeBitCast(raw, to: CFTypeRef.self)
                            if CFGetTypeID(object) == CGImage.typeID {
                                let source = unsafeBitCast(object, to: CGImage.self)
                                result = Self.bitmap(source)
                            }
                        }
                        continuation.resume(returning: result)
                    }
                }
                guard ticket == generation, !Task.isCancelled else { return }
                var final = image
                if final == nil && !row.minimized {
                    if shareable == nil { shareable = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) }
                    if let window = shareable?.windows.first(where: { $0.windowID == id }) {
                        let config = SCStreamConfiguration()
                        let ratio = window.frame.height / max(1, window.frame.width)
                        config.width = 640; config.height = max(1, Int(640 * ratio)); config.showsCursor = false
                        if let captured = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config) {
                            final = Self.bitmap(captured)
                        }
                    }
                }
                guard ticket == generation, !Task.isCancelled else { return }
                if let final, final.width > 1, final.height > 1 {
                    let thumbnail = NSImage(cgImage: final, size: NSSize(width: final.width, height: final.height))
                    cache[id] = thumbnail; order.removeAll { $0 == id }; order.append(id)
                    while order.count > 48 { cache.removeValue(forKey: order.removeFirst()) }
                    onUpdate(id, thumbnail)
                }
            }
        }
    }
    nonisolated private static func bitmap(_ image: CGImage) -> CGImage? {
        let scale = min(1, 640 / CGFloat(max(image.width, image.height)))
        let w = max(1, Int(CGFloat(image.width) * scale)), h = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high; context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }
}
