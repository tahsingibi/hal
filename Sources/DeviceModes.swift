import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import IOKit.pwr_mgt

final class DeviceModes {
    static let shared = DeviceModes()

    private var displayAssertion: IOPMAssertionID = 0
    private var idleAssertion: IOPMAssertionID = 0
    private var systemAssertion: IOPMAssertionID = 0
    private var activity: NSObjectProtocol?

    private init() {}

    @MainActor
    var isCleaning: Bool { CleaningLock.shared.isActive }

    var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    struct CleaningResult {
        var active: Bool
        var message: String?
    }

    /// Temizlik ekranında görünecek başlık ve not.
    struct CleaningCopy {
        var title: String
        var note: String
        var keepScreenVisible: Bool
    }

    /// Temizlik modunu açar ya da kapatır. Klavye kilidi Erişilebilirlik izni
    /// olmadan kurulamaz; izin yoksa mod başlamaz ve kullanıcı ayara yönlendirilir.
    @MainActor
    @discardableResult
    func setCleaning(_ on: Bool, copy: CleaningCopy? = nil) -> CleaningResult {
        let lock = CleaningLock.shared
        guard on else {
            lock.requestStop()
            return CleaningResult(active: false, message: nil)
        }
        lock.onEnded = {
            NotificationCenter.default.post(name: .halCleaningEnded, object: nil)
        }
        let content = CleaningLock.Content(
            title: copy?.title ?? "",
            note: copy?.note ?? "",
            keepScreenVisible: copy?.keepScreenVisible ?? false
        )
        if lock.start(content) {
            return CleaningResult(active: true, message: nil)
        }
        if !AXIsProcessTrusted() {
            promptForAccessibility()
            return CleaningResult(active: false, message: L(
                "Klavyeyi güvenle kilitlemek için Hâl’in Erişilebilirlik iznine ihtiyacı var. İzin verip tekrar dene.",
                "Hâl needs Accessibility permission to lock the keyboard safely. Grant it and try again."
            ))
        }
        return CleaningResult(active: false, message: L(
            "Klavye kilidi kurulamadı. Hâl’i Erişilebilirlik listesinden kaldırıp yeniden ekle, sonra tekrar dene.",
            "The keyboard lock couldn’t be set up. Remove Hâl from the Accessibility list, add it again, then retry."
        ))
    }

    @MainActor
    private func promptForAccessibility() {
        let alert = NSAlert()
        alert.messageText = L("Erişilebilirlik izni gerekli", "Accessibility permission needed")
        alert.informativeText = L(
            "Temizlik modu klavyeyi kilitlemek için Hâl’in Erişilebilirlik iznine ihtiyaç duyar. İzin olmadan kilit hiç başlamaz; böylece açılamayan bir klavyeyle kalmazsın.",
            "Cleaning mode needs Accessibility permission to lock the keyboard. Without it the lock never starts, so you can’t get stuck with a keyboard you can’t unlock."
        )
        alert.addButton(withTitle: L("Ayarları aç", "Open Settings"))
        alert.addButton(withTitle: L("Vazgeç", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            requestKeyboardLockPermission()
            openAccessibilitySettings()
        }
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

    @MainActor
    func shutdown() {
        CleaningLock.shared.stopNow()
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

    /// Yalnızca kullanıcı açıkça istediğinde sistem izin sorusunu gösterir.
    func requestKeyboardLockPermission() {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(prompt)
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

extension Notification.Name {
    static let halCleaningEnded = Notification.Name("hal.cleaningEnded")
}
