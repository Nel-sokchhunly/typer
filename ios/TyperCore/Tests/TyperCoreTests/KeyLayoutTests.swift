import XCTest

@testable import TyperCore

final class KeyLayoutTests: XCTestCase {
    let w: CGFloat = 390
    var letters: [Key] { KeyLayout.keys(width: w, page: .letters, upper: false, globe: true, bar: []) }

    func key(_ a: KeyAction, in keys: [Key]) -> Key { keys.first { $0.action == a }! }

    func testPointInsideKeyHitsIt() {
        let g = key(.char("g"), in: letters)
        XCTAssertEqual(KeyLayout.hit(CGPoint(x: g.rect.midX, y: g.rect.midY), in: letters)?.action, .char("g"))
    }

    func testGapBetweenKeysResolvesToNearestNeighbour() {
        let q = key(.char("q"), in: letters), wk = key(.char("w"), in: letters)
        let mid = (q.rect.maxX + wk.rect.minX) / 2
        XCTAssertEqual(KeyLayout.hit(CGPoint(x: mid - 1, y: q.rect.midY), in: letters)?.action, .char("q"))
        XCTAssertEqual(KeyLayout.hit(CGPoint(x: mid + 1, y: q.rect.midY), in: letters)?.action, .char("w"))
    }

    func testGapBetweenRowsResolvesToNearestRow() {
        let q = key(.char("q"), in: letters)
        XCTAssertEqual(KeyLayout.hit(CGPoint(x: q.rect.midX, y: q.rect.maxY + 1), in: letters)?.action, .char("q"))
    }

    func testLeftOfRowTwoIsA() {
        let a = key(.char("a"), in: letters)
        XCTAssertEqual(KeyLayout.hit(CGPoint(x: 2, y: a.rect.midY), in: letters)?.action, .char("a"))
        XCTAssertEqual(KeyLayout.hit(CGPoint(x: w - 1, y: a.rect.midY), in: letters)?.action, .char("l"))
    }

    func testOutsideTheViewStillResolves() {
        XCTAssertNotNil(KeyLayout.hit(CGPoint(x: -50, y: 9999), in: letters))
        XCTAssertNil(KeyLayout.hit(.zero, in: []))
    }

    func testRowsFitTheWidthAndKeyboardHeight() {
        for page in [KeyPage.letters, .numbers, .symbols] {
            let ks = KeyLayout.keys(width: w, page: page, upper: false, globe: true, bar: KeyLayout.punctuation)
            XCTAssertEqual(ks.map(\.rect.maxX).max()!, w - KeyLayout.margin, accuracy: 0.01)
            XCTAssertEqual(ks.map(\.rect.minX).min()!, KeyLayout.margin, accuracy: 0.01)
            XCTAssertLessThanOrEqual(ks.map(\.rect.maxY).max()!, KeyLayout.height)
        }
    }

    func testShiftShowsUppercaseGlobeIsOptionalBarHasSixPunctuationKeys() {
        let up = KeyLayout.keys(width: w, page: .letters, upper: true, globe: false, bar: [])
        XCTAssertTrue(up.contains { $0.action == .char("Q") })
        XCTAssertFalse(up.contains { $0.action == .globe })
        let bar = KeyLayout.keys(width: w, page: .letters, upper: false, globe: true, bar: KeyLayout.punctuation)
        XCTAssertEqual(bar.filter { if case .punct = $0.action { true } else { false } }.count, 6)
        let english = KeyLayout.keys(width: w, page: .letters, upper: false, globe: true, bar: KeyLayout.englishPunctuation)
        XCTAssertTrue(english.contains { $0.action == .punct(".") })
        XCTAssertFalse(english.contains { $0.action == .punct("។") })
    }
}

final class KeyTouchesTests: XCTestCase {
    func k(_ c: String) -> Key { Key(action: .char(c), rect: .zero) }
    let bs = Key(action: .backspace, rect: .zero)

    func testTapFiresOnUp() {
        var t = KeyTouches<Int>()
        XCTAssertEqual(t.down(1, k("a")), [.press])
        XCTAssertEqual(t.up(1, k("a")), [.fire(.char("a"))])
    }

    func testRolloverFiresEarlierKeyAtNextDown() {
        var t = KeyTouches<Int>()
        _ = t.down(1, k("a"))
        XCTAssertEqual(t.down(2, k("b")), [.fire(.char("a")), .press])
        XCTAssertEqual(t.up(1, k("a")), [])
        XCTAssertEqual(t.up(2, k("b")), [.fire(.char("b"))])
    }

    func testSlideFiresKeyUnderFingerAtLift() {
        var t = KeyTouches<Int>()
        _ = t.down(1, k("a"))
        _ = t.move(1, k("b"))
        XCTAssertEqual(t.pressed, [k("b")])
        XCTAssertEqual(t.up(1, k("b")), [.fire(.char("b"))])
    }

    func testCancelFiresNothing() {
        var t = KeyTouches<Int>()
        _ = t.down(1, k("a"))
        XCTAssertEqual(t.cancel(1), [])
        XCTAssertEqual(t.up(1, k("a")), [])
        XCTAssertEqual(t.pressed, [])
    }

    func testBackspaceFiresAtDownAndRepeatsUntilUp() {
        var t = KeyTouches<Int>()
        XCTAssertEqual(t.down(1, bs), [.press, .fire(.backspace), .startRepeat])
        XCTAssertEqual(t.up(1, bs), [.stopRepeat])
    }

    func testAnotherTouchStopsBackspaceRepeatWithoutFiringAgain() {
        var t = KeyTouches<Int>()
        _ = t.down(1, bs)
        XCTAssertEqual(t.down(2, k("a")), [.stopRepeat, .press])
    }

    func testSlidingOffBackspaceStopsRepeat() {
        var t = KeyTouches<Int>()
        _ = t.down(1, bs)
        XCTAssertEqual(t.move(1, k("a")), [.stopRepeat])
        XCTAssertEqual(t.up(1, k("a")), [.fire(.char("a"))])
    }
}
