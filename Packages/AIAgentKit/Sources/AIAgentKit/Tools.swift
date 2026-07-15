import Foundation

// MARK: - 도구 스키마 (제공자 중립)

/// 도구 파라미터 하나의 타입/설명. JSON Schema의 실용적 부분집합으로,
/// 4개 제공자(Anthropic / OpenAI / Grok / Gemini)가 공통으로 받아들이는 범위만 쓴다.
/// (Gemini는 OpenAPI 서브셋이라 `additionalProperties`·`$ref` 등을 거부한다.)
public indirect enum AIToolParameter: Sendable {
    case string(_ description: String, enumValues: [String] = [])
    case integer(_ description: String)
    case number(_ description: String)
    case boolean(_ description: String)
    case array(_ description: String, of: AIToolParameter)
    case object(_ description: String, properties: [String: AIToolParameter], required: [String] = [])

    var jsonSchema: [String: Any] {
        switch self {
        case .string(let description, let enumValues):
            var schema: [String: Any] = ["type": "string", "description": description]
            if !enumValues.isEmpty { schema["enum"] = enumValues }
            return schema
        case .integer(let description):
            return ["type": "integer", "description": description]
        case .number(let description):
            return ["type": "number", "description": description]
        case .boolean(let description):
            return ["type": "boolean", "description": description]
        case .array(let description, let items):
            return ["type": "array", "description": description, "items": items.jsonSchema]
        case .object(let description, let properties, let required):
            return [
                "type": "object",
                "description": description,
                "properties": properties.mapValues(\.jsonSchema),
                "required": required,
            ]
        }
    }
}

/// 에이전트가 호출할 수 있는 도구 하나의 정의.
public struct AITool: Sendable, Identifiable, Equatable {
    public var name: String
    public var description: String
    public var properties: [String: AIToolParameter]
    public var required: [String]

    public var id: String { name }

    public init(
        name: String,
        description: String,
        properties: [String: AIToolParameter] = [:],
        required: [String] = []
    ) {
        self.name = name
        self.description = description
        self.properties = properties
        self.required = required
    }

    /// 공통 JSON Schema. 제공자별 래핑(input_schema / function.parameters /
    /// function_declarations)은 각 어댑터가 담당한다.
    public var parameterSchema: [String: Any] {
        [
            "type": "object",
            "properties": properties.mapValues(\.jsonSchema),
            "required": required,
        ]
    }

    public static func == (lhs: AITool, rhs: AITool) -> Bool {
        lhs.name == rhs.name && lhs.description == rhs.description
    }
}

// MARK: - 호출 · 인자 · 결과

/// 모델이 요청한 도구 호출.
/// 인자는 `[String: Any]`가 Sendable이 아니므로 JSON 문자열로 보관한다.
public struct AIToolCall: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON.isEmpty ? "{}" : argumentsJSON
    }

    public var arguments: AIToolArguments { AIToolArguments(json: argumentsJSON) }
}

public struct AIToolArgumentError: LocalizedError {
    public let key: String
    public let reason: String

    public init(key: String, reason: String) {
        self.key = key
        self.reason = reason
    }

    public var errorDescription: String? { "인자 '\(key)': \(reason)" }
}

/// 도구 인자 리더 — 핸들러가 타입을 확인하며 꺼내 쓴다.
/// 모델이 스키마를 어겨도 앱이 크래시하지 않고 오류 결과로 되돌려주기 위한 계층.
public struct AIToolArguments: Sendable {
    let json: String

    public init(json: String) { self.json = json }

    /// 원본 딕셔너리 (제공자 어댑터가 히스토리를 되돌려 보낼 때도 쓴다).
    public var dictionary: [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    public func string(_ key: String) throws -> String {
        guard let value = dictionary[key] as? String, !value.isEmpty else {
            throw AIToolArgumentError(key: key, reason: "필수 문자열이 없습니다")
        }
        return value
    }

    public func string(_ key: String, or fallback: String) -> String {
        dictionary[key] as? String ?? fallback
    }

    public func optionalString(_ key: String) -> String? {
        guard let value = dictionary[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    public func int(_ key: String, or fallback: Int) -> Int {
        if let value = dictionary[key] as? Int { return value }
        // 일부 모델은 숫자를 문자열로 보낸다
        if let text = dictionary[key] as? String, let value = Int(text) { return value }
        if let value = dictionary[key] as? Double { return Int(value) }
        return fallback
    }

    public func bool(_ key: String, or fallback: Bool) -> Bool {
        if let value = dictionary[key] as? Bool { return value }
        if let text = dictionary[key] as? String { return text == "true" }
        return fallback
    }

    public func stringArray(_ key: String) -> [String] {
        (dictionary[key] as? [Any])?.compactMap { $0 as? String } ?? []
    }

    /// 오브젝트 배열 — 각 원소를 다시 인자 리더로 감싸 돌려준다.
    public func objects(_ key: String) -> [AIToolArguments] {
        guard let raw = dictionary[key] as? [Any] else { return [] }
        return raw.compactMap { element in
            guard let object = element as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: object),
                  let text = String(data: data, encoding: .utf8)
            else { return nil }
            return AIToolArguments(json: text)
        }
    }
}

/// 도구 실행 결과. 실패도 예외가 아니라 결과로 모델에 돌려줘야 루프가 스스로 회복한다.
public struct AIToolResult: Sendable, Equatable {
    public let callID: String
    /// Gemini는 호출 ID가 없어 이름으로 결과를 매칭한다 — 그래서 이름도 함께 보관한다.
    public let toolName: String
    public let content: String
    public let isError: Bool

    public init(callID: String, toolName: String, content: String, isError: Bool = false) {
        self.callID = callID
        self.toolName = toolName
        self.content = content
        self.isError = isError
    }
}

// MARK: - 툴박스 (확장 지점)

// MARK: - 파괴적 작업 확인

/// 되돌리기 어려운 도구를 실행하기 직전에 사용자에게 묻는 요청.
public struct AIToolConfirmationRequest: Sendable, Identifiable {
    public let id: String
    public let toolName: String
    /// 무엇이 일어날지 사람이 읽을 요약 — 도구가 인자를 해석해 만든다.
    public let summary: String

    public init(id: String, toolName: String, summary: String) {
        self.id = id
        self.toolName = toolName
        self.summary = summary
    }
}

/// 도구 정의 + 실행부 한 쌍.
public struct AIToolHandler: Sendable {
    public let tool: AITool
    /// 파괴적 도구만 채운다 — 실행 전 사용자에게 보여줄 요약을 인자에서 만든다.
    /// nil이면 확인 없이 바로 실행한다 (추가/생성처럼 되돌리기로 충분한 작업).
    public let confirmationSummary: (@Sendable (AIToolArguments) async throws -> String)?
    public let run: @Sendable (AIToolArguments) async throws -> String

    public init(
        _ tool: AITool,
        confirmationSummary: (@Sendable (AIToolArguments) async throws -> String)? = nil,
        run: @escaping @Sendable (AIToolArguments) async throws -> String
    ) {
        self.tool = tool
        self.confirmationSummary = confirmationSummary
        self.run = run
    }

    /// 사용자 확인이 필요한 도구인지.
    public var isDestructive: Bool { confirmationSummary != nil }
}

/// 도구 모음. 기능 모듈이 각자 핸들러를 기여하고, 합쳐서 에이전트에 넘긴다 —
/// 새 기능을 붙일 때 여기에 핸들러만 더하면 에이전트가 즉시 쓸 수 있다.
public struct AIToolbox: Sendable {
    private var handlers: [String: AIToolHandler]

    /// 파괴적 도구 실행 전 사용자 확인 — 앱이 주입한다.
    /// **주입하지 않으면 파괴적 도구는 실행되지 않고 거부된다** (확인 없이 지우는 일이
    /// 절대 없도록 기본값이 안전한 쪽으로 열려 있다).
    public var confirmationHandler: (@Sendable (AIToolConfirmationRequest) async -> Bool)?

    public init(
        _ handlers: [AIToolHandler] = [],
        confirmationHandler: (@Sendable (AIToolConfirmationRequest) async -> Bool)? = nil
    ) {
        self.handlers = Dictionary(handlers.map { ($0.tool.name, $0) }) { _, latest in latest }
        self.confirmationHandler = confirmationHandler
    }

    /// 이름 오름차순 — 순서가 매 요청 같아야 프롬프트 캐시가 유지된다.
    public var tools: [AITool] {
        handlers.values.map(\.tool).sorted { $0.name < $1.name }
    }

    public var isEmpty: Bool { handlers.isEmpty }

    public mutating func add(_ handler: AIToolHandler) {
        handlers[handler.tool.name] = handler
    }

    public func adding(_ others: [AIToolHandler]) -> AIToolbox {
        var copy = self
        for handler in others { copy.add(handler) }
        return copy
    }

    /// 호출 실행. 알 수 없는 도구·인자 오류·핸들러 예외를 전부 오류 '결과'로 감싼다 —
    /// 모델이 그걸 읽고 스스로 고쳐 다시 호출할 수 있어야 한다.
    /// 파괴적 도구는 실행 전에 사용자 확인을 거친다.
    public func execute(_ call: AIToolCall) async -> AIToolResult {
        guard let handler = handlers[call.name] else {
            let known = tools.map(\.name).joined(separator: ", ")
            return AIToolResult(
                callID: call.id, toolName: call.name,
                content: "알 수 없는 도구 '\(call.name)'. 사용 가능: \(known)",
                isError: true
            )
        }
        do {
            if let summarize = handler.confirmationSummary {
                // 요약을 먼저 만든다 — 대상이 없으면 여기서 걸러져 사용자를 귀찮게 하지 않는다.
                let summary = try await summarize(call.arguments)
                guard let confirmationHandler else {
                    return AIToolResult(
                        callID: call.id, toolName: call.name,
                        content: "이 작업은 사용자 확인이 필요하지만 확인 절차가 없어 실행하지 않았습니다.",
                        isError: true
                    )
                }
                let request = AIToolConfirmationRequest(
                    id: call.id, toolName: call.name, summary: summary
                )
                guard await confirmationHandler(request) else {
                    // 거부는 오류가 아니다 — 모델이 재시도하지 말고 방향을 바꾸도록 알린다.
                    return AIToolResult(
                        callID: call.id, toolName: call.name,
                        content: "사용자가 이 작업을 거부했습니다. 다시 시도하지 말고, 필요하면 다른 방법을 제안하세요.",
                        isError: false
                    )
                }
            }
            return AIToolResult(
                callID: call.id, toolName: call.name,
                content: try await handler.run(call.arguments)
            )
        } catch {
            return AIToolResult(
                callID: call.id, toolName: call.name,
                content: error.localizedDescription, isError: true
            )
        }
    }
}
