import AppKit

/// 디자인 테마 M1 토큰(PLAN.md "디자인 테마"). 패널·HUD·미리보기가 함께 쓴다.
enum Theme {
    static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }

    static let bg = rgb(0x161618)
    static let item = rgb(0x242426)
    static let itemHover = rgb(0x2e2e31)
    static let itemSelected = rgb(0x34343a)
    static let text = rgb(0xececec)
    static let text2 = rgb(0xcfcfd2)
    static let dim = rgb(0x6e6e73)
    static let secondary = rgb(0x98989d)
    static let coral = rgb(0xfab387)
    static let coralFill = rgb(0xfab387, 0.16)
    static let border = NSColor(white: 1, alpha: 0.16)
    static let separator = NSColor(white: 1, alpha: 0.08)

    static let windowRadius: CGFloat = 12
    static let itemRadius: CGFloat = 8
}
