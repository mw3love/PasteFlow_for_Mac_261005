import XCTest
@testable import PasteFlowCore

final class HotkeysTests: XCTestCase {
    func testPasteFamily() {
        let v = Hotkeys.keyV
        XCTAssertEqual(Hotkeys.action(keyCode: v, modifiers: [.command, .shift]), .sequential)
        XCTAssertEqual(Hotkeys.action(keyCode: v, modifiers: [.command, .shift, .option]), .sequentialAll)
        XCTAssertEqual(Hotkeys.action(keyCode: v, modifiers: [.command, .control]), .path)
        XCTAssertEqual(Hotkeys.action(keyCode: v, modifiers: [.command, .control, .option]), .pathAll)
        XCTAssertEqual(Hotkeys.action(keyCode: v, modifiers: [.command]), .plainPaste)
    }

    func testPanelToggle() {
        XCTAssertTrue(Hotkeys.isPanelToggle(keyCode: Hotkeys.keySpace, modifiers: [.option]))
        XCTAssertFalse(Hotkeys.isPanelToggle(keyCode: Hotkeys.keySpace, modifiers: [.command]))   // Spotlight
        XCTAssertFalse(Hotkeys.isPanelToggle(keyCode: Hotkeys.keySpace, modifiers: [.control]))   // 한/영 전환
        XCTAssertFalse(Hotkeys.isPanelToggle(keyCode: Hotkeys.keySpace, modifiers: [.option, .shift]))
    }

    func testScreenActions() {
        XCTAssertEqual(Hotkeys.screenAction(keyCode: Hotkeys.key2, modifiers: [.command, .shift]), .capture)
        XCTAssertEqual(Hotkeys.screenAction(keyCode: Hotkeys.key1, modifiers: [.command, .shift]), .pin)
        XCTAssertEqual(Hotkeys.screenAction(keyCode: Hotkeys.keyE, modifiers: [.command, .shift]), .ocr)
        XCTAssertNil(Hotkeys.screenAction(keyCode: 20, modifiers: [.command, .shift]))          // ⌘⇧3 = 맥 스크린샷
        XCTAssertNil(Hotkeys.screenAction(keyCode: Hotkeys.key2, modifiers: [.command]))
    }

    func testOtherCombosIgnored() {
        XCTAssertNil(Hotkeys.action(keyCode: Hotkeys.keyV, modifiers: []))
        XCTAssertNil(Hotkeys.action(keyCode: Hotkeys.keyV, modifiers: [.command, .option]))  // Finder "이동" 붙여넣기
        XCTAssertNil(Hotkeys.action(keyCode: Hotkeys.keyV, modifiers: [.shift]))
        XCTAssertNil(Hotkeys.action(keyCode: 8, modifiers: [.command, .shift]))              // ⌘⇧C
    }
}

final class TempImageStoreTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pf-test-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func testSaveWritesPngAndReturnsAbsolutePath() throws {
        let store = TempImageStore(directory: dir)
        let url = try store.save(png: Data([0x89, 0x50]), itemId: 7)
        XCTAssertTrue(url.path.hasPrefix("/"))
        XCTAssertEqual(url.pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: url), Data([0x89, 0x50]))
    }

    func testCleanupRemovesOnlyOldFiles() throws {
        let store = TempImageStore(directory: dir, maxAge: 3600)
        let old = try store.save(png: Data([1]), itemId: 1)
        let fresh = try store.save(png: Data([2]), itemId: 2)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-7200)], ofItemAtPath: old.path)
        XCTAssertEqual(store.cleanup(), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
    }
}
