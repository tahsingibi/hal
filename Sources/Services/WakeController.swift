import AppKit
import CoreGraphics
import Foundation
import IOKit
import IOKit.ps

/// Uyanık tutmanın koşulları. Sürekli açık, 1.0.0’daki Always Wake davranışıdır.
/// Diğer kurallar ancak sürekli kapalıyken aranır; hiçbiri seçili değilse yine sürekli kalır.
@MainActor
final class WakeController: ObservableObject {
    static let shared = WakeController()

    /// Ayarlarda bir alanı düzeltmek için. AppStore atar.
    /// Ayar deposunu, verilen değişiklikle günceller. AppStore atar.
    var onPatch: (((inout AppSettings) -> Void) -> Void)?

    @Published private(set) var holding = false
    @Published private(set) var status = ""
    private var ticker: Timer?
    private var appliedMinutes = 0
    private var model = AppSettings()

    private init() {}

    func apply(_ settings: AppSettings) {
        let minutesChanged = appliedMinutes != 0 && settings.wakeTimerMinutes != appliedMinutes
        appliedMinutes = settings.wakeTimerMinutes

        let timerNeedsStart = settings.alwaysWake && settings.usesWakeTimer && (settings.wakeUntil == nil || minutesChanged)
        if timerNeedsStart {
            let until = Date().addingTimeInterval(TimeInterval(max(5, settings.wakeTimerMinutes) * 60))
            var copy = settings
            copy.wakeUntil = until
            model = copy
            evaluate()
            schedule()
            // didSet içinden gelen yama aynı turda yeniden didSet çağırmaz; kayıt bir sonraki tura kalır.
            Task { @MainActor in
                self.onPatch? { draft in
                    guard draft.alwaysWake, draft.usesWakeTimer else { return }
                    guard draft.wakeUntil == nil || minutesChanged else { return }
                    draft.wakeUntil = until
                }
            }
            return
        }

        if let until = settings.wakeUntil, until <= Date(), settings.usesWakeTimer {
            var copy = settings
            copy.wakeUntil = nil
            copy.wakeTimerEnabled = false
            if !copy.wakeWhileApps && !copy.wakeWhilePowerOrDisplay && !copy.wakeWhileLidClosed {
                copy.alwaysWake = false
            }
            model = copy
            evaluate()
            schedule()
            Task { @MainActor in
                self.onPatch? { draft in
                    guard draft.wakeUntil == until else { return }
                    draft.wakeUntil = nil
                    draft.wakeTimerEnabled = false
                    if !draft.wakeWhileApps && !draft.wakeWhilePowerOrDisplay && !draft.wakeWhileLidClosed {
                        draft.alwaysWake = false
                    }
                }
            }
            return
        }

        model = settings
        evaluate()
        schedule()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        setHolding(false)
        status = ""
    }

    private var usesConditions: Bool {
        model.alwaysWake && !model.wakeIndefinite && model.hasWakeCondition
    }

    private func schedule() {
        ticker?.invalidate()
        ticker = nil
        guard usesConditions else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        timer.tolerance = 0.4
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func evaluate() {
        if let until = model.wakeUntil, until <= Date(), model.usesWakeTimer {
            expireTimer(until: until)
            return
        }
        guard model.alwaysWake else {
            setHolding(false)
            status = L("Kapalı", "Off")
            return
        }
        if model.wakeIndefinite || !model.hasWakeCondition {
            setHolding(true)
            status = L("Sürekli", "Always")
            return
        }

        var reasons: [String] = []
        if model.usesWakeTimer, let until = model.wakeUntil, until > Date() {
            reasons.append(TimeFormatters.remaining(until.timeIntervalSinceNow))
        }
        if model.wakeWhileApps, Self.frontAppMatches(model.focusApps) {
            reasons.append(L("uygulama", "app"))
        }
        if model.wakeWhilePowerOrDisplay, Self.onPowerOrExternalDisplay() {
            reasons.append(L("güç / ekran", "power / display"))
        }
        if model.wakeWhileLidClosed, Self.lidClosed() == true {
            reasons.append(L("kapak", "lid"))
        }

        setHolding(!reasons.isEmpty)
        if reasons.isEmpty {
            status = waitingStatus()
        } else {
            status = reasons.joined(separator: " · ")
        }
    }

    private func waitingStatus() -> String {
        if model.wakeWhileLidClosed, Self.lidClosed() == nil, !model.wakeWhileApps, !model.wakeWhilePowerOrDisplay, !model.usesWakeTimer {
            return L("Bu Mac’te kapak yok", "This Mac has no lid")
        }
        return L("Koşul bekleniyor", "Waiting for a condition")
    }

    /// Sayaç süre dolduğunda koşullu denetlemede de kapanır; ayar kaydı bir sonraki tura kalır.
    private func expireTimer(until: Date) {
        var copy = model
        copy.wakeUntil = nil
        copy.wakeTimerEnabled = false
        if !copy.wakeWhileApps && !copy.wakeWhilePowerOrDisplay && !copy.wakeWhileLidClosed {
            copy.alwaysWake = false
        }
        model = copy
        evaluate()
        Task { @MainActor in
            self.onPatch? { draft in
                guard draft.wakeUntil == until else { return }
                draft.wakeUntil = nil
                draft.wakeTimerEnabled = false
                if !draft.wakeWhileApps && !draft.wakeWhilePowerOrDisplay && !draft.wakeWhileLidClosed {
                    draft.alwaysWake = false
                }
            }
        }
    }

    private func setHolding(_ on: Bool) {
        guard holding != on else { return }
        holding = on
        DeviceModes.shared.setAlwaysWake(on)
    }

    static func frontAppMatches(_ needles: [String]) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        return FocusTracker.matches(app, needles: needles)
    }

    static func onPowerOrExternalDisplay() -> Bool {
        onACPower() || hasExternalDisplay()
    }

    /// Kapak yoksa nil. 0 açık, 1 kapalı.
    static func lidClosed() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let raw = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        let value = raw.takeRetainedValue()
        if let number = value as? NSNumber { return number.intValue != 0 }
        return nil
    }

    static func onACPower() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return true }
        guard let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef], !list.isEmpty else {
            return true
        }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            let state = desc[kIOPSPowerSourceStateKey as String] as? String
            if state == kIOPSACPowerValue as String { return true }
            if state == kIOPSBatteryPowerValue as String { return false }
        }
        return true
    }

    static func hasExternalDisplay() -> Bool {
        NSScreen.screens.contains { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) == 0
        }
    }
}

extension AppSettings {
    /// Sayaç, sürekli kapalıyken anlam taşır.
    var usesWakeTimer: Bool { wakeTimerEnabled && !wakeIndefinite }

    var hasWakeCondition: Bool {
        wakeTimerEnabled || wakeWhileApps || wakeWhilePowerOrDisplay || wakeWhileLidClosed
    }
}
