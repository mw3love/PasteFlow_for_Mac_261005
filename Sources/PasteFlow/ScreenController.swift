import AppKit
import PasteFlowCore

/// 영역 캡처(⌘⇧2)와 화면 핀(⌘⇧1).
final class ScreenController {
    private let overlay = CaptureOverlay()
    private let paste: PasteController
    private let db: ClipDatabase?
    /// 마지막 캡처 — 같은 이미지를 핀하면 캡처한 자리에 띄운다.
    private var lastCapture: (png: Data, rect: NSRect)?

    init(paste: PasteController, db: ClipDatabase?) {
        self.paste = paste
        self.db = db
        overlay.onCapture = { [weak self] png, rect in self?.didCapture(png, rect) }
    }

    func handle(_ action: ScreenAction) {
        switch action {
        case .capture: overlay.isActive ? overlay.cancel() : overlay.start()
        case .pin: pin()
        }
    }

    // MARK: 캡처

    private func didCapture(_ png: Data, _ rect: NSRect) {
        lastCapture = (png, rect)
        // 클립보드에 올리면 감시기가 일반 복사처럼 히스토리·순차 큐에 넣는다(같은 경로 재사용)
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        pb.writeObjects([item])

        let folderSetting = (try? db?.setting("capture_save_folder")) ?? nil
        let folder = folderSetting.map { URL(fileURLWithPath: $0) } ?? CaptureFiles.defaultFolder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = CaptureFiles.uniqueURL(in: folder)
            try png.write(to: url, options: .atomic)
            StatusLog.append("capture saved \(url.path) rect=\(rect)")
            Toast.show("캡처됨", detail: url.lastPathComponent)
        } catch {
            StatusLog.append("capture save FAILED: \(error)")
            Toast.show("캡처됨", detail: "파일 저장 실패 — 클립보드에는 있어요")
        }
    }

    // MARK: 핀

    private func pin() {
        if let item = paste.takeNextForPin() {
            pinItem(formats: item.formats, text: item.previewText)
            return
        }
        pinClipboard()
    }

    private func pinItem(formats: [String: Data], text: String) {
        for t in ClipClassifier.imageTypes {
            if let d = formats[t], let img = NSImage(data: d) {
                show(img, png: formats["public.png"])
                return
            }
        }
        if let d = formats[ClipClassifier.plainText], let s = String(data: d, encoding: .utf8) {
            pinText(s)
        } else {
            pinText(text)
        }
    }

    private func pinClipboard() {
        let pb = NSPasteboard.general
        if let png = pb.data(forType: .png), let img = NSImage(data: png) { show(img, png: png); return }
        if let tiff = pb.data(forType: .tiff), let img = NSImage(data: tiff) { show(img, png: nil); return }
        if let s = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            // 경로 붙여넣기로 올라간 PNG 경로면 원본 이미지로 되살린다
            if s.hasPrefix("/"), s.lowercased().hasSuffix(".png"), FileManager.default.fileExists(atPath: s),
               let img = NSImage(contentsOfFile: s) {
                show(img, png: nil)
                return
            }
            pinText(s)
            return
        }
        Toast.show("핀할 내용이 없어요", detail: "큐와 클립보드가 비어 있어요")
    }

    private func show(_ img: NSImage, png: Data?) {
        let at = (png != nil && png == lastCapture?.png) ? lastCapture?.rect : nil
        PinWindow.show(image: img, pixelScale: 1, at: at)
    }

    /// 텍스트를 M1 테마 카드 이미지로 그려 핀한다.
    private func pinText(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: Theme.text]
        let str = NSAttributedString(string: String(text.prefix(4000)), attributes: attrs)
        let maxW: CGFloat = 480, pad: CGFloat = 14
        let bound = str.boundingRect(with: NSSize(width: maxW, height: 2000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let size = NSSize(width: ceil(bound.width) + pad * 2, height: min(ceil(bound.height), 2000) + pad * 2)
        let img = NSImage(size: size, flipped: false) { rect in
            Theme.bg.setFill()
            rect.fill()
            str.draw(with: NSRect(x: pad, y: pad, width: maxW, height: size.height - pad * 2),
                     options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
            return true
        }
        PinWindow.show(image: img, pixelScale: 1)
    }
}
