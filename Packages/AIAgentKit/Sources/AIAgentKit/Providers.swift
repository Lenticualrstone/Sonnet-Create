import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - SSE 공통 유틸

/// Server-Sent Events 스트림에서 "data: " 라인의 JSON 페이로드를 추출해
/// 텍스트 델타로 변환하는 공통 루프. 각 제공자는 extract 클로저만 제공한다.
enum SSEStream {
    static func textDeltas(
        request: URLRequest,
        extract: @escaping @Sendable ([String: Any]) -> String?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
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
                        if let delta = extract(json), !delta.isEmpty {
                            continuation.yield(delta)
                        }
                        if Task.isCancelled { break }
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

// MARK: - Anthropic (Claude)

/// Anthropic Messages API 어댑터 — SSE 스트리밍 지원.
public struct AnthropicProvider: AIProvider {
    public let kind: AIProviderKind = .anthropic

    let apiKey: String
    let model: String

    public init(apiKey: String, model: String = AIProviderKind.anthropic.defaultModel) {
        self.apiKey = apiKey
        self.model = model.isEmpty ? AIProviderKind.anthropic.defaultModel : model
    }

    public func availability() async -> AIAvailability {
        apiKey.isEmpty ? .unavailable(reason: "API 키가 설정되지 않았습니다") : .available
    }

    private func makeRequest(system: String, messages: [[String: Any]], stream: Bool, maxTokens: Int) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
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
        if stream { body["stream"] = true }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public func generate(system: String, prompt: String) async throws -> String {
        let request = try makeRequest(
            system: system,
            messages: [["role": "user", "content": prompt]],
            stream: false,
            maxTokens: 8192
        )
        let json = try await JSONRequest.post(request)
        guard let contentItems = json["content"] as? [[String: Any]] else { return "" }
        return contentItems.compactMap { $0["text"] as? String }.joined()
    }

    public func chatStream(history: [AIChatMessage], system: String) -> AsyncThrowingStream<String, Error> {
        let messages = history.map { message in
            ["role": message.role == .user ? "user" : "assistant", "content": message.text]
        }
        do {
            let request = try makeRequest(system: system, messages: messages, stream: true, maxTokens: 4096)
            return SSEStream.textDeltas(request: request) { json in
                // content_block_delta → delta.text
                guard json["type"] as? String == "content_block_delta",
                      let delta = json["delta"] as? [String: Any]
                else { return nil }
                return delta["text"] as? String
            }
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }
}

// MARK: - OpenAI 호환 (ChatGPT / Grok)

/// OpenAI Chat Completions 호환 어댑터 — OpenAI(ChatGPT)와 xAI(Grok)가 공유한다.
public struct OpenAICompatibleProvider: AIProvider {
    public let kind: AIProviderKind

    let apiKey: String
    let model: String
    let baseURL: URL

    /// ChatGPT (api.openai.com)
    public static func openAI(apiKey: String, model: String = AIProviderKind.openai.defaultModel) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(
            kind: .openai,
            apiKey: apiKey,
            model: model.isEmpty ? AIProviderKind.openai.defaultModel : model,
            baseURL: URL(string: "https://api.openai.com/v1")!
        )
    }

    /// Grok (api.x.ai)
    public static func grok(apiKey: String, model: String = AIProviderKind.grok.defaultModel) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(
            kind: .grok,
            apiKey: apiKey,
            model: model.isEmpty ? AIProviderKind.grok.defaultModel : model,
            baseURL: URL(string: "https://api.x.ai/v1")!
        )
    }

    public func availability() async -> AIAvailability {
        apiKey.isEmpty ? .unavailable(reason: "API 키가 설정되지 않았습니다") : .available
    }

    private func makeRequest(system: String, history: [AIChatMessage], stream: Bool) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var messages: [[String: Any]] = [["role": "system", "content": system]]
        messages += history.map { message in
            ["role": message.role == .user ? "user" : "assistant", "content": message.text]
        }
        var body: [String: Any] = [
            "model": model,
            "messages": messages,
        ]
        if stream { body["stream"] = true }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public func generate(system: String, prompt: String) async throws -> String {
        let request = try makeRequest(
            system: system,
            history: [AIChatMessage(role: .user, text: prompt)],
            stream: false
        )
        let json = try await JSONRequest.post(request)
        guard
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any]
        else { return "" }
        return message["content"] as? String ?? ""
    }

    public func chatStream(history: [AIChatMessage], system: String) -> AsyncThrowingStream<String, Error> {
        do {
            let request = try makeRequest(system: system, history: history, stream: true)
            return SSEStream.textDeltas(request: request) { json in
                guard
                    let choices = json["choices"] as? [[String: Any]],
                    let delta = choices.first?["delta"] as? [String: Any]
                else { return nil }
                return delta["content"] as? String
            }
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }
}

// MARK: - Google Gemini

/// Google Gemini generateContent API 어댑터 — SSE 스트리밍 지원.
public struct GeminiProvider: AIProvider {
    public let kind: AIProviderKind = .gemini

    let apiKey: String
    let model: String

    public init(apiKey: String, model: String = AIProviderKind.gemini.defaultModel) {
        self.apiKey = apiKey
        self.model = model.isEmpty ? AIProviderKind.gemini.defaultModel : model
    }

    public func availability() async -> AIAvailability {
        apiKey.isEmpty ? .unavailable(reason: "API 키가 설정되지 않았습니다") : .available
    }

    private func makeRequest(system: String, history: [AIChatMessage], stream: Bool) throws -> URLRequest {
        let endpoint = stream ? "streamGenerateContent?alt=sse" : "generateContent"
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let contents = history.map { message in
            [
                "role": message.role == .user ? "user" : "model",
                "parts": [["text": message.text]],
            ] as [String: Any]
        }
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": contents,
        ]
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
            stream: false
        )
        let json = try await JSONRequest.post(request)
        return Self.extractText(json) ?? ""
    }

    public func chatStream(history: [AIChatMessage], system: String) -> AsyncThrowingStream<String, Error> {
        do {
            let request = try makeRequest(system: system, history: history, stream: true)
            return SSEStream.textDeltas(request: request) { Self.extractText($0) }
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }
}

// MARK: - 온디바이스 (Apple Foundation Model)

/// Apple Intelligence 온디바이스 모델 어댑터. 오프라인·프라이버시 우선.
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

    public func chatStream(history: [AIChatMessage], system: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let transcript = history.map { message in
                        (message.role == .user ? "사용자: " : "보조: ") + message.text
                    }.joined(separator: "\n")
                    let reply = try await generate(system: system, prompt: transcript + "\n보조: ")
                    continuation.yield(reply)
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

    public func chatStream(history: [AIChatMessage], system: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                try? await Task.sleep(for: .milliseconds(350))
                let topic = history.last(where: { $0.role == .user })?.text.prefix(48) ?? ""
                continuation.yield("""
                (오프라인 초안 모드) "\(topic)" — 지금은 내장 초안 생성기만 동작 중이라 깊은 답변은 어려워요. \
                설정 > AI 에이전트에서 온디바이스(Apple) 또는 Claude/ChatGPT/Gemini/Grok API 제공자를 연결하면 \
                세계관·캐릭터·플롯에 대해 실제 대화를 나눌 수 있습니다.
                """)
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
