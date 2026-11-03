import Cocoa
import InputMethodKit

/// Screen rect of the start of the text being typed.
func caretRect(_ client: IMKTextInput) -> NSRect {
    var rect = NSRect.zero
    client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
    return rect
}

/// Borderless frosted popup with rounded corners, like native menus. Put content in the returned view.
func popupPanel(radius: CGFloat = 10) -> (NSPanel, NSVisualEffectView) {
    let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    p.level = .popUpMenu
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = true
    p.becomesKeyOnlyIfNeeded = true
    let v = NSVisualEffectView()
    v.material = .popover
    v.state = .active
    v.blendingMode = .behindWindow
    let d = radius * 2 + 1
    let mask = NSImage(size: NSSize(width: d, height: d), flipped: false) { r in
        NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
        return true
    }
    mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    mask.resizingMode = .stretch
    v.maskImage = mask
    p.contentView = v
    return (p, v)
}

/// Numbered suggestion list under the caret. Drawn by us because IMKCandidates
/// doesn't reliably move its highlight when driven from code.
final class CandidatePanel {
    static let shared = CandidatePanel()
    var onPick: ((Int) -> Void)?

    private let stack = NSStackView()
    private lazy var panel: NSPanel = {
        let (p, v) = popupPanel()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        stack.frame = v.bounds
        stack.autoresizingMask = [.width, .height]
        v.addSubview(stack)
        return p
    }()

    func show(_ items: [String], selected: Int, caret: NSRect) {
        _ = panel
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let rows = items.enumerated().map { i, text in
            CandidateRow(number: i + 1, text: text, on: i == selected) { [weak self] in self?.onPick?(i) }
        }
        let width = max(rows.map(\.textWidth).max() ?? 0, 130)
        for row in rows {
            row.widthAnchor.constraint(equalToConstant: width).isActive = true
            row.heightAnchor.constraint(equalToConstant: CandidateRow.height).isActive = true
            stack.addArrangedSubview(row)
        }
        let size = stack.fittingSize
        var origin = NSPoint(x: caret.minX, y: caret.minY - size.height - 6)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(caret.origin) }) ?? NSScreen.main {
            let vf = screen.visibleFrame
            if origin.y < vf.minY { origin.y = caret.maxY + 6 }  // no room below: flip above
            origin.x = min(max(origin.x, vf.minX), vf.maxX - size.width)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.invalidateShadow()  // shadow follows the rounded mask
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

/// One suggestion: number + Khmer text, drawn directly. A button would clip Khmer stacks
/// (vowels above, subscripts below) to the system font's short line box.
private final class CandidateRow: NSView {
    static let height: CGFloat = 26
    static let textX: CGFloat = 26
    // Khmer Sangam MN's line box (2x point size) holds the full stack; the system fallback's (~1.1x) doesn't.
    private static let khmer = NSFont(name: "Khmer Sangam MN", size: 14) ?? .systemFont(ofSize: 14)
    private static let digits = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

    private let number: NSAttributedString
    private let text: NSAttributedString
    private let on: Bool
    private let pick: () -> Void
    var textWidth: CGFloat { ceil(text.size().width) + Self.textX + 14 }

    init(number n: Int, text t: String, on: Bool, pick: @escaping () -> Void) {
        number = NSAttributedString(string: "\(n)", attributes: [
            .font: Self.digits,
            .foregroundColor: on ? NSColor.white.withAlphaComponent(0.75) : NSColor.tertiaryLabelColor,
        ])
        text = NSAttributedString(string: t, attributes: [
            .font: Self.khmer, .foregroundColor: on ? NSColor.white : NSColor.labelColor,
        ])
        self.on = on
        self.pick = pick
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        if on {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        let mid = bounds.midY
        number.draw(at: NSPoint(x: 9, y: mid - number.size().height / 2))
        text.draw(at: NSPoint(x: Self.textX, y: mid - text.size().height / 2))
    }

    override func mouseDown(with event: NSEvent) { pick() }
}
