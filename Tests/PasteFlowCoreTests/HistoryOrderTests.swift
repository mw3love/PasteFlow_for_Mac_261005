import XCTest
import SQLite3
@testable import PasteFlowCore

/// 히스토리 표시 순서(윈도우판 `history_order`)·맨 위로 올리기·최대 개수.
final class HistoryOrderTests: XCTestCase {
    private func text(_ s: String) -> ClipItem {
        ClipItem(kind: .text, formats: ["public.utf8-plain-text": Data(s.utf8)], previewText: s)
    }
    private func ids(_ db: ClipDatabase) throws -> [Int64] { try db.recent(withFormats: false).compactMap(\.id) }

    func testNewItemsGoOnTop() throws {
        let db = try ClipDatabase(path: ":memory:")
        let a = try db.insert(text("a")), b = try db.insert(text("b")), c = try db.insert(text("c"))
        XCTAssertEqual(try ids(db), [c, b, a])
    }

    func testBumpMovesOldItemToTop() throws {
        let db = try ClipDatabase(path: ":memory:")
        let a = try db.insert(text("a")), b = try db.insert(text("b")), c = try db.insert(text("c"))
        try db.bumpToTop(id: a)
        XCTAssertEqual(try ids(db), [a, c, b])
        let d = try db.insert(text("d"))
        XCTAssertEqual(try ids(db), [d, a, c, b])
    }

    func testSetHistoryOrder() throws {
        let db = try ClipDatabase(path: ":memory:")
        let a = try db.insert(text("a")), b = try db.insert(text("b")), c = try db.insert(text("c"))
        try db.setHistoryOrder([b, a, c])
        XCTAssertEqual(try ids(db), [b, a, c])
        let d = try db.insert(text("d"))
        XCTAssertEqual(try ids(db), [d, b, a, c])
    }

    func testBumpIgnoresPinned() throws {
        let db = try ClipDatabase(path: ":memory:")
        let a = try db.insert(text("a")), b = try db.insert(text("b"))
        try db.setPinned(id: a, true)
        try db.bumpToTop(id: a)
        XCTAssertEqual(try ids(db), [b])
        XCTAssertEqual(try db.pinned(withFormats: false).compactMap(\.id), [a])
    }

    func testHistoryMaxTrimsOldestByCopyTime() throws {
        let db = try ClipDatabase(path: ":memory:", historyMax: 3)
        let a = try db.insert(text("a")), b = try db.insert(text("b")), c = try db.insert(text("c"))
        try db.bumpToTop(id: a)              // 표시 순서는 a가 위지만, 지울 땐 오래 복사된 것(id 순)부터 — 윈도우판과 같음
        let d = try db.insert(text("d"))
        XCTAssertEqual(try ids(db), [d, c, b])
        XCTAssertFalse(try ids(db).contains(a))
        XCTAssertEqual(Set(try ids(db)), [b, c, d])
    }

    func testChangingHistoryMaxTrimsImmediately() throws {
        let db = try ClipDatabase(path: ":memory:")
        for s in ["a", "b", "c", "d", "e"] { _ = try db.insert(text(s)) }
        try db.setHistoryMax(2)
        XCTAssertEqual(try db.recent(withFormats: false).map(\.previewText), ["e", "d"])
        XCTAssertEqual(db.historyMax, 2)
    }

    func testExistingDatabaseIsMigrated() throws {
        // history_order 열이 없던 옛 DB를 열어도 id 역순(최신 위)으로 보인다
        let path = NSTemporaryDirectory() + "pf-migrate-\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        var raw: OpaquePointer?
        sqlite3_open(path, &raw)
        sqlite3_exec(raw, """
            CREATE TABLE clip_items (id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, preview_text TEXT NOT NULL,
              thumbnail BLOB, created_at REAL NOT NULL, is_pinned INTEGER NOT NULL DEFAULT 0, pin_order INTEGER NOT NULL DEFAULT 0,
              saved_image_path TEXT);
            INSERT INTO clip_items (kind, preview_text, created_at) VALUES ('text','old1',0),('text','old2',0);
            """, nil, nil, nil)
        sqlite3_close(raw)
        let db = try ClipDatabase(path: path)
        let n = try db.insert(text("new"))
        XCTAssertEqual(try db.recent(withFormats: false).map(\.previewText), ["new", "old2", "old1"])
        try db.bumpToTop(id: 1)
        XCTAssertEqual(try db.recent(withFormats: false).map(\.previewText), ["old1", "new", "old2"])
        _ = n
    }
}
