import AppKit
import SwiftUI

/// The first-run window: what Hâl is, which modules to start with, and a
/// note that permissions are asked only when a feature needs them.
struct WelcomeView: View {
    @EnvironmentObject private var store: AppStore
    var onFinish: () -> Void

    static let seenKey = "hal.welcome.seen"

    private let choices: [ModuleKind] = [.focus, .usage, .prayer, .calendar, .fitness, .money]

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                BrandMark(icon: .app, size: 56)
                Text(L("Hâl’e hoş geldin", "Welcome to Hâl"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(L("Günün, kotaların, vakitlerin ve Mac’in tek bir menü çubuğu panelinde.",
                       "Your day, quotas, prayer times and Mac in a single menu bar panel."))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(L("Hangi modüllerle başlamak istersin?", "Which modules would you like to start with?"))
                    .font(.system(size: 13, weight: .semibold))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(choices) { module in
                        tile(module)
                    }
                }
                Text(L("Bugün her zaman açık. Seçimini sonra Ayarlar › Özellikler’den değiştirebilirsin.",
                       "Today is always on. You can change this later in Settings › Features."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)
                Text(L("Hâl izinleri yalnızca bir özellik onlara ihtiyaç duyduğunda ister. Verilerin Mac’inde kalır.",
                       "Hâl asks for permissions only when a feature needs them. Your data stays on your Mac."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))

            Button(action: onFinish) {
                Text(L("Başla", "Get started"))
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 460)
    }

    private func tile(_ module: ModuleKind) -> some View {
        let on = store.settings.isModuleEnabled(module)
        return Button {
            store.setModule(module, enabled: !on)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: module.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
                    .frame(width: 22)
                Text(module.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(on ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(on ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
