import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PasteFlowCore

/// 작은(얇은) 이미지는 OCR 전에 여백을 붙인다 — 827×24 한 줄 캡처에서 낱자 띄어쓰기 결과가 6번 중 3번 나오던 문제(2026-10-05 실측).
final class OCRPaddingTests: XCTestCase {
    private func png(w: Int, h: Int, gray: CGFloat) -> Data {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }
    private func size(_ d: Data) -> (Int, Int) {
        let img = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(d as CFData, nil)!, 0, nil)!
        return (img.width, img.height)
    }

    func testThinStripIsPaddedToMinimumCanvas() {
        let out = OCRImagePrep.padIfSmall(png(w: 827, h: 24, gray: 0.12))
        XCTAssertEqual(size(out).0, 1800)
        XCTAssertEqual(size(out).1, 400)
    }

    func testWideStripKeepsMarginBeyondMinimum() {
        let out = OCRImagePrep.padIfSmall(png(w: 1854, h: 48, gray: 1))
        XCTAssertEqual(size(out).0, 1854 + 80)
        XCTAssertEqual(size(out).1, 400)
    }

    func testLargeImageUnchanged() {
        let d = png(w: 1900, h: 799, gray: 1)
        XCTAssertEqual(OCRImagePrep.padIfSmall(d), d)
    }

    func testPadColorFollowsImageEdge() {
        let out = OCRImagePrep.padIfSmall(png(w: 100, h: 20, gray: 0))
        let img = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(out as CFData, nil)!, 0, nil)!
        var px = [UInt8](repeating: 255, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 1, height: 1).offsetBy(dx: 0, dy: 0), byTiling: false)
        // 모서리(여백)도 원본과 같은 검정이어야 한다 — 흰 여백이면 대비가 바뀐다
        XCTAssertLessThan(Int(px[0]), 30)
    }

    func testNotAnImageReturnsInput() {
        let junk = Data([1, 2, 3])
        XCTAssertEqual(OCRImagePrep.padIfSmall(junk), junk)
    }
}
