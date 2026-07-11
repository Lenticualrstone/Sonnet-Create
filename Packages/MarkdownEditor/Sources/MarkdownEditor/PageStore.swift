import AppCore
import DocumentKit
import Foundation
import Observation

/// 블록형 마크다운 페이지 에디터의 상태/로직. 캐릭터 페이지(.scpa, character)도 함께 담당한다.
@MainActor
@Observable
public final class PageStore {
    public private(set) var content: PageContent
    public var onContentChanged: ((PageContent) -> Void)?

    /// 뷰가 포커스를 옮겨야 할 블록
    public var focusRequest: UUID?
    /// '/' 커맨드 메뉴가 붙을 블록
    public var slashBlockID: UUID?
    /// '/' 메뉴에서 키보드(↑↓)로 선택 중인 항목 인덱스
    public var slashSelectionIndex: Int = 0

    /// 리소스 경로(번들 상대) → 실제 URL 해석 (앱이 주입)
    public var resourceResolver: ((String) -> URL?)?
    /// 외부 파일 → 번들 리소스 복사 후 상대 경로 반환 (앱이 주입)
    public var resourceImporter: ((URL) -> String?)?
    /// 같은 프로젝트의 다른 캐릭터 페이지 목록 — 관계 탭용 (앱이 주입)
    public var characterCatalog: (() -> [(id: UUID, name: String)])?
    /// 이 캐릭터의 등장 기록 (시나리오 제목, 대사 수) — 보조 표시용 (앱이 주입)
    public var appearanceStats: (() -> [(title: String, lineCount: Int)])?
    /// 다른 문서 열기 (관계 노드 클릭 등, 앱이 주입)
    public var onOpenDocument: ((UUID) -> Void)?

    private var undoStack: [PageContent] = []
    private var redoStack: [PageContent] = []
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public init(content: PageContent) {
        var normalized = content
        if normalized.blocks.isEmpty {
            normalized.blocks = [PageBlock(kind: .paragraph)]
        }
        self.content = normalized
    }

    public var isCharacterPage: Bool { content.profile != nil }

    private func mutate(_ transform: (inout PageContent) -> Void) {
        undoStack.append(content)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
        transform(&content)
        onContentChanged?(content)
    }

    /// 스냅샷 복원 등 콘텐츠 전면 교체 — 되돌리기 스택에 남는 단일 작업.
    public func replaceContent(_ newContent: PageContent) {
        mutate { $0 = newContent }
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(content)
        content = previous
        onContentChanged?(content)
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(content)
        content = next
        onContentChanged?(content)
    }

    // MARK: 표시 블록 (토글 접힘 반영)

    public var visibleBlocks: [PageBlock] {
        var result: [PageBlock] = []
        var hideDeeperThan: Int?
        for block in content.blocks {
            if let threshold = hideDeeperThan {
                if block.indent > threshold { continue }
                hideDeeperThan = nil
            }
            result.append(block)
            if block.kind == .toggle, !block.isExpanded {
                hideDeeperThan = block.indent
            }
        }
        return result
    }

    public func block(id: UUID) -> PageBlock? {
        content.blocks.first { $0.id == id }
    }

    private func index(of id: UUID) -> Int? {
        content.blocks.firstIndex { $0.id == id }
    }

    private func index(of id: UUID, in blocks: [PageBlock]) -> Int? {
        blocks.firstIndex { $0.id == id }
    }

    // MARK: 텍스트 편집 + '/' 감지

    public func updateText(_ id: UUID, text: String) {
        guard let idx = index(of: id) else { return }

        // Notion식 마크다운 자동 변환 ("# ", "- ", "1. ", "[] ", "> ", "```", "---")
        if autoConvertMarkdown(at: idx, id: id, text: text) { return }

        // 타이핑 단위 undo는 과하므로 직접 갱신 (블록 구조 변경만 undo 대상)
        content.blocks[idx].text = text
        onContentChanged?(content)

        if text.hasPrefix("/") {
            slashBlockID = id
            slashSelectionIndex = 0 // 쿼리가 바뀌면 첫 항목부터
        } else if slashBlockID == id {
            slashBlockID = nil
        }
    }

    /// 줄 시작 마크다운 문법을 블록 타입으로 자동 변환. 변환했으면 true.
    private func autoConvertMarkdown(at idx: Int, id: UUID, text: String) -> Bool {
        guard content.blocks[idx].kind == .paragraph else { return false }

        let prefixMap: [(String, PageBlockKind)] = [
            ("# ", .heading1), ("## ", .heading2), ("### ", .heading3),
            ("- ", .bulleted), ("* ", .bulleted), ("+ ", .bulleted),
            ("1. ", .numbered),
            ("[] ", .task), ("[ ] ", .task),
            ("> ", .quote),
            ("``` ", .code), ("```", .code),
        ]
        // 정확히 "문법+공백"만 입력된 순간 변환 (뒤에 내용이 있으면 일반 텍스트로 취급)
        for (prefix, kind) in prefixMap where text == prefix {
            mutate { c in
                c.blocks[idx].kind = kind
                c.blocks[idx].text = ""
            }
            focusRequest = id
            return true
        }
        if text == "---" || text == "***" {
            let newBlock = PageBlock(kind: .paragraph, indent: content.blocks[idx].indent)
            mutate { c in
                c.blocks[idx].kind = .divider
                c.blocks[idx].text = ""
                c.blocks.insert(newBlock, at: idx + 1)
            }
            focusRequest = newBlock.id
            return true
        }
        return false
    }

    public var slashQuery: String {
        guard let id = slashBlockID, let block = block(id: id), block.text.hasPrefix("/") else { return "" }
        return String(block.text.dropFirst())
    }

    /// '/' 메뉴에서 블록 타입 선택 → 변환.
    public func applySlashCommand(_ kind: PageBlockKind) {
        guard let id = slashBlockID else { return }
        mutate { c in
            guard let idx = c.blocks.firstIndex(where: { $0.id == id }) else { return }
            c.blocks[idx].kind = kind
            c.blocks[idx].text = ""
        }
        slashBlockID = nil
        focusRequest = id
    }

    public func closeSlashMenu() {
        slashBlockID = nil
    }

    // MARK: 블록 구조 조작

    /// Enter — 아래에 새 블록 생성 (리스트류는 같은 타입 유지).
    public func insertBlock(after id: UUID) {
        guard let idx = index(of: id) else { return }
        let current = content.blocks[idx]
        let continuingKinds: Set<PageBlockKind> = [.bulleted, .numbered, .task]
        // 빈 리스트 블록에서 Enter → 본문으로 전환 (Notion 관례)
        if continuingKinds.contains(current.kind), current.text.isEmpty {
            mutate { $0.blocks[idx].kind = .paragraph }
            focusRequest = id
            return
        }
        let newKind: PageBlockKind = continuingKinds.contains(current.kind) ? current.kind : .paragraph
        let newBlock = PageBlock(kind: newKind, indent: current.indent)
        mutate { $0.blocks.insert(newBlock, at: idx + 1) }
        focusRequest = newBlock.id
    }

    /// 빈 블록에서 Backspace — 블록 삭제 후 이전 블록으로 포커스 (병합).
    public func removeBlockFocusPrevious(_ id: UUID) {
        guard let idx = index(of: id), content.blocks.count > 1 else { return }
        let previousID = idx > 0 ? content.blocks[idx - 1].id : nil
        mutate { $0.blocks.remove(at: idx) }
        focusRequest = previousID ?? content.blocks.first?.id
        if slashBlockID == id { slashBlockID = nil }
    }

    /// 블록 전체 교체 (이미지 경로/비율, 표 데이터 등 구조적 속성 변경).
    public func updateBlock(_ block: PageBlock) {
        mutate { c in
            guard let idx = c.blocks.firstIndex(where: { $0.id == block.id }) else { return }
            c.blocks[idx] = block
        }
    }

    public func convert(_ id: UUID, to kind: PageBlockKind) {
        mutate { c in
            guard let idx = c.blocks.firstIndex(where: { $0.id == id }) else { return }
            c.blocks[idx].kind = kind
        }
    }

    public func indent(_ id: UUID) {
        mutate { c in
            guard let idx = c.blocks.firstIndex(where: { $0.id == id }) else { return }
            c.blocks[idx].indent = min(5, c.blocks[idx].indent + 1)
        }
    }

    public func outdent(_ id: UUID) {
        mutate { c in
            guard let idx = c.blocks.firstIndex(where: { $0.id == id }) else { return }
            c.blocks[idx].indent = max(0, c.blocks[idx].indent - 1)
        }
    }

    public func toggleCheck(_ id: UUID) {
        mutate { c in
            guard let idx = c.blocks.firstIndex(where: { $0.id == id }) else { return }
            c.blocks[idx].isChecked.toggle()
        }
    }

    public func toggleExpand(_ id: UUID) {
        mutate { c in
            guard let idx = c.blocks.firstIndex(where: { $0.id == id }) else { return }
            c.blocks[idx].isExpanded.toggle()
        }
    }

    public func deleteBlock(_ id: UUID) {
        guard content.blocks.count > 1 else { return }
        mutate { $0.blocks.removeAll { $0.id == id } }
    }

    public func duplicateBlock(_ id: UUID) {
        mutate { c in
            guard let idx = c.blocks.firstIndex(where: { $0.id == id }) else { return }
            var copy = c.blocks[idx]
            copy = PageBlock(
                kind: copy.kind, text: copy.text, isChecked: copy.isChecked,
                indent: copy.indent, isExpanded: copy.isExpanded
            )
            c.blocks.insert(copy, at: idx + 1)
        }
    }

    /// visibleBlocks 기준 onMove → 실제 배열 인덱스로 매핑해 이동.
    public func moveVisibleBlocks(from source: IndexSet, to destination: Int) {
        let visible = visibleBlocks
        guard let sourceVisibleIndex = source.first, sourceVisibleIndex < visible.count else { return }
        let movingID = visible[sourceVisibleIndex].id
        guard let actualSource = index(of: movingID) else { return }

        let actualDestination: Int
        if destination >= visible.count {
            actualDestination = content.blocks.count
        } else {
            guard let idx = index(of: visible[destination].id) else { return }
            actualDestination = idx
        }
        mutate { $0.blocks.move(fromOffsets: IndexSet(integer: actualSource), toOffset: actualDestination) }
    }

    // MARK: 커스텀 드래그 재정렬 (블록 ID 기반)

    /// draggedID를 targetID 바로 앞으로 옮긴다.
    public func moveBlock(_ draggedID: UUID, before targetID: UUID) {
        guard draggedID != targetID, let sourceIndex = index(of: draggedID) else { return }
        mutate { c in
            let block = c.blocks.remove(at: sourceIndex)
            guard let targetIndex = self.index(of: targetID, in: c.blocks) else {
                c.blocks.insert(block, at: sourceIndex)
                return
            }
            c.blocks.insert(block, at: targetIndex)
        }
    }

    /// draggedID를 targetID 바로 뒤로 옮긴다.
    public func moveBlock(_ draggedID: UUID, after targetID: UUID) {
        guard draggedID != targetID, let sourceIndex = index(of: draggedID) else { return }
        mutate { c in
            let block = c.blocks.remove(at: sourceIndex)
            guard let targetIndex = self.index(of: targetID, in: c.blocks) else {
                c.blocks.insert(block, at: sourceIndex)
                return
            }
            c.blocks.insert(block, at: targetIndex + 1)
        }
    }

    /// draggedID를 문서 맨 끝으로 옮긴다 (하단 빈 영역에 드롭).
    public func moveBlockToEnd(_ draggedID: UUID) {
        guard let sourceIndex = index(of: draggedID) else { return }
        mutate { c in
            let block = c.blocks.remove(at: sourceIndex)
            c.blocks.append(block)
        }
    }

    /// numbered 블록의 표시 번호 (같은 indent에서 연속된 numbered 나열 기준).
    public func numberedIndex(of id: UUID) -> Int {
        guard let idx = index(of: id) else { return 1 }
        let target = content.blocks[idx]
        var count = 1
        var i = idx - 1
        while i >= 0 {
            let prev = content.blocks[i]
            if prev.kind == .numbered, prev.indent == target.indent {
                count += 1
                i -= 1
            } else if prev.indent > target.indent {
                i -= 1
            } else {
                break
            }
        }
        return count
    }

    // MARK: 프로필 (캐릭터 페이지)

    public func updateProfile(_ transform: (inout CharacterProfile) -> Void) {
        mutate { c in
            var profile = c.profile ?? CharacterProfile()
            transform(&profile)
            c.profile = profile
        }
    }

    // MARK: Markdown Import/Export

    public func exportMarkdown() -> String {
        PageMarkdown.export(content.blocks)
    }

    public func importMarkdown(_ text: String) {
        let imported = PageMarkdown.import(text)
        guard !imported.isEmpty else { return }
        mutate { $0.blocks = imported }
    }
}
