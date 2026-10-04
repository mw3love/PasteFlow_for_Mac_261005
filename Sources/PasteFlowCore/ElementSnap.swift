import CoreGraphics

/// 캡처 오버레이의 요소 단위 스냅 규칙(윈도우판 `_target_rect_logical`과 같은 뜻).
/// 커서 아래 최말단 요소부터 부모 쪽으로 올라가며 "잡을 만한" 사각형 하나를 고르고,
/// 못 고르면 창 전체로 돌아간다. 좌표계는 호출하는 쪽이 하나로 맞춘다(창·요소·커서 모두 같은 좌표).
public enum ElementSnap {
    public struct Node: Equatable {
        public let role: String
        public let rect: CGRect
        public init(role: String, rect: CGRect) { self.role = role; self.rect = rect }
    }

    /// 창 위쪽 이 높이 안(제목 막대)이면 요소 대신 창 전체 — 윈도우판 "비클라이언트 = 창 통째로".
    public static let titleBarHeight: CGFloat = 28
    /// 이보다 작은 요소(글자 조각·장식)는 건너뛰고 부모를 본다.
    public static let minSide: CGFloat = 8
    /// 창 넓이의 이 비율 이상이면 사실상 창이므로 창 전체로.
    public static let windowLikeFraction: CGFloat = 0.9

    /// 이 역할이 걸리면 요소가 아니라 창 전체를 잡는다.
    static let windowRoles: Set<String> = ["AXWindow", "AXToolbar", "AXApplication"]
    /// 이 역할 안의 글자·그림은 따로 잡지 않고 바깥(버튼·링크 등)을 잡는다.
    static let clickableRoles: Set<String> = ["AXButton", "AXLink", "AXCell", "AXRadioButton", "AXCheckBox",
                                              "AXPopUpButton", "AXMenuButton", "AXMenuItem", "AXTab", "AXRow"]
    static let contentRoles: Set<String> = ["AXStaticText", "AXImage"]

    /// - Parameters:
    ///   - chain: 최말단 요소부터 위로(부모 쪽으로) 나열. 비어 있으면 창 전체.
    ///   - window: 커서 아래 창 사각형.
    ///   - cursor: 커서 위치.
    ///   - topIsMinY: 좌표계의 위쪽이 minY인지(CG·AX 좌표 = true, Cocoa = false).
    public static func choose(chain: [Node], window: CGRect, cursor: CGPoint, topIsMinY: Bool = true) -> CGRect {
        let fromTop = topIsMinY ? cursor.y - window.minY : window.maxY - cursor.y
        if fromTop < titleBarHeight { return window }
        let windowArea = window.width * window.height
        for (i, node) in chain.enumerated() {
            if windowRoles.contains(node.role) { return window }
            if contentRoles.contains(node.role), i + 1 < chain.count, clickableRoles.contains(chain[i + 1].role) { continue }
            let r = node.rect.intersection(window)
            guard !r.isNull, r.width >= minSide, r.height >= minSide, r.contains(cursor) else { continue }
            return r.width * r.height >= windowArea * windowLikeFraction ? window : r
        }
        return window
    }
}
