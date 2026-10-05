import Foundation
import SQLite3

public struct ClipDatabaseError: Error, CustomStringConvertible {
    public let description: String
}

/// SQLite 저장소. 히스토리(고정 제외 최대 `historyMax`개, 오래된 것부터 삭제) + 고정 항목 + 설정.
public final class ClipDatabase {
    public static let defaultHistoryMax = 50

    private var db: OpaquePointer?
    /// 고정 제외 히스토리 최대 개수(설정 `history_max`, 윈도우판과 같은 키). 바꾸려면 `setHistoryMax`.
    public private(set) var historyMax: Int
    public static let historyMaxKey = "history_max"
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(path: String, historyMax: Int = ClipDatabase.defaultHistoryMax) throws {
        self.historyMax = historyMax
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw ClipDatabaseError(description: "DB 열기 실패: \(path)")
        }
        try exec("PRAGMA foreign_keys = ON")
        try exec("""
            CREATE TABLE IF NOT EXISTS clip_items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind TEXT NOT NULL,
                preview_text TEXT NOT NULL,
                thumbnail BLOB,
                created_at REAL NOT NULL,
                is_pinned INTEGER NOT NULL DEFAULT 0,
                pin_order INTEGER NOT NULL DEFAULT 0,
                saved_image_path TEXT
            );
            CREATE TABLE IF NOT EXISTS clip_formats (
                item_id INTEGER NOT NULL REFERENCES clip_items(id) ON DELETE CASCADE,
                type TEXT NOT NULL,
                data BLOB NOT NULL,
                PRIMARY KEY (item_id, type)
            );
            CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            """)
        try migrateHistoryOrder()
    }

    /// 히스토리 표시 순서 열(윈도우판 `history_order` — 작을수록 위). 옛 DB는 id 역순(최신 위)으로 채운다.
    private func migrateHistoryOrder() throws {
        var has = false
        try step("PRAGMA table_info(clip_items)", []) { stmt in
            if String(cString: sqlite3_column_text(stmt, 1)) == "history_order" { has = true }
        }
        guard !has else { return }
        try exec("ALTER TABLE clip_items ADD COLUMN history_order INTEGER")
        try exec("UPDATE clip_items SET history_order = -id")
    }

    deinit { sqlite3_close(db) }

    // MARK: 항목

    @discardableResult
    public func insert(_ item: ClipItem) throws -> Int64 {
        try exec("BEGIN")
        do {
            try run("""
                INSERT INTO clip_items (kind, preview_text, thumbnail, created_at, is_pinned, pin_order, saved_image_path, history_order)
                VALUES (?, ?, ?, ?, ?, ?, ?, (SELECT COALESCE(MIN(history_order), 0) - 1 FROM clip_items))
                """, [item.kind.rawValue, item.previewText, item.thumbnail, item.createdAt.timeIntervalSince1970,
                      item.isPinned ? 1 : 0, item.pinOrder, item.savedImagePath])
            let id = sqlite3_last_insert_rowid(db)
            for (type, data) in item.formats {
                try run("INSERT INTO clip_formats (item_id, type, data) VALUES (?, ?, ?)", [id, type, data])
            }
            try trimHistory()
            try exec("COMMIT")
            return id
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    public func item(id: Int64) throws -> ClipItem? {
        try query("SELECT * FROM clip_items WHERE id = ?", [id]).first
    }

    /// 고정 안 된 히스토리, 표시 순서대로(새 복사·맨 위로 올린 것이 먼저). 패널 목록처럼 원본이 필요 없으면 `withFormats: false`(큰 이미지 원본을 안 읽음).
    public func recent(limit: Int? = nil, withFormats: Bool = true) throws -> [ClipItem] {
        try query("SELECT * FROM clip_items WHERE is_pinned = 0 ORDER BY history_order, id DESC LIMIT ?", [limit ?? historyMax], withFormats: withFormats)
    }

    /// 고정 항목, 고정한 순서대로.
    public func pinned(withFormats: Bool = true) throws -> [ClipItem] {
        try query("SELECT * FROM clip_items WHERE is_pinned = 1 ORDER BY pin_order, id", [], withFormats: withFormats)
    }

    /// 고정 해제된 것까지 포함해 히스토리를 모두 지운다(고정 항목은 남김).
    public func clearHistory() throws {
        try run("DELETE FROM clip_items WHERE is_pinned = 0", [])
    }

    public func setPinned(id: Int64, _ pinned: Bool) throws {
        if pinned {
            try run("""
                UPDATE clip_items SET is_pinned = 1,
                    pin_order = (SELECT COALESCE(MAX(pin_order), 0) + 1 FROM clip_items WHERE is_pinned = 1)
                WHERE id = ?
                """, [id])
        } else {
            try run("UPDATE clip_items SET is_pinned = 0, pin_order = 0 WHERE id = ?", [id])
            try trimHistory()
        }
    }

    /// 히스토리 맨 위로(패널에서 옛 항목을 복사하면 "맨 위 = 지금 클립보드"를 지키려고 — 윈도우판 `bump_history_to_top`). 고정 항목은 그대로.
    public func bumpToTop(id: Int64) throws {
        try run("""
            UPDATE clip_items SET history_order = (SELECT COALESCE(MIN(history_order), 0) - 1 FROM clip_items)
            WHERE id = ? AND is_pinned = 0
            """, [id])
    }

    /// 히스토리 표시 순서를 통째로 정한다(위에서부터). 끌어서 순서 바꾸기용.
    public func setHistoryOrder(_ ids: [Int64]) throws {
        try exec("BEGIN")
        do {
            // 지금 맨 위 값부터 아래로 이어 붙여, 이후 새 복사(MIN-1)가 여전히 맨 위로 오게 한다
            var top: Int64 = 0
            try step("SELECT COALESCE(MIN(history_order), 0) FROM clip_items", []) { top = sqlite3_column_int64($0, 0) }
            for (i, id) in ids.enumerated() {
                try run("UPDATE clip_items SET history_order = ? WHERE id = ? AND is_pinned = 0", [top + Int64(i), id])
            }
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    /// 히스토리 최대 개수를 바꾸고 넘치는 오래된 항목을 바로 지운다.
    public func setHistoryMax(_ n: Int) throws {
        historyMax = max(1, n)
        try trimHistory()
    }

    /// 고정 항목 순서를 통째로 정한다(앞에서부터 1, 2, 3…).
    public func setPinOrder(_ ids: [Int64]) throws {
        try exec("BEGIN")
        do {
            for (i, id) in ids.enumerated() {
                try run("UPDATE clip_items SET pin_order = ? WHERE id = ? AND is_pinned = 1", [i + 1, id])
            }
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    /// 글자 수정 — 원본 형식(HTML·RTF 등)은 버리고 평문 하나로 바꾼다(윈도우판 `update_item_text`와 같음).
    public func updateText(id: Int64, _ text: String) throws {
        let formats = [ClipClassifier.plainText: Data(text.utf8)]
        try exec("BEGIN")
        do {
            try run("UPDATE clip_items SET kind = ?, preview_text = ?, thumbnail = NULL WHERE id = ?",
                    [ClipItem.Kind.text.rawValue, ClipClassifier.preview(formats: formats, kind: .text), id])
            try run("DELETE FROM clip_formats WHERE item_id = ?", [id])
            try run("INSERT INTO clip_formats (item_id, type, data) VALUES (?, ?, ?)", [id, ClipClassifier.plainText, formats[ClipClassifier.plainText]!])
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    /// 글자 내용이 정확히 같은 항목을 지운다(고정 포함) — 비밀값이 히스토리에 남았을 때 정리용. 지운 id를 돌려준다.
    @discardableResult
    public func deleteItems(withPlainText text: String) throws -> [Int64] {
        let target = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return [] }
        var ids: [Int64] = []
        try step("SELECT item_id, data FROM clip_formats WHERE type = ?", [ClipClassifier.plainText]) { stmt in
            if let d = self.blob(stmt, 1), String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == target {
                ids.append(sqlite3_column_int64(stmt, 0))
            }
        }
        for id in ids { try delete(id: id) }
        return ids
    }

    public func delete(id: Int64) throws {
        try run("DELETE FROM clip_items WHERE id = ?", [id])
    }

    // MARK: 설정

    public func setting(_ key: String) throws -> String? {
        var result: String?
        try step("SELECT value FROM settings WHERE key = ?", [key]) { stmt in
            result = String(cString: sqlite3_column_text(stmt, 0))
        }
        return result
    }

    public func setSetting(_ key: String, _ value: String) throws {
        try run("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [key, value])
    }

    // MARK: 내부

    private func trimHistory() throws {
        try run("""
            DELETE FROM clip_items WHERE is_pinned = 0 AND id NOT IN
                (SELECT id FROM clip_items WHERE is_pinned = 0 ORDER BY id DESC LIMIT ?)
            """, [historyMax])
    }

    private func query(_ sql: String, _ params: [Any?], withFormats: Bool = true) throws -> [ClipItem] {
        var items: [ClipItem] = []
        try step(sql, params) { stmt in
            var item = ClipItem(
                id: sqlite3_column_int64(stmt, 0),
                kind: ClipItem.Kind(rawValue: String(cString: sqlite3_column_text(stmt, 1))) ?? .other,
                formats: [:],
                previewText: String(cString: sqlite3_column_text(stmt, 2)),
                thumbnail: self.blob(stmt, 3),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
                isPinned: sqlite3_column_int(stmt, 5) != 0,
                pinOrder: Int(sqlite3_column_int(stmt, 6)),
                savedImagePath: sqlite3_column_text(stmt, 7).map { String(cString: $0) })
            item.formats = [:]
            items.append(item)
        }
        for i in items.indices where withFormats {
            try step("SELECT type, data FROM clip_formats WHERE item_id = ?", [items[i].id]) { stmt in
                items[i].formats[String(cString: sqlite3_column_text(stmt, 0))] = self.blob(stmt, 1) ?? Data()
            }
        }
        return items
    }

    private func blob(_ stmt: OpaquePointer?, _ col: Int32) -> Data? {
        guard sqlite3_column_type(stmt, col) != SQLITE_NULL else { return nil }
        let n = Int(sqlite3_column_bytes(stmt, col))
        guard n > 0, let p = sqlite3_column_blob(stmt, col) else { return Data() }
        return Data(bytes: p, count: n)
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw lastError(sql) }
    }

    private func run(_ sql: String, _ params: [Any?]) throws {
        try step(sql, params) { _ in }
    }

    private func step(_ sql: String, _ params: [Any?], row: (OpaquePointer?) throws -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw lastError(sql) }
        defer { sqlite3_finalize(stmt) }
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case nil: sqlite3_bind_null(stmt, idx)
            case let v as Int: sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Int64: sqlite3_bind_int64(stmt, idx, v)
            case let v as Double: sqlite3_bind_double(stmt, idx, v)
            case let v as String: sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case let v as Data:
                _ = v.withUnsafeBytes { sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32(v.count), SQLITE_TRANSIENT) }
            default: throw ClipDatabaseError(description: "지원하지 않는 값: \(String(describing: p))")
            }
        }
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW { try row(stmt); continue }
            if rc == SQLITE_DONE { break }
            throw lastError(sql)
        }
    }

    private func lastError(_ sql: String) -> ClipDatabaseError {
        ClipDatabaseError(description: "\(String(cString: sqlite3_errmsg(db))) — \(sql.prefix(60))")
    }
}
