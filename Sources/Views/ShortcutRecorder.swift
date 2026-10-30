import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var key: SwitcherKey
    var onRecording: (Bool) -> Void = { _ in }
    var onError: (String?) -> Void = { _ in }
    func makeNSView(context: Context) -> ShortcutField {
        let button = ShortcutField()
        button.bezelStyle = .rounded; button.setButtonType(.momentaryPushIn)
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.target = button; button.action = #selector(ShortcutField.startRecording)
        updateNSView(button, context: context)
        return button
    }
    func updateNSView(_ view: ShortcutField, context: Context) {
        view.key = key; view.capture = { key = $0 }; view.recordingChanged = onRecording; view.failure = onError
        if !view.recording { view.title = key.title }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ShortcutField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 150, height: 27)
    }
    static func dismantleNSView(_ nsView: ShortcutField, coordinator: ()) { nsView.finish() }
}
final class ShortcutField: NSButton {
    var key = SwitcherKey.apps
    var capture: ((SwitcherKey) -> Void)?
    var failure: ((String?) -> Void)?
    var recordingChanged: ((Bool) -> Void)?
    private(set) var recording = false
    private var keys: Any?
    private var focusObserver: Any?
    override var acceptsFirstResponder: Bool { true }
    @objc func startRecording() {
        guard !recording, window?.makeFirstResponder(self) == true else { return }
        recording = true; title = L("Tuşlara bas…", "Press keys…"); failure?(nil); recordingChanged?(true)
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.recording else { return event }
            self.receive(event.keyCode, UInt64(event.modifierFlags.rawValue) & SwitcherKey.mask)
            return nil
        }
        SwitcherInput.shared.record { [weak self] code, flags in self?.receive(code, flags) }
        focusObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in self?.finish() }
    }
    private func receive(_ code: UInt16, _ flags: UInt64) {
        guard recording else { return }
        if code == 53 { finish(); return }
        let candidate = SwitcherKey(code: code, modifiers: flags)
        guard candidate.isValid else {
            failure?(L("⌘, ⌥ veya ⌃ ile bir tuşa bas. Esc iptal eder.", "Press a key with ⌘, ⌥ or ⌃. Escape cancels.")); return
        }
        finish(); capture?(candidate)
    }
    func finish() {
        guard recording else { return }
        recording = false; SwitcherInput.shared.record(nil)
        if let keys { NSEvent.removeMonitor(keys); self.keys = nil }
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver); self.focusObserver = nil }
        title = key.title; recordingChanged?(false)
    }
    override func resignFirstResponder() -> Bool { finish(); return super.resignFirstResponder() }
}
