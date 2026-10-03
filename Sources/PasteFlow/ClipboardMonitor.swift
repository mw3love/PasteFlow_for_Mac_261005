import AppKit
import PasteFlowCore

/// 맥 클립보드 감시. NSPasteboard는 변경 알림이 없어 `changeCount`를 주기적으로 확인한다.
final class ClipboardMonitor {
    static let pollInterval: TimeInterval = 0.25

    var onCopy: ((ClipItem) -> Void)?

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var lastHash: String?
    private var timer: Timer?
    /// 앱이 직접 클립보드를 바꾼 경우의 changeCount — 자기 복사를 히스토리에 다시 넣지 않기 위함.
    private var selfChangeCounts: Set<Int> = []

    init() {
        lastChangeCount = pasteboard.changeCount   // 실행 전부터 있던 내용은 기록하지 않음
    }

    func start() {
        let t = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 앱이 클립보드에 쓴 직후 호출한다(4단계 붙여넣기에서 사용).
    func noteSelfChange() {
        selfChangeCounts.insert(pasteboard.changeCount)
    }

    private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        if selfChangeCounts.remove(count) != nil { return }
        guard let item = capture() else { return }
        onCopy?(item)
    }

    private func capture() -> ClipItem? {
        // 여러 항목(예: Finder에서 파일 여러 개) 중 첫 항목만 보존 — 알려진 한계
        guard let pbItem = pasteboard.pasteboardItems?.first else { return nil }
        let types = pbItem.types.map(\.rawValue)
        if ClipClassifier.shouldSkip(types: types) { return nil }

        var formats: [String: Data] = [:]
        for type in pbItem.types {
            guard let data = pbItem.data(forType: type), data.count <= ClipClassifier.maxFormatBytes else { continue }
            formats[type.rawValue] = data
        }
        guard !ClipClassifier.isEmpty(formats: formats) else { return nil }

        let hash = ClipItem.contentHash(formats)
        guard hash != lastHash else { return nil }
        lastHash = hash

        let kind = ClipClassifier.kind(for: types)
        var thumbnail: Data?
        var size: (Int, Int)?
        if kind == .image, let image = Self.image(from: formats) {
            let rep = image.representations.first
            size = (rep?.pixelsWide ?? Int(image.size.width), rep?.pixelsHigh ?? Int(image.size.height))
            thumbnail = Self.thumbnailPNG(image)
        }
        return ClipItem(kind: kind, formats: formats,
                        previewText: ClipClassifier.preview(formats: formats, kind: kind, imageSize: size),
                        thumbnail: thumbnail)
    }

    private static func image(from formats: [String: Data]) -> NSImage? {
        for t in ClipClassifier.imageTypes {
            if let d = formats[t], let img = NSImage(data: d) { return img }
        }
        return nil
    }

    /// 패널용 썸네일(최대 192×144px, 비율 유지) PNG.
    private static func thumbnailPNG(_ image: NSImage) -> Data? {
        let maxW: CGFloat = 192, maxH: CGFloat = 144
        let s = image.size
        guard s.width > 0, s.height > 0 else { return nil }
        let scale = min(maxW / s.width, maxH / s.height, 1)
        let w = Int((s.width * scale).rounded()), h = Int((s.height * scale).rounded())
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
