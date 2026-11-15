import Foundation

/// One Clip: the copied text and when the Keyboard first noticed it.
public struct Clip: Codable, Equatable {
    public let text: String
    public let at: Date
    public init(text: String, at: Date) { self.text = text; self.at = at }

    /// How the Clipboard panel shows it: whitespace collapsed to single spaces (one line; the view adds the ellipsis).
    public var line: String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
}

/// Where the Clips live: on the phone only, in the Keyboard's own storage.
public protocol ClipStore: AnyObject {
    var clips: [Clip] { get set }
}

public final class InMemoryClipStore: ClipStore {
    public var clips: [Clip] = []
    public init() {}
}

/// A small JSON file, written with complete file protection: unreadable while the phone is locked (then it reads as empty).
public final class FileClipStore: ClipStore {
    private let url: URL
    public init(url: URL) { self.url = url }
    public var clips: [Clip] {
        get { (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([Clip].self, from: $0) } ?? [] }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }
}

/// The Clipboard panel's list: text only, newest first. Time is passed in so tests control it.
public final class ClipList {
    public static let limit = 10
    public static let maxLength = 5_000
    public static let keep: TimeInterval = 3_600

    private let store: ClipStore
    public init(store: ClipStore) { self.store = store }

    /// Blank text is ignored, long text is cut; a Clip with the same text moves to the top.
    public func add(_ text: String, now: Date) {
        guard !text.allSatisfy(\.isWhitespace) else { return }
        let text = String(text.prefix(Self.maxLength))
        store.clips = Array(([Clip(text: text, at: now)] + store.clips.filter { $0.text != text }).prefix(Self.limit))
    }

    /// The Clips still kept, newest first; expired ones are dropped for good.
    public func list(now: Date) -> [Clip] {
        let kept = store.clips.filter { now.timeIntervalSince($0.at) <= Self.keep }
        if kept.count != store.clips.count { store.clips = kept }
        return kept
    }

    public func clearAll() { store.clips = [] }
}
