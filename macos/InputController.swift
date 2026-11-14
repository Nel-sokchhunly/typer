import Cocoa
import InputMethodKit

/// Letters and spaces build an underlined latin phrase; the panel shows Khmer suggestions.
/// ↓/↑ or Tab/Shift-Tab: move highlight. Enter: insert highlighted. 1-9 / click: insert that one.
/// Inserted suggestions are learned. Esc: insert the latin as typed.
/// Delete: edit the phrase. Punctuation joins the phrase as typed. Shortcuts: insert top suggestion, then pass the key on.
/// Tap Ctrl alone with nothing typed: toggle English passthrough (keys go straight to the app).
@objc(TyperInputController)
class TyperInputController: IMKInputController {
    private static var english = false  // shared by all apps, like the system Caps Lock
    private var ctrlAlone = false  // Ctrl pressed with no other key since
    private var buffer = ""
    private var suggestions: [String] = []
    private var selected = 0  // highlighted row; Enter inserts it
    private let noRange = NSRange(location: NSNotFound, length: NSNotFound)

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged]).rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let client = sender as? IMKTextInput else { return false }
        if event.type == .flagsChanged {
            let ctrlKey = event.keyCode == 59 || event.keyCode == 62
            let others = !event.modifierFlags.intersection([.command, .shift, .option]).isEmpty
            if !ctrlKey || others {
                ctrlAlone = false
            } else if event.modifierFlags.contains(.control) {
                ctrlAlone = true
            } else if ctrlAlone {
                ctrlAlone = false
                toggleEnglish(client)
            }
            return false
        }
        guard event.type == .keyDown else { return false }
        defer { refreshBadge(client) }  // not on modifiers: they don't move the caret, and would cut the toggle flash
        ctrlAlone = false  // Ctrl+key is a shortcut, not a toggle
        if Self.english { return false }
        let composing = !buffer.isEmpty

        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if composing { commit(0, client) }
            return false
        }
        switch event.keyCode {
        case 36, 76:  // return, keypad enter
            guard composing else { return false }
            commit(selected, client)
            return true
        case 125, 126:  // down, up
            guard composing, !suggestions.isEmpty else { return false }
            selected = (selected + (event.keyCode == 126 ? -1 : 1) + suggestions.count) % suggestions.count
            showPanel(client)
            return true
        case 48 where composing && !suggestions.isEmpty:  // tab, shift-tab; without suggestions it's an ordinary key
            selected = (selected + (event.modifierFlags.contains(.shift) ? -1 : 1) + suggestions.count) % suggestions.count
            showPanel(client)
            return true
        case 53:  // escape
            guard composing else { return false }
            insert(buffer, client)
            return true
        case 51:  // delete
            guard composing else { return false }
            buffer.removeLast()
            update(client)
            return true
        default:
            break
        }

        guard let chars = event.characters, chars.count == 1, let c = chars.first else { return false }
        if c.isASCII && (c.isLetter || c == "'") {
            buffer.append(c)
            update(client)
            return true
        }
        if c == " " && composing {
            if !buffer.hasSuffix(" ") { buffer.append(" ") }  // space separates words, never commits
            update(client)
            return true
        }
        if composing, let d = c.wholeNumberValue, (1...suggestions.count).contains(d) {
            commit(d - 1, client)
            return true
        }
        if composing && c.isASCII && (c.isPunctuation || c.isSymbol) {
            buffer.append(c)  // stays as typed in the suggestion: "knhom," -> ខ្ញុំ,
            update(client)
            return true
        }
        if composing { commit(0, client) }
        return false
    }

    private func toggleEnglish(_ client: IMKTextInput) {
        guard buffer.isEmpty else { return }  // mid-phrase: a stray tap, not a command
        Self.english.toggle()
        ModeBadge.show(mode, near: client)
    }

    private var mode: String { Self.english ? "EN" : "ខ" }

    /// Faint badge under the caret, except while the suggestion list has that spot.
    private func refreshBadge(_ client: IMKTextInput) {
        if buffer.isEmpty { ModeBadge.follow(mode, near: client) } else { ModeBadge.hide() }
    }

    private func update(_ client: IMKTextInput) {
        client.setMarkedText(
            buffer, selectionRange: NSRange(location: buffer.utf16.count, length: 0), replacementRange: noRange)
        suggestions = buffer.trimmingCharacters(in: .whitespaces).isEmpty ? [] : Typer.suggest(buffer)
        selected = 0
        showPanel(client)
    }

    private func showPanel(_ client: IMKTextInput) {
        guard !suggestions.isEmpty else { return CandidatePanel.shared.hide() }
        CandidatePanel.shared.onPick = { [weak self] i in
            guard let self, let client = self.client() else { return }
            self.commit(i, client)
        }
        CandidatePanel.shared.show(suggestions, selected: selected, caret: caretRect(client))
    }

    private func commit(_ index: Int, _ client: IMKTextInput) {
        guard index < suggestions.count else { return insert(buffer, client) }
        let input = buffer
        insert(suggestions[index], client)
        Typer.pick(input, index)
    }

    private func insert(_ text: String, _ client: IMKTextInput) {
        client.insertText(text, replacementRange: noRange)
        buffer = ""
        suggestions = []
        CandidatePanel.shared.hide()
    }

    /// Focus moved away mid-phrase: keep what was typed, don't guess.
    override func commitComposition(_ sender: Any!) {
        guard !buffer.isEmpty, let client = sender as? IMKTextInput else { return }
        insert(buffer, client)
    }

    /// Typer's entries in the input menu (menu bar): open the bundled Typer Settings app.
    override func menu() -> NSMenu! {
        let m = NSMenu()
        for (title, action) in [("Typer Settings…", #selector(openSettings(_:))), ("Typer Tutorial…", #selector(openTutorial(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            m.addItem(item)
        }
        return m
    }

    @objc private func openSettings(_ sender: Any?) { openSettingsApp([]) }
    // ponytail: if Settings is already open this just brings it forward; its Tutorial tab is one click away.
    @objc private func openTutorial(_ sender: Any?) { openSettingsApp(["--tutorial"]) }

    private func openSettingsApp(_ args: [String]) {
        let app = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Typer Settings.app")
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = args
        NSWorkspace.shared.openApplication(at: app, configuration: config)
    }

    override func activateServer(_ sender: Any!) {
        ctrlAlone = false  // Ctrl+Space switched input source: its Ctrl release is not a tap
        if let client = sender as? IMKTextInput { ModeBadge.follow(mode, near: client) }
    }

    override func deactivateServer(_ sender: Any!) {
        ctrlAlone = false
        commitComposition(sender)
        CandidatePanel.shared.hide()
        ModeBadge.hide()
    }
}
