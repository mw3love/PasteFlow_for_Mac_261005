import CoreGraphics
import Foundation

/// 주석 편집기 도구. 순서·숫자키는 윈도우판(v1.33)과 같다: 1 선택 · 2 네모 · 3 텍스트 · 4 화살표 · 5 원 · 6 선 · 7 펜 · 8 번호.
public enum AnnotationTool: String, Codable, CaseIterable {
    case select, rect, text, arrow, ellipse, line, pen, badge

    /// 숫자키(1~8) → 도구.
    public static func forDigit(_ n: Int) -> AnnotationTool? {
        (1...allCases.count).contains(n) ? allCases[n - 1] : nil
    }

    public var digit: Int { Self.allCases.firstIndex(of: self)! + 1 }

    /// 끌어서 만드는 도형 — 4pt 미만으로 끌면 실수 클릭으로 보고 버린다.
    public var isDragShape: Bool { [.rect, .ellipse, .line, .arrow].contains(self) }
}

/// 이미지 좌표(왼쪽 위 원점, 아래로 y 증가, 단위 = 이미지 포인트) 위의 주석 하나.
public struct Annotation: Equatable {
    public enum Shape: Equatable {
        case rect(CGRect)
        case ellipse(CGRect)
        case line(CGPoint, CGPoint)
        case arrow(CGPoint, CGPoint)   // 첫 점 = 꼬리, 둘째 점 = 화살촉
        case pen([CGPoint])
        case badge(center: CGPoint, number: Int)
        /// `measured`는 앱이 글꼴로 잰 글자 상자 크기(로직은 글꼴을 모르므로 받아서 쓴다).
        case text(origin: CGPoint, string: String, measured: CGSize)
    }

    /// 손잡이: 네모·원·펜·텍스트·번호는 오른쪽 아래 하나(크기), 선·화살표는 양 끝점.
    public enum Handle: Equatable { case resize, start, end }

    public var id: Int
    public var shape: Shape
    public var color: UInt32        // 0xRRGGBB
    /// 도형·선·펜 = 두께, 텍스트 = 글자 크기, 번호 = 지름.
    public var size: CGFloat

    public init(id: Int = 0, shape: Shape, color: UInt32, size: CGFloat) {
        self.id = id
        self.shape = shape
        self.color = color
        self.size = size
    }

    // MARK: 경계

    /// 그려지는 내용의 경계(획 두께·화살촉 포함). 선택 상자·손잡이 위치의 기준.
    public var bounds: CGRect {
        let half = size / 2
        switch shape {
        case .rect(let r), .ellipse(let r):
            return r.standardized.insetBy(dx: -half, dy: -half)
        case .line(let a, let b):
            return CGRect(p1: a, p2: b).insetBy(dx: -half, dy: -half)
        case .arrow(let a, let b):
            var r = CGRect(p1: a, p2: b).insetBy(dx: -half, dy: -half)
            for p in Self.arrowHead(tail: a, tip: b, width: size) { r = r.union(CGRect(origin: p, size: .zero)) }
            return r
        case .pen(let pts):
            guard let first = pts.first else { return .null }
            return pts.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
                .insetBy(dx: -half, dy: -half)
        case .badge(let c, _):
            return CGRect(x: c.x - half, y: c.y - half, width: size, height: size)
        case .text(let o, _, let m):
            return CGRect(origin: o, size: m)
        }
    }

    /// 화살촉 삼각형(촉 + 뒤쪽 두 점). 크기는 두께에서 계산(두께 6 → 약 22, 윈도우판 기본 머리 크기).
    public static func arrowHead(tail: CGPoint, tip: CGPoint, width: CGFloat) -> [CGPoint] {
        let head = 12 + width * 1.7
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let a1 = angle + .pi * 150 / 180, a2 = angle - .pi * 150 / 180
        return [tip,
                CGPoint(x: tip.x + head * cos(a1), y: tip.y + head * sin(a1)),
                CGPoint(x: tip.x + head * cos(a2), y: tip.y + head * sin(a2))]
    }

    // MARK: 클릭 판정

    /// `interior`가 true면 네모·원 안쪽도 맞은 것으로 본다(선택 도구). 그리기 도구에서는 획 위만 —
    /// 그래야 네모 안에서 새 화살표를 시작할 수 있다. 텍스트·번호는 언제나 상자 전체.
    public func contains(_ p: CGPoint, tolerance: CGFloat, interior: Bool) -> Bool {
        let band = size / 2 + tolerance
        switch shape {
        case .rect(let r):
            let r = r.standardized
            if interior { return r.insetBy(dx: -band, dy: -band).contains(p) }
            return r.insetBy(dx: -band, dy: -band).contains(p) && !r.insetBy(dx: band, dy: band).contains(p)
        case .ellipse(let r):
            let r = r.standardized
            let rx = r.width / 2, ry = r.height / 2
            guard rx > 0, ry > 0 else { return Self.distance(p, CGPoint(x: r.midX, y: r.midY)) <= band }
            let dx = p.x - r.midX, dy = p.y - r.midY
            // 반지름을 band만큼 넓힌/좁힌 두 타원 사이면 획 위
            func inside(_ ax: CGFloat, _ ay: CGFloat) -> Bool {
                guard ax > 0, ay > 0 else { return false }
                return (dx * dx) / (ax * ax) + (dy * dy) / (ay * ay) <= 1
            }
            if interior { return inside(rx + band, ry + band) }
            return inside(rx + band, ry + band) && !inside(rx - band, ry - band)
        case .line(let a, let b):
            return Self.distance(p, segment: a, b) <= band
        case .arrow(let a, let b):
            return Self.distance(p, segment: a, b) <= band || bounds(ofHead: a, b).insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        case .pen(let pts):
            if pts.count == 1 { return Self.distance(p, pts[0]) <= band }
            return zip(pts, pts.dropFirst()).contains { Self.distance(p, segment: $0, $1) <= band }
        case .badge(let c, _):
            return Self.distance(p, c) <= size / 2 + tolerance
        case .text:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        }
    }

    private func bounds(ofHead a: CGPoint, _ b: CGPoint) -> CGRect {
        let h = Self.arrowHead(tail: a, tip: b, width: size)
        return h.dropFirst().reduce(CGRect(origin: h[0], size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    // MARK: 손잡이

    public var handles: [Handle] {
        switch shape {
        case .line, .arrow: return [.start, .end]
        default: return [.resize]
        }
    }

    public func point(of handle: Handle) -> CGPoint {
        switch (shape, handle) {
        case (.line(let a, _), .start), (.arrow(let a, _), .start): return a
        case (.line(_, let b), .end), (.arrow(_, let b), .end): return b
        case (.rect(let r), _), (.ellipse(let r), _): return CGPoint(x: r.standardized.maxX, y: r.standardized.maxY)
        default: return CGPoint(x: bounds.maxX, y: bounds.maxY)
        }
    }

    /// 손잡이를 `p`로 끈 결과. 네모·원은 왼쪽 위 고정(⇧ = 정사각·정원), 선·화살표는 그 끝점(⇧ = 45° 단위),
    /// 펜은 왼쪽 위 기준 가로·세로 비율, 텍스트·번호는 같은 비율로 키운다(글자 크기·지름이 바뀜).
    public func resized(_ handle: Handle, to p: CGPoint, constrain: Bool) -> Annotation {
        var a = self
        switch shape {
        case .rect(let r), .ellipse(let r):
            let o = r.standardized.origin
            let q = constrain ? Self.square(from: o, to: p) : p
            let nr = CGRect(x: o.x, y: o.y, width: max(1, q.x - o.x), height: max(1, q.y - o.y))
            if case .rect = shape { a.shape = .rect(nr) } else { a.shape = .ellipse(nr) }
        case .line(let s, let e), .arrow(let s, let e):
            let (ns, ne) = handle == .start ? (constrain ? Self.snap45(from: e, to: p) : p, e)
                                            : (s, constrain ? Self.snap45(from: s, to: p) : p)
            if case .line = shape { a.shape = .line(ns, ne) } else { a.shape = .arrow(ns, ne) }
        case .pen(let pts):
            let b = bounds.insetBy(dx: size / 2, dy: size / 2)
            let sx = b.width > 0.5 ? max(1, p.x - b.minX - size / 2) / b.width : 1
            let sy = b.height > 0.5 ? max(1, p.y - b.minY - size / 2) / b.height : 1
            a.shape = .pen(pts.map { CGPoint(x: b.minX + ($0.x - b.minX) * sx, y: b.minY + ($0.y - b.minY) * sy) })
        case .text(let o, let s, let m):
            guard m.height > 0 else { return a }
            let f = max(6 / size, (p.y - o.y) / m.height)
            a.size = size * f
            a.shape = .text(origin: o, string: s, measured: CGSize(width: m.width * f, height: m.height * f))
        case .badge(let c, _):
            a.size = min(max(2 * max(p.x - c.x, p.y - c.y), 12), 120)
        }
        return a
    }

    public func moved(by d: CGVector) -> Annotation {
        var a = self
        func m(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + d.dx, y: p.y + d.dy) }
        switch shape {
        case .rect(let r): a.shape = .rect(r.offsetBy(dx: d.dx, dy: d.dy))
        case .ellipse(let r): a.shape = .ellipse(r.offsetBy(dx: d.dx, dy: d.dy))
        case .line(let s, let e): a.shape = .line(m(s), m(e))
        case .arrow(let s, let e): a.shape = .arrow(m(s), m(e))
        case .pen(let pts): a.shape = .pen(pts.map(m))
        case .badge(let c, let n): a.shape = .badge(center: m(c), number: n)
        case .text(let o, let s, let ms): a.shape = .text(origin: m(o), string: s, measured: ms)
        }
        return a
    }

    // MARK: 기하 도우미

    /// ⇧: 정사각·정원 — 긴 변에 맞추고 끄는 방향은 유지.
    public static func square(from o: CGPoint, to p: CGPoint) -> CGPoint {
        let dx = p.x - o.x, dy = p.y - o.y
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: o.x + (dx < 0 ? -side : side), y: o.y + (dy < 0 ? -side : side))
    }

    /// ⇧: 선·화살표 각도를 45° 단위로.
    public static func snap45(from o: CGPoint, to p: CGPoint) -> CGPoint {
        let dx = p.x - o.x, dy = p.y - o.y
        let len = hypot(dx, dy)
        let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
        return CGPoint(x: o.x + len * cos(angle), y: o.y + len * sin(angle))
    }

    public static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    public static func distance(_ p: CGPoint, segment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let vx = b.x - a.x, vy = b.y - a.y
        let len2 = vx * vx + vy * vy
        guard len2 > 0 else { return distance(p, a) }
        let t = min(max(((p.x - a.x) * vx + (p.y - a.y) * vy) / len2, 0), 1)
        return distance(p, CGPoint(x: a.x + t * vx, y: a.y + t * vy))
    }
}

private extension CGRect {
    init(p1: CGPoint, p2: CGPoint) {
        self.init(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p1.x - p2.x), height: abs(p1.y - p2.y))
    }
}

/// 주석 목록 + 되돌리기. 변경은 `begin()` … `end()`로 묶는다 — 끄는 동안 여러 번 바꿔도 되돌리기는 한 번.
public final class AnnotationDocument {
    public private(set) var items: [Annotation] = []
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    private var pending: [Annotation]?
    private var nextID = 1

    public init() {}

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var isEmpty: Bool { items.isEmpty }

    /// 다음 번호 배지 — 남아 있는 번호 중 가장 큰 것 + 1(되돌리거나 지우면 자연히 줄어든다).
    public var nextBadgeNumber: Int {
        items.compactMap { if case .badge(_, let n) = $0.shape { return n } else { return nil } }.max().map { $0 + 1 } ?? 1
    }

    public func item(_ id: Int) -> Annotation? { items.first { $0.id == id } }

    // MARK: 변경 묶음

    public func begin() {
        if pending == nil { pending = items }
    }

    /// 묶음 안에서 실제로 바뀐 게 있을 때만 되돌리기 기록을 남긴다.
    public func end() {
        guard let before = pending else { return }
        pending = nil
        if before != items {
            undoStack.append(before)
            redoStack.removeAll()
        }
    }

    @discardableResult
    public func add(_ a: Annotation) -> Int {
        let wrap = pending == nil
        if wrap { begin() }
        var a = a
        a.id = nextID
        nextID += 1
        items.append(a)
        if wrap { end() }
        return a.id
    }

    public func update(_ a: Annotation) {
        guard let i = items.firstIndex(where: { $0.id == a.id }) else { return }
        let wrap = pending == nil
        if wrap { begin() }
        items[i] = a
        if wrap { end() }
    }

    public func remove(_ id: Int) {
        let wrap = pending == nil
        if wrap { begin() }
        items.removeAll { $0.id == id }
        if wrap { end() }
    }

    @discardableResult
    public func undo() -> Bool {
        end()
        guard let prev = undoStack.popLast() else { return false }
        redoStack.append(items)
        items = prev
        return true
    }

    @discardableResult
    public func redo() -> Bool {
        end()
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(items)
        items = next
        return true
    }

    /// 맨 위(나중에 그린 것)부터 찾는다.
    public func topmost(at p: CGPoint, tolerance: CGFloat, interior: Bool) -> Annotation? {
        items.last { $0.contains(p, tolerance: tolerance, interior: interior) }
    }
}

/// 도구별 색·크기 기본값(윈도우판 `annot_tool_defaults`처럼 도구마다 따로 기억). DB 설정에 JSON 하나로 저장.
public struct AnnotationDefaults: Codable, Equatable {
    public struct Style: Codable, Equatable {
        public var color: UInt32
        public var size: CGFloat

        public init(color: UInt32, size: CGFloat) {
            self.color = color
            self.size = size
        }
    }

    public static let settingKey = "annot_tool_defaults"
    /// 빨강·주황·노랑·초록·파랑·검정·흰색(윈도우판 프리셋).
    public static let presets: [UInt32] = [0xFF3B30, 0xFF9500, 0xFFCC00, 0x34C759, 0x007AFF, 0x000000, 0xFFFFFF]

    private var styles: [String: Style] = [:]

    public init() {}

    /// 크기 범위·기본값·± 한 칸: 도형류 두께 1~40(6), 텍스트 6~200(16), 번호 지름 12~120(30).
    public static func range(for tool: AnnotationTool) -> (min: CGFloat, max: CGFloat, initial: CGFloat, step: CGFloat) {
        switch tool {
        case .text: return (6, 200, 16, 2)
        case .badge: return (12, 120, 30, 2)
        default: return (1, 40, 6, 1)
        }
    }

    public func style(for tool: AnnotationTool) -> Style {
        styles[tool.rawValue] ?? Style(color: Self.presets[0], size: Self.range(for: tool).initial)
    }

    public mutating func set(_ style: Style, for tool: AnnotationTool) {
        let r = Self.range(for: tool)
        styles[tool.rawValue] = Style(color: style.color & 0xFFFFFF, size: min(max(style.size, r.min), r.max))
    }

    public func json() -> String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// 깨진 값이면 기본값으로 시작한다.
    public static func from(json: String?) -> AnnotationDefaults {
        guard let d = json?.data(using: .utf8), let v = try? JSONDecoder().decode(Self.self, from: d) else { return Self() }
        return v
    }
}
