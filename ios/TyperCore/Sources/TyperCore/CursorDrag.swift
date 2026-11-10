import Foundation

/// The UTF-16 offset for `adjustTextPosition(byCharacterOffset:)` that moves the caret `clusters`
/// clusters (negative = left, positive = right) without stopping inside one. Clamped to the
/// available context; 0 when the context is nil or empty in that direction.
/// A cluster is a Swift `Character`, except that a coeng (U+17D2) joins the next one: the runtime's
/// grapheme rules split ខ្ញុំ into ខ្ + ញុំ, which is exactly the break the drag must not stop at.
public func cursorOffset(before: String?, after: String?, clusters: Int) -> Int {
    func units(_ s: String?) -> [Int] {  // UTF-16 length of each cluster
        var out: [Int] = []
        var joined = false
        for ch in s ?? "" {
            if joined { out[out.count - 1] += ch.utf16.count } else { out.append(ch.utf16.count) }
            joined = ch.unicodeScalars.last?.value == 0x17D2
        }
        return out
    }
    return clusters < 0
        ? -units(before).suffix(-clusters).reduce(0, +)
        : units(after).prefix(clusters).reduce(0, +)
}
