import AppKit
import ApplicationServices

/// The event-tap thread only compares key codes and snapshots. AX enumeration,
/// screenshots and UI work never run on the input thread or block its callback.
final class SwitcherInput {
    enum Action {
        case begin(SwitcherScope, SwitcherKey, Bool)
        case step(Int), key(UInt16, UInt64), commit, cancel, scroll(Int), middleClick
    }
    static let shared = SwitcherInput()
    var onAction: ((Action) -> Void)?
    var onAvailability: ((Bool) -> Void)?
    private let lock = NSLock()
    private var settings = SwitcherPreferences()
    private var active = false
    private var pinned = false
    private var holdMask: UInt64 = 0
    private var recording: ((UInt16, UInt64) -> Void)?
    private var panelFrame = CGRect.zero
    private var tap: CFMachPort?
    private var loop: CFRunLoop?
    private var thread: Thread?
    private var stopRequested = false
    private var swallowedKeyUps = Set<UInt16>()
    private var live = false
    var isLive: Bool {
        lock.lock(); let port = tap; let running = live; lock.unlock()
        return running && port.map { CGEvent.tapIsEnabled(tap: $0) } == true
    }

    func configure(_ preferences: SwitcherPreferences) {
        lock.lock(); settings = preferences; let needed = preferences.enabled || recording != nil; lock.unlock()
        if needed && AXIsProcessTrusted() { start() } else { stop() }
    }
    func setSession(active: Bool, pinned: Bool, holdMask: UInt64 = 0, frame: CGRect = .zero) {
        lock.lock(); self.active = active; self.pinned = pinned; self.holdMask = holdMask; panelFrame = frame; lock.unlock()
    }
    func record(_ callback: ((UInt16, UInt64) -> Void)?) {
        lock.lock(); recording = callback; let prefs = settings; lock.unlock()
        configure(prefs)
    }
    static func shouldCommit(flags: UInt64, required: UInt64, pinned: Bool) -> Bool {
        !pinned && required != 0 && flags & required != required
    }
    static func shouldReconnect(permissionGranted: Bool, wasGranted: Bool, live: Bool,
                                recording: Bool, secureInput: Bool) -> Bool {
        permissionGranted != wasGranted || (permissionGranted && !live && !recording && !secureInput)
    }
    private func emit(_ action: Action) {
        DispatchQueue.main.async { [weak self] in self?.onAction?(action) }
    }
    private func start() {
        lock.lock()
        guard thread == nil else { stopRequested = false; lock.unlock(); return }
        stopRequested = false
        let worker = Thread { [weak self] in self?.run() }
        worker.name = "Hâl switcher input"; worker.qualityOfService = .userInteractive
        thread = worker; lock.unlock(); worker.start()
    }
    func stop() {
        lock.lock(); stopRequested = true; let loop = self.loop; let tap = self.tap; lock.unlock()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let loop { CFRunLoopStop(loop) }
    }
    private func run() {
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
            .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                                   callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<SwitcherInput>.fromOpaque(context).takeUnretainedValue().route(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            lock.lock(); thread = nil; live = false; lock.unlock()
            DispatchQueue.main.async { [weak self] in self?.onAvailability?(false) }
            return
        }
        let loop = CFRunLoopGetCurrent()!
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)!
        lock.lock(); self.tap = tap; self.loop = loop; live = true; let stop = stopRequested; lock.unlock()
        CFRunLoopAddSource(loop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: !stop)
        DispatchQueue.main.async { [weak self] in self?.onAvailability?(!stop) }
        if !stop { CFRunLoopRun() }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(loop, source, .commonModes); CFMachPortInvalidate(tap)
        lock.lock(); self.tap = nil; self.loop = nil; thread = nil; live = false
        let restart = !stopRequested && (settings.enabled || recording != nil)
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.onAvailability?(false) }
        if restart { start() }
    }
    private func route(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock(); let tap = stopRequested ? nil : self.tap; active = false; lock.unlock()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            emit(.cancel)
            return Unmanaged.passUnretained(event)
        }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.rawValue & SwitcherKey.mask
        lock.lock()
        if type == .keyUp, swallowedKeyUps.remove(code) != nil { lock.unlock(); return nil }
        let recording = self.recording
        if let recording, type == .keyDown {
            swallowedKeyUps.insert(code); lock.unlock()
            DispatchQueue.main.async { recording(code, flags) }
            return nil
        }
        if recording != nil { lock.unlock(); return Unmanaged.passUnretained(event) }
        let prefs = settings
        let isActive = active, isPinned = pinned, held = holdMask, frame = panelFrame
        guard prefs.enabled else { lock.unlock(); return Unmanaged.passUnretained(event) }
        if type == .flagsChanged {
            if isActive && Self.shouldCommit(flags: flags, required: held, pinned: isPinned) {
                active = false; lock.unlock(); emit(.commit)
            } else { lock.unlock() }
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown {
            let match = prefs.shortcuts.first { _, shortcut in
                shortcut.matches(code: code, flags: flags) && (!shortcut.isSystem || prefs.takeOverSystemShortcuts)
            }
            if let (scope, key) = match {
                swallowedKeyUps.insert(code)
                if !isActive {
                    active = true; pinned = false; holdMask = key.holdMask
                    lock.unlock(); emit(.begin(scope, key, flags & CGEventFlags.maskShift.rawValue != 0))
                } else {
                    lock.unlock()
                    if scope == .currentApp { emit(.begin(scope, key, flags & CGEventFlags.maskShift.rawValue != 0)) }
                    else { emit(.step(flags & CGEventFlags.maskShift.rawValue != 0 ? -1 : 1)) }
                }
                return nil
            }
            if isActive {
                swallowedKeyUps.insert(code); lock.unlock(); emit(.key(code, flags)); return nil
            }
        }
        lock.unlock()
        if isActive && [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type) {
            if !frame.contains(event.location) { emit(.cancel) }
            else if type == .otherMouseDown && event.getIntegerValueField(.mouseEventButtonNumber) == 2 { emit(.middleClick); return nil }
        }
        if isActive && type == .scrollWheel && frame.contains(event.location) {
            let delta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            if delta != 0 { emit(.scroll(delta > 0 ? -1 : 1)) }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}
