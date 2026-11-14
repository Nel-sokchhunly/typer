import XCTest

@testable import TyperCore

final class AutoCapTests: XCTestCase {
    private func shifted(_ before: String?, _ kind: AutoCap.Kind, khmer: Bool = false) -> Bool {
        AutoCap.shouldShift(before: before, kind: kind, khmerMode: khmer)
    }

    func testKhmerModeNeverShifts() {
        for kind in [AutoCap.Kind.sentences, .words, .allCharacters] {
            XCTAssertFalse(shifted("", kind, khmer: true))
            XCTAssertFalse(shifted("hi. ", kind, khmer: true))
        }
    }

    func testNoneNeverShifts() {
        XCTAssertFalse(shifted("", .none))
        XCTAssertFalse(shifted("Hi. ", .none))
    }

    func testAllCharactersAlwaysShifts() {
        XCTAssertTrue(shifted("abc", .allCharacters))
    }

    func testSentencesAtStart() {
        XCTAssertTrue(shifted("", .sentences))
        XCTAssertTrue(shifted(nil, .sentences))
    }

    func testSentencesAfterTerminatorAndSpace() {
        XCTAssertTrue(shifted("Hello. ", .sentences))
        XCTAssertTrue(shifted("Really? ", .sentences))
        XCTAssertTrue(shifted("Wow!  ", .sentences))
        XCTAssertTrue(shifted("line one\n", .sentences))
    }

    func testSentencesMidSentence() {
        XCTAssertFalse(shifted("Hello", .sentences))
        XCTAssertFalse(shifted("Hello ", .sentences))
        XCTAssertFalse(shifted("Hello.", .sentences))  // no space yet: "3.5", "e.g."
        XCTAssertFalse(shifted("Hello, ", .sentences))
    }

    func testWords() {
        XCTAssertTrue(shifted("", .words))
        XCTAssertTrue(shifted("Hello ", .words))
        XCTAssertFalse(shifted("Hello", .words))
    }
}
