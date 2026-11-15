import SwiftUI

/// The Emoji panel (ADR 0007): sections side by side, scrolling sideways, and a bottom bar with ABC, the categories
/// and delete. `sections` is a snapshot from when the panel opened, so Recents never reshuffle under the finger.
struct EmojiPanel: View {
    let sections: [EmojiSection]
    let onPick: (String) -> Void
    /// [] when the emoji has no skin tones, else the default plus five.
    let tones: (String) -> [String]
    let onSearch: () -> Void
    let onLetters: () -> Void
    let onDelete: () -> Void
    /// The section at the left edge, which is the highlighted category.
    @State private var current: String?
    /// The open skin tone picker.
    @State private var picker: TonePicker?

    private let barHeight: CGFloat = 40
    private let titleHeight: CGFloat = 20
    static let space = "emojiPanel"

    var body: some View {
        GeometryReader { geo in
          ZStack(alignment: .topLeading) {
            let area = geo.size.height - KeyLayout.barTop - EmojiSearchBar.fieldHeight - 6 - barHeight - 10 - titleHeight
            let rows = max(4, Int(area / 34))
            let cell = area / CGFloat(rows)
            VStack(spacing: 6) {
                EmojiSearchBar.field(query: "").onTouchUp(onSearch).accessibilityLabel("Search Emoji").accessibilityAddTraits(.isButton)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {  // not lazy: section widths are exact, so jumps land (the cells are lazy)
                        ForEach(sections, id: \.title) { s in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(s.title).font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                                    .frame(height: titleHeight)
                                LazyHGrid(rows: Array(repeating: GridItem(.fixed(cell), spacing: 0), count: rows), spacing: 0) {
                                    ForEach(s.emoji, id: \.self) { e in
                                        EmojiCell(emoji: e, size: cell, width: geo.size.width, tones: tones, picker: $picker, onPick: onPick)
                                    }
                                }
                            }
                            .frame(width: CGFloat((s.emoji.count + rows - 1) / rows) * cell, alignment: .leading)
                            .id(s.title)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $current, anchor: .leading)
                .scrollDisabled(picker != nil)
                .frame(height: area + titleHeight)
                bottomBar
            }
            .padding(.horizontal, KeyLayout.margin)
            .padding(.top, KeyLayout.barTop)
            if let p = picker { tonePicker(p) }
          }
          .coordinateSpace(name: Self.space)
        }
    }

    /// The held emoji's tones; the highlighted one is inserted on release.
    private func tonePicker(_ p: TonePicker) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8).fill(KeyStyle.letter.background)
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            ForEach(p.options.indices, id: \.self) { i in
                Text(p.options[i]).font(.system(size: 30)).frame(width: TonePicker.optionWidth, height: p.frame.height)
                    .background(i == p.selected ? RoundedRectangle(cornerRadius: 6).fill(KeyStyle.mode.background) : nil)
                    .offset(x: CGFloat(i) * TonePicker.optionWidth)
                    .accessibilityLabel(p.options[i])
            }
        }
        .frame(width: p.frame.width, height: p.frame.height)
        .offset(x: p.frame.minX, y: p.frame.minY)
        .allowsHitTesting(false)
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

struct TonePicker {
    static let optionWidth: CGFloat = 44
    let options: [String]
    /// in the panel's coordinate space
    let frame: CGRect
    var selected: Int?

    /// The option under `p`; nil outside the popup (releasing there cancels).
    func index(at p: CGPoint) -> Int? {
        guard p.x >= frame.minX, p.x < frame.maxX, p.y > frame.minY - 30 else { return nil }
        return Int((p.x - frame.minX) / Self.optionWidth)
    }
}

/// A grid cell: tap inserts; holding 0.4 s on one with skin tones opens the picker, and the cell then shows the tone
/// picked. One drag gesture does both, in the panel's space so scrolling (which moves the cell) reads as movement.
private struct EmojiCell: View {
    let emoji: String
    let size: CGFloat
    let width: CGFloat
    let tones: (String) -> [String]
    @Binding var picker: TonePicker?
    let onPick: (String) -> Void
    @State private var picked: String?
    @State private var hold: DispatchWorkItem?
    @State private var start: CGPoint?

    var body: some View {
        let shown = picked ?? emoji
        Text(shown).font(.system(size: size * 0.64)).frame(width: size, height: size)
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(EmojiPanel.space))
                .onChanged { v in
                    if start != v.startLocation {  // a new touch
                        start = v.startLocation
                        let options = tones(shown)
                        hold?.cancel()
                        guard !options.isEmpty else { return }
                        let w = TonePicker.optionWidth * CGFloat(options.count), h: CGFloat = 48
                        let x = min(max(v.startLocation.x - w / 2, KeyLayout.margin), width - KeyLayout.margin - w)
                        let y = max(0, v.startLocation.y - size / 2 - h - 4)
                        let item = DispatchWorkItem {
                            picker = TonePicker(options: options, frame: CGRect(x: x, y: y, width: w, height: h),
                                                selected: options.firstIndex(of: shown))
                        }
                        hold = item
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
                    } else if picker != nil {
                        picker?.selected = picker?.index(at: v.location)
                    } else if hypot(v.translation.width, v.translation.height) > 10 {
                        hold?.cancel()
                    }
                }
                .onEnded { v in
                    hold?.cancel()
                    start = nil
                    if let p = picker {
                        picker = nil
                        if let i = p.index(at: v.location) { picked = p.options[i]; onPick(p.options[i]) }
                    } else if hypot(v.translation.width, v.translation.height) < 10 {
                        onPick(shown)
                    }
                })
            .accessibilityLabel(shown).accessibilityAddTraits(.isButton).accessibilityAction { onPick(shown) }
    }
}

/// The search field, and in search mode the row of results under it.
struct EmojiSearchBar: View {
    static let fieldHeight: CGFloat = 34
    static let resultsHeight: CGFloat = 42
    let query: String
    let results: [String]
    let onPick: (String) -> Void

    static func field(query: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            Text(query.isEmpty ? "Search Emoji" : query + "|").foregroundColor(query.isEmpty ? .secondary : .primary)
                .lineLimit(1).truncationMode(.head)
            Spacer(minLength: 0)
        }
        .font(.system(size: 16))
        .padding(.horizontal, 8)
        .frame(height: fieldHeight)
        .background(KeyStyle.function.background.opacity(0.6))
        .cornerRadius(8)
    }

    var body: some View {
        VStack(spacing: 4) {
            Self.field(query: query).accessibilityLabel("Search Emoji").accessibilityValue(query)
            if results.isEmpty && !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("No emoji").font(.system(size: 15)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: Self.resultsHeight)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(results, id: \.self) { e in
                            Button { onPick(e) } label: {
                                Text(e).font(.system(size: 30)).frame(width: 44, height: Self.resultsHeight)
                            }
                            .accessibilityLabel(e)
                        }
                    }
                }
                .frame(height: Self.resultsHeight)
            }
        }
    }
}
