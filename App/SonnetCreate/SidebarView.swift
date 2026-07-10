import AppCore
import AppKit
import DesignSystem
import DocumentKit
import FileManagerKit
import SwiftUI

/// 사이드바 내부 탭.
enum SidebarTab: String, CaseIterable, Identifiable {
    case home, agent, inbox

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house"
        case .agent: "sparkles"
        case .inbox: "tray"
        }
    }

    var labelKey: L10nKey {
        switch self {
        case .home: .home
        case .agent: .sonnetAI
        case .inbox: .inbox
        }
    }
}

/// 사이드바 풀폭 버튼(파일 아카이브 등) — 호버 하이라이트 + 눌림 스케일.
struct SidebarLongButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.interfaceTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .fill(fill(pressed: configuration.isPressed))
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .onHover { hovering = $0 }
            .animation(DesignTokens.Motion.snappy, value: hovering)
            .animation(DesignTokens.Motion.snappy, value: configuration.isPressed)
    }

    private func fill(pressed: Bool) -> Color {
        if theme.isBranded {
            if pressed { return SonnetPalette.sunken }
            if hovering { return SonnetPalette.surface }
            return .clear
        }
        if pressed { return Color.primary.opacity(0.10) }
        if hovering { return Color.primary.opacity(0.06) }
        return .clear
    }
}

/// 좌측 사이드바 — 정보(날짜/시간) · 탭(홈/에이전트/수신함) · 작업자 프로필.
struct SidebarView: View {
    @Environment(AppState.self) private var app
    @Environment(\.renderQuality) private var quality
    @Environment(\.resolvedAccent) private var accent

    @State private var showProfileMenu = false
    @State private var tab: SidebarTab = .home
    @Namespace private var tabHighlight
    /// profileFooter의 실측 높이 — 오버레이 패널을 그 바로 위에 정확히 앉히는 데 쓴다.
    @State private var footerHeight: CGFloat = 64

    var body: some View {
        let l10n = Localizer.shared
        VStack(spacing: 0) {
            // 신호등 예약은 이제 프로그램 공통 헤더(ChromeTabBar)가 전담한다 — 사이드바는
            // 그 헤더 바로 아래에서 시작하므로 별도의 상단 여백 줄이 필요 없다.
            infoHeader

            sidebarTabPicker(l10n)
            Divider().opacity(0.35)

            switch tab {
            case .home:
                homeTree(l10n)
            case .agent:
                SidebarAIChatSection(maxMessages: 10)
                    .padding(DesignTokens.Spacing.m)
                Spacer(minLength: 0)
            case .inbox:
                inboxList(l10n)
            }

            Divider().opacity(0.4)
            profileFooter(l10n)
        }
        .background(
            // 메인 콘텐츠(canvas)보다 살짝 가라앉은 톤으로 패널을 구분
            app.settings.applied.interfaceTheme.isBranded
                ? AnyShapeStyle(SonnetPalette.sunken)
                : AnyShapeStyle(.clear)
        )
        .overlay(alignment: .bottom) { profileMenuOverlay }
        .animation(DesignTokens.Motion.gentle, value: showProfileMenu)
    }

    /// 주어진 폭을 채우는 데 필요한 픽셀 열 개수 (셀+간격 기준).
    private func fillingColumns(for width: CGFloat, cell: CGFloat = 3, spacing: CGFloat = 3) -> Int {
        guard width > 0 else { return 10 }
        return max(4, Int((width + spacing) / (cell + spacing)))
    }

    // MARK: 사이드바 탭

    private func sidebarTabPicker(_ l10n: Localizer) -> some View {
        HStack(spacing: 2) {
            ForEach(SidebarTab.allCases) { candidate in
                Button {
                    withAnimation(DesignTokens.Motion.snappy) { tab = candidate }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: candidate.symbol)
                            .font(.caption)
                        Text(l10n.t(candidate.labelKey))
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .foregroundStyle(tab == candidate ? accent : Color.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background {
                        // 탭 사이를 미끄러지듯 이동하는 하이라이트 (matchedGeometryEffect)
                        if tab == candidate {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(accent.opacity(0.12))
                                .matchedGeometryEffect(id: "sidebarTabHighlight", in: tabHighlight)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s)
        .padding(.vertical, 5)
    }

    // MARK: 수신함

    @ViewBuilder
    private func inboxList(_ l10n: Localizer) -> some View {
        if app.inbox.isEmpty {
            VStack(spacing: DesignTokens.Spacing.s) {
                Image(systemName: "tray")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text(l10n.t(.noRecents))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(app.inbox) { event in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: event.symbol)
                        .font(.caption)
                        .foregroundStyle(accent)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.message)
                            .font(.caption)
                            .lineLimit(2)
                        Text(event.date, format: .dateTime.month().day().hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: 홈 트리 (프로젝트/문서)

    /// List/Section/DisclosureGroup 대신 순수 VStack으로 직접 그린다.
    /// macOS의 `.listStyle(.sidebar)`는 하위(DisclosureGroup 내부) 행에
    /// listRowInsets/defaultMinListRowHeight를 거의 무시하고 자체 여백을 강제해서
    /// 항목 사이 간격이 눈에 띄게 넓어지는 문제가 있었다 — 리스트를 걷어내는 게 근본 해결책.
    private func homeTree(_ l10n: Localizer) -> some View {
        VStack(spacing: 0) {
            archiveButton(l10n)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    projectSectionHeader(l10n)

                    ForEach(app.workspace.projects) { project in
                        ProjectTreeRow(project: project)
                    }

                    if !standaloneDocuments.isEmpty {
                        documentsSectionHeader(l10n)

                        ForEach(standaloneDocuments) { item in
                            SidebarDocumentRow(item: item)
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.s)
                .padding(.bottom, DesignTokens.Spacing.s)
            }
        }
    }

    private func projectSectionHeader(_ l10n: Localizer) -> some View {
        // '새 문서' 생성은 탭바/도구막대에도 이미 있어 헤더에서는 중복 제거 — 새 프로젝트만 남긴다.
        HStack(spacing: 10) {
            Text(l10n.t(.project))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                createProject()
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(l10n.t(.newProject))
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 3)
    }

    private func documentsSectionHeader(_ l10n: Localizer) -> some View {
        Text(l10n.t(.documents))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.top, 10)
            .padding(.bottom, 3)
    }

    /// 파일 아카이브 — 프로젝트 목록 위 풀폭 버튼.
    private func archiveButton(_ l10n: Localizer) -> some View {
        Button {
            app.openArchiveTab()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "archivebox")
                    .font(.callout)
                Text(l10n.t(.archive))
                    .font(.callout.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(SonnetPalette.ink)
            .padding(.horizontal, DesignTokens.Spacing.m)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarLongButtonStyle())
        .padding(.horizontal, DesignTokens.Spacing.s)
        .padding(.top, DesignTokens.Spacing.s)
        .padding(.bottom, 4)
    }

    private var standaloneDocuments: [DocumentListItem] {
        app.workspace.visibleDocuments.filter { $0.projectName == nil }
    }

    private func createProject() {
        _ = try? app.workspace.createProject(name: Localizer.shared.t(.newProject))
    }

    // MARK: 정보 헤더 (날짜/시간)

    private var infoHeader: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 8) {
                // 픽셀 필드가 시계 위에서 사이드바 폭을 가득 채운다 — 예전엔 전체화면 전용,
                // 윈도우 모드는 신호등 옆 별도 줄(topStrip)에 있었지만 그 줄이 사라지며
                // 창모드/전체화면 공통으로 통합됐다.
                GeometryReader { geo in
                    PixelBreathField(
                        columns: fillingColumns(for: geo.size.width),
                        rows: 3, baseSize: 3, spacing: 3, color: accent, quality: quality
                    )
                }
                .frame(height: 3 * 3 + 2 * 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.date, format: .dateTime.weekday(.wide).month().day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55) // 좁은 폭에서도 오전/오후가 잘리지 않게
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Spacing.m)
            .padding(.top, DesignTokens.Spacing.s)
            .padding(.bottom, DesignTokens.Spacing.s)
        }
    }

    // MARK: 작업자 프로필

    /// 진짜 오버레이로 띄운다 — 이전엔 이 패널이 사이드바의 일반 VStack 레이아웃 안에
    /// 끼워 넣어져서, 나타날 때 위쪽 프로젝트 목록이 동시에 눌리며 리레이아웃되는 타이밍과
    /// 슬라이드 애니메이션이 어긋나 순간적으로 글자가 비쳐 보였다. `.overlay`로 완전히
    /// 분리하면 아래 레이아웃은 전혀 건드리지 않고 이 패널만 독립된 z-레이어로 뜬다.
    @ViewBuilder
    private var profileMenuOverlay: some View {
        if showProfileMenu {
            SidebarProfileMenu(dismiss: { showProfileMenu = false })
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
                        .fill(
                            app.settings.applied.interfaceTheme.isBranded
                                ? AnyShapeStyle(SonnetPalette.surface)
                                : AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                        )
                        // 강조색과 이어지도록 얇은 테두리 — 흰 카드가 붕 떠 보이는 느낌 완화
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
                                .strokeBorder(accent.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
                )
                .padding(.horizontal, DesignTokens.Spacing.s)
                .padding(.bottom, footerHeight + 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
        }
    }

    private func profileFooter(_ l10n: Localizer) -> some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            profileAvatar
            VStack(alignment: .leading, spacing: 0) {
                Text(app.settings.applied.authorName.isEmpty ? l10n.t(.profile) : app.settings.applied.authorName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(app.workspace.rootURL.lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(l10n.t(.settings))
        }
        .padding(DesignTokens.Spacing.m)
        .contentShape(Rectangle())
        .onTapGesture { showProfileMenu.toggle() }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { footerHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, newValue in footerHeight = newValue }
            }
        )
    }

    @ViewBuilder
    private var profileAvatar: some View {
        let path = app.settings.applied.authorPhotoPath
        if !path.isEmpty, let image = ImageThumbnailCache.thumbnail(for: URL(fileURLWithPath: path), maxPointSize: 28) {
            CroppedCircleImage(
                image: image,
                zoom: app.settings.applied.authorCropZoom,
                offsetX: app.settings.applied.authorCropOffsetX,
                offsetY: app.settings.applied.authorCropOffsetY,
                size: 28
            )
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(accent)
        }
    }
}

/// 프로필 행 인라인 패널 — 사진/이름/소개 미리보기 + 프로필 보기·설정·가려진 항목·최근 지워진 항목.
/// 별도 플로팅 popover가 아니라 사이드바 레이아웃 안에서 위로 솟구치듯 펼쳐진다(profileFooter 바로 위 삽입).
struct SidebarProfileMenu: View {
    @Environment(AppState.self) private var app
    @Environment(\.resolvedAccent) private var accent
    let dismiss: () -> Void

    var body: some View {
        let l10n = Localizer.shared
        let s = app.settings.applied
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: DesignTokens.Spacing.s) {
                if !s.authorPhotoPath.isEmpty, let image = ImageThumbnailCache.thumbnail(for: URL(fileURLWithPath: s.authorPhotoPath), maxPointSize: 36) {
                    CroppedCircleImage(
                        image: image,
                        zoom: s.authorCropZoom,
                        offsetX: s.authorCropOffsetX,
                        offsetY: s.authorCropOffsetY,
                        size: 36
                    )
                } else {
                    ZStack {
                        Circle().fill(accent.opacity(0.16))
                        Image(systemName: "person.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    .frame(width: 36, height: 36)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.authorName.isEmpty ? l10n.t(.profile) : s.authorName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    if !s.authorBio.isEmpty {
                        Text(s.authorBio)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignTokens.Spacing.m)
            .padding(.top, DesignTokens.Spacing.s)

            VStack(alignment: .leading, spacing: 3) {
                menuRow(l10n.t(.viewProfile), symbol: "person.crop.circle") {
                    app.openProfileTab()
                    dismiss()
                }
                menuRow(l10n.t(.settings), symbol: "gearshape") {
                    dismiss()
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                menuRow(l10n.t(.hiddenItems), symbol: "eye.slash", count: app.workspace.hiddenDocuments.count) {
                    app.openArchiveTab(category: .hidden)
                    dismiss()
                }
                menuRow(l10n.t(.recentlyDeleted), symbol: "trash", count: app.workspace.trashedDocuments.count) {
                    app.openArchiveTab(category: .trash)
                    dismiss()
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.s)
            .padding(.bottom, 4)
        }
    }

    private func menuRow(_ title: String, symbol: String, count: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Label(title, systemImage: symbol)
                    .font(.callout)
                Spacer(minLength: 4)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarLongButtonStyle())
        .padding(.vertical, 3)
    }
}

// MARK: - 프로젝트 트리

struct ProjectTreeRow: View {
    @Environment(AppState.self) private var app
    let project: ProjectFolder

    @State private var expanded = true
    @State private var renaming = false
    @State private var draftName = ""
    @State private var hovering = false

    private var docs: [DocumentListItem] {
        app.workspace.visibleDocuments.filter { $0.envelope.projectID == project.id }
    }

    var body: some View {
        let l10n = Localizer.shared
        let characters = docs.filter { $0.envelope.isCharacterPage }
        let others = docs.filter { !$0.envelope.isCharacterPage }

        VStack(alignment: .leading, spacing: 3) {
            // 폴더 행 — DisclosureGroup 대신 직접 그린 토글. 시스템 DisclosureGroup은
            // contextMenu/popover의 앵커가 펼쳐진 하위 콘텐츠까지 포함돼 이름 변경 팝오버가
            // 엉뚱한 위치에 뜨는 문제가 있었고, 이 행 하나에만 정확히 스코프하기 위함.
            Button {
                withAnimation(DesignTokens.Motion.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 10)
                    Label(project.manifest.name, systemImage: "folder.fill")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(0.06) : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .contextMenu {
                Button(l10n.t(.rename)) {
                    draftName = project.manifest.name
                    // contextMenu가 닫히는 애니메이션 도중 popover를 열면 앵커 뷰가
                    // 아직 윈도우 계층에서 확정되지 않아 NSPopover가 크래시한다 (macOS 26).
                    DispatchQueue.main.async { renaming = true }
                }
                Button(l10n.t(.exportProject)) { app.exportProject(project) }
                Button(l10n.t(.deleteProject), role: .destructive) { app.requestDeleteProject(project) }
                Divider()
                Button(l10n.t(.openProjectArchive)) { app.openArchiveTab(category: .all, project: project.id) }
                Divider()
                Menu(l10n.t(.newDocument)) {
                    Button(l10n.t(.newScenario)) { app.createAndOpen(kind: .scenario, in: project) }
                    Button(l10n.t(.newMindMap)) { app.createAndOpen(kind: .mindmap, in: project) }
                    Button(l10n.t(.newPage)) { app.createAndOpen(kind: .page, in: project) }
                    Button(l10n.t(.newCharacter)) { app.createAndOpen(kind: .page, pageRole: .character, in: project) }
                }
            }
            .popover(isPresented: $renaming, arrowEdge: .trailing) {
                SidebarRenamePopover(draft: $draftName) {
                    app.workspace.renameProject(project, to: draftName)
                    renaming = false
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(characters) { item in
                        SidebarDocumentRow(item: item)
                    }
                    ForEach(others) { item in
                        SidebarDocumentRow(item: item)
                    }

                    // 시스템 Menu 컨트롤은 자체 청 마진이 있어 위 VStack의 spacing이
                    // 온전히 반영되지 않는다 — 상단 여백을 명시적으로 줘 다른 행과 간격을 맞춘다.
                    Menu {
                        Button(l10n.t(.newScenario)) { app.createAndOpen(kind: .scenario, in: project) }
                        Button(l10n.t(.newMindMap)) { app.createAndOpen(kind: .mindmap, in: project) }
                        Button(l10n.t(.newPage)) { app.createAndOpen(kind: .page, in: project) }
                        Button(l10n.t(.newCharacter)) { app.createAndOpen(kind: .page, pageRole: .character, in: project) }
                    } label: {
                        // 흰 글씨 문제: 시스템 accent 대비색이 적용되지 않도록 잉크색을 명시
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.caption2)
                            Text(l10n.t(.newDocument))
                                .font(.caption)
                        }
                        .foregroundStyle(SonnetPalette.inkMuted)
                        .padding(.vertical, 3)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .tint(SonnetPalette.inkMuted)
                    .fixedSize()
                    .padding(.top, 3)
                }
                .padding(.leading, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // 프로젝트 간 간격을 다른 항목(3pt)보다 넓게 — 바깥 LazyVStack의 3pt spacing에
        // 이 여백이 더해져 프로젝트-프로젝트 사이는 총 6~7pt가 된다.
        .padding(.bottom, 4)
    }
}

/// 사이드바 공용 이름 변경 팝오버.
struct SidebarRenamePopover: View {
    @Binding var draft: String
    let onCommit: () -> Void

    var body: some View {
        let l10n = Localizer.shared
        HStack(spacing: 6) {
            TextField(l10n.t(.rename), text: $draft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 190)
                .onSubmit(onCommit)
            Button(l10n.t(.done), action: onCommit)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(10)
    }
}

struct SidebarDocumentRow: View {
    @Environment(AppState.self) private var app
    @Environment(\.resolvedAccent) private var accent
    let item: DocumentListItem

    @State private var hovering = false
    @State private var renaming = false
    @State private var draftTitle = ""

    /// 현재 선택된 탭이 이 문서인지 (열려 있음 강조)
    private var isActive: Bool {
        if case .document(let docID) = app.selectedTab?.content {
            return docID == item.id
        }
        return false
    }

    var body: some View {
        Button {
            app.openDocument(item)
        } label: {
            Label {
                Text(item.envelope.title.isEmpty ? Localizer.shared.t(.untitled) : item.envelope.title)
                    .lineLimit(1)
                    .fontWeight(isActive ? .semibold : .regular)
            } icon: {
                Image(systemName: item.envelope.isCharacterPage ? "person.crop.circle" : item.envelope.kind.symbolName)
                    .foregroundStyle(accent)
            }
            .font(.callout)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isActive
                            ? accent.opacity(0.18)
                            : (hovering ? Color.primary.opacity(0.06) : .clear)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(DesignTokens.Motion.snappy, value: hovering)
        .contextMenu {
            let l10n = Localizer.shared
            Button(l10n.t(.open)) { app.openDocument(item) }
            Button(l10n.t(.rename)) {
                draftTitle = item.envelope.title
                DispatchQueue.main.async { renaming = true }
            }
            Button(l10n.t(.duplicate)) { _ = app.workspace.duplicateDocument(item) }
            Divider()
            Button(l10n.t(.hide)) { app.workspace.setHidden(item, hidden: true) }
            Button(l10n.t(.moveToTrash), role: .destructive) { app.requestTrash(item) }
        }
        .popover(isPresented: $renaming, arrowEdge: .trailing) {
            SidebarRenamePopover(draft: $draftTitle) {
                app.renameDocument(item, to: draftTitle)
                renaming = false
            }
        }
    }
}
