import AppCore
import DesignSystem
import DocumentKit
import SwiftUI

// MARK: - 캐스트 아바타

struct CastAvatar: View {
    let member: CastMember?
    var size: CGFloat = 26

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
        .opacity(store.editingBlockID == block.id ? 0.4 : 1)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }

    /// 대사 — 버블 없이 투명 배경 (스크린플레이처럼 담백하게).
    private var lineBubble: some View {
        let speakers = store.speakers(of: block)
        return HStack(alignment: .top, spacing: DesignTokens.Spacing.s) {
            SpeakerCluster(speakers: speakers)
            VStack(alignment: .leading, spacing: 3) {
                Text(speakerLabel(speakers))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(speakers.first.map { Color(hex: $0.accentHex) } ?? .secondary)
                Text(markdownText)
                    .font(DSFonts.font(size: 13 * fontScale, family: fontFamily))
                    .contentLineSpacing(lineScale)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        }
    }

    /// 구분선 — 장면 전환.
    private var dividerBlock: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
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
        (try? AttributedString(
            markdown: block.text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(block.text)
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

    @State private var showPopover = false

    var body: some View {
        Group {
            if speakers.count <= 1 {
                CastAvatar(member: speakers.first)
            } else {
                ZStack {
                    ForEach(Array(speakers.prefix(3).enumerated()), id: \.element.id) { index, member in
                        CastAvatar(member: member, size: 24)
                            .offset(x: CGFloat(index) * 12)
                    }
                }
                .frame(width: 24 + CGFloat(min(speakers.count, 3) - 1) * 12, alignment: .leading)
                .onHover { showPopover = $0 }
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
            HStack {
                Label(
                    store.isGenerating ? l10n.t(.aiSuggesting) : l10n.t(.aiCompose),
                    systemImage: "sparkles"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                if store.isGenerating { ProgressView().controlSize(.mini) }
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

    var body: some View {
        let l10n = Localizer.shared
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(l10n.t(.characters))
                    .font(.headline)
                Spacer()
                importMenu(l10n)
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
                        .foregroundStyle(newName.isEmpty ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(newName.isEmpty)
            }
            .padding(DesignTokens.Spacing.s)
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
            CastAvatar(member: member, size: 30)
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
        .onTapGesture { editing = true }
        .popover(isPresented: $editing, arrowEdge: .trailing) {
            CastEditorView(store: store, memberID: member.id, onOpen: onOpen, onCreatePage: onCreatePage)
        }
        .contextMenu {
            Button(l10n.t(.editContent)) { editing = true }
            if let pageID = member.characterPageID {
                Button(l10n.t(.open)) { onOpen(pageID) }
            }
            Divider()
            Button(l10n.t(.delete), role: .destructive) { store.removeCastMember(member.id) }
        }
        .animation(DesignTokens.Motion.snappy, value: hovering)
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
    private let palette = ["#5AC8FA", "#B18CFF", "#FF6482", "#FFB340", "#63E6B6"]

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
