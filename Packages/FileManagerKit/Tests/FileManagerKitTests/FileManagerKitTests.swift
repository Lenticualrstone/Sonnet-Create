import DocumentKit
import Foundation
import Testing
@testable import FileManagerKit

/// 임시·격리 워크스페이스를 만들고 문서 번들 몇 개를 실제로 기록한다.
/// 실제 사용자 워크스페이스(~/Documents/SonnetCreate)는 절대 건드리지 않는다.
@MainActor
private func makeWorkspace(documentCount: Int) throws -> (store: WorkspaceStore, root: URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("SonnetCreateTests-\(UUID().uuidString)", isDirectory: true)
    let store = WorkspaceStore(rootURL: root)
    for index in 1...documentCount {
        let document = store.createDocument(title: "테스트 문서 \(index)", kind: .page)
        _ = try DocumentPackageIO.write(document)
    }
    store.scan()
    return (store, root)
}

/// 다중 휴지통 이동 회귀 — 확인 후 일괄 이동돼도 전 항목이 휴지통에 들어가고,
/// 전부 원위치로 복원 가능해야 한다 (지시서 1단계 1).
@MainActor
@Test func bulkTrashMovesAllAndRestores() async throws {
    let (store, root) = try makeWorkspace(documentCount: 3)
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(store.visibleDocuments.count == 3)

    // 앱의 confirmPendingTrash와 동일한 경로: 항목별 moveToTrash 순회
    for item in store.visibleDocuments {
        store.moveToTrash(item)
    }
    #expect(store.visibleDocuments.isEmpty)
    #expect(store.trashedDocuments.count == 3)

    // 전부 복원 — 원래 폴더(워크스페이스 루트)가 살아 있으므로 폴백 없이 돌아와야 한다
    for item in store.trashedDocuments {
        let fellBack = store.restoreFromTrash(item)
        #expect(!fellBack)
    }
    #expect(store.visibleDocuments.count == 3)
    #expect(store.trashedDocuments.isEmpty)
}

/// 다중 영구 삭제 회귀 — 휴지통의 여러 항목을 한 번에 지우면 전부 사라져야 한다 (지시서 1단계 1).
@MainActor
@Test func bulkPermanentDeleteRemovesAll() async throws {
    let (store, root) = try makeWorkspace(documentCount: 2)
    defer { try? FileManager.default.removeItem(at: root) }

    for item in store.visibleDocuments {
        store.moveToTrash(item)
    }
    #expect(store.trashedDocuments.count == 2)

    store.deletePermanently(store.trashedDocuments)
    #expect(store.trashedDocuments.isEmpty)
    #expect(store.visibleDocuments.isEmpty)
}
