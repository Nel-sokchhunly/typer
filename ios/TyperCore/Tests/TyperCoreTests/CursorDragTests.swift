import XCTest

@testable import TyperCore

final class CursorDragTests: XCTestCase {
    /// Walks `text` (2 clusters) one cluster at a time from the left end, then back, checking every stop is a Character boundary.
    func testKhmerStepsNeverLandInsideACluster() {
        let text = "ខ្ញុំទៅ"
        var boundaries = Set<Int>()
        for i in text.indices { boundaries.insert(text.utf16.distance(from: text.startIndex, to: i)) }
        boundaries.insert(text.utf16.count)

        let u = Array(text.utf16)
        func split(_ pos: Int) -> (String, String) {
            (String(decoding: u[..<pos], as: UTF16.self), String(decoding: u[pos...], as: UTF16.self))
        }
        var pos = 0
        for _ in 0..<2 {
            pos += cursorOffset(before: split(pos).0, after: split(pos).1, clusters: 1)
            XCTAssertTrue(boundaries.contains(pos), "landed inside a cluster at \(pos)")
        }
        XCTAssertEqual(pos, u.count)
        for _ in 0..<2 {
            pos += cursorOffset(before: split(pos).0, after: split(pos).1, clusters: -1)
            XCTAssertTrue(boundaries.contains(pos), "landed inside a cluster at \(pos)")
        }
        XCTAssertEqual(pos, 0)
    }

    func testKhmerClusterIsOneStep() {
        XCTAssertEqual(cursorOffset(before: nil, after: "ខ្ញុំទៅ", clusters: 1), "ខ្ញុំ".utf16.count)
        XCTAssertEqual(cursorOffset(before: "ខ្ញុំទៅ", after: nil, clusters: -1), -"ទៅ".utf16.count)
    }

    func testMixedLatinKhmerEmoji() {
        let s = "a👍🏽🇰🇭ខ្ញុំb"
        XCTAssertEqual(cursorOffset(before: nil, after: s, clusters: 1), 1)
        XCTAssertEqual(cursorOffset(before: nil, after: s, clusters: 2), 1 + "👍🏽".utf16.count)
        XCTAssertEqual(cursorOffset(before: nil, after: s, clusters: 3), 1 + "👍🏽🇰🇭".utf16.count)
        XCTAssertEqual(cursorOffset(before: s, after: nil, clusters: -2), -("ខ្ញុំb".utf16.count))
        XCTAssertEqual(cursorOffset(before: "x🇰🇭", after: nil, clusters: -1), -4)
    }

    func testClampsAtTheEnds() {
        XCTAssertEqual(cursorOffset(before: "ab", after: nil, clusters: -9), -2)
        XCTAssertEqual(cursorOffset(before: nil, after: "ខ្ញុំ", clusters: 9), "ខ្ញុំ".utf16.count)
    }

    func testNilOrEmptyContextIsZero() {
        XCTAssertEqual(cursorOffset(before: nil, after: nil, clusters: -3), 0)
        XCTAssertEqual(cursorOffset(before: nil, after: nil, clusters: 3), 0)
        XCTAssertEqual(cursorOffset(before: "", after: "", clusters: -1), 0)
        XCTAssertEqual(cursorOffset(before: "abc", after: "", clusters: 1), 0)
        XCTAssertEqual(cursorOffset(before: "", after: "abc", clusters: -1), 0)
        XCTAssertEqual(cursorOffset(before: "abc", after: "abc", clusters: 0), 0)
    }
}
