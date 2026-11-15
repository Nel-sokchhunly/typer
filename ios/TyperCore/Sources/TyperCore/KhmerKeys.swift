/// The Khmer layout's keys in the standard Khmer arrangement (#79's observed key map), as the text each key types;
/// a key may type several code points (ុំ). Row 4 is the 10 keys between shift and delete.
public enum KhmerKeys {
    public static let base: [[String]] = [
        ["១", "២", "៣", "៤", "៥", "៦", "៧", "៨", "៩", "០", "ឥ", "ឲ"],
        ["ឆ", "ឹ", "េ", "រ", "ត", "យ", "ុ", "ិ", "ោ", "ផ", "ៀ", "ឪ"],
        ["ា", "ស", "ដ", "ថ", "ង", "ហ", "្", "ក", "ល", "ើ", "់", "ឮ"],
        ["ឋ", "ខ", "ច", "វ", "ប", "ន", "ម", "ុំ", "។", "៊"],
    ]
}
