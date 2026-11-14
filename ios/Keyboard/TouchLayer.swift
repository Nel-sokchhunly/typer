import UIKit

/// The one UIKit view that takes every touch on the keys. SwiftUI per-key gestures drop or delay fast, overlapping
/// touches in a keyboard extension, and the gaps between keys hit nothing; here every touch resolves to the nearest key
/// (KeyLayout.hit) and KeyTouches decides what fires. Touches outside the key area fall through to the SwiftUI bar and panel.
final class TouchLayer: UIView {
    var keys: (CGFloat) -> [Key] = { _ in [] }
    var press: () -> Void = {}
    var fire: (KeyAction) -> Void = { _ in }
    var pressedChanged: ([Key]) -> Void = { _ in }

    private var tracker = KeyTouches<ObjectIdentifier>()
    private var repeater: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { repeater?.cancel() }

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
            if let k = key(t) { run(tracker.down(ObjectIdentifier(t), k)) }
        }
        pressedChanged(tracker.pressed)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if let k = key(t) { run(tracker.move(ObjectIdentifier(t), k)) }
        }
        pressedChanged(tracker.pressed)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let k = key(t) { run(tracker.up(ObjectIdentifier(t), k)) } else { run(tracker.cancel(ObjectIdentifier(t))) }
        }
        pressedChanged(tracker.pressed)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { run(tracker.cancel(ObjectIdentifier(t))) }
        pressedChanged(tracker.pressed)
    }

    private func reset() {
        repeater?.cancel()
        tracker = KeyTouches()
        pressedChanged([])
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
