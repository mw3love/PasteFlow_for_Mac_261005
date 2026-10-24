import XCTest
@testable import PasteFlowCore

final class HotkeysTests: XCTestCase {
    private let map = HotkeyMap()

    func testDefaultsMatchPlan() {
        let v = Hotkeys.keyV
        XCTAssertEqual(map.action(keyCode: v, modifiers: [.command, .shift]), .sequential)
        XCTAssertEqual(map.action(keyCode: 11, modifiers: [.command, .shift]), .sequentialAll)
        XCTAssertEqual(map.action(keyCode: 35, modifiers: [.command, .shift]), .path)
        XCTAssertEqual(map.action(keyCode: 33, modifiers: [.command, .shift]), .pathAll)
        XCTAssertEqual(map.action(keyCode: 49, modifiers: [.command]), .panel)
        XCTAssertEqual(map.action(keyCode: 120, modifiers: [.command]), .capture)
        XCTAssertEqual(map.action(keyCode: 99, modifiers: [.command]), .pin)
        XCTAssertEqual(map.action(keyCode: 122, modifiers: [.command]), .ocr)
        XCTAssertEqual(HotkeyAction.sequentialAll.pasteAction, .sequentialAll)
        XCTAssertEqual(HotkeyAction.ocr.screenAction, .ocr)
        XCTAssertNil(HotkeyAction.panel.pasteAction)
    }

    func testPlainPasteIsFixed() {
        XCTAssertTrue(Hotkeys.isPlainPaste(keyCode: Hotkeys.keyV, modifiers: [.command]))
        XCTAssertFalse(Hotkeys.isPlainPaste(keyCode: Hotkeys.keyV, modifiers: [.command, .shift]))
        XCTAssertNil(map.action(keyCode: Hotkeys.keyV, modifiers: [.command]))
    }

    func testOtherCombosIgnored() {
        XCTAssertNil(map.action(keyCode: Hotkeys.keyV, modifiers: []))
        XCTAssertNil(map.action(keyCode: Hotkeys.keyV, modifiers: [.command, .option]))  // Finder "이동" 붙여넣기
        XCTAssertNil(map.action(keyCode: 8, modifiers: [.command, .shift]))              // ⌘⇧C
        XCTAssertNil(map.action(keyCode: 20, modifiers: [.command, .shift]))             // ⌘⇧3 = 맥 스크린샷
        XCTAssertNil(map.action(keyCode: 49, modifiers: [.option]))                      // Spotlight(이 맥에서 바꾼 키)
        XCTAssertNil(map.action(keyCode: 49, modifiers: [.option, .shift]))
    }

    func testChangeTakesOverAndOldKeyStopsWorking() {
        var m = HotkeyMap()
        m.set(Hotkey(15, [.command, .option]), for: .capture)     // ⌥⌘R
        XCTAssertEqual(m.action(keyCode: 15, modifiers: [.command, .option]), .capture)
        XCTAssertNil(m.action(keyCode: 120, modifiers: [.command]))
        XCTAssertFalse(m.isDefault(.capture))
        m.set(nil, for: .capture)
        XCTAssertTrue(m.isDefault(.capture))
        XCTAssertEqual(m.action(keyCode: 120, modifiers: [.command]), .capture)
    }

    func testJSONRoundTripKeepsOnlyChanges() {
        var m = HotkeyMap()
        m.set(Hotkey(35, [.control, .option]), for: .pin)
        let json = m.json()
        XCTAssertTrue(json.contains("pin"))
        XCTAssertFalse(json.contains("ocr"))
        XCTAssertEqual(HotkeyMap.from(json: json), m)
        XCTAssertEqual(HotkeyMap.from(json: "깨짐"), HotkeyMap())
        XCTAssertEqual(HotkeyMap.from(json: #"{"없는동작":{"keyCode":1,"modifiers":1}}"#), HotkeyMap())
    }

    func testProblems() {
        XCTAssertEqual(map.problem(Hotkey(0, []), for: .pin), .needsModifier)
        XCTAssertEqual(map.problem(Hotkey(0, [.shift]), for: .pin), .needsModifier)
        if case .reserved = map.problem(Hotkey(9, [.command]), for: .pin) {} else { XCTFail("⌘V는 예약") }
        if case .reserved = map.problem(Hotkey(49, [.control]), for: .panel) {} else { XCTFail("⌃Space는 한/영") }
        XCTAssertNil(map.problem(Hotkey(49, [.command]), for: .panel))        // Spotlight를 ⌥Space로 옮겨 풀림
        XCTAssertEqual(map.problem(Hotkey(120, [.command]), for: .pin), .duplicate(.capture))
        XCTAssertNil(map.problem(Hotkey(99, [.command]), for: .pin))   // 자기 키는 그대로 둬도 됨
        XCTAssertNil(map.problem(Hotkey(15, [.command, .option]), for: .pin))
        XCTAssertNotNil(HotkeyMap.warning(Hotkey(1, [.command, .shift])))     // ⌘⇧S
        XCTAssertNil(HotkeyMap.warning(Hotkey(15, [.command, .option])))
    }

    func testDisplay() {
        XCTAssertEqual(Hotkey(9, [.command, .shift, .option]).display, "⌥⇧⌘V")
        XCTAssertEqual(Hotkey(9, [.command, .control, .option]).display, "⌃⌥⌘V")
        XCTAssertEqual(Hotkey(49, [.option]).display, "⌥Space")
        XCTAssertTrue(KeyNames.isModifierKey(56))
        XCTAssertFalse(KeyNames.isModifierKey(9))
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
