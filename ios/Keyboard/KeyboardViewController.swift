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
    /// The all-Suggestions panel is open in place of the keys.
    @Published var showAll = false
    @Published var needsGlobe = false
    @Published var shift = Shift.off
    @Published var page = Page.letters
    @Published var mode = "ខ"  // the Composer's mode label
    @Published var canToggle = true
    @Published var returnLabel = "return"
    @Published var returnProminent = false
    var autoCap = AutoCap.Kind.sentences
    /// The user set shift by hand since the last key; auto-cap leaves it alone until a key is typed.
    var shiftChosen = false
    private var lastShiftTap = Date.distantPast

    /// Keys currently held down, for the highlight and pop-up preview.
    @Published var pressed: [Key] = []

    enum Shift { case off, once, lock }
    typealias Page = KeyPage

    /// The one layout both the drawn keys and the touch layer use; empty while the all-Suggestions panel replaces the keys.
    func keys(width: CGFloat) -> [Key] {
        if showAll && !typed.isEmpty { return [] }
        return KeyLayout.keys(width: width, page: page, upper: shift != .off, globe: needsGlobe, bar: !typed.isEmpty ? [] : mode == "EN" ? KeyLayout.englishPunctuation : KeyLayout.punctuation)
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
    private lazy var composer: Composer = {
        let userDir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).path
        if userDir == nil { Logger(subsystem: "com.chhunly.typer.keyboard", category: "engine").error("no Application Support dir, Learning disabled") }
        let engine = Engine(dataDir: Bundle.main.resourcePath! + "/data", userDir: userDir)
        // load failure: an empty Suggester, the keyboard still types Latin
        let suggester: Suggester = engine.loaded ? engine : NoSuggestions()
        let c = Composer(engine: suggester, proxy: ProxyAdapter { [unowned self] in textDocumentProxy })
        c.onSuggestions = { [unowned self] in model.suggestions = composer.suggestions }  // results arrive after the key
        return c
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
                onLatin: { [unowned self] in handle(composer.rawLatin()) }))
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
        view.addSubview(layer)
        NSLayoutConstraint.activate([
            layer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            layer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            layer.topAnchor.constraint(equalTo: view.topAnchor),
            layer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let height = view.heightAnchor.constraint(equalToConstant: KeyboardView.height)
        height.priority = UILayoutPriority(999)
        height.isActive = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.needsGlobe = needsInputModeSwitchKey
        if hasFullAccess { haptic.prepare() }
        traitsChanged()
        refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        _ = composer.fieldEnded()
        refresh()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        traitsChanged()
        _ = composer.textChanged()
        refresh()
    }

    private func traitsChanged() {
        let t = textDocumentProxy
        let type: FieldType
        switch t.keyboardType {
        case .emailAddress: type = .email
        case .URL, .webSearch: type = .url
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
    }

    /// A key fired by the touch layer.
    private func fire(_ action: KeyAction) {
        func type(_ c: String) { handle(composer.key(c), else: { textDocumentProxy.insertText(c) }) }
        switch action {
        case .char(let c), .punct(let c): type(c)
        case .space: type(" ")
        case .backspace: handle(composer.backspace(), else: { textDocumentProxy.deleteBackward() })
        case .returnKey: handle(composer.returnKey(), else: { textDocumentProxy.insertText("\n") })
        case .shift: model.shiftTapped()
        case .symbols: model.page = model.page == .numbers ? .symbols : .numbers
        case .page: model.page = model.page == .letters ? .numbers : .letters
        case .globe: advanceToNextInputMode()
        case .mode: modeTapped()
        }
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
        model.typed = composer.typed
        model.suggestions = composer.suggestions
        if composer.typed.isEmpty { model.showAll = false }
        model.mode = composer.mode
        model.canToggle = composer.canToggle
        if afterKey { model.shiftChosen = false }
        if model.shift != .lock && !model.shiftChosen {  // a typed key or a field change re-decides shift, like Apple's
            let khmer = composer.mode == "ខ"
            let before = khmer ? nil : textDocumentProxy.documentContextBeforeInput  // Khmer never auto-caps: skip the IPC read
            model.shift = AutoCap.shouldShift(before: before, kind: model.autoCap, khmerMode: khmer) ? .once : .off
        }
    }
}

private final class NoSuggestions: Suggester {
    func suggest(_ input: String, _ k: Int) -> [String] { [] }
    func pick(_ input: String, _ index: Int) {}
}
