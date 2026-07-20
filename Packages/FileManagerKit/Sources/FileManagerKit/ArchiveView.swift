import AppCore
import AppKit
import DesignSystem
import DocumentKit
import SwiftUI

/// 파일 아카이브 — 유형별 카테고리 · 프로젝트 필터 · 락업 리스트 · 아이콘 그리드 · 정렬/보기 도구막대.
/// 가리기/휴지통 섹션은 인증 게이트(주입)로 보호된다. 리스트뷰에서는 Cmd/Shift 클릭으로 다중 선택이 가능하다.
public struct ArchiveView: View {
    public enum Category: String, CaseIterable, Identifiable {
        case all, scenario, mindmap, page, character, other, hidden, trash

        public var id: String { rawValue }
    }

    public enum SortOrder: String, CaseIterable, Identifiable {
        case modified, name, kind, trashedDate

        public var id: String { rawValue }
    }

    /// 외부에서 카테고리+프로젝트 필터를 한 번에 지정해 열 때 쓰는 목적지. 두 값을 하나의 옵셔널로
    /// 묶어야 "프로젝트 필터를 명시적으로 전체(nil)로 되돌리기"와 "요청 없음"을 구분할 수 있다.
    public struct ArchiveNavigationTarget: Equatable {
        public var category: Category
        public var projectID: UUID?

        public init(category: Category, projectID: UUID? = nil) {
            self.category = category
            self.projectID = projectID
        }
    }

    /// 리스트/그리드에 그려지는 통합 항목 — 문서 또는 보기 전용 기타 파일.
    enum ArchiveEntry: Identifiable, Equatable {
        case document(DocumentListItem)
        case other(OtherFileItem)

        var id: String {
            switch self {
            case .document(let item): item.id.uuidString
            case .other(let item): item.id
            }
        }
    }

    @Bindable var workspace: WorkspaceStore
    let onOpen: (DocumentListItem) -> Void
    /// 보호 섹션 접근 시 호출 — true 반환 시 접근 허용
    let requestUnlock: (String) async -> Bool
    /// 열기 클릭 방식 (설정 연동: true = 싱글 클릭)
    let openOnSingleClick: Bool
    /// 외부(사이드바 바로가기, 프로젝트 우클릭 메뉴, 뒤로/앞으로 탐색 등)에서 카테고리+프로젝트를
    /// 한 번에 지정해 열 때 (소비 후 nil로 되돌림)
    @Binding var externalTarget: ArchiveNavigationTarget?
    /// 휴지통 이동 요청(단건/다건 공용) — nil이면 즉시 이동, 지정 시 앱이 확인 팝업을 거친다
    let requestTrash: (([DocumentListItem]) -> Void)?
    /// 영구 삭제 요청(단건/다건 공용) — nil이면 즉시 삭제, 지정 시 앱이 확인 팝업을 거친다
    let requestPermanentDelete: (([DocumentListItem]) -> Void)?
    /// PrivacyGate가 이미 이번 세션에 잠금 해제된 상태인지 — 참이면 카테고리 전환 시 잠금 화면이 깜빡이지 않는다
    let isSessionUnlocked: Bool
    /// 복원 시 원래 위치가 사라져 최상위로 대신 복원됐을 때 호출 (사용자 알림용)
    let onRestoreFallback: (() -> Void)?
    /// 카테고리/프로젝트 필터가 바뀔 때마다 호출 — 뒤로/앞으로 탐색 히스토리 기록용
    let onNavigate: ((Category, UUID?) -> Void)?
    /// 빈 카테고리의 빠른 생성 버튼 — 앱이 컨텍스트 프로젝트를 반영해 생성한다
    let onCreate: ((DocumentKind, PageRole?) -> Void)?

    @State private var category: Category = .all
    @State private var sortOrder: SortOrder = .modified
    @State private var isGrid = false
    @State private var query = ""
    @State private var unlockGranted = false
    @State private var projectFilter: UUID?
    @State private var selection: Set<String> = []
    @State private var lastSelectedID: String?
    /// 키보드 탐색 포커스 (↑↓ 이동, ⏎ 열기) — 마우스 선택과 독립
    @State private var keyFocusID: String?
    /// 리스트가 키보드 포커스를 갖고 있는지 (.focusable + FocusState)
    @FocusState private var listFocused: Bool

    @Environment(\.renderQuality) private var quality
    @Environment(\.resolvedAccent) private var accent
    /// 카테고리 칩의 선택 하이라이트가 칩 사이를 미끄러지게 하는 네임스페이스
    @Namespace private var categoryHighlight

    public init(
        workspace: WorkspaceStore,
        onOpen: @escaping (DocumentListItem) -> Void,
        requestUnlock: @escaping (String) async -> Bool = { _ in true },
        openOnSingleClick: Bool = true,
        externalTarget: Binding<ArchiveNavigationTarget?> = .constant(nil),
        requestTrash: (([DocumentListItem]) -> Void)? = nil,
        requestPermanentDelete: (([DocumentListItem]) -> Void)? = nil,
        isSessionUnlocked: Bool = false,
        onRestoreFallback: (() -> Void)? = nil,
        onNavigate: ((Category, UUID?) -> Void)? = nil,
        onCreate: ((DocumentKind, PageRole?) -> Void)? = nil
    ) {
        self.workspace = workspace
        self.onOpen = onOpen
        self.requestUnlock = requestUnlock
        self.openOnSingleClick = openOnSingleClick
        _externalTarget = externalTarget
        self.requestTrash = requestTrash
        self.requestPermanentDelete = requestPermanentDelete
        self.isSessionUnlocked = isSessionUnlocked
        self.onRestoreFallback = onRestoreFallback
        self.onNavigate = onNavigate
        self.onCreate = onCreate
    }

    public var body: some View {
        let l10n = Localizer.shared
        // 4a — 좌측 카테고리 열 + 우측 콘텐츠 (상단 칩 필터에서 재배치)
        HStack(spacing: 0) {
            categorySidebar(l10n)
                .frame(width: 188)
            Divider().opacity(0.4)
            VStack(spacing: 0) {
                toolbar(l10n)
                Divider().opacity(0.4)
                if category == .hidden, unlockGranted {
                    Text(l10n.t(.hideFinderHint))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, DesignTokens.Spacing.m)
                        .padding(.top, 4)
                }
                selectionBar(l10n)
                if isProtected, !unlockGranted {
                    lockedPlaceholder(l10n)
                } else if category == .all {
                    if overviewSections.isEmpty, otherItems.isEmpty {
                        emptyPlaceholder(l10n)
                    } else {
                        overviewView
                    }
                } else if entries.isEmpty {
                    emptyPlaceholder(l10n)
                } else if isGrid {
                    gridView
                } else {
                    listView
                }
            }
        }
        .onChange(of: category) { _, newValue in
            selection = []
            onNavigate?(category, projectFilter)
            guard newValue == .hidden || newValue == .trash else {
                unlockGranted = false
                return
            }
            if isSessionUnlocked {
                unlockGranted = true
                return
            }
            Task {
                let l10n = Localizer.shared
                unlockGranted = await requestUnlock(l10n.t(.authReason))
            }
        }
        .onChange(of: isGrid) { _, _ in selection = [] }
        .onChange(of: projectFilter) { _, _ in
            selection = []
            onNavigate?(category, projectFilter)
        }
        .onAppear {
            consumeExternalTarget()
            if isProtected, isSessionUnlocked { unlockGranted = true }
        }
        .onChange(of: externalTarget) { _, _ in consumeExternalTarget() }
        .animation(DesignTokens.Motion.snappy, value: selection.isEmpty)
    }

    private func consumeExternalTarget() {
        if let requested = externalTarget {
            category = requested.category
            projectFilter = requested.projectID
            externalTarget = nil
        }
    }

    private var isProtected: Bool {
        category == .hidden || category == .trash
    }

    // MARK: 필터링/정렬

    private var items: [DocumentListItem] {
        documents(for: category)
    }

    /// 특정 카테고리 기준 문서 목록 (프로젝트 필터/검색/정렬 공용 적용). 개요(전체) 화면이 여러
    /// 카테고리를 동시에 조회할 수 있도록 `category` 상태와 분리해 파라미터로 받는다.
    private func documents(for cat: Category) -> [DocumentListItem] {
        var base: [DocumentListItem] = switch cat {
        case .all: workspace.visibleDocuments
        case .scenario: workspace.visibleDocuments.filter { $0.envelope.kind == .scenario }
        case .mindmap: workspace.visibleDocuments.filter { $0.envelope.kind == .mindmap }
        case .page: workspace.visibleDocuments.filter { $0.envelope.kind == .page && !$0.envelope.isCharacterPage }
        case .character: workspace.visibleDocuments.filter { $0.envelope.isCharacterPage }
        case .other: []
        case .hidden: workspace.hiddenDocuments
        case .trash: workspace.trashedDocuments
        }
        if let projectFilter {
            base = base.filter { $0.envelope.projectID == projectFilter }
        }
        if !query.isEmpty {
            base = base.filter { $0.envelope.title.localizedCaseInsensitiveContains(query) }
        }
        return switch sortOrder {
        case .modified: base.sorted { $0.envelope.modifiedAt > $1.envelope.modifiedAt }
        case .name: base.sorted { $0.envelope.title.localizedCompare($1.envelope.title) == .orderedAscending }
        case .kind: base.sorted { $0.envelope.kind.rawValue < $1.envelope.kind.rawValue }
        case .trashedDate:
            base.sorted { ($0.envelope.trashedAt ?? $0.envelope.modifiedAt) > ($1.envelope.trashedAt ?? $1.envelope.modifiedAt) }
        }
    }

    /// '전체' 카테고리에서 종류별로 묶어 보여줄 섹션 목록 (비어있지 않은 것만).
    private var overviewSections: [(Category, [DocumentListItem])] {
        [Category.scenario, .mindmap, .page, .character].compactMap { cat in
            let docs = documents(for: cat)
            return docs.isEmpty ? nil : (cat, docs)
        }
    }

    private var otherItems: [OtherFileItem] {
        var files = workspace.otherFiles
        if let projectFilter {
            files = files.filter { $0.projectID == projectFilter }
        }
        if !query.isEmpty {
            files = files.filter { $0.filename.localizedCaseInsensitiveContains(query) }
        }
        return files
    }

    private var entries: [ArchiveEntry] {
        if category == .other {
            return otherItems.map { .other($0) }
        }
        return items.map { .document($0) }
    }

    private var selectedDocuments: [DocumentListItem] {
        entries.compactMap { entry in
            guard case .document(let item) = entry, selection.contains(entry.id) else { return nil }
            return item
        }
    }

    private func categoryLabel(_ c: Category, _ l10n: Localizer) -> String {
        switch c {
        case .all: l10n.t(.allDocuments)
        case .scenario: l10n.t(.scenario)
        case .mindmap: l10n.t(.mindmap)
        case .page: l10n.t(.page)
        case .character: l10n.t(.characterPage)
        case .other: l10n.t(.otherFiles)
        case .hidden: l10n.t(.hiddenItems)
        case .trash: l10n.t(.trashItems)
        }
    }

    // MARK: 카테고리 사이드바 (4a)

    /// 카테고리별 항목 수 — 사이드바 카운트 배지.
    private func categoryCount(_ cat: Category) -> Int {
        switch cat {
        case .other: otherItems.count
        default: documentsUnfiltered(for: cat).count
        }
    }

    /// 프로젝트 필터/검색과 무관한 원 카운트 (사이드바 배지용).
    private func documentsUnfiltered(for cat: Category) -> [DocumentListItem] {
        switch cat {
        case .all: workspace.visibleDocuments
        case .scenario: workspace.visibleDocuments.filter { $0.envelope.kind == .scenario }
        case .mindmap: workspace.visibleDocuments.filter { $0.envelope.kind == .mindmap }
        case .page: workspace.visibleDocuments.filter { $0.envelope.kind == .page && !$0.envelope.isCharacterPage }
        case .character: workspace.visibleDocuments.filter { $0.envelope.isCharacterPage }
        case .other: []
        case .hidden: workspace.hiddenDocuments
        case .trash: workspace.trashedDocuments
        }
    }

    private func categorySidebar(_ l10n: Localizer) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(l10n.t(.categorySection))
                .font(DSFonts.font(size: 11, weight: .semibold, family: .pretendard))
                .kerning(0.8)
                .foregroundStyle(SonnetPalette.inkMuted)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 6)

            ForEach([Category.all, .scenario, .mindmap, .page, .character, .other]) { candidate in
                categoryRow(candidate, l10n)
            }

            Spacer(minLength: 0)

            Divider().opacity(0.35)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)

            // 보호 구역 — 가려진 파일은 Touch ID 게이트
            categoryRow(.hidden, l10n, trailingSymbol: "touchid")
            categoryRow(.trash, l10n)
                .padding(.bottom, 10)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(SonnetPalette.sunken.opacity(0.45))
    }

    @ViewBuilder
    private func categoryRow(_ candidate: Category, _ l10n: Localizer, trailingSymbol: String? = nil) -> some View {
        let isSelected = category == candidate
        let count = categoryCount(candidate)
        Button {
            withAnimation(DesignTokens.Motion.glassPop) { category = candidate }
        } label: {
            HStack(spacing: 8) {
                categoryIcon(candidate)
                    .frame(width: 16)
                Text(categoryLabel(candidate, l10n))
                    .font(DSFonts.font(size: 13, weight: isSelected ? .semibold : .regular, family: .pretendard))
                    .foregroundStyle(isSelected ? SonnetPalette.ink : SonnetPalette.inkSoft)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .font(.system(size: 11))
                        .foregroundStyle(SonnetPalette.inkMuted)
                } else if count > 0 {
                    Text("\(count)")
                        .font(DSFonts.font(size: 11, family: .pretendard))
                        .foregroundStyle(SonnetPalette.inkMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(SonnetPalette.accentTint)
                        .matchedGeometryEffect(id: "archiveCategoryHighlight", in: categoryHighlight)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func categoryIcon(_ candidate: Category) -> some View {
        switch candidate {
        case .all:
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 12))
                .foregroundStyle(SonnetPalette.inkMuted)
        case .scenario: FileTypeIcon(.scenario, size: 14)
        case .mindmap: FileTypeIcon(.mindmap, size: 14)
        case .page: FileTypeIcon(.page, size: 14)
        case .character: FileTypeIcon(.character, size: 14)
        case .other: FileTypeIcon(.attachment, size: 14)
        case .hidden:
            Image(systemName: "eye.slash")
                .font(.system(size: 12))
                .foregroundStyle(SonnetPalette.inkMuted)
        case .trash:
            Image(systemName: "trash")
                .font(.system(size: 12))
                .foregroundStyle(SonnetPalette.inkMuted)
        }
    }

    // MARK: 도구막대

    private func toolbar(_ l10n: Localizer) -> some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            if !workspace.projects.isEmpty {
                projectFilterMenu(l10n)
            }

            Spacer()

            SearchCapsule(text: $query, placeholder: l10n.t(.searchPlaceholder), quality: quality)

            Menu {
                Picker(l10n.t(.sortBy), selection: $sortOrder) {
                    Text(l10n.t(.sortModified)).tag(SortOrder.modified)
                    Text(l10n.t(.sortName)).tag(SortOrder.name)
                    Text(l10n.t(.sortKind)).tag(SortOrder.kind)
                    Text(l10n.t(.sortTrashedDate)).tag(SortOrder.trashedDate)
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if !isGrid, category != .other, category != .all, !items.isEmpty {
                ToolbarIconButton("checkmark.circle", help: l10n.t(.selectAll)) {
                    selection = Set(items.map { $0.id.uuidString })
                }
            }

            if category == .trash, !workspace.trashedDocuments.isEmpty {
                ToolbarIconButton("trash.slash", help: l10n.t(.emptyTrashAction)) {
                    let all = workspace.trashedDocuments
                    if let requestPermanentDelete {
                        requestPermanentDelete(all)
                    } else {
                        workspace.emptyTrash()
                    }
                }
            }

            if category != .all {
                ToolbarIconButton(
                    isGrid ? "list.bullet" : "square.grid.2x2",
                    help: isGrid ? l10n.t(.viewList) : l10n.t(.viewGrid)
                ) { isGrid.toggle() }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.vertical, DesignTokens.Spacing.s)
    }

    // MARK: 다중 선택 액션바

    @ViewBuilder
    private func selectionBar(_ l10n: Localizer) -> some View {
        if !selection.isEmpty {
            HStack(spacing: DesignTokens.Spacing.s) {
                Text(String(format: l10n.t(.selectedCountFormat), selection.count))
                    .font(.callout.weight(.medium))
                Spacer()
                if category == .trash {
                    Button(l10n.t(.restore)) { bulkRestore() }
                    Button(l10n.t(.permanentDelete), role: .destructive) { bulkPermanentDelete() }
                } else {
                    if category == .hidden {
                        Button(l10n.t(.unhide)) { bulkHide(false) }
                    } else {
                        Button(l10n.t(.hide)) { bulkHide(true) }
                    }
                    Button(l10n.t(.moveToTrash), role: .destructive) { bulkMoveToTrash() }
                }
                Button(l10n.t(.deselectAll)) { selection = [] }
            }
            .padding(.horizontal, DesignTokens.Spacing.m)
            .padding(.vertical, DesignTokens.Spacing.s)
            .background(Color.primary.opacity(0.05))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func bulkHide(_ hidden: Bool) {
        for item in selectedDocuments { workspace.setHidden(item, hidden: hidden) }
        selection = []
    }

    /// 다중 휴지통 이동 — 개별 이동과 같은 확인 경로(requestTrash)를 쓴다. 즉시 실행하지 않는다.
    private func bulkMoveToTrash() {
        let docs = selectedDocuments
        selection = []
        if let requestTrash {
            requestTrash(docs)
        } else {
            for item in docs { workspace.moveToTrash(item) }
        }
    }

    private func bulkRestore() {
        var fellBack = false
        for item in selectedDocuments where workspace.restoreFromTrash(item) { fellBack = true }
        selection = []
        if fellBack { onRestoreFallback?() }
    }

    private func bulkPermanentDelete() {
        let docs = selectedDocuments
        selection = []
        if let requestPermanentDelete {
            requestPermanentDelete(docs)
        } else {
            workspace.deletePermanently(docs)
        }
    }

    private func toggleSelection(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        lastSelectedID = id
    }

    private func extendSelection(to id: String) {
        guard let last = lastSelectedID,
              let lastIdx = entries.firstIndex(where: { $0.id == last }),
              let idx = entries.firstIndex(where: { $0.id == id })
        else {
            toggleSelection(id)
            return
        }
        let range = lastIdx <= idx ? lastIdx...idx : idx...lastIdx
        for entry in entries[range] {
            if case .document = entry { selection.insert(entry.id) }
        }
        lastSelectedID = id
    }

    private func replaceSelection(with id: String) {
        selection = [id]
        lastSelectedID = id
    }

    private func lockedPlaceholder(_ l10n: Localizer) -> some View {
        VStack(spacing: DesignTokens.Spacing.m) {
            Image(systemName: "touchid")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(category == .hidden ? l10n.t(.authRequiredHidden) : l10n.t(.authRequiredTrash))
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                Task {
                    unlockGranted = await requestUnlock(l10n.t(.authReason))
                }
            } label: {
                Text(l10n.t(.unlocked))
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyPlaceholder(_ l10n: Localizer) -> some View {
        VStack(spacing: DesignTokens.Spacing.s) {
            Image(systemName: category == .trash ? "trash" : (category == .hidden ? "eye.slash" : "tray"))
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(emptyMessage(l10n))
                .font(.callout)
                .foregroundStyle(.secondary)

            // 빈 문서 카테고리에서는 바로 만들 수 있게 — 목적지(프로젝트 필터)도 따라간다
            if query.isEmpty, let creation = emptyCreationTarget, let onCreate {
                Button {
                    onCreate(creation.kind, creation.role)
                } label: {
                    Label(l10n.t(creation.labelKey), systemImage: "plus")
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 빈 카테고리에서 제안할 생성 대상 — 문서 종류 카테고리에서만.
    private var emptyCreationTarget: (kind: DocumentKind, role: PageRole?, labelKey: L10nKey)? {
        switch category {
        case .scenario: (.scenario, nil, .newScenario)
        case .mindmap: (.mindmap, nil, .newMindMap)
        case .page: (.page, nil, .newPage)
        case .character: (.page, .character, .newCharacter)
        default: nil
        }
    }

    private func emptyMessage(_ l10n: Localizer) -> String {
        guard query.isEmpty else { return l10n.t(.noRecents) }
        switch category {
        case .hidden: return l10n.t(.emptyHiddenItems)
        case .trash: return l10n.t(.emptyTrashItems)
        case .other: return l10n.t(.emptyOtherFiles)
        default: return l10n.t(.emptyCategory)
        }
    }

    // MARK: 리스트 (락업)

    // List 대신 ScrollView+LazyVStack — List의 내부 NSTableView가 방향키를 소비해
    // .onMoveCommand가 동작하지 않는다. 멀티선택/컨텍스트 메뉴는 행 내부에서 처리하므로
    // List 스타일에 의존하지 않아 안전하게 대체된다.
    private var listView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(entries) { entry in
                        switch entry {
                        case .document(let item):
                            ArchiveRow(
                                item: item,
                                clickCount: openOnSingleClick ? 1 : 2,
                                isSelected: selection.contains(entry.id),
                                isKeyFocused: keyFocusID == entry.id,
                                hasSelection: !selection.isEmpty,
                                showTrashMeta: category == .trash,
                                originLabel: category == .trash ? workspace.trashOriginLabel(for: item) : nil,
                                onOpen: onOpen,
                                onToggleSelect: { toggleSelection(entry.id) },
                                onExtendSelect: { extendSelection(to: entry.id) },
                                onReplaceSelect: { replaceSelection(with: entry.id) }
                            )
                            .id(entry.id)
                            .contextMenu { contextMenu(for: item) }
                        case .other(let file):
                            OtherFileRow(item: file)
                                .id(entry.id)
                                .contextMenu { otherContextMenu(for: file) }
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.s)
                .padding(.vertical, 4)
            }
            // 키보드 탐색 — ↑↓로 이동(스크롤 대신 포커스 이동), ⏎ 열기, ⎋ 해제.
            // onMoveCommand는 ScrollView 스크롤에 가로채이므로 onKeyPress로 직접 처리하고
            // .handled를 반환해 기본 스크롤을 막는다. 뷰가 나타나면 자동 포커스.
            .focusable()
            .focused($listFocused)
            .onAppear { listFocused = true }
            .onKeyPress(.downArrow) {
                moveKeyFocus(delta: 1, proxy: proxy)
                return .handled
            }
            .onKeyPress(.upArrow) {
                moveKeyFocus(delta: -1, proxy: proxy)
                return .handled
            }
            .onKeyPress(.return) {
                openKeyFocused()
                return keyFocusID != nil ? .handled : .ignored
            }
            .onExitCommand {
                keyFocusID = nil
            }
        }
    }

    /// 방향키로 포커스 행 이동 (delta: +1 아래 / -1 위) — 이동 후 해당 행으로 스크롤.
    private func moveKeyFocus(delta: Int, proxy: ScrollViewProxy) {
        let ids = entries.map(\.id)
        guard !ids.isEmpty else { return }
        guard let current = keyFocusID, let index = ids.firstIndex(of: current) else {
            keyFocusID = ids.first
            keyFocusID.map { proxy.scrollTo($0, anchor: .center) }
            return
        }
        let target = index + delta
        guard target >= 0, target < ids.count else { return }
        keyFocusID = ids[target]
        proxy.scrollTo(ids[target], anchor: .center)
    }

    /// 포커스된 문서 열기 (기타 파일이면 기본 앱으로).
    private func openKeyFocused() {
        guard let id = keyFocusID, let entry = entries.first(where: { $0.id == id }) else { return }
        switch entry {
        case .document(let item): onOpen(item)
        case .other(let file): NSWorkspace.shared.open(file.url)
        }
    }

    // MARK: 그리드 (아이콘)

    private var gridView: some View {
        ScrollView {
            // 카드 최소·최대 폭 지정 — 넓은 화면에서 카드가 늘어나 고립돼 보이지 않게 (4단계 아카이브)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150, maximum: 230), spacing: DesignTokens.Spacing.m)],
                spacing: DesignTokens.Spacing.m
            ) {
                ForEach(entries) { entry in
                    switch entry {
                    case .document(let item):
                        ArchiveCard(
                            item: item,
                            clickCount: openOnSingleClick ? 1 : 2,
                            showTrashMeta: category == .trash,
                            originLabel: category == .trash ? workspace.trashOriginLabel(for: item) : nil,
                            onOpen: onOpen
                        )
                        .contextMenu { contextMenu(for: item) }
                    case .other(let file):
                        OtherFileCard(item: file)
                            .contextMenu { otherContextMenu(for: file) }
                    }
                }
            }
            .padding(DesignTokens.Spacing.m)
        }
    }

    // MARK: 개요 ('전체' — 종류별 섹션을 한 화면에)

    private var overviewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                ForEach(overviewSections, id: \.0) { cat, docs in
                    overviewSection(cat, docs)
                }
                if !otherItems.isEmpty {
                    overviewOtherSection()
                }
            }
            .padding(DesignTokens.Spacing.m)
        }
    }

    private static let overviewCap = 8

    private func overviewSection(_ cat: Category, _ docs: [DocumentListItem]) -> some View {
        let l10n = Localizer.shared
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            HStack {
                Text(categoryLabel(cat, l10n))
                    .font(.headline)
                Spacer()
                Button(String(format: l10n.t(.showAllFormat), docs.count)) { category = cat }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.m) {
                    ForEach(docs.prefix(Self.overviewCap)) { item in
                        ArchiveCard(
                            item: item, clickCount: openOnSingleClick ? 1 : 2,
                            showTrashMeta: false, originLabel: nil, onOpen: onOpen
                        )
                        .frame(width: 140)
                        .contextMenu { contextMenu(for: item) }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func overviewOtherSection() -> some View {
        let l10n = Localizer.shared
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            HStack {
                Text(l10n.t(.otherFiles))
                    .font(.headline)
                Spacer()
                Button(String(format: l10n.t(.showAllFormat), otherItems.count)) { category = .other }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.m) {
                    ForEach(otherItems.prefix(Self.overviewCap)) { file in
                        OtherFileCard(item: file)
                            .frame(width: 140)
                            .contextMenu { otherContextMenu(for: file) }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: 컨텍스트 메뉴

    @ViewBuilder
    private func contextMenu(for item: DocumentListItem) -> some View {
        let l10n = Localizer.shared
        if item.envelope.isTrashed {
            Button(l10n.t(.restore)) {
                if workspace.restoreFromTrash(item) { onRestoreFallback?() }
            }
            Button(l10n.t(.permanentDelete), role: .destructive) {
                if let requestPermanentDelete {
                    requestPermanentDelete([item])
                } else {
                    workspace.deletePermanently(item)
                }
            }
        } else {
            Button(l10n.t(.open)) { onOpen(item) }
            Divider()
            if item.envelope.isHidden {
                Button(l10n.t(.unhide)) { workspace.setHidden(item, hidden: false) }
            } else {
                Button(l10n.t(.hide)) { workspace.setHidden(item, hidden: true) }
            }
            Button(l10n.t(.moveToTrash), role: .destructive) {
                if let requestTrash {
                    requestTrash([item])
                } else {
                    workspace.moveToTrash(item)
                }
            }
        }
    }

    @ViewBuilder
    private func otherContextMenu(for file: OtherFileItem) -> some View {
        let l10n = Localizer.shared
        Button(l10n.t(.open)) { NSWorkspace.shared.open(file.url) }
        Button(l10n.t(.revealInFinder)) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
    }
}

// MARK: - 행/카드

extension DocumentListItem {
    /// 디자인 시스템 파일 유형 (5a 아이콘/컬러 문법).
    var dsFileType: DSFileType {
        if envelope.isCharacterPage { return .character }
        switch envelope.kind {
        case .scenario: return .scenario
        case .mindmap: return .mindmap
        case .page: return .page
        }
    }
}

struct ArchiveRow: View {
    let item: DocumentListItem
    let clickCount: Int
    let isSelected: Bool
    var isKeyFocused: Bool = false
    let hasSelection: Bool
    let showTrashMeta: Bool
    let originLabel: String?
    let onOpen: (DocumentListItem) -> Void
    let onToggleSelect: () -> Void
    let onExtendSelect: () -> Void
    let onReplaceSelect: () -> Void

    @State private var hovering = false
    @Environment(\.resolvedAccent) private var accent

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            FileTypeIcon(item.dsFileType, size: 18)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.envelope.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let project = item.projectName {
                        Text(project)
                        Text("·")
                    }
                    if showTrashMeta, let trashedAt = item.envelope.trashedAt {
                        Text(Localizer.shared.t(.trashedOn))
                        Text(trashedAt, style: .relative)
                    } else {
                        Text(item.envelope.modifiedAt, style: .date)
                    }
                }
                // 수정일은 핵심 메타 — 최소 12pt (2단계 3)
                .font(DSFonts.font(size: 12, family: .pretendard))
                .foregroundStyle(.secondary)
                if showTrashMeta, let originLabel {
                    Text("\(Localizer.shared.t(.originalLocation)): \(originLabel)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(accent)
            }
            Text("." + item.envelope.kind.fileExtension)
                .font(DSType.mono(size: 10.5, weight: .semibold))
                .foregroundStyle(item.dsFileType.color)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .fill(isSelected ? accent.opacity(0.16) : (hovering ? Color.primary.opacity(0.06) : .clear))
        )
        // 키보드 포커스 링 — 마우스 선택과 구분되는 강조색 테두리
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .strokeBorder(accent, lineWidth: isKeyFocused ? 1.5 : 0)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // 별도의 simultaneousGesture로 Cmd/Shift 클릭을 감지하면 같은 뷰에 카운트가 다른
        // 탭 제스처 인식기 두 개가 경합해 더블클릭/열기 자체가 씹히는 문제가 있었다.
        // 하나의 제스처 안에서 수정키를 분기해 인식기 경합을 없앤다.
        .onTapGesture(count: clickCount) {
            let flags = NSEvent.modifierFlags
            if flags.contains(.command) {
                onToggleSelect()
                return
            }
            if flags.contains(.shift) {
                onExtendSelect()
                return
            }
            if clickCount == 1, hasSelection {
                onReplaceSelect()
                return
            }
            onOpen(item)
        }
        .animation(DesignTokens.Motion.snappy, value: hovering)
    }
}

struct ArchiveCard: View {
    let item: DocumentListItem
    let clickCount: Int
    let showTrashMeta: Bool
    let originLabel: String?
    let onOpen: (DocumentListItem) -> Void

    @State private var hovering = false
    @Environment(\.renderQuality) private var quality
    @Environment(\.resolvedAccent) private var accent

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.s) {
            FileTypeIcon(item.dsFileType, size: 34)
                .frame(height: 54)
            Text(item.envelope.title)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if showTrashMeta, let trashedAt = item.envelope.trashedAt {
                Text(trashedAt, style: .relative)
                    .font(DSFonts.font(size: 12, family: .pretendard))
                    .foregroundStyle(.secondary)
                if let originLabel {
                    Text(originLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            } else {
                // 수정일은 핵심 메타 — 최소 12pt (2단계 3)
                Text(item.envelope.modifiedAt, style: .date)
                    .font(DSFonts.font(size: 12, family: .pretendard))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DesignTokens.Spacing.m)
        .frame(maxWidth: .infinity)
        .glassSurface(cornerRadius: DesignTokens.Radius.medium, quality: quality)
        .scaleEffect(hovering ? 1.03 : 1)
        .shadow(color: .black.opacity(hovering ? 0.12 : 0), radius: hovering ? 8 : 0, y: hovering ? 3 : 0)
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(count: clickCount) { onOpen(item) }
        .animation(DesignTokens.Motion.snappy, value: hovering)
    }
}

// MARK: - 기타 파일 (보기 전용)

struct OtherFileRow: View {
    let item: OtherFileItem

    @State private var hovering = false

    private var symbolName: String {
        let ext = item.url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "svg", "tiff", "bmp"].contains(ext) { return "photo" }
        if ext == "pdf" { return "doc.richtext" }
        return "doc.text"
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.filename)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let project = item.projectName {
                        Text(project)
                        Text("·")
                    }
                    Text(item.modifiedAt, style: .date)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .help(Localizer.shared.t(.viewOnlyHint))
        .animation(DesignTokens.Motion.snappy, value: hovering)
    }
}

struct OtherFileCard: View {
    let item: OtherFileItem

    @State private var hovering = false
    @Environment(\.renderQuality) private var quality

    private var symbolName: String {
        let ext = item.url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "svg", "tiff", "bmp"].contains(ext) { return "photo" }
        if ext == "pdf" { return "doc.richtext" }
        return "doc.text"
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.s) {
            Image(systemName: symbolName)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
                .frame(height: 54)
            Text(item.filename)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(item.modifiedAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(DesignTokens.Spacing.m)
        .frame(maxWidth: .infinity)
        .glassSurface(cornerRadius: DesignTokens.Radius.medium, quality: quality)
        .scaleEffect(hovering ? 1.03 : 1)
        .shadow(color: .black.opacity(hovering ? 0.12 : 0), radius: hovering ? 8 : 0, y: hovering ? 3 : 0)
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .help(Localizer.shared.t(.viewOnlyHint))
        .animation(DesignTokens.Motion.snappy, value: hovering)
    }
}

// MARK: - 도구막대 필터 컨트롤 (칩/프로젝트 메뉴)

private extension ArchiveView {
    /// 프로젝트 필터 — 필터가 걸리면 강조색 캡슐로 표시되는 커스텀 메뉴.
    private func projectFilterMenu(_ l10n: Localizer) -> some View {
        let filteredName = projectFilter.flatMap { id in
            workspace.projects.first { $0.id == id }?.manifest.name
        }
        return Menu {
            Button {
                projectFilter = nil
            } label: {
                if projectFilter == nil {
                    Label(l10n.t(.allProjects), systemImage: "checkmark")
                } else {
                    Text(l10n.t(.allProjects))
                }
            }
            Divider()
            ForEach(workspace.projects) { project in
                Button {
                    projectFilter = project.id
                } label: {
                    if projectFilter == project.id {
                        Label(project.manifest.name, systemImage: "checkmark")
                    } else {
                        Text(project.manifest.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.caption)
                Text(filteredName ?? l10n.t(.allProjects))
                    .font(.callout)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(filteredName == nil ? Color.secondary : accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(filteredName == nil ? Color.primary.opacity(0.055) : accent.opacity(0.14))
            )
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
