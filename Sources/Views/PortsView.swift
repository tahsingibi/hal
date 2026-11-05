import SwiftUI

/// Ayarlar > Araçlar ve sağ tık menüsü aynı paneli kullanır.
struct PortsUtilityView: View {
    var body: some View {
        PortsPanel(showsTitle: true)
            .padding(18)
            .frame(
                minWidth: 440,
                maxWidth: .infinity,
                minHeight: 420,
                maxHeight: .infinity,
                alignment: .topLeading
            )
    }
}

struct PortsPanel: View {
    var showsTitle: Bool
    /// Ayarlar sayfasında kartlar halinde, sayfanın kendi kaydırmasıyla gösterilir.
    var embedsInSettings: Bool = false
    @ObservedObject private var service = PortService.shared
    @AppStorage("hal.ports.onlyMine") private var onlyMine = true
    @AppStorage("hal.ports.developersOnly") private var developersOnly = false
    @State private var query = ""
    @State private var pending: PortScan.Listener?

    var body: some View {
        Group {
            if embedsInSettings {
                settingsForm
            } else {
                windowStack
            }
        }
        .task { await service.refresh() }
        .alert(alertTitle, isPresented: pendingShown) {
            Button(L("Vazgeç", "Cancel"), role: .cancel) { pending = nil }
            Button(confirmTitle, role: .destructive) {
                if let pending { service.stop(pending) }
            }
        } message: {
            if let pending {
                Text(stopMessage(for: pending))
            }
        }
    }

    private var windowStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle {
                Text(L("Açık portlar", "Open ports"))
                    .font(.system(size: 18, weight: .semibold))
            }
            caption
            searchField
            metaRow
            statusBlock
            list
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var settingsForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard {
                searchField
                metaRow
                statusBlock
            }
            SettingsCard(title: L("Dinleyen portlar", "Listening ports")) {
                VStack(alignment: .leading, spacing: 0) {
                    settingsRows
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                caption
                SettingsFootnote(L(
                    "Menü çubuğu ikonuna sağ tıklayıp Araçlar > Açık portlar ile de açılır.",
                    "Also available via right-click on the menu bar icon → Tools > Open ports."
                ))
            }
            .padding(.horizontal, 4)
        }
    }

    private var caption: some View {
        Text(L(
            "Dinleyen TCP portları. Durdur, programı sonlandırır; aynı programın diğer portları da kapanır.",
            "Listening TCP ports. Stop ends the program; its other ports close too."
        ))
            .font(embedsInSettings ? .caption : .system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField(L("Port veya program", "Port or program"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var metaRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(countLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                refreshButton
            }
            filterControls
        }
    }

    private var filterControls: some View {
        HStack(spacing: 10) {
            developerChip
            Toggle(L("Yalnızca benim süreçlerim", "Only my processes"), isOn: $onlyMine)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .controlSize(.small)
                .disabled(developersOnly)
                .help(developersOnly
                    ? L("Geliştirici filtresi açıkken bütün kullanıcıların sunucuları listelenir.",
                        "With the developer filter on, servers from all users are listed.")
                    : L("Sistem süreçlerini gizler", "Hides system processes"))
            Spacer(minLength: 0)
        }
    }

    private var developerChip: some View {
        Button {
            developersOnly.toggle()
        } label: {
            Text(L("Geliştirici", "Developer"))
                .font(.system(size: 11, weight: developersOnly ? .semibold : .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    developersOnly ? Color.primary.opacity(0.14) : Color.primary.opacity(0.05),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(L(
            "React, Node, Vite, Docker, Supabase ve benzeri sunucular",
            "React, Node, Vite, Docker, Supabase, and similar servers"
        ))
    }

    @ViewBuilder
    private var statusBlock: some View {
        if let error = service.errorMessage {
            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(.red)
        }
        if let note = service.statusNote {
            Text(note)
                .font(.system(size: 11))
                .foregroundStyle(service.statusIsError ? Color.red : Color.secondary)
        }
    }

    private var countLabel: String {
        guard service.hasLoaded else { return L("Bakılıyor…", "Looking…") }
        if filtered.isEmpty { return L("Port yok", "No ports") }
        let programs = Set(filtered.map(\.pid)).count
        return Lf("%1$d port · %2$d program", "%1$d ports · %2$d programs", filtered.count, programs)
    }

    private var refreshButton: some View {
        Group {
            if service.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await service.refresh(resetStatus: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(L("Yenile", "Refresh"))
            }
        }
        .frame(width: 20, height: 20)
    }

    @ViewBuilder
    private var list: some View {
        if service.isLoading && !service.hasLoaded {
            ProgressView().controlSize(.small)
        } else if filtered.isEmpty {
            Text(emptyText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                rows
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, port in
                if index > 0 {
                    Divider().opacity(0.35)
                }
                portRow(port)
            }
        }
    }

    @ViewBuilder
    private var settingsRows: some View {
        if service.isLoading && !service.hasLoaded {
            ProgressView().controlSize(.small)
        } else if filtered.isEmpty {
            Text(emptyText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            ForEach(filtered) { port in
                portRow(port)
            }
        }
    }

    private func portRow(_ port: PortScan.Listener) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: ":\(port.port)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(width: 64, alignment: .leading)
                .textSelection(.enabled)
            VStack(alignment: .leading, spacing: 1) {
                Text(port.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(port.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if port.canStop {
                Button(L("Durdur", "Stop"), role: .destructive) { pending = port }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(service.stopping.contains(port.pid))
                    .help(Lf("%1$@ sürecini durdur (PID %2$d)", "Stop %1$@ (PID %2$d)", port.displayName, port.pid))
            } else {
                Text(port.pid == Int32(ProcessInfo.processInfo.processIdentifier)
                     ? L("bu uygulama", "this app")
                     : L("sistem", "system"))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5)
    }

    private var filtered: [PortScan.Listener] {
        service.ports.filter { port in
            if developersOnly {
                guard PortScan.isDeveloper(port) else { return false }
            } else if onlyMine && port.uid != service.myUID {
                return false
            }
            return matches(port)
        }
    }

    private func matches(_ port: PortScan.Listener) -> Bool {
        var needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if needle.hasPrefix(":") { needle.removeFirst() }
        if needle.isEmpty { return true }
        if String(port.port).contains(needle) { return true }
        if String(port.pid).contains(needle) { return true }
        if port.displayName.lowercased().contains(needle) { return true }
        if port.command.lowercased().contains(needle) { return true }
        if port.address.lowercased().contains(needle) { return true }
        if let hint = port.hint, hint.lowercased().contains(needle) { return true }
        return false
    }

    private var emptyText: String {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty { return L("Eşleşen port yok.", "No matching ports.") }
        if developersOnly { return L("Geliştirici portu yok.", "No developer ports.") }
        if onlyMine && service.ports.contains(where: { $0.uid != service.myUID }) {
            return L("Senin süreçlerin dinlemiyor.", "None of your processes are listening.")
        }
        return L("Dinleyen TCP portu yok.", "No listening TCP ports.")
    }

    private var pendingShown: Binding<Bool> {
        Binding(
            get: { pending != nil },
            set: { if !$0 { pending = nil } }
        )
    }

    private var alertTitle: String {
        guard let pending else { return "" }
        if service.needsForce(pending.pid) {
            return Lf("%1$@ zorla durdurulsun mu?", "Force stop %1$@?", pending.displayName)
        }
        return Lf("%1$@ durdurulsun mu?", "Stop %1$@?", pending.displayName)
    }

    private var confirmTitle: String {
        guard let pending, service.needsForce(pending.pid) else { return L("Durdur", "Stop") }
        return L("Zorla durdur", "Force stop")
    }

    private func stopMessage(for port: PortScan.Listener) -> String {
        let siblings = service.ports.filter { $0.pid == port.pid }.map(\.port).sorted()
        let closing: String
        if siblings.count <= 1 {
            closing = Lf("%1$d portu boşalır.", "Port %1$d will free.", port.port)
        } else {
            let list = siblings.map(String.init).joined(separator: ", ")
            closing = Lf("%1$@ portları boşalır.", "Ports %1$@ will free.", list)
        }
        if service.needsForce(port.pid) {
            return Lf(
                "Az önce kapanmadı. Zorla durdurmak PID %1$d sürecini anında keser. %2$@",
                "It did not stop just now. Force stop kills PID %1$d immediately. %2$@",
                port.pid, closing
            )
        }
        return Lf("PID %1$d kapanır. %2$@", "PID %1$d will quit. %2$@", port.pid, closing)
    }
}
