import AppKit
import Foundation

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
    private static let providerTimeout: TimeInterval = 30

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
                        status: .error(L("Zaman aşımı", "Timed out")),
                        message: Lf(
                            "%1$@ kotası %2$d saniyede yanıt vermedi.",
                            "%1$@ quota did not respond in %2$d seconds.",
                            name,
                            Int(timeout)
                        ),
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

    /// Kota Claude Code'a sorulur (`claude` kontrol protokolü, `get_usage`). Oturumu
    /// Claude Code kendisi açar ve yeniler; Hâl anahtar zincirine hiç dokunmaz.
    /// Claude Code yanıt veremezse Claude masaüstü uygulamasının kaydı okunur.
    static func fetchClaude() async -> QuotaGroup {
        if let fresh = await AgentQuotaMemory.shared.fresh("claude") { return fresh }
        let result = await AgentCLIQueue.run { ClaudeUsageCLI.read() }
        switch result {
        case .success(let reading):
            let windows = claudeWindows(reading.rateLimits)
            guard !windows.isEmpty else {
                return claudeGroup(
                    status: .error(L("Claude kota biçimi okunamadı", "Could not read the Claude quota format")),
                    message: L("Claude kota biçimi okunamadı", "Could not read the Claude quota format")
                )
            }
            var group = claudeGroup(status: .ready, message: nil, windows: windows)
            group.plan = reading.plan
            group.observedAt = reading.observedAt
            await AgentQuotaMemory.shared.store(group)
            return group
        case .failure(let failure):
            if let app = ClaudeAppUsageHistory.latest() {
                var group = claudeGroup(status: .ready, message: nil, windows: app.windows)
                group.observedAt = app.observedAt
                group.note = L("Claude uygulamasının kaydından", "From the Claude app’s record")
                return group
            }
            if failure == .unreachable, let last = await AgentQuotaMemory.shared.last("claude") {
                return last
            }
            let message = claudeFailureMessage(failure)
            switch failure {
            case .missing, .needsSignIn:
                return claudeGroup(status: .missingAuth, message: message)
            case .outdated, .unreachable:
                return claudeGroup(status: .error(message), message: message)
            }
        }
    }

    private static func claudeFailureMessage(_ failure: ClaudeUsageCLI.Failure) -> String {
        switch failure {
        case .missing:
            return L("Claude Code bulunamadı. Yükle, sonra Terminal’de claude ile giriş yap.",
                     "Claude Code was not found. Install it, then sign in with claude in Terminal.")
        case .needsSignIn:
            return L("Claude Code planlı bir hesapla oturum açmamış. Terminal’de claude /login çalıştır.",
                     "Claude Code isn’t signed in with a plan. Run claude /login in Terminal.")
        case .outdated:
            return L("Claude Code bu sürümde kotayı dışarıya vermiyor. Terminal’de claude update çalıştır.",
                     "This Claude Code version can’t report usage. Run claude update in Terminal.")
        case .unreachable:
            return L("Claude Code yanıt vermedi; biraz sonra tekrar denenecek.",
                     "Claude Code didn’t answer; it will be tried again shortly.")
        }
    }

    /// api.anthropic.com/api/oauth/usage yanıtı. `utilization` ve `percent` alanları 0…100 aralığında.
    static func claudeWindows(_ object: [String: Any]) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []

        let breakdown = claudeBreakdown(object)

        // Öncelik: sunucunun kendi normalize ettiği `limits` dizisi.
        for item in JSONValue.array(object["limits"]) ?? [] {
            guard let limit = JSONValue.object(item) else { continue }
            guard let percent = JSONValue.percentage(limit["percent"]) else { continue }
            let kind = JSONValue.string(limit["kind"]) ?? JSONValue.string(limit["group"]) ?? "limit"
            let reset = JSONValue.date(JSONValue.lookup(limit, keys: ["resets_at", "resetsAt"]))
            let weekly = (JSONValue.string(limit["group"]) ?? kind).lowercased().contains("week")
            let all = ["weekly_all", "weekly", "seven_day"].contains(kind.lowercased())
            windows.append(
                QuotaWindow(
                    id: "claude-\(kind)",
                    title: claudeTitle(kind),
                    percent: percent,
                    usedText: dollarText(limit),
                    resetText: TimeFormatters.resetPhrase(reset),
                    detail: (all ? breakdown : nil) ?? claudeSeverity(JSONValue.string(limit["severity"])),
                    resetsAt: reset,
                    windowMinutes: claudeMinutes(kind) ?? (weekly ? 10_080 : nil)
                )
            )
        }

        // Yedek: adlandırılmış pencere nesneleri.
        if windows.isEmpty {
            let named: [(key: String, title: String)] = [
                ("five_hour", L("Oturum (5 saat)", "Session (5 hours)")),
                ("seven_day", L("Haftalık", "Weekly")),
                ("seven_day_opus", L("Haftalık · Opus", "Weekly · Opus")),
                ("seven_day_sonnet", L("Haftalık · Sonnet", "Weekly · Sonnet")),
                ("seven_day_cowork", L("Haftalık · Cowork", "Weekly · Cowork"))
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
                        detail: JSONValue.string(node["locked_reason"]) ?? (item.key == "seven_day" ? breakdown : nil),
                        resetsAt: reset,
                        windowMinutes: claudeMinutes(item.key)
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
                    title: L("Ek kullanım", "Extra usage"),
                    percent: percent,
                    usedText: (used != nil && cap != nil) ? "\(used!.clean) / \(cap!.clean)" : "",
                    resetText: L("Aylık", "Monthly"),
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
                    title: L("Kredi", "Credits"),
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
        case "session", "five_hour": return L("Oturum (5 saat)", "Session (5 hours)")
        case "weekly_all", "weekly", "seven_day": return L("Haftalık", "Weekly")
        case "weekly_opus", "seven_day_opus": return L("Haftalık · Opus", "Weekly · Opus")
        case "weekly_sonnet", "seven_day_sonnet": return L("Haftalık · Sonnet", "Weekly · Sonnet")
        case "weekly_cowork", "seven_day_cowork": return L("Haftalık · Cowork", "Weekly · Cowork")
        default:
            return kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func claudeMinutes(_ kind: String) -> Int? {
        switch kind.lowercased() {
        case "session", "five_hour": return 300
        case let key where key.hasPrefix("weekly") || key.hasPrefix("seven_day"): return 10_080
        default: return nil
        }
    }

    /// Haftalık kullanımın nereye gittiği: "Claude Code %80 · Cowork %15 · Sohbet %5".
    private static func claudeBreakdown(_ object: [String: Any]) -> String? {
        guard let node = JSONValue.object(object["seven_day_breakdown"]) else { return nil }
        let parts = (JSONValue.array(node["rows"]) ?? []).compactMap { item -> (String, Double)? in
            guard let row = JSONValue.object(item),
                  let percent = JSONValue.number(row["percent"]), percent >= 1 else { return nil }
            let key = JSONValue.string(row["key"]) ?? ""
            let name: String
            switch key {
            case "chat": name = L("Sohbet", "Chats")
            case "other": name = L("Diğer", "Other")
            default: name = JSONValue.string(row["display_name"]) ?? key
            }
            return (name, percent)
        }
        .sorted { $0.1 > $1.1 }
        guard parts.count > 1 else { return nil }
        return parts.map { Lf("%1$@ %%%2$d", "%1$@ %2$d%%", $0.0, Int($0.1.rounded())) }.joined(separator: " · ")
    }

    private static func claudeSeverity(_ raw: String?) -> String? {
        switch (raw ?? "").lowercased() {
        case "", "normal": return nil
        case "warning": return L("Limite yaklaşıldı", "Near the limit")
        case "critical", "exceeded": return L("Limit doldu", "Limit reached")
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

    /// Kota Codex'in kendi sunucusuna sorulur (`codex app-server`,
    /// `account/rateLimits/read`). Oturumu Codex yönetir; Hâl `auth.json`'a dokunmaz.
    static func fetchCodex() async -> QuotaGroup {
        if let fresh = await AgentQuotaMemory.shared.fresh("codex") { return fresh }
        let result = await AgentCLIQueue.run { CodexAppServer.read() }
        switch result {
        case .success(let reading):
            let group = codexGroup(reading)
            if group.status == .ready { await AgentQuotaMemory.shared.store(group) }
            return group
        case .failure(let failure):
            if failure == .unreachable || failure == .refused,
               let last = await AgentQuotaMemory.shared.last("codex") {
                return last
            }
            let message = codexFailureMessage(failure)
            switch failure {
            case .missing, .needsSignIn:
                return codexGroup(status: .missingAuth, message: message)
            case .outdated, .unreachable, .refused:
                return codexGroup(status: .error(message), message: message)
            }
        }
    }

    static func codexGroup(_ reading: CodexAppServer.Reading) -> QuotaGroup {
        let windows = codexWindows(reading.rateLimits)
        guard !windows.isEmpty else {
            let message = L("Codex kota biçimi okunamadı", "Could not read the Codex quota format")
            return codexGroup(status: .error(message), message: message)
        }
        var group = codexGroup(status: .ready, message: nil, windows: windows)
        group.plan = reading.plan
        group.observedAt = reading.observedAt
        group.resetCredits = codexResetCredits(reading.rateLimits, now: reading.observedAt)
        return group
    }

    static func codexFailureMessage(_ failure: CodexAppServer.Failure) -> String {
        switch failure {
        case .missing:
            return L("Codex uygulaması ya da CLI’si bulunamadı.", "Neither the Codex app nor its CLI was found.")
        case .needsSignIn:
            return L("Codex planlı bir ChatGPT hesabıyla oturum açmamış. Terminal’de codex login çalıştır.",
                     "Codex isn’t signed in with a ChatGPT plan. Run codex login in Terminal.")
        case .outdated:
            return L("Bu Codex sürümü limitleri dışarıya vermiyor. Codex’i güncelle.",
                     "This Codex version can’t report limits. Update Codex.")
        case .unreachable, .refused:
            return L("Codex yanıt vermedi; biraz sonra tekrar denenecek.",
                     "Codex didn’t answer; it will be tried again shortly.")
        }
    }

    /// `account/rateLimits/read` yanıtı. Ana kova (`codex`) önce, ek kovalar adlarıyla.
    /// `usedPercent` 0…100, `resetsAt` Unix saniyesi.
    static func codexWindows(_ result: [String: Any]) -> [QuotaWindow] {
        var buckets: [(id: String, snapshot: [String: Any])] = []
        if let byID = JSONValue.object(result["rateLimitsByLimitId"]) {
            for key in byID.keys.sorted(by: { ($0 == "codex" ? 0 : 1, $0) < ($1 == "codex" ? 0 : 1, $1) }) {
                if let snapshot = JSONValue.object(byID[key]) { buckets.append((key, snapshot)) }
            }
        } else if let single = JSONValue.object(result["rateLimits"]) {
            buckets.append((JSONValue.string(single["limitId"]) ?? "codex", single))
        }
        var windows: [QuotaWindow] = []
        for bucket in buckets {
            let main = bucket.id == "codex"
            let label = main ? nil : codexLabel(JSONValue.string(bucket.snapshot["limitName"]) ?? bucket.id)
            var found: [QuotaWindow] = []
            for slot in ["primary", "secondary"] {
                guard let node = JSONValue.object(bucket.snapshot[slot]),
                      let used = JSONValue.number(node["usedPercent"]), used.isFinite else { continue }
                let minutes = JSONValue.number(node["windowDurationMins"]).map { Int($0) }
                let reset = unixDate(node["resetsAt"])
                var title = codexWindowTitle(minutes.map { Double($0) * 60 }, fallback: slot + "_window")
                if let label { title = "\(label) · \(title)" }
                found.append(QuotaWindow(
                    id: "codex-\(bucket.id)-\(minutes.map(String.init) ?? slot)",
                    title: title,
                    percent: min(100, max(0, used)) / 100,
                    usedText: "",
                    resetText: TimeFormatters.resetPhrase(reset),
                    resetsAt: reset,
                    windowMinutes: minutes
                ))
            }
            // Bazı hesaplar yalnızca kişisel bir sınır bildirir.
            if found.isEmpty, let individual = JSONValue.object(bucket.snapshot["individualLimit"]),
               let remaining = JSONValue.number(individual["remainingPercent"]), remaining.isFinite {
                let reset = unixDate(individual["resetsAt"])
                found.append(QuotaWindow(
                    id: "codex-\(bucket.id)-individual",
                    title: label ?? L("Kişisel sınır", "Individual limit"),
                    percent: min(100, max(0, 100 - remaining)) / 100,
                    usedText: "",
                    resetText: TimeFormatters.resetPhrase(reset),
                    resetsAt: reset
                ))
            }
            windows += found.sorted { ($0.windowMinutes ?? .max) < ($1.windowMinutes ?? .max) }

            if main, let credits = JSONValue.object(bucket.snapshot["credits"]),
               (credits["hasCredits"] as? Bool) == true {
                let unlimited = (credits["unlimited"] as? Bool) == true
                let balance = JSONValue.number(credits["balance"]) ?? Double(JSONValue.string(credits["balance"]) ?? "") ?? 0
                windows.append(QuotaWindow(
                    id: "codex-credits",
                    title: L("Kredi", "Credits"),
                    percent: 0,
                    usedText: unlimited ? L("Sınırsız", "Unlimited") : Lf("%1$@ kredi", "%1$@ credits", balance.clean),
                    resetText: "",
                    hasLimit: false
                ))
            }
        }
        return dedupe(windows)
    }

    /// Hesapta biriken sıfırlama hakları; bunları bildirmeyen bir Codex için nil.
    static func codexResetCredits(_ result: [String: Any], now: Date) -> QuotaResetCredits? {
        guard result.keys.contains("rateLimitResetCredits") else { return nil }
        let node = JSONValue.object(result["rateLimitResetCredits"])
        let listed = (JSONValue.array(node?["credits"]) ?? []).compactMap { item -> QuotaResetCredits.Credit? in
            guard let credit = JSONValue.object(item),
                  let id = JSONValue.string(credit["id"]), !id.isEmpty,
                  (JSONValue.string(credit["status"]) ?? "available") == "available" else { return nil }
            let expires = unixDate(credit["expiresAt"])
            if let expires, expires <= now { return nil }
            return QuotaResetCredits.Credit(id: id, title: JSONValue.string(credit["title"]), expiresAt: expires)
        }
        let credits = listed.sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
        let count = max(credits.count, Int(JSONValue.number(node?["availableCount"]) ?? 0))
        return QuotaResetCredits(available: count, credits: credits)
    }

    /// Unix saniyesi; milisaniye yazan sürümler de olur.
    private static func unixDate(_ value: Any?) -> Date? {
        guard let number = JSONValue.number(value), number.isFinite, number > 0 else { return nil }
        return Date(timeIntervalSince1970: number > 100_000_000_000 ? number / 1000 : number)
    }

    private static func codexWindowTitle(_ seconds: Double?, fallback: String) -> String {
        guard let seconds, seconds > 0 else {
            return fallback == "primary_window"
                ? L("Oturum", "Session")
                : L("Haftalık", "Weekly")
        }
        let hours = Int((seconds / 3600).rounded())
        if hours >= 24 {
            let days = Int((seconds / 86_400).rounded())
            return days == 7
                ? L("Haftalık", "Weekly")
                : Lf("%1$d günlük", "%1$d-day", days)
        }
        return Lf("Oturum (%1$d saat)", "Session (%1$d hours)", hours)
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
                throw HalError.message(L(
                    "Grok kota yanıtında kullanım yüzdesi yok.",
                    "Grok quota response has no usage percent."
                ))
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
            throw HalError.message(Lf("Grok HTTP %1$d", "Grok HTTP %1$d", response.statusCode))
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
                        usedText: Lf(
                            "%1$d%% kullanıldı",
                            "%1$d%% used",
                            Int((percent * 100).rounded())
                        ),
                        resetText: L("Manuel", "Manual"),
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
                    status: windows.isEmpty ? .error(L("Komut çıktısı okunamadı", "Could not read command output")) : .ready,
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
                    status: .error(L("Geçersiz URL", "Invalid URL")),
                    message: L("Geçersiz URL", "Invalid URL"),
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
                    throw HalError.message(Lf("HTTP %1$d", "HTTP %1$d", response.statusCode))
                }
                let json = try NetworkClient.json(data)
                let windows = QuotaParser.windows(from: json, fallbackTitle: provider.name)
                return QuotaGroup(
                    id: provider.id.uuidString,
                    name: provider.name,
                    kind: .custom,
                    accentHex: provider.accentHex,
                    status: windows.isEmpty ? .error(L("JSON okunamadı", "Could not read JSON")) : .ready,
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

/// Claude Code girişini Terminal'de açar. Hâl Claude'un oturumunu okumaz ya da
/// yenilemez; giriş tamamen Claude Code'a aittir.
enum ClaudeAuth {
    static func openLogin() -> String? {
        guard let binary = ClaudeUsageCLI.executable()?.path ?? ProcessRunner.which("claude") else {
            return L(
                "claude komutu bulunamadı. Claude Code’u yükle, sonra Terminal’de claude /login çalıştır.",
                "claude command not found. Install Claude Code, then run claude /login in Terminal."
            )
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hal-claude-login.command")
        let body = """
        #!/bin/zsh
        echo "\(L("Claude Code girişi", "Claude Code sign-in"))"
        echo "\(L("Tarayıcı açılırsa login ol. Bitince bu pencereyi kapat, Hâl’de Yenile’ye bas.", "If a browser opens, sign in. When done, close this window and press Refresh in Hâl."))"
        echo
        \(shellEscape(binary)) /login
        echo
        echo "\(L("Giriş bittiyse bu pencereyi kapat, Hâl’de Yenile’ye bas.", "If sign-in finished, close this window and press Refresh in Hâl."))"
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

    private static func shellEscape(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

/// Claude ve Codex okumalarının bellekteki son hâli. CLI başlatmak ucuz değil:
/// taze bir okuma tekrar sorulmaz, yanıt alınamayan bir denetimde de son okuma
/// (yenilenmiş pencereleri sıfırlanmış olarak) gösterilmeye devam eder.
actor AgentQuotaMemory {
    static let shared = AgentQuotaMemory()
    /// Bundan yeni bir okuma yeniden sorulmaz.
    static let freshness: TimeInterval = 60
    /// Yanıt alınamadığında son okuma bu kadar eskiyene dek gösterilir.
    static let retention: TimeInterval = 6 * 3600

    private var groups: [String: (group: QuotaGroup, fetched: Date)] = [:]

    func store(_ group: QuotaGroup) {
        groups[group.id] = (group, Date())
    }

    func invalidate(_ id: String) {
        groups[id] = nil
    }

    func fresh(_ id: String, now: Date = Date()) -> QuotaGroup? {
        guard let entry = groups[id], now.timeIntervalSince(entry.fetched) < Self.freshness else { return nil }
        return Self.current(entry.group, now: now)
    }

    func last(_ id: String, now: Date = Date()) -> QuotaGroup? {
        guard let entry = groups[id], now.timeIntervalSince(entry.fetched) < Self.retention else { return nil }
        var group = Self.current(entry.group, now: now)
        group.note = L("Son okuma gösteriliyor; şu an yanıt alınamadı.", "Showing the last reading; no answer right now.")
        return group
    }

    private static func current(_ group: QuotaGroup, now: Date) -> QuotaGroup {
        var group = group
        group.windows = group.windows.map { $0.current(at: now) }
        return group
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
            (["five_hour", "fiveHour", "session", "current_session", "primary_window", "primaryWindow"], L("Oturum", "Session")),
            (["seven_day", "sevenDay", "weekly", "all_models", "secondary_window", "secondaryWindow", "week"], L("Haftalık", "Weekly")),
            (["seven_day_sonnet", "sonnet"], "Sonnet"),
            (["seven_day_opus", "opus"], "Opus"),
            (["extra", "extra_usage", "overage", "extraUsage"], L("Ek kullanım", "Extra usage"))
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
                    title: L("Kullanım", "Usage"),
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
        if k.contains("five") || k.contains("session") { return L("Oturum", "Session") }
        if k.contains("opus") { return "Opus" }
        if k.contains("sonnet") { return "Sonnet" }
        if k.contains("seven") || k.contains("week") { return L("Haftalık", "Weekly") }
        if k.contains("extra") { return L("Ek kullanım", "Extra usage") }
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
