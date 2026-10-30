import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WindowSwitcherSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var switcher = WindowSwitcher.shared
    @State private var shortcutNote: String?
    private var prefs: Binding<SwitcherPreferences> { $store.settings.switcher }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L("Uygulamalar ve pencereler arasında kendi tarzında geçiş yap.", "Switch between apps and windows your way."))
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                SettingsCard(title: L("Pencere değiştirici", "Window switcher")) {
                    SettingsToggleRow(title: L("Hâl değiştiricisini kullan", "Use the Hâl switcher"), detail: L("Küçültülmüş pencereler ve aynı uygulamanın birden çok penceresi dahil.", "Includes minimized windows and multiple windows from the same app."), symbol: "macwindow.on.rectangle", isOn: prefs.enabled)
                    Text(L("Yerleşim", "Layout")).font(.system(size: 12, weight: .medium)).padding(.top, 4)
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(SwitcherLayout.allCases) { layout in
                            Button { store.settings.switcher.layout = layout } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    SwitcherLayoutDiagram(layout: layout).frame(height: 76).frame(maxWidth: .infinity)
                                        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 11))
                                    Text(layout.title).font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(store.settings.switcher.layout == layout ? Color.accentColor : .primary)
                                    Text(layout.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, minHeight: 143, alignment: .topLeading).padding(11)
                                .background(store.settings.switcher.layout == layout ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
                                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(store.settings.switcher.layout == layout ? Color.accentColor : .clear))
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    Divider().padding(.vertical, 3)
                    shortcutRow(L("Uygulamalar", "Applications"), symbol: "app.dashed", key: prefs.appShortcut, reset: .apps)
                    shortcutRow(L("Pencereler", "Windows"), symbol: "macwindow.on.rectangle", key: prefs.windowShortcut, reset: .windows)
                    Text(L("Pencereler kısayolu öndeki uygulamanın pencerelerini açar. Değiştirici açıkken seçili uygulamanın pencereleri arasında gezinir.", "The Windows shortcut shows the front app’s windows. While the switcher is open it cycles windows of the selected app."))
                        .font(.caption).foregroundStyle(.secondary)
                    SettingsToggleRow(title: L("Tüm pencereler", "All windows"), detail: L("Her yerleşimde bütün uygulamaların pencereleri için ayrı bir kısayol.", "A separate shortcut for every app’s windows in any layout."), symbol: "rectangle.on.rectangle", isOn: prefs.allWindowsEnabled)
                    if store.settings.switcher.allWindowsEnabled { shortcutRow(L("Tüm pencereler", "All windows"), symbol: "rectangle.stack", key: prefs.allWindowsShortcut, reset: .all) }
                    SettingsToggleRow(title: L("macOS pencere kısayollarını değiştir", "Replace macOS switching shortcuts"), detail: L("Kaydettiğin ⌘Tab ve ⌘` birleşimlerini Hâl yönetir. Özellik kapanınca macOS davranışı geri gelir.", "Hâl handles recorded ⌘Tab and ⌘` combinations. Disabling it restores macOS behavior."), symbol: "command", isOn: prefs.takeOverSystemShortcuts)
                    if let note = shortcutNote ?? switcher.shortcutError { Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.orange) }
                    Text(L("Kısayol tuşlarını basılı tutarak aç; Tab veya oklarla gezin, değiştirici tuşunu bırakınca seçilen pencere açılır. Shift geri gider. W pencereyi kapatır, Q uygulamadan çıkar; Esc iptal eder.", "Hold the shortcut modifiers and navigate with Tab or arrows; release to activate. Shift goes backward. W closes a window, Q quits its app and Escape cancels."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button(L("Değiştiriciyi dene", "Try the switcher")) { switcher.openOrAdvance() }.disabled(!store.settings.switcher.enabled)
                }
                SettingsCard(title: L("Seçenekler", "Options")) {
                    sliderRow(L("Görünme gecikmesi", "Appearance delay"), detail: L("Kısa basışta pencereyi göstermeden geçiş yapar.", "A quick tap switches without flashing the panel."), symbol: "timer", value: Binding(get: { Double(store.settings.switcher.appearanceDelay) }, set: { store.settings.switcher.appearanceDelay = Int($0) }), range: 0...500, step: 25, text: "\(store.settings.switcher.appearanceDelay) ms")
                    sliderRow(L("En fazla sütun", "Maximum columns"), detail: L("Pencereler bu sayıdan sonra yeni satıra geçer.", "Windows wrap to a new row after this number."), symbol: "square.grid.3x3", value: Binding(get: { Double(store.settings.switcher.maxColumns) }, set: { store.settings.switcher.maxColumns = Int($0) }), range: 0...12, step: 1, text: store.settings.switcher.maxColumns == 0 ? L("Otomatik", "Automatic") : String(store.settings.switcher.maxColumns))
                    SettingsToggleRow(title: L("Anında seçim", "Instant selection"), detail: L("Vurgu ve kaydırma geçiş animasyonunu kapatır.", "Disables highlight and scroll transition animations."), symbol: "cursorarrow.rays", isOn: prefs.instantSelection)
                    SettingsToggleRow(title: L("S ile aramayı sabitle", "Pin search with S"), detail: L("S’ye basınca değiştirici tuşunu bırakıp yazabilirsin. Enter açar, Esc kapatır.", "Press S to release the modifier and type. Enter activates; Escape dismisses."), symbol: "magnifyingglass", isOn: prefs.pinSearch)
                    SettingsToggleRow(title: L("Uygulama başına bir giriş göster", "One entry per application"), detail: L("Aynı uygulamanın pencerelerini tek girişte toplar. Pencereler kısayoluyla içlerine geçebilirsin.", "Groups an app’s windows into one entry. Use the Windows shortcut to browse them."), symbol: "app", isOn: prefs.mergeWindows)
                    SettingsToggleRow(title: L("Tam ekran pencereleri göster", "Show fullscreen windows"), detail: L("Uygulamaların tam ekran pencerelerini listeye ekler.", "Includes apps’ fullscreen windows."), symbol: "arrow.up.left.and.arrow.down.right", isOn: prefs.showFullscreen)
                    Divider()
                    optionRow(L("Küçültülmüş pencereler", "Minimized windows"), symbol: "arrow.down.to.line") {
                        Picker(L("Küçültülmüş pencereler", "Minimized windows"), selection: prefs.minimized) {
                            Text(L("Normal sıralama", "Normal order")).tag(SwitcherMinimized.normal)
                            Text(L("Sona yerleştir", "Place last")).tag(SwitcherMinimized.last)
                            Text(L("Gizle", "Hide")).tag(SwitcherMinimized.hidden)
                        }.pickerStyle(.segmented)
                    }
                    optionRow(L("Şurada göster", "Show on"), symbol: "display.2") {
                        Picker(L("Ekran", "Display"), selection: prefs.placement) {
                            Text(L("İmlecin olduğu ekran", "Pointer display")).tag(SwitcherPlacement.pointer)
                            Text(L("Menü çubuğu ekranı", "Menu bar display")).tag(SwitcherPlacement.menuBar)
                            Text(L("Etkin pencerenin ekranı", "Active window display")).tag(SwitcherPlacement.activeWindow)
                        }.pickerStyle(.menu).fixedSize()
                    }
                    SettingsToggleRow(title: L("Yalnızca geçerli ekranı göster", "Current display only"), detail: L("Değiştiricinin açıldığı ekrana ait pencereleri listeler.", "Lists windows on the display where the switcher opens."), symbol: "display", isOn: prefs.currentScreenOnly)
                    SettingsToggleRow(title: L("Yalnızca geçerli masaüstünü göster", "Current desktop only"), detail: L("Görünür masaüstlerindeki pencereleri listeler.", "Lists windows on the currently visible desktops."), symbol: "rectangle.split.2x2", isOn: prefs.currentSpaceOnly)
                    Divider()
                    optionRow(L("Açık penceresi olmayan uygulamalar", "Apps without open windows"), symbol: "app.dashed") {
                        Picker(L("Uygulamalar", "Applications"), selection: prefs.windowless) {
                            Text(L("Gösterme", "Hide")).tag(SwitcherWindowless.none)
                            Text(L("Yalnızca Finder", "Finder only")).tag(SwitcherWindowless.finder)
                            Text(L("Tüm uygulamalar", "All apps")).tag(SwitcherWindowless.all)
                        }.pickerStyle(.segmented)
                    }
                    DisclosureGroup(L("Uygulamaya göre kurallar", "Per-app rules")) {
                        SwitcherAppList(apps: prefs.excludedApps, caption: L("Bu uygulamaları değiştiriciden gizle.", "Hide these applications from the switcher."))
                            .padding(.top, 10)
                    }.font(.callout)
                }
                SettingsCard(title: L("Pencere küçük resimleri", "Window thumbnails")) {
                    Text(L("Önizleme boyutu", "Preview size")).font(.system(size: 12, weight: .medium))
                    HStack(spacing: 10) {
                        ForEach(Array(SwitcherPreviewSize.allCases.enumerated()), id: \.element.rawValue) { index, size in
                            Button { store.settings.switcher.previewSize = size } label: {
                                VStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 5).fill(store.settings.switcher.previewSize == size ? Color.accentColor.opacity(0.4) : Color.gray.opacity(0.4))
                                        .overlay(alignment: .top) { Capsule().fill(store.settings.switcher.previewSize == size ? Color.accentColor : .gray).frame(height: 4).padding(4) }
                                        .frame(width: CGFloat(30 + index * 9), height: CGFloat(24 + index * 7)).frame(height: 50)
                                    Text([L("Küçük", "Small"), L("Normal", "Normal"), L("Büyük", "Large"), L("Çok büyük", "Extra large")][index]).font(.system(size: 12, weight: .medium))
                                }.frame(maxWidth: .infinity).padding(12)
                                    .background(store.settings.switcher.previewSize == size ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(store.settings.switcher.previewSize == size ? Color.accentColor : .clear))
                            }.buttonStyle(.plain)
                        }
                    }
                    SettingsToggleRow(title: L("Sade önizlemeler", "Minimal previews"), detail: L("Pencere başlıklarını ve süslemeleri gizler; seçim görünür kalır.", "Hides window titles and decorations while keeping selection visible."), symbol: "rectangle.dashed", isOn: prefs.minimalPreviews)
                    DisclosureGroup(L("Bu uygulamalarda önizlemeleri duraklat", "Pause previews in these apps")) {
                        SwitcherAppList(apps: prefs.previewExcludedApps, caption: L("Bu uygulamalardan geçiş yaparken ekran yakalanmaz. Bu uygulamaların pencereleri de yakalanmaz.", "No screen capture while switching from these apps, and no previews of their windows."))
                            .padding(.top, 10)
                    }.font(.callout)
                }
                SettingsCard(title: L("İzinler", "Permissions")) {
                    permissionRow(L("Erişilebilirlik", "Accessibility"), detail: L("Gerçek pencereleri listelemek ve basılı tut/bırak kısayollarını kullanmak için.", "For individual windows and hold-and-release keyboard switching."), granted: switcher.accessibilityGranted, action: switcher.requestAccessibility)
                    Divider()
                    permissionRow(L("Ekran kaydı", "Screen Recording"), detail: L("Pencere önizlemeleri için. Görüntüler yalnızca bellekte tutulur; dosyaya veya ağa yazılmaz.", "For window previews. Images stay in memory and are never saved or uploaded."), granted: switcher.captureGranted, action: switcher.requestCapture)
                }
            }.frame(maxWidth: 820).frame(maxWidth: .infinity).padding(24)
        }
        .onChange(of: store.settings.switcher.allWindowsEnabled) { _, enabled in
            if enabled, [store.settings.switcher.appShortcut, store.settings.switcher.windowShortcut].contains(where: { $0.code == store.settings.switcher.allWindowsShortcut.code && $0.holdMask == store.settings.switcher.allWindowsShortcut.holdMask }) {
                store.settings.switcher.allWindowsShortcut = SwitcherKey(code: 49, modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue)
            }
        }
        .onAppear { switcher.permissionsChanged() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in switcher.permissionsChanged() }
    }
    private func shortcutRow(_ title: String, symbol: String, key: Binding<SwitcherKey>, reset: SwitcherKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 26)
            Text(title).font(.callout)
            Spacer()
            ShortcutRecorder(key: Binding(get: { key.wrappedValue }, set: { candidate in
                let conflict = store.settings.switcher.shortcuts.contains { _, existing in
                    existing != key.wrappedValue && existing.code == candidate.code && existing.holdMask == candidate.holdMask
                }
                guard !conflict else {
                    shortcutNote = L("Bu birleşim başka bir değiştirici eyleminde kullanılıyor.", "This combination is already assigned to another switcher action."); return
                }
                key.wrappedValue = candidate
                if candidate.isSystem {
                    store.settings.switcher.takeOverSystemShortcuts = true
                    shortcutNote = L("Kaydedildi. Bu macOS kısayolu, değiştirici açıkken Hâl tarafından yönetilir.", "Recorded. Hâl handles this macOS shortcut while the switcher is enabled.")
                } else { shortcutNote = nil }
            }), onRecording: switcher.setRecording, onError: { shortcutNote = $0 }).frame(width: 150, height: 27)
            Button(L("Sıfırla", "Reset")) { key.wrappedValue = reset }.disabled(key.wrappedValue == reset).controlSize(.small)
        }
    }
    private func optionRow<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.callout)
            content().labelsHidden().padding(.leading, 26)
        }
    }
    private func sliderRow(_ title: String, detail: String, symbol: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(.tint).frame(width: 26)
                Text(title).font(.callout)
                Spacer()
                Slider(value: value, in: range, step: step).frame(width: 130).accessibilityLabel(title)
                Text(text).font(.caption).foregroundStyle(.secondary).frame(width: 65, alignment: .trailing)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary).padding(.leading, 38)
        }
    }
    private func permissionRow(_ title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                if granted { Label(L("İzin verildi", "Granted"), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
                else { Button(L("İzin ver…", "Grant access…"), action: action).controlSize(.small) }
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct SwitcherAppList: View {
    @Binding var apps: [String]
    var caption: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(caption).font(.caption).foregroundStyle(.secondary)
            ForEach(apps, id: \.self) { id in
                HStack {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 22, height: 22)
                        Text(url.deletingPathExtension().lastPathComponent).font(.callout)
                    } else { Text(id).font(.caption) }
                    Spacer()
                    Button { apps.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).help(L("Kaldır", "Remove"))
                }
            }
            Button(L("Uygulama ekle…", "Add application…")) {
                let picker = NSOpenPanel(); picker.allowedContentTypes = [.applicationBundle]; picker.allowsMultipleSelection = true
                picker.directoryURL = URL(fileURLWithPath: "/Applications")
                picker.begin { response in
                    guard response == .OK else { return }
                    for url in picker.urls {
                        if let id = Bundle(url: url)?.bundleIdentifier, !apps.contains(id) { apps.append(id) }
                    }
                }
            }.controlSize(.small)
        }
    }
}

private struct SwitcherLayoutDiagram: View {
    var layout: SwitcherLayout
    var body: some View {
        Group {
            if layout == .icons {
                VStack(spacing: 6) {
                    miniature(selected: true).frame(width: 30, height: 23)
                    HStack(spacing: 10) { ForEach(0..<4) { i in RoundedRectangle(cornerRadius: 4).fill(i == 0 ? Color.accentColor : .gray.opacity(0.5)).frame(width: 17, height: 17) } }
                }
            } else if layout == .list {
                VStack(spacing: 7) {
                    Capsule().fill(Color.gray.opacity(0.7)).frame(width: 50, height: 4)
                    HStack(spacing: 8) { ForEach(0..<4) { i in RoundedRectangle(cornerRadius: 4).fill(i == 0 ? Color.accentColor : .gray.opacity(0.5)).frame(width: 17, height: 17) } }
                }
            } else {
                HStack(spacing: 6) { ForEach(0..<3) { i in miniature(selected: i == 0).frame(width: 30, height: 28) } }
            }
        }
    }
    private func miniature(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.6))
            .overlay(alignment: .top) { Rectangle().fill(Color.gray.opacity(0.7)).frame(height: 5).padding(2) }
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
    }
}

struct WindowSwitcherPanel: View {
    @EnvironmentObject private var switcher: WindowSwitcher
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 12) {
            if switcher.searchPinned || !switcher.query.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L("Uygulama veya pencere ara", "Search apps or windows"), text: $switcher.query).textFieldStyle(.plain)
                    Text("\(switcher.filtered.count)").font(.caption).foregroundStyle(.secondary)
                    Button { switcher.hide() } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help(L("Kapat", "Close"))
                }.padding(.horizontal, 10).frame(height: 28)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
            if switcher.filtered.isEmpty {
                HStack(spacing: 10) {
                    if switcher.loading { ProgressView().controlSize(.small) }
                    Text(switcher.loading ? L("Pencereler hazırlanıyor…", "Preparing windows…") : L("Pencere bulunamadı", "No windows found")).font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if switcher.preferences.layout == .icons && switcher.scope == .apps {
                iconLayout
            } else if switcher.preferences.layout == .list {
                listLayout
            } else {
                previewLayout
            }
            if switcher.searchPinned && switcher.usesPreviews && !switcher.captureGranted {
                Label(L("Gerçek pencere görüntüleri için Ayarlar’dan Ekran Kaydı izni ver.", "Enable Screen Recording in Settings for actual window previews."), systemImage: "info.circle")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.primary.opacity(0.13)))
        .environment(\.locale, Language.locale)
        .ignoresSafeArea()
        .onChange(of: switcher.query) { _, _ in switcher.reconcileSearch() }
    }
    private var animate: Animation? { reduceMotion || switcher.preferences.instantSelection ? nil : .easeOut(duration: 0.14) }
    private var previewLayout: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: max(1, switcher.columns)), spacing: 12) {
                    ForEach(switcher.filtered) { row in previewCard(row).id(row.id) }
                }
            }
            .onChange(of: switcher.selectedID) { _, id in if let id { withAnimation(animate) { proxy.scrollTo(id) } } }
        }
    }
    private var iconLayout: some View {
        VStack(spacing: 14) {
            if let selected = switcher.selected, switcher.captureGranted, switcher.canCaptureSession {
                HStack(spacing: 10) {
                    ForEach(Array(switcher.selectedAppWindows.prefix(4))) { row in
                        Button { switcher.activate(row) } label: {
                            thumbnail(row).frame(maxWidth: 220).frame(height: 140).clipShape(RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                }.frame(maxWidth: .infinity)
                Text(selected.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(switcher.filtered) { row in
                            Button { switcher.activate(row) } label: {
                                VStack(spacing: 7) {
                                    Image(nsImage: row.icon).resizable().frame(width: 44, height: 44)
                                    Text(row.appName).font(.system(size: 10)).lineLimit(1).frame(width: 64)
                                }.padding(6).background(switcher.selectedID == row.id ? Color.accentColor.opacity(0.17) : .clear, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(switcher.selectedID == row.id ? Color.accentColor : .clear))
                            }.buttonStyle(.plain).id(row.id).onHover { switcher.hover(row.id, inside: $0) }
                        }
                    }
                }.onChange(of: switcher.selectedID) { _, id in if let id { withAnimation(animate) { proxy.scrollTo(id, anchor: .center) } } }
            }
        }
    }
    private var listLayout: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    ForEach(switcher.filtered) { row in
                        Button { switcher.activate(row) } label: {
                            HStack(spacing: 10) {
                                Image(nsImage: row.icon).resizable().frame(width: 27, height: 27)
                                Text(row.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Spacer()
                                Text(row.appName).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                if row.minimized { Image(systemName: "minus.rectangle").foregroundStyle(.secondary) }
                            }.padding(9).background(switcher.selectedID == row.id ? Color.accentColor.opacity(0.17) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).id(row.id).onHover { switcher.hover(row.id, inside: $0) }
                    }
                }
            }.onChange(of: switcher.selectedID) { _, id in if let id { withAnimation(animate) { proxy.scrollTo(id) } } }
        }
    }
    private func previewCard(_ row: SwitcherWindow) -> some View {
        Button { switcher.activate(row) } label: {
            VStack(spacing: 8) {
                thumbnail(row)
                    .frame(height: switcher.preferences.previewSize.width * 0.62 - 14)
                    .frame(maxWidth: .infinity)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(alignment: .bottomLeading) {
                        if !switcher.preferences.minimalPreviews, let id = row.windowID, switcher.previews[id] != nil {
                            Image(nsImage: row.icon).resizable().frame(width: 23, height: 23)
                                .padding(5).background(Color(nsColor: .windowBackgroundColor).opacity(0.9), in: RoundedRectangle(cornerRadius: 7)).padding(5)
                        }
                    }
                if !switcher.preferences.minimalPreviews {
                    Text(row.title).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 4) {
                        if row.minimized { Image(systemName: "minus.rectangle") }
                        Text(row.appName)
                    }.font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(maxWidth: .infinity).padding(9)
                .background(switcher.selectedID == row.id ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(switcher.selectedID == row.id ? Color.accentColor : .clear, lineWidth: 2))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { switcher.hover(row.id, inside: $0) }
            .animation(animate, value: switcher.selectedID == row.id)
            .accessibilityLabel("\(row.title), \(row.appName)")
    }
    @ViewBuilder private func thumbnail(_ row: SwitcherWindow) -> some View {
        if let id = row.windowID, let image = switcher.previews[id], !switcher.preferences.previewExcludedApps.contains(row.bundleID), switcher.canCaptureSession {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            VStack(spacing: 7) {
                Image(nsImage: row.icon).resizable().frame(width: 46, height: 46)

            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
