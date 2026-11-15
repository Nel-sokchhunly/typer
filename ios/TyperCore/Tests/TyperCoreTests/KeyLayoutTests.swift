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

    func testKhmerLayoutHasFourRowsOfTwelveNoModeKeyAndFitsItsHeight() {
        let ks = KeyLayout.keys(width: w, page: .letters, upper: false, globe: true, bar: KeyLayout.khmerPunctuation, khmer: true)
        let rows = Dictionary(grouping: ks.filter { $0.rect.minY >= KeyLayout.rowsTop }, by: \.rect.minY).sorted { $0.key < $1.key }
        XCTAssertEqual(rows.map(\.value.count), [12, 12, 12, 12, 4])  // page, globe, space, return
        XCTAssertEqual(rows[3].value.first?.action, .shift)
        XCTAssertEqual(rows[3].value.last?.action, .backspace)
        XCTAssertEqual(rows[0].value.map(\.action), KhmerKeys.base[0].map { .char($0) })
        XCTAssertFalse(ks.contains { $0.action == .mode })
        XCTAssertEqual(ks.filter { if case .punct = $0.action { true } else { false } }.count, 8)
        XCTAssertEqual(ks.first { $0.action == .slot }?.rect.maxX ?? 0, w - KeyLayout.margin, accuracy: 0.01)
        XCTAssertEqual(ks.map(\.rect.maxX).max()!, w - KeyLayout.margin, accuracy: 0.01)
        XCTAssertLessThanOrEqual(ks.map(\.rect.maxY).max()!, KeyLayout.khmerHeight)
        XCTAssertGreaterThan(ks.map(\.rect.maxY).max()!, KeyLayout.height)
    }

    func testKhmerShiftShowsTheShiftLayerInTheSameShape() {
        XCTAssertEqual(KhmerKeys.shift.map(\.count), KhmerKeys.base.map(\.count))
        let ks = KeyLayout.keys(width: w, page: .letters, upper: true, globe: true, bar: [], khmer: true)
        let rows = Dictionary(grouping: ks, by: \.rect.minY).sorted { $0.key < $1.key }
        XCTAssertEqual(rows.map(\.value.count), [12, 12, 12, 12, 4])
        for i in 0..<4 {
            let chars = rows[i].value.map(\.action).filter { $0 != .shift && $0 != .backspace }
            XCTAssertEqual(chars, KhmerKeys.shift[i].map { .char($0) })
        }
        XCTAssertEqual(rows[3].value.first?.action, .shift)
        XCTAssertEqual(rows[3].value.last?.action, .backspace)
    }

    /// Every Khmer character (U+1780–17DD, U+17E0–17E9) types from base, shift or a long-press list.
    func testKhmerLettersAreReachable() {
        let excluded: Set<UInt32> = [
            0x17A3, 0x17A4, 0x17D3,  // ឣ ឤ ៓: deprecated by Unicode
            0x17B4, 0x17B5,  // inherent vowels: Unicode says don't use
        ]
        let layers = (KhmerKeys.base + KhmerKeys.shift).joined()
        let typed = Set((layers + layers.flatMap { KhmerKeys.longPress[$0] ?? [] }).flatMap(\.unicodeScalars).map(\.value))
        for v: UInt32 in Array(0x1780...0x17DD) + Array(0x17E0...0x17E9) where !excluded.contains(v) {
            XCTAssertTrue(typed.contains(v), String(format: "U+%04X", v))
        }
        XCTAssertTrue(excluded.isDisjoint(with: typed))
    }

    /// #79's lists in definition order, plus ៑ on ្ (ours).
    func testLongPressListsMatchTheKeyMap() {
        XCTAssertEqual(KhmerKeys.longPress, [
            "១": ["1", "៱"], "២": ["2", "៲"], "៣": ["3", "៳"], "៤": ["4", "៴"], "៥": ["5", "៵"],
            "៦": ["6", "៶"], "៧": ["7", "៷"], "៨": ["8", "៸"], "៩": ["9", "៹"], "០": ["0", "៰"],
            "ឥ": ["ឦ"], "ឲ": ["ឱ"], "ឪ": ["ឧ", "ឱ", "ឳ", "ឩ", "ឨ"], "ឮ": ["ឭ", "ឰ"], "៊": ["៘"],
            "៛": ["$", "€"], "%": ["៖"], "៍": ["៙"], "័": ["៚"], "៏": ["ៗ"], "(": ["{", "«"], ")": ["}", "»"],
            "៌": ["×"], "ឈ": ["ៜ"], "ឺ": ["៝"], "ឬ": ["ឫ"], "ះ": ["ៈ"], "គ": ["ឝ"], "ព": ["ឞ"],
            "!": ["\u{200D}"], "ៗ": ["\u{200C}"], "្": ["\u{17D1}"],
        ])
        XCTAssertEqual(KhmerKeys.optionLabel(for: "\u{200D}"), "ZWJ")
        XCTAssertEqual(KhmerKeys.optionLabel(for: "\u{200C}"), "ZWNJ")
        XCTAssertEqual(KhmerKeys.optionLabel(for: "៑"), "៑")
    }

    func testOnlyKhmerLettersHaveLongPress() {
        let base = KeyLayout.keys(width: w, page: .letters, upper: false, globe: true, bar: [], khmer: true)
        let shift = KeyLayout.keys(width: w, page: .letters, upper: true, globe: true, bar: [], khmer: true)
        XCTAssertEqual(key(.char("ឪ"), in: base).longPress, ["ឧ", "ឱ", "ឳ", "ឩ", "ឨ"])
        XCTAssertEqual(key(.char("!"), in: shift).longPress, ["\u{200D}"])
        XCTAssertEqual(key(.char("ក"), in: base).longPress, [])
        for page in [KeyPage.letters, .numbers, .symbols] {  // Sing pages have ( ) ! % too
            XCTAssertTrue(KeyLayout.keys(width: w, page: page, upper: false, globe: true, bar: []).allSatisfy(\.longPress.isEmpty))
        }
        let khmerNumbers = KeyLayout.keys(width: w, page: .numbers, upper: false, globe: true, bar: [], khmer: true)
        XCTAssertTrue(khmerNumbers.allSatisfy(\.longPress.isEmpty))
    }

    func testPanelRunsFromTheKeyTowardTheWiderSideAndStaysInside() {
        for upper in [false, true] {
            let ks = KeyLayout.keys(width: w, page: .letters, upper: upper, globe: true, bar: [], khmer: true)
            for k in ks where !k.longPress.isEmpty {
                let p = LongPressPanel(key: k, width: w)
                XCTAssertEqual(p.options.count, k.longPress.count + 1)
                XCTAssertGreaterThanOrEqual(p.cells.map(\.minX).min()!, KeyLayout.margin - 0.01)
                XCTAssertLessThanOrEqual(p.cells.map(\.maxX).max()!, w - KeyLayout.margin + 0.01)
                XCTAssertGreaterThanOrEqual(p.cells[0].minY, 0)
                XCTAssertLessThanOrEqual(p.cells[0].maxY, k.rect.minY)
                XCTAssertEqual(p.index(at: k.rect.midX), 0, "\(k.action)")  // release without sliding: the key itself
            }
        }
        let base = KeyLayout.keys(width: w, page: .letters, upper: false, globe: true, bar: [], khmer: true)
        let left = LongPressPanel(key: key(.char("១"), in: base), width: w)
        XCTAssertEqual(left.options, ["១", "1", "៱"])
        XCTAssertEqual(left.cells[0].minX, KeyLayout.margin, accuracy: 0.01)  // shifted in from the edge
        XCTAssertLessThan(left.cells[0].minX, left.cells[1].minX)
        let right = LongPressPanel(key: key(.char("ឪ"), in: base), width: w)
        XCTAssertEqual(right.options, ["ឪ", "ឧ", "ឱ", "ឳ", "ឩ", "ឨ"])
        XCTAssertEqual(right.cells[0].maxX, w - KeyLayout.margin, accuracy: 0.01)
        XCTAssertTrue(zip(right.cells, right.cells.dropFirst()).allSatisfy { $0.minX > $1.minX })  // runs leftward
    }

    func testPanelIndexIsTheCellUnderTheFingerClampedAtTheEnds() {
        func panel(x: CGFloat, width: CGFloat) -> LongPressPanel {
            LongPressPanel(key: Key(action: .char("ក"), rect: CGRect(x: x, y: 100, width: 30, height: 43), longPress: ["a", "b"]),
                           width: width)
        }
        let p = panel(x: 100, width: 400)  // cells 38 wide
        XCTAssertEqual(p.cells.map(\.minX), [96, 134, 172])
        XCTAssertEqual(p.cells[0].minY, 100 - LongPressPanel.cellHeight - 4)
        XCTAssertEqual(p.index(at: 115), 0)
        XCTAssertEqual(p.index(at: 171), 1)
        XCTAssertEqual(p.index(at: 173), 2)
        XCTAssertEqual(p.index(at: -999), 0)
        XCTAssertEqual(p.index(at: 999), 2)
        XCTAssertEqual(panel(x: 100, width: 200).cells.map(\.minX), [96, 58, 20])  // right half: leftward
        XCTAssertEqual(panel(x: 0, width: 400).cells.map(\.minX), [6, 44, 82])  // past the left margin: shifted in
        XCTAssertEqual(panel(x: 40, width: 150).cells.map(\.minX), [30, 68, 106])  // overhangs the right: shifted in
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
