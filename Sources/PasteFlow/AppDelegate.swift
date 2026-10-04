import AppKit
import PasteFlowCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let reopenNote = Notification.Name("com.minwoo.pasteflow.reopen")
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
        // 한 번만 실행: 이미 떠 있으면 그쪽에 설정창을 열라고 알리고 이쪽은 끝낸다
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != NSRunningApplication.current }
        if !others.isEmpty {
            DistributedNotificationCenter.default().postNotificationName(Self.reopenNote, object: nil, userInfo: nil, deliverImmediately: true)
            StatusLog.append("second instance — handed over to pid=\(others[0].processIdentifier) and quit")
            NSApp.terminate(nil)
            return
        }
        DistributedNotificationCenter.default().addObserver(forName: Self.reopenNote, object: nil, queue: .main) { _ in
            SettingsWindow.show()
        }
        // 자리 값이 없으면 맥이 새 아이콘을 맨 왼쪽(Hidden Bar 숨김 구역)에 둔다 → 첫 실행에 오른쪽 자리를 정해 둔다.
        // 값은 메뉴바 오른쪽 끝에서의 거리. Hidden Bar 화살표(385)보다 작으면 늘 보이는 구역이다.
        let positionKey = "NSStatusItem Preferred Position PasteFlowMain"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(360, forKey: positionKey)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "PasteFlowMain"
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
        AnnotationCanvas.settingsDB = db   // 주석 도구별 색·크기 기억
        screen = ScreenController(paste: paste, db: db, monitor: monitor)
        ElementSnapper.startWaking()
        keys.onScreenAction = { [weak self] action in self?.screen?.handle(action) }
        SettingsWindow.configure(db: db, keys: keys, queue: queue)   // 저장된 단축키·알림·큐 시간
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
        } catch {
            StatusLog.append("DB 열기 실패: \(error)")
            return
        }
        monitor.onCopy = { [weak self] item, fromApp in
            guard let self else { return }
            do {
                var saved = item
                saved.id = try self.db.insert(item)
                self.queue.add(saved)
                self.paste?.didCopy()
                let q = self.queue.status
                if !fromApp { Toast.showCopy(saved, queueCount: q.total) }   // 윈도우판 복사 토스트(Q배지)
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
        // 단축키는 설정에서 바뀔 수 있어 제목 옆에 글자로 보여준다(메뉴 단축키는 전역으로 동작하지 않음)
        menu.addItem(withTitle: "패널 열기  \(keys.map.hotkey(for: .panel).display)", action: #selector(openPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "설정…", action: #selector(openSettings), keyEquivalent: ",").target = self
        // 메뉴를 열 때는 네트워크·비밀값을 건드리지 않는다(메뉴가 키보드를 잡고 있어 뜬 창에 입력이 안 됨) — 마지막 값만
        menu.addItem(withTitle: OCRSettings.cachedCredits(db) ?? "크레딧: OCR 설정에서 확인", action: nil, keyEquivalent: "")
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

    @objc private func openSettings() { SettingsWindow.show() }

    /// Finder·Spotlight에서 이미 실행 중인 앱을 다시 열면 설정창을 띄운다(메뉴바 아이콘이 숨어 있어도 찾을 수 있게).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.show()
        return false
    }

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
