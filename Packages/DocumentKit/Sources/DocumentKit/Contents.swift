import Foundation

// MARK: - 시나리오 (.scen)

/// 시나리오 등장 캐릭터(캐스트). 프로젝트 캐릭터 페이지를 참조하거나 문서 자체에 정의된다.
public struct CastMember: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var roleLine: String
    public var symbolName: String
    public var accentHex: String
    /// 프로젝트 캐릭터 페이지(.scpa, character) 참조
    public var characterPageID: UUID?
    /// 리허설 낭독 목소리 (AVSpeechSynthesisVoice identifier) — nil이면 자동 배정.
    /// 선택적 필드라 구버전 파일과 양방향 호환된다.
    public var voiceIdentifier: String?

    public init(
        id: UUID = UUID(),
        name: String,
        roleLine: String = "",
        symbolName: String = "person.fill",
        accentHex: String = "#5AC8FA",
        characterPageID: UUID? = nil,
        voiceIdentifier: String? = nil
    ) {
        self.id = id
        self.name = name
        self.roleLine = roleLine
        self.symbolName = symbolName
        self.accentHex = accentHex
        self.characterPageID = characterPageID
        self.voiceIdentifier = voiceIdentifier
    }
}

public enum ScenarioBlockKind: String, Codable, Sendable {
    case line // 대사
    case instruction // 지침
    case divider // 구분선 (장면 전환 등)
}

public struct ScenarioBlock: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var kind: ScenarioBlockKind
    /// 대사 블록의 화자(다중 캐릭터 지원). 비어 있으면 화자 미지정(물음표).
    public var speakerIDs: [UUID]
    public var text: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: ScenarioBlockKind,
        speakerIDs: [UUID] = [],
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.speakerIDs = speakerIDs
        self.text = text
        self.createdAt = createdAt
    }
}

/// 시나리오 분기 — 본편의 특정 블록에서 갈라지는 대안 전개.
public struct ScenarioBranch: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    /// 분기가 갈라지는 본편 블록 (nil이면 처음부터 갈라짐)
    public var parentBlockID: UUID?
    public var blocks: [ScenarioBlock]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        parentBlockID: UUID? = nil,
        blocks: [ScenarioBlock] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.parentBlockID = parentBlockID
        self.blocks = blocks
        self.createdAt = createdAt
    }
}

public struct ScenarioContent: Codable, Sendable, Equatable {
    public var cast: [CastMember]
    public var blocks: [ScenarioBlock]
    public var branches: [ScenarioBranch]

    public init(cast: [CastMember] = [], blocks: [ScenarioBlock] = [], branches: [ScenarioBranch] = []) {
        self.cast = cast
        self.blocks = blocks
        self.branches = branches
    }

    private enum CodingKeys: String, CodingKey { case cast, blocks, branches }

    /// branches가 없는 구버전 파일과의 하위 호환.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cast = try container.decodeIfPresent([CastMember].self, forKey: .cast) ?? []
        blocks = try container.decodeIfPresent([ScenarioBlock].self, forKey: .blocks) ?? []
        branches = try container.decodeIfPresent([ScenarioBranch].self, forKey: .branches) ?? []
    }
}

// MARK: - 마인드맵 (.scno)

public enum MindMapNodeKind: String, Codable, Sendable {
    case text, page, image, file
}

public struct MindMapNode: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var kind: MindMapNodeKind
    public var title: String
    public var detail: String
    public var x: Double
    public var y: Double
    public var colorHex: String?
    /// page 노드가 참조하는 문서
    public var linkedDocumentID: UUID?
    /// image/file 노드의 리소스 경로 (번들 resources/ 상대)
    public var resourcePath: String?

    public init(
        id: UUID = UUID(),
        kind: MindMapNodeKind = .text,
        title: String,
        detail: String = "",
        x: Double,
        y: Double,
        colorHex: String? = nil,
        linkedDocumentID: UUID? = nil,
        resourcePath: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.x = x
        self.y = y
        self.colorHex = colorHex
        self.linkedDocumentID = linkedDocumentID
        self.resourcePath = resourcePath
    }
}

public struct MindMapEdge: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var fromID: UUID
    public var toID: UUID
    public var caption: String

    public init(id: UUID = UUID(), fromID: UUID, toID: UUID, caption: String = "") {
        self.id = id
        self.fromID = fromID
        self.toID = toID
        self.caption = caption
    }
}

public struct MindMapContent: Codable, Sendable, Equatable {
    public var nodes: [MindMapNode]
    public var edges: [MindMapEdge]
    public var zoom: Double
    public var offsetX: Double
    public var offsetY: Double

    public init(
        nodes: [MindMapNode] = [],
        edges: [MindMapEdge] = [],
        zoom: Double = 1.0,
        offsetX: Double = 0,
        offsetY: Double = 0
    ) {
        self.nodes = nodes
        self.edges = edges
        self.zoom = zoom
        self.offsetX = offsetX
        self.offsetY = offsetY
    }
}

// MARK: - 블록형 페이지 (.scpa)

public enum PageBlockKind: String, Codable, CaseIterable, Sendable {
    case paragraph, heading1, heading2, heading3
    case bulleted, numbered, task, toggle
    case quote, code, divider, callout
    case image, table
    /// 다른 문서(.scen/.scpa/.scno)의 라이브 미리보기 삽입 (3b)
    case embed
}

public struct PageBlock: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var kind: PageBlockKind
    public var text: String
    public var isChecked: Bool
    public var indent: Int
    public var isExpanded: Bool
    /// image 블록: 번들 resources/ 상대 경로 또는 http(s) URL
    public var resourcePath: String?
    /// image 블록: 표시 비율 (nil = 원본)
    public var aspect: Double?
    /// image 블록: 표시 너비 비율 0.25~1.0 (nil = 1.0)
    public var widthFraction: Double?
    /// image 블록: 정렬 "left" | "center" | "right" (nil = center)
    public var alignRaw: String?
    /// 다음 블록과 나란히(2단) 배치
    public var sideBySide: Bool?
    /// table 블록: 행 × 열 문자열
    public var tableData: [[String]]?
    /// embed 블록: 미리보기로 삽입한 문서 id
    public var embeddedDocumentID: UUID?

    public init(
        id: UUID = UUID(),
        kind: PageBlockKind = .paragraph,
        text: String = "",
        isChecked: Bool = false,
        indent: Int = 0,
        isExpanded: Bool = true,
        resourcePath: String? = nil,
        aspect: Double? = nil,
        tableData: [[String]]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.isChecked = isChecked
        self.indent = indent
        self.isExpanded = isExpanded
        self.resourcePath = resourcePath
        self.aspect = aspect
        self.tableData = tableData
        // widthFraction/alignRaw/sideBySide는 옵셔널 기본 nil
    }
}

public struct PageContent: Codable, Sendable, Equatable {
    public var blocks: [PageBlock]
    /// 캐릭터 페이지(.scpa, role=character)일 때만 존재
    public var profile: CharacterProfile?

    public init(blocks: [PageBlock] = [], profile: CharacterProfile? = nil) {
        self.blocks = blocks
        self.profile = profile
    }
}

// MARK: - 통합 콘텐츠 (content.json)

/// 에디터별 본문(Payload). 공통 껍데기와 분리되어 content.json으로 저장된다.
public enum DocumentContent: Codable, Sendable, Equatable {
    case scenario(ScenarioContent)
    case mindmap(MindMapContent)
    case page(PageContent)

    public var kind: DocumentKind {
        switch self {
        case .scenario: .scenario
        case .mindmap: .mindmap
        case .page: .page
        }
    }

    public static func empty(for kind: DocumentKind, pageRole: PageRole? = nil) -> DocumentContent {
        switch kind {
        case .scenario: .scenario(ScenarioContent())
        case .mindmap: .mindmap(MindMapContent())
        case .page: .page(PageContent(profile: pageRole == .character ? CharacterProfile() : nil))
        }
    }

    /// 검색 색인용 본문 평문.
    public var plainText: String {
        switch self {
        case .scenario(let c):
            let cast = c.cast.map { "\($0.name) \($0.roleLine)" }
            let main = c.blocks.map(\.text)
            let branched = c.branches.flatMap { branch in [branch.name] + branch.blocks.map(\.text) }
            return (cast + main + branched).joined(separator: "\n")
        case .mindmap(let c):
            let nodes = c.nodes.map { "\($0.title) \($0.detail)" }
            let captions = c.edges.map(\.caption).filter { !$0.isEmpty }
            return (nodes + captions).joined(separator: "\n")
        case .page(let c):
            var parts = c.blocks.map { block in
                block.text + " " + (block.tableData?.flatMap { $0 }.joined(separator: " ") ?? "")
            }
            if let profile = c.profile {
                parts.append("\(profile.role) \(profile.summary)")
            }
            return parts.joined(separator: "\n")
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, payload }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(DocumentKind.self, forKey: .kind)
        switch kind {
        case .scenario: self = .scenario(try container.decode(ScenarioContent.self, forKey: .payload))
        case .mindmap: self = .mindmap(try container.decode(MindMapContent.self, forKey: .payload))
        case .page: self = .page(try container.decode(PageContent.self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .scenario(let payload): try container.encode(payload, forKey: .payload)
        case .mindmap(let payload): try container.encode(payload, forKey: .payload)
        case .page(let payload): try container.encode(payload, forKey: .payload)
        }
    }
}
