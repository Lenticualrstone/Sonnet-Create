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
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 244, max: 320)
                // 사이드바 상단의 시스템 툴바(백색 박스 원인) 제거
                .toolbar(removing: .sidebarToggle)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } detail: {
            ZStack {
                // Sonnet 테마: 본톤 캔버스가 모든 레이어의 바닥
                if app.settings.applied.interfaceTheme == .sonnet {
                    SonnetPalette.canvas.ignoresSafeArea()
                }
                background

                VStack(spacing: 0) {
                    // 탭바가 곧 헤더 — 사이드바 토글·우측 액션까지 모두 이 한 줄에
                    ChromeTabBar(columnVisibility: $columnVisibility)
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
        .navigationTitle("")
        // 크롬(버튼/탭/툴바)의 안내 텍스트가 커서로 선택되는 것을 방지.
        // 본문 텍스트 선택이 필요한 곳(시나리오 블록 등)은 개별적으로 다시 활성화한다.
        .textSelection(.disabled)
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
        case .archive:
            ArchiveView(
                workspace: app.workspace,
                onOpen: { app.openDocument($0) },
                requestUnlock: { reason in
                    await app.privacyGate.unlock(reason: reason)
                },
                openOnSingleClick: app.settings.applied.openOnSingleClick
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

// MARK: - Chrome-tabs 스타일 탭바
// 참고: github.com/adamschwartz/chrome-tabs — 좌측 정렬 유동 폭 탭,
// 활성 탭은 콘텐츠 캔버스와 병합, 비활성 탭 사이 세로 구분선.

struct ChromeTabBar: View {
    @Environment(AppState.self) private var app
    @Environment(\.interfaceTheme) private var theme
    @Binding var columnVisibility: NavigationSplitViewVisibility

    private var isChrome: Bool { app.settings.applied.tabStyleRaw == "chrome" }

    var body: some View {
        let l10n = Localizer.shared
        HStack(spacing: isChrome ? 0 : 6) {
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: isChrome ? 0 : 4) {
                    ForEach(Array(app.tabs.enumerated()), id: \.element.id) { index, tab in
                        TabChip(tab: tab, isFirst: index == 0)
                    }
                }
                .padding(.leading, isChrome ? 6 : 4)
                .padding(.top, isChrome ? 5 : 3)
            }

            ToolbarIconButton("plus", help: l10n.t(.newDocument)) {
                app.selectOrOpenHome()
            }

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
        if isChrome {
            // 탭바는 콘텐츠보다 가라앉은 톤 — 활성 탭이 캔버스색으로 떠오른다
            (theme == .sonnet ? SonnetPalette.sunken : Color.primary.opacity(0.06))
                .ignoresSafeArea(edges: .top)
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
        renaming = true
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
