import AppKit
import Foundation

/// yt-dlp sarmalayıcısı. `youtube.command` betiğinin yaptığı işi arayüzden yapar:
/// bağlantı sor, biçim sor, hedef klasör sor, indir.
///
/// Betikten farkı ilerlemenin canlı okunması ve iptal edilebilmesi. Araçların
/// kurulumu kullanıcıya bırakılır; uygulama kendi başına bir şey kurmaz.
@MainActor
final class DownloadService: ObservableObject {
    static let shared = DownloadService()

    enum Format: String, CaseIterable, Identifiable, Codable, Sendable {
        case mp3, mp4

        var id: String { rawValue }
        var title: String {
            switch self {
            case .mp3: return "MP3 · yüksek kalite ses"
            case .mp4: return "MP4 · en iyi video"
            }
        }
        var shortTitle: String { rawValue.uppercased() }
    }

    enum State: Equatable {
        case idle
        case updating(String)
        case running(progress: Double, line: String)
        case finished(path: String)
        case failed(String)
        case cancelled
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var log: [String] = []
    @Published private(set) var lastUpdateNote: String?

    private var process: Process?
    private var pendingRetry: (link: String, format: Format, destination: URL)?
    private let lastCheckKey = "hal.downloader.lastUpdateCheck"

    private init() {}

    var isRunning: Bool {
        switch state {
        case .running, .updating: return true
        default: return false
        }
    }

    // MARK: - Araç durumu

    nonisolated struct Tools {
        var ytdlp: String?
        var ffmpeg: String?

        var ready: Bool { ytdlp != nil && ffmpeg != nil }
        var missing: [String] {
            var list: [String] = []
            if ytdlp == nil { list.append("yt-dlp") }
            if ffmpeg == nil { list.append("ffmpeg") }
            return list
        }
    }

    nonisolated static func tools() -> Tools {
        Tools(ytdlp: ProcessRunner.which("yt-dlp"), ffmpeg: ProcessRunner.which("ffmpeg"))
    }

    nonisolated static var defaultDestination: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
    }

    // MARK: - Güncelleme

    /// yt-dlp'nin nasıl kurulduğuna göre doğru güncelleme komutu.
    /// YouTube çıkarıcıları sık bozulur; güncel olmayan yt-dlp'nin ilk belirtisi
    /// "Unable to extract" türü hatalardır.
    enum UpdateStrategy {
        case selfUpdate(String)      // tek dosya derleme: yt-dlp -U
        case homebrew
        case pipx
        case pip

        var describe: String {
            switch self {
            case .selfUpdate: return "yt-dlp -U"
            case .homebrew: return "brew upgrade yt-dlp"
            case .pipx: return "pipx upgrade yt-dlp"
            case .pip: return "pip3 install -U yt-dlp"
            }
        }
    }

    nonisolated static func updateStrategy(for path: String) -> UpdateStrategy {
        if path.contains("/Cellar/") || path.contains("/opt/homebrew/") || path.contains("/usr/local/") {
            return .homebrew
        }
        // Tek dosya derleme mi, Python betiği mi?
        if let handle = FileHandle(forReadingAtPath: path),
           let head = try? handle.read(upToCount: 2),
           head == Data("#!".utf8) {
            try? handle.close()
            return ProcessRunner.which("pipx") != nil ? .pipx : .pip
        }
        return .selfUpdate(path)
    }

    /// Günde bir kez sessizce, hata sonrası zorla çalışır.
    private func needsDailyCheck() -> Bool {
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        guard last > 0 else { return true }
        return Date().timeIntervalSince1970 - last > 86_400
    }

    private func markChecked() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
    }

    /// Güncellemeyi çalıştırır. Başarısızlık indirmeyi engellemez —
    /// eski sürümle denemek, hiç denememekten iyidir.
    @discardableResult
    func updateTool() async -> String {
        guard let ytdlp = Self.tools().ytdlp else { return "yt-dlp yok" }
        let strategy = Self.updateStrategy(for: ytdlp)
        state = .updating("\(strategy.describe) çalışıyor…")

        let command: (String, [String])
        switch strategy {
        case .selfUpdate(let path): command = (path, ["-U"])
        case .homebrew:
            guard let brew = ProcessRunner.which("brew") else { return "brew bulunamadı" }
            command = (brew, ["upgrade", "yt-dlp"])
        case .pipx:
            guard let pipx = ProcessRunner.which("pipx") else { return "pipx bulunamadı" }
            command = (pipx, ["upgrade", "yt-dlp"])
        case .pip:
            guard let python = ProcessRunner.which("python3") else { return "python3 bulunamadı" }
            command = (python, ["-m", "pip", "install", "-U", "yt-dlp"])
        }

        let result: String = await Task.detached(priority: .utility) {
            guard let output = try? ProcessRunner.output(
                command.0, arguments: command.1, timeout: 180, environment: ProcessRunner.enrichedEnvironment()
            ) else { return "güncelleme zaman aşımına uğradı" }
            let text = String(data: output.data, encoding: .utf8) ?? ""
            let line = text.split(separator: "\n").last.map(String.init) ?? ""
            return output.status == 0 ? (line.isEmpty ? "güncel" : line) : "güncelleme atlandı"
        }.value

        markChecked()
        lastUpdateNote = result
        // Durumu bırakma: indirme hemen başlamazsa `updating` takılı kalır ve
        // `isRunning` sürekli true olur.
        if case .updating = state { state = .idle }
        return result
    }

    /// Güncel olmayan yt-dlp'nin tipik belirtileri.
    nonisolated static func looksLikeStaleExtractor(_ message: String) -> Bool {
        let text = message.lowercased()
        return [
            "unable to extract", "nsig extraction failed", "signature extraction failed",
            "please report this issue", "unable to download api page",
            "failed to parse json", "http error 403"
        ].contains { text.contains($0) }
    }

    // MARK: - İndirme

    /// Gerekiyorsa önce güncelleyip sonra indirir; çıkarıcı hatası alırsa
    /// zorla güncelleyip bir kez daha dener. Betiğin her açılışta güncelleme
    /// yapmasından farkı: günde bir kez, ve gerçekten bozulduğunda.
    func startManaged(link: String, format: Format, destination: URL, autoUpdate: Bool) {
        guard !isRunning else { return }
        pendingRetry = nil
        guard autoUpdate, needsDailyCheck() else {
            start(link: link, format: format, destination: destination)
            return
        }
        Task {
            await updateTool()
            start(link: link, format: format, destination: destination)
        }
    }

    func start(link: String, format: Format, destination: URL) {
        if case .running = state { return }
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .failed("Bağlantı boş olamaz.")
            return
        }
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            state = .failed("Geçerli bir bağlantı değil.")
            return
        }
        let tools = Self.tools()
        guard let ytdlp = tools.ytdlp else {
            state = .failed("yt-dlp bulunamadı.")
            return
        }

        log = []
        state = .running(progress: 0, line: "Başlatılıyor…")

        let template = destination.appendingPathComponent("%(title)s.%(ext)s").path
        var arguments: [String] = ["--newline", "--no-check-certificates", "-o", template]
        switch format {
        case .mp3:
            arguments += [
                "-x", "--audio-format", "mp3", "--audio-quality", "0",
                "--embed-thumbnail", "--embed-metadata", "--convert-thumbnails", "jpg"
            ]
        case .mp4:
            arguments += ["-f", "bestvideo+bestaudio/best", "--merge-output-format", "mp4"]
        }
        arguments.append(trimmed)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: ytdlp)
        task.arguments = arguments
        task.environment = ProcessRunner.enrichedEnvironment()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.standardInput = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.consume(text)
            }
        }

        task.terminationHandler = { finished in
            Task { @MainActor [weak self] in
                pipe.fileHandleForReading.readabilityHandler = nil
                self?.complete(status: finished.terminationStatus, destination: destination)
            }
        }

        do {
            try task.run()
            process = task
            // Yalnızca ilk deneme için: hata gelirse bir kez güncelleyip tekrarlar.
            if pendingRetry == nil {
                pendingRetry = (link: trimmed, format: format, destination: destination)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func cancel() {
        process?.terminate()
        process = nil
        state = .cancelled
    }

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: - Çıktı

    private func consume(_ text: String) {
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            log.append(line)
            if log.count > 200 { log.removeFirst(log.count - 200) }
            if case .running = state {
                state = .running(progress: Self.progress(in: line) ?? currentProgress, line: line)
            }
        }
    }

    private var currentProgress: Double {
        if case .running(let value, _) = state { return value }
        return 0
    }

    /// `[download]  45.2% of ...` satırından yüzdeyi çıkarır.
    static func progress(in line: String) -> Double? {
        guard line.hasPrefix("[download]"), let range = line.range(of: "%") else { return nil }
        let head = line[line.startIndex..<range.lowerBound]
        let number = head.reversed().prefix { $0.isNumber || $0 == "." }
        let text = String(number.reversed())
        guard let value = Double(text) else { return nil }
        return min(max(value / 100, 0), 1)
    }

    private func complete(status: Int32, destination: URL) {
        process = nil
        if case .cancelled = state { return }
        if status == 0 {
            pendingRetry = nil
            state = .finished(path: destination.path)
            return
        }
        let reason = log.last(where: { $0.lowercased().contains("error") }) ?? "yt-dlp \(status) koduyla çıktı"

        // Çıkarıcı bozulmuşsa bu neredeyse her zaman eski yt-dlp demektir:
        // zorla güncelle ve bir kez daha dene. İkinci denemede yine olmazsa bırak.
        if let retry = pendingRetry, Self.looksLikeStaleExtractor(reason) {
            pendingRetry = nil
            Task {
                let note = await updateTool()
                lastUpdateNote = "Güncellendi (\(note)), tekrar deneniyor…"
                start(link: retry.link, format: retry.format, destination: retry.destination)
            }
            return
        }
        pendingRetry = nil
        state = .failed(reason)
    }
}
