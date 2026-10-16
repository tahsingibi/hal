import EventKit
import Foundation

/// Takvim erişimi. **Kendiliğinden izin istemez.**
///
/// İzin yalnızca kullanıcı Ayarlar'dan açıkça "Takvime bağlan" dediğinde sorulur.
/// Bu bilinçli: bu uygulamada habersiz açılan sistem izin pencereleriyle yeterince
/// uğraşıldı. İzin yoksa modül sessizce boş kalır, hata göstermez.
@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    private let store = EKEventStore()
    @Published private(set) var events: [CalendarEvent] = []

    private init() {}

    enum Access {
        case granted
        case denied
        case notDetermined
    }

    var access: Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        default:
            return .denied
        }
    }

    /// Yalnızca kullanıcı isteğiyle çağrılır.
    @discardableResult
    func requestAccess() async -> Bool {
        guard access == .notDetermined else { return access == .granted }
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        if granted { reload() }
        return granted
    }

    /// Bugünün kalan olayları. İzin yoksa boş liste; istek yapılmaz.
    func reload(now: Date = Date()) {
        guard access == .granted else {
            events = []
            return
        }
        let calendar = Calendar.current
        let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-1800), end: end, calendars: nil)
        events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .prefix(8)
            .map {
                CalendarEvent(
                    id: $0.eventIdentifier ?? UUID().uuidString,
                    title: $0.title ?? L("Başlıksız", "Untitled"),
                    start: $0.startDate,
                    end: $0.endDate,
                    calendarName: $0.calendar?.title ?? ""
                )
            }
    }

    /// Şu andan sonraki ilk olay.
    func next(after now: Date = Date()) -> CalendarEvent? {
        events.first { $0.start > now } ?? events.first { $0.end > now }
    }
}

struct CalendarEvent: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var calendarName: String

    func isRunning(at now: Date) -> Bool {
        start <= now && end > now
    }
}
