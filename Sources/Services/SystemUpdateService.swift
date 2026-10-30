import AppKit
import Foundation

enum UpdateOrigin: String, Codable {
    case system, brew, sparkle, appStore

    var title: String {
        switch self {
        case .system: return "macOS"
        case .brew: return "Homebrew"
        case .sparkle: return L("Uygulamalar", "Apps")
        case .appStore: return "App Store"
        }
    }
}

struct AvailableUpdate: Identifiable, Equatable {
    var id: String
    var origin: UpdateOrigin
    var name: String
    var installed: String
    var available: String
    /// Kurmak için gereken belirteç: yazılım etiketi, paket adı, uygulama yolu veya mas kimliği.
    var token: String
    var cask: Bool = false

    var versions: String {
        if installed.isEmpty { return available }
        if available.isEmpty { return installed }
        return "\(installed) → \(available)"
    }
}

/// macOS, Homebrew ve yüklü uygulamaların güncellemeleri. Kurulum kendiliğinden başlamaz.
@MainActor
final class SystemUpdateService: ObservableObject {
    static let shared = SystemUpdateService()

    @Published private(set) var items: [AvailableUpdate] = []
    @Published private(set) var scanning = false
    @Published private(set) var applying = false
    @Published var log = ""
    @Published var summary = ""

    private var generation = 0

    private init() {}

    func scan() async {
        generation += 1
        let ticket = generation
        scanning = true
        items = []
        summary = L("Denetleniyor…", "Checking…")
        log = ""
        defer {
            if ticket == generation { scanning = false }
        }

        var found: [AvailableUpdate] = []
        found.append(contentsOf: await systemUpdates())
        if ticket != generation { return }
        found.append(contentsOf: await brewUpdates())
        if ticket != generation { return }
        found.append(contentsOf: await appUpdates())
        if ticket != generation { return }
        items = found
        summary = found.isEmpty
            ? L("Yeni güncelleme yok.", "No updates.")
            : Lf("%1$d güncelleme", "%1$d updates", found.count)
    }

    func apply(_ item: AvailableUpdate) async {
        applying = true
        defer { applying = false }
        switch item.origin {
        case .system:
            await run("/usr/sbin/softwareupdate", ["--install", item.token, "--agree-to-license"], timeout: 1800)
        case .brew:
            guard let brew = HomebrewService.locate() else { return }
            let args = item.cask ? ["upgrade", "--cask", item.token] : ["upgrade", item.token]
            await run(brew, args, timeout: 900, environment: Self.brewEnvironment())
            await scan()
        case .sparkle:
            NSWorkspace.shared.open(URL(fileURLWithPath: item.token))
            append(L("Uygulama açıldı. Kendi güncelleyicisi sürümü sorar.", "The app was opened. Its own updater asks about the version."))
        case .appStore:
            if item.token == "store" {
                if let url = URL(string: "macappstore://showUpdatesPage") {
                    NSWorkspace.shared.open(url)
                }
            } else if let mas = ProcessRunner.which("mas") {
                await run(mas, ["upgrade", item.token], timeout: 900)
                await scan()
            }
        }
    }

    func upgradeAllBrew() async {
        guard let brew = HomebrewService.locate() else { return }
        applying = true
        defer { applying = false }
        await run(brew, ["upgrade", "--greedy"], timeout: 1800, environment: Self.brewEnvironment())
        await scan()
    }

    private func systemUpdates() async -> [AvailableUpdate] {
        append("softwareupdate --list")
        guard let text = await capture("/usr/sbin/softwareupdate", ["--list"], timeout: 240) else {
            append(L("Sistem güncellemeleri okunamadı.", "Could not read system updates."))
            return []
        }
        append(text)
        if text.localizedCaseInsensitiveContains("No new software") || text.localizedCaseInsensitiveContains("yeni yazılım yok") {
            return []
        }
        var items: [AvailableUpdate] = []
        var label = ""
        for raw in text.split(separator: "\n") {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if let range = line.range(of: "Label: ") {
                label = String(line[range.upperBound])
                continue
            }
            if line.hasPrefix("Title:"), !label.isEmpty {
                let title = line.replacingOccurrences(of: "Title:", with: "")
                    .split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? label
                let version = Self.value(after: "Version:", in: line)
                items.append(AvailableUpdate(id: "system:\(label)", origin: .system, name: title, installed: "", available: version, token: label))
                label = ""
            }
        }
        return items
    }

    private func brewUpdates() async -> [AvailableUpdate] {
        guard let brew = HomebrewService.locate() else { return [] }
        append("brew update")
        _ = await capture(brew, ["update"], timeout: 180, environment: Self.brewEnvironment(autoUpdate: true))
        append("brew outdated --greedy --json=v2")
        guard let text = await capture(brew, ["outdated", "--greedy", "--json=v2"], timeout: 180, environment: Self.brewEnvironment()),
              let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            append(L("Homebrew listesi okunamadı.", "Could not read the Homebrew list."))
            return []
        }
        var items: [AvailableUpdate] = []
        items.append(contentsOf: Self.brewRows(root["formulae"], cask: false))
        items.append(contentsOf: Self.brewRows(root["casks"], cask: true))
        return items
    }

    private func appUpdates() async -> [AvailableUpdate] {
        let bundles = Self.appBundles()
        var sparkle: [(name: String, local: String, feed: URL, path: String)] = []
        var storeCount = 0
        for url in bundles {
            let plistURL = url.appendingPathComponent("Contents/Info.plist")
            guard let data = try? Data(contentsOf: plistURL),
                  let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
            let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
            let local = (info["CFBundleShortVersionString"] as? String) ?? ""
            let receipt = url.appendingPathComponent("Contents/_MASReceipt/receipt")
            if FileManager.default.fileExists(atPath: receipt.path) { storeCount += 1 }
            if let feed = info["SUFeedURL"] as? String, let feedURL = URL(string: feed),
               feedURL.scheme == "https" || feedURL.scheme == "http" {
                sparkle.append((name, local, feedURL, url.path))
            }
        }

        var items: [AvailableUpdate] = []
        if let mas = ProcessRunner.which("mas"), let text = await capture(mas, ["outdated"], timeout: 90) {
            items.append(contentsOf: Self.masRows(text))
        } else if storeCount > 0 {
            items.append(AvailableUpdate(
                id: "appstore:page",
                origin: .appStore,
                name: L("App Store güncellemeleri", "App Store updates"),
                installed: "",
                available: Lf("%1$d uygulama App Store’dan", "%1$d apps from the App Store", storeCount),
                token: "store"
            ))
        }

        let limited = sparkle.prefix(40)
        await withTaskGroup(of: AvailableUpdate?.self) { group in
            for app in limited {
                group.addTask {
                    await Self.sparkleUpdate(name: app.name, local: app.local, feed: app.feed, path: app.path)
                }
            }
            for await item in group {
                if let item { items.append(item) }
            }
        }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func run(_ path: String, _ args: [String], timeout: TimeInterval, environment: [String: String]? = nil) async {
        append("\(URL(fileURLWithPath: path).lastPathComponent) \(args.joined(separator: " "))")
        switch await Self.captureResult(path, args, timeout: timeout, environment: environment) {
        case .success(let (status, text)):
            append(text)
            if status != 0 {
                append(Lf("Çıkış kodu %1$d.", "Exit code %1$d.", Int(status)))
            }
        case .failure(let error):
            append(error.localizedDescription)
        }
    }

    private func capture(
        _ path: String,
        _ args: [String],
        timeout: TimeInterval,
        environment: [String: String]? = nil
    ) async -> String? {
        guard case .success(let (_, text)) = await Self.captureResult(path, args, timeout: timeout, environment: environment) else {
            return nil
        }
        return text
    }

    private func append(_ text: String) {
        let chunk = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chunk.isEmpty else { return }
        let joined = log.isEmpty ? chunk : log + "\n" + chunk
        log = String(joined.suffix(8000))
    }

    private static func captureResult(
        _ path: String,
        _ args: [String],
        timeout: TimeInterval,
        environment: [String: String]?
    ) async -> Result<(Int32, String), Error> {
        await Task.detached(priority: .utility) {
            Result {
                let output = try ProcessRunner.output(path, arguments: args, timeout: timeout, environment: environment, mergeStderr: true)
                return (output.status, String(data: output.data, encoding: .utf8) ?? "")
            }
        }.value
    }

    private static func brewEnvironment(autoUpdate: Bool = false) -> [String: String] {
        var env = ProcessRunner.enrichedEnvironment()
        if !autoUpdate { env["HOMEBREW_NO_AUTO_UPDATE"] = "1" }
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["HOMEBREW_NO_ANALYTICS"] = "1"
        return env
    }

    private static func brewRows(_ raw: Any?, cask: Bool) -> [AvailableUpdate] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let name = row["name"] as? String else { return nil }
            let installed = (row["installed_versions"] as? [String])?.joined(separator: ", ") ?? ""
            let current = row["current_version"] as? String ?? ""
            return AvailableUpdate(
                id: "brew:\(cask ? "cask" : "formula"):\(name)",
                origin: .brew,
                name: name,
                installed: installed,
                available: current,
                token: name,
                cask: cask
            )
        }
    }

    private static func masRows(_ text: String) -> [AvailableUpdate] {
        text.split(separator: "\n").compactMap { raw in
            let line = String(raw)
            guard let arrow = line.range(of: "->") else { return nil }
            let head = line[..<arrow.lowerBound]
            guard let open = head.lastIndex(of: "("), let idEnd = head.firstIndex(of: " ") else { return nil }
            let id = String(head[..<idEnd]).trimmingCharacters(in: .whitespaces)
            let name = String(head[head.index(after: idEnd)..<open]).trimmingCharacters(in: .whitespaces)
            let installed = String(head[head.index(after: open)...]).trimmingCharacters(in: .whitespaces)
            let available = line[arrow.upperBound...].replacingOccurrences(of: ")", with: "").trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
            return AvailableUpdate(id: "mas:\(id)", origin: .appStore, name: name, installed: installed, available: available, token: id)
        }
    }

    private static func sparkleUpdate(name: String, local: String, feed: URL, path: String) async -> AvailableUpdate? {
        var request = URLRequest(url: feed, timeoutInterval: 12)
        request.setValue("Hal", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let xml = String(data: data, encoding: .utf8) else { return nil }
        guard let remote = newestVersion(in: xml), versionIsNewer(remote, than: local) else { return nil }
        return AvailableUpdate(id: "sparkle:\(path)", origin: .sparkle, name: name, installed: local, available: remote, token: path)
    }

    private static func newestVersion(in xml: String) -> String? {
        let patterns = [
            "sparkle:shortVersionString=\"([^\"]+)\"",
            "sparkle:shortVersionString='([^']+)'",
            "<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>"
        ]
        var found: [String] = []
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = xml as NSString
            for match in expression.matches(in: xml, range: NSRange(location: 0, length: ns.length)) where match.numberOfRanges > 1 {
                found.append(ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces))
            }
            if !found.isEmpty { break }
        }
        return found.max { versionIsNewer($1, than: $0) }
    }

    private static func versionIsNewer(_ remote: String, than local: String) -> Bool {
        let left = versionParts(remote)
        let right = versionParts(local)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func versionParts(_ raw: String) -> [Int] {
        raw.split(separator: ".").map { token in
            Int(token.prefix { $0.isNumber }) ?? 0
        }
    }

    private static func value(after key: String, in line: String) -> String {
        guard let range = line.range(of: key) else { return "" }
        let rest = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return rest.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    private static func appBundles() -> [URL] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory() + "/Applications", isDirectory: true)
        ]
        let manager = FileManager.default
        var found: [URL] = []
        for root in roots {
            guard let items = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for url in items {
                if url.pathExtension == "app" {
                    found.append(url)
                    continue
                }
                guard let nested = try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
                found.append(contentsOf: nested.filter { $0.pathExtension == "app" })
            }
        }
        return found
    }
}
