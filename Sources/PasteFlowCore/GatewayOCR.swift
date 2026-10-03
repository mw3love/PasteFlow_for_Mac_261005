import Foundation

/// OpenAI 호환 게이트웨이(mindlogic)로 Gemini에게 이미지 글자 읽기를 맡긴다 — 윈도우판 `ocr_engine.py` 규칙.
public enum GatewayOCR {
    public static let defaultBaseURL = "https://factchat-cloud.mindlogic.ai/v1/gateway"   // jbnu 계정(OCR용)
    /// 2026-10-03 게이트웨이 목록 기준 lite 중 최상위(실측: 한글 샘플 정확, 2.1~2.9초).
    public static let defaultModel = "gemini-3.5-flash-lite"
    /// 받아 둔 모델 목록이 없을 때만 쓰는 폴백. 평소엔 `pickFallback`이 목록에서 최신 flash를 고른다
    /// (옛 모델부터 사라지므로 이름을 고정한 폴백은 언젠가 깨진다 — 윈도우판의 gemini-2.0-flash가 그랬다).
    public static let staticFallback = "gemini-3.8-flash"
    /// 게이트웨이가 생각(thinking) 토큰을 같은 예산에서 빼므로 작게 잡으면 본문이 잘린다(윈도우판 실측).
    public static let maxTokens = 16384
    /// Cloudflare가 기본 UA를 봇으로 보고 403(code 1010)으로 막아 브라우저형 UA를 쓴다.
    public static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

    public static let koreanPrompt =
        "Extract all text from this image with high accuracy. " +
        "This image contains Korean text — carefully distinguish similar-looking " +
        "Korean characters (e.g. ㅂ/ㅍ, ㄱ/ㄴ/ㄷ/ㄹ, ㅅ/ㅈ/ㅊ, ㅗ/ㅛ/ㅜ/ㅠ, 이/의/에). " +
        "Preserve line breaks. Output only the extracted text with no explanation or commentary."

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case missingKey
        case cloudflareBlocked
        case unauthorized
        case modelNotFound(String)
        case imageNotSupported(String)
        case quotaOrBusy(Int)
        case http(Int, String)
        case emptyResult
        case badResponse

        /// 사용자에게 보여줄 한 줄.
        public var description: String {
            switch self {
            case .missingKey: return "API 키가 없어요 — 메뉴바 PasteFlow ▸ OCR 설정"
            case .cloudflareBlocked: return "게이트웨이 앞단에서 막혔어요(403/1010)"
            case .unauthorized: return "API 키가 거부됐어요(401/403)"
            case .modelNotFound(let m): return "모델을 찾을 수 없어요: \(m)"
            case .imageNotSupported(let m): return "이 모델은 이미지를 못 받아요: \(m)"
            case .quotaOrBusy(let c): return "서버가 바쁘거나 한도 초과예요(\(c)) — 잠시 뒤 다시"
            case .http(let c, let m): return "요청 실패(\(c)) \(m.prefix(80))"
            case .emptyResult: return "읽은 글자가 없어요"
            case .badResponse: return "응답을 해석하지 못했어요"
            }
        }

        /// 다른 모델로 다시 시도할 만한 실패인가.
        public var shouldFallback: Bool {
            switch self {
            case .modelNotFound, .imageNotSupported: return true
            default: return false
            }
        }
    }

    /// 사용자가 `/chat/completions`까지 붙여 넣어도 SDK 표준 base로 자른다.
    public static func normalizeBaseURL(_ raw: String) -> String {
        var url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") { url.removeLast() }
        for suffix in ["/chat/completions", "/completions", "/models", "/embeddings"] where url.hasSuffix(suffix) {
            url.removeLast(suffix.count)
            break
        }
        return url
    }

    public static func makeRequest(baseURL: String, apiKey: String, model: String, png: Data, prompt: String = koreanPrompt) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw Failure.missingKey }
        guard let url = URL(string: normalizeBaseURL(baseURL) + "/chat/completions") else { throw Failure.badResponse }
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image_url", "image_url": ["url": "data:image/png;base64," + png.base64EncodedString()]],
                    ["type": "text", "text": prompt],
                ],
            ]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// 응답을 글자 또는 실패로 바꾼다.
    public static func parse(status: Int, body: Data, model: String) -> Result<String, Failure> {
        let text = String(data: body, encoding: .utf8) ?? ""
        let lower = text.lowercased()
        guard (200..<300).contains(status) else {
            if status == 403, lower.contains("1010") { return .failure(.cloudflareBlocked) }
            if status == 401 || status == 403 { return .failure(.unauthorized) }
            if status == 429 || status == 503 { return .failure(.quotaOrBusy(status)) }
            if status == 404 || lower.contains("model_not_found") || (lower.contains("model") && lower.contains("not found")) {
                return .failure(.modelNotFound(model))
            }
            if status == 400, ["image", "vision", "multimodal"].contains(where: lower.contains) {
                return .failure(.imageNotSupported(model))
            }
            return .failure(.http(status, text))
        }
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else { return .failure(.badResponse) }
        let content = (message["content"] as? String ?? "")
        let cleaned = stripCodeFence(content).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? .failure(.emptyResult) : .success(cleaned)
    }

    /// 모델이 ```로 감싸 답하는 경우 껍데기만 벗긴다.
    static func stripCodeFence(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("```"), t.hasSuffix("```"), t.count >= 6 else { return s }
        var inner = String(t.dropFirst(3).dropLast(3))
        if let nl = inner.firstIndex(of: "\n"), !inner[..<nl].contains(" ") { inner = String(inner[inner.index(after: nl)...]) }
        return inner
    }

    // MARK: 모델 목록·크레딧

    /// 목록에서 버전이 가장 높은 `gemini-<버전>-flash`(lite·이미지·음성·실시간 제외).
    public static func pickFallback(from models: [String], excluding: String? = nil) -> String? {
        let pattern = try! NSRegularExpression(pattern: #"^gemini-(\d+(?:\.\d+)*)-flash$"#)
        func version(_ s: String) -> [Int]? {
            guard let m = pattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let r = Range(m.range(at: 1), in: s) else { return nil }
            return s[r].split(separator: ".").compactMap { Int($0) }
        }
        return models.filter { $0 != excluding }
            .compactMap { m in version(m).map { (m, $0) } }
            .max { $0.1.lexicographicallyPrecedes($1.1) }?.0
    }

    public static func request(_ path: String, baseURL: String, apiKey: String) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw Failure.missingKey }
        guard let url = URL(string: normalizeBaseURL(baseURL) + path) else { throw Failure.badResponse }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return req
    }

    /// `/models` 응답 → 모델 id 목록(거르지 않음 — 윈도우판 원칙: 못 쓰는 모델을 몰래 지우면 "왜 없지?"가 된다).
    public static func parseModels(_ data: Data) -> [String]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { return nil }
        return Array(Set(list.compactMap { $0["id"] as? String })).sorted()
    }

    /// `/credits/` 응답 → (남은 양, 전체 한도). mindlogic 게이트웨이 전용.
    public static func parseCredits(_ data: Data) -> (remaining: Double, quota: Double)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let total = json["total"] as? [String: Any],
              let remaining = (total["remaining"] as? NSNumber)?.doubleValue,
              let quota = (total["quota"] as? NSNumber)?.doubleValue else { return nil }
        return (remaining, quota)
    }

    public static func fetchModels(baseURL: String, apiKey: String, session: URLSession = .shared) async throws -> [String] {
        let (data, resp) = try await session.data(for: request("/models", baseURL: baseURL, apiKey: apiKey))
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let models = parseModels(data) else {
            if case .failure(let f) = parse(status: status, body: data, model: "") { throw f }
            throw Failure.badResponse
        }
        return models
    }

    public static func fetchCredits(baseURL: String, apiKey: String, session: URLSession = .shared) async throws -> (remaining: Double, quota: Double) {
        let (data, resp) = try await session.data(for: request("/credits/", baseURL: baseURL, apiKey: apiKey))
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let c = parseCredits(data) else {
            if case .failure(let f) = parse(status: status, body: data, model: "") { throw f }
            throw Failure.badResponse
        }
        return c
    }

    /// 실제 호출(폴백 포함). 돌려준 모델은 실제로 쓴 모델. `fallback`이 nil이면 폴백 없이 한 번만(연결 테스트용).
    public static func recognize(png: Data, baseURL: String, apiKey: String, model: String, fallback: String?,
                                 session: URLSession = .shared) async -> (Result<String, Failure>, String) {
        var tried: [String] = []
        for m in [model] + (fallback.map { [$0] } ?? []) where !tried.contains(m) {
            tried.append(m)
            let result: Result<String, Failure>
            do {
                let req = try makeRequest(baseURL: baseURL, apiKey: apiKey, model: m, png: png)
                let (data, resp) = try await session.data(for: req)
                result = parse(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, body: data, model: m)
            } catch let f as Failure {
                return (.failure(f), m)
            } catch {
                return (.failure(.http(0, error.localizedDescription)), m)
            }
            if case .failure(let f) = result, f.shouldFallback { continue }
            return (result, m)
        }
        return (.failure(.modelNotFound(model)), model)
    }
}
