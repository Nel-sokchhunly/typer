import Foundation
import XCTest

@testable import TyperCore

/// A text field: the document, with the last `marked` characters marked and the caret at the end.
final class FakeProxy: TextProxy {
    var doc = ""
    var marked = 0
    var markedText: String { String(doc.suffix(marked)) }

    func setMarkedText(_ text: String) {
        doc.removeLast(marked)
        doc += text
        marked = text.count
    }
    func unmarkText() { marked = 0 }
    func insertText(_ text: String) {
        doc.removeLast(marked)  // like UIKit: inserting replaces the marked text
        doc += text
        marked = 0
    }
    func deleteBackward() {
        guard !doc.isEmpty else { return }
        doc.removeLast()
        marked = max(0, marked - 1)
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

final class ComposerTests: XCTestCase {
    static let dataDir = URL(fileURLWithPath: #filePath)
        .appendingPathComponent("../../../../../data/out").standardized.path
    var userDir: URL!
    var spy: Spy!
    var proxy: FakeProxy!
    var composer: Composer!

    override func setUpWithError() throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: Self.dataDir + "/lexicon.tsv"), "run python3 data/build.py")
        userDir = FileManager.default.temporaryDirectory.appendingPathComponent("typer-ios-\(UUID())")
        make()
        XCTAssertTrue(spy.engine.loaded)
        if composer.mode == "EN" { _ = composer.toggleMode() }  // mode is static: undo other tests
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: userDir)
    }

    /// A fresh engine + composer on the same user dir (keeps the document unless asked).
    func make(dataDir: String = dataDir, usesMarkedText: Bool = true) {
        spy = Spy(Engine(dataDir: dataDir, userDir: userDir.path))
        proxy = proxy ?? FakeProxy()
        composer = Composer(engine: spy, proxy: proxy, usesMarkedText: usesMarkedText)
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
        proxy.doc = "ab"
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

    func testExternalChangeKeepsLatin() {
        type("knhom")
        XCTAssertTrue(composer.textChanged())
        XCTAssertEqual(proxy.doc, "knhom")
        XCTAssertEqual(proxy.marked, 0)
        XCTAssertFalse(composer.isComposing)
        XCTAssertEqual(spy.picks, [])
    }

    func testOwnChangeIgnored() {
        type("knhom")
        _ = composer.candidateTapped(0)
        XCTAssertTrue(composer.ownChangePending)
        type("tov")
        XCTAssertFalse(composer.textChanged(), "the commit's own textDidChange")
        XCTAssertTrue(composer.isComposing)
        XCTAssertTrue(composer.textChanged(), "a real one")
        XCTAssertEqual(proxy.doc, "ខ្ញុំtov")
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
        proxy.doc = "hi "
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
        XCTAssertTrue(composer.textChanged())
        XCTAssertEqual(proxy.doc, "hi ខ្ញុំtovx")
    }
}
