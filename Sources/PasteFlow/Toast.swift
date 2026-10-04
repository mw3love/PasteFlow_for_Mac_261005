import AppKit
import PasteFlowCore

/// 우하단 짧은 알림(포커스 안 뺏음). 주 모니터 오른쪽 아래에 최신이 맨 아래로 쌓이고, 최대 5개(윈도우판 `toast.py`와 같은 규칙).
/// 설정 "알림"을 끄면 확인 알림(캡처됨 등)만 숨긴다 — 실패와 OCR 진행·결과처럼 기다리는 알림은 `always`로 계속 뜬다.
enum Toast {
    static let settingKey = "toast_enabled"
    static var enabled = true
    static let copyDuration: TimeInterval = 2.0   // 윈도우판 COPY_TOAST_DURATION_MS
    private static let maxCount = 5

    private final class Entry {
        let panel: NSPanel
        let key: String?
        var hideWork: DispatchWorkItem?
        init(panel: NSPanel, key: String?) { self.panel = panel; self.key = key }
    }
    private static var entries: [Entry] = []

    /// `key`가 같은 알림이 떠 있으면 새로 쌓지 않고 그 자리에서 바꾼다(예: OCR 진행 → 결과).
    static func show(_ title: String, detail: String? = nil, duration: TimeInterval = 1.8, key: String? = nil, always: Bool = false) {
        guard enabled || always else { return }
        present(duration: duration, key: key) { fill($0, title: title, detail: detail) }
    }

    /// 복사 알림 — 앞에 큐 개수 배지(Q3), 뒤에 글자 미리보기(30자) 또는 이미지 썸네일(윈도우판 `show_copy_toast`).
    static func showCopy(_ item: ClipItem, queueCount: Int) {
        guard enabled else { return }   // 확인 알림과 같은 설정 하나로 켜고 끈다(2026-10-04 사용자 결정)
        var image: NSImage?
        if item.kind == .image {
            // 원본을 줄여 그려야 선명하다(패널 썸네일 192px보다 원본 우선 — 윈도우판과 같은 이유)
            image = ClipClassifier.imageTypes.lazy.compactMap { item.formats[$0].flatMap(NSImage.init(data:)) }.first
                ?? item.thumbnail.flatMap(NSImage.init(data:))
        }
        let text = Self.elide(item.previewText)
        present(duration: copyDuration, key: nil) { fillCopy($0, badge: "Q\(queueCount)", text: text, image: image) }
    }

    /// 공백·줄바꿈을 한 칸으로 합치고 30자로 줄인다(윈도우판 `_elide`).
    static func elide(_ s: String, limit: Int = 30) -> String {
        let one = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return one.count > limit ? String(one.prefix(limit)) + "…" : (one.isEmpty ? "클립보드 항목" : one)
    }

    private static func present(duration: TimeInterval, key: String?, fillPanel: (NSPanel) -> Void) {
        let entry: Entry
        if let key, let existing = entries.first(where: { $0.key == key }) {
            entry = existing
        } else {
            entry = Entry(panel: makePanel(), key: key)
            entries.append(entry)
            if entries.count > maxCount { remove(entries[0], animated: false) }
        }
        fillPanel(entry.panel)
        entry.panel.alphaValue = 1
        entry.panel.orderFrontRegardless()
        relayout()

        entry.hideWork?.cancel()
        let work = DispatchWorkItem { remove(entry, animated: true) }
        entry.hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private static func remove(_ entry: Entry, animated: Bool) {
        entry.hideWork?.cancel()
        entries.removeAll { $0 === entry }
        relayout()
        guard animated else { entry.panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; entry.panel.animator().alphaValue = 0 },
                                             completionHandler: { entry.panel.orderOut(nil) })
    }

    /// 맨 아래가 최신. 주 모니터(메뉴바가 있는 화면)에 고정 — 커서를 따라 옮겨 다니지 않게.
    private static func relayout() {
        let vf = NSScreen.screens.first?.visibleFrame ?? .zero
        var y = vf.minY + 20
        for e in entries.reversed() {
            let size = e.panel.frame.size
            e.panel.setFrame(NSRect(x: vf.maxX - size.width - 20, y: y, width: size.width, height: size.height), display: true)
            y += size.height + 8
        }
    }

    private static func fill(_ p: NSPanel, title: String, detail: String?) {
        let box = p.contentView!
        box.subviews.forEach { $0.removeFromSuperview() }

        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 13, weight: .semibold)
        t.textColor = Theme.coral
        var views: [NSView] = [t]
        if let detail {
            let d = NSTextField(labelWithString: detail)
            d.font = .systemFont(ofSize: 12)
            d.textColor = Theme.text2
            d.lineBreakMode = .byTruncatingMiddle
            d.widthAnchor.constraint(lessThanOrEqualToConstant: 300).isActive = true
            views.append(d)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor), stack.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            stack.topAnchor.constraint(equalTo: box.topAnchor), stack.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        box.layoutSubtreeIfNeeded()
        p.setContentSize(stack.fittingSize)
    }

    private static func fillCopy(_ p: NSPanel, badge: String, text: String, image: NSImage?) {
        let box = p.contentView!
        box.subviews.forEach { $0.removeFromSuperview() }

        let b = NSTextField(labelWithString: badge)
        b.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        b.textColor = Theme.bg
        b.alignment = .center
        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = Theme.coral.cgColor
        pill.layer?.cornerRadius = 9
        pill.translatesAutoresizingMaskIntoConstraints = false
        b.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(b)
        NSLayoutConstraint.activate([
            b.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 7),
            b.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -7),
            b.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: 18),
        ])

        var views: [NSView] = [pill]
        if let image, image.size.width > 0, image.size.height > 0 {
            // 최대 96×72pt, 비율 유지
            let scale = min(96 / image.size.width, 72 / image.size.height, 1)
            let iv = NSImageView(image: image)
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.wantsLayer = true
            iv.layer?.cornerRadius = 4
            iv.layer?.masksToBounds = true
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.widthAnchor.constraint(equalToConstant: max(1, (image.size.width * scale).rounded())).isActive = true
            iv.heightAnchor.constraint(equalToConstant: max(1, (image.size.height * scale).rounded())).isActive = true
            views.append(iv)
        } else {
            let t = NSTextField(labelWithString: text)
            t.font = .systemFont(ofSize: 12)
            t.textColor = Theme.text
            t.lineBreakMode = .byTruncatingTail
            t.widthAnchor.constraint(lessThanOrEqualToConstant: 280).isActive = true
            views.append(t)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 9, left: 10, bottom: 9, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor), stack.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            stack.topAnchor.constraint(equalTo: box.topAnchor), stack.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        box.layoutSubtreeIfNeeded()
        p.setContentSize(stack.fittingSize)
    }

    private static func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = Theme.bg.cgColor
        box.layer?.cornerRadius = Theme.windowRadius
        box.layer?.borderWidth = 0.5
        box.layer?.borderColor = Theme.border.cgColor
        p.contentView = box
        return p
    }
}
