/// The Khmer layout's keys in the standard Khmer arrangement (#79's observed key map), as the text each key types;
/// a key may type several code points (ុំ). Row 4 is the 10 keys between shift and delete.
public enum KhmerKeys {
    public static let base: [[String]] = [
        ["១", "២", "៣", "៤", "៥", "៦", "៧", "៨", "៩", "០", "ឥ", "ឲ"],
        ["ឆ", "ឹ", "េ", "រ", "ត", "យ", "ុ", "ិ", "ោ", "ផ", "ៀ", "ឪ"],
        ["ា", "ស", "ដ", "ថ", "ង", "ហ", "្", "ក", "ល", "ើ", "់", "ឮ"],
        ["ឋ", "ខ", "ច", "វ", "ប", "ន", "ម", "ុំ", "។", "៊"],
    ]
    /// Shown while shift is on; same shape as `base`.
    public static let shift: [[String]] = [
        ["!", "ៗ", "\"", "៛", "%", "៍", "័", "៏", "(", ")", "៌", "៎"],
        ["ឈ", "ឺ", "ែ", "ឬ", "ទ", "ួ", "ូ", "ី", "ៅ", "ភ", "ឿ", "ឰ"],
        ["ាំ", "ៃ", "ឌ", "ធ", "អ", "ះ", "ញ", "គ", "ឡ", "ោះ", "៉", "ឯ"],
        ["ឍ", "ឃ", "ជ", "េះ", "ព", "ណ", "ំ", "ុះ", "៕", "?"],
    ]

    /// The key face: text starting with a combining mark sits on a dotted circle (◌ិ); the key still types `text`.
    public static func label(for text: String) -> String {
        switch text.unicodeScalars.first?.properties.generalCategory {
        case .nonspacingMark?, .spacingMark?: return "\u{25CC}" + text
        default: return text
        }
    }
}
