import Foundation
import SwiftUI

/// Uygulamadaki bir modül: popover'da bir sekmesi, menü çubuğunda sıfır veya
/// daha çok ikonu, isteğe bağlı bildirimleri olur.
///
/// Yeni modül eklemek için dokunulacak yerler:
///  1. Buraya bir `case` ve üstteki meta bilgiler (`title`, `symbol`)
///  2. `AppStore.pages(for:)` — modülün sayfaları
///  3. `DetailPopoverView.page(for:)` — sayfanın görünümü
///  4. Modülün kendi dosyası (veri kaynağı) ve gerekiyorsa `ModuleAlerts` içinde uyarıları
///
/// Sıralama `allCases` sırasıdır; sekmeler de menü çubuğu da bunu izler.
enum ModuleKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case today
    case focus
    case usage
    case prayer
    case calendar
    case fitness
    case money

    /// Ana panoda yer alan modüller. İndirici kalıcı bir durum değil, tek seferlik araçtır.
    static var dashboardCases: [ModuleKind] {
        [.today, .focus, .usage, .prayer, .calendar, .fitness, .money]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return L("Bugün", "Today")
        case .focus: return L("Odak", "Focus")
        case .usage: return L("Kotalar", "Quotas")
        case .prayer: return L("İbadet", "Prayer")
        case .calendar: return L("Takvim", "Calendar")
        case .fitness: return L("Sağlık", "Health")
        case .money: return L("Ödemeler", "Payments")
        }
    }

    /// Sekme başlığının yanındaki SF Symbol.
    var symbol: String {
        switch self {
        case .today: return "sun.horizon"
        case .focus: return "scope"
        case .usage: return "gauge.with.dots.needle.67percent"
        case .prayer: return "moon.stars"
        case .calendar: return "calendar"
        case .fitness: return "figure.strengthtraining.traditional"
        case .money: return "creditcard"
        }
    }

    /// Kullanıcı kapatabilir mi? Kapatılan modül sekmelerden ve menü çubuğundan düşer.
    var canDisable: Bool { self != .today }

    /// Panoya satır veren modüller. `today` kendi kendini toplayamaz.
    var contributesToSummary: Bool { self != .today }
}

/// Panoda tek bir satır. Her modül bunu üreterek "Bugün" ekranına katılır;
/// pano tarafında yeni modül için yazılacak kod yoktur.
struct SummaryLine: Identifiable, Equatable {
    var id: String
    /// SF Symbol adı.
    var icon: String
    var title: String
    var value: String
    var detail: String?
    /// 0…1 arası; verildiğinde satırın altında ince bir çubuk çizilir.
    var progress: Double?
    var tintHex: String?
    /// Tıklanınca gidilecek sekme.
    var target: DetailTarget?
    /// Ayarlardaki satır listesinde kullanılacak sabit ad. Başlığı gün içinde
    /// değişen satırlar (sıradaki vakit, sonraki olay) için gerekli: kullanıcı
    /// "İmsak" yazan bir anahtarı kapattığında akşam "Akşam"ı kapatmış olmamalı.
    var catalogTitle: String?

    var tint: Color? {
        tintHex.map { Color(hex: $0) }
    }
}

/// Panoda görülebilecek bir satırın kaydı: kimliği, o anki başlığı ve hangi
/// modülden geldiği. Satırlar koşullu üretiliyor (dolu kota, sıradaki olay,
/// bugünün ilaç dozu); yalnızca "şu an ekranda olanı" listeleseydik çoğu satırı
/// gizleme şansı hiç doğmazdı. Bu yüzden bir kez görülen satır kayıtta kalır.
struct SummaryLineRef: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String
    var title: String
    var module: ModuleKind
}

/// Popover'da gösterilen tek bir sayfa. Bir modül birden çok sayfa üretebilir
/// (kota modülü her sağlayıcı için bir sayfa verir), ya da tek sayfa (namaz).
struct ModulePage: Identifiable, Equatable, Sendable {
    var module: ModuleKind
    /// Modül içi kimlik; tek sayfalı modüllerde nil.
    var item: String?
    var title: String
    var icon: BrandIcon
    /// Menü çubuğunda kendi ikonu olabilecek sayfalar için kimlik.
    var menuBarID: String?

    var id: String { target.id }

    var target: DetailTarget {
        DetailTarget(module: module, item: item)
    }
}

/// Popover'da neyin seçili olduğunu tarif eder.
/// Eski `HoverTarget` yalnızca kota ve namazı tanıyordu; bu yapı modülden bağımsız.
struct DetailTarget: Equatable, Hashable, Sendable {
    var module: ModuleKind
    var item: String?

    init(module: ModuleKind, item: String? = nil) {
        self.module = module
        self.item = item
    }

    /// Kalıcı biçim: "usage/claude", "prayer".
    var id: String {
        guard let item, !item.isEmpty else { return module.rawValue }
        return "\(module.rawValue)/\(item)"
    }

    init?(id: String) {
        // Eski sürümde İndirici bir pano modülüydü; artık Ayarlar > Araçlar’da.
        if id == "downloader" || id.hasPrefix("downloader/") {
            self = DetailTarget(module: .today)
            return
        }
        let parts = id.split(separator: "/", maxSplits: 1).map(String.init)
        guard let first = parts.first, let module = ModuleKind(rawValue: first) else {
            // Eski kayıtlar yalnızca kota kimliği ya da "prayer" tutuyordu.
            if id == "prayer" { self = DetailTarget(module: .prayer); return }
            if id.isEmpty { return nil }
            self = DetailTarget(module: .usage, item: id)
            return
        }
        self = DetailTarget(module: module, item: parts.count > 1 ? parts[1] : nil)
    }
}

enum MenuBarSummary {
    static let id = "summary"
}
