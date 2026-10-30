import Foundation

struct BrewPackage: Identifiable, Equatable {
    var name: String
    var version: String
    var cask: Bool
    var id: String { (cask ? "cask:" : "formula:") + name }
}

struct BrewServiceInfo: Identifiable, Equatable {
    var name: String
    var status: String
    var user: String
    var id: String { name }
    var running: Bool { status == "started" || status == "scheduled" }
}

/// Bu Mac’teki Homebrew kurulumu. Komutlar kabuksuz, argüman listesiyle çalışır.
@MainActor
final class HomebrewService: ObservableObject {
    static let shared = HomebrewService()

    @Published private(set) var brewPath: String?
    @Published private(set) var formulae: [BrewPackage] = []
    @Published private(set) var casks: [BrewPackage] = []
    @Published private(set) var services: [BrewServiceInfo] = []
    @Published private(set) var searchResults: [BrewPackage] = []
    @Published private(set) var busy = false
    @Published var log = ""
    @Published var error: String?

    private init() {
        brewPath = Self.locate()
    }

    func reload() {
        brewPath = Self.locate()
    }

    func refreshInstalled() async {
        guard let brew = brewPath else {
            error = L("Homebrew bulunamadı.", "Homebrew was not found.")
            return
        }
        busy = true
        defer { busy = false }
        error = nil
        async let formulaText = Self.run(brew, ["list", "--formula", "--versions"])
        async let caskText = Self.run(brew, ["list", "--cask", "--versions"])
        async let serviceText = Self.run(brew, ["services", "list"])
        let (formulaeResult, casksResult, servicesResult) = await (formulaText, caskText, serviceText)
        if let text = formulaeResult { formulae = Self.packages(text, cask: false) }
        if let text = casksResult { casks = Self.packages(text, cask: true) }
        if let text = servicesResult { services = Self.serviceRows(text) }
        if formulaeResult == nil && casksResult == nil {
            error = L("Kurulu liste okunamadı.", "Could not read the installed list.")
        }
    }

    func search(_ raw: String, cask: Bool) async {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let brew = brewPath, !query.isEmpty else {
            searchResults = []
            return
        }
        busy = true
        defer { busy = false }
        let flag = cask ? "--cask" : "--formula"
        guard let text = await Self.run(brew, ["search", flag, query]) else { return }
        searchResults = text
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("=") }
            .map { BrewPackage(name: $0, version: "", cask: cask) }
    }

    func install(name raw: String, cask: Bool) async {
        guard let name = Self.validName(raw), let brew = brewPath else {
            error = L("Paket adı geçersiz.", "That package name is not valid.")
            return
        }
        await perform(L("Kuruluyor", "Installing"), brew, cask ? ["install", "--cask", name] : ["install", name], timeout: 900)
        await refreshInstalled()
    }

    func uninstall(_ package: BrewPackage, zap: Bool) async {
        guard let brew = brewPath else { return }
        var args = ["uninstall"]
        if package.cask { args.append("--cask") }
        if zap && package.cask { args.append("--zap") }
        args.append(package.name)
        await perform(L("Kaldırılıyor", "Removing"), brew, args, timeout: 300)
        await refreshInstalled()
    }

    func upgrade(_ package: BrewPackage) async {
        guard let brew = brewPath else { return }
        let args = package.cask ? ["upgrade", "--cask", package.name] : ["upgrade", package.name]
        await perform(L("Yükseltiliyor", "Upgrading"), brew, args, timeout: 900)
        await refreshInstalled()
    }

    func setService(_ service: BrewServiceInfo, running: Bool) async {
        guard let brew = brewPath, Self.validName(service.name) != nil else { return }
        let verb = running ? "start" : "stop"
        await perform(running ? L("Başlatılıyor", "Starting") : L("Durduruluyor", "Stopping"), brew, ["services", verb, service.name], timeout: 60)
        await refreshInstalled()
    }

    private func perform(_ title: String, _ brew: String, _ args: [String], timeout: TimeInterval) async {
        busy = true
        defer { busy = false }
        error = nil
        append("\(title): brew \(args.joined(separator: " "))")
        let result = await Self.capture(brew, args, timeout: timeout)
        switch result {
        case .success(let (status, text)):
            append(text)
            if status != 0 {
                error = Lf("brew %1$d koduyla çıktı.", "brew exited with code %1$d.", Int(status))
            }
        case .failure(let failure):
            error = failure.localizedDescription
            append(failure.localizedDescription)
        }
    }

    private func append(_ text: String) {
        let chunk = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chunk.isEmpty else { return }
        let joined = log.isEmpty ? chunk : log + "\n" + chunk
        log = String(joined.suffix(8000))
    }

    static func locate() -> String? {
        for path in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return ProcessRunner.which("brew")
    }

    static func validName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("-"), name.count < 160 else { return nil }
        let extras = CharacterSet(charactersIn: "/@+_.-")
        let ok = name.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || extras.contains($0) }
        return ok ? name : nil
    }

    private static func packages(_ text: String, cask: Bool) -> [BrewPackage] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard let name = parts.first, !name.isEmpty else { return nil }
            let version = parts.count > 1 ? parts[1] : ""
            return BrewPackage(name: name, version: version, cask: cask)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func serviceRows(_ text: String) -> [BrewServiceInfo] {
        text.split(separator: "\n").compactMap { raw in
            let line = String(raw)
            if line.hasPrefix("Name") { return nil }
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
            guard parts.count >= 2 else { return nil }
            let user = parts.count >= 3 ? parts[2] : ""
            return BrewServiceInfo(name: parts[0], status: parts[1], user: user)
        }
    }

    private static func run(_ brew: String, _ args: [String]) async -> String? {
        guard case .success(let (status, text)) = await capture(brew, args, timeout: 90), status == 0 else { return nil }
        return text
    }

    private static func capture(_ brew: String, _ args: [String], timeout: TimeInterval) async -> Result<(Int32, String), Error> {
        let env = environment()
        return await Task.detached(priority: .utility) {
            Result {
                let output = try ProcessRunner.output(brew, arguments: args, timeout: timeout, environment: env, mergeStderr: true)
                return (output.status, String(data: output.data, encoding: .utf8) ?? "")
            }
        }.value
    }

    private static func environment() -> [String: String] {
        var env = ProcessRunner.enrichedEnvironment()
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["HOMEBREW_NO_ANALYTICS"] = "1"
        return env
    }
}
