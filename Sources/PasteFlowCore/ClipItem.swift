import CryptoKit
import Foundation

/// 클립보드 항목 하나. `formats`에 원본 형식(pasteboard type → 데이터)을 모두 보존한다.
public struct ClipItem: Equatable {
    public enum Kind: String {
        case text, image, html, rtf, file, other
    }

    public var id: Int64?
    public var kind: Kind
    public var formats: [String: Data]
    public var previewText: String
    public var thumbnail: Data?
    public var createdAt: Date
    public var isPinned: Bool
    public var pinOrder: Int
    public var savedImagePath: String?

    public init(
        id: Int64? = nil, kind: Kind, formats: [String: Data], previewText: String,
        thumbnail: Data? = nil, createdAt: Date = Date(), isPinned: Bool = false,
        pinOrder: Int = 0, savedImagePath: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.formats = formats
        self.previewText = previewText
        self.thumbnail = thumbnail
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.pinOrder = pinOrder
        self.savedImagePath = savedImagePath
    }

    /// 형식 순서와 무관한 내용 해시 — 직전 항목과 같은 복사를 거르는 데 쓴다.
    public static func contentHash(_ formats: [String: Data]) -> String {
        var h = SHA256()
        for key in formats.keys.sorted() {
            h.update(data: Data(key.utf8))
            h.update(data: Data([0]))
            h.update(data: formats[key]!)
            h.update(data: Data([0]))
        }
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
