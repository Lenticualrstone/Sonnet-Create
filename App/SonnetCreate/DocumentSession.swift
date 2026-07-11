import AppCore
import DesignSystem
import DocumentKit
import Foundation
import MarkdownEditor
import MindMapEditor
import Observation
import ScenarioEditor
import SwiftUI

/// 열린 문서 하나의 세션 — 에디터 스토어와 디스크 사이에서 저장 상태를 관리한다.
@MainActor
@Observable
final class DocumentSession {
    enum EditorStore {
        case scenario(ScenarioStore)
        case mindmap(MindMapStore)
        case page(PageStore)
    }

    private(set) var document: LoadedDocument
    let editor: EditorStore
    private(set) var saveState: SaveState

    var autosaveEnabled = true
    /// 읽기 전용 뷰어 모드 — 세션(탭) 단위로 켜고 끈다. 파일에는 저장하지 않는다.
    var isReadOnly = false
    /// 저장 후(제목 변경 등) 워크스페이스 재스캔 트리거
    var onSaved: (() -> Void)?

    private var autosaveTask: Task<Void, Never>?
    /// 디스크에 한 번이라도 기록됐는지 (기존 파일을 연 세션이면 처음부터 true)
    private var isPersisted: Bool
    /// 세션 동안 실제 편집이 한 번이라도 있었는지. false면 저장하지 않는다 —
    /// 새 문서 버튼만 누르고 아무 것도 하지 않은 채 닫으면 더미 파일이 남지 않게 하기 위함.
    private var hasChanged = false

    var id: UUID { document.envelope.id }
    var title: String {
        get { document.envelope.title }
        set {
            guard newValue != document.envelope.title else { return }
            document.envelope.title = newValue
            markDirty()
        }
    }

    /// 집필 통계 — 내용 글자 수가 늘어난 만큼 AppState로 보고.
    var onWritingDelta: ((Int) -> Void)?
    private var lastCharCount = 0

    init(document: LoadedDocument, isPersisted: Bool) {
        self.document = document
        self.isPersisted = isPersisted
        lastCharCount = Self.charCount(of: document.content)
        saveState = isPersisted ? .savedAuto : .unsaved
        switch document.content {
        case .scenario(let content):
            let store = ScenarioStore(content: content)
            editor = .scenario(store)
            store.onContentChanged = { [weak self] updated in
                self?.document.content = .scenario(updated)
                self?.reportWritingDelta()
                self?.markDirty()
            }
        case .mindmap(let content):
            let store = MindMapStore(content: content)
            editor = .mindmap(store)
            store.onContentChanged = { [weak self] updated in
                self?.document.content = .mindmap(updated)
                self?.reportWritingDelta()
                self?.markDirty()
            }
            store.resourceResolver = { [weak self] relative in self?.resolveResource(relative) }
            store.resourceImporter = { [weak self] source in self?.importResource(source) }
        case .page(let content):
            let store = PageStore(content: content)
            editor = .page(store)
            store.onContentChanged = { [weak self] updated in
                self?.document.content = .page(updated)
                self?.reportWritingDelta()
                self?.markDirty()
            }
            store.resourceResolver = { [weak self] relative in self?.resolveResource(relative) }
            store.resourceImporter = { [weak self] source in self?.importResource(source) }
        }
    }

    // MARK: 번들 resources/ 리소스 관리

    private func resolveResource(_ relative: String) -> URL? {
        document.url.appendingPathComponent("resources").appendingPathComponent(relative)
    }

    /// 외부 파일을 문서 번들 resources/로 복사하고 상대 경로를 돌려준다.
    private func importResource(_ source: URL) -> String? {
        let resources = document.url.appendingPathComponent("resources", isDirectory: true)
        try? FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        var name = source.lastPathComponent
        var target = resources.appendingPathComponent(name)
        var counter = 2
        while FileManager.default.fileExists(atPath: target.path) {
            name = "\(counter)-\(source.lastPathComponent)"
            target = resources.appendingPathComponent(name)
            counter += 1
        }
        do {
            try FileManager.default.copyItem(at: source, to: target)
            return name
        } catch {
            return nil
        }
    }

    private func reportWritingDelta() {
        let count = Self.charCount(of: document.content)
        let delta = count - lastCharCount
        lastCharCount = count
        if delta > 0, !isReadOnly { onWritingDelta?(delta) }
    }

    /// 문서 종류별 본문 글자 수 (시나리오는 분기 포함).
    private static func charCount(of content: DocumentContent) -> Int {
        switch content {
        case .scenario(let c):
            c.blocks.reduce(0) { $0 + $1.text.count }
                + c.branches.reduce(0) { sum, branch in
                    sum + branch.blocks.reduce(0) { $0 + $1.text.count }
                }
        case .page(let c):
            c.blocks.reduce(0) { $0 + $1.text.count }
        case .mindmap(let c):
            c.nodes.reduce(0) { $0 + $1.title.count + $1.detail.count }
        }
    }

    private func markDirty() {
        // 읽기 전용 모드에서는 편집 UI가 모두 잠기므로 여기 도달할 일이 없어야
        // 하지만, 만약 우회 경로로 변경이 들어와도 더티 처리하지 않는다.
        guard !isReadOnly else { return }
        hasChanged = true
        saveState = .unsaved
        guard autosaveEnabled else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.save(manual: false)
        }
    }

    func save(manual: Bool) {
        // 실제 변경이 한 번도 없었다면 저장하지 않는다 (빈 새 문서가 더미 파일로 남는 것을 방지).
        guard hasChanged else { return }
        autosaveTask?.cancel()
        saveState = .saving
        document.envelope.modifiedAt = Date()
        mergeDerivedReferences()
        do {
            try DocumentPackageIO.write(document)
            isPersisted = true
            saveState = manual ? .savedManual : .savedAuto
            // ⌘S 습관을 스냅샷 안전망으로 — 자동 표시가 붙고 오래된 것부터 정리된다
            if manual, shouldSnapshotOnManualSave?() == true {
                takeSnapshot(named: Localizer.shared.t(.autosave), automatic: true)
            }
            onSaved?()
        } catch {
            saveState = .error
        }
    }

    // MARK: 참조 관리

    /// 수동 참조 추가 (참조 패널).
    func addReference(to target: UUID) {
        guard target != id,
              !document.refs.outgoing.contains(where: { $0.target == target && $0.kind == .link })
        else { return }
        document.refs.outgoing.append(ReferenceGraph.Reference(target: target, kind: .link))
        markDirty()
    }

    func removeReference(_ refID: UUID) {
        document.refs.outgoing.removeAll { $0.id == refID }
        markDirty()
    }

    /// 콘텐츠에서 파생되는 자동 참조(캐스트의 캐릭터 페이지, 마인드맵 페이지 노드)를 병합.
    private func mergeDerivedReferences() {
        let derived: [(UUID, ReferenceGraph.Reference.Kind)]
        switch document.content {
        case .scenario(let content):
            derived = content.cast.compactMap { $0.characterPageID }.map { ($0, .character) }
        case .mindmap(let content):
            derived = content.nodes.compactMap { $0.linkedDocumentID }.map { ($0, .link) }
        case .page:
            derived = []
        }
        for (target, kind) in derived {
            let exists = document.refs.outgoing.contains { $0.target == target && $0.kind == kind }
            if !exists {
                document.refs.outgoing.append(ReferenceGraph.Reference(target: target, kind: kind))
            }
        }
    }

    // MARK: 스냅샷

    private(set) var snapshots: [DocumentSnapshot] = []

    func refreshSnapshots() {
        snapshots = SnapshotIO.list(in: document.url)
    }

    /// 문서당 보관하는 자동 스냅샷 상한 — 이름 붙인 수동 스냅샷은 무제한.
    private static let automaticSnapshotCap = 10

    /// 설정 > 일반의 '수동 저장 시 자동 스냅샷' — AppState가 주입.
    var shouldSnapshotOnManualSave: (() -> Bool)?

    func takeSnapshot(named name: String, automatic: Bool = false) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let snapshot = DocumentSnapshot(
            name: trimmed.isEmpty ? Localizer.shared.t(.snapshots) : trimmed,
            content: document.content,
            isAutomatic: automatic
        )
        try? SnapshotIO.save(snapshot, in: document.url)
        refreshSnapshots()
        if automatic { pruneAutomaticSnapshots() }
    }

    /// 자동 스냅샷이 상한을 넘으면 오래된 것부터 삭제한다 (수동은 보존).
    private func pruneAutomaticSnapshots() {
        let automatic = snapshots.filter(\.isAutomatic) // 최신순 정렬 상태
        guard automatic.count > Self.automaticSnapshotCap else { return }
        for stale in automatic.dropFirst(Self.automaticSnapshotCap) {
            SnapshotIO.delete(stale.id, in: document.url)
        }
        refreshSnapshots()
    }

    func deleteSnapshot(_ id: UUID) {
        SnapshotIO.delete(id, in: document.url)
        refreshSnapshots()
    }

    /// 복원 — 현재 상태를 자동 스냅샷으로 보관한 뒤 에디터 스토어를 통째로 교체.
    /// 교체는 스토어의 undo 스택에 남는 단일 작업이라 ⌘Z로도 되돌릴 수 있다.
    func restoreSnapshot(_ snapshot: DocumentSnapshot) {
        takeSnapshot(named: Localizer.shared.t(.beforeRestoreSnapshot), automatic: true)
        switch (editor, snapshot.content) {
        case (.scenario(let store), .scenario(let content)):
            store.replaceContent(content)
        case (.mindmap(let store), .mindmap(let content)):
            store.replaceContent(content)
        case (.page(let store), .page(let content)):
            store.replaceContent(content)
        default:
            break // 같은 문서의 스냅샷이므로 종류 불일치는 없다
        }
    }

    /// 종료/탭 닫기 시 미저장분 플러시.
    func flush() {
        if saveState == .unsaved || saveState == .saving {
            save(manual: false)
        }
    }
}
