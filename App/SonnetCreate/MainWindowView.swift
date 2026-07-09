import AppCore
import AppKit
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
    /// 전체화면 전용 플로팅 사이드바의 표시 여부 (구조적 사이드바 컬럼과는 별개 상태).
    @State private var floatingSidebarVisible = true

    private var showFloatingSidebar: Bool { app.isFullscreen && floatingSidebarVisible }
    /// 플로팅 패널 폭(280) + 좌측 여백(10) + 콘텐츠와의 여유 간격(10) — 콘텐츠가 이만큼
    /// "가짜로" 비워두면, 패널을 닫을 때 이 여백이 사라지며 자연스럽게 확장된다.
    private let floatingSidebarReservedWidth: CGFloat = 300

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // 전체화면에서는 이 컬럼을 비워둔다. columnVisibility를 .detailOnly로 접어도
            // macOS는 창 왼쪽 가장자리에 마우스를 대면 접힌 사이드바를 임시로 "미리보기"
            // 형태로 다시 드러내는 자체 제스처가 있어서, 실제 SidebarView를 넣어두면
            // 우리가 피하려던 버그 있는 컬럼이 호버만으로 다시 나타나 버렸다.
            // 내용이 비어있으면 호버해도 보여줄 게 없어 그 문제가 사라진다.
            if !app.isFullscreen {
                SidebarView()
                    // min을 260으로 올려 홈/Sonnet AI/수신함 3개 탭의 아이콘+텍스트가
                    // 줄바꿈되지 않고 한 줄에 들어갈 최소 폭을 항상 보장한다.
                    .navigationSplitViewColumnWidth(min: 260, ideal: 264, max: 340)
                    // 사이드바 상단의 시스템 툴바(백색 박스 원인) 제거
                    .toolbar(removing: .sidebarToggle)
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                    // 윈도우 모드에서만 콘텐츠를 타이틀 라인(신호등 뒤)까지 끌어올린다.
                    // 전체화면에서는 그대로 두어야 한다 — 무조건 ignoresSafeArea하면
                    // 전체화면의 (더 큰) 상단 안전영역만큼 헤더가 화면 밖으로 밀려나 사라진다.
                    .modifier(TopChromeExtension(active: true))
            } else {
                Color.clear
                    .toolbar(removing: .sidebarToggle)
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            }
        } detail: {
            ZStack(alignment: .topLeading) {
                // Sonnet 테마: 본톤 캔버스가 모든 레이어의 바닥
                if app.settings.applied.interfaceTheme == .sonnet {
                    SonnetPalette.canvas.ignoresSafeArea()
                }
                background

                VStack(spacing: 0) {
                    // 탭바가 곧 타이틀 라인 — 신호등과 같은 줄에 토글/탭/도구막대. 탭바 자체는
                    // 전체 폭을 유지하고(플로팅 패널이 그 아래에서 시작하므로 겹치지 않는다),
                    // 문서 콘텐츠만 플로팅 패널이 차지하는 만큼 여백을 두어 "가짜 예약 영역"을
                    // 만든다 — 패널을 닫으면 이 여백이 사라지며 콘텐츠가 자연스럽게 확장된다.
                    ChromeTabBar(
                        columnVisibility: $columnVisibility,
                        floatingSidebarVisible: $floatingSidebarVisible,
                        needsTrafficLightInset: columnVisibility == .detailOnly && !app.isFullscreen
                    )
                    content
                        .padding(.leading, showFloatingSidebar ? floatingSidebarReservedWidth : 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .modifier(TopChromeExtension(active: !app.isFullscreen))

                // 전체화면 전용 — NavigationSplitView의 사이드바 컬럼은 macOS에서 툴바
                // 안전영역을 이중으로 잘못 예약하는 SwiftUI 버그(rdar://122947424)가 있어
                // 전체화면에서는 그 컬럼을 아예 접어두고(.detailOnly), 대신 헤더 아래
                // 콘텐츠 위에 자연스럽게 얹히는 플로팅 패널로 사이드바를 대체한다.
                if showFloatingSidebar {
                    SidebarView(isFloating: true)
                        .frame(width: 280)
                        .frame(maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.large, style: .continuous)
                                .fill(
                                    app.settings.applied.interfaceTheme == .sonnet
                                        ? AnyShapeStyle(SonnetPalette.sunken)
                                        : AnyShapeStyle(.regularMaterial)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.large, style: .continuous)
                                .strokeBorder(SonnetPalette.accent.opacity(0.14), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.large, style: .continuous))
                        .shadow(color: .black.opacity(0.22), radius: 20, y: 8)
                        // 탭바 높이(전체화면 메뉴바 여백 20 + 탭바 38 = 58)보다 확실히 아래에서
                        // 시작해야 탭바 영역을 침범하지 않는다.
                        .padding(.top, 64)
                        .padding(.leading, 10)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            // 콘텐츠 여백/플로팅 패널의 등장·퇴장을 하나의 트랜잭션으로 함께 애니메이션한다.
            // (각각 따로 .animation을 걸면 등장은 되는데 퇴장이 즉시 컷되는 비대칭이 생겼다.)
            .animation(DesignTokens.Motion.gentle, value: floatingSidebarVisible)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
        .navigationTitle("")
        // 크롬(버튼/탭/툴바)의 안내 텍스트가 커서로 선택되는 것을 방지.
        // 본문 텍스트 선택이 필요한 곳(시나리오 블록 등)은 개별적으로 다시 활성화한다.
        .textSelection(.disabled)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
            withAnimation(DesignTokens.Motion.gentle) {
                app.isFullscreen = true
                // NavigationSplitView의 구조적 사이드바 컬럼은 전체화면에서 macOS 툴바
                // 안전영역 버그(rdar://122947424)를 겪는다 — 아예 접어두고 플로팅 패널로 대체.
                columnVisibility = .detailOnly
            }
            // macOS는 전체화면 전환 시 별도의 시스템 툴바 영역을 다시 노출시키는 경우가
            // 있다 (창모드용 toolbarBackgroundVisibility 설정이 전체화면에는 안 이어짐) —
            // 사이드바 위쪽에 정체불명의 흰 박스로 보이던 원인. 전체화면 진입 시점에
            // 툴바를 명시적으로 다시 숨긴다.
            if let window = notification.object as? NSWindow {
                window.toolbar?.isVisible = false
                window.titlebarAppearsTransparent = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            withAnimation(DesignTokens.Motion.gentle) {
                app.isFullscreen = false
                // 창모드로 복귀하면 원래 구조적 사이드바 컬럼을 되돌린다.
                columnVisibility = .all
            }
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
        if s.interfaceTheme == .sonnet {
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
                externalCategory: Binding(
                    get: { app.archiveCategoryRequest },
                    set: { app.archiveCategoryRequest = $0 }
                ),
                requestTrash: { app.requestTrash($0) }
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
    @Binding var columnVisibility: NavigationSplitViewVisibility
    /// 전체화면 전용 플로팅 사이드바의 표시 여부 — 전체화면에서는 구조적 컬럼 대신 이걸 토글한다.
    @Binding var floatingSidebarVisible: Bool
    /// 사이드바가 접혀 신호등이 이 바 위에 겹칠 때의 좌측 여백 (전체화면에서는 불필요)
    var needsTrafficLightInset = false

    @State private var newDocMenuHover = false

    private var isChrome: Bool { app.settings.applied.tabStyleRaw == "chrome" }

    var body: some View {
        let l10n = Localizer.shared
        VStack(spacing: 0) {
            // 메뉴바 자동 숨김이 꺼진 환경에서는 전체화면에서도 메뉴바가 계속 보이는데,
            // 이 여백을 탭바 바깥에 붙이면(.padding) barBackground가 안 덮인 채로 남아
            // 캔버스색 빈 줄이 탭바 위에 별도 박스처럼 떠 보였다 — barBackground가 함께
            // 덮이도록 탭바 내부(같은 배경을 받는 컨테이너 안)에 여백을 넣는다.
            if app.isFullscreen {
                Spacer().frame(height: 20)
            }
            tabBarContent(l10n)
        }
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

    private func tabBarContent(_ l10n: Localizer) -> some View {
        HStack(spacing: isChrome ? 0 : 6) {
            // 브랜드 앵커 — 사이드바가 접혀 신호등과 겹칠 땐 숨겨 공간을 확보
            if !needsTrafficLightInset {
                Image(systemName: "feather")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme == .sonnet ? SonnetPalette.accent : Color.accentColor)
                    .padding(.leading, 12)
                    .padding(.trailing, 2)
            }

            // 사이드바 토글 — 전체화면에서는 플로팅 패널을, 창모드에서는 구조적 컬럼을 토글한다.
            ToolbarIconButton(
                "sidebar.left",
                help: l10n.t(.workspace),
                isActive: app.isFullscreen ? floatingSidebarVisible : columnVisibility != .detailOnly
            ) {
                withAnimation(DesignTokens.Motion.gentle) {
                    if app.isFullscreen {
                        floatingSidebarVisible.toggle()
                    } else {
                        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                    }
                }
            }
            .padding(.leading, needsTrafficLightInset ? 76 : 6)

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
                    .foregroundStyle(newDocMenuHover ? Color.accentColor : .secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                            .fill(newDocMenuHover ? Color.accentColor.opacity(0.1) : .clear)
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
    }

    @ViewBuilder
    private var barBackground: some View {
        if isChrome {
            // 탭바는 콘텐츠보다 가라앉은 톤 — 활성 탭이 캔버스색으로 떠오른다.
            // NavigationSplitView/툴바의 안전영역 이중 예약 버그(rdar://122947424) 때문에
            // ignoresSafeArea만으로는 미세한 틈이 남을 수 있어 위로 살짝 오버스캔한다.
            ZStack {
                (theme == .sonnet ? SonnetPalette.sunken : Color.primary.opacity(0.06))
                if theme == .sonnet {
                    // 앤티크 페이퍼 무드를 강화하는 미세 그레인
                    GrainOverlay(color: SonnetPalette.ink, opacity: 0.045, density: 500)
                }
            }
            .ignoresSafeArea(edges: .top)
            .padding(.top, -24)
        } else {
            Color.clear
        }
    }
}

struct TabChip: View {
    @Environment(AppState.self) private var app
    @Environment(\.renderQuality) private var quality
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
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
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
        .onTapGesture { app.selectedTabID = tab.id }
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
                // "지금 여기" 정체성 — 활성 탭 상단에 적갈 액센트 언더라인
                .overlay(alignment: .top) {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(theme == .sonnet ? SonnetPalette.accent : Color.accentColor)
                            .frame(height: 2)
                            .padding(.horizontal, 8)
                            .transition(.opacity)
                    }
                }
                .opacity(isSelected ? 1 : 0.85)
        } else {
            content
                .glassCapsule(
                    tint: isSelected ? Color.accentColor : nil,
                    interactive: true,
                    quality: quality
                )
                .opacity(isSelected ? 1 : 0.75)
        }
    }

    private var chromeFill: Color {
        // 활성 탭 = 콘텐츠 캔버스색 → 병합되어 보임
        let active = theme == .sonnet ? SonnetPalette.canvas : Color(nsColor: .windowBackgroundColor)
        let hover = theme == .sonnet ? SonnetPalette.surface.opacity(0.5) : Color.primary.opacity(0.05)
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
