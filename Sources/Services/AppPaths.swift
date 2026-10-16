import Foundation

/// Uygulamanın yerel veri klasörü: `~/Library/Application Support/Hal`.
enum AppPaths {
    private static let folder = "Hal"

    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    }

    static let support: URL = {
        let current = applicationSupport.appendingPathComponent(folder)
        try? FileManager.default.createDirectory(
            at: current,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return current
    }()
}
