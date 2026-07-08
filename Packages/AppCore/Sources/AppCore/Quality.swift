import Foundation

/// 렌더링/효과 품질 단계. 전 계층이 공유하는 어휘라 AppCore에 둔다.
/// - high: 전체 Liquid Glass + 배경 애니메이션 (전원 연결·고성능)
/// - standard: 핵심 표면만 유리 효과 (기본값)
/// - low: 효과 최소화, 불투명 대체 (배터리·발열·저사양)
public enum RenderQuality: String, Codable, CaseIterable, Sendable, Identifiable {
    case low, standard, high

    public var id: String { rawValue }
}

/// AI 에이전트가 참조할 수 있는 컨텍스트 범위 (최소 범위가 기본값).
public enum AIContextScope: String, Codable, CaseIterable, Sendable, Identifiable {
    case document, project, workspace

    public var id: String { rawValue }
}
