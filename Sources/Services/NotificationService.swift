import Foundation
import UserNotifications

/// Modülden bağımsız bildirim borusu.
///
/// Modüller (namaz, kota, ileride odak/sağlık) yalnızca `Alert` üretir; ne zaman
/// gönderileceğine, tekrarın nasıl engelleneceğine ve iznin ne zaman isteneceğine
/// burası karar verir. Yeni bir modül eklerken bildirim tarafında yazılacak tek şey
/// kendi `Alert`'lerini üretmektir.
struct Alert: Equatable, Sendable {
    /// Aynı olayın tekrar tekrar bildirilmemesi için kalıcı kimlik.
    var id: String
    var title: String
    var body: String
    /// Gelecekteki bir an için planlanır; nil ise hemen gönderilir.
    var fireAt: Date?
    /// Tıklanınca açılacak popover hedefi (`today/end` gibi).
    var target: String? = nil

    var isScheduled: Bool { fireAt != nil }
}

enum NotificationRoute {
    static let targetKey = "hal.target"
}

extension Notification.Name {
    static let hilalOpenTarget = Notification.Name("hilal.openTarget")
}

/// Bildirim tıklamasını yakalar. `UNUserNotificationCenter.delegate` zayıf referans
/// tuttuğu için bu nesne `NotificationService` içinde güçlü tutulur.
private final class NotificationTapHandler: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let target = response.notification.request.content.userInfo[NotificationRoute.targetKey] as? String
        DispatchQueue.main.async {
            Task { @MainActor in
                NotificationService.shared.handleTap(target: target)
            }
        }
        completionHandler()
    }
}

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let deliveredKey = "hilal.notify.delivered"
    private let tapHandler = NotificationTapHandler()
    private var authorized: Bool?
    /// Uygulama henüz menü çubuğunu kurmadan tıklanırsa hedef burada bekler.
    private(set) var pendingTarget: String?

    private init() {
        center.delegate = tapHandler
    }

    /// Delegate'i uygulama ayağa kalkmadan önce bağlar; tıklama kaybolmasın.
    func install() {
        center.delegate = tapHandler
    }

    func handleTap(target: String?) {
        pendingTarget = target
        guard let target else { return }
        NotificationCenter.default.post(
            name: .hilalOpenTarget,
            object: nil,
            userInfo: [NotificationRoute.targetKey: target]
        )
    }

    func takePendingTarget() -> String? {
        defer { pendingTarget = nil }
        return pendingTarget
    }

    /// İzni yalnızca kullanıcı bir bildirimi açtığında ister; açılışta sormaz.
    @discardableResult
    func ensureAuthorized() async -> Bool {
        if let authorized { return authorized }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            authorized = true
        case .notDetermined:
            authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            authorized = false
        }
        return authorized ?? false
    }

    /// Kullanıcı ayarlardan bildirimi kapatıp açtığında izin durumunu yeniden sorgular.
    func resetAuthorizationCache() {
        authorized = nil
    }

    /// Anlık bildirim. Aynı `id` ile daha önce gönderildiyse tekrar gönderilmez.
    func post(_ alert: Alert) async {
        guard await ensureAuthorized(), !alert.isScheduled else { return }
        guard markDelivered(alert.id) else { return }
        let request = UNNotificationRequest(
            identifier: "now.\(alert.id)",
            content: Self.content(for: alert),
            trigger: nil
        )
        try? await center.add(request)
    }

    /// Verilen kimlik önekine sahip planlı bildirimleri tamamen yeniler.
    /// Vakitler her yenilemede yeniden hesaplandığı için sil-yeniden kur en güvenlisi.
    func reschedule(prefix: String, alerts: [Alert]) async {
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
        guard !alerts.isEmpty, await ensureAuthorized() else { return }

        for alert in alerts {
            guard let fireAt = alert.fireAt, fireAt.timeIntervalSinceNow > 5 else { continue }
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireAt
            )
            let request = UNNotificationRequest(
                identifier: "\(prefix)\(alert.id)",
                content: Self.content(for: alert),
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    func cancel(prefix: String) async {
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
    }

    private static func content(for alert: Alert) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        if let target = alert.target {
            content.userInfo = [NotificationRoute.targetKey: target]
        }
        return content
    }

    // MARK: - Tekrar engelleme

    /// Gönderilen kimlikleri saklar; aynı sıfırlanma ya da eşik iki kez bildirilmez.
    /// Liste sınırlı tutulur, süresiz büyümez.
    private func markDelivered(_ id: String) -> Bool {
        var seen = UserDefaults.standard.stringArray(forKey: deliveredKey) ?? []
        guard !seen.contains(id) else { return false }
        seen.append(id)
        if seen.count > 200 { seen.removeFirst(seen.count - 200) }
        UserDefaults.standard.set(seen, forKey: deliveredKey)
        return true
    }
}
