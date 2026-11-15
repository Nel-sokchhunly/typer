import UIKit

/// The one UIKit view that takes every touch on the keys. SwiftUI per-key gestures drop or delay fast, overlapping
/// touches in a keyboard extension, and the gaps between keys hit nothing; here every touch resolves to the nearest key
/// (KeyLayout.hit) and KeyTouches decides what fires. Touches outside the key area fall through to the SwiftUI bar and panel.
/// Holding a key with a long-press list 0.3 s opens its LongPressPanel; that touch then picks an option instead.
final class TouchLayer: UIView {
    var keys: (CGFloat) -> [Key] = { _ in [] }
    var press: () -> Void = {}
    var fire: (KeyAction) -> Void = { _ in }
    var pressedChanged: ([Key]) -> Void = { _ in }
    var panelChanged: (LongPressPanel?, Int) -> Void = { _, _ in }

    private var tracker = KeyTouches<ObjectIdentifier>()
    private var repeater: Task<Void, Never>?
    private var hold: (id: ObjectIdentifier, timer: DispatchWorkItem)?
    private var panel: (id: ObjectIdentifier, panel: LongPressPanel, selected: Int)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        // Not .clear: since iOS 26 the host app decides where keyboard touches go from our layer tree, and a fully
        // clear view counts as see-through, so no touch reached the keyboard at all. An invisible tint makes it solid.
        backgroundColor = UIColor(white: 0.5, alpha: 0.015)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { repeater?.cancel(); hold?.timer.cancel() }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard bounds.contains(point), let top = keys(bounds.width).map(\.rect.minY).min() else { return false }
        return point.y >= top - 3
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil { reset() }
    }

    private func key(_ t: UITouch) -> Key? { KeyLayout.hit(t.location(in: self), in: keys(bounds.width)) }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            closePanel(typing: true)  // like rollover: a new touch finishes the open panel
            hold?.timer.cancel(); hold = nil
            guard let k = key(t) else { continue }
            run(tracker.down(ObjectIdentifier(t), k))
            if !k.longPress.isEmpty { startHold(t, k) }
        }
        pressedChanged(tracker.pressed)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if let p = panel, p.id == ObjectIdentifier(t) {
                let i = p.panel.index(at: t.location(in: self).x)
                if i != p.selected { panel?.selected = i; panelChanged(p.panel, i) }
            } else if let k = key(t) { run(tracker.move(ObjectIdentifier(t), k)) }
        }
        pressedChanged(tracker.pressed)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            endHold(t)
            if panel?.id == ObjectIdentifier(t) { closePanel(typing: true) }
            else if let k = key(t) { run(tracker.up(ObjectIdentifier(t), k)) } else { run(tracker.cancel(ObjectIdentifier(t))) }
        }
        pressedChanged(tracker.pressed)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            endHold(t)
            if panel?.id == ObjectIdentifier(t) { closePanel(typing: false) }
            run(tracker.cancel(ObjectIdentifier(t)))
        }
        pressedChanged(tracker.pressed)
    }

    private func reset() {
        repeater?.cancel()
        hold?.timer.cancel(); hold = nil
        tracker = KeyTouches()
        closePanel(typing: false)
        pressedChanged([])
    }

    /// Opens the panel if the finger is still on or near `key` after 0.3 s (a wobble onto the neighbour's edge
    /// doesn't count as leaving); the tracker lets go of the touch, so the key fires nothing itself.
    private func startHold(_ t: UITouch, _ key: Key) {
        let id = ObjectIdentifier(t)
        let timer = DispatchWorkItem { [weak self, weak t] in
            guard let self, let t, hold?.id == id,
                  key.rect.insetBy(dx: -12, dy: -12).contains(t.location(in: self)) else { return }
            hold = nil
            _ = tracker.cancel(id)
            let p = LongPressPanel(key: key, width: bounds.width)
            panel = (id, p, 0)
            press()  // haptic: the panel is open
            pressedChanged(tracker.pressed)
            panelChanged(p, 0)
        }
        hold = (id, timer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: timer)
    }

    private func endHold(_ t: UITouch) {
        if hold?.id == ObjectIdentifier(t) { hold?.timer.cancel(); hold = nil }
    }

    private func closePanel(typing: Bool) {
        guard let p = panel else { return }
        panel = nil
        panelChanged(nil, 0)
        if typing { fire(.char(p.panel.options[p.selected])) }
    }

    private func run(_ effects: [KeyEffect]) {
        for e in effects {
            switch e {
            case .press: press()
            case .fire(let a): fire(a)
            case .startRepeat:
                repeater = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    while !Task.isCancelled {
                        self?.fire(.backspace)
                        try? await Task.sleep(nanoseconds: 80_000_000)
                    }
                }
            case .stopRepeat: repeater?.cancel()
            }
        }
    }
}
