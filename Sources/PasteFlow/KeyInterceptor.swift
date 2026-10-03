import AppKit
import PasteFlowCore

/// 전역 키 감시(CGEventTap). 붙여넣기 단축키는 삼키고 동작으로 넘기며, 일반 ⌘V는 통과시키되 알린다.
/// 손쉬운 사용 권한이 있어야 탭이 만들어진다.
final class KeyInterceptor {
    /// 앱이 주입한 키 이벤트에 붙이는 표식 — 탭에서 이걸 보고 "사용자가 누른 ⌘V"와 구분한다.
    static let injectedMarker: Int64 = 0x5046_4C57  // "PFLW"

    var onAction: ((PasteAction) -> Void)?
    var onPanelToggle: (() -> Void)?
    var onScreenAction: ((ScreenAction) -> Void)?

    private var tap: CFMachPort?
    private var swallowedKeyUp: Int64?

    /// 성공하면 true. 권한이 없으면 false.
    @discardableResult
    func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let me = Unmanaged<KeyInterceptor>.fromOpaque(refcon!).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 맥이 감시가 느리다고 판단하거나 사용자 입력으로 탭을 끄면 다시 켠다
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            StatusLog.append("key tap re-enabled (\(type == .tapDisabledByTimeout ? "timeout" : "userInput"))")
            return Unmanaged.passUnretained(event)
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .keyUp {
            if swallowedKeyUp == keyCode {
                swallowedKeyUp = nil
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        // 앱이 직접 주입한 키는 그대로 통과
        if event.getIntegerValueField(.eventSourceUserData) == Self.injectedMarker {
            return Unmanaged.passUnretained(event)
        }
        let mods = Self.modifiers(event.flags)
        if Hotkeys.isPanelToggle(keyCode: Int(keyCode), modifiers: mods) {
            swallowedKeyUp = keyCode
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                DispatchQueue.main.async { self.onPanelToggle?() }
            }
            return nil
        }
        if let screen = Hotkeys.screenAction(keyCode: Int(keyCode), modifiers: mods) {
            swallowedKeyUp = keyCode
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                DispatchQueue.main.async { self.onScreenAction?(screen) }
            }
            return nil
        }
        guard let action = Hotkeys.action(keyCode: Int(keyCode), modifiers: mods) else {
            return Unmanaged.passUnretained(event)
        }
        if action == .plainPaste {
            DispatchQueue.main.async { self.onAction?(.plainPaste) }
            return Unmanaged.passUnretained(event)
        }
        swallowedKeyUp = keyCode
        // 키를 누르고 있어 반복 입력이 오면 삼키기만 한다
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            DispatchQueue.main.async { self.onAction?(action) }
        }
        return nil
    }

    private static func modifiers(_ flags: CGEventFlags) -> Modifiers {
        var m: Modifiers = []
        if flags.contains(.maskCommand) { m.insert(.command) }
        if flags.contains(.maskShift) { m.insert(.shift) }
        if flags.contains(.maskAlternate) { m.insert(.option) }
        if flags.contains(.maskControl) { m.insert(.control) }
        return m
    }

    /// ⌘V를 주입한다. 사용자가 아직 ⇧·⌥·⌃를 누르고 있어도 앱에는 ⌘V로만 보이도록 플래그를 고정한다.
    static func injectCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.userData = injectedMarker
        let vKey = CGKeyCode(Hotkeys.keyV)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: down) else { continue }
            e.flags = .maskCommand
            e.setIntegerValueField(.eventSourceUserData, value: injectedMarker)
            e.post(tap: .cgSessionEventTap)
        }
    }
}
