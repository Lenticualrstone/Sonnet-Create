import AppCore
import DesignSystem
import DocumentKit
import FileManagerKit
import MarkdownEditor
import MindMapEditor
import RenderingKit
import ScenarioEditor
import SwiftUI

/// 메인 윈도우 — Wavy Dot 배경 + 사이드바 + 탭 스트립 + 콘텐츠.
struct MainWindowView: View {
    @Environment(AppState.self) private var app
    @Environment(\.renderQuality) private var quality
    @Environment(\.colorScheme) private var colorScheme
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showCommandPalette = false
    /// 프로젝트 파일 인스펙터 폭 — 드래그로 조절, 재시작 후에도 유지
    @AppStorage("project-navigator-width") private var navigatorWidth = 232.0
    @State private var navigatorDragBaseWidth: Double?

    var body: some View {
        // 헤더는 사이드바/콘텐츠 그 어느 쪽에도 귀속되지 않는 프로그램 전체의 유일한
        // 상단 크롬이다 — NavigationSplitView 바깥에서 전체 폭을 한 번만 차지하고,
        // 그 아래에 사이드바와 콘텐츠가 나란히 존재한다. 안전영역 무시(ignoresSafeArea)도
        // 이 트리에서 단 한 곳(맨 아래 .modifier)에서만 일어나— 예전에 사이드바 컬럼과
        // 콘텐츠 컬럼이 각자 따로 안전영역을 무시하다 전체화면에서 어긋나며 생기던
        // "흰 박스" 이음매 버그가 구조적으로 발생할 수 없다.
        VStack(spacing: 0) {
            ChromeTabBar(columnVisibility: $columnVisibility)

            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView()
                    // min을 260으로 올려 홈/Sonnet AI/수신함 3개 탭의 아이콘+텍스트가
                    // 줄바꿈되지 않고 한 줄에 들어갈 최소 폭을 항상 보장한다.
                    .navigationSplitViewColumnWidth(min: 260, ideal: 264, max: 340)
                    // 사이드바 상단의 시스템 툴바(백색 박스 원인) 제거
                    .toolbar(removing: .sidebarToggle)
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            } detail: {
                ZStack {
                    // 브랜드 테마(Sonnet/Pilgrimage): 테마별 캔버스가 모든 레이어의 바닥
                    if app.settings.applied.interfaceTheme.isBranded {
                        app.settings.applied.interfaceTheme.canvasColor.ignoresSafeArea()
                    }
                    background
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            }
        }
        // 윈도우 모드에서만 헤더를 타이틀 라인(신호등 뒤)까지 끌어올린다.
        // 전체화면에서는 그대로 두어야 한다 — 무조건 ignoresSafeArea하면
        // 전체화면의 (더 큰) 상단 안전영역만큼 헤더가 화면 밖으로 밀려나 사라진다.
        .modifier(TopChromeExtension(active: !app.isFullscreen))
        // ⌘K 커맨드 팔레트 — 어디서든 문서 점프/빠른 명령
        .overlay {
            if showCommandPalette {
                CommandPaletteView(isPresented: $showCommandPalette)
            }
        }
        .background {
            Button("") {
                withAnimation(DesignTokens.Motion.snappy) { showCommandPalette.toggle() }
            }
            .keyboardShortcut("k", modifiers: .command)
            .buttonStyle(.plain)
            .opacity(0)
            .accessibilityHidden(true)
        }
        .navigationTitle("")
        // 크롬(버튼/탭/툴바)의 안내 텍스트가 커서로 선택되는 것을 방지.
        // 본문 텍스트 선택이 필요한 곳(시나리오 블록 등)은 개별적으로 다시 활성화한다.
        .textSelection(.disabled)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            withAnimation(DesignTokens.Motion.gentle) { app.isFullscreen = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            withAnimation(DesignTokens.Motion.gentle) { app.isFullscreen = false }
        }
        // 휴지통 이동 확인
        .confirmationDialog(
            Localizer.shared.t(.moveToTrash),
            isPresented: Binding(
                get: { app.pendingTrashItem != nil },
                set: { if !$0 { app.pendingTrashItem = nil } }
            ),
            presenting: app.pendingTrashItem
        ) { item in
            Button("\(Localizer.shared.t(.moveToTrash)): \(item.envelope.title)", role: .destructive) {
                app.confirmPendingTrash()
            }
            Button(Localizer.shared.t(.cancel), role: .cancel) {}
        } message: { _ in
            Text(Localizer.shared.t(.trashConfirmMessage))
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

    /// 시그니처 배경 — 설정에서 켠 경우에만 (기본 꺼짐).
    @ViewBuilder
    private var background: some View {
        if app.settings.applied.backgroundEffectEnabled {
            wavyField
        }
    }

    private var wavyField: some View {
        let s = app.settings.applied
        return WavyDotFieldView(
            configuration: WavyDotFieldConfiguration(
                speed: s.backgroundSpeed,
                density: s.backgroundDensity,
                amplitude: 1.0,
                vignette: 0.75,
                blurRadius: app.isHomeSelected ? 0 : s.backgroundBlurOthers,
                dotScale: s.backgroundDotSize,
                pitch: s.backgroundPitch
            ),
            // 다크에서는 더 밝게, 라이트에서는 절제되게 — 시인성/대비 튜닝
            tint: dotTint,
            quality: quality
        )
        .opacity(app.isHomeSelected ? 1 : 0.4)
        .ignoresSafeArea()
        .animation(DesignTokens.Motion.gentle, value: app.isHomeSelected)
    }

    private var dotTint: Color {
        let s = app.settings.applied
        if s.backgroundUseAccent {
            return app.resolvedAccent.opacity(colorScheme == .dark ? 0.62 : 0.5)
        }
        if s.interfaceTheme.isBranded {
            return SonnetPalette.dot.opacity(colorScheme == .dark ? 0.5 : 0.4)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.52 : 0.36)
    }

    /// 탭 전환 시 부드러운 크로스페이드 + 미세한 상승 전환.
    @ViewBuilder
    private var content: some View {
        ZStack {
            if let tab = app.selectedTab {
                tabContent(tab)
                    .id(tab.id)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .animation(DesignTokens.Motion.gentle, value: app.selectedTabID)
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
                }
            )
        case .document(let docID):
            if let session = app.sessions[docID] {
                HStack(spacing: 0) {
                    DocumentHostView(session: session)
                    // 프로젝트 파일 인스펙터 — 프로젝트 소속 문서에서만. 사이드바가 프로젝트
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
                .animation(DesignTokens.Motion.gentle, value: app.showReferencePanel)
                .animation(DesignTokens.Motion.gentle, value: app.showSnapshotPanel)
                .animation(DesignTokens.Motion.gentle, value: app.showProjectNavigator)
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

// MARK: - Chrome-tabs 스타일 탭바
// 참고: github.com/adamschwartz/chrome-tabs — 좌측 정렬 유동 폭 탭,
// 활성 탭은 콘텐츠 캔버스와 병합, 비활성 탭 사이 세로 구분선.

struct ChromeTabBar: View {
    @Environment(AppState.self) private var app
    @Environment(\.interfaceTheme) private var theme
    @Environment(\.resolvedAccent) private var accent
    @Binding var columnVisibility: NavigationSplitViewVisibility

    @State private var newDocMenuHover = false
    @State private var showUpdateMenu = false

    private var isChrome: Bool { app.settings.applied.tabStyleRaw == "chrome" }
    /// 현재 선택된 문서가 프로젝트 소속인지 — 프로젝트 파일 인스펙터 토글 노출 조건.
    private var selectedDocumentHasProject: Bool {
        guard let tab = app.selectedTab, let session = app.session(for: tab) else { return false }
        return app.workspace.project(id: session.document.envelope.projectID) != nil
    }

    /// 헤더가 항상 창 최상단 전체 폭을 차지하므로, 사이드바 펼침/접힘과 무관하게
    /// 윈도우 모드에서는 항상 좌측에 신호등 자리를 남겨야 한다.
    private var needsTrafficLightInset: Bool { !app.isFullscreen }
    /// 현재 테마에 맞는 브랜드 마크 이미지셋 이름.
    private var brandMarkImageName: String {
        switch app.settings.applied.interfaceTheme {
        case .sonnet: "BrandMark"
        case .pilgrimage: "BrandMark-Pilgrimage"
        case .system: "BrandMark-System"
        }
    }

    var body: some View {
        let l10n = Localizer.shared
        HStack(spacing: isChrome ? 0 : 6) {
            // 브랜드 앵커 — 프로젝트의 실제 앱 아이콘(깃털 로고) 아트워크를 그대로 축소해
            // 쓴다. 예전엔 존재하지 않는 SF Symbol "feather"를 참조해 빈 화면으로
            // 렌더링됐다. AppIcon.appiconset은 앱 번들 아이콘 전용 슬롯이라 일반 Image(_:)/
            // NSApp.applicationIconImage로는 안정적으로 불러와지지 않아, 같은 아트워크를
            // 복사한 별도의 BrandMark 이미지셋(테마별 색상 바리에이션 포함)을 참조한다.
            // 헤더가 창 전체 폭을 차지하므로 항상 보이되, 윈도우 모드에서는 신호등 자리만큼
            // 왼쪽 여백을 더 준다.
            Image(brandMarkImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .padding(.leading, needsTrafficLightInset ? 76 : 12)
                .padding(.trailing, 4)
                // 신호등 옆 브랜드 구역은 타이틀바처럼 창을 끌 수 있다
                .background(windowDragArea)

            // 사이드바 토글 (시스템 툴바 제거에 따른 대체)
            ToolbarIconButton(
                "sidebar.left",
                help: l10n.t(.workspace),
                isActive: columnVisibility != .detailOnly
            ) {
                withAnimation(DesignTokens.Motion.gentle) {
                    columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                }
            }
            .padding(.leading, 6)

            // 뒤로/앞으로 탐색 — 편집 되돌리기(⌘Z)와 무관, 탐색 중인 화면(문서/아카이브 카테고리·
            // 프로젝트 필터)의 이동 기록을 오간다.
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
                    HStack(spacing: isChrome ? 0 : 4) {
                        ForEach(Array(app.tabs.enumerated()), id: \.element.id) { index, tab in
                            TabChip(tab: tab, isFirst: index == 0)
                                .id(tab.id)
                        }
                    }
                    .padding(.leading, isChrome ? 6 : 4)
                    .padding(.top, isChrome ? 5 : 3)
                    // 탭 스트립에서는 시스템 타이틀바 창 끌기를 차단 — 칩 드래그(순서 변경)와 경합 방지
                    .background(BlockWindowDrag())
                }
                // 칩 상단(활성 언더라인)이 스크롤 뷰 경계에 잘리지 않게 한다
                .scrollClipDisabled()
                // 탭이 많아 가려질 때 선택 탭을 항상 시야로 데려온다
                .onChange(of: app.selectedTabID) { _, selected in
                    if let selected {
                        withAnimation(DesignTokens.Motion.gentle) {
                            proxy.scrollTo(selected, anchor: .trailing)
                        }
                    }
                }
            }

            // 새 문서 종류 선택 메뉴 — 프로젝트 아카이브/프로젝트 문서 탭에서는
            // 그 프로젝트 안에 생성한다 (헤더에서 만든 문서가 무소속으로 떨어지던 문제 수정).
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
                    .foregroundStyle(newDocMenuHover ? accent : .secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                            .fill(newDocMenuHover ? accent.opacity(0.1) : .clear)
                    )
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(l10n.t(.newDocument))
            .onHover { newDocMenuHover = $0 }
            .animation(DesignTokens.Motion.snappy, value: newDocMenuHover)

            // 남는 가운데 여백 — 컨트롤이 없으므로 창 드래그 영역으로 쓴다.
            // (Color 기반 뷰는 탭 스크롤뷰와 폭을 반분해 + 버튼이 가운데로 밀린다 —
            //  레이아웃은 Spacer가 담당하고 드래그 히트 영역만 overlay로 얹는다)
            Spacer(minLength: 0)
                .overlay(windowDragArea)

            // 우측 액션 (기존 툴바에서 이전)
            if case .document = app.selectedTab?.content {
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
                    help: Localizer.shared.t(.snapshots),
                    isActive: app.showSnapshotPanel
                ) {
                    app.showSnapshotPanel.toggle()
                }
            }
            // 새 릴리스가 발견되면 나타나는 업데이트 인디케이터 — 클릭 시 퀵메뉴
            if let update = app.availableUpdate {
                updateIndicator(update, l10n)
            }
            ToolbarIconButton("archivebox", help: l10n.t(.archive)) {
                app.openArchiveTab()
            }
            ToolbarIconButton("sparkles", help: l10n.t(.aiAgent)) {
                app.openAIChatTab()
            }
            .padding(.trailing, 8)
        }
        .frame(height: 38)
        .background(barBackground)
        .overlay(alignment: .bottom) {
            if isChrome {
                Divider().opacity(0.35)
            }
        }
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

    /// 창 이동 전용 드래그 영역 — 예전엔 탭바 전체 배경에 WindowDragGesture를 깔아서
    /// 탭 칩을 드래그해 순서를 바꾸려 하면 창 전체가 따라 움직였다. 이제 창 드래그는
    /// 컨트롤이 없는 빈 영역(브랜드 마크 주변, 우측 여백)에서만 동작한다.
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

    @ViewBuilder
    private var barBackground: some View {
        // 헤더가 NavigationSplitView 바깥의 독립된 최상위 뷰라 뒤에 깔린 캔버스가
        // 없다 — 탭 스타일과 무관하게 항상 불투명한 테마 베이스로 채워야 신호등
        // 뒤 코너에 창의 기본 배경색(흰 박스)이 비쳐 보이지 않는다.
        ZStack {
            Rectangle()
                .fill(theme.isBranded ? AnyShapeStyle(theme.canvasColor) : AnyShapeStyle(Color(nsColor: .windowBackgroundColor)))
            if isChrome {
                // 탭바는 콘텐츠보다 가라앉은 톤 — 활성 탭이 캔버스색으로 떠오른다
                theme.isBranded ? SonnetPalette.sunken : Color.primary.opacity(0.06)
                if theme.isBranded {
                    // 앤티크 페이퍼 무드를 강화하는 미세 그레인
                    GrainOverlay(color: SonnetPalette.ink, opacity: 0.045, density: 500)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}

struct TabChip: View {
    @Environment(AppState.self) private var app
    @Environment(\.renderQuality) private var quality
    @Environment(\.resolvedAccent) private var accent
    let tab: OpenTab
    var isFirst: Bool = false

    @State private var hovering = false
    @State private var renaming = false
    @State private var draftTitle = ""

    private var isSelected: Bool { app.selectedTabID == tab.id }
    private var isChrome: Bool { app.settings.applied.tabStyleRaw == "chrome" }

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
        HStack(spacing: 0) {
            // 비활성 탭 사이 세로 구분선 (chrome-tabs 시그니처)
            if isChrome, !isFirst {
                Rectangle()
                    .fill(Color.primary.opacity(isSelected || hovering ? 0 : 0.18))
                    .frame(width: 1, height: 16)
            }

            HStack(spacing: 6) {
                Image(systemName: app.tabSymbol(for: tab))
                    .font(.caption)
                    .foregroundStyle(isSelected ? accent : Color.secondary)
                Text(app.tabTitle(for: tab))
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // 미저장 표시 — 브라우저 관례처럼 호버 전에는 점, 호버하면 닫기 버튼.
                // 홈 탭은 닫아도 곧바로 재생성되므로 X를 아예 숨긴다 (⌘W/우클릭은 유지).
                if tab.content != .home {
                    ZStack {
                        if hasUnsavedChanges, !hovering {
                            Circle()
                                .fill(accent.opacity(0.85))
                                .frame(width: 7, height: 7)
                                .transition(.opacity.combined(with: .scale(scale: 0.5)))
                        }
                        Button {
                            app.closeTab(tab)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 17, height: 17)
                                .background(
                                    Circle().fill(Color.primary.opacity(hovering ? 0.09 : 0))
                                )
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .opacity(hovering ? 1 : (isSelected && !hasUnsavedChanges ? 1 : 0))
                    }
                    .frame(width: 17, height: 17)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, isChrome ? 7 : 5)
            .frame(minWidth: isChrome ? 130 : nil, maxWidth: isChrome ? 210 : 190)
            .modifier(TabChipStyle(
                chrome: isChrome,
                isSelected: isSelected,
                hovering: hovering,
                quality: quality
            ))
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
                Button(l10n.t(.rename)) { beginRename() }
                    .disabled(session.isReadOnly)
                Divider()
            }
            Button(l10n.t(.close)) { app.closeTab(tab) }
        }
        .popover(isPresented: $renaming, arrowEdge: .bottom) {
            renamePopover
        }
        .animation(DesignTokens.Motion.snappy, value: hovering)
        .animation(DesignTokens.Motion.snappy, value: isSelected)
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
            withAnimation(DesignTokens.Motion.snappy) {
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

/// 탭 모양 — 캡슐(기본) 또는 Chrome식 사각.
struct TabChipStyle: ViewModifier {
    let chrome: Bool
    let isSelected: Bool
    let hovering: Bool
    let quality: RenderQuality

    @Environment(\.interfaceTheme) private var theme
    @Environment(\.resolvedAccent) private var accent

    func body(content: Content) -> some View {
        if chrome {
            // 활성 탭이 아래 콘텐츠 캔버스로 흘러들어가는 chrome-tabs 룩
            content
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 9, bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0, topTrailingRadius: 9,
                        style: .continuous
                    )
                    .fill(chromeFill)
                )
                // "지금 여기" 정체성 — 활성 탭 상단에 강조색 언더라인
                .overlay(alignment: .top) {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(accent)
                            .frame(height: 2)
                            .padding(.horizontal, 8)
                            .transition(.opacity)
                    }
                }
                .opacity(isSelected ? 1 : 0.85)
        } else {
            content
                .glassCapsule(
                    tint: isSelected ? accent : nil,
                    interactive: true,
                    quality: quality
                )
                .opacity(isSelected ? 1 : 0.75)
        }
    }

    private var chromeFill: Color {
        // 활성 탭 = 콘텐츠 캔버스색 → 병합되어 보임
        let active = theme.isBranded ? theme.canvasColor : Color(nsColor: .windowBackgroundColor)
        let hover = theme.isBranded ? SonnetPalette.surface.opacity(0.5) : Color.primary.opacity(0.05)
        if isSelected { return active }
        if hovering { return hover }
        return .clear
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
