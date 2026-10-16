import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import IOKit.hid
import IOKit.pwr_mgt

final class DeviceModes {
    static let shared = DeviceModes()

    var clickTargetProvider: (() -> [NSRect])?

    private var hidManager: IOHIDManager?
    private var seizedDevices: [IOHIDDevice] = []
    private var eventTap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var displayAssertion: IOPMAssertionID = 0
    private var idleAssertion: IOPMAssertionID = 0
    private var systemAssertion: IOPMAssertionID = 0
    private var activity: NSObjectProtocol?
    private var watchdog: Timer?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var cleaning = false
    private var allowedQuartzRects: [CGRect] = []
    private var savedPolicy: NSApplication.ActivationPolicy?
    private let lock = NSLock()
    private let shield = CleaningShield()

    private init() {}

    var isCleaning: Bool {
        lock.lock(); defer { lock.unlock() }
        return cleaning
    }

    var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    struct CleaningResult {
        var active: Bool
        var message: String?
    }

    struct CleaningCopy {
        var title: String
        var hint: String
        var buttonTitle: String

        static var standard: CleaningCopy {
            CleaningCopy(
                title: AppSettings.defaultCleaningTitle,
                hint: AppSettings.defaultCleaningHint,
                buttonTitle: AppSettings.defaultCleaningButtonTitle
            )
        }
    }

    @discardableResult
    func setCleaning(_ on: Bool, copy: CleaningCopy = .standard) -> CleaningResult {
        if on { return startCleaning(copy: copy) }
        stopCleaning()
        return CleaningResult(active: false, message: nil)
    }

    func setAlwaysWake(_ on: Bool) {
        clearSleepAssertions()
        guard on else { return }
        displayAssertion = createAssertion(kIOPMAssertionTypePreventUserIdleDisplaySleep, "Hâl Always Wake Display")
        idleAssertion = createAssertion(kIOPMAssertionTypePreventUserIdleSystemSleep, "Hâl Always Wake Idle")
        systemAssertion = createAssertion(kIOPMAssertionTypePreventSystemSleep, "Hâl Always Wake System")
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .suddenTerminationDisabled, .userInitiated],
            reason: "Hâl Always Wake"
        )
    }

    func shutdown() {
        stopCleaning()
        setAlwaysWake(false)
    }

    func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
    }

    func refreshClickTargets() {
        refreshAllowedRects()
    }

    func openInputMonitoringSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
        openAccessibilitySettings()
    }

    private func startCleaning(copy: CleaningCopy) -> CleaningResult {
        stopCleaning()
        setCleaningFlag(true)
        presentAsRegularApp()
        shield.show(copy: copy) { [weak self] in
            _ = self?.setCleaning(false)
            NotificationCenter.default.post(name: .halCleaningEnded, object: nil)
        }
        seizeBuiltInInput()
        installMonitors()
        refreshAllowedRects()

        // Olay yakalayıcıyı yalnızca izin zaten varsa dene: izinsiz denemek
        // her açılışta sistem izin penceresi doğuruyordu. Ekranı kaplayan kalkan
        // ve yerel izleyiciler zaten çalışıyor, yönlendirmeye gerek yok.
        let tapOK = canInstallEventTap ? installEventTap() : false
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCleaning else { return }
            self.shield.raise()
            self.refreshAllowedRects()
            if self.eventTap == nil, self.canInstallEventTap {
                _ = self.installEventTap()
            }
        }
        startWatchdog()

        if tapOK {
            return CleaningResult(
                active: true,
                message: Lf(
                    "%1$@ açık. Dahili klavye ve trackpad tıklamaları kilitli. Kapatmak için düğmeye veya Hâl ikonuna tıkla.",
                    "%1$@ is on. Built-in keyboard and trackpad clicks are locked. Click the button or the Hâl icon to stop.",
                    copy.title
                )
            )
        }
        return CleaningResult(
            active: true,
            message: Lf(
                "%1$@ açık; ekran kalkanı devrede. Sistem kısayollarının da kilitlenmesi için Ayarlar’dan “Klavye kilidi izni”ni ver.",
                "%1$@ is on and the screen shield is up. Allow “Keyboard lock” in Settings to lock system shortcuts too.",
                copy.title
            )
        )
    }

    /// İzin verilmemişken olay yakalayıcı kurmaya çalışmak sistem izin penceresi açar.
    private var canInstallEventTap: Bool {
        guard AXIsProcessTrusted() else { return false }
        if #available(macOS 10.15, *) {
            return CGPreflightListenEventAccess()
        }
        return true
    }

    /// Yalnızca kullanıcı Ayarlar’dan açıkça istediğinde izin sorar.
    func requestKeyboardLockPermission() {
        requestPermissions()
    }

    private func stopCleaning() {
        setCleaningFlag(false)
        watchdog?.invalidate()
        watchdog = nil
        removeEventTap()
        removeMonitors()
        releaseSeizedDevices()
        shield.hide()
        restoreActivationPolicy()
    }

    private func setCleaningFlag(_ on: Bool) {
        lock.lock()
        cleaning = on
        lock.unlock()
    }

    private func presentAsRegularApp() {
        if savedPolicy == nil {
            savedPolicy = NSApp.activationPolicy()
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func restoreActivationPolicy() {
        guard let savedPolicy else { return }
        NSApp.setActivationPolicy(savedPolicy)
        self.savedPolicy = nil
    }

    private func requestPermissions() {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(prompt)
        if #available(macOS 10.15, *) {
            if !CGPreflightListenEventAccess() {
                _ = CGRequestListenEventAccess()
            }
            if !CGPreflightPostEventAccess() {
                _ = CGRequestPostEventAccess()
            }
        }
    }

    private func installMonitors() {
        removeMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .systemDefined]) { [weak self] event in
            guard self?.isCleaning == true else { return event }
            return nil
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { _ in }
    }

    private func removeMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    private func seizeBuiltInInput() {
        releaseSeizedDevices()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [CFDictionary] = [
            [kIOHIDDeviceUsagePageKey: 1, kIOHIDDeviceUsageKey: 6] as CFDictionary,
            [kIOHIDDeviceUsagePageKey: 1, kIOHIDDeviceUsageKey: 7] as CFDictionary,
            [kIOHIDDeviceUsagePageKey: 13] as CFDictionary
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<DeviceModes>.fromOpaque(context).takeUnretainedValue().trySeize(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return }
        hidManager = manager
        if let all = IOHIDManagerCopyDevices(manager) {
            seizeSet(all)
        }
    }

    private func seizeSet(_ cfDevices: CFSet) {
        let count = CFSetGetCount(cfDevices)
        var pointers = Array<UnsafeRawPointer?>(repeating: nil, count: count)
        pointers.withUnsafeMutableBufferPointer { buffer in
            CFSetGetValues(cfDevices, buffer.baseAddress)
        }
        for pointer in pointers {
            guard let pointer else { continue }
            let device = Unmanaged<IOHIDDevice>.fromOpaque(pointer).takeUnretainedValue()
            trySeize(device)
        }
    }

    private func trySeize(_ device: IOHIDDevice) {
        guard shouldSeize(device) else { return }
        lock.lock()
        defer { lock.unlock() }
        if seizedDevices.contains(where: { $0 === device }) { return }
        if IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) == kIOReturnSuccess {
            seizedDevices.append(device)
        }
    }

    private func releaseSeizedDevices() {
        lock.lock()
        for device in seizedDevices {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        seizedDevices.removeAll()
        if let hidManager {
            IOHIDManagerRegisterDeviceMatchingCallback(hidManager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        hidManager = nil
        lock.unlock()
    }

    private func shouldSeize(_ device: IOHIDDevice) -> Bool {
        let product = stringProperty(device, kIOHIDProductKey).lowercased()
        let transport = stringProperty(device, kIOHIDTransportKey).lowercased()
        if product.contains("magic mouse") { return false }
        if product.contains("mouse") && !product.contains("trackpad") && !product.contains("touch") { return false }

        let isKey = isKeyboard(device) || product.contains("keyboard")
        let isPad = isTrackpad(device)
            || product.contains("trackpad")
            || product.contains("touchpad")
            || product.contains("multitouch")
            || product.contains("touch bar")
        guard isKey || isPad else { return false }

        if product.contains("magic keyboard") || product.contains("magic trackpad") { return false }
        if transport.contains("bluetooth") { return false }

        if isInternal(device)
            || product.contains("internal")
            || product.contains("built-in")
            || product.contains("apple internal")
            || product.contains("spi") {
            return true
        }

        let vendor = intProperty(device, kIOHIDVendorIDKey)
        if vendor == 0x05AC && !transport.contains("usb") { return true }
        if vendor == 0x05AC && (isInternal(device) || product.contains("internal") || product.contains("keyboard / trackpad")) {
            return true
        }
        return isInternal(device)
    }

    private func isInternal(_ device: IOHIDDevice) -> Bool {
        if boolProperty(device, kIOHIDBuiltInKey) { return true }
        let transport = stringProperty(device, kIOHIDTransportKey).uppercased()
        return ["SPI", "I2C", "FIFO", "ACPI"].contains(transport)
    }

    private func isKeyboard(_ device: IOHIDDevice) -> Bool {
        let page = intProperty(device, kIOHIDPrimaryUsagePageKey)
        let usage = intProperty(device, kIOHIDPrimaryUsageKey)
        return page == 0x01 && (usage == 0x06 || usage == 0x07)
    }

    private func isTrackpad(_ device: IOHIDDevice) -> Bool {
        let page = intProperty(device, kIOHIDPrimaryUsagePageKey)
        let usage = intProperty(device, kIOHIDPrimaryUsageKey)
        if page == 0x0D { return true }
        if page == 0x01 && (usage == 0x01 || usage == 0x02) {
            let product = stringProperty(device, kIOHIDProductKey).lowercased()
            return product.contains("trackpad") || product.contains("touch") || product.contains("multitouch")
        }
        return false
    }

    private func stringProperty(_ device: IOHIDDevice, _ key: String) -> String {
        IOHIDDeviceGetProperty(device, key as CFString) as? String ?? ""
    }

    private func intProperty(_ device: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
    }

    private func boolProperty(_ device: IOHIDDevice, _ key: String) -> Bool {
        if let flag = IOHIDDeviceGetProperty(device, key as CFString) as? Bool { return flag }
        return (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.boolValue ?? false
    }

    private func installEventTap() -> Bool {
        removeEventTap()
        let mask = Self.eventMask()
        let info = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let modes = Unmanaged<DeviceModes>.fromOpaque(refcon).takeUnretainedValue()
            return modes.handleTap(type: type, event: event)
        }

        let locations: [CGEventTapLocation] = [.cgSessionEventTap, .cghidEventTap]
        var tap: CFMachPort?
        for location in locations {
            tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: info
            )
            if tap != nil { break }
        }
        guard let tap else { return false }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private static func eventMask() -> CGEventMask {
        var mask: CGEventMask = 0
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .scrollWheel, .tabletPointer, .tabletProximity
        ]
        for type in types {
            mask |= (CGEventMask(1) << type.rawValue)
        }
        for raw in [14, 22, 23, 24, 29, 30, 31, 32, 33, 34, 37] {
            mask |= (CGEventMask(1) << UInt64(raw))
        }
        return mask
    }

    private func removeEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes)
        }
        eventTap = nil
        tapSource = nil
    }

    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self, self.isCleaning else { return }
            self.refreshAllowedRects()
            if self.eventTap == nil {
                _ = self.installEventTap()
            } else if let tap = self.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            if self.hidManager == nil {
                self.seizeBuiltInInput()
            }
            self.shield.raise()
        }
        watchdog?.tolerance = 0.15
        if let watchdog {
            RunLoop.main.add(watchdog, forMode: .common)
        }
    }

    private func refreshAllowedRects() {
        var rects = clickTargetProvider?() ?? []
        rects.append(contentsOf: shield.unlockRects)
        let quartz = rects.map(Self.cocoaToQuartz)
        lock.lock()
        allowedQuartzRects = quartz
        lock.unlock()
    }

    private func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        let on = cleaning
        let allowed = allowedQuartzRects
        lock.unlock()
        guard on else { return Unmanaged.passUnretained(event) }

        if isKeyEvent(type) {
            return nil
        }

        if isPointerOrGesture(type) {
            if isUnlockClick(type, event, allowed: allowed) {
                return Unmanaged.passUnretained(event)
            }
            if type == .mouseMoved {
                return Unmanaged.passUnretained(event)
            }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func isKeyEvent(_ type: CGEventType) -> Bool {
        type == .keyDown || type == .keyUp || type == .flagsChanged || type.rawValue == 14
    }

    private func isPointerOrGesture(_ type: CGEventType) -> Bool {
        switch type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
             .mouseMoved, .leftMouseDragged, .rightMouseDragged,
             .otherMouseDown, .otherMouseUp, .otherMouseDragged,
             .scrollWheel, .tabletPointer, .tabletProximity:
            return true
        default:
            return [18, 19, 20, 22, 23, 24, 29, 30, 31, 32, 33, 34, 37].contains(type.rawValue)
        }
    }

    private func isUnlockClick(_ type: CGEventType, _ event: CGEvent, allowed: [CGRect]) -> Bool {
        switch type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp:
            let point = event.location
            return allowed.contains { $0.insetBy(dx: -10, dy: -10).contains(point) }
        default:
            return false
        }
    }

    private static func cocoaToQuartz(_ rect: NSRect) -> CGRect {
        let maxY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        return CGRect(x: rect.minX, y: maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    private func createAssertion(_ type: String, _ name: String) -> IOPMAssertionID {
        var assertionID: IOPMAssertionID = 0
        IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name as CFString,
            &assertionID
        )
        return assertionID
    }

    private func clearSleepAssertions() {
        if displayAssertion != 0 { IOPMAssertionRelease(displayAssertion) }
        if idleAssertion != 0 { IOPMAssertionRelease(idleAssertion) }
        if systemAssertion != 0 { IOPMAssertionRelease(systemAssertion) }
        displayAssertion = 0
        idleAssertion = 0
        systemAssertion = 0
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
    }
}

private final class ShieldWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Sarmalı kalkan yazısı: `sizeToFit` tek satır yüksekliği verdiği için
/// ikinci satır kırpılıyordu. Genişliğe göre yüksekliği kendisi hesaplar.
private final class ShieldLabel: NSTextField {
    override var intrinsicContentSize: NSSize {
        let width = preferredMaxLayoutWidth > 0 ? preferredMaxLayoutWidth : bounds.width
        guard width > 0 else { return super.intrinsicContentSize }
        return sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude))
    }

    override func layout() {
        super.layout()
        if bounds.width > 0, abs(preferredMaxLayoutWidth - bounds.width) > 0.5 {
            preferredMaxLayoutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }
}

private final class CleaningShield {
    private var windows: [ShieldWindow] = []
    private var buttons: [NSButton] = []
    private var onUnlock: (() -> Void)?

    var unlockRects: [NSRect] {
        buttons.compactMap { button in
            guard let window = button.window else { return nil }
            let local = button.convert(button.bounds.insetBy(dx: -8, dy: -8), to: nil)
            return window.convertToScreen(local)
        }
    }

    func show(copy: DeviceModes.CleaningCopy, onUnlock: @escaping () -> Void) {
        hide()
        self.onUnlock = onUnlock
        let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) - 1)
        for screen in NSScreen.screens {
            let window = ShieldWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.title = copy.title
            window.level = level
            window.isOpaque = false
            window.backgroundColor = NSColor.black.withAlphaComponent(0.72)
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.animationBehavior = .none
            window.acceptsMouseMovedEvents = true
            window.isReleasedWhenClosed = false
            window.sharingType = .none
            window.isExcludedFromWindowsMenu = true

            let root = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            root.wantsLayer = true
            root.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor

            let stackWidth = min(560, max(320, screen.frame.width - 96))
            let label = makeShieldLabel(
                copy.title,
                font: .systemFont(ofSize: 32, weight: .semibold),
                color: .white,
                wrapping: true,
                width: stackWidth
            )
            let hint = makeShieldLabel(
                copy.hint,
                font: .systemFont(ofSize: 16, weight: .regular),
                color: NSColor.white.withAlphaComponent(0.95),
                wrapping: true,
                width: stackWidth
            )

            let button = NSButton(title: copy.buttonTitle, target: self, action: #selector(unlock))
            button.bezelStyle = .rounded
            button.controlSize = .large
            button.keyEquivalent = ""
            button.setContentHuggingPriority(.required, for: .vertical)
            button.setContentCompressionResistancePriority(.required, for: .vertical)

            let stack = NSStackView(views: [label, hint, button])
            stack.orientation = .vertical
            stack.alignment = .centerX
            stack.distribution = .fill
            stack.spacing = 14
            stack.setCustomSpacing(26, after: hint)
            stack.translatesAutoresizingMaskIntoConstraints = false

            root.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
                stack.widthAnchor.constraint(equalToConstant: stackWidth),
                stack.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 32),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -32),
                label.widthAnchor.constraint(equalTo: stack.widthAnchor),
                hint.widthAnchor.constraint(equalTo: stack.widthAnchor)
            ])

            window.contentView = root
            window.setFrame(screen.frame, display: true)
            windows.append(window)
            buttons.append(button)
        }
        raise()
    }

    private func makeShieldLabel(
        _ string: String,
        font: NSFont,
        color: NSColor,
        wrapping: Bool,
        width: CGFloat
    ) -> NSTextField {
        let field = ShieldLabel(wrappingLabelWithString: string)
        field.font = font
        field.textColor = color
        field.alignment = .center
        field.drawsBackground = false
        field.isBezeled = false
        field.isEditable = false
        field.isSelectable = false
        field.usesSingleLineMode = !wrapping
        field.lineBreakMode = wrapping ? .byWordWrapping : .byTruncatingTail
        field.maximumNumberOfLines = wrapping ? 0 : 1
        field.preferredMaxLayoutWidth = width
        field.cell?.wraps = wrapping
        field.cell?.isScrollable = false
        field.cell?.truncatesLastVisibleLine = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.required, for: .vertical)
        return field
    }

    func raise() {
        NSApp.activate(ignoringOtherApps: true)
        if let first = windows.first {
            first.makeKeyAndOrderFront(nil)
        }
        for window in windows {
            window.orderFrontRegardless()
        }
    }

    func hide() {
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        buttons.removeAll()
        onUnlock = nil
    }

    @objc private func unlock() {
        let action = onUnlock
        hide()
        action?()
    }
}

extension Notification.Name {
    static let halCleaningEnded = Notification.Name("hal.cleaningEnded")
}
