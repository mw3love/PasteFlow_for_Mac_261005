import XCTest
@testable import PasteFlowCore

final class GatewayOCRTests: XCTestCase {
    func testNormalizeBaseURL() {
        XCTAssertEqual(GatewayOCR.normalizeBaseURL("https://h/v1/gateway/chat/completions"), "https://h/v1/gateway")
        XCTAssertEqual(GatewayOCR.normalizeBaseURL(" https://h/v1/gateway/ "), "https://h/v1/gateway")
        XCTAssertEqual(GatewayOCR.normalizeBaseURL("https://h/v1/gateway/models"), "https://h/v1/gateway")
    }

    func testRequestShape() throws {
        let req = try GatewayOCR.makeRequest(baseURL: "https://h/v1/gateway/", apiKey: "k", model: "m", png: Data([1, 2]))
        XCTAssertEqual(req.url?.absoluteString, "https://h/v1/gateway/chat/completions")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        XCTAssertTrue(req.value(forHTTPHeaderField: "User-Agent")?.contains("Mozilla") ?? false)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "m")
        XCTAssertEqual(body["max_tokens"] as? Int, 16384)
        let content = try XCTUnwrap(((body["messages"] as? [[String: Any]])?.first?["content"]) as? [[String: Any]])
        XCTAssertEqual((content[0]["image_url"] as? [String: String])?["url"], "data:image/png;base64,AQI=")
        XCTAssertEqual(content[1]["type"] as? String, "text")
    }

    func testMissingKeyFailsBeforeNetwork() {
        XCTAssertThrowsError(try GatewayOCR.makeRequest(baseURL: "https://h", apiKey: "", model: "m", png: Data())) {
            XCTAssertEqual($0 as? GatewayOCR.Failure, .missingKey)
        }
    }

    func testParseSuccessStripsFence() {
        let ok = #"{"choices":[{"message":{"content":"```text\n안녕하세요\n둘째 줄\n```"}}]}"#
        XCTAssertEqual(try GatewayOCR.parse(status: 200, body: Data(ok.utf8), model: "m").get(), "안녕하세요\n둘째 줄")
        let empty = #"{"choices":[{"message":{"content":"  "}}]}"#
        XCTAssertEqual(GatewayOCR.parse(status: 200, body: Data(empty.utf8), model: "m"), .failure(.emptyResult))
    }

    func testParseErrors() {
        func p(_ s: Int, _ b: String) -> Result<String, GatewayOCR.Failure> { GatewayOCR.parse(status: s, body: Data(b.utf8), model: "m") }
        XCTAssertEqual(p(403, "error code: 1010"), .failure(.cloudflareBlocked))
        XCTAssertEqual(p(401, "bad key"), .failure(.unauthorized))
        XCTAssertEqual(p(404, "Error code: 404 model not found"), .failure(.modelNotFound("m")))
        XCTAssertEqual(p(400, "this model does not support image input"), .failure(.imageNotSupported("m")))
        XCTAssertEqual(p(429, "rate"), .failure(.quotaOrBusy(429)))
        XCTAssertTrue(GatewayOCR.Failure.modelNotFound("m").shouldFallback)
        XCTAssertFalse(GatewayOCR.Failure.unauthorized.shouldFallback)
    }

    func testPickFallbackChoosesNewestPlainFlash() {
        let list = ["gemini-2.5-flash-image", "gemini-3.1-flash-lite", "gemini-3.5-flash", "gemini-3.5-flash-lite",
                    "gemini-3.10-flash", "gemini-3.8-flash", "gemini-3.8-live", "gemini-3.1-flash-tts-preview", "gpt-5.4-mini"]
        XCTAssertEqual(GatewayOCR.pickFallback(from: list), "gemini-3.10-flash")       // 3.10 > 3.8 (숫자 비교)
        XCTAssertEqual(GatewayOCR.pickFallback(from: list, excluding: "gemini-3.10-flash"), "gemini-3.8-flash")
        XCTAssertNil(GatewayOCR.pickFallback(from: ["gemini-3.5-flash-lite", "claude-haiku-4-5"]))
    }

    func testParseModelsAndCredits() {
        let models = #"{"data":[{"id":"b"},{"id":"a"},{"id":"a"}]}"#
        XCTAssertEqual(GatewayOCR.parseModels(Data(models.utf8)), ["a", "b"])
        XCTAssertNil(GatewayOCR.parseModels(Data("{}".utf8)))
        let credits = #"{"total":{"quota":10000.0,"used":243.52,"remaining":9756.48}}"#
        let c = GatewayOCR.parseCredits(Data(credits.utf8))
        XCTAssertEqual(c?.remaining, 9756.48)
        XCTAssertEqual(c?.quota, 10000)
    }

    func testDefaultsPointAtCurrentModels() {
        XCTAssertEqual(GatewayOCR.defaultModel, "gemini-3.5-flash-lite")
        XCTAssertEqual(GatewayOCR.staticFallback, "gemini-3.8-flash")
    }
}
