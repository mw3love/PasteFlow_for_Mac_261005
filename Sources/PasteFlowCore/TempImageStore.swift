import Foundation

/// 경로 붙여넣기용 임시 PNG 보관함. 붙여넣은 경로를 다른 프로그램(예: Claude CLI)이 나중에 읽으므로
/// 바로 지우지 않고, 일정 시간(기본 24시간)이 지난 파일만 정리한다.
public struct TempImageStore {
    public let directory: URL
    public let maxAge: TimeInterval

    public init(directory: URL, maxAge: TimeInterval = 24 * 3600) {
        self.directory = directory
        self.maxAge = maxAge
    }

    /// PNG를 저장하고 절대경로를 돌려준다.
    public func save(png: Data, itemId: Int64?, now: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = Int(now.timeIntervalSince1970 * 1000)
        let url = directory.appendingPathComponent("pasteflow-\(stamp)-\(itemId ?? 0).png")
        try png.write(to: url, options: .atomic)
        return url
    }

    /// `maxAge`보다 오래된 PNG를 지우고, 지운 개수를 돌려준다.
    @discardableResult
    public func cleanup(now: Date = Date()) -> Int {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return 0 }
        var removed = 0
        for f in files where f.pathExtension == "png" {
            let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now
            if now.timeIntervalSince(date) > maxAge, (try? fm.removeItem(at: f)) != nil {
                removed += 1
            }
        }
        return removed
    }
}
