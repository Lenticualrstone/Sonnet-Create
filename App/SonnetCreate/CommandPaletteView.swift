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
        case document(DocumentListItem)
        case action(PaletteAction)

        var id: String {
            switch self {
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

    /// 빈 쿼리: 최근 문서 + 전체 명령. 쿼리 있음: 딥서치 결과 + 제목 일치 명령.
    private var items: [PaletteItem] {
        let documents: [DocumentListItem]
        if query.isEmpty {
            documents = Array(
                app.workspace.visibleDocuments
                    .sorted { $0.envelope.modifiedAt > $1.envelope.modifiedAt }
                    .prefix(6)
            )
        } else {
            documents = Array(documentResults.prefix(12))
        }
        let matchingActions = query.isEmpty
            ? actions
            : actions.filter { $0.title.localizedCaseInsensitiveContains(query) }
        return documents.map(PaletteItem.document) + matchingActions.map(PaletteItem.action)
    }

    private var actions: [PaletteAction] {
        let l10n = Localizer.shared
        return [
            PaletteAction(id: "new-scenario", title: l10n.t(.newScenario), symbol: "text.bubble") {
                app.createAndOpen(kind: .scenario)
            },
            PaletteAction(id: "new-mindmap", title: l10n.t(.newMindMap), symbol: "point.3.connected.trianglepath.dotted") {
                app.createAndOpen(kind: .mindmap)
            },
            PaletteAction(id: "new-page", title: l10n.t(.newPage), symbol: "doc.richtext") {
                app.createAndOpen(kind: .page)
            },
            PaletteAction(id: "new-character", title: l10n.t(.newCharacter), symbol: "person.crop.circle.badge.plus") {
                app.createAndOpen(kind: .page, pageRole: .character)
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

    @ViewBuilder
    private func row(_ item: PaletteItem, isSelected: Bool, l10n: Localizer) -> some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            switch item {
            case .document(let doc):
                Image(systemName: doc.envelope.isCharacterPage ? "person.crop.circle" : doc.envelope.kind.symbolName)
                    .foregroundStyle(accent)
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
                Text(l10n.t(.actionsSection))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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

    // MARK: 실행

    private func runSelected() {
        guard items.indices.contains(selection) else { return }
        let item = items[selection]
        close()
        switch item {
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
