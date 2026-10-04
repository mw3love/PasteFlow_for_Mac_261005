import XCTest
@testable import PasteFlowCore

final class ElementSnapTests: XCTestCase {
    private let win = CGRect(x: 100, y: 100, width: 800, height: 600)
    private func n(_ role: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> ElementSnap.Node {
        .init(role: role, rect: CGRect(x: x, y: y, width: w, height: h))
    }

    func testTitleBarSnapsWholeWindow() {
        let chain = [n("AXButton", 110, 105, 16, 16)]
        XCTAssertEqual(ElementSnap.choose(chain: chain, window: win, cursor: CGPoint(x: 115, y: 110)), win)
    }

    func testTextInsideButtonPicksButton() {
        let chain = [n("AXStaticText", 205, 205, 40, 14), n("AXButton", 200, 200, 60, 24), n("AXGroup", 100, 160, 800, 540)]
        XCTAssertEqual(ElementSnap.choose(chain: chain, window: win, cursor: CGPoint(x: 210, y: 210)),
                       CGRect(x: 200, y: 200, width: 60, height: 24))
    }

    func testPlainTextIsKept() {
        let chain = [n("AXStaticText", 205, 205, 300, 20), n("AXGroup", 100, 160, 800, 540)]
        XCTAssertEqual(ElementSnap.choose(chain: chain, window: win, cursor: CGPoint(x: 210, y: 210)),
                       CGRect(x: 205, y: 205, width: 300, height: 20))
    }

    func testTinyElementFallsToParent() {
        let chain = [n("AXGroup", 300, 300, 4, 30), n("AXGroup", 250, 280, 200, 100)]
        XCTAssertEqual(ElementSnap.choose(chain: chain, window: win, cursor: CGPoint(x: 301, y: 310)),
                       CGRect(x: 250, y: 280, width: 200, height: 100))
    }

    func testWindowSizedGroupIsWindow() {
        let chain = [n("AXGroup", 100, 100, 800, 590)]
        XCTAssertEqual(ElementSnap.choose(chain: chain, window: win, cursor: CGPoint(x: 400, y: 400)), win)
    }

    func testToolbarIsWindow() {
        let chain = [n("AXToolbar", 100, 100, 800, 52)]
        XCTAssertEqual(ElementSnap.choose(chain: chain, window: win, cursor: CGPoint(x: 400, y: 140)), win)
    }

    func testOversizedElementClampedToWindow() {
        // 글 영역이 창보다 길게(스크롤 내용) 보고되는 경우 — TextEdit 실측 656x1625
        let chain = [n("AXTextArea", 100, -500, 400, 2000)]
        XCTAssertEqual(ElementSnap.choose(chain: chain, window: win, cursor: CGPoint(x: 200, y: 400)),
                       CGRect(x: 100, y: 100, width: 400, height: 600))
    }

    func testElementNotUnderCursorSkipped() {
        let chain = [n("AXButton", 600, 600, 50, 20), n("AXGroup", 150, 300, 300, 200)]
        XCTAssertEqual(ElementSnap.choose(chain: chain, window: win, cursor: CGPoint(x: 200, y: 350)),
                       CGRect(x: 150, y: 300, width: 300, height: 200))
    }

    func testEmptyChainIsWindow() {
        XCTAssertEqual(ElementSnap.choose(chain: [], window: win, cursor: CGPoint(x: 400, y: 400)), win)
    }

    func testCocoaCoordinatesTitleBar() {
        // Cocoa(아래 원점): 창 위쪽 = maxY
        XCTAssertEqual(ElementSnap.choose(chain: [n("AXButton", 400, 680, 30, 16)], window: win,
                                          cursor: CGPoint(x: 410, y: 690), topIsMinY: false), win)
    }
}
