import AppKit
import Darwin
import Foundation

/// Bir ajan CLI'siyle standart giriş/çıkış üzerinden yürütülen tek bir konuşma:
/// her satır bir JSON mesajı. Bütün yanıtlar tek bir son tarihe bağlıdır; takılan
/// bir süreç en fazla konuşmanın süresi kadar bekletir. Çağıranı bloklar, bu yüzden
/// kendi kuyruğunda çalıştırılmalıdır.
///
/// Neden böyle: Claude Code ve Codex kimlik bilgilerini kendileri tutar ve
/// yeniler. Hâl onları hiç okumaz; kotayı CLI'ye sorar. Böylece anahtar zinciri
/// soruları ve CLI'nin oturumunu bozan jeton yenilemeleri ortadan kalkar.
final class AgentCLIConversation {
    private static let maximumBuffer = 4 << 20

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let deadline: DispatchTime
    private let arrived = DispatchSemaphore(value: 0)
    private let exited = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var buffer = Data()
    private var closed = false
    private var ended = false

    init?(_ executable: URL, arguments: [String], environment: [String: String], timeout: TimeInterval) {
        deadline = .now() + timeout
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        // Hiçbir proje klasörü gerekmez; kök dizin, CLI'nin bir projenin dosyalarına
        // ya da korumalı bir klasöre takılmasını önler.
        process.currentDirectoryURL = URL(fileURLWithPath: "/", isDirectory: true)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // Erken kapanan bir süreç uygulamayı SIGPIPE ile düşürmesin, yazma başarısız olsun.
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { return nil }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil }
            self?.receive(chunk)
        }
        process.terminationHandler = { [exited] _ in exited.signal() }
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }
    }

    deinit { end() }

    /// Girişi kapatmak sunucuyu bitirir; oyalanan süreç durdurulur.
    func end() {
        lock.lock()
        if ended { lock.unlock(); return }
        ended = true
        lock.unlock()
        try? input.fileHandleForWriting.close()
        let child = process
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            guard child.isRunning else { return }
            child.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
    }

    /// `end()` sonrası sürecin çıkmasını bekler; çıkarken diske yazdıkları yerinde olur.
    @discardableResult
    func waitForExit(timeout: TimeInterval) -> Bool {
        exited.wait(timeout: .now() + timeout) == .success
    }

    func send(_ message: [String: Any]) -> Bool {
        guard DispatchTime.now() < deadline,
              JSONSerialization.isValidJSONObject(message),
              var line = try? JSONSerialization.data(withJSONObject: message, options: .withoutEscapingSlashes)
        else { return false }
        line.append(0x0A)
        do {
            try input.fileHandleForWriting.write(contentsOf: line)
            return true
        } catch {
            return false
        }
    }

    private func receive(_ chunk: Data) {
        lock.lock()
        if chunk.isEmpty || buffer.count + chunk.count > Self.maximumBuffer {
            closed = true
        } else {
            buffer.append(chunk)
        }
        lock.unlock()
        arrived.signal()
    }

    /// Sıradaki mesaj; süreç bittiyse ya da süre dolduysa nil.
    func next() -> [String: Any]? {
        while true {
            lock.lock()
            var line: Data?
            if let newline = buffer.firstIndex(of: 0x0A) {
                line = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            let isClosed = closed
            lock.unlock()
            if let line {
                if let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] {
                    return message
                }
                continue
            }
            if isClosed { return nil }
            if arrived.wait(timeout: deadline) == .timedOut { return nil }
        }
    }
}

/// Bloklayan bir işi iş parçacığı havuzunu tıkamadan bekler.
enum AgentCLIQueue {
    private static let queue = DispatchQueue(label: "hal.agent-cli", qos: .utility, attributes: .concurrent)

    static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }
}

/// CLI'lerin bulunabileceği yerler ve onlara verilecek PATH.
enum AgentCLILocator {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// npm, Bun, pnpm ve Node sürüm yöneticilerinin global araç klasörleri; her
    /// yöneticinin en yeni Node'u önce. Node isteyen bir CLI onu da burada bulur.
    static func toolFolders() -> [String] {
        let path = { (relative: String) -> String in home.appendingPathComponent(relative).path }
        let fnm = ["Library/Application Support/fnm", ".local/share/fnm", ".fnm"].map(path)
        var folders = [path(".volta/bin")]
        folders += fnm.map { $0 + "/aliases/default/bin" }
        folders += newest(in: path(".nvm/versions/node")).map { $0 + "/bin" }
        folders += fnm.flatMap { root in newest(in: root + "/node-versions").map { $0 + "/installation/bin" } }
        folders += newest(in: path(".asdf/installs/nodejs")).map { $0 + "/bin" }
        folders += newest(in: path(".local/share/mise/installs/node")).map { $0 + "/bin" }
        folders += [path(".bun/bin"), path("Library/pnpm"), path(".local/share/pnpm"), path(".npm-global/bin")]
        return folders
    }

    /// `v22.11.0` ya da `22.11.0` adlı klasörler, en yenisi önce.
    private static func newest(in folder: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        return names.compactMap { name -> (version: [Int], path: String)? in
            let parts = (name.hasPrefix("v") ? String(name.dropFirst()) : name).split(separator: ".").map { Int($0) }
            guard !parts.isEmpty, !parts.contains(nil) else { return nil }
            return (parts.compactMap { $0 }, folder + "/" + name)
        }
        .sorted { $1.version.lexicographicallyPrecedes($0.version) }
        .map(\.path)
    }

    static func firstExecutable(_ candidates: [URL]) -> URL? {
        candidates.first { url in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
                && !directory.boolValue
                && FileManager.default.isExecutableFile(atPath: url.path)
        }
    }

    /// Finder'dan açılan bir uygulamanın PATH'inde yalnızca sistem klasörleri olur.
    static func searchPath(prefix: [String] = []) -> String {
        let base = ProcessRunner.enrichedEnvironment()["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        var seen = Set<String>()
        return (prefix + base.split(separator: ":").map(String.init) + toolFolders())
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
    }
}

// MARK: - Claude

/// Claude Code'un yapılandırılmış kontrol protokolü üzerinden /usage ile aynı
/// hesap verisini okur. Oturumu ve yenilemesini Claude Code kendisi yönetir.
/// Hiçbir kullanıcı mesajı, model isteği, MCP sunucusu, araç ya da kanca çalışmaz.
enum ClaudeUsageCLI {
    enum Failure: Error, Equatable {
        case missing, needsSignIn, outdated, unreachable
    }

    /// İçerik JSONSerialization'dan gelir ve hiç değiştirilmez.
    struct Reading: @unchecked Sendable {
        /// `get_usage` yanıtındaki `rate_limits` nesnesi; oauth/usage ile aynı biçim.
        let rateLimits: [String: Any]
        let plan: String?
        let observedAt: Date
    }

    static let timeout: TimeInterval = 25
    /// Kullanıcının Claude Code ayarlarında tuttuğu, `--setting-sources ""` ile dışarıda
    /// kalan tercihler ve ağ ayarları.
    private static let optOuts = ["DISABLE_TELEMETRY", "DISABLE_ERROR_REPORTING", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"]
    private static let networkSettings = ["HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY", "NODE_EXTRA_CA_CERTS"]

    static func executable() -> URL? {
        let home = AgentCLILocator.home
        var folders = [
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".claude/local").path,
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]
        folders += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        folders += AgentCLILocator.toolFolders()
        let candidates = folders.filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("claude") }
        return AgentCLILocator.firstExecutable(candidates)
    }

    /// Uygulamanın kendisi başka bir ajandan açılmış olabilir; onun jetonları ve
    /// yönlendirmeleri kullanıcının kendi oturumunun yerine geçmemeli.
    static func environment(for executable: URL) -> [String: String] {
        let base = ProcessInfo.processInfo.environment
        var environment = base.filter {
            optOuts.contains($0.key) || (!$0.key.hasPrefix("CLAUDE_") && !$0.key.hasPrefix("ANTHROPIC_"))
        }
        environment.removeValue(forKey: "CLAUDECODE")
        environment["DISABLE_AUTOUPDATER"] = "1"
        environment["PATH"] = AgentCLILocator.searchPath(prefix: [executable.deletingLastPathComponent().path])
        let settingsURL = AgentCLILocator.home.appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let settings = json["env"] as? [String: Any] else { return environment }
        for key in optOuts + networkSettings {
            switch settings[key] {
            case let text as String: environment[key] = text
            case let number as NSNumber:
                environment[key] = CFGetTypeID(number) == CFBooleanGetTypeID()
                    ? (number.boolValue ? "true" : "false") : number.stringValue
            default: break
            }
        }
        return environment
    }

    static func read() -> Result<Reading, Failure> {
        guard let executable = executable() else { return .failure(.missing) }
        let arguments = [
            "--print", "--input-format", "stream-json", "--output-format", "stream-json",
            "--verbose", "--no-session-persistence", "--tools", "", "--strict-mcp-config",
            "--mcp-config", "{\"mcpServers\":{}}", "--setting-sources", "",
            "--settings", "{\"disableAllHooks\":true}"
        ]
        guard let channel = AgentCLIConversation(
            executable, arguments: arguments, environment: environment(for: executable), timeout: timeout
        ) else { return .failure(.unreachable) }
        defer { channel.end() }
        if case .failure(let failure) = ask(channel, id: "initialize", request: ["subtype": "initialize"]) {
            return .failure(failure)
        }
        let answer = ask(channel, id: "usage", request: ["subtype": "get_usage", "skip_behaviors": true])
        guard case .success(let result) = answer else {
            if case .failure(let failure) = answer { return .failure(failure) }
            return .failure(.unreachable)
        }
        guard result["rate_limits_available"] as? Bool == true,
              let limits = result["rate_limits"] as? [String: Any] else { return .failure(.needsSignIn) }
        // Claude Code yanıtı kaydettiği kopyadan verebilir; o kopyanın zamanı okumanın zamanıdır.
        channel.end()
        channel.waitForExit(timeout: 3)
        let observed = min(Date(), savedUsageDate() ?? Date())
        return .success(Reading(
            rateLimits: limits,
            plan: planName(result["subscription_type"] as? String),
            observedAt: observed
        ))
    }

    private static func ask(
        _ channel: AgentCLIConversation, id: String, request: [String: Any]
    ) -> Result<[String: Any], Failure> {
        guard channel.send(["type": "control_request", "request_id": id, "request": request]) else {
            return .failure(.unreachable)
        }
        while let message = channel.next() {
            guard message["type"] as? String == "control_response",
                  let response = message["response"] as? [String: Any],
                  response["request_id"] as? String == id else { continue }
            guard response["subtype"] as? String == "success" else {
                let error = (response["error"] as? String ?? "").lowercased()
                // İsteği bilmeyen eski bir CLI "Unsupported control request subtype" der.
                if error.contains("supported") || error.contains("unknown") { return .failure(.outdated) }
                if error.contains("auth") || error.contains("login") || error.contains("sign in") {
                    return .failure(.needsSignIn)
                }
                return .failure(.unreachable)
            }
            return .success(response["response"] as? [String: Any] ?? [:])
        }
        return .failure(.unreachable)
    }

    /// `~/.claude.json` içindeki `cachedUsageUtilization.fetchedAtMs`: yalnızca zaman okunur.
    private static func savedUsageDate() -> Date? {
        let url = AgentCLILocator.home.appendingPathComponent(".claude.json")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4 << 20,
              let data = try? Data(contentsOf: url),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let cached = json["cachedUsageUtilization"] as? [String: Any],
              let value = cached["fetchedAtMs"] as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite, value.doubleValue > 0 else { return nil }
        return Date(timeIntervalSince1970: value.doubleValue / 1000)
    }

    private static func planName(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else { return nil }
        switch raw {
        case "pro": return "Pro"
        case "max": return "Max"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        case "free": return "Free"
        default: return raw.capitalized
        }
    }
}

/// Claude masaüstü uygulaması planın limitlerini kendisi denetler ve son bir ayını
/// bu Mac'te tutar. Claude Code yoksa ya da yanıt veremezse yalnızca bu dosya okunur;
/// oturum gerekmez, hiçbir şey gönderilmez.
enum ClaudeAppUsageHistory {
    /// Uygulama 5–15 dakikada bir denetler; bundan eski okuma bir denetimi kaçırmıştır.
    static let freshness: TimeInterval = 30 * 60

    private static let windows: [(key: String, title: () -> String, minutes: Int)] = [
        ("fh", { L("Oturum (5 saat)", "Session (5 hours)") }, 300),
        ("sd", { L("Haftalık", "Weekly") }, 10_080),
        ("so", { L("Haftalık · Opus", "Weekly · Opus") }, 10_080),
        ("sn", { L("Haftalık · Sonnet", "Weekly · Sonnet") }, 10_080)
    ]

    static var url: URL {
        AgentCLILocator.home.appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
    }

    /// En son okuma; bilinmeyen bir sürüm ya da eski bir okuma nil döner.
    static func latest(now: Date = Date()) -> (windows: [QuotaWindow], observedAt: Date)? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4 << 20,
              let data = try? Data(contentsOf: url),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let version = (json["version"] as? NSNumber)?.intValue, version == 1 || version == 2,
              let entries = json["samples"] as? [[String: Any]] else { return nil }
        let latest = entries.compactMap { entry -> (Date, [String: Any])? in
            guard let ms = (entry["t"] as? NSNumber)?.doubleValue, ms.isFinite, ms > 0 else { return nil }
            // İlk sürüm pencereleri zamanın yanında tutuyordu.
            let values = version == 1 ? entry : (entry["u"] as? [String: Any] ?? [:])
            return (Date(timeIntervalSince1970: ms / 1000), values)
        }.max { $0.0 < $1.0 }
        guard let (date, values) = latest, date <= now.addingTimeInterval(300),
              now.timeIntervalSince(date) < freshness else { return nil }
        let result = windows.compactMap { window -> QuotaWindow? in
            guard let number = values[window.key] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
            return QuotaWindow(
                id: "claude-app-\(window.key)",
                title: window.title(),
                percent: min(100, max(0, number.doubleValue)) / 100,
                usedText: "",
                resetText: "",
                windowMinutes: window.minutes
            )
        }
        return result.isEmpty ? nil : (result, date)
    }
}

// MARK: - Codex

/// Codex'in kendi sunucusu (`codex app-server`), her seferinde kısa bir konuşma için
/// başlatılır ve hesabın limitlerini kendisi sorar. Hâl Codex'in kimlik bilgilerini
/// hiç okumaz ve oturumu yenilemesini istemez.
enum CodexAppServer {
    enum Failure: Error, Equatable {
        /// Bu Mac'te ne Codex uygulaması ne de CLI'si var.
        case missing
        /// Oturum yok ya da plan içermeyen bir anahtarla açılmış.
        case needsSignIn
        /// Limitlerin dışarıdan okunamadığı eski bir Codex.
        case outdated
        /// Yanıt yok: durdu, süresi doldu ya da tanınmayan bir yanıt verdi.
        case unreachable
        /// Kendi hatasıyla yanıt verdi.
        case refused
    }

    enum Outcome: String, Sendable {
        case reset, nothingToReset, noCredit, alreadyRedeemed
    }

    /// İçerik JSONSerialization'dan gelir ve hiç değiştirilmez.
    struct Reading: @unchecked Sendable {
        let rateLimits: [String: Any]
        let plan: String?
        let observedAt: Date
    }

    /// Codex'i içinde taşıyan ve güncel tutan masaüstü uygulamaları.
    static let appIdentifiers = ["com.openai.codex", "com.openai.chat"]
    static let checkTimeout: TimeInterval = 20
    static let redeemTimeout: TimeInterval = 30

    static func executable() -> URL? {
        let apps = appIdentifiers.flatMap { NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0) }
        let bundled = apps.flatMap { app in
            ["Contents/Resources/codex-cli/bin/codex", "Contents/Resources/codex"].map {
                app.appendingPathComponent($0)
            }
        }
        let home = AgentCLILocator.home
        var folders = [home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
        folders += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        folders += AgentCLILocator.toolFolders()
        let installed = folders.filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("codex") }
        return AgentCLILocator.firstExecutable(bundled + installed)
    }

    /// Uygulamanın açıldığı ortamdaki bir oturum ya da sağlayıcı, denetimi başka
    /// bir hesaba yöneltmesin; yalnızca ağ ve sistem değişkenleri geçer.
    static func environment(for executable: URL) -> [String: String] {
        let allowed: Set<String> = [
            "HOME", "USER", "LOGNAME", "TMPDIR", "CODEX_HOME",
            "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
            "http_proxy", "https_proxy", "all_proxy", "no_proxy",
            "SSL_CERT_FILE", "SSL_CERT_DIR", "NODE_EXTRA_CA_CERTS", "DO_NOT_TRACK", "DISABLE_TELEMETRY"
        ]
        var environment = ProcessInfo.processInfo.environment.filter { allowed.contains($0.key) }
        environment["PATH"] = AgentCLILocator.searchPath(prefix: [executable.deletingLastPathComponent().path])
        environment["LANG"] = "en_US.UTF-8"
        return environment
    }

    /// Yalnızca hesabı ve limitlerini sorar; oturumu bilerek yenilemez, reset kullanmaz.
    static func read() -> Result<Reading, Failure> {
        guard let executable = executable() else { return .failure(.missing) }
        guard let conversation = Conversation(executable, timeout: checkTimeout) else { return .failure(.unreachable) }
        defer { conversation.end() }
        return conversation.start()
            .flatMap { _ in conversation.ask("account/read", ["refreshToken": false]) }
            .flatMap { account -> Result<Reading, Failure> in
                if let failure = signInFailure(account) { return .failure(failure) }
                return conversation.ask("account/rateLimits/read").map { result in
                    Reading(rateLimits: result, plan: plan(account), observedAt: Date())
                }
            }
    }

    /// Bir sıfırlama hakkı kullanır: `credit` verilmişse onu, yoksa hesabın sıradakini.
    /// Aynı `key` ile tekrar denemek ikinci bir hak harcamaz. Ardından hesabı yeniden okur.
    static func redeem(credit: String?, key: String) -> (outcome: Result<Outcome, Failure>, reading: Reading?) {
        guard let executable = executable() else { return (.failure(.missing), nil) }
        guard let conversation = Conversation(executable, timeout: redeemTimeout) else {
            return (.failure(.unreachable), nil)
        }
        defer { conversation.end() }
        var params: [String: Any] = ["idempotencyKey": key]
        if let credit { params["creditId"] = credit }
        let outcome = conversation.start()
            .flatMap { _ in conversation.ask("account/rateLimitResetCredit/consume", params) }
            .flatMap { result -> Result<Outcome, Failure> in
                guard let raw = result["outcome"] as? String, let outcome = Outcome(rawValue: raw) else {
                    return .failure(.unreachable)
                }
                return .success(outcome)
            }
        let reading = try? conversation.ask("account/rateLimits/read").map { result in
            Reading(rateLimits: result, plan: nil, observedAt: Date())
        }.get()
        return (outcome, reading)
    }

    /// Hesabın bir planı varsa nil.
    static func signInFailure(_ result: [String: Any]) -> Failure? {
        (result["account"] as? [String: Any])?["type"] as? String == "chatgpt" ? nil : .needsSignIn
    }

    private static func plan(_ account: [String: Any]) -> String? {
        guard let raw = (account["account"] as? [String: Any])?["planType"] as? String,
              ["free", "go", "plus", "pro", "team", "business", "enterprise", "edu"].contains(raw) else { return nil }
        return raw.capitalized
    }

    /// Sunucu retlerini sözle anlatır: bilmediği bir soru "unknown variant",
    /// kapalı oturum "authentication" içerir.
    static func failure(_ error: Any?) -> Failure {
        let error = error as? [String: Any]
        let message = (error?["message"] as? String ?? "").lowercased()
        if (error?["code"] as? NSNumber)?.intValue == -32601 || message.contains("unknown variant")
            || message.contains("method not found") { return .outdated }
        if message.contains("authentication") || message.contains("not logged in") { return .needsSignIn }
        return .refused
    }

    /// Codex'in JSON-RPC protokolü, ortak CLI taşıyıcısı üzerinde.
    final class Conversation {
        private let channel: AgentCLIConversation
        private var lastID = 0

        init?(_ executable: URL, timeout: TimeInterval) {
            // Hesap verisi için eklentiler ve pazar yeri güncellemeleri gerekmez.
            guard let channel = AgentCLIConversation(
                executable,
                arguments: ["-c", "features.plugins=false", "app-server"],
                environment: CodexAppServer.environment(for: executable),
                timeout: timeout
            ) else { return nil }
            self.channel = channel
        }

        func end() { channel.end() }

        /// Her konuşma uygulamayı tanıtarak başlar.
        func start() -> Result<Void, Failure> {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            let client: [String: Any] = ["name": "hal", "title": "Hâl", "version": version]
            return ask("initialize", ["clientInfo": client, "capabilities": NSNull()])
                .flatMap { _ in channel.send(["method": "initialized"]) ? .success(()) : .failure(.unreachable) }
        }

        func ask(_ method: String, _ params: [String: Any] = [:]) -> Result<[String: Any], Failure> {
            lastID += 1
            let id = lastID
            guard channel.send(["id": id, "method": method, "params": params]) else { return .failure(.unreachable) }
            while let message = channel.next() {
                // Bildirimler ve sunucunun kendi istekleri yanıt değildir.
                guard message["method"] == nil, (message["id"] as? NSNumber)?.intValue == id else { continue }
                if let result = message["result"] as? [String: Any] { return .success(result) }
                return .failure(CodexAppServer.failure(message["error"]))
            }
            return .failure(.unreachable)
        }
    }
}
