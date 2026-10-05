import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// OCR에 보내기 전 이미지 손질. 얇은 한 줄 캡처(예: 827×24)는 모델이 글자를 낱자로 띄어 읽는 일이 잦아(6번 중 3번),
/// 테두리 평균색 여백을 붙여 최소 1800×400 캔버스 가운데에 둔다(같은 이미지로 6번 모두 정상 — 2026-10-05 실측).
public enum OCRImagePrep {
    public static let minWidth = 1800
    public static let minHeight = 400
    public static let margin = 40

    /// 가로나 세로가 최소보다 작으면 여백을 붙인 PNG, 아니면(또는 읽을 수 없으면) 그대로.
    public static func padIfSmall(_ png: Data) -> Data {
        guard let src = CGImageSourceCreateWithData(png as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
              img.width < minWidth || img.height < minHeight else { return png }
        let w = max(img.width + margin * 2, minWidth), h = max(img.height + margin * 2, minHeight)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return png }
        ctx.setFillColor(edgeColor(img))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(img, in: CGRect(x: (w - img.width) / 2, y: (h - img.height) / 2, width: img.width, height: img.height))
        guard let out = ctx.makeImage() else { return png }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return png }
        CGImageDestinationAddImage(dest, out, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : png
    }

    /// 테두리(맨 위·아래 줄, 맨 왼쪽·오른쪽 열) 평균색 — 모서리 한 점은 테두리선 등 다른 색일 수 있어 평균을 쓴다.
    private static func edgeColor(_ img: CGImage) -> CGColor {
        let w = img.width, h = img.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ok = px.withUnsafeMutableBytes { buf -> Bool in
            guard let c = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok, w > 0, h > 0 else { return CGColor(red: 1, green: 1, blue: 1, alpha: 1) }
        var sum = [0, 0, 0], n = 0
        func add(_ x: Int, _ y: Int) { let i = (y * w + x) * 4; sum[0] += Int(px[i]); sum[1] += Int(px[i + 1]); sum[2] += Int(px[i + 2]); n += 1 }
        for x in 0..<w { add(x, 0); add(x, h - 1) }
        for y in 0..<h { add(0, y); add(w - 1, y) }
        return CGColor(red: CGFloat(sum[0] / n) / 255, green: CGFloat(sum[1] / n) / 255, blue: CGFloat(sum[2] / n) / 255, alpha: 1)
    }
}
