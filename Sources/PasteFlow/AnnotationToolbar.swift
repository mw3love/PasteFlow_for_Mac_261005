import AppKit
import PasteFlowCore

/// 편집 모드에서 이미지 아래에 붙는 작은 도구 막대(M1 토큰).
/// [도구 8개] | [색 7개] | [− 크기 +] | [되돌리기] [복사]
final class AnnotationToolbar: NSView {
    static let height: CGFloat = 36
    private(set) var fittingWidth: CGFloat = 0

    private weak var canvas: AnnotationCanvas?
    private var toolChips: [(AnnotationTool, ToolbarChip)] = []
    private var swatches: [(UInt32, ToolbarChip)] = []
    private let sizeLabel = NSTextField(labelWithString: "")
    private var undoChip: ToolbarChip!

    private static let toolInfo: [AnnotationTool: (symbol: String, name: String)] = [
        .select: ("cursorarrow", "선택"), .rect: ("rectangle", "네모"), .text: ("textformat", "텍스트"),
        .arrow: ("arrow.up.right", "화살표"), .ellipse: ("circle", "원"), .line: ("line.diagonal", "선"),
        .pen: ("scribble", "펜"), .badge: ("1.circle", "번호"),
    ]

    init(canvas: AnnotationCanvas) {
        self.canvas = canvas
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.bg.cgColor
        layer?.cornerRadius = Theme.itemRadius
        layer?.borderWidth = 0.5
        layer?.borderColor = Theme.border.cgColor

        var x: CGFloat = 5
        let y: CGFloat = 4, s: CGFloat = 28
        func place(_ v: NSView, width: CGFloat) {
            v.frame = NSRect(x: x, y: y, width: width, height: s)
            addSubview(v)
            x += width
        }
        func gap() {
            let line = NSView(frame: NSRect(x: x + 5, y: 9, width: 1, height: 18))
            line.wantsLayer = true
            line.layer?.backgroundColor = Theme.separator.cgColor
            addSubview(line)
            x += 11
        }

        for t in AnnotationTool.allCases {
            let info = Self.toolInfo[t]!
            let chip = ToolbarChip(symbol: info.symbol) { [weak self] in self?.canvas?.tool = t }
            chip.toolTip = "\(info.name) (\(t.digit))"
            toolChips.append((t, chip))
            place(chip, width: s)
        }
        gap()
        for c in AnnotationDefaults.presets {
            let chip = ToolbarChip(symbol: nil) { [weak self] in self?.canvas?.setColor(c) }
            chip.swatch = Theme.rgb(c)
            swatches.append((c, chip))
            place(chip, width: 22)
        }
        gap()
        place(ToolbarChip(symbol: "minus") { [weak self] in self?.canvas?.stepSize(-1) }, width: 24)
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        sizeLabel.textColor = Theme.text2
        sizeLabel.alignment = .center
        sizeLabel.frame = NSRect(x: x, y: y + 6, width: 28, height: 16)
        addSubview(sizeLabel)
        x += 28
        place(ToolbarChip(symbol: "plus") { [weak self] in self?.canvas?.stepSize(1) }, width: 24)
        gap()
        undoChip = ToolbarChip(symbol: "arrow.uturn.backward") { [weak self] in self?.canvas?.undo() }
        undoChip.toolTip = "되돌리기 (⌘Z)"
        place(undoChip, width: s)
        let copy = ToolbarChip(symbol: "checkmark", title: "복사") { [weak self] in self?.canvas?.onCopy?() }
        copy.accent = true
        copy.toolTip = "결과를 클립보드·히스토리로 (Enter · ⌘C)"
        x += 4
        place(copy, width: 62)
        fittingWidth = x + 5
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { true }   // 막대 빈 곳을 끌면 창 이동

    func refresh() {
        guard let canvas else { return }
        for (t, chip) in toolChips { chip.selected = t == canvas.tool }
        let style = canvas.targetStyle
        for (c, chip) in swatches { chip.selected = c == style.color }
        sizeLabel.stringValue = "\(Int(style.size.rounded()))"
        sizeLabel.toolTip = canvas.targetTool == .text ? "글자 크기 ([ ])" : canvas.targetTool == .badge ? "번호 크기 ([ ])" : "두께 ([ ])"
        undoChip.enabled = canvas.doc.canUndo
    }
}

/// 막대 안 작은 버튼: SF Symbol 아이콘, 색 견본, 또는 아이콘+글자.
final class ToolbarChip: NSView {
    var selected = false { didSet { needsDisplay = true } }
    var enabled = true { didSet { needsDisplay = true } }
    var accent = false
    var swatch: NSColor?
    private let image: NSImage?
    private let title: String?
    private let action: () -> Void
    private var hover = false
    private var tracking: NSTrackingArea?

    init(symbol: String?, title: String? = nil, action: @escaping () -> Void) {
        image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium)) }
        self.title = title
        self.action = action
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(t)
        tracking = t
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if enabled, bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 2, dy: 1)
        if let swatch {
            let d: CGFloat = 14
            let r = NSRect(x: bounds.midX - d / 2, y: bounds.midY - d / 2, width: d, height: d)
            if selected {
                let ring = NSBezierPath(ovalIn: r.insetBy(dx: -3, dy: -3))
                ring.lineWidth = 1.5
                Theme.coral.setStroke()
                ring.stroke()
            }
            swatch.setFill()
            let dot = NSBezierPath(ovalIn: r)
            dot.fill()
            NSColor(white: 1, alpha: 0.25).setStroke()
            dot.lineWidth = 0.5
            dot.stroke()
            return
        }
        if accent {
            Theme.coral.setFill()
            NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        } else if selected {
            Theme.coralFill.setFill()
            NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        } else if hover && enabled {
            Theme.itemHover.setFill()
            NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        }
        let ink: NSColor = accent ? Theme.bg : !enabled ? Theme.dim : selected ? Theme.coral : Theme.text2
        var contentW: CGFloat = 0
        var titleStr: NSAttributedString?
        if let title {
            titleStr = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                                                                       .foregroundColor: ink])
            contentW += titleStr!.size().width + 4
        }
        if let image { contentW += image.size.width }
        var x = bounds.midX - contentW / 2
        if let image {
            let tinted = NSImage(size: image.size, flipped: false) { r in
                image.draw(in: r)
                ink.set()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: x, y: bounds.midY - image.size.height / 2, width: image.size.width, height: image.size.height))
            x += image.size.width + 4
        }
        if let titleStr {
            let sz = titleStr.size()
            titleStr.draw(at: NSPoint(x: x, y: bounds.midY - sz.height / 2))
        }
    }
}
