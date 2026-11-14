/// Which part of a Suggestion differs from the first one: strip the common prefix and suffix by Character
/// (grapheme cluster, so Khmer clusters are never split). nil when nothing of `s` differs.
public enum SuggestionDiff {
    public static func changed(_ s: String, from first: String) -> Range<String.Index>? {
        let prefix = zip(s, first).prefix { $0 == $1 }.count
        let start = s.index(s.startIndex, offsetBy: prefix)
        let room = min(s.count, first.count) - prefix  // the suffix may not overlap the prefix
        let suffix = zip(s.reversed(), first.reversed()).prefix(room).prefix { $0 == $1 }.count
        let end = s.index(s.endIndex, offsetBy: -suffix)
        return start < end ? start..<end : nil
    }
}
