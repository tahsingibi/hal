import Foundation

/// Kaydedilen dil seçimi. `system` anahtarı yokmuş gibi davranır: eski ayar dosyaları bozulmaz.
enum LanguageChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case tr
    case en

    var id: String { rawValue }

    /// Seçenek adları kendi dilinde kalır. "Sistem" o anki arayüz diline uyar.
    var title: String {
        switch self {
        case .system: return L("Sistem", "System")
        case .tr: return "Türkçe"
        case .en: return "English"
        }
    }
}

enum AppLanguage: String, Equatable, Sendable {
    case tr
    case en
}

/// Çalışma anındaki dil. `Bundle` yerelleştirmesine bağlı değildir; menü çubuğu
/// uygulaması yeniden açılmadan değişebilir.
enum Language {
    private static let lock = NSLock()
    private static var stored: LanguageChoice = .system

    static var choice: LanguageChoice {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set { apply(newValue) }
    }

    static func apply(_ choice: LanguageChoice) {
        lock.lock()
        stored = choice
        lock.unlock()
    }

    static var resolved: AppLanguage {
        switch choice {
        case .tr: return .tr
        case .en: return .en
        case .system:
            let tag = Locale.preferredLanguages.first?.lowercased() ?? ""
            return tag.hasPrefix("tr") ? .tr : .en
        }
    }

    static var isEnglish: Bool { resolved == .en }

    static var locale: Locale {
        Locale(identifier: isEnglish ? "en_US" : "tr_TR")
    }
}

func L(_ tr: String, _ en: String) -> String {
    Language.isEnglish ? en : tr
}

/// İki dil de aynı argümanları alır. Sözcük sırası değişiyorsa her iki dizgede `%1$@` / `%2$d` kullan.
func Lf(_ tr: String, _ en: String, _ args: CVarArg...) -> String {
    String(format: L(tr, en), locale: Language.locale, arguments: args)
}

func LInDays(_ days: Int) -> String {
    if days == 0 { return L("bugün", "today") }
    if days == 1 { return L("1 gün sonra", "in 1 day") }
    return Lf("%1$d gün sonra", "in %1$d days", days)
}

enum PrayerCopy {
    static func name(id: String) -> String {
        switch id {
        case "Fajr": return L("İmsak", "Fajr")
        case "Sunrise": return L("Güneş", "Sunrise")
        case "Dhuhr": return L("Öğle", "Dhuhr")
        case "Asr": return L("İkindi", "Asr")
        case "Maghrib": return L("Akşam", "Maghrib")
        case "Isha": return L("Yatsı", "Isha")
        default: return id
        }
    }
}

/// Ayarlardaki pano listesi kayda yazılmış başlığı değil, satır kimliğini gösterir.
enum SummaryCatalogCopy {
    static func title(id: String, fallback: String) -> String {
        switch id {
        case "focus": return L("Derin çalışma", "Deep work")
        case "prayer.next": return L("Sıradaki vakit", "Next prayer")
        case "prayer.done": return L("Kılınan", "Prayed")
        case "usage.best": return L("En boş kota", "Most remaining")
        case "usage.full": return L("Dolu", "Full")
        case "usage.broken": return L("Okunamıyor", "Unreadable")
        case "calendar.next": return L("Sonraki olay", "Next event")
        case "medication": return L("İlaç & Takviye", "Meds & supplements")
        case "workout": return L("Antrenman", "Workout")
        case "money.next": return L("Sıradaki ödeme", "Next payment")
        case "water": return L("Su", "Water")
        case "protein": return "Protein"
        case "dayclose": return L("Gün sonu", "End of day")
        default: return fallback
        }
    }
}

enum CountryNames {
    static func display(code: String, turkish: String) -> String {
        guard Language.isEnglish, let english = english[code.uppercased()] else { return turkish }
        return english
    }

    private static let english: [String: String] = [
        "TR": "Turkey",
        "DE": "Germany",
        "US": "United States",
        "AR": "Argentina",
        "AL": "Albania",
        "AU": "Australia",
        "AT": "Austria",
        "AZ": "Azerbaijan",
        "BH": "Bahrain",
        "BD": "Bangladesh",
        "BE": "Belgium",
        "AE": "United Arab Emirates",
        "GB": "United Kingdom",
        "BA": "Bosnia and Herzegovina",
        "BR": "Brazil",
        "BG": "Bulgaria",
        "DZ": "Algeria",
        "CN": "China",
        "DK": "Denmark",
        "ID": "Indonesia",
        "MA": "Morocco",
        "PS": "Palestine",
        "FI": "Finland",
        "FR": "France",
        "ZA": "South Africa",
        "GE": "Georgia",
        "IN": "India",
        "NL": "Netherlands",
        "IQ": "Iraq",
        "IR": "Iran",
        "IE": "Ireland",
        "ES": "Spain",
        "SE": "Sweden",
        "CH": "Switzerland",
        "IT": "Italy",
        "JP": "Japan",
        "CA": "Canada",
        "ME": "Montenegro",
        "QA": "Qatar",
        "KZ": "Kazakhstan",
        "KE": "Kenya",
        "CY": "Cyprus",
        "KG": "Kyrgyzstan",
        "KR": "Korea",
        "XK": "Kosovo",
        "KW": "Kuwait",
        "LY": "Libya",
        "LB": "Lebanon",
        "HU": "Hungary",
        "MY": "Malaysia",
        "EG": "Egypt",
        "NG": "Nigeria",
        "NO": "Norway",
        "UZ": "Uzbekistan",
        "PK": "Pakistan",
        "PL": "Poland",
        "PT": "Portugal",
        "RO": "Romania",
        "RU": "Russia",
        "SN": "Senegal",
        "RS": "Serbia",
        "SG": "Singapore",
        "SO": "Somalia",
        "SA": "Saudi Arabia",
        "TN": "Tunisia",
        "TM": "Turkmenistan",
        "UA": "Ukraine",
        "OM": "Oman",
        "JO": "Jordan",
        "YE": "Yemen",
        "GR": "Greece"
    ]
}
