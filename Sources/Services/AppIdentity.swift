import AppKit

/// Çalışan bir sürecin insanlara görünen adı.
///
/// Ses çıkaran süreç çoğu zaman uygulamanın kendisi değil, içindeki yardımcıdır
/// (`com.brave.Browser.helper`). Ad ve simge, yolu saran en dış `.app` paketinden okunur.
enum AppIdentity {
    struct Resolved: Equatable {
        var id: String
        var name: String?
        var iconPath: String?
    }

    static func resolve(pid: pid_t, bundleIdentifier: String?) -> Resolved {
        let running = pid > 0 ? NSRunningApplication(processIdentifier: pid) : nil
        let rawID = nonempty(running?.bundleIdentifier) ?? nonempty(bundleIdentifier)
        let seed = running?.bundleURL ?? running?.executableURL
        let app = outermostApp(from: seed) ?? locatedApp(bundleID: rawID)
        let info = app.flatMap(readInfo)
        let id = nonempty(info?.bundleID) ?? groupIdentifier(rawID) ?? (pid > 0 ? "pid:\(pid)" : (rawID ?? "unknown"))
        let name = humanName(
            candidates: [info?.displayName, info?.bundleName, running?.localizedName],
            bundleID: nonempty(info?.bundleID) ?? rawID
        )
        return Resolved(id: id, name: name, iconPath: app?.path ?? running?.bundleURL?.path)
    }

    static func resolve(bundleIdentifier: String) -> Resolved {
        resolve(pid: 0, bundleIdentifier: bundleIdentifier)
    }

    /// Paket kimliği, yardımcı süreç adı veya boş metin. Ekranda gösterilmez.
    static func looksTechnical(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let lower = trimmed.lowercased()
        if lower.hasSuffix(" helper") || lower.contains(" helper (") { return true }
        if trimmed.contains(" ") { return false }
        if trimmed.split(separator: ".").count >= 3 { return true }
        if lower.hasSuffix("helper") || lower.hasSuffix(".xpc") { return true }
        return false
    }

    /// `com.brave.Browser.helper` gibi bir kimliği, paket okunamazsa "Brave" yapar.
    static func prettify(_ bundleID: String) -> String? {
        var parts = bundleID.split(separator: ".").map(String.init)
        if let first = parts.first?.lowercased(), domainPrefixes.contains(first) {
            parts.removeFirst()
        }
        while let last = parts.last?.lowercased(), genericSuffix(last) {
            parts.removeLast()
        }
        guard let token = parts.last, !token.isEmpty else { return nil }
        if token.contains(where: \.isUppercase) { return token }
        return token.prefix(1).uppercased() + token.dropFirst()
    }

    private struct BundleInfo {
        var displayName: String?
        var bundleName: String?
        var bundleID: String?
    }

    private static let domainPrefixes: Set<String> = ["com", "org", "net", "io", "me", "dev", "app", "co"]

    private static func genericSuffix(_ token: String) -> Bool {
        let generic: Set<String> = [
            "browser", "helper", "helpers", "renderer", "gpu", "plugin",
            "agent", "service", "xpc", "framework", "crashpad"
        ]
        return generic.contains(token) || token.hasSuffix("helper")
    }

    private static func nonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Yardımcıların kendi `.app` klasörünü değil, onu saran uygulamayı seçer.
    private static func outermostApp(from url: URL?) -> URL? {
        guard var current = url?.standardizedFileURL else { return nil }
        var found: URL?
        while current.path != "/" {
            if current.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                found = current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return found
    }

    private static func locatedApp(bundleID: String?) -> URL? {
        guard var candidate = bundleID, !candidate.isEmpty else { return nil }
        for _ in 0..<4 {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate) {
                return outermostApp(from: url) ?? url
            }
            guard let dot = candidate.lastIndex(of: ".") else { break }
            let suffix = candidate[candidate.index(after: dot)...].lowercased()
            guard genericSuffix(suffix) else { break }
            candidate = String(candidate[..<dot])
        }
        return nil
    }

    private static func readInfo(_ app: URL) -> BundleInfo? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        func string(_ key: String) -> String? {
            nonempty(info[key] as? String)
        }
        return BundleInfo(
            displayName: string("CFBundleDisplayName"),
            bundleName: string("CFBundleName"),
            bundleID: string("CFBundleIdentifier")
        )
    }

    /// `com.brave.Browser.helper` ile `com.brave.Browser` aynı satıra düşsün.
    private static func groupIdentifier(_ bundleID: String?) -> String? {
        guard var parts = bundleID?.split(separator: ".").map(String.init), !parts.isEmpty else { return nil }
        while let last = parts.last?.lowercased(), genericSuffix(last) {
            parts.removeLast()
        }
        guard parts.count >= 2 else { return bundleID }
        return parts.joined(separator: ".")
    }

    private static func humanName(candidates: [String?], bundleID: String?) -> String? {
        for candidate in candidates {
            guard let name = nonempty(candidate), !looksTechnical(name) else { continue }
            return name
        }
        if let bundleID { return prettify(bundleID) }
        return nil
    }
}
