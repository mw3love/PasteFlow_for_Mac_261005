import AppKit

/// 영역 캡처 오버레이(⌘⇧2). 얼린 화면 위에서 커서 아래 요소(버튼·링크 등, 제목 막대 위면 창 전체)를 하이라이트하고,
/// 클릭 = 그 요소·창 캡처, 4pt 이상 끌기 = 자유 사각형, 우클릭/Esc = 취소, Space = 실제 커서 포함 토글.
final class CaptureOverlay {
    static let dragThreshold: CGFloat = 4

    enum Mode { case capture, ocr }

    /// (PNG, 캡처한 Cocoa 전역 사각형, 모드)
    var onCapture: ((Data, NSRect, Mode) -> Void)?
    private(set) var mode: Mode = .capture

    private var windows: [OverlayWindow] = []
    private var snapshot: ScreenSnapshot?
    private var includeCursor = false

    var isActive: Bool { !windows.isEmpty }

    func start(mode: Mode = .capture) {
        guard !isActive else { return }
        self.mode = mode
        Task { @MainActor in
            let t0 = Date()
            do {
                let snap = try await ScreenSnapshot.take()
                StatusLog.append("capture snapshot displays=\(snap.displays.count) windows=\(snap.windows.count) ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
                show(snap)
            } catch {
                StatusLog.append("capture snapshot FAILED: \(error)")
            }
        }
    }

    private func show(_ snap: ScreenSnapshot) {
        snapshot = snap
        includeCursor = false
        for d in snap.displays {
            let w = OverlayWindow(display: d, snapshot: snap)
            w.view.controller = self
            windows.append(w)
            w.orderFrontRegardless()
        }
        // 커서가 있는 모니터 창이 키 입력(Esc·Space)을 받는다
        let key = windows.first { $0.frame.contains(NSEvent.mouseLocation) } ?? windows.first
        key?.makeKey()
        key?.makeFirstResponder(key?.view)
        NSCursor.crosshair.push()
        windows.forEach { $0.view.refreshHover(at: NSEvent.mouseLocation) }
    }

    func cancel() { close() }

    func toggleCursor() {
        includeCursor.toggle()
        windows.forEach { $0.view.showsCursorMarker = includeCursor; $0.view.needsDisplay = true }
    }

    func finish(rect: NSRect, on display: ScreenSnapshot.Display) {
        guard let snap = snapshot, let png = snap.crop(rect, on: display, includeCursor: includeCursor) else { close(); return }
        let m = mode
        close()
        onCapture?(png, rect, m)
    }

    private func close() {
        guard isActive else { return }
        NSCursor.pop()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        snapshot = nil
    }
}

final class OverlayWindow: NSPanel {
    let view: OverlayView

    init(display: ScreenSnapshot.Display, snapshot: ScreenSnapshot) {
        view = OverlayView(display: display, snapshot: snapshot)
        super.init(contentRect: display.screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        hasShadow = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        contentView = view
        setFrame(display.screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
}

final class OverlayView: NSView {
    weak var controller: CaptureOverlay?
    var showsCursorMarker = false

    private let display: ScreenSnapshot.Display
    private let snapshot: ScreenSnapshot
    private var highlight: NSRect?     // Cocoa 전역
    private var dragStart: NSPoint?    // Cocoa 전역
    private var dragRect: NSRect?

    init(display: ScreenSnapshot.Display, snapshot: ScreenSnapshot) {
        self.display = display
        self.snapshot = snapshot
        super.init(frame: NSRect(origin: .zero, size: display.screen.frame.size))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    private func toLocal(_ global: NSRect) -> NSRect {
        global.offsetBy(dx: -display.screen.frame.minX, dy: -display.screen.frame.minY)
    }

    func refreshHover(at global: NSPoint) {
        guard dragStart == nil else { return }
        var new: NSRect?
        if display.screen.frame.contains(global), let w = snapshot.windows.first(where: { $0.rect.contains(global) }) {
            new = ElementSnapper.rect(at: global, pid: w.pid, window: w.rect)
        }
        if new != highlight { highlight = new; needsDisplay = true }
    }

    override func mouseMoved(with event: NSEvent) { refreshHover(at: NSEvent.mouseLocation) }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        dragRect = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let p = NSEvent.mouseLocation
        if dragRect == nil, hypot(p.x - start.x, p.y - start.y) < CaptureOverlay.dragThreshold { return }
        dragRect = NSRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; dragRect = nil }
        if let r = dragRect {
            if r.width >= 2, r.height >= 2 { controller?.finish(rect: r, on: display) }
        } else if let h = highlight {
            controller?.finish(rect: h, on: display)
        }
        // 빈 곳을 끌지 않고 클릭하면 무시
    }

    override func rightMouseDown(with event: NSEvent) { controller?.cancel() }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: controller?.cancel()          // Esc
        case 49: controller?.toggleCursor()    // Space
        default: break
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.draw(display.image, in: bounds)
        let sel = dragRect ?? highlight
        // 선택 바깥을 어둡게
        ctx.setFillColor(NSColor(white: 0, alpha: 0.35).cgColor)
        if let sel {
            let local = toLocal(sel).intersection(bounds)
            ctx.addRect(bounds)
            ctx.addRect(local)
            ctx.fillPath(using: .evenOdd)
            ctx.setStrokeColor(Theme.coral.cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(local.insetBy(dx: 1, dy: 1))
            if dragRect != nil {
                let label = "\(Int(sel.width)) × \(Int(sel.height))" as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                                                            .foregroundColor: NSColor.white]
                let size = label.size(withAttributes: attrs)
                let bg = NSRect(x: local.minX, y: local.maxY + 4, width: size.width + 10, height: size.height + 4)
                NSColor(white: 0, alpha: 0.7).setFill()
                NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
                label.draw(at: NSPoint(x: bg.minX + 5, y: bg.minY + 2), withAttributes: attrs)
            }
        } else {
            ctx.fill(bounds)
        }
        // Space로 켠 실제 커서 위치 표시
        if showsCursorMarker, let cur = snapshot.cursorImage, display.screen.frame.contains(snapshot.cursorLocation) {
            let p = NSPoint(x: snapshot.cursorLocation.x - display.screen.frame.minX - snapshot.cursorHotSpot.x,
                            y: snapshot.cursorLocation.y - display.screen.frame.minY - (cur.size.height - snapshot.cursorHotSpot.y))
            cur.draw(in: NSRect(origin: p, size: cur.size))
        }
    }
}
