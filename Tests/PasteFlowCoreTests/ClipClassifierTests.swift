import XCTest
@testable import PasteFlowCore

final class ClipClassifierTests: XCTestCase {
    func testKinds() {
        XCTAssertEqual(ClipClassifier.kind(for: ["public.utf8-plain-text"]), .text)
        XCTAssertEqual(ClipClassifier.kind(for: ["public.html", "public.utf8-plain-text"]), .html)
        XCTAssertEqual(ClipClassifier.kind(for: ["public.png", "public.tiff"]), .image)
        XCTAssertEqual(ClipClassifier.kind(for: ["public.file-url", "public.utf8-plain-text"]), .file)
        XCTAssertEqual(ClipClassifier.kind(for: ["com.example.custom"]), .other)
    }

    func testSkipsPasswordManagerMarkers() {
        XCTAssertTrue(ClipClassifier.shouldSkip(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertFalse(ClipClassifier.shouldSkip(types: ["public.utf8-plain-text"]))
    }

    func testPreview() {
        let text = ["public.utf8-plain-text": Data("  안녕\n".utf8)]
        XCTAssertEqual(ClipClassifier.preview(formats: text, kind: .text), "안녕")
        XCTAssertEqual(ClipClassifier.preview(formats: [:], kind: .image, imageSize: (1280, 720)), "이미지 1280×720")
        let file = ["public.file-url": Data("file:///Users/me/Desktop/report.pdf".utf8)]
        XCTAssertEqual(ClipClassifier.preview(formats: file, kind: .file), "report.pdf")
    }
}
