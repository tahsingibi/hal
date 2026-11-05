import AppKit
import ApplicationServices
import Carbon
import SwiftUI

@MainActor
final class WindowSwitcher: ObservableObject {
    static let shared = WindowSwitcher()
    @Published private(set) var windows: [SwitcherWindow] = []
    @Published private(set) var previews: [UInt32: NSImage] = [:]
    @Published private(set) var preferences = SwitcherPreferences()
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var captureGranted = CGPreflightScreenCaptureAccess()
    @Published private(set) var shortcutError: String?
    @Published private(set) var inputLive = false
    @Published private(set) var loading = false
    @Published var query = ""
    @Published var selectedID: String?
    @Published private(set) var searchPinned = false
    @Published private(set) var columns = 1
    @Published private(set) var scope = SwitcherScope.apps
    @Published private(set) var sessionActive = false
    private var sessionWindows: [SwitcherWindow] = []
    private var sourcePID: pid_t?
    private var scopePID: pid_t?
    private var activeKey: SwitcherKey?
    /// Oturum açıldığında öndeki pencere; geçişte ikinci sıraya alınır ki
    /// kısayola tekrar basmak geri döndürsün.
    private var sourceWindowID: CGWindowID?
    private var generation = 0
    private var stepsWhileLoading = 0
    private var pendingCommit = false
    private var showTask: DispatchWorkItem?
    private var panel: NSPanel?
    private var localKeys: Any?
    private var outsideClicks: Any?
    private var hotKeys: [EventHotKeyRef] = []
    private var hotKeyHandler: EventHandlerRef?
    private var recording = false
    private let enumeration = DispatchQueue(label: "dev.sungur.Hal.switcher.windows", qos: .userInitiated)
    private let cancellation = SwitcherCancellation()
    private let thumbnails = SwitcherThumbnails()
    private let nativeKeys = SwitcherSystemKeys()
    private var secureInputTimer: Timer?
    private var fallbackReleaseTimer: Timer?
    private var lastPermissionCheck: TimeInterval = 0
    private var placementFrame = CGRect.zero
    private var hoveredID: String?
    private var hoverAnchor = NSPoint.zero
    private var lastScroll: TimeInterval = 0

    private init() {
        SwitcherInput.shared.onAction = { [weak self] action in self?.handle(action) }
        SwitcherInput.shared.onAvailability = { [weak self] available in
            guard let self else { return }
            self.inputLive = available
            if available { self.shortcutError = nil }
            self.registerFallback(enabled: !available)
            self.nativeKeys.sync(self.preferences, recording: self.recording, live: available)
        }
    }
    var filtered: [SwitcherWindow] {
        Self.displayRows(sessionWindows, scope: scope, scopePID: scopePID, preferences: preferences, query: query)
    }
    static func displayRows(_ rows: [SwitcherWindow], scope: SwitcherScope, scopePID: pid_t?, preferences: SwitcherPreferences, query: String) -> [SwitcherWindow] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var rows = rows.filter {
            (scope != .currentApp || $0.pid == scopePID) && (term.isEmpty || "\($0.appName) \($0.title)".localizedCaseInsensitiveContains(term))
        }
        if scope == .apps && (preferences.mergeWindows || preferences.layout == .icons) {
            var seen = Set<pid_t>(); rows = rows.filter { seen.insert($0.pid).inserted }
        }
        if preferences.minimized == .last { rows = rows.filter { !$0.minimized } + rows.filter(\.minimized) }
        return rows
    }
    var selected: SwitcherWindow? { filtered.first { $0.id == selectedID } ?? filtered.first }
    var selectedAppWindows: [SwitcherWindow] {
        guard let selected else { return [] }
        return sessionWindows.filter { $0.pid == selected.pid }
    }
    var usesPreviews: Bool { preferences.layout != .list }
    var canCaptureSession: Bool { sourcePID.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }.map { !preferences.previewExcludedApps.contains($0) } ?? true }

    func apply(_ settings: SwitcherPreferences) {
        preferences = settings
        shortcutError = nil
        refreshPermissions()
        if !settings.enabled { hide(); thumbnails.clear(); SwitcherHistory.shared.stop() }
        else { SwitcherHistory.shared.start() }
        updateInput()
        secureInputTimer?.invalidate(); secureInputTimer = nil
        if settings.enabled {
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - self.lastPermissionCheck >= 2 {
                        self.lastPermissionCheck = now
                        let wasGranted = self.accessibilityGranted
                        self.refreshPermissions()
                        if SwitcherInput.shouldReconnect(permissionGranted: self.accessibilityGranted,
                                                         wasGranted: wasGranted,
                                                         live: SwitcherInput.shared.isLive,
                                                         recording: self.recording,
                                                         secureInput: IsSecureEventInputEnabled()) {
                            self.updateInput()
                        }
                    }
                    self.nativeKeys.sync(self.preferences, recording: self.recording, live: SwitcherInput.shared.isLive)
                    if IsSecureEventInputEnabled(), self.sessionActive { self.hide() }
                }
            }
            timer.tolerance = 0.1; RunLoop.main.add(timer, forMode: .common); secureInputTimer = timer
        }
    }
    func setRecording(_ recording: Bool) {
        self.recording = recording
        if recording { hide(); unregisterHotKeys() }
        else { updateInput() }
        nativeKeys.sync(preferences, recording: recording, live: SwitcherInput.shared.isLive)
    }
    private func updateInput() {
        SwitcherInput.shared.configure(preferences)
        inputLive = SwitcherInput.shared.isLive
        if !SwitcherInput.shared.isLive { registerFallback(enabled: true) }
        nativeKeys.sync(preferences, recording: recording, live: SwitcherInput.shared.isLive)
    }
    private func unregisterHotKeys() {
        for key in hotKeys { UnregisterEventHotKey(key) }; hotKeys = []
    }
    private func registerFallback(enabled: Bool) {
        unregisterHotKeys()
        guard enabled, preferences.enabled, !recording else { return }
        shortcutError = nil
        if hotKeyHandler == nil {
            let specs = [kEventHotKeyPressed, kEventHotKeyReleased].map {
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32($0))
            }
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                      id.signature == 0x48414C57, let scope = SwitcherScope(rawValue: Int(id.id)) else { return OSStatus(eventNotHandledErr) }
                let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                Task { @MainActor in
                    let switcher = WindowSwitcher.shared
                    guard let key = switcher.preferences.shortcuts.first(where: { $0.0 == scope })?.1 else { return }
                    if pressed {
                        switcher.begin(scope, key: key, reversed: NSEvent.modifierFlags.contains(.shift), pinned: false)
                    } else if !switcher.searchPinned, switcher.activeKey == key,
                              SwitcherInput.shouldCommit(flags: UInt64(NSEvent.modifierFlags.rawValue), required: key.holdMask, pinned: false) {
                        // Carbon still works without an event tap. It must also
                        // finish a quick press released before the panel opens.
                        switcher.commit()
                    }
                }
                return noErr
            }, specs.count, specs, nil, &hotKeyHandler)
        }
        for (scope, key) in preferences.shortcuts {
            guard key.isValid, !key.isSystem else { continue }
            var carbon: UInt32 = 0
            for (flag, value) in [(CGEventFlags.maskAlternate, optionKey), (.maskControl, controlKey), (.maskCommand, cmdKey), (.maskShift, shiftKey)] {
                if key.modifiers & flag.rawValue != 0 { carbon |= UInt32(value) }
            }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(key.code), carbon, EventHotKeyID(signature: 0x48414C57, id: UInt32(scope.rawValue)), GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { hotKeys.append(ref) }
            else { shortcutError = Lf("%1$@ başka bir uygulamada kullanılıyor. Yeni bir kısayol kaydet.", "%1$@ is used by another app. Record a different shortcut.", key.title) }
        }
    }
    func openOrAdvance() { begin(.apps, key: nil, reversed: false, pinned: true) }
    func begin(_ requestedScope: SwitcherScope, key: SwitcherKey?, reversed: Bool, pinned: Bool) {
        guard preferences.enabled, !recording else {
            // Olay yakalayıcı oturumu çoktan açık saydı; açık kalırsa her tuşu yutar.
            updateRouting()
            return
        }
        if sessionActive && pendingCommit { hide() }
        if sessionActive {
            if requestedScope == .currentApp && scope != .currentApp {
                scopePID = selected?.pid ?? sourcePID; scope = .currentApp; query = ""; selectedID = nil
                reconcileSearch(); resize()
            } else { advance(reversed ? -1 : 1) }
            return
        }
        generation += 1; let ticket = generation; cancellation.set(ticket)
        sessionActive = true; searchPinned = pinned; activeKey = key
        sourcePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        scopePID = sourcePID; scope = requestedScope; query = ""; selectedID = nil
        stepsWhileLoading = reversed ? -1 : 1; pendingCommit = false; loading = true
        sessionWindows = []; windows = []; hoveredID = nil; hoverAnchor = NSEvent.mouseLocation; sourceWindowID = nil
        placementFrame = screenForSession().visibleFrame
        updateRouting()
        if let key, !pinned, !SwitcherInput.shared.isLive {
            // A Carbon key-up can arrive while Option is still held. Watch
            // modifier release for this session, including before first draw.
            let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if SwitcherInput.shouldCommit(flags: UInt64(NSEvent.modifierFlags.rawValue),
                                                  required: key.holdMask, pinned: self.searchPinned) {
                        self.commit()
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            fallbackReleaseTimer = timer
        }
        let show = DispatchWorkItem { [weak self] in
            guard let self, self.generation == ticket, self.sessionActive, !self.pendingCommit else { return }
            self.show()
        }
        showTask = show
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(preferences.appearanceDelay) / 1000, execute: show)
        let prefs = preferences, accessible = accessibilityGranted
        let screen = screenForSession(); let screenBounds = CGDisplayBounds(screen.displayID)
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular || $0.processIdentifier == ProcessInfo.processInfo.processIdentifier
        }.map { SwitcherAppSnapshot(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier ?? "", name: $0.localizedName ?? "",
                                    icon: $0.icon ?? NSWorkspace.shared.icon(for: .applicationBundle), hidden: $0.isHidden) }
        let cancellation = self.cancellation
        enumeration.async { [weak self] in
            let result = SwitcherWindowQuery.scan(apps: apps, preferences: prefs, accessibility: accessible, screen: screenBounds, cancelled: { !cancellation.isCurrent(ticket) })
            DispatchQueue.main.async { [weak self] in self?.complete(result, ticket: ticket) }
        }
    }
    private func complete(_ rows: [SwitcherWindow], ticket: Int) {
        guard ticket == generation, sessionActive else { return }
        loading = false
        // Sıra: kullanıcının gerçekten kullandığı pencereler en son kullanılan
        // önce; hiç odak almamışlar uygulamanın son kullanımına, sonra
        // pencere sunucusunun önden arkaya sırasına göre. Öndeki pencere başta
        // durur, böylece ilk adım bir önceki pencereye gider.
        let windowRank = SwitcherHistory.shared.windowRanks()
        let appRank = SwitcherHistory.shared.appRanks()
        func rank(_ row: SwitcherWindow) -> (Int, Int, Int) {
            if let id = row.windowID, let known = windowRank[id] { return (0, known, 0) }
            return (row.windowID == nil ? 2 : 1, appRank[row.pid] ?? Int.max / 2, row.order)
        }
        let source = rows.filter { $0.pid == sourcePID && !$0.minimized }.min { rank($0) < rank($1) }
        sourceWindowID = source?.windowID
        sessionWindows = rows.sorted { a, b in
            if a.id == source?.id { return b.id != source?.id }
            if b.id == source?.id { return false }
            return rank(a) < rank(b)
        }
        windows = sessionWindows
        let visible = filtered
        if !visible.isEmpty {
            let index = ((stepsWhileLoading % visible.count) + visible.count) % visible.count
            selectedID = visible[index].id
        }
        if pendingCommit { activateSelected(); return }
        if panel?.isVisible == true { resize() }
        if usesPreviews && captureGranted && canCaptureSession {
            for row in rows { if let id = row.windowID, let cached = thumbnails.existing(id) { previews[id] = cached } }
            let priority = selected.map { chosen in rows.filter { $0.id == chosen.id } + rows.filter { $0.id != chosen.id } } ?? rows
            thumbnails.refresh(priority, excluded: preferences.previewExcludedApps) { [weak self] id, image in
                guard let self, self.generation == ticket, self.sessionActive else { return }; self.previews[id] = image
            }
        }
    }
    private func screenForSession() -> NSScreen {
        switch preferences.placement {
        case .menuBar: return NSScreen.screens.first ?? .preferred
        case .activeWindow:
            if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, accessibilityGranted {
                let app = AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(app, 0.05)
                if let raw = SwitcherWindowQuery.value(app, kAXFocusedWindowAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID(),
                   let frame = SwitcherWindowQuery.frame(unsafeBitCast(raw, to: AXUIElement.self)),
                   let screen = NSScreen.screens.max(by: { CGDisplayBounds($0.displayID).intersection(frame).area < CGDisplayBounds($1.displayID).intersection(frame).area }) { return screen }
            }
            return NSScreen.main ?? .preferred
        case .pointer: return NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? .preferred
        }
    }
    private func makePanel() -> NSPanel {
        let panel = SwitcherPanel(contentRect: .zero, styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = L("Hâl · Pencere değiştirici", "Hâl · Window switcher")
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { panel.standardWindowButton(button)?.isHidden = true }
        panel.isReleasedWhenClosed = false; panel.becomesKeyOnlyIfNeeded = false
        panel.level = .popUpMenu; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: WindowSwitcherPanel().environmentObject(self))
        // Also accept local/accessibility-generated keys, which can bypass the
        // session event tap. Already-consumed physical keys never arrive here.
        localKeys = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.sessionActive else { return event }
            if event.type == .flagsChanged {
                if !self.searchPinned, let key = self.activeKey, UInt64(event.modifierFlags.rawValue) & key.holdMask != key.holdMask { self.commit() }
                return event
            }
            self.handleKey(event.keyCode, flags: UInt64(event.modifierFlags.rawValue)); return nil
        }
        return panel
    }
    private func show() {
        guard sessionActive, !pendingCommit else { return }
        if panel == nil { panel = makePanel() }
        resize()
        panel?.makeKeyAndOrderFront(nil)
        if searchPinned || !accessibilityGranted { NSApp.activate(ignoringOtherApps: true) }
        updateRouting()
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }
    func resize() {
        guard let panel else { return }
        let count = max(1, filtered.count)
        let maxWidth = max(300, placementFrame.width - 64)
        let width: CGFloat, height: CGFloat
        if preferences.layout == .list {
            columns = 1; width = min(560, maxWidth); height = min(placementFrame.height - 90, CGFloat(min(12, count)) * 48 + 36 + (searchPinned || !query.isEmpty ? 38 : 0) + (searchPinned && usesPreviews && !captureGranted ? 22 : 0))
        } else if preferences.layout == .icons && scope == .apps {
            let iconsWidth = CGFloat(count) * 68 + 36
            columns = min(count, max(1, Int((maxWidth - 36) / 68)))
            width = min(maxWidth, max(420, iconsWidth)); height = captureGranted && canCaptureSession ? 310 : 170
        } else {
            let cardWidth = preferences.previewSize.width
            let availableColumns = max(1, Int((maxWidth - 36 + 12) / (cardWidth + 12)))
            columns = min(count, preferences.maxColumns == 0 ? availableColumns : min(availableColumns, preferences.maxColumns))
            width = min(maxWidth, CGFloat(columns) * (cardWidth + 12) + 24)
            let rows = Int(ceil(Double(count) / Double(columns)))
            let rowHeight = cardWidth * 0.62 + (preferences.minimalPreviews ? 16 : 54)
            height = min(placementFrame.height - 90, CGFloat(rows) * rowHeight + 36 + (searchPinned || !query.isEmpty ? 38 : 0) + (searchPinned && usesPreviews && !captureGranted ? 22 : 0))
        }
        panel.setContentSize(NSSize(width: width, height: max(130, height)))
        panel.setFrameOrigin(NSPoint(x: placementFrame.midX - width / 2, y: placementFrame.midY - panel.frame.height / 2))
        updateRouting()
    }
    private func updateRouting() {
        let nsFrame = panel?.isVisible == true ? panel!.frame : .zero
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let cgFrame = CGRect(x: nsFrame.minX, y: top - nsFrame.maxY, width: nsFrame.width, height: nsFrame.height)
        SwitcherInput.shared.setSession(active: sessionActive, pinned: searchPinned, holdMask: activeKey?.holdMask ?? 0, frame: cgFrame)
    }
    private func handle(_ action: SwitcherInput.Action) {
        switch action {
        case let .begin(scope, key, reverse): begin(scope, key: key, reversed: reverse, pinned: false)
        case let .step(delta): advance(delta)
        case let .key(code, flags): handleKey(code, flags: flags)
        case .commit: commit()
        case .cancel: hide()
        case let .scroll(delta):
            if ProcessInfo.processInfo.systemUptime - lastScroll > 0.09 { advance(delta); lastScroll = ProcessInfo.processInfo.systemUptime }
        case .middleClick: if let id = hoveredID { closeWindow(id) }
        }
    }
    private func handleKey(_ code: UInt16, flags: UInt64) {
        guard sessionActive else { return }
        switch code {
        case 53: hide()
        case 36, 76: activateSelected()
        case 48, 124: advance(flags & CGEventFlags.maskShift.rawValue != 0 ? -1 : 1)
        case 123: advance(-1)
        case 125: advance(columns)
        case 126: advance(-columns)
        case 51, 117:
            if !query.isEmpty { query.removeLast(); reconcileSearch() }
        default:
            let character = SwitcherKey.character(code, shift: flags & CGEventFlags.maskShift.rawValue != 0)
            if !searchPinned && query.isEmpty {
                if character.lowercased() == "s" && preferences.pinSearch { searchPinned = true; updateRouting(); resize(); return }
                if character.lowercased() == "w" { if let selected { closeWindow(selected.id) }; return }
                if character.lowercased() == "q" { quitSelectedApp(); return }
            }
            if !character.isEmpty && !character.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                query += character; reconcileSearch()
            }
        }
    }
    func advance(_ delta: Int) {
        guard sessionActive else { return }
        if loading { stepsWhileLoading += delta; return }
        let rows = filtered; guard !rows.isEmpty else { return }
        let index = rows.firstIndex { $0.id == selectedID } ?? 0
        selectedID = rows[Self.wrappedIndex(index + delta, count: rows.count)].id
        hoverAnchor = NSEvent.mouseLocation; hoveredID = nil
    }
    static func wrappedIndex(_ index: Int, count: Int) -> Int { count > 0 ? ((index % count) + count) % count : 0 }
    func hover(_ id: String, inside: Bool) {
        if !inside { if hoveredID == id { hoveredID = nil }; return }
        let mouse = NSEvent.mouseLocation
        guard hypot(mouse.x - hoverAnchor.x, mouse.y - hoverAnchor.y) > 4 else { return }
        hoveredID = id; selectedID = id
    }
    func reconcileSearch() {
        if !filtered.contains(where: { $0.id == selectedID }) { selectedID = filtered.first?.id }
        resize()
    }
    private func commit() {
        fallbackReleaseTimer?.invalidate(); fallbackReleaseTimer = nil
        guard sessionActive else { return }
        if loading { pendingCommit = true; showTask?.cancel(); return }
        activateSelected()
    }
    func activateSelected() { if let selected { activate(selected) } else { hide() } }
    func activate(_ row: SwitcherWindow) {
        // Geçmiş hemen güncellenir: hızlı bir ikinci basış, pencere sunucusu
        // ve AX bu geçişi bildirmeden önce gelebilir.
        SwitcherHistory.shared.noteSwitch(to: row.windowID, pid: row.pid, from: sourceWindowID)
        let source = sourcePID
        hide()
        SwitcherActivator.activate(row, sourcePID: source)
    }
    func closeWindow(_ id: String) {
        // Başka Space'teki pencerenin AX öğesi listede yoktur; kimliğiyle aranır.
        guard let row = sessionWindows.first(where: { $0.id == id }),
              let element = row.element ?? row.windowID.flatMap({ SwitcherWindowServer.element(for: $0, pid: row.pid) }),
              let raw = SwitcherWindowQuery.value(element, kAXCloseButtonAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return }
        let button = unsafeBitCast(raw, to: AXUIElement.self)
        guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else { return }
        sessionWindows.removeAll { $0.id == id }; windows = sessionWindows; reconcileSearch()
    }
    private func quitSelectedApp() {
        guard let pid = selected?.pid, pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid), app.terminate() else { return }
        sessionWindows.removeAll { $0.pid == pid }; windows = sessionWindows; reconcileSearch()
    }
    func hide() {
        fallbackReleaseTimer?.invalidate(); fallbackReleaseTimer = nil
        generation += 1; cancellation.set(generation); sessionActive = false
        showTask?.cancel(); showTask = nil; thumbnails.cancel(); pendingCommit = false; loading = false
        panel?.orderOut(nil); previews = [:]; query = ""; searchPinned = false
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks); self.outsideClicks = nil }
        updateRouting()
    }
    func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted(); captureGranted = CGPreflightScreenCaptureAccess()
        if !captureGranted { thumbnails.clear(); previews = [:] }
    }
    func permissionsChanged() { refreshPermissions(); updateInput() }
    func requestAccessibility() { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) }
    func requestCapture() { captureGranted = CGRequestScreenCaptureAccess() }
    func shutdown() {
        hide(); unregisterHotKeys(); nativeKeys.restore(); SwitcherInput.shared.stop(); thumbnails.clear(); SwitcherHistory.shared.stop()
        secureInputTimer?.invalidate(); secureInputTimer = nil
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler); self.hotKeyHandler = nil }
        if let localKeys { NSEvent.removeMonitor(localKeys); self.localKeys = nil }
    }
}
private final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
private final class SwitcherCancellation: @unchecked Sendable {
    private let lock = NSLock(); private var ticket = 0
    func set(_ value: Int) { lock.lock(); ticket = value; lock.unlock() }
    func isCurrent(_ value: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return ticket == value }
}
private extension CGRect { var area: CGFloat { isNull ? 0 : max(0, width) * max(0, height) } }
