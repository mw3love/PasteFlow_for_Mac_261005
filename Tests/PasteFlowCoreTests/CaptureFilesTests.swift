import XCTest
@testable import PasteFlowCore

final class CaptureFilesTests: XCTestCase {
    func testNameAndCollisionSuffix() {
        let folder = URL(fileURLWithPath: "/tmp/pf")
        var comps = DateComponents(year: 2026, month: 10, day: 3, hour: 9, minute: 5, second: 7)
        comps.timeZone = .current
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        XCTAssertEqual(CaptureFiles.uniqueURL(in: folder, date: date, exists: { _ in false }).lastPathComponent, "clip_20261003_090507.png")
        let taken: Set<String> = ["clip_20261003_090507.png", "clip_20261003_090507_1.png"]
        XCTAssertEqual(CaptureFiles.uniqueURL(in: folder, date: date, exists: { taken.contains($0.lastPathComponent) }).lastPathComponent,
                       "clip_20261003_090507_2.png")
    }

    func testDefaultFolderIsPicturesPasteFlow() {
        XCTAssertTrue(CaptureFiles.defaultFolder.path.hasSuffix("/Pictures/PasteFlow"))
    }
}
