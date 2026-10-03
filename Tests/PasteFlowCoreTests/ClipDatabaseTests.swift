import XCTest
@testable import PasteFlowCore

final class ClipDatabaseTests: XCTestCase {
    private func text(_ s: String) -> ClipItem {
        ClipItem(kind: .text, formats: ["public.utf8-plain-text": Data(s.utf8)], previewText: s)
    }

    func testInsertAssignsIdAndRoundTripsFormats() throws {
        let db = try ClipDatabase(path: ":memory:")
        var item = text("hello")
        item.formats["public.html"] = Data("<b>hello</b>".utf8)
        item.thumbnail = Data([1, 2, 3])
        let id = try db.insert(item)
        let back = try XCTUnwrap(db.item(id: id))
        XCTAssertEqual(back.id, id)
        XCTAssertEqual(back.kind, .text)
        XCTAssertEqual(back.previewText, "hello")
        XCTAssertEqual(back.formats, item.formats)
        XCTAssertEqual(back.thumbnail, Data([1, 2, 3]))
    }

    func testRecentIsNewestFirst() throws {
        let db = try ClipDatabase(path: ":memory:")
        _ = try db.insert(text("a")); _ = try db.insert(text("b"))
        XCTAssertEqual(try db.recent().map(\.previewText), ["b", "a"])
    }

    func testHistoryCappedAtMaxButPinnedExcluded() throws {
        let db = try ClipDatabase(path: ":memory:", historyMax: 3)
        let pinnedId = try db.insert(text("pin"))
        try db.setPinned(id: pinnedId, true)
        for i in 1...5 { _ = try db.insert(text("h\(i)")) }
        XCTAssertEqual(try db.recent().map(\.previewText), ["h5", "h4", "h3"])
        XCTAssertEqual(try db.pinned().map(\.previewText), ["pin"])
    }

    func testPinnedOrderFollowsPinSequence() throws {
        let db = try ClipDatabase(path: ":memory:")
        let a = try db.insert(text("a")), b = try db.insert(text("b"))
        try db.setPinned(id: b, true)
        try db.setPinned(id: a, true)
        XCTAssertEqual(try db.pinned().map(\.previewText), ["b", "a"])
        try db.setPinned(id: b, false)
        XCTAssertEqual(try db.pinned().map(\.previewText), ["a"])
        XCTAssertEqual(try db.recent().map(\.previewText), ["b"])
    }

    func testListWithoutFormatsSkipsPayloadButKeepsSummary() throws {
        let db = try ClipDatabase(path: ":memory:")
        var item = text("big")
        item.thumbnail = Data([9])
        let id = try db.insert(item)
        let light = try XCTUnwrap(db.recent(withFormats: false).first)
        XCTAssertEqual(light.id, id)
        XCTAssertEqual(light.previewText, "big")
        XCTAssertEqual(light.thumbnail, Data([9]))
        XCTAssertTrue(light.formats.isEmpty)
        XCTAssertFalse(try XCTUnwrap(db.item(id: id)).formats.isEmpty)
    }

    func testClearHistoryKeepsPinned() throws {
        let db = try ClipDatabase(path: ":memory:")
        let p = try db.insert(text("pin")); try db.setPinned(id: p, true)
        _ = try db.insert(text("h"))
        try db.clearHistory()
        XCTAssertTrue(try db.recent().isEmpty)
        XCTAssertEqual(try db.pinned().count, 1)
    }

    func testDelete() throws {
        let db = try ClipDatabase(path: ":memory:")
        let id = try db.insert(text("x"))
        try db.delete(id: id)
        XCTAssertNil(try db.item(id: id))
    }

    func testSettingsRoundTrip() throws {
        let db = try ClipDatabase(path: ":memory:")
        XCTAssertNil(try db.setting("queue_idle_reset_sec"))
        try db.setSetting("queue_idle_reset_sec", "12")
        try db.setSetting("queue_idle_reset_sec", "15")
        XCTAssertEqual(try db.setting("queue_idle_reset_sec"), "15")
    }

    func testContentHashIgnoresFormatOrderButSeesContent() {
        let a = ClipItem.contentHash(["b": Data("2".utf8), "a": Data("1".utf8)])
        let b = ClipItem.contentHash(["a": Data("1".utf8), "b": Data("2".utf8)])
        let c = ClipItem.contentHash(["a": Data("1".utf8), "b": Data("3".utf8)])
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
