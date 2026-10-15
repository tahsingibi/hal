import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private final class Extra {
        let id: String
        let item: NSStatusItem
        init(id: String, item: NSStatusItem) {
            self.id = id
            self.item = item
        }
    }

    private let store: AppStore
    private var extras: [Extra] = []
    private var popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var downloaderWindow: NSWindow?
    private var portsWindow: NSWindow?
    private var settingsTab: SettingsTab = .location
    private var replicas: [UInt32: Replica] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var screenObserver: Any?
    private var outsideClickMonitor: Any?
    private var escapeMonitor: Any?

    init(store: AppStore) {
        self.store = store
        super.init()
        buildPopover()
        DeviceModes.shared.clickTargetProvider = { [weak self] in
            self?.extraClickRects() ?? []
        }
        observe()
        rebuildExtras()
        syncReplicas()
    }

    func openSettings(tab: SettingsTab = .location) {
        if let settingsWindow {
            // Farklı bir sekme istendiyse içeriği yenile; aynıysa var olanı öne al.
            if settingsTab != tab {
                settingsWindow.contentViewController = NSHostingController(
                    rootView: SettingsView(initialTab: tab).environmentObject(store)
                )
                settingsTab = tab
            }
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        settingsTab = tab
        let controller = NSHostingController(rootView: SettingsView(initialTab: tab).environmentObject(store))
        let window = NSWindow(contentViewController: controller)
        window.title = "Hâl Ayarları"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 740, height: 700))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    func openDownloader() {
        if let downloaderWindow {
            downloaderWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(rootView: DownloaderUtilityView().environmentObject(store))
        let window = NSWindow(contentViewController: controller)
        window.title = "Hâl · Video indir"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 440, height: 320))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        downloaderWindow = window
    }

    func openPorts() {
        if let portsWindow {
            portsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            Task { await PortService.shared.refresh(resetStatus: true) }
            return
        }
        let controller = NSHostingController(rootView: PortsUtilityView().environmentObject(store))
        let window = NSWindow(contentViewController: controller)
        window.title = "Hâl · Açık portlar"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 480, height: 520))
        window.minSize = NSSize(width: 440, height: 420)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        portsWindow = window
    }

    private func buildPopover() {
        // Dışarı tıklamayla kapanmayı kendimiz yönetiyoruz; sabitleme (pin) ancak böyle iş görür.
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        let controller = NSHostingController(rootView: DetailPopoverView(onSettings: { [weak self] tab in
            self?.popover.performClose(nil)
            self?.openSettings(tab: tab)
        }).environmentObject(store))
        // Popover'ın SwiftUI içeriğine göre boyutlanması için şart.
        // Bu olmadan popover sabit yükseklikte kalıyor ve içerik üst üste biniyor.
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: MenuBarLayout.popoverWidth, height: 360)
    }

    private func observe() {
        store.$quotas
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshExtras() }
            .store(in: &cancellables)

        store.$prayers
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshExtras() }
            .store(in: &cancellables)

        store.$settings
            .map { "\($0.menuBarVisible.joined())-\($0.disabledModules.joined())-\($0.mirrorToOtherDisplays)-\($0.menuBarCollapsed)-\($0.claudeEnabled)-\($0.codexEnabled)-\($0.grokEnabled)-\($0.customProviders.count)-\($0.countryCode)-\($0.city)" }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildExtras()
                self?.syncReplicas()
            }
            .store(in: &cancellables)

        store.$now
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshExtras() }
            .store(in: &cancellables)

        store.$cleaningMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshExtras()
                self?.syncReplicas()
            }
            .store(in: &cancellables)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncReplicas() }
        }

        NotificationCenter.default.addObserver(
            forName: .hilalOpenSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.openSettings() }
        }

        NotificationCenter.default.addObserver(
            forName: .hilalOpenTarget,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let id = note.userInfo?[NotificationRoute.targetKey] as? String
            Task { @MainActor in
                let targetID = id ?? NotificationService.shared.takePendingTarget()
                if let targetID { self?.present(targetID: targetID) }
            }
        }

        if let targetID = NotificationService.shared.takePendingTarget() {
            DispatchQueue.main.async { [weak self] in
                self?.present(targetID: targetID)
            }
        }
    }

    private var visibleIDs: [String] {
        let extras = store.menuBarIDs
        return extras.isEmpty ? [BrandIcon.appItemID] : extras
    }

    private func rebuildExtras() {
        let wanted = visibleIDs
        for extra in extras where !wanted.contains(extra.id) {
            NSStatusBar.system.removeStatusItem(extra.item)
        }
        var next: [Extra] = []
        for id in wanted {
            if let existing = extras.first(where: { $0.id == id }) {
                next.append(existing)
            } else {
                next.append(makeExtra(id: id))
            }
        }
        extras = next
        refreshExtras()
    }

    private func makeExtra(id: String) -> Extra {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "dev.sungur.Hilal.\(id)"
        if let button = item.button {
            button.imagePosition = .imageLeading
            button.font = NSFont.menuBarFont(ofSize: 0)
            button.setButtonType(.momentaryPushIn)
            button.imageHugsTitle = true
            button.target = self
            button.action = #selector(extraClicked(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseUp])
        }
        return Extra(id: id, item: item)
    }

    private func refreshExtras() {
        for extra in extras {
            apply(extra)
        }
        relayoutReplicas()
    }

    private func apply(_ extra: Extra) {
        guard let button = extra.item.button else { return }
        let spec = spec(for: extra.id)
        button.image = icon(for: extra.id).templateImage(size: 16)
        button.imageScaling = NSImageScaling(rawValue: 0)!
        button.appearsDisabled = false
        button.title = spec.title
        button.imageHugsTitle = true
        button.toolTip = spec.tooltip
        extra.item.length = NSStatusItem.variableLength
    }

    /// Özet ikon, temsil ettiği sağlayıcının markasını gösterir.
    private func icon(for id: String) -> BrandIcon {
        guard id == MenuBarSummary.id else { return BrandIcon.from(id: id) }
        return store.summaryQuota.map { BrandIcon.from(id: $0.id) } ?? .app
    }

    private func spec(for id: String) -> (title: String, tooltip: String) {
        if id == BrandIcon.appItemID {
            return ("", "Hâl")
        }
        if id == MenuBarSummary.id {
            return summarySpec()
        }
        if id == "prayer" {
            if !store.settings.hasLocation {
                return ("", "Konum seç · Ayarlar › İbadet")
            }
            if let next = store.nextPrayer {
                let clock = TimeFormatters.clock(next.time)
                return (clock, "\(next.name) \(clock)")
            }
            return ("--:--", "Namaz")
        }
        if let group = store.quotas.first(where: { $0.id == id }) {
            return (group.menuBarTitle, group.tooltip)
        }
        return ("…", id)
    }

    /// Toplu moddaki tek ikon: en dolu kotanın yüzdesi, ipucunda hepsinin dökümü.
    private func summarySpec() -> (title: String, tooltip: String) {
        let visible = Set(store.visibleQuotaIDs)
        let groups = store.quotas.filter { visible.contains($0.id) }
        guard !groups.isEmpty else { return ("…", "Hâl") }
        let title = store.summaryQuota?.menuBarTitle ?? "…"
        let lines = groups.map { "\($0.name): \($0.menuBarTitle)" }
        return (title, lines.joined(separator: "\n"))
    }

    private func extraClickRects() -> [NSRect] {
        var rects: [NSRect] = []
        for extra in extras {
            guard let button = extra.item.button, let window = button.window else { continue }
            let local = button.convert(button.bounds.insetBy(dx: -6, dy: -3), to: nil)
            rects.append(window.convertToScreen(local))
        }
        if popover.isShown, let window = popover.contentViewController?.view.window {
            rects.append(window.frame)
        }
        if let settingsWindow, settingsWindow.isVisible {
            rects.append(settingsWindow.frame)
        }
        return rects
    }

    @objc private func extraClicked(_ sender: NSStatusBarButton) {
        guard let extra = extras.first(where: { $0.item.button === sender }) else { return }
        let eventType = NSApp.currentEvent?.type
        if eventType == .rightMouseUp || eventType == .rightMouseDown {
            showStatusMenu(from: extra)
            return
        }
        // Açıkken aynı öğeye tıklamak kapatır; başka bir öğeye tıklamak
        // pencereyi o öğenin altına taşıyıp onun detayını gösterir.
        if popover.isShown {
            // Genel ikon kendi sekmesi olmadığı için hep kapatır.
            if extra.id == BrandIcon.appItemID || store.selection == target(for: extra.id) {
                closePopover()
            } else {
                stopOutsideClickMonitor()
                popover.performClose(nil)
                DispatchQueue.main.async { [weak self] in
                    self?.showPopover(from: sender, id: extra.id)
                }
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.showPopover(from: sender, id: extra.id)
        }
    }

    /// Açıkken aynı ikona tekrar tıklandığını anlamak için, tıklamanın
    /// gerçekte açtığı hedefe bakılır — temsil ettiğine değil.
    private func target(for id: String) -> DetailTarget? {
        store.clickTarget(forMenuBarID: id)
    }

    /// Bildirim tıklaması: ilgili sayfayı seçip popover'ı açar.
    func present(targetID: String) {
        if let target = DetailTarget(id: targetID) {
            store.select(target)
        }
        guard let extra = extras.first, let button = extra.item.button else { return }
        if popover.isShown {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        showPopover(from: button, id: nil)
    }

    private func showPopover(from view: NSView, id: String?) {
        if let id {
            store.focus(menuBarID: id)
        } else if store.selection == nil {
            store.restoreSelection()
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        if let window = popover.contentViewController?.view.window {
            window.level = .popUpMenu
            window.makeKey()
        }
        startOutsideClickMonitor()
        DeviceModes.shared.refreshClickTargets()
    }

    private func closePopover() {
        stopOutsideClickMonitor()
        store.collapseImmediate()
        popover.performClose(nil)
    }

    /// Sabitli değilken uygulama dışına tıklanınca kapat. Sabitliyken açık kalır.
    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.popover.isShown, !self.store.pinned else { return }
                self.closePopover()
            }
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.popover.isShown, event.keyCode == 53 else { return event }
            self.closePopover()
            return nil
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    private func showStatusMenu(from extra: Extra) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Yenile", action: #selector(refreshClicked), keyEquivalent: "r")
        menu.addItem(withTitle: "Ayarlar…", action: #selector(settingsClicked), keyEquivalent: ",")
        menu.addItem(.separator())
        let tools = NSMenuItem(title: "Araçlar", action: nil, keyEquivalent: "")
        let toolsMenu = NSMenu()
        toolsMenu.addItem(withTitle: "Video indir…", action: #selector(downloaderClicked), keyEquivalent: "")
        toolsMenu.addItem(withTitle: "Açık portlar…", action: #selector(portsClicked), keyEquivalent: "")
        toolsMenu.items.forEach { $0.target = self }
        tools.submenu = toolsMenu
        menu.addItem(tools)
        let cleaningTitle = store.settings.resolvedCleaningTitle
        menu.addItem(
            withTitle: store.cleaningMode ? "\(cleaningTitle) — kapat" : cleaningTitle,
            action: #selector(toggleCleaning),
            keyEquivalent: ""
        )
        menu.addItem(withTitle: store.settings.alwaysWake ? "Always Wake: kapat" : "Always Wake", action: #selector(toggleWake), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Çıkış", action: #selector(quitClicked), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        if let button = extra.item.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
    }

    @objc private func refreshClicked() { Task { await store.refresh() } }
    @objc private func settingsClicked() { openSettings() }
    @objc private func downloaderClicked() { openDownloader() }
    @objc private func portsClicked() { openPorts() }
    @objc private func toggleCleaning() { store.setCleaningMode(!store.cleaningMode) }
    @objc private func toggleWake() { store.setAlwaysWake(!store.settings.alwaysWake) }
    @objc private func quitClicked() { NSApp.terminate(nil) }

    func popoverDidClose(_ notification: Notification) {
        // Başka bir öğeye taşınırken kapanma bildirimi yeni pencere açıldıktan sonra
        // gelebilir; o durumda daraltma yapılmaz.
        guard !popover.isShown else { return }
        stopOutsideClickMonitor()
        store.collapseImmediate()
    }

    private func syncReplicas() {
        let keep = Set(replicas.keys)
        var wanted: Set<UInt32> = []
        if store.settings.mirrorToOtherDisplays {
            let occupied = Set(extras.compactMap { $0.item.button?.window?.screen?.displayID })
            let primary = extras.first?.item.button?.window?.screen?.displayID
                ?? NSScreen.main?.displayID
                ?? NSScreen.preferred.displayID
            for screen in NSScreen.screens where screen.menuBarHeight > 10 {
                if screen.displayID == primary { continue }
                if occupied.contains(screen.displayID) { continue }
                wanted.insert(screen.displayID)
                if replicas[screen.displayID] == nil {
                    replicas[screen.displayID] = Replica(screen: screen, owner: self)
                } else {
                    replicas[screen.displayID]?.place(on: screen)
                }
            }
        }
        for id in keep where !wanted.contains(id) {
            replicas[id]?.close()
            replicas.removeValue(forKey: id)
        }
        relayoutReplicas()
    }

    private func relayoutReplicas() {
        let image = MenuBarRenderer.stripImage(items: extras.map { extra in
            (icon(for: extra.id), spec(for: extra.id).title)
        })
        for replica in replicas.values {
            replica.update(image: image)
        }
    }

    fileprivate func replicaClicked(_ replica: Replica) {
        if popover.isShown {
            closePopover()
            return
        }
        showPopover(from: replica.imageView, id: nil)
    }
}

@MainActor
final class Replica {
    private weak var owner: StatusBarController?
    private let panel: NSPanel
    let imageView: NSImageView
    private var displayID: UInt32

    init(screen: NSScreen, owner: StatusBarController) {
        self.owner = owner
        self.displayID = screen.displayID
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 24),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        let imageView = NSImageView()
        imageView.imageScaling = NSImageScaling(rawValue: 2)!
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.contentTintColor = .labelColor
        panel.contentView = imageView
        self.panel = panel
        self.imageView = imageView
        let recognizer = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        imageView.addGestureRecognizer(recognizer)
        place(on: screen)
        panel.orderFrontRegardless()
    }

    @objc private func clicked() {
        owner?.replicaClicked(self)
    }

    func place(on screen: NSScreen) {
        displayID = screen.displayID
        update(image: imageView.image)
    }

    func update(image: NSImage?) {
        guard let screen = NSScreen.matching(displayID: displayID) else {
            panel.orderOut(nil)
            return
        }
        imageView.image = image
        imageView.contentTintColor = .labelColor
        let height = min(max(screen.menuBarHeight, 22), 32)
        let size = image?.size ?? NSSize(width: 22, height: 18)
        let width = ceil(size.width) + 8
        let clockReserve: CGFloat = 248
        let x = screen.frame.maxX - clockReserve - width
        let y = screen.frame.maxY - height
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}

enum MenuBarRenderer {
    static func stripImage(items: [(BrandIcon, String)]) -> NSImage {
        let font = NSFont.menuBarFont(ofSize: 0)
        let spacing: CGFloat = 10
        var parts: [(NSImage, NSAttributedString)] = []
        var width: CGFloat = 0
        var height: CGFloat = 18
        for (icon, title) in items {
            let image = icon.templateImage(size: 16)
            let text = NSAttributedString(string: title.isEmpty ? "" : " \(title)", attributes: [
                .font: font,
                .foregroundColor: NSColor.black
            ])
            let textSize = text.size()
            width += image.size.width + textSize.width + spacing
            height = max(height, max(image.size.height, textSize.height))
            parts.append((image, text))
        }
        width = max(width - spacing, 18)
        let canvas = NSImage(size: NSSize(width: width, height: height))
        canvas.lockFocus()
        var x: CGFloat = 0
        for (image, text) in parts {
            let imageRect = NSRect(
                x: x,
                y: (height - image.size.height) / 2,
                width: image.size.width,
                height: image.size.height
            )
            image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
            x += image.size.width
            if text.length > 0 {
                let size = text.size()
                text.draw(at: NSPoint(x: x, y: (height - size.height) / 2 - 1))
                x += size.width
            }
            x += spacing
        }
        canvas.unlockFocus()
        canvas.isTemplate = true
        return canvas
    }
}
