import XCTest
@testable import PasteFlowCore

final class PasteQueueTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000)
    private func makeQueue(idle: TimeInterval = 10) -> PasteQueue {
        PasteQueue(idleResetSec: idle, clock: { [unowned self] in self.now })
    }
    private func item(_ id: Int64) -> ClipItem {
        ClipItem(id: id, kind: .text, formats: [:], previewText: "\(id)")
    }

    func testAccumulatesWithinIdleWindow() {
        let q = makeQueue()
        q.add(item(1)); now += 3
        q.add(item(2)); now += 3
        q.add(item(3))
        XCTAssertEqual(q.status.total, 3)
        XCTAssertEqual(q.items.map(\.id), [1, 2, 3])
    }

    func testIdleExpiryStartsNewBatch() {
        let q = makeQueue()
        q.add(item(1)); now += 3
        q.add(item(2)); now += 10   // 정확히 idle 값만큼 지나도 리셋(>=)
        q.add(item(3))
        XCTAssertEqual(q.items.map(\.id), [3])
    }

    func testGetNextAdvancesInCopyOrderThenExhausts() {
        let q = makeQueue()
        q.add(item(1)); q.add(item(2))
        XCTAssertEqual(q.next()?.id, 1)
        XCTAssertEqual(q.status.pointer, 1)
        XCTAssertEqual(q.next()?.id, 2)
        XCTAssertTrue(q.isExhausted)
        XCTAssertNil(q.next())
    }

    func testCopyAfterPastingStartedResetsQueue() {
        let q = makeQueue()
        q.add(item(1)); q.add(item(2))
        _ = q.next()
        q.add(item(3))   // pointer > 0 이면 새 묶음
        XCTAssertEqual(q.items.map(\.id), [3])
        XCTAssertEqual(q.status.pointer, 0)
    }

    func testPlainPasteClearsQueue() {
        let q = makeQueue()
        q.add(item(1)); q.add(item(2))
        q.markPlainPaste()
        XCTAssertEqual(q.status.total, 0)
        XCTAssertNil(q.next())
    }

    func testRemoveBeforePointerShiftsPointer() {
        let q = makeQueue()
        q.add(item(1)); q.add(item(2)); q.add(item(3))
        _ = q.next(); _ = q.next()          // pointer = 2
        XCTAssertTrue(q.remove(id: 1))
        XCTAssertEqual(q.status.pointer, 1)
        XCTAssertEqual(q.next()?.id, 3)
    }

    func testRemoveAfterPointerKeepsPointer() {
        let q = makeQueue()
        q.add(item(1)); q.add(item(2)); q.add(item(3))
        _ = q.next()                         // pointer = 1
        XCTAssertTrue(q.remove(id: 3))
        XCTAssertEqual(q.status.pointer, 1)
        XCTAssertEqual(q.status.total, 2)
        XCTAssertFalse(q.remove(id: 99))
    }

    func testIdleChangeAppliesImmediately() {
        let q = makeQueue(idle: 10)
        q.add(item(1)); now += 5
        q.idleResetSec = 4
        q.add(item(2))
        XCTAssertEqual(q.items.map(\.id), [2])
    }
}
