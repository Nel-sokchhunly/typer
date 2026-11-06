import Cocoa
import InputMethodKit

/// "EN" / "ខ" under the cursor, on yellow: bright for a moment after a toggle, then faint and always there.
/// Sits below the current line, click-through. Hidden while typing; back at the caret after a pause.
enum ModeBadge {
    private static let faint: CGFloat = 0.75
    private static let restDelay = 1.0  // typing pause before it comes back
    private static var generation = 0
    private static let label: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.font = .systemFont(ofSize: 12, weight: .semibold)
        l.alignment = .center
        l.textColor = NSColor(white: 0.1, alpha: 1)  // dark on yellow, readable in light and dark mode
        return l
    }()
    private static let panel: NSPanel = {
        let (p, v) = popupPanel(radius: 6)
        p.ignoresMouseEvents = true  // never in the way of a click
        p.hasShadow = false
        p.setContentSize(NSSize(width: 30, height: 20))
        label.frame = NSRect(x: 0, y: 3, width: 30, height: 15)  // labels draw top-aligned; nudge to center
        let fill = NSView(frame: NSRect(x: 0, y: 0, width: 30, height: 20))
        fill.wantsLayer = true
        fill.layer?.backgroundColor = NSColor(red: 0.96, green: 0.78, blue: 0.26, alpha: 1).cgColor  // #f5c842
        v.addSubview(fill)
        v.addSubview(label)
        return p
    }()

    /// Just toggled: bright, then fade to faint.
    static func show(_ text: String, near client: IMKTextInput) {
        guard Typer.setting("badge") else { return hide() }
        guard place(text, client) else { return }
        panel.alphaValue = 1
        let mine = bump()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if mine == generation { panel.animator().alphaValue = faint }
        }
    }

    /// Any key or focus change: out of the way now, faint at the caret once typing pauses.
    static func follow(_ text: String, near client: IMKTextInput) {
        let mine = bump()
        panel.orderOut(nil)
        guard Typer.setting("badge") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + restDelay) {
            guard mine == generation, place(text, client) else { return }
            panel.alphaValue = faint
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
        panel.setFrameOrigin(NSPoint(x: caret.minX - panel.frame.width, y: caret.minY - panel.frame.height - 6))
        panel.orderFrontRegardless()
        return true
    }
}
