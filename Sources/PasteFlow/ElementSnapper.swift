import AppKit
import ApplicationServices
import PasteFlowCore

/// 캡처 오버레이에서 커서 아래 다른 앱의 요소(버튼·링크 등) 사각형을 손쉬운 사용(AX)으로 묻는다.
/// 실측(2026-10-04): 앱 요소 대상 `AXUIElementCopyElementAtPosition` 1회 0.2~0.6ms → 커서가 움직일 때마다 물어도 된다.
enum ElementSnapper {
    private static var apps: [pid_t: AXUIElement] = [:]
    private static var launchObserver: NSObjectProtocol?

    /// 크롬 계열 — 웹페이지 안 접근성 정보를 기본으로 꺼 둔다.
    private static let chromiumIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "com.microsoft.edgemac",
        "com.brave.Browser", "com.vivaldi.Vivaldi", "company.thebrowser.Browser", "com.operasoftware.Opera",
    ]

    /// 실행 중인 앱과 새로 켜지는 앱의 접근성 정보를 미리 깨운다(켜지는 데 약 1.5초라 캡처 순간엔 늦다).
    static func startWaking() {
        NSWorkspace.shared.runningApplications.forEach(wake)
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            // 막 켜진 앱은 창이 생기기 전이라 잠시 뒤에
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { wake(app) }
        }
    }

    /// 크롬 계열은 `AXEnhancedUserInterface`로 깨운다(실측: 오류 코드를 돌려주지만 웹 내용이 켜지고 계속 유지).
    /// 일렉트론 앱은 `AXManualAccessibility`(일렉트론이 정한 방법). 다른 앱은 건드리지 않는다.
    private static func wake(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        if chromiumIDs.contains(id) {
            AXUIElementSetAttributeValue(el, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        } else if let url = app.bundleURL,
                  FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path) {
            AXUIElementSetAttributeValue(el, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
    }

    /// 커서 아래 잡을 사각형(Cocoa 전역). 요소를 못 고르면 창 전체.
    static func rect(at point: NSPoint, pid: pid_t, window: NSRect) -> NSRect {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return window }
        // AX는 CG 좌표(주 모니터 왼쪽 위 원점)
        let cgPoint = CGPoint(x: point.x, y: primaryHeight - point.y)
        let cgWindow = CGRect(x: window.minX, y: primaryHeight - window.maxY, width: window.width, height: window.height)
        let app = appElement(pid)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(cgPoint.x), Float(cgPoint.y), &hit) == .success, var el = hit else { return window }
        var chain: [ElementSnap.Node] = []
        // 규칙은 첫 몇 단계에서 결정된다 — 깊은 웹 트리(실측 27단)를 끝까지 오르지 않는다
        for _ in 0..<8 {
            let role = (attribute(el, kAXRoleAttribute) as? String) ?? ""
            chain.append(.init(role: role, rect: frame(el) ?? .null))
            if role == kAXWindowRole as String { break }
            guard let parent = attribute(el, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            el = parent as! AXUIElement
        }
        let r = ElementSnap.choose(chain: chain, window: cgWindow, cursor: cgPoint, topIsMinY: true)
        return NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    private static func appElement(_ pid: pid_t) -> AXUIElement {
        if let el = apps[pid] { return el }
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, 0.1)   // 멈춘 앱 때문에 커서가 굳지 않게
        apps[pid] = el
        return el
    }

    private static func attribute(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    private static func frame(_ el: AXUIElement) -> CGRect? {
        guard let p = attribute(el, kAXPositionAttribute), let s = attribute(el, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &origin)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }
}
