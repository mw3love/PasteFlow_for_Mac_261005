import Foundation

/// 비밀값을 앱 전용 파일(나만 읽기 600, 폴더 700)에 보관한다.
/// 키체인은 자체 서명(팀 ID 없음) 앱을 빌드마다 다른 앱으로 보고 비밀번호를 다시 물어서 쓰지 않는다(2026-10-03 사용자 결정).
/// DB·로그에는 절대 쓰지 않는다.
enum SecretStore {
    private static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PasteFlow/secrets", isDirectory: true)
    }

    static func get(_ name: String) -> String? {
        guard let s = try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) else { return nil }
        let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    @discardableResult
    static func set(_ name: String, _ value: String) -> Bool {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            let file = dir.appendingPathComponent(name)
            try Data(value.utf8).write(to: file, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return true
        } catch {
            return false
        }
    }
}
