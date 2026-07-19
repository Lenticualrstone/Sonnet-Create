import AppCore
import AppKit
import DesignSystem
import DocumentKit
import FileManagerKit
import SwiftUI

/// ⌘K 커맨드 팔레트 — 문서 점프(제목+본문 딥서치)와 빠른 명령을 한 입력으로 묶는다.
/// Linear/Notion/Raycast에서 확립된 패턴: 중앙 상단 패널, ↑↓ 이동, ⏎ 실행, ⎋ 닫기.
struct CommandPaletteView: View {
    @Environment(AppState.self) private var app
    @Environment(\.renderQuality) private var quality
    @Environment(\.resolvedAccent) private var accent
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var documentResults: [DocumentListItem] = []
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    /// 실행 가능한 명령 한 줄.
    private struct PaletteAction: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let run: () -> Void
    }

    /// 문서와 명령을 한 리스트로 합친 표시 단위.
    private enum PaletteItem: Identifiable {
        case openTab(OpenTab, index: Int)
        case document(DocumentListItem)
        case action(PaletteAction)

        var id: String {
            switch self {
            case .openTab(let tab, _): "tab-\(tab.id.uuidString)"
            case .document(let item): item.id.uuidString
            case .action(let action): action.id
            }
        }
    }

    var body: some View {
        let l10n = Localizer.shared
        ZStack(alignment: .top) {
            // 배경 — 클릭하면 닫힘
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "command")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField(l10n.t(.quickOpenPlaceholder), text: $query)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($fieldFocused)
                        .onSubmit { runSelected() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                Divider().opacity(0.4)

                if items.isEmpty {
                    Text(l10n.t(.noMatches))
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 28)
                        .frame(maxWidth: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    // 섹션 경계마다 제목 행 — 열린 탭 / 문서 / 명령 (3단계 3)
                                    if index == 0 || sectionKey(items[index - 1]) != sectionKey(item) {
                                        sectionHeader(item, l10n: l10n)
                                    }
                                    row(item, isSelected: index == selection, l10n: l10n)
                                        .id(index)
                                        .onTapGesture {
                                            selection = index
                                            runSelected()
                                        }
                                        .onHover { hovering in
                                            if hovering { selection = index }
                                        }
                                }
                            }
                            .padding(6)
                        }
                        .frame(maxHeight: 340)
                        .onChange(of: selection) { _, index in
                            proxy.scrollTo(index)
                        }
                    }
                }

                Divider().opacity(0.4)

                // 하단 키 도움말 (3단계 3)
                Text(l10n.t(.paletteHints))
                    .font(DSType.mono(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 7)
            }
            .frame(width: 560)
            .glassSurface(cornerRadius: DesignTokens.Radius.large, quality: quality)
            .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
            .padding(.top, 110)
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            // ↑↓ 탐색은 텍스트필드가 포커스를 쥔 채로 동작해야 한다
            .onKeyPress(.upArrow) {
                selection = max(0, selection - 1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                selection = min(max(items.count - 1, 0), selection + 1)
                return .handled
            }
        }
        .onAppear { fieldFocused = true }
        .onExitCommand { close() }
        .onChange(of: query) { selection = 0 }
        .task(id: query) {
            guard !query.isEmpty else {
                documentResults = []
                return
            }
            try? await Task.sleep(for: .milliseconds(120)) // 타이핑 디바운스
            guard !Task.isCancelled else { return }
            documentResults = await app.workspace.deepSearch(query)
        }
    }

    // MARK: 항목 구성

    /// 빈 쿼리: 열린 탭 + 최근 문서 + 전체 명령. 쿼리 있음: 열린 탭(제목 일치) +
    /// 딥서치 결과 + 제목 일치 명령. '열린 탭' 섹션이 최상단 — ⌘1~9 병기 (4b 신규).
    private var items: [PaletteItem] {
        let openTabIDs = Set(app.tabs.compactMap { tab -> UUID? in
            if case .document(let docID) = tab.content { return docID }
            return nil
        })
        let openTabs: [PaletteItem] = app.tabs.enumerated().compactMap { index, tab in
            guard case .document = tab.content else { return nil }
            let title = app.tabTitle(for: tab)
            guard query.isEmpty || title.localizedCaseInsensitiveContains(query) else { return nil }
            return .openTab(tab, index: index)
        }

        let documents: [DocumentListItem]
        if query.isEmpty {
            documents = Array(
                app.workspace.visibleDocuments
                    .filter { !openTabIDs.contains($0.id) }
                    .sorted { $0.envelope.modifiedAt > $1.envelope.modifiedAt }
                    .prefix(6)
            )
        } else {
            documents = Array(documentResults.filter { !openTabIDs.contains($0.id) }.prefix(12))
        }
        let matchingActions = query.isEmpty
            ? actions
            : actions.filter { $0.title.localizedCaseInsensitiveContains(query) }
        return openTabs + documents.map(PaletteItem.document) + matchingActions.map(PaletteItem.action)
    }

    private var actions: [PaletteAction] {
        let l10n = Localizer.shared
        // 새 문서는 헤더 + 메뉴와 같은 컨텍스트 규칙 — 프로젝트 맥락에서는 그 프로젝트 안에.
        let target = app.creationTargetProject
        let suffix = target.map { " → \($0.manifest.name)" } ?? ""
        return [
            PaletteAction(id: "new-scenario", title: l10n.t(.newScenario) + suffix, symbol: "text.bubble") {
                app.createAndOpen(kind: .scenario, in: target)
            },
            PaletteAction(id: "new-mindmap", title: l10n.t(.newMindMap) + suffix, symbol: "point.3.connected.trianglepath.dotted") {
                app.createAndOpen(kind: .mindmap, in: target)
            },
            PaletteAction(id: "new-page", title: l10n.t(.newPage) + suffix, symbol: "doc.richtext") {
                app.createAndOpen(kind: .page, in: target)
            },
            PaletteAction(id: "new-character", title: l10n.t(.newCharacter) + suffix, symbol: "person.crop.circle.badge.plus") {
                app.createAndOpen(kind: .page, pageRole: .character, in: target)
            },
            PaletteAction(id: "new-project", title: l10n.t(.newProject), symbol: "folder.badge.plus") {
                _ = try? app.workspace.createProject(name: l10n.t(.newProject))
            },
            PaletteAction(id: "archive", title: l10n.t(.archive), symbol: "archivebox") {
                app.openArchiveTab()
            },
            PaletteAction(id: "ai-chat", title: l10n.t(.sonnetAI), symbol: "sparkles") {
                app.openAIChatTab()
            },
            PaletteAction(id: "settings", title: l10n.t(.settings), symbol: "gearshape") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            },
        ]
    }

    // MARK: 행 렌더링

    /// 섹션 구분 키 — 같은 값끼리 한 섹션.
    private func sectionKey(_ item: PaletteItem) -> Int {
        switch item {
        case .openTab: 0
        case .document: 1
        case .action: 2
        }
    }

    /// 섹션 제목 행 — 열린 탭 / 문서 / 명령.
    private func sectionHeader(_ item: PaletteItem, l10n: Localizer) -> some View {
        let key: L10nKey = switch item {
        case .openTab: .openTabs
        case .document: .documents
        case .action: .actionsSection
        }
        return Text(l10n.t(key))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private func row(_ item: PaletteItem, isSelected: Bool, l10n: Localizer) -> some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            switch item {
            case .openTab(let tab, let index):
                if let type = app.fileType(for: tab) {
                    FileTypeIcon(type, size: 15)
                        .frame(width: 22)
                } else {
                    Image(systemName: app.tabSymbol(for: tab))
                        .foregroundStyle(accent)
                        .frame(width: 22)
                }
                Text(app.tabTitle(for: tab))
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(DSType.mono(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            case .document(let doc):
                FileTypeIcon(fileType(of: doc), size: 15)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(doc.envelope.title.isEmpty ? l10n.t(.untitled) : doc.envelope.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if let project = doc.projectName {
                        Text(project)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(doc.envelope.modifiedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            case .action(let action):
                Image(systemName: action.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                Text(action.title)
                    .font(.callout)
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .fill(isSelected ? accent.opacity(0.14) : .clear)
        )
        .contentShape(Rectangle())
    }

    /// 문서 유형 → 아이콘 타입.
    private func fileType(of doc: DocumentListItem) -> DSFileType {
        if doc.envelope.isCharacterPage { return .character }
        switch doc.envelope.kind {
        case .scenario: return .scenario
        case .mindmap: return .mindmap
        case .page: return .page
        }
    }

    // MARK: 실행

    private func runSelected() {
        guard items.indices.contains(selection) else { return }
        let item = items[selection]
        close()
        switch item {
        case .openTab(let tab, _):
            app.selectExistingTab(tab)
        case .document(let doc):
            app.openDocument(doc)
        case .action(let action):
            action.run()
        }
    }

    private func close() {
        withAnimation(DesignTokens.Motion.snappy) { isPresented = false }
        query = ""
        selection = 0
    }
}
