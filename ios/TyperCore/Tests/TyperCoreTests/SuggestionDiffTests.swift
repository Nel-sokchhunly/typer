import XCTest

@testable import TyperCore

final class SuggestionDiffTests: XCTestCase {
    private func changed(_ s: String, _ first: String) -> String? {
        SuggestionDiff.changed(s, from: first).map { String(s[$0]) }
    }

    func testIdenticalIsNil() { XCTAssertNil(changed("abc", "abc")) }
    func testMiddleWord() { XCTAssertEqual(changed("a NEW c", "a old c"), "NEW") }
    func testChangeAtEnd() { XCTAssertEqual(changed("go home", "go work"), "home") }
    func testChangeAtStart() { XCTAssertEqual(changed("X rest", "Y rest"), "X") }
    func testDifferentLength() { XCTAssertEqual(changed("ab12cd", "abcd"), "12") }
    func testShorterThanFirstIsNil() { XCTAssertNil(changed("abcd", "ab12cd")) }
    func testKhmerClustersStayWhole() {
        XCTAssertEqual(changed("ខ្ញុំទៅសាលារៀននៅឯភ្នំពេញ", "ខ្ញុំទៅសាលារៀននៅភ្នំពេញ"), "ឯ")
        XCTAssertEqual(changed("ខ្ញុំទៅសាលារៀននូវភ្នំពេញ", "ខ្ញុំទៅសាលារៀននៅភ្នំពេញ"), "នូវ")
    }
}
