import AppKit
import PasteFlowCore
import ServiceManagement

/// 설정창(메뉴바 "설정…"·패널 빈 곳 우클릭·앱을 다시 열 때). 탭: 일반 / 단축키 / OCR.
/// 일반·단축키는 바꾸는 즉시 저장·적용, OCR은 키 입력이 있어 [저장] 버튼.
final class SettingsWindow: NSWindowController, NSWindowDelegate {
    enum Tab: Int { case general, hotkeys, ocr }

    private static var shared: SettingsWindow?
    private static var db: ClipDatabase?
    private static var keys: KeyInterceptor?
    private static var queue: PasteQueue?

    static let captureFolderKey = "capture_save_folder"
    static let idleKey = "queue_idle_reset_sec"

    /// 시작할 때 한 번 — 저장된 단축키·알림 설정을 읽어 적용한다.
    static func configure(db: ClipDatabase?, keys: KeyInterceptor, queue: PasteQueue) {
        self.db = db
        self.keys = keys
        self.queue = queue
        keys.map = HotkeyMap.from(json: (try? db?.setting(HotkeyMap.settingKey)) ?? nil)
        Toast.enabled = ((try? db?.setting(Toast.settingKey)) ?? nil) != "0"
        if let v = (try? db?.setting(idleKey)) ?? nil, let sec = TimeInterval(v) { queue.idleResetSec = sec }
    }

    static func show(tab: Tab = .general) {
        if shared == nil { shared = SettingsWindow() }
        guard let s = shared else { return }
        s.reload()
        s.tabs.selectTabViewItem(at: tab.rawValue)
        NSApp.activate(ignoringOtherApps: true)
        s.showWindow(nil)
        s.window?.makeKeyAndOrderFront(nil)
        s.window?.orderFrontRegardless()   // macOS 14+는 활성화가 양보식이라 다른 앱 창 뒤에 남을 수 있음
    }

    private let tabs = NSTabView()
    private let ocrPane: OCRSettingsPane
    // 일반
    private let loginCheck = NSButton(checkboxWithTitle: "로그인할 때 자동으로 열기", target: nil, action: nil)
    private let loginStatus = NSTextField(labelWithString: "")
    private let idleField = NSTextField()
    private let idleStepper = NSStepper()
    private let folderLabel = NSTextField(labelWithString: "")
    private let toastCheck = NSButton(checkboxWithTitle: "알림 보이기 (복사·캡처·주석 복사)", target: nil, action: nil)
    // 단축키
    private var recorders: [HotkeyAction: NSButton] = [:]
    private var notes: [HotkeyAction: NSTextField] = [:]
    private var recording: HotkeyAction?
    private var monitor: Any?

    private init() {
        ocrPane = OCRSettingsPane(db: Self.db)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 420), styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "PasteFlow 설정"
        w.isReleasedWhenClosed = false
        super.init(window: w)
        w.delegate = self
        build()
        w.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) { stopRecording() }

    private func build() {
        let general = NSTabViewItem(identifier: "general")
        general.label = "일반"
        general.view = generalView()
        let hotkeys = NSTabViewItem(identifier: "hotkeys")
        hotkeys.label = "단축키"
        hotkeys.view = hotkeyView()
        let ocr = NSTabViewItem(viewController: ocrPane)
        ocr.label = "OCR"
        [general, hotkeys, ocr].forEach(tabs.addTabViewItem)
        tabs.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            tabs.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            tabs.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            tabs.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
        ])
        window?.contentView = root
    }

    private func reload() {
        stopRecording()
        // 로그인 항목
        let status = SMAppService.mainApp.status
        loginCheck.state = status == .enabled || status == .requiresApproval ? .on : .off
        loginStatus.stringValue = Self.describe(status)
        // 큐
        let idle = Int(Self.queue?.idleResetSec ?? PasteQueue.defaultIdleResetSec)
        idleField.integerValue = idle
        idleStepper.integerValue = idle
        // 캡처 폴더
        folderLabel.stringValue = Self.captureFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        toastCheck.state = Toast.enabled ? .on : .off
        refreshHotkeys()
        ocrPane.reloadFields()
    }

    static var captureFolder: URL {
        let s = (try? db?.setting(captureFolderKey)) ?? nil
        return s.map { URL(fileURLWithPath: $0) } ?? CaptureFiles.defaultFolder
    }

    private static func describe(_ s: SMAppService.Status) -> String {
        switch s {
        case .enabled: return "켜짐"
        case .requiresApproval: return "시스템 설정 → 일반 → 로그인 항목에서 허용이 필요해요"
        case .notRegistered: return "꺼짐"
        case .notFound: return "꺼짐"   // 한 번도 등록하지 않은 앱도 이 값이 나온다(2026-10-03 실측)
        @unknown default: return "알 수 없음"
        }
    }

    // MARK: 일반 탭

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.alignment = .right
        return l
    }

    private func small(_ l: NSTextField) -> NSTextField {
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func generalView() -> NSView {
        loginCheck.target = self
        loginCheck.action = #selector(toggleLogin)
        idleField.formatter = { let f = NumberFormatter(); f.minimum = 1; f.maximum = 600; f.allowsFloats = false; return f }()
        idleField.target = self
        idleField.action = #selector(idleChanged(_:))
        idleField.widthAnchor.constraint(equalToConstant: 56).isActive = true
        idleStepper.minValue = 1
        idleStepper.maxValue = 600
        idleStepper.target = self
        idleStepper.action = #selector(idleChanged(_:))
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true
        toastCheck.target = self
        toastCheck.action = #selector(toggleToast)

        let idleRow = NSStackView(views: [idleField, idleStepper, NSTextField(labelWithString: "초")])
        idleRow.spacing = 4
        let folderRow = NSStackView(views: [folderLabel, NSButton(title: "선택…", target: self, action: #selector(chooseFolder)),
                                            NSButton(title: "열기", target: self, action: #selector(openFolder)),
                                            NSButton(title: "기본값", target: self, action: #selector(resetFolder))])
        let grid = NSGridView(views: [
            [label("시작"), loginCheck],
            [NSGridCell.emptyContentView, small(loginStatus)],
            [label("새 묶음"), idleRow],
            [NSGridCell.emptyContentView, small(NSTextField(labelWithString: "마지막 복사 후 이 시간이 지나 다시 복사하면 큐를 새로 시작해요"))],
            [label("캡처 저장"), folderRow],
            [label("알림"), toastCheck],
            [NSGridCell.emptyContentView, small(NSTextField(labelWithString: "실패·OCR 진행 알림은 끄더라도 떠요"))],
        ])
        grid.rowSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        return padded(grid)
    }

    private func padded(_ v: NSView) -> NSView {
        let box = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 20),
            v.topAnchor.constraint(equalTo: box.topAnchor, constant: 20),
            v.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -20),
        ])
        return box
    }

    @objc private func toggleLogin() {
        do {
            if loginCheck.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            StatusLog.append("login item \(loginCheck.state == .on ? "register" : "unregister") FAILED: \(error)")
            Toast.show("자동 시작 설정 실패", detail: error.localizedDescription, duration: 4, always: true)
        }
        let status = SMAppService.mainApp.status
        StatusLog.append("login item status=\(status.rawValue) (0 notRegistered 1 enabled 2 requiresApproval 3 notFound)")
        loginCheck.state = status == .enabled || status == .requiresApproval ? .on : .off
        loginStatus.stringValue = Self.describe(status)
        if status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    @objc private func idleChanged(_ sender: NSControl) {
        let v = min(max(sender.integerValue, 1), 600)
        idleField.integerValue = v
        idleStepper.integerValue = v
        Self.queue?.idleResetSec = TimeInterval(v)
        try? Self.db?.setSetting(Self.idleKey, String(v))
    }

    @objc private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.directoryURL = Self.captureFolder
        p.prompt = "선택"
        guard p.runModal() == .OK, let url = p.url else { return }
        try? Self.db?.setSetting(Self.captureFolderKey, url.path)
        reload()
    }

    @objc private func openFolder() {
        let url = Self.captureFolder
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    @objc private func resetFolder() {
        try? Self.db?.setSetting(Self.captureFolderKey, CaptureFiles.defaultFolder.path)
        reload()
    }

    @objc private func toggleToast() {
        Toast.enabled = toastCheck.state == .on
        try? Self.db?.setSetting(Toast.settingKey, Toast.enabled ? "1" : "0")
    }

    // MARK: 단축키 탭

    private func hotkeyView() -> NSView {
        var rows: [[NSView]] = []
        for a in HotkeyAction.allCases {
            let rec = NSButton(title: "", target: self, action: #selector(recordClicked(_:)))
            rec.tag = HotkeyAction.allCases.firstIndex(of: a)!
            rec.bezelStyle = .rounded
            rec.widthAnchor.constraint(equalToConstant: 150).isActive = true
            let reset = NSButton(title: "기본값", target: self, action: #selector(resetClicked(_:)))
            reset.tag = rec.tag
            reset.bezelStyle = .rounded
            let note = small(NSTextField(labelWithString: ""))
            note.lineBreakMode = .byTruncatingTail
            note.widthAnchor.constraint(equalToConstant: 210).isActive = true
            recorders[a] = rec
            notes[a] = note
            rows.append([label(a.title), rec, reset, note])
        }
        rows.append([NSGridCell.emptyContentView, small(NSTextField(labelWithString: "일반 ⌘V(큐 비우기)는 바꿀 수 없어요")),
                     NSGridCell.emptyContentView, NSGridCell.emptyContentView])
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 6
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        return padded(grid)
    }

    private func refreshHotkeys(error: (HotkeyAction, String)? = nil) {
        guard let map = Self.keys?.map else { return }
        for a in HotkeyAction.allCases {
            recorders[a]?.title = recording == a ? "새 키를 누르세요… (Esc 취소)" : map.hotkey(for: a).display
            if let error, error.0 == a {
                notes[a]?.stringValue = error.1
                notes[a]?.textColor = .systemRed
            } else {
                notes[a]?.stringValue = HotkeyMap.warning(map.hotkey(for: a)) ?? (map.isDefault(a) ? "" : "기본: \(HotkeyMap.defaults[a]!.display)")
                notes[a]?.textColor = .secondaryLabelColor
            }
            notes[a]?.toolTip = notes[a]?.stringValue
        }
    }

    @objc private func recordClicked(_ sender: NSButton) {
        let a = HotkeyAction.allCases[sender.tag]
        if recording == a { stopRecording(); refreshHotkeys(); return }
        stopRecording()
        recording = a
        Self.keys?.isRecording = true   // 녹화 중엔 전역 단축키가 키를 삼키지 않게
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.recorded(e)
            return nil
        }
        refreshHotkeys()
    }

    private func recorded(_ e: NSEvent) {
        guard let a = recording, var map = Self.keys?.map else { return }
        if e.keyCode == 53 && e.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            stopRecording()
            refreshHotkeys()
            return
        }
        var m: Modifiers = []
        let f = e.modifierFlags
        if f.contains(.command) { m.insert(.command) }
        if f.contains(.shift) { m.insert(.shift) }
        if f.contains(.option) { m.insert(.option) }
        if f.contains(.control) { m.insert(.control) }
        let k = Hotkey(Int(e.keyCode), m)
        stopRecording()
        if let p = map.problem(k, for: a) {
            let msg: String
            switch p {
            case .needsModifier: msg = "⌘·⌃·⌥ 중 하나와 같이 눌러 주세요"
            case .reserved(let name): msg = "\(k.display)는 \(name)라 못 써요"
            case .duplicate(let other): msg = "\(k.display)는 \"\(other.title)\"가 쓰고 있어요"
            }
            refreshHotkeys(error: (a, msg))
            return
        }
        map.set(k, for: a)
        apply(map)
        StatusLog.append("hotkey \(a.rawValue) = \(k.display)")
    }

    @objc private func resetClicked(_ sender: NSButton) {
        guard var map = Self.keys?.map else { return }
        let a = HotkeyAction.allCases[sender.tag]
        // 기본값이 지금 다른 동작에 걸려 있으면 되돌릴 수 없다
        if case .duplicate(let other)? = map.problem(HotkeyMap.defaults[a]!, for: a) {
            refreshHotkeys(error: (a, "기본값을 \"\(other.title)\"가 쓰고 있어요"))
            return
        }
        stopRecording()
        map.set(nil, for: a)
        apply(map)
    }

    private func apply(_ map: HotkeyMap) {
        Self.keys?.map = map
        try? Self.db?.setSetting(HotkeyMap.settingKey, map.json())
        refreshHotkeys()
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        Self.keys?.isRecording = false
    }
}
