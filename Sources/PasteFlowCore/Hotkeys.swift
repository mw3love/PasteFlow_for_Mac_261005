import Foundation

/// 붙여넣기 계열 단축키 판정. 글자가 아니라 키 코드로 본다(한글 입력 상태에서도 동작).
/// 규칙: V 하나에 수식키만 바꾼다 — ⇧=순차, ⌃=경로, ⌥=전체 (PLAN.md 단축키 표).
public enum PasteAction: Equatable {
    case sequential       // ⌘⇧V
    case sequentialAll    // ⌥⌘⇧V
    case path             // ⌃⌘V
    case pathAll          // ⌃⌥⌘V
    case plainPaste       // ⌘V — 가로채지 않고 큐만 비운다
}

/// 화면 계열 단축키 — ⌘⇧+숫자(맥 스크린샷 ⌘⇧3/4/5 옆자리).
public enum ScreenAction: Equatable {
    case capture   // ⌘⇧2 영역 캡처
    case pin       // ⌘⇧1 화면 핀
}

public struct Modifiers: OptionSet, Hashable {
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

    /// Space 키의 가상 키 코드(kVK_Space).
    public static let keySpace: Int = 49

    /// 패널 열기/닫기 — ⌥Space.
    public static func isPanelToggle(keyCode: Int, modifiers: Modifiers) -> Bool {
        keyCode == keySpace && modifiers == [.option]
    }

    /// 숫자 1·2 키의 가상 키 코드(kVK_ANSI_1, kVK_ANSI_2).
    public static let key1: Int = 18
    public static let key2: Int = 19

    public static func screenAction(keyCode: Int, modifiers: Modifiers) -> ScreenAction? {
        guard modifiers == [.command, .shift] else { return nil }
        switch keyCode {
        case key2: return .capture
        case key1: return .pin
        default: return nil
        }
    }

    public static func action(keyCode: Int, modifiers: Modifiers) -> PasteAction? {
        guard keyCode == keyV else { return nil }
        switch modifiers {
        case [.command, .shift]: return .sequential
        case [.command, .shift, .option]: return .sequentialAll
        case [.command, .control]: return .path
        case [.command, .control, .option]: return .pathAll
        case [.command]: return .plainPaste
        default: return nil
        }
    }
}
