import AppKit

/// 화면 핀(⌘⇧1) — 이미지를 원본 크기(1:1)로 화면 위에 띄워 둔다. 여러 개 가능.
/// 끌어서 이동, 휠·핀치로 크기 조절, 더블클릭·Esc로 닫기. 포커스는 빼앗지 않는다.
/// Space = 주석 편집 모드(이미지 아래에 도구 막대). 주석은 핀에 남아 다시 편집할 수 있다.
final class PinWindow: NSPanel {
    private static var open: [PinWindow] = []
    private static let gap: CGFloat = 6
    private let canvas: AnnotationCanvas
    private let toolBar: AnnotationToolbar
    private let baseSize: NSSize
    /// 화면에 보이는 이미지 크기(확대·축소 반영).
    private var imageSize: NSSize

    /// `at`이 있으면 그 자리(캡처한 위치)에, 없으면 커서 근처에 띄운다. `edit`면 바로 편집 모드.
    static func show(image: NSImage, pixelScale: CGFloat, at rect: NSRect? = nil, edit: Bool = false) {
        let screen = NSScreen.screens.first { $0.frame.contains(rect?.origin ?? NSEvent.mouseLocation) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        // 원본 1:1(픽셀 ÷ 배율), 화면보다 크면만 줄인다
        var size = NSSize(width: image.size.width / pixelScale, height: image.size.height / pixelScale)
        let fit = min(1, vf.width * 0.9 / size.width, vf.height * 0.9 / size.height)
        size = NSSize(width: size.width * fit, height: size.height * fit)
        var origin = rect?.origin ?? NSPoint(x: NSEvent.mouseLocation.x - size.width / 2, y: NSEvent.mouseLocation.y - size.height / 2)
        origin.x = min(max(origin.x, vf.minX), vf.maxX - size.width)
        origin.y = min(max(origin.y, vf.minY), vf.maxY - size.height)
        let w = PinWindow(image: image, size: size)
        w.setFrameOrigin(origin)
        open.append(w)
        w.orderFrontRegardless()
        w.makeKey()
        if edit { w.setEditing(true) }
    }

    private init(image: NSImage, size: NSSize) {
        canvas = AnnotationCanvas(image: image)
        toolBar = AnnotationToolbar(canvas: canvas)
        baseSize = size
        imageSize = size
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        hidesOnDeactivate = false
        let root = PinRootView(frame: NSRect(origin: .zero, size: size))
        canvas.frame = root.bounds
        root.addSubview(canvas)
        toolBar.isHidden = true
        root.addSubview(toolBar)
        contentView = root
        canvas.onClose = { [weak self] in self?.close() }
        canvas.onToggleEdit = { [weak self] in
            guard let self else { return }
            self.setEditing(!self.canvas.editing)
        }
        canvas.onCopy = { [weak self] in self?.copyResult() }
        canvas.onStateChange = { [weak self] in self?.toolBar.refresh() }
        makeFirstResponder(canvas)
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { close() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close() } else { super.keyDown(with: event) }
    }

    override func scrollWheel(with event: NSEvent) {
        let factor: CGFloat = 1 + (event.scrollingDeltaY > 0 ? 0.08 : -0.08)
        resize(by: factor)
    }

    override func magnify(with event: NSEvent) { resize(by: 1 + event.magnification) }

    private func resize(by factor: CGFloat) {
        canvas.commitText()   // 글자 입력 칸은 확대 배율을 따라가지 않으므로 먼저 끝낸다
        let r = imageScreenRect
        let newW = min(max(r.width * factor, 40), baseSize.width * 8)
        let newH = newW * baseSize.height / baseSize.width
        imageSize = NSSize(width: newW, height: newH)
        layoutChrome(imageRect: NSRect(x: r.midX - newW / 2, y: r.midY - newH / 2, width: newW, height: newH))
    }

    // MARK: 편집 모드

    /// 이미지가 화면에 놓인 자리(창 아래쪽엔 편집 중 도구 막대가 붙는다).
    private var imageScreenRect: NSRect {
        NSRect(x: frame.minX, y: frame.maxY - imageSize.height, width: imageSize.width, height: imageSize.height)
    }

    private func setEditing(_ on: Bool) {
        let r = imageScreenRect
        canvas.editing = on
        toolBar.refresh()
        layoutChrome(imageRect: r)
        if on {
            // 막대가 화면 아래로 나가면 창 전체를 올린다
            let vf = (screen ?? NSScreen.main)?.visibleFrame ?? frame
            if frame.minY < vf.minY { setFrameOrigin(NSPoint(x: frame.minX, y: vf.minY)) }
        }
        makeKey()
        makeFirstResponder(canvas)
    }

    /// 이미지 자리를 그대로 두고, 편집 중이면 그 아래에 도구 막대 높이만큼 창을 늘린다.
    private func layoutChrome(imageRect r: NSRect) {
        let chrome = canvas.editing ? Self.gap + AnnotationToolbar.height : 0
        let width = max(r.width, canvas.editing ? toolBar.fittingWidth : 0)
        setFrame(NSRect(x: r.minX, y: r.minY - chrome, width: width, height: r.height + chrome), display: false)
        canvas.frame = NSRect(x: 0, y: 0, width: r.width, height: r.height)
        toolBar.frame = NSRect(x: 0, y: r.height + Self.gap, width: toolBar.fittingWidth, height: AnnotationToolbar.height)
        toolBar.isHidden = !canvas.editing
        contentView?.needsDisplay = true
        display()
    }

    /// 주석을 입힌 원본 해상도 PNG를 클립보드에 올린다 — 감시기가 일반 복사처럼 히스토리·순차 큐에 넣는다.
    private func copyResult() {
        canvas.commitText()
        guard let png = AnnotationRenderer.renderPNG(image: canvas.image, items: canvas.doc.items) else {
            Toast.show("복사 실패", detail: "이미지를 만들지 못했어요", always: true)
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        pb.writeObjects([item])
        StatusLog.append("annotation copied items=\(canvas.doc.items.count) bytes=\(png.count)")
        Toast.show("주석 이미지 복사됨", detail: "히스토리·큐에 들어가요")
        setEditing(false)
    }

    override func close() {
        super.close()
        Self.open.removeAll { $0 === self }
    }
}

private final class PinRootView: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
}
