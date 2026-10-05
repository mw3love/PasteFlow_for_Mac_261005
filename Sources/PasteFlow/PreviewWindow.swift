import AppKit
import PasteFlowCore

/// 항목 미리보기 창. 여러 개를 동시에 띄울 수 있고, Esc·더블클릭으로 닫는다.
/// 이미지는 휠(트랙패드 핀치)로 확대·축소하고 끌어서 이동한다. Space = 그 자리에 핀으로 바꿔 주석 편집.
final class PreviewWindow: NSPanel {
    private static var open: [PreviewWindow] = []
    private var image: NSImage?
    private let item: ClipItem

    static func show(_ item: ClipItem, near anchor: NSRect) {
        let w = PreviewWindow(item: item)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? .zero
        var frame = w.frame
        // 패널 왼쪽(공간이 없으면 오른쪽)에 놓고, 여러 개면 조금씩 어긋나게
        let offset = CGFloat(open.count % 6) * 24
        frame.origin.x = anchor.minX - frame.width - 12 - offset
        if frame.minX < vf.minX { frame.origin.x = anchor.maxX + 12 + offset }
        frame.origin.y = min(max(anchor.maxY - frame.height - offset, vf.minY), vf.maxY - frame.height)
        w.setFrame(frame, display: true)
        open.append(w)
        w.makeKeyAndOrderFront(nil)
    }

    private init(item: ClipItem) {
        self.item = item
        let content: NSView
        var size = NSSize(width: 420, height: 300)
        if item.kind == .image, let image = Self.image(item) {
            let vf = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1200, height: 800)
            let fit = min(1, (vf.width * 0.6) / image.size.width, (vf.height * 0.6) / image.size.height)
            size = NSSize(width: max(200, image.size.width * fit), height: max(120, image.size.height * fit))
            let iv = MenuImageView(image: image)
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.frame = NSRect(origin: .zero, size: size)
            let scroll = NSScrollView()
            scroll.documentView = iv
            scroll.allowsMagnification = true
            scroll.minMagnification = 0.2
            scroll.maxMagnification = 8
            scroll.hasHorizontalScroller = false
            scroll.hasVerticalScroller = false
            scroll.drawsBackground = false
            content = scroll
        } else {
            let text = Self.text(item)
            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true
            let tv = MenuTextView(frame: NSRect(origin: .zero, size: size))
            tv.minSize = NSSize(width: 0, height: size.height)
            tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            tv.autoresizingMask = [.width]
            tv.isVerticallyResizable = true
            tv.textContainer?.widthTracksTextView = true
            scroll.documentView = tv
            tv.string = text
            tv.isEditable = false
            tv.font = .systemFont(ofSize: 13)
            tv.textColor = Theme.text
            tv.backgroundColor = Theme.bg
            tv.textContainerInset = NSSize(width: 10, height: 10)
            scroll.drawsBackground = false
            content = scroll
        }
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = item.kind == .image ? item.previewText : "미리보기"
        level = .floating
        isReleasedWhenClosed = false
        backgroundColor = Theme.bg
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        contentView = content
        if item.kind == .image { image = Self.image(item) }
        let menuProvider: () -> NSMenu? = { [weak self] in self?.contextMenu() }
        (content as? NSScrollView).flatMap { $0.documentView as? MenuImageView }?.menuProvider = menuProvider
        (content as? NSScrollView).flatMap { $0.documentView as? MenuTextView }?.menuProvider = menuProvider
    }

    /// 윈도우판 미리보기 메뉴 — 이미지: 복사·경로·OCR·복제·주석 편집·닫기 / 글자: 전체 복사·수정·닫기.
    private func contextMenu() -> NSMenu {
        let m = NSMenu()
        let item = self.item
        if let image {
            m.addItem(MenuAction("복사", key: "c", mods: .command) { AppActions.copyItem?(item) })
            m.addItem(MenuAction("파일로 저장 후 경로 복사") { AppActions.copyPath?(item) })
            m.addItem(.separator())
            m.addItem(MenuAction("텍스트 추출(OCR)") { if let png = PasteController.pngData(item) { AppActions.ocr?(png) } })
            m.addItem(.separator())
            m.addItem(MenuAction("복제") { [weak self] in PreviewWindow.show(item, near: self?.frame ?? .zero) })
            m.addItem(MenuAction("주석 편집", key: " ") { [weak self] in
                guard let self else { return }
                PinWindow.show(image: image, pixelScale: 1, at: self.frame, edit: true)
                self.close()
            })
        } else {
            m.addItem(MenuAction("전체 복사") { AppActions.copyItem?(item) })
            let edit = MenuAction("수정") { [weak self] in
                guard let id = item.id else { return }
                self?.close()   // 고친 뒤엔 옛 내용이므로 닫는다
                AppActions.editText?(id)
            }
            edit.isEnabled = item.id != nil && [.text, .html, .rtf].contains(item.kind)
            m.addItem(edit)
        }
        m.addItem(.separator())
        m.addItem(MenuAction("닫기", key: "\u{1b}") { [weak self] in self?.close() })
        return m
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 49, let image else { return super.keyDown(with: event) }
        PinWindow.show(image: image, pixelScale: 1, at: frame, edit: true)
        close()
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { close() }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 2 { close() } else { super.mouseUp(with: event) }
    }

    override func sendEvent(_ event: NSEvent) {
        // 이미지 영역 더블클릭도 닫기(스크롤 뷰가 이벤트를 먹으므로 여기서 가로챔)
        if event.type == .leftMouseUp, event.clickCount == 2 { close(); return }
        super.sendEvent(event)
    }

    override func close() {
        super.close()
        Self.open.removeAll { $0 === self }
    }

    private static func image(_ item: ClipItem) -> NSImage? {
        for t in ClipClassifier.imageTypes {
            if let d = item.formats[t], let img = NSImage(data: d) { return img }
        }
        return nil
    }

    private static func text(_ item: ClipItem) -> String {
        if let d = item.formats[ClipClassifier.plainText], let s = String(data: d, encoding: .utf8) { return s }
        return item.previewText
    }
}

/// 우클릭 메뉴를 바꿔 끼울 수 있는 미리보기 뷰들(글자 칸 기본 메뉴 대신 윈도우판 미리보기 메뉴).
private final class MenuImageView: NSImageView {
    var menuProvider: (() -> NSMenu?)?
    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }
}

private final class MenuTextView: NSTextView {
    var menuProvider: (() -> NSMenu?)?
    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() ?? super.menu(for: event) }
}
