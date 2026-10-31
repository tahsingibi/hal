import Foundation
import AppKit

/// Run using scripts/verify-settings.sh; never opens AppStore or touches user preferences.
@main
struct SettingsLocalizationTests {
    @MainActor static func main() throws {
        let decoder = JSONDecoder()
        let defaults = try decoder.decode(AppSettings.self, from: Data("{}".utf8))
        precondition(defaults.moduleOrder.isEmpty && !defaults.compactPanel)
        precondition(defaults.enabledModules == ModuleKind.dashboardCases)
        precondition(defaults.language == .system)
        precondition(!defaults.switcher.enabled && !defaults.displayControlsEnabled)
        precondition(defaults.switcher.appShortcut == .apps)
        precondition(defaults.menuBarCollapsed)
        let explicitOff = try decoder.decode(AppSettings.self, from: Data(#"{"menuBarCollapsed":false}"#.utf8))
        precondition(!explicitOff.menuBarCollapsed)
        precondition(QuotaRotation.next(in: ["claude", "codex", "grok"], after: "claude") == "codex")
        precondition(QuotaRotation.next(in: ["claude", "codex", "grok"], after: "grok") == "claude")
        precondition(QuotaRotation.next(in: ["claude"], after: "removed") == "claude")
        precondition(QuotaRotation.next(in: [], after: "claude") == nil)
        let migrated = try decoder.decode(SwitcherPreferences.self, from: Data(#"{"enabled":true,"shortcut":"controlShiftSpace","showMinimized":false,"includeAppsWithoutWindows":true}"#.utf8))
        precondition(migrated.appShortcut == SwitcherShortcut.controlShiftSpace.key && migrated.minimized == .hidden && migrated.windowless == .all)
        let invalidKey = try decoder.decode(SwitcherPreferences.self, from: Data(#"{"appShortcut":{"code":48,"modifiers":0},"appearanceDelay":-10,"maxColumns":500}"#.utf8))
        precondition(invalidKey.appShortcut == .apps && invalidKey.appearanceDelay == 0 && invalidKey.maxColumns == 12)
        precondition(SwitcherKey.apps.matches(code: 48, flags: SwitcherKey.apps.modifiers | CGEventFlags.maskShift.rawValue))
        precondition(!SwitcherKey.apps.matches(code: 48, flags: CGEventFlags.maskCommand.rawValue))
        precondition(!SwitcherKey(code: 48, modifiers: CGEventFlags.maskShift.rawValue).isValid)
        precondition(SwitcherInput.shouldCommit(flags: 0, required: SwitcherKey.apps.holdMask, pinned: false))
        precondition(!SwitcherInput.shouldCommit(flags: SwitcherKey.apps.modifiers | CGEventFlags.maskShift.rawValue, required: SwitcherKey.apps.holdMask, pinned: false))
        precondition(!SwitcherInput.shouldCommit(flags: 0, required: SwitcherKey.apps.holdMask, pinned: true))
        precondition(!SwitcherInput.shouldCommit(flags: 0, required: 0, pinned: false))
        // Granting permission later must reconnect without reopening Settings;
        // healthy taps, recording and secure input must not trigger restarts.
        precondition(SwitcherInput.shouldReconnect(permissionGranted: true, wasGranted: false, live: false, recording: false, secureInput: false))
        precondition(SwitcherInput.shouldReconnect(permissionGranted: false, wasGranted: true, live: true, recording: false, secureInput: false))
        precondition(SwitcherInput.shouldReconnect(permissionGranted: true, wasGranted: true, live: false, recording: false, secureInput: false))
        precondition(!SwitcherInput.shouldReconnect(permissionGranted: false, wasGranted: false, live: false, recording: false, secureInput: false))
        precondition(!SwitcherInput.shouldReconnect(permissionGranted: true, wasGranted: true, live: true, recording: false, secureInput: false))
        precondition(!SwitcherInput.shouldReconnect(permissionGranted: true, wasGranted: true, live: false, recording: true, secureInput: false))
        precondition(!SwitcherInput.shouldReconnect(permissionGranted: true, wasGranted: true, live: false, recording: false, secureInput: true))
        precondition(WindowSwitcher.wrappedIndex(-1, count: 3) == 2)
        precondition(WindowSwitcher.wrappedIndex(3, count: 3) == 0)
        precondition(WindowSwitcher.wrappedIndex(3, count: 0) == 0)
        func window(_ id: String, pid: pid_t, title: String, minimized: Bool = false) -> SwitcherWindow {
            SwitcherWindow(id: id, pid: pid, bundleID: "test", appName: "App \(pid)", title: title, icon: NSImage(size: NSSize(width: 1, height: 1)), element: nil, windowID: nil, minimized: minimized, fullscreen: false, frame: nil, order: 0)
        }
        let rows = [window("a", pid: 1, title: "First"), window("b", pid: 1, title: "Second"), window("c", pid: 2, title: "Third", minimized: true)]
        var filters = SwitcherPreferences()
        precondition(WindowSwitcher.displayRows(rows, scope: .currentApp, scopePID: 1, preferences: filters, query: "").map(\.id) == ["a", "b"])
        filters.layout = .icons
        precondition(WindowSwitcher.displayRows(rows, scope: .apps, scopePID: nil, preferences: filters, query: "").map(\.id) == ["a", "c"])
        precondition(WindowSwitcher.displayRows(rows, scope: .allWindows, scopePID: nil, preferences: filters, query: "").count == 3)
        precondition(WindowSwitcher.displayRows(rows, scope: .apps, scopePID: nil, preferences: filters, query: "Second").first?.id == "b")
        filters.minimized = .last
        precondition(WindowSwitcher.displayRows(Array(rows.reversed()), scope: .allWindows, scopePID: nil, preferences: filters, query: "").last?.id == "c")

        // Preserve earlier settings, reject stale module IDs and deduplicate order.
        let legacy = Data(#"{"disabledModules":["focus","today"],"displayName":"Ada","language":"tr"}"#.utf8)
        var settings = try decoder.decode(AppSettings.self, from: legacy)
        precondition(settings.displayName == "Ada" && settings.isModuleEnabled(.today))
        precondition(!settings.enabledModules.contains(.focus))
        settings.moduleOrder = ["money", "obsolete", "money", "today", "usage"]
        settings.compactPanel = true
        precondition(settings.orderedModules.prefix(3) == [.money, .today, .usage])
        precondition(Set(settings.orderedModules).count == ModuleKind.dashboardCases.count)
        settings.switcher.enabled = true
        settings.switcher.layout = .previews
        settings.switcher.shortcut = .optionTab
        settings.switcher.showMinimized = false
        settings.displayControlsEnabled = true
        let restored = try decoder.decode(AppSettings.self, from: JSONEncoder().encode(settings))
        precondition(restored == settings && restored.compactPanel)
        precondition(restored.enabledModules.first == .money)
        precondition(restored.switcher.enabled && restored.switcher.layout == .previews && restored.switcher.shortcut == .optionTab)
        precondition(!restored.switcher.showMinimized && restored.displayControlsEnabled)
        precondition(Set(SwitcherShortcut.allCases.map(\.id)).count == SwitcherShortcut.allCases.count)

        // Invalid/extreme values cannot black out a display or overflow the panel.
        precondition(DisplayController.clampedLevel(-10, hardware: true) == 0.05)
        precondition(DisplayController.clampedLevel(-10, hardware: false) == 0.2)
        precondition(DisplayController.clampedLevel(10, hardware: true) == 1)
        precondition(DisplayController.clampedLevel(.nan, hardware: false) == 1)

        // Homebrew dependencies and upgrades are identified from metadata, not
        // guessed from package names or the presence of an Upgrade button.
        let metadata: [[String: Any]] = [
            ["name": "library", "installed": [["installed_on_request": false]], "outdated": true, "dependencies": ["dep"], "desc": "Library"],
            ["name": "tool", "installed": [["installed_on_request": true]], "outdated": false]
        ]
        let packages = HomebrewService.detailedPackages(metadata, cask: false, fallback: [BrewPackage(name: "library", version: "1.2", cask: false)])
        precondition(packages.count == 2 && packages[0].isDependency && packages[0].outdated)
        precondition(packages[0].version == "1.2" && packages[0].dependencies == ["dep"])
        precondition(!packages[1].isDependency && !packages[1].outdated)
        var options = UpdateOptions()
        options.includeBrew = false; options.intervalDays = 7
        let restoredOptions = try decoder.decode(UpdateOptions.self, from: JSONEncoder().encode(options))
        precondition(restoredOptions == options)

        // Both languages must come from packaged native catalogs, including
        // English keys with distinct Turkish meanings in different contexts.
        for language in [LanguageChoice.tr, .en] {
            Language.apply(language)
            let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj")!
            let bundle = Bundle(path: path)!
            precondition(bundle.localizedString(forKey: "Features", value: nil, table: nil) == (language == .tr ? "Katalog testi" : "Features"))
            precondition(L("İbadet", "Prayer") == (language == .tr ? "İbadet" : "Prayer"))
            precondition(L("Namaz", "Prayer") == (language == .tr ? "Namaz" : "Prayer"))
            precondition(LInDays(3) == (language == .tr ? "3 gün sonra" : "in 3 days"))
            precondition(Language.locale.identifier == (language == .tr ? "tr_TR" : "en_US"))
            let native = bundle.localizedString(forKey: "NSAudioCaptureUsageDescription", value: nil, table: "InfoPlist")
            precondition(native != "NSAudioCaptureUsageDescription")
        }
        // A deliberately distinct translation in the test bundle proves L reads
        // the resource rather than simply returning the inline Turkish fallback.
        Language.apply(.tr)
        precondition(L("Özellikler", "Features") == "Katalog testi")
        Language.apply(.en)
        precondition(L("Özellikler", "Features") == "Features")
        Language.apply(.tr)
        precondition(L("Özellikler", "Features") == "Katalog testi")
        precondition(L("Katalogda yok", "Uncatalogued text") == "Katalogda yok")
        print("PASS: quota cycling, shortcut migration/matching/release, switcher scopes/grouping/search/order, settings persistence, brightness bounds and localization")
    }
}
