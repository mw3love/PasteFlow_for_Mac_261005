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
