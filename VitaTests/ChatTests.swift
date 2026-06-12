import XCTest
import SwiftData
@testable import Vita

final class ChatTests: XCTestCase {

    // MARK: - Chat request shape (Opus 4.8 constraints)

    func testChatBodyShape() {
        let body = AnthropicClient.makeBody(
            maxTokens: 2048,
            system: [.init(text: "catalog", cache: true), .init(text: "grounding", cache: false)],
            messages: [["role": "user", "content": "hi"]],
            tools: [ClaudeSchemas.suggestStackActionTool],
            toolChoice: ["type": "auto"],
            stream: true, adaptiveThinking: true, effort: "high")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual((body["output_config"] as? [String: Any])?["effort"] as? String, "high")
        XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, "adaptive")
        XCTAssertEqual((body["tool_choice"] as? [String: Any])?["type"] as? String, "auto")
        XCTAssertNil(body["temperature"]); XCTAssertNil(body["top_p"]); XCTAssertNil(body["top_k"])
    }

    // MARK: - SSE parsing

    private func feed(_ payloads: [String]) -> [ChatStreamEvent] {
        var parser = SSEChatParser()
        return payloads.flatMap { (try? parser.consume($0)) ?? [] }
    }

    func testSSEErrorEventThrows() {
        // A mid-stream error means a truncated reply: the stream must FAIL (the UI
        // keeps the partial text + offers retry), never finish as if complete.
        var parser = SSEChatParser()
        XCTAssertThrowsError(try parser.consume(
            #"{"type":"error","error":{"type":"overloaded_error","message":"busy"}}"#))
    }

    func testSSETextThenFinish() {
        let events = feed([
            #"{"type":"message_start"}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"BPC"}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"-157"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"message_stop"}"#,
        ])
        XCTAssertEqual(events, [.text("BPC"), .text("-157"), .finished])
    }

    func testSSEThinkingDeltaIgnored() {
        let events = feed([
            #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hmm"}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hi"}}"#,
        ])
        XCTAssertEqual(events, [.text("hi")])
    }

    func testSSETwoToolBlocksTwoSuggestions() {
        let events = feed([
            #"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","name":"suggest_stack_action","input":{}}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"action\":\"add\",\"compound_slug\":\"melanotan-1\",\"reason\":\"x\"}"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","name":"suggest_stack_action","input":{}}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"action\":\"add\",\"compound_slug\":\"melanotan-2\",\"reason\":\"y\"}"}}"#,
            #"{"type":"content_block_stop","index":1}"#,
            #"{"type":"message_stop"}"#,
        ])
        XCTAssertEqual(events, [
            .suggestion(action: "add", slug: "melanotan-1", reason: "x", dose: nil),
            .suggestion(action: "add", slug: "melanotan-2", reason: "y", dose: nil),
            .finished,
        ])
    }

    // MARK: - Em-dash sanitizer

    func testSanitizeStripsDashes() {
        XCTAssertEqual(ChatText.sanitize("MT-1 is cleaner — fewer effects"), "MT-1 is cleaner, fewer effects")
        XCTAssertEqual(ChatText.sanitize("a—b"), "a, b")
        XCTAssertEqual(ChatText.sanitize("range 0.5 – 1 mg"), "range 0.5, 1 mg")
        XCTAssertFalse(ChatText.sanitize("no dashes here").contains("—"))
        XCTAssertEqual(ChatText.sanitize("hyphen-word stays"), "hyphen-word stays")
    }

    func testSSEToolUseAccumulatesToSuggestion() {
        let events = feed([
            #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","name":"suggest_stack_action","input":{}}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"action\":\"add\","}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"compound_slug\":\"tb-500\",\"reason\":\"recovery\"}"}}"#,
            #"{"type":"content_block_stop","index":1}"#,
            #"{"type":"message_stop"}"#,
        ])
        XCTAssertEqual(events, [.suggestion(action: "add", slug: "tb-500", reason: "recovery", dose: nil), .finished])
    }

    func testSSEIgnoresDoneAndJunk() {
        XCTAssertTrue(feed(["[DONE]", "", "not json", #"{"type":"ping"}"#]).isEmpty)
    }

    func testSSESuggestionCarriesSuggestedDose() {
        let events = feed([
            #"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","name":"suggest_stack_action","input":{}}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"action\":\"add\",\"compound_slug\":\"bpc-157\",\"reason\":\"r\",\"suggested_dose\":250}"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
        ])
        XCTAssertEqual(events, [.suggestion(action: "add", slug: "bpc-157", reason: "r", dose: 250)])
    }

    // MARK: - Suggestion validation

    func testSuggestionValidation() {
        let catalog: Set<String> = ["bpc-157", "tb-500", "semaglutide"]
        let stack: Set<String> = ["bpc-157"]
        // add a new catalog compound → valid
        XCTAssertTrue(ChatSuggestion.isValid(action: "add", slug: "tb-500", catalogSlugs: catalog, stackSlugs: stack))
        // add one already in the stack → invalid
        XCTAssertFalse(ChatSuggestion.isValid(action: "add", slug: "bpc-157", catalogSlugs: catalog, stackSlugs: stack))
        // adjust one in the stack → valid
        XCTAssertTrue(ChatSuggestion.isValid(action: "adjust", slug: "bpc-157", catalogSlugs: catalog, stackSlugs: stack))
        // adjust one not in the stack → invalid
        XCTAssertFalse(ChatSuggestion.isValid(action: "adjust", slug: "tb-500", catalogSlugs: catalog, stackSlugs: stack))
        // unknown slug → invalid
        XCTAssertFalse(ChatSuggestion.isValid(action: "add", slug: "nope", catalogSlugs: catalog, stackSlugs: stack))
        // unknown action → invalid
        XCTAssertFalse(ChatSuggestion.isValid(action: "remove", slug: "bpc-157", catalogSlugs: catalog, stackSlugs: stack))
    }

    // MARK: - Rolling window

    func testWindowedMessagesTrimsLeadingAssistant() {
        let turns = [
            ChatTurn(role: "assistant", text: "leftover"),
            ChatTurn(role: "user", text: "q1"),
            ChatTurn(role: "assistant", text: "a1"),
            ChatTurn(role: "user", text: "q2"),
        ]
        let msgs = ClaudeService.windowedMessages(turns)
        XCTAssertEqual(msgs.first?["role"], "user")          // never starts with assistant
        XCTAssertEqual(msgs.count, 3)
        XCTAssertEqual(msgs.last?["content"], "q2")
    }

    // MARK: - ChatMessage persistence

    @MainActor
    func testChatMessageRoundTrips() throws {
        let container = VitaContainer.make(inMemory: true)
        let ctx = container.mainContext
        let m = ChatMessage()
        m.roleRaw = "assistant"; m.text = "hello"
        m.suggestionSlugs = ["melanotan-1", "melanotan-2"]
        m.suggestionActions = ["add", "add"]
        ctx.insert(m)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<ChatMessage>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.isUser, false)
        XCTAssertEqual(fetched.first?.suggestionSlugs, ["melanotan-1", "melanotan-2"])
    }
}
