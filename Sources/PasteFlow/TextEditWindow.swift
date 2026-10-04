import AppKit

/// 패널 항목의 글자 수정 창. [저장](⌘Enter) / [취소](Esc). 한 번에 하나만 연다.
final class TextEditWindow: NSPanel, NSWindowDelegate {
    private static var current: TextEditWindow?

    private let textView = NSTextView()
    private let onSave: (String) -> Void
    /// 열기 전 맨 앞 앱 — 닫으면 돌려준다(안 그러면 패널 Enter 붙여넣기가 PasteFlow로 들어감).
    private var previousApp: NSRunningApplication?

    static func show(text: String, near frame: NSRect, onSave: @escaping (String) -> Void) {
        current?.close()
        let w = TextEditWindow(text: text, onSave: onSave)
        // 패널 왼쪽에, 화면을 벗어나면 오른쪽에
        let vf = NSScreen.screens.first { $0.frame.intersects(frame) }?.visibleFrame ?? .zero
        var x = frame.minX - w.frame.width - 12
        if x < vf.minX { x = min(frame.maxX + 12, vf.maxX - w.frame.width) }
        w.setFrameOrigin(NSPoint(x: x, y: max(vf.minY, frame.maxY - w.frame.height)))
        current = w
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { w.previousApp = front }
        // LSUIElement 앱 — 활성화가 양보식이라 orderFrontRegardless로 앞에(설정창과 같은 이유)
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
        w.makeFirstResponder(w.textView)
    }

    private init(text: String, onSave: @escaping (String) -> Void) {
        self.onSave = onSave
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
                   styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        title = "글자 수정"
        level = .modalPanel   // 떠 있는 패널보다 위
        appearance = NSAppearance(named: .darkAqua)
        isReleasedWhenClosed = false
        minSize = NSSize(width: 300, height: 180)
        delegate = self

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        textView.string = text
        textView.font = .systemFont(ofSize: 13)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView

        let cancel = NSButton(title: "취소", target: self, action: #selector(cancelClicked))
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "저장", target: self, action: #selector(saveClicked))
        save.keyEquivalent = "\r"
        save.keyEquivalentModifierMask = .command   // Enter는 줄바꿈, ⌘Enter가 저장
        save.toolTip = "⌘Enter"
        let buttons = NSStackView(views: [NSView(), cancel, save])
        buttons.orientation = .horizontal
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(scroll)
        root.addSubview(buttons)
        contentView = root
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            buttons.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            buttons.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
        ])
    }

    @objc private func saveClicked() {
        onSave(textView.string)
        close()
    }

    @objc private func cancelClicked() { close() }

    func windowWillClose(_ notification: Notification) {
        if Self.current === self { Self.current = nil }
        previousApp?.activate()
    }
}
