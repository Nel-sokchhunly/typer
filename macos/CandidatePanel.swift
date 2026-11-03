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
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        stack.frame = v.bounds
        stack.autoresizingMask = [.width, .height]
        v.addSubview(stack)
        return p
    }()

    func show(_ items: [String], selected: Int, caret: NSRect) {
        _ = panel
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let para = NSMutableParagraphStyle()
        para.firstLineHeadIndent = 10
        para.tabStops = [NSTextTab(textAlignment: .left, location: 32)]
        for (i, text) in items.enumerated() {
            let on = i == selected
            let title = NSMutableAttributedString(
                string: "\(i + 1)\t",
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
                    .foregroundColor: on ? NSColor.white.withAlphaComponent(0.75) : NSColor.tertiaryLabelColor,
                    .paragraphStyle: para,
                ])
            title.append(NSAttributedString(
                string: text + "    ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 20),
                    .foregroundColor: on ? NSColor.white : NSColor.labelColor,
                    .paragraphStyle: para,
                ]))
            let row = NSButton(title: "", target: self, action: #selector(click(_:)))
            row.tag = i
            row.isBordered = false
            row.alignment = .left
            row.attributedTitle = title
            row.wantsLayer = true
            row.layer?.cornerRadius = 6
            row.layer?.backgroundColor = on ? NSColor.controlAccentColor.cgColor : nil
            row.heightAnchor.constraint(equalToConstant: 34).isActive = true  // room for Khmer subscripts
            stack.addArrangedSubview(row)
        }
        var size = stack.fittingSize
        size.width = max(size.width, 180)
        for row in stack.arrangedSubviews {  // full-width rows so the highlight is a bar
            row.widthAnchor.constraint(equalToConstant: size.width - 10).isActive = true
        }
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

    @objc private func click(_ sender: NSButton) {
        onPick?(sender.tag)
    }
}
