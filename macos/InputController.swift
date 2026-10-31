import Cocoa
import InputMethodKit

/// Letters and spaces build an underlined latin phrase; the panel shows Khmer suggestions.
/// Enter / 1-9 / click: insert suggestion (and learn it). Esc: insert the latin as typed.
/// Delete: edit the phrase. Punctuation or shortcuts: insert top suggestion, then pass the key on.
@objc(TyperInputController)
class TyperInputController: IMKInputController {
    private var buffer = ""
    private var suggestions: [String] = []
    private let noRange = NSRange(location: NSNotFound, length: NSNotFound)

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown, let client = sender as? IMKTextInput else { return false }
        let composing = !buffer.isEmpty

        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if composing { commit(0, client) }
            return false
        }
        switch event.keyCode {
        case 36, 76:  // return, keypad enter
            guard composing else { return false }
            commit(0, client)
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
        if composing { commit(0, client) }
        return false
    }

    private func update(_ client: IMKTextInput) {
        client.setMarkedText(
            buffer, selectionRange: NSRange(location: buffer.utf16.count, length: 0), replacementRange: noRange)
        suggestions = buffer.trimmingCharacters(in: .whitespaces).isEmpty ? [] : Typer.suggest(buffer)
        if suggestions.isEmpty {
            candidatesPanel.hide()
        } else {
            candidatesPanel.update()
            candidatesPanel.show(kIMKLocateCandidatesBelowHint)
        }
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
        candidatesPanel.hide()
    }

    override func candidates(_ sender: Any!) -> [Any]! {
        suggestions
    }

    override func candidateSelected(_ candidateString: NSAttributedString!) {
        guard let client = client(), let i = suggestions.firstIndex(of: candidateString.string) else { return }
        commit(i, client)
    }

    /// Focus moved away mid-phrase: keep what was typed, don't guess.
    override func commitComposition(_ sender: Any!) {
        guard !buffer.isEmpty, let client = sender as? IMKTextInput else { return }
        insert(buffer, client)
    }

    override func deactivateServer(_ sender: Any!) {
        commitComposition(sender)
        candidatesPanel.hide()
    }
}
