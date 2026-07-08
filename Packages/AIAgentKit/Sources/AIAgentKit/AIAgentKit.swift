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

/// 채팅용 공통 시스템 지침.
public let aiChatSystemPrompt = """
당신은 macOS 창작 워크스페이스 'Sonnet Create'의 AI 보조입니다. \
사용자의 시나리오·마인드맵·페이지 작업(세계관, 캐릭터, 플롯 등)을 돕습니다. \
간결하고 실용적으로 한국어로 답하되, 사용자가 다른 언어를 쓰면 그 언어를 따르세요.
"""

public enum AIProviderKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case appleOnDevice
    case anthropic
    case offline

    public var id: String { rawValue }
}

/// 공통 제공자 인터페이스. 각 제공자는 어댑터로 연결되어 모델 교체 시 나머지 코드가 바뀌지 않는다.
public protocol AIProvider: Sendable {
    var kind: AIProviderKind { get }
    func availability() async -> AIAvailability
    /// 대사/지침 블록 연속 생성 (최대 maxBlocks개 제안)
    func draftScenario(context: AIScenarioContext, maxBlocks: Int) async throws -> [AISuggestedBlock]
    /// 자유 대화 (에이전트 채팅)
    func chat(history: [AIChatMessage]) async throws -> String
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
