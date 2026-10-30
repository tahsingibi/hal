import AppKit
import Carbon

/// Take over only matching native window-switching keys, only while a working
/// input tap owns them. Restore on recording end, secure input, disable and quit.
@MainActor
final class SwitcherSystemKeys {
    private typealias SetEnabled = @convention(c) (Int32, Bool) -> CGError
    private typealias IsEnabled = @convention(c) (Int32) -> Bool
    private typealias GetValue = @convention(c) (Int32, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>) -> CGError
    private let setEnabled = SwitcherWindowQuery.symbol("CGSSetSymbolicHotKeyEnabled").map { unsafeBitCast($0, to: SetEnabled.self) }
    private let isEnabled = SwitcherWindowQuery.symbol("CGSIsSymbolicHotKeyEnabled").map { unsafeBitCast($0, to: IsEnabled.self) }
    private let getValue = SwitcherWindowQuery.symbol("CGSGetSymbolicHotKeyValue").map { unsafeBitCast($0, to: GetValue.self) }
    private var owned: Set<Int32> = []
    private let marker = "hal.switcher.nativeKeysToRestore"
    init() {
        for id in UserDefaults.standard.array(forKey: marker) as? [Int] ?? [] {
            if let id = Int32(exactly: id), setEnabled?(id, true) == .success { continue }
            if let id = Int32(exactly: id) { owned.insert(id) }
        }
        persist()
    }
    func sync(_ prefs: SwitcherPreferences, recording: Bool, live: Bool) {
        guard let getValue, let isEnabled, let setEnabled else { return }
        var wanted = Set<Int32>()
        if live && !IsSecureEventInputEnabled() && (recording || (prefs.enabled && prefs.takeOverSystemShortcuts)) {
            // WindowServer’s app-forward, app-backward and window-cycle IDs.
            for id: Int32 in [1, 2, 27, 220] {
                var character: UInt32 = 0, code: UInt32 = 0, flags: UInt32 = 0
                guard getValue(id, &character, &code, &flags) == .success, code < 128 else { continue }
                let key = SwitcherKey(code: UInt16(code), modifiers: UInt64(flags) & SwitcherKey.mask)
                guard key.isSystem else { continue }
                if recording || prefs.shortcuts.contains(where: { $0.1.matches(code: key.code, flags: key.modifiers) }) { wanted.insert(id) }
            }
        }
        for id in owned.subtracting(wanted) {
            if setEnabled(id, true) == .success { owned.remove(id); persist() }
        }
        for id in wanted where !owned.contains(id) && isEnabled(id) {
            owned.insert(id); persist() // write before changing WindowServer state
            if setEnabled(id, false) != .success { owned.remove(id); persist() }
        }
    }
    func restore() {
        for id in Array(owned) where setEnabled?(id, true) == .success { owned.remove(id) }
        persist()
    }
    private func persist() {
        if owned.isEmpty { UserDefaults.standard.removeObject(forKey: marker) }
        else { UserDefaults.standard.set(owned.map(Int.init).sorted(), forKey: marker) }
    }
}
