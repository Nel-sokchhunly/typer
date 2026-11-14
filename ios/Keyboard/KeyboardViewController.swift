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

    enum Shift { case off, once, lock }
    enum Page: Int { case letters, numbers, symbols }

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
        return Composer(engine: suggester, proxy: ProxyAdapter { [unowned self] in textDocumentProxy })
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
                onKey: { [unowned self] c in handle(composer.key(c), else: { textDocumentProxy.insertText(c) }) },
                onBackspace: { [unowned self] in handle(composer.backspace(), else: { textDocumentProxy.deleteBackward() }) },
                onReturn: { [unowned self] in handle(composer.returnKey(), else: { textDocumentProxy.insertText("\n") }) },
                onCandidate: { [unowned self] in handle(composer.candidateTapped($0)) },
                onLatin: { [unowned self] in handle(composer.rawLatin()) },
                onGlobe: { [unowned self] in advanceToNextInputMode() },
                onMode: { [unowned self] in modeTapped() })
                .environment(\.keyPress, { [unowned self] in keyFeedback() }))
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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
        model.mode = composer.mode
        model.canToggle = composer.canToggle
        if afterKey { model.shiftChosen = false }
        if model.shift != .lock && !model.shiftChosen {  // a typed key or a field change re-decides shift, like Apple's
            let before = textDocumentProxy.documentContextBeforeInput
            model.shift = AutoCap.shouldShift(before: before, kind: model.autoCap, khmerMode: composer.mode == "ខ") ? .once : .off
        }
    }
}

private final class NoSuggestions: Suggester {
    func suggest(_ input: String, _ k: Int) -> [String] { [] }
    func pick(_ input: String, _ index: Int) {}
}
