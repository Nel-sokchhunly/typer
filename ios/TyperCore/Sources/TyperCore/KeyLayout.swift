import CoreGraphics
import Foundation

public enum KeyPage: Int { case letters, numbers, symbols }

public enum KeyAction: Hashable {
    case char(String), punct(String)
    case shift, symbols, page, emoji, backspace, globe, mode, space, returnKey
    case slot  // the idle bar's rightmost slot: switch layouts
}

public struct Key: Equatable {
    public let action: KeyAction
    public let rect: CGRect
    /// Long-press list (Khmer layout letters only); empty: no long-press.
    public let longPress: [String]
    public init(action: KeyAction, rect: CGRect, longPress: [String] = []) {
        self.action = action; self.rect = rect; self.longPress = longPress
    }
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
    /// The Khmer layout's letters: one row more.
    public static let khmerHeight: CGFloat = height + keyHeight + rowGap
    public static let slotWidth: CGFloat = 52

    private static let letters = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    private static let numbers = ["1234567890", "-/:;()$&@\"", ".,?!'"]
    private static let symbols = ["[]{}#%^*+=", "_\\|~<>€£¥•", ".,?!'"]
    /// The idle candidate bar's keys: Khmer punctuation in Khmer mode, the 123-page regulars in English mode.
    public static let punctuation = ["។", "៕", "ៗ", "៛", "?", "!"]
    public static let englishPunctuation = [",", ".", "'", "\"", "@", "-"]
    public static let khmerPunctuation = punctuation + [",", "."]

    /// `bar`: the idle candidate bar's punctuation keys, then the slot; empty while composing. `upper`: letters page
    /// with shift on (the Khmer layout: its shift layer). `khmer`: the Khmer layout, 4 rows of 12 letters and no ខ/EN key.
    public static func keys(width w: CGFloat, page: KeyPage, upper: Bool, globe: Bool, bar: [String],
                            khmer: Bool = false) -> [Key] {
        let inner = w - 2 * margin
        let kw = (inner - 9 * gap) / 10
        let fw = (inner - 7 * kw - 8 * gap) / 2  // function key beside the letters of row 3
        var out: [Key] = []
        func add(_ a: KeyAction, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat = keyHeight,
                 longPress: [String] = []) {
            out.append(Key(action: a, rect: CGRect(x: x, y: y, width: width, height: height), longPress: longPress))
        }

        if !bar.isEmpty {
            let n = CGFloat(bar.count)
            let pw = (inner - slotWidth - n * gap) / n
            for (j, p) in bar.enumerated() { add(.punct(p), margin + CGFloat(j) * (pw + gap), barTop + 2, pw, 36) }
            add(.slot, w - margin - slotWidth, barTop + 2, slotWidth, 36)
        }

        let khmerLetters = khmer && page == .letters
        if khmerLetters {
            let kw = (inner - 11 * gap) / 12
            for (i, row) in (upper ? KhmerKeys.shift : KhmerKeys.base).enumerated() {
                let y = rowsTop + CGFloat(i) * (keyHeight + rowGap)
                var x = margin
                if i == 3 { add(.shift, x, y, kw); x += kw + gap }
                for s in row { add(.char(s), x, y, kw, longPress: KhmerKeys.longPress[s] ?? []); x += kw + gap }
                if i == 3 { add(.backspace, x, y, kw) }
            }
        }

        let rows = [letters, numbers, symbols][page.rawValue]
        for i in 0..<3 where !khmerLetters {
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

        let y = rowsTop + (khmerLetters ? 4 : 3) * (keyHeight + rowGap)
        var x = margin
        func fixed(_ a: KeyAction, _ f: CGFloat) { add(a, x, y, kw * f); x += kw * f + gap }
        fixed(.page, 1.35)
        fixed(.emoji, 1.1)
        if globe { fixed(.globe, 1.1) }
        if !khmer { fixed(.mode, 1.1) }
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

/// A held key's long-press panel: the key's own text then its list, one cell each, in a row above the key. Cell 0
/// sits over the key and the list runs toward the keyboard's wider half (leftward near the right edge, like Gboard);
/// the row is then shifted inside the keyboard if it overhangs.
public struct LongPressPanel: Equatable {
    public static let cellHeight: CGFloat = 48
    public let options: [String]
    /// `cells[i]` shows `options[i]`.
    public let cells: [CGRect]

    public init(key: Key, width: CGFloat) {
        let own: [String] = if case .char(let t) = key.action { [t] } else { [] }
        self.init(options: own + key.longPress, above: key.rect, width: width)
    }

    /// The same panel above any rect, e.g. an emoji in the Emoji panel (its skin tones).
    public init(options: [String], above r: CGRect, width: CGFloat) {
        self.options = options
        let cw = r.width + 8
        let step = r.midX < width / 2 ? cw : -cw
        let y = max(0, r.minY - Self.cellHeight - 4)
        let xs = options.indices.map { r.midX - cw / 2 + CGFloat($0) * step }
        let lo = xs.min()!, hi = xs.max()! + cw, m = KeyLayout.margin
        let dx = lo < m ? m - lo : hi > width - m ? width - m - hi : 0
        cells = xs.map { CGRect(x: $0 + dx, y: y, width: cw, height: Self.cellHeight) }
    }

    /// The option under a finger at `x`; past either end, the end cell.
    public func index(at x: CGFloat) -> Int {
        cells.indices.min { abs(cells[$0].midX - x) < abs(cells[$1].midX - x) }!
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
