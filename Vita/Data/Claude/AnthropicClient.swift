import Foundation

/// The only network surface to Claude. Raw HTTPS over URLSession (Swift has no
/// official Anthropic SDK). Enforces Opus 4.8 request constraints: never sends
/// temperature/top_p/top_k or budget_tokens (all → 400). Retries 429/500/529 +
/// transient transport errors only; never retries 400.
actor AnthropicClient {
    enum Const {
        static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
        static let version = "2023-06-01"
        static let model = "claude-opus-4-8"
    }

    enum AnthropicError: Error, Equatable {
        case noKey
        case http(Int, String)       // non-retryable status (e.g. 400)
        case overloaded(Int)         // 429/500/529 after retries exhausted
        case transport
        case decode
        case noToolUse               // response had no emit_protocol block
    }

    /// One system block; the catalog/safety prefix sets `cache = true`.
    struct SystemBlock: Sendable, Equatable {
        let text: String
        let cache: Bool
    }

    private nonisolated let session: URLSession
    private nonisolated let keyProvider: @Sendable () -> String?
    private let maxRetries = 2

    /// Longer timeouts than `URLSession.shared` (whose 60s `timeoutIntervalForRequest`
    /// is too short): a multi-page lab vision read can take 50-60s and would otherwise
    /// time out on a slower network.
    nonisolated static let longSession: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 180
        c.timeoutIntervalForResource = 600
        return URLSession(configuration: c)
    }()

    init(session: URLSession = AnthropicClient.longSession,
         keyProvider: @escaping @Sendable () -> String? = { Keychain.apiKey }) {
        self.session = session
        self.keyProvider = keyProvider
    }

    // MARK: - Pure builders (testable without network)

    /// Builds the JSON request body. Deliberately omits temperature/top_p/top_k
    /// and (for forced tool-use) thinking — both incompatible / 400 on Opus 4.8.
    static func makeBody(model: String = Const.model,
                         maxTokens: Int,
                         system: [SystemBlock],
                         messages: [[String: String]],
                         tools: [[String: Any]]? = nil,
                         toolChoice: [String: Any]? = nil,
                         stream: Bool = false,
                         adaptiveThinking: Bool = false,
                         effort: String? = nil) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system.map { block -> [String: Any] in
                var b: [String: Any] = ["type": "text", "text": block.text]
                if block.cache { b["cache_control"] = ["type": "ephemeral"] }
                return b
            },
            "messages": messages.map { ["role": $0["role"] ?? "user", "content": $0["content"] ?? ""] },
        ]
        if let tools { body["tools"] = tools }
        if let toolChoice { body["tool_choice"] = toolChoice }
        if stream { body["stream"] = true }
        if adaptiveThinking { body["thinking"] = ["type": "adaptive"] }
        if let effort { body["output_config"] = ["effort": effort] }
        return body
    }

    static func makeRequest(body: [String: Any], apiKey: String) throws -> URLRequest {
        var req = URLRequest(url: Const.endpoint)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(Const.version, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// Vision request body: the user message content is an ARRAY of blocks (text +
    /// image/document) rather than a String. Kept separate from `makeBody` (string
    /// content) so that builder + its tests stay byte-stable. Forced tool-use; no
    /// sampling params / no thinking (Opus-4.8-legal, like `makeBody`).
    static func makeVisionBody(model: String = Const.model,
                               maxTokens: Int,
                               system: [SystemBlock],
                               userBlocks: [[String: Any]],
                               tools: [[String: Any]],
                               toolName: String) -> [String: Any] {
        [
            "model": model,
            "max_tokens": maxTokens,
            "system": system.map { block -> [String: Any] in
                var b: [String: Any] = ["type": "text", "text": block.text]
                if block.cache { b["cache_control"] = ["type": "ephemeral"] }
                return b
            },
            "messages": [["role": "user", "content": userBlocks]],
            "tools": tools,
            "tool_choice": ["type": "tool", "name": toolName],
        ]
    }

    /// `{type:image, source:{type:base64, media_type, data}}` — GA on 2023-06-01.
    static func imageBlock(base64 data: String, mediaType: String) -> [String: Any] {
        ["type": "image", "source": ["type": "base64", "media_type": mediaType, "data": data]]
    }
    /// `{type:document, source:{type:base64, media_type:application/pdf, data}}` — GA on 2023-06-01.
    static func documentBlock(base64 data: String, mediaType: String = "application/pdf") -> [String: Any] {
        ["type": "document", "source": ["type": "base64", "media_type": mediaType, "data": data]]
    }

    // MARK: - Send (non-streaming; used by protocol-gen)

    struct Result: Sendable {
        let toolInput: Data?         // JSON of the emit_protocol input block
        let cacheReadTokens: Int
    }

    /// Sends a non-streaming request and returns the first tool_use input as JSON.
    func send(maxTokens: Int,
              system: [SystemBlock],
              userText: String,
              tool: @Sendable () -> [String: Any],
              toolName: String) async throws -> Result {
        guard let key = keyProvider(), !key.isEmpty else { throw AnthropicError.noKey }
        let body = Self.makeBody(
            maxTokens: maxTokens,
            system: system,
            messages: [["role": "user", "content": userText]],
            tools: [tool()],
            toolChoice: ["type": "tool", "name": toolName])
        let request = try Self.makeRequest(body: body, apiKey: key)

        let (data, response) = try await sendWithRetry(request)
        guard let http = response as? HTTPURLResponse else { throw AnthropicError.transport }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            if [429, 500, 529].contains(http.statusCode) { throw AnthropicError.overloaded(http.statusCode) }
            throw AnthropicError.http(http.statusCode, msg)
        }
        return try Self.parse(data: data, toolName: toolName)
    }

    /// Non-streaming vision send (lab scan): text + one-or-more image/document blocks
    /// + forced tool. Reuses makeRequest/sendWithRetry/parse verbatim. Attachments are
    /// base64 (Sendable) so the heavy UIImage/encode work stays off this actor. A PDF
    /// attachment becomes a `document` block; everything else an `image` block (so a
    /// rasterized multi-page PDF rides the proven image path).
    func sendVision(maxTokens: Int,
                    system: [SystemBlock],
                    userText: String,
                    attachments: [(base64: String, mediaType: String)],
                    tool: @Sendable () -> [String: Any],
                    toolName: String) async throws -> Result {
        guard let key = keyProvider(), !key.isEmpty else { throw AnthropicError.noKey }
        let media: [[String: Any]] = attachments.map { a in
            a.mediaType == "application/pdf"
                ? Self.documentBlock(base64: a.base64)
                : Self.imageBlock(base64: a.base64, mediaType: a.mediaType)
        }
        let userBlocks: [[String: Any]] = [["type": "text", "text": userText]] + media
        let body = Self.makeVisionBody(maxTokens: maxTokens, system: system,
                                       userBlocks: userBlocks, tools: [tool()], toolName: toolName)
        let request = try Self.makeRequest(body: body, apiKey: key)
        #if DEBUG
        if ProcessInfo.processInfo.environment["VITA_LAB_SELFTEST"] == "1" {
            // Write the FULL request body (with base64) so it can be replayed verbatim via curl.
            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
               let j = try? JSONSerialization.data(withJSONObject: body) {
                try? j.write(to: docs.appendingPathComponent("lastreq.json"))
            }
            var dbg = body
            if var msgs = dbg["messages"] as? [[String: Any]], var content = msgs[0]["content"] as? [[String: Any]] {
                for i in content.indices {
                    if var src = content[i]["source"] as? [String: Any], let d = src["data"] as? String {
                        src["data"] = "<base64 \(d.count) chars>"; content[i]["source"] = src
                    }
                }
                msgs[0]["content"] = content; dbg["messages"] = msgs
            }
            if let j = try? JSONSerialization.data(withJSONObject: dbg, options: [.sortedKeys]),
               let s = String(data: j, encoding: .utf8) {
                NSLog("vita-vision-req: %@", s)
            }
        }
        #endif
        let (data, response) = try await sendWithRetry(request)
        guard let http = response as? HTTPURLResponse else { throw AnthropicError.transport }
        #if DEBUG
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            NSLog("vita-vision-resp: sent_max_tokens=%d status=%d stop=%@ out=%@",
                  maxTokens, http.statusCode, String(describing: obj["stop_reason"]),
                  String(describing: (obj["usage"] as? [String: Any])?["output_tokens"]))
        }
        #endif
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            if [429, 500, 529].contains(http.statusCode) { throw AnthropicError.overloaded(http.statusCode) }
            throw AnthropicError.http(http.statusCode, msg)
        }
        return try Self.parse(data: data, toolName: toolName)
    }

    /// Minimal liveness check for Settings "Test connection": one 1-token message,
    /// no tools. true on 2xx; false on no-key / non-2xx / transport. Never throws.
    func ping() async -> Bool {
        guard let key = keyProvider(), !key.isEmpty else { return false }
        let body = Self.makeBody(
            maxTokens: 1,
            system: [SystemBlock(text: "You are a connection test. Reply with ok.", cache: false)],
            messages: [["role": "user", "content": "hi"]])
        do {
            let request = try Self.makeRequest(body: body, apiKey: key)
            let (_, response) = try await sendWithRetry(request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch { return false }
    }

    private func sendWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse,
                   [429, 500, 529].contains(http.statusCode), attempt < maxRetries {
                    try await backoff(after: http, attempt: attempt)
                    attempt += 1
                    continue
                }
                return (data, response)
            } catch {
                // Transient transport errors are retryable; 400-class never reaches here.
                if attempt < maxRetries, (error as? URLError) != nil {
                    try await backoff(after: nil, attempt: attempt)
                    attempt += 1
                    continue
                }
                throw AnthropicError.transport
            }
        }
    }

    private func backoff(after http: HTTPURLResponse?, attempt: Int) async throws {
        let retryAfter = http?.value(forHTTPHeaderField: "retry-after").flatMap(Double.init)
        let base = pow(2.0, Double(attempt))            // 1s, 2s
        let jitter = Double(attempt + 1) * 0.25         // deterministic-ish, no RNG
        let delay = retryAfter ?? (base + jitter)
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    // MARK: - Parse

    static func parse(data: Data, toolName: String) throws -> Result {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnthropicError.decode
        }
        let usage = root["usage"] as? [String: Any]
        let cacheRead = (usage?["cache_read_input_tokens"] as? Int) ?? 0
        let content = root["content"] as? [[String: Any]] ?? []
        let block = content.first { ($0["type"] as? String) == "tool_use" && ($0["name"] as? String) == toolName }
        guard let input = block?["input"] else { throw AnthropicError.noToolUse }
        let inputData = try JSONSerialization.data(withJSONObject: input)
        return Result(toolInput: inputData, cacheReadTokens: cacheRead)
    }

    // MARK: - Stream (chat; SSE via URLSession.bytes)

    /// Streams a chat reply. Adaptive thinking on (display omitted), effort high,
    /// one optional `suggest_stack_action` tool offered (tool_choice auto). Emits
    /// text deltas, an optional action suggestion, then `.finished`. A mid-stream
    /// drop surfaces as a thrown error the UI turns into "tap to retry".
    nonisolated func streamChat(maxTokens: Int,
                                system: [SystemBlock],
                                messages: [[String: String]],
                                tool: @Sendable () -> [String: Any]) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let session = self.session
        let key = keyProvider()
        // Build the URLRequest (Sendable) here so the non-Sendable [String:Any]
        // body never crosses into the streaming Task.
        let request: URLRequest? = {
            guard let key, !key.isEmpty else { return nil }
            let body = Self.makeBody(
                maxTokens: maxTokens, system: system, messages: messages,
                tools: [tool()], toolChoice: ["type": "auto"],
                stream: true, adaptiveThinking: true, effort: "high")
            return try? Self.makeRequest(body: body, apiKey: key)
        }()

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let request else { throw AnthropicError.noKey }
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw AnthropicError.transport }
                    guard (200...299).contains(http.statusCode) else {
                        throw AnthropicError.http(http.statusCode, "")
                    }
                    var parser = SSEChatParser()
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        for event in parser.consume(String(payload)) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Events emitted while streaming a chat reply.
enum ChatStreamEvent: Sendable, Equatable {
    case text(String)
    case suggestion(action: String, slug: String, reason: String)
    case finished
}

/// Pure, stateful reducer for Anthropic SSE `data:` payloads → ChatStreamEvents.
/// Extracted so the streaming logic (incl. tool-input accumulation) is unit-testable
/// without a live URLSession. Feed each `data:` JSON string via `consume`.
struct SSEChatParser {
    private var inToolBlock = false
    private var toolJSON = ""

    mutating func consume(_ payload: String) -> [ChatStreamEvent] {
        guard !payload.isEmpty, payload != "[DONE]",
              let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return [] }
        switch type {
        case "content_block_start":
            if let cb = obj["content_block"] as? [String: Any],
               (cb["type"] as? String) == "tool_use" {
                inToolBlock = true; toolJSON = ""
            }
            return []
        case "content_block_delta":
            guard let delta = obj["delta"] as? [String: Any] else { return [] }
            switch delta["type"] as? String {
            case "text_delta":
                if let t = delta["text"] as? String { return [.text(t)] }
            case "input_json_delta":
                if let pj = delta["partial_json"] as? String { toolJSON += pj }
            default:
                break   // thinking_delta omitted
            }
            return []
        case "content_block_stop":
            guard inToolBlock else { return [] }
            inToolBlock = false
            if let d = toolJSON.data(using: .utf8),
               let input = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let action = input["action"] as? String,
               let slug = input["compound_slug"] as? String {
                return [.suggestion(action: action, slug: slug,
                                    reason: (input["reason"] as? String) ?? "")]
            }
            return []
        case "message_stop":
            return [.finished]
        default:
            return []
        }
    }
}
