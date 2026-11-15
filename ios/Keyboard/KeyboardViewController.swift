import SwiftUI
import UIKit
import os

/// UITextDocumentProxy as TyperCore's TextProxy. The system proxy is read live, so a re-set controller is fine.
final class ProxyAdapter: TextProxy {
    private let proxy: () -> UITextDocumentProxy
    init(_ proxy: @escaping () -> UITextDocumentProxy) { self.proxy = proxy }
    var documentContextBeforeInput: String? { proxy().documentContextBeforeInput }
    func setMarkedText(_ text: String) {
        proxy().setMarkedText(text, selectedRange: NSRange(location: (text as NSString).length, length: 0))
    }
    func unmarkText() { proxy().unmarkText() }
    func insertText(_ text: String) { proxy().insertText(text) }
    func deleteBackward() { proxy().deleteBackward() }
}

/// Composer state the SwiftUI view shows; bumped after every event.
final class KeyboardModel: ObservableObject {
    @Published var typed = ""
    @Published var suggestions: [String] = []
    /// English mode: the word before the caret, then up to two iOS completions or fixes for it; empty hides them.
    @Published var englishWords: [String] = []
    /// The all-Suggestions panel is open in place of the keys.
    @Published var showAll = false
    /// The Emoji panel is open in place of the keys; `emojiSections` is what it shows, fixed while open.
    @Published var showEmoji = false
    var emojiSections: [EmojiSection] = []
    var emojiTones: (String) -> [String] = { _ in [] }
    var emojiDisplay: (String) -> String = { $0 }
    var emojiSearch: (String) -> [String] = { _ in [] }
    /// Search mode: the Sing letter keys under a field and a results row. Keys edit `emojiQuery`, never the Host app.
    @Published var emojiSearching = false
    @Published var emojiQuery = ""
    /// Recents (as of opening) for an empty query, else the matches.
    var emojiResults: [String] {
        emojiQuery.trimmingCharacters(in: .whitespaces).isEmpty
            ? emojiSections.first { $0.title == "Recently Used" }?.emoji ?? [] : Array(emojiSearch(emojiQuery).prefix(50))
    }
    /// The Clipboard panel is open in place of the keys; `clips` is what it shows, fixed while open.
    @Published var showClipboard = false
    @Published var clips: [Clip] = []
    /// The Clipboard button may show: Full Access and not a password field (the bar still hides it while composing).
    var clipboardAllowed = false
    @Published var needsGlobe = false
    @Published var shift = Shift.off
    @Published var page = Page.letters
    @Published var mode = "ខ"  // the Composer's mode label
    @Published var layout = Composer.Layout.sing
    @Published var layoutForced = false  // password, email, number: Sing only
    @Published var canToggle = true
    @Published var returnLabel = "return"
    @Published var returnProminent = false
    var autoCap = AutoCap.Kind.sentences
    /// The user set shift by hand since the last key; auto-cap leaves it alone until a key is typed.
    var shiftChosen = false
    private var lastShiftTap = Date.distantPast
    private var slotShown = "កខគ", slotSince = Date.distantPast

    /// Keys currently held down, for the highlight and pop-up preview.
    @Published var pressed: [Key] = []
    /// The open long-press panel and its highlighted option.
    @Published var panel: LongPressPanel?
    @Published var panelSelected = 0

    enum Shift { case off, once, lock }
    typealias Page = KeyPage

    /// The one layout both the drawn keys and the touch layer use; empty while the all-Suggestions panel replaces the keys.
    func keys(width: CGFloat) -> [Key] {
        if emojiSearching { return searchKeys(width: width) }
        if showEmoji || showAll && !typed.isEmpty { return [] }
        let bar = !typed.isEmpty || !englishWords.isEmpty ? []
            : layout == .khmer ? KeyLayout.khmerPunctuation : mode == "EN" ? KeyLayout.englishPunctuation : KeyLayout.punctuation
        let all = KeyLayout.keys(width: width, page: page, upper: shift != .off, globe: needsGlobe, bar: bar,
                                 khmer: layout == .khmer, clipboard: clipboardAllowed)
        return showClipboard ? all.filter { $0.rect.minY < KeyLayout.rowsTop } : all  // the panel replaces the keys, the strip stays
    }

    /// English letters, lowercase, below the field and results row; the rows shrink so it all fits the panel's own height.
    /// No emoji or ខ/EN key, so space grows over their place.
    private func searchKeys(width: CGFloat) -> [Key] {
        let keys = KeyLayout.keys(width: width, page: .letters, upper: false, globe: false, bar: [])
        guard let page = keys.first(where: { $0.action == .page }) else { return [] }
        let top = KeyLayout.barTop + EmojiSearchBar.fieldHeight + 4 + EmojiSearchBar.resultsHeight + 4
        // normal-size keys at the bottom, as on the letters page; shorter only if the panel is too short for them
        let gap = KeyLayout.rowGap, keyHeight = min(KeyLayout.keyHeight, (height - 4 - top - 3 * gap) / 4)
        let keysTop = height - 4 - 4 * keyHeight - 3 * gap
        return keys.filter { $0.action != .emoji && $0.action != .mode }.map { k in
            let row = ((k.rect.minY - KeyLayout.rowsTop) / (KeyLayout.keyHeight + KeyLayout.rowGap)).rounded()
            var r = CGRect(x: k.rect.minX, y: keysTop + row * (keyHeight + gap), width: k.rect.width, height: keyHeight)
            if k.action == .space { r = CGRect(x: page.rect.maxX + KeyLayout.gap, y: r.minY, width: r.maxX - page.rect.maxX - KeyLayout.gap, height: r.height) }
            return Key(action: k.action, rect: r)
        }
    }

    /// The Khmer layout's letters take one row more; the Emoji panel (and its search) always has that height.
    var height: CGFloat { showEmoji || layout == .khmer && page == .letters ? KeyLayout.khmerHeight : KeyLayout.height }

    /// The bar's rightmost slot: abc keeps the Latin while composing; idle, it switches layouts.
    var slotLabel: String { typed.isEmpty && layout == .sing ? "កខគ" : "abc" }
    /// Taps on the slot count 0.3 s after its label last changed: a quick double tap on abc only keeps the Latin.
    var slotReady: Bool { Date().timeIntervalSince(slotSince) > 0.3 }
    func slotChecked() {
        if slotLabel != slotShown { slotShown = slotLabel; slotSince = Date() }
    }

    /// Shift once; a quick second tap locks caps; tapping a lock (or a lone shift) turns it off.
    func shiftTapped() {
        let now = Date()
        defer { lastShiftTap = now; shiftChosen = true }
        switch shift {
        case .lock: shift = .off
        case .once: shift = now.timeIntervalSince(lastShiftTap) < 0.4 ? .lock : .off
        case .off: shift = .once
        }
    }
}

/// The keyboard's root view; UIInputViewAudioFeedback is what lets playInputClick() make a sound.
private final class ClickInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
    override init(frame: CGRect, inputViewStyle: UIInputView.Style) {
        super.init(frame: frame, inputViewStyle: inputViewStyle)
        isMultipleTouchEnabled = true  // a second finger may land before the first lifts
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class KeyboardViewController: UIInputViewController {
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let model = KeyboardModel()
    private var lexicon: [String] = []  // iOS's extra words for keyboards: contact names, text replacements
    private var wordsAllowed = false  // English word suggestions: plain text fields that allow autocorrection
    private lazy var clipList: ClipList = {
        // the Keyboard's own sandbox, no App Group: nothing else can read it
        let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return ClipList(store: FileClipStore(url: (dir ?? FileManager.default.temporaryDirectory).appendingPathComponent("clips.json")))
    }()
    private var heightConstraint: NSLayoutConstraint!
    private lazy var composer: Composer = {
        let userDir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).path
        if userDir == nil { Logger(subsystem: "com.chhunly.typer.keyboard", category: "engine").error("no Application Support dir, Learning disabled") }
        let engine = Engine(dataDir: Bundle.main.resourcePath! + "/data", userDir: userDir)
        // load failure: an empty Suggester, the keyboard still types Latin
        let suggester: Suggester = engine.loaded ? engine : NoSuggestions()
        let c = Composer(engine: suggester, proxy: ProxyAdapter { [unowned self] in textDocumentProxy },
                         layout: UserDefaults.standard.string(forKey: "layout").flatMap(Composer.Layout.init) ?? .sing)
        c.onSuggestions = { [unowned self] in model.suggestions = composer.suggestions }  // results arrive after the key
        return c
    }()

    /// nil if the bundled data won't load: the emoji key then does nothing.
    private lazy var emojiCatalog: EmojiCatalog? = {
        let url = URL(fileURLWithPath: Bundle.main.resourcePath! + "/data/emoji.json")
        let max = EmojiCatalog.maxEmojiVersion(iOS: ProcessInfo.processInfo.operatingSystemVersion)
        return (try? Data(contentsOf: url)).flatMap { try? EmojiCatalog(data: $0, maxVersion: max, store: UserDefaultsEmojiStore(.standard)) }
    }()

    override func loadView() { view = ClickInputView(frame: .zero, inputViewStyle: .keyboard) }

    /// Key touch-down feedback. Both need Full Access; without it we stay silent.
    private func keyFeedback() {
        guard hasFullAccess else { return }
        haptic.impactOccurred()
        UIDevice.current.playInputClick()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let hosting = UIHostingController(
            rootView: KeyboardView(
                model: model,
                onCandidate: { [unowned self] in handle(composer.candidateTapped($0)) },
                onLatin: { [unowned self] in handle(composer.rawLatin()) },
                onEnglishWord: { [unowned self] in englishWordTapped($0) },
                onSlot: { [unowned self] in slotTapped() },
                onEmoji: { [unowned self] in emojiPicked($0) },
                onClip: { [unowned self] in clipPicked($0) },
                onClearClips: { [unowned self] in keyFeedback(); clipList.clearAll(); model.clips = clipList.list(now: Date()) },
                onPinClip: { [unowned self] c in
                    keyFeedback()
                    if c.isPinned { clipList.unpin(c.text, now: Date()) } else { clipList.pin(c.text, now: Date()) }
                    model.clips = clipList.list(now: Date())
                },
                onDeleteClip: { [unowned self] in keyFeedback(); clipList.delete($0.text); model.clips = clipList.list(now: Date()) },
                onHold: { [unowned self] in emojiHeld($0) },
                onSearch: { [unowned self] in keyFeedback(); model.emojiQuery = ""; model.emojiSearching = true },
                onGlobe: { [unowned self] in advanceToNextInputMode() },
                onLetters: { [unowned self] in keyFeedback(); model.showEmoji = false; model.page = .letters; refresh() },  // refresh: back to the layout's height
                onDelete: { [unowned self] in keyFeedback(); textDocumentProxy.deleteBackward() }))  // a grapheme, ZWJ emoji included
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear
        hosting.view.isMultipleTouchEnabled = true
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let layer = TouchLayer()
        layer.translatesAutoresizingMaskIntoConstraints = false
        layer.keys = { [unowned self] in model.keys(width: $0) }
        layer.press = { [unowned self] in keyFeedback() }
        layer.fire = { [unowned self] in fire($0) }
        layer.pressedChanged = { [unowned self] in if model.pressed != $0 { model.pressed = $0 } }
        layer.panelChanged = { [unowned self] in model.panel = $0; model.panelSelected = $1 }
        view.addSubview(layer)
        NSLayoutConstraint.activate([
            layer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            layer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            layer.topAnchor.constraint(equalTo: view.topAnchor),
            layer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        requestSupplementaryLexicon { [weak self] lex in self?.lexicon = lex.entries.map(\.documentText) }
        heightConstraint = view.heightAnchor.constraint(equalToConstant: model.height)
        heightConstraint.priority = UILayoutPriority(999)
        heightConstraint.isActive = true
    }

    /// Near the screen edges iOS holds a touch's start back while it checks for a system edge swipe: a tap still
    /// lands (start and end arrive together) but a long-press opened late. Keys want touches at once.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.window?.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.needsGlobe = needsInputModeSwitchKey
        if hasFullAccess { haptic.prepare() }
        traitsChanged()
        noticeCopy()
        refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        _ = composer.fieldEnded()
        model.showEmoji = false; model.emojiSearching = false; model.emojiQuery = ""  // reopens on the letters
        model.showClipboard = false
        refresh()  // also restores the height
    }

    override func textDidChange(_ textInput: UITextInput?) {
        traitsChanged()
        noticeCopy()
        _ = composer.textChanged()
        refresh()
    }

    private func traitsChanged() {
        let t = textDocumentProxy
        let type: FieldType
        switch t.keyboardType {
        case .emailAddress: type = .email
        case .numberPad, .decimalPad, .phonePad, .numbersAndPunctuation, .asciiCapableNumberPad: type = .number
        default: type = .text
        }
        model.autoCap = switch t.autocapitalizationType ?? .sentences {
        case .none: .none
        case .words: .words
        case .allCharacters: .allCharacters
        default: .sentences
        }
        let rt = t.returnKeyType ?? .default
        model.returnProminent = rt != .default
        model.returnLabel = switch rt {
        case .go: "go"
        case .google, .search, .yahoo: "search"
        case .join: "join"
        case .next: "next"
        case .route: "route"
        case .send: "send"
        case .done: "done"
        case .emergencyCall: "emergency"
        case .continue: "continue"
        default: "return"
        }
        _ = composer.fieldTraitsChanged(secure: t.isSecureTextEntry ?? false, type: type)
        model.clipboardAllowed = hasFullAccess && t.isSecureTextEntry != true
        wordsAllowed = type == .text && t.isSecureTextEntry != true && t.autocorrectionType != .no
    }

    /// A key fired by the touch layer.
    private func fire(_ action: KeyAction) {
        if model.emojiSearching { return searchKey(action) }
        if action != .clipboard { model.showClipboard = false }  // any other key closes the panel
        func type(_ c: String) { handle(composer.key(c), else: { textDocumentProxy.insertText(c) }) }
        switch action {
        case .char(let c), .punct(let c): type(c)
        case .space: type(" ")
        case .backspace: handle(composer.backspace(), else: { textDocumentProxy.deleteBackward() })
        case .returnKey: handle(composer.returnKey(), else: { textDocumentProxy.insertText("\n") })
        case .shift: model.shiftTapped()
        case .symbols: model.page = model.page == .numbers ? .symbols : .numbers
        case .page: model.page = model.page == .letters ? .numbers : .letters
        case .emoji: openEmoji()
        case .clipboard: toggleClipboard()
        case .globe: advanceToNextInputMode()
        case .mode: modeTapped()
        case .slot: slotTapped()
        }
        heightConstraint.constant = model.height
    }

    /// While searching, keys edit the query only; return and ABC go back to the grid.
    private func searchKey(_ action: KeyAction) {
        switch action {
        case .char(let c): model.emojiQuery += c
        case .space: model.emojiQuery += " "
        case .backspace: model.emojiQuery = String(model.emojiQuery.dropLast())
        case .returnKey, .page: model.emojiSearching = false
        default: break
        }
    }

    /// Commits the top Suggestion (no learning) and swaps the keys for the Emoji panel.
    private func openEmoji() {
        guard let catalog = emojiCatalog else { return }
        _ = composer.commitTop()
        model.emojiSections = catalog.sections
        model.emojiTones = { [unowned catalog] in catalog.tones(for: $0) }
        model.emojiDisplay = { [unowned catalog] in catalog.display($0) }
        model.emojiSearch = { [unowned catalog] in catalog.search($0) }
        model.showEmoji = true
        refresh(afterKey: true)
    }

    /// Opens the Clipboard panel (committing the top Suggestion first, no learning) or closes it back to where the user was.
    private func toggleClipboard() {
        if model.showClipboard { return refresh() }  // fire already closed it
        guard model.clipboardAllowed else { return }
        _ = composer.commitTop()
        noticeCopy()
        model.clips = clipList.list(now: Date())
        model.showClipboard = true
        refresh(afterKey: true)
    }

    /// A Clip's text goes into the field as typed (never through the Composer) and the panel closes.
    private func clipPicked(_ text: String) {
        keyFeedback()
        textDocumentProxy.insertText(text)
        model.showClipboard = false
        refresh(afterKey: true)
    }

    /// The one place that decides when the Keyboard looks at the pasteboard: when it appears and on text input, if the
    /// copy count changed. Reading text may trigger iOS's "Allow Paste" alert (#144); if so, read only on the user's tap
    /// by changing just this function and its callers.
    private func noticeCopy() {
        guard hasFullAccess else { return }
        let board = UIPasteboard.general
        let count = board.changeCount
        guard count != UserDefaults.standard.integer(forKey: "clip.changeCount") else { return }  // the process may be new
        UserDefaults.standard.set(count, forKey: "clip.changeCount")
        let hidden: Set = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"]  // password managers
        guard board.hasStrings, textDocumentProxy.isSecureTextEntry != true, hidden.isDisjoint(with: board.types),
              let text = board.string else { return }
        clipList.add(text, now: Date())
    }

    /// An emoji's skin tones in the keyboard's long-press panel, as on a Khmer key: the highlighted one goes in on release.
    private func emojiHeld(_ h: EmojiHold) {
        switch h {
        case .began(let options, let current, let cell):
            let p = LongPressPanel(options: options, above: view.convert(cell, from: nil), width: view.bounds.width)
            model.panel = p
            model.panelSelected = options.firstIndex(of: current) ?? 0
            keyFeedback()
        case .moved(let at):
            if let p = model.panel { model.panelSelected = p.index(at: view.convert(at, from: nil).x) }
        case .ended:
            if let p = model.panel, p.options.indices.contains(model.panelSelected) { emojiPicked(p.options[model.panelSelected]) }
            model.panel = nil
        case .cancelled:
            model.panel = nil
        }
    }

    private func emojiPicked(_ e: String) {
        keyFeedback()
        handle(composer.key(e), else: { textDocumentProxy.insertText(e) })
        emojiCatalog?.pick(e)
    }

    /// While a Phrase is open the slot keeps the Latin; idle, it switches layouts and shows the letters.
    private func slotTapped() {
        guard model.slotReady else { return }
        if composer.isComposing { return handle(composer.rawLatin()) }
        if composer.switchLayout() {
            UserDefaults.standard.set(composer.chosen.rawValue, forKey: "layout")
            model.page = .letters; model.shift = .off
        }
        refresh(afterKey: true)
    }

    /// Switching mode never turns shift on: the keys stay as they are until the next letter.
    private func modeTapped() {
        _ = composer.toggleMode()
        if model.shift == .once { model.shift = .off }
        model.shiftChosen = true
        refresh()
    }

    /// If the Composer declined the key, do the normal thing.
    private func handle(_ consumed: Bool, else fallback: () -> Void = {}) {
        if !consumed { fallback() }
        refresh(afterKey: true)
    }

    private func refresh(afterKey: Bool = false) {
        let english = composer.layout == .sing && composer.mode == "EN"
        let before = english ? textDocumentProxy.documentContextBeforeInput : nil  // only English needs it: skip the IPC read
        model.englishWords = english && wordsAllowed ? Self.englishWords(before: before, lexicon: lexicon) : []
        model.typed = composer.typed
        model.suggestions = composer.suggestions
        if composer.typed.isEmpty { model.showAll = false }
        if !model.clipboardAllowed || !composer.typed.isEmpty || !model.englishWords.isEmpty { model.showClipboard = false }
        model.mode = composer.mode
        model.layout = composer.layout
        model.layoutForced = composer.layoutForced
        model.canToggle = composer.canToggle
        if afterKey { model.shiftChosen = false }
        if model.shift != .lock && !model.shiftChosen {  // a typed key or a field change re-decides shift, like Apple's
            model.shift = composer.layout == .sing  // no auto-cap on the Khmer layout
                && AutoCap.shouldShift(before: before, kind: model.autoCap, khmerMode: !english) ? .once : .off
        }
        model.slotChecked()
        heightConstraint.constant = model.height
    }
}

extension KeyboardViewController {
    /// The word you were typing becomes the tapped one, then a space; index 0 keeps it as typed.
    fileprivate func englishWordTapped(_ i: Int) {
        let words = model.englishWords
        guard i < words.count else { return }
        if i > 0 {
            for _ in words[0] { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(words[i])
        }
        textDocumentProxy.insertText(" ")
        refresh(afterKey: true)
    }

    private static let checker = UITextChecker()

    /// [typed, best, second] from iOS's English dictionary (and your contacts and text replacements), or [] if no help.
    /// Completions, most likely first; a spelling fix only when nothing completes the word.
    static func englishWords(before: String?, lexicon: [String]) -> [String] {
        guard let before else { return [] }
        let word = String(before.reversed().prefix { $0.isLetter || $0 == "'" }.reversed())
        guard !word.isEmpty, word != "'" else { return [] }
        let range = NSRange(location: 0, length: (word as NSString).length)
        let lower = word.lowercased()
        var found = lexicon.filter { $0.count > word.count && $0.lowercased().hasPrefix(lower) }.prefix(1).map { $0 }
        found += checker.completions(forPartialWordRange: range, in: word, language: "en_US") ?? []
        // a half-typed word looks misspelled ("hel"), so spelling fixes only when nothing completes it ("teh" -> the)
        if found.isEmpty,
           checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: "en_US").location != NSNotFound {
            found += checker.guesses(forWordRange: range, in: word, language: "en_US") ?? []
        }
        var seen: Set<String> = [lower]
        let capital = word.first?.isUppercase == true
        let picks = found.compactMap { w -> String? in
            let w = capital ? w.prefix(1).uppercased() + w.dropFirst() : w
            return seen.insert(w.lowercased()).inserted ? w : nil
        }.prefix(2)
        return picks.isEmpty ? [] : [word] + picks
    }
}

private final class NoSuggestions: Suggester {
    func suggest(_ input: String, _ k: Int) -> [String] { [] }
    func pick(_ input: String, _ index: Int) {}
}
