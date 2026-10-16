import Foundation

/// Haftalık antrenman programı ve geçmişi.
///
/// Bilerek sade: gün başına bir plan etiketi ve "yapıldı" işareti. Set/tekrar/ağırlık
/// kaydı bu uygulamanın şekline uymuyor — 336 piksellik bir popover'da her seti girmek
/// sürtünmesi yüksek bir iş ve o veriyi hak eden ayrı bir uygulama zaten var.
/// Buradaki soru şu: bugün ne var, yaptım mı, kaç gündür sürüyor.
enum Workout {
    /// Program haftanın günlerine göre; 0 = Pazartesi.
    static var dayNames: [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Language.locale
        let symbols = calendar.weekdaySymbols
        return (0..<7).map { symbols[($0 + 1) % 7] }
    }

    static var shortNames: [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Language.locale
        let symbols = calendar.shortWeekdaySymbols
        return (0..<7).map { symbols[($0 + 1) % 7] }
    }

    /// Yeni kurulumda o anki dile göre dolar. Kaydedilmiş program dil değişince yeniden yazılmaz.
    static var defaultPlan: [String] {
        [
            L("Göğüs + Triceps", "Chest + triceps"),
            L("Sırt + Biceps", "Back + biceps"),
            L("Dinlenme", "Rest"),
            L("Bacak", "Legs"),
            L("Omuz + Karın", "Shoulders + core"),
            L("Kardiyo", "Cardio"),
            L("Dinlenme", "Rest")
        ]
    }

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
