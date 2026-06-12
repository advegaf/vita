import XCTest
@testable import Vita

/// Guards the Opus 4.8 request constraints: no sampling params, no thinking on
/// forced tool-use, correct headers, and the forced tool_choice shape.
final class AnthropicRequestTests: XCTestCase {

    private func protocolGenBody() -> [String: Any] {
        AnthropicClient.makeBody(
            maxTokens: 2048,
            system: [.init(text: "catalog", cache: true), .init(text: "grounding", cache: false)],
            messages: [["role": "user", "content": "go"]],
            tools: [ClaudeSchemas.emitProtocolTool],
            toolChoice: ["type": "tool", "name": ClaudeSchemas.toolName],
            stream: false,
            adaptiveThinking: false)
    }

    func testModelAndMaxTokens() {
        let body = protocolGenBody()
        XCTAssertEqual(body["model"] as? String, "claude-opus-4-8")
        XCTAssertEqual(body["max_tokens"] as? Int, 2048)
    }

    func testNoSamplingParams() {
        let body = protocolGenBody()
        XCTAssertNil(body["temperature"])
        XCTAssertNil(body["top_p"])
        XCTAssertNil(body["top_k"])
    }

    func testNoThinkingOnForcedToolUse() {
        // Forced tool-use disables thinking; the protocol-gen body must omit it.
        XCTAssertNil(protocolGenBody()["thinking"])
    }

    func testAdaptiveThinkingOptIn() {
        let body = AnthropicClient.makeBody(
            maxTokens: 1024, system: [], messages: [["role": "user", "content": "hi"]],
            adaptiveThinking: true)
        let thinking = body["thinking"] as? [String: Any]
        XCTAssertEqual(thinking?["type"] as? String, "adaptive")
    }

    func testForcedToolChoice() {
        let choice = protocolGenBody()["tool_choice"] as? [String: Any]
        XCTAssertEqual(choice?["type"] as? String, "tool")
        XCTAssertEqual(choice?["name"] as? String, "emit_protocol")
    }

    func testSystemBlocksCarryCacheControlOnlyWhereMarked() {
        let blocks = protocolGenBody()["system"] as? [[String: Any]]
        XCTAssertEqual(blocks?.count, 2)
        XCTAssertNotNil(blocks?[0]["cache_control"])   // catalog block cached
        XCTAssertNil(blocks?[1]["cache_control"])      // grounding block not cached
    }

    func testRequestHeaders() throws {
        let req = try AnthropicClient.makeRequest(body: protocolGenBody(), apiKey: "sk-test")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(req.value(forHTTPHeaderField: "content-type"), "application/json")
        XCTAssertEqual(req.url, AnthropicClient.Const.endpoint)
        XCTAssertNotNil(req.httpBody)
    }

    func testParseExtractsToolInput() throws {
        let response = """
        {"content":[{"type":"text","text":"sure"},
        {"type":"tool_use","name":"emit_protocol","input":{"disclaimer":"x","items":[]}}],
        "usage":{"cache_read_input_tokens":42}}
        """.data(using: .utf8)!
        let result = try AnthropicClient.parse(data: response, toolName: "emit_protocol")
        XCTAssertEqual(result.cacheReadTokens, 42)
        let dto = try JSONDecoder().decode(ProtocolDTO.self, from: XCTUnwrap(result.toolInput))
        XCTAssertEqual(dto.disclaimer, "x")
    }

    func testParseThrowsWhenNoToolUse() {
        let response = #"{"content":[{"type":"text","text":"no tool"}]}"#.data(using: .utf8)!
        XCTAssertThrowsError(try AnthropicClient.parse(data: response, toolName: "emit_protocol"))
    }

    func testCancellationIsNeverRetried() {
        // A skipped onboarding refine cancels its request mid-flight; the retry
        // loop must classify that as cancellation, not a retryable transport blip.
        XCTAssertTrue(AnthropicClient.isCancellation(CancellationError()))
        XCTAssertTrue(AnthropicClient.isCancellation(URLError(.cancelled)))
        XCTAssertFalse(AnthropicClient.isCancellation(URLError(.timedOut)))
        XCTAssertFalse(AnthropicClient.isCancellation(URLError(.notConnectedToInternet)))
    }
}
