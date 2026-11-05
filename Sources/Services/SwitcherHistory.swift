import AppKit
import ApplicationServices

/// Hangi pencerenin ve uygulamanın en son kullanıldığını tutar. Değiştiricinin
/// sırası bu geçmiş kadar iyidir.
///
/// Uygulama etkinleşmesi tek başına yetmez: aynı uygulamanın iki penceresi
/// arasında geçişte sistem hiçbir şey yayınlamaz, fareyle yapılan geçişleri
/// de değiştiricinin kendi seçimleri bilmez. Bu yüzden öndeki uygulamanın
/// odaklanan penceresi Erişilebilirlik gözlemcisiyle izlenir. AX çağrıları
/// yanıt vermeyen bir uygulamada uzun süre bekleyebileceği için hepsi kendi
/// iş parçacığında ve kısa zaman aşımıyla çalışır; ana iş parçacığı hiç beklemez.
final class SwitcherHistory: @unchecked Sendable {
    static let shared = SwitcherHistory()
    private static let limit = 400

    private let lock = NSLock()
    /// En son kullanılan önce.
    private var windows: [CGWindowID] = []
    private var apps: [pid_t] = []
    private var seeded = false

    private var thread: Thread?
    private var loop: CFRunLoop?
    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var observedApp: AXUIElement?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var running = false

    // MARK: Yaşam döngüsü

    func start() {
        lock.lock()
        guard !running else { lock.unlock(); return }
        running = true
        lock.unlock()
        seedIfNeeded()
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.appActivated(app.processIdentifier)
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.forget(app.processIdentifier)
            }
        ]
        let worker = Thread { [weak self] in self?.runWatcher() }
        worker.name = "Hâl switcher focus"
        worker.qualityOfService = .utility
        thread = worker
        worker.start()
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier { appActivated(front) }
    }

    func stop() {
        lock.lock()
        running = false
        windows = []; apps = []; seeded = false
        let loop = self.loop
        lock.unlock()
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceTokens = []
        if let loop {
            CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) { [weak self] in
                self?.detachObserver()
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
            CFRunLoopWakeUp(loop)
        }
        thread = nil
    }

    // MARK: Sorgular

    /// Pencerelerin sırası: kullanım geçmişi; geçmişte olmayanlar en sonda
    /// pencere sunucusunun önden arkaya sırasıyla.
    func windowRanks() -> [CGWindowID: Int] {
        lock.lock(); defer { lock.unlock() }
        var ranks: [CGWindowID: Int] = [:]
        for (index, id) in windows.enumerated() where ranks[id] == nil { ranks[id] = index }
        return ranks
    }

    func appRanks() -> [pid_t: Int] {
        lock.lock(); defer { lock.unlock() }
        var ranks: [pid_t: Int] = [:]
        for (index, pid) in apps.enumerated() where ranks[pid] == nil { ranks[pid] = index }
        return ranks
    }

    // MARK: Güncellemeler

    /// Değiştiricinin yaptığı geçiş. Pencere sunucusu ve AX bunu bir iki kare
    /// geç bildirir; hızlı bir ikinci basış ise tam o an doğru yeri bulmalı.
    /// Gelinen pencere ikinci sıraya geçer, böylece tekrar basış geri döndürür.
    func noteSwitch(to target: CGWindowID?, pid: pid_t, from previous: CGWindowID?) {
        lock.lock(); defer { lock.unlock() }
        if let previous, previous != target { move(previous, toFront: &windows) }
        if let target { move(target, toFront: &windows) }
        move(pid, toFront: &apps)
    }

    /// Artık olmayan pencereleri ve uygulamaları düşürür; hiç odak almamış
    /// pencereleri, bilinenlerden daha eski sayarak önden arkaya sırayla sona ekler.
    func reconcile(existing: Set<CGWindowID>, frontToBack: [CGWindowID], running: Set<pid_t>, appOrder: [pid_t]) {
        lock.lock(); defer { lock.unlock() }
        windows.removeAll { !existing.contains($0) }
        var known = Set(windows)
        for id in frontToBack where existing.contains(id) && known.insert(id).inserted { windows.append(id) }
        apps.removeAll { !running.contains($0) }
        var knownApps = Set(apps)
        for pid in appOrder where running.contains(pid) && knownApps.insert(pid).inserted { apps.append(pid) }
        if windows.count > Self.limit { windows.removeLast(windows.count - Self.limit) }
    }

    /// İlk geçmiş: uygulama çalışmadan önce ne kullanıldığının tek tanığı
    /// pencere sunucusunun önden arkaya sırasıdır.
    private func seedIfNeeded() {
        lock.lock()
        let needed = !seeded
        seeded = true
        lock.unlock()
        guard needed else { return }
        let order = Self.frontToBack()
        lock.lock()
        for entry in order {
            if !windows.contains(entry.id) { windows.append(entry.id) }
            if !apps.contains(entry.pid) { apps.append(entry.pid) }
        }
        lock.unlock()
    }

    /// Ekrandaki sıradan (katman 0) pencereler, öndeki önce.
    static func frontToBack() -> [(id: CGWindowID, pid: pid_t)] {
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return raw.compactMap { info in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { return nil }
            return (id, pid)
        }
    }

    private func forget(_ pid: pid_t) {
        lock.lock(); apps.removeAll { $0 == pid }; lock.unlock()
    }

    private func appActivated(_ pid: pid_t) {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        lock.lock()
        move(pid, toFront: &apps)
        let loop = self.loop
        lock.unlock()
        guard let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) { [weak self] in
            self?.observe(pid)
        }
        CFRunLoopWakeUp(loop)
    }

    private func promote(window id: CGWindowID, pid: pid_t) {
        lock.lock(); defer { lock.unlock() }
        guard running else { return }
        move(id, toFront: &windows)
        move(pid, toFront: &apps)
    }

    private func move<T: Equatable>(_ value: T, toFront list: inout [T]) {
        list.removeAll { $0 == value }
        list.insert(value, at: 0)
    }

    // MARK: Gözlemci iş parçacığı

    private func runWatcher() {
        lock.lock(); loop = CFRunLoopGetCurrent(); let front = NSWorkspace.shared.frontmostApplication?.processIdentifier; lock.unlock()
        if let front { observe(front) }
        // Kaynak yokken çalışma döngüsü hemen döner; boş bir zamanlayıcı onu ayakta tutar.
        let keepAlive = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + 1e9, 1e9, 0, 0) { _ in }
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), keepAlive, .defaultMode)
        CFRunLoopRun()
        CFRunLoopRemoveTimer(CFRunLoopGetCurrent(), keepAlive, .defaultMode)
        lock.lock(); loop = nil; lock.unlock()
    }

    /// Yalnızca öndeki uygulama izlenir: etkinleşme bildirimi olmadan pencere
    /// odağı yalnızca klavyesi zaten o uygulamada olan uygulama içinde değişir.
    private func observe(_ pid: pid_t) {
        guard AXIsProcessTrusted(), pid != observedPID else {
            if pid == observedPID { readFocus() }
            return
        }
        detachObserver()
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, _, context in
            guard let context else { return }
            let history = Unmanaged<SwitcherHistory>.fromOpaque(context).takeUnretainedValue()
            history.focusChanged(element)
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
            AXObserverAddNotification(created, app, name as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        observedPID = pid
        observedApp = app
        readFocus()
    }

    private func detachObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedApp = nil
        observedPID = 0
    }

    private func readFocus() {
        guard let observedApp,
              let raw = SwitcherWindowQuery.value(observedApp, kAXFocusedWindowAttribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return }
        focusChanged(unsafeBitCast(raw, to: AXUIElement.self))
    }

    private func focusChanged(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, 0.25)
        var window = element
        if SwitcherWindowQuery.value(element, kAXRoleAttribute) as? String != kAXWindowRole as String,
           let raw = SwitcherWindowQuery.value(element, kAXWindowAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() {
            window = unsafeBitCast(raw, to: AXUIElement.self)
        }
        guard let id = SwitcherWindowQuery.windowID(window) else { return }
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        promote(window: id, pid: pid)
    }
}
