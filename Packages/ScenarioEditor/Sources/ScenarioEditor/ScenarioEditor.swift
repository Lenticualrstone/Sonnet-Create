import AppCore
import DesignSystem
import DocumentKit
import SwiftUI

/// 채팅형 시나리오 뷰어/에디터.
public struct ScenarioEditorView: View {
    @Bindable var store: ScenarioStore
    let breadcrumb: [String]
    let saveState: SaveState
    let onManualSave: () -> Void
    let onOpenCharacterPage: (UUID) -> Void
    let onCreateCharacterPage: (CastMember) -> UUID?
    /// 캐릭터 인스펙터 배치 (설정: 왼쪽/오른쪽)
    let inspectorOnRight: Bool

    @State private var showInspector = true
    @Environment(\.renderQuality) private var quality
    @Environment(\.contentBlockSpacing) private var blockSpacing
    @Environment(\.resolvedAccent) private var accent

    public init(
        store: ScenarioStore,
        breadcrumb: [String],
        saveState: SaveState,
        onManualSave: @escaping () -> Void,
        onOpenCharacterPage: @escaping (UUID) -> Void = { _ in },
        onCreateCharacterPage: @escaping (CastMember) -> UUID? = { _ in nil },
        inspectorOnRight: Bool = false
    ) {
        self.store = store
        self.breadcrumb = breadcrumb
        self.saveState = saveState
        self.onManualSave = onManualSave
        self.onOpenCharacterPage = onOpenCharacterPage
        self.onCreateCharacterPage = onCreateCharacterPage
        self.inspectorOnRight = inspectorOnRight
    }

    public var body: some View {
        let l10n = Localizer.shared
        VStack(spacing: 0) {
            toolbar(l10n)
            Divider().opacity(0.4)
            HStack(spacing: 0) {
                if showInspector, !inspectorOnRight {
                    inspector
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider().opacity(0.4)
                }
                blockArea(l10n)
                if showInspector, inspectorOnRight {
                    Divider().opacity(0.4)
                    inspector
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .animation(DesignTokens.Motion.gentle, value: showInspector)
    }

    private var inspector: some View {
        CharacterInspectorView(
            store: store,
            onOpenCharacterPage: onOpenCharacterPage,
            onCreateCharacterPage: onCreateCharacterPage
        )
        .frame(width: 232)
    }

    // MARK: 헤더 도구막대

    private func toolbar(_ l10n: Localizer) -> some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            ToolbarIconButton(
                "sidebar.left",
                help: l10n.t(.characters),
                isActive: showInspector
            ) { showInspector.toggle() }

            BreadcrumbView(breadcrumb)

            branchPicker(l10n)

            Spacer()

            ToolbarIconButton("arrow.uturn.backward", help: l10n.t(.undo)) { store.undo() }
                .disabled(!store.canUndo)
                .opacity(store.canUndo ? 1 : 0.35)
            ToolbarIconButton("arrow.uturn.forward", help: l10n.t(.redo)) { store.redo() }
                .disabled(!store.canRedo)
                .opacity(store.canRedo ? 1 : 0.35)

            SaveStatusBadge(state: saveState, label: l10n.t(saveState.labelKey), action: onManualSave)

            ToolbarIconButton(
                "sparkles",
                help: l10n.t(.aiCompose),
                isActive: store.aiEnabled
            ) { store.aiEnabled.toggle() }

            SearchCapsule(text: $store.searchQuery, placeholder: l10n.t(.searchInDocument), quality: quality)
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.vertical, DesignTokens.Spacing.s)
    }

    // MARK: 분기 피커

    private func branchPicker(_ l10n: Localizer) -> some View {
        Menu {
            Button {
                store.switchBranch(nil)
            } label: {
                if store.activeBranchID == nil {
                    Label(l10n.t(.mainRoute), systemImage: "checkmark")
                } else {
                    Text(l10n.t(.mainRoute))
                }
            }
            if !store.content.branches.isEmpty {
                Divider()
                ForEach(store.content.branches) { branch in
                    Button {
                        store.switchBranch(branch.id)
                    } label: {
                        if store.activeBranchID == branch.id {
                            Label(branch.name, systemImage: "checkmark")
                        } else {
                            Text(branch.name)
                        }
                    }
                }
            }
            Divider()
            Button(l10n.t(.newBranch)) {
                store.createBranch(
                    after: store.activeBranchID == nil ? store.content.blocks.last : nil,
                    name: "\(l10n.t(.branch)) \(store.content.branches.count + 1)"
                )
            }
            if let branch = store.activeBranch {
                Button(l10n.t(.delete), role: .destructive) {
                    store.deleteBranch(branch.id)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption)
                Text(store.activeBranch?.name ?? l10n.t(.mainRoute))
                    .font(.caption.weight(.semibold))
                    .textStateSwap()
            }
            .foregroundStyle(store.activeBranchID == nil ? Color.secondary : accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(l10n.t(.branch))
    }

    // MARK: 블록 영역

    private func blockArea(_ l10n: Localizer) -> some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                List {
                    // 분기 모드: 분기점 직전 본편 블록을 흐리게 + 분기 시작 배너
                    if store.activeBranch != nil {
                        ForEach(store.branchContextBlocks) { block in
                            ScenarioBlockRow(store: store, block: block)
                                .opacity(0.35)
                                .allowsHitTesting(false)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(
                                    top: blockSpacing / 2, leading: DesignTokens.Spacing.m,
                                    bottom: blockSpacing / 2, trailing: DesignTokens.Spacing.m
                                ))
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.caption)
                            Text("\(l10n.t(.branchPoint)) — \(store.activeBranch?.name ?? "")")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button(l10n.t(.backToMain)) { store.switchBranch(nil) }
                                .font(.caption)
                                .buttonStyle(.borderless)
                        }
                        .foregroundStyle(accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                                .fill(accent.opacity(0.08))
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(
                            top: blockSpacing / 2, leading: DesignTokens.Spacing.m,
                            bottom: blockSpacing / 2, trailing: DesignTokens.Spacing.m
                        ))
                    }

                    if store.activeBlocks.isEmpty {
                        Text(l10n.t(.emptyEditorHint))
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(store.visibleBlocks) { block in
                        ScenarioBlockRow(store: store, block: block)
                            .id(block.id)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(
                                top: blockSpacing / 2, leading: DesignTokens.Spacing.m,
                                bottom: blockSpacing / 2, trailing: DesignTokens.Spacing.m
                            ))
                    }
                    .onMove { store.moveBlocks(from: $0, to: $1) }

                    // 입력기에 가리지 않도록 여백
                    Color.clear
                        .frame(height: 120)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onChange(of: store.activeBlocks.count) {
                    if let last = store.activeBlocks.last {
                        withAnimation(DesignTokens.Motion.arrival) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            VStack(spacing: DesignTokens.Spacing.s) {
                if store.aiEnabled, !store.pendingSuggestions.isEmpty || store.isGenerating {
                    SuggestionStrip(store: store)
                }
                ComposerView(store: store)
            }
            .padding(.horizontal, DesignTokens.Spacing.l)
            .padding(.bottom, DesignTokens.Spacing.m)
        }
    }
}
