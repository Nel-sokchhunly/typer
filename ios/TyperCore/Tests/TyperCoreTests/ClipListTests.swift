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
}
