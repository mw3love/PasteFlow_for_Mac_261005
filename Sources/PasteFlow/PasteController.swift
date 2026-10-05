import AppKit
import PasteFlowCore

extension Notification.Name {
    /// 히스토리·큐 상태가 바뀜 — 패널이 듣고 다시 그린다.
    static let pasteFlowStateChanged = Notification.Name("PasteFlowStateChanged")
}

/// 큐에서 항목을 꺼내 클립보드에 쓰고 ⌘V를 주입한다. 순차·전체·경로 붙여넣기와 큐 비우기를 한곳에서 다룬다.
final class PasteController {
    /// 전체 자동 붙여넣기 간격(윈도우판과 동일).
    static let bulkInterval: TimeInterval = 0.3
    /// 클립보드에 쓴 뒤 ⌘V를 누르기까지 기다리는 시간.
    static let injectDelay: TimeInterval = 0.05

    private let queue: PasteQueue
    private let monitor: ClipboardMonitor
    private let hud: PasteHUD
    private let tempStore: TempImageStore
    private var bulkTimer: Timer?

    init(queue: PasteQueue, monitor: ClipboardMonitor, hud: PasteHUD, tempStore: TempImageStore) {
        self.queue = queue
        self.monitor = monitor
        self.hud = hud
        self.tempStore = tempStore
        hud.onCancel = { [weak self] in self?.clearQueue(reason: "cancel") }
    }

    func handle(_ action: PasteAction) {
        switch action {
        case .sequential: pasteNext(asPath: false)
        case .path: pasteNext(asPath: true)
        case .sequentialAll: startBulk(asPath: false)
        case .pathAll: startBulk(asPath: true)
        case .plainPaste:
            // 사용자가 직접 누른 ⌘V — 진행 중인 큐는 포기
            if queue.status.total > 0 { clearQueue(reason: "plain ⌘V") }
        }
    }

    /// 새 복사가 들어왔을 때(큐가 새 묶음으로 바뀌었을 수 있음) HUD를 정리한다.
    func didCopy() {
        bulkTimer?.invalidate()
        bulkTimer = nil
        hud.dismiss()
        notifyChanged()
    }

    /// 패널에서 고른 항목 하나를 바로 붙여넣는다(큐와 무관). `asPath`면 이미지를 임시 PNG 경로로.
    func pasteItem(_ item: ClipItem, asPath: Bool = false) {
        write(item, asPath: asPath)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.injectDelay) {
            KeyInterceptor.injectCommandV()
        }
        StatusLog.append("paste from panel id=\(item.id ?? 0) asPath=\(asPath)")
    }

    /// 클립보드에만 올린다(붙여넣기 없이).
    func copyToClipboard(_ item: ClipItem, asPath: Bool = false) {
        write(item, asPath: asPath)
    }

    /// 이미지 항목을 임시 PNG로 저장하고 경로를 돌려준다(끌어다 놓기·경로 복사용).
    func tempPNGPath(for item: ClipItem) -> URL? {
        guard item.kind == .image, let png = Self.pngData(item) else { return nil }
        return try? tempStore.save(png: png, itemId: item.id)
    }

    /// 패널에서 고른 항목들로 큐를 새로 지정한다(C). 다음 순차 붙여넣기부터 이 순서로.
    func setQueue(_ items: [ClipItem]) {
        bulkTimer?.invalidate()
        bulkTimer = nil
        queue.replace(with: items)
        hud.dismiss()
        notifyChanged()
        StatusLog.append("queue set from panel ids=\(items.compactMap(\.id))")
    }

    /// 패널에서 큐 해제(C·메뉴).
    func clearQueueFromPanel() { clearQueue(reason: "panel") }

    /// 히스토리에서 지운 항목을 큐에서도 빼고 HUD를 맞춘다.
    func removeFromQueue(id: Int64) {
        guard queue.remove(id: id) else { return }
        let s = queue.status
        if s.total == 0 {
            hud.dismiss()
        } else if hud.isVisible {
            hud.show(items: queue.items, pointer: s.pointer)
        }
        notifyChanged()
    }

    /// 화면 핀용으로 큐의 다음 항목을 꺼낸다(순차 붙여넣기와 포인터 공유). 큐가 비었으면 nil.
    func takeNextForPin() -> ClipItem? {
        guard let item = queue.next() else { return nil }
        let s = queue.status
        hud.show(items: queue.items, pointer: s.pointer)
        if queue.isExhausted { finish() }
        notifyChanged()
        return item
    }

    func notifyChanged() {
        NotificationCenter.default.post(name: .pasteFlowStateChanged, object: nil)
    }

    // MARK: 내부

    @discardableResult
    private func pasteNext(asPath: Bool) -> Bool {
        guard let item = queue.next() else { return false }   // 소진: 키만 삼키고 아무것도 안 함
        write(item, asPath: asPath)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.injectDelay) {
            KeyInterceptor.injectCommandV()
        }
        let s = queue.status
        StatusLog.append("paste id=\(item.id ?? 0) asPath=\(asPath) queue=\(s.pointer)/\(s.total)")
        hud.show(items: queue.items, pointer: s.pointer)
        if queue.isExhausted { finish() }
        notifyChanged()
        return true
    }

    private func startBulk(asPath: Bool) {
        bulkTimer?.invalidate()
        guard pasteNext(asPath: asPath) else { return }
        bulkTimer = Timer.scheduledTimer(withTimeInterval: Self.bulkInterval, repeats: true) { [weak self] t in
            guard let self, self.pasteNext(asPath: asPath) else { t.invalidate(); return }
        }
    }

    private func finish() {
        bulkTimer?.invalidate()
        bulkTimer = nil
        hud.finish()
        // 소진 완료 — 다음 ⌘V가 엉뚱한 큐 찌꺼기를 보지 않도록 비운다. HUD는 마지막 상태를 잠시 보여준 뒤 사라진다.
        queue.clear()
    }

    private func clearQueue(reason: String) {
        bulkTimer?.invalidate()
        bulkTimer = nil
        queue.clear()
        hud.dismiss()
        notifyChanged()
        StatusLog.append("queue cleared (\(reason))")
    }

    private func write(_ item: ClipItem, asPath: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if asPath, let url = tempPNGPath(for: item) {
            pb.setString(url.path, forType: .string)
        } else {
            let pbItem = NSPasteboardItem()
            for (type, data) in item.formats {
                pbItem.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            pb.writeObjects([pbItem])
        }
        monitor.noteSelfChange()
    }

    static func pngData(_ item: ClipItem) -> Data? {
        if let png = item.formats["public.png"] { return png }
        for t in ClipClassifier.imageTypes {
            if let d = item.formats[t], let rep = NSBitmapImageRep(data: d) {
                return rep.representation(using: .png, properties: [:])
            }
        }
        return nil
    }
}
