/// Whether the Keyboard's shift should start on, like Apple's keyboard follows a field's autocapitalization.
public enum AutoCap {
    public enum Kind { case none, words, sentences, allCharacters }

    /// Khmer mode never auto-capitalizes (Sing is typed lower case); English mode follows the field.
    public static func shouldShift(before: String?, kind: Kind, khmerMode: Bool) -> Bool {
        if khmerMode { return false }
        let text = before ?? ""
        switch kind {
        case .none: return false
        case .allCharacters: return true
        case .words: return text.last?.isWhitespace ?? true
        case .sentences:
            guard let last = text.last else { return true }
            if last.isNewline { return true }
            guard last.isWhitespace else { return false }
            // whitespace after a sentence end; the end itself must come right before the spaces
            let before = text.reversed().drop { $0.isWhitespace }
            return before.first.map { ".?!".contains($0) } ?? true
        }
    }
}
