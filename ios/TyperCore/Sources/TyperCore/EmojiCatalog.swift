import Foundation

/// Where Recents and tone choices live. On the phone only; nothing here leaves the device.
public protocol EmojiStore: AnyObject {
    var recents: [String] { get set }
    /// base emoji -> the toned variant last picked for it
    var tones: [String: String] { get set }
}

public final class UserDefaultsEmojiStore: EmojiStore {
    private let defaults: UserDefaults
    public init(_ defaults: UserDefaults) { self.defaults = defaults }
    public var recents: [String] {
        get { defaults.stringArray(forKey: "emoji.recents") ?? [] }
        set { defaults.set(newValue, forKey: "emoji.recents") }
    }
    public var tones: [String: String] {
        get { defaults.dictionary(forKey: "emoji.tones") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "emoji.tones") }
    }
}

public final class InMemoryEmojiStore: EmojiStore {
    public var recents: [String] = []
    public var tones: [String: String] = [:]
    public init() {}
}

public struct EmojiSection: Equatable {
    public let title: String
    /// SF Symbol for the category bar
    public let symbol: String
    /// display strings, each with its remembered tone
    public let emoji: [String]
}

/// The panel's logic: sections, Recents, skin tones, search. Data is data/out/emoji.json.
public final class EmojiCatalog {
    private struct Group: Decodable { let group: String; let emoji: [Item] }
    private struct Item: Decodable {
        let e: String
        let v: String
        let n: String
        let k: [String]?
        let t: [String]?
    }

    public static let recentsLimit = 32
    private static let symbols = [
        "Smileys & Emotion": "face.smiling", "People & Body": "person", "Animals & Nature": "leaf",
        "Food & Drink": "fork.knife", "Travel & Places": "car", "Activities": "soccerball",
        "Objects": "lightbulb", "Symbols": "heart", "Flags": "flag",
    ]

    private let groups: [Group]
    private let maxVersion: Double
    private let store: EmojiStore
    private var baseOf: [String: String] = [:]  // toned variant -> base
    private var tonesOf: [String: [String]] = [:]  // base -> 5 tones

    /// Emoji newer than `maxVersion` (the Emoji version the running iOS can draw) are hidden.
    public init(data: Data, maxVersion: Double, store: EmojiStore) throws {
        self.groups = try JSONDecoder().decode([Group].self, from: data)
        self.maxVersion = maxVersion
        self.store = store
        for item in groups.flatMap(\.emoji) {
            guard let t = item.t else { continue }
            tonesOf[item.e] = t
            for x in t { baseOf[x] = item.e }
        }
    }

    public static func maxEmojiVersion(iOS v: OperatingSystemVersion) -> Double {
        let n = v.majorVersion * 100 + v.minorVersion
        return n < 1704 ? 15.0 : n < 1804 ? 15.1 : 16.0
    }

    public var sections: [EmojiSection] {
        var out: [EmojiSection] = []
        if !store.recents.isEmpty {
            out.append(EmojiSection(title: "Recently Used", symbol: "clock", emoji: store.recents))
        }
        for g in groups {
            let visible = g.emoji.filter(supported).map { shown($0.e) }
            if !visible.isEmpty {
                out.append(EmojiSection(title: g.group, symbol: Self.symbols[g.group] ?? "square", emoji: visible))
            }
        }
        return out
    }

    /// Record a pick: Recents (newest first, max 32) and, for a toned variant, the tone for its base.
    public func pick(_ emoji: String) {
        store.recents = Array(([emoji] + store.recents.filter { $0 != emoji }).prefix(Self.recentsLimit))
        var memory = store.tones
        if let base = baseOf[emoji] {
            memory[base] = emoji
        } else {
            memory[emoji] = nil
        }
        store.tones = memory
    }

    /// [] when the emoji has no tones, else the default plus five tones.
    public func tones(for emoji: String) -> [String] {
        let base = baseOf[emoji] ?? emoji
        return tonesOf[base].map { [base] + $0 } ?? []
    }

    /// The emoji as the grid shows it now: its base with the remembered tone (a toned variant maps to its base).
    public func display(_ emoji: String) -> String { shown(baseOf[emoji] ?? emoji) }

    /// Emoji where every word of the query starts some word of the name or keywords, name matches first.
    public func search(_ query: String) -> [String] {
        func words(_ s: String) -> [Substring] { s.lowercased().split { !$0.isLetter && !$0.isNumber } }
        let q = words(query)
        if q.isEmpty { return [] }
        func hit(_ text: [String]) -> Bool {
            let w = text.flatMap(words)
            return q.allSatisfy { t in w.contains { $0.hasPrefix(t) } }
        }
        let items = groups.lazy.flatMap(\.emoji).filter(supported)  // no copy of the catalog per search
        let byName = items.filter { hit([$0.n]) }
        let byKeyword = items.filter { !hit([$0.n]) && hit([$0.n] + ($0.k ?? [])) }
        return (Array(byName) + Array(byKeyword)).map { shown($0.e) }
    }

    private func supported(_ item: Item) -> Bool { (Double(item.v) ?? 0) <= maxVersion }
    private func shown(_ base: String) -> String { store.tones[base] ?? base }
}
