import Foundation

/// Yayınlanmış davranışın sürümü ve tarihi. Hakkında sayfası ve README aynı listeyi taşır.
enum Changelog {
    struct Release: Identifiable {
        var version: String
        var date: String
        var notesTR: [String]
        var notesEN: [String]

        var id: String { version }

        var notes: [String] { Language.isEnglish ? notesEN : notesTR }

        var dateText: String {
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.dateFormat = "yyyy-MM-dd"
            guard let day = parser.date(from: date) else { return date }
            let out = DateFormatter()
            out.locale = Language.locale
            out.setLocalizedDateFormatFromTemplate("dMMMMy")
            return out.string(from: day)
        }
    }

    static let releases: [Release] = [
        Release(
            version: "1.1.0",
            date: "2026-10-31",
            notesTR: [
                "Yeni menü paneli: tek satırda ikon sekmeleri, Kişisel sekmesi ve Ayarlar / Uyanık tut / Çık düğmeleri",
                "Kotalar: her sağlayıcı kendi sekmesinde",
                "Güç: pil ve sistem grafikleri, adaptör gücü, pil sıcaklığı, sağlık, döngü ve kapasite ayrıntıları",
                "Harici monitörlerde DDC ile parlaklık",
                "Hakkında sayfasından yeniden açılabilen tanıtım ekranı",
                "Pencere değiştirici: izin durumu, izin sonrası kısayolların yeniden bağlanması ve basılı tut / bırak geçişi",
                "Uyanık tutma: sayaç, seçili uygulamalar öndeyken, prizde veya harici ekrandayken, kapak kapalıyken",
                "Homebrew: arama, kurma, kaldırma, yükseltme, servisi başlatma ve durdurma",
                "Ses mikseri: çıkış sesi ve uygulama başına seviye",
                "Güncellemeler: macOS, Homebrew ve yüklü uygulamalar",
                "Menü çubuğu paneli: simge şeridi, uyanık tutma süreleri, ses mikseri ve araçlar",
                "Yenilikler kendi sayfasında"
            ],
            notesEN: [
                "New menu panel: icon tabs on one row, a Personal tab and Settings / Keep awake / Quit buttons",
                "Quotas: each provider on its own tab",
                "Power: battery and system charts, adapter power, battery temperature, health, cycles and capacity details",
                "Brightness over DDC on external monitors",
                "Introduction screen that can be reopened from About",
                "Window switcher: permission status, shortcut reconnection after granting access and hold-and-release switching",
                "Keep awake: a timer, while selected apps are frontmost, while on power or an external display, and while the lid is closed",
                "Homebrew: search, install, remove, upgrade, start and stop services",
                "Volume mixer: output level and a level per app",
                "Updates: macOS, Homebrew and installed apps",
                "Menu bar panel: icon rail, keep-awake durations, volume mixer and tools",
                "What's New on its own page"
            ]
        ),
        Release(
            version: "1.0.0",
            date: "2026-10-16",
            notesTR: [
                "Bugün panosu, hafta özeti ve gün sonu",
                "Odak ölçümü",
                "Kotalar: Claude, Codex, Grok ve özel kaynak",
                "İbadet ve namaz takibi",
                "Takvim",
                "Sağlık: su, protein, antrenman, ilaç ve takviye",
                "Ödemeler",
                "İndirici (yt-dlp)",
                "Portlar",
                "Temizlik modu",
                "Uyanık tutma: sürekli",
                "Bildirimler, Türkçe ve İngilizce, Sparkle ile sürüm sorusu"
            ],
            notesEN: [
                "Today board, week summary and end of day",
                "Focus tracking",
                "Quotas: Claude, Codex, Grok and custom sources",
                "Prayer times and prayer tracking",
                "Calendar",
                "Health: water, protein, workouts, medication and supplements",
                "Payments",
                "Downloader (yt-dlp)",
                "Ports",
                "Cleaning mode",
                "Keep awake: always on",
                "Notifications, Turkish and English, Sparkle update prompt"
            ]
        )
    ]
}
