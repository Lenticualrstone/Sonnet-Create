import AppCore
import DocumentKit
import Foundation
import Observation

/// 노드 연결형 마인드맵 에디터의 상태/로직.
@MainActor
@Observable
public final class MindMapStore {
    public private(set) var content: MindMapContent
    public var onContentChanged: ((MindMapContent) -> Void)?

    /// 선택된 노드
    public var selectedNodeID: UUID?
    /// 연결선 시작 노드 (연결 모드)
    public var connectingFromID: UUID?
    /// 포트 드래그 중 현재 위치 (캔버스 뷰 좌표) — 라이브 프리뷰 라인용
    public var connectPreviewPoint: CGPoint?

    /// 페이지 노드에 연결 가능한 문서 목록 (앱이 주입)
    public var documentCatalog: (() -> [(id: UUID, title: String)])?

    /// 리소스 경로(번들 상대) → 실제 URL 해석 (앱이 주입)
    public var resourceResolver: ((String) -> URL?)?
    /// 외부 파일 → 번들 리소스 복사 후 상대 경로 반환 (앱이 주입)
    public var resourceImporter: ((URL) -> String?)?

    private var undoStack: [MindMapContent] = []
    private var redoStack: [MindMapContent] = []
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public init(content: MindMapContent) {
        self.content = content
    }

    /// 직전 onContentChanged가 undo/redo/스냅샷 복원에서 왔는지 — 세션이 집필 통계에
    /// 히스토리 이동을 집계하지 않도록 구분하는 신호.
    public private(set) var lastChangeWasHistory = false

    private func mutate(isHistory: Bool = false, _ transform: (inout MindMapContent) -> Void) {
        lastChangeWasHistory = isHistory
        undoStack.append(content)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
        transform(&content)
        onContentChanged?(content)
    }

    /// 스냅샷 복원 등 콘텐츠 전면 교체 — 되돌리기 스택에 남는 단일 작업.
    public func replaceContent(_ newContent: MindMapContent) {
        mutate(isHistory: true) { $0 = newContent }
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        lastChangeWasHistory = true
        redoStack.append(content)
        content = previous
        onContentChanged?(content)
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        lastChangeWasHistory = true
        undoStack.append(content)
        content = next
        onContentChanged?(content)
    }

    // MARK: 뷰포트 (undo 대상 아님)

    /// 팬/줌은 onContentChanged가 아닌 전용 채널로 보고한다 — 보기만 한 문서가
    /// '미저장' 상태가 되어 자동저장·워크스페이스 리스캔을 연쇄시키는 것을 막는다.
    /// 세션은 이 값을 메모리에만 반영하고, 실제 편집이 있어 저장될 때 함께 영속된다.
    public var onViewportChanged: ((MindMapContent) -> Void)?

    public func setViewport(zoom: Double, offsetX: Double, offsetY: Double) {
        content.zoom = zoom
        content.offsetX = offsetX
        content.offsetY = offsetY
        onViewportChanged?(content)
    }

    // MARK: 노드

    public func node(id: UUID) -> MindMapNode? {
        content.nodes.first { $0.id == id }
    }

    public var selectedNode: MindMapNode? {
        selectedNodeID.flatMap { node(id: $0) }
    }

    @discardableResult
    public func addNode(kind: MindMapNodeKind, title: String, at point: CGPoint) -> MindMapNode {
        let node = MindMapNode(kind: kind, title: title, x: point.x, y: point.y)
        mutate { $0.nodes.append(node) }
        selectedNodeID = node.id
        return node
    }

    public func updateNode(_ node: MindMapNode) {
        mutate { c in
            guard let idx = c.nodes.firstIndex(where: { $0.id == node.id }) else { return }
            c.nodes[idx] = node
        }
    }

    /// 드래그 중 위치 갱신 (undo 스택에 쌓지 않음 — 드래그 종료 시 commitMove 호출)
    public func liveMoveNode(id: UUID, to point: CGPoint) {
        guard let idx = content.nodes.firstIndex(where: { $0.id == id }) else { return }
        content.nodes[idx].x = point.x
        content.nodes[idx].y = point.y
    }

    public func commitMove(id: UUID, from origin: CGPoint) {
        guard let idx = content.nodes.firstIndex(where: { $0.id == id }) else { return }
        let final = CGPoint(x: content.nodes[idx].x, y: content.nodes[idx].y)
        // undo 스택에는 이동 전 상태를 쌓는다
        content.nodes[idx].x = origin.x
        content.nodes[idx].y = origin.y
        mutate { c in
            guard let i = c.nodes.firstIndex(where: { $0.id == id }) else { return }
            c.nodes[i].x = final.x
            c.nodes[i].y = final.y
        }
    }

    public func deleteNode(_ id: UUID) {
        mutate { c in
            c.nodes.removeAll { $0.id == id }
            c.edges.removeAll { $0.fromID == id || $0.toID == id }
        }
        if selectedNodeID == id { selectedNodeID = nil }
        if connectingFromID == id { connectingFromID = nil }
    }

    // MARK: 엣지

    public func beginConnecting(from id: UUID) {
        connectingFromID = id
    }

    public func cancelConnecting() {
        connectingFromID = nil
        connectPreviewPoint = nil
    }

    /// 연결 모드에서 대상 노드 확정 → 엣지 생성 (분기 연결선: 한 노드에서 여러 개 허용).
    public func completeConnection(to targetID: UUID) {
        defer {
            connectingFromID = nil
            connectPreviewPoint = nil
        }
        guard let from = connectingFromID, from != targetID else { return }
        let exists = content.edges.contains {
            ($0.fromID == from && $0.toID == targetID) || ($0.fromID == targetID && $0.toID == from)
        }
        if !exists {
            mutate { $0.edges.append(MindMapEdge(fromID: from, toID: targetID)) }
        }
    }

    public func updateEdgeCaption(_ edgeID: UUID, caption: String) {
        mutate { c in
            guard let idx = c.edges.firstIndex(where: { $0.id == edgeID }) else { return }
            c.edges[idx].caption = caption
        }
    }

    public func deleteEdge(_ edgeID: UUID) {
        mutate { $0.edges.removeAll { $0.id == edgeID } }
    }

    /// 선택 노드에 닿은 엣지 (하이라이팅 대상)
    public func edgesTouching(_ nodeID: UUID?) -> Set<UUID> {
        guard let nodeID else { return [] }
        return Set(content.edges.filter { $0.fromID == nodeID || $0.toID == nodeID }.map(\.id))
    }

    public func edges(of nodeID: UUID) -> [MindMapEdge] {
        content.edges.filter { $0.fromID == nodeID || $0.toID == nodeID }
    }
}
