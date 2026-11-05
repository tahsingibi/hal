import AppKit
import ApplicationServices
import CoreGraphics

/// Pencere sunucusunun (SkyLight / CoreGraphics Services) belgelenmemiş ama
/// macOS pencere değiştiricilerinin yaygın olarak kullandığı uçları. Hepsi
/// çalışma anında `dlsym` ile aranır; bir sembol yoksa ilgili soru "bilinmiyor"
/// döner ve çağıran, belgelenmiş yola geri düşer.
enum SwitcherWindowServer {
    private static func lookup(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
    }

    private typealias MainConnection = @convention(c) () -> UInt32
    private typealias SpacesForWindows = @convention(c) (UInt32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias ManagedDisplaySpaces = @convention(c) (UInt32) -> Unmanaged<CFArray>?
    private typealias OrderedIn = @convention(c) (UInt32, UInt32, UnsafeMutablePointer<UInt8>) -> CGError
    private typealias WindowTags = @convention(c) (UInt32, UInt32, UnsafeMutablePointer<UInt32>, Int) -> CGError
    private typealias FrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> CGError
    private typealias PostRecord = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    private typealias PSNForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias RemoteElement = @convention(c) (CFData) -> Unmanaged<AXUIElement>?

    static let connection: UInt32 = lookup("CGSMainConnectionID").map { unsafeBitCast($0, to: MainConnection.self)() } ?? 0
    private static let spacesForWindows = lookup("CGSCopySpacesForWindows").map { unsafeBitCast($0, to: SpacesForWindows.self) }
    private static let managedDisplaySpaces = lookup("CGSCopyManagedDisplaySpaces").map { unsafeBitCast($0, to: ManagedDisplaySpaces.self) }
    private static let orderedIn = lookup("CGSWindowIsOrderedIn").map { unsafeBitCast($0, to: OrderedIn.self) }
    private static let windowTags = lookup("CGSGetWindowTags").map { unsafeBitCast($0, to: WindowTags.self) }
    private static let frontProcess = lookup("_SLPSSetFrontProcessWithOptions").map { unsafeBitCast($0, to: FrontProcess.self) }
    private static let postRecord = lookup("SLPSPostEventRecordTo").map { unsafeBitCast($0, to: PostRecord.self) }
    private static let psnForPID = lookup("GetProcessForPID").map { unsafeBitCast($0, to: PSNForPID.self) }
    private static let remoteElement = lookup("_AXUIElementCreateWithRemoteToken").map { unsafeBitCast($0, to: RemoteElement.self) }

    // MARK: Space'ler

    /// Space sorguları bu oturumda yanıt verebiliyor mu? Vermiyorsa "hiçbir
    /// Space'te değil" sonucu kalıntı sayılmamalı.
    static var canResolveSpaces: Bool { connection != 0 && spacesForWindows != nil }

    /// Pencerenin bulunduğu Space kimlikleri (tümü maskesiyle); bilinmiyorsa nil.
    static func spaces(of windowID: CGWindowID) -> Set<UInt64>? {
        guard connection != 0, let spacesForWindows,
              let list = spacesForWindows(connection, 7, [NSNumber(value: windowID)] as CFArray)?.takeRetainedValue() as? [NSNumber]
        else { return nil }
        return Set(list.map(\.uint64Value))
    }

    /// Her ekranda şu an görünen Space'ler.
    static func visibleSpaces() -> Set<UInt64> {
        guard connection != 0, let managedDisplaySpaces,
              let displays = managedDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return Set(displays.compactMap { (($0["Current Space"] as? [String: Any])?["id64"] as? NSNumber)?.uint64Value })
    }

    /// Tam ekran uygulamaların kendi Space'leri (tür 4).
    static func fullscreenSpaces() -> Set<UInt64> {
        guard connection != 0, let managedDisplaySpaces,
              let displays = managedDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]] else { return [] }
        var result = Set<UInt64>()
        for display in displays {
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                guard (space["type"] as? NSNumber)?.intValue == 4,
                      let id = (space["id64"] as? NSNumber)?.uint64Value else { continue }
                result.insert(id)
            }
        }
        return result
    }

    /// Ekranda görünmese bile pencere sunucusu pencereyi sıraya almış mı?
    /// Başka Space'e taşınmış canlı pencere sırada kalır; kapatılmış bir yüzey kalmaz.
    static func isOrderedIn(_ windowID: CGWindowID) -> Bool? {
        guard connection != 0, let orderedIn else { return nil }
        var value: UInt8 = 0
        guard orderedIn(connection, windowID, &value) == .success else { return nil }
        return value != 0
    }

    /// Uygulamanın pencere döngüsünden (⌘`) çıkardığı yardımcı yüzeyler.
    /// Bazı macOS sürümlerinde başka uygulamalar için sıfır döner; o zaman kimse elenmez.
    static func isExcludedFromCycle(_ windowID: CGWindowID) -> Bool {
        guard connection != 0, let windowTags else { return false }
        var tags = [UInt32](repeating: 0, count: 2)
        let status = tags.withUnsafeMutableBufferPointer { buffer -> CGError in
            guard let base = buffer.baseAddress else { return .failure }
            return windowTags(connection, windowID, base, 64)
        }
        guard status == .success else { return false }
        let value = UInt64(tags[0]) | UInt64(tags[1]) << 32
        return value & (1 << 18) != 0
    }

    // MARK: Öne alma

    /// Süreci, verilen pencere öne gelecek şekilde ve kullanıcı isteği olarak
    /// öne alır; ardından pencereyi anahtar pencere yapan tek bir basış kaydı
    /// gönderir. `NSRunningApplication.activate` uygulamanın kendi seçtiği
    /// pencereyi öne çıkardığı için tam pencereyi bu yol getirir.
    ///
    /// Basışın konumu pencere koordinatlarında çok uzak bir noktadır; böylece
    /// hiçbir denetime ya da yeniden boyutlandırma kenarına denk gelmez.
    /// Wine gibi uyumluluk katmanları basışı gerçek fare tıklaması sayabildiği
    /// için onlara yalnızca öne alma isteği gider.
    @discardableResult
    static func front(_ windowID: CGWindowID, pid: pid_t, sendsKeyRecord: Bool) -> Bool {
        guard let frontProcess, let psnForPID else { return false }
        var psn = ProcessSerialNumber()
        guard psnForPID(pid, &psn) == noErr else { return false }
        let userGenerated: UInt32 = 0x200
        guard frontProcess(&psn, windowID, userGenerated) == .success else { return false }
        guard sendsKeyRecord else { return true }
        guard let postRecord else { return true }
        var bytes = [UInt8](repeating: 0, count: 0x100)
        bytes[0x04] = 0xF8
        bytes[0x08] = 0x01
        bytes[0x3A] = 0x10
        var far = CGPoint(x: 300_000, y: 300_000)
        withUnsafeBytes(of: &far) { bytes.replaceSubrange(0x20..<(0x20 + $0.count), with: $0) }
        var id = windowID
        withUnsafeBytes(of: &id) { bytes.replaceSubrange(0x3C..<(0x3C + $0.count), with: $0) }
        return postRecord(&psn, &bytes) == .success
    }

    // MARK: Erişilebilirlik öğesi

    /// Uygulamanın yayımlamadığı (başka Space'teki, tam ekran) pencerelerin AX
    /// öğesini sınırlı bir taramayla bulur. Belirteç: pid, sıfır, "coco"
    /// işareti ve öğe numarası. Süre dolunca durur; bulunamazsa nil.
    static func hiddenElements(for windowIDs: Set<CGWindowID>, pid: pid_t,
                               budget: TimeInterval = 0.15) -> [CGWindowID: AXUIElement] {
        let wanted = windowIDs.subtracting([0])
        guard let remoteElement, !wanted.isEmpty, pid > 0,
              pid != ProcessInfo.processInfo.processIdentifier else { return [:] }
        let deadline = ProcessInfo.processInfo.systemUptime + budget
        var found: [CGWindowID: AXUIElement] = [:]
        var token = Data(count: 20)
        var number: UInt64 = 0
        while number < 3_000, found.count < wanted.count {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { break }
            token.withUnsafeMutableBytes { raw in
                raw.storeBytes(of: pid, toByteOffset: 0, as: pid_t.self)
                raw.storeBytes(of: Int32(0), toByteOffset: 4, as: Int32.self)
                raw.storeBytes(of: Int32(0x636F_636F), toByteOffset: 8, as: Int32.self)
                raw.storeBytes(of: number, toByteOffset: 12, as: UInt64.self)
            }
            number += 1
            guard let element = remoteElement(token as CFData)?.takeRetainedValue() else { continue }
            AXUIElementSetMessagingTimeout(element, Float(min(0.05, remaining)))
            guard let id = SwitcherWindowQuery.windowID(element), wanted.contains(id), found[id] == nil,
                  SwitcherWindowQuery.value(element, kAXRoleAttribute) as? String == kAXWindowRole as String
            else { continue }
            found[id] = element
        }
        return found
    }

    /// Bir pencere kimliğinin AX öğesi: önce yayımlanan liste, sonra ana ve
    /// odaklı pencere, en son gizli Space taraması.
    static func element(for windowID: CGWindowID, pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        for element in SwitcherWindowQuery.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            if SwitcherWindowQuery.windowID(element) == windowID { return element }
        }
        for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            if let raw = SwitcherWindowQuery.value(app, attribute), CFGetTypeID(raw) == AXUIElementGetTypeID() {
                let element = unsafeBitCast(raw, to: AXUIElement.self)
                if SwitcherWindowQuery.windowID(element) == windowID { return element }
            }
        }
        return hiddenElements(for: [windowID], pid: pid)[windowID]
    }
}
