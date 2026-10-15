import SwiftUI
import AppKit
final class Runner: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        let store = AppStore()
        store.settings.trackMedication = true; store.settings.trackIntake = true
        store.settings.trackWorkout = true; store.settings.trackDua = true
        store.settings.trackQuran = true
        store.settings.duaList = [DuaItem(name: "Sabah zikri")]
        store.settings.medications = [
            Medication(name: "D3K2 + OMEGA3", dose: "1 tablet", times: [11*60+41]),
            Medication(name: "MAGNEZYUM", dose: "1 tablet", times: [9*60, 21*60])
        ]
        print("— tüm bölümler —")
        for t in SettingsTab.allCases {
            let host = NSHostingController(rootView: SettingsView(initialTab: t).environmentObject(store))
            let win = NSWindow(contentViewController: host)
            win.setContentSize(NSSize(width: 700, height: 640))
            win.orderFront(nil)
            host.view.layoutSubtreeIfNeeded()
            print("  \(t.title.padding(toLength: 12, withPad: " ", startingAt: 0)) ok")
            win.orderOut(nil)
        }
        print("\n— ilaç mantığı —")
        print("  dozlar: \(store.todayDoses.map { "\($0.clock) \($0.medication.name)" })")
        print("  boş saat: \(Medication.clock(store.settings.medications[1].nextFreeTime()))  (09:00/21:00 dolu)")
        exit(0)
    }
}
let app = NSApplication.shared
let r = Runner(); app.delegate = r
app.setActivationPolicy(.accessory); app.run()
