import XCTest

@testable import TyperCore

final class EmojiCatalogTests: XCTestCase {
    private let json = """
        [{"group":"Smileys & Emotion","emoji":[
          {"e":"😀","v":"1.0","n":"grinning face","k":["face","grin","happy"]},
          {"e":"🫨","v":"15.0","n":"shaking face","k":["earthquake"]},
          {"e":"🙂‍↔️","v":"15.1","n":"head shaking horizontally","k":["no"]}]},
         {"group":"People & Body","emoji":[
          {"e":"👋","v":"0.6","n":"waving hand","k":["hello","wave"],"t":["👋🏻","👋🏼","👋🏽","👋🏾","👋🏿"]},
          {"e":"🤝","v":"3.0","n":"handshake","k":["deal"],"t":["🤝🏻","🤝🏼","🤝🏽","🤝🏾","🤝🏿"]},
          {"e":"👍","v":"0.6","n":"thumbs up","k":["+1"],"t":["👍🏻","👍🏼","👍🏽","👍🏾","👍🏿"]}]},
         {"group":"Food & Drink","emoji":[
          {"e":"🍕","v":"0.6","n":"pizza","k":["cheese","slice"]}]},
         {"group":"Flags","emoji":[
          {"e":"🇫🇷","v":"0.6","n":"flag: France","k":["flag"]}]}]
        """

    private func catalog(_ max: Double = 16.0, store: EmojiStore = InMemoryEmojiStore()) -> EmojiCatalog {
        try! EmojiCatalog(data: Data(json.utf8), maxVersion: max, store: store)
    }

    func testSectionsInOrderWithSymbols() {
        let s = catalog().sections
        XCTAssertEqual(s.map(\.title), ["Smileys & Emotion", "People & Body", "Food & Drink", "Flags"])
        XCTAssertEqual(s.map(\.symbol), ["face.smiling", "person", "fork.knife", "flag"])
    }

    func testRecentsHiddenWhenEmptyThenFirst() {
        let c = catalog()
        XCTAssertNotEqual(c.sections.first?.title, "Recently Used")
        c.pick("🍕")
        XCTAssertEqual(c.sections.first, EmojiSection(title: "Recently Used", symbol: "clock", emoji: ["🍕"]))
    }

    func testVersionFiltering() {
        XCTAssertEqual(catalog(15.0).sections[0].emoji, ["😀", "🫨"])
        XCTAssertEqual(catalog(15.1).sections[0].emoji.count, 3)
        XCTAssertEqual(catalog(1.0).sections.map(\.title), ["Smileys & Emotion", "People & Body", "Food & Drink", "Flags"])
        XCTAssertEqual(catalog(1.0).sections[0].emoji, ["😀"])
        XCTAssertEqual(catalog(15.0).search("head"), [])
    }

    func testMaxEmojiVersion() {
        func v(_ a: Int, _ b: Int) -> Double {
            EmojiCatalog.maxEmojiVersion(iOS: OperatingSystemVersion(majorVersion: a, minorVersion: b, patchVersion: 0))
        }
        XCTAssertEqual(v(15, 0), 15.0)
        XCTAssertEqual(v(17, 0), 15.0)
        XCTAssertEqual(v(17, 3), 15.0)
        XCTAssertEqual(v(17, 4), 15.1)
        XCTAssertEqual(v(18, 3), 15.1)
        XCTAssertEqual(v(18, 4), 16.0)
        XCTAssertEqual(v(26, 0), 16.0)
    }

    func testRecentsCapNewestFirstDedupe() {
        let store = InMemoryEmojiStore()
        let c = catalog(store: store)
        for i in 0..<40 { c.pick("x\(i)") }
        XCTAssertEqual(store.recents.count, 32)
        XCTAssertEqual(store.recents.first, "x39")
        c.pick("x20")
        XCTAssertEqual(store.recents.first, "x20")
        XCTAssertEqual(store.recents.filter { $0 == "x20" }.count, 1)
        XCTAssertEqual(store.recents.count, 32)
    }

    func testRecentsPersistThroughStore() {
        let store = InMemoryEmojiStore()
        catalog(store: store).pick("🍕")
        XCTAssertEqual(catalog(store: store).sections.first?.emoji, ["🍕"])
    }

    func testToneMemoryShownPerEmojiOnly() {
        let c = catalog()
        c.pick("👋🏽")
        let people = c.sections.first { $0.title == "People & Body" }!
        XCTAssertEqual(people.emoji, ["👋🏽", "🤝", "👍"])
        XCTAssertEqual(c.sections.first?.emoji, ["👋🏽"])  // Recents as picked
        c.pick("👋")
        XCTAssertEqual(c.sections.first { $0.title == "People & Body" }!.emoji, ["👋", "🤝", "👍"])
    }

    func testTones() {
        let c = catalog()
        XCTAssertEqual(c.tones(for: "😀"), [])
        XCTAssertEqual(c.tones(for: "👋"), ["👋", "👋🏻", "👋🏼", "👋🏽", "👋🏾", "👋🏿"])
        XCTAssertEqual(c.tones(for: "👋🏾"), c.tones(for: "👋"))
        XCTAssertEqual(c.tones(for: "🤝").count, 6)
        XCTAssertEqual(c.tones(for: "🤝")[3], "🤝🏽")
    }

    func testSearch() {
        let c = catalog()
        XCTAssertEqual(c.search("pizz"), ["🍕"])
        XCTAssertEqual(c.search("  GRIN "), ["😀"])
        XCTAssertEqual(c.search("slice"), ["🍕"])
        XCTAssertEqual(c.search("zzz"), [])
        XCTAssertEqual(c.search(""), [])
        XCTAssertEqual(c.search("   "), [])
        XCTAssertEqual(c.search("izza"), [])  // prefix of a word, not substring
    }

    func testSearchNameMatchesFirstAndShowsTone() {
        let c = catalog()
        XCTAssertEqual(c.search("ha"), ["👋", "🤝", "😀"])  // name hit before keyword hit
        c.pick("👍🏿")
        XCTAssertEqual(c.search("thumbs"), ["👍🏿"])
    }

    func testRealBundledData() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("../../../../data/out/emoji.json").standardized
        let c = try EmojiCatalog(data: try Data(contentsOf: url), maxVersion: 16.0, store: InMemoryEmojiStore())
        XCTAssertEqual(c.sections.first?.title, "Smileys & Emotion")
        XCTAssertEqual(c.sections.first?.emoji.first, "😀")
        XCTAssertTrue(c.search("pizza").contains("🍕"))
        XCTAssertEqual(c.tones(for: "👍").count, 6)
    }
}
