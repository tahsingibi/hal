import AppKit
import Darwin
import Foundation

struct GrokCredential: Sendable {
    var token: String
    var userID: String
}

enum GrokAuthError: LocalizedError {
    case signedOut
    case relogin
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .signedOut:
            return L(
                "grok login oturumu yok. Terminalde grok login çalıştır, sonra Yenile.",
                "No grok login session. Run grok login in Terminal, then press Refresh."
            )
        case .relogin:
            return L(
                "Grok oturumunun süresi dolmuş. Terminalde grok login çalıştır, sonra Yenile.",
                "Grok session expired. Run grok login in Terminal, then press Refresh."
            )
        case .failed(let message):
            return message
        }
    }
}

/// Grok kotası yalnızca `grok login`'in yazdığı oturumla okunur.
/// Tarayıcı çerez veritabanlarına, anahtar zincirine ve management key'e gidilmez.
enum GrokAuth {
    /// grok CLI'nin gizli anahtarı olmayan genel OAuth istemcisi.
    private static let publicClientID = "b1a00492-073a-47ea-816f-4c329264a828"
    private static let tokenURL = URL(string: "https://auth.x.ai/oauth2/token")!
    private static let defaultBillingURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    /// Süre dolmadan bu kadar önce yenile. grok CLI de kendi oturumunu yeniler;
    /// erken yenilemek 401 yarışını azaltır.
    private static let refreshLeeway: TimeInterval = 120
    private static let gate = RefreshGate()

    static var billingURL: URL {
        guard let raw = ProcessInfo.processInfo.environment["GROK_CLI_CHAT_PROXY_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let base = URL(string: raw),
              base.scheme == "https" else {
            return defaultBillingURL
        }
        let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        return URL(string: trimmed + "/billing?format=credits") ?? defaultBillingURL
    }

    /// Dosyadaki erişim anahtarı tazeyse onu döndürür. Süresi yaklaşmışsa
    /// refresh token ile yeniler ve yeni anahtarı aynı dosyaya yazar.
    static func credential() async throws -> GrokCredential {
        let session = try load()
        if let fresh = session.credential(validFor: refreshLeeway) { return fresh }
        return try await gate.run {
            let latest = try load()
            if let fresh = latest.credential(validFor: 30) { return fresh }
            return try await refresh(latest, reuseIfRefreshFails: true)
        }
    }

    /// Sunucu anahtarı reddettiyse dosyayı yeniden okuyup bir kez yeniler.
    static func forceRefresh() async throws -> GrokCredential {
        try await gate.run {
            try await refresh(try load(), reuseIfRefreshFails: false)
        }
    }

    @discardableResult
    static func openLogin() -> String? {
        guard let binary = ProcessRunner.which("grok") else {
            return L(
                "grok komutu bulunamadı. Grok’u yükle, sonra Terminal’de grok login çalıştır.",
                "grok command not found. Install Grok, then run grok login in Terminal."
            )
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hal-grok-login.command")
        let body = """
        #!/bin/zsh
        echo "\(L("Grok girişi", "Grok sign-in"))"
        echo "\(L("Tarayıcı açılırsa login ol. Bitince bu pencereyi kapat, Hâl’de Yenile’ye bas.", "If a browser opens, sign in. When done, close this window and press Refresh in Hâl."))"
        echo
        \(shellEscape(binary)) login
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

    // MARK: - auth.json

    private struct Session {
        var scope: String
        var root: [String: Any]
        var fields: [String: Any]
        var token: String
        var refreshToken: String?
        var userID: String
        var expires: Date?
        var clientID: String
        var principalType: String?
        var principalID: String?

        func credential(validFor leeway: TimeInterval) -> GrokCredential? {
            guard let expires, expires.timeIntervalSinceNow > leeway else { return nil }
            return GrokCredential(token: token, userID: userID)
        }
    }

    private static func authFileURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let path = env["GROK_AUTH_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        if let home = env["GROK_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines), !home.isEmpty {
            return URL(fileURLWithPath: home).appendingPathComponent("auth.json")
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".grok/auth.json")
    }

    private static func load() throws -> Session {
        let url = authFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { throw GrokAuthError.signedOut }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw GrokAuthError.failed(L("Grok oturum dosyası okunamadı.", "Could not read the Grok session file."))
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GrokAuthError.failed(L("Grok oturum dosyası okunamadı.", "Could not read the Grok session file."))
        }
        guard let session = pick(root) else { throw GrokAuthError.signedOut }
        return session
    }

    private static func pick(_ root: [String: Any]) -> Session? {
        var best: Session?
        var bestScore: TimeInterval = -.infinity
        for (scope, value) in root {
            guard let fields = value as? [String: Any],
                  let session = session(scope: scope, root: root, fields: fields) else { continue }
            let score = rank(session)
            if score > bestScore {
                best = session
                bestScore = score
            }
        }
        if let flat = session(scope: "", root: root, fields: root), rank(flat) > bestScore {
            return flat
        }
        return best
    }

    private static func session(scope: String, root: [String: Any], fields: [String: Any]) -> Session? {
        let token = string(fields["key"]) ?? string(fields["access_token"]) ?? ""
        guard !token.isEmpty else { return nil }
        let refresh = string(fields["refresh_token"])
        let client = string(fields["oidc_client_id"]) ?? publicClientID
        return Session(
            scope: scope,
            root: root,
            fields: fields,
            token: token,
            refreshToken: refresh?.isEmpty == false ? refresh : nil,
            userID: string(fields["user_id"]) ?? "",
            expires: JSONValue.date(fields["expires_at"]) ?? jwtExpiry(token),
            clientID: client,
            principalType: string(fields["principal_type"]),
            principalID: string(fields["principal_id"])
        )
    }

    /// auth.x.ai kapsamı, düz nesnedeki rastgele `key` alanına tercih edilir.
    private static func rank(_ session: Session) -> TimeInterval {
        let expiry = session.expires?.timeIntervalSince1970 ?? 0
        let preferred = session.scope.contains("auth.x.ai") ? 1_000_000_000_000.0 : 0
        return preferred + expiry
    }

    private static func refresh(_ session: Session, reuseIfRefreshFails: Bool) async throws -> GrokCredential {
        // grok CLI aynı dosyayı yeniler. Kilit, iki tarafın aynı refresh token'ı
        // harcamasını engeller; ağ çağrısı bitene kadar tutulur.
        let fd = authFileURL().path.withCString { Darwin.open($0, O_RDWR) }
        if fd >= 0 { _ = flock(fd, LOCK_EX) }
        defer { if fd >= 0 { _ = flock(fd, LOCK_UN); close(fd) } }

        let current = (try? load()) ?? session
        if current.token != session.token || current.refreshToken != session.refreshToken,
           let fresh = current.credential(validFor: 0) {
            return fresh
        }
        guard let refreshToken = current.refreshToken else {
            if reuseIfRefreshFails, let usable = current.credential(validFor: 0) { return usable }
            throw GrokAuthError.relogin
        }
        let renewed: Renewed
        do {
            renewed = try await exchange(current, refreshToken: refreshToken)
        } catch {
            if reuseIfRefreshFails, let usable = current.credential(validFor: 0) { return usable }
            throw error
        }
        // Sunucu eski refresh token'ı harcadı. Yeni anahtar diske yazılmazsa
        // bir sonraki grok açılışı oturumu kaybeder.
        try persist(renewed, previous: current)
        return GrokCredential(token: renewed.token, userID: renewed.userID)
    }

    private struct Renewed {
        var token: String
        var refreshToken: String
        var expires: Date
        var userID: String
    }

    private static func exchange(_ session: Session, refreshToken: String) async throws -> Renewed {
        var fields: [(String, String)] = [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", session.clientID)
        ]
        if let principal = session.principalType, !principal.isEmpty {
            fields.append(("principal_type", principal))
        }
        if let principal = session.principalID, !principal.isEmpty {
            fields.append(("principal_id", principal))
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formBody(fields)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GrokAuthError.failed(L("Grok oturumu yenilenemedi.", "Could not refresh the Grok session."))
        }
        guard let http = response as? HTTPURLResponse else {
            throw GrokAuthError.failed(L("Grok oturumu yenilenemedi.", "Could not refresh the Grok session."))
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 400 || http.statusCode == 401 { throw GrokAuthError.relogin }
            throw GrokAuthError.failed(Lf(
                "Grok oturumu yenilenemedi (HTTP %1$d).",
                "Could not refresh the Grok session (HTTP %1$d).",
                http.statusCode
            ))
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = string(object["access_token"]), !token.isEmpty else {
            throw GrokAuthError.failed(L("Grok oturumu yenilenemedi.", "Could not refresh the Grok session."))
        }
        let nextRefresh = string(object["refresh_token"]).flatMap { $0.isEmpty ? nil : $0 } ?? refreshToken
        let expires: Date
        if let seconds = JSONValue.number(object["expires_in"]), seconds > 0 {
            expires = Date().addingTimeInterval(seconds)
        } else if let jwt = jwtExpiry(token) {
            expires = jwt
        } else {
            expires = Date().addingTimeInterval(3600)
        }
        return Renewed(token: token, refreshToken: nextRefresh, expires: expires, userID: session.userID)
    }

    /// Yenilenen anahtarı `auth.json` içine, diğer alanlara dokunmadan yazar.
    private static func persist(_ renewed: Renewed, previous: Session) throws {
        var root = previous.root
        var fields = previous.fields
        fields["key"] = renewed.token
        fields["refresh_token"] = renewed.refreshToken
        fields["expires_at"] = iso8601(renewed.expires)
        if previous.scope.isEmpty {
            root = fields
        } else {
            root[previous.scope] = fields
        }
        guard JSONSerialization.isValidJSONObject(root),
              let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else {
            throw GrokAuthError.failed(L("Grok oturumu kaydedilemedi.", "Could not save the Grok session."))
        }
        let url = authFileURL()
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw GrokAuthError.failed(L("Grok oturumu kaydedilemedi.", "Could not save the Grok session."))
        }
    }

    private static func formBody(_ fields: [(String, String)]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let body = fields.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    private static func string(_ any: Any?) -> String? {
        guard let value = any as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func jwtExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 { payload += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = JSONValue.number(object["exp"]), exp > 0 else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    private static func shellEscape(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

/// Aynı anda iki kota okuması refresh token'ı iki kez harcamasın.
private final class RefreshGate: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<GrokCredential, Error>?
    private var generation = 0

    func run(_ body: @escaping @Sendable () async throws -> GrokCredential) async throws -> GrokCredential {
        let started = start(body)
        do {
            let value = try await started.task.value
            if started.owns { finish(started.id) }
            return value
        } catch {
            if started.owns { finish(started.id) }
            throw error
        }
    }

    private func start(
        _ body: @escaping @Sendable () async throws -> GrokCredential
    ) -> (id: Int, task: Task<GrokCredential, Error>, owns: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if let task { return (generation, task, false) }
        generation += 1
        let created = Task { try await body() }
        task = created
        return (generation, created, true)
    }

    private func finish(_ id: Int) {
        lock.lock()
        defer { lock.unlock() }
        if generation == id {
            task = nil
        }
    }
}

extension Notification.Name {
    static let halGrokSessionChanged = Notification.Name("hal.grokSessionChanged")
}
