import XCTest

@testable import TyperCore

final class ClipListTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let store = InMemoryClipStore()
    var clips: ClipList { ClipList(store: store) }
    func texts(_ now: Date) -> [String] { clips.list(now: now).map(\.text) }

    func testNewestFirstAndDuplicateMovesToTop() {
        clips.add("a", now: t0); clips.add("b", now: t0 + 1); clips.add("a", now: t0 + 2)
        XCTAssertEqual(texts(t0 + 3), ["a", "b"])
    }

    func testBlankIsIgnored() {
        clips.add("", now: t0); clips.add(" \n\t ", now: t0)
        XCTAssertEqual(texts(t0), [])
    }

    func testLongTextIsCutAt5000() {
        clips.add(String(repeating: "x", count: 6_000), now: t0)
        XCTAssertEqual(texts(t0).first?.count, 5_000)
    }

    func testAtMostTenKeepsTheNewest() {
        for i in 0..<12 { clips.add("c\(i)", now: t0 + Double(i)) }
        XCTAssertEqual(texts(t0 + 12), (2..<12).reversed().map { "c\($0)" })
    }

    func testExpiresAnHourAfterFirstNoticedAndIsPrunedOnRead() {
        clips.add("old", now: t0); clips.add("new", now: t0 + 1_800)
        XCTAssertEqual(texts(t0 + 3_600), ["new", "old"])
        XCTAssertEqual(texts(t0 + 3_601), ["new"])
        XCTAssertEqual(store.clips.count, 1)
        XCTAssertEqual(texts(t0 + 5_401), [])
    }

    func testClearAll() {
        clips.add("a", now: t0)
        clips.clearAll()
        XCTAssertEqual(texts(t0), [])
    }

    func testLineCollapsesWhitespace() {
        XCTAssertEqual(Clip(text: "  a \n\n b\t c ", at: t0).line, "a b c")
    }

    func testFileStoreRoundTrips() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clips-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        ClipList(store: FileClipStore(url: url)).add("hi", now: t0)
        XCTAssertEqual(ClipList(store: FileClipStore(url: url)).list(now: t0).map(\.text), ["hi"])
    }

    func testPinnedFirstMostRecentlyPinnedFirst() {
        clips.add("a", now: t0); clips.add("b", now: t0 + 1); clips.add("c", now: t0 + 2)
        clips.pin("a", now: t0 + 3); clips.pin("c", now: t0 + 4)
        XCTAssertEqual(texts(t0 + 5), ["c", "a", "b"])
        XCTAssertEqual(clips.list(now: t0 + 5).map(\.isPinned), [true, true, false])
    }

    func testPinnedNeverExpireAndSurviveTheCap() {
        clips.add("p", now: t0); clips.pin("p", now: t0)
        for i in 0..<12 { clips.add("c\(i)", now: t0 + Double(i)) }
        XCTAssertEqual(texts(t0 + 12).count, 11)
        XCTAssertEqual(texts(t0 + 100_000), ["p"])
    }

    func testNoCapOnPins() {
        for i in 0..<15 { clips.add("c\(i)", now: t0); clips.pin("c\(i)", now: t0 + Double(i)) }
        XCTAssertEqual(texts(t0 + 20).count, 15)
    }

    func testClearAllKeepsPins() {
        clips.add("a", now: t0); clips.add("b", now: t0); clips.pin("a", now: t0)
        clips.clearAll()
        XCTAssertEqual(texts(t0), ["a"])
    }

    func testCopyEqualToPinnedAddsNothingAndKeepsPlace() {
        clips.add("a", now: t0); clips.add("b", now: t0); clips.pin("a", now: t0); clips.pin("b", now: t0 + 1)
        clips.add("a", now: t0 + 2)
        XCTAssertEqual(texts(t0 + 3), ["b", "a"])
    }

    func testUnpinReturnsToTopOfRecentWithFreshHour() {
        clips.add("a", now: t0); clips.pin("a", now: t0); clips.add("b", now: t0 + 1)
        clips.unpin("a", now: t0 + 120)  // b is no longer the Fresh clip
        XCTAssertEqual(texts(t0 + 123), ["a", "b"])
        XCTAssertEqual(clips.list(now: t0 + 123).map(\.isPinned), [false, false])
        XCTAssertEqual(texts(t0 + 120 + 3_601), [])
    }

    func testUnpinStaysBelowTheFreshClip() {
        clips.add("a", now: t0); clips.pin("a", now: t0); clips.add("b", now: t0 + 1)
        clips.unpin("a", now: t0 + 2)
        XCTAssertEqual(texts(t0 + 3), ["b", "a"])
    }

    func testDeleteRemovesPinnedOrRecent() {
        clips.add("a", now: t0); clips.add("b", now: t0); clips.pin("a", now: t0)
        clips.delete("a"); clips.delete("b")
        XCTAssertEqual(texts(t0), [])
    }

    func testFileStoreKeepsPinsAndLoadsOldFileWithoutThem() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clips-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONEncoder().encode([OldClip(text: "old", at: t0)]).write(to: url)
        let list = ClipList(store: FileClipStore(url: url))
        XCTAssertEqual(list.list(now: t0).map(\.isPinned), [false])
        list.pin("old", now: t0 + 1)
        XCTAssertEqual(ClipList(store: FileClipStore(url: url)).list(now: t0 + 100_000).map(\.text), ["old"])
    }
    private struct OldClip: Codable { let text: String; let at: Date }
}

extension ClipListTests {
    func testFreshForAMinuteThenNot() {
        clips.add("a", now: t0)
        XCTAssertEqual(clips.fresh(now: t0 + 59)?.text, "a")
        XCTAssertNil(clips.fresh(now: t0 + 60))
    }

    func testFreshIsTheNewestAndEndsOncePasted() {
        clips.add("a", now: t0); clips.add("b", now: t0 + 1)
        XCTAssertEqual(clips.fresh(now: t0 + 2)?.text, "b")
        clips.markUsed("b", now: t0 + 3)
        XCTAssertNil(clips.fresh(now: t0 + 4))  // not the older one either
        clips.add("b", now: t0 + 5)  // copied again: fresh again
        XCTAssertEqual(clips.fresh(now: t0 + 6)?.text, "b")
    }

    func testUsedSurvivesANewListOverTheSameStore() {
        clips.add("a", now: t0); clips.markUsed("a", now: t0 + 1)
        XCTAssertNil(ClipList(store: store).fresh(now: t0 + 2))
    }

    func testPinnedDuplicateIsNotFresh() {
        clips.add("a", now: t0); clips.pin("a", now: t0 + 1)
        clips.add("a", now: t0 + 2)
        XCTAssertNil(clips.fresh(now: t0 + 3))
    }

    func testWipeDeletesEverything() {
        clips.add("a", now: t0)
        clips.wipe()
        XCTAssertEqual(texts(t0), [])
    }

    func testFileStoreWipeRemovesFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clips-\(UUID()).json")
        let list = ClipList(store: FileClipStore(url: url))
        list.add("a", now: t0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        list.wipe()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(list.list(now: t0), [])
    }

    func testSettingIsOnWhenAbsent() {
        let d = UserDefaults(suiteName: "test-\(UUID())")!
        XCTAssertTrue(ClipSettings.isOn(d))
        XCTAssertTrue(ClipSettings.isOn(nil))
        d.set(false, forKey: ClipSettings.key)
        XCTAssertFalse(ClipSettings.isOn(d))
    }

    func testUnpinnedClipIsNotFresh() {
        let l = ClipList(store: InMemoryClipStore())
        let t0 = Date(timeIntervalSince1970: 1000)
        l.add("old", now: t0)
        l.add("new", now: t0.addingTimeInterval(1))
        l.pin("old", now: t0.addingTimeInterval(2))
        l.unpin("old", now: t0.addingTimeInterval(3))
        XCTAssertEqual(l.fresh(now: t0.addingTimeInterval(4))?.text, "new")
    }
}
