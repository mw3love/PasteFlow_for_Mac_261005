import ApplicationServices
import CoreGraphics

/// 앱이 필요로 하는 두 권한의 현재 상태.
public struct PermissionStatus: Equatable {
    /// 손쉬운 사용 — 전역 키 감시·⌘V 주입
    public var accessibility: Bool
    /// 화면 기록 — 캡처·OCR
    public var screenRecording: Bool

    public static func current() -> PermissionStatus {
        PermissionStatus(
            accessibility: AXIsProcessTrusted(),
            screenRecording: CGPreflightScreenCaptureAccess()
        )
    }

    /// 없는 권한만 시스템 요청 창을 띄운다.
    public static func requestMissing() {
        let s = current()
        if !s.accessibility {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        if !s.screenRecording {
            _ = CGRequestScreenCaptureAccess()
        }
    }
}
