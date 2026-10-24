import Foundation

/// 붙여넣기 계열 동작.
public enum PasteAction: Equatable {
    case sequential       // ⌘⇧V
    case sequentialAll    // ⇧⌘B
    case path             // ⇧⌘P
    case pathAll          // ⇧⌘[
    case plainPaste       // ⌘V — 가로채지 않고 큐만 비운다(바꿀 수 없음)
}

/// 화면 계열 동작.
public enum ScreenAction: Equatable {
    case capture   // ⌘F2 영역 캡처
    case pin       // ⌘F3 화면 핀
    case ocr       // ⌘F1 화면 OCR
}

public struct Modifiers: OptionSet, Hashable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = Modifiers(rawValue: 1 << 0)
    public static let shift = Modifiers(rawValue: 1 << 1)
    public static let option = Modifiers(rawValue: 1 << 2)
    public static let control = Modifiers(rawValue: 1 << 3)
}

public enum Hotkeys {
    /// ANSI 배열 V 키의 가상 키 코드(kVK_ANSI_V).
    public static let keyV: Int = 9

    /// 사용자가 직접 누른 일반 ⌘V — 큐를 비우는 신호라 설정으로 바꾸지 않는다.
    public static func isPlainPaste(keyCode: Int, modifiers: Modifiers) -> Bool {
        keyCode == keyV && modifiers == [.command]
    }
}

/// 설정에서 바꿀 수 있는 단축키 8개(PLAN.md 단축키 표 순서).
public enum HotkeyAction: String, Codable, CaseIterable {
    case sequential, sequentialAll, path, pathAll, panel, capture, pin, ocr

    public var title: String {
        switch self {
        case .sequential: return "순차 붙여넣기"
        case .sequentialAll: return "순차 전체 자동"
        case .path: return "경로 붙여넣기(하나)"
        case .pathAll: return "경로 붙여넣기(전체)"
        case .panel: return "패널 열기"
        case .capture: return "영역 캡처"
        case .pin: return "화면 핀"
        case .ocr: return "OCR"
        }
    }

    public var pasteAction: PasteAction? {
        switch self {
        case .sequential: return .sequential
        case .sequentialAll: return .sequentialAll
        case .path: return .path
        case .pathAll: return .pathAll
        default: return nil
        }
    }

    public var screenAction: ScreenAction? {
        switch self {
        case .capture: return .capture
        case .pin: return .pin
        case .ocr: return .ocr
        default: return nil
        }
    }
}

/// 키 하나 + 수식키. 글자가 아니라 키 코드로 본다(한글 입력 상태에서도 동작).
public struct Hotkey: Codable, Hashable {
    public var keyCode: Int
    public var modifiers: Modifiers

    public init(_ keyCode: Int, _ modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// 맥 표기 순서(⌃⌥⇧⌘) + 키 이름. 예: ⌥⌘⇧V → "⌥⇧⌘V".
    public var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + KeyNames.name(keyCode)
    }
}

/// 단축키 표 — 기본값 위에 사용자가 바꾼 것만 얹는다. DB 설정 `hotkeys`에 JSON으로 저장.
public struct HotkeyMap: Equatable {
    public static let settingKey = "hotkeys"

    public static let defaults: [HotkeyAction: Hotkey] = [
        .sequential: Hotkey(9, [.command, .shift]),
        .sequentialAll: Hotkey(11, [.command, .shift]),
        .path: Hotkey(35, [.command, .shift]),
        .pathAll: Hotkey(33, [.command, .shift]),
        .panel: Hotkey(49, [.command]),
        .capture: Hotkey(120, [.command]),
        .pin: Hotkey(99, [.command]),
        .ocr: Hotkey(122, [.command]),
    ]

    private var custom: [HotkeyAction: Hotkey] = [:]

    public init() {}

    public func hotkey(for a: HotkeyAction) -> Hotkey { custom[a] ?? Self.defaults[a]! }

    public func isDefault(_ a: HotkeyAction) -> Bool { hotkey(for: a) == Self.defaults[a] }

    /// nil이면 기본값으로 되돌린다.
    public mutating func set(_ k: Hotkey?, for a: HotkeyAction) {
        custom[a] = (k == Self.defaults[a]) ? nil : k
    }

    public func action(keyCode: Int, modifiers: Modifiers) -> HotkeyAction? {
        let k = Hotkey(keyCode, modifiers)
        return HotkeyAction.allCases.first { hotkey(for: $0) == k }
    }

    // MARK: 검사

    public enum Problem: Equatable {
        case needsModifier           // ⌘·⌃·⌥ 중 하나는 있어야 함(그냥 글자 키는 입력을 막는다)
        case reserved(String)        // 맥·앱이 꼭 쓰는 키
        case duplicate(HotkeyAction) // 다른 동작이 이미 씀
    }

    /// 쓰면 안 되는 키. 문제가 없으면 nil.
    public func problem(_ k: Hotkey, for a: HotkeyAction) -> Problem? {
        if k.modifiers.intersection([.command, .control, .option]).isEmpty { return .needsModifier }
        if let name = Self.reserved[k] { return .reserved(name) }
        if let other = HotkeyAction.allCases.first(where: { $0 != a && hotkey(for: $0) == k }) { return .duplicate(other) }
        return nil
    }

    /// 써도 되지만 다른 앱과 겹치는 키(PLAN.md "피한 키"·"알려진 겹침").
    public static func warning(_ k: Hotkey) -> String? { overlaps[k] }

    private static let reserved: [Hotkey: String] = [
        Hotkey(9, [.command]): "일반 붙여넣기(⌘V)",
        Hotkey(8, [.command]): "복사(⌘C)",
        Hotkey(7, [.command]): "잘라내기(⌘X)",
        Hotkey(6, [.command]): "실행 취소(⌘Z)",
        Hotkey(0, [.command]): "전체 선택(⌘A)",
        Hotkey(12, [.command]): "앱 종료(⌘Q)",
        Hotkey(13, [.command]): "창 닫기(⌘W)",
        Hotkey(48, [.command]): "앱 전환(⌘Tab)",
        Hotkey(49, [.control]): "한/영 전환(⌃Space)",
        Hotkey(20, [.command, .shift]): "맥 스크린샷(⌘⇧3)",
        Hotkey(21, [.command, .shift]): "맥 스크린샷(⌘⇧4)",
        Hotkey(23, [.command, .shift]): "맥 스크린샷(⌘⇧5)",
    ]

    private static let overlaps: [Hotkey: String] = [
        Hotkey(9, [.command, .shift]): "일부 앱의 \"서식 없이 붙여넣기\"와 겹쳐요",
        Hotkey(14, [.command, .shift]): "VS Code 탐색기와 겹쳐요",
        Hotkey(1, [.command, .shift]): "\"다른 이름으로 저장\"과 겹쳐요",
        Hotkey(35, [.command, .shift]): "VS Code 명령 팔레트와 겹쳐요",
        Hotkey(33, [.command, .shift]): "탭 이동과 겹쳐요",
        Hotkey(30, [.command, .shift]): "탭 이동과 겹쳐요",
    ]

    // MARK: 저장

    public func json() -> String {
        let dict = Dictionary(uniqueKeysWithValues: custom.map { ($0.key.rawValue, $0.value) })
        return (try? JSONEncoder().encode(dict)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// 깨졌거나 모르는 동작 이름은 건너뛰고 기본값을 쓴다.
    public static func from(json: String?) -> HotkeyMap {
        var m = HotkeyMap()
        guard let d = json?.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Hotkey].self, from: d) else { return m }
        for (name, k) in dict {
            if let a = HotkeyAction(rawValue: name) { m.set(k, for: a) }
        }
        return m
    }
}

/// 가상 키 코드 → 표시 이름(ANSI 배열).
public enum KeyNames {
    private static let table: [Int: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M",
        45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 53: "Esc", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 42: "\\", 50: "`",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12",
    ]

    public static func name(_ keyCode: Int) -> String { table[keyCode] ?? "키\(keyCode)" }

    /// 수식키 자체(⌘·⇧·⌥·⌃·fn·Caps Lock) — 녹화 중 이것만 눌렸으면 아직 기다린다.
    public static func isModifierKey(_ keyCode: Int) -> Bool { (54...63).contains(keyCode) }
}
