import AppKit

/// 화면 핀(⌘⇧1) — 이미지를 원본 크기(1:1)로 화면 위에 띄워 둔다. 여러 개 가능.
/// 끌어서 이동, 휠·핀치로 크기 조절, 더블클릭·Esc로 닫기. 포커스는 빼앗지 않는다.
final class PinWindow: NSPanel {
    private static var open: [PinWindow] = []
    private let image: NSImage
    private let baseSize: NSSize

    /// `at`이 있으면 그 자리(캡처한 위치)에, 없으면 커서 근처에 띄운다.
    static func show(image: NSImage, pixelScale: CGFloat, at rect: NSRect? = nil) {
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
    }

    private init(image: NSImage, size: NSSize) {
        self.image = image
        self.baseSize = size
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        hidesOnDeactivate = false
        let iv = PinImageView(image: image)
        iv.imageScaling = .scaleAxesIndependently
        iv.wantsLayer = true
        iv.layer?.borderWidth = 0.5
        iv.layer?.borderColor = Theme.border.cgColor
        iv.onClose = { [weak self] in self?.close() }
        contentView = iv
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
        var f = frame
        let newW = min(max(f.width * factor, 40), baseSize.width * 8)
        let newH = newW * baseSize.height / baseSize.width
        f.origin.x += (f.width - newW) / 2
        f.origin.y += (f.height - newH) / 2
        f.size = NSSize(width: newW, height: newH)
        setFrame(f, display: true)
    }

    override func close() {
        super.close()
        Self.open.removeAll { $0 === self }
    }
}

final class PinImageView: NSImageView {
    var onClose: (() -> Void)?
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onClose?() } else { super.mouseDown(with: event) }
    }
}
