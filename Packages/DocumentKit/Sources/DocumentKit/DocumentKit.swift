import AppCore
import Foundation
import PersistenceKit

/// content.json 스키마 버전. 구조적(non-additive) 변경(필드 삭제/이름 변경/타입 변경/enum 케이스 변경) 시
/// +1 하고 DocumentContentMigrations.all에 마이그레이션을 추가한다.
public enum DocumentFormatVersion {
    public static let current = 1
}

/// 문서 종류. 각 에디터가 독립 확장자를 가진다 (상호 변환 없음).
public enum DocumentKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case scenario // 채팅형 시나리오
    case mindmap // 노드 연결형 마인드맵
    case page // 블록형 마크다운 페이지 (캐릭터 페이지 포함)

    public var id: String { rawValue }

    /// 파일 확장자 (확정: .scen / .scno / .scpa)
    public var fileExtension: String {
        switch self {
        case .scenario: "scen"
        case .mindmap: "scno"
        case .page: "scpa"
        }
    }

    public var symbolName: String {
        switch self {
        case .scenario: "text.bubble"
        case .mindmap: "point.3.connected.trianglepath.dotted"
        case .page: "doc.richtext"
        }
    }

    public static func from(fileExtension ext: String) -> DocumentKind? {
        allCases.first { $0.fileExtension == ext.lowercased() }
    }
}

/// 페이지(.scpa)의 세부 종류 — 캐릭터 페이지는 페이지의 서브타입이다.
public enum PageRole: String, Codable, Sendable {
    case standard
    case character
}

/// 구조화 프로필 필드 (나이/소속 등 사용자 정의 키-값).
public struct CharacterField: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var value: String

    public init(id: UUID = UUID(), name: String = "", value: String = "") {
        self.id = id
        self.name = name
        self.value = value
    }
}

/// 캐릭터 간 관계 (다른 캐릭터 페이지 참조 + 자유 라벨).
public struct CharacterRelation: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var targetPageID: UUID
    public var label: String

    public init(id: UUID = UUID(), targetPageID: UUID, label: String = "") {
        self.id = id
        self.targetPageID = targetPageID
        self.label = label
    }
}

/// 갤러리 항목 (복수 이미지 + 시점/상태 태그).
public struct CharacterGalleryItem: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var resourcePath: String
    public var caption: String
    /// 스토리 시점/상태 태그 (예: "1장", "부상")
    public var phase: String

    public init(id: UUID = UUID(), resourcePath: String, caption: String = "", phase: String = "") {
        self.id = id
        self.resourcePath = resourcePath
        self.caption = caption
        self.phase = phase
    }
}

/// 보이스 카드 — 말투/예시 대사/금기. AI 자동작성 컨텍스트에 주입된다. (선택적)
public struct CharacterVoice: Codable, Sendable, Equatable {
    public var tone: String
    public var taboo: String
    public var samples: [String]

    public init(tone: String = "", taboo: String = "", samples: [String] = []) {
        self.tone = tone
        self.taboo = taboo
        self.samples = samples
    }
}

/// 캐릭터 프로필 메타 (캐릭터 페이지 상단에 노출).
public struct CharacterProfile: Codable, Sendable, Equatable {
    public var role: String
    public var summary: String
    /// SF Symbols 아이콘 프로필 (이미지 미지정 시)
    public var symbolName: String
    public var accentHex: String
    /// 프로젝트 리소스 내 원본 이미지 참조 (원형 크롭 정보만 파일에 기록)
    public var imageResourcePath: String?
    /// 원형 크롭 — 중심 오프셋 (아바타 지름 대비 비율, -1...1)
    public var cropOffsetX: Double?
    public var cropOffsetY: Double?
    /// 원형 크롭 — 확대 배율 (1 = 꽉 채움)
    public var cropZoom: Double?
    /// 구조화 필드 (v2 탭 구조)
    public var fields: [CharacterField]?
    /// 관계 목록
    public var relations: [CharacterRelation]?
    /// 갤러리
    public var gallery: [CharacterGalleryItem]?
    /// 보이스 카드 (선택적)
    public var voice: CharacterVoice?

    public init(
        role: String = "",
        summary: String = "",
        symbolName: String = "person.fill",
        accentHex: String = "#8E8E93",
        imageResourcePath: String? = nil,
        cropOffsetX: Double? = nil,
        cropOffsetY: Double? = nil,
        cropZoom: Double? = nil
    ) {
        self.role = role
        self.summary = summary
        self.symbolName = symbolName
        self.accentHex = accentHex
        self.imageResourcePath = imageResourcePath
        self.cropOffsetX = cropOffsetX
        self.cropOffsetY = cropOffsetY
        self.cropZoom = cropZoom
    }
}

/// 모든 문서가 공유하는 공통 껍데기(Envelope). metadata.json으로 저장된다.
public struct DocumentEnvelope: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var kind: DocumentKind
    public var pageRole: PageRole?
    public var createdAt: Date
    public var modifiedAt: Date
    public var tags: [String]
    public var projectID: UUID?
    public var isHidden: Bool
    public var isTrashed: Bool
    /// 휴지통으로 이동한 시각 (정렬/자동정리/표시용). 휴지통 밖에서는 nil.
    public var trashedAt: Date?
    public var formatVersion: Int

    public init(
        id: UUID = UUID(),
        title: String,
        kind: DocumentKind,
        pageRole: PageRole? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        tags: [String] = [],
        projectID: UUID? = nil,
        isHidden: Bool = false,
        isTrashed: Bool = false,
        trashedAt: Date? = nil,
        formatVersion: Int = DocumentFormatVersion.current
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.pageRole = kind == .page ? (pageRole ?? .standard) : nil
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.tags = tags
        self.projectID = projectID
        self.isHidden = isHidden
        self.isTrashed = isTrashed
        self.trashedAt = trashedAt
        self.formatVersion = formatVersion
    }

    public var isCharacterPage: Bool { kind == .page && pageRole == .character }
}

/// UUID 기반 문서 간 참조/첨부/연결 그래프. refs.json으로 저장된다.
public struct ReferenceGraph: Codable, Sendable, Equatable {
    public struct Reference: Codable, Sendable, Equatable, Identifiable {
        public enum Kind: String, Codable, Sendable {
            case link, attachment, character
        }

        public var id: UUID
        public var target: UUID
        public var kind: Kind

        public init(id: UUID = UUID(), target: UUID, kind: Kind) {
            self.id = id
            self.target = target
            self.kind = kind
        }
    }

    public var outgoing: [Reference]

    public init(outgoing: [Reference] = []) {
        self.outgoing = outgoing
    }
}
