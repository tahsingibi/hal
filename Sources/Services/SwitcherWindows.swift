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
    /// Bir uygulamanın Erişilebilirlik yanıtındaki tek pencere.
    struct AXReading {
        var element: AXUIElement
        var windowID: CGWindowID?
        var title: String
        var minimized: Bool
        var fullscreen: Bool
        var frame: CGRect?
        var userFacing: Bool
    }

    /// Bir uygulamanın Erişilebilirlik yanıtı. `answered` false ise uygulama
    /// meşgul ya da kapanıyordur; yanıtı bir pencerenin varlığına ya da
    /// yokluğuna tanıklık edemez.
    struct AXReport {
        var answered = false
        var windows: [AXReading] = []
        var timedOut: Set<CGWindowID> = []
        var byID: [CGWindowID: AXReading] {
            Dictionary(windows.compactMap { reading in reading.windowID.map { ($0, reading) } },
                       uniquingKeysWith: { first, _ in first })
        }
    }

    /// Pencere listesi pencere sunucusundan kurulur; Erişilebilirlik tanık olarak
    /// kullanılır. AX başka Space'teki pencereleri yayımlamaz, pencere sunucusu
    /// ise kapatılmış sekmelerin hayalet yüzeylerini bir süre tutar; ikisi
    /// birbirinin açığını kapatır. AX okumaları uygulamalar arasında paralel ve
    /// toplam bir süre sınırıyla yapılır, böylece meşgul bir uygulama listeyi bekletmez.
    static func scan(apps: [SwitcherAppSnapshot], preferences: SwitcherPreferences, accessibility: Bool,
                     screen: CGRect, cancelled: @escaping () -> Bool) -> [SwitcherWindow] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let eligible = apps.filter { !preferences.excludedApps.contains($0.bundleID) }
        let appsByPID = Dictionary(eligible.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let allIDs = Set(raw.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
        let normalLevel = Set(raw.compactMap { info -> CGWindowID? in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 else { return nil }
            return (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        })

        // Kullanım geçmişini güncel tut: olmayan pencereler düşer, hiç odak
        // almamış pencereler önden arkaya sırayla en sona yerleşir.
        let front = SwitcherHistory.frontToBack()
        var appOrder: [pid_t] = []
        for entry in front where !appOrder.contains(entry.pid) { appOrder.append(entry.pid) }
        SwitcherHistory.shared.reconcile(existing: allIDs, frontToBack: front.map(\.id),
                                         running: Set(apps.map(\.pid)), appOrder: appOrder)

        let reports = accessibility
            ? readAccessibility(eligible.filter { $0.pid != ownPID }, normalLevel: normalLevel, cancelled: cancelled)
            : [:]
        if cancelled() { return [] }

        let visibleSpaces = SwitcherWindowServer.visibleSpaces()
        let fullscreenSpaces = SwitcherWindowServer.fullscreenSpaces()
        var spaceCache: [CGWindowID: Set<UInt64>] = [:]
        var spaceMisses = Set<CGWindowID>()
        func spaces(_ id: CGWindowID) -> Set<UInt64>? {
            if let cached = spaceCache[id] { return cached }
            if spaceMisses.contains(id) { return nil }
            guard let value = SwitcherWindowServer.spaces(of: id) else { spaceMisses.insert(id); return nil }
            spaceCache[id] = value
            return value
        }
        func onHiddenSpace(_ id: CGWindowID) -> Bool {
            guard !visibleSpaces.isEmpty, let set = spaces(id), !set.isEmpty else { return false }
            return set.isDisjoint(with: visibleSpaces)
        }
        func onFullscreenSpace(_ id: CGWindowID) -> Bool {
            guard !fullscreenSpaces.isEmpty, let set = spaces(id) else { return false }
            return !set.isDisjoint(with: fullscreenSpaces)
        }

        var windows: [SwitcherWindow] = []
        var seen = Set<CGWindowID>()
        /// Penceresi bilerek dışarıda bırakılan uygulamalar "penceresiz" sayılmaz.
        var withheld = Set<pid_t>()

        func admit(id: CGWindowID, app: SwitcherAppSnapshot, title: String, element: AXUIElement?,
                   minimized: Bool, fullscreen: Bool, frame: CGRect?, order: Int) {
            if minimized && preferences.minimized == .hidden { withheld.insert(app.pid); return }
            if fullscreen && !preferences.showFullscreen { withheld.insert(app.pid); return }
            if preferences.currentScreenOnly, !minimized, let frame, !screen.intersects(frame) {
                withheld.insert(app.pid); return
            }
            if preferences.currentSpaceOnly, onHiddenSpace(id), !(fullscreen && preferences.showFullscreen) {
                withheld.insert(app.pid); return
            }
            seen.insert(id)
            windows.append(SwitcherWindow(id: "w:\(id)", pid: app.pid, bundleID: app.bundleID, appName: app.name,
                                          title: title.isEmpty ? app.name : title, icon: app.icon, element: element,
                                          windowID: id, minimized: minimized, fullscreen: fullscreen,
                                          frame: frame, order: order))
        }

        for (index, info) in raw.enumerated() {
            if index % 32 == 0, cancelled() { return [] }
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value, !seen.contains(id),
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let app = appsByPID[pid] else { continue }
            let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }
            let onScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            let serverTitle = info[kCGWindowName as String] as? String ?? ""

            // Hâl'in kendi pencereleri: AX kendi sürecine ana iş parçacığı
            // dışından sorulmaz; görünen ve başlığı olan pencereler yeter.
            if pid == ownPID {
                guard onScreen, !serverTitle.isEmpty,
                      !serverTitle.contains(L("Pencere değiştirici", "Window switcher")),
                      let bounds, bounds.width >= 200, bounds.height >= 120 else { continue }
                admit(id: id, app: app, title: serverTitle, element: nil, minimized: false,
                      fullscreen: false, frame: bounds, order: index)
                continue
            }

            let report = reports[pid]
            let reading = report?.byID[id]
            let minimized = (reading?.minimized ?? false) || app.hidden
            if let bounds, !minimized, bounds.width < 80 || bounds.height < 50 { continue }
            if let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha == 0, !minimized { continue }

            let keep: Bool
            if let reading {
                keep = reading.userFacing
            } else if let report, report.answered, !report.timedOut.contains(id) {
                // Uygulama yanıt verdi ama bu pencereyi saymadı. Yalnızca AX'in
                // göremediği yerdeki canlı pencereler kalır: gizli uygulamanın
                // pencereleri ya da başka Space'te sıraya alınmış pencereler.
                if SwitcherWindowServer.isExcludedFromCycle(id) {
                    keep = false
                } else if app.hidden {
                    keep = !serverTitle.isEmpty || (spaces(id)?.isEmpty == false)
                } else if onHiddenSpace(id) {
                    keep = SwitcherWindowServer.isOrderedIn(id) ?? report.windows.isEmpty
                } else {
                    keep = false
                }
            } else {
                // Yanıt yok (izin yok, meşgul ya da kapanıyor): pencere sunucusu
                // karar verir. Ekranda olmayan ve hiçbir Space'e ait olmayan yüzey kalıntıdır.
                if SwitcherWindowServer.isExcludedFromCycle(id) {
                    keep = false
                } else if !onScreen, SwitcherWindowServer.canResolveSpaces, spaces(id)?.isEmpty ?? true {
                    keep = false
                } else {
                    keep = onScreen || !serverTitle.isEmpty || onHiddenSpace(id)
                }
            }
            guard keep else { continue }
            let title = serverTitle.isEmpty ? (reading?.title ?? "") : serverTitle
            // Başlıksız, ekranda olmayan ve AX'in tanımadığı yüzeyler çoğunlukla görünmez yardımcılardır.
            if title.isEmpty && !onScreen && reading == nil && !onHiddenSpace(id) && !app.hidden { continue }
            let fullscreen = (reading?.fullscreen ?? false) || onFullscreenSpace(id)
            admit(id: id, app: app, title: title, element: reading?.element, minimized: minimized,
                  fullscreen: fullscreen, frame: bounds ?? reading?.frame, order: index)
        }

        // Pencere sunucusunun listesinde olmayan ama AX'in tanıdığı pencereler
        // (çoğunlukla başka Space'teki tam ekran pencereler).
        for (pid, report) in reports {
            guard let app = appsByPID[pid] else { continue }
            for reading in report.windows where reading.userFacing {
                guard let id = reading.windowID, !seen.contains(id), !allIDs.contains(id) else { continue }
                admit(id: id, app: app, title: reading.title, element: reading.element,
                      minimized: reading.minimized || app.hidden, fullscreen: reading.fullscreen,
                      frame: reading.frame, order: 5_000)
            }
        }

        // Penceresiz uygulamalar: yalnızca yanıt verip hiç kullanıcı penceresi
        // tanımlamayan uygulamalar. Meşgul bir uygulamaya "penceresi yok" denmez.
        let hasWindow = Set(windows.map(\.pid))
        for app in eligible where app.pid != ownPID && !hasWindow.contains(app.pid) && !withheld.contains(app.pid) {
            let wanted = preferences.windowless == .all
                || (preferences.windowless == .finder && app.bundleID == "com.apple.finder")
            if accessibility {
                guard wanted, !preferences.currentScreenOnly,
                      let report = reports[app.pid], report.answered, report.timedOut.isEmpty,
                      !report.windows.contains(where: \.userFacing) else { continue }
            }
            windows.append(SwitcherWindow(id: "app:\(app.pid)", pid: app.pid, bundleID: app.bundleID, appName: app.name,
                                          title: app.name, icon: app.icon, element: nil, windowID: nil,
                                          minimized: app.hidden, fullscreen: false, frame: nil, order: 20_000))
        }
        return windows
    }

    /// Uygulamaları paralel okur. Her uygulamanın kendi kısa zaman aşımı ve
    /// hepsinin ortak bir son tarihi vardır.
    private static func readAccessibility(_ apps: [SwitcherAppSnapshot], normalLevel: Set<CGWindowID>,
                                          cancelled: @escaping () -> Bool) -> [pid_t: AXReport] {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.45
        let lock = NSLock()
        var reports: [pid_t: AXReport] = [:]
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            let app = apps[index]
            guard !cancelled() else { return }
            let report = readApp(app, normalLevel: normalLevel, deadline: deadline, cancelled: cancelled)
            lock.lock(); reports[app.pid] = report; lock.unlock()
        }
        return reports
    }

    private static func readApp(_ app: SwitcherAppSnapshot, normalLevel: Set<CGWindowID>,
                                deadline: TimeInterval, cancelled: () -> Bool) -> AXReport {
        var report = AXReport()
        func remaining() -> Float { Float(max(0, deadline - ProcessInfo.processInfo.systemUptime)) }
        guard remaining() > 0.01 else { return report }
        let ax = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(ax, min(0.15, remaining()))
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &value)
        switch status {
        case .success:
            report.answered = true
        case .noValue, .attributeUnsupported:
            report.answered = true
            return report
        default:
            return report
        }
        let elements = (value as? [AXUIElement]) ?? []
        let attributes = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXMinimizedAttribute,
                          "AXFullScreen", kAXPositionAttribute, kAXSizeAttribute] as CFArray
        for element in elements.prefix(80) {
            if cancelled() { return report }
            let time = remaining()
            let id = windowID(element)
            guard time > 0.005 else {
                if let id { report.timedOut.insert(id) }
                continue
            }
            AXUIElementSetMessagingTimeout(element, min(0.06, time))
            var batch: CFArray?
            let read = AXUIElementCopyMultipleAttributeValues(element, attributes, AXCopyMultipleAttributeOptions(rawValue: 0), &batch)
            guard read == .success, let values = batch as? [AnyObject], values.count == 7 else {
                if let id { report.timedOut.insert(id) }
                continue
            }
            func text(_ index: Int) -> String? { values[index] as? String }
            func flag(_ index: Int) -> Bool { (values[index] as? NSNumber)?.boolValue ?? false }
            var frame: CGRect?
            let position = values[5], size = values[6]
            if CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
                var point = CGPoint.zero, extent = CGSize.zero
                if AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
                   AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &extent) {
                    frame = CGRect(origin: point, size: extent)
                }
            }
            let title = text(2) ?? ""
            let minimized = flag(3), fullscreen = flag(4)
            let userFacing = isUserFacing(element: element, role: text(0), subrole: text(1), minimized: minimized,
                                          fullscreen: fullscreen, frame: frame, windowID: id,
                                          title: title, normalLevel: normalLevel)
            report.windows.append(AXReading(element: element, windowID: id, title: title, minimized: minimized,
                                            fullscreen: fullscreen, frame: frame, userFacing: userFacing))
        }
        return report
    }

    /// Kullanıcının geçiş yapacağı gerçek pencere mi? Standart ve tam ekran
    /// pencereler evet, küçültülmüş pencereler evet. Diyaloglar yalnızca normal
    /// düzeyde ve çalışan bir küçültme düğmesi varsa (gizli uygulamanın
    /// pencereleri diyalog görünür). Tanımsız yüzeyler yalnızca normal düzeyde,
    /// döngüden çıkarılmamış, başlıklı ve yeterince büyükse.
    private static func isUserFacing(element: AXUIElement, role: String?, subrole: String?, minimized: Bool,
                                     fullscreen: Bool, frame: CGRect?, windowID: CGWindowID?, title: String,
                                     normalLevel: Set<CGWindowID>) -> Bool {
        if fullscreen { return true }
        if minimized && role == kAXWindowRole as String { return true }
        guard let subrole else { return role == kAXWindowRole as String }
        switch subrole {
        case kAXStandardWindowSubrole, "AXFullScreenWindow":
            return true
        case kAXDialogSubrole:
            guard let windowID, normalLevel.contains(windowID),
                  let raw = value(element, kAXMinimizeButtonAttribute),
                  CFGetTypeID(raw) == AXUIElementGetTypeID() else { return false }
            return value(unsafeBitCast(raw, to: AXUIElement.self), kAXEnabledAttribute) as? Bool ?? false
        case "AXUnknown":
            guard let windowID, normalLevel.contains(windowID), !title.isEmpty,
                  let frame, frame.width >= 200, frame.height >= 150 else { return false }
            return !SwitcherWindowServer.isExcludedFromCycle(windowID)
        default:
            return false
        }
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
