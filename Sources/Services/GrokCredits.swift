import Foundation

/// grok CLI'nin `GET /v1/billing?format=credits` yanıtı.
/// Yüzde uydurulmaz: alan yoksa satır da yoktur. Haftalık pencerede toplam
/// yüzde proto3 gibi düşmüşse ve ürün satırı da yoksa bu 0 kabul edilir.
enum GrokCredits {
    struct Row: Equatable, Sendable {
        var id: String
        var title: String
        var percent: Double
        var resetsAt: Date?
    }

    static func rows(from json: Any) -> [Row] {
        guard let root = json as? [String: Any] else { return [] }
        let config = (root["config"] as? [String: Any]) ?? root
        let period = config["currentPeriod"] as? [String: Any]
        let periodType = (period?["type"] as? String) ?? ""
        let reset = date(period?["end"]) ?? date(config["billingPeriodEnd"])

        let products = config["productUsage"] as? [Any] ?? []
        var productRows: [Row] = []
        for (index, item) in products.enumerated() {
            guard let object = item as? [String: Any],
                  let percent = number(object["usagePercent"]) else { continue }
            let name = (object["product"] as? String) ?? ""
            productRows.append(Row(
                id: "grok-product-\(index)",
                title: productTitle(name),
                percent: clamp(percent / 100),
                resetsAt: reset
            ))
        }

        var rows: [Row] = []
        if let percent = number(config["creditUsagePercent"]) {
            rows.append(Row(
                id: "grok-limit",
                title: limitTitle(periodType),
                percent: clamp(percent / 100),
                resetsAt: reset
            ))
        } else if productRows.isEmpty, periodType.contains("WEEKLY") || periodType.contains("MONTHLY") {
            rows.append(Row(
                id: "grok-limit",
                title: limitTitle(periodType),
                percent: 0,
                resetsAt: reset
            ))
        }
        rows.append(contentsOf: productRows)
        return rows
    }

    private static func limitTitle(_ periodType: String) -> String {
        if periodType.contains("MONTHLY") { return "Aylık Sınır" }
        if periodType.contains("WEEKLY") { return "Haftalık Sınır" }
        return "Kullanım"
    }

    private static func productTitle(_ raw: String) -> String {
        switch raw.lowercased() {
        case "grokbuild", "grok_build": return "Grok Build"
        case "grok": return "Grok"
        case "imagine": return "Imagine"
        case "api", "grokapi", "grok_api": return "API"
        case "": return "Kullanım"
        default:
            var spaced = ""
            for character in raw {
                if character == "_" || character == "-" {
                    spaced.append(" ")
                } else if character.isUppercase, let last = spaced.last, last != " " {
                    spaced.append(" ")
                    spaced.append(character)
                } else {
                    spaced.append(character)
                }
            }
            return spaced.trimmingCharacters(in: .whitespaces)
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func number(_ any: Any?) -> Double? {
        if let value = any as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() { return nil }
            return value.doubleValue
        }
        if let value = any as? String { return Double(value) }
        return nil
    }

    private static func date(_ any: Any?) -> Date? {
        guard let value = any as? String else { return nil }
        let plain = ISO8601DateFormatter()
        if let parsed = plain.date(from: value) { return parsed }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }
}
