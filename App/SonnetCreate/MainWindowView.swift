import AppCore
import DesignSystem
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
            Text(items.count > 1 ? Localizer.shared.t(.permanentDeleteConfirmMessagePlural) : Localizer.shared.t(.permanentDeleteConfirmMessage))
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
                    if app.showReferencePanel {
                        Divider().opacity(0.4)
                        ReferencePanelView(session: session)
                            .frame(width: 250)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(DesignTokens.Motion.gentle, value: app.showReferencePanel)
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

    private var isChrome: Bool { app.settings.applied.tabStyleRaw == "chrome" }
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: isChrome ? 0 : 4) {
                    ForEach(Array(app.tabs.enumerated()), id: \.element.id) { index, tab in
                        TabChip(tab: tab, isFirst: index == 0)
                    }
                }
                .padding(.leading, isChrome ? 6 : 4)
                .padding(.top, isChrome ? 5 : 3)
            }

            // 새 문서 종류 선택 메뉴
            Menu {
                Button(l10n.t(.newScenario), systemImage: "text.bubble") {
                    app.createAndOpen(kind: .scenario)
                }
                Button(l10n.t(.newMindMap), systemImage: "point.3.connected.trianglepath.dotted") {
                    app.createAndOpen(kind: .mindmap)
                }
                Button(l10n.t(.newPage), systemImage: "doc.richtext") {
                    app.createAndOpen(kind: .page)
                }
                Button(l10n.t(.newCharacter), systemImage: "person.crop.circle.badge.plus") {
                    app.createAndOpen(kind: .page, pageRole: .character)
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

            Spacer(minLength: 0)

            // 우측 액션 (기존 툴바에서 이전)
            if case .document = app.selectedTab?.content {
                ToolbarIconButton("link", help: l10n.t(.references), isActive: app.showReferencePanel) {
                    app.showReferencePanel.toggle()
                }
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
        // 탭바 빈 영역 드래그로 창 이동 (타이틀바 역할)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
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
                (theme.isBranded ? SonnetPalette.sunken : Color.primary.opacity(0.06))
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
                .opacity(hovering || isSelected ? 1 : 0)
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
        .onHover { hovering = $0 }
        .contextMenu {
            let l10n = Localizer.shared
            if documentSession != nil {
                Button(l10n.t(.rename)) { beginRename() }
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
        guard let session = documentSession else { return }
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
        switch session.editor {
        case .scenario(let store):
            ScenarioEditorView(
                store: store,
                breadcrumb: app.breadcrumb(for: session),
                saveState: session.saveState,
                onManualSave: { session.save(manual: true) },
                onOpenCharacterPage: { app.openDocument(id: $0) },
                onCreateCharacterPage: { app.createCharacterPage(for: $0, linkedTo: session) },
                inspectorOnRight: app.settings.applied.scenarioInspectorOnRight
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
