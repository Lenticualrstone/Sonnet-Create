import AppCore
import DesignSystem
import DocumentKit
import FileManagerKit
import MarkdownEditor
import MindMapEditor
import RenderingKit
import ScenarioEditor
import SwiftUI

/// 문서 유형 → 디자인 시스템 파일 타입 매핑 (탭 칩·카드·배지 공용).
extension AppState {
    func fileType(for tab: OpenTab) -> DSFileType? {
        guard case .document(let docID) = tab.content else { return nil }
        let envelope = sessions[docID]?.document.envelope ?? workspace.item(id: docID)?.envelope
        guard let envelope else { return nil }
        if envelope.isCharacterPage { return .character }
        switch envelope.kind {
        case .scenario: return .scenario
        case .mindmap: return .mindmap
        case .page: return .page
        }
    }
}

/// 메인 윈도우 — 인장&원고 v2.0: 52px 통합 타이틀바(11a) + 좌측 아이콘 레일 + 콘텐츠.
struct MainWindowView: View {
    @Environment(AppState.self) private var app
    @Environment(\.renderQuality) private var quality
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.motionReduced) private var motionReduced
    /// 프로젝트 파일 인스펙터 폭 — 드래그로 조절, 재시작 후에도 유지
    @AppStorage("project-navigator-width") private var navigatorWidth = 232.0
    @State private var navigatorDragBaseWidth: Double?
    /// 시동 스플래시 (8a) — 창 최초 표시 시 한 번만.
    @State private var showSplash = true

    var body: some View {
        @Bindable var app = app
        // 11a 통합 타이틀바: 신호등·로고·탭·상태가 하나의 52px 헤더에 수납되고,
        // 레일은 헤더 아래에서 시작한다 (브라우저 문법). 기준선이 물리적으로 1개라
        // 상단이 어긋날 여지가 없다.
        VStack(spacing: 0) {
            UnifiedTitlebar()

            HStack(spacing: 0) {
                RailView()
                Rectangle()
                    .fill(SonnetPalette.ink.opacity(0.08))
                    .frame(width: 1)
                ZStack {
                    SonnetPalette.canvas.ignoresSafeArea()
                    if app.settings.applied.paperGrainEnabled {
                        GrainOverlay(color: SonnetPalette.ink, opacity: 0.04)
                            .ignoresSafeArea()
                    }
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // 문서를 벗어나지 않고 에이전트와 대화하는 플로팅 패널 (⇧⌘A / 레일 ✨).
                // ⌘K가 열려 있는 동안은 잠시 내려가고, 닫히면 이전 상태로 복원된다 (3단계 3).
                .overlay(alignment: .bottomTrailing) {
                    if app.showFloatingChat, !app.showCommandPalette {
                        FloatingChatPanel()
                            .transition(.scale(scale: 0.94, anchor: .bottomTrailing).combined(with: .opacity))
                    }
                }
                .animation(
                    app.showFloatingChat ? DesignTokens.Motion.glassPop : DesignTokens.Motion.glassPopOut,
                    value: app.showFloatingChat
                )
                .animation(DesignTokens.Motion.glassPopOut, value: app.showCommandPalette)
            }
        }
        .background(SonnetPalette.canvas)
        // 윈도우 모드에서만 헤더를 타이틀 라인(신호등 뒤)까지 끌어올린다.
        // 전체화면에서는 그대로 두어야 한다 — 무조건 ignoresSafeArea하면
        // 전체화면의 (더 큰) 상단 안전영역만큼 헤더가 화면 밖으로 밀려나 사라진다.
        .modifier(TopChromeExtension(active: !app.isFullscreen))
        // ⌘K 커맨드 팔레트 — 어디서든 문서 점프/빠른 명령
        .overlay {
            if app.showCommandPalette {
                CommandPaletteView(isPresented: $app.showCommandPalette)
            }
        }
        // 시동 스플래시 (8a) — 잉크 스트로크 획순 드로우 → 워드마크 → 잉크 바 → 홈 인계
        .overlay {
            if showSplash {
                SplashView { showSplash = false }
            }
        }
        .background {
            Button("") {
                withAnimation(DesignTokens.Motion.glassPop) { app.showCommandPalette.toggle() }
            }
            .keyboardShortcut("k", modifiers: .command)
            .buttonStyle(.plain)
            .opacity(0)
            .accessibilityHidden(true)

            // ⇧⌘A — 어디서든 에이전트 호출 (문서에서는 플로팅, 그 외에는 탭)
            Button("") { app.toggleAgentSurface() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .buttonStyle(.plain)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .navigationTitle("")
        // 크롬(버튼/탭/툴바)의 안내 텍스트가 커서로 선택되는 것을 방지.
        // 본문 텍스트 선택이 필요한 곳(시나리오 블록 등)은 개별적으로 다시 활성화한다.
        .textSelection(.disabled)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            withAnimation(DesignTokens.Motion.rise) { app.isFullscreen = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            withAnimation(DesignTokens.Motion.rise) { app.isFullscreen = false }
        }
        // 휴지통 이동 확인 (단건/다건 공용) — 선택 수·대표 제목 표시, 복구 가능함을 명시
        .confirmationDialog(
            Localizer.shared.t(.moveToTrash),
            isPresented: Binding(
                get: { !app.pendingTrashItems.isEmpty },
                set: { if !$0 { app.pendingTrashItems = [] } }
            ),
            presenting: app.pendingTrashItems.isEmpty ? nil : app.pendingTrashItems
        ) { items in
            Button(
                items.count == 1
                    ? "\(Localizer.shared.t(.moveToTrash)): \(items[0].envelope.title)"
                    : "\(Localizer.shared.t(.moveToTrash)) (\(items.count))",
                role: .destructive
            ) {
                app.confirmPendingTrash()
            }
            Button(Localizer.shared.t(.cancel), role: .cancel) {}
        } message: { items in
            if items.count == 1 {
                Text(Localizer.shared.t(.trashConfirmMessage))
            } else {
                Text(String(
                    format: Localizer.shared.t(.trashConfirmMessagePlural),
                    items[0].envelope.title, items.count - 1
                ))
            }
        }
        // 영구 삭제 확인 (단건/다건 공용, 되돌릴 수 없음)
        .confirmationDialog(
            Localizer.shared.t(.permanentDelete),
            isPresented: Binding(
                get: { !app.pendingPermanentDeleteItems.isEmpty },
                set: { if !$0 { app.pendingPermanentDeleteItems = [] } }
            ),
            presenting: app.pendingPermanentDeleteItems.isEmpty ? nil : app.pendingPermanentDeleteItems
        ) { items in
            Button("\(Localizer.shared.t(.permanentDelete)) (\(items.count))", role: .destructive) {
                app.confirmPendingPermanentDelete()
            }
            Button(Localizer.shared.t(.cancel), role: .cancel) {}
        } message: { items in
            Text(items.count > 1
                ? Localizer.shared.t(.permanentDeleteConfirmMessagePlural)
                : Localizer.shared.t(.permanentDeleteConfirmMessage))
        }
        // 탭 닫기 시 저장 실패 — 변경분을 조용히 버리지 않고 묻는다
        .confirmationDialog(
            Localizer.shared.t(.saveFailedCloseTitle),
            isPresented: Binding(
                get: { app.pendingSaveFailureTab != nil },
                set: { if !$0 { app.pendingSaveFailureTab = nil } }
            ),
            presenting: app.pendingSaveFailureTab
        ) { tab in
            Button(Localizer.shared.t(.retrySave)) {
                app.pendingSaveFailureTab = nil
                app.closeTab(tab) // flush를 다시 시도하고, 실패하면 다이얼로그가 재등장
            }
            Button(Localizer.shared.t(.closeWithoutSaving), role: .destructive) {
                app.pendingSaveFailureTab = nil
                app.forceCloseTab(tab)
            }
            Button(Localizer.shared.t(.cancel), role: .cancel) {}
        } message: { tab in
            let detail = app.session(for: tab)?.lastSaveError
            Text(detail.map { "\(Localizer.shared.t(.saveFailedCloseMessage))\n\n\($0)" }
                ?? Localizer.shared.t(.saveFailedCloseMessage))
        }
        // 프로젝트 삭제 확인
        .confirmationDialog(
            Localizer.shared.t(.deleteProject),
            isPresented: Binding(
                get: { app.pendingDeleteProject != nil },
                set: { if !$0 { app.pendingDeleteProject = nil } }
            ),
            presenting: app.pendingDeleteProject
        ) { project in
            Button("\(Localizer.shared.t(.deleteProject)): \(project.manifest.name)", role: .destructive) {
                app.confirmPendingDeleteProject()
            }
            Button(Localizer.shared.t(.cancel), role: .cancel) {}
        } message: { _ in
            Text(Localizer.shared.t(.projectDeleteMessage))
        }
    }

    /// 프로젝트 파일 인스펙터 좌측 가장자리의 보이지 않는 리사이즈 스트립.
    private var navigatorResizeHandle: some View {
        Color.clear
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let base = navigatorDragBaseWidth ?? navigatorWidth
                        navigatorDragBaseWidth = base
                        navigatorWidth = min(320, max(200, base - value.translation.width))
                    }
                    .onEnded { _ in navigatorDragBaseWidth = nil }
            )
    }

    /// 탭 전환 — EXIT 즉시. ENTER는 문서면 rise 360ms(8b), 홈/아카이브 같은
    /// 대공간 이동이면 디더 디졸브(9b) — 판화가 찍히듯 점묘로 나타난다.
    @ViewBuilder
    private var content: some View {
        let isSpatial: Bool = {
            if case .document = app.selectedTab?.content { return false }
            return true
        }()
        ZStack {
            if let tab = app.selectedTab {
                tabContent(tab)
                    .id(tab.id)
                    .transition(.asymmetric(
                        // 모션 줄이기 — 디더/rise 대신 120ms opacity (6단계)
                        insertion: motionReduced
                            ? .opacity
                            : (isSpatial
                                ? .ditherReveal
                                : .opacity.combined(with: .offset(y: 14))),
                        removal: .identity
                    ))
            }
        }
        .animation(
            motionReduced
                ? .easeOut(duration: 0.12)
                : (isSpatial ? .linear(duration: 0.68) : DesignTokens.Motion.rise),
            value: app.selectedTabID
        )
    }

    @ViewBuilder
    private func tabContent(_ tab: OpenTab) -> some View {
        switch tab.content {
        case .home:
            HomeView()
        case .aiChat:
            AIChatView()
        case .profile:
            ProfileView()
        case .archive:
            ArchiveView(
                workspace: app.workspace,
                onOpen: { app.openDocument($0) },
                requestUnlock: { reason in
                    await app.privacyGate.unlock(reason: reason)
                },
                openOnSingleClick: app.settings.applied.openOnSingleClick,
                externalTarget: Binding(
                    get: { app.archiveNavigationRequest },
                    set: { app.archiveNavigationRequest = $0 }
                ),
                requestTrash: { app.requestTrash($0) },
                requestPermanentDelete: { app.requestPermanentDelete($0) },
                isSessionUnlocked: app.privacyGate.unlockedThisSession,
                onRestoreFallback: {
                    app.notify(symbol: "arrow.uturn.backward", message: Localizer.shared.t(.restoredToWorkspaceRoot))
                },
                onNavigate: { category, projectID in
                    app.recordArchiveNav(category, projectID)
                },
                onCreate: { kind, role in
                    app.createAndOpen(kind: kind, pageRole: role, in: app.creationTargetProject)
                }
            )
        case .document(let docID):
            if let session = app.sessions[docID] {
                HStack(spacing: 0) {
                    DocumentHostView(session: session)
                    // 프로젝트 파일 인스펙터 — 프로젝트 소속 문서에서만. 레일이 프로젝트
                    // 내부를 펼치지 않는 대신 이웃 파일 탐색/생성을 여기서 담당한다.
                    if app.showProjectNavigator,
                       let project = app.workspace.project(id: session.document.envelope.projectID) {
                        Divider().opacity(0.4)
                        ProjectNavigatorView(session: session, project: project)
                            .frame(width: navigatorWidth)
                            // 좌측 가장자리 드래그로 폭 조절 (200~320pt)
                            .overlay(alignment: .leading) { navigatorResizeHandle }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    if app.showReferencePanel {
                        Divider().opacity(0.4)
                        ReferencePanelView(session: session)
                            .frame(width: 250)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    if app.showSnapshotPanel {
                        Divider().opacity(0.4)
                        SnapshotPanelView(session: session)
                            .frame(width: 250)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(DesignTokens.Motion.rise, value: app.showReferencePanel)
                .animation(DesignTokens.Motion.rise, value: app.showSnapshotPanel)
                .animation(DesignTokens.Motion.rise, value: app.showProjectNavigator)
            }
        }
    }
}

/// 윈도우 모드에서만 상단 안전영역을 무시해 신호등 뒤로 콘텐츠를 확장한다.
/// 전체화면에서는 안전영역이 (더 크게) 다시 보고되므로 그대로 두지 않으면 헤더 전체가 화면 밖으로 밀려 사라진다.
private struct TopChromeExtension: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.ignoresSafeArea(.container, edges: .top)
        } else {
            content
        }
    }
}

// MARK: - 11a 통합 타이틀바
// 신호등 · 잉크 스트로크 로고 · 문서 탭 · 열린 탭 메뉴 · 저장 상태를 하나의
// 52px 헤더에 수납. 헤더는 Liquid Glass로 캔버스 위에 떠 있다.

struct UnifiedTitlebar: View {
    @Environment(AppState.self) private var app
    @Environment(\.resolvedAccent) private var accent
    @Environment(\.liquidGlassDisabled) private var glassDisabled

    @State private var newDocMenuHover = false
    @State private var showUpdateMenu = false
    @Environment(\.glassIntensity) private var glassIntensity
    /// 헤더 실측 폭 — 좁은 창에서 우선순위 낮은 패널 토글을 overflow 메뉴로 접는다 (3단계 1)
    @State private var headerWidth: CGFloat = 0

    /// 헤더가 항상 창 최상단 전체 폭을 차지하므로, 윈도우 모드에서는
    /// 항상 좌측에 신호등 자리를 남겨야 한다.
    private var needsTrafficLightInset: Bool { !app.isFullscreen }
    /// 현재 선택된 문서가 프로젝트 소속인지 — 프로젝트 파일 인스펙터 토글 노출 조건.
    private var selectedDocumentHasProject: Bool {
        guard let tab = app.selectedTab, let session = app.session(for: tab) else { return false }
        return app.workspace.project(id: session.document.envelope.projectID) != nil
    }

    var body: some View {
        let l10n = Localizer.shared
        HStack(spacing: 8) {
            // 잉크 스트로크 로고 — 신호등 바로 옆, 타이틀바 소속 (11a)
            InkStrokeMark(size: 20, color: accent)
                .frame(width: 26, height: 26)
                .padding(.leading, needsTrafficLightInset ? 76 : 16)
                .background(windowDragArea)

            Rectangle()
                .fill(SonnetPalette.ink.opacity(0.1))
                .frame(width: 1, height: 20)

            // 뒤로/앞으로 탐색 — 편집 되돌리기(⌘Z)와 무관, 탐색 중인 화면의 이동 기록.
            HStack(spacing: 0) {
                ToolbarIconButton("chevron.left", help: l10n.t(.navigateBack)) {
                    app.goBack()
                }
                .disabled(!app.canGoBack)
                .opacity(app.canGoBack ? 1 : 0.35)

                ToolbarIconButton("chevron.right", help: l10n.t(.navigateForward)) {
                    app.goForward()
                }
                .disabled(!app.canGoForward)
                .opacity(app.canGoForward ? 1 : 0.35)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(app.tabs) { tab in
                            TabChip(tab: tab)
                                .id(tab.id)
                        }
                    }
                    .padding(.leading, 2)
                    // 탭 스트립에서는 시스템 타이틀바 창 끌기를 차단 — 칩 드래그(순서 변경)와 경합 방지
                    .background(BlockWindowDrag())
                }
                .scrollClipDisabled()
                // 탭이 많아 가려질 때 선택 탭을 항상 시야로 데려온다
                .onChange(of: app.selectedTabID) { _, selected in
                    if let selected {
                        withAnimation(DesignTokens.Motion.rise) {
                            proxy.scrollTo(selected, anchor: .trailing)
                        }
                    }
                }
            }

            // 새 문서 종류 선택 메뉴 — 프로젝트 아카이브/프로젝트 문서 탭에서는
            // 그 프로젝트 안에 생성한다.
            Menu {
                let target = app.creationTargetProject
                if let target {
                    Section("→ \(target.manifest.name)") {
                        newDocumentButtons(l10n, in: target)
                    }
                } else {
                    newDocumentButtons(l10n, in: nil)
                }
                Divider()
                Button(l10n.t(.newProject), systemImage: "folder.badge.plus") {
                    _ = try? app.workspace.createProject(name: l10n.t(.newProject))
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(newDocMenuHover ? SonnetPalette.ink : SonnetPalette.inkMuted)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(newDocMenuHover ? SonnetPalette.ink.opacity(0.07) : .clear)
                    )
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(
                app.creationTargetProject.map { "\(l10n.t(.newDocument)) → \($0.manifest.name)" }
                    ?? l10n.t(.newDocument)
            )
            .onHover { newDocMenuHover = $0 }
            .animation(DesignTokens.Motion.glassPop, value: newDocMenuHover)

            // 남는 가운데 여백 — 컨트롤이 없으므로 창 드래그 영역으로 쓴다.
            Spacer(minLength: 0)
                .overlay(windowDragArea)

            // 문서 컨텍스트 패널 토글 (프로젝트 파일/참조/스냅샷).
            // 좁은 창(<1120pt)에서는 하나의 overflow 메뉴로 접는다 — 활성 탭·저장 상태가 우선 (3단계 1).
            if case .document = app.selectedTab?.content {
                if headerWidth >= 1120 {
                    if selectedDocumentHasProject {
                        ToolbarIconButton("folder", help: l10n.t(.projectFiles), isActive: app.showProjectNavigator) {
                            app.showProjectNavigator.toggle()
                        }
                    }
                    ToolbarIconButton("link", help: l10n.t(.references), isActive: app.showReferencePanel) {
                        app.showReferencePanel.toggle()
                    }
                    ToolbarIconButton(
                        "clock.arrow.circlepath",
                        help: l10n.t(.snapshots),
                        isActive: app.showSnapshotPanel
                    ) {
                        app.showSnapshotPanel.toggle()
                    }
                } else {
                    panelOverflowMenu(l10n)
                }
            }
            // 새 릴리스가 발견되면 나타나는 업데이트 인디케이터 — 클릭 시 퀵메뉴
            if let update = app.availableUpdate {
                updateIndicator(update, l10n)
            }

            // '열린 탭 N ▾' — 넘침 대비 전체 탭 메뉴 (5b)
            openTabsMenu(l10n)

            // 저장 상태 배지 — 문서 탭에서만
            if let tab = app.selectedTab, let session = app.session(for: tab) {
                SaveStatusBadge(
                    state: session.saveState,
                    label: l10n.t(session.saveState.labelKey)
                ) {
                    session.save(manual: true)
                }
                .environment(\.saveErrorDetail, session.lastSaveError)
            }
        }
        .padding(.trailing, 16)
        .frame(height: 52)
        .background(titlebarBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SonnetPalette.ink.opacity(0.08))
                .frame(height: 1)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            headerWidth = width
        }
    }

    /// 좁은 창용 패널 overflow 메뉴 — 프로젝트 파일/참조/스냅샷 토글을 한 버튼에 수납.
    private func panelOverflowMenu(_ l10n: Localizer) -> some View {
        Menu {
            if selectedDocumentHasProject {
                Toggle(l10n.t(.projectFiles), isOn: Binding(
                    get: { app.showProjectNavigator },
                    set: { app.showProjectNavigator = $0 }
                ))
            }
            Toggle(l10n.t(.references), isOn: Binding(
                get: { app.showReferencePanel },
                set: { app.showReferencePanel = $0 }
            ))
            Toggle(l10n.t(.snapshots), isOn: Binding(
                get: { app.showSnapshotPanel },
                set: { app.showSnapshotPanel = $0 }
            ))
        } label: {
            Image(systemName: "sidebar.trailing")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(
                    app.showProjectNavigator || app.showReferencePanel || app.showSnapshotPanel
                        ? accent : SonnetPalette.inkMuted
                )
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(l10n.t(.projectFiles) + " · " + l10n.t(.references) + " · " + l10n.t(.snapshots))
    }

    /// '열린 탭 N ▾' 칩 — 클릭 시 전체 탭 목록 메뉴 (⌘1~9 병기).
    private func openTabsMenu(_ l10n: Localizer) -> some View {
        Menu {
            ForEach(Array(app.tabs.enumerated()), id: \.element.id) { index, tab in
                Button {
                    app.selectExistingTab(tab)
                } label: {
                    if index < 9 {
                        Text("\(app.tabTitle(for: tab))  ⌘\(index + 1)")
                    } else {
                        Text(app.tabTitle(for: tab))
                    }
                }
            }
        } label: {
            Text("\(l10n.t(.openTabs)) \(app.tabs.count) ▾")
                .font(DSFonts.font(size: 11.5, weight: .medium, family: .pretendard))
                .foregroundStyle(SonnetPalette.inkSoft)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(SonnetPalette.ink.opacity(0.05))
                )
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// 업데이트 가능 인디케이터 — 액센트 점 배지가 붙은 다운로드 아이콘.
    private func updateIndicator(_ update: UpdateInfo, _ l10n: Localizer) -> some View {
        ZStack(alignment: .topTrailing) {
            ToolbarIconButton(
                "arrow.down.circle",
                help: String(format: l10n.t(.updateAvailableFormat), update.version),
                isActive: showUpdateMenu
            ) {
                // 탭 스트립 디프 중 popover 앵커 미확정 크래시 방지 — 한 틱 지연 (macOS 26)
                DispatchQueue.main.async { showUpdateMenu = true }
            }
            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
                .offset(x: -4, y: 4)
                .allowsHitTesting(false)
        }
        .popover(isPresented: $showUpdateMenu, arrowEdge: .bottom) {
            UpdateQuickMenu(update: update) { showUpdateMenu = false }
                .environment(app)
        }
    }

    /// 창 이동 전용 드래그 영역 — 컨트롤이 없는 빈 영역에서만 동작.
    private var windowDragArea: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
    }

    /// 새 문서 4종 버튼 — 대상 프로젝트가 있으면 그 안에, 없으면 최상위에.
    @ViewBuilder
    private func newDocumentButtons(_ l10n: Localizer, in project: ProjectFolder?) -> some View {
        Button(l10n.t(.newScenario), systemImage: "text.bubble") {
            app.createAndOpen(kind: .scenario, in: project)
        }
        Button(l10n.t(.newMindMap), systemImage: "point.3.connected.trianglepath.dotted") {
            app.createAndOpen(kind: .mindmap, in: project)
        }
        Button(l10n.t(.newPage), systemImage: "doc.richtext") {
            app.createAndOpen(kind: .page, in: project)
        }
        Button(l10n.t(.newCharacter), systemImage: "person.crop.circle.badge.plus") {
            app.createAndOpen(kind: .page, pageRole: .character, in: project)
        }
    }

    /// 헤더 배경 — Liquid Glass (끔/저사양이면 평면 시트 톤).
    /// 워시 불투명도는 설정의 유리 강도를 따른다 — 강도가 낮을수록 뒤 캔버스가 더 비친다.
    @ViewBuilder
    private var titlebarBackground: some View {
        ZStack {
            if glassDisabled {
                SonnetPalette.surface
            } else {
                Rectangle().fill(.ultraThinMaterial)
                SonnetPalette.surface.opacity(0.15 + 0.65 * glassIntensity)
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - 문서 탭 칩 (5b)
// 활성: Sheet 백지 카드 + 그림자 / 비활성: 투명, 호버 잉크 워시.
// 미저장 점 → 호버 시 ✕ · 드래그 재정렬 · ⌘1~9 · 더블클릭 이름 변경.

struct TabChip: View {
    @Environment(AppState.self) private var app
    @Environment(\.resolvedAccent) private var accent
    let tab: OpenTab

    @State private var hovering = false
    @State private var renaming = false
    @State private var draftTitle = ""

    private var isSelected: Bool { app.selectedTabID == tab.id }

    /// 문서 탭이면 해당 세션 (이름 변경 대상)
    private var documentSession: DocumentSession? {
        if case .document(let docID) = tab.content {
            return app.sessions[docID]
        }
        return nil
    }

    private var hasUnsavedChanges: Bool {
        guard let state = documentSession?.saveState else { return false }
        return state == .unsaved || state == .saving
    }

    var body: some View {
        HStack(spacing: 8) {
            tabIcon
            Text(app.tabTitle(for: tab))
                .font(DSFonts.font(size: 12.5, weight: isSelected ? .semibold : .medium, family: .pretendard))
                .foregroundStyle(isSelected ? SonnetPalette.ink : SonnetPalette.inkSoft)
                .lineLimit(1)
                .truncationMode(.tail)

            // 미저장 표시 — 브라우저 관례처럼 호버 전에는 점, 호버하면 닫기 버튼.
            // 홈 탭은 닫아도 곧바로 재생성되므로 X를 아예 숨긴다 (⌘W/우클릭은 유지).
            if tab.content != .home {
                ZStack {
                    if hasUnsavedChanges, !hovering {
                        // 미저장 점은 Dirty/Warning 골드 — 버밀리온과 의미 분리 (2단계)
                        Circle()
                            .fill(SonnetPalette.warning)
                            .frame(width: 7, height: 7)
                            .transition(.opacity.combined(with: .scale(scale: 0.5)))
                    }
                    Button {
                        app.closeTab(tab)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(SonnetPalette.inkMuted)
                            .frame(width: 16, height: 16)
                            .background(
                                Circle().fill(SonnetPalette.ink.opacity(hovering ? 0.08 : 0))
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(hovering ? 1 : 0)
                    .help(Localizer.shared.t(.close) + " (⌘W)")
                    .accessibilityLabel(Localizer.shared.t(.close))
                }
                .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .frame(maxWidth: 210)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SonnetPalette.surface)
                    .shadow(color: SonnetPalette.ink.opacity(0.12), radius: 4, y: 2)
            } else if hovering {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SonnetPalette.ink.opacity(0.06))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginRename() }
        .onTapGesture { app.selectExistingTab(tab) }
        // 드래그로 탭 순서 재배치 (브라우저 관례) — ⌘1~9 번호도 새 순서를 따른다
        .onDrag {
            app.draggingTabID = tab.id
            return NSItemProvider(object: tab.id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: TabReorderDropDelegate(target: tab, app: app))
        .onHover { hovering = $0 }
        .contextMenu {
            let l10n = Localizer.shared
            if let session = documentSession {
                // 읽기 전용 문서는 이름 변경 금지 (지시서 1단계 4)
                Button(l10n.t(.rename)) { beginRename() }
                    .disabled(session.isReadOnly)
                Divider()
                // 우측 패널 토글 — 프로젝트 파일 인스펙터는 프로젝트 소속 문서에서만
                if app.workspace.project(id: session.document.envelope.projectID) != nil {
                    Toggle(l10n.t(.projectFiles), isOn: Binding(
                        get: { app.showProjectNavigator },
                        set: { app.showProjectNavigator = $0 }
                    ))
                }
                Toggle(l10n.t(.references), isOn: Binding(
                    get: { app.showReferencePanel },
                    set: { app.showReferencePanel = $0 }
                ))
                Divider()
            }
            Button(l10n.t(.close)) { app.closeTab(tab) }
            // 닫기 계열은 탭별로 기존 닫기 확인 흐름(저장 실패 다이얼로그)을 재사용한다
            Button(l10n.t(.closeOtherTabs)) { app.closeOtherTabs(than: tab) }
                .disabled(app.tabs.count <= 1)
            Button(l10n.t(.closeTabsToRight)) { app.closeTabsToTheRight(of: tab) }
                .disabled(app.tabs.last?.id == tab.id)
        }
        .popover(isPresented: $renaming, arrowEdge: .bottom) {
            renamePopover
        }
        .animation(DesignTokens.Motion.glassPop, value: hovering)
        .animation(DesignTokens.Motion.glassPop, value: isSelected)
    }

    /// 탭 아이콘 — 문서는 유형 글리프(유형색), 시스템 탭은 SF 심볼.
    @ViewBuilder
    private var tabIcon: some View {
        if let type = app.fileType(for: tab) {
            FileTypeIcon(type, size: 14)
        } else {
            Image(systemName: app.tabSymbol(for: tab))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? accent : SonnetPalette.inkMuted)
        }
    }

    private func beginRename() {
        // 읽기 전용 세션은 제목 변경이 저장되지 않으므로 시작조차 하지 않는다
        guard let session = documentSession, !session.isReadOnly else { return }
        draftTitle = session.title
        // 탭 ForEach가 재배치/디프 중일 때 popover를 열면 앵커 뷰가 아직
        // 윈도우 계층에서 확정되지 않아 NSPopover가 크래시한다 (macOS 26).
        DispatchQueue.main.async { renaming = true }
    }

    private var renamePopover: some View {
        let l10n = Localizer.shared
        return HStack(spacing: 6) {
            TextField(l10n.t(.untitled), text: $draftTitle)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit(commitRename)
            Button(l10n.t(.done), action: commitRename)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(10)
    }

    private func commitRename() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            documentSession?.title = trimmed
        }
        renaming = false
    }
}

/// 탭 드래그 재정렬 — 드래그한 칩이 다른 칩 위로 들어오는 순간 자리를 바꾼다 (라이브 리오더).
private struct TabReorderDropDelegate: DropDelegate {
    let target: OpenTab
    let app: AppState

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated {
            guard let draggingID = app.draggingTabID, draggingID != target.id,
                  let from = app.tabs.firstIndex(where: { $0.id == draggingID }),
                  let to = app.tabs.firstIndex(where: { $0.id == target.id })
            else { return }
            withAnimation(DesignTokens.Motion.glassPop) {
                app.tabs.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated { app.draggingTabID = nil }
        return true
    }
}

// MARK: - 문서 호스트 (에디터 렌더링 영역)

struct DocumentHostView: View {
    @Environment(AppState.self) private var app
    @Bindable var session: DocumentSession

    var body: some View {
        editorView
            .environment(\.readOnlyMode, $session.isReadOnly)
            .environment(\.saveErrorDetail, session.lastSaveError)
    }

    @ViewBuilder
    private var editorView: some View {
        switch session.editor {
        case .scenario(let store):
            ScenarioEditorView(
                store: store,
                breadcrumb: app.breadcrumb(for: session),
                saveState: session.saveState,
                onManualSave: { session.save(manual: true) },
                onOpenCharacterPage: { app.openDocument(id: $0) },
                onCreateCharacterPage: { app.createCharacterPage(for: $0, linkedTo: session) },
                // 우측은 프로젝트 파일 인스펙터 자리 — 캐릭터 인스펙터는 항상 좌측 고정
                inspectorOnRight: false
            )
        case .mindmap(let store):
            MindMapEditorView(
                store: store,
                breadcrumb: app.breadcrumb(for: session),
                saveState: session.saveState,
                onManualSave: { session.save(manual: true) },
                onOpenDocument: { app.openDocument(id: $0) }
            )
        case .page(let store):
            PageEditorView(
                store: store,
                title: Binding(
                    get: { session.title },
                    set: { session.title = $0 }
                ),
                breadcrumb: app.breadcrumb(for: session),
                saveState: session.saveState,
                onManualSave: { session.save(manual: true) }
            )
        }
    }
}

// MARK: - 플로팅 에이전트 패널

/// 문서를 벗어나지 않고 에이전트와 대화하는 플로팅 패널 — AIChatView(compact)를
/// 글래스 카드로 감싼다 (1b: 우하단 AI 패널, glass pop 280ms 진입).
struct FloatingChatPanel: View {
    @Environment(AppState.self) private var app

    var body: some View {
        AIChatView(compact: true)
            .frame(width: 400, height: 520)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(SonnetPalette.canvas)
                    .shadow(color: SonnetPalette.ink.opacity(0.22), radius: 25, y: 9)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(SonnetPalette.ink.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    app.showFloatingChat = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(SonnetPalette.inkMuted)
                        .background(Circle().fill(SonnetPalette.canvas))
                }
                .buttonStyle(PressBounceButtonStyle())
                .help(Localizer.shared.t(.close) + " (⇧⌘A)")
                .offset(x: 7, y: -7)
            }
            .padding(.trailing, DesignTokens.Spacing.l)
            .padding(.bottom, DesignTokens.Spacing.l)
    }
}
