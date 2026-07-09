import AppCore
import DesignSystem
import DocumentKit
import SwiftUI

/// 블록 한 행 — 호버 드래그 핸들 + 타입별 렌더링 + '/' 커맨드 메뉴.
struct PageBlockRow: View {
    @Bindable var store: PageStore
    let block: PageBlock
    var focusedBlockID: FocusState<UUID?>.Binding

    @State private var hovering = false
    /// 드래그 중인 블록이 이 행 위로 올라왔는지 — 삽입 위치 표시선에 쓴다.
    @State private var isDropTargeted = false
    @Environment(\.renderQuality) private var quality
    @Environment(\.contentFontScale) private var fontScale
    @Environment(\.contentLineSpacing) private var lineScale
    @Environment(\.contentFontFamily) private var fontFamily
    @Environment(\.resolvedAccent) private var accent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            gutter

            // 들여쓰기
            if block.indent > 0 {
                Spacer().frame(width: CGFloat(block.indent) * 22)
            }

            leading

            content
        }
        // Notion처럼 줄 전체가 호버/클릭 대상이 되도록 — 이게 없으면 텍스트가 짧을 때
        // 글자 바로 옆까지만 반응해서 "빈 공간을 눌러도 편집이 안 되는" 느낌을 준다.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, verticalPadding)
        .padding(.trailing, 6)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.05) : .clear)
        )
        .overlay(alignment: .top) {
            if isDropTargeted {
                Rectangle()
                    .fill(accent)
                    .frame(height: 2)
                    .padding(.leading, 44)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // 호버 피드백은 즉각적이어야 한다 — 기존 snappy 스프링(0.28초)은 마우스를 올렸을 때
        // 거터/배경이 한 박자 늦게 나타나는 느낌을 줬다. 거의 즉시 반응하도록 빠르게.
        .animation(.easeOut(duration: 0.08), value: hovering)
        // 커스텀 드래그 재정렬 — List의 .onMove를 대체. 블록 ID(문자열)만 옮겨서 항상
        // "이 블록 바로 앞"에 끼워 넣는다 (위/아래 절반 구분 없이 단순하게).
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let draggedID = UUID(uuidString: raw), draggedID != block.id else {
                return false
            }
            store.moveBlock(draggedID, before: block.id)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        // 주의: 여기에 popover를 붙이면 List 레이아웃 패스 중 NSPopover 예외로 크래시한다.
        // 슬래시 메뉴는 PageEditorView의 하단 팔레트 오버레이로 렌더링된다.
    }

    /// 좌측 거터 — 블록 추가(+)와 드래그 핸들, 호버 시 노출 (Notion 패턴).
    private var gutter: some View {
        HStack(spacing: 0) {
            Button {
                store.insertBlock(after: block.id)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Localizer.shared.t(.newDocument))

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 20, height: 22)
                .contentShape(Rectangle())
                // 핸들만 드래그 가능 — 행 전체를 드래그 소스로 만들면 텍스트 선택/편집과 충돌한다.
                .draggable(block.id.uuidString)
                .contextMenu {
                    let l10n = Localizer.shared
                    // 좌우(2단) 배치 — 다음 블록과 나란히
                    Toggle(l10n.t(.sideBySideToggle), isOn: Binding(
                        get: { store.block(id: block.id)?.sideBySide ?? false },
                        set: { enabled in
                            guard var updated = store.block(id: block.id) else { return }
                            updated.sideBySide = enabled ? true : nil
                            store.updateBlock(updated)
                        }
                    ))
                    Divider()
                    Button(l10n.t(.duplicate)) { store.duplicateBlock(block.id) }
                    Button(l10n.t(.delete), role: .destructive) { store.deleteBlock(block.id) }
                }
        }
        .frame(width: 44, alignment: .trailing)
        .opacity(hovering ? 1 : 0)
    }

    @Environment(\.contentBlockSpacing) private var blockSpacing

    private var verticalPadding: CGFloat {
        let base: CGFloat = switch block.kind {
        case .heading1: 10
        case .heading2: 7
        case .heading3: 5
        default: 1
        }
        return base + blockSpacing / 2
    }

    // MARK: 타입별 leading 장식

    @ViewBuilder
    private var leading: some View {
        switch block.kind {
        case .bulleted:
            Text("•").font(.body.weight(.bold)).foregroundStyle(.secondary)
        case .numbered:
            Text("\(store.numberedIndex(of: block.id)).")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        case .task:
            Button {
                store.toggleCheck(block.id)
            } label: {
                Image(systemName: block.isChecked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(block.isChecked ? accent : .secondary)
            }
            .buttonStyle(.plain)
        case .toggle:
            Button {
                store.toggleExpand(block.id)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(block.isExpanded ? 90 : 0))
            }
            .buttonStyle(.plain)
            .animation(DesignTokens.Motion.snappy, value: block.isExpanded)
        case .quote:
            RoundedRectangle(cornerRadius: 1)
                .fill(accent.opacity(0.6))
                .frame(width: 3, height: 18)
        case .callout:
            Text("💡").font(.callout)
        default:
            EmptyView()
        }
    }

    // MARK: 본문

    @ViewBuilder
    private var content: some View {
        switch block.kind {
        case .image:
            ImageBlockView(store: store, block: block)
        case .table:
            TableBlockView(store: store, block: block)
        case .divider:
            Rectangle()
                .fill(.separator)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        case .code:
            textField
                .font(.system(.callout, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
        case .callout:
            textField
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(cornerRadius: DesignTokens.Radius.small, tint: accent, quality: quality)
        default:
            textField
        }
    }

    private var textField: some View {
        TextField(
            placeholder,
            text: Binding(
                get: { store.block(id: block.id)?.text ?? "" },
                set: { store.updateText(block.id, text: $0) }
            ),
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(font)
        .contentLineSpacing(lineScale)
        .strikethrough(block.kind == .task && block.isChecked)
        .foregroundStyle(textColor)
        .focused(focusedBlockID, equals: block.id)
        // 텍스트가 짧아도 줄 전체가 클릭 대상이 되도록 폭을 채운다 — 빈 공간을 눌러도
        // 커서가 가장 가까운 위치(대개 줄 끝)로 들어가는 Notion식 동작.
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // Delete는 전용 오버로드로 분리 — 필드가 이미 비어있을 때는 AppKit이 "지울 게 없다"며
        // 내부에서 이벤트를 삼켜, 범용 onKeyPress 클로저 안의 switch로는 잡히지 않는 경우가 있었다.
        .onKeyPress(.delete) {
            let text = store.block(id: block.id)?.text ?? ""
            guard text.isEmpty else { return .ignored }
            store.removeBlockFocusPrevious(block.id)
            return .handled
        }
        .onKeyPress { press in
            handleKey(press)
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // 슬래시 메뉴가 열려 있으면 ↑↓로 후보 탐색
        if store.slashBlockID == block.id {
            let candidates = SlashCommandMenu.matches(query: store.slashQuery)
            switch press.key {
            case .upArrow:
                store.slashSelectionIndex = max(0, store.slashSelectionIndex - 1)
                return .handled
            case .downArrow:
                store.slashSelectionIndex = min(max(0, candidates.count - 1), store.slashSelectionIndex + 1)
                return .handled
            default:
                break
            }
        }
        switch press.key {
        case .return:
            // Enter = 새 블록 (슬래시 메뉴가 열려 있으면 선택된 후보 적용), ⇧Enter = 줄바꿈
            if press.modifiers.contains(.shift) { return .ignored }
            if store.slashBlockID == block.id {
                let candidates = SlashCommandMenu.matches(query: store.slashQuery)
                if candidates.indices.contains(store.slashSelectionIndex) {
                    store.applySlashCommand(candidates[store.slashSelectionIndex].kind)
                } else if let first = candidates.first {
                    store.applySlashCommand(first.kind)
                } else {
                    store.closeSlashMenu()
                }
            } else {
                store.insertBlock(after: block.id)
            }
            return .handled
        case .tab:
            if press.modifiers.contains(.shift) {
                store.outdent(block.id)
            } else {
                store.indent(block.id)
            }
            return .handled
        case .escape:
            if store.slashBlockID == block.id {
                store.closeSlashMenu()
                return .handled
            }
            return .ignored
        default:
            return .ignored
        }
    }

    /// '/' 힌트는 포커스 + 빈 블록일 때만 — 항상 보이면 편집 중이 아닌 빈 블록도
    /// 전부 힌트로 뒤덮여 오히려 산만해진다 (헤딩 placeholder는 원래부터 상시 노출).
    private var placeholder: String {
        let l10n = Localizer.shared
        switch block.kind {
        case .heading1: return l10n.t(.blockHeading1)
        case .heading2: return l10n.t(.blockHeading2)
        case .heading3: return l10n.t(.blockHeading3)
        case .code: return "code"
        default: return focusedBlockID.wrappedValue == block.id ? l10n.t(.slashHint) : ""
        }
    }

    private var font: Font {
        switch block.kind {
        case .heading1: DSFonts.font(size: 24 * fontScale, weight: .bold, family: fontFamily)
        case .heading2: DSFonts.font(size: 19 * fontScale, weight: .bold, family: fontFamily)
        case .heading3: DSFonts.font(size: 16 * fontScale, weight: .semibold, family: fontFamily)
        case .quote: DSFonts.font(size: 13 * fontScale, family: fontFamily).italic()
        default: DSFonts.font(size: 13 * fontScale, family: fontFamily)
        }
    }

    private var textColor: Color {
        switch block.kind {
        case .quote: .secondary
        case .task where block.isChecked: .secondary
        default: .primary
        }
    }
}

// MARK: - '/' 커맨드 메뉴

struct SlashCommandMenu: View {
    @Bindable var store: PageStore
    @Environment(\.resolvedAccent) private var accent

    struct Item: Identifiable {
        let kind: PageBlockKind
        let key: L10nKey
        let symbol: String
        var id: String { kind.rawValue }
    }

    private static let items: [Item] = [
        Item(kind: .paragraph, key: .blockParagraph, symbol: "text.alignleft"),
        Item(kind: .heading1, key: .blockHeading1, symbol: "textformat.size.larger"),
        Item(kind: .heading2, key: .blockHeading2, symbol: "textformat.size"),
        Item(kind: .heading3, key: .blockHeading3, symbol: "textformat.size.smaller"),
        Item(kind: .bulleted, key: .blockBulleted, symbol: "list.bullet"),
        Item(kind: .numbered, key: .blockNumbered, symbol: "list.number"),
        Item(kind: .task, key: .blockTask, symbol: "checkmark.square"),
        Item(kind: .toggle, key: .blockToggle, symbol: "chevron.right.square"),
        Item(kind: .quote, key: .blockQuote, symbol: "text.quote"),
        Item(kind: .code, key: .blockCode, symbol: "chevron.left.forwardslash.chevron.right"),
        Item(kind: .divider, key: .blockDivider, symbol: "minus"),
        Item(kind: .callout, key: .blockCallout, symbol: "lightbulb"),
        Item(kind: .image, key: .blockImage, symbol: "photo"),
        Item(kind: .table, key: .blockTable, symbol: "tablecells"),
    ]

    @MainActor
    static func matches(query: String) -> [Item] {
        let l10n = Localizer.shared
        guard !query.isEmpty else { return items }
        return items.filter {
            l10n.t($0.key).localizedCaseInsensitiveContains(query)
                || $0.kind.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

    /// Enter로 첫 후보를 즉시 적용할 때 사용.
    @MainActor
    static func firstMatch(query: String) -> PageBlockKind? {
        matches(query: query).first?.kind
    }

    private var filtered: [Item] {
        Self.matches(query: store.slashQuery)
    }

    var body: some View {
        let l10n = Localizer.shared
        let selection = min(store.slashSelectionIndex, max(0, filtered.count - 1))
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                    Button {
                        store.applySlashCommand(item.kind)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: item.symbol)
                                .font(.callout)
                                .foregroundStyle(index == selection ? accent : .secondary)
                                .frame(width: 22)
                            Text(l10n.t(item.key))
                                .font(.callout)
                            Spacer()
                            if index == selection {
                                Text("↩")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(index == selection ? Color.primary.opacity(0.08) : .clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        if inside { store.slashSelectionIndex = index }
                    }
                }
            }
            .padding(6)
        }
        .frame(width: 220, height: min(CGFloat(filtered.count) * 30 + 16, 320))
    }
}
