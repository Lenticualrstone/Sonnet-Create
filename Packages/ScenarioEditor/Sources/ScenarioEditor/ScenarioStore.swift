import AIAgentKit
import AppCore
import DocumentKit
import Foundation
import Observation

/// 프로젝트 캐릭터 페이지에서 캐스트로 가져올 수 있는 항목.
public struct ImportableCharacter: Identifiable, Sendable {
    public let id: UUID // 캐릭터 페이지 문서 UUID
    public let name: String
    public let role: String
    public let symbolName: String
    public let accentHex: String

    public init(id: UUID, name: String, role: String, symbolName: String, accentHex: String) {
        self.id = id
        self.name = name
        self.role = role
        self.symbolName = symbolName
        self.accentHex = accentHex
    }
}

/// 채팅형 시나리오 에디터의 상태/로직.
@MainActor
@Observable
public final class ScenarioStore {
    public enum ComposerMode: Sendable, CaseIterable {
        case line, instruction, scene
    }

    // MARK: 문서 상태

    public private(set) var content: ScenarioContent
    /// 내용이 바뀔 때마다 호출 (세션이 dirty 표시/자동저장에 사용)
    public var onContentChanged: ((ScenarioContent) -> Void)?

    // MARK: 입력기 상태

    public var composerMode: ComposerMode = .line
    public var composerText: String = ""
    public var selectedSpeakerIDs: Set<UUID> = []
    /// 빈 입력 전송 시도 시 Error State Shake 트리거
    public var shakeTrigger: CGFloat = 0
    /// '내용 수정' 중인 블록 (입력란으로 이동 후 원위치 복귀)
    public private(set) var editingBlockID: UUID?

    // MARK: 분기

    /// 현재 보고 있는 분기 (nil = 본편)
    public var activeBranchID: UUID?

    /// 프로젝트 캐릭터 페이지 목록 (앱이 주입)
    public var characterCatalog: (() -> [ImportableCharacter])?

    // MARK: 검색/undo

    public var searchQuery: String = ""
    private var undoStack: [ScenarioContent] = []
    private var redoStack: [ScenarioContent] = []
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    // MARK: AI 제안

    public var pendingSuggestions: [ScenarioBlock] = []
    public var isGenerating: Bool = false
    public var aiEnabled: Bool = false
    /// 앱이 주입하는 자동 작성 파이프라인
    public var autoWriter: (@MainActor (ScenarioContent) async throws -> [AISuggestedBlock])?

    public init(content: ScenarioContent) {
        self.content = content
    }

    // MARK: 변형 헬퍼

    /// 직전 onContentChanged가 undo/redo/스냅샷 복원에서 왔는지 — 세션이 집필 통계(늘어난
    /// 글자 수)에 히스토리 이동을 집계하지 않도록 구분하는 신호.
    public private(set) var lastChangeWasHistory = false

    private func mutate(isHistory: Bool = false, _ transform: (inout ScenarioContent) -> Void) {
        lastChangeWasHistory = isHistory
        undoStack.append(content)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
        transform(&content)
        onContentChanged?(content)
    }

    /// 스냅샷 복원 등 콘텐츠 전면 교체 — 되돌리기 스택에 남는 단일 작업.
    public func replaceContent(_ newContent: ScenarioContent) {
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

    // MARK: 분기 접근자

    public var activeBranch: ScenarioBranch? {
        activeBranchID.flatMap { id in content.branches.first { $0.id == id } }
    }

    /// 현재 편집 중인 블록 시퀀스 (본편 또는 활성 분기)
    public var activeBlocks: [ScenarioBlock] {
        activeBranch?.blocks ?? content.blocks
    }

    /// 분기 모드에서 상단에 흐리게 보여줄 분기점 직전 본편 블록들 (최대 2개)
    public var branchContextBlocks: [ScenarioBlock] {
        guard let branch = activeBranch,
              let parentID = branch.parentBlockID,
              let idx = content.blocks.firstIndex(where: { $0.id == parentID })
        else { return [] }
        let start = max(0, idx - 1)
        return Array(content.blocks[start...idx])
    }

    /// 활성 시퀀스에 대한 변형 (본편/분기 자동 라우팅)
    private func withActiveBlocks(_ transform: (inout [ScenarioBlock]) -> Void) {
        mutate { c in
            if let branchID = activeBranchID,
               let idx = c.branches.firstIndex(where: { $0.id == branchID }) {
                transform(&c.branches[idx].blocks)
            } else {
                transform(&c.blocks)
            }
        }
    }

    public func switchBranch(_ id: UUID?) {
        activeBranchID = id
        cancelEditing()
    }

    /// 본편의 특정 블록에서 분기 생성 후 그 분기로 전환.
    @discardableResult
    public func createBranch(after block: ScenarioBlock?, name: String) -> ScenarioBranch {
        let branch = ScenarioBranch(name: name, parentBlockID: block?.id)
        mutate { $0.branches.append(branch) }
        activeBranchID = branch.id
        return branch
    }

    public func renameBranch(_ id: UUID, to name: String) {
        mutate { c in
            guard let idx = c.branches.firstIndex(where: { $0.id == id }) else { return }
            c.branches[idx].name = name
        }
    }

    public func deleteBranch(_ id: UUID) {
        mutate { $0.branches.removeAll { $0.id == id } }
        if activeBranchID == id { activeBranchID = nil }
    }

    /// AI 이어쓰기용 유효 흐름: 분기면 분기점까지의 본편 + 분기 블록.
    public var effectiveFlowForAI: [ScenarioBlock] {
        guard let branch = activeBranch else { return content.blocks }
        var flow: [ScenarioBlock] = []
        if let parentID = branch.parentBlockID,
           let idx = content.blocks.firstIndex(where: { $0.id == parentID }) {
            flow.append(contentsOf: content.blocks[...idx])
        }
        flow.append(contentsOf: branch.blocks)
        return flow
    }

    // MARK: 블록

    /// 에디터 표준 ⌘F처럼 검색은 목록을 필터링하지 않고 점프 탐색한다 —
    /// 채팅형 흐름의 맥락(앞뒤 블록)을 유지한 채 일치 위치만 하이라이트/이동.
    public var visibleBlocks: [ScenarioBlock] {
        activeBlocks
    }

    /// 검색어와 일치하는 블록 ID 목록 (문서 순서).
    public var searchMatchIDs: [UUID] {
        guard !searchQuery.isEmpty else { return [] }
        return activeBlocks
            .filter { $0.text.localizedCaseInsensitiveContains(searchQuery) }
            .map(\.id)
    }

    /// 현재 포커스된 검색 일치 블록 — 행이 강조 링을 그리는 데 쓴다.
    public var searchFocusID: UUID?

    /// 입력기 제출. 빈 텍스트면 shake만 발동하고 false 반환.
    @discardableResult
    public func submitComposer() -> Bool {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            shakeTrigger += 1
            return false
        }
        // 지침 모드에서 마크다운 구분선 문법 → 구분선 블록 (전용 버튼 대체)
        if editingBlockID == nil, composerMode == .instruction, text == "---" || text == "***" {
            withActiveBlocks { $0.append(ScenarioBlock(kind: .divider, text: "")) }
            composerText = ""
            return true
        }

        // 장면 모드 (2a) — 입력한 제목을 단 장면 경계(구분선)를 삽입하고 대사 모드로 복귀
        if editingBlockID == nil, composerMode == .scene {
            withActiveBlocks { $0.append(ScenarioBlock(kind: .divider, text: text)) }
            composerText = ""
            composerMode = .line
            return true
        }

        if let editingID = editingBlockID {
            withActiveBlocks { blocks in
                guard let idx = blocks.firstIndex(where: { $0.id == editingID }) else { return }
                blocks[idx].text = text
                if blocks[idx].kind == .line {
                    blocks[idx].speakerIDs = Array(selectedSpeakerIDs)
                }
            }
            editingBlockID = nil
        } else {
            let block = ScenarioBlock(
                kind: composerMode == .line ? .line : .instruction,
                speakerIDs: composerMode == .line ? Array(selectedSpeakerIDs) : [],
                text: text
            )
            withActiveBlocks { $0.append(block) }
        }
        composerText = ""
        return true
    }

    /// 구분선 블록 삽입 (장면 전환 등).
    public func insertDivider() {
        withActiveBlocks { $0.append(ScenarioBlock(kind: .divider, text: "")) }
    }

    // MARK: 플롯 타임라인 (2a)

    /// 타임라인의 장면 한 칸 — 본편을 구분선으로 자른 세그먼트.
    public struct PlotScene: Identifiable, Equatable {
        public let id: UUID
        /// 구분선 제목 우선, 없으면 첫 텍스트 미리보기
        public let title: String
        /// 카드 클릭 시 스크롤 타깃 (세그먼트 첫 블록)
        public let jumpTargetID: UUID
        public let lineCount: Int
        /// 이 장면 안에서 갈라진 분기들
        public let branchIDs: [UUID]
        /// content.blocks 내 세그먼트 범위 (여는 구분선 포함)
        public let range: Range<Int>
    }

    /// 타임라인에서 마지막으로 선택한 장면 (강조 표시용).
    public var currentSceneID: UUID?

    /// 본편을 구분선 기준으로 자른 장면 목록 — 타임라인은 항상 본편 순서를 다룬다.
    public var plotScenes: [PlotScene] {
        let blocks = content.blocks
        guard !blocks.isEmpty else { return [] }
        var boundaries: [Int] = []
        for (index, block) in blocks.enumerated() where block.kind == .divider {
            boundaries.append(index)
        }
        var ranges: [Range<Int>] = []
        var start = 0
        for boundary in boundaries {
            if boundary > start { ranges.append(start..<boundary) }
            start = boundary
        }
        ranges.append(start..<blocks.count)
        // 첫 블록이 구분선이면 위 로직상 0..<0이 생기지 않도록 이미 처리됨
        return ranges.compactMap { range in
            guard !range.isEmpty else { return nil }
            let segment = Array(blocks[range])
            let opener = segment.first!
            let title: String
            if opener.kind == .divider, !opener.text.isEmpty {
                title = opener.text
            } else {
                title = segment.first(where: { $0.kind != .divider && !$0.text.isEmpty })
                    .map { String($0.text.prefix(14)) } ?? ""
            }
            let segmentIDs = Set(segment.map(\.id))
            return PlotScene(
                id: opener.id,
                title: title,
                jumpTargetID: opener.id,
                lineCount: segment.count { $0.kind == .line },
                branchIDs: content.branches
                    .filter { $0.parentBlockID.map(segmentIDs.contains) ?? false }
                    .map(\.id),
                range: range
            )
        }
    }

    /// 드래그 재배열 — 시작 시 스냅샷을 잡아 두고, 라이브 이동은 undo 스택을 오염시키지
    /// 않으며, 끝날 때 실제로 순서가 바뀐 경우에만 단일 undo 항목으로 확정한다.
    private var sceneDragBaseline: ScenarioContent?

    public func beginSceneDrag() {
        guard sceneDragBaseline == nil else { return }
        sceneDragBaseline = content
    }

    /// 드래그한 장면이 대상 장면 위로 들어온 순간의 라이브 리오더 (undo 기록 없음).
    public func moveSceneLive(draggedID: UUID, over targetID: UUID) {
        let scenes = plotScenes
        guard let from = scenes.firstIndex(where: { $0.id == draggedID }),
              let to = scenes.firstIndex(where: { $0.id == targetID }),
              from != to
        else { return }
        var segments = scenes.map { Array(content.blocks[$0.range]) }
        let moved = segments.remove(at: from)
        segments.insert(moved, at: to)
        lastChangeWasHistory = true // 순서 이동은 집필량이 아니다
        content.blocks = segments.flatMap { $0 }
        onContentChanged?(content)
    }

    public func endSceneDrag() {
        defer { sceneDragBaseline = nil }
        guard let baseline = sceneDragBaseline,
              baseline.blocks.map(\.id) != content.blocks.map(\.id)
        else { return }
        undoStack.append(baseline)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    /// ＋ 장면 — 본편 끝에 제목 달린 장면 경계를 추가한다.
    @discardableResult
    public func addScene(title: String) -> UUID {
        let divider = ScenarioBlock(kind: .divider, text: title)
        mutate { $0.blocks.append(divider) }
        currentSceneID = divider.id
        return divider.id
    }

    /// 빠른 메뉴 '내용 수정' — 블록 내용을 입력란으로 이동.
    public func beginEditing(_ block: ScenarioBlock) {
        editingBlockID = block.id
        composerText = block.text
        composerMode = block.kind == .line ? .line : .instruction
        selectedSpeakerIDs = Set(block.speakerIDs)
    }

    public func cancelEditing() {
        editingBlockID = nil
        composerText = ""
    }

    public func deleteBlock(_ id: UUID) {
        withActiveBlocks { $0.removeAll { $0.id == id } }
        if editingBlockID == id { cancelEditing() }
    }

    public func moveBlocks(from source: IndexSet, to destination: Int) {
        withActiveBlocks { $0.move(fromOffsets: source, toOffset: destination) }
    }

    // MARK: 캐스트

    public func castMember(id: UUID) -> CastMember? {
        content.cast.first { $0.id == id }
    }

    public func speakers(of block: ScenarioBlock) -> [CastMember] {
        block.speakerIDs.compactMap { castMember(id: $0) }
    }

    public func addCastMember(name: String) {
        let palette = ["#B23A21", "#3E5C50", "#8A6D2F", "#9E5A3C", "#5F6B7C"]
        let hex = palette[content.cast.count % palette.count]
        mutate { $0.cast.append(CastMember(name: name, accentHex: hex)) }
    }

    public func updateCastMember(_ member: CastMember) {
        mutate { c in
            guard let idx = c.cast.firstIndex(where: { $0.id == member.id }) else { return }
            c.cast[idx] = member
        }
    }

    public func removeCastMember(_ id: UUID) {
        mutate { c in
            c.cast.removeAll { $0.id == id }
            for i in c.blocks.indices {
                c.blocks[i].speakerIDs.removeAll { $0 == id }
            }
            for b in c.branches.indices {
                for i in c.branches[b].blocks.indices {
                    c.branches[b].blocks[i].speakerIDs.removeAll { $0 == id }
                }
            }
        }
        selectedSpeakerIDs.remove(id)
    }

    /// 프로젝트 캐릭터 페이지를 캐스트로 가져오기 (이미 연결된 페이지는 중복 방지).
    public func importCastMember(_ character: ImportableCharacter) {
        guard !content.cast.contains(where: { $0.characterPageID == character.id }) else { return }
        mutate {
            $0.cast.append(CastMember(
                name: character.name,
                roleLine: character.role,
                symbolName: character.symbolName,
                accentHex: character.accentHex,
                characterPageID: character.id
            ))
        }
    }

    public func moveCast(from source: IndexSet, to destination: Int) {
        mutate { $0.cast.move(fromOffsets: source, toOffset: destination) }
    }

    public func toggleSpeaker(_ id: UUID, exclusive: Bool) {
        if exclusive {
            selectedSpeakerIDs = selectedSpeakerIDs == [id] ? [] : [id]
        } else if selectedSpeakerIDs.contains(id) {
            selectedSpeakerIDs.remove(id)
        } else {
            selectedSpeakerIDs.insert(id)
        }
    }

    // MARK: AI

    /// 프로젝트·시나리오·캐릭터를 파악해 이어쓰기 제안 생성 (최대 10블록).
    public func generateSuggestions() async {
        guard let autoWriter, !isGenerating else { return }
        isGenerating = true
        defer { isGenerating = false }
        do {
            // 분기 모드에서는 분기점까지의 본편 + 분기 흐름을 컨텍스트로 사용
            let effective = ScenarioContent(cast: content.cast, blocks: effectiveFlowForAI)
            let suggested = try await autoWriter(effective)
            pendingSuggestions = suggested.prefix(10).map { suggestion in
                let speaker = content.cast.first {
                    $0.name.localizedCaseInsensitiveContains(suggestion.speakerName ?? "")
                        && !(suggestion.speakerName ?? "").isEmpty
                }
                return ScenarioBlock(
                    kind: suggestion.isInstruction ? .instruction : .line,
                    speakerIDs: speaker.map { [$0.id] } ?? [],
                    text: suggestion.text
                )
            }
        } catch {
            pendingSuggestions = []
        }
    }

    public func acceptSuggestion(_ block: ScenarioBlock) {
        withActiveBlocks { $0.append(block) }
        pendingSuggestions.removeAll { $0.id == block.id }
    }

    public func acceptAllSuggestions() {
        let blocks = pendingSuggestions
        withActiveBlocks { $0.append(contentsOf: blocks) }
        pendingSuggestions = []
    }

    public func dismissSuggestions() {
        pendingSuggestions = []
    }
}
