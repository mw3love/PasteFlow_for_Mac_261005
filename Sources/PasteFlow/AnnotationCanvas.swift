import AppKit
import PasteFlowCore

/// 주석을 그린다. 화면(편집 판)과 결과 PNG 만들기가 같은 코드를 쓴다 — 좌표는 뒤집힌(왼쪽 위 원점) 이미지 포인트.
enum AnnotationRenderer {
    static func font(_ size: CGFloat) -> NSFont { .systemFont(ofSize: size, weight: .semibold) }

    static func measure(_ s: String, size: CGFloat) -> CGSize {
        let str = NSAttributedString(string: s.isEmpty ? " " : s, attributes: [.font: font(size)])
        let r = str.boundingRect(with: NSSize(width: 100_000, height: 100_000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return CGSize(width: ceil(r.width), height: ceil(r.height))
    }

    static func draw(_ a: Annotation) {
        let color = Theme.rgb(a.color)
        color.set()
        switch a.shape {
        case .rect(let r):
            stroke(NSBezierPath(rect: r.standardized), a.size)
        case .ellipse(let r):
            stroke(NSBezierPath(ovalIn: r.standardized), a.size)
        case .line(let s, let e):
            stroke(segment(s, e), a.size)
        case .arrow(let s, let e):
            let head = Annotation.arrowHead(tail: s, tip: e, width: a.size)
            // 굵은 선이 화살촉 끝으로 삐져나오지 않게, 몸통은 촉 밑변 중간까지만
            let base = CGPoint(x: (head[1].x + head[2].x) / 2, y: (head[1].y + head[2].y) / 2)
            let len = Annotation.distance(s, e), back = Annotation.distance(base, e)
            if len > back { stroke(segment(s, base), a.size) }
            let tri = NSBezierPath()
            tri.move(to: head[0]); tri.line(to: head[1]); tri.line(to: head[2]); tri.close()
            tri.lineJoinStyle = .round
            tri.lineWidth = 1
            tri.fill()
            tri.stroke()
        case .pen(let pts):
            guard let first = pts.first else { return }
            if pts.count == 1 {
                NSBezierPath(ovalIn: NSRect(x: first.x - a.size / 2, y: first.y - a.size / 2, width: a.size, height: a.size)).fill()
                return
            }
            let p = NSBezierPath()
            p.move(to: first)
            pts.dropFirst().forEach { p.line(to: $0) }
            stroke(p, a.size)
        case .badge(let c, let n):
            let r = a.size / 2
            let circle = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: a.size, height: a.size))
            circle.fill()
            NSColor.white.set()
            circle.lineWidth = max(1, a.size / 15)
            circle.stroke()
            let ink: NSColor = luminance(a.color) > 0.75 ? .black : .white
            let str = NSAttributedString(string: "\(n)", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: a.size * 0.45, weight: .bold), .foregroundColor: ink])
            let sz = str.size()
            str.draw(at: NSPoint(x: c.x - sz.width / 2, y: c.y - sz.height / 2))
        case .text(let o, let s, _):
            NSAttributedString(string: s, attributes: [.font: font(a.size), .foregroundColor: color])
                .draw(with: NSRect(x: o.x, y: o.y, width: 100_000, height: 100_000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
    }

    private static func segment(_ a: CGPoint, _ b: CGPoint) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: a)
        p.line(to: b)
        return p
    }

    private static func stroke(_ p: NSBezierPath, _ width: CGFloat) {
        p.lineWidth = width
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        p.stroke()
    }

    static func luminance(_ hex: UInt32) -> CGFloat {
        let r = CGFloat((hex >> 16) & 0xff), g = CGFloat((hex >> 8) & 0xff), b = CGFloat(hex & 0xff)
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255
    }

    /// 이미지 + 주석을 원본 픽셀 크기 PNG로(배율 기록은 원본과 같게 — 캡처는 144dpi).
    static func renderPNG(image: NSImage, items: [Annotation]) -> Data? {
        let rep = image.representations.first
        let pw = max(1, rep?.pixelsWide ?? 0 > 0 ? rep!.pixelsWide : Int(image.size.width))
        let ph = max(1, rep?.pixelsHigh ?? 0 > 0 ? rep!.pixelsHigh : Int(image.size.height))
        guard image.size.width > 0,
              let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let s = CGFloat(pw) / image.size.width
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: s, y: -s)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        image.draw(in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .copy, fraction: 1,
                   respectFlipped: true, hints: nil)
        items.forEach(draw)
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = ctx.makeImage() else { return nil }
        let out = NSBitmapImageRep(cgImage: cg)
        out.size = image.size
        return out.representation(using: .png, properties: [:])
    }
}

/// 핀 창 안의 이미지 + 주석 판. 보기 모드에서는 끌면 창 이동·더블클릭 닫기, 편집 모드(Space)에서는 그리기.
final class AnnotationCanvas: NSView, NSTextViewDelegate {
    /// 도구별 색·크기 기본값 — 모든 핀이 함께 쓰고 DB 설정에 저장한다.
    static var settingsDB: ClipDatabase?
    private static var _defaults: AnnotationDefaults?
    static var defaults: AnnotationDefaults {
        get {
            if let d = _defaults { return d }
            let d = AnnotationDefaults.from(json: (try? settingsDB?.setting(AnnotationDefaults.settingKey)) ?? nil)
            _defaults = d
            return d
        }
        set {
            _defaults = newValue
            try? settingsDB?.setSetting(AnnotationDefaults.settingKey, newValue.json())
        }
    }
    private static var lastTool: AnnotationTool = .rect

    let image: NSImage
    let doc = AnnotationDocument()
    var onClose: (() -> Void)?
    var onToggleEdit: (() -> Void)?
    var onCopy: (() -> Void)?
    /// 도구 막대 갱신(도구·선택·되돌리기 상태가 바뀔 때).
    var onStateChange: (() -> Void)?

    var editing = false {
        didSet {
            commitText()
            selection = nil
            if editing { tool = Self.lastTool }
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }
    var tool: AnnotationTool = .rect {
        didSet {
            Self.lastTool = tool
            window?.invalidateCursorRects(for: self)
            onStateChange?()
        }
    }
    private(set) var selection: Int? {
        didSet { needsDisplay = true; onStateChange?() }
    }

    private enum Drag {
        case none
        case create(Int, start: CGPoint)
        case move(Int, last: CGPoint)
        case handle(Int, Annotation.Handle)
        case pen(Int)
    }
    private var drag: Drag = .none
    private var downPoint: NSPoint = .zero
    private var textView: AnnotationTextView?
    private var editingTextID: Int?

    init(image: NSImage) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { !editing }

    private var scale: CGFloat { image.size.width > 0 ? bounds.width / image.size.width : 1 }
    private func toImage(_ p: NSPoint) -> CGPoint { CGPoint(x: p.x / scale, y: p.y / scale) }

    // MARK: 도구 막대가 읽고 쓰는 값

    /// 색·크기 조절 대상: 선택된 주석이 있으면 그 주석, 없으면 지금 도구.
    var targetTool: AnnotationTool {
        if let id = selection ?? editingTextID, let a = doc.item(id) { return Self.tool(for: a) }
        return tool
    }

    var targetStyle: AnnotationDefaults.Style {
        if let id = selection ?? editingTextID, let a = doc.item(id) { return .init(color: a.color, size: a.size) }
        return Self.defaults.style(for: tool)
    }

    func setColor(_ color: UInt32) {
        applyStyle(.init(color: color, size: targetStyle.size))
    }

    func stepSize(_ dir: CGFloat) {
        let r = AnnotationDefaults.range(for: targetTool)
        applyStyle(.init(color: targetStyle.color, size: min(max(targetStyle.size + dir * r.step, r.min), r.max)))
    }

    private func applyStyle(_ style: AnnotationDefaults.Style) {
        Self.defaults.set(style, for: targetTool)
        if let id = selection ?? editingTextID, var a = doc.item(id) {
            a.color = style.color
            a.size = style.size
            if case .text(let o, let s, _) = a.shape {
                a.shape = .text(origin: o, string: s, measured: AnnotationRenderer.measure(s, size: a.size))
            }
            doc.update(a)   // 바뀐 게 없으면 되돌리기 기록도 안 남는다
            if editingTextID == id, let tv = textView { styleTextView(tv, a) }
        }
        needsDisplay = true
        onStateChange?()
    }

    func undo() {
        commitText()
        if doc.undo() { selection = nil; needsDisplay = true; onStateChange?() }
    }

    func redo() {
        commitText()
        if doc.redo() { selection = nil; needsDisplay = true; onStateChange?() }
    }

    private static func tool(for a: Annotation) -> AnnotationTool {
        switch a.shape {
        case .rect: return .rect
        case .ellipse: return .ellipse
        case .line: return .line
        case .arrow: return .arrow
        case .pen: return .pen
        case .badge: return .badge
        case .text: return .text
        }
    }

    // MARK: 그리기

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)
        for a in doc.items where a.id != editingTextID { AnnotationRenderer.draw(a) }
        ctx.restoreGState()

        if editing, let id = selection, let a = doc.item(id) { drawSelection(a) }
        // 테두리: 편집 중엔 코랄, 보기 모드는 흐린 선
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = editing ? 1.5 : 0.5
        (editing ? Theme.coral : Theme.border).setStroke()
        border.stroke()
    }

    private func drawSelection(_ a: Annotation) {
        let b = a.bounds
        let r = NSRect(x: b.minX * scale, y: b.minY * scale, width: b.width * scale, height: b.height * scale).insetBy(dx: -3, dy: -3)
        let box = NSBezierPath(rect: r)
        box.lineWidth = 1
        box.setLineDash([4, 3], count: 2, phase: 0)
        NSColor.white.withAlphaComponent(0.9).setStroke()
        box.stroke()
        for h in a.handles {
            let p = a.point(of: h)
            let c = NSPoint(x: p.x * scale, y: p.y * scale)
            let dot = h == .resize ? NSBezierPath(rect: NSRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9))
                                   : NSBezierPath(ovalIn: NSRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10))
            Theme.coral.setFill()
            dot.fill()
            NSColor.white.setStroke()
            dot.lineWidth = 1.5
            dot.stroke()
        }
    }

    override func resetCursorRects() {
        if editing && tool != .select { addCursorRect(bounds, cursor: .crosshair) }
    }

    // MARK: 마우스

    override func mouseDown(with event: NSEvent) {
        guard editing else {
            if event.clickCount == 2 { onClose?() } else { super.mouseDown(with: event) }
            return
        }
        if textView != nil {   // 글자 칸 바깥을 누르면 글자 입력만 끝낸다
            commitText()
            return
        }
        window?.makeFirstResponder(self)
        let vp = convert(event.locationInWindow, from: nil)
        downPoint = vp
        let p = toImage(vp)
        let tol = 6 / scale

        if event.clickCount == 2, let hit = doc.topmost(at: p, tolerance: tol, interior: true), case .text = hit.shape {
            beginTextEdit(hit.id)
            return
        }
        // 선택된 주석의 손잡이(화면 기준 지름 20pt 안이면 잡힘)
        if let id = selection, let a = doc.item(id),
           let h = a.handles.first(where: { Annotation.distance(a.point(of: $0), p) <= 10 / scale }) {
            doc.begin()
            drag = .handle(id, h)
            return
        }
        let style = Self.defaults.style(for: tool)
        if tool == .pen {   // 펜은 주석 위에서도 늘 새로 그린다
            selection = nil
            doc.begin()
            drag = .pen(doc.add(Annotation(shape: .pen([p]), color: style.color, size: style.size)))
            return
        }
        if let hit = doc.topmost(at: p, tolerance: tol, interior: tool == .select) {
            selection = hit.id
            doc.begin()
            drag = .move(hit.id, last: p)
            return
        }
        selection = nil
        switch tool {
        case .select, .pen:
            return
        case .text:
            let size = AnnotationRenderer.measure("", size: style.size)
            doc.begin()
            let id = doc.add(Annotation(shape: .text(origin: CGPoint(x: p.x, y: p.y - size.height / 2), string: "", measured: size),
                                        color: style.color, size: style.size))
            beginTextEdit(id)
        case .badge:
            doc.begin()
            let id = doc.add(Annotation(shape: .badge(center: p, number: doc.nextBadgeNumber), color: style.color, size: style.size))
            selection = id
            drag = .move(id, last: p)   // 놓기 전 끌면 그대로 옮겨진다
        case .rect, .ellipse, .line, .arrow:
            doc.begin()
            drag = .create(doc.add(Annotation(shape: shape(tool, p, p), color: style.color, size: style.size)), start: p)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard editing else { return super.mouseDragged(with: event) }
        let p = toImage(convert(event.locationInWindow, from: nil))
        let shift = event.modifierFlags.contains(.shift)
        switch drag {
        case .none:
            return
        case .create(let id, let start):
            guard var a = doc.item(id) else { return }
            let q: CGPoint
            switch tool {
            case .rect, .ellipse: q = shift ? Annotation.square(from: start, to: p) : p
            default: q = shift ? Annotation.snap45(from: start, to: p) : p
            }
            a.shape = shape(tool, start, q)
            doc.update(a)
        case .move(let id, let last):
            guard let a = doc.item(id) else { return }
            doc.update(a.moved(by: CGVector(dx: p.x - last.x, dy: p.y - last.y)))
            drag = .move(id, last: p)
        case .handle(let id, let h):
            guard let a = doc.item(id) else { return }
            doc.update(a.resized(h, to: p, constrain: shift))
        case .pen(let id):
            guard var a = doc.item(id), case .pen(var pts) = a.shape else { return }
            if let last = pts.last, Annotation.distance(last, p) * scale < 1 { return }
            pts.append(p)
            a.shape = .pen(pts)
            doc.update(a)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard editing else { return super.mouseUp(with: event) }
        let vp = convert(event.locationInWindow, from: nil)
        if case .create(let id, _) = drag {
            // 4pt 미만으로 끌었으면 실수 클릭 — 버린다(윈도우판 규칙)
            if hypot(vp.x - downPoint.x, vp.y - downPoint.y) < 4 {
                doc.remove(id)
                selection = nil
            } else {
                selection = id
            }
        }
        if case .none = drag {} else { doc.end() }
        drag = .none
        needsDisplay = true
        onStateChange?()
    }

    private func shape(_ tool: AnnotationTool, _ a: CGPoint, _ b: CGPoint) -> Annotation.Shape {
        let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        switch tool {
        case .ellipse: return .ellipse(r)
        case .line: return .line(a, b)
        case .arrow: return .arrow(a, b)
        default: return .rect(r)
        }
    }

    // MARK: 키

    override func keyDown(with event: NSEvent) {
        let cmd = event.modifierFlags.contains(.command), shift = event.modifierFlags.contains(.shift)
        guard editing else {
            if event.keyCode == 49 && !cmd { onToggleEdit?() } else { super.keyDown(with: event) }
            return
        }
        // 한글 입력 중에도 되도록 문자 대신 키 코드로 판정
        let digitKeys: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8]
        switch event.keyCode {
        case 53:   // Esc: 선택 해제 → 한 번 더 누르면 편집 끝
            if selection != nil { selection = nil } else { onToggleEdit?() }
        case 49 where !cmd:
            onToggleEdit?()
        case 36, 76:
            onCopy?()
        case 8 where cmd:
            onCopy?()
        case 6 where cmd:
            shift ? redo() : undo()
        case 51, 117:
            if let id = selection { doc.remove(id); selection = nil }
        case 123, 124, 125, 126:
            guard let id = selection, let a = doc.item(id) else { return }
            let step = (shift ? 1 : 10) / scale
            let d: CGVector = [123: CGVector(dx: -step, dy: 0), 124: CGVector(dx: step, dy: 0),
                               125: CGVector(dx: 0, dy: step), 126: CGVector(dx: 0, dy: -step)][event.keyCode]!
            doc.update(a.moved(by: d))
            needsDisplay = true
        case 33:
            stepSize(-1)
        case 30:
            stepSize(1)
        default:
            if !cmd, let n = digitKeys[event.keyCode], let t = AnnotationTool.forDigit(n) {
                tool = t
            } else {
                super.keyDown(with: event)
            }
        }
    }

    // MARK: 글자

    private func beginTextEdit(_ id: Int) {
        guard let a = doc.item(id), case .text(let o, let s, _) = a.shape else { return }
        doc.begin()
        selection = nil
        editingTextID = id
        let tv = AnnotationTextView(frame: NSRect(x: o.x * scale, y: o.y * scale, width: 10, height: 10))
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: 100_000, height: 100_000)
        tv.maxSize = NSSize(width: 100_000, height: 100_000)
        tv.string = s
        styleTextView(tv, a)
        tv.delegate = self
        tv.onCommit = { [weak self] in self?.commitText() }
        addSubview(tv)
        textView = tv
        window?.makeFirstResponder(tv)
        needsDisplay = true
        onStateChange?()
    }

    private func styleTextView(_ tv: NSTextView, _ a: Annotation) {
        let c = Theme.rgb(a.color)
        tv.font = AnnotationRenderer.font(a.size * scale)
        tv.textColor = c
        tv.insertionPointColor = c
        tv.typingAttributes = [.font: AnnotationRenderer.font(a.size * scale), .foregroundColor: c]
        fitTextView()
    }

    func textDidChange(_ notification: Notification) { fitTextView() }

    private func fitTextView() {
        guard let tv = textView ?? subviews.compactMap({ $0 as? AnnotationTextView }).first,
              let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        let lineH = lm.defaultLineHeight(for: tv.font ?? .systemFont(ofSize: 13))
        tv.setFrameSize(NSSize(width: max(ceil(used.width) + 4, 8), height: max(ceil(used.height), lineH)))
    }

    /// 글자 입력을 끝낸다(⌘Enter·Esc·바깥 클릭). 빈 글자는 지운다.
    func commitText() {
        guard let tv = textView, let id = editingTextID else { return }
        textView = nil
        editingTextID = nil
        tv.removeFromSuperview()
        if var a = doc.item(id), case .text(let o, _, _) = a.shape {
            let s = tv.string
            if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                doc.remove(id)
            } else {
                a.shape = .text(origin: o, string: s, measured: AnnotationRenderer.measure(s, size: a.size))
                doc.update(a)
                selection = id
            }
        }
        doc.end()
        window?.makeFirstResponder(self)
        needsDisplay = true
        onStateChange?()
    }
}

/// 주석 글자 입력 칸. Enter는 줄바꿈, ⌘Enter·Esc로 끝낸다(윈도우판 Ctrl+Enter).
final class AnnotationTextView: NSTextView {
    var onCommit: (() -> Void)?
    override var mouseDownCanMoveWindow: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || ((event.keyCode == 36 || event.keyCode == 76) && event.modifierFlags.contains(.command)) {
            // 한글 조합 중이면 조합부터 확정
            if hasMarkedText() { unmarkText() }
            onCommit?()
            return
        }
        super.keyDown(with: event)
    }
}
