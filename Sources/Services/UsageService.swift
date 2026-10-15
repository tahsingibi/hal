import AppKit
import Foundation
import Security

/// Yarışan iki görevden ilk sonucu tek seferlik iletir.
private final class QuotaRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<QuotaGroup, Never>?
    private var pending: QuotaGroup?
    private var finished = false

    func attach(_ continuation: CheckedContinuation<QuotaGroup, Never>) {
        lock.lock()
        if let pending, !finished {
            finished = true
            lock.unlock()
            continuation.resume(returning: pending)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func deliver(_ group: QuotaGroup) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        guard let continuation else {
            pending = group
            lock.unlock()
            return
        }
        finished = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: group)
    }
}

struct UsageService {
    /// Tek bir sağlayıcının okunması bu süreyi aşarsa hata olarak işaretlenir.
    /// Böylece takılan bir kaynak diğer kotaların güncellenmesini engellemez.
    private static let providerTimeout: TimeInterval = 25

    static func loadGroups(settings: AppSettings) async -> [QuotaGroup] {
        await withTaskGroup(of: QuotaGroup?.self) { group in
            if settings.claudeEnabled {
                group.addTask {
                    await timeboxed(id: "claude", name: "Claude", kind: .claude) { await fetchClaude() }
                }
            }
            if settings.codexEnabled {
                group.addTask {
                    await timeboxed(id: "codex", name: "Codex", kind: .codex) { await fetchCodex() }
                }
            }
            if settings.grokEnabled {
                group.addTask {
                    await timeboxed(id: "grok", name: "Grok", kind: .grok) { await fetchGrok() }
                }
            }
            for provider in settings.customProviders where provider.enabled {
                group.addTask {
                    await timeboxed(
                        id: provider.id.uuidString,
                        name: provider.name,
                        kind: .custom,
                        accentHex: provider.accentHex
                    ) { await fetchCustom(provider) }
                }
            }
            var items: [QuotaGroup] = []
            for await item in group {
                if let item { items.append(item) }
            }
            let order = ["claude", "codex", "grok"] + settings.customProviders.map(\.id.uuidString)
            return items.sorted {
                (order.firstIndex(of: $0.id) ?? 99) < (order.firstIndex(of: $1.id) ?? 99)
            }
        }
    }

    /// Süre dolarsa bekleyen işi bırakır ve hata durumu döndürür.
    private static func timeboxed(
        id: String,
        name: String,
        kind: ProviderKind,
        accentHex: String? = nil,
        operation: @escaping @Sendable () async -> QuotaGroup
    ) async -> QuotaGroup {
        let timeout = providerTimeout
        let relay = QuotaRelay()
        return await withCheckedContinuation { (continuation: CheckedContinuation<QuotaGroup, Never>) in
            relay.attach(continuation)
            Task.detached(priority: .utility) {
                relay.deliver(await operation())
            }
            Task.detached(priority: .utility) {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                relay.deliver(
                    QuotaGroup(
                        id: id,
                        name: name,
                        kind: kind,
                        accentHex: accentHex ?? kind.accentHex,
                        status: .error("Zaman aşımı"),
                        message: "\(name) kotası \(Int(timeout)) saniyede yanıt vermedi.",
                        windows: []
                    )
                )
            }
        }
    }

    // MARK: - Claude

    private static func claudeGroup(status: QuotaStatus, message: String?, windows: [QuotaWindow] = []) -> QuotaGroup {
        QuotaGroup(
            id: "claude",
            name: "Claude",
            kind: .claude,
            accentHex: ProviderKind.claude.accentHex,
            status: status,
            message: message,
            windows: windows
        )
    }

    static func fetchClaude() async -> QuotaGroup {
        do {
            guard var token = try ClaudeAuth.accessToken() else {
                return claudeGroup(
                    status: .missingAuth,
                    message: "Claude Code oturumu bulunamadı. Terminalde claude ile tekrar giriş yap."
                )
            }
            if ClaudeAuth.needsRefresh() {
                if let refreshed = try? await ClaudeAuth.refresh() {
                    token = refreshed
                }
            }
            guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
                return claudeGroup(status: .error("Adres yok"), message: "Adres yok")
            }
            var lastError = "Kota alınamadı"
            for attempt in 0..<2 {
                do {
                    let (data, response) = try await NetworkClient.get(url, headers: [
                        "Authorization": "Bearer \(token)",
                        "anthropic-beta": "oauth-2025-04-20",
                        "anthropic-version": "2023-06-01",
                        "Content-Type": "application/json"
                    ])
                    if response.statusCode == 401 || response.statusCode == 403 {
                        if attempt == 0, let refreshed = try? await ClaudeAuth.refresh() {
                            token = refreshed
                            continue
                        }
                        lastError = "Claude oturumu süresi dolmuş. Terminalde claude /login ile tekrar giriş yap."
                        break
                    }
                    guard (200..<300).contains(response.statusCode) else {
                        lastError = "Claude HTTP \(response.statusCode)"
                        break
                    }
                    guard let object = JSONValue.object(try? NetworkClient.json(data)) else {
                        lastError = "Claude yanıtı JSON değil"
                        break
                    }
                    let windows = claudeWindows(object)
                    if windows.isEmpty {
                        lastError = "Claude kota biçimi okunamadı"
                        break
                    }
                    return claudeGroup(status: .ready, message: nil, windows: windows)
                } catch {
                    lastError = error.localizedDescription
                    break
                }
            }
            return claudeGroup(status: .error(lastError), message: lastError)
        } catch {
            return claudeGroup(status: .error(error.localizedDescription), message: error.localizedDescription)
        }
    }

    /// api.anthropic.com/api/oauth/usage yanıtı. `utilization` ve `percent` alanları 0…100 aralığında.
    static func claudeWindows(_ object: [String: Any]) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []

        // Öncelik: sunucunun kendi normalize ettiği `limits` dizisi.
        for item in JSONValue.array(object["limits"]) ?? [] {
            guard let limit = JSONValue.object(item) else { continue }
            guard let percent = JSONValue.percentage(limit["percent"]) else { continue }
            let kind = JSONValue.string(limit["kind"]) ?? JSONValue.string(limit["group"]) ?? "limit"
            let reset = JSONValue.date(JSONValue.lookup(limit, keys: ["resets_at", "resetsAt"]))
            windows.append(
                QuotaWindow(
                    id: "claude-\(kind)",
                    title: claudeTitle(kind),
                    percent: percent,
                    usedText: dollarText(limit),
                    resetText: TimeFormatters.resetPhrase(reset),
                    detail: claudeSeverity(JSONValue.string(limit["severity"])),
                    resetsAt: reset
                )
            )
        }

        // Yedek: adlandırılmış pencere nesneleri.
        if windows.isEmpty {
            let named: [(key: String, title: String)] = [
                ("five_hour", "Oturum (5 saat)"),
                ("seven_day", "Haftalık"),
                ("seven_day_opus", "Haftalık · Opus"),
                ("seven_day_sonnet", "Haftalık · Sonnet"),
                ("seven_day_cowork", "Haftalık · Cowork")
            ]
            for item in named {
                guard let node = JSONValue.object(object[item.key]) else { continue }
                guard let percent = JSONValue.percentage(node["utilization"]) else { continue }
                let reset = JSONValue.date(JSONValue.lookup(node, keys: ["resets_at", "resetsAt"]))
                windows.append(
                    QuotaWindow(
                        id: "claude-\(item.key)",
                        title: item.title,
                        percent: percent,
                        usedText: dollarText(node),
                        resetText: TimeFormatters.resetPhrase(reset),
                        detail: JSONValue.string(node["locked_reason"]),
                        resetsAt: reset
                    )
                )
            }
        }

        // Ek kullanım (extra usage) yalnızca açıkken anlamlı.
        if let extra = JSONValue.object(object["extra_usage"]),
           (extra["is_enabled"] as? Bool) == true,
           let percent = JSONValue.percentage(extra["utilization"]) {
            let used = JSONValue.number(extra["used_credits"])
            let cap = JSONValue.number(extra["monthly_limit"])
            windows.append(
                QuotaWindow(
                    id: "claude-extra",
                    title: "Ek kullanım",
                    percent: percent,
                    usedText: (used != nil && cap != nil) ? "\(used!.clean) / \(cap!.clean)" : "",
                    resetText: "Aylık",
                    detail: JSONValue.string(extra["disabled_reason"])
                )
            )
        }

        // Kredi harcaması, limiti varsa.
        if let spend = JSONValue.object(object["spend"]),
           (spend["enabled"] as? Bool) == true,
           let percent = JSONValue.percentage(spend["percent"]) {
            windows.append(
                QuotaWindow(
                    id: "claude-spend",
                    title: "Kredi",
                    percent: percent,
                    usedText: moneyText(spend["used"], limit: spend["limit"]),
                    resetText: "",
                    detail: nil
                )
            )
        }

        return dedupe(windows)
    }

    private static func claudeTitle(_ kind: String) -> String {
        switch kind.lowercased() {
        case "session", "five_hour": return "Oturum (5 saat)"
        case "weekly_all", "weekly", "seven_day": return "Haftalık"
        case "weekly_opus", "seven_day_opus": return "Haftalık · Opus"
        case "weekly_sonnet", "seven_day_sonnet": return "Haftalık · Sonnet"
        case "weekly_cowork", "seven_day_cowork": return "Haftalık · Cowork"
        default:
            return kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func claudeSeverity(_ raw: String?) -> String? {
        switch (raw ?? "").lowercased() {
        case "", "normal": return nil
        case "warning": return "Limite yaklaşıldı"
        case "critical", "exceeded": return "Limit doldu"
        default: return raw
        }
    }

    /// `{ "amount_minor": 1234, "currency": "USD", "exponent": 2 }` biçimini okur.
    private static func minorAmount(_ any: Any?) -> Double? {
        guard let object = JSONValue.object(any),
              let minor = JSONValue.number(object["amount_minor"]) else {
            return JSONValue.number(any)
        }
        let exponent = JSONValue.number(object["exponent"]) ?? 2
        return minor / pow(10, exponent)
    }

    private static func moneyText(_ used: Any?, limit: Any?) -> String {
        guard let usedValue = minorAmount(used) else { return "" }
        if let limitValue = minorAmount(limit), limitValue > 0 {
            return String(format: "$%.2f / $%.2f", usedValue, limitValue)
        }
        return String(format: "$%.2f", usedValue)
    }

    private static func dollarText(_ object: [String: Any]) -> String {
        let used = JSONValue.number(object["used_dollars"])
        let limit = JSONValue.number(object["limit_dollars"])
        if let used, let limit, limit > 0 {
            return String(format: "$%.2f / $%.2f", used, limit)
        }
        if let used {
            return String(format: "$%.2f", used)
        }
        return ""
    }

    private static func dedupe(_ windows: [QuotaWindow]) -> [QuotaWindow] {
        var seen = Set<String>()
        return windows.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Codex

    private static func codexGroup(status: QuotaStatus, message: String?, windows: [QuotaWindow] = []) -> QuotaGroup {
        QuotaGroup(
            id: "codex",
            name: "Codex",
            kind: .codex,
            accentHex: ProviderKind.codex.accentHex,
            status: status,
            message: message,
            windows: windows
        )
    }

    static func fetchCodex() async -> QuotaGroup {
        guard var auth = CodexAuth.load() else {
            return codexGroup(
                status: .missingAuth,
                message: "Codex oturumu bulunamadı (~/.codex/auth.json)"
            )
        }
        if CodexAuth.needsRefresh(auth.accessToken) {
            if let refreshed = try? await CodexAuth.refresh() {
                auth = refreshed
            }
        }
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            return codexGroup(status: .error("Adres yok"), message: "Adres yok")
        }
        var lastError = "Kota alınamadı"
        for attempt in 0..<2 {
            var headers = [
                "Authorization": "Bearer \(auth.accessToken)",
                "Content-Type": "application/json"
            ]
            if let account = auth.accountId, !account.isEmpty {
                headers["ChatGPT-Account-Id"] = account
            }
            do {
                let (data, response) = try await NetworkClient.get(url, headers: headers)
                if response.statusCode == 401 || response.statusCode == 403 {
                    if attempt == 0, let refreshed = try? await CodexAuth.refresh() {
                        auth = refreshed
                        continue
                    }
                    lastError = "Codex oturumu süresi dolmuş. Terminalde codex login çalıştır."
                    break
                }
                guard (200..<300).contains(response.statusCode) else {
                    lastError = "Codex HTTP \(response.statusCode)"
                    break
                }
                guard let object = JSONValue.object(try? NetworkClient.json(data)) else {
                    // 200 ama HTML dönerse oturum Cloudflare tarafından reddedilmiştir.
                    lastError = "Codex yanıtı JSON değil, oturum geçersiz olabilir"
                    break
                }
                let windows = codexWindows(object)
                if windows.isEmpty {
                    lastError = "Codex kota biçimi okunamadı"
                    break
                }
                return codexGroup(status: .ready, message: nil, windows: windows)
            } catch {
                lastError = error.localizedDescription
                break
            }
        }
        return codexGroup(status: .error(lastError), message: lastError)
    }

    /// chatgpt.com/backend-api/wham/usage yanıtı. `used_percent` 0…100 aralığında.
    static func codexWindows(_ object: [String: Any]) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []
        let plan = JSONValue.string(object["plan_type"])?.capitalized

        if let rateLimit = JSONValue.object(object["rate_limit"]) {
            windows.append(contentsOf: codexRateLimit(rateLimit, prefix: "codex", detail: plan))
        }

        for item in JSONValue.array(object["additional_rate_limits"]) ?? [] {
            guard let entry = JSONValue.object(item),
                  let rateLimit = JSONValue.object(entry["rate_limit"]) else { continue }
            let name = JSONValue.string(entry["limit_name"]) ?? "ek"
            windows.append(
                contentsOf: codexRateLimit(rateLimit, prefix: "codex-\(name)", label: codexLabel(name), detail: nil)
            )
        }

        if let credits = JSONValue.object(object["credits"]),
           (credits["has_credits"] as? Bool) == true {
            let unlimited = (credits["unlimited"] as? Bool) == true
            let balance = JSONValue.number(credits["balance"]) ?? 0
            windows.append(
                QuotaWindow(
                    id: "codex-credits",
                    title: "Kredi",
                    percent: 0,
                    usedText: unlimited ? "Sınırsız" : "\(balance.clean) kredi",
                    resetText: "",
                    detail: nil,
                    hasLimit: false
                )
            )
        }

        return dedupe(windows)
    }

    private static func codexRateLimit(
        _ rateLimit: [String: Any],
        prefix: String,
        label: String? = nil,
        detail: String?
    ) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []
        for key in ["primary_window", "secondary_window"] {
            guard let node = JSONValue.object(rateLimit[key]) else { continue }
            guard let percent = JSONValue.percentage(node["used_percent"]) else { continue }
            let span = JSONValue.number(node["limit_window_seconds"])
            var title = codexWindowTitle(span, fallback: key)
            if let label { title = "\(label) · \(title)" }
            let reset = codexResetDate(node)
            windows.append(
                QuotaWindow(
                    id: "\(prefix)-\(key)",
                    title: title,
                    percent: percent,
                    usedText: "",
                    resetText: TimeFormatters.resetPhrase(reset),
                    detail: detail,
                    resetsAt: reset
                )
            )
        }
        return windows
    }

    private static func codexResetDate(_ node: [String: Any]) -> Date? {
        if let at = JSONValue.date(node["reset_at"]) { return at }
        if let after = JSONValue.number(node["reset_after_seconds"]), after > 0 {
            return Date().addingTimeInterval(after)
        }
        return nil
    }

    private static func codexWindowTitle(_ seconds: Double?, fallback: String) -> String {
        guard let seconds, seconds > 0 else {
            return fallback == "primary_window" ? "Oturum" : "Haftalık"
        }
        let hours = Int((seconds / 3600).rounded())
        if hours >= 24 {
            let days = Int((seconds / 86_400).rounded())
            return days == 7 ? "Haftalık" : "\(days) günlük"
        }
        return "Oturum (\(hours) saat)"
    }

    private static func codexLabel(_ raw: String) -> String {
        raw.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    // MARK: - Grok / xAI

    /// Haftalık sınır, grok CLI'nin kendi fatura ucundan gelir.
    /// `https://cli-chat-proxy.grok.com/v1/billing?format=credits`
    /// Oturum `~/.grok/auth.json` (grok login). Çerez taraması ve management key yok.
    static func fetchGrok() async -> QuotaGroup {
        do {
            let credential = try await GrokAuth.credential()
            let windows = try await grokCredits(credential)
            if windows.isEmpty {
                throw HilalError.message("Grok kota yanıtında kullanım yüzdesi yok.")
            }
            return grokGroup(status: .ready, message: nil, windows: windows)
        } catch let error as GrokAuthError {
            switch error {
            case .signedOut:
                return grokGroup(status: .missingAuth, message: error.localizedDescription)
            case .relogin, .failed:
                return grokGroup(status: .error(error.localizedDescription), message: error.localizedDescription)
            }
        } catch {
            return grokGroup(status: .error(error.localizedDescription), message: error.localizedDescription)
        }
    }

    private static func grokGroup(
        status: QuotaStatus,
        message: String?,
        windows: [QuotaWindow] = []
    ) -> QuotaGroup {
        QuotaGroup(
            id: "grok",
            name: "Grok",
            kind: .grok,
            accentHex: ProviderKind.grok.accentHex,
            status: status,
            message: message,
            windows: windows
        )
    }

    private struct GrokUnauthorized: Error {}

    private static func grokCredits(_ credential: GrokCredential) async throws -> [QuotaWindow] {
        do {
            return try await grokCreditsOnce(credential)
        } catch is GrokUnauthorized {
            let fresh = try await GrokAuth.forceRefresh()
            do {
                return try await grokCreditsOnce(fresh)
            } catch is GrokUnauthorized {
                throw GrokAuthError.relogin
            }
        }
    }

    private static func grokCreditsOnce(_ credential: GrokCredential) async throws -> [QuotaWindow] {
        var headers = [
            "Authorization": "Bearer \(credential.token)",
            "X-XAI-Token-Auth": "xai-grok-cli"
        ]
        if !credential.userID.isEmpty {
            headers["x-userid"] = credential.userID
        }
        let (data, response) = try await NetworkClient.get(GrokAuth.billingURL, headers: headers)
        if response.statusCode == 401 || response.statusCode == 403 {
            throw GrokUnauthorized()
        }
        guard (200..<300).contains(response.statusCode) else {
            throw HilalError.message("Grok HTTP \(response.statusCode)")
        }
        let rows = GrokCredits.rows(from: try NetworkClient.json(data))
        return rows.map { row in
            QuotaWindow(
                id: row.id,
                title: row.title,
                percent: row.percent,
                usedText: "",
                resetText: TimeFormatters.resetPhrase(row.resetsAt),
                detail: nil,
                resetsAt: row.resetsAt
            )
        }
    }

    // MARK: - Custom

    static func fetchCustom(_ provider: CustomProvider) async -> QuotaGroup {
        switch provider.source {
        case .manual:
            let limit = max(provider.limit, 0.0001)
            let percent = min(max(provider.used / limit, 0), 1)
            return QuotaGroup(
                id: provider.id.uuidString,
                name: provider.name,
                kind: .custom,
                accentHex: provider.accentHex,
                status: .ready,
                message: nil,
                windows: [
                    QuotaWindow(
                        id: provider.id.uuidString + "-manual",
                        title: provider.name,
                        percent: percent,
                        usedText: "\(Int((percent * 100).rounded()))% kullanıldı",
                        resetText: "Manuel",
                        detail: "\(provider.used.clean) / \(provider.limit.clean)"
                    )
                ]
            )
        case .command:
            do {
                let shell = "/bin/zsh"
                let output = try ProcessRunner.run(shell, arguments: ["-lc", provider.command])
                let json = try JSONSerialization.jsonObject(with: Data(output.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
                let windows = QuotaParser.windows(from: json, fallbackTitle: provider.name)
                return QuotaGroup(
                    id: provider.id.uuidString,
                    name: provider.name,
                    kind: .custom,
                    accentHex: provider.accentHex,
                    status: windows.isEmpty ? .error("Komut çıktısı okunamadı") : .ready,
                    message: windows.isEmpty ? output.prefix(160).description : nil,
                    windows: windows
                )
            } catch {
                return QuotaGroup(
                    id: provider.id.uuidString,
                    name: provider.name,
                    kind: .custom,
                    accentHex: provider.accentHex,
                    status: .error(error.localizedDescription),
                    message: error.localizedDescription,
                    windows: []
                )
            }
        case .url:
            guard let url = URL(string: provider.url) else {
                return QuotaGroup(
                    id: provider.id.uuidString,
                    name: provider.name,
                    kind: .custom,
                    accentHex: provider.accentHex,
                    status: .error("Geçersiz URL"),
                    message: "Geçersiz URL",
                    windows: []
                )
            }
            do {
                var headers: [String: String] = [:]
                let token = provider.token.trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty {
                    headers["Authorization"] = token.lowercased().hasPrefix("bearer ") ? token : "Bearer \(token)"
                }
                let (data, response) = try await NetworkClient.get(url, headers: headers)
                guard (200..<300).contains(response.statusCode) else {
                    throw HilalError.message("HTTP \(response.statusCode)")
                }
                let json = try NetworkClient.json(data)
                let windows = QuotaParser.windows(from: json, fallbackTitle: provider.name)
                return QuotaGroup(
                    id: provider.id.uuidString,
                    name: provider.name,
                    kind: .custom,
                    accentHex: provider.accentHex,
                    status: windows.isEmpty ? .error("JSON okunamadı") : .ready,
                    message: nil,
                    windows: windows
                )
            } catch {
                return QuotaGroup(
                    id: provider.id.uuidString,
                    name: provider.name,
                    kind: .custom,
                    accentHex: provider.accentHex,
                    status: .error(error.localizedDescription),
                    message: error.localizedDescription,
                    windows: []
                )
            }
        }
    }
}

/// Claude kimlik bilgisini bellekte tutar.
///
/// Kayıt Claude Code'a ait olduğu için ACL'inde Hâl yok; ilk okumada macOS bir kez
/// sorar. Süre dolmamış bir jeton varken tekrar okumaya gerek yoktur, bu yüzden
/// önbellek jetonun geçerlilik süresine bağlanır: dakikalık yenilemeler anahtar
/// zincirine hiç gitmez.
private final class KeychainCache: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: Any]?
    private var validUntil = Date.distantPast

    func value() -> [String: Any]? {
        lock.lock(); defer { lock.unlock() }
        guard let stored, Date() < validUntil else { return nil }
        return stored
    }

    func store(_ value: [String: Any]) {
        lock.lock()
        stored = value
        // Jetonun bitimine 5 dk kalana kadar geçerli; üst sınır 30 dk.
        let expiry = KeychainCache.tokenExpiry(value)?.addingTimeInterval(-300)
        let cap = Date().addingTimeInterval(1800)
        validUntil = min(expiry ?? cap, cap)
        lock.unlock()
    }

    func clear() {
        lock.lock(); stored = nil; validUntil = .distantPast; lock.unlock()
    }

    private static func tokenExpiry(_ json: [String: Any]) -> Date? {
        guard let oauth = JSONValue.object(json["claudeAiOauth"]),
              let raw = JSONValue.number(oauth["expiresAt"]) else { return nil }
        return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1000 : raw)
    }
}

enum ClaudeAuth {
    private static let credentialService = "Claude Code-credentials"
    private static let cache = KeychainCache()

    /// Kimlik bilgisini doğrudan Security çerçevesinden okur.
    /// `/usr/bin/security` ile okumak, kaydın erişim listesinde olmayan bir süreç
    /// istekte bulunduğu için her yenilemede yeni bir anahtar zinciri sorusu doğuruyordu.
    /// Uygulama kendi okuduğunda kullanıcı bir kez “Her Zaman İzin Ver” diyebilir.
    /// Sonuç ayrıca kısa süre bellekte tutulur; tek yenilemede üç kez okunmaz.
    static func credentialJSON() throws -> [String: Any]? {
        if let cached = cache.value() { return cached }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: credentialService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, !data.isEmpty else {
            // Yalnızca kayıt bulunamadığında `security` ile bir kez daha bak.
            // Erişim reddedildiyse tekrar denemek ikinci bir şifre sorusu doğurur.
            guard status == errSecItemNotFound, let fallback = legacyCredentialJSON() else { return nil }
            cache.store(fallback)
            return fallback
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let json { cache.store(json) }
        return json
    }

    /// Bazı kurulumlarda kayıt yalnızca `security` üzerinden görünüyor.
    private static func legacyCredentialJSON() -> [String: Any]? {
        guard let result = try? ProcessRunner.output(
            "/usr/bin/security",
            arguments: ["find-generic-password", "-s", credentialService, "-w"],
            timeout: 5
        ), result.status == 0, !result.data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: result.data)) as? [String: Any]
    }

    static func invalidateCache() {
        cache.clear()
    }

    static func accessToken() throws -> String? {
        guard let json = try credentialJSON() else { return nil }
        if let oauth = JSONValue.object(json["claudeAiOauth"]) {
            return JSONValue.string(oauth["accessToken"])
        }
        return JSONValue.string(json["accessToken"])
    }

    static func needsRefresh() -> Bool {
        guard let json = try? credentialJSON(),
              let oauth = JSONValue.object(json["claudeAiOauth"]),
              let expires = JSONValue.number(oauth["expiresAt"]) else { return false }
        let date = Date(timeIntervalSince1970: expires > 10_000_000_000 ? expires / 1000 : expires)
        return date.timeIntervalSinceNow < 60
    }

    static func refresh() async throws -> String? {
        guard let json = try credentialJSON(),
              let oauth = JSONValue.object(json["claudeAiOauth"]),
              let refreshToken = JSONValue.string(oauth["refreshToken"]) else { return nil }
        let urls = [
            "https://platform.claude.com/v1/oauth/token",
            "https://console.anthropic.com/v1/oauth/token"
        ]
        for raw in urls {
            guard let url = URL(string: raw) else { continue }
            let (data, response) = try await NetworkClient.post(url, json: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
            ])
            guard (200..<300).contains(response.statusCode) else { continue }
            let object = JSONValue.object(try NetworkClient.json(data)) ?? [:]
            if let token = JSONValue.string(JSONValue.lookup(object, keys: ["access_token", "accessToken"])) {
                persistOAuth(
                    accessToken: token,
                    refreshToken: JSONValue.string(JSONValue.lookup(object, keys: ["refresh_token", "refreshToken"])),
                    expiresIn: JSONValue.number(JSONValue.lookup(object, keys: ["expires_in", "expiresIn"]))
                )
                return token
            }
        }
        return nil
    }

    static func openLogin() -> String? {
        guard let binary = ProcessRunner.which("claude") else {
            return "claude komutu bulunamadı. Claude Code’u yükle, sonra Terminal’de claude /login çalıştır."
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hilal-claude-login.command")
        let body = """
        #!/bin/zsh
        echo "Claude Code girişi"
        echo "Tarayıcı açılırsa login ol. Bitince bu pencereyi kapat, Hâl’de Yenile’ye bas."
        echo
        \(shellEscape(binary)) /login
        echo
        echo "Giriş bittiyse bu pencereyi kapat, Hâl’de Yenile’ye bas."
        echo
        exec /bin/zsh
        """
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private static func persistOAuth(accessToken: String, refreshToken: String?, expiresIn: Double?) {
        guard var json = try? credentialJSON() else { return }
        var oauth = (json["claudeAiOauth"] as? [String: Any]) ?? [:]
        oauth["accessToken"] = accessToken
        if let refreshToken, !refreshToken.isEmpty {
            oauth["refreshToken"] = refreshToken
        }
        if let expiresIn, expiresIn > 0 {
            oauth["expiresAt"] = Date().addingTimeInterval(expiresIn).timeIntervalSince1970 * 1000
        }
        json["claudeAiOauth"] = oauth
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: credentialService
        ]
        SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        cache.store(json)
    }

    private static func shellEscape(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

enum CodexAuth {
    struct Session {
        var accessToken: String
        var accountId: String?
        var refreshToken: String?
        var clientID: String
    }

    private static var authURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/auth.json")
    }

    static func load() -> Session? {
        guard let object = readJSON() else { return nil }
        let tokens = JSONValue.object(object["tokens"]) ?? object
        guard let access = JSONValue.string(JSONValue.lookup(tokens, keys: ["access_token", "accessToken"])) else {
            return nil
        }
        return Session(
            accessToken: access,
            accountId: JSONValue.string(JSONValue.lookup(tokens, keys: ["account_id", "accountId"])),
            refreshToken: JSONValue.string(JSONValue.lookup(tokens, keys: ["refresh_token", "refreshToken"])),
            clientID: jwtClientID(access) ?? "app_EMoamEEZ73f0CkXaXp7hrann"
        )
    }

    static func needsRefresh(_ accessToken: String) -> Bool {
        guard let exp = jwtExpiry(accessToken) else { return true }
        return exp.timeIntervalSinceNow < 120
    }

    static func refresh() async throws -> Session? {
        guard let current = load(), let refresh = current.refreshToken else { return nil }
        let urls = [
            "https://auth.openai.com/oauth/token",
            "https://auth0.openai.com/oauth/token"
        ]
        for raw in urls {
            guard let url = URL(string: raw) else { continue }
            let (data, response) = try await NetworkClient.post(url, form: [
                "grant_type": "refresh_token",
                "refresh_token": refresh,
                "client_id": current.clientID
            ])
            guard (200..<300).contains(response.statusCode) else { continue }
            let object = JSONValue.object(try NetworkClient.json(data)) ?? [:]
            guard let access = JSONValue.string(JSONValue.lookup(object, keys: ["access_token", "accessToken"])) else {
                continue
            }
            persist(
                accessToken: access,
                refreshToken: JSONValue.string(JSONValue.lookup(object, keys: ["refresh_token", "refreshToken"])) ?? refresh,
                idToken: JSONValue.string(JSONValue.lookup(object, keys: ["id_token", "idToken"]))
            )
            return Session(
                accessToken: access,
                accountId: current.accountId,
                refreshToken: JSONValue.string(JSONValue.lookup(object, keys: ["refresh_token", "refreshToken"])) ?? refresh,
                clientID: current.clientID
            )
        }
        return nil
    }

    private static func persist(accessToken: String, refreshToken: String, idToken: String?) {
        guard var object = readJSON() else { return }
        var tokens = JSONValue.object(object["tokens"]) ?? [:]
        tokens["access_token"] = accessToken
        tokens["refresh_token"] = refreshToken
        if let idToken { tokens["id_token"] = idToken }
        object["tokens"] = tokens
        object["last_refresh"] = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: authURL, options: .atomic)
    }

    private static func readJSON() -> [String: Any]? {
        guard let data = try? Data(contentsOf: authURL),
              let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return JSONValue.object(json)
    }

    private static func jwtExpiry(_ token: String) -> Date? {
        guard let payload = jwtPayload(token),
              let exp = JSONValue.number(payload["exp"]) else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    private static func jwtClientID(_ token: String) -> String? {
        jwtPayload(token).flatMap { JSONValue.string($0["client_id"]) }
    }

    private static func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return JSONValue.object(try? JSONSerialization.jsonObject(with: data))
    }
}

/// Şeması bilinmeyen JSON kaynakları (özel sağlayıcılar) için çözümleyici.
/// Bilinen sağlayıcılar kendi şemalarını doğrudan okur; burada tahmin yapılır,
/// bu yüzden yalnızca gerçekten kota gibi görünen alanlar kabul edilir.
enum QuotaParser {
    /// Yüzde/oran taşıdığı ada bakılarak güvenilir sayılan alanlar.
    private static let percentKeys = [
        "utilization", "percent", "used_percent", "usedpercent", "percentage",
        "usage_percent", "used_ratio", "usedratio", "windowusagepercent", "pct"
    ]

    static func windows(from json: Any, fallbackTitle: String) -> [QuotaWindow] {
        if let direct = parseKnown(json), !direct.isEmpty { return direct }
        var found: [QuotaWindow] = []
        walk(json, path: "", into: &found, depth: 0)
        if found.isEmpty,
           let object = JSONValue.object(json),
           let percent = JSONValue.usedPercent(from: object) {
            found.append(
                QuotaWindow(
                    id: fallbackTitle,
                    title: fallbackTitle,
                    percent: percent,
                    usedText: "",
                    resetText: TimeFormatters.resetPhrase(JSONValue.date(JSONValue.lookup(object, keys: ["resets_at", "reset_at", "resetsAt"]))),
                    detail: nil
                )
            )
        }
        return unique(found)
    }

    private static func parseKnown(_ json: Any) -> [QuotaWindow]? {
        guard let object = JSONValue.object(json) else { return nil }
        let nested = JSONValue.object(object["data"])
            ?? JSONValue.object(object["usage"])
            ?? JSONValue.object(object["rate_limit"])
            ?? JSONValue.object(object["rateLimit"])
            ?? JSONValue.object(object["rate_limits"])
            ?? object
        var windows: [QuotaWindow] = []
        let mapping: [(keys: [String], title: String)] = [
            (["five_hour", "fiveHour", "session", "current_session", "primary_window", "primaryWindow"], "Oturum"),
            (["seven_day", "sevenDay", "weekly", "all_models", "secondary_window", "secondaryWindow", "week"], "Haftalık"),
            (["seven_day_sonnet", "sonnet"], "Sonnet"),
            (["seven_day_opus", "opus"], "Opus"),
            (["extra", "extra_usage", "overage", "extraUsage"], "Ek kullanım")
        ]
        for item in mapping {
            if let value = JSONValue.lookup(nested, keys: item.keys) {
                windows.append(contentsOf: window(from: value, title: item.title, id: item.title))
            }
        }
        if windows.isEmpty, let percent = JSONValue.usedPercent(from: nested) {
            windows.append(
                QuotaWindow(
                    id: "main",
                    title: "Kullanım",
                    percent: percent,
                    usedText: "",
                    resetText: TimeFormatters.resetPhrase(JSONValue.date(JSONValue.lookup(nested, keys: ["resets_at", "reset_at", "resetsAt"]))),
                    detail: JSONValue.string(JSONValue.lookup(nested, keys: ["detail", "label"]))
                )
            )
        }
        return windows.isEmpty ? nil : windows
    }

    private static func window(from value: Any, title: String, id: String) -> [QuotaWindow] {
        if let array = JSONValue.array(value) {
            return array.enumerated().flatMap { window(from: $0.element, title: title, id: "\(id)-\($0.offset)") }
        }
        guard let object = JSONValue.object(value) else { return [] }
        guard let computed = JSONValue.usedPercent(from: object) else { return [] }

        let used = JSONValue.number(JSONValue.lookup(object, keys: ["used", "used_usd", "tokens_used", "current"]))
        let limit = JSONValue.number(JSONValue.lookup(object, keys: ["limit", "cap", "max", "quota"]))
        let resetText: String
        if let seconds = JSONValue.number(JSONValue.lookup(object, keys: ["resets_in_seconds", "resetsInSeconds", "reset_after_seconds"])),
           seconds > 0, seconds < 30_000_000 {
            resetText = TimeFormatters.resetPhrase(Date().addingTimeInterval(seconds))
        } else {
            resetText = TimeFormatters.resetPhrase(
                JSONValue.date(JSONValue.lookup(object, keys: [
                    "resets_at", "reset_at", "resetsAt", "resetAt", "expires_at"
                ]))
            )
        }
        let usedText: String
        if let used, let limit, limit > 0 {
            usedText = "\(used.clean) / \(limit.clean)"
        } else {
            usedText = ""
        }
        return [
            QuotaWindow(
                id: id,
                title: JSONValue.string(JSONValue.lookup(object, keys: ["title", "name", "label"])) ?? title,
                percent: computed,
                usedText: usedText,
                resetText: resetText,
                detail: JSONValue.string(JSONValue.lookup(object, keys: ["detail", "description"]))
            )
        ]
    }

    /// Ağacı gezer ama yalnızca adı yüzde/oran belirten alanları kabul eder ve derinliği sınırlar,
    /// böylece alakasız sayılar kota gibi gösterilmez.
    private static func walk(_ json: Any, path: String, into result: inout [QuotaWindow], depth: Int) {
        guard depth <= 4, result.count < 12 else { return }
        if let object = JSONValue.object(json) {
            if depth > 0, let windows = parseKnown(object), !windows.isEmpty {
                result.append(contentsOf: windows)
                return
            }
            for (key, value) in object.sorted(by: { $0.key < $1.key }) {
                let next = path.isEmpty ? key : "\(path).\(key)"
                if percentKeys.contains(key.lowercased()),
                   let percent = JSONValue.fraction(key: key, value: value) {
                    result.append(
                        QuotaWindow(
                            id: next,
                            title: humanize(key, fallback: path),
                            percent: percent,
                            usedText: "",
                            resetText: TimeFormatters.resetPhrase(JSONValue.date(JSONValue.lookup(object, keys: ["resets_at", "reset_at"]))),
                            detail: nil
                        )
                    )
                } else {
                    walk(value, path: next, into: &result, depth: depth + 1)
                }
            }
        } else if let array = JSONValue.array(json) {
            for (index, item) in array.enumerated() {
                walk(item, path: "\(path)[\(index)]", into: &result, depth: depth + 1)
            }
        }
    }

    private static func humanize(_ key: String, fallback: String) -> String {
        let k = key.lowercased()
        if k.contains("five") || k.contains("session") { return "Oturum" }
        if k.contains("opus") { return "Opus" }
        if k.contains("sonnet") { return "Sonnet" }
        if k.contains("seven") || k.contains("week") { return "Haftalık" }
        if k.contains("extra") { return "Ek kullanım" }
        if fallback.contains(".") { return fallback.split(separator: ".").last.map(String.init) ?? key }
        if !fallback.isEmpty { return fallback.replacingOccurrences(of: "_", with: " ").capitalized }
        return key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func unique(_ windows: [QuotaWindow]) -> [QuotaWindow] {
        var seen = Set<String>()
        return windows.filter { window in
            let key = window.title + String(format: "%.4f", window.percent)
            return seen.insert(key).inserted
        }
    }
}

private extension Double {
    var clean: String {
        if rounded() == self { return String(Int(self)) }
        return String(format: "%.1f", self)
    }
}
