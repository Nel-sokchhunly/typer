import Cocoa
import InputMethodKit

/// Small "EN" / "ខ" label under the cursor for a moment after toggling mode.
enum ModeBadge {
    private static var generation = 0
    private static let label: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.font = .systemFont(ofSize: 15, weight: .semibold)
        l.alignment = .center
        l.frame = NSRect(x: 0, y: 0, width: 44, height: 26)
        return l
    }()
    private static let panel: NSPanel = {
        let p = NSPanel(
            contentRect: label.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = .popUpMenu
        p.backgroundColor = .windowBackgroundColor
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.contentView = label
        return p
    }()

    static func show(_ text: String, near client: IMKTextInput) {
        var caret = NSRect.zero
        client.attributes(forCharacterIndex: 0, lineHeightRectangle: &caret)
        label.stringValue = text
        panel.setFrameOrigin(NSPoint(x: caret.minX, y: caret.minY - panel.frame.height - 4))
        panel.orderFrontRegardless()
        generation += 1
        let mine = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if mine == generation { panel.orderOut(nil) }
        }
    }
}
