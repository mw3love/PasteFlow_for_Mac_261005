import XCTest
@testable import PasteFlowCore

final class AnnotationTests: XCTestCase {
    private func rect(_ r: CGRect) -> Annotation { Annotation(shape: .rect(r), color: 0xFF0000, size: 4) }
    private func badge(_ n: Int) -> Annotation { Annotation(shape: .badge(center: .zero, number: n), color: 0xFF0000, size: 30) }

    func testDigitsFollowWindowsOrder() {
        XCTAssertEqual(AnnotationTool.forDigit(1), .select)
        XCTAssertEqual(AnnotationTool.forDigit(2), .rect)
        XCTAssertEqual(AnnotationTool.forDigit(3), .text)
        XCTAssertEqual(AnnotationTool.forDigit(4), .arrow)
        XCTAssertEqual(AnnotationTool.forDigit(8), .badge)
        XCTAssertNil(AnnotationTool.forDigit(0))
        XCTAssertNil(AnnotationTool.forDigit(9))
        XCTAssertEqual(AnnotationTool.pen.digit, 7)
    }

    // MARK: 되돌리기

    func testUndoRedoAddAndRemove() {
        let doc = AnnotationDocument()
        let id = doc.add(rect(CGRect(x: 0, y: 0, width: 10, height: 10)))
        doc.add(badge(1))
        XCTAssertEqual(doc.items.count, 2)
        doc.remove(id)
        XCTAssertEqual(doc.items.count, 1)
        XCTAssertTrue(doc.undo())
        XCTAssertEqual(doc.items.count, 2)
        XCTAssertTrue(doc.undo())
        XCTAssertTrue(doc.undo())
        XCTAssertTrue(doc.isEmpty)
        XCTAssertFalse(doc.undo())
        XCTAssertTrue(doc.redo())
        XCTAssertEqual(doc.items.count, 1)
    }

    func testDragIsOneUndoStep() {
        let doc = AnnotationDocument()
        let id = doc.add(rect(CGRect(x: 0, y: 0, width: 10, height: 10)))
        doc.begin()
        for i in 1...5 { doc.update(doc.item(id)!.moved(by: CGVector(dx: CGFloat(i), dy: 0))) }
        doc.end()
        XCTAssertTrue(doc.undo())
        XCTAssertEqual(doc.item(id)?.bounds.minX, -2)   // 처음 자리(획 반폭만큼 바깥)
        XCTAssertTrue(doc.undo())
        XCTAssertTrue(doc.isEmpty)
    }

    func testUnchangedGroupLeavesNoUndo() {
        let doc = AnnotationDocument()
        doc.begin()
        let id = doc.add(rect(.zero))
        doc.remove(id)   // 너무 작게 끌어 버린 도형
        doc.end()
        XCTAssertFalse(doc.canUndo)
    }

    func testNewEditClearsRedo() {
        let doc = AnnotationDocument()
        doc.add(badge(1))
        doc.undo()
        XCTAssertTrue(doc.canRedo)
        doc.add(badge(1))
        XCTAssertFalse(doc.canRedo)
    }

    // MARK: 번호

    func testBadgeNumbersIncrementAndFollowUndo() {
        let doc = AnnotationDocument()
        XCTAssertEqual(doc.nextBadgeNumber, 1)
        doc.add(badge(doc.nextBadgeNumber))
        doc.add(rect(.zero))
        doc.add(badge(doc.nextBadgeNumber))
        XCTAssertEqual(doc.nextBadgeNumber, 3)
        doc.undo()
        XCTAssertEqual(doc.nextBadgeNumber, 2)
    }

    // MARK: 클릭 판정

    func testRectHitOnStrokeOnlyUnlessInterior() {
        let a = rect(CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertTrue(a.contains(CGPoint(x: 1, y: 50), tolerance: 3, interior: false))
        XCTAssertFalse(a.contains(CGPoint(x: 50, y: 50), tolerance: 3, interior: false))
        XCTAssertTrue(a.contains(CGPoint(x: 50, y: 50), tolerance: 3, interior: true))
        XCTAssertFalse(a.contains(CGPoint(x: 120, y: 50), tolerance: 3, interior: true))
    }

    func testEllipseAndLineHit() {
        let e = Annotation(shape: .ellipse(CGRect(x: 0, y: 0, width: 100, height: 50)), color: 0, size: 4)
        XCTAssertTrue(e.contains(CGPoint(x: 100, y: 25), tolerance: 2, interior: false))
        XCTAssertFalse(e.contains(CGPoint(x: 50, y: 25), tolerance: 2, interior: false))
        XCTAssertFalse(e.contains(CGPoint(x: 99, y: 2), tolerance: 2, interior: true))   // 모서리 바깥
        let l = Annotation(shape: .line(.zero, CGPoint(x: 100, y: 0)), color: 0, size: 4)
        XCTAssertTrue(l.contains(CGPoint(x: 50, y: 3), tolerance: 2, interior: false))
        XCTAssertFalse(l.contains(CGPoint(x: 50, y: 8), tolerance: 2, interior: false))
        XCTAssertFalse(l.contains(CGPoint(x: 110, y: 0), tolerance: 2, interior: false))
    }

    func testTopmostPrefersLaterItem() {
        let doc = AnnotationDocument()
        doc.add(rect(CGRect(x: 0, y: 0, width: 100, height: 100)))
        let top = doc.add(Annotation(shape: .badge(center: CGPoint(x: 50, y: 50), number: 1), color: 0, size: 30))
        XCTAssertEqual(doc.topmost(at: CGPoint(x: 50, y: 50), tolerance: 2, interior: true)?.id, top)
        XCTAssertNil(doc.topmost(at: CGPoint(x: 300, y: 300), tolerance: 2, interior: true))
    }

    // MARK: 손잡이·이동

    func testRectResizeKeepsTopLeftAndShiftMakesSquare() {
        let a = rect(CGRect(x: 10, y: 10, width: 20, height: 20))
        XCTAssertEqual(a.resized(.resize, to: CGPoint(x: 60, y: 40), constrain: false).shape, .rect(CGRect(x: 10, y: 10, width: 50, height: 30)))
        XCTAssertEqual(a.resized(.resize, to: CGPoint(x: 60, y: 40), constrain: true).shape, .rect(CGRect(x: 10, y: 10, width: 50, height: 50)))
    }

    func testLineEndpointSnap45() {
        let a = Annotation(shape: .arrow(.zero, CGPoint(x: 10, y: 0)), color: 0, size: 2)
        guard case .arrow(let s, let e) = a.resized(.end, to: CGPoint(x: 100, y: 90), constrain: true).shape else { return XCTFail() }
        XCTAssertEqual(s, .zero)
        XCTAssertEqual(e.x, e.y, accuracy: 0.001)
    }

    func testBadgeAndTextResize() {
        let b = Annotation(shape: .badge(center: CGPoint(x: 50, y: 50), number: 1), color: 0, size: 30)
        XCTAssertEqual(b.resized(.resize, to: CGPoint(x: 70, y: 60), constrain: false).size, 40)
        XCTAssertEqual(b.resized(.resize, to: CGPoint(x: 500, y: 500), constrain: false).size, 120)
        let t = Annotation(shape: .text(origin: .zero, string: "가", measured: CGSize(width: 20, height: 20)), color: 0, size: 16)
        let big = t.resized(.resize, to: CGPoint(x: 40, y: 40), constrain: false)
        XCTAssertEqual(big.size, 32)
        XCTAssertEqual(big.bounds.size, CGSize(width: 40, height: 40))
    }

    func testMoveShiftsEveryPoint() {
        let p = Annotation(shape: .pen([.zero, CGPoint(x: 5, y: 5)]), color: 0, size: 2)
        XCTAssertEqual(p.moved(by: CGVector(dx: 1, dy: 2)).shape, .pen([CGPoint(x: 1, y: 2), CGPoint(x: 6, y: 7)]))
    }

    func testArrowBoundsIncludeHead() {
        let a = Annotation(shape: .arrow(CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50)), color: 0, size: 6)
        XCTAssertGreaterThan(a.bounds.height, 20)   // 화살촉이 위아래로 튀어나옴
    }

    // MARK: 도구별 기본값

    func testDefaultsPerToolAndJSONRoundTrip() {
        var d = AnnotationDefaults()
        XCTAssertEqual(d.style(for: .rect).size, 6)
        XCTAssertEqual(d.style(for: .text).size, 16)
        XCTAssertEqual(d.style(for: .badge).size, 30)
        d.set(.init(color: 0x007AFF, size: 99), for: .arrow)
        XCTAssertEqual(d.style(for: .arrow).size, 40)   // 범위로 자름
        XCTAssertEqual(d.style(for: .rect).color, 0xFF3B30)   // 다른 도구는 그대로
        let back = AnnotationDefaults.from(json: d.json())
        XCTAssertEqual(back, d)
        XCTAssertEqual(AnnotationDefaults.from(json: "깨진 값"), AnnotationDefaults())
    }
}
