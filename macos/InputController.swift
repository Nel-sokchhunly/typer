import Cocoa
import InputMethodKit

/// Letters and spaces build an underlined latin phrase; the panel shows Khmer suggestions.
/// ↓/↑ or Tab/Shift-Tab: move highlight. Enter: insert highlighted. 1-9 / click: insert that one.
/// Inserted suggestions are learned. Esc: insert the latin as typed.
/// Delete: edit the phrase. Punctuation or shortcuts: insert top suggestion, then pass the key on.
/// Tap Shift alone: toggle English passthrough (keys go straight to the app).
@objc(TyperInputController)
class TyperInputController: IMKInputController {
    private static var english = false  // shared by all apps, like the system Caps Lock
    private var shiftAlone = false  // Shift pressed with no other key since
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
            let shiftKey = event.keyCode == 56 || event.keyCode == 60
            let others = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            if !shiftKey || others {
                shiftAlone = false
            } else if event.modifierFlags.contains(.shift) {
                shiftAlone = true
            } else if shiftAlone {
                shiftAlone = false
                toggleEnglish(client)
            }
            return false
        }
        guard event.type == .keyDown else { return false }
        shiftAlone = false  // Shift+letter is a capital, not a toggle
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
        case 125, 126, 48:  // down, up, tab (shift-tab goes up)
            guard composing, !suggestions.isEmpty else { return false }
            let back = event.keyCode == 126 || (event.keyCode == 48 && event.modifierFlags.contains(.shift))
            select((selected + (back ? -1 : 1) + suggestions.count) % suggestions.count)
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

    private func toggleEnglish(_ client: IMKTextInput) {
        if !buffer.isEmpty { insert(buffer, client) }  // keep the half-typed phrase as latin
        Self.english.toggle()
        ModeBadge.show(Self.english ? "EN" : "ខ", near: client)
    }

    private func update(_ client: IMKTextInput) {
        client.setMarkedText(
            buffer, selectionRange: NSRange(location: buffer.utf16.count, length: 0), replacementRange: noRange)
        suggestions = buffer.trimmingCharacters(in: .whitespaces).isEmpty ? [] : Typer.suggest(buffer)
        selected = 0
        if suggestions.isEmpty {
            candidatesPanel.hide()
        } else {
            candidatesPanel.update()
            candidatesPanel.show(kIMKLocateCandidatesBelowHint)
        }
    }

    private func select(_ index: Int) {
        selected = index
        candidatesPanel.selectCandidate(withIdentifier: candidatesPanel.candidateIdentifier(atLineNumber: index))
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
