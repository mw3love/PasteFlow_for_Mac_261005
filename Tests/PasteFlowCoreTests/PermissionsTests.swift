import XCTest
@testable import PasteFlowCore

final class PermissionsTests: XCTestCase {
    // 뼈대 확인용: 상태 조회가 크래시 없이 값을 돌려준다
    func testCurrentReturnsStatus() {
        let s = PermissionStatus.current()
        XCTAssertEqual(s, PermissionStatus(accessibility: s.accessibility, screenRecording: s.screenRecording))
    }
}
