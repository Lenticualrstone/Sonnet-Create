import AppCore
import DocumentKit
import Foundation

// MARK: - 공통 모델

/// AI가 제안한 시나리오 블록 한 건 (에디터 중립 표현).
public struct AISuggestedBlock: Sendable, Equatable {
    public var isInstruction: Bool
    public var speakerName: String?
    public var text: String

    public init(isInstruction: Bool, speakerName: String? = nil, text: String) {
        self.isInstruction = isInstruction
        self.speakerName = speakerName
        self.text = text
    }
}

/// 자동 작성에 전달되는 컨텍스트. 범위는 사용자 설정(최소 범위 기본값)으로 제어된다.
public struct AIScenarioContext: Sendable {
    public var projectName: String?
    public var castNames: [String]
    /// 캐릭터 보이스 카드 요약 (말투 유지용, 선택적)
    public var castNotes: [String]
    /// (화자, 텍스트, 지침 여부) — 최근 블록 순서대로
    public var recentBlocks: [(speaker: String?, text: String, isInstruction: Bool)]

    public init(
        projectName: String? = nil,
        castNames: [String],
        castNotes: [String] = [],
        recentBlocks: [(speaker: String?, text: String, isInstruction: Bool)]
    ) {
        self.projectName = projectName
        self.castNames = castNames
        self.castNotes = castNotes
        self.recentBlocks = recentBlocks
    }
}

public enum AIAvailability: Sendable, Equatable {
    case available
    case unavailable(reason: String)
}

// MARK: - 채팅

public enum AIChatRole: String, Codable, Sendable {
    case user, assistant
}

public struct AIChatMessage: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var role: AIChatRole
    public var text: String

    public init(id: UUID = UUID(), role: AIChatRole, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

// MARK: - 에이전트 페르소나

/// 사용자가 설정하는 에이전트 정체성 — 이름 + 행동지침(마크다운).
/// 시스템 프롬프트에 합성되어 모든 제공자 호출에 공통 적용된다.
public struct AIAgentPersona: Codable, Sendable, Equatable {
    public var name: String
    /// 마크다운 행동지침 페이지 전문
    public var instructionsMarkdown: String

    public init(name: String = "", instructionsMarkdown: String = "") {
        self.name = name
        self.instructionsMarkdown = instructionsMarkdown
    }

    /// 기본 시스템 프롬프트 + 페르소나를 합성한 실효 시스템 프롬프트.
    public func systemPrompt() -> String {
        var parts: [String] = []
        let displayName = name.trimmingCharacters(in: .whitespaces)
        parts.append("""
        당신은 macOS 창작 워크스페이스 'Sonnet Create'의 AI 에이전트\(displayName.isEmpty ? "" : " '\(displayName)'")입니다. \
        사용자의 시나리오·마인드맵·페이지 작업(세계관, 캐릭터, 플롯 등)을 돕습니다. \
        간결하고 실용적으로 한국어로 답하되, 사용자가 다른 언어를 쓰면 그 언어를 따르세요.
        """)
        let instructions = instructionsMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty {
            parts.append("--- 사용자가 정의한 행동지침 ---\n\(instructions)")
        }
        return parts.joined(separator: "\n\n")
    }
}

/// 레거시 호환용 기본 시스템 프롬프트 (페르소나 미설정 시와 동일).
public let aiChatSystemPrompt = AIAgentPersona().systemPrompt()

// MARK: - 제공자 종류

public enum AIProviderKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case appleOnDevice
    case anthropic
    case openai
    case gemini
    case grok
    case offline

    public var id: String { rawValue }

    /// 사용자에게 보여줄 브랜드 이름.
    public var displayName: String {
        switch self {
        case .appleOnDevice: "Apple 온디바이스"
        case .anthropic: "Claude"
        case .openai: "ChatGPT"
        case .gemini: "Gemini"
        case .grok: "Grok"
        case .offline: "오프라인 초안"
        }
    }

    /// API 키가 필요한 클라우드 제공자인지.
    public var requiresAPIKey: Bool {
        switch self {
        case .anthropic, .openai, .gemini, .grok: true
        case .appleOnDevice, .offline: false
        }
    }

    /// Keychain 저장 키.
    public var keychainKey: String {
        switch self {
        case .anthropic: "anthropic-api-key"
        case .openai: "openai-api-key"
        case .gemini: "gemini-api-key"
        case .grok: "grok-api-key"
        case .appleOnDevice, .offline: ""
        }
    }

    /// 기본 모델 ID.
    public var defaultModel: String {
        switch self {
        case .anthropic: "claude-opus-4-8"
        case .openai: "gpt-5.1"
        case .gemini: "gemini-2.5-flash"
        case .grok: "grok-4"
        case .appleOnDevice, .offline: ""
        }
    }

    /// 픽커에 노출할 추천 모델 목록 (직접 입력도 허용).
    public var suggestedModels: [String] {
        switch self {
        case .anthropic: ["claude-opus-4-8", "claude-sonnet-5", "claude-haiku-4-5"]
        case .openai: ["gpt-5.1", "gpt-5", "gpt-4.1-mini"]
        case .gemini: ["gemini-2.5-flash", "gemini-2.5-pro"]
        case .grok: ["grok-4", "grok-3-mini"]
        case .appleOnDevice, .offline: []
        }
    }
}

// MARK: - 제공자 프로토콜

/// 공통 제공자 인터페이스. 각 제공자는 어댑터로 연결되어 모델 교체 시 나머지 코드가 바뀌지 않는다.
/// 필수 구현은 generate(단발 생성)와 chatStream(스트리밍 채팅) 두 가지 —
/// 시나리오 자동작성 등 상위 기능은 기본 구현이 이 둘 위에서 조립된다.
public protocol AIProvider: Sendable {
    var kind: AIProviderKind { get }
    func availability() async -> AIAvailability
    /// 단발 텍스트 생성 (문서/구조 생성용)
    func generate(system: String, prompt: String) async throws -> String
    /// 스트리밍 채팅 — 텍스트 델타를 순서대로 방출
    func chatStream(history: [AIChatMessage], system: String) -> AsyncThrowingStream<String, Error>
    /// 대사/지침 블록 연속 생성 (최대 maxBlocks개 제안).
    /// 기본 구현은 generate 기반이며 제공자가 재정의할 수 있다 — 재정의분이 실제로
    /// 불리려면 반드시 프로토콜 요구사항이어야 한다 (extension 전용이면 `any AIProvider`
    /// 경유 호출이 정적 디스패치로 기본 구현에 묶인다).
    func draftScenario(context: AIScenarioContext, maxBlocks: Int) async throws -> [AISuggestedBlock]
}

public extension AIProvider {
    /// 비스트리밍 채팅 — 스트림을 모아서 반환.
    func chat(history: [AIChatMessage], system: String = aiChatSystemPrompt) async throws -> String {
        var result = ""
        for try await delta in chatStream(history: history, system: system) {
            result += delta
        }
        return result
    }

    /// 대사/지침 블록 연속 생성 (최대 maxBlocks개 제안) — generate 기반 기본 구현.
    func draftScenario(context: AIScenarioContext, maxBlocks: Int) async throws -> [AISuggestedBlock] {
        let text = try await generate(
            system: "당신은 시나리오 이어쓰기 보조입니다. 요청된 형식만 정확히 지켜 출력하세요.",
            prompt: ScenarioResponseParser.prompt(for: context, maxBlocks: maxBlocks)
        )
        return Array(ScenarioResponseParser.parse(text, castNames: context.castNames).prefix(maxBlocks))
    }
}

/// 제공자 공통 오류 헬퍼.
enum AIProviderError {
    static func make(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "AIAgentKit", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// MARK: - 응답 파서 (제공자 공유)

/// 모델 응답을 블록 리스트로 파싱한다.
/// 형식: "이름: 대사" → 대사 블록, "[지침] 내용" 또는 "(내용)" → 지침 블록.
public enum ScenarioResponseParser {
    public static func parse(_ text: String, castNames: [String]) -> [AISuggestedBlock] {
        var blocks: [AISuggestedBlock] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("[지침]") || line.hasPrefix("[Direction]") || line.hasPrefix("[指示]") {
                let content = line
                    .replacingOccurrences(of: "[지침]", with: "")
                    .replacingOccurrences(of: "[Direction]", with: "")
                    .replacingOccurrences(of: "[指示]", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !content.isEmpty { blocks.append(AISuggestedBlock(isInstruction: true, text: content)) }
                continue
            }
            if line.hasPrefix("("), line.hasSuffix(")") {
                let content = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if !content.isEmpty { blocks.append(AISuggestedBlock(isInstruction: true, text: content)) }
                continue
            }
            if let colonIndex = line.firstIndex(of: ":") {
                let name = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let content = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                if !content.isEmpty, name.count <= 24 {
                    let matched = castNames.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
                    blocks.append(AISuggestedBlock(isInstruction: false, speakerName: matched, text: content))
                    continue
                }
            }
            blocks.append(AISuggestedBlock(isInstruction: true, text: line))
        }
        return blocks
    }

    public static func prompt(for context: AIScenarioContext, maxBlocks: Int) -> String {
        var lines: [String] = []
        lines.append("당신은 시나리오 작가의 보조입니다. 아래 시나리오의 자연스러운 다음 전개를 최대 \(maxBlocks)개 블록으로 이어서 작성하세요.")
        lines.append("형식 규칙: 대사는 '이름: 내용', 무대 지침은 '[지침] 내용'. 다른 형식/설명/번호는 금지.")
        if let project = context.projectName {
            lines.append("프로젝트: \(project)")
        }
        if !context.castNames.isEmpty {
            lines.append("등장 캐릭터: \(context.castNames.joined(separator: ", ")) — 이 이름만 화자로 사용.")
        }
        if !context.castNotes.isEmpty {
            lines.append("캐릭터 보이스 (말투를 반드시 유지할 것):")
            lines.append(contentsOf: context.castNotes.map { "- " + $0 })
        }
        lines.append("--- 지금까지의 시나리오 ---")
        for block in context.recentBlocks.suffix(30) {
            if block.isInstruction {
                lines.append("[지침] \(block.text)")
            } else {
                lines.append("\(block.speaker ?? "?"): \(block.text)")
            }
        }
        lines.append("--- 여기서부터 이어서 ---")
        return lines.joined(separator: "\n")
    }
}
