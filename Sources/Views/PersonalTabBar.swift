import SwiftUI

/// A tab row that always fits its width: tabs share it equally and their
/// titles shrink or truncate instead of pushing the panel wider, which a
/// segmented control does once its segments stop fitting.
struct PersonalTabBar<ID: Hashable>: View {
    struct Item {
        let id: ID
        let title: String
        let symbol: String?

        init(id: ID, title: String, symbol: String? = nil) {
            self.id = id
            self.title = title
            self.symbol = symbol
        }
    }

    let items: [Item]
    @Binding var selection: ID

    init(items: [Item], selection: Binding<ID>) {
        self.items = items
        _selection = selection
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.id) { item in
                let active = item.id == selection
                Button { selection = item.id } label: {
                    VStack(spacing: 3) {
                        if let symbol = item.symbol {
                            Image(systemName: symbol)
                                .font(.system(size: 13, weight: .medium))
                                .frame(height: 16)
                        }
                        Text(item.title)
                            .font(.system(size: item.symbol == nil ? 11.5 : 10, weight: active ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(active ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, item.symbol == nil ? 5 : 6)
                    .padding(.horizontal, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(active ? Color.accentColor.opacity(0.22) : Color.clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(item.title)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}
