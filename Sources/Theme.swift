import SwiftUI
import AppKit

enum Theme {
    static let text = Color.primary
    static let muted = Color.secondary
    static let dim = Color.secondary.opacity(0.8)

    static func barColor(percent: Double) -> Color {
        if percent >= 0.9 { return Color(hex: "E85D4C") }
        if percent >= 0.7 { return Color(hex: "E8A04A") }
        if percent >= 0.4 { return Color(hex: "E8C84A") }
        return Color(hex: "5BC48A")
    }
}

enum MenuBarLayout {
    static let height: CGFloat = 22
    static let ring: CGFloat = 15
    static let ringLine: CGFloat = 2.2
    static let ringSymbol: CGFloat = 7
    static let itemSpacing: CGFloat = 8
    static let percentFont: CGFloat = 10
    static let popoverWidth: CGFloat = 336
    static let popoverPageWidth: CGFloat = 308
    /// Sayfa içeriğinin alabileceği en fazla yükseklik. Üstünde sayfa kendi içinde kayar.
    /// Ekran alçaksa daha da kısalır; popover menü çubuğunun altına sığmalı.
    static var popoverMaxContentHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return max(220, min(440, screen - 280))
    }
    static let popoverMinContentHeight: CGFloat = 170

    static func stripWidth(itemCount: Int) -> CGFloat {
        if itemCount <= 0 { return 26 }
        let item = ring + 3 + 28
        return 6 + CGFloat(itemCount) * item + CGFloat(itemCount - 1) * itemSpacing
    }
}

extension NSScreen {
    var menuBarHeight: CGFloat {
        max(frame.maxY - visibleFrame.maxY, 24)
    }

    var hasNotch: Bool {
        if #available(macOS 12.0, *) {
            return (auxiliaryTopLeftArea?.width ?? 0) > 0 && (auxiliaryTopRightArea?.width ?? 0) > 0
        }
        return false
    }

    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static var preferred: NSScreen {
        NSScreen.main ?? screens.first!
    }

    static func matching(displayID: UInt32) -> NSScreen? {
        guard displayID != 0 else { return nil }
        return screens.first { $0.displayID == displayID }
    }
}

enum TimeFormatters {
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let headerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "E d MMM  HH.mm"
        return f
    }()

    private static let resetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "E h:mm a"
        return f
    }()

    static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    static func header(_ date: Date) -> String {
        headerFormatter.string(from: date)
    }

    static func remaining(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours >= 24 {
            return "\(hours / 24)g \(hours % 24)s"
        }
        if hours > 0 {
            return "\(hours)s \(minutes)dk"
        }
        return "\(max(minutes, 1)) min"
    }

    private static let longDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM EEEE"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "EEEEE"
        return f
    }()

    static func weekdayInitial(_ date: Date) -> String {
        weekdayFormatter.string(from: date)
    }

    private static let weekdayShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "EEE"
        return f
    }()

    static func weekdayShort(_ date: Date) -> String {
        weekdayShortFormatter.string(from: date)
    }

    /// Bugün / Dün / kısa gün adı. Gün sonu tarih seçiminde kullanılır.
    static func relativeDay(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Bugün" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Dün"
        }
        return weekdayShort(date)
    }

    static func longDate(_ date: Date) -> String {
        longDateFormatter.string(from: date)
    }

    /// "3s 42dk" / "42dk" / "12dk" biçiminde süre.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)s \(minutes)dk" }
        return "\(minutes)dk"
    }

    static func resetPhrase(_ date: Date?) -> String {
        guard let date else { return "" }
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "Reset" }
        if interval < 6 * 3600 {
            return "Resets in \(remaining(interval))"
        }
        return "Resets \(resetFormatter.string(from: date))"
    }
}
