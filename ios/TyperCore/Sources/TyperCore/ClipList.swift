import Foundation

/// One Clip: the copied text and when the Keyboard first noticed it.
public struct Clip: Codable, Equatable {
    public let text: String
    public var at: Date
    /// When it was Pinned; nil for a recent Clip. Absent in files written before Pinned clips, which still load.
    public var pinnedAt: Date?
    /// When it was pasted as the Fresh clip or from the panel; nil if not yet. Stored so a new process does not offer it again.
    public var usedAt: Date?
    public init(text: String, at: Date, pinnedAt: Date? = nil, usedAt: Date? = nil) {
        self.text = text; self.at = at; self.pinnedAt = pinnedAt; self.usedAt = usedAt
    }
    public var isPinned: Bool { pinnedAt != nil }

    /// How the Clipboard panel shows it: whitespace collapsed to single spaces (one line; the view adds the ellipsis).
    public var line: String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
}

/// Where the Clips live: on the phone only, in the Keyboard's own storage.
public protocol ClipStore: AnyObject {
    var clips: [Clip] { get set }
    /// Deletes everything stored, whatever it holds.
    func wipe()
}

public final class InMemoryClipStore: ClipStore {
    public var clips: [Clip] = []
    public init() {}
    public func wipe() { clips = [] }
}

/// A small JSON file, written with complete file protection: unreadable while the phone is locked (then it reads as empty).
public final class FileClipStore: ClipStore {
    private let url: URL
    public init(url: URL) { self.url = url }
    public func wipe() { try? FileManager.default.removeItem(at: url) }
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
    public static let freshFor: TimeInterval = 60

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

    /// The newest recent Clip, if first noticed under a minute ago and not pasted yet. A Pinned clip is never fresh.
    public func fresh(now: Date) -> Clip? {
        guard let c = store.clips.first(where: { !$0.isPinned }), c.usedAt == nil, now.timeIntervalSince(c.at) < Self.freshFor else { return nil }
        return c
    }

    /// The Clip was pasted (from the strip or the panel): it is no longer fresh.
    public func markUsed(_ text: String, now: Date) {
        store.clips = store.clips.map { $0.text == text && $0.usedAt == nil ? Clip(text: $0.text, at: $0.at, pinnedAt: $0.pinnedAt, usedAt: now) : $0 }
    }

    public func pin(_ text: String, now: Date) {
        store.clips = store.clips.map { $0.text == text && !$0.isPinned ? Clip(text: $0.text, at: $0.at, pinnedAt: now, usedAt: $0.usedAt) : $0 }
    }

    /// Back among the recent Clips at the top (below the Fresh clip, if any) with a fresh hour; the cap applies again. Never a Fresh clip itself: it is not a new copy.
    public func unpin(_ text: String, now: Date) {
        let all = store.clips
        guard let c = all.first(where: { $0.isPinned && $0.text == text }) else { return }
        let fresh = fresh(now: now)  // stays the Fresh clip: the unpinned one goes just below it
        var recent = all.filter { !$0.isPinned }
        recent.insert(Clip(text: c.text, at: now, usedAt: now), at: fresh == nil ? 0 : 1)
        store.clips = all.filter { $0.isPinned && $0.text != text } + Array(recent.prefix(Self.limit))
    }

    public func delete(_ text: String) { store.clips = store.clips.filter { $0.text != text } }

    /// Removes the recent Clips; Pinned clips stay.
    public func clearAll() { store.clips = store.clips.filter(\.isPinned) }


    /// Turning clipboard history off: delete the whole store, so nothing stays behind.
    public func wipe() { store.wipe() }
}

/// The clipboard history switch, set in the Companion app and read by the Keyboard through the shared container
/// (settings only). On unless it was turned off.
public enum ClipSettings {
    public static let group = "group.com.chhunly.typer"
    public static let key = "clipboardHistory"
    public static func isOn(_ defaults: UserDefaults?) -> Bool { defaults?.object(forKey: key) as? Bool ?? true }
}
