import AppCore
import AppKit
import DesignSystem
import DocumentKit
import FileManagerKit
import SwiftUI

/// 편집기 우측의 프로젝트 파일 인스펙터 — 현재 문서가 속한 프로젝트의 파일들을
/// 종류별로 묶어 보여주는 간이 Finder. 사이드바가 프로젝트 내부를 펼치지 않는 대신
/// (대규모 프로젝트에서 목록이 한없이 길어지는 문제 방지), 문서 작업 중 이웃 파일의
/// 탐색·생성은 여기서 한다.
struct ProjectNavigatorView: View {
    @Environment(AppState.self) private var app
    @Environment(\.resolvedAccent) private var accent
    let session: DocumentSession
    let project: ProjectFolder

    private var memberDocs: [DocumentListItem] {
        app.workspace.visibleDocuments.filter { $0.envelope.projectID == project.id }
    }

    var body: some View {
        let l10n = Localizer.shared
        let docs = memberDocs
        let scenarios = docs.filter { $0.envelope.kind == .scenario }
        let mindmaps = docs.filter { $0.envelope.kind == .mindmap }
        let pages = docs.filter { $0.envelope.kind == .page && !$0.envelope.isCharacterPage }
        let characters = docs.filter { $0.envelope.isCharacterPage }
        let others = app.workspace.otherFiles.filter { $0.projectID == project.id }

        VStack(alignment: .leading, spacing: 0) {
            header(l10n)
            Divider().opacity(0.4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    kindSection(l10n.t(.scenario), symbol: DocumentKind.scenario.symbolName, items: scenarios)
                    kindSection(l10n.t(.mindmap), symbol: DocumentKind.mindmap.symbolName, items: mindmaps)
                    kindSection(l10n.t(.page), symbol: DocumentKind.page.symbolName, items: pages)
                    kindSection(l10n.t(.characterPage), symbol: "person.crop.circle", items: characters)
                    otherFileSection(l10n, files: others)
                }
                .padding(DesignTokens.Spacing.s)
            }

            Divider().opacity(0.4)
            archiveFooter(l10n)
        }
    }

    // MARK: 헤더 — 프로젝트 이름 + 새 문서

    private func header(_ l10n: Localizer) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.caption)
                .foregroundStyle(accent)
            Text(project.manifest.name)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Menu {
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
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(l10n.t(.newDocument))
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.vertical, 10)
    }

    // MARK: 종류별 섹션

    @ViewBuilder
    private func kindSection(_ title: String, symbol: String, items: [DocumentListItem]) -> some View {
        if !items.isEmpty {
            sectionHeader(title, count: items.count)
            ForEach(items) { item in
                SidebarDocumentRow(item: item)
            }
        }
    }

    @ViewBuilder
    private func otherFileSection(_ l10n: Localizer, files: [OtherFileItem]) -> some View {
        if !files.isEmpty {
            sectionHeader(l10n.t(.otherFiles), count: files.count)
            ForEach(files) { file in
                OtherFileRow(file: file)
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    // MARK: 푸터 — 프로젝트 아카이브

    private func archiveFooter(_ l10n: Localizer) -> some View {
        Button {
            app.openArchiveTab(category: .all, project: project.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "archivebox")
                    .font(.caption)
                Text(l10n.t(.openProjectArchive))
                    .font(.caption)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, DesignTokens.Spacing.m)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarLongButtonStyle())
    }
}

/// 문서로 인식되지 않는 첨부 파일 행 — 클릭하면 기본 앱으로 연다 (보기 전용).
private struct OtherFileRow: View {
    @Environment(\.resolvedAccent) private var accent
    let file: OtherFileItem

    @State private var hovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(file.url)
        } label: {
            Label {
                Text(file.filename)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "paperclip")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.06) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(DesignTokens.Motion.snappy, value: hovering)
        .help(Localizer.shared.t(.viewOnlyHint))
        .contextMenu {
            Button(Localizer.shared.t(.revealInFinder)) {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            }
        }
    }
}
