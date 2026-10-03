import AppKit
import ScreenCaptureKit

/// 키를 누른 순간의 화면을 "얼려" 둔다 — 모니터별 스크린샷 + 그 순간의 창 사각형 목록.
/// (CGWindowListCreateImage는 이 SDK에서 사용 불가라 ScreenCaptureKit을 쓴다.)
struct ScreenSnapshot {
    struct Display {
        let screen: NSScreen
        let image: CGImage      // 픽셀 단위(Retina면 2배)
    }

    /// 창 사각형(Cocoa 전역 좌표, 왼쪽 아래 원점). 앞에 있는 창이 먼저.
    let windows: [NSRect]
    let displays: [Display]
    /// 찍기 직전의 실제 커서(Space로 결과에 넣을 때 사용).
    let cursorImage: NSImage?
    let cursorHotSpot: NSPoint
    let cursorLocation: NSPoint

    static func take() async throws -> ScreenSnapshot {
        let cursor = NSCursor.currentSystem
        let mouse = NSEvent.mouseLocation
        let windows = currentWindowRects()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var displays: [Display] = []
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let sc = content.displays.first(where: { $0.displayID == id }) else { continue }
            let cfg = SCStreamConfiguration()
            cfg.width = Int(screen.frame.width * screen.backingScaleFactor)
            cfg.height = Int(screen.frame.height * screen.backingScaleFactor)
            cfg.showsCursor = false
            let img = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(display: sc, excludingWindows: []), configuration: cfg)
            displays.append(Display(screen: screen, image: img))
        }
        return ScreenSnapshot(windows: windows, displays: displays, cursorImage: cursor?.image,
                              cursorHotSpot: cursor?.hotSpot ?? .zero, cursorLocation: mouse)
    }

    /// 보이는 일반 창(layer 0)의 사각형. 내 앱 창·아주 작은 창은 뺀다.
    private static func currentWindowRects() -> [NSRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let myPid = ProcessInfo.processInfo.processIdentifier
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return list.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != myPid,
                  ((w[kCGWindowAlpha as String] as? Double) ?? 1) > 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"],
                  width >= 40, height >= 40 else { return nil }
            // CG 좌표(왼쪽 위 원점) → Cocoa 좌표(왼쪽 아래 원점)
            return NSRect(x: x, y: primaryHeight - y - height, width: width, height: height)
        }
    }

    /// Cocoa 전역 사각형을 한 모니터 스크린샷에서 잘라 PNG로. 선택은 시작한 모니터 안으로 한정한다.
    func crop(_ rect: NSRect, on display: Display, includeCursor: Bool) -> Data? {
        let s = display.screen
        let r = rect.intersection(s.frame)
        guard r.width >= 1, r.height >= 1 else { return nil }
        let scale = s.backingScaleFactor
        // 모니터 안 좌표(왼쪽 위 원점, 픽셀)
        let px = CGRect(x: (r.minX - s.frame.minX) * scale, y: (s.frame.maxY - r.maxY) * scale,
                        width: r.width * scale, height: r.height * scale).integral
        guard let cut = display.image.cropping(to: px) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cut)
        if includeCursor, let cur = cursorImage, r.contains(cursorLocation) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            let origin = NSPoint(x: (cursorLocation.x - r.minX - cursorHotSpot.x) * scale,
                                 y: (cursorLocation.y - r.minY) * scale - (cur.size.height - cursorHotSpot.y) * scale)
            cur.draw(in: NSRect(origin: origin, size: NSSize(width: cur.size.width * scale, height: cur.size.height * scale)))
            NSGraphicsContext.restoreGraphicsState()
        }
        rep.size = r.size   // PNG에 Retina 해상도(144dpi) 기록 → 다른 앱·핀에서 실제 크기로 보임
        return rep.representation(using: .png, properties: [:])
    }
}
