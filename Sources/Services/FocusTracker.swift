import AppKit
import Foundation

/// Derin çalışma süresini kendiliğinden ölçer.
///
/// Panodaki en değerli satır bu, çünkü sıfır sürtünmeli: kullanıcı hiçbir şey
/// girmiyor. Ölçüt basit ve dürüst — öndeki uygulama çalışma listesindeyse ve
/// makine boşta değilse, geçen süre sayılır. Uygulama açık ama sen masadan
/// kalkmışsan sayılmaz.
@MainActor
final class FocusTracker {
    static let shared = FocusTracker()

    /// Bu süre boyunca hiç giriş olmazsa masa başında sayılmaz.
    private let idleCutoff: TimeInterval = 120
    /// Örnekleme aralığı; her örnek bu kadar süre ekler.
    private let tick: TimeInterval = 30

    private var timer: Timer?
    private var apps: [String] = []
    private var enabled = false

    private init() {}

    func start(apps: [String], enabled: Bool) {
        self.apps = apps.map { $0.lowercased() }
        self.enabled = enabled
        timer?.invalidate()
        guard enabled else { return }
        let timer = Timer(timeInterval: tick, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        enabled = false
    }

    /// Şu an çalışma sayılan uygulama hangisi? (nil ise sayılmıyor)
    var currentApp: String? {
        guard enabled, let front = NSWorkspace.shared.frontmostApplication else { return nil }
        guard matches(front) else { return nil }
        return front.localizedName
    }

    private func sample() {
        guard enabled, !DeviceModes.shared.isCleaning else { return }
        guard let front = NSWorkspace.shared.frontmostApplication, matches(front) else { return }
        guard Self.idleSeconds() < idleCutoff else { return }
        DailyLog.shared.add(Metric.focusSeconds, tick)
    }

    private func matches(_ app: NSRunningApplication) -> Bool {
        let name = (app.localizedName ?? "").lowercased()
        let bundle = (app.bundleIdentifier ?? "").lowercased()
        return apps.contains { needle in
            !needle.isEmpty && (name.contains(needle) || bundle.contains(needle))
        }
    }

    /// Son klavye/fare olayından bu yana geçen süre.
    static func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .init(rawValue: ~0)!)
    }

    /// Varsayılan çalışma uygulamaları: yazılım işinde sık kullanılanlar.
    /// Ad ya da bundle kimliği bu parçalardan birini içeriyorsa sayılır.
    nonisolated static let defaultApps = [
        "terminal", "iterm", "ghostty", "warp", "alacritty", "kitty",
        "xcode", "code", "cursor", "zed", "sublime", "nova", "windsurf",
        "intellij", "webstorm", "pycharm", "goland", "android studio",
        "figma", "tower", "fork", "postman", "tableplus"
    ]
}
