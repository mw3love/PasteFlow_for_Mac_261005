import AppKit
import PasteFlowCore

/// OCR 설정 값(주소·모델은 DB, API 키는 앱 전용 비밀 파일, 받아 둔 모델 목록·크레딧은 DB 캐시).
enum OCRSettings {
    static let keyAccount = "ocr_api_key"

    static func baseURL(_ db: ClipDatabase?) -> String {
        ((try? db?.setting("ocr_base_url")) ?? nil) ?? GatewayOCR.defaultBaseURL
    }

    static func model(_ db: ClipDatabase?) -> String {
        ((try? db?.setting("ocr_model")) ?? nil) ?? GatewayOCR.defaultModel
    }

    static var apiKey: String? { SecretStore.get(keyAccount) }

    /// 마지막으로 받은 크레딧 문구(메뉴는 이 값만 보여준다 — 메뉴를 열 때 네트워크·비밀값을 건드리지 않음).
    static func cachedCredits(_ db: ClipDatabase?) -> String? { (try? db?.setting("ocr_credits_text")) ?? nil }

    /// 크레딧을 새로 받아 캐시에 넣고 문구를 돌려준다.
    @discardableResult
    static func refreshCredits(_ db: ClipDatabase?, key: String? = nil) async throws -> String {
        guard let key = key ?? apiKey else { throw GatewayOCR.Failure.missingKey }
        let text = creditsText(try await GatewayOCR.fetchCredits(baseURL: baseURL(db), apiKey: key))
        try? db?.setSetting("ocr_credits_text", text)
        return text
    }

    /// 새로고침으로 받아 둔 게이트웨이 모델 목록.
    static func cachedModels(_ db: ClipDatabase?) -> [String] {
        (((try? db?.setting("ocr_models_cache")) ?? nil) ?? "").split(separator: "\n").map(String.init)
    }

    static func saveModels(_ models: [String], db: ClipDatabase?) {
        try? db?.setSetting("ocr_models_cache", models.joined(separator: "\n"))
    }

    /// 폴백: 받아 둔 목록에서 최신 flash, 목록이 없으면 고정값.
    static func fallback(_ db: ClipDatabase?, for model: String) -> String {
        GatewayOCR.pickFallback(from: cachedModels(db), excluding: model) ?? GatewayOCR.staticFallback
    }

    static func creditsText(_ c: (remaining: Double, quota: Double)) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return "남은 크레딧 \(f.string(from: NSNumber(value: c.remaining)) ?? "?") / \(f.string(from: NSNumber(value: c.quota)) ?? "?")"
    }

    /// 연결 테스트용 한글 샘플(앱 안에서 그림).
    static func samplePNG() -> Data? {
        let text = "순차 붙여넣기 123\n밥·팝, 이·의·에"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 26), .foregroundColor: NSColor.black]
        let size = NSSize(width: 420, height: 100)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        (text as NSString).draw(in: NSRect(x: 14, y: 8, width: size.width - 28, height: size.height - 16), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

/// OCR 설정 창(임시 — 9단계 설정창의 OCR 칸으로 옮길 예정). 모달이 아니라서 새로고침·테스트가 창을 막지 않는다.
final class OCRSettingsWindow: NSWindowController, NSWindowDelegate {
    private static var shared: OCRSettingsWindow?

    static func show(db: ClipDatabase?) {
        if shared == nil { shared = OCRSettingsWindow(db: db) }
        shared?.reloadFields()
        NSApp.activate(ignoringOtherApps: true)
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
    }

    private let db: ClipDatabase?
    private let baseField = NSTextField()
    private let modelBox = NSComboBox()
    private let keyField = NSSecureTextField()
    private let keyStatus = NSTextField(labelWithString: "")
    private let creditsLabel = NSTextField(labelWithString: "")
    private let modelsLabel = NSTextField(labelWithString: "")
    private let testLabel = NSTextField(labelWithString: "")

    private init(db: ClipDatabase?) {
        self.db = db
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300), styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "OCR 설정"
        w.isReleasedWhenClosed = false
        super.init(window: w)
        w.delegate = self
        build()
        w.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        return b
    }

    private func build() {
        modelBox.isEditable = true
        modelBox.completes = true
        modelBox.numberOfVisibleItems = 14
        keyField.placeholderString = "새 키를 붙여넣을 때만 입력"
        [keyStatus, creditsLabel, modelsLabel, testLabel].forEach {
            $0.font = .systemFont(ofSize: 12)
            $0.textColor = .secondaryLabelColor
        }

        let modelRow = NSStackView(views: [modelBox, button("새로고침", #selector(refresh))])
        let testRow = NSStackView(views: [button("연결 테스트", #selector(test)), testLabel])
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "주소"), baseField],
            [NSTextField(labelWithString: "모델"), modelRow],
            [NSGridCell.emptyContentView, modelsLabel],
            [NSTextField(labelWithString: "API 키"), keyField],
            [NSGridCell.emptyContentView, keyStatus],
            [NSTextField(labelWithString: "크레딧"), creditsLabel],
            [NSGridCell.emptyContentView, testRow],
        ])
        grid.rowSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 400

        let save = button("저장", #selector(save))
        save.keyEquivalent = "\r"
        let close = button("닫기", #selector(closeClicked))
        close.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [NSView(), close, save])

        let stack = NSStackView(views: [grid, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        window?.contentView = NSView()
        window?.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window!.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window!.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window!.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: window!.contentView!.bottomAnchor),
            buttons.widthAnchor.constraint(equalTo: grid.widthAnchor),
            modelBox.widthAnchor.constraint(equalToConstant: 300),
        ])
    }

    private func reloadFields() {
        baseField.stringValue = OCRSettings.baseURL(db)
        let models = OCRSettings.cachedModels(db)
        modelBox.removeAllItems()
        modelBox.addItems(withObjectValues: models)
        modelBox.stringValue = OCRSettings.model(db)
        modelsLabel.stringValue = models.isEmpty ? "모델 목록을 아직 받지 않았어요 — 새로고침" : "받아 둔 모델 \(models.count)개 · 폴백: \(OCRSettings.fallback(db, for: modelBox.stringValue))"
        keyField.stringValue = ""
        keyStatus.stringValue = OCRSettings.apiKey == nil ? "키 없음 — 붙여넣고 저장하세요" : "저장됨(앱 전용 파일)"
        testLabel.stringValue = ""
        creditsLabel.stringValue = "확인 중…"
        Task { @MainActor in await self.loadCredits() }
    }

    /// 입력칸의 새 키가 있으면 그걸, 없으면 저장된 키.
    private var currentKey: String? {
        let typed = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? OCRSettings.apiKey : typed
    }

    private func loadCredits() async {
        guard let key = currentKey else { creditsLabel.stringValue = "키가 없어 확인할 수 없어요"; return }
        do {
            creditsLabel.stringValue = try await OCRSettings.refreshCredits(db, key: key)
        } catch {
            creditsLabel.stringValue = "확인 실패: \(error)"
        }
    }

    @objc private func refresh() {
        guard let key = currentKey else { modelsLabel.stringValue = "키가 없어요"; return }
        modelsLabel.stringValue = "받는 중…"
        Task { @MainActor in
            do {
                let models = try await GatewayOCR.fetchModels(baseURL: baseField.stringValue, apiKey: key)
                OCRSettings.saveModels(models, db: db)
                let current = modelBox.stringValue
                modelBox.removeAllItems()
                modelBox.addItems(withObjectValues: models)
                modelBox.stringValue = current
                let missing = models.contains(current) ? "" : " ⚠ 지금 모델은 목록에 없어요"
                modelsLabel.stringValue = "모델 \(models.count)개 · 폴백: \(OCRSettings.fallback(db, for: current))\(missing)"
                StatusLog.append("ocr models refreshed count=\(models.count) currentListed=\(missing.isEmpty)")
            } catch {
                modelsLabel.stringValue = "받기 실패: \(error)"
            }
            await loadCredits()
        }
    }

    @objc private func test() {
        guard let key = currentKey, let png = OCRSettings.samplePNG() else { testLabel.stringValue = "키가 없어요"; return }
        let model = modelBox.stringValue.trimmingCharacters(in: .whitespaces)
        testLabel.stringValue = "\(model) 확인 중…"
        let t0 = Date()
        Task { @MainActor in
            // 폴백 없이 고른 모델만 — 망가진 모델이 폴백으로 조용히 ✓가 되지 않게(윈도우판 원칙)
            let (result, _) = await GatewayOCR.recognize(png: png, baseURL: baseField.stringValue, apiKey: key, model: model, fallback: nil)
            let sec = String(format: "%.1f초", Date().timeIntervalSince(t0))
            switch result {
            case .success(let text):
                let ok = text.contains("순차") && text.contains("123")
                testLabel.stringValue = ok ? "✓ \(sec) — 한글 샘플을 정확히 읽었어요" : "△ \(sec) — 읽었지만 내용이 달라요: \(text.prefix(30))"
            case .failure(let f):
                testLabel.stringValue = "✗ \(f.description)"
            }
            StatusLog.append("ocr test model=\(model) result=\(testLabel.stringValue.prefix(2))")
            await loadCredits()
        }
    }

    @objc private func save() {
        try? db?.setSetting("ocr_base_url", GatewayOCR.normalizeBaseURL(baseField.stringValue))
        try? db?.setSetting("ocr_model", modelBox.stringValue.trimmingCharacters(in: .whitespaces))
        let newKey = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newKey.isEmpty {
            SecretStore.set(OCRSettings.keyAccount, newKey)
            // 키를 복사해 붙여넣었다면 그 복사가 히스토리에 남았을 수 있다 → 같은 내용은 지운다
            let removed = (try? db?.deleteItems(withPlainText: newKey)) ?? []
            StatusLog.append("ocr key saved; removed matching history items=\(removed.count)")
            NotificationCenter.default.post(name: .pasteFlowStateChanged, object: nil)
        }
        StatusLog.append("ocr settings saved model=\(OCRSettings.model(db)) keyStored=\(OCRSettings.apiKey != nil)")
        window?.close()
    }

    @objc private func closeClicked() { window?.close() }
}
