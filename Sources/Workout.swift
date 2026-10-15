import Foundation

/// Haftalık antrenman programı ve geçmişi.
///
/// Bilerek sade: gün başına bir plan etiketi ve "yapıldı" işareti. Set/tekrar/ağırlık
/// kaydı bu uygulamanın şekline uymuyor — 336 piksellik bir popover'da her seti girmek
/// sürtünmesi yüksek bir iş ve o veriyi hak eden ayrı bir uygulama zaten var.
/// Buradaki soru şu: bugün ne var, yaptım mı, kaç gündür sürüyor.
enum Workout {
    /// Program haftanın günlerine göre; 0 = Pazartesi.
    static let dayNames = ["Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"]
    static let shortNames = ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"]

    static let defaultPlan = [
        "Göğüs + Triceps",
        "Sırt + Biceps",
        "Dinlenme",
        "Bacak",
        "Omuz + Karın",
        "Kardiyo",
        "Dinlenme"
    ]

    /// Pazartesi = 0 olacak biçimde gün indeksi.
    static func index(for date: Date, calendar: Calendar = .current) -> Int {
        // Calendar.weekday: 1 = Pazar … 7 = Cumartesi
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    static func plan(_ plan: [String], on date: Date) -> String {
        let i = index(for: date)
        guard plan.indices.contains(i) else { return "" }
        return plan[i].trimmingCharacters(in: .whitespaces)
    }

    /// Dinlenme günü mü? Boş ya da "dinlenme" yazan günler antrenman sayılmaz.
    static func isRestDay(_ label: String) -> Bool {
        let text = label.trimmingCharacters(in: .whitespaces).lowercased()
        return text.isEmpty || text == "dinlenme" || text == "off" || text == "rest"
    }
}
