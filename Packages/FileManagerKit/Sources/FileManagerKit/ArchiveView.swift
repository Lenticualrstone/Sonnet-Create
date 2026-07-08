import AppCore
import DesignSystem
import DocumentKit
import SwiftUI

/// 파일 아카이브 — 유형별 카테고리 · 락업 리스트 · 아이콘 그리드 · 정렬/보기 도구막대.
/// 가리기/휴지통 섹션은 인증 게이트(주입)로 보호된다.
public struct ArchiveView: View {
    public enum Category: String, CaseIterable, Identifiable {
        case all, scenario, mindmap, page, character, hidden, trash

        public var id: String { rawValue }
    }

    public enum SortOrder: String, CaseIterable, Identifiable {
        case modified, name, kind

        public var id: String { rawValue }
    }

    @Bindable var workspace: WorkspaceStore
    let onOpen: (DocumentListItem) -> Void
    /// 보호 섹션 접근 시 호출 — true 반환 시 접근 허용
    let requestUnlock: (String) async -> Bool
    /// 열기 클릭 방식 (설정 연동: true = 싱글 클릭)
    let openOnSingleClick: Bool

    @State private var category: Category = .all
    @State private var sortOrder: SortOrder = .modified
    @State private var isGrid = false
    @State private var query = ""
    @State private var unlockGranted = false

    @Environment(\.renderQuality) private var quality

    public init(
        workspace: WorkspaceStore,
        onOpen: @escaping (DocumentListItem) -> Void,
        requestUnlock: @escaping (String) async -> Bool = { _ in true },
        openOnSingleClick: Bool = true
    ) {
        self.workspace = workspace
        self.onOpen = onOpen
        self.requestUnlock = requestUnlock
        self.openOnSingleClick = openOnSingleClick
    }

    public var body: some View {
        let l10n = Localizer.shared
        VStack(spacing: 0) {
            toolbar(l10n)
            Divider().opacity(0.4)
            if isProtected, !unlockGranted {
                lockedPlaceholder(l10n)
            } else if items.isEmpty {
                emptyPlaceholder(l10n)
            } else if isGrid {
                gridView
            } else {
                listView
            }
        }
        .onChange(of: category) { _, newValue in
            guard newValue == .hidden || newValue == .trash else {
                unlockGranted = false
                return
            }
            Task {
                let l10n = Localizer.shared
                unlockGranted = await requestUnlock(l10n.t(.authReason))
            }
        }
    }

    private var isProtected: Bool {
        category == .hidden || category == .trash
    }

    // MARK: 필터링/정렬

    private var items: [DocumentListItem] {
        var base: [DocumentListItem] = switch category {
        case .all: workspace.visibleDocuments
        case .scenario: workspace.visibleDocuments.filter { $0.envelope.kind == .scenario }
        case .mindmap: workspace.visibleDocuments.filter { $0.envelope.kind == .mindmap }
        case .page: workspace.visibleDocuments.filter { $0.envelope.kind == .page && !$0.envelope.isCharacterPage }
        case .character: workspace.visibleDocuments.filter { $0.envelope.isCharacterPage }
        case .hidden: workspace.hiddenDocuments
        case .trash: workspace.trashedDocuments
        }
        if !query.isEmpty {
            base = base.filter { $0.envelope.title.localizedCaseInsensitiveContains(query) }
        }
        return switch sortOrder {
        case .modified: base.sorted { $0.envelope.modifiedAt > $1.envelope.modifiedAt }
        case .name: base.sorted { $0.envelope.title.localizedCompare($1.envelope.title) == .orderedAscending }
        case .kind: base.sorted { $0.envelope.kind.rawValue < $1.envelope.kind.rawValue }
        }
    }

    private func categoryLabel(_ c: Category, _ l10n: Localizer) -> String {
        switch c {
        case .all: l10n.t(.allDocuments)
        case .scenario: l10n.t(.scenario)
        case .mindmap: l10n.t(.mindmap)
        case .page: l10n.t(.page)
        case .character: l10n.t(.characterPage)
        case .hidden: l10n.t(.hiddenItems)
        case .trash: l10n.t(.trashItems)
        }
    }

    // MARK: 도구막대

    private func toolbar(_ l10n: Localizer) -> some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            Picker("", selection: $category) {
                ForEach(Category.allCases) { c in
                    if c == .hidden {
                        Label(categoryLabel(c, l10n), systemImage: "eye.slash").tag(c)
                    } else if c == .trash {
                        Label(categoryLabel(c, l10n), systemImage: "trash").tag(c)
                    } else {
                        Text(categoryLabel(c, l10n)).tag(c)
                    }
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            Spacer()

            SearchCapsule(text: $query, placeholder: l10n.t(.searchPlaceholder), quality: quality)

            Menu {
                Picker(l10n.t(.sortBy), selection: $sortOrder) {
                    Text(l10n.t(.sortModified)).tag(SortOrder.modified)
                    Text(l10n.t(.sortName)).tag(SortOrder.name)
                    Text(l10n.t(.sortKind)).tag(SortOrder.kind)
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            ToolbarIconButton(
                isGrid ? "list.bullet" : "square.grid.2x2",
                help: isGrid ? l10n.t(.viewList) : l10n.t(.viewGrid)
            ) { isGrid.toggle() }
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.vertical, DesignTokens.Spacing.s)
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
            Text(query.isEmpty ? l10n.t(.emptyCategory) : l10n.t(.noRecents))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 리스트 (락업)

    private var listView: some View {
        List(items) { item in
            ArchiveRow(item: item, clickCount: openOnSingleClick ? 1 : 2, onOpen: onOpen)
                .contextMenu { contextMenu(for: item) }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: 그리드 (아이콘)

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: DesignTokens.Spacing.m)], spacing: DesignTokens.Spacing.m) {
                ForEach(items) { item in
                    ArchiveCard(item: item, clickCount: openOnSingleClick ? 1 : 2, onOpen: onOpen)
                        .contextMenu { contextMenu(for: item) }
                }
            }
            .padding(DesignTokens.Spacing.m)
        }
    }

    // MARK: 컨텍스트 메뉴

    @ViewBuilder
    private func contextMenu(for item: DocumentListItem) -> some View {
        let l10n = Localizer.shared
        if item.envelope.isTrashed {
            Button(l10n.t(.restore)) { workspace.restoreFromTrash(item) }
            Button(l10n.t(.delete), role: .destructive) { workspace.deletePermanently(item) }
        } else {
            Button(l10n.t(.open)) { onOpen(item) }
            Divider()
            if item.envelope.isHidden {
                Button(l10n.t(.unhide)) { workspace.setHidden(item, hidden: false) }
            } else {
                Button(l10n.t(.hide)) { workspace.setHidden(item, hidden: true) }
            }
            Button(l10n.t(.moveToTrash), role: .destructive) { workspace.moveToTrash(item) }
        }
    }
}

// MARK: - 행/카드

struct ArchiveRow: View {
    let item: DocumentListItem
    let clickCount: Int
    let onOpen: (DocumentListItem) -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            Image(systemName: item.envelope.isCharacterPage ? "person.crop.circle" : item.envelope.kind.symbolName)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
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
                    Text(item.envelope.modifiedAt, style: .date)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text("." + item.envelope.kind.fileExtension)
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
        .onTapGesture(count: clickCount) { onOpen(item) }
        .animation(DesignTokens.Motion.snappy, value: hovering)
    }
}

struct ArchiveCard: View {
    let item: DocumentListItem
    let clickCount: Int
    let onOpen: (DocumentListItem) -> Void

    @State private var hovering = false
    @Environment(\.renderQuality) private var quality

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.s) {
            Image(systemName: item.envelope.isCharacterPage ? "person.crop.circle" : item.envelope.kind.symbolName)
                .font(.system(size: 34))
                .foregroundStyle(Color.accentColor)
                .frame(height: 54)
            Text(item.envelope.title)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(item.envelope.modifiedAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(DesignTokens.Spacing.m)
        .frame(maxWidth: .infinity)
        .glassSurface(cornerRadius: DesignTokens.Radius.medium, quality: quality)
        .scaleEffect(hovering ? 1.03 : 1)
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(count: clickCount) { onOpen(item) }
        .animation(DesignTokens.Motion.snappy, value: hovering)
    }
}
