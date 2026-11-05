import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI

/// Temizlik modunun kilit açma hareketi: Esc'ye arka arkaya, kasıtlı basışlar.
///
/// Klavye silinirken bezin Esc'ye tek başına değmesi olasıdır, ama aynı anda
/// başka tuşlara da değer. Bu yüzden Esc dışındaki her tuş (değiştiriciler ve
/// sistem tuşları dahil) sayacı sıfırlar, basılı tutmanın tekrarları sayılmaz ve
/// iki basış arasında uzun bir boşluk sayımı baştan başlatır. Boşluk cömert
/// tutulur: yavaş ama kasıtlı basan biri de kilidi açabilmeli.
struct CleaningUnlockGesture {
    static let escapeKeyCode: Int64 = 53

    let required: Int
    let maximumGap: TimeInterval
    private(set) var count = 0
    private var lastPress: TimeInterval?

    init(required: Int = 5, maximumGap: TimeInterval = 6) {
        self.required = required
        self.maximumGap = maximumGap
    }

    /// Bir tuş basışını işler; hareket tamamlandığında true döner.
    mutating func press(keyCode: Int64, at time: TimeInterval, repeated: Bool) -> Bool {
        if repeated { return false }
        guard keyCode == Self.escapeKeyCode else {
            reset()
            return false
        }
        if let lastPress, time - lastPress <= maximumGap {
            count += 1
        } else {
            count = 1
        }
        lastPress = time
        return count >= required
    }

    mutating func reset() {
        count = 0
        lastPress = nil
    }
}

/// Ses, parlaklık, medya ve güç tuşları klavye olayı olarak değil, "sistem
/// tanımlı" (NX_SYSDEFINED, 14) olay olarak gelir. Kilit bunları da yutar ve
/// kilit açma sayacına basılmış bir tuş olarak iletir.
enum CleaningSystemKey {
    static let eventType: UInt32 = 14
    private static let auxiliaryButtons = 8
    private static let powerButton = 1
    /// Gerçek tuş kodlarıyla karışmasın diye sistem tuşları bu tabanın üstünde sayılır.
    private static let codeBase: Int64 = 20_000

    struct Press { let code: Int64; let down: Bool; let repeated: Bool }

    static func decode(_ event: CGEvent) -> Press? {
        guard let ns = NSEvent(cgEvent: event) else { return nil }
        switch Int(ns.subtype.rawValue) {
        case auxiliaryButtons:
            let bits = UInt32(truncatingIfNeeded: ns.data1)
            let state = (bits & 0x0000_FF00) >> 8
            guard state == 0x0A || state == 0x0B else { return nil }
            return Press(code: codeBase + Int64(bits >> 16), down: state == 0x0A, repeated: bits & 1 == 1)
        case powerButton:
            return Press(code: codeBase + 1, down: true, repeated: false)
        default:
            return nil
        }
    }
}

/// Temizlik modu: klavye silinirken anlamsız yazı yazılmasın diye klavyeyi
/// HID seviyesinde kilitler. Tuşlar, sistem tuşları, kaydırma ve trackpad
/// hareketleri yutulur; işaretçi ve tıklamalar serbesttir, böylece ekrandaki
/// "Kilidi aç" düğmesi her zaman çalışır. İkinci çıkış yolu Esc'ye beş kez basmak.
///
/// Erişilebilirlik izni yoksa olay yakalayıcı kurulamaz; o durumda kilit hiç
/// başlamaz, böylece kimse açılamayan bir klavyeyle baş başa kalmaz.
@MainActor
final class CleaningLock: ObservableObject {
    static let shared = CleaningLock()

    struct Content: Equatable {
        /// Kullanıcının yazdığı başlık; boşsa varsayılan kilit başlığı.
        var title: String
        /// Ekranda duracak not; boşsa gösterilmez.
        var note: String
        /// Ekranı karartmak yerine köşede küçük bir gösterge.
        var keepScreenVisible: Bool
    }

    @Published private(set) var isActive = false
    @Published private(set) var progress = 0
    @Published private(set) var content = Content(title: "", note: "", keepScreenVisible: false)
    var required: Int { gesture.required }

    /// Kullanıcı ya da sistem kilidi kapattığında haber verir.
    var onEnded: (() -> Void)?

    /// Bırakılması beklenen bir tıklama en fazla bu kadar beklenir: bağlantısı
    /// kopan bir farenin hiç gelmeyecek bırakışı klavyeyi kilitli tutmamalı.
    private static let releaseWaitLimit: TimeInterval = 5

    private var gesture = CleaningUnlockGesture()
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var panels: [NSPanel] = []
    private var observers: [NSObjectProtocol] = []
    /// Kilit açıkken başlayan tıklamalar. Kapanış, gerçek bırakışlarını bekler;
    /// hiçbir zaman sahte bir bırakış üretilmez.
    private var heldButtons: Set<Int64> = []
    private var stopRequested = false
    private var releaseDeadline: DispatchWorkItem?

    private init() {}

    // MARK: Başlat / bitir

    @discardableResult
    func start(_ content: Content) -> Bool {
        self.content = content
        if isActive {
            showPanels()
            return true
        }
        guard AXIsProcessTrusted() else { return false }
        heldButtons.removeAll()
        stopRequested = false
        guard installTap() else { return false }
        gesture.reset()
        progress = 0
        isActive = true
        observe()
        showPanels()
        return true
    }

    /// Kullanıcının isteği: basılı bir tıklama varsa bırakılmasını bekler.
    func requestStop() {
        guard isActive else { return }
        stopRequested = true
        armReleaseDeadline()
        guard heldButtons.isEmpty else { return }
        scheduleFinish()
    }

    /// Uygulama kapanışı, oturum değişimi ya da izin kaybı: beklemeden kapatır.
    func stopNow() {
        finish(notify: false)
    }

    private func armReleaseDeadline() {
        guard releaseDeadline == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isActive, self.stopRequested else { return }
                self.releaseDeadline = nil
                self.heldButtons.removeAll()
                self.scheduleFinish()
            }
        }
        releaseDeadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseWaitLimit, execute: work)
    }

    /// Kapanış, olay yakalayıcının kendi geri çağrısından değil bir sonraki
    /// döngüde yapılır; düğmenin eylemi de böylece bitmiş olur.
    private func scheduleFinish() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isActive, self.stopRequested, self.heldButtons.isEmpty else { return }
                self.finish(notify: true)
            }
        }
    }

    private func finish(notify: Bool) {
        guard isActive else { return }
        releaseDeadline?.cancel()
        releaseDeadline = nil
        removeTap()
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        heldButtons.removeAll()
        stopRequested = false
        gesture.reset()
        progress = 0
        isActive = false
        if notify { onEnded?() }
    }

    private func observe() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { if self?.isActive == true { self?.showPanels() } }
        })
        // Başka bir kullanıcı oturumuna geçilince yakalayıcı giriş zincirinde
        // kalamaz; temizlik geçici bir durum olduğu için orada biter.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(notify: true) }
        })
    }

    // MARK: Olay yakalayıcı

    private static var eventMask: CGEventMask {
        let types: [UInt32] = [
            CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue, CGEventType.flagsChanged.rawValue,
            CGEventType.scrollWheel.rawValue,
            CGEventType.leftMouseDown.rawValue, CGEventType.leftMouseUp.rawValue,
            CGEventType.rightMouseDown.rawValue, CGEventType.rightMouseUp.rawValue,
            CGEventType.otherMouseDown.rawValue, CGEventType.otherMouseUp.rawValue,
            CleaningSystemKey.eventType,
            UInt32(NSEvent.EventType.gesture.rawValue)
        ]
        return types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1)) }
    }

    private func installTap() -> Bool {
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let lock = Unmanaged<CleaningLock>.fromOpaque(info).takeUnretainedValue()
            // Kaynak ana döngüye eklendiği için geri çağrı ana iş parçacığında çalışır.
            return MainActor.assumeIsolated { lock.handle(type, event) }
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        tapSource = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // Sistem takılan ya da kilit ekranına giren yakalayıcıyı kapatır; klavye
        // sessizce geri gelmesin diye yeniden açılır.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if AXIsProcessTrusted(), let tap {
                // Kör kalınan sürede bırakışlar kaçmış olabilir; beklenen tıklamalar unutulur.
                heldButtons.removeAll()
                CGEvent.tapEnable(tap: tap, enable: true)
                if stopRequested { scheduleFinish() }
                return nil
            }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.finish(notify: true) }
            }
            return Unmanaged.passUnretained(event)
        }

        if let (button, down) = mouseButton(type, event) {
            if down {
                heldButtons.insert(button)
            } else if heldButtons.remove(button) != nil, stopRequested, heldButtons.isEmpty {
                scheduleFinish()
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            count(event.getIntegerValueField(.keyboardEventKeycode),
                  repeated: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        case .flagsChanged:
            // Değiştiriciler Esc'ye en yakın tuşlar; üstlerinde duran bez sayacı sıfırlamalı.
            count(event.getIntegerValueField(.keyboardEventKeycode), repeated: false)
        default:
            if type.rawValue == CleaningSystemKey.eventType, let key = CleaningSystemKey.decode(event), key.down {
                count(key.code, repeated: key.repeated)
            }
        }
        // Tuşlar, kaydırma ve hareketler kilit boyunca yutulur.
        return nil
    }

    private func mouseButton(_ type: CGEventType, _ event: CGEvent) -> (Int64, Bool)? {
        switch type {
        case .leftMouseDown: return (0, true)
        case .leftMouseUp: return (0, false)
        case .rightMouseDown: return (1, true)
        case .rightMouseUp: return (1, false)
        case .otherMouseDown: return (event.getIntegerValueField(.mouseEventButtonNumber), true)
        case .otherMouseUp: return (event.getIntegerValueField(.mouseEventButtonNumber), false)
        default: return nil
        }
    }

    private func count(_ keyCode: Int64, repeated: Bool) {
        let done = gesture.press(keyCode: keyCode, at: ProcessInfo.processInfo.systemUptime, repeated: repeated)
        progress = gesture.count
        if done { requestStop() }
    }

    // MARK: Ekran katmanı

    private func showPanels() {
        let frames = NSScreen.screens.map(\.frame)
        let targets = frames.isEmpty ? [NSRect(x: 0, y: 0, width: 800, height: 600)] : frames
        // Ekran bildirimleri çerçeve değişmeden de art arda gelebilir; aynı
        // çerçevedeki paneller korunur, katman yanıp sönmez, tıklama kaybolmaz.
        var spare = panels
        panels = targets.map { frame in
            if let index = spare.firstIndex(where: { $0.frame == frame }) {
                let panel = spare.remove(at: index)
                panel.orderFrontRegardless()
                return panel
            }
            return makePanel(frame)
        }
        spare.forEach { $0.orderOut(nil) }
    }

    private func makePanel(_ frame: NSRect) -> NSPanel {
        let panel = CleaningPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        // Menü çubuğunun ve tam ekran uygulamaların üstünde; macOS'un kilit pencereleri bu düzeyi kullanır.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = FirstClickHostingView(rootView: CleaningOverlayView(lock: self))
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        return panel
    }
}

private final class CleaningPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Panel hiç öne gelmez; ilk tıklama da düğmeye ulaşsın, pencereyi etkinleştirmeye harcanmasın.
private final class FirstClickHostingView: NSHostingView<CleaningOverlayView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Görünüm

/// Kilidin ekrandaki yüzü. Varsayılan olarak ekranı karartır; "ekranı görünür
/// tut" açıksa köşede küçük bir gösterge olur. Kullanıcının başlığı ve notu her
/// iki görünümde de durur.
struct CleaningOverlayView: View {
    @ObservedObject var lock: CleaningLock

    private var title: String {
        let trimmed = lock.content.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L("Klavye temizlik için kilitlendi", "Keyboard locked for cleaning") : trimmed
    }

    private var note: String? {
        let trimmed = lock.content.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var instruction: String {
        Lf("Kilidi açmak için Esc tuşuna %1$d kez bas", "Press Esc %1$d times to unlock", lock.required)
    }

    var body: some View {
        ZStack {
            if lock.content.keepScreenVisible {
                Color.clear
                cornerCard
            } else {
                Color.black
                blackout
            }
        }
        .ignoresSafeArea()
    }

    private var blackout: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(.white)
            Text(title)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(note)
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.08)))
            }
            Text(instruction)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            dots(size: 12, spacing: 11, filled: .white, empty: .white.opacity(0.22))
            Button { lock.requestStop() } label: {
                Text(L("Kilidi aç", "Unlock"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(minWidth: 130)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
                    .background(Capsule(style: .continuous).fill(.white))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            Text(L("Fare ve trackpad tıklamaları çalışmaya devam eder", "Mouse and trackpad clicks keep working"))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(44)
        .frame(maxWidth: 520)
    }

    private var cornerCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.primary.opacity(0.08)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                if let note {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Text(instruction)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    dots(size: 6, spacing: 4, filled: .accentColor, empty: Color.primary.opacity(0.2))
                }
            }
            Button(L("Kilidi aç", "Unlock")) { lock.requestStop() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: 420, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
        .padding(.top, 40)
        .padding(.trailing, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private func dots(size: CGFloat, spacing: CGFloat, filled: Color, empty: Color) -> some View {
        HStack(spacing: spacing) {
            ForEach(0..<lock.required, id: \.self) { index in
                Circle()
                    .fill(index < lock.progress ? filled : empty)
                    .frame(width: size, height: size)
            }
        }
        .animation(.easeOut(duration: 0.15), value: lock.progress)
    }
}
