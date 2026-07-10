import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

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

    public func draftScenario(context: AIScenarioContext, maxBlocks: Int) async throws -> [AISuggestedBlock] {
        #if canImport(FoundationModels)
        let session = LanguageModelSession(
            instructions: "당신은 시나리오 이어쓰기 보조입니다. 요청된 형식만 정확히 지켜 출력하세요."
        )
        let prompt = ScenarioResponseParser.prompt(for: context, maxBlocks: maxBlocks)
        let response = try await session.respond(to: prompt)
        return Array(
            ScenarioResponseParser.parse(response.content, castNames: context.castNames).prefix(maxBlocks)
        )
        #else
        throw NSError(domain: "AIAgentKit", code: 10, userInfo: [
            NSLocalizedDescriptionKey: "이 시스템에서는 온디바이스 모델을 사용할 수 없습니다.",
        ])
        #endif
    }

    public func chat(history: [AIChatMessage]) async throws -> String {
        #if canImport(FoundationModels)
        let session = LanguageModelSession(instructions: aiChatSystemPrompt)
        let transcript = history.map { message in
            (message.role == .user ? "사용자: " : "보조: ") + message.text
        }.joined(separator: "\n")
        let response = try await session.respond(to: transcript + "\n보조: ")
        return response.content
        #else
        throw NSError(domain: "AIAgentKit", code: 11, userInfo: [
            NSLocalizedDescriptionKey: "이 시스템에서는 온디바이스 모델을 사용할 수 없습니다.",
        ])
        #endif
    }
}

// MARK: - Anthropic API

/// Anthropic Messages API 어댑터.
public struct AnthropicProvider: AIProvider {
    public let kind: AIProviderKind = .anthropic

    let apiKey: String
    let model: String

    public init(apiKey: String, model: String = "claude-sonnet-5") {
        self.apiKey = apiKey
        self.model = model
    }

    public func availability() async -> AIAvailability {
        apiKey.isEmpty ? .unavailable(reason: "API 키가 설정되지 않았습니다") : .available
    }

    public func draftScenario(context: AIScenarioContext, maxBlocks: Int) async throws -> [AISuggestedBlock] {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": ScenarioResponseParser.prompt(for: context, maxBlocks: maxBlocks)],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "unknown"
            throw NSError(domain: "AIAgentKit", code: 20, userInfo: [
                NSLocalizedDescriptionKey: "Anthropic API 오류: \(message)",
            ])
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let contentItems = json["content"] as? [[String: Any]]
        else { return [] }

        let text = contentItems.compactMap { $0["text"] as? String }.joined(separator: "\n")
        return Array(ScenarioResponseParser.parse(text, castNames: context.castNames).prefix(maxBlocks))
    }

    public func chat(history: [AIChatMessage]) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let messages = history.map { message in
            ["role": message.role == .user ? "user" : "assistant", "content": message.text]
        }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": aiChatSystemPrompt,
            "messages": messages,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "unknown"
            throw NSError(domain: "AIAgentKit", code: 21, userInfo: [
                NSLocalizedDescriptionKey: "Anthropic API 오류: \(message.prefix(200))",
            ])
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let contentItems = json["content"] as? [[String: Any]]
        else { return "" }
        return contentItems.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }
}

// MARK: - 오프라인 초안 (내장)

/// 네트워크/모델 없이도 동작하는 결정적 초안 생성기.
/// 실제 창작 대체가 아니라, 파이프라인 검증과 데모용 뼈대 제안을 만든다.
public struct OfflineDraftProvider: AIProvider {
    public let kind: AIProviderKind = .offline

    public init() {}

    public func availability() async -> AIAvailability { .available }

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

    public func chat(history: [AIChatMessage]) async throws -> String {
        try await Task.sleep(for: .milliseconds(350))
        guard let last = history.last(where: { $0.role == .user }) else { return "" }
        let topic = last.text.prefix(48)
        return """
        (오프라인 초안 모드) "\(topic)" — 지금은 내장 초안 생성기만 동작 중이라 깊은 답변은 어려워요. \
        설정 > 베타에서 온디바이스(Apple) 또는 Anthropic API 제공자를 연결하면 \
        세계관·캐릭터·플롯에 대해 실제 대화를 나눌 수 있습니다.
        """
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
            throw NSError(domain: "AIAgentKit", code: 30, userInfo: [NSLocalizedDescriptionKey: reason])
        }
        return try await provider.draftScenario(context: context, maxBlocks: maxBlocks)
    }
}
