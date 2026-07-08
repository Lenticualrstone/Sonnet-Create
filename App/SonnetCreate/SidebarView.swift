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
        case .agent: .aiAgent
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
        if theme == .sonnet {
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

    @State private var showProfileMenu = false
    @State private var tab: SidebarTab = .home
    @Namespace private var tabHighlight

    var body: some View {
        let l10n = Localizer.shared
        VStack(spacing: 0) {
            // 신호등(닫기/최소화/확대) 영역 — 윈도우 모드에서만 예약, 전체화면에는 없음.
            // 윈도우 모드에서는 이 줄에 픽셀 필드가 함께 들어간다 (전체화면에서는 시계 위로 이동).
            topStrip

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
            app.settings.applied.interfaceTheme == .sonnet
                ? AnyShapeStyle(SonnetPalette.sunken)
                : AnyShapeStyle(.clear)
        )
        .animation(DesignTokens.Motion.gentle, value: app.isFullscreen)
    }

    // MARK: 상단 스트립 (신호등 줄 — 윈도우 모드 전용)

    @ViewBuilder
    private var topStrip: some View {
        if app.isFullscreen {
            Spacer().frame(height: 10)
        } else {
            GeometryReader { geo in
                HStack(spacing: 8) {
                    Spacer().frame(width: 72) // 신호등 예약 폭
                    PixelBreathField(
                        columns: fillingColumns(for: geo.size.width - 72 - 12),
                        rows: 3, baseSize: 3, spacing: 3, quality: quality
                    )
                    Spacer(minLength: 0)
                }
                .padding(.trailing, 12)
            }
            .frame(height: 30)
        }
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
                    }
                    .foregroundStyle(tab == candidate ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background {
                        // 탭 사이를 미끄러지듯 이동하는 하이라이트 (matchedGeometryEffect)
                        if tab == candidate {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
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
                        .foregroundStyle(Color.accentColor)
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

    private func homeTree(_ l10n: Localizer) -> some View {
        VStack(spacing: 0) {
            archiveButton(l10n)

            List {
                Section {
                    ForEach(app.workspace.projects) { project in
                        ProjectTreeRow(project: project)
                    }
                } header: {
                    // 헤더 라인에 새 프로젝트/새 문서 아이콘 (인라인 버튼 대체)
                    HStack(spacing: 10) {
                        Text(l10n.t(.project))
                        Spacer()
                        Menu {
                            Button(l10n.t(.newScenario)) { app.createAndOpen(kind: .scenario) }
                            Button(l10n.t(.newMindMap)) { app.createAndOpen(kind: .mindmap) }
                            Button(l10n.t(.newPage)) { app.createAndOpen(kind: .page) }
                            Button(l10n.t(.newCharacter)) { app.createAndOpen(kind: .page, pageRole: .character) }
                        } label: {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help(l10n.t(.newDocument))

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
                    // 가장자리에 바짝 붙지 않도록 여유 확보
                    .padding(.trailing, 6)
                }

                Section(l10n.t(.documents)) {
                    ForEach(standaloneDocuments) { item in
                        SidebarDocumentRow(item: item)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
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
                // 전체화면에서만: 픽셀 필드가 시계 위로 내려와 사이드바 폭을 가득 채운다.
                if app.isFullscreen {
                    GeometryReader { geo in
                        PixelBreathField(
                            columns: fillingColumns(for: geo.size.width),
                            rows: 3, baseSize: 3, spacing: 3, quality: quality
                        )
                    }
                    .frame(height: 3 * 3 + 2 * 3)
                }
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
            .padding(.top, app.isFullscreen ? DesignTokens.Spacing.s : 0)
            .padding(.bottom, DesignTokens.Spacing.s)
        }
    }

    // MARK: 작업자 프로필

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
        .onTapGesture { showProfileMenu = true }
        .popover(isPresented: $showProfileMenu, arrowEdge: .top) {
            SidebarProfileMenu()
        }
    }

    @ViewBuilder
    private var profileAvatar: some View {
        let path = app.settings.applied.authorPhotoPath
        if !path.isEmpty, let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 28)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
        }
    }
}

/// 프로필 클릭 팝업 — 사진/이름/소개 미리보기 + 프로필 보기·설정·가려진 항목·최근 지워진 항목.
struct SidebarProfileMenu: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let l10n = Localizer.shared
        let s = app.settings.applied
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            HStack(spacing: DesignTokens.Spacing.s) {
                if !s.authorPhotoPath.isEmpty, let image = NSImage(contentsOfFile: s.authorPhotoPath) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else {
                    ZStack {
                        Circle().fill(Color.accentColor.opacity(0.16))
                        Image(systemName: "person.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: 44, height: 44)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.authorName.isEmpty ? l10n.t(.profile) : s.authorName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    if !s.authorBio.isEmpty {
                        Text(s.authorBio)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                menuRow(l10n.t(.viewProfile), symbol: "person.crop.circle") {
                    app.openProfileTab()
                    dismiss()
                }
                menuRow(l10n.t(.settings), symbol: "gearshape") {
                    dismiss()
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                Divider()
                menuRow(l10n.t(.hiddenItems), symbol: "eye.slash") {
                    app.openArchiveTab(category: .hidden)
                    dismiss()
                }
                menuRow(l10n.t(.recentlyDeleted), symbol: "trash") {
                    app.openArchiveTab(category: .trash)
                    dismiss()
                }
            }
        }
        .padding(DesignTokens.Spacing.m)
        .frame(width: 250)
    }

    private func menuRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    var body: some View {
        let l10n = Localizer.shared
        DisclosureGroup(isExpanded: $expanded) {
            let docs = app.workspace.visibleDocuments.filter { $0.envelope.projectID == project.id }
            let characters = docs.filter { $0.envelope.isCharacterPage }
            let others = docs.filter { !$0.envelope.isCharacterPage }

            ForEach(characters) { item in
                SidebarDocumentRow(item: item)
            }
            ForEach(others) { item in
                SidebarDocumentRow(item: item)
            }

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
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(SonnetPalette.inkMuted)
        } label: {
            Label(project.manifest.name, systemImage: "folder.fill")
                .font(.callout.weight(.medium))
        }
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
                    .foregroundStyle(Color.accentColor)
            }
            .font(.callout)
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isActive
                            ? Color.accentColor.opacity(0.18)
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
