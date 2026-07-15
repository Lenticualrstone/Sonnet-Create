import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - SSE 공통

/// SSE 프레임(JSON) 하나를 스트림 이벤트로 바꾸는 제공자별 파서.
/// 도구 호출은 여러 프레임에 걸쳐 조각으로 오므로 상태를 들고 누적한다.
protocol SSEFrameParser {
    func parse(_ json: [String: Any]) -> [AIStreamEvent]
    /// 스트림이 끝났을 때 남은 누적분을 비운다 (종료 신호를 안 주는 제공자 대비).
    func finish() -> [AIStreamEvent]
}

enum SSEStream {
    /// 파서는 Task 안에서 만들어져 한 스트림에만 쓰이므로 Sendable일 필요가 없다 —
    /// 대신 팩토리를 @Sendable로 받는다.
    static func events(
        request: URLRequest,
        makeParser: @escaping @Sendable () -> any SSEFrameParser
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let parser = makeParser()
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw AIProviderError.make(50, "잘못된 응답")
                    }
                    guard http.statusCode == 200 else {
                        // 오류 본문을 모아 사유를 보여준다
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                            if body.count > 600 { break }
                        }
                        throw AIProviderError.make(http.statusCode, "API 오류 (\(http.statusCode)): \(body.prefix(300))")
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard payload != "[DONE]", !payload.isEmpty else { continue }
                        guard
                            let data = payload.data(using: .utf8),
                            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        for event in parser.parse(json) { continuation.yield(event) }
                        if Task.isCancelled { break }
                    }
                    for event in parser.finish() { continuation.yield(event) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// 비스트리밍 POST + JSON 응답 공통 헬퍼.
enum JSONRequest {
    static func post(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let message = String(data: data, encoding: .utf8) ?? "unknown"
            throw AIProviderError.make(code, "API 오류 (\(code)): \(message.prefix(300))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.make(51, "JSON 파싱 실패")
        }
        return json
    }
}

/// 스트림 오류를 그대로 전달하는 실패 스트림 (요청 구성 단계 실패용).
func failedStream(_ error: Error) -> AsyncThrowingStream<AIStreamEvent, Error> {
    AsyncThrowingStream { $0.finish(throwing: error) }
}

// MARK: - Anthropic (Claude)

/// Anthropic Messages API 어댑터 — SSE 스트리밍 + 도구 호출 지원.
public struct AnthropicProvider: AIProvider {
    public let kind: AIProviderKind = .anthropic
    public let supportsTools = true

    /// 공식 엔드포인트. 프록시/게이트웨이를 쓸 때만 다른 값을 넣는다.
    public static let defaultBaseURL = URL(string: "https://api.anthropic.com")!

    let apiKey: String
    let model: String
    let baseURL: URL

    public init(
        apiKey: String,
        model: String = AIProviderKind.anthropic.defaultModel,
        baseURL: URL = AnthropicProvider.defaultBaseURL
    ) {
        self.apiKey = apiKey
        self.model = model.isEmpty ? AIProviderKind.anthropic.defaultModel : model
        self.baseURL = baseURL
    }

    public func availability() async -> AIAvailability {
        apiKey.isEmpty ? .unavailable(reason: "API 키가 설정되지 않았습니다") : .available
    }

    /// 대화 히스토리 → Anthropic messages[]. 도구 결과는 user 턴의 tool_result 블록으로 간다.
    private func encode(_ history: [AIChatMessage]) -> [[String: Any]] {
        var output: [[String: Any]] = []
        for message in history {
            switch message.role {
            case .user:
                guard !message.text.isEmpty else { continue }
                output.append(["role": "user", "content": message.text])
            case .assistant:
                var content: [[String: Any]] = []
                if !message.text.isEmpty {
                    content.append(["type": "text", "text": message.text])
                }
                for call in message.toolCalls {
                    content.append([
                        "type": "tool_use", "id": call.id, "name": call.name,
                        "input": call.arguments.dictionary,
                    ])
                }
                guard !content.isEmpty else { continue }
                output.append(["role": "assistant", "content": content])
            case .tool:
                let blocks: [[String: Any]] = message.toolResults.map { result in
                    var block: [String: Any] = [
                        "type": "tool_result", "tool_use_id": result.callID, "content": result.content,
                    ]
                    if result.isError { block["is_error"] = true }
                    return block
                }
                guard !blocks.isEmpty else { continue }
                output.append(["role": "user", "content": blocks])
            }
        }
        return output
    }

    private func makeRequest(
        system: String, messages: [[String: Any]], tools: [AITool],
        stream: Bool, maxTokens: Int
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "v1/messages"))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages,
        ]
        if !tools.isEmpty {
            body["tools"] = tools.map { tool in
                ["name": tool.name, "description": tool.description, "input_schema": tool.parameterSchema]
            }
        }
        if stream { body["stream"] = true }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public func generate(system: String, prompt: String) async throws -> String {
        let request = try makeRequest(
            system: system,
            messages: [["role": "user", "content": prompt]],
            tools: [], stream: false, maxTokens: 8192
        )
        let json = try await JSONRequest.post(request)
        guard let contentItems = json["content"] as? [[String: Any]] else { return "" }
        return contentItems.compactMap { $0["text"] as? String }.joined()
    }

    public func chatStream(
        history: [AIChatMessage], system: String, tools: [AITool]
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        do {
            let request = try makeRequest(
                system: system, messages: encode(history), tools: tools,
                stream: true, maxTokens: 4096
            )
            return SSEStream.events(request: request) { AnthropicFrameParser() }
        } catch {
            return failedStream(error)
        }
    }
}

/// Anthropic 스트림: 텍스트는 text_delta, 도구 인자는 input_json_delta로 조각조각 온다.
/// content_block_start(tool_use)에서 시작해 content_block_stop에서 완성된다.
private final class AnthropicFrameParser: SSEFrameParser {
    private var toolBlocks: [Int: (id: String, name: String, json: String)] = [:]

    func parse(_ json: [String: Any]) -> [AIStreamEvent] {
        switch json["type"] as? String {
        case "content_block_start":
            guard let index = json["index"] as? Int,
                  let block = json["content_block"] as? [String: Any],
                  block["type"] as? String == "tool_use",
                  let id = block["id"] as? String,
                  let name = block["name"] as? String
            else { return [] }
            toolBlocks[index] = (id: id, name: name, json: "")
            return []

        case "content_block_delta":
            guard let index = json["index"] as? Int,
                  let delta = json["delta"] as? [String: Any]
            else { return [] }
            if let text = delta["text"] as? String, !text.isEmpty {
                return [.textDelta(text)]
            }
            if let partial = delta["partial_json"] as? String, var accumulated = toolBlocks[index] {
                accumulated.json += partial
                toolBlocks[index] = accumulated
            }
            return []

        case "content_block_stop":
            guard let index = json["index"] as? Int,
                  let block = toolBlocks.removeValue(forKey: index)
            else { return [] }
            return [.toolCall(AIToolCall(id: block.id, name: block.name, argumentsJSON: block.json))]

        default:
            return []
        }
    }

    func finish() -> [AIStreamEvent] {
        let leftovers = toolBlocks.sorted { $0.key < $1.key }.map { entry in
            AIStreamEvent.toolCall(AIToolCall(
                id: entry.value.id, name: entry.value.name, argumentsJSON: entry.value.json
            ))
        }
        toolBlocks = [:]
        return leftovers
    }
}

// MARK: - OpenAI 호환 (ChatGPT / Grok)

/// OpenAI Chat Completions 호환 어댑터 — OpenAI(ChatGPT)와 xAI(Grok)가 공유한다.
public struct OpenAICompatibleProvider: AIProvider {
    public let kind: AIProviderKind
    public let supportsTools = true

    /// 공식 엔드포인트. 프록시/게이트웨이를 쓸 때만 다른 값을 넣는다.
    public static let openAIBaseURL = URL(string: "https://api.openai.com/v1")!
    public static let grokBaseURL = URL(string: "https://api.x.ai/v1")!

    let apiKey: String
    let model: String
    let baseURL: URL

    /// ChatGPT (api.openai.com)
    public static func openAI(
        apiKey: String,
        model: String = AIProviderKind.openai.defaultModel,
        baseURL: URL = OpenAICompatibleProvider.openAIBaseURL
    ) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(
            kind: .openai,
            apiKey: apiKey,
            model: model.isEmpty ? AIProviderKind.openai.defaultModel : model,
            baseURL: baseURL
        )
    }

    /// Grok (api.x.ai)
    public static func grok(
        apiKey: String,
        model: String = AIProviderKind.grok.defaultModel,
        baseURL: URL = OpenAICompatibleProvider.grokBaseURL
    ) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(
            kind: .grok,
            apiKey: apiKey,
            model: model.isEmpty ? AIProviderKind.grok.defaultModel : model,
            baseURL: baseURL
        )
    }

    public func availability() async -> AIAvailability {
        apiKey.isEmpty ? .unavailable(reason: "API 키가 설정되지 않았습니다") : .available
    }

    /// 대화 히스토리 → OpenAI messages[]. 도구 결과는 호출당 별도 role:"tool" 메시지로 쪼갠다.
    private func encode(_ history: [AIChatMessage], system: String) -> [[String: Any]] {
        var output: [[String: Any]] = [["role": "system", "content": system]]
        for message in history {
            switch message.role {
            case .user:
                guard !message.text.isEmpty else { continue }
                output.append(["role": "user", "content": message.text])
            case .assistant:
                var entry: [String: Any] = ["role": "assistant"]
                // 도구만 호출한 턴은 content가 null이어야 한다
                entry["content"] = message.text.isEmpty ? NSNull() : message.text
                if !message.toolCalls.isEmpty {
                    entry["tool_calls"] = message.toolCalls.map { call in
                        [
                            "id": call.id, "type": "function",
                            "function": ["name": call.name, "arguments": call.argumentsJSON],
                        ]
                    }
                }
                output.append(entry)
            case .tool:
                for result in message.toolResults {
                    output.append([
                        "role": "tool", "tool_call_id": result.callID, "content": result.content,
                    ])
                }
            }
        }
        return output
    }

    private func makeRequest(
        system: String, history: [AIChatMessage], tools: [AITool], stream: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": model,
            "messages": encode(history, system: system),
        ]
        if !tools.isEmpty {
            body["tools"] = tools.map { tool in
                [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": tool.parameterSchema,
                    ],
                ]
            }
        }
        if stream { body["stream"] = true }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public func generate(system: String, prompt: String) async throws -> String {
        let request = try makeRequest(
            system: system,
            history: [AIChatMessage(role: .user, text: prompt)],
            tools: [], stream: false
        )
        let json = try await JSONRequest.post(request)
        guard
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any]
        else { return "" }
        return message["content"] as? String ?? ""
    }

    public func chatStream(
        history: [AIChatMessage], system: String, tools: [AITool]
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        do {
            let request = try makeRequest(system: system, history: history, tools: tools, stream: true)
            return SSEStream.events(request: request) { OpenAIFrameParser() }
        } catch {
            return failedStream(error)
        }
    }
}

/// OpenAI 스트림: tool_calls가 index별로 쪼개져 오고, arguments는 JSON 문자열 조각이다.
/// finish_reason이 오면 누적분을 방출한다.
private final class OpenAIFrameParser: SSEFrameParser {
    private var calls: [Int: (id: String, name: String, arguments: String)] = [:]

    func parse(_ json: [String: Any]) -> [AIStreamEvent] {
        guard let choices = json["choices"] as? [[String: Any]], let choice = choices.first else {
            return []
        }
        var events: [AIStreamEvent] = []
        if let delta = choice["delta"] as? [String: Any] {
            if let text = delta["content"] as? String, !text.isEmpty {
                events.append(.textDelta(text))
            }
            for entry in delta["tool_calls"] as? [[String: Any]] ?? [] {
                let index = entry["index"] as? Int ?? 0
                var accumulated = calls[index] ?? (id: "", name: "", arguments: "")
                if let id = entry["id"] as? String, !id.isEmpty { accumulated.id = id }
                if let function = entry["function"] as? [String: Any] {
                    if let name = function["name"] as? String, !name.isEmpty { accumulated.name = name }
                    if let arguments = function["arguments"] as? String { accumulated.arguments += arguments }
                }
                calls[index] = accumulated
            }
        }
        if choice["finish_reason"] as? String != nil {
            events += flush()
        }
        return events
    }

    func finish() -> [AIStreamEvent] { flush() }

    private func flush() -> [AIStreamEvent] {
        let events = calls.sorted { $0.key < $1.key }.compactMap { entry -> AIStreamEvent? in
            guard !entry.value.name.isEmpty else { return nil }
            let id = entry.value.id.isEmpty ? "call_\(UUID().uuidString.prefix(8))" : entry.value.id
            return .toolCall(AIToolCall(
                id: id, name: entry.value.name, argumentsJSON: entry.value.arguments
            ))
        }
        calls = [:]
        return events
    }
}

// MARK: - Google Gemini

/// Google Gemini generateContent API 어댑터 — SSE 스트리밍 + functionCall 지원.
public struct GeminiProvider: AIProvider {
    public let kind: AIProviderKind = .gemini
    public let supportsTools = true

    /// 공식 엔드포인트. 프록시/게이트웨이를 쓸 때만 다른 값을 넣는다.
    public static let defaultBaseURL = URL(string: "https://generativelanguage.googleapis.com")!

    let apiKey: String
    let model: String
    let baseURL: URL

    public init(
        apiKey: String,
        model: String = AIProviderKind.gemini.defaultModel,
        baseURL: URL = GeminiProvider.defaultBaseURL
    ) {
        self.apiKey = apiKey
        self.model = model.isEmpty ? AIProviderKind.gemini.defaultModel : model
        self.baseURL = baseURL
    }

    public func availability() async -> AIAvailability {
        apiKey.isEmpty ? .unavailable(reason: "API 키가 설정되지 않았습니다") : .available
    }

    /// 대화 히스토리 → Gemini contents[]. 도구 결과는 functionResponse 파트로 간다.
    private func encode(_ history: [AIChatMessage]) -> [[String: Any]] {
        var output: [[String: Any]] = []
        for message in history {
            switch message.role {
            case .user:
                guard !message.text.isEmpty else { continue }
                output.append(["role": "user", "parts": [["text": message.text]]])
            case .assistant:
                var parts: [[String: Any]] = []
                if !message.text.isEmpty { parts.append(["text": message.text]) }
                for call in message.toolCalls {
                    parts.append(["functionCall": ["name": call.name, "args": call.arguments.dictionary]])
                }
                guard !parts.isEmpty else { continue }
                output.append(["role": "model", "parts": parts])
            case .tool:
                // Gemini는 호출 ID가 없어 도구 '이름'으로 결과를 매칭한다.
                let parts: [[String: Any]] = message.toolResults.map { result in
                    ["functionResponse": [
                        "name": result.toolName,
                        "response": ["result": result.content],
                    ]]
                }
                guard !parts.isEmpty else { continue }
                output.append(["role": "user", "parts": parts])
            }
        }
        return output
    }

    private func makeRequest(
        system: String, history: [AIChatMessage], tools: [AITool], stream: Bool
    ) throws -> URLRequest {
        // 쿼리는 path와 분리해서 붙인다 — appending(path:)는 '?'를 퍼센트 인코딩한다.
        let method = stream ? "streamGenerateContent" : "generateContent"
        var url = baseURL.appending(path: "v1beta/models/\(model):\(method)")
        if stream {
            url.append(queryItems: [URLQueryItem(name: "alt", value: "sse")])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": encode(history),
        ]
        if !tools.isEmpty {
            body["tools"] = [[
                "function_declarations": tools.map { tool in
                    [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": tool.parameterSchema,
                    ]
                },
            ]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func extractText(_ json: [String: Any]) -> String? {
        guard
            let candidates = json["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else { return nil }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        return text.isEmpty ? nil : text
    }

    public func generate(system: String, prompt: String) async throws -> String {
        let request = try makeRequest(
            system: system,
            history: [AIChatMessage(role: .user, text: prompt)],
            tools: [], stream: false
        )
        let json = try await JSONRequest.post(request)
        return Self.extractText(json) ?? ""
    }

    public func chatStream(
        history: [AIChatMessage], system: String, tools: [AITool]
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        do {
            let request = try makeRequest(system: system, history: history, tools: tools, stream: true)
            return SSEStream.events(request: request) { GeminiFrameParser() }
        } catch {
            return failedStream(error)
        }
    }
}

/// Gemini 스트림: 파트가 통째로 온다 (텍스트도 functionCall도 조각내지 않는다).
private final class GeminiFrameParser: SSEFrameParser {
    func parse(_ json: [String: Any]) -> [AIStreamEvent] {
        guard
            let candidates = json["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else { return [] }

        var events: [AIStreamEvent] = []
        for part in parts {
            if let text = part["text"] as? String, !text.isEmpty {
                events.append(.textDelta(text))
            }
            guard let call = part["functionCall"] as? [String: Any],
                  let name = call["name"] as? String
            else { continue }
            let arguments = call["args"] as? [String: Any] ?? [:]
            let data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
            // Gemini는 호출 ID를 주지 않으므로 로컬에서 만든다 (결과 매칭은 이름으로 한다).
            events.append(.toolCall(AIToolCall(
                id: "gemini_\(name)_\(UUID().uuidString.prefix(6))",
                name: name,
                argumentsJSON: String(data: data, encoding: .utf8) ?? "{}"
            )))
        }
        return events
    }

    func finish() -> [AIStreamEvent] { [] }
}

// MARK: - 온디바이스 (Apple Foundation Model)

/// Apple Intelligence 온디바이스 모델 어댑터. 오프라인·프라이버시 우선.
/// 도구 호출은 지원하지 않는다 — 에이전트 루프가 텍스트 전용 모드로 떨어진다.
public struct AppleOnDeviceProvider: AIProvider {
    public let kind: AIProviderKind = .appleOnDevice

    public init() {}

    public func availability() async -> AIAvailability {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(reason: String(describing: reason))
        }
        #else
        return .unavailable(reason: "FoundationModels 프레임워크 없음")
        #endif
    }

    public func generate(system: String, prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        let session = LanguageModelSession(instructions: system)
        let response = try await session.respond(to: prompt)
        return response.content
        #else
        throw AIProviderError.make(10, "이 시스템에서는 온디바이스 모델을 사용할 수 없습니다.")
        #endif
    }

    public func chatStream(
        history: [AIChatMessage], system: String, tools: [AITool]
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let transcript = history
                        .filter { $0.role != .tool }
                        .map { ($0.role == .user ? "사용자: " : "보조: ") + $0.text }
                        .joined(separator: "\n")
                    let reply = try await generate(system: system, prompt: transcript + "\n보조: ")
                    continuation.yield(.textDelta(reply))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - 오프라인 초안 (내장)

/// 네트워크/모델 없이도 동작하는 결정적 초안 생성기.
/// 실제 창작 대체가 아니라, 파이프라인 검증과 데모용 뼈대 제안을 만든다.
public struct OfflineDraftProvider: AIProvider {
    public let kind: AIProviderKind = .offline

    public init() {}

    public func availability() async -> AIAvailability { .available }

    public func generate(system: String, prompt: String) async throws -> String {
        try await Task.sleep(for: .milliseconds(350))
        return """
        (오프라인 초안 모드) 지금은 내장 초안 생성기만 동작 중이라 실제 생성은 어려워요. \
        설정 > AI 에이전트에서 Claude / ChatGPT / Gemini / Grok API를 연결하면 \
        문서 자동 작성과 실제 대화를 사용할 수 있습니다.
        """
    }

    public func chatStream(
        history: [AIChatMessage], system: String, tools: [AITool]
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                try? await Task.sleep(for: .milliseconds(350))
                let topic = history.last(where: { $0.role == .user })?.text.prefix(48) ?? ""
                continuation.yield(.textDelta("""
                (오프라인 초안 모드) "\(topic)" — 지금은 내장 초안 생성기만 동작 중이라 깊은 답변은 어려워요. \
                설정 > AI 에이전트에서 온디바이스(Apple) 또는 Claude/ChatGPT/Gemini/Grok API 제공자를 연결하면 \
                세계관·캐릭터·플롯에 대해 실제 대화를 나눌 수 있습니다.
                """))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func draftScenario(context: AIScenarioContext, maxBlocks: Int) async throws -> [AISuggestedBlock] {
        // 살짝의 지연으로 실제 생성 감각을 재현
        try await Task.sleep(for: .milliseconds(450))

        let cast = context.castNames
        let lastSpeaker = context.recentBlocks.last(where: { !$0.isInstruction })?.speaker
        // 마지막 화자 다음 순서의 캐릭터가 응답하는 뼈대
        let nextSpeaker: String? = {
            guard !cast.isEmpty else { return nil }
            guard let last = lastSpeaker, let idx = cast.firstIndex(of: last) else { return cast.first }
            return cast[(idx + 1) % cast.count]
        }()

        var blocks: [AISuggestedBlock] = []
        if context.recentBlocks.isEmpty {
            blocks.append(AISuggestedBlock(isInstruction: true, text: "장면이 열린다. 장소와 시간대를 지정하세요."))
            if let first = cast.first {
                blocks.append(AISuggestedBlock(isInstruction: false, speakerName: first, text: "(첫 대사 — 인물의 목표가 드러나는 한 마디)"))
            }
        } else {
            if let speaker = nextSpeaker {
                blocks.append(AISuggestedBlock(isInstruction: false, speakerName: speaker, text: "(직전 대사에 대한 반응 — 갈등을 한 단계 키우기)"))
            }
            blocks.append(AISuggestedBlock(isInstruction: true, text: "짧은 사이. 인물들의 시선이 교차한다."))
            if let speaker = lastSpeaker {
                blocks.append(AISuggestedBlock(isInstruction: false, speakerName: speaker, text: "(반박 또는 후퇴 — 인물의 약점이 스치는 순간)"))
            }
        }
        return Array(blocks.prefix(maxBlocks))
    }
}

// MARK: - 시나리오 자동작성 파이프라인

/// 제공자 선택 + 컨텍스트 구성 + 호출을 묶는 진입점.
public struct ScenarioAutoWriter: Sendable {
    public var provider: any AIProvider
    public var maxBlocks: Int

    public init(provider: any AIProvider, maxBlocks: Int = 10) {
        self.provider = provider
        self.maxBlocks = maxBlocks
    }

    public func draft(context: AIScenarioContext) async throws -> [AISuggestedBlock] {
        if case .unavailable(let reason) = await provider.availability() {
            throw AIProviderError.make(30, reason)
        }
        return try await provider.draftScenario(context: context, maxBlocks: maxBlocks)
    }
}
