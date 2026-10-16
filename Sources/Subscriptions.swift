import Foundation

/// Düzenli ödeme. Tek seferlik harcamalar bilerek yok: Türkiye'de banka API'si
/// pratikte olmadığı için her harcamayı elle girmek sürdürülebilir değil.
/// Düzenli ödemeler ise bir kez girilir ve kendiliğinden işler.
struct Subscription: Identifiable, Codable, Equatable, Hashable, Sendable {
    enum Period: String, Codable, CaseIterable, Identifiable, Sendable {
        case monthly, yearly

        var id: String { rawValue }
        var title: String {
            switch self {
            case .monthly: return L("Aylık", "Monthly")
            case .yearly: return L("Yıllık", "Yearly")
            }
        }
        var component: Calendar.Component {
            switch self {
            case .monthly: return .month
            case .yearly: return .year
            }
        }
    }

    var id: UUID
    var name: String
    var amount: Double
    var currency: String
    var period: Period
    /// İlk (ya da bilinen son) yenileme tarihi. Sonraki yenilemeler bundan türetilir.
    var anchor: Date
    var enabled: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        amount: Double = 0,
        currency: String = "USD",
        period: Period = .monthly,
        anchor: Date = Date(),
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.currency = currency
        self.period = period
        self.anchor = anchor
        self.enabled = enabled
    }

    /// Verilen andan sonraki ilk yenileme. Tarih ileri sarılır, kayıt değiştirilmez;
    /// böylece uygulama günlerce kapalı kalsa da tarih doğru hesaplanır.
    func nextRenewal(after now: Date = Date()) -> Date {
        let calendar = Calendar.current
        var date = anchor
        if date > now { return date }
        // Kaba bir sıçrama, sonra tek tek: uzun aralarda döngü kısa kalsın.
        let step = period == .monthly ? 1 : 12
        while date <= now {
            guard let advanced = calendar.date(byAdding: .month, value: step, to: date) else { break }
            date = advanced
        }
        return date
    }

    func daysUntilRenewal(from now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: nextRenewal(after: now))
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// Aylık karşılığı; yıllık abonelikler 12'ye bölünür.
    var monthlyEquivalent: Double {
        period == .monthly ? amount : amount / 12
    }

    var amountText: String {
        let symbol = Self.symbol(for: currency)
        let value = amount == amount.rounded()
            ? String(Int(amount))
            : String(format: "%.2f", locale: Language.locale, amount)
        return "\(symbol)\(value)"
    }

    static func symbol(for currency: String) -> String {
        switch currency.uppercased() {
        case "USD": return "$"
        case "EUR": return "€"
        case "TRY", "TL": return "₺"
        case "GBP": return "£"
        default: return currency.uppercased() + " "
        }
    }

    static let currencies = ["USD", "EUR", "TRY", "GBP"]
}
