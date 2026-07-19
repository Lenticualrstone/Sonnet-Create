import AppCore
import AppKit
import DesignSystem
import DocumentKit
import SwiftUI

// MARK: - 캐릭터 페이지 탭

enum CharacterPageTab: String, CaseIterable, Identifiable {
    case profile, notes, relations, gallery, voice

    var id: String { rawValue }

    var key: L10nKey {
        switch self {
        case .profile: .profileTab
        case .notes: .notesTab
        case .relations: .relationsTab
        case .gallery: .galleryTab
        case .voice: .voiceTab
        }
    }

    var symbol: String {
        switch self {
        case .profile: "person.text.rectangle"
        case .notes: "doc.text"
        case .relations: "point.3.connected.trianglepath.dotted"
        case .gallery: "photo.on.rectangle.angled"
        case .voice: "waveform"
        }
    }
}

/// 캐릭터 페이지 컨테이너 — 프로필/노트/관계/갤러리/보이스 탭 (Campfire·World Anvil 패턴).
struct CharacterPageContainer<Notes: View>: View {
    @Bindable var store: PageStore
    @Binding var title: String
    @ViewBuilder let notes: () -> Notes

    @State private var tab: CharacterPageTab = .profile
    @Environment(\.renderQuality) private var quality
    @Environment(\.contentFontFamily) private var fontFamily
    @Environment(\.resolvedAccent) private var accent
    @Environment(\.readOnlyMode) private var readOnlyMode

    private var isReadOnly: Bool { readOnlyMode?.wrappedValue == true }

    var body: some View {
        let l10n = Localizer.shared
        VStack(spacing: 0) {
            // 탭 선택기
            HStack(spacing: 2) {
                ForEach(CharacterPageTab.allCases) { candidate in
                    Button {
                        withAnimation(DesignTokens.Motion.snappy) { tab = candidate }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: candidate.symbol)
                                .font(.caption)
                            Text(l10n.t(candidate.key))
                                .font(.callout)
                        }
                        .foregroundStyle(tab == candidate ? accent : Color.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                                .fill(tab == candidate ? accent.opacity(0.12) : .clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.m)
            .padding(.vertical, 6)
            Divider().opacity(0.35)

            // 읽기 전용 모드: 탭 전환·스크롤은 살리고 각 탭의 편집 표면만
            // 스크롤 콘텐츠 계층에서 잠근다 (각 탭 내부에서 처리).
            switch tab {
            case .profile:
                CharacterProfileTab(store: store, title: $title)
            case .notes:
                notes()
            case .relations:
                CharacterRelationsTab(store: store)
            case .gallery:
                CharacterGalleryTab(store: store)
            case .voice:
                CharacterVoiceTab(store: store)
            }
        }
    }
}

// MARK: - 프로필 탭 (구조화 필드 + 등장 기록 보조)

struct CharacterProfileTab: View {
    @Bindable var store: PageStore
    @Binding var title: String

    @State private var showImagePanel = false
    @Environment(\.renderQuality) private var quality
    @Environment(\.contentFontFamily) private var fontFamily
    @Environment(\.resolvedAccent) private var accent

    var body: some View {
        let l10n = Localizer.shared
        let profile = store.content.profile ?? CharacterProfile()
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                // 헤더: 대형 아바타(클릭 → 편집 패널) + 이름/역할/소개
                HStack(alignment: .top, spacing: DesignTokens.Spacing.l) {
                    Button {
                        showImagePanel = true
                    } label: {
                        CharacterAvatarView(store: store, profile: profile, size: 128)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(accent)
                                    .background(Circle().fill(SonnetPalette.surface))
                            }
                    }
                    .buttonStyle(.plain)
                    .help(l10n.t(.editProfileImage))

                    VStack(alignment: .leading, spacing: 8) {
                        TextField(l10n.t(.untitled), text: $title)
                            .textFieldStyle(.plain)
                            .font(DSFonts.font(size: 28, weight: .bold, family: fontFamily))
                        TextField(l10n.t(.characterRole), text: profileField(\.role))
                            .textFieldStyle(.plain)
                            .font(DSFonts.font(size: 15, weight: .medium, family: fontFamily))
                            .foregroundStyle(accent)
                        TextField(l10n.t(.characterSummary), text: profileField(\.summary), axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(DSFonts.font(size: 13, family: fontFamily))
                            .foregroundStyle(.secondary)
                            .lineLimit(2...5)
                    }
                }

                // 구조화 필드 (나이/소속 등 자유 키-값)
                fieldsSection(l10n)

                // 등장 기록 — 보조 정보 (메인이 되지 않게 하단 캡션)
                appearancesSection(l10n)
            }
            .padding(DesignTokens.Spacing.l)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
            .modifier(ReadOnlyContentLock())
        }
        .sheet(isPresented: $showImagePanel) {
            ProfileImagePanel(store: store)
        }
    }

    private func profileField(_ keyPath: WritableKeyPath<CharacterProfile, String>) -> Binding<String> {
        Binding(
            get: { store.content.profile?[keyPath: keyPath] ?? "" },
            set: { newValue in store.updateProfile { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func fieldsSection(_ l10n: Localizer) -> some View {
        let fields = store.content.profile?.fields ?? []
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(fields) { field in
                HStack(spacing: DesignTokens.Spacing.s) {
                    TextField(l10n.t(.fieldName), text: fieldBinding(field.id, \.name))
                        .textFieldStyle(.plain)
                        .font(.callout.weight(.semibold))
                        .frame(width: 120, alignment: .leading)
                    TextField(l10n.t(.fieldValue), text: fieldBinding(field.id, \.value))
                        .textFieldStyle(.plain)
                        .font(.callout)
                    Button {
                        store.updateProfile { $0.fields?.removeAll { $0.id == field.id } }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                        .fill(SonnetPalette.surface)
                )
            }
            Button {
                store.updateProfile {
                    var current = $0.fields ?? []
                    current.append(CharacterField())
                    $0.fields = current
                }
            } label: {
                Label(l10n.t(.addField), systemImage: "plus")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
        }
    }

    private func fieldBinding(_ id: UUID, _ keyPath: WritableKeyPath<CharacterField, String>) -> Binding<String> {
        Binding(
            get: {
                store.content.profile?.fields?.first { $0.id == id }?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                store.updateProfile { profile in
                    guard var fields = profile.fields,
                          let idx = fields.firstIndex(where: { $0.id == id }) else { return }
                    fields[idx][keyPath: keyPath] = newValue
                    profile.fields = fields
                }
            }
        )
    }

    @ViewBuilder
    private func appearancesSection(_ l10n: Localizer) -> some View {
        let stats = store.appearanceStats?() ?? []
        if !stats.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label(l10n.t(.appearances), systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                    HStack(spacing: 6) {
                        Text(stat.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: l10n.t(.linesCountFormat), stat.lineCount))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.top, DesignTokens.Spacing.m)
        }
    }
}

// MARK: - 아바타 (크롭 적용 렌더)

struct CharacterAvatarView: View {
    @Bindable var store: PageStore
    let profile: CharacterProfile
    let size: CGFloat

    var body: some View {
        if let path = profile.imageResourcePath,
           let url = store.resourceResolver?(path),
           let image = ImageThumbnailCache.thumbnail(for: url, maxPointSize: size) {
            CroppedCircleImage(
                image: image,
                zoom: profile.cropZoom ?? 1,
                offsetX: profile.cropOffsetX ?? 0,
                offsetY: profile.cropOffsetY ?? 0,
                size: size
            )
            .overlay(Circle().strokeBorder(Color(hex: profile.accentHex).opacity(0.6), lineWidth: 2.5))
        } else {
            ZStack {
                Circle().fill(Color(hex: profile.accentHex).opacity(0.22))
                Image(systemName: profile.symbolName)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Color(hex: profile.accentHex))
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - 관계 탭 (목록 + 방사형 그래프)

struct CharacterRelationsTab: View {
    @Bindable var store: PageStore
    @Environment(\.resolvedAccent) private var accent

    var body: some View {
        let l10n = Localizer.shared
        let relations = store.content.profile?.relations ?? []
        let catalog = store.characterCatalog?() ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                // 방사형 관계도 (자동 생성) + 마인드맵 승격 (3c)
                if !relations.isEmpty {
                    if store.onPromoteRelations != nil {
                        HStack {
                            Spacer()
                            Button {
                                let pairs = relations.map { relation in
                                    (
                                        relation: relation,
                                        name: catalog.first { $0.id == relation.targetPageID }?.name ?? "…"
                                    )
                                }
                                store.onPromoteRelations?(pairs)
                            } label: {
                                Text(l10n.t(.promoteToMindmap))
                                    .font(DSFonts.font(size: 12, family: .pretendard))
                                    .foregroundStyle(accent)
                            }
                            .buttonStyle(.plain)
                            .help(l10n.t(.promoteToMindmap))
                        }
                    }
                    RelationsRadialView(store: store, relations: relations, catalog: catalog)
                        .frame(height: 300)
                        .frame(maxWidth: .infinity)
                }

                // 관계 목록 편집
                ForEach(relations) { relation in
                    HStack(spacing: DesignTokens.Spacing.s) {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(accent)
                        Text(catalog.first { $0.id == relation.targetPageID }?.name ?? "…")
                            .font(.callout.weight(.medium))
                        TextField(l10n.t(.relationLabel), text: relationLabelBinding(relation.id))
                            .textFieldStyle(.plain)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            store.onOpenDocument?(relation.targetPageID)
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        Button {
                            store.updateProfile { $0.relations?.removeAll { $0.id == relation.id } }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                            .fill(SonnetPalette.surface)
                    )
                }

                // 관계 추가
                let existing = Set(relations.map(\.targetPageID))
                let candidates = catalog.filter { !existing.contains($0.id) }
                if !candidates.isEmpty {
                    Menu {
                        ForEach(candidates, id: \.id) { candidate in
                            Button(candidate.name) {
                                store.updateProfile {
                                    var current = $0.relations ?? []
                                    current.append(CharacterRelation(targetPageID: candidate.id))
                                    $0.relations = current
                                }
                            }
                        }
                    } label: {
                        Label(l10n.t(.addRelation), systemImage: "plus")
                            .font(.callout)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            .padding(DesignTokens.Spacing.l)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
            .modifier(ReadOnlyContentLock())
        }
    }

    private func relationLabelBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { store.content.profile?.relations?.first { $0.id == id }?.label ?? "" },
            set: { newValue in
                store.updateProfile { profile in
                    guard var relations = profile.relations,
                          let idx = relations.firstIndex(where: { $0.id == id }) else { return }
                    relations[idx].label = newValue
                    profile.relations = relations
                }
            }
        )
    }
}

/// 중심(이 캐릭터)에서 관계 캐릭터들이 방사형으로 배치되는 자동 관계도.
struct RelationsRadialView: View {
    @Bindable var store: PageStore
    let relations: [CharacterRelation]
    let catalog: [(id: UUID, name: String)]
    @Environment(\.resolvedAccent) private var accent

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - 56
            let profile = store.content.profile ?? CharacterProfile()

            ZStack {
                // 연결선 + 라벨
                Canvas { context, _ in
                    for index in relations.indices {
                        let angle = angleFor(index)
                        let point = CGPoint(
                            x: center.x + cos(angle) * radius,
                            y: center.y + sin(angle) * radius
                        )
                        var path = Path()
                        path.move(to: center)
                        path.addLine(to: point)
                        context.stroke(path, with: .color(.secondary.opacity(0.35)), lineWidth: 1.2)
                    }
                }

                ForEach(Array(relations.enumerated()), id: \.element.id) { index, relation in
                    let angle = angleFor(index)
                    let point = CGPoint(
                        x: center.x + cos(angle) * radius,
                        y: center.y + sin(angle) * radius
                    )
                    let midpoint = CGPoint(
                        x: center.x + cos(angle) * radius * 0.55,
                        y: center.y + sin(angle) * radius * 0.55
                    )

                    if !relation.label.isEmpty {
                        Text(relation.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(SonnetPalette.surface))
                            .position(midpoint)
                    }

                    VStack(spacing: 3) {
                        ZStack {
                            Circle().fill(accent.opacity(0.15))
                            Image(systemName: "person.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(accent)
                        }
                        .frame(width: 40, height: 40)
                        Text(catalog.first { $0.id == relation.targetPageID }?.name ?? "…")
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .position(point)
                    .onTapGesture {
                        store.onOpenDocument?(relation.targetPageID)
                    }
                }

                // 중심 = 이 캐릭터
                CharacterAvatarView(store: store, profile: profile, size: 56)
                    .position(center)
            }
        }
    }

    private func angleFor(_ index: Int) -> CGFloat {
        let count = max(relations.count, 1)
        return CGFloat(index) / CGFloat(count) * 2 * .pi - .pi / 2
    }
}

// MARK: - 갤러리 탭 (복수 이미지 + 시점 태그)

struct CharacterGalleryTab: View {
    @Bindable var store: PageStore
    @Environment(\.resolvedAccent) private var accent

    @State private var enlarged: CharacterGalleryItem?

    var body: some View {
        let l10n = Localizer.shared
        let items = store.content.profile?.gallery ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: DesignTokens.Spacing.m)], spacing: DesignTokens.Spacing.m) {
                    ForEach(items) { item in
                        galleryCard(item, l10n: l10n)
                    }
                }
                Button {
                    addImage()
                } label: {
                    Label(l10n.t(.addImage), systemImage: "photo.badge.plus")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
            }
            .padding(DesignTokens.Spacing.l)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .modifier(ReadOnlyContentLock())
        }
        .sheet(item: $enlarged) { item in
            VStack(spacing: 0) {
                HStack {
                    if !item.phase.isEmpty {
                        Text(item.phase)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(accent.opacity(0.15)))
                    }
                    Spacer()
                    Button {
                        enlarged = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(DesignTokens.Spacing.s)
                if let url = store.resourceResolver?(item.resourcePath),
                   let image = ImageThumbnailCache.thumbnail(for: url, maxPointSize: 900) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .aspectRatio(contentMode: .fit)
                        .padding([.horizontal, .bottom], DesignTokens.Spacing.m)
                }
            }
            .frame(minWidth: 440, minHeight: 360)
            .frame(maxWidth: 860, maxHeight: 680)
        }
    }

    @ViewBuilder
    private func galleryCard(_ item: CharacterGalleryItem, l10n: Localizer) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let url = store.resourceResolver?(item.resourcePath),
               let image = ImageThumbnailCache.thumbnail(for: url, maxPointSize: 260) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous))
                    .onTapGesture {
                        // 갤러리 그리드 ForEach 안 — 항목 삭제/삽입과 겹치면 앵커가
                        // 확정되기 전에 시트가 열려 크래시할 수 있다 (macOS 26). 한 틱 지연.
                        DispatchQueue.main.async { enlarged = item }
                    }
            }
            TextField(l10n.t(.phaseTag), text: galleryBinding(item.id, \.phase))
                .textFieldStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
            TextField(l10n.t(.captionLabel), text: galleryBinding(item.id, \.caption))
                .textFieldStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
                .fill(SonnetPalette.surface)
        )
        .contextMenu {
            Button(l10n.t(.enlarge)) {
                DispatchQueue.main.async { enlarged = item }
            }
            Button(l10n.t(.delete), role: .destructive) {
                store.updateProfile { $0.gallery?.removeAll { $0.id == item.id } }
            }
        }
    }

    private func galleryBinding(_ id: UUID, _ keyPath: WritableKeyPath<CharacterGalleryItem, String>) -> Binding<String> {
        Binding(
            get: { store.content.profile?.gallery?.first { $0.id == id }?[keyPath: keyPath] ?? "" },
            set: { newValue in
                store.updateProfile { profile in
                    guard var gallery = profile.gallery,
                          let idx = gallery.firstIndex(where: { $0.id == id }) else { return }
                    gallery[idx][keyPath: keyPath] = newValue
                    profile.gallery = gallery
                }
            }
        )
    }

    private func addImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let relative = store.resourceImporter?(url) else { continue }
            store.updateProfile {
                var gallery = $0.gallery ?? []
                gallery.append(CharacterGalleryItem(resourcePath: relative))
                $0.gallery = gallery
            }
        }
    }
}

// MARK: - 보이스 탭 (선택적 카드)

struct CharacterVoiceTab: View {
    @Bindable var store: PageStore

    var body: some View {
        let l10n = Localizer.shared
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                if store.content.profile?.voice == nil {
                    // 선택적 기능 — 명시적으로 추가해야 생긴다
                    VStack(spacing: DesignTokens.Spacing.s) {
                        Image(systemName: "waveform")
                            .font(.system(size: 30))
                            .foregroundStyle(.tertiary)
                        Text(l10n.t(.aiCompose) + " ← " + l10n.t(.voiceTab))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Button {
                            store.updateProfile { $0.voice = CharacterVoice() }
                        } label: {
                            Label(l10n.t(.addVoiceCard), systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 70)
                } else {
                    voiceEditor(l10n)
                }
            }
            .padding(DesignTokens.Spacing.l)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
            .modifier(ReadOnlyContentLock())
        }
    }

    @ViewBuilder
    private func voiceEditor(_ l10n: Localizer) -> some View {
        let samples = store.content.profile?.voice?.samples ?? []
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            LabeledContent(l10n.t(.voiceTone)) {
                TextField("", text: voiceBinding(\.tone), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }
            LabeledContent(l10n.t(.voiceTaboo)) {
                TextField("", text: voiceBinding(\.taboo))
                    .textFieldStyle(.roundedBorder)
            }

            // 말투 카드 (3c) — 카드에 마우스를 올리면 예시 대사가 타자기로 재생된다.
            // '보이스 카드 = AI 말투 주입 소스'라는 정체성을 눈으로 보여주는 프리뷰.
            let playableSamples = samples.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if !playableSamples.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                    ForEach(Array(playableSamples.enumerated()), id: \.offset) { _, sample in
                        VoiceSampleCard(text: sample)
                    }
                }
            }

            Text(l10n.t(.voiceSamples))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(samples.enumerated()), id: \.offset) { index, _ in
                HStack {
                    TextField("", text: sampleBinding(index))
                        .textFieldStyle(.roundedBorder)
                    Button {
                        store.updateProfile { profile in
                            guard profile.voice?.samples.indices.contains(index) == true else { return }
                            profile.voice?.samples.remove(at: index)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                store.updateProfile { $0.voice?.samples.append("") }
            } label: {
                Label(l10n.t(.addSample), systemImage: "plus")
                    .font(.callout)
            }
            .buttonStyle(.borderless)

            Divider()
            Button(role: .destructive) {
                store.updateProfile { $0.voice = nil }
            } label: {
                Label(l10n.t(.delete), systemImage: "trash")
            }
            Text("보이스 카드는 AI 자동작성 시 캐릭터 말투 유지에 사용됩니다.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// 보이스 샘플 카드 (3c) — 흰 카드 + 버밀리온 좌측 보더 + 세리프 이탤릭 인용.
    /// 마우스를 올리면 대사가 타자기 리빌로 재생돼 '말투가 재생되는' 카드가 된다.
    private struct VoiceSampleCard: View {
        let text: String

        @State private var hovering = false
        /// 리빌 재시작 트리거 — 호버 진입마다 갱신돼 TypewriterText가 처음부터 다시 새긴다.
        @State private var playID = 0

        var body: some View {
            Group {
                if hovering {
                    TypewriterText(
                        "“\(text)”",
                        font: DSFonts.font(size: 13.5, family: .serif).italic(),
                        color: SonnetPalette.inkSoft
                    )
                    .id(playID)
                } else {
                    Text("“\(text)”")
                        .font(DSFonts.font(size: 13.5, family: .serif).italic())
                        .foregroundStyle(SonnetPalette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
                    .fill(SonnetPalette.surface)
            )
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(
                    topLeadingRadius: DesignTokens.Radius.medium,
                    bottomLeadingRadius: DesignTokens.Radius.medium
                )
                .fill(SonnetPalette.accent)
                .frame(width: 3)
            }
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
                    .strokeBorder(SonnetPalette.ink.opacity(0.09), lineWidth: 1)
            )
            .onHover { inside in
                if inside, !hovering { playID += 1 }
                hovering = inside
            }
        }
    }

    private func voiceBinding(_ keyPath: WritableKeyPath<CharacterVoice, String>) -> Binding<String> {
        Binding(
            get: { store.content.profile?.voice?[keyPath: keyPath] ?? "" },
            set: { newValue in
                store.updateProfile { profile in
                    var voice = profile.voice ?? CharacterVoice()
                    voice[keyPath: keyPath] = newValue
                    profile.voice = voice
                }
            }
        )
    }

    private func sampleBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                let samples = store.content.profile?.voice?.samples ?? []
                return samples.indices.contains(index) ? samples[index] : ""
            },
            set: { newValue in
                store.updateProfile { profile in
                    guard var voice = profile.voice, voice.samples.indices.contains(index) else { return }
                    voice.samples[index] = newValue
                    profile.voice = voice
                }
            }
        )
    }
}

// MARK: - 프로필 이미지 편집 패널 (팝업, 빠른 메뉴 대체)

struct ProfileImagePanel: View {
    @Bindable var store: PageStore

    @State private var offsetX: Double = 0
    @State private var offsetY: Double = 0
    @State private var zoom: Double = 1
    @Environment(\.dismiss) private var dismiss

    private let diameter: CGFloat = 200

    private let symbols = [
        "person.fill", "theatermasks.fill", "crown.fill", "flame.fill", "leaf.fill",
        "moon.stars.fill", "bolt.fill", "heart.fill", "eye.fill", "pawprint.fill",
    ]
    private let palette = ["#B23A21", "#3E5C50", "#8A6D2F", "#9E5A3C", "#5F6B7C", "#191713"]

    var body: some View {
        let l10n = Localizer.shared
        let profile = store.content.profile ?? CharacterProfile()
        VStack(spacing: DesignTokens.Spacing.m) {
            Text(l10n.t(.editProfileImage))
                .font(.headline)

            // 미리보기 + 크롭 (드래그 팬 / 슬라이더 줌)
            if let path = profile.imageResourcePath,
               let url = store.resourceResolver?(path),
               let image = ImageThumbnailCache.thumbnail(for: url, maxPointSize: 600) {
                CircularCropEditor(
                    image: image,
                    zoom: $zoom,
                    offsetX: $offsetX,
                    offsetY: $offsetY,
                    diameter: diameter
                ) { commitCrop() }
            } else {
                CharacterAvatarView(store: store, profile: profile, size: diameter)
            }

            // 이미지 선택 / 아이콘 대체
            HStack(spacing: DesignTokens.Spacing.s) {
                Button {
                    pickImage()
                } label: {
                    Label(l10n.t(.chooseImage), systemImage: "photo.badge.plus")
                }
                if profile.imageResourcePath != nil {
                    Button {
                        store.updateProfile { $0.imageResourcePath = nil }
                    } label: {
                        Label(l10n.t(.showAsIcon), systemImage: "person.crop.square")
                    }
                }
            }

            // 아이콘 (이미지 없을 때 대체)
            if profile.imageResourcePath == nil {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 5), count: 5), spacing: 5) {
                    ForEach(symbols, id: \.self) { symbol in
                        Button {
                            store.updateProfile { $0.symbolName = symbol }
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 13))
                                .foregroundStyle(profile.symbolName == symbol ? Color(hex: profile.accentHex) : .secondary)
                                .frame(width: 30, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(profile.symbolName == symbol ? Color(hex: profile.accentHex).opacity(0.16) : .clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // 강조색
            HStack(spacing: 6) {
                ForEach(palette, id: \.self) { hex in
                    Button {
                        store.updateProfile { $0.accentHex = hex }
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle().strokeBorder(
                                    profile.accentHex == hex ? Color.primary : .clear, lineWidth: 2
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Spacer()
                Button(l10n.t(.done)) { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(DesignTokens.Spacing.l)
        .frame(width: 340)
        .onAppear {
            let profile = store.content.profile ?? CharacterProfile()
            zoom = profile.cropZoom ?? 1
            offsetX = profile.cropOffsetX ?? 0
            offsetY = profile.cropOffsetY ?? 0
        }
    }

    private func commitCrop() {
        store.updateProfile {
            $0.cropOffsetX = offsetX
            $0.cropOffsetY = offsetY
            $0.cropZoom = zoom
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let relative = store.resourceImporter?(url)
        else { return }
        store.updateProfile {
            $0.imageResourcePath = relative
            $0.cropOffsetX = nil
            $0.cropOffsetY = nil
            $0.cropZoom = nil
        }
        offsetX = 0
        offsetY = 0
        zoom = 1
    }
}

/// 읽기 전용 모드에서 탭의 편집 표면을 잠근다 — 스크롤 자체는 부모 ScrollView가
/// 히트테스트 가능한 상태로 남아 그대로 동작한다.
private struct ReadOnlyContentLock: ViewModifier {
    @Environment(\.readOnlyMode) private var readOnlyMode

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(readOnlyMode?.wrappedValue != true)
            .opacity(readOnlyMode?.wrappedValue == true ? 0.92 : 1)
    }
}
