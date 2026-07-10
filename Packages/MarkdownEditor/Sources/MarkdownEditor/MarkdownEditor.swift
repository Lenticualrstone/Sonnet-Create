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
    @Environment(\.readOnlyMode) private var readOnlyMode

    private var isReadOnly: Bool { readOnlyMode?.wrappedValue == true }

    /// 빈 블록 위에서 백스페이스 — SwiftUI의 `.onKeyPress`가 SwiftUI 레이어 문제.
    /// 필드가 완전히 비어있으면 AppKit이 "지울 게 없다"며 이벤트를 자체적으로 삼켜
    /// SwiftUI KeyPress 시스템까지 아예 전달되지 않는다 (raw keyDown을 직접 가로채야 확실히 잡힌다).
    @State private var backspaceMonitor: Any?

    public init(
        store: PageStore,
        title: Binding<String>,
        breadcrumb: [String],
        saveState: SaveState,
        onManualSave: @escaping () -> Void
    ) {
        self.store = store
        _title = title
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
                // 포커스가 프로그래밍적으로 이동하면 AppKit이 기본으로 전체 텍스트를
                // 선택해버린다 (빈 블록 백스페이스 병합 시 이전 블록 전체가 선택된 채로
                // 포커스를 받아, 이어서 타이핑하면 기존 내용이 통째로 지워지는 문제였다).
                // 포커스 반영 다음 런루프에서 커서를 텍스트 끝으로 되돌린다.
                DispatchQueue.main.async {
                    if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                        editor.selectedRange = NSRange(location: editor.string.count, length: 0)
                    }
                }
            }
        }
        .onAppear { installBackspaceMonitor() }
        .onDisappear { removeBackspaceMonitor() }
    }

    /// keyCode 51 = 백스페이스(Delete 키). 포커스된 블록이 완전히 비어있을 때만 개입하고,
    /// 그 외(제목 필드 등 다른 텍스트 입력 중, 또는 내용이 있는 블록)는 이벤트를 그대로 흘려보낸다.
    private func installBackspaceMonitor() {
        guard backspaceMonitor == nil else { return }
        backspaceMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 51,
                  !isReadOnly,
                  let focusedID = focusedBlockID,
                  let block = store.block(id: focusedID),
                  block.text.isEmpty
            else { return event }
            store.removeBlockFocusPrevious(focusedID)
            return nil
        }
    }

    private func removeBackspaceMonitor() {
        if let backspaceMonitor {
            NSEvent.removeMonitor(backspaceMonitor)
        }
        backspaceMonitor = nil
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

    /// 표시 단위 — 단일 블록 또는 나란히 페어.
    private enum DisplayItem: Identifiable {
        case single(PageBlock)
        case pair(PageBlock, PageBlock)

        var id: UUID {
            switch self {
            case .single(let block): block.id
            case .pair(let left, _): left.id
            }
        }
    }

    private var displayItems: [DisplayItem] {
        let blocks = store.visibleBlocks
        var result: [DisplayItem] = []
        var index = 0
        while index < blocks.count {
            let block = blocks[index]
            if block.sideBySide == true, index + 1 < blocks.count {
                result.append(.pair(block, blocks[index + 1]))
                index += 2
            } else {
                result.append(.single(block))
                index += 1
            }
        }
        return result
    }

    /// `List`(NSTableView 기반)는 첫 클릭을 행 선택으로 먼저 가로채서 안의 TextField로
    /// 포커스가 넘어가기까지 눈에 띄는 지연이 있었다 — 순수 SwiftUI 레이아웃인
    /// ScrollView + LazyVStack으로 바꿔 그 중간 계층을 없앤다.
    /// 트레이드오프: List가 제공하던 `.onMove` 네이티브 드래그 재정렬은 이 전환으로 사라졌다.
    /// (커스텀 드래그 재정렬은 후속 작업으로 남겨둠)
    private func pageList(_ l10n: Localizer) -> some View {
        // 콘텐츠가 뷰포트보다 짧으면 그 아래 남는 여백은 원래 아무 뷰도 없어 클릭이
        // 반응하지 않았다 — GeometryReader로 뷰포트 높이를 재서 트레일링 여백이
        // 화면 끝까지 채우도록 늘려, 어디를 클릭해도 새 블록으로 이어지게 한다.
        GeometryReader { geo in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Notion처럼 중앙 정렬된 본문 칼럼 (캐릭터 페이지는 제목을 프로필 탭에서 편집)
                    if !store.isCharacterPage {
                        TextField(l10n.t(.untitled), text: $title)
                            .textFieldStyle(.plain)
                            .font(DSFonts.font(size: 30, weight: .bold, family: fontFamily))
                            .padding(.top, 6)
                            .padding(.bottom, 6)
                            .padding(.leading, 44) // 블록 거터와 정렬
                            .modifier(CenteredColumn())
                            .disabled(isReadOnly)
                    }

                    // 나란히(2단) 배치: sideBySide 블록은 다음 블록과 한 행으로 묶는다
                    let display = displayItems
                    ForEach(display) { item in
                        Group {
                            switch item {
                            case .single(let block):
                                PageBlockRow(store: store, block: block, focusedBlockID: $focusedBlockID)
                            case .pair(let left, let right):
                                HStack(alignment: .top, spacing: DesignTokens.Spacing.m) {
                                    PageBlockRow(store: store, block: left, focusedBlockID: $focusedBlockID)
                                        .frame(maxWidth: .infinity, alignment: .topLeading)
                                    PageBlockRow(store: store, block: right, focusedBlockID: $focusedBlockID)
                                        .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                            }
                        }
                        .modifier(CenteredColumn())
                        .id(item.id)
                        .allowsHitTesting(!isReadOnly)
                    }

                    Color.clear
                        .frame(minHeight: 200, maxHeight: .infinity)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !isReadOnly else { return }
                            if let last = store.content.blocks.last {
                                if last.text.isEmpty, last.kind == .paragraph {
                                    store.focusRequest = last.id
                                } else {
                                    store.insertBlock(after: last.id)
                                }
                            }
                        }
                        // 문서 맨 끝으로 드래그해서 놓으면 마지막 블록 뒤로 옮긴다.
                        .dropDestination(for: String.self) { items, _ in
                            guard !isReadOnly,
                                  let raw = items.first, let draggedID = UUID(uuidString: raw) else { return false }
                            store.moveBlockToEnd(draggedID)
                            return true
                        }
                }
                .frame(minHeight: geo.size.height, alignment: .top)
            }
        }
    }

    private func toolbar(_ l10n: Localizer) -> some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            BreadcrumbView(breadcrumb)
            Spacer()

            ReadOnlyBadge()

            ToolbarIconButton("arrow.uturn.backward", help: l10n.t(.undo)) { store.undo() }
                .disabled(!store.canUndo || isReadOnly)
                .opacity(store.canUndo && !isReadOnly ? 1 : 0.35)
            ToolbarIconButton("arrow.uturn.forward", help: l10n.t(.redo)) { store.redo() }
                .disabled(!store.canRedo || isReadOnly)
                .opacity(store.canRedo && !isReadOnly ? 1 : 0.35)

            SaveStatusBadge(state: saveState, label: l10n.t(saveState.labelKey), action: onManualSave)

            ReadOnlyToggle()

            Menu {
                Button(l10n.t(.exportMarkdown)) { exportMarkdown() }
                Button(l10n.t(.exportHTML)) { exportHTML() }
                Button(l10n.t(.exportPDF)) { exportPDF() }
                if !isReadOnly {
                    Divider()
                    Button(l10n.t(.importMarkdown)) { importMarkdown() }
                }
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
