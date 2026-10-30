import SwiftUI

enum ToolPresentation { case settings, menu }
private struct ToolPresentationKey: EnvironmentKey { static let defaultValue = ToolPresentation.settings }
extension EnvironmentValues {
    var toolPresentation: ToolPresentation {
        get { self[ToolPresentationKey.self] }
        set { self[ToolPresentationKey.self] = newValue }
    }
}

struct SettingsCard<Content: View>: View {
    @Environment(\.toolPresentation) private var presentation
    var title: String? = nil
    var symbol: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: presentation == .menu ? 8 : 14) {
            if let title {
                HStack(spacing: 8) {
                    if let symbol { Image(systemName: symbol).foregroundStyle(.tint) }
                    Text(title).font(.system(size: 13, weight: .semibold))
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(presentation == .menu ? 0 : 16)
        .background(Color.primary.opacity(presentation == .menu ? 0 : 0.045), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(presentation == .menu ? 0 : 0.045)))
    }
}

struct SettingsToggleRow: View {
    var title: String
    var detail: String
    var symbol: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(.tint)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

struct ToolEmptyState: View {
    var symbol: String
    var title: String
    var detail: String
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity).padding(.vertical, 24)
    }
}

struct ToolBadge: View {
    var title: String
    var color: Color = .secondary
    var body: some View {
        Text(title).font(.system(size: 10, weight: .medium))
            .foregroundStyle(color).padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}
