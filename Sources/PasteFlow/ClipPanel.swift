import AppKit
import PasteFlowCore

/// 클립보드 패널(⌥Space) — 고정메모 + 히스토리. 검색은 없다(윈도우판에서 의도적으로 제거).
///
/// 포커스: 다른 앱을 활성화하지 않는 패널(nonactivating)이지만 키 입력은 받는다.
/// 그래서 Enter로 붙여넣으면 패널을 닫은 뒤 원래 앱에 ⌘V가 들어간다.
final class ClipPanelController: NSObject {
    static let defaultSize = NSSize(width: 320, height: 430)
    static let minSize = NSSize(width: 260, height: 390)

    private let db: ClipDatabase
    private let queue: PasteQueue
    private let paste: PasteController
    private let window: ClipPanelWindow
    private let statusLabel = NSTextField(labelWithString: "")
    private let pinButton = NSButton()
    private let list = NSStackView()
    private let scroll = NSScrollView()
    private let doc = PanelListView()
    /// 고정메모와 히스토리 사이 구분선 — 끌어 놓기에서 "고정 영역" 경계.
    private var pinnedSeparator: NSView?

    private var pinnedItems: [ClipItem] = []
    private var historyItems: [ClipItem] = []
    private var itemViews: [Int64: ClipItemView] = [:]
    private var selectedId: Int64?
    private var collapsed: Set<String> = []
    private var alwaysOnTop = true

    init(db: ClipDatabase, queue: PasteQueue, paste: PasteController) {
        self.db = db
        self.queue = queue
        self.paste = paste
        window = ClipPanelWindow(contentRect: NSRect(origin: .zero, size: Self.defaultSize))
        super.init()
        buildUI()
        NotificationCenter.default.addObserver(self, selector: #selector(stateChanged), name: .pasteFlowStateChanged, object: nil)
    }

    var isVisible: Bool { window.isVisible }

    func toggle() {
        if window.isVisible { hide() } else { show() }
    }

    func show() {
        reload()
        if !window.setFrameUsingName("PasteFlowPanel") {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            let vf = screen?.visibleFrame ?? .zero
            window.setFrameOrigin(NSPoint(x: vf.maxX - Self.defaultSize.width - 24, y: vf.maxY - Self.defaultSize.height - 24))
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)
        StatusLog.append("panel show isKey=\(window.isKeyWindow) history=\(historyItems.count) pinned=\(pinnedItems.count)")
    }

    func hide() {
        StatusLog.append("panel hide")
        window.saveFrame(usingName: "PasteFlowPanel")
        window.orderOut(nil)
    }

    @objc private func stateChanged() {
        if window.isVisible { reload() }
    }

    // MARK: 화면 구성

    private func buildUI() {
        window.minSize = Self.minSize
        window.keyHandler = { [weak self] e in self?.handleKey(e) ?? false }

        let root = PanelRootView()
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.bg.cgColor
        root.layer?.cornerRadius = Theme.windowRadius
        root.layer?.borderWidth = 0.5
        root.layer?.borderColor = Theme.border.cgColor
        root.layer?.masksToBounds = true
        root.onBackgroundMenu = { [weak self] in self?.backgroundMenu() }
        window.contentView = root

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        statusLabel.textColor = Theme.coral

        configureIconButton(pinButton, symbol: "pin.fill", tip: "항상 위에", action: #selector(togglePin))
        let close = NSButton()
        configureIconButton(close, symbol: "minus", tip: "닫기(Esc)", action: #selector(closeClicked))
        updatePinButton()

        let header = NSStackView(views: [statusLabel, NSView(), pinButton, close])
        header.orientation = .horizontal
        header.spacing = 4
        header.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 4, right: 8)

        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 6
        list.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 12, right: 10)
        list.translatesAutoresizingMaskIntoConstraints = false

        doc.controller = self
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(list)
        scroll.documentView = doc
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let stack = NSStackView(views: [header, scroll])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            list.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            list.topAnchor.constraint(equalTo: doc.topAnchor),
            list.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])
    }

    private func configureIconButton(_ b: NSButton, symbol: String, tip: String, action: Selector) {
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        b.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
        b.isBordered = false
        b.toolTip = tip
        b.target = self
        b.action = action
        b.contentTintColor = Theme.secondary
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 24).isActive = true
        b.heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    func reload() {
        let savedY = scroll.contentView.bounds.origin.y
        defer { restoreScroll(savedY) }
        pinnedItems = (try? db.pinned(withFormats: false)) ?? []
        historyItems = (try? db.recent(withFormats: false)) ?? []
        let q = queue.status
        statusLabel.stringValue = q.total > 0 ? "붙여넣기 \(q.pointer)/\(q.total)" : ""

        let qIds = queue.items.compactMap(\.id)
        let qIndex = Dictionary(qIds.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })

        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        itemViews.removeAll()

        addSection("고정메모", key: "pinned", items: pinnedItems, qIndex: qIndex, pointer: q.pointer)
        let sep = NSBox()
        sep.boxType = .custom
        sep.borderWidth = 0
        sep.fillColor = Theme.separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
        list.addArrangedSubview(sep)
        pinnedSeparator = sep
        sep.widthAnchor.constraint(equalTo: list.widthAnchor, constant: -20).isActive = true
        addSection("히스토리", key: "history", items: historyItems, qIndex: qIndex, pointer: q.pointer)

        if let id = selectedId, itemViews[id] == nil { selectedId = nil }
        itemViews[selectedId ?? -1]?.isSelected = true
    }

    /// 목록을 다시 그린 뒤 원래 스크롤 위치로 돌린다(맨 위·맨 아래로 튀지 않게).
    private func restoreScroll(_ y: CGFloat) {
        scroll.documentView?.layoutSubtreeIfNeeded()
        let maxY = max(0, (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(y, maxY)))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func addSection(_ title: String, key: String, items: [ClipItem], qIndex: [Int64: Int], pointer: Int) {
        let isCollapsed = collapsed.contains(key)
        let header = NSButton(title: "", target: self, action: #selector(toggleSection(_:)))
        header.identifier = NSUserInterfaceItemIdentifier(key)
        header.isBordered = false
        header.image = NSImage(systemSymbolName: isCollapsed ? "chevron.right" : "chevron.down", accessibilityDescription: nil)
        header.symbolConfiguration = .init(pointSize: 9, weight: .bold)
        header.imagePosition = .imageLeading
        header.contentTintColor = Theme.secondary
        header.attributedTitle = NSAttributedString(string: " \(title)  \(items.count)", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: Theme.secondary])
        list.addArrangedSubview(header)
        guard !isCollapsed else { return }

        if items.isEmpty {
            let empty = NSTextField(labelWithString: key == "pinned" ? "고정한 항목이 없어요 (항목에서 P)" : "복사하면 여기에 쌓여요")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = Theme.dim
            list.addArrangedSubview(empty)
            return
        }
        for item in items {
            guard let id = item.id else { continue }
            var state: ClipItemView.QueueState = .none
            if let i = qIndex[id] { state = i < pointer ? .done : (i == pointer ? .next : .waiting) }
            let v = ClipItemView(item: item, state: state)
            v.onClick = { [weak self] in self?.select(id) }
            v.onDoubleClick = { [weak self] in self?.preview(id) }
            v.onMenu = { [weak self] in self?.itemMenu(id) }
            v.dragProvider = { [weak self] asPath in self?.dragItem(id, asPath: asPath) }
            list.addArrangedSubview(v)
            v.widthAnchor.constraint(equalTo: list.widthAnchor, constant: -20).isActive = true
            itemViews[id] = v
        }
    }

    // MARK: 동작

    private var orderedIds: [Int64] {
        (collapsed.contains("pinned") ? [] : pinnedItems.compactMap(\.id))
            + (collapsed.contains("history") ? [] : historyItems.compactMap(\.id))
    }

    private func select(_ id: Int64?) {
        itemViews[selectedId ?? -1]?.isSelected = false
        selectedId = id
        if let id, let v = itemViews[id] {
            v.isSelected = true
            scroll.documentView?.layoutSubtreeIfNeeded()   // 배치가 끝난 뒤의 위치로 스크롤
            v.scrollToVisible(v.bounds)
        }
    }

    private func full(_ id: Int64) -> ClipItem? { try? db.item(id: id) }

    private func preview(_ id: Int64) {
        guard let item = full(id) else { return }
        PreviewWindow.show(item, near: window.frame)
    }

    private func pasteSelected(asPath: Bool = false) {
        guard let id = selectedId, let item = full(id) else { return }
        hide()
        paste.pasteItem(item, asPath: asPath)
    }

    private func togglePinned(_ id: Int64) {
        let isPinned = pinnedItems.contains { $0.id == id }
        try? db.setPinned(id: id, !isPinned)
        reload()
        select(id)
    }

    private func delete(_ id: Int64) {
        let ids = orderedIds
        let next = ids.firstIndex(of: id).flatMap { i in i + 1 < ids.count ? ids[i + 1] : (i > 0 ? ids[i - 1] : nil) }
        try? db.delete(id: id)
        paste.removeFromQueue(id: id)
        reload()
        select(next)
    }

    /// C — 큐 맨 앞 항목에서 누르면 해제, 아니면 그 항목부터 큐를 새로 지정(윈도우판 `_kbd_queue_toggle`).
    private func toggleQueue(_ id: Int64) {
        if queue.items.first?.id == id { paste.clearQueueFromPanel() } else { selectQueue(id) }
    }

    private func selectQueue(_ id: Int64) {
        guard let ids = QueueSelection.ids(for: id, history: historyItems.compactMap(\.id),
                                           pinned: pinnedItems.compactMap(\.id)) else { return }
        paste.setQueue(ids.compactMap(full))   // 붙여넣으려면 원본 형식이 필요하다
    }

    /// 항목이 가리키는 파일: 이미지는 캡처 저장 파일, Finder 복사는 그 파일, 글자는 경로 글자일 때.
    private func fileURL(_ id: Int64) -> URL? {
        guard let item = full(id) else { return nil }
        let path: String?
        switch item.kind {
        case .image: path = item.savedImagePath
        case .file: path = item.formats[ClipClassifier.fileURL].flatMap { String(data: $0, encoding: .utf8) }
                .flatMap(URL.init(string:))?.path
        default: path = item.formats[ClipClassifier.plainText].flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let p = path, !p.isEmpty, !p.contains("\n") else { return nil }
        let expanded = (p as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: expanded) ? URL(fileURLWithPath: expanded) : nil
    }

    private func openFileLocation(_ id: Int64) {
        guard let url = fileURL(id) else {
            Toast.show("파일을 찾을 수 없어요", always: true)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        StatusLog.append("panel open location id=\(id)")
    }

    /// 고칠 수 있는 글자(평문·HTML·RTF 항목의 평문). 이미지·파일은 nil.
    private func editableText(_ id: Int64) -> String? {
        guard let item = full(id), [.text, .html, .rtf].contains(item.kind) else { return nil }
        return item.formats[ClipClassifier.plainText].flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private func editText(_ id: Int64) {
        guard let text = editableText(id) else { return }
        TextEditWindow.show(text: text, near: window.frame) { [weak self] new in
            guard let self, new != text else { return }
            try? self.db.updateText(id: id, new)
            StatusLog.append("panel edit id=\(id) chars=\(new.count)")
            self.reload()
            self.select(id)
        }
    }

    // MARK: 끌어서 고정 순서 바꾸기·고정

    /// 패널 안 끌기 위치 → 고정 영역이면 (표시할 선의 y, 이 항목 앞 — nil은 맨 뒤). 히스토리 영역이면 nil.
    fileprivate func pinDropTarget(at p: NSPoint) -> (lineY: CGFloat, before: Int64?)? {
        guard let sep = pinnedSeparator else { return nil }
        let sepY = sep.convert(sep.bounds, to: doc).minY
        guard p.y < sepY else { return nil }   // 뒤집힌 좌표: 위쪽이 작은 y
        let rows = pinnedItems.compactMap(\.id).compactMap { id in itemViews[id].map { (id, $0.convert($0.bounds, to: doc)) } }
        for (id, r) in rows where p.y < r.midY { return (r.minY - 3, id) }
        return (rows.last.map { $0.1.maxY + 3 } ?? sepY - 4, nil)
    }

    /// 고정 항목은 그 자리로 옮기고, 히스토리 항목은 그 자리에 고정한다.
    fileprivate func dropOnPinned(_ id: Int64, before: Int64?) {
        if !pinnedItems.contains(where: { $0.id == id }) { try? db.setPinned(id: id, true) }
        try? db.setPinOrder(PinOrder.moving(id, before: before, in: pinnedItems.compactMap(\.id)))
        StatusLog.append("panel pin drop id=\(id) before=\(before.map(String.init) ?? "end")")
        reload()
        select(id)
    }

    private func dragItem(_ id: Int64, asPath: Bool) -> NSPasteboardItem? {
        guard let item = full(id) else { return nil }
        let pb = NSPasteboardItem()
        pb.setString(String(id), forType: .pasteFlowItem)   // 패널 안에 놓으면 고정 순서 바꾸기·고정
        if item.kind == .image, let url = paste.tempPNGPath(for: item) {
            if asPath {
                pb.setString(url.path, forType: .string)       // ⌥+드래그: 경로 글자
            } else {
                pb.setString(url.absoluteString, forType: .fileURL)  // Finder 등은 파일로 받음
                if let png = item.formats["public.png"] { pb.setData(png, forType: .png) }
            }
            return pb
        }
        for (type, data) in item.formats {
            pb.setData(data, forType: NSPasteboard.PasteboardType(type))
        }
        return pb
    }

    /// 패널이 키 창일 때의 키 입력. 처리했으면 true.
    private func handleKey(_ e: NSEvent) -> Bool {
        StatusLog.append("panel key code=\(e.keyCode) selected=\(selectedId.map(String.init) ?? "-")")
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch e.keyCode {
        case 53: hide(); return true                                        // Esc
        case 36, 76: pasteSelected(asPath: mods.contains(.option)); return true  // Enter(⌥Enter = 경로로)
        case 49: if let id = selectedId { preview(id) }; return true        // Space
        case 51, 117: if let id = selectedId { delete(id) }; return true    // ⌫, ⌦
        case 125, 126:                                                      // ↓ ↑
            let ids = orderedIds
            guard !ids.isEmpty else { return true }
            let cur = selectedId.flatMap { ids.firstIndex(of: $0) }
            let next = e.keyCode == 125 ? min((cur ?? -1) + 1, ids.count - 1) : max((cur ?? ids.count) - 1, 0)
            select(ids[next])
            return true
        default: break
        }
        if mods.contains(.command), e.charactersIgnoringModifiers == "c", let id = selectedId, let item = full(id) {
            paste.copyToClipboard(item)
            return true
        }
        if mods.isEmpty, e.keyCode == 35, let id = selectedId {             // P
            togglePinned(id)
            return true
        }
        if mods.isEmpty, e.keyCode == 8, let id = selectedId {              // C: 큐 지정/해제
            toggleQueue(id)
            return true
        }
        if mods.isEmpty, e.keyCode == 31, let id = selectedId {             // O: 파일 위치 열기
            openFileLocation(id)
            return true
        }
        return false
    }

    private func itemMenu(_ id: Int64) -> NSMenu {
        select(id)
        let m = NSMenu()
        let isPinned = pinnedItems.contains { $0.id == id }
        let isImage = (pinnedItems + historyItems).first { $0.id == id }?.kind == .image
        m.addItem(MenuAction("미리보기", key: " ") { [weak self] in self?.preview(id) })
        m.addItem(MenuAction("붙여넣기", key: "\r") { [weak self] in self?.pasteSelected() })
        let inQueue = queue.items.contains { $0.id == id }
        m.addItem(MenuAction(inQueue ? "큐 해제" : "큐에 추가", key: "c") { [weak self] in
            if inQueue { self?.paste.clearQueueFromPanel() } else { self?.selectQueue(id) } })
        m.addItem(.separator())
        m.addItem(MenuAction("복사", key: "c", mods: .command) { [weak self] in
            if let item = self?.full(id) { self?.paste.copyToClipboard(item) } })
        if isImage {
            m.addItem(MenuAction("파일로 저장 후 경로 복사") { [weak self] in
                if let item = self?.full(id) { self?.paste.copyToClipboard(item, asPath: true) } })
        }
        // 조건부 항목은 숨기지 않고 비활성(윈도우판 — 자리가 흔들리지 않게)
        let open = MenuAction("파일 위치 열기", key: "o") { [weak self] in self?.openFileLocation(id) }
        open.isEnabled = fileURL(id) != nil
        m.addItem(open)
        let editItem = MenuAction("수정") { [weak self] in self?.editText(id) }
        editItem.isEnabled = !isImage && editableText(id) != nil
        m.addItem(editItem)
        m.addItem(.separator())
        m.addItem(MenuAction(isPinned ? "고정 해제" : "고정추가", key: "p") { [weak self] in self?.togglePinned(id) })
        m.addItem(MenuAction("삭제", key: "\u{8}") { [weak self] in self?.delete(id) })
        return m
    }

    private func backgroundMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(MenuAction("패널 숨기기") { [weak self] in self?.hide() })
        m.addItem(MenuAction("히스토리 초기화") { [weak self] in self?.confirmClearHistory() })
        m.addItem(.separator())
        m.addItem(MenuAction("설정…") { [weak self] in
            self?.hide()
            SettingsWindow.show()
        })
        m.addItem(.separator())
        m.addItem(MenuAction("PasteFlow 종료") { NSApp.terminate(nil) })
        return m
    }

    private func confirmClearHistory() {
        let a = NSAlert()
        a.messageText = "히스토리를 모두 지울까요?"
        a.informativeText = "고정메모는 남아요. 지운 항목은 되돌릴 수 없어요."
        a.addButton(withTitle: "지우기")
        a.addButton(withTitle: "취소")
        a.buttons.first?.hasDestructiveAction = true
        guard a.runModal() == .alertFirstButtonReturn else { return }
        for item in historyItems { if let id = item.id { paste.removeFromQueue(id: id) } }
        try? db.clearHistory()
        reload()
    }

    @objc private func toggleSection(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        if collapsed.contains(key) { collapsed.remove(key) } else { collapsed.insert(key) }
        reload()
    }

    @objc private func togglePin() {
        alwaysOnTop.toggle()
        window.level = alwaysOnTop ? .floating : .normal
        updatePinButton()
    }

    private func updatePinButton() {
        pinButton.contentTintColor = alwaysOnTop ? Theme.coral : Theme.secondary
        pinButton.toolTip = alwaysOnTop ? "항상 위에: 켜짐" : "항상 위에: 꺼짐"
    }

    @objc private func closeClicked() { hide() }
}

// MARK: - 창

final class ClipPanelWindow: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel, .resizable],
                   backing: .buffered, defer: false)
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) != true { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

final class PanelRootView: NSView {
    var onBackgroundMenu: (() -> NSMenu?)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { window?.keyDown(with: event) }
    override func menu(for event: NSEvent) -> NSMenu? { onBackgroundMenu?() }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

extension NSPasteboard.PasteboardType {
    /// 패널 항목 id — 패널 안에서 끌어 놓을 때만 쓴다.
    static let pasteFlowItem = NSPasteboard.PasteboardType("com.minwoo.pasteflow.item-id")
}

/// 패널 목록 바탕 — 항목을 고정 영역에 끌어 놓으면 순서 바꾸기·고정. 놓일 자리에 코랄 선을 그린다.
final class PanelListView: NSView {
    weak var controller: ClipPanelController?
    override var isFlipped: Bool { true }
    private var lineY: CGFloat? { didSet { if lineY != oldValue { needsDisplay = true } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.pasteFlowItem])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func target(_ info: NSDraggingInfo) -> (lineY: CGFloat, before: Int64?)? {
        guard info.draggingPasteboard.string(forType: .pasteFlowItem) != nil else { return nil }
        return controller?.pinDropTarget(at: convert(info.draggingLocation, from: nil))
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let t = target(sender)
        lineY = t?.lineY
        return t == nil ? [] : .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { lineY = nil }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { lineY = nil }
        guard let t = target(sender), let s = sender.draggingPasteboard.string(forType: .pasteFlowItem),
              let id = Int64(s) else { return false }
        // 놓기 처리 중 목록을 다시 그리면 끌기 세션이 지운 뷰를 붙잡는다 → 다음 차례에
        DispatchQueue.main.async { [weak controller] in controller?.dropOnPinned(id, before: t.before) }
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let y = lineY else { return }
        Theme.coral.setFill()
        NSBezierPath(roundedRect: NSRect(x: 10, y: y - 1, width: bounds.width - 20, height: 2), xRadius: 1, yRadius: 1).fill()
    }
}

/// 클로저로 동작하는 메뉴 항목.
final class MenuAction: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", mods: NSEvent.ModifierFlags = [], handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        keyEquivalentModifierMask = mods
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func fire() { handler() }
}

// MARK: - 항목 한 칸

final class ClipItemView: NSView, NSDraggingSource {
    enum QueueState { case none, waiting, next, done }

    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onMenu: (() -> NSMenu?)?
    var dragProvider: ((Bool) -> NSPasteboardItem?)?
    var isSelected = false { didSet { updateLook() } }

    private let item: ClipItem
    private let state: QueueState
    private let label = NSTextField(wrappingLabelWithString: "")
    private var hovering = false { didSet { updateLook() } }
    private var mouseDownEvent: NSEvent?

    init(item: ClipItem, state: QueueState) {
        self.item = item
        self.state = state
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Theme.itemRadius
        translatesAutoresizingMaskIntoConstraints = false

        if item.kind == .image, let data = item.thumbnail, let img = NSImage(data: data) {
            let iv = NSImageView(image: img)
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.wantsLayer = true
            iv.layer?.cornerRadius = Theme.itemRadius - 2
            iv.layer?.masksToBounds = true
            iv.translatesAutoresizingMaskIntoConstraints = false
            addSubview(iv)
            NSLayoutConstraint.activate([
                iv.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
                iv.topAnchor.constraint(equalTo: topAnchor, constant: 5),
                iv.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
                iv.widthAnchor.constraint(equalToConstant: 96),
                iv.heightAnchor.constraint(equalToConstant: 72),
            ])
            toolTip = item.previewText
        } else {
            label.stringValue = item.previewText
            label.font = .systemFont(ofSize: 12)
            label.maximumNumberOfLines = 5
            label.lineBreakMode = .byWordWrapping
            label.cell?.truncatesLastVisibleLine = true
            label.isSelectable = false
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
                label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
                label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            ])
        }
        updateLook()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let w = bounds.width - 18
        if w > 0, label.preferredMaxLayoutWidth != w {
            label.preferredMaxLayoutWidth = w
            invalidateIntrinsicContentSize()
        }
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    private func updateLook() {
        let bg: NSColor
        switch (state, isSelected, hovering) {
        case (.next, _, _): bg = Theme.coralFill
        case (_, true, _): bg = Theme.itemSelected
        case (_, _, true): bg = Theme.itemHover
        default: bg = Theme.item
        }
        layer?.backgroundColor = bg.cgColor
        let ring = state == .waiting || state == .next
        layer?.borderWidth = ring ? 1 : (isSelected ? 1 : 0)
        layer?.borderColor = (ring ? Theme.coral : NSColor(white: 1, alpha: 0.28)).cgColor
        label.textColor = state == .done ? Theme.dim : Theme.text
        alphaValue = (state == .done && item.kind == .image) ? 0.5 : 1
    }

    // 항목 안의 글자 칸·이미지가 클릭을 가로채면 패널의 "빈 곳 끌어 창 이동"이 발동한다 → 항목이 직접 받는다
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override var mouseDownCanMoveWindow: Bool { false }
    // 다른 창에서 일하다 패널 항목을 바로 끌 수 있게 — 첫 클릭(패널 깨우기)도 항목이 받는다
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        if event.clickCount == 2 { onDoubleClick?() } else { onClick?() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        let a = down.locationInWindow, b = event.locationInWindow
        guard hypot(b.x - a.x, b.y - a.y) > 4 else { return }
        mouseDownEvent = nil
        let asPath = event.modifierFlags.contains(.option)
        guard let pbItem = dragProvider?(asPath) else { return }
        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        dragItem.setDraggingFrame(bounds, contents: snapshot())
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? { onMenu?() }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy] : [.move]   // 앱 안 = 패널 고정 영역에 놓기
    }

    /// 다른 앱에 놓았으면 그 앱을 앞으로 — 안 그러면 키보드가 패널에 남아 놓은 뒤 친 글자가 패널로 간다(윈도우판도 놓은 창을 앞으로).
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard !operation.isEmpty, window?.frame.contains(screenPoint) == false,
              let pid = Self.appPID(at: screenPoint), let app = NSRunningApplication(processIdentifier: pid) else { return }
        // 놓은 앱이 이미 맨 앞 앱이면 activate만으로는 키보드가 패널에서 안 돌아온다(패널은 앱을 앞으로 안 부르는 창)
        // → 패널을 잠깐 내렸다 키 없이 다시 띄워 키보드를 놓아 준다
        if let w = window { w.orderOut(nil); w.orderFrontRegardless() }
        let ok = app.activate()
        // macOS 14+ 활성화는 양보식이라 거절될 수 있다 — 실제로 앞에 왔는지 남겨 둔다
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            StatusLog.append("panel drop-out activate \(app.bundleIdentifier ?? "\(pid)") ok=\(ok) front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-")")
        }
    }

    /// 화면 지점(Cocoa 전역)에서 맨 앞 일반 창(layer 0)의 앱. 내 창은 뺀다.
    private static func appPID(at p: NSPoint) -> pid_t? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let cg = CGPoint(x: p.x, y: primaryHeight - p.y)
        let myPid = ProcessInfo.processInfo.processIdentifier
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? Int32, pid != myPid,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0).contains(cg) else { continue }
            return pid
        }
        return nil
    }

    private func snapshot() -> NSImage {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return NSImage() }
        cacheDisplay(in: bounds, to: rep)
        let img = NSImage(size: bounds.size)
        img.addRepresentation(rep)
        return img
    }
}
