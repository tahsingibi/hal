import AppKit
import Foundation

/// Dinleyen TCP portları. Pano modülü değil: gün boyu bakılan bir durum değil,
/// port dolunca açılan bir araç. İndirici ile aynı yerde durur.
@MainActor
final class PortService: ObservableObject {
    static let shared = PortService()

    @Published private(set) var ports: [PortScan.Listener] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusNote: String?
    @Published private(set) var statusIsError = false
    @Published private(set) var stopping: Set<Int32> = []

    let myUID: uid_t = getuid()
    private var generation = 0
    /// SIGTERM'den sonra hâlâ dinleyenler. Sonraki durdurma SIGKILL olur;
    /// nazik kapanmayı atlamadan zorlamak için.
    private var stubborn: Set<Int32> = []

    private init() {}

    func needsForce(_ pid: Int32) -> Bool {
        stubborn.contains(pid)
    }

    func refresh(resetStatus: Bool = false) async {
        if resetStatus {
            statusNote = nil
            statusIsError = false
        }
        generation += 1
        let token = generation
        isLoading = true
        let myUID = self.myUID
        let selfPID = Int32(ProcessInfo.processInfo.processIdentifier)
        let scanned = await Task.detached(priority: .userInitiated) {
            PortSurvey.listen(myUID: myUID, selfPID: selfPID)
        }.value
        guard token == generation else { return }
        ports = scanned.ports.map(Self.withAppName).sorted(by: Self.displayOrder)
        errorMessage = scanned.error
        stubborn.formIntersection(Set(ports.map(\.pid)))
        hasLoaded = true
        isLoading = false
        // Bağlantı sayımı ikinci tur: bütün kurulmuş soketleri taramak
        // listen listesinden yavaş, satırlar onun için beklememeli.
        guard scanned.error == nil, !ports.isEmpty else { return }
        let wanted = Set(ports.map(\.port))
        let counts = await Task.detached(priority: .userInitiated) {
            PortSurvey.connectionCounts(on: wanted)
        }.value
        guard token == generation else { return }
        ports = ports.map { port in
            var port = port
            port.connections = counts[port.port] ?? 0
            return port
        }
    }

    private static func displayOrder(_ lhs: PortScan.Listener, _ rhs: PortScan.Listener) -> Bool {
        if lhs.port != rhs.port { return lhs.port < rhs.port }
        if lhs.displayName != rhs.displayName {
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        return lhs.pid < rhs.pid
    }

    func stopDetail(for port: PortScan.Listener, force: Bool) -> String {
        let siblings = ports.filter { $0.pid == port.pid }.map(\.port).sorted()
        let closing: String
        if siblings.count <= 1 {
            closing = Lf("%1$d portu boşalır.", "%1$d port will close.", port.port)
        } else {
            let list = siblings.map(String.init).joined(separator: ", ")
            closing = Lf("%1$@ portları boşalır.", "%1$@ ports will close.", list)
        }
        if force {
            return Lf(
                "Az önce kapanmadı. Zorla durdurmak PID %1$d sürecini anında keser. %2$@",
                "It did not quit just now. Force stop immediately kills PID %1$d. %2$@",
                port.pid,
                closing
            )
        }
        return Lf("PID %1$d kapanır. %2$@", "PID %1$d will quit. %2$@", port.pid, closing)
    }

    func stop(_ port: PortScan.Listener) {
        guard port.canStop, port.pid > 1, port.pid != Int32(ProcessInfo.processInfo.processIdentifier) else {
            statusNote = L("Bu süreç durdurulamaz.", "This process cannot be stopped.")
            statusIsError = true
            return
        }
        let force = needsForce(port.pid)
        let signal: Int32 = force ? SIGKILL : SIGTERM
        if kill(port.pid, signal) != 0 {
            let err = errno
            if err != ESRCH {
                statusNote = err == EPERM
                    ? L("Bu süreci durdurma iznin yok.", "You do not have permission to stop this process.")
                    : L("Durdurulamadı.", "Could not stop it.")
                statusIsError = true
                return
            }
        }
        stopping.insert(port.pid)
        statusNote = L("Durduruluyor…", "Stopping…")
        statusIsError = false
        let pid = port.pid
        let portNumber = port.port
        let name = port.displayName
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            await refresh()
            stopping.remove(pid)
            let stillUp = ports.contains { $0.pid == pid && $0.port == portNumber }
            if stillUp {
                stubborn.insert(pid)
                statusNote = force
                    ? Lf("%1$@ kapanmadı.", "%1$@ did not quit.", name)
                    : Lf("%1$@ kapanmadı. Zorla durdurabilirsin.", "%1$@ did not quit. You can force stop it.", name)
                statusIsError = true
            } else {
                stubborn.remove(pid)
                statusNote = Lf("%1$@ durduruldu.", "%1$@ stopped.", name)
                statusIsError = false
            }
        }
    }

    /// Paketli uygulamada lsof'un verdiği `Code Helper` yerine görünen ad
    /// (Cursor, Figma). Yardımcı sürecin kendi adı alt satıra iner.
    private static func withAppName(_ port: PortScan.Listener) -> PortScan.Listener {
        var port = port
        guard let app = NSRunningApplication(processIdentifier: port.pid),
              app.bundleURL != nil,
              let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return port }
        if port.hint == nil, !PortScan.sameProcessName(name, port.command) {
            port.hint = port.command
        }
        port.displayName = name
        return port
    }
}

private enum PortSurvey {
    struct Result: Sendable {
        var ports: [PortScan.Listener]
        var error: String?
    }

    static func listen(myUID: uid_t, selfPID: Int32) -> Result {
        guard FileManager.default.isExecutableFile(atPath: "/usr/sbin/lsof") else {
            return Result(ports: [], error: L("lsof bulunamadı.", "lsof not found."))
        }
        let listed: (status: Int32, data: Data)
        do {
            listed = try ProcessRunner.output(
                "/usr/sbin/lsof",
                arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcuPn"],
                timeout: 8
            )
        } catch {
            return Result(ports: [], error: L("Portlar okunamadı.", "Could not read ports."))
        }
        let text = String(data: listed.data, encoding: .utf8) ?? ""
        if text.isEmpty {
            if listed.status == 0 || listed.status == 1 {
                return Result(ports: [], error: nil)
            }
            return Result(ports: [], error: L("Portlar okunamadı.", "Could not read ports."))
        }
        let rough = PortScan.listeners(from: text, myUID: myUID, selfPID: selfPID)
        let commands = commandLines(pids: Array(Set(rough.map(\.pid))))
        let ports = PortScan.listeners(
            from: text,
            myUID: myUID,
            selfPID: selfPID,
            commandLines: commands
        )
        return Result(ports: ports, error: nil)
    }

    private static func commandLines(pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        var map: [Int32: String] = [:]
        var start = 0
        while start < pids.count {
            let end = min(start + 80, pids.count)
            let chunk = pids[start..<end].map(String.init).joined(separator: ",")
            start = end
            guard let result = try? ProcessRunner.output(
                "/bin/ps",
                arguments: ["-ww", "-p", chunk, "-o", "pid=,command="],
                timeout: 4
            ), let text = String(data: result.data, encoding: .utf8) else { continue }
            map.merge(PortScan.commandLines(from: text)) { _, new in new }
        }
        return map
    }

    /// Bütün kurulmuş soketler değil, yalnızca dinlenen portlara düşenler.
    /// Tarayıcının kendi bağlantılarını saymak listeyi şişirirdi.
    static func connectionCounts(on ports: Set<Int>) -> [Int: Int] {
        guard !ports.isEmpty,
              let result = try? ProcessRunner.output(
                "/usr/sbin/lsof",
                arguments: ["-nP", "-iTCP", "-sTCP:ESTABLISHED", "-F", "Pn"],
                timeout: 8
              ),
              let text = String(data: result.data, encoding: .utf8) else { return [:] }
        let counts = PortScan.establishedCounts(from: text)
        return counts.filter { ports.contains($0.key) }
    }
}
