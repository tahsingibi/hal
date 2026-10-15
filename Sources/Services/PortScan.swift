import Foundation

/// `lsof -F` çıktısından dinleyen TCP portları. Saf ayrıştırma; süreç başlatmaz.
enum PortScan {
    struct Listener: Identifiable, Equatable, Sendable {
        var pid: Int32
        var uid: uid_t
        var command: String
        var displayName: String
        var hint: String?
        /// Kurulmuş TCP bağlantısı. Sıfırsa arayüz bunu yazmaz; boşta dinleyen
        /// sunucu ile gerçekten kullanılanı ayırmak için durur.
        var connections: Int
        var port: Int
        var address: String
        var canStop: Bool

        var id: String { "\(pid)-\(port)" }

        var subtitle: String {
            var parts = ["PID \(pid)", address]
            if connections > 0 {
                parts.append("\(connections) bağlantı")
            }
            if let hint, !hint.isEmpty {
                parts.append(hint)
            }
            return parts.joined(separator: " · ")
        }
    }

    /// `-F pcuPn` çıktısı. Aynı sürecin IPv4/IPv6 çiftleri tek satırda birleşir.
    static func listeners(
        from text: String,
        myUID: uid_t,
        selfPID: Int32,
        commandLines: [Int32: String] = [:],
        connections: [Int: Int] = [:]
    ) -> [Listener] {
        struct Raw {
            var pid: Int32 = 0
            var uid: uid_t = 0
            var command = ""
            var proto = ""
            var sockets: [(port: Int, host: String)] = []
        }

        var current = Raw()
        var seenProcess = false
        var groups: [Raw] = []

        func flush() {
            guard seenProcess, current.pid > 0 else { return }
            groups.append(current)
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let marker = line.first else { continue }
            let value = String(line.dropFirst())
            switch marker {
            case "p":
                flush()
                current = Raw(pid: Int32(value) ?? 0)
                seenProcess = true
            case "c":
                current.command = value
            case "u":
                current.uid = uid_t(value) ?? 0
            case "P":
                current.proto = value
            case "n":
                guard current.proto == "TCP" || current.proto.isEmpty else { continue }
                guard let endpoint = endpoint(value) else { continue }
                current.sockets.append(endpoint)
            default:
                break
            }
        }
        flush()

        var rows: [Listener] = []
        for group in groups {
            let command = group.command.isEmpty ? "süreç" : group.command
            var byPort: [Int: [String]] = [:]
            var order: [Int] = []
            for socket in group.sockets {
                if byPort[socket.port] == nil { order.append(socket.port) }
                byPort[socket.port, default: []].append(socket.host)
            }
            let hint = commandLines[group.pid].flatMap { scriptHint(from: $0, command: command) }
            let canStop = group.uid == myUID && group.pid != selfPID && group.pid > 1
            for port in order {
                rows.append(Listener(
                    pid: group.pid,
                    uid: group.uid,
                    command: command,
                    displayName: command,
                    hint: hint,
                    connections: connections[port] ?? 0,
                    port: port,
                    address: addressLabel(byPort[port] ?? []),
                    canStop: canStop
                ))
            }
        }
        return rows.sorted {
            if $0.port != $1.port { return $0.port < $1.port }
            if $0.displayName != $1.displayName {
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            return $0.pid < $1.pid
        }
    }

    /// `-F Pn` ile kurulmuş bağlantılar. Anahtar, soketin yerel portu.
    static func establishedCounts(from text: String) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        var proto = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let marker = line.first else { continue }
            let value = String(line.dropFirst())
            switch marker {
            case "P":
                proto = value
            case "n" where proto == "TCP" || proto.isEmpty:
                let local = value.components(separatedBy: "->").first ?? value
                guard let endpoint = endpoint(local) else { continue }
                counts[endpoint.port, default: 0] += 1
            default:
                break
            }
        }
        return counts
    }

    /// `ps -o pid=,command=` satırları.
    static func commandLines(from text: String) -> [Int32: String] {
        var map: [Int32: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let split = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let pid = Int32(trimmed[..<split])
            let command = trimmed[trimmed.index(after: split)...].trimmingCharacters(in: .whitespaces)
            if let pid, !command.isEmpty {
                map[pid] = command
            }
        }
        return map
    }

    /// Komut satırından ayırt edici argüman: `node …/vite.js` → `vite.js`.
    /// Bayraklar ve düz kelimeler (adb'nin `fork-server`'ı gibi) gürültü olduğu için yok.
    static func scriptHint(from commandLine: String, command: String) -> String? {
        let parts = commandLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count > 1 else { return nil }
        for arg in parts.dropFirst() {
            if arg.hasPrefix("-") { continue }
            // Boşluklu uygulama yolunu ps bölünce `Code` gibi bir parça kalır.
            // Parantezli kırıklar ve bayraklar ipucu değil.
            if arg.contains("(") || arg.contains(")") || arg.contains(".app") { continue }
            let intactPath = arg.hasPrefix("/") || arg.hasPrefix("./") || arg.hasPrefix("~/")
            let fileName = arg.contains(".") && !arg.contains("/")
            // `Application Support/Code` gibi bölünmüş bir yolun son parçası değil,
            // uzantısı olan göreli bir dosya: `node_modules/.../vite.js`.
            let relativeScript = arg.contains("/")
                && URL(fileURLWithPath: arg).lastPathComponent.contains(".")
            guard intactPath || fileName || relativeScript else { continue }
            let base = URL(fileURLWithPath: arg).lastPathComponent
            if base.isEmpty || base == "." || base == ".." { continue }
            if base.caseInsensitiveCompare(command) == .orderedSame { continue }
            if base.count > 42 { return String(base.prefix(42)) }
            return base
        }
        return nil
    }

    /// `figma_agent` ile `FigmaAgent` aynı süreç. Alt satıra ikisini birden yazmayız.
    static func sameProcessName(_ lhs: String, _ rhs: String) -> Bool {
        let left = fold(lhs)
        let right = fold(rhs)
        return !left.isEmpty && left == right
    }

    /// Geliştirici sunucusu: süreç adı (node, vite, docker, supabase…) ya da
    /// bilinen bir geliştirme portu. AirPlay 5000'i Control Center dinler;
    /// o isimler port numarasıyla içeri sızmasın diye ayrıca elenir.
    static func isDeveloper(_ port: Listener) -> Bool {
        if isSystem(port) { return false }
        // Raycast'in gömülü node'u proje sunucusu değil. İpucu vite/next ise
        // ya da port bilinen bir geliştirme portuysa yine sayılır.
        if isConsumerApp(port) {
            if hintIsProjectTool(port) { return true }
            return developerPorts.contains(port.port)
        }
        if usesDeveloperTool(port) { return true }
        return developerPorts.contains(port.port)
    }

    private static let developerTools: Set<String> = [
        "node", "nodejs", "npm", "npx", "pnpm", "yarn", "bun", "deno", "nodemon",
        "vite", "next", "nuxt", "astro", "remix", "webpack", "turbopack", "esbuild",
        "parcel", "metro", "expo", "storybook", "react", "reactscripts",
        "docker", "dockerproxy", "containerd", "colima", "podman", "orbstack",
        "supabase", "postgrest", "gotrue", "kong", "inbucket", "pgbouncer", "supavisor",
        "postgres", "postgresql", "redis", "redisserver", "mongod", "mysql", "mysqld", "mariadbd",
        "python", "python3", "uvicorn", "gunicorn", "flask", "django", "streamlit", "jupyter",
        "ruby", "rails", "puma", "php", "phpfpm",
        "java", "gradle", "kotlin", "dotnet",
        "hugo", "caddy", "nginx", "ollama", "adb",
        "flutter", "dart", "cargo", "wrangler", "firebase", "prisma",
        "ngrok", "cloudflared", "pocketbase", "minio", "mailpit", "mailhog",
        "elixir", "erlang", "phoenix", "beam",
        "hardhat", "anvil", "foundry",
        "meilisearch", "typesense", "localstack", "minikube",
        "hasura", "strapi", "directus", "grafana", "prometheus",
        "liveserver", "browsersync"
    ]

    /// Yerel yığınların varsayılan portları. İsim eşleşmezse (özel bir ikili
    /// `my-api` gibi) yine de geliştirici sunucusu sayılsın.
    private static let developerPorts: Set<Int> = [
        1234, 1313, 24678, 3000, 3001, 3002, 3030, 3333,
        35729, 4000, 4173, 4200, 4321, 5000, 5001, 5173, 5174, 5273, 5500,
        5432, 54321, 54322, 54323, 54324, 54325, 54326, 54327,
        6006, 6379, 7545, 8000, 8001, 8080, 8081, 8443, 8545, 8787, 8888,
        9000, 9229, 19000, 19001, 19006, 27017, 3306, 2375, 2376
    ]

    private static let systemNames: Set<String> = [
        "controlcenter", "denetimmerkezi", "rapportd", "sharingd",
        "identityservicesd", "airplay", "airplayxpcservice",
        "windowserver", "loginwindow", "syspolicyd", "mdnsresponder"
    ]

    /// Dinleyen süreç node olsa da kendisi bir proje sunucusu olmayan uygulamalar.
    private static let consumerApps: Set<String> = [
        "raycast", "figma", "spotify", "slack", "discord", "zoom",
        "chrome", "safari", "firefox", "arc", "notion", "obsidian",
        "cursor", "code"
    ]

    private static let genericRuntimes: Set<String> = [
        "node", "nodejs", "python", "python3", "ruby", "java", "php", "deno", "bun"
    ]

    private static func usesDeveloperTool(_ port: Listener) -> Bool {
        [port.command, port.hint ?? ""].contains { field in
            tokens(field).contains { developerTools.contains($0) }
        }
    }

    private static func hintIsProjectTool(_ port: Listener) -> Bool {
        guard let hint = port.hint else { return false }
        return tokens(hint).contains { developerTools.contains($0) && !genericRuntimes.contains($0) }
    }

    private static func isConsumerApp(_ port: Listener) -> Bool {
        let name = fold(port.displayName)
        if consumerApps.contains(name) { return true }
        return consumerApps.contains { name.hasPrefix($0) && name.count > $0.count }
    }

    private static func isSystem(_ port: Listener) -> Bool {
        [port.command, port.displayName].contains { systemNames.contains(fold($0)) }
    }

    private static func tokens(_ field: String) -> [String] {
        field.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func fold(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func endpoint(_ name: String) -> (port: Int, host: String)? {
        var cleaned = name.components(separatedBy: "->").first ?? name
        if let range = cleaned.range(of: " (") {
            cleaned = String(cleaned[..<range.lowerBound])
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        guard let colon = cleaned.lastIndex(of: ":") else { return nil }
        let host = String(cleaned[..<colon])
        let portString = cleaned[cleaned.index(after: colon)...]
        guard let port = Int(portString), (1...65535).contains(port) else { return nil }
        return (port, host)
    }

    /// `*` bütün arayüzler. Yalnızca geri dönüş adresleri tek etikette birleşir;
    /// aksi halde IPv4 ve IPv6 aynı port için iki satır gibi durur.
    static func addressLabel(_ hosts: [String]) -> String {
        var ordered: [String] = []
        for host in hosts {
            let norm = normalizeHost(host)
            if !ordered.contains(norm) { ordered.append(norm) }
        }
        if ordered.isEmpty || ordered.contains("*") { return "*" }
        let loopback: Set<String> = ["127.0.0.1", "::1"]
        let set = Set(ordered)
        if set.isSubset(of: loopback) {
            return set.contains("127.0.0.1") ? "127.0.0.1" : "::1"
        }
        return ordered.filter { !loopback.contains($0) }.joined(separator: ", ")
    }

    static func normalizeHost(_ raw: String) -> String {
        var host = raw.trimmingCharacters(in: .whitespaces)
        if host.hasPrefix("["), let end = host.firstIndex(of: "]") {
            host = String(host[host.index(after: host.startIndex)..<end])
        }
        switch host.lowercased() {
        case "*", "", "0.0.0.0", "::", "::0":
            return "*"
        case "localhost":
            return "127.0.0.1"
        default:
            return host
        }
    }
}
