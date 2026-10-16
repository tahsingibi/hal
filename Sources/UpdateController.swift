import AppKit
import Sparkle

/// Güncelleme denetimi. Yeni sürüm inince kurulumu kendisi yapmaz; sorar.
@MainActor
enum UpdateController {
    private static var controller: SPUStandardUpdaterController?

    static func start() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    static func check() {
        start()
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }
}
