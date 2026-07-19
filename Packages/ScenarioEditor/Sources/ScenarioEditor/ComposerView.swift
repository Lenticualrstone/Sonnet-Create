import AppCore
import DesignSystem
import DocumentKit
import SwiftUI

/// 하단 중앙 Liquid Glass 입력기.
/// 대사↔지침 모드 토글, 캐릭터 선택(⌘ 다중선택), 라이트=블랙/다크=화이트 전송 버튼.
struct ComposerView: View {
    @Bindable var store: ScenarioStore

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.renderQuality) private var quality
    @Environment(\.resolvedAccent) private var accent
    @FocusState private var focused: Bool

    var body: some View {
        let l10n = Localizer.shared
        VStack(spacing: 6) {
            if store.editingBlockID != nil {
                editingBanner(l10n)
            }
            HStack(spacing: DesignTokens.Spacing.s) {
                modeTabs(l10n)

                if store.composerMode == .line {
                    speakerSelector
                }

                TextField(
                    placeholder(l10n),
                    text: $store.composerText,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($focused)
                .onKeyPress(.return, phases: .down) { press in
                    // Enter = 전송, ⇧Enter = 줄바꿈
                    if press.modifiers.contains(.shift) { return .ignored }
                    submit()
                    return .handled
                }
                // Tab — 모드 순환 (2a: 하이라이트가 glass pop 곡선으로 따라온다)
                .onKeyPress(.tab, phases: .down) { _ in
                    cycleMode()
                    return .handled
                }

                sendButton
            }
            .padding(.horizontal, DesignTokens.Spacing.m)
            .padding(.vertical, 10)
            .glassSurface(cornerRadius: DesignTokens.Radius.large, interactive: true, quality: quality)
            .modifier(ShakeEffect(animatableData: store.shakeTrigger))
            .animation(DesignTokens.Motion.snappy, value: store.shakeTrigger)
        }
        .frame(maxWidth: 640)
    }

    private func submit() {
        if store.submitComposer() {
            focused = true
        }
    }

    // MARK: 모드 탭 (2a — 대사/지침/장면, Tab 순환, 슬라이딩 하이라이트)

    @Namespace private var modeHighlight

    private func placeholder(_ l10n: Localizer) -> String {
        switch store.composerMode {
        case .line: l10n.t(.composerPlaceholderLine)
        case .instruction: l10n.t(.composerPlaceholderNote)
        case .scene: l10n.t(.composerPlaceholderScene)
        }
    }

    private func cycleMode() {
        let all = ScenarioStore.ComposerMode.allCases
        guard let index = all.firstIndex(of: store.composerMode) else { return }
        withAnimation(DesignTokens.Motion.glassPop) {
            store.composerMode = all[(index + 1) % all.count]
        }
    }

    private func modeLabel(_ mode: ScenarioStore.ComposerMode, _ l10n: Localizer) -> String {
        switch mode {
        case .line: l10n.t(.dialogue)
        case .instruction: l10n.t(.instruction)
        case .scene: l10n.t(.sceneBlock)
        }
    }

    private func modeTabs(_ l10n: Localizer) -> some View {
        HStack(spacing: 2) {
            ForEach(ScenarioStore.ComposerMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(DesignTokens.Motion.glassPop) { store.composerMode = mode }
                } label: {
                    Text(modeLabel(mode, l10n))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(store.composerMode == mode ? accent : Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            if store.composerMode == mode {
                                Capsule()
                                    .fill(SonnetPalette.accentTint)
                                    .matchedGeometryEffect(id: "composerMode", in: modeHighlight)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .help(l10n.t(.dialogue) + " / " + l10n.t(.instruction) + " / " + l10n.t(.sceneBlock) + " — Tab")
    }

    // MARK: 캐릭터 선택

    @State private var showSpeakerMenu = false

    private var speakerSelector: some View {
        let selected = store.content.cast.filter { store.selectedSpeakerIDs.contains($0.id) }
        return Button {
            showSpeakerMenu.toggle()
        } label: {
            SpeakerCluster(speakers: selected)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showSpeakerMenu, arrowEdge: .top) {
            speakerMenu
        }
        .help(Localizer.shared.t(.characters))
    }

    private var speakerMenu: some View {
        let l10n = Localizer.shared
        return VStack(alignment: .leading, spacing: 2) {
            if store.content.cast.isEmpty {
                Text(l10n.t(.addCharacter))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            ForEach(store.content.cast) { member in
                Button {
                    let exclusive = !NSEvent.modifierFlags.contains(.command)
                    store.toggleSpeaker(member.id, exclusive: exclusive)
                    if exclusive { showSpeakerMenu = false }
                } label: {
                    HStack(spacing: 8) {
                        CastAvatar(member: member, size: 22)
                        Text(member.name).font(.callout)
                        Spacer()
                        if store.selectedSpeakerIDs.contains(member.id) {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(accent)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("⌘ + 클릭: 다중 선택")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.top, 4)
        }
        .padding(6)
        .frame(minWidth: 180)
    }

    // MARK: 전송 버튼

    private var sendButton: some View {
        let empty = store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button(action: submit) {
            Image(systemName: store.editingBlockID != nil ? "checkmark" : "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(accent.opacity(empty ? 0.3 : 1)))
        }
        .buttonStyle(.plain)
        .animation(DesignTokens.Motion.snappy, value: empty)
    }

    // MARK: 수정 모드 배너

    private func editingBanner(_ l10n: Localizer) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil")
                .font(.caption2)
            Text(l10n.t(.editContent))
                .font(.caption)
            Spacer()
            Button {
                store.cancelEditing()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .glassCapsule(quality: quality)
        .frame(maxWidth: 320)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
