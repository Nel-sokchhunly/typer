import Cocoa
import InputMethodKit

/// Screen rect of the start of the text being typed.
func caretRect(_ client: IMKTextInput) -> NSRect {
    var rect = NSRect.zero
    client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
    return rect
}

/// Numbered suggestion list under the caret. Drawn by us because IMKCandidates
/// doesn't reliably move its highlight when driven from code.
final class CandidatePanel {
    static let shared = CandidatePanel()
    var onPick: ((Int) -> Void)?

    private let stack = NSStackView()
    private lazy var panel: NSPanel = {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = .popUpMenu
        p.hasShadow = true
        p.backgroundColor = .windowBackgroundColor
        p.becomesKeyOnlyIfNeeded = true
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        p.contentView = stack
        return p
    }()

    func show(_ items: [String], selected: Int, caret: NSRect) {
        _ = panel
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, text) in items.enumerated() {
            let on = i == selected
            let row = NSButton(title: "", target: self, action: #selector(click(_:)))
            row.tag = i
            row.isBordered = false
            row.alignment = .left
            row.attributedTitle = NSAttributedString(
                string: " \(i + 1)  \(text) ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 18),
                    .foregroundColor: on ? NSColor.alternateSelectedControlTextColor : NSColor.labelColor,
                ])
            row.wantsLayer = true
            row.layer?.cornerRadius = 5
            row.layer?.backgroundColor = on ? NSColor.controlAccentColor.cgColor : nil
            stack.addArrangedSubview(row)
        }
        let size = stack.fittingSize
        for row in stack.arrangedSubviews {  // full-width rows so the highlight is a bar
            row.widthAnchor.constraint(equalToConstant: size.width - 8).isActive = true
        }
        var origin = NSPoint(x: caret.minX, y: caret.minY - size.height - 4)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(caret.origin) }) ?? NSScreen.main {
            let vf = screen.visibleFrame
            if origin.y < vf.minY { origin.y = caret.maxY + 4 }  // no room below: flip above
            origin.x = min(max(origin.x, vf.minX), vf.maxX - size.width)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    @objc private func click(_ sender: NSButton) {
        onPick?(sender.tag)
    }
}
