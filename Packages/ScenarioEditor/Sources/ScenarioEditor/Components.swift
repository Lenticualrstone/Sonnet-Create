import AppCore
import DesignSystem
import DocumentKit
import SwiftUI

// MARK: - 캐스트 아바타

struct CastAvatar: View {
    let member: CastMember?
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle()
                .fill((member.map { Color(hex: $0.accentHex) } ?? Color.gray).opacity(0.28))
            if let member {
                Image(systemName: member.symbolName)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(Color(hex: member.accentHex))
            } else {
                Text("?")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(.separator.opacity(0.5), lineWidth: 0.5))
    }
}

// MARK: - 블록 행 (투명 버블 + 호버 드래그 핸들 + 빠른 메뉴)

struct ScenarioBlockRow: View {
    @Bindable var store: ScenarioStore
    let block: ScenarioBlock

    @State private var hovering = false
    @Environment(\.renderQuality) private var quality
    @Environment(\.contentFontScale) private var fontScale
    @Environment(\.contentLineSpacing) private var lineScale
    @Environment(\.contentFontFamily) private var fontFamily
    @Environment(\.dialogueDisplayStyle) private var displayStyle
    @Environment(\.dialogueAvatarSize) private var avatarSize
    @Environment(\.resolvedAccent) private var accent

    var body: some View {
        let l10n = Localizer.shared
        HStack(alignment: .top, spacing: DesignTokens.Spacing.s) {
            // 세로 3점 드래그 핸들 (호버 시 노출)
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 16, height: 24)
                .opacity(hovering ? 1 : 0)

            switch block.kind {
            case .line: lineBubble
            case .instruction: instructionBlock
            case .divider: dividerBlock
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(DesignTokens.Motion.snappy, value: hovering)
        .contextMenu {
            if block.kind != .divider {
                Button(l10n.t(.editContent)) { store.beginEditing(block) }
            }
            if store.activeBranchID == nil {
                Button(l10n.t(.branchFromHere)) {
                    store.createBranch(
                        after: block,
                        name: "\(l10n.t(.branch)) \(store.content.branches.count + 1)"
                    )
                }
            }
            Divider()
            Button(l10n.t(.delete), role: .destructive) { store.deleteBlock(block.id) }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .strokeBorder(accent.opacity(0.55), lineWidth: 1.5)
                .opacity(store.searchFocusID == block.id ? 1 : 0)
        )
        .opacity(store.editingBlockID == block.id ? 0.4 : 1)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }

    /// 대사 — 버블 없이 투명 배경 (스크린플레이처럼 담백하게).
    /// 캐릭터 프로필/이름 표시 방식과 프로필 크기는 설정 > 에디터에서 조절한다.
    private var lineBubble: some View {
        let speakers = store.speakers(of: block)
        return HStack(alignment: .top, spacing: DesignTokens.Spacing.s) {
            if displayStyle != "nameOnly", displayStyle != "hidden" {
                SpeakerCluster(speakers: speakers, avatarSize: avatarSize)
            }
            VStack(alignment: .leading, spacing: 3) {
                if displayStyle != "avatarOnly", displayStyle != "hidden" {
                    Text(speakerLabel(speakers))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(speakers.first.map { Color(hex: $0.accentHex) } ?? .secondary)
                }
                Text(markdownText)
                    .font(DSFonts.font(size: 13 * fontScale, family: fontFamily))
                    .contentLineSpacing(lineScale)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        }
    }

    /// 구분선 — 장면 전환. 제목이 있으면 중앙 모노 칩(2a 장면 헤더), 없으면 얇은 선.
    @ViewBuilder
    private var dividerBlock: some View {
        if block.text.isEmpty {
            Rectangle()
                .fill(.separator)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        } else {
            HStack {
                Spacer()
                Text(block.text)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .kerning(1.2)
                    .foregroundStyle(SonnetPalette.inkMuted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(SonnetPalette.ink.opacity(0.05)))
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    private var instructionBlock: some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            Rectangle()
                .fill(.tertiary)
                .frame(width: 2)
            Text(markdownText)
                .font(DSFonts.font(size: 12 * fontScale, family: fontFamily).italic())
                .contentLineSpacing(lineScale)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
    }

    private var markdownText: AttributedString {
        var attributed = (try? AttributedString(
            markdown: block.text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(block.text)

        // 검색 일치 구간 하이라이트 (대소문자·발음 구별 없이 전 구간)
        let query = store.searchQuery
        if !query.isEmpty {
            var start = attributed.startIndex
            while start < attributed.endIndex,
                  let range = attributed[start...].range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
                attributed[range].backgroundColor = .yellow.opacity(0.45)
                start = range.upperBound
            }
        }
        return attributed
    }

    private func speakerLabel(_ speakers: [CastMember]) -> String {
        let l10n = Localizer.shared
        guard let first = speakers.first else { return "?" }
        if speakers.count == 1 { return first.name }
        return first.name + " " + String(format: l10n.t(.andOthers), speakers.count - 1)
    }
}

/// 다중 화자: 아바타 겹침 + 호버 팝오버로 전체 명단.
struct SpeakerCluster: View {
    let speakers: [CastMember]
    var avatarSize: CGFloat = 34

    @State private var showPopover = false

    /// 겹친 아바타 사이 오프셋 — 크기에 비례해 겹침 비율을 유지한다.
    private var stackOffset: CGFloat { avatarSize * 0.41 }

    var body: some View {
        Group {
            if speakers.count <= 1 {
                CastAvatar(member: speakers.first, size: avatarSize)
            } else {
                ZStack {
                    ForEach(Array(speakers.prefix(3).enumerated()), id: \.element.id) { index, member in
                        CastAvatar(member: member, size: avatarSize)
                            .offset(x: CGFloat(index) * stackOffset)
                    }
                }
                .frame(width: avatarSize + CGFloat(min(speakers.count, 3) - 1) * stackOffset, alignment: .leading)
                .onHover { hovering in
                    if hovering {
                        // 이 클러스터는 List/ForEach 블록 행 안에 있다 — 다른 트리거로
                        // 블록 배열이 바뀌는 도중 popover를 열면 앵커 뷰가 아직 확정되지
                        // 않아 NSPopover가 크래시할 수 있다 (macOS 26). 한 틱 지연해서 연다.
                        DispatchQueue.main.async { showPopover = true }
                    } else {
                        showPopover = false
                    }
                }
                .popover(isPresented: $showPopover, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(speakers) { member in
                            HStack(spacing: 6) {
                                CastAvatar(member: member, size: 20)
                                Text(member.name).font(.callout)
                            }
                        }
                    }
                    .padding(10)
                }
            }
        }
    }
}

// MARK: - AI 제안 스트립

struct SuggestionStrip: View {
    @Bindable var store: ScenarioStore
    @Environment(\.renderQuality) private var quality

    var body: some View {
        let l10n = Localizer.shared
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            HStack(spacing: 6) {
                // 이어쓰기 생성 중엔 AI 스피어가 요동친다 (채팅과 동일한 아이덴티티)
                AISphere(size: 16, activity: store.isGenerating ? .thinking : .idle)
                Text(store.isGenerating ? l10n.t(.aiSuggesting) : l10n.t(.aiCompose))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.pendingSuggestions.isEmpty {
                    Button(l10n.t(.acceptAll)) { store.acceptAllSuggestions() }
                        .font(.caption)
                    Button(l10n.t(.dismissAll)) { store.dismissSuggestions() }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            ForEach(store.pendingSuggestions) { block in
                HStack(alignment: .top, spacing: DesignTokens.Spacing.s) {
                    if block.kind == .line {
                        SpeakerCluster(speakers: store.speakers(of: block))
                    }
                    Text(block.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(l10n.t(.accept)) { store.acceptSuggestion(block) }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    Button {
                        store.pendingSuggestions.removeAll { $0.id == block.id }
                    } label: {
                        Image(systemName: "xmark").font(.caption2)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.tertiary)
                )
            }
        }
        .padding(DesignTokens.Spacing.s)
        .glassSurface(cornerRadius: DesignTokens.Radius.medium, quality: quality)
        .frame(maxWidth: 640)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - 캐릭터 인스펙터 (좌측)

struct CharacterInspectorView: View {
    @Bindable var store: ScenarioStore
    let onOpenCharacterPage: (UUID) -> Void
    /// 캐스트로부터 캐릭터 페이지(.scpa) 생성 — 생성된 문서 UUID 반환 (앱이 주입)
    let onCreateCharacterPage: (CastMember) -> UUID?

    @State private var newName = ""
    @Environment(\.resolvedAccent) private var accent
    @Environment(\.readOnlyMode) private var readOnlyMode

    private var isReadOnly: Bool { readOnlyMode?.wrappedValue == true }

    var body: some View {
        let l10n = Localizer.shared
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(l10n.t(.characters))
                    .font(.headline)
                Spacer()
                if !isReadOnly {
                    importMenu(l10n)
                }
            }
            .padding(DesignTokens.Spacing.m)

            List {
                ForEach(store.content.cast) { member in
                    CastInspectorRow(
                        store: store,
                        member: member,
                        onOpen: onOpenCharacterPage,
                        onCreatePage: onCreateCharacterPage
                    )
                    .allowsHitTesting(!isReadOnly)
                    .moveDisabled(isReadOnly)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .onMove { store.moveCast(from: $0, to: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Divider().opacity(0.4)
            HStack(spacing: 6) {
                TextField(l10n.t(.addCharacter), text: $newName)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .onSubmit(addMember)
                Button(action: addMember) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(newName.isEmpty ? Color.secondary : accent)
                }
                .buttonStyle(.plain)
                .disabled(newName.isEmpty)
            }
            .padding(DesignTokens.Spacing.s)
            .allowsHitTesting(!isReadOnly)
            .opacity(isReadOnly ? 0.4 : 1)
        }
    }

    private func addMember() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.addCastMember(name: name)
        newName = ""
    }

    /// 프로젝트 캐릭터 페이지 → 캐스트 가져오기.
    @ViewBuilder
    private func importMenu(_ l10n: Localizer) -> some View {
        let catalog = store.characterCatalog?() ?? []
        if !catalog.isEmpty {
            Menu {
                ForEach(catalog) { character in
                    let alreadyImported = store.content.cast.contains { $0.characterPageID == character.id }
                    Button {
                        store.importCastMember(character)
                    } label: {
                        if alreadyImported {
                            Label(character.name, systemImage: "checkmark")
                        } else {
                            Label(character.name, systemImage: character.symbolName)
                        }
                    }
                    .disabled(alreadyImported)
                }
            } label: {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(l10n.t(.importFromProject))
        }
    }
}

struct CastInspectorRow: View {
    @Bindable var store: ScenarioStore
    let member: CastMember
    let onOpen: (UUID) -> Void
    let onCreatePage: (CastMember) -> UUID?

    @State private var hovering = false
    @State private var editing = false

    var body: some View {
        let l10n = Localizer.shared
        HStack(spacing: DesignTokens.Spacing.s) {
            CastAvatar(member: member, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(member.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if !member.roleLine.isEmpty {
                    Text(member.roleLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if hovering {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { beginEditing() }
        .popover(isPresented: $editing, arrowEdge: .trailing) {
            CastEditorView(store: store, memberID: member.id, onOpen: onOpen, onCreatePage: onCreatePage)
        }
        .contextMenu {
            Button(l10n.t(.editContent)) { beginEditing() }
            if let pageID = member.characterPageID {
                Button(l10n.t(.open)) { onOpen(pageID) }
            }
            Divider()
            Button(l10n.t(.delete), role: .destructive) { store.removeCastMember(member.id) }
        }
        .animation(DesignTokens.Motion.snappy, value: hovering)
    }

    /// List 행이 아직 재배치/디프 중일 때 popover를 열면 앵커 뷰가 유효하지 않아
    /// NSPopover가 크래시한다 (macOS 26) — 다음 런루프 틱으로 지연해 안전하게 연다.
    private func beginEditing() {
        DispatchQueue.main.async { editing = true }
    }
}

/// 캐릭터 편집 팝오버 — 이름·역할·심볼·색, 캐릭터 페이지 생성/열기.
struct CastEditorView: View {
    @Bindable var store: ScenarioStore
    let memberID: UUID
    let onOpen: (UUID) -> Void
    let onCreatePage: (CastMember) -> UUID?

    @Environment(\.dismiss) private var dismiss

    private let symbols = [
        "person.fill", "theatermasks.fill", "crown.fill", "flame.fill", "leaf.fill",
        "moon.stars.fill", "bolt.fill", "heart.fill", "eye.fill", "pawprint.fill",
    ]
    private let palette = ["#B23A21", "#3E5C50", "#8A6D2F", "#9E5A3C", "#5F6B7C"]

    private var member: CastMember? { store.castMember(id: memberID) }

    var body: some View {
        let l10n = Localizer.shared
        if let member {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                HStack(spacing: DesignTokens.Spacing.s) {
                    CastAvatar(member: member, size: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(l10n.t(.characterName), text: field(\.name))
                            .textFieldStyle(.roundedBorder)
                        TextField(l10n.t(.characterRole), text: field(\.roleLine))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }
                }

                // 심볼
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 4), count: 5), spacing: 4) {
                    ForEach(symbols, id: \.self) { symbol in
                        Button {
                            update { $0.symbolName = symbol }
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 12))
                                .foregroundStyle(member.symbolName == symbol ? Color(hex: member.accentHex) : .secondary)
                                .frame(width: 26, height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(member.symbolName == symbol ? Color(hex: member.accentHex).opacity(0.18) : .clear)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                // 색상
                HStack(spacing: 6) {
                    ForEach(palette, id: \.self) { hex in
                        Button {
                            update { $0.accentHex = hex }
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle().strokeBorder(
                                        member.accentHex == hex ? Color.primary : .clear, lineWidth: 2
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                // 캐릭터 페이지 연결
                if let pageID = member.characterPageID {
                    Button {
                        dismiss()
                        onOpen(pageID)
                    } label: {
                        Label(l10n.t(.characterPage) + " " + l10n.t(.open), systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    Button {
                        if let pageID = onCreatePage(member) {
                            update { $0.characterPageID = pageID }
                            dismiss()
                            onOpen(pageID)
                        }
                    } label: {
                        Label(l10n.t(.newCharacter), systemImage: "person.crop.circle.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                }

                Button(role: .destructive) {
                    dismiss()
                    store.removeCastMember(memberID)
                } label: {
                    Label(l10n.t(.delete), systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(DesignTokens.Spacing.m)
            .frame(width: 240)
        }
    }

    private func update(_ transform: (inout CastMember) -> Void) {
        guard var current = member else { return }
        transform(&current)
        store.updateCastMember(current)
    }

    private func field(_ keyPath: WritableKeyPath<CastMember, String>) -> Binding<String> {
        Binding(
            get: { member?[keyPath: keyPath] ?? "" },
            set: { newValue in update { $0[keyPath: keyPath] = newValue } }
        )
    }
}
