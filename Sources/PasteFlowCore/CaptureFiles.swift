import Foundation

/// 캡처 파일 저장 규칙 — 윈도우판과 같은 `clip_YYYYMMDD_HHMMSS.png`, 같은 이름이 있으면 `_1`, `_2`…
public enum CaptureFiles {
    public static var defaultFolder: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("PasteFlow")
    }

    public static func uniqueURL(in folder: URL, date: Date = Date(), exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        let base = "clip_\(f.string(from: date))"
        var url = folder.appendingPathComponent(base + ".png")
        var n = 0
        while exists(url) {
            n += 1
            url = folder.appendingPathComponent("\(base)_\(n).png")
        }
        return url
    }
}
