import SwiftUI
import UIKit

/// The Emoji panel (ADR 0007): sections side by side, scrolling sideways, and a bottom bar with ABC, the categories
/// and delete. `sections` is a snapshot from when the panel opened, so Recents never reshuffle under the finger.
/// The grid is a UICollectionView (EmojiGrid): reused one-label cells, because a SwiftUI grid built every section
/// up to a jump target and the extension was killed for memory.
struct EmojiPanel: View {
    let sections: [EmojiSection]
    let onPick: (String) -> Void
    /// [] when the emoji has no skin tones, else the default plus five.
    let tones: (String) -> [String]
    /// an emoji as it shows now, with the remembered tone
    let display: (String) -> String
    let onHold: (EmojiHold) -> Void
    let onSearch: () -> Void
    let globe: Bool
    let onGlobe: () -> Void
    let onLetters: () -> Void
    let onDelete: () -> Void
    /// The index of the section at the left edge, which is the highlighted category.
    @State private var current = 0
    @State private var scroller = EmojiGrid.Scroller()

    private let barHeight: CGFloat = 40
    private let titleHeight = EmojiGridLayout.headerHeight

    var body: some View {
        GeometryReader { geo in
            // 8 columns across; 4 rows, or 5 when each row stays at least 42 pt
            let area = geo.size.height - KeyLayout.barTop - EmojiSearchBar.fieldHeight - 6 - barHeight - 10 - titleHeight
            let rows = area / 5 >= 42 ? 5 : 4
            let cell = CGSize(width: (geo.size.width - 2 * KeyLayout.margin) / 8, height: area / CGFloat(rows))
            VStack(spacing: 6) {
                EmojiSearchBar.field(query: "").onTouchUp(onSearch).accessibilityLabel("Search Emoji").accessibilityAddTraits(.isButton)
                    .padding(.horizontal, KeyLayout.margin)
                EmojiGrid(sections: sections, rows: rows, cell: cell, tones: tones, display: display, onPick: onPick,
                          onSection: { current = $0 }, onHold: onHold, scroller: scroller)
                    .frame(height: area + titleHeight)
                bottomBar.padding(.horizontal, KeyLayout.margin)
            }
            .padding(.top, KeyLayout.barTop)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            barKey { Text("ABC").font(.system(size: 16)) }.onTouchUp(onLetters).accessibilityLabel("Letters")
            if globe { barKey { Image(systemName: "globe").font(.system(size: 18)) }.onTouchUp(onGlobe).accessibilityLabel("Next keyboard") }
            ForEach(sections.indices, id: \.self) { i in
                Image(systemName: sections[i].symbol).font(.system(size: 16))
                    .foregroundColor(i == current ? .primary : .secondary)
                    .frame(maxWidth: .infinity, minHeight: barHeight)
                    .onTouchUp { scroller.scroll(to: i) }
                    .accessibilityLabel(sections[i].title).accessibilityAddTraits(.isButton)
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
            .shadow(color: KeyStyle.shadow, radius: 0, x: 0, y: 1)
            .accessibilityAddTraits(.isButton)
    }
}

/// Sections one after another, left to right. A section is columns of `rows` items filled top to bottom, under a
/// header that is at least as wide as its title (a short Recents section grows to fit it). Every frame is computed
/// once in prepare(); attributes are made on demand.
final class EmojiGridLayout: UICollectionViewLayout {
    static let headerHeight: CGFloat = 20
    static let gap: CGFloat = 12
    var rows = 4
    var cell = CGSize(width: 48, height: 34)
    var titles: [String] = []
    /// x of each section's first column: what a category jump scrolls to
    private(set) var starts: [CGFloat] = []
    private var items: [[CGRect]] = []
    private var headers: [CGRect] = []
    private var width: CGFloat = 0

    override func prepare() {
        guard let cv = collectionView else { return }
        starts = []; items = []; headers = []
        var x: CGFloat = 0
        let font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        for s in 0..<cv.numberOfSections {
            let n = cv.numberOfItems(inSection: s)
            let titleWidth = ceil((titles[s] as NSString).size(withAttributes: [.font: font]).width) + 2
            let w = max(CGFloat((n + rows - 1) / rows) * cell.width, titleWidth)
            starts.append(x)
            headers.append(CGRect(x: x, y: 0, width: w, height: Self.headerHeight))
            items.append((0..<n).map { CGRect(x: x + CGFloat($0 / rows) * cell.width, y: Self.headerHeight + CGFloat($0 % rows) * cell.height,
                                              width: cell.width, height: cell.height) })
            x += w + Self.gap
        }
        width = max(0, x - Self.gap)
    }

    override var collectionViewContentSize: CGSize { CGSize(width: width, height: collectionView?.bounds.height ?? 0) }
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool { newBounds.height != collectionView?.bounds.height }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var out: [UICollectionViewLayoutAttributes] = []
        for (s, h) in headers.enumerated() where h.intersects(rect) {
            out.append(layoutAttributesForSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: s))!)
        }
        for (s, rects) in items.enumerated() where rects.last.map({ $0.maxX > rect.minX }) == true && rects[0].minX < rect.maxX {
            for (i, r) in rects.enumerated() where r.intersects(rect) { out.append(layoutAttributesForItem(at: IndexPath(item: i, section: s))!) }
        }
        return out
    }

    override func layoutAttributesForItem(at ip: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard ip.section < items.count, ip.item < items[ip.section].count else { return nil }
        let a = UICollectionViewLayoutAttributes(forCellWith: ip)
        a.frame = items[ip.section][ip.item]
        return a
    }

    override func layoutAttributesForSupplementaryView(ofKind kind: String, at ip: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard ip.section < headers.count else { return nil }
        let a = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: kind, with: ip)
        a.frame = headers[ip.section]
        return a
    }
}

/// The grid: tap inserts; holding 0.4 s on an emoji with skin tones opens the keyboard's long-press panel with its
/// tones (as on a Khmer key): sliding highlights one, lifting inserts it, and the cell then shows that tone.
struct EmojiGrid: UIViewRepresentable {
    /// Lets the category bar scroll the grid.
    final class Scroller { fileprivate weak var grid: UICollectionView?; fileprivate var layout: EmojiGridLayout?
        func scroll(to section: Int) {
            guard let cv = grid, let x = layout?.starts[safe: section] else { return }
            // not animated: an animated jump draws every emoji on the way, and each drawn glyph stays cached (~130 KB)
            cv.setContentOffset(CGPoint(x: x - cv.contentInset.left, y: 0), animated: false)
        }
    }

    let sections: [EmojiSection]
    let rows: Int
    let cell: CGSize
    let tones: (String) -> [String]
    let display: (String) -> String
    let onPick: (String) -> Void
    let onSection: (Int) -> Void
    /// The long-press on a toned emoji, in window coordinates; the keyboard draws its long-press panel from it.
    let onHold: (EmojiHold) -> Void
    let scroller: Scroller

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        let c = context.coordinator
        let layout = EmojiGridLayout()
        layout.rows = rows; layout.cell = cell; layout.titles = sections.map(\.title)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.alwaysBounceVertical = false
        cv.contentInset = UIEdgeInsets(top: 0, left: KeyLayout.margin, bottom: 0, right: KeyLayout.margin)
        cv.contentOffset.x = -KeyLayout.margin
        cv.register(EmojiCellView.self, forCellWithReuseIdentifier: "e")
        cv.register(EmojiHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "h")
        cv.dataSource = c; cv.delegate = c
        let hold = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.held(_:)))
        hold.minimumPressDuration = 0.4
        cv.addGestureRecognizer(hold)
        scroller.grid = cv; scroller.layout = layout
        c.layout = layout
        return cv
    }

    func updateUIView(_ cv: UICollectionView, context: Context) {
        let c = context.coordinator
        c.parent = self  // closures; `sections` stays the snapshot taken at open
        guard let layout = c.layout, layout.rows != rows || layout.cell != cell else { return }
        layout.rows = rows; layout.cell = cell
        layout.invalidateLayout()
        cv.reloadData()
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
        var parent: EmojiGrid
        let sections: [EmojiSection]
        var layout: EmojiGridLayout?
        private var lastSection = 0
        private var pressed: IndexPath?

        init(_ p: EmojiGrid) { parent = p; sections = p.sections }

        private func shown(_ ip: IndexPath) -> String {
            let e = sections[ip.section].emoji[ip.item]
            return sections[ip.section].symbol == "clock" ? e : parent.display(e)  // Recents show what was picked
        }

        func numberOfSections(in cv: UICollectionView) -> Int { sections.count }
        func collectionView(_ cv: UICollectionView, numberOfItemsInSection s: Int) -> Int { sections[s].emoji.count }

        func collectionView(_ cv: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: "e", for: ip) as! EmojiCellView
            cell.glyphSize = 0.62 * min(parent.cell.width, parent.cell.height)
            cell.label.text = shown(ip)
            cell.accessibilityLabel = cell.label.text
            return cell
        }

        func collectionView(_ cv: UICollectionView, viewForSupplementaryElementOfKind kind: String, at ip: IndexPath) -> UICollectionReusableView {
            let h = cv.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "h", for: ip) as! EmojiHeaderView
            h.label.text = sections[ip.section].title
            return h
        }

        func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) { parent.onPick(shown(ip)) }

        func scrollViewDidScroll(_ sv: UIScrollView) {
            guard let starts = layout?.starts, !starts.isEmpty else { return }
            let edge = sv.contentOffset.x + sv.contentInset.left + 1
            let s = starts.lastIndex { $0 <= edge } ?? 0
            if s != lastSection { lastSection = s; parent.onSection(s) }
        }

        @objc func held(_ g: UILongPressGestureRecognizer) {
            guard let cv = g.view as? UICollectionView else { return }
            switch g.state {
            case .began:
                guard let ip = cv.indexPathForItem(at: g.location(in: cv)), let a = cv.layoutAttributesForItem(at: ip) else { return }
                let e = shown(ip), options = parent.tones(e)
                guard !options.isEmpty else { return }
                pressed = ip
                cv.isScrollEnabled = false
                parent.onHold(.began(options: options, current: e, cell: cv.convert(a.frame, to: nil)))
            case .changed:
                if pressed != nil { parent.onHold(.moved(g.location(in: nil))) }
            case .ended, .cancelled, .failed:
                guard let ip = pressed else { return }
                parent.onHold(g.state == .ended ? .ended : .cancelled)
                pressed = nil
                cv.isScrollEnabled = true
                cv.reloadItems(at: [ip])  // shows the tone just picked
            default: break
            }
        }
    }
}

/// A long-press on a toned emoji, in window coordinates.
enum EmojiHold {
    case began(options: [String], current: String, cell: CGRect)
    case moved(CGPoint)
    case ended, cancelled
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// Memory: CoreText keeps every emoji it has drawn decoded for the life of the process; nothing frees it. The
/// bitmap it keeps is the font's strike for the point size on this screen: up to 17 pt (51 px at 3x) it is a small
/// strike, at 20 pt and up the 160 px one, about 3x the memory per emoji. So the label draws at 17 pt and a
/// transform scales it to the cell's size: a slightly softer glyph, a third of the memory.
final class EmojiCellView: UICollectionViewCell {
    static let drawSize: CGFloat = 17
    let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        label.font = .systemFont(ofSize: Self.drawSize)
        contentView.addSubview(label)
        contentView.layer.cornerRadius = 8
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }
    /// The glyph's on-screen size; the label is laid out at drawSize and scaled up.
    var glyphSize: CGFloat = 17 { didSet { if glyphSize != oldValue { setNeedsLayout() } } }
    override func layoutSubviews() {
        super.layoutSubviews()
        let k = glyphSize / Self.drawSize
        label.transform = .identity
        label.bounds = CGRect(x: 0, y: 0, width: contentView.bounds.width / k, height: contentView.bounds.height / k)
        label.center = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        label.transform = CGAffineTransform(scaleX: k, y: k)
    }
    override var isHighlighted: Bool { didSet { contentView.backgroundColor = isHighlighted ? .tertiarySystemFill : nil } }
}

private final class EmojiHeaderView: UICollectionReusableView {
    let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabel
        label.frame = bounds
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// The search field, and in search mode the row of results under it.
struct EmojiSearchBar: View {
    static let fieldHeight: CGFloat = 34
    static let resultsHeight: CGFloat = 40
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
                                Text(e).font(.system(size: EmojiCellView.drawSize)).scaleEffect(30 / EmojiCellView.drawSize).frame(width: 44, height: Self.resultsHeight)  // small strike, see EmojiCellView
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
