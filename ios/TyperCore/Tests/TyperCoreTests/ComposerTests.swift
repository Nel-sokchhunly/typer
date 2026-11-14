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

/// Runs every case of fixtures/composer.json, the Composer behaviour shared with Android (docs/adr/0001).
/// The Kotlin runner (android/app/src/test/.../ComposerFixtureTest.kt) reads the same file.
final class ComposerTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).appendingPathComponent("../../../../..").standardized
    static let dataDir = root.appendingPathComponent("data/out").path

    func testFixtures() throws {
        let file = Self.root.appendingPathComponent("fixtures/composer.json")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let cases = try XCTUnwrap(json["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 30)
        for c in cases {
            let name = c["name"] as? String ?? "?"
            try XCTContext.runActivity(named: name) { _ in try FixtureRun(c, name: name).run() }
        }
    }
}

/// One fixture case: a fresh user dir, a fake field, the real engine behind a spy, the Composer in Khmer mode.
private final class FixtureRun {
    let steps: [[String: Any]]
    let name: String
    let userDir = FileManager.default.temporaryDirectory.appendingPathComponent("typer-ios-\(UUID())")
    var proxy = FakeProxy()
    var spy: Spy!
    var composer: Composer!
    var manual: ManualScheduler?
    var published = 0
    var saved: [String: Any] = [:]
    var where_ = ""

    init(_ c: [String: Any], name: String) {
        steps = c["steps"] as? [[String: Any]] ?? []
        self.name = name
    }

    func make(dataDir: String = ComposerTests.dataDir, usesMarkedText: Bool = true) {
        spy = Spy(Engine(dataDir: dataDir, userDir: userDir.path))
        manual = nil
        composer = Composer(engine: spy, proxy: proxy, usesMarkedText: usesMarkedText, scheduler: .immediate)
    }

    func run() throws {
        make()
        defer { try? FileManager.default.removeItem(at: userDir) }
        XCTAssertTrue(spy.engine.loaded, "no engine data: run python3 data/build.py")
        if composer.mode == "EN" { _ = composer.toggleMode() }  // mode is static: undo other cases
        for (i, s) in steps.enumerated() {
            where_ = "\(name), step \(i + 1) \(s["op"] ?? "")"
            try step(s)
        }
    }

    func type(_ s: String) {
        for c in s where !composer.key(String(c)) { proxy.insertText(String(c)) }
    }

    var picksFile: String { (try? String(contentsOf: userDir.appendingPathComponent("picks.tsv"), encoding: .utf8)) ?? "" }
    var settings: Settings { Settings(userDir: userDir.path) }

    func field(_ s: String) -> FieldType {
        switch s {
        case "email": .email
        case "url": .url
        case "number": .number
        default: .text
        }
    }

    func step(_ s: [String: Any]) throws {
        let op = s["op"] as! String
        func str(_ k: String) -> String { s[k] as! String }
        func int(_ k: String) -> Int { (s[k] as! NSNumber).intValue }
        func bool(_ k: String) -> Bool { (s[k] as! NSNumber).boolValue }
        var consumed: Bool?
        switch op {
        case "type": type(str("text"))
        case "key": consumed = composer.key(str("text"))
        case "backspace": if !composer.backspace() { proxy.deleteBackward() }
        case "return": if !composer.returnKey() { proxy.insertText("\n") }
        case "composerBackspace": consumed = composer.backspace()
        case "returnKey": consumed = composer.returnKey()
        case "rawLatin": consumed = composer.rawLatin()
        case "toggle": consumed = composer.toggleMode()
        case "textChanged": consumed = composer.textChanged()
        case "fieldEnded": consumed = composer.fieldEnded()
        case "tap":
            let index: Int
            if s["index"] != nil { index = int("index") }
            else if let k = s["saved"] as? String { index = saved[k] as! Int }
            else { index = try XCTUnwrap(composer.suggestions.firstIndex(of: str("text")), where_) }
            consumed = composer.candidateTapped(index)
        case "traits": consumed = composer.fieldTraitsChanged(secure: bool("secure"), type: field(str("field")))
        case "moveCaretLeft": proxy.moveCaretLeft(int("n"))
        case "setBefore": proxy.before = str("text"); proxy.marked = 0
        case "proxy":
            if s["contextHasMarked"] != nil { proxy.contextHasMarked = bool("contextHasMarked") }
            if s["contextNil"] != nil { proxy.contextNil = bool("contextNil") }
        case "remake":
            make(dataDir: (s["missingData"] as? Bool) == true ? "/nonexistent" : ComposerTests.dataDir,
                 usesMarkedText: (s["usesMarkedText"] as? Bool) ?? true)
        case "manual":
            let m = ManualScheduler()
            manual = m
            composer = Composer(engine: spy, proxy: proxy, scheduler: m.scheduler)
            composer.onSuggestions = { [unowned self] in published += 1 }
        case "runEngine": manual!.runEngine(int("index"))
        case "runMain": manual!.runMain()
        case "runAll": manual!.runAll()
        case "otherToggle": consumed = Composer(engine: spy, proxy: FakeProxy(), scheduler: .immediate).toggleMode()
        case "otherMode": XCTAssertEqual(Composer(engine: spy, proxy: proxy, scheduler: .immediate).mode, str("expect"), where_)
        case "setting": try settings.set(str("name"), bool("on"))
        case "writeUserFile":
            try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
            try str("content").write(to: userDir.appendingPathComponent(str("name")), atomically: true, encoding: .utf8)
        case "resetLearning": try spy.engine.resetLearning()
        case "engineSuggest": XCTAssertEqual(spy.engine.suggest(str("input"), int("k")), s["expect"] as! [String], where_)
        case "enginePick": spy.engine.pick(str("input"), int("index"))
        case "saveFirst": saved[str("as")] = composer.suggestions[0]
        case "saveSuggestions": saved[str("as")] = composer.suggestions
        case "saveIndex": saved[str("as")] = try XCTUnwrap(composer.suggestions.firstIndex(of: str("of")), where_)
        case "saveEngine": saved[str("as")] = spy.engine.suggest(str("input"), 9)
        case "saveSuggests": saved[str("as")] = spy.suggests
        case "check": break
        default: XCTFail("unknown op \(op)")
        }
        if let want = s["consumed"] as? NSNumber { XCTAssertEqual(consumed, want.boolValue, "\(where_): consumed") }
        if let e = s["expect"] as? [String: Any] { try expect(e) }
    }

    /// "{name}" -> a saved string (or a saved list's first item).
    func text(_ v: Any) -> String {
        var s = v as! String
        for (k, value) in saved {
            if let t = value as? String { s = s.replacingOccurrences(of: "{\(k)}", with: t) }
            else if let l = value as? [String] { s = s.replacingOccurrences(of: "{\(k)}", with: l.first ?? "") }
        }
        return s
    }

    func list(_ v: Any) -> [String] {
        if let s = v as? String, s.hasPrefix("@") { return saved[String(s.dropFirst())] as! [String] }
        return v as! [String]
    }

    func int(_ v: Any) -> Int {
        if let s = v as? String, s.hasPrefix("@") { return saved[String(s.dropFirst())] as! Int }
        return (v as! NSNumber).intValue
    }

    func expect(_ e: [String: Any]) throws {
        let w = where_
        for (key, v) in e {
            switch key {
            case "doc": XCTAssertEqual(proxy.doc, text(v), "\(w): doc")
            case "markedText": XCTAssertEqual(proxy.markedText, text(v), "\(w): markedText")
            case "marked": XCTAssertEqual(proxy.marked, int(v), "\(w): marked")
            case "typed": XCTAssertEqual(composer.typed, text(v), "\(w): typed")
            case "mode": XCTAssertEqual(composer.mode, text(v), "\(w): mode")
            case "canToggle": XCTAssertEqual(composer.canToggle, (v as! NSNumber).boolValue, "\(w): canToggle")
            case "isComposing": XCTAssertEqual(composer.isComposing, (v as! NSNumber).boolValue, "\(w): isComposing")
            case "engineLoaded": XCTAssertEqual(spy.engine.loaded, (v as! NSNumber).boolValue, "\(w): engineLoaded")
            case "suggestions": XCTAssertEqual(composer.suggestions, list(v), "\(w): suggestions")
            case "notSuggestions": XCTAssertNotEqual(composer.suggestions, list(v), "\(w): suggestions should differ")
            case "suggestionsContain": XCTAssertTrue(composer.suggestions.contains(text(v)), "\(w): \(text(v)) in \(composer.suggestions)")
            case "suggestionsNotContain": XCTAssertFalse(composer.suggestions.contains(text(v)), "\(w): \(text(v)) not in suggestions")
            case "firstSuggestion": XCTAssertEqual(composer.suggestions.first, text(v), "\(w): first Suggestion")
            case "picks": XCTAssertEqual(spy.picks, list(v), "\(w): picks")
            case "picksFile": XCTAssertEqual(picksFile, text(v), "\(w): picks.tsv")
            case "picksFileContains": XCTAssertTrue(picksFile.contains(text(v)), "\(w): picks.tsv has \(text(v))")
            case "suggests": XCTAssertEqual(spy.suggests, int(v), "\(w): suggest calls")
            case "published": XCTAssertEqual(published, int(v), "\(w): published")
            case "fileExists":
                for (f, want) in v as! [String: Any] {
                    XCTAssertEqual(FileManager.default.fileExists(atPath: userDir.appendingPathComponent(f).path),
                                   (want as! NSNumber).boolValue, "\(w): \(f) exists")
                }
            case "file":
                let o = v as! [String: Any]
                XCTAssertEqual(try String(contentsOf: userDir.appendingPathComponent(o["name"] as! String), encoding: .utf8),
                               o["content"] as! String, "\(w): file")
            case "settingsOn":
                for (n, want) in v as! [String: Any] { XCTAssertEqual(settings.isOn(n), (want as! NSNumber).boolValue, "\(w): setting \(n)") }
            case "engineSetting":
                for (n, want) in v as! [String: Any] { XCTAssertEqual(spy.engine.setting(n), (want as! NSNumber).boolValue, "\(w): engine setting \(n)") }
            case "indexOf":
                let o = v as! [String: Any]
                let i = try XCTUnwrap(composer.suggestions.firstIndex(of: o["text"] as! String), "\(w): indexOf")
                if let lt = o["lt"] { XCTAssertLessThan(i, int(lt), "\(w): index") }
                if let gt = o["gt"] { XCTAssertGreaterThan(i, int(gt), "\(w): index") }
                if let eq = o["eq"] { XCTAssertEqual(i, int(eq), "\(w): index") }
            default: XCTFail("\(w): unknown expectation \(key)")
            }
        }
    }
}
