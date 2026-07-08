import AppCore
import DesignSystem
import DocumentKit
import FileManagerKit
import SwiftUI

/// 메인 화면 — 중앙 검색 필드로 프로젝트/파일 탐색 + 새 문서 빠른 생성 + 최근 항목.
struct HomeView: View {
    @Environment(AppState.self) private var app
    @Environment(\.renderQuality) private var quality

    @State private var query = ""
    @State private var searchResults: [DocumentListItem] = []
    @FocusState private var searchFocused: Bool

    var body: some View {
        let l10n = Localizer.shared
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.l) {
                Spacer().frame(height: 44)

                // 인사말 위 대형 픽셀 필드 — 크기가 제각각인 픽셀들의 무작위 브리딩
                PixelBreathField(
                    columns: 18, rows: 4,
                    baseSize: 3.5, sizeVariance: 4, spacing: 4,
                    quality: quality
                )

                Text(l10n.t(.greeting))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .textStateSwap()

                searchField(l10n)

                if query.isEmpty {
                    if isWorkspaceEmpty {
                        emptyWorkspaceHero(l10n)
                    }
                    projectActions(l10n)
                    quickCreate(l10n)
                    if !isWorkspaceEmpty {
                        recents(l10n)
                    }
                } else {
                    searchResultList(l10n)
                }

                Spacer()
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DesignTokens.Spacing.xl)
        }
        .task(id: query) {
            // 제목 + 본문 딥서치 (SQLite 색인)
            guard !query.isEmpty else {
                searchResults = []
                return
            }
            try? await Task.sleep(for: .milliseconds(150)) // 타이핑 디바운스
            guard !Task.isCancelled else { return }
            searchResults = await app.workspace.deepSearch(query)
        }
    }

    // MARK: 중앙 검색

    private func searchField(_ l10n: Localizer) -> some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(l10n.t(.searchPlaceholder), text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFocused)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.vertical, 14)
        .glassSurface(cornerRadius: DesignTokens.Radius.large, interactive: true, quality: quality)
        .frame(maxWidth: 560)
    }

    private var isWorkspaceEmpty: Bool {
        app.workspace.projects.isEmpty && app.workspace.visibleDocuments.isEmpty
    }

    // MARK: 첫 실행 히어로

    private func emptyWorkspaceHero(_ l10n: Localizer) -> some View {
        VStack(spacing: DesignTokens.Spacing.m) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 76, height: 76)
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            Text(l10n.t(.emptyWorkspaceTitle))
                .font(.title3.weight(.semibold))
            Text(l10n.t(.emptyWorkspaceBody))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button {
                _ = try? app.workspace.createProject(name: Localizer.shared.t(.newProject))
            } label: {
                Label(l10n.t(.createFirstProject), systemImage: "folder.badge.plus")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(DesignTokens.Spacing.l)
        .frame(maxWidth: 520)
        .glassSurface(cornerRadius: DesignTokens.Radius.large, quality: quality)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    // MARK: 프로젝트 액션 (검색 바로 아래)

    private func projectActions(_ l10n: Localizer) -> some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            Button {
                _ = try? app.workspace.createProject(name: l10n.t(.newProject))
            } label: {
                Label(l10n.t(.newProject), systemImage: "folder.badge.plus")
            }
            Button {
                app.importFromDisk()
            } label: {
                Label(l10n.t(.importAny), systemImage: "square.and.arrow.down")
            }
            Button {
                app.openAIChatTab()
            } label: {
                Label(l10n.t(.aiAgent), systemImage: "sparkles")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    // MARK: 빠른 생성

    private func quickCreate(_ l10n: Localizer) -> some View {
        GlassEffectContainer(spacing: DesignTokens.Spacing.m) {
            HStack(spacing: DesignTokens.Spacing.m) {
                QuickCreateButton(symbol: "text.bubble", title: l10n.t(.newScenario)) {
                    app.createAndOpen(kind: .scenario)
                }
                QuickCreateButton(symbol: "point.3.connected.trianglepath.dotted", title: l10n.t(.newMindMap)) {
                    app.createAndOpen(kind: .mindmap)
                }
                QuickCreateButton(symbol: "doc.richtext", title: l10n.t(.newPage)) {
                    app.createAndOpen(kind: .page)
                }
                QuickCreateButton(symbol: "person.crop.circle.badge.plus", title: l10n.t(.newCharacter)) {
                    app.createAndOpen(kind: .page, pageRole: .character)
                }
            }
        }
    }

    // MARK: 최근 항목

    @ViewBuilder
    private func recents(_ l10n: Localizer) -> some View {
        let items = app.workspace.recentDocuments
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            Text(l10n.t(.recentDocuments))
                .font(.headline)
                .foregroundStyle(.secondary)

            if items.isEmpty {
                Text(l10n.t(.noRecents))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DesignTokens.Spacing.l)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160), spacing: DesignTokens.Spacing.s)],
                    spacing: DesignTokens.Spacing.s
                ) {
                    ForEach(items) { item in
                        RecentCard(item: item) { app.openDocument(item) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 검색 결과

    @ViewBuilder
    private func searchResultList(_ l10n: Localizer) -> some View {
        let results = searchResults
        VStack(alignment: .leading, spacing: 4) {
            ForEach(results) { item in
                Button {
                    app.openDocument(item)
                } label: {
                    HStack(spacing: DesignTokens.Spacing.s) {
                        Image(systemName: item.envelope.isCharacterPage ? "person.crop.circle" : item.envelope.kind.symbolName)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.envelope.title)
                                .font(.callout.weight(.medium))
                            if let project = item.projectName {
                                Text(project)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(item.envelope.modifiedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassSurface(cornerRadius: DesignTokens.Radius.small, quality: quality)
            }
            if results.isEmpty {
                Text(l10n.t(.noRecents))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DesignTokens.Spacing.l)
            }
        }
        .frame(maxWidth: 560)
    }
}

struct QuickCreateButton: View {
    let symbol: String
    let title: String
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.renderQuality) private var quality

    var body: some View {
        Button(action: action) {
            VStack(spacing: DesignTokens.Spacing.s) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .frame(width: 108, height: 76)
            .glassSurface(cornerRadius: DesignTokens.Radius.medium, interactive: true, quality: quality)
            .scaleEffect(hovering ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(DesignTokens.Motion.snappy, value: hovering)
    }
}

struct RecentCard: View {
    let item: DocumentListItem
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.renderQuality) private var quality

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: item.envelope.isCharacterPage ? "person.crop.circle" : item.envelope.kind.symbolName)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                Text(item.envelope.title.isEmpty ? Localizer.shared.t(.untitled) : item.envelope.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Text(item.envelope.modifiedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(DesignTokens.Spacing.s)
            .frame(height: 104, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: DesignTokens.Radius.medium, interactive: true, quality: quality)
            .scaleEffect(hovering ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(DesignTokens.Motion.snappy, value: hovering)
    }
}
