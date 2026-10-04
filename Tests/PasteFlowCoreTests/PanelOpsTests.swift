import XCTest
@testable import PasteFlowCore

/// 패널 동작(큐 지정·고정 순서·글자 수정) — 윈도우판 규칙 그대로.
final class PanelOpsTests: XCTestCase {
    private func text(_ s: String) -> ClipItem {
        ClipItem(kind: .text, formats: ["public.utf8-plain-text": Data(s.utf8)], previewText: s)
    }

    // MARK: 큐 지정(C)

    func testHistorySelectionQueuesFromSelectedToNewest() {
        // 히스토리는 최신 먼저: [5, 4, 3, 2, 1]. 3을 고르면 3 → 4 → 5 순서
        XCTAssertEqual(QueueSelection.ids(for: 3, history: [5, 4, 3, 2, 1], pinned: [9]), [3, 4, 5])
        XCTAssertEqual(QueueSelection.ids(for: 5, history: [5, 4, 3], pinned: []), [5])
    }

    func testPinnedSelectionQueuesFromSelectedBackToFirstPin() {
        // 고정 [10, 11, 12]에서 12를 고르면 12 → 11 → 10(윈도우판과 같은 역순)
        XCTAssertEqual(QueueSelection.ids(for: 12, history: [1], pinned: [10, 11, 12]), [12, 11, 10])
        XCTAssertEqual(QueueSelection.ids(for: 10, history: [], pinned: [10, 11]), [10])
    }

    func testUnknownSelectionIsNil() {
        XCTAssertNil(QueueSelection.ids(for: 99, history: [1], pinned: [2]))
    }

    func testReplaceStartsQueueFromFirst() {
        let q = PasteQueue()
        q.add(text("old"))
        _ = q.next()
        var a = text("a"); a.id = 1
        var b = text("b"); b.id = 2
        q.replace(with: [a, b])
        XCTAssertEqual(q.status.pointer, 0)
        XCTAssertEqual(q.status.total, 2)
        XCTAssertEqual(q.next()?.id, 1)
        XCTAssertEqual(q.next()?.id, 2)
        XCTAssertNil(q.next())
    }

    // MARK: 고정 순서

    func testSetPinOrderReordersPinned() throws {
        let db = try ClipDatabase(path: ":memory:")
        let a = try db.insert(text("a")), b = try db.insert(text("b")), c = try db.insert(text("c"))
        for id in [a, b, c] { try db.setPinned(id: id, true) }
        try db.setPinOrder([c, a, b])
        XCTAssertEqual(try db.pinned(withFormats: false).compactMap(\.id), [c, a, b])
        // 새로 고정하면 맨 뒤
        let d = try db.insert(text("d"))
        try db.setPinned(id: d, true)
        XCTAssertEqual(try db.pinned(withFormats: false).compactMap(\.id), [c, a, b, d])
    }

    func testPinOrderInsertMovesBeforeTarget() {
        // [1,2,3,4]에서 4를 2 앞으로 → [1,4,2,3]; 1을 맨 뒤(nil)로 → [2,3,4,1]
        XCTAssertEqual(PinOrder.moving(4, before: 2, in: [1, 2, 3, 4]), [1, 4, 2, 3])
        XCTAssertEqual(PinOrder.moving(1, before: nil, in: [1, 2, 3, 4]), [2, 3, 4, 1])
        // 목록에 없던 항목(히스토리에서 끌어온 것)은 그 자리에 끼운다
        XCTAssertEqual(PinOrder.moving(9, before: 3, in: [1, 2, 3]), [1, 2, 9, 3])
        // 자기 자신 앞 = 그대로
        XCTAssertEqual(PinOrder.moving(2, before: 2, in: [1, 2, 3]), [1, 2, 3])
    }

    // MARK: 글자 수정

    func testUpdateTextReplacesFormatsWithPlainText() throws {
        let db = try ClipDatabase(path: ":memory:")
        var item = text("hello")
        item.formats["public.html"] = Data("<b>hello</b>".utf8)
        item.kind = .html
        let id = try db.insert(item)
        try db.setPinned(id: id, true)
        try db.updateText(id: id, "안녕\n두 번째 줄")
        let back = try XCTUnwrap(db.item(id: id))
        XCTAssertEqual(back.kind, .text)
        XCTAssertEqual(back.formats, ["public.utf8-plain-text": Data("안녕\n두 번째 줄".utf8)])
        XCTAssertEqual(back.previewText, "안녕\n두 번째 줄")
        XCTAssertTrue(back.isPinned)
    }

    func testSavedImagePathRoundTrips() throws {
        let db = try ClipDatabase(path: ":memory:")
        var item = ClipItem(kind: .image, formats: ["public.png": Data([1])], previewText: "이미지")
        item.savedImagePath = "/tmp/clip.png"
        let id = try db.insert(item)
        XCTAssertEqual(try db.recent(withFormats: false).first { $0.id == id }?.savedImagePath, "/tmp/clip.png")
    }
}
