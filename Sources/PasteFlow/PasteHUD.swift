import AppKit
import PasteFlowCore

/// 순차 붙여넣기 진행 HUD — 포커스를 뺏지 않는 작은 창(우하단). 디자인은 PLAN.md "디자인 테마"(M1).
final class PasteHUD {
    static let width: CGFloat = 340
    static let maxRows = 8
    static let finishLinger: TimeInterval = 1.2

    var onCancel: (() -> Void)?

    private let panel: NSPanel
    private let titleLabel = NSTextField(labelWithString: "순차 붙여넣기")
    private let countLabel = NSTextField(labelWithString: "")
    private let rows = NSStackView()
    private var finishWork: DispatchWorkItem?

    private enum Theme {
        static let bg = NSColor(srgbRed: 0x16 / 255, green: 0x16 / 255, blue: 0x18 / 255, alpha: 1)
        static let text = NSColor(srgbRed: 0xec / 255, green: 0xec / 255, blue: 0xec / 255, alpha: 1)
        static let text2 = NSColor(srgbRed: 0xcf / 255, green: 0xcf / 255, blue: 0xd2 / 255, alpha: 1)
        static let dim = NSColor(srgbRed: 0x6e / 255, green: 0x6e / 255, blue: 0x73 / 255, alpha: 1)
        static let secondary = NSColor(srgbRed: 0x98 / 255, green: 0x98 / 255, blue: 0x9d / 255, alpha: 1)
        static let coral = NSColor(srgbRed: 0xfa / 255, green: 0xb3 / 255, blue: 0x87 / 255, alpha: 1)
    }

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 80),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = Theme.bg.cgColor
        box.layer?.cornerRadius = 12
        box.layer?.borderWidth = 0.5
        box.layer?.borderColor = NSColor(white: 1, alpha: 0.16).cgColor
        panel.contentView = box

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = Theme.coral
        countLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        countLabel.textColor = Theme.coral

        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "취소")!,
                             target: self, action: #selector(cancelClicked))
        close.isBordered = false
        close.contentTintColor = Theme.secondary
        close.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
        close.toolTip = "순차 붙여넣기 취소"

        let header = NSStackView(views: [titleLabel, countLabel, NSView(), close])
        header.orientation = .horizontal
        header.spacing = 8

        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 3

        let stack = NSStackView(views: [header, rows])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            stack.topAnchor.constraint(equalTo: box.topAnchor),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: Self.width),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -30),
        ])
    }

    /// 표시·갱신. pointer = 이미 붙인 개수.
    func show(items: [ClipItem], pointer: Int) {
        finishWork?.cancel()
        finishWork = nil
        countLabel.stringValue = "\(pointer)/\(items.count)"
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // 항목이 많으면 다음 항목 주변만 보여준다
        let start = max(0, min(pointer - 2, items.count - Self.maxRows))
        let end = min(items.count, start + Self.maxRows)
        for i in start..<end {
            rows.addArrangedSubview(row(index: i, item: items[i], pointer: pointer))
        }

        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? NSSize(width: Self.width, height: 80)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: vf.maxX - size.width - 20, y: vf.minY + 20, width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    /// 소진 완료 — 마지막 상태를 잠시 보여주고 사라진다.
    func finish() {
        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.finishLinger, execute: work)
    }

    func dismiss() {
        finishWork?.cancel()
        finishWork = nil
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in self?.panel.orderOut(nil) })
    }

    @objc private func cancelClicked() { onCancel?() }

    private func row(index: Int, item: ClipItem, pointer: Int) -> NSView {
        let done = index < pointer, isNext = index == pointer
        let mark: NSView
        if done || isNext {
            let iv = NSImageView(image: NSImage(systemSymbolName: done ? "checkmark" : "play.fill", accessibilityDescription: nil)!)
            iv.symbolConfiguration = .init(pointSize: 9, weight: .bold)
            iv.contentTintColor = done ? Theme.dim : Theme.coral
            mark = iv
        } else {
            let dot = NSTextField(labelWithString: "·")
            dot.textColor = Theme.text2
            mark = dot
        }
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.widthAnchor.constraint(equalToConstant: 12).isActive = true

        let text = item.previewText.replacingOccurrences(of: "\n", with: " ")
        let label = NSTextField(labelWithString: "\(index + 1). \(text)")
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: 12, weight: isNext ? .semibold : .regular)
        label.textColor = done ? Theme.dim : (isNext ? Theme.text : Theme.text2)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let r = NSStackView(views: [mark, label])
        r.orientation = .horizontal
        r.spacing = 8
        r.translatesAutoresizingMaskIntoConstraints = false
        r.widthAnchor.constraint(equalToConstant: Self.width - 30).isActive = true
        return r
    }
}
