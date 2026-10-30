import AppKit
import SwiftUI

enum QuotaRotation {
    static func next(in ids: [String], after current: String?) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else { return ids.first }
        return ids[(index + 1) % ids.count]
    }
}
struct QuotaTickerValue: Equatable {
    var id: String
    var title: String
    var icon: BrandIcon
}
@MainActor final class QuotaTickerModel: ObservableObject {
    @Published var value = QuotaTickerValue(id: "", title: "…", icon: .app)
}
struct QuotaTickerView: View {
    @ObservedObject var model: QuotaTickerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            HStack(spacing: 5) {
                Image(nsImage: model.value.icon.templateImage(size: 16)).renderingMode(.template).frame(width: 16, height: 16)
                Text(model.value.title).font(.system(size: 12)).monospacedDigit()
                    .contentTransition(.numericText())
            }
            .id(model.value.id)
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
        }
        .frame(width: 68, height: 22)
        .foregroundStyle(.primary)
        .clipped()
        .animation(.easeInOut(duration: reduceMotion ? 0.12 : 0.28), value: model.value)
        .accessibilityHidden(true)
    }
}
/// Preserve the native status button as the sole hit target and AX element.
final class QuotaTickerHost: NSHostingView<QuotaTickerView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
