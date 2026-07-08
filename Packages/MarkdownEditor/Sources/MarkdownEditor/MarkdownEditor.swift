import AppCore
import AppKit
import DesignSystem
import DocumentKit
import SwiftUI
import UniformTypeIdentifiers

/// 블록형 마크다운 페이지 뷰어/에디터. 캐릭터 페이지는 상단 프로필 헤더가 추가된다.
public struct PageEditorView: View {
    @Bindable var store: PageStore
    @Binding var title: String
    let breadcrumb: [String]
    let saveState: SaveState
    let onManualSave: () -> Void

    @FocusState private var focusedBlockID: UUID?
    @Environment(\.renderQuality) private var quality
    @Environment(\.contentFontFamily) private var fontFamily

    public init(
        store: PageStore,
        title: Binding<String>,
        breadcrumb: [String],
        saveState: SaveState,
        onManualSave: @escaping () -> Void
    ) {
        self.store = store
        self._title = title
        self.breadcrumb = breadcrumb
        self.saveState = saveState
        self.onManualSave = onManualSave
    }

    public var body: some View {
        let l10n = Localizer.shared
        VStack(spacing: 0) {
            toolbar(l10n)
            Divider().opacity(0.4)

            if store.isCharacterPage {
                // 캐릭터 페이지 v2 — 탭 구조 (프로필/노트/관계/갤러리/보이스)
                CharacterPageContainer(store: store, title: $title) {
                    notesBody(l10n)
                }
            } else {
                notesBody(l10n)
            }
        }
        .onChange(of: store.focusRequest) { _, newValue in
            if let newValue {
                focusedBlockID = newValue
                store.focusRequest = nil
            }
        }
    }

    /// 블록 에디터 본문 (+ 슬래시 팔레트).
    private func notesBody(_ l10n: Localizer) -> some View {
        ZStack(alignment: .bottom) {
            pageList(l10n)

            // '/' 커맨드 팔레트 — 하단 도킹 (행 팝오버는 AppKit 크래시 유발)
            if store.slashBlockID != nil {
                SlashCommandMenu(store: store)
                    .frame(width: 260)
                    .glassSurface(cornerRadius: DesignTokens.Radius.medium, quality: quality)
                    .padding(.bottom, DesignTokens.Spacing.m)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(DesignTokens.Motion.snappy, value: store.slashBlockID != nil)
    }

    private func pageList(_ l10n: Localizer) -> some View {
            List {
                // Notion처럼 중앙 정렬된 본문 칼럼 (캐릭터 페이지는 제목을 프로필 탭에서 편집)
                if !store.isCharacterPage {
                    TextField(l10n.t(.untitled), text: $title)
                        .textFieldStyle(.plain)
                        .font(DSFonts.font(size: 30, weight: .bold, family: fontFamily))
                        .padding(.bottom, 6)
                        .padding(.leading, 44) // 블록 거터와 정렬
                        .modifier(CenteredColumn())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 2, trailing: 0))
                }

                ForEach(store.visibleBlocks) { block in
                    PageBlockRow(store: store, block: block, focusedBlockID: $focusedBlockID)
                        .modifier(CenteredColumn())
                        .id(block.id)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                .onMove { store.moveVisibleBlocks(from: $0, to: $1) }

                Color.clear
                    .frame(height: 200)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let last = store.content.blocks.last {
                            if last.text.isEmpty, last.kind == .paragraph {
                                store.focusRequest = last.id
                            } else {
                                store.insertBlock(after: last.id)
                            }
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
    }

    private func toolbar(_ l10n: Localizer) -> some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            BreadcrumbView(breadcrumb)
            Spacer()

            ToolbarIconButton("arrow.uturn.backward", help: l10n.t(.undo)) { store.undo() }
                .disabled(!store.canUndo)
                .opacity(store.canUndo ? 1 : 0.35)
            ToolbarIconButton("arrow.uturn.forward", help: l10n.t(.redo)) { store.redo() }
                .disabled(!store.canRedo)
                .opacity(store.canRedo ? 1 : 0.35)

            SaveStatusBadge(state: saveState, label: l10n.t(saveState.labelKey), action: onManualSave)

            Menu {
                Button(l10n.t(.exportMarkdown)) { exportMarkdown() }
                Button(l10n.t(.exportHTML)) { exportHTML() }
                Button(l10n.t(.exportPDF)) { exportPDF() }
                Divider()
                Button(l10n.t(.importMarkdown)) { importMarkdown() }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(l10n.t(.exportMarkdown))

            Text(l10n.t(.slashHint))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.vertical, DesignTokens.Spacing.s)
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = (title.isEmpty ? "Untitled" : title) + ".md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? store.exportMarkdown().write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportHTML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = (title.isEmpty ? "Untitled" : title) + ".html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let html = PageExport.html(
            title: title,
            blocks: store.content.blocks,
            resolver: store.resourceResolver
        )
        try? html.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (title.isEmpty ? "Untitled" : title) + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let data = PageExport.pdf(
            title: title,
            blocks: store.content.blocks,
            resolver: store.resourceResolver
        ) {
            try? data.write(to: url)
        }
    }

    private func importMarkdown() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        store.importMarkdown(text)
    }
}

/// 본문을 중앙 760pt 칼럼으로 제한 (Notion 레이아웃).
struct CenteredColumn: ViewModifier {
    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: DesignTokens.Spacing.l)
            content
                .frame(maxWidth: 760, alignment: .leading)
            Spacer(minLength: DesignTokens.Spacing.l)
        }
    }
}
