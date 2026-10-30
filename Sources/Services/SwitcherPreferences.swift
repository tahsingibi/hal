import AppKit
import Carbon

struct SwitcherKey: Codable, Equatable, Hashable, Sendable {
    var code: UInt16
    var modifiers: UInt64
    static let mask = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue
    static let apps = SwitcherKey(code: 48, modifiers: CGEventFlags.maskAlternate.rawValue)
    static let windows = SwitcherKey(code: 50, modifiers: CGEventFlags.maskAlternate.rawValue)
    static let all = SwitcherKey(code: 48, modifiers: CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskControl.rawValue)
    var holdMask: UInt64 { modifiers & ~CGEventFlags.maskShift.rawValue }
    var isValid: Bool { holdMask != 0 && code < 128 }
    var isSystem: Bool { modifiers & ~CGEventFlags.maskShift.rawValue == CGEventFlags.maskCommand.rawValue && [48, 50].contains(code) }
    func matches(code: UInt16, flags: UInt64) -> Bool {
        self.code == code && (flags & Self.mask & ~CGEventFlags.maskShift.rawValue) == (modifiers & ~CGEventFlags.maskShift.rawValue)
        && (modifiers & CGEventFlags.maskShift.rawValue == 0 || flags & CGEventFlags.maskShift.rawValue != 0)
    }
    var title: String {
        var text = ""
        for (flag, glyph) in [(CGEventFlags.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"), (.maskCommand, "⌘")] {
            if modifiers & flag.rawValue != 0 { text += glyph }
        }
        return text + Self.label(code)
    }
    static func label(_ code: UInt16) -> String {
        let special: [UInt16: String] = [48:"⇥",49:"Space",50:"`",36:"↩",51:"⌫",53:"Esc",123:"←",124:"→",125:"↓",126:"↑",76:"⌤",115:"Home",119:"End",116:"PgUp",121:"PgDn"]
        if let value = special[code] { return value }
        let fkeys: [UInt16:Int] = [122:1,120:2,99:3,118:4,96:5,97:6,98:7,100:8,101:9,109:10,103:11,111:12,105:13,107:14,113:15,106:16,64:17,79:18,80:19,90:20]
        if let number = fkeys[code] { return "F\(number)" }
        return character(code, shift: false).uppercased()
    }
    /// Translate the physical key with only Shift, so holding Option does not
    /// insert symbols into the switcher's search field on non-US keyboards.
    static func character(_ code: UInt16, shift: Bool) -> String {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "" }
        let data = unsafeBitCast(raw, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(data) else { return "" }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var state: UInt32 = 0, length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        let result = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), shift ? UInt32(shiftKey >> 8) : 0,
                                    UInt32(LMGetKbdType()), OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &state,
                                    buffer.count, &length, &buffer)
        guard result == noErr, length > 0 else { return "" }
        return String(utf16CodeUnits: buffer, count: length)
    }
}

enum SwitcherLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case previews, icons, list
    var id: String { rawValue }
    var title: String {
        switch self { case .previews: return L("Pencere önizlemeleri", "Window previews"); case .icons: return L("Büyük simgeler", "Large icons"); case .list: return L("Basit liste", "Simple list") }
    }
    var detail: String {
        switch self {
        case .previews: return L("Her pencereyi kendi görüntüsüyle gösterir.", "Shows each window with its own preview.")
        case .icons: return L("Uygulama simgeleri ve seçili uygulamanın pencereleri.", "App icons with windows of the selected app.")
        case .list: return L("Simgeler ve başlıklar. Ekran yakalama kullanmaz.", "Icons and titles. Does not capture the screen.")
        }
    }
}
enum SwitcherMinimized: String, Codable, CaseIterable { case normal, last, hidden }
enum SwitcherPlacement: String, Codable, CaseIterable { case pointer, menuBar, activeWindow }
enum SwitcherWindowless: String, Codable, CaseIterable { case none, finder, all }
enum SwitcherPreviewSize: String, Codable, CaseIterable {
    case small, normal, large, extraLarge
    var width: CGFloat { switch self { case .small: return 172; case .normal: return 220; case .large: return 280; case .extraLarge: return 340 } }
}
enum SwitcherScope: Int, Sendable { case apps = 1, currentApp, allWindows }

// Retained solely to migrate preferences written by earlier Hâl builds.
enum SwitcherShortcut: String, Codable, CaseIterable, Identifiable, Sendable {
    case controlOptionTab, optionTab, controlShiftSpace
    var id: String { rawValue }
    var key: SwitcherKey {
        switch self {
        case .controlOptionTab: return .all
        case .optionTab: return .apps
        case .controlShiftSpace: return SwitcherKey(code: 49, modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue)
        }
    }
    var title: String { key.title }
}

struct SwitcherPreferences: Codable, Equatable, Sendable {
    var enabled = false
    var layout = SwitcherLayout.previews
    var appShortcut = SwitcherKey.apps
    var windowShortcut = SwitcherKey.windows
    var allWindowsShortcut = SwitcherKey.all
    var allWindowsEnabled = false
    var takeOverSystemShortcuts = false
    var appearanceDelay = 100
    var maxColumns = 0
    var instantSelection = false
    var pinSearch = false
    var mergeWindows = false
    var showFullscreen = true
    var minimized = SwitcherMinimized.normal
    var placement = SwitcherPlacement.pointer
    var currentScreenOnly = false
    var currentSpaceOnly = false
    var windowless = SwitcherWindowless.finder
    var previewSize = SwitcherPreviewSize.normal
    var minimalPreviews = false
    var excludedApps: [String] = []
    var previewExcludedApps: [String] = []
    var shortcut: SwitcherShortcut {
        get { SwitcherShortcut.allCases.first { $0.key == appShortcut } ?? .controlOptionTab }
        set { appShortcut = newValue.key }
    }
    var showMinimized: Bool { get { minimized != .hidden } set { minimized = newValue ? .normal : .hidden } }
    var includeAppsWithoutWindows: Bool { get { windowless != .none } set { windowless = newValue ? .all : .none } }
    enum CodingKeys: String, CodingKey {
        case enabled, layout, appShortcut, windowShortcut, allWindowsShortcut, allWindowsEnabled, takeOverSystemShortcuts
        case appearanceDelay, maxColumns, instantSelection, pinSearch, mergeWindows, showFullscreen, minimized, placement
        case currentScreenOnly, currentSpaceOnly, windowless, previewSize, minimalPreviews, excludedApps, previewExcludedApps
        case shortcut, showMinimized, includeAppsWithoutWindows
    }
    init() {}
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        layout = (try? c.decode(SwitcherLayout.self, forKey: .layout)) ?? layout
        appShortcut = (try? c.decode(SwitcherKey.self, forKey: .appShortcut)) ?? (try? c.decode(SwitcherShortcut.self, forKey: .shortcut))?.key ?? .apps
        windowShortcut = (try? c.decode(SwitcherKey.self, forKey: .windowShortcut)) ?? .windows
        allWindowsShortcut = (try? c.decode(SwitcherKey.self, forKey: .allWindowsShortcut)) ?? .all
        allWindowsEnabled = try c.decodeIfPresent(Bool.self, forKey: .allWindowsEnabled) ?? false
        takeOverSystemShortcuts = try c.decodeIfPresent(Bool.self, forKey: .takeOverSystemShortcuts) ?? false
        appearanceDelay = min(500, max(0, try c.decodeIfPresent(Int.self, forKey: .appearanceDelay) ?? 100))
        maxColumns = min(12, max(0, try c.decodeIfPresent(Int.self, forKey: .maxColumns) ?? 0))
        instantSelection = try c.decodeIfPresent(Bool.self, forKey: .instantSelection) ?? false
        pinSearch = try c.decodeIfPresent(Bool.self, forKey: .pinSearch) ?? false
        mergeWindows = try c.decodeIfPresent(Bool.self, forKey: .mergeWindows) ?? false
        showFullscreen = try c.decodeIfPresent(Bool.self, forKey: .showFullscreen) ?? true
        minimized = (try? c.decode(SwitcherMinimized.self, forKey: .minimized)) ?? (((try? c.decode(Bool.self, forKey: .showMinimized)) ?? true) ? .normal : .hidden)
        placement = (try? c.decode(SwitcherPlacement.self, forKey: .placement)) ?? .pointer
        currentScreenOnly = try c.decodeIfPresent(Bool.self, forKey: .currentScreenOnly) ?? false
        currentSpaceOnly = try c.decodeIfPresent(Bool.self, forKey: .currentSpaceOnly) ?? false
        windowless = (try? c.decode(SwitcherWindowless.self, forKey: .windowless)) ?? ((try? c.decode(Bool.self, forKey: .includeAppsWithoutWindows)).map { $0 ? .all : .none } ?? .finder)
        previewSize = (try? c.decode(SwitcherPreviewSize.self, forKey: .previewSize)) ?? .normal
        minimalPreviews = try c.decodeIfPresent(Bool.self, forKey: .minimalPreviews) ?? false
        excludedApps = try c.decodeIfPresent([String].self, forKey: .excludedApps) ?? []
        previewExcludedApps = try c.decodeIfPresent([String].self, forKey: .previewExcludedApps) ?? []
        if !appShortcut.isValid { appShortcut = .apps }
        if !windowShortcut.isValid { windowShortcut = .windows }
        if !allWindowsShortcut.isValid { allWindowsShortcut = .all }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled); try c.encode(layout, forKey: .layout)
        try c.encode(appShortcut, forKey: .appShortcut); try c.encode(windowShortcut, forKey: .windowShortcut)
        try c.encode(allWindowsShortcut, forKey: .allWindowsShortcut); try c.encode(allWindowsEnabled, forKey: .allWindowsEnabled)
        try c.encode(takeOverSystemShortcuts, forKey: .takeOverSystemShortcuts)
        try c.encode(appearanceDelay, forKey: .appearanceDelay); try c.encode(maxColumns, forKey: .maxColumns)
        try c.encode(instantSelection, forKey: .instantSelection); try c.encode(pinSearch, forKey: .pinSearch)
        try c.encode(mergeWindows, forKey: .mergeWindows); try c.encode(showFullscreen, forKey: .showFullscreen)
        try c.encode(minimized, forKey: .minimized); try c.encode(placement, forKey: .placement)
        try c.encode(currentScreenOnly, forKey: .currentScreenOnly); try c.encode(currentSpaceOnly, forKey: .currentSpaceOnly)
        try c.encode(windowless, forKey: .windowless); try c.encode(previewSize, forKey: .previewSize)
        try c.encode(minimalPreviews, forKey: .minimalPreviews); try c.encode(excludedApps, forKey: .excludedApps)
        try c.encode(previewExcludedApps, forKey: .previewExcludedApps)
    }
    var shortcuts: [(SwitcherScope, SwitcherKey)] {
        var values: [(SwitcherScope, SwitcherKey)] = [(.apps, appShortcut), (.currentApp, windowShortcut)]
        if allWindowsEnabled { values.append((.allWindows, allWindowsShortcut)) }
        return values
    }
}
