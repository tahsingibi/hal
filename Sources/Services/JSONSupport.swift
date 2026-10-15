import Foundation

enum JSONValue {
    static func object(_ any: Any?) -> [String: Any]? {
        any as? [String: Any]
    }

    static func array(_ any: Any?) -> [Any]? {
        any as? [Any]
    }

    static func string(_ any: Any?) -> String? {
        if let value = any as? String { return value }
        if let value = any as? NSNumber { return value.stringValue }
        return nil
    }

    static func number(_ any: Any?) -> Double? {
        if let value = any as? NSNumber { return value.doubleValue }
        if let value = any as? Double { return value }
        if let value = any as? Int { return Double(value) }
        if let value = any as? String {
            let cleaned = value.replacingOccurrences(of: "%", with: "")
                .replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: .whitespaces)
            return Double(cleaned)
        }
        return nil
    }

    static func date(_ any: Any?) -> Date? {
        if let value = any as? TimeInterval, value > 1_000_000_000 {
            return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
        }
        if let value = any as? Int {
            let raw = Double(value)
            return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1000 : raw)
        }
        if let value = any as? String {
            if let direct = ISO8601DateFormatter().date(from: value) {
                return direct
            }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = fractional.date(from: value) {
                return parsed
            }
            if let raw = Double(value) {
                return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1000 : raw)
            }
        }
        return nil
    }

    static func lookup(_ object: [String: Any], keys: [String]) -> Any? {
        entry(object, keys: keys)?.value
    }

    /// Bulunan anahtarı da döndürür; birim (oran mı yüzde mi) anahtar adından anlaşılır.
    static func entry(_ object: [String: Any], keys: [String]) -> (key: String, value: Any)? {
        var lowered: [String: (String, Any)] = [:]
        for (key, value) in object where !(value is NSNull) {
            lowered[key.lowercased()] = (key, value)
        }
        for key in keys {
            if let hit = lowered[key.lowercased()] {
                return (hit.0, hit.1)
            }
        }
        return nil
    }

    static func clamp01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    /// Değer 0…1 aralığında bir oran.
    static func ratio(_ any: Any?) -> Double? {
        number(any).map(clamp01)
    }

    /// Değer 0…100 aralığında bir yüzde.
    static func percentage(_ any: Any?) -> Double? {
        number(any).map { clamp01($0 / 100) }
    }

    /// Birim anahtar adından çıkarılır. `used_percent: 31` → 0.31, `used_ratio: 0.31` → 0.31.
    /// Böylece `%1` gibi küçük yüzdeler yanlışlıkla `%100` olarak okunmaz.
    static func fraction(key: String, value: Any?) -> Double? {
        guard let raw = number(value) else { return nil }
        let k = key.lowercased()
        if k.contains("ratio") || k.contains("fraction") || k.hasSuffix("_frac") {
            return clamp01(raw)
        }
        if k.contains("percent") || k.contains("pct") || k.contains("utilization") || k.contains("percentage") {
            return clamp01(raw / 100)
        }
        // Birim bilinmiyor: 1'in üstü ancak yüzde olabilir, altı oran sayılır.
        return clamp01(raw > 1 ? raw / 100 : raw)
    }

    /// Anahtar listesinden birim-farkındalıklı oran okur.
    static func fraction(_ object: [String: Any], keys: [String]) -> Double? {
        guard let hit = entry(object, keys: keys) else { return nil }
        return fraction(key: hit.key, value: hit.value)
    }

    /// Birimi tamamen bilinmeyen tek bir değer için son çare.
    static func percent(from any: Any?) -> Double? {
        guard let value = number(any) else { return nil }
        return clamp01(value > 1 ? value / 100 : value)
    }

    static func usedPercent(from object: [String: Any]) -> Double? {
        if let used = fraction(object, keys: [
            "used_percent", "usedPercent", "utilization", "usage_percent",
            "windowUsagePercent", "used_ratio", "usedRatio"
        ]) {
            return used
        }
        if let remaining = fraction(object, keys: [
            "remaining_percent", "remainingPercent", "remaining_ratio", "remainingRatio"
        ]) {
            return clamp01(1 - remaining)
        }
        let used = number(lookup(object, keys: ["used", "used_usd", "tokens_used", "current", "usedQueries"]))
        let remaining = number(lookup(object, keys: ["remaining", "remainingQueries", "remaining_tokens", "tokensRemaining"]))
        let limit = number(lookup(object, keys: ["limit", "cap", "max", "quota", "total", "totalQueries", "windowLimit"]))
        if let used, let limit, limit > 0 {
            return clamp01(used / limit)
        }
        if let remaining, let limit, limit > 0 {
            return clamp01(1 - remaining / limit)
        }
        return nil
    }
}

enum NetworkClient {
    static func get(_ url: URL, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Hilal/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HilalError.message("Geçersiz yanıt")
        }
        return (data, http)
    }

    static func post(_ url: URL, json: [String: Any], headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Hilal/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HilalError.message("Geçersiz yanıt")
        }
        return (data, http)
    }

    static func post(_ url: URL, form: [String: String], headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Hilal/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HilalError.message("Geçersiz yanıt")
        }
        return (data, http)
    }

    static func request(
        _ url: URL,
        method: String,
        headers: [String: String] = [:],
        json: [String: Any]? = nil,
        browser: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.httpShouldHandleCookies = false
        let ua = browser
            ? "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
            : "Hilal/1.0 (macOS)"
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if json != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if browser {
            request.setValue("https://grok.com", forHTTPHeaderField: "Origin")
            request.setValue("https://grok.com/", forHTTPHeaderField: "Referer")
            request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HilalError.message("Geçersiz yanıt")
        }
        return (data, http)
    }

    /// Ham gövdeli istek (gRPC-Web gibi ikili protokoller için).
    static func raw(
        _ url: URL,
        body: Data,
        contentType: String,
        headers: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpShouldHandleCookies = false
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(contentType, forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://grok.com", forHTTPHeaderField: "Origin")
        request.setValue("https://grok.com/", forHTTPHeaderField: "Referer")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HilalError.message("Geçersiz yanıt")
        }
        return (data, http)
    }

    static func json(_ data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data)
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock(); data.append(chunk); lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock(); defer { lock.unlock() }
        return data
    }
}

enum ProcessRunner {
    static func run(_ launchPath: String, arguments: [String], timeout: TimeInterval = 12) throws -> String {
        let result = try output(launchPath, arguments: arguments, timeout: timeout, environment: enrichedEnvironment())
        return String(data: result.data, encoding: .utf8) ?? ""
    }

    /// Alt süreci süre sınırıyla çalıştırır ve stdout'u boru dolmadan okur.
    /// Süre dolarsa süreç sonlandırılır; hiçbir çağıran süresiz beklemez.
    @discardableResult
    static func output(
        _ launchPath: String,
        arguments: [String],
        timeout: TimeInterval = 8,
        environment: [String: String]? = nil
    ) throws -> (status: Int32, data: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        if let environment { process.environment = environment }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        try process.run()

        // Boru arabelleği dolup süreci kilitlemesin diye çıktıyı arka planda topla.
        let collector = OutputCollector()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                collector.append(chunk)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.1)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw HilalError.message("Komut zaman aşımına uğradı")
        }
        // Süreç bitti; kalan veriyi al.
        Thread.sleep(forTimeInterval: 0.02)
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        collector.append(stdout.fileHandleForReading.availableData)
        return (process.terminationStatus, collector.snapshot())
    }

    static func which(_ name: String) -> String? {
        let env = enrichedEnvironment()
        let path = env["PATH"] ?? ""
        for folder in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(folder)).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    static func enrichedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extras = [
            NSHomeDirectory() + "/.local/bin",
            NSHomeDirectory() + "/.fx/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        let current = env["PATH"] ?? ""
        env["PATH"] = (extras + current.split(separator: ":").map(String.init)).joined(separator: ":")
        return env
    }
}
