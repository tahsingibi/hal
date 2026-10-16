import AppKit
import Foundation
import SwiftUI

enum DockEdge: String, Codable, CaseIterable, Sendable, Identifiable {
    case top, bottom, leading, trailing

    var id: String { rawValue }

    var isVertical: Bool { self == .leading || self == .trailing }

    var title: String {
        switch self {
        case .top: return L("Üst", "Top")
        case .bottom: return L("Alt", "Bottom")
        case .leading: return L("Sol", "Left")
        case .trailing: return L("Sağ", "Right")
        }
    }
}

enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case grok
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .grok: return "Grok"
        case .custom: return L("Özel", "Custom")
        }
    }

    var symbol: String {
        switch self {
        case .claude: return "sparkle"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .grok: return "xmark"
        case .custom: return "star"
        }
    }

    var accentHex: String {
        switch self {
        case .claude: return "D97757"
        case .codex: return "10A37F"
        case .grok: return "8A8A8A"
        case .custom: return "E8B84A"
        }
    }
}

enum CustomSourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual
    case command
    case url

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return L("Manuel", "Manual")
        case .command: return L("Komut", "Command")
        case .url: return "URL"
        }
    }
}

struct CustomProvider: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var name: String
    var enabled: Bool
    var accentHex: String
    var source: CustomSourceKind
    var used: Double
    var limit: Double
    var command: String
    var url: String
    var token: String

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, accentHex, source, used, limit, command, url, token
    }

    init(
        id: UUID = UUID(),
        name: String,
        enabled: Bool = true,
        accentHex: String = "E8B84A",
        source: CustomSourceKind = .manual,
        used: Double = 0,
        limit: Double = 100,
        command: String = "",
        url: String = "",
        token: String = ""
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.accentHex = accentHex
        self.source = source
        self.used = used
        self.limit = limit
        self.command = command
        self.url = url
        self.token = token
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        accentHex = try c.decodeIfPresent(String.self, forKey: .accentHex) ?? "E8B84A"
        source = try c.decodeIfPresent(CustomSourceKind.self, forKey: .source) ?? .manual
        used = try c.decodeIfPresent(Double.self, forKey: .used) ?? 0
        limit = try c.decodeIfPresent(Double.self, forKey: .limit) ?? 100
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
    }
}

/// Menü çubuğundaki bir ikona tıklayınca ne açılsın?
enum MenuBarClickTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Hangi ikona basılırsa basılsın pano açılır.
    case today
    /// İkon ne gösteriyorsa onun detayı açılır. Özet ve genel ikon yine panoya gider,
    /// çünkü onlar zaten "genel bakış" demek.
    case item

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return L("Bugün panosu", "Today board")
        case .item: return L("Tıklanan öğenin detayı", "The clicked item")
        }
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var claudeEnabled: Bool = false
    var codexEnabled: Bool = false
    /// Eski ayar dosyalarında duran anahtar. Artık okunmaz; yeni kurulumda kapalı kalır.
    var fxEnabled: Bool = false
    var grokEnabled: Bool = false
    var customProviders: [CustomProvider] = []
    var country: String = ""
    var countryCode: String = ""
    var state: String = ""
    var city: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var method: Int = 13
    var school: Int = 0
    var launchAtLogin: Bool = false
    var expandOnHover: Bool = false
    var showSunrise: Bool = true
    var dockEdge: DockEdge = .trailing
    var dockOffset: Double = 0.55
    var dockDisplayID: UInt32 = 0
    var alwaysWake: Bool = false
    var menuBarVisible: [String] = []
    var mirrorToOtherDisplays: Bool = false
    /// Açıkken kota ikonları tek bir özet ikonda toplanır.
    var menuBarCollapsed: Bool = false
    var menuBarClickOpens: MenuBarClickTarget = .today
    var notifyPrayer: Bool = false
    /// Vakitten kaç dakika önce bildirilsin; 0 ise vaktin tam saatinde.
    var notifyPrayerMinutes: Int = 10
    var notifyQuotaReset: Bool = false
    var notifyQuotaThreshold: Bool = false
    /// Eşik yüzdesi (0-100).
    var notifyQuotaThresholdPercent: Int = 80
    /// Kapatılan modüller; boşsa hepsi açık.
    var disabledModules: [String] = []
    /// Panodaki selamlamada kullanılır; boşsa yalnızca selam yazılır.
    var displayName: String = ""
    /// Temizlik kalkanındaki büyük başlık; boşsa “Temizlik modu”.
    var cleaningTitle: String = ""
    /// Temizlik kalkanındaki açıklama; boşsa varsayılan kilit metni.
    var cleaningHint: String = ""
    var focusTracking: Bool = true
    /// Bugünkü derin çalışma hedefi. Sıfır hedefi kapatır, ölçümü değil.
    var focusGoalMinutes: Int = 240
    /// Derin çalışma sayılan uygulamalar (ad ya da bundle kimliği parçası).
    var focusApps: [String] = FocusTracker.defaultApps
    var trackPrayers: Bool = true
    var waterGoalML: Double = 3000
    var proteinGoalG: Double = 180
    /// Hızlı giriş adımları.
    var waterStepML: Double = 250
    var proteinStepG: Double = 30
    /// 0 ise su/protein satırları panoda görünmez.
    var trackIntake: Bool = false
    var subscriptions: [Subscription] = []
    /// Yenilemeden kaç gün önce haber verilsin.
    var notifyRenewalDays: Int = 3
    var trackMedication: Bool = false
    var medications: [Medication] = []
    /// Doz saatinde bildirim gönder.
    var notifyMedication: Bool = true
    var trackWorkout: Bool = false
    var workoutPlan: [String] = Workout.defaultPlan
    var downloadFormat: DownloadService.Format = .mp4
    /// Boşsa masaüstüne iner.
    var downloadFolder: String = ""
    /// yt-dlp'yi günde bir kez ve çıkarıcı hatasında güncelle.
    var downloaderAutoUpdate: Bool = true
    var notifyDailySummary: Bool = false
    /// Gün özeti bildiriminin saati (0-23).
    var dailySummaryHour: Int = 21
    /// Gün sonu hatırlatması; tıklanınca Gün Sonu sayfası açılır.
    var notifyDayClose: Bool = true
    /// Gün sonu hatırlatmasının saati (0-23).
    var dayCloseHour: Int = 12
    /// Bugün panosunda gizlenen satırların kimlikleri.
    var hiddenSummaryLines: [String] = []
    /// Yoksa sistem dili. Türkçe değilse İngilizce.
    var language: LanguageChoice = .system

    var downloadDestination: URL {
        let trimmed = downloadFolder.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? DownloadService.defaultDestination : URL(fileURLWithPath: trimmed)
    }

    var locationLabel: String {
        [city, state].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Şehir adı ve gerçek bir koordinat varsa vakit istenir. 0,0 (Gine Körfezi) konum sayılmaz.
    var hasLocation: Bool {
        let name = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, latitude.isFinite, longitude.isFinite else { return false }
        return !(latitude == 0 && longitude == 0)
    }

    static var defaultCleaningTitle: String { L("Temizlik modu", "Cleaning mode") }
    static var defaultCleaningHint: String {
        L(
            "Klavye ve trackpad tıklamaları kilitli.\nKapatmak için düğmeye veya Hâl ikonuna tıklayın.",
            "Keyboard and trackpad clicks are locked.\nClick the button or the Hâl icon to stop."
        )
    }
    static var defaultCleaningButtonTitle: String { L("Temizlik modunu kapat", "Stop cleaning mode") }

    var resolvedCleaningTitle: String {
        let trimmed = cleaningTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultCleaningTitle : trimmed
    }

    var resolvedCleaningHint: String {
        let trimmed = cleaningHint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultCleaningHint : trimmed
    }

    var resolvedCleaningButtonTitle: String {
        cleaningTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultCleaningButtonTitle
            : L("Kapat", "Stop")
    }

    var resolvedCleaningMenuTitle: String {
        let trimmed = cleaningTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L("Temizlik", "Cleaning") : trimmed
    }

    enum CodingKeys: String, CodingKey {
        case claudeEnabled, codexEnabled, fxEnabled, grokEnabled, customProviders
        case country, countryCode, state, city, latitude, longitude, method, school
        case launchAtLogin, expandOnHover, showSunrise, dockEdge, dockOffset, dockDisplayID, alwaysWake
        case menuBarVisible, menuBarHidden, mirrorToOtherDisplays, menuBarCollapsed, menuBarClickOpens
        case notifyPrayer, notifyPrayerMinutes
        case notifyQuotaReset, notifyQuotaThreshold, notifyQuotaThresholdPercent
        case disabledModules, displayName, cleaningTitle, cleaningHint
        case focusTracking, focusGoalMinutes, focusApps, trackPrayers
        case waterGoalML, proteinGoalG, trackIntake, notifyDailySummary, dailySummaryHour
        case notifyDayClose, dayCloseHour
        case subscriptions, notifyRenewalDays
        case trackWorkout, workoutPlan
        case trackMedication, medications, notifyMedication
        case downloadFormat, downloadFolder, waterStepML, proteinStepG, downloaderAutoUpdate
        case hiddenSummaryLines, language
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        claudeEnabled = try c.decodeIfPresent(Bool.self, forKey: .claudeEnabled) ?? false
        codexEnabled = try c.decodeIfPresent(Bool.self, forKey: .codexEnabled) ?? false
        fxEnabled = try c.decodeIfPresent(Bool.self, forKey: .fxEnabled) ?? false
        grokEnabled = try c.decodeIfPresent(Bool.self, forKey: .grokEnabled) ?? false
        customProviders = try c.decodeIfPresent([CustomProvider].self, forKey: .customProviders) ?? []
        country = try c.decodeIfPresent(String.self, forKey: .country) ?? ""
        countryCode = try c.decodeIfPresent(String.self, forKey: .countryCode) ?? ""
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude) ?? 0
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude) ?? 0
        method = try c.decodeIfPresent(Int.self, forKey: .method) ?? 13
        school = try c.decodeIfPresent(Int.self, forKey: .school) ?? 0
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        expandOnHover = try c.decodeIfPresent(Bool.self, forKey: .expandOnHover) ?? false
        showSunrise = try c.decodeIfPresent(Bool.self, forKey: .showSunrise) ?? true
        dockEdge = try c.decodeIfPresent(DockEdge.self, forKey: .dockEdge) ?? .trailing
        dockOffset = try c.decodeIfPresent(Double.self, forKey: .dockOffset) ?? 0.55
        dockDisplayID = try c.decodeIfPresent(UInt32.self, forKey: .dockDisplayID) ?? 0
        alwaysWake = try c.decodeIfPresent(Bool.self, forKey: .alwaysWake) ?? false
        if let visible = try c.decodeIfPresent([String].self, forKey: .menuBarVisible) {
            menuBarVisible = visible
        } else {
            menuBarVisible = []
        }
        mirrorToOtherDisplays = try c.decodeIfPresent(Bool.self, forKey: .mirrorToOtherDisplays) ?? false
        menuBarCollapsed = try c.decodeIfPresent(Bool.self, forKey: .menuBarCollapsed) ?? false
        menuBarClickOpens = try c.decodeIfPresent(MenuBarClickTarget.self, forKey: .menuBarClickOpens) ?? .today
        notifyPrayer = try c.decodeIfPresent(Bool.self, forKey: .notifyPrayer) ?? false
        notifyPrayerMinutes = try c.decodeIfPresent(Int.self, forKey: .notifyPrayerMinutes) ?? 10
        notifyQuotaReset = try c.decodeIfPresent(Bool.self, forKey: .notifyQuotaReset) ?? false
        notifyQuotaThreshold = try c.decodeIfPresent(Bool.self, forKey: .notifyQuotaThreshold) ?? false
        notifyQuotaThresholdPercent = try c.decodeIfPresent(Int.self, forKey: .notifyQuotaThresholdPercent) ?? 80
        disabledModules = try c.decodeIfPresent([String].self, forKey: .disabledModules) ?? []
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        cleaningTitle = try c.decodeIfPresent(String.self, forKey: .cleaningTitle) ?? ""
        cleaningHint = try c.decodeIfPresent(String.self, forKey: .cleaningHint) ?? ""
        focusTracking = try c.decodeIfPresent(Bool.self, forKey: .focusTracking) ?? true
        focusGoalMinutes = try c.decodeIfPresent(Int.self, forKey: .focusGoalMinutes) ?? 240
        focusApps = try c.decodeIfPresent([String].self, forKey: .focusApps) ?? FocusTracker.defaultApps
        trackPrayers = try c.decodeIfPresent(Bool.self, forKey: .trackPrayers) ?? true
        waterGoalML = try c.decodeIfPresent(Double.self, forKey: .waterGoalML) ?? 3000
        proteinGoalG = try c.decodeIfPresent(Double.self, forKey: .proteinGoalG) ?? 180
        trackIntake = try c.decodeIfPresent(Bool.self, forKey: .trackIntake) ?? false
        notifyDailySummary = try c.decodeIfPresent(Bool.self, forKey: .notifyDailySummary) ?? false
        dailySummaryHour = try c.decodeIfPresent(Int.self, forKey: .dailySummaryHour) ?? 21
        notifyDayClose = try c.decodeIfPresent(Bool.self, forKey: .notifyDayClose) ?? true
        dayCloseHour = try c.decodeIfPresent(Int.self, forKey: .dayCloseHour) ?? 12
        subscriptions = try c.decodeIfPresent([Subscription].self, forKey: .subscriptions) ?? []
        notifyRenewalDays = try c.decodeIfPresent(Int.self, forKey: .notifyRenewalDays) ?? 3
        downloadFormat = try c.decodeIfPresent(DownloadService.Format.self, forKey: .downloadFormat) ?? .mp4
        downloadFolder = try c.decodeIfPresent(String.self, forKey: .downloadFolder) ?? ""
        downloaderAutoUpdate = try c.decodeIfPresent(Bool.self, forKey: .downloaderAutoUpdate) ?? true
        waterStepML = try c.decodeIfPresent(Double.self, forKey: .waterStepML) ?? 250
        proteinStepG = try c.decodeIfPresent(Double.self, forKey: .proteinStepG) ?? 30
        trackMedication = try c.decodeIfPresent(Bool.self, forKey: .trackMedication) ?? false
        medications = try c.decodeIfPresent([Medication].self, forKey: .medications) ?? []
        notifyMedication = try c.decodeIfPresent(Bool.self, forKey: .notifyMedication) ?? true
        trackWorkout = try c.decodeIfPresent(Bool.self, forKey: .trackWorkout) ?? false
        hiddenSummaryLines = try c.decodeIfPresent([String].self, forKey: .hiddenSummaryLines) ?? []
        language = try c.decodeIfPresent(LanguageChoice.self, forKey: .language) ?? .system
        let storedPlan = try c.decodeIfPresent([String].self, forKey: .workoutPlan) ?? Workout.defaultPlan
        workoutPlan = storedPlan.count == 7 ? storedPlan : Workout.defaultPlan
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(claudeEnabled, forKey: .claudeEnabled)
        try c.encode(codexEnabled, forKey: .codexEnabled)
        try c.encode(fxEnabled, forKey: .fxEnabled)
        try c.encode(grokEnabled, forKey: .grokEnabled)
        try c.encode(customProviders, forKey: .customProviders)
        try c.encode(country, forKey: .country)
        try c.encode(countryCode, forKey: .countryCode)
        try c.encode(state, forKey: .state)
        try c.encode(city, forKey: .city)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encode(method, forKey: .method)
        try c.encode(school, forKey: .school)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(expandOnHover, forKey: .expandOnHover)
        try c.encode(showSunrise, forKey: .showSunrise)
        try c.encode(dockEdge, forKey: .dockEdge)
        try c.encode(dockOffset, forKey: .dockOffset)
        try c.encode(dockDisplayID, forKey: .dockDisplayID)
        try c.encode(alwaysWake, forKey: .alwaysWake)
        try c.encode(menuBarVisible, forKey: .menuBarVisible)
        try c.encode(mirrorToOtherDisplays, forKey: .mirrorToOtherDisplays)
        try c.encode(menuBarCollapsed, forKey: .menuBarCollapsed)
        try c.encode(menuBarClickOpens, forKey: .menuBarClickOpens)
        try c.encode(notifyPrayer, forKey: .notifyPrayer)
        try c.encode(notifyPrayerMinutes, forKey: .notifyPrayerMinutes)
        try c.encode(notifyQuotaReset, forKey: .notifyQuotaReset)
        try c.encode(notifyQuotaThreshold, forKey: .notifyQuotaThreshold)
        try c.encode(notifyQuotaThresholdPercent, forKey: .notifyQuotaThresholdPercent)
        try c.encode(disabledModules, forKey: .disabledModules)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(cleaningTitle, forKey: .cleaningTitle)
        try c.encode(cleaningHint, forKey: .cleaningHint)
        try c.encode(focusTracking, forKey: .focusTracking)
        try c.encode(focusGoalMinutes, forKey: .focusGoalMinutes)
        try c.encode(focusApps, forKey: .focusApps)
        try c.encode(trackPrayers, forKey: .trackPrayers)
        try c.encode(waterGoalML, forKey: .waterGoalML)
        try c.encode(proteinGoalG, forKey: .proteinGoalG)
        try c.encode(trackIntake, forKey: .trackIntake)
        try c.encode(notifyDailySummary, forKey: .notifyDailySummary)
        try c.encode(dailySummaryHour, forKey: .dailySummaryHour)
        try c.encode(notifyDayClose, forKey: .notifyDayClose)
        try c.encode(dayCloseHour, forKey: .dayCloseHour)
        try c.encode(subscriptions, forKey: .subscriptions)
        try c.encode(notifyRenewalDays, forKey: .notifyRenewalDays)
        try c.encode(downloadFormat, forKey: .downloadFormat)
        try c.encode(downloadFolder, forKey: .downloadFolder)
        try c.encode(downloaderAutoUpdate, forKey: .downloaderAutoUpdate)
        try c.encode(waterStepML, forKey: .waterStepML)
        try c.encode(proteinStepG, forKey: .proteinStepG)
        try c.encode(trackMedication, forKey: .trackMedication)
        try c.encode(medications, forKey: .medications)
        try c.encode(notifyMedication, forKey: .notifyMedication)
        try c.encode(trackWorkout, forKey: .trackWorkout)
        try c.encode(workoutPlan, forKey: .workoutPlan)
        try c.encode(hiddenSummaryLines, forKey: .hiddenSummaryLines)
        try c.encode(language, forKey: .language)
    }

    func isModuleEnabled(_ module: ModuleKind) -> Bool {
        if module == .today { return true }
        return !disabledModules.contains(module.rawValue)
    }

    var enabledModules: [ModuleKind] {
        ModuleKind.dashboardCases.filter(isModuleEnabled)
    }

    var anyNotificationEnabled: Bool {
        notifyPrayer || notifyQuotaReset || notifyQuotaThreshold || notifyDailySummary || notifyDayClose
            || (trackMedication && notifyMedication && !medications.isEmpty)
            || (notifyRenewalDays > 0 && !subscriptions.isEmpty)
    }

    func isMenuBarVisible(_ id: String) -> Bool {
        menuBarVisible.contains(id)
    }
}

struct QuotaWindow: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var percent: Double
    var usedText: String
    var resetText: String
    var detail: String?
    /// false ise gerçek bir kota sınırı yok; satır bilgi amaçlıdır, yüzde çubuğu çizilmez.
    var hasLimit: Bool = true
    /// Pencerenin sıfırlanacağı an. Bildirimler ve "sıfırlandı" tespiti bunu kullanır.
    var resetsAt: Date?

    init(
        id: String,
        title: String,
        percent: Double,
        usedText: String,
        resetText: String,
        detail: String? = nil,
        hasLimit: Bool = true,
        resetsAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.percent = percent
        self.usedText = usedText
        self.resetText = resetText
        self.detail = detail
        self.hasLimit = hasLimit
        self.resetsAt = resetsAt
    }

    var clampedPercent: Double {
        min(max(percent, 0), 1)
    }

    var percentText: String {
        "\(Int((clampedPercent * 100).rounded()))%"
    }
}

enum QuotaStatus: Equatable, Sendable {
    case loading
    case ready
    case missingAuth
    case error(String)
}

struct QuotaGroup: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var kind: ProviderKind
    var accentHex: String
    var status: QuotaStatus
    var message: String?
    var windows: [QuotaWindow]
    /// Kota yüzdesi olmayan bir sağlayıcı için menü çubuğunda gösterilecek metin.
    var menuBarOverride: String?

    init(
        id: String,
        name: String,
        kind: ProviderKind,
        accentHex: String,
        status: QuotaStatus,
        message: String?,
        windows: [QuotaWindow],
        menuBarOverride: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.accentHex = accentHex
        self.status = status
        self.message = message
        self.windows = windows
        self.menuBarOverride = menuBarOverride
    }

    var symbol: String { kind.symbol }

    /// Gerçek sınırı olan pencereler; yüzde yalnızca bunlar için anlamlı.
    var meteredWindows: [QuotaWindow] {
        windows.filter(\.hasLimit)
    }

    /// Kullanıcıyı ilk bloklayacak pencere: en dolu olan.
    var headlineWindow: QuotaWindow? {
        meteredWindows.max { $0.clampedPercent < $1.clampedPercent }
    }

    var headlinePercent: Double? {
        headlineWindow?.clampedPercent
    }

    /// Menü çubuğu başlığı. Hata/oturum yokken sayı uydurmaz.
    var menuBarTitle: String {
        switch status {
        case .loading: return "…"
        case .missingAuth: return "–"
        case .error: return "!"
        case .ready:
            if let menuBarOverride { return menuBarOverride }
            guard let percent = headlinePercent else { return "–" }
            return "\(Int((percent * 100).rounded()))%"
        }
    }

    var tooltip: String {
        switch status {
        case .loading:
            return Lf("%1$@: yükleniyor…", "%1$@: loading…", name)
        case .missingAuth:
            return Lf("%1$@: %2$@", "%1$@: %2$@", name, message ?? L("oturum yok", "no session"))
        case .error(let reason):
            return "\(name): \(message ?? reason)"
        case .ready:
            let lines = windows.map { window -> String in
                let value = window.hasLimit ? window.percentText : window.usedText
                return "\(window.title): \(value)"
            }
            return ([name] + lines).joined(separator: "\n")
        }
    }
}

struct PrayerTime: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var time: Date
    var isSunnah: Bool

    var localizedName: String { PrayerCopy.name(id: id) }
}

struct PrayerDay: Equatable, Sendable {
    var gregorian: String
    var hijri: String
    var timezone: String
    var times: [PrayerTime]
    var fetchedAt: Date

    func next(after now: Date = Date(), includeSunrise: Bool = true) -> PrayerTime? {
        let visible = times.filter { includeSunrise || !$0.isSunnah }
        return visible.first { $0.time > now } ?? visible.first { !$0.isSunnah }
    }

    func remaining(to prayer: PrayerTime, now: Date = Date()) -> TimeInterval {
        var target = prayer.time
        if target <= now {
            target = target.addingTimeInterval(24 * 60 * 60)
        }
        return target.timeIntervalSince(now)
    }
}

struct PlaceCountry: Identifiable, Hashable, Sendable {
    var id: String { code }
    var name: String
    var code: String

    /// Listedeki ad. Kayıttaki `settings.country` dil değişince eski dilde kalabilir.
    var localizedName: String { CountryNames.display(code: code, turkish: name) }
}

struct PlaceRegion: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var latitude: Double?
    var longitude: Double?
}

struct PlaceCity: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var latitude: Double?
    var longitude: Double?
}

struct CalculationMethod: Identifiable, Hashable, Sendable {
    var id: Int
    var name: String { CalculationMethods.name(for: id) }
}

enum CalculationMethods {
    static let all: [CalculationMethod] = [13, 3, 2, 5, 4, 1, 8, 9, 10, 7, 14, 12, 21, 19, 18, 17, 20, 23]
        .map { CalculationMethod(id: $0) }

    static func name(for id: Int) -> String {
        switch id {
        case 13: return L("Diyanet İşleri (Türkiye)", "Diyanet (Turkey)")
        case 3: return "Muslim World League"
        case 2: return "ISNA"
        case 5: return L("Mısır", "Egypt")
        case 4: return L("Ümmül-Kura (Mekke)", "Umm al-Qura (Makkah)")
        case 1: return L("Karaçi", "Karachi")
        case 8: return L("Körfez", "Gulf")
        case 9: return L("Kuveyt", "Kuwait")
        case 10: return L("Katar", "Qatar")
        case 7: return L("Tahran", "Tehran")
        case 14: return L("Rusya", "Russia")
        case 12: return L("Fransa", "France")
        case 21: return L("Fas", "Morocco")
        case 19: return L("Cezayir", "Algeria")
        case 18: return L("Tunus", "Tunisia")
        case 17: return L("Malezya (JAKIM)", "Malaysia (JAKIM)")
        case 20: return L("Endonezya (Kemenag)", "Indonesia (Kemenag)")
        case 23: return L("Ürdün", "Jordan")
        default: return "\(id)"
        }
    }

    static func recommended(for countryCode: String) -> (method: Int, school: Int) {
        switch countryCode.uppercased() {
        case "TR": return (13, 0)
        case "US", "CA": return (2, 0)
        case "EG": return (5, 0)
        case "SA", "AE", "QA", "BH", "OM": return (4, 0)
        case "KW": return (9, 0)
        case "PK", "IN", "BD": return (1, 1)
        case "IR": return (7, 0)
        case "RU": return (14, 1)
        case "FR": return (12, 0)
        case "MA": return (21, 0)
        case "DZ": return (19, 0)
        case "TN": return (18, 0)
        case "MY", "SG": return (17, 0)
        case "ID": return (20, 0)
        case "JO": return (23, 0)
        default: return (3, 0)
        }
    }
}

enum HalError: LocalizedError, Sendable {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let value): return value
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: Double
        switch cleaned.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 1; g = 1; b = 1
        }
        self.init(red: r, green: g, blue: b)
    }
}


extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
