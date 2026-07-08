import AppCore
import DesignSystem
import DocumentKit
import FileManagerKit
import SwiftUI

/// 좌측 사이드바 — 정보(날짜/시간) · 프로젝트 파일 인스펙터 · 작업자 프로필.
struct SidebarView: View {
    @Environment(AppState.self) private var app
    @Environment(\.renderQuality) private var quality

    @State private var showProfilePopover = false

    var body: some View {
        let l10n = Localizer.shared
        VStack(spacing: 0) {
            infoHeader

            List {
                Section(l10n.t(.project)) {
                    ForEach(app.workspace.projects) { project in
                        ProjectTreeRow(project: project)
                    }
                    Button {
                        createProject()
                    } label: {
                        Label(l10n.t(.newProject), systemImage: "plus")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Section(l10n.t(.documents)) {
                    ForEach(standaloneDocuments) { item in
                        SidebarDocumentRow(item: item)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider().opacity(0.4)
            SidebarAIChatSection()
                .padding(.horizontal, DesignTokens.Spacing.m)
                .padding(.vertical, DesignTokens.Spacing.s)
            Divider().opacity(0.4)
            profileFooter(l10n)
        }
        .background(
            // 메인 콘텐츠(canvas)보다 살짝 가라앉은 톤으로 패널을 구분
            app.settings.applied.interfaceTheme == .sonnet
                ? AnyShapeStyle(SonnetPalette.sunken)
                : AnyShapeStyle(.clear)
        )
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
                // 시계 위 픽셀 필드 — 사이드바 폭에 맞춘 소형 (무작위 디밍/브리딩)
                PixelBreathField(columns: 14, rows: 2, baseSize: 3, spacing: 3, quality: quality)
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
            .padding(DesignTokens.Spacing.m)
            .padding(.top, 22) // 신호등(닫기/최소화) 버튼 영역 확보
        }
    }

    // MARK: 작업자 프로필

    private func profileFooter(_ l10n: Localizer) -> some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
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
        .onTapGesture { showProfilePopover = true }
        .popover(isPresented: $showProfilePopover, arrowEdge: .top) {
            ProfilePopoverView()
                .environment(app)
        }
    }
}

/// 프로필 수정 팝오버 — 이름 즉시 저장 + 설정 진입.
struct ProfilePopoverView: View {
    @Environment(AppState.self) private var app
    @State private var nameDraft = ""

    var body: some View {
        let l10n = Localizer.shared
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            HStack(spacing: DesignTokens.Spacing.s) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor)
                TextField(l10n.t(.profile), text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commit)
            }
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.caption2)
                Text(app.workspace.rootURL.path)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.secondary)

            Divider()
            HStack {
                SettingsLink {
                    Label(l10n.t(.settings), systemImage: "gearshape")
                }
                Spacer()
                Button(l10n.t(.save), action: commit)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(nameDraft == app.settings.applied.authorName)
            }
        }
        .padding(DesignTokens.Spacing.m)
        .frame(width: 260)
        .onAppear { nameDraft = app.settings.applied.authorName }
    }

    private func commit() {
        app.settings.draft.authorName = nameDraft
        app.settings.save()
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
                renaming = true
            }
            Button(l10n.t(.exportProject)) { app.exportProject(project) }
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
                renaming = true
            }
            Button(l10n.t(.duplicate)) { _ = app.workspace.duplicateDocument(item) }
            Divider()
            Button(l10n.t(.hide)) { app.workspace.setHidden(item, hidden: true) }
            Button(l10n.t(.moveToTrash), role: .destructive) { app.workspace.moveToTrash(item) }
        }
        .popover(isPresented: $renaming, arrowEdge: .trailing) {
            SidebarRenamePopover(draft: $draftTitle) {
                app.renameDocument(item, to: draftTitle)
                renaming = false
            }
        }
    }
}
