import Cocoa
import InputMethodKit

/// "EN" / "ខ" under the cursor: bright for a moment after a toggle, then faint and always there.
/// Sits below the current line, click-through; moves after each key. Hidden while suggestions show.
enum ModeBadge {
    private static let faint: CGFloat = 0.4
    // the app moves its caret after us; re-check soon and keep re-checking for slow apps
    private static let followDelays = [0.015, 0.05, 0.15]
    private static var generation = 0
    private static let label: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.font = .systemFont(ofSize: 12, weight: .semibold)
        l.alignment = .center
        return l
    }()
    private static let panel: NSPanel = {
        let (p, v) = popupPanel(radius: 6)
        p.ignoresMouseEvents = true  // never in the way of a click
        p.hasShadow = false
        p.setContentSize(NSSize(width: 30, height: 20))
        label.frame = NSRect(x: 0, y: 3, width: 30, height: 15)  // labels draw top-aligned; nudge to center
        v.addSubview(label)
        return p
    }()

    /// Just toggled: bright, then fade to faint.
    static func show(_ text: String, near client: IMKTextInput) {
        guard place(text, client) else { return }
        panel.alphaValue = 1
        let mine = bump()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if mine == generation { panel.animator().alphaValue = faint }
        }
    }

    /// Any key or focus change: move the faint badge to the caret.
    static func follow(_ text: String, near client: IMKTextInput) {
        let mine = bump()
        for delay in followDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard mine == generation, place(text, client) else { return }
                panel.alphaValue = faint
            }
        }
    }

    static func hide() {
        bump()
        panel.orderOut(nil)
    }

    @discardableResult private static func bump() -> Int {
        generation += 1
        return generation
    }

    private static func place(_ text: String, _ client: IMKTextInput) -> Bool {
        let caret = caretRect(client)
        guard caret != .zero else {  // app doesn't report a caret: nowhere sensible to sit
            panel.orderOut(nil)
            return false
        }
        label.stringValue = text
        // behind the caret (right edge on it), so it never covers what comes next
        panel.setFrameOrigin(NSPoint(x: caret.minX - panel.frame.width, y: caret.minY - panel.frame.height - 2))
        panel.orderFrontRegardless()
        return true
    }
}
