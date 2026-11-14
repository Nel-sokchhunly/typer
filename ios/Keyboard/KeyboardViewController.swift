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
}

final class KeyboardViewController: UIInputViewController {
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
                onGlobe: { [unowned self] in advanceToNextInputMode() }))
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
        let height = view.heightAnchor.constraint(equalToConstant: 300)
        height.priority = UILayoutPriority(999)
        height.isActive = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.needsGlobe = needsInputModeSwitchKey
        traitsChanged()
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
        _ = composer.fieldTraitsChanged(secure: t.isSecureTextEntry ?? false, type: type)
    }

    /// If the Composer declined the key, do the normal thing.
    private func handle(_ consumed: Bool, else fallback: () -> Void = {}) {
        if !consumed { fallback() }
        refresh()
    }

    private func refresh() {
        model.typed = composer.typed
        model.suggestions = composer.suggestions
    }
}

private final class NoSuggestions: Suggester {
    func suggest(_ input: String, _ k: Int) -> [String] { [] }
    func pick(_ input: String, _ index: Int) {}
}
