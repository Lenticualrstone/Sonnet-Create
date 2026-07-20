import AppCore
import DesignSystem
import DocumentKit
import FileManagerKit
import SwiftUI

// MARK: - 프로젝트 화면
// 프로젝트를 1급 시민으로 — 카드 그리드로 나열하고, 카드에서 바로 열기·이름 변경·
// 새 문서·삭제까지. 카드 클릭은 아카이브의 해당 프로젝트 필터로 이어진다.

struct ProjectsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.resolvedAccent) private var accent

    var body: some View {
        let l10n = Localizer.shared
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(l10n)
                    .fadeUpOnAppear(once: "projects")

                if app.workspace.projects.isEmpty {
                    emptyState(l10n)
                        .fadeUpOnAppear(delay: 0.045, once: "projects")
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 14)],
                        alignment: .leading,
                        spacing: 14
                    ) {
                        ForEach(app.workspace.projects) { project in
                            ProjectCard(project: project)
                        }
                        newProjectCard(l10n)
                    }
                    .fadeUpOnAppear(delay: 0.045, once: "projects")
                }
            }
            .padding(.top, 48)
            .padding(.horizontal, 56)
            .padding(.bottom, 80)
            .frame(maxWidth: 1180, alignment: .topLeading)
            .frame(maxWidth: .infinity)
        }
    }

    private func header(_ l10n: Localizer) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(l10n.t(.project))
                .font(DSFonts.display(size: 27, weight: .bold))
                .foregroundStyle(SonnetPalette.ink)
            if !app.workspace.projects.isEmpty {
                Text("\(app.workspace.projects.count)")
                    .font(DSType.mono(size: 13, weight: .semibold))
                    .foregroundStyle(SonnetPalette.inkMuted)
            }
            Spacer()
            Button {
                app.promptNewProject()
            } label: {
                Label(l10n.t(.newProject), systemImage: "plus")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(LiftButtonStyle(hoverScale: 1.02, pressScale: 0.97))
        }
    }

    /// 빈 상태 — 프로젝트 개념을 짧게 설명하고 첫 생성으로 잇는다.
    private func emptyState(_ l10n: Localizer) -> some View {
        VStack(spacing: DesignTokens.Spacing.m) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(l10n.t(.projectsEmptyHint))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Button {
                app.promptNewProject()
            } label: {
                Label(l10n.t(.newProject), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }

    /// 그리드 끝의 점선 '+ 새 프로젝트' 카드.
    private func newProjectCard(_ l10n: Localizer) -> some View {
        Button {
            app.promptNewProject()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .medium))
                Text(l10n.t(.newProject))
                    .font(.callout.weight(.medium))
            }
            .foregroundStyle(SonnetPalette.inkMuted)
            .frame(maxWidth: .infinity, minHeight: 130)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
                    .strokeBorder(
                        SonnetPalette.ink.opacity(0.18),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous))
        }
        .buttonStyle(LiftButtonStyle(hoverScale: 1.01, pressScale: 0.99))
    }
}

// MARK: - 새 프로젝트 이름 프롬프트

/// 모든 생성 진입점이 공유하는 이름 입력 시트 — 조용히 "새 프로젝트"로 생기던 흐름 대체.
/// 만들면 아카이브의 해당 프로젝트로 바로 이동한다.
struct NewProjectPrompt: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        let l10n = Localizer.shared
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            Label(l10n.t(.newProject), systemImage: "folder.badge.plus")
                .font(.headline)
            TextField(l10n.t(.newProjectNamePrompt), text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(create)
            Text(l10n.t(.projectsEmptyHint))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(l10n.t(.cancel)) { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button(l10n.t(.createAction), action: create)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignTokens.Spacing.l)
        .frame(width: 340)
        .onAppear { focused = true }
    }

    private func create() {
        guard app.createProjectAndReveal(name: name) != nil else { return }
        dismiss()
    }
}

// MARK: - 프로젝트 카드

private struct ProjectCard: View {
    @Environment(AppState.self) private var app
    @Environment(\.resolvedAccent) private var accent
    let project: ProjectFolder

    @State private var renaming = false
    @State private var draftName = ""

    /// 프로젝트 소속 문서 (보이는 것만).
    private var members: [DocumentListItem] {
        app.workspace.visibleDocuments.filter { $0.envelope.projectID == project.id }
    }

    private var lastModified: Date? {
        members.map(\.envelope.modifiedAt).max()
    }

    var body: some View {
        let l10n = Localizer.shared
        let members = members
        Button {
            app.openArchiveTab(category: .all, project: project.id)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(accent)
                    Text(project.manifest.name)
                        .font(DSFonts.display(size: 16, weight: .semibold))
                        .foregroundStyle(SonnetPalette.ink)
                        .lineLimit(1)
                    Spacer()
                }

                // 유형 구성 — 있는 유형만 아이콘+수로
                HStack(spacing: 10) {
                    kindChip(.scenario, count: count(.scenario, in: members))
                    kindChip(.mindmap, count: count(.mindmap, in: members))
                    kindChip(.page, count: pageCount(in: members))
                    kindChip(.character, count: characterCount(in: members))
                    if members.isEmpty {
                        Text(l10n.t(.emptyCategory))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack {
                    Text(String(format: l10n.t(.projectDocCountFormat), members.count))
                        .font(DSFonts.font(size: 12, family: .pretendard))
                        .foregroundStyle(SonnetPalette.inkMuted)
                    Spacer()
                    if let lastModified {
                        Text(lastModified, style: .relative)
                            .font(DSFonts.font(size: 12, family: .pretendard))
                            .foregroundStyle(SonnetPalette.inkMuted)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
                    .fill(SonnetPalette.surface)
                    .shadow(color: SonnetPalette.ink.opacity(0.07), radius: 5, y: 2)
            )
            // 표지 — 이 프로젝트 문서 제목들로 짠 활자 나선 (아주 옅은 정적 장식)
            .background {
                if members.count >= 3 {
                    SpiralTypeField(
                        words: members.prefix(10).map(\.envelope.title),
                        speed: 0,
                        maxOpacity: 0.14,
                        color: SonnetPalette.ink
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous))
                    .allowsHitTesting(false)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
                    .strokeBorder(SonnetPalette.ink.opacity(0.09), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous))
        }
        .buttonStyle(LiftButtonStyle(hoverScale: 1.015, pressScale: 0.99))
        .contextMenu {
            Button(l10n.t(.rename)) { beginRename() }
            Menu(l10n.t(.newDocument)) {
                Button(l10n.t(.newScenario)) { app.createAndOpen(kind: .scenario, in: project) }
                Button(l10n.t(.newMindMap)) { app.createAndOpen(kind: .mindmap, in: project) }
                Button(l10n.t(.newPage)) { app.createAndOpen(kind: .page, in: project) }
                Button(l10n.t(.newCharacter)) { app.createAndOpen(kind: .page, pageRole: .character, in: project) }
            }
            Divider()
            Button(l10n.t(.delete), role: .destructive) { app.requestDeleteProject(project) }
        }
        .popover(isPresented: $renaming, arrowEdge: .bottom) {
            HStack(spacing: 6) {
                TextField(l10n.t(.newProjectNamePrompt), text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit(commitRename)
                Button(l10n.t(.done), action: commitRename)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(10)
        }
    }

    private func beginRename() {
        draftName = project.manifest.name
        DispatchQueue.main.async { renaming = true }
    }

    private func commitRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            app.workspace.renameProject(project, to: trimmed)
        }
        renaming = false
    }

    @ViewBuilder
    private func kindChip(_ type: DSFileType, count: Int) -> some View {
        if count > 0 {
            HStack(spacing: 3) {
                FileTypeIcon(type, size: 12)
                Text("\(count)")
                    .font(DSType.mono(size: 11))
                    .foregroundStyle(SonnetPalette.inkMuted)
            }
        }
    }

    private func count(_ kind: DocumentKind, in members: [DocumentListItem]) -> Int {
        // 페이지는 캐릭터와 분리 집계하므로 여기서는 시나리오/마인드맵만
        members.filter { $0.envelope.kind == kind && !$0.envelope.isCharacterPage }.count
    }

    private func pageCount(in members: [DocumentListItem]) -> Int {
        members.filter { $0.envelope.kind == .page && !$0.envelope.isCharacterPage }.count
    }

    private func characterCount(in members: [DocumentListItem]) -> Int {
        members.filter(\.envelope.isCharacterPage).count
    }
}
