import Foundation
import XCTest

@testable import TyperCore

/// A text field: `before` + `after` with the caret between; the last `marked` characters of `before` are marked.
final class FakeProxy: TextProxy {
    var before = ""
    var after = ""
    var marked = 0
    var contextHasMarked = true  // whether the host counts marked text as before the caret
    var contextNil = false  // hosts that never report context
    var doc: String { before + after }
    var markedText: String { String(before.suffix(marked)) }

    var documentContextBeforeInput: String? {
        contextNil ? nil : contextHasMarked ? before : String(before.dropLast(marked))
    }
    func setMarkedText(_ text: String) {
        before.removeLast(marked)
        before += text
        marked = text.count
    }
    func unmarkText() { marked = 0 }
    func insertText(_ text: String) {
        before.removeLast(marked)  // like UIKit: inserting replaces the marked text
        before += text
        marked = 0
    }
    func deleteBackward() {
        guard !before.isEmpty else { return }
        before.removeLast()
        marked = max(0, marked - 1)
    }
    /// The user taps `n` characters to the left; the host keeps the marked text as plain text.
    func moveCaretLeft(_ n: Int) {
        marked = 0
        after = String(before.suffix(n)) + after
        before.removeLast(n)
    }
}

/// The real engine, counting calls.
final class Spy: Suggester {
    let engine: Engine
    var suggests = 0
    var picks: [String] = []
    init(_ engine: Engine) { self.engine = engine }
    func suggest(_ input: String, _ k: Int) -> [String] {
        suggests += 1
        return engine.suggest(input, k)
    }
    func pick(_ input: String, _ index: Int) {
        picks.append(input)
        engine.pick(input, index)
    }
}

/// Holds engine jobs and main hops until the test runs them, to play out any ordering.
final class ManualScheduler {
    var engine: [() -> Void] = []
    var main: [() -> Void] = []
    lazy var scheduler = Scheduler(
        async: { [unowned self] in engine.append($0) },
        sync: { $0() },
        main: { [unowned self] in main.append($0) })
    func runEngine(_ i: Int) { engine[i]() }
    func runMain() { let m = main; main = []; m.forEach { $0() } }
    func runAll() { engine.forEach { $0() }; runMain() }
}

final class ComposerTests: XCTestCase {
    static let dataDir = URL(fileURLWithPath: #filePath)
        .appendingPathComponent("../../../../../data/out").standardized.path
    var userDir: URL!
    var spy: Spy!
    var proxy: FakeProxy!
    var composer: Composer!

    override func setUpWithError() throws {
        userDir = FileManager.default.temporaryDirectory.appendingPathComponent("typer-ios-\(UUID())")
        make()
        XCTAssertTrue(spy.engine.loaded, "no engine data: run python3 data/build.py")
        if composer.mode == "EN" { _ = composer.toggleMode() }  // mode is static: undo other tests
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: userDir)
    }

    /// A fresh engine + composer on the same user dir (keeps the document unless asked).
    func make(dataDir: String = dataDir, usesMarkedText: Bool = true) {
        spy = Spy(Engine(dataDir: dataDir, userDir: userDir.path))
        proxy = proxy ?? FakeProxy()
        composer = Composer(engine: spy, proxy: proxy, usesMarkedText: usesMarkedText, scheduler: .immediate)
    }

    /// Type each character; what the Composer doesn't consume, the keyboard inserts as usual.
    func type(_ s: String) {
        for c in s where !composer.key(String(c)) { proxy.insertText(String(c)) }
    }

    func backspace() { if !composer.backspace() { proxy.deleteBackward() } }
    func returnKey() { if !composer.returnKey() { proxy.insertText("\n") } }
    var picks: String { (try? String(contentsOf: userDir.appendingPathComponent("picks.tsv"))) ?? "" }

    func testKnhomTapKhmer() throws {
        type("knhom")
        XCTAssertEqual(proxy.doc, "knhom")
        XCTAssertEqual(proxy.markedText, "knhom")
        XCTAssertTrue(composer.isComposing)
        let i = try XCTUnwrap(composer.suggestions.firstIndex(of: "ខ្ញុំ"))
        XCTAssertTrue(composer.candidateTapped(i))
        XCTAssertEqual(proxy.doc, "ខ្ញុំ")
        XCTAssertEqual(proxy.marked, 0)
        XCTAssertEqual(spy.picks, ["knhom"])
        XCTAssertTrue(picks.contains("knhom\tខ្ញុំ"))
        XCTAssertEqual(composer.suggestions, [])
        XCTAssertFalse(composer.isComposing)
    }

    func testPhrase() {
        type("knhom tov sala rean")
        XCTAssertEqual(proxy.markedText, "knhom tov sala rean")
        XCTAssertTrue(composer.candidateTapped(0))
        XCTAssertEqual(proxy.doc, "ខ្ញុំទៅសាលារៀន")
        XCTAssertEqual(proxy.marked, 0)
    }

    func testSpace() {
        XCTAssertFalse(composer.key(" "), "idle space passes through")
        type("knhom  tov ")
        XCTAssertEqual(proxy.doc, "knhom tov ", "double space collapses, space never commits")
        XCTAssertEqual(proxy.markedText, "knhom tov ")
    }

    func testPunctuationJoinsPhrase() {
        XCTAssertFalse(composer.key("?"), "idle punctuation passes through")
        type("knhom, tov te?")
        XCTAssertEqual(proxy.markedText, "knhom, tov te?")
        XCTAssertEqual(composer.suggestions.first, "ខ្ញុំ, ទៅទេ?")
        returnKey()
        XCTAssertEqual(proxy.doc, "ខ្ញុំ, ទៅទេ?")
    }

    func testReturn() {
        type("knhom")
        let top = composer.suggestions[0]
        XCTAssertTrue(composer.returnKey())
        XCTAssertEqual(proxy.doc, top)
        XCTAssertEqual(proxy.marked, 0)
        XCTAssertFalse(composer.returnKey(), "idle return passes through")
    }

    func testBackspace() {
        type("knhomx")
        backspace()
        XCTAssertEqual(proxy.markedText, "knhom")
        XCTAssertTrue(composer.suggestions.contains("ខ្ញុំ"))
        for _ in 0..<5 { backspace() }
        XCTAssertEqual(proxy.doc, "")
        XCTAssertEqual(proxy.marked, 0)
        XCTAssertEqual(composer.suggestions, [])
        XCTAssertFalse(composer.isComposing)
        proxy.before = "ab"
        XCTAssertFalse(composer.backspace(), "idle backspace passes through")
    }

    func testDigitCommitsTopThenPassesThrough() {
        type("knhom")
        let top = composer.suggestions[0]
        type("2")
        XCTAssertEqual(proxy.doc, top + "2")
        XCTAssertEqual(proxy.marked, 0)
        type("😀")
        XCTAssertEqual(proxy.doc, top + "2😀", "idle: other keys pass through")
    }

    func testRawLatinLearnsNothing() {
        type("knhom tov ")
        XCTAssertTrue(composer.rawLatin())
        XCTAssertEqual(proxy.doc, "knhom tov ")
        XCTAssertEqual(proxy.marked, 0)
        XCTAssertEqual(spy.picks, [])
        XCTAssertEqual(picks, "")
        XCTAssertFalse(composer.rawLatin())
    }

    func testPickPersists() throws {
        type("ah ach")
        let before = composer.suggestions
        let i = try XCTUnwrap(before.firstIndex(of: "អាអាចម៍"))
        XCTAssertGreaterThan(i, 0)
        _ = composer.candidateTapped(i)
        make()  // as if the keyboard reloaded
        type("ah ach")
        let after = try XCTUnwrap(composer.suggestions.firstIndex(of: "អាអាចម៍"))
        XCTAssertLessThan(after, i)
    }

    func testLearnSwitchOff() throws {
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        try "learn=off\n".write(to: userDir.appendingPathComponent("settings.txt"), atomically: true, encoding: .utf8)
        type("knhom")
        _ = composer.candidateTapped(0)
        XCTAssertEqual(proxy.doc, "ខ្ញុំ")
        XCTAssertFalse(FileManager.default.fileExists(atPath: userDir.appendingPathComponent("picks.tsv").path))
    }

    var settings: Settings { Settings(userDir: userDir.path) }
    var settingsFile: URL { userDir.appendingPathComponent("settings.txt") }

    func testSettingsFormat() throws {
        XCTAssertTrue(Settings.names.allSatisfy(settings.isOn), "no settings.txt: all on, like the engine")
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        try "# note\nlearn = off\nbadge=off\nfoo=bar".write(to: settingsFile, atomically: true, encoding: .utf8)
        XCTAssertFalse(settings.isOn("learn"))
        XCTAssertFalse(settings.isOn("badge"))
        XCTAssertTrue(settings.isOn("english"))
        try settings.set("learn", true)
        try settings.set("english", false)
        XCTAssertEqual(try String(contentsOf: settingsFile), "# note\nlearn=on\nbadge=off\nfoo=bar\nenglish=off\n")
        XCTAssertTrue(spy.engine.setting("learn"))
        XCTAssertFalse(spy.engine.setting("english"))
        XCTAssertFalse(spy.engine.setting("badge"))
    }

    func testEnglishSwitchAppliesNextKeystroke() throws {
        let want = "thank you បង"
        type("thank you bong")
        XCTAssertTrue(composer.suggestions.contains(want))
        for on in [false, true, false] {
            try settings.set("english", on)
            backspace()
            type("g")
            XCTAssertEqual(composer.suggestions.contains(want), on, "english=\(on)")
        }
    }

    func testLearnOffPickDoesNotRank() throws {
        try settings.set("learn", false)
        type("ah ach")
        let i = try XCTUnwrap(composer.suggestions.firstIndex(of: "អាអាចម៍"))
        XCTAssertGreaterThan(i, 0)
        _ = composer.candidateTapped(i)
        XCTAssertEqual(spy.picks, ["ah ach"], "the Composer still calls pick; the engine ignores it")
        type("ah ach")
        XCTAssertEqual(composer.suggestions.firstIndex(of: "អាអាចម៍"), i)
        XCTAssertEqual(picks, "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: userDir.appendingPathComponent("user.tsv").path))
    }

    func testResetLearning() throws {
        try settings.set("generated", false)
        type("ah ach")
        let fresh = composer.suggestions
        _ = composer.candidateTapped(try XCTUnwrap(fresh.firstIndex(of: "អាអាចម៍")))
        type("ah ach")
        XCTAssertNotEqual(composer.suggestions, fresh)
        _ = composer.rawLatin()
        try spy.engine.resetLearning()
        type("ah ach")
        XCTAssertEqual(composer.suggestions, fresh, "same as before any pick, with no new Composer")
        for f in ["user.tsv", "picks.tsv"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: userDir.appendingPathComponent(f).path))
        }
        XCTAssertFalse(settings.isOn("generated"), "settings survive a reset")
        try spy.engine.resetLearning()  // nothing to delete
    }

    func testExternalChangeKeepsLatin() {
        type("knhom")
        proxy.moveCaretLeft(2)
        XCTAssertTrue(composer.textChanged())
        XCTAssertEqual(proxy.doc, "knhom")
        XCTAssertEqual(proxy.marked, 0)
        XCTAssertFalse(composer.isComposing)
        XCTAssertEqual(spy.picks, [])
    }

    func testEchoesOfOwnWritesIgnored() {
        for hasMarked in [true, false] {
            proxy.contextHasMarked = hasMarked
            type("knhom")
            XCTAssertFalse(composer.textChanged(), "selectionDidChange after setMarkedText")
            XCTAssertFalse(composer.textChanged(), "double echo")
            XCTAssertEqual(proxy.markedText, "knhom")
            _ = composer.candidateTapped(0)
            XCTAssertFalse(composer.textChanged(), "the commit's echo")
        }
        XCTAssertEqual(spy.picks.count, 2)
    }

    func testNoEchoThenRealChange() {
        type("knhom")
        _ = composer.candidateTapped(0)  // no textChanged follows
        type("tov")
        proxy.moveCaretLeft(1)
        XCTAssertTrue(composer.textChanged())
        XCTAssertEqual(proxy.doc, "ខ្ញុំtov")
        XCTAssertFalse(composer.isComposing)
    }

    func testNilContextNeverCommits() {
        proxy.contextNil = true
        type("knhom")
        XCTAssertFalse(composer.textChanged())
        XCTAssertEqual(proxy.markedText, "knhom")
    }

    func testFallbackDoubleEcho() {
        make(usesMarkedText: false)
        type("kn")
        XCTAssertFalse(composer.textChanged())
        XCTAssertFalse(composer.textChanged())
        type("hom")
        XCTAssertEqual(proxy.doc, "knhom")
        XCTAssertTrue(composer.isComposing)
    }

    func testFallbackCaretMovedBeforeCommit() throws {
        make(usesMarkedText: false)
        proxy.before = "hi "
        type("knhom")
        let i = try XCTUnwrap(composer.suggestions.firstIndex(of: "ខ្ញុំ"))
        proxy.moveCaretLeft(2)  // no textChanged arrives
        XCTAssertTrue(composer.candidateTapped(i))
        XCTAssertEqual(proxy.doc, "hi knhom", "nothing deleted blind")
        XCTAssertFalse(composer.isComposing)
        XCTAssertEqual(spy.picks, [], "not inserted, so not learned")
    }

    func testSameTraitsReportedAgain() {
        type("knhom")
        XCTAssertFalse(composer.fieldTraitsChanged(secure: false, type: .text))
        XCTAssertTrue(composer.isComposing)
        XCTAssertEqual(proxy.markedText, "knhom")
    }

    func testModeFlipMidPhrase() {
        type("knhom")
        let other = Composer(engine: spy, proxy: FakeProxy())  // another keyboard instance
        XCTAssertTrue(other.toggleMode())
        XCTAssertFalse(composer.returnKey())
        XCTAssertEqual(proxy.doc, "knhom")
        XCTAssertEqual(proxy.marked, 0, "no marked text left dangling")
        XCTAssertFalse(composer.isComposing)
        for flip in [{ self.composer.backspace() }, { self.composer.candidateTapped(0) }, { self.composer.rawLatin() }] {
            XCTAssertFalse(flip())
        }
        XCTAssertTrue(other.toggleMode())
    }

    func testBadIndexes() {
        type("knhom")
        XCTAssertTrue(composer.candidateTapped(-1), "out of range: the Latin")
        XCTAssertEqual(proxy.doc, "knhom")
        XCTAssertEqual(spy.picks, [])
        XCTAssertEqual(spy.engine.suggest("knhom", -1), [])
        spy.engine.pick("knhom", -1)
    }

    func testFieldEndedKeepsLatin() {
        type("knhom")
        XCTAssertTrue(composer.fieldEnded())
        XCTAssertEqual(proxy.doc, "knhom")
        XCTAssertEqual(proxy.marked, 0)
        XCTAssertFalse(composer.fieldEnded())
    }

    func testToggle() {
        type("knhom")
        XCTAssertFalse(composer.toggleMode(), "ignored mid-phrase")
        XCTAssertEqual(composer.mode, "ខ")
        _ = composer.rawLatin()
        XCTAssertTrue(composer.toggleMode())
        XCTAssertEqual(composer.mode, "EN")
        let other = Composer(engine: spy, proxy: proxy)
        XCTAssertEqual(other.mode, "EN", "shared across keyboard instances")
        let calls = spy.suggests
        for k in ["k", " ", ",", "1"] { XCTAssertFalse(composer.key(k)) }
        XCTAssertFalse(composer.backspace())
        XCTAssertFalse(composer.returnKey())
        XCTAssertEqual(spy.suggests, calls)
        XCTAssertTrue(composer.toggleMode())
        XCTAssertEqual(composer.mode, "ខ")
    }

    func testCanToggleOnlyInKhmerEmptyTextField() {
        XCTAssertTrue(composer.canToggle)
        type("k")
        XCTAssertFalse(composer.canToggle, "mid-phrase")
        _ = composer.rawLatin()
        XCTAssertTrue(composer.canToggle)
        for (s, t) in [(true, FieldType.text), (false, .email), (false, .number)] {
            _ = composer.fieldTraitsChanged(secure: s, type: t)
            XCTAssertFalse(composer.canToggle)
            XCTAssertEqual(composer.mode, "EN")
        }
        _ = composer.fieldTraitsChanged(secure: false, type: .text)
        XCTAssertTrue(composer.canToggle)
        XCTAssertEqual(composer.mode, "ខ")
    }

    func testURLFieldStartsEnglishButCanSwitchToKhmer() {
        _ = composer.fieldTraitsChanged(secure: false, type: .url)
        XCTAssertEqual(composer.mode, "EN", "URLs are Latin, so EN first")
        XCTAssertTrue(composer.canToggle)
        XCTAssertTrue(composer.toggleMode())
        XCTAssertEqual(composer.mode, "ខ", "searching in Khmer from the address bar")
        type("knhom")
        XCTAssertEqual(composer.typed, "knhom")
        _ = composer.rawLatin()
        _ = composer.fieldTraitsChanged(secure: false, type: .text)
        XCTAssertEqual(composer.mode, "ខ", "the global mode was not touched")
        _ = composer.fieldTraitsChanged(secure: false, type: .url)
        XCTAssertEqual(composer.mode, "EN", "a new URL field starts EN again")
    }

    func testEnglishChoiceSurvivesForcedField() {
        XCTAssertTrue(composer.toggleMode())
        _ = composer.fieldTraitsChanged(secure: true, type: .text)
        XCTAssertEqual(composer.mode, "EN")
        _ = composer.fieldTraitsChanged(secure: false, type: .text)
        XCTAssertEqual(composer.mode, "EN", "the user's English choice is back after the password field")
        XCTAssertTrue(composer.toggleMode())
        XCTAssertEqual(composer.mode, "ខ")
    }

    func testEnglishModeTypesPlain() {
        XCTAssertTrue(composer.toggleMode())
        type("hello world")
        XCTAssertEqual(proxy.doc, "hello world")
        XCTAssertEqual(proxy.marked, 0)
        XCTAssertEqual(composer.typed, "")
        XCTAssertEqual(composer.suggestions, [])
        XCTAssertEqual(spy.suggests, 0)
    }

    func testCursorMoveAndFieldEndLearnNothing() {
        type("knhom")
        proxy.moveCaretLeft(2)
        XCTAssertTrue(composer.textChanged())
        XCTAssertEqual(spy.picks, [])
        type("tov")
        XCTAssertTrue(composer.fieldEnded())
        XCTAssertEqual(spy.picks, [])
        XCTAssertEqual(picks, "")
        XCTAssertEqual(proxy.marked, 0)
    }

    func testSecureFieldNeverCallsEngine() {
        _ = composer.fieldTraitsChanged(secure: true, type: .text)
        XCTAssertEqual(composer.mode, "EN")
        type("knhom tov")
        XCTAssertFalse(composer.returnKey())
        XCTAssertFalse(composer.candidateTapped(0))
        XCTAssertEqual(proxy.doc, "knhom tov")
        XCTAssertEqual(proxy.marked, 0)
        XCTAssertEqual(spy.suggests, 0)
        XCTAssertEqual(spy.picks, [])
        XCTAssertFalse(composer.toggleMode())
        _ = composer.fieldTraitsChanged(secure: false, type: .text)
        XCTAssertEqual(composer.mode, "ខ")
    }

    func testEmailURLNumberPassThrough() {
        for t in [FieldType.email, .url, .number] {
            _ = composer.fieldTraitsChanged(secure: false, type: t)
            XCTAssertFalse(composer.key("a"))
        }
        XCTAssertEqual(spy.suggests, 0)
    }

    func testTraitsChangeMidPhraseKeepsLatin() {
        type("knhom")
        XCTAssertTrue(composer.fieldTraitsChanged(secure: true, type: .text))
        XCTAssertEqual(proxy.doc, "knhom")
        XCTAssertEqual(proxy.marked, 0)
    }

    func testEngineFailedTypesLatin() {
        make(dataDir: "/nonexistent")
        XCTAssertFalse(spy.engine.loaded)
        XCTAssertTrue(spy.engine.setting("learn"))
        type("knhom tov")
        XCTAssertEqual(proxy.markedText, "knhom tov")
        XCTAssertEqual(composer.suggestions, [])
        returnKey()
        XCTAssertEqual(proxy.doc, "knhom tov")
        XCTAssertEqual(proxy.marked, 0)
        type("ab")
        XCTAssertTrue(composer.candidateTapped(3), "no suggestions: inserts the Latin")
        XCTAssertEqual(proxy.doc, "knhom tovab")
    }

    func testMarkedTextFallback() throws {
        make(usesMarkedText: false)
        proxy.before = "hi "
        type("knhomx")
        XCTAssertEqual(proxy.doc, "hi knhomx")
        XCTAssertEqual(proxy.marked, 0, "no marked text at all")
        backspace()
        XCTAssertEqual(proxy.doc, "hi knhom")
        let i = try XCTUnwrap(composer.suggestions.firstIndex(of: "ខ្ញុំ"))
        _ = composer.candidateTapped(i)
        XCTAssertEqual(proxy.doc, "hi ខ្ញុំ")
        type("tov")
        XCTAssertTrue(composer.rawLatin())
        XCTAssertEqual(proxy.doc, "hi ខ្ញុំtov")
        type("ab")
        for _ in 0..<2 { backspace() }
        XCTAssertEqual(proxy.doc, "hi ខ្ញុំtov")
        XCTAssertFalse(composer.isComposing)
        type("x")
        XCTAssertFalse(composer.textChanged(), "the insert's own textDidChange")
        proxy.moveCaretLeft(1)
        XCTAssertTrue(composer.textChanged())
        XCTAssertEqual(proxy.doc, "hi ខ្ញុំtovx")
    }

    // MARK: suggestions off the main thread

    func manualComposer() -> ManualScheduler {
        let m = ManualScheduler()
        composer = Composer(engine: spy, proxy: proxy, scheduler: m.scheduler)
        return m
    }

    func testStaleSuggestionsAreDropped() {
        let m = manualComposer()
        type("k")
        m.runEngine(0)  // "k" computed, its hop to main not run yet
        type("n")
        m.runMain()  // the stale result arrives
        XCTAssertEqual(composer.suggestions, [], "stale result for a Phrase that moved on")
        m.runEngine(1)
        m.runMain()
        XCTAssertEqual(composer.suggestions, spy.engine.suggest("kn", 9))
    }

    func testReturnBeforeResultsCommitsCurrentPhrase() {
        let m = manualComposer()
        type("knhom")
        returnKey()
        XCTAssertEqual(proxy.doc, spy.engine.suggest("knhom", 9)[0])
        XCTAssertEqual(proxy.marked, 0)
        m.runAll()  // late jobs must not resurrect anything
        XCTAssertEqual(composer.suggestions, [])
        XCTAssertFalse(composer.isComposing)
        XCTAssertEqual(spy.picks, ["knhom"])
    }

    func testMarkedTextUpdatesBeforeSuggestions() {
        let m = manualComposer()
        var published = 0
        composer.onSuggestions = { published += 1 }
        type("knh")
        XCTAssertEqual(proxy.markedText, "knh")
        XCTAssertEqual(composer.suggestions, [])
        XCTAssertEqual(spy.suggests, 0)
        m.runAll()
        XCTAssertEqual(composer.suggestions, spy.engine.suggest("knh", 9))
        XCTAssertEqual(published, 1, "only the latest request publishes")
    }
}
