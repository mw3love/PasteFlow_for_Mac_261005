import AppKit

/// 우하단 짧은 알림(포커스 안 뺏음). 9단계에서 여러 개 쌓기·설정 on/off로 확장 예정.
enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ title: String, detail: String? = nil, duration: TimeInterval = 1.8) {
        let p = panel ?? makePanel()
        panel = p
        let box = p.contentView!
        box.subviews.forEach { $0.removeFromSuperview() }

        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 13, weight: .semibold)
        t.textColor = Theme.coral
        var views: [NSView] = [t]
        if let detail {
            let d = NSTextField(labelWithString: detail)
            d.font = .systemFont(ofSize: 12)
            d.textColor = Theme.text2
            d.lineBreakMode = .byTruncatingMiddle
            d.widthAnchor.constraint(lessThanOrEqualToConstant: 300).isActive = true
            views.append(d)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor), stack.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            stack.topAnchor.constraint(equalTo: box.topAnchor), stack.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        box.layoutSubtreeIfNeeded()
        let size = stack.fittingSize
        let vf = (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)?.visibleFrame ?? .zero
        p.setFrame(NSRect(x: vf.maxX - size.width - 20, y: vf.minY + 20, width: size.width, height: size.height), display: true)
        p.alphaValue = 1
        p.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 }, completionHandler: { p.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private static func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.ignoresMouseEvents = true
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = Theme.bg.cgColor
        box.layer?.cornerRadius = Theme.windowRadius
        box.layer?.borderWidth = 0.5
        box.layer?.borderColor = Theme.border.cgColor
        p.contentView = box
        return p
    }
}
