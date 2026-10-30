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
    static let popoverWidth: CGFloat = 360
    /// Dış boşluk 12+12 ve kart boşluğu 10+10.
    static let popoverPageWidth: CGFloat = 316
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
    private static let lock = NSLock()
    private static var cached: AppLanguage?
    private static let clockFormatter = DateFormatter()
    private static let resetFormatter = DateFormatter()
    private static let longDateFormatter = DateFormatter()
    private static let weekdayFormatter = DateFormatter()
    private static let weekdayShortFormatter = DateFormatter()

    /// Dosya ve ağ anahtarları için sabit. Ekran dili bunu değiştirmez.
    private static let headerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "E d MMM  HH.mm"
        return f
    }()

    private static func prepareLocked(language: AppLanguage, locale: Locale) {
        guard cached != language else { return }
        cached = language
        clockFormatter.locale = locale
        clockFormatter.dateFormat = "HH:mm"
        resetFormatter.locale = locale
        resetFormatter.setLocalizedDateFormatFromTemplate("Ejm")
        longDateFormatter.locale = locale
        longDateFormatter.dateFormat = "d MMMM EEEE"
        weekdayFormatter.locale = locale
        weekdayFormatter.dateFormat = "EEEEE"
        weekdayShortFormatter.locale = locale
        weekdayShortFormatter.dateFormat = "EEE"
    }

    private static func withFormatters<T>(_ body: () -> T) -> T {
        let language = Language.resolved
        let locale = Language.locale
        lock.lock()
        defer { lock.unlock() }
        prepareLocked(language: language, locale: locale)
        return body()
    }

    static func clock(_ date: Date) -> String {
        withFormatters { clockFormatter.string(from: date) }
    }

    static func header(_ date: Date) -> String {
        headerFormatter.string(from: date)
    }

    static func remaining(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            let rest = hours % 24
            return Language.isEnglish ? "\(days)d \(rest)h" : "\(days)g \(rest)s"
        }
        if hours > 0 {
            return Language.isEnglish ? "\(hours)h \(minutes)m" : "\(hours)s \(minutes)dk"
        }
        let shown = max(minutes, 1)
        return Language.isEnglish ? "\(shown)m" : "\(shown)dk"
    }

    static func weekdayInitial(_ date: Date) -> String {
        withFormatters { weekdayFormatter.string(from: date) }
    }

    static func weekdayShort(_ date: Date) -> String {
        withFormatters { weekdayShortFormatter.string(from: date) }
    }

    /// Bugün / Dün / kısa gün adı. Gün sonu tarih seçiminde kullanılır.
    static func relativeDay(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return L("Bugün", "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return L("Dün", "Yesterday")
        }
        return weekdayShort(date)
    }

    static func longDate(_ date: Date) -> String {
        withFormatters { longDateFormatter.string(from: date) }
    }

    /// Türkçe "3s 42dk", İngilizce "3h 42m".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return Language.isEnglish ? "\(hours)h \(minutes)m" : "\(hours)s \(minutes)dk"
        }
        return Language.isEnglish ? "\(minutes)m" : "\(minutes)dk"
    }

    static func resetPhrase(_ date: Date?) -> String {
        guard let date else { return "" }
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return L("Sıfırlandı", "Reset") }
        if interval < 6 * 3600 {
            return Lf("%1$@ içinde sıfırlanır", "Resets in %1$@", remaining(interval))
        }
        let stamp = withFormatters { resetFormatter.string(from: date) }
        return Lf("%1$@ sıfırlanır", "Resets %1$@", stamp)
    }
}
