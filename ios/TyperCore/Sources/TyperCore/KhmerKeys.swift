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
        ["ាំ", "ៃ", "ឌ", "ធ", "អ", "ះ", "ញ", "គ", "ឡ", "៖", "៉", "ឯ"],
        ["ឍ", "ឃ", "ជ", "េះ", "ព", "ណ", "ំ", "ុះ", "៕", "?"],
    ]

    /// Long-press lists by key text, both layers, in #79's definition order. ៑ on ្ is ours (#79 has it nowhere).
    /// ៓ (U+17D3) is left out: Unicode deprecates it.
    public static let longPress: [String: [String]] = {
        var m: [String: [String]] = [
            "ឥ": ["ឦ"], "ឲ": ["ឱ"], "ឪ": ["ឧ", "ឱ", "ឳ", "ឩ", "ឨ"], "ឮ": ["ឭ", "ឰ"], "៊": ["៘"], "្": ["៑"],
            "៛": ["$", "€"], "%": ["៖"], "៍": ["៙"], "័": ["៚"], "៏": ["ៗ"], "(": ["{", "«"], ")": ["}", "»"],
            "៌": ["×"], "ឈ": ["ៜ"], "ឺ": ["៝"], "ឬ": ["ឫ"], "ះ": ["ៈ"], "គ": ["ឝ"], "ព": ["ឞ"],
            "!": ["\u{200D}"], "ៗ": ["\u{200C}"],  // zero-width joiner, non-joiner
        ]
        for (i, d) in base[0].prefix(10).enumerated() {  // ១ → 1 ៱ … ០ → 0 ៰
            let n = (i + 1) % 10
            m[d] = [String(n), String(UnicodeScalar(0x17F0 + UInt32(n))!)]
        }
        return m
    }()

    /// A long-press option's face: the invisible joiners get a name. A bare combining mark needs no ◌ of ours:
    /// iOS text drawing already puts one under it (adding U+25CC showed two).
    public static func optionLabel(for text: String) -> String {
        switch text {
        case "\u{200D}": return "ZWJ"
        case "\u{200C}": return "ZWNJ"
        default: return text
        }
    }
}
