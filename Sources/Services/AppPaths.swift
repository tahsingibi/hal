import Foundation

/// Uygulamanın yerel veri klasörü ve eski klasörden göç.
///
/// Uygulama "Hilal" adıyla yazılmıştı; yeniden adlandırmada klasörü de taşıyoruz.
/// Göç yalnızca yeni klasör yokken ve eski klasör varken, bir kez çalışır.
/// Bundle kimliği (`dev.sungur.Hilal`) bilerek değiştirilmedi: değişseydi tüm
/// ayarlar, bildirim izni ve açılışta başlatma kaydı sıfırlanırdı.
enum AppPaths {
    private static let folder = "Hal"
    private static let legacyFolder = "Hilal"

    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    }

    static let support: URL = {
        let base = applicationSupport
        let current = base.appendingPathComponent(folder)
        let legacy = base.appendingPathComponent(legacyFolder)
        let manager = FileManager.default
        if !manager.fileExists(atPath: current.path), manager.fileExists(atPath: legacy.path) {
            try? manager.moveItem(at: legacy, to: current)
        }
        try? manager.createDirectory(
            at: current,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return current
    }()
}
