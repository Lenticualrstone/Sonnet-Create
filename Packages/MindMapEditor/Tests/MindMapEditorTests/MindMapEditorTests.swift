import DocumentKit
import Foundation
import Testing
@testable import MindMapEditor

/// 읽기 전용 회귀 (지시서 1단계 2) — 스토어가 최종 방어선:
/// 읽기 전용에서 모든 변경 경로(추가/삭제/이동/연결/캡션/undo)가 무시돼야 한다.
@MainActor
@Test func readOnlyBlocksAllMutations() async throws {
    let store = MindMapStore(content: MindMapContent())
    let node = store.addNode(kind: .text, title: "A", at: .zero)
    let other = store.addNode(kind: .text, title: "B", at: CGPoint(x: 100, y: 0))
    store.beginConnecting(from: node.id)
    store.completeConnection(to: other.id)
    #expect(store.content.nodes.count == 2)
    #expect(store.content.edges.count == 1)

    store.isReadOnly = true

    // 삭제 무시
    store.deleteNode(node.id)
    #expect(store.content.nodes.count == 2)

    // 추가 무시 (반환 노드는 콘텐츠에 들어가지 않는다)
    store.addNode(kind: .text, title: "C", at: .zero)
    #expect(store.content.nodes.count == 2)

    // 이동 무시
    store.liveMoveNode(id: node.id, to: CGPoint(x: 999, y: 999))
    store.commitMove(id: node.id, from: .zero)
    #expect(store.node(id: node.id)?.x == 0)

    // 연결 생성 무시
    store.beginConnecting(from: node.id)
    store.completeConnection(to: other.id)
    #expect(store.content.edges.count == 1)

    // 엣지 캡션/삭제 무시
    let edgeID = store.content.edges[0].id
    store.updateEdgeCaption(edgeID, caption: "변경")
    #expect(store.content.edges[0].caption.isEmpty)
    store.deleteEdge(edgeID)
    #expect(store.content.edges.count == 1)

    // undo도 무시 (히스토리로 내용이 되돌아가는 것도 변경이다)
    store.undo()
    #expect(store.content.nodes.count == 2)

    // 잠금 해제 후에는 정상 동작
    store.isReadOnly = false
    store.deleteNode(node.id)
    #expect(store.content.nodes.count == 1)
    #expect(store.content.edges.isEmpty)
}
