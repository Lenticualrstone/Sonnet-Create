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
    @Environment(\.readOnlyMode) private var readOnlyMode

    private var isReadOnly: Bool { readOnlyMode?.wrappedValue == true }

    // MARK: 리허설 (읽기 전용 모드 전용) — 블록이 대화 리플레이처럼 하나씩 등장

    @State private var rehearsalCount: Int?
    @State private var rehearsalPaused = false
    @State private var rehearsalSpeed: Double = 1
    @State private var rehearsalTask: Task<Void, Never>?

    private var isRehearsing: Bool { rehearsalCount != nil }

    // MARK: 검색 점프 탐색

    @State private var searchMatchIndex = 0
    /// blockArea의 ScrollViewReader가 구독하는 스크롤 목표.
    @State private var searchScrollTarget: UUID?

    /// 현재 일치 위치로 포커스를 옮기고 스크롤을 요청한다.
    private func focusSearchMatch(_ index: Int) {
        let matches = store.searchMatchIDs
        guard !matches.isEmpty else {
            store.searchFocusID = nil
            return
        }
        let wrapped = ((index % matches.count) + matches.count) % matches.count
        searchMatchIndex = wrapped
        store.searchFocusID = matches[wrapped]
        searchScrollTarget = matches[wrapped]
    }

    /// 리허설 중에는 진행분까지만, 평소에는 전체.
    private var displayedBlocks: [ScenarioBlock] {
        if let count = rehearsalCount { return Array(store.visibleBlocks.prefix(count)) }
        return store.visibleBlocks
    }

    /// 다음에 등장할 대사 블록의 화자 이름 (타이핑 인디케이터 라벨).
    private var nextRehearsalSpeakers: String? {
        guard let count = rehearsalCount, count < store.visibleBlocks.count else { return nil }
        let block = store.visibleBlocks[count]
        guard block.kind == .line else { return nil }
        let names = block.speakerIDs.compactMap { id in store.content.cast.first { $0.id == id }?.name }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

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
        .onChange(of: isReadOnly) { _, locked in
            if !locked { stopRehearsal() }
        }
        .onDisappear { stopRehearsal() }
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

            ReadOnlyBadge()

            ToolbarIconButton("arrow.uturn.backward", help: l10n.t(.undo)) { store.undo() }
                .disabled(!store.canUndo || isReadOnly)
                .opacity(store.canUndo && !isReadOnly ? 1 : 0.35)
            ToolbarIconButton("arrow.uturn.forward", help: l10n.t(.redo)) { store.redo() }
                .disabled(!store.canRedo || isReadOnly)
                .opacity(store.canRedo && !isReadOnly ? 1 : 0.35)

            SaveStatusBadge(state: saveState, label: l10n.t(saveState.labelKey), action: onManualSave)

            ReadOnlyToggle()

            if isReadOnly {
                rehearsalControls(l10n)
            }

            ToolbarIconButton(
                "sparkles",
                help: l10n.t(.aiCompose),
                isActive: store.aiEnabled
            ) { store.aiEnabled.toggle() }
                .disabled(isReadOnly)
                .opacity(isReadOnly ? 0.35 : 1)

            if !store.searchQuery.isEmpty {
                let matches = store.searchMatchIDs
                HStack(spacing: 2) {
                    Text(matches.isEmpty ? "0" : "\(searchMatchIndex + 1)/\(matches.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(matches.isEmpty ? .tertiary : .secondary)
                    ToolbarIconButton("chevron.up", help: "↑") {
                        focusSearchMatch(searchMatchIndex - 1)
                    }
                    .disabled(matches.isEmpty)
                    ToolbarIconButton("chevron.down", help: "↓") {
                        focusSearchMatch(searchMatchIndex + 1)
                    }
                    .disabled(matches.isEmpty)
                }
                .transition(.opacity)
            }

            SearchCapsule(text: $store.searchQuery, placeholder: l10n.t(.searchInDocument), quality: quality)
                .onChange(of: store.searchQuery) {
                    focusSearchMatch(0)
                }
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
            if !isReadOnly {
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
                    ForEach(displayedBlocks) { block in
                        ScenarioBlockRow(store: store, block: block)
                            .id(block.id)
                            .allowsHitTesting(!isReadOnly)
                            .moveDisabled(isReadOnly)
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
                .onChange(of: rehearsalCount) {
                    if let last = displayedBlocks.last {
                        withAnimation(DesignTokens.Motion.arrival) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: searchScrollTarget) { _, target in
                    if let target {
                        withAnimation(DesignTokens.Motion.gentle) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                    }
                }
            }

            // 리허설 타이핑 인디케이터 — 다음 블록을 '입력 중'인 것처럼 보여준다
            if isRehearsing, !rehearsalPaused, let count = rehearsalCount, count < store.visibleBlocks.count {
                RehearsalTypingIndicator(name: nextRehearsalSpeakers)
                    .padding(.bottom, DesignTokens.Spacing.l)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if !isReadOnly {
                VStack(spacing: DesignTokens.Spacing.s) {
                    if store.aiEnabled, !store.pendingSuggestions.isEmpty || store.isGenerating {
                        SuggestionStrip(store: store)
                    }
                    ComposerView(store: store)
                }
                .padding(.horizontal, DesignTokens.Spacing.l)
                .padding(.bottom, DesignTokens.Spacing.m)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: 리허설 컨트롤/엔진

    @ViewBuilder
    private func rehearsalControls(_ l10n: Localizer) -> some View {
        if isRehearsing {
            Button {
                cycleRehearsalSpeed()
            } label: {
                Text(speedLabel)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(accent.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help(l10n.t(.rehearsalSpeed))

            ToolbarIconButton(
                rehearsalPaused ? "play.fill" : "pause.fill",
                help: l10n.t(rehearsalPaused ? .rehearsalResume : .rehearsalPause)
            ) { rehearsalPaused.toggle() }

            ToolbarIconButton("stop.fill", help: l10n.t(.rehearsalStop)) { stopRehearsal() }
        } else {
            ToolbarIconButton("play.circle", help: l10n.t(.rehearsal)) { startRehearsal() }
                .disabled(store.visibleBlocks.isEmpty)
                .opacity(store.visibleBlocks.isEmpty ? 0.35 : 1)
        }
    }

    private var speedLabel: String {
        rehearsalSpeed == 1 ? "1×" : String(format: "%.1f×", rehearsalSpeed)
    }

    private func cycleRehearsalSpeed() {
        let steps: [Double] = [0.5, 1, 1.5, 2]
        let index = steps.firstIndex(of: rehearsalSpeed) ?? 1
        rehearsalSpeed = steps[(index + 1) % steps.count]
    }

    private func startRehearsal() {
        rehearsalTask?.cancel()
        rehearsalPaused = false
        withAnimation(DesignTokens.Motion.gentle) { rehearsalCount = 0 }
        rehearsalTask = Task {
            var index = 0
            while index < store.visibleBlocks.count, !Task.isCancelled {
                let block = store.visibleBlocks[index]
                try? await Task.sleep(for: .seconds(rehearsalDelay(for: block)))
                while rehearsalPaused, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(120))
                }
                guard !Task.isCancelled else { return }
                withAnimation(DesignTokens.Motion.arrival) { rehearsalCount = index + 1 }
                index += 1
            }
        }
    }

    private func stopRehearsal() {
        rehearsalTask?.cancel()
        rehearsalTask = nil
        rehearsalPaused = false
        withAnimation(DesignTokens.Motion.gentle) { rehearsalCount = nil }
    }

    /// 텍스트 길이에 비례한 등장 간격 — 실제 대화 리듬처럼 느껴지는 값.
    private func rehearsalDelay(for block: ScenarioBlock) -> Double {
        let base: Double = block.kind == .line ? 0.55 : 0.4
        let perChar: Double = block.kind == .line ? 0.032 : 0.018
        return min(3.2, base + Double(block.text.count) * perChar) / rehearsalSpeed
    }
}

/// 리허설 중 '입력 중…' 버블 — 화자 이름 + 파동치는 점 3개.
private struct RehearsalTypingIndicator: View {
    let name: String?

    @State private var pulsing = false
    @Environment(\.resolvedAccent) private var accent

    var body: some View {
        HStack(spacing: 8) {
            if let name {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(accent.opacity(0.75))
                        .frame(width: 6, height: 6)
                        .scaleEffect(pulsing ? 1 : 0.55)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.16),
                            value: pulsing
                        )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
        .onAppear { pulsing = true }
    }
}
