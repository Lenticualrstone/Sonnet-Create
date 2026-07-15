import AppCore
import AppKit
import DesignSystem
import DocumentKit
import FileManagerKit
import SwiftUI

/// 메인 화면 — 중앙 검색 필드로 프로젝트/파일 탐색 + 새 문서 빠른 생성 + 최근 항목.
struct HomeView: View {
    @Environment(AppState.self) private var app
    @Environment(\.renderQuality) private var quality
    @Environment(\.resolvedAccent) private var accent

    @State private var query = ""
    @State private var searchResults: [DocumentListItem] = []
    @FocusState private var searchFocused: Bool

    var body: some View {
        let l10n = Localizer.shared
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.l) {
                Spacer().frame(height: 44)

                // 인사말 위 ASCII 웨이브 — 터미널 감성의 문자 물결 (픽셀 디밍 필드 대체).
                // 밤에는 느리고 잔잔하게, 아침엔 또렷하게 흐른다 (시간대 반응).
                // 히어로 전체가 Sonnet AI 진입점 — 클릭하면 AI 채팅 탭이 열린다.
                VStack(spacing: DesignTokens.Spacing.l) {
                    ASCIIWaveField(
                        columns: 48, rows: 6,
                        fontSize: 11,
                        color: accent,
                        quality: quality,
                        speed: timeOfDay.waveSpeed
                    )
                    .frame(maxWidth: 560)

                    Text(greetingText)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .textStateSwap()
                }
                .contentShape(Rectangle())
                .onTapGesture { app.openAIChatTab() }
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .help(l10n.t(.askAnything))
                .fadeUpOnAppear()

                searchField(l10n)
                    .fadeUpOnAppear(delay: 0.06)

                if query.isEmpty {
                    if isWorkspaceEmpty {
                        emptyWorkspaceHero(l10n)
                            .fadeUpOnAppear(delay: 0.12)
                    }
                    projectActions(l10n)
                        .fadeUpOnAppear(delay: 0.12)
                    quickCreate(l10n)
                        .fadeUpOnAppear(delay: 0.18)
                    if !isWorkspaceEmpty {
                        recents(l10n)
                            .fadeUpOnAppear(delay: 0.24)
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

    // MARK: 시간대 반응 인사말

    /// 하루의 네 구간 — 인사말 문구와 웨이브 속도가 여기에 따라 갈린다.
    private enum TimeOfDay {
        case morning, afternoon, evening, night

        var waveSpeed: Double {
            switch self {
            case .morning: 1.15 // 또렷하게
            case .afternoon: 1.0
            case .evening: 0.8
            case .night: 0.6 // 잔잔하게
            }
        }

        var plainKey: L10nKey {
            switch self {
            case .morning: .greetingMorning
            case .afternoon: .greetingAfternoon
            case .evening: .greetingEvening
            case .night: .greetingNight
            }
        }

        var namedKey: L10nKey {
            switch self {
            case .morning: .greetingMorningNamed
            case .afternoon: .greetingAfternoonNamed
            case .evening: .greetingEveningNamed
            case .night: .greetingNightNamed
            }
        }
    }

    private var timeOfDay: TimeOfDay {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: .morning
        case 12..<18: .afternoon
        case 18..<23: .evening
        default: .night
        }
    }

    /// 작가 이름이 설정돼 있으면 이름을 넣은 인사말, 아니면 일반 문구.
    private var greetingText: String {
        let l10n = Localizer.shared
        let name = app.settings.applied.authorName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return l10n.t(timeOfDay.plainKey) }
        return String(format: l10n.t(timeOfDay.namedKey), name)
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
                    .fill(accent.opacity(0.14))
                    .frame(width: 76, height: 76)
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(accent)
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
                            .foregroundStyle(accent)
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
                    .glassSurface(cornerRadius: DesignTokens.Radius.small, quality: quality)
                }
                .buttonStyle(LiftButtonStyle(hoverScale: 1.015, pressScale: 0.99))
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

    @Environment(\.renderQuality) private var quality
    @Environment(\.resolvedAccent) private var accent

    var body: some View {
        Button(action: action) {
            VStack(spacing: DesignTokens.Spacing.s) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .frame(width: 108, height: 76)
            .glassSurface(cornerRadius: DesignTokens.Radius.medium, interactive: true, quality: quality)
        }
        .buttonStyle(LiftButtonStyle())
    }
}

struct RecentCard: View {
    let item: DocumentListItem
    let action: () -> Void

    @Environment(\.renderQuality) private var quality
    @Environment(\.resolvedAccent) private var accent

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: item.envelope.isCharacterPage ? "person.crop.circle" : item.envelope.kind.symbolName)
                    .font(.title3)
                    .foregroundStyle(accent)
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
        }
        .buttonStyle(LiftButtonStyle())
    }
}
