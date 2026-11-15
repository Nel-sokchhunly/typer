import SwiftUI

/// The Emoji panel (ADR 0007): sections side by side, scrolling sideways, and a bottom bar with ABC, the categories
/// and delete. `sections` is a snapshot from when the panel opened, so Recents never reshuffle under the finger.
struct EmojiPanel: View {
    let sections: [EmojiSection]
    let onPick: (String) -> Void
    let onLetters: () -> Void
    let onDelete: () -> Void
    /// The section at the left edge, which is the highlighted category.
    @State private var current: String?

    private let barHeight: CGFloat = 40
    private let titleHeight: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let area = geo.size.height - KeyLayout.barTop - barHeight - 10 - titleHeight
            let rows = max(4, Int(area / 34))
            let cell = area / CGFloat(rows)
            VStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(sections, id: \.title) { s in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(s.title).font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                                    .frame(height: titleHeight)
                                LazyHGrid(rows: Array(repeating: GridItem(.fixed(cell), spacing: 0), count: rows), spacing: 0) {
                                    ForEach(s.emoji, id: \.self) { e in
                                        Button { onPick(e) } label: {
                                            Text(e).font(.system(size: cell * 0.72)).frame(width: cell, height: cell)
                                        }
                                        .accessibilityLabel(e)
                                    }
                                }
                            }
                            .id(s.title)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $current, anchor: .leading)
                .frame(height: area + titleHeight)
                bottomBar
            }
            .padding(.horizontal, KeyLayout.margin)
            .padding(.top, KeyLayout.barTop)
        }
    }

    private var bottomBar: some View {
        let shown = current ?? sections.first?.title
        return HStack(spacing: 0) {
            barKey { Text("ABC").font(.system(size: 16)) }.onTouchUp(onLetters).accessibilityLabel("Letters")
            ForEach(sections, id: \.title) { s in
                Image(systemName: s.symbol).font(.system(size: 16))
                    .foregroundColor(s.title == shown ? .primary : .secondary)
                    .frame(maxWidth: .infinity, minHeight: barHeight)
                    .onTouchUp { withAnimation { current = s.title } }
                    .accessibilityLabel(s.title).accessibilityAddTraits(.isButton)
            }
            barKey { Image(systemName: "delete.left").font(.system(size: 18)) }.onTouchUp(onDelete).accessibilityLabel("Delete")
        }
        .frame(height: barHeight)
    }

    private func barKey<L: View>(@ViewBuilder _ label: () -> L) -> some View {
        label().foregroundColor(KeyStyle.function.foreground)
            .frame(width: KeyLayout.slotWidth, height: 36)
            .background(KeyStyle.function.background)
            .cornerRadius(5)
            .shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: 1)
            .accessibilityAddTraits(.isButton)
    }
}
