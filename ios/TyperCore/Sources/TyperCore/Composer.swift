import Foundation

/// The keyboard's link to the host app. The real one wraps UITextDocumentProxy.
public protocol TextProxy: AnyObject {
    /// Text before the caret, as the host reports it (may or may not include marked text; may be nil).
    var documentContextBeforeInput: String? { get }
    /// Replace the marked text (or insert at the caret) with `text`, marked, caret at its end. "" clears it.
    func setMarkedText(_ text: String)
    /// Keep the marked text as plain text.
    func unmarkText()
    func insertText(_ text: String)
    func deleteBackward()
}

/// Where engine work runs. The Rust engine is not thread-safe: every engine call goes through `async`/`sync`,
/// which must be one serial queue. `main` hops back to the main thread. Tests inject `.immediate`.
public struct Scheduler {
    public var async: (@escaping () -> Void) -> Void
    public var sync: (() -> Void) -> Void
    public var main: (@escaping () -> Void) -> Void

    public init(async: @escaping (@escaping () -> Void) -> Void, sync: @escaping (() -> Void) -> Void,
                main: @escaping (@escaping () -> Void) -> Void) {
        self.async = async
        self.sync = sync
        self.main = main
    }

    public static let immediate = Scheduler(async: { $0() }, sync: { $0() }, main: { $0() })

    public static func background() -> Scheduler {
        let q = DispatchQueue(label: "typer.engine", qos: .userInteractive)
        return Scheduler(async: { q.async(execute: $0) }, sync: { q.sync(execute: $0) },
                         main: { DispatchQueue.main.async(execute: $0) })
    }
}

/// How a field wants its keys. Everything but `.text` passes straight through, like English mode.
public enum FieldType { case text, email, url, number }

/// Sing Khmer typing rules from the macOS input method (macos/InputController.swift), adapted to touch.
/// Letters, `'`, spaces and ASCII punctuation build a Latin phrase shown as marked text; `suggestions`
/// are its Khmer conversions. Every event returns whether it consumed the key; if not, the keyboard
/// does its normal thing with it.
public final class Composer {
    private static var english = false  // shared by every keyboard instance while the process lives, like macOS

    public private(set) var suggestions: [String] = []
    /// The phrase as typed, for the candidate bar's Latin chip.
    public private(set) var typed = ""
    public var isComposing: Bool { !typed.isEmpty }
    /// "ខ" or "EN"; a secure, email or number field shows EN, and a URL field starts EN.
    public var mode: String { passthrough ? "EN" : "ខ" }

    /// Called on the main thread when new suggestions arrive after a key (they are computed off-thread).
    public var onSuggestions: (() -> Void)?

    private let engine: Suggester
    private let scheduler: Scheduler
    private var suggestionsFor = ""  // the Phrase `suggestions` were computed for
    private var requestSeq = 0  // main thread: bumped on every Phrase change
    private let latest = LockedInt()  // same value, readable from the engine queue to skip stale work
    private let proxy: TextProxy
    private let usesMarkedText: Bool
    private var secure = false
    private var field = FieldType.text
    private var urlKhmer = false  // ខ tapped in this URL field (a search in Khmer); the global mode stays as it was
    private var anchor: String?  // marked text: the context before the caret when the phrase began
    private var shown = ""  // without marked text: the phrase as plain text in the document (ASCII)

    /// `usesMarkedText: false` is the fallback for hosts that mishandle marked text: the phrase is
    /// typed as plain text, and a commit deletes its length and inserts the choice.
    public init(engine: Suggester, proxy: TextProxy, usesMarkedText: Bool = true,
                scheduler: Scheduler = .background()) {
        self.engine = engine
        self.scheduler = scheduler
        self.proxy = proxy
        self.usesMarkedText = usesMarkedText
    }

    private var passthrough: Bool {
        switch field {
        case .text: Self.english || secure
        case .url: !urlKhmer || secure
        case .email, .number: true
        }
    }

    /// Passthrough is on (EN, a secure/email/number field, or a URL field left in EN). If it came on mid-phrase
    /// (EN toggled in another keyboard instance), keep the phrase as typed.
    private func passingThrough() -> Bool {
        guard passthrough else { return false }
        _ = keepLatin()
        return true
    }

    /// A typed character: letter, `'`, space, punctuation, digit, emoji, ...
    public func key(_ text: String) -> Bool {
        if passingThrough() { return false }
        guard text.count == 1, let c = text.first else { return otherKey() }
        let starting = !isComposing
        if c.isASCII && (c.isLetter || c == "'") {
            typed.append(c)
        } else if c == " " && isComposing {
            if !typed.hasSuffix(" ") { typed.append(" ") }  // space separates words, never commits
        } else if isComposing && c.isASCII && (c.isPunctuation || c.isSymbol || c.isNumber) {
            typed.append(c)  // stays as typed in the suggestion: "knhom," -> ខ្ញុំ, and "mean 3 nak" -> មាន 3 នាក់
        } else {
            return otherKey()
        }
        if starting { anchor = proxy.documentContextBeforeInput }
        update()
        return true
    }

    /// Emoji, non-ASCII, ...: insert the top suggestion, then let the key through.
    private func otherKey() -> Bool {
        if isComposing { commit(0) }
        return false
    }

    public func backspace() -> Bool {
        guard !passingThrough(), isComposing else { return false }
        typed.removeLast()
        update()
        return true
    }

    public func returnKey() -> Bool {
        guard !passingThrough(), isComposing else { return false }
        commit(0)
        return true
    }

    public func candidateTapped(_ index: Int) -> Bool {
        guard !passingThrough(), isComposing else { return false }
        commit(index)
        return true
    }

    /// The Latin chip: insert the phrase exactly as typed, learn nothing.
    public func rawLatin() -> Bool {
        guard !passingThrough(), isComposing else { return false }
        _ = write(typed, final: true)
        return true
    }

    /// Whether the ខ/EN key does anything right now; the keyboard dims it otherwise.
    public var canToggle: Bool { !isComposing && !secure && (field == .text || field == .url) }

    /// Khmer <-> English. Ignored mid-phrase (a stray tap) and in fields that are English anyway.
    /// In a URL field it switches only that field, so typing a search in Khmer leaves the global mode alone.
    public func toggleMode() -> Bool {
        guard canToggle else { return false }
        if field == .url { urlKhmer.toggle() } else { Self.english.toggle() }
        return true
    }

    /// textDidChange / selectionDidChange, including the echoes of the Composer's own writes.
    /// Mid-phrase, if the caret no longer sits right after the phrase, keep the phrase as typed.
    public func textChanged() -> Bool {
        guard isComposing, !stillAfterPhrase() else { return false }
        return keepLatin()
    }

    /// Whether the text before the caret is what the Composer left there. A nil context counts as
    /// yes: some hosts never report it, and a false "moved" would end every phrase after one letter.
    private func stillAfterPhrase() -> Bool {
        guard let before = proxy.documentContextBeforeInput else { return true }
        if !usesMarkedText { return before.hasSuffix(shown) }
        return before.hasSuffix(typed) || before == anchor  // iOS may or may not count marked text
    }

    /// Focus left the field or the keyboard was dismissed: keep the phrase as typed.
    public func fieldEnded() -> Bool { keepLatin() }

    /// A new field, or its traits changed (iOS re-reports unchanged traits; those are ignored).
    public func fieldTraitsChanged(secure: Bool, type: FieldType) -> Bool {
        guard secure != self.secure || type != field else { return false }
        let kept = keepLatin()
        self.secure = secure
        field = type
        urlKhmer = false
        return kept
    }

    /// Marked text updates now; suggestions follow from the engine queue, the latest request wins.
    /// Until they land, the previous ones stay on the bar.
    private func update() {
        invalidate()
        if !typed.isEmpty {
            let input = typed, seq = requestSeq, latest = latest, engine = engine, scheduler = scheduler
            scheduler.async { [weak self] in
                guard latest.value == seq else { return }  // a newer key already superseded this one
                let result = engine.suggest(input, 9)
                scheduler.main {
                    guard let self, self.requestSeq == seq else { return }
                    self.suggestions = result
                    self.suggestionsFor = input
                    self.onSuggestions?()
                }
            }
        }
        _ = write(typed, final: typed.isEmpty)
    }

    private func invalidate() {
        requestSeq += 1
        latest.value = requestSeq
    }

    /// A Pick must come from the current Phrase: if its result hasn't landed, compute it now.
    private func commit(_ index: Int) {
        let input = typed
        if suggestionsFor != input {
            scheduler.sync { suggestions = engine.suggest(input, 9) }
            suggestionsFor = input
        }
        guard suggestions.indices.contains(index) else {
            _ = write(input, final: true)
            return
        }
        if write(suggestions[index], final: true) {
            let engine = engine
            scheduler.async { engine.pick(input, index) }
        }
    }

    /// Leave the phrase in the document as it stands (Latin), no learning.
    private func keepLatin() -> Bool {
        guard isComposing else { return false }
        if usesMarkedText { proxy.unmarkText() }
        reset()
        return true
    }

    /// Show `text` as the phrase; `final` ends the phrase with `text` in the document.
    /// False if the fallback found the caret moved and kept the Latin instead.
    private func write(_ text: String, final: Bool) -> Bool {
        if usesMarkedText {
            proxy.setMarkedText(text)
        } else {
            let same = zip(shown, text).prefix { $0 == $1 }.count
            let deletes = shown.count - same  // shown is ASCII: one deleteBackward per character
            if deletes > 0 && proxy.documentContextBeforeInput?.hasSuffix(shown) != true {
                _ = keepLatin()  // don't delete blind: that could eat the user's text
                return false
            }
            for _ in 0..<deletes { proxy.deleteBackward() }
            let rest = text.dropFirst(same)
            if !rest.isEmpty { proxy.insertText(String(rest)) }
            shown = text
        }
        if final {
            if usesMarkedText { proxy.unmarkText() }
            reset()
        }
        return true
    }

    private func reset() {
        typed = ""
        shown = ""
        anchor = nil
        suggestions = []
        suggestionsFor = ""
        invalidate()
    }
}

private final class LockedInt {
    private let lock = NSLock()
    private var v = 0
    var value: Int {
        get { lock.lock(); defer { lock.unlock() }; return v }
        set { lock.lock(); v = newValue; lock.unlock() }
    }
}
