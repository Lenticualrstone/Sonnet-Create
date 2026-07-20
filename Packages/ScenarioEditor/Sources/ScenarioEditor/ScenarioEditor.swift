import AVFoundation
import AppCore
import DesignSystem
import DocumentKit
import SwiftUI
import UniformTypeIdentifiers

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
    /// 낭독(TTS) — 대사를 캐릭터별 목소리로 읽어준다.
    @State private var rehearsalVoiceEnabled = false
    @State private var narrator = RehearsalNarrator()
    /// 낭독 중 TTS가 말한 글자 수 — 마지막 블록의 타자기 리빌이 이 값을 따라간다.
    @State private var rehearsalSpokenChars: Int?

    private var isRehearsing: Bool { rehearsalCount != nil }

    // MARK: 검색 점프 탐색

    @State private var searchMatchIndex = 0
    @FocusState private var searchFocused: Bool
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
            // 플롯 타임라인 (2a) — 장면 카드 + 분기 레인. 리허설 중에는 숨긴다.
            if !isRehearsing, !store.content.blocks.isEmpty {
                PlotTimelineView(store: store, isReadOnly: isReadOnly) { targetID in
                    jumpToScene(targetID)
                }
                Divider().opacity(0.25)
            }
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
        .onChange(of: rehearsalPaused) { _, paused in
            narrator.setPaused(paused)
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
                help: l10n.t(.characters) + " (⌥⌘I)",
                isActive: showInspector
            ) { showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])

            BreadcrumbView(breadcrumb)

            branchPicker(l10n)

            if scenes.count >= 2 {
                sceneMenu(l10n)
            }

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

            Menu {
                Button(l10n.t(.exportText)) { exportText() }
                Button(l10n.t(.exportPDF)) { exportPDF() }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(l10n.t(.exportScript))

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

            SearchCapsule(
                text: $store.searchQuery,
                placeholder: l10n.t(.searchInDocument),
                quality: quality,
                focusBinding: $searchFocused
            )
            .onChange(of: store.searchQuery) {
                focusSearchMatch(0)
            }

            // ⌘F — 문서 내 검색 포커스 (보이지 않는 단축키 버튼)
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .buttonStyle(.plain)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.vertical, DesignTokens.Spacing.s)
    }

    // MARK: 씬 목차 (구분선 블록 = 장면 경계)

    /// 활성 시퀀스를 구분선으로 잘라 장면 목록을 만든다.
    /// 제목은 장면을 여는 구분선의 텍스트(장면 모드 입력)가 우선, 없으면 첫 텍스트 미리보기.
    private var scenes: [(id: UUID, title: String)] {
        var result: [(UUID, String)] = []
        var segment: [ScenarioBlock] = []
        var pendingTitle = ""
        func flush(nextTitle: String) {
            defer {
                segment = []
                pendingTitle = nextTitle
            }
            guard let first = segment.first else { return }
            if !pendingTitle.isEmpty {
                result.append((first.id, String(pendingTitle.prefix(24))))
                return
            }
            let preview = segment.first(where: { !$0.text.isEmpty })?.text.prefix(20)
            result.append((first.id, preview.map(String.init) ?? ""))
        }
        for block in store.activeBlocks {
            if block.kind == .divider {
                flush(nextTitle: block.text)
            } else {
                segment.append(block)
            }
        }
        flush(nextTitle: "")
        return result
    }

    private func sceneMenu(_ l10n: Localizer) -> some View {
        Menu {
            ForEach(Array(scenes.enumerated()), id: \.element.id) { index, scene in
                Button {
                    jumpToScene(scene.id)
                } label: {
                    let number = String(format: l10n.t(.sceneFormat), index + 1)
                    Text(scene.title.isEmpty ? number : "\(number) — \(scene.title)")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.caption)
                Text("\(scenes.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
            }
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(l10n.t(.sceneList))
    }

    /// 같은 장면을 연속으로 선택해도 스크롤되도록 nil을 한 틱 거쳐 목표를 갱신한다.
    private func jumpToScene(_ id: UUID) {
        searchScrollTarget = nil
        DispatchQueue.main.async { searchScrollTarget = id }
    }

    // MARK: 대본 내보내기

    private var exportTitle: String {
        breadcrumb.last ?? "Scenario"
    }

    private func exportText() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = exportTitle + ".txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let script = ScenarioExport.text(
            title: exportTitle, content: store.content, blocks: store.effectiveFlowForAI
        )
        try? script.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = exportTitle + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let data = ScenarioExport.pdf(
            title: exportTitle, content: store.content, blocks: store.effectiveFlowForAI
        ) {
            try? data.write(to: url)
        }
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
                        // 빈 본문 — 다음 행동으로 이어지는 시작 안내 (4단계 시나리오)
                        VStack(spacing: DesignTokens.Spacing.m) {
                            Text(l10n.t(.emptyEditorHint))
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                            if !isReadOnly {
                                HStack(spacing: DesignTokens.Spacing.s) {
                                    emptyStateAction(l10n.t(.emptyAddFirstScene), symbol: "film") {
                                        store.composerMode = .scene
                                    }
                                    emptyStateAction(l10n.t(.emptyConnectCharacter), symbol: "person.badge.plus") {
                                        withAnimation(DesignTokens.Motion.gentle) { showInspector = true }
                                    }
                                    emptyStateAction(l10n.t(.aiCompose), symbol: "sparkles") {
                                        store.aiEnabled = true
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    ForEach(displayedBlocks) { block in
                        ScenarioBlockRow(
                            store: store,
                            block: block,
                            // 리허설 중 방금 등장한 대사만 타자기 리빌 (9e)
                            typewriterReveal: isRehearsing
                                && block.kind == .line
                                && block.id == displayedBlocks.last?.id,
                            // 낭독 중이면 리빌이 TTS 진행을, 아니면 재생 배속을 따른다
                            typewriterProgress: block.id == displayedBlocks.last?.id
                                ? rehearsalSpokenChars : nil,
                            typewriterSpeed: rehearsalSpeed
                        )
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
                    // 첫 사용 안내 — 입력 모드 3종을 한 번만 짧게 (5단계 상황별 안내)
                    FirstUseCallout(id: "scenario-modes", text: l10n.t(.calloutScenarioModes))
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

    /// 마지막 블록까지 등장을 마친 상태.
    private var rehearsalFinished: Bool {
        guard let count = rehearsalCount else { return false }
        return count >= store.visibleBlocks.count
    }

    @ViewBuilder
    private func rehearsalControls(_ l10n: Localizer) -> some View {
        if isRehearsing {
            // 진행 표시 — 현재/전체 블록
            Text("\(min(rehearsalCount ?? 0, store.visibleBlocks.count))/\(store.visibleBlocks.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            voiceToggle(l10n)

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

            if rehearsalFinished {
                ToolbarIconButton("gobackward", help: l10n.t(.rehearsal) + " (⌘R)") { startRehearsal() }
                    .keyboardShortcut("r", modifiers: .command)
            } else {
                ToolbarIconButton(
                    rehearsalPaused ? "play.fill" : "pause.fill",
                    help: l10n.t(rehearsalPaused ? .rehearsalResume : .rehearsalPause) + " (⌘R)"
                ) { rehearsalPaused.toggle() }
                    .keyboardShortcut("r", modifiers: .command)
            }

            ToolbarIconButton("stop.fill", help: l10n.t(.rehearsalStop) + " (⎋)") { stopRehearsal() }
                .keyboardShortcut(.escape, modifiers: [])
        } else {
            voiceToggle(l10n)

            ToolbarIconButton("play.circle", help: l10n.t(.rehearsal) + " (⌘R)") { startRehearsal() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.visibleBlocks.isEmpty)
                .opacity(store.visibleBlocks.isEmpty ? 0.35 : 1)
        }
    }

    private func voiceToggle(_ l10n: Localizer) -> some View {
        ToolbarIconButton(
            rehearsalVoiceEnabled ? "speaker.wave.2.fill" : "speaker.slash",
            help: l10n.t(.rehearsalVoice),
            isActive: rehearsalVoiceEnabled
        ) {
            rehearsalVoiceEnabled.toggle()
            if !rehearsalVoiceEnabled { narrator.stop() }
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
        // 정지 직후 도착하는 늦은 콜백이 상태를 되살리지 않게 리허설 중일 때만 반영
        narrator.onProgress = { spoken in
            if rehearsalCount != nil { rehearsalSpokenChars = spoken }
        }
        withAnimation(DesignTokens.Motion.gentle) { rehearsalCount = 0 }
        rehearsalTask = Task {
            var index = 0
            while index < store.visibleBlocks.count, !Task.isCancelled {
                let block = store.visibleBlocks[index]
                if rehearsalVoiceEnabled, block.kind == .line, !block.text.isEmpty {
                    // 낭독 모드: 자막처럼 먼저 등장시키고, 말이 끝나야 다음으로.
                    // 리빌은 TTS 진행 콜백에 글자 단위로 동기화된다.
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    rehearsalSpokenChars = 0
                    withAnimation(DesignTokens.Motion.arrival) { rehearsalCount = index + 1 }
                    await narrator.speak(
                        plainText(of: block),
                        voice: rehearsalVoice(for: block),
                        rate: speechRate
                    )
                    rehearsalSpokenChars = nil
                } else {
                    try? await Task.sleep(for: .seconds(rehearsalDelay(for: block)))
                    guard !Task.isCancelled else { return }
                    withAnimation(DesignTokens.Motion.arrival) { rehearsalCount = index + 1 }
                }
                while rehearsalPaused, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(120))
                }
                guard !Task.isCancelled else { return }
                index += 1
            }
        }
    }

    /// 빈 상태의 행동 칩 — 잉크 워시 배경의 조용한 보조 버튼 (Primary는 컴포저가 담당).
    private func emptyStateAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.callout)
                .foregroundStyle(SonnetPalette.inkSoft)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(SonnetPalette.ink.opacity(0.05))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func stopRehearsal() {
        rehearsalTask?.cancel()
        rehearsalTask = nil
        narrator.onProgress = nil
        narrator.stop()
        rehearsalSpokenChars = nil
        rehearsalPaused = false
        withAnimation(DesignTokens.Motion.gentle) { rehearsalCount = nil }
    }

    // MARK: 낭독 보이스

    /// 마크다운 강조 기호를 걷어낸 낭독용 평문.
    private func plainText(of block: ScenarioBlock) -> String {
        let attributed = (try? AttributedString(
            markdown: block.text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(block.text)
        return String(attributed.characters)
    }

    /// 낭독 목소리 — 캐스트에 수동 지정이 있으면 그 목소리, 없으면 순번 자동 배정.
    private func rehearsalVoice(for block: ScenarioBlock) -> AVSpeechSynthesisVoice? {
        let member = block.speakerIDs.first.flatMap { id in
            store.content.cast.first { $0.id == id }
        }
        if let identifier = member?.voiceIdentifier,
           let chosen = AVSpeechSynthesisVoice(identifier: identifier) {
            return chosen
        }
        let castIndex = member.flatMap { chosen in
            store.content.cast.firstIndex { $0.id == chosen.id }
        }
        return RehearsalVoiceCasting.voice(
            languageCode: Localizer.shared.language.rawValue,
            castIndex: castIndex
        )
    }

    /// 재생 속도 칩과 연동된 발화 속도. AVSpeech 기본 0.5 근처에서 완만하게 가감.
    private var speechRate: Float {
        AVSpeechUtteranceDefaultSpeechRate * Float(1 + (rehearsalSpeed - 1) * 0.2)
    }

    /// 텍스트 길이에 비례한 등장 간격 — 실제 대화 리듬처럼 느껴지는 값.
    /// 구분선(장면 전환)은 텍스트가 없어도 한 호흡 길게 쉰다.
    private func rehearsalDelay(for block: ScenarioBlock) -> Double {
        if block.kind == .divider { return 1.4 / rehearsalSpeed }
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
