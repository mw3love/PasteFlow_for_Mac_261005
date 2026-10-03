import AppKit
import PasteFlowCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var db: ClipDatabase!
    private let queue = PasteQueue()
    private let monitor = ClipboardMonitor()
    private let keys = KeyInterceptor()
    private let hud = PasteHUD()
    private var paste: PasteController!
    private var panel: ClipPanelController?
    private var screen: ScreenController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "PasteFlow")
        menu.delegate = self
        statusItem.menu = menu

        let status = PermissionStatus.current()
        StatusLog.write(status)
        // 메뉴바 아이콘이 실제로 화면 안에 놓였는지 기록(노치·숨김 확인용)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            let f = self?.statusItem.button?.window?.frame ?? .zero
            StatusLog.append("statusItem frame=\(f) visible=\(self?.statusItem.isVisible ?? false)")
        }
        if !status.accessibility || !status.screenRecording {
            PermissionStatus.requestMissing()
        }
        startClipboard()
        startPaste()
    }

    // 붙여넣기 단축키 → 큐에서 꺼내 주입 + 진행 HUD
    private func startPaste() {
        let tempStore = TempImageStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("PasteFlow"))
        let removed = tempStore.cleanup()
        paste = PasteController(queue: queue, monitor: monitor, hud: hud, tempStore: tempStore)
        keys.onAction = { [weak self] action in self?.paste.handle(action) }
        if let db {
            panel = ClipPanelController(db: db, queue: queue, paste: paste)
        }
        keys.onPanelToggle = { [weak self] in self?.panel?.toggle() }
        screen = ScreenController(paste: paste, db: db)
        keys.onScreenAction = { [weak self] action in self?.screen?.handle(action) }
        let ok = keys.start()
        StatusLog.append("key tap \(ok ? "started" : "FAILED (손쉬운 사용 권한 필요)") tempCleanup=\(removed)")
    }

    // 클립보드 감시 → DB 저장 → 순차 큐
    private func startClipboard() {
        do {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PasteFlow")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            db = try ClipDatabase(path: dir.appendingPathComponent("pasteflow.db").path)
            if let v = try db.setting("queue_idle_reset_sec"), let sec = TimeInterval(v) {
                queue.idleResetSec = sec
            }
        } catch {
            StatusLog.append("DB 열기 실패: \(error)")
            return
        }
        monitor.onCopy = { [weak self] item in
            guard let self else { return }
            do {
                var saved = item
                saved.id = try self.db.insert(item)
                self.queue.add(saved)
                self.paste?.didCopy()
                let q = self.queue.status
                StatusLog.append("copy id=\(saved.id!) kind=\(item.kind.rawValue) formats=\(item.formats.count) queue=\(q.pointer)/\(q.total) preview=\(item.previewText.prefix(40).replacingOccurrences(of: "\n", with: " "))")
            } catch {
                StatusLog.append("저장 실패: \(error)")
            }
        }
        monitor.start()
    }

    // 메뉴를 열 때마다 권한 상태를 새로 읽어 표시
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = PermissionStatus.current()
        menu.addItem(withTitle: "PasteFlow", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let open = menu.addItem(withTitle: "패널 열기", action: #selector(openPanel), keyEquivalent: " ")
        open.keyEquivalentModifierMask = [.option]
        open.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "손쉬운 사용: \(s.accessibility ? "허용됨" : "필요")", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "화면 기록: \(s.screenRecording ? "허용됨" : "필요")", action: nil, keyEquivalent: "")
        if !s.accessibility || !s.screenRecording {
            menu.addItem(withTitle: "권한 설정 열기…", action: #selector(openPrivacySettings), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func openPanel() { panel?.show() }

    @objc private func openPrivacySettings() {
        let s = PermissionStatus.current()
        let pane = s.accessibility ? "Privacy_ScreenCapture" : "Privacy_Accessibility"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// 실행할 때마다 권한 상태를 로그 파일에 남긴다(재빌드 후 권한 유지 확인용).
enum StatusLog {
    static func write(_ s: PermissionStatus) {
        append("accessibility=\(s.accessibility) screenRecording=\(s.screenRecording)")
    }

    static func append(_ message: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/PasteFlow")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("status.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8)!)
            try? h.close()
        } else {
            try? line.write(to: file, atomically: true, encoding: .utf8)
        }
    }
}
