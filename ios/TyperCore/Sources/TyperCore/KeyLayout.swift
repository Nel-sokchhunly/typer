import CoreGraphics
import Foundation

public enum KeyPage: Int { case letters, numbers, symbols }

public enum KeyAction: Hashable {
    case char(String), punct(String)
    case shift, symbols, page, backspace, globe, mode, space, returnKey
}

public struct Key: Equatable {
    public let action: KeyAction
    public let rect: CGRect
    public init(action: KeyAction, rect: CGRect) { self.action = action; self.rect = rect }
}

/// Key frames in the keyboard view's coordinates. The SwiftUI keys are drawn from these and the UIKit touch layer
/// hit-tests against them, so what you see is what you hit.
public enum KeyLayout {
    public static let margin: CGFloat = 6  // same side inset for bar and keys; clears the iOS 26 frame's rounded corners
    public static let gap: CGFloat = 6
    public static let keyHeight: CGFloat = 43
    public static let rowGap: CGFloat = 8
    public static let barTop: CGFloat = 10
    public static let barHeight: CGFloat = 40
    public static let rowsTop: CGFloat = barTop + barHeight + 6
    /// Candidate bar + gap + four rows: the controller sizes the keyboard to exactly this.
    public static let height: CGFloat = rowsTop + 4 * keyHeight + 3 * rowGap + 4

    private static let letters = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    private static let numbers = ["1234567890", "-/:;()$&@\"", ".,?!'"]
    private static let symbols = ["[]{}#%^*+=", "_\\|~<>€£¥•", ".,?!'"]
    public static let punctuation = ["។", "៕", "ៗ", "៛", "?", "!"]

    /// `bar`: include the idle candidate bar's punctuation keys. `upper`: letters page with shift on.
    public static func keys(width w: CGFloat, page: KeyPage, upper: Bool, globe: Bool, bar: Bool) -> [Key] {
        let inner = w - 2 * margin
        let kw = (inner - 9 * gap) / 10
        let fw = (inner - 7 * kw - 8 * gap) / 2  // function key beside the letters of row 3
        var out: [Key] = []
        func add(_ a: KeyAction, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat = keyHeight) {
            out.append(Key(action: a, rect: CGRect(x: x, y: y, width: width, height: height)))
        }

        if bar {
            let pw = (inner - 5 * gap) / 6
            for (j, p) in punctuation.enumerated() { add(.punct(p), margin + CGFloat(j) * (pw + gap), barTop + 2, pw, 36) }
        }

        let rows = [letters, numbers, symbols][page.rawValue]
        for i in 0..<3 {
            let y = rowsTop + CGFloat(i) * (keyHeight + rowGap)
            let chars = Array(rows[i])
            var x = margin
            if i == 2 {
                add(page == .letters ? .shift : .symbols, x, y, fw)
                x += fw + gap
            }
            if i == 1 && page == .letters { x += (kw + gap) / 2 }
            let cw = i == 2 && page != .letters ? (inner - 2 * fw - 6 * gap) / 5 : kw
            for c in chars {
                let s = String(c)
                add(.char(page == .letters && upper ? s.uppercased() : s), x, y, cw)
                x += cw + gap
            }
            if i == 2 { add(.backspace, x, y, fw) }
        }

        let y = rowsTop + 3 * (keyHeight + rowGap)
        var x = margin
        func fixed(_ a: KeyAction, _ f: CGFloat) { add(a, x, y, kw * f); x += kw * f + gap }
        fixed(.page, 1.35)
        if globe { fixed(.globe, 1.1) }
        fixed(.mode, 1.1)
        let space = w - margin - kw * 2.1 - x - gap  // flexible
        add(.space, x, y, space)
        add(.returnKey, x + space + gap, y, kw * 2.1)
        return out
    }

    /// The key containing the point, else the nearest by distance to its rect: no dead zones in gaps or at the edges.
    public static func hit(_ p: CGPoint, in keys: [Key]) -> Key? {
        func dist(_ r: CGRect) -> CGFloat {
            hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
        }
        return keys.min { dist($0.rect) < dist($1.rect) }
    }
}

public enum KeyEffect: Equatable {
    case press  // touch-down feedback: haptic and click
    case fire(KeyAction)
    case startRepeat, stopRepeat  // backspace auto-repeat (0.4 s, then every 0.08 s); the caller owns the timer
}

/// Touch semantics like Apple's keyboard. Keys fire on touch-up for the key under the finger; a new touch finishes
/// every earlier one at once (rollover), so at most one touch is live. Backspace fires on touch-down and repeats.
public struct KeyTouches<ID: Hashable> {
    private var held: (id: ID, key: Key, repeating: Bool)?
    public init() {}

    /// The key(s) to highlight.
    public var pressed: [Key] { held.map { [$0.key] } ?? [] }

    public mutating func down(_ id: ID, _ key: Key) -> [KeyEffect] {
        var fx: [KeyEffect] = []
        if let h = held { fx.append(h.repeating ? .stopRepeat : .fire(h.key.action)) }
        fx.append(.press)
        held = (id, key, key.action == .backspace)
        if key.action == .backspace { fx += [.fire(.backspace), .startRepeat] }
        return fx
    }

    public mutating func move(_ id: ID, _ key: Key) -> [KeyEffect] {
        guard let h = held, h.id == id, h.key != key else { return [] }
        held = (id, key, false)
        return h.repeating ? [.stopRepeat] : []
    }

    public mutating func up(_ id: ID, _ key: Key) -> [KeyEffect] {
        guard let h = held, h.id == id else { return [] }
        held = nil
        return h.repeating ? [.stopRepeat] : [.fire(key.action)]
    }

    public mutating func cancel(_ id: ID) -> [KeyEffect] {
        guard let h = held, h.id == id else { return [] }
        held = nil
        return h.repeating ? [.stopRepeat] : []
    }
}
