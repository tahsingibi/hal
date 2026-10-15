import SwiftUI

struct SwipePager<Item: Hashable, Content: View>: View {
    let items: [Item]
    @Binding var selection: Item
    var pageWidth: CGFloat
    @ViewBuilder var content: (Item) -> Content

    @State private var drag: CGFloat = 0

    var body: some View {
        let index = items.firstIndex(of: selection) ?? 0
        // Üstten hizala: sayfalar en uzun sayfanın yüksekliğini paylaşır, ortalanırsa
        // kısa sayfaların içeriği aşağı kayar.
        HStack(alignment: .top, spacing: 0) {
            ForEach(items, id: \.self) { item in
                // Her sayfa kendi içinde kayar. Yükseklik dışarıdan sabitlendiği için
                // uzun sayfa popover'ı taşırmaz, kısa sayfa da boşluk bırakmaz.
                ScrollView(.vertical, showsIndicators: false) {
                    content(item)
                        .frame(width: pageWidth, alignment: .topLeading)
                }
                .frame(width: pageWidth)
            }
        }
        .offset(x: -CGFloat(index) * pageWidth + clampedDrag(index: index))
        .frame(width: pageWidth, alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
        .gesture(swipeGesture(index: index))
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: selection)
        .animation(.interactiveSpring(), value: drag)
    }

    private func clampedDrag(index: Int) -> CGFloat {
        if items.isEmpty { return 0 }
        if index == 0 && drag > 0 { return drag * 0.28 }
        if index == items.count - 1 && drag < 0 { return drag * 0.28 }
        return drag
    }

    private func swipeGesture(index: Int) -> some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                drag = value.translation.width
            }
            .onEnded { value in
                let threshold = max(pageWidth * 0.18, 48)
                let predicted = value.predictedEndTranslation.width
                var next = index
                if predicted < -threshold || value.translation.width < -threshold {
                    next = min(index + 1, max(items.count - 1, 0))
                } else if predicted > threshold || value.translation.width > threshold {
                    next = max(index - 1, 0)
                }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                    drag = 0
                    if items.indices.contains(next) {
                        selection = items[next]
                    }
                }
            }
    }
}
