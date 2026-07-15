import Foundation

/// 에이전트 루프가 UI에 알리는 사건.
public enum AIAgentEvent: Sendable {
    /// 응답 텍스트 조각 (스트리밍)
    case textDelta(String)
    /// 도구 실행 시작
    case toolStarted(AIToolCall)
    /// 도구 실행 완료 (실패도 포함 — isError로 구분)
    case toolFinished(AIToolResult)
    /// 반복 상한에 걸려 도구 사용을 멈추고 마무리 답변으로 넘어감
    case iterationLimitReached
}

/// 도구 호출 루프.
///
/// 모델 → (도구 요청) → 앱이 실행 → 결과 반환 → 모델 → … 을 도구 요청이 멈출 때까지 반복한다.
/// 도구를 지원하지 않는 제공자(오프라인/온디바이스)에서는 도구 없이 한 번만 돌고 끝난다.
public struct AIAgentRunner: Sendable {
    public var provider: any AIProvider
    public var persona: AIAgentPersona
    public var toolbox: AIToolbox
    /// 무한 루프 방지 상한 — 도달하면 도구를 끄고 마무리 답변을 한 번 받는다.
    public var maxIterations: Int

    public init(
        provider: any AIProvider,
        persona: AIAgentPersona,
        toolbox: AIToolbox = AIToolbox(),
        maxIterations: Int = 8
    ) {
        self.provider = provider
        self.persona = persona
        self.toolbox = toolbox
        self.maxIterations = maxIterations
    }

    /// 히스토리를 받아 루프를 돌고, 도구 호출·결과까지 포함한 최종 히스토리를 돌려준다.
    /// 반환된 히스토리를 그대로 다음 턴에 넘겨야 모델이 앞선 도구 결과를 기억한다.
    public func run(
        history: [AIChatMessage],
        onEvent: @escaping @MainActor (AIAgentEvent) -> Void
    ) async throws -> [AIChatMessage] {
        if case .unavailable(let reason) = await provider.availability() {
            throw AIProviderError.make(30, reason)
        }

        var messages = history
        let tools = provider.supportsTools ? toolbox.tools : []
        let system = persona.systemPrompt()

        // 도구가 없으면 루프 자체가 무의미하다 — 한 번만 돌고 끝낸다.
        guard !tools.isEmpty else {
            messages.append(try await respond(messages: messages, system: system, tools: [], onEvent: onEvent))
            return messages
        }

        for iteration in 0..<maxIterations {
            let reply = try await respond(messages: messages, system: system, tools: tools, onEvent: onEvent)
            messages.append(reply)

            // 도구를 더 안 부르면 이 턴이 최종 답변이다.
            guard !reply.toolCalls.isEmpty else { return messages }

            var results: [AIToolResult] = []
            for call in reply.toolCalls {
                await onEvent(.toolStarted(call))
                let result = await toolbox.execute(call)
                await onEvent(.toolFinished(result))
                results.append(result)
            }
            messages.append(AIChatMessage(role: .tool, text: "", toolResults: results))

            // 마지막 반복인데도 도구를 부르는 중 — 도구를 끄고 말로 마무리시킨다.
            if iteration == maxIterations - 1 {
                await onEvent(.iterationLimitReached)
                messages.append(try await respond(messages: messages, system: system, tools: [], onEvent: onEvent))
            }
        }
        return messages
    }

    /// 한 턴 — 스트림을 소비해 텍스트와 도구 호출을 모아 assistant 메시지로 만든다.
    private func respond(
        messages: [AIChatMessage],
        system: String,
        tools: [AITool],
        onEvent: @escaping @MainActor (AIAgentEvent) -> Void
    ) async throws -> AIChatMessage {
        var text = ""
        var calls: [AIToolCall] = []
        for try await event in provider.chatStream(history: messages, system: system, tools: tools) {
            switch event {
            case .textDelta(let delta):
                text += delta
                await onEvent(.textDelta(delta))
            case .toolCall(let call):
                calls.append(call)
            }
        }
        return AIChatMessage(role: .assistant, text: text, toolCalls: calls)
    }
}
