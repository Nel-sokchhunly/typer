import Foundation

/// One Clip: the copied text and when the Keyboard first noticed it.
public struct Clip: Codable, Equatable {
    public let text: String
    public var at: Date
    /// When it was Pinned; nil for a recent Clip. Absent in files written before Pinned clips, which still load.
    public var pinnedAt: Date?
    public init(text: String, at: Date, pinnedAt: Date? = nil) { self.text = text; self.at = at; self.pinnedAt = pinnedAt }
    public var isPinned: Bool { pinnedAt != nil }

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

/// The Clipboard panel's list: text only; Pinned clips first (latest pinned first), then recent ones newest first.
/// Time is passed in so tests control it. Pinned clips never expire and sit outside the cap.
public final class ClipList {
    public static let limit = 10
    public static let maxLength = 5_000
    public static let keep: TimeInterval = 3_600

    private let store: ClipStore
    public init(store: ClipStore) { self.store = store }

    /// Blank text is ignored, long text is cut; a Clip with the same text moves to the top.
    /// Text equal to a Pinned clip adds nothing.
    public func add(_ text: String, now: Date) {
        guard !text.allSatisfy(\.isWhitespace) else { return }
        let text = String(text.prefix(Self.maxLength))
        let all = store.clips
        guard !all.contains(where: { $0.isPinned && $0.text == text }) else { return }
        let recent = all.filter { !$0.isPinned && $0.text != text }
        store.clips = all.filter(\.isPinned) + Array(([Clip(text: text, at: now)] + recent).prefix(Self.limit))
    }

    /// The Clips still kept: Pinned first, then recent ones; expired recent ones are dropped for good.
    public func list(now: Date) -> [Clip] {
        let all = store.clips
        let kept = all.filter { $0.isPinned || now.timeIntervalSince($0.at) <= Self.keep }
        if kept.count != all.count { store.clips = kept }
        return kept.filter(\.isPinned).sorted { $0.pinnedAt! > $1.pinnedAt! } + kept.filter { !$0.isPinned }
    }

    public func pin(_ text: String, now: Date) {
        store.clips = store.clips.map { $0.text == text && !$0.isPinned ? Clip(text: $0.text, at: $0.at, pinnedAt: now) : $0 }
    }

    /// Back among the recent Clips as if just noticed (at the top, a fresh hour); the cap applies again.
    public func unpin(_ text: String, now: Date) {
        let all = store.clips
        guard let c = all.first(where: { $0.isPinned && $0.text == text }) else { return }
        let recent = all.filter { !$0.isPinned }
        store.clips = all.filter { $0.isPinned && $0.text != text } + Array(([Clip(text: c.text, at: now)] + recent).prefix(Self.limit))
    }

    public func delete(_ text: String) { store.clips = store.clips.filter { $0.text != text } }

    /// Removes the recent Clips; Pinned clips stay.
    public func clearAll() { store.clips = store.clips.filter(\.isPinned) }
}
