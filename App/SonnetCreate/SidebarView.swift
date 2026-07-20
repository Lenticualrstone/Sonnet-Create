import AppCore
import AppKit
import DesignSystem
import DocumentKit
import FileManagerKit
import SwiftUI

/// 사이드바 풀폭 버튼(프로젝트 파일 인스펙터 등) — 호버 하이라이트 + 눌림 스케일.
struct SidebarLongButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .fill(fill(pressed: configuration.isPressed))
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .onHover { hovering = $0 }
            .animation(DesignTokens.Motion.glassPop, value: hovering)
            .animation(DesignTokens.Motion.press, value: configuration.isPressed)
    }

    private func fill(pressed: Bool) -> Color {
        if pressed { return SonnetPalette.sunken }
        if hovering { return SonnetPalette.surface }
        return .clear
    }
}

// MARK: - 좌측 아이콘 레일 (1b · 11a)
// 72px 고정 폭 — 홈 · 아카이브 · 검색(⌘K) · Sonnet AI · 수신함, 하단에 설정 · 프로필.
// 통합 타이틀바(11a) 아래에서 시작한다.

struct RailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.resolvedAccent) private var accent

    @State private var showInbox = false

    var body: some View {
        let l10n = Localizer.shared
        VStack(spacing: 8) {
            RailButton(
                symbol: "house",
                help: l10n.t(.home),
                isActive: isSelected(.home)
            ) {
                app.selectOrOpenHome()
            }

            // 프로젝트 — 카드 그리드 화면 (프로젝트가 1급 시민)
            RailButton(
                symbol: "folder",
                help: l10n.t(.project),
                isActive: isSelected(.projects)
            ) {
                app.openProjectsTab()
            }

            RailButton(
                symbol: "archivebox",
                help: l10n.t(.archive),
                isActive: isSelected(.archive)
            ) {
                app.openArchiveTab()
            }

            RailButton(
                symbol: "magnifyingglass",
                help: l10n.t(.searchPlaceholder) + " (⌘K)",
                isActive: app.showCommandPalette
            ) {
                withAnimation(DesignTokens.Motion.glassPop) { app.showCommandPalette.toggle() }
            }

            // AI가 열려 있으면 닫기 형태로 — 같은 버튼이 여닫이임을 명확히 (3단계 2)
            let aiOpen = isSelected(.aiChat) || app.showFloatingChat
            RailButton(
                symbol: aiOpen ? "xmark" : "sparkle",
                help: aiOpen
                    ? l10n.t(.sonnetAI) + " — " + l10n.t(.close) + " (⇧⌘A)"
                    : l10n.t(.sonnetAI) + " (⇧⌘A)",
                isActive: aiOpen
            ) {
                app.toggleAgentSurface()
            }
            .animation(DesignTokens.Motion.snappy, value: aiOpen)

            RailButton(
                symbol: "tray",
                help: l10n.t(.inbox),
                isActive: showInbox,
                badgeCount: 0
            ) {
                // 레일 아이콘 위 popover — 앵커 확정 후 열기 (macOS 26 크래시 방지)
                DispatchQueue.main.async { showInbox = true }
            }
            .popover(isPresented: $showInbox, arrowEdge: .trailing) {
                InboxPopover()
                    .environment(app)
            }

            Spacer(minLength: 0)

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(SonnetPalette.inkMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(RailHoverButtonStyle())
            .help(l10n.t(.settings))

            profileButton
        }
        .padding(.top, 14)
        .padding(.bottom, 20)
        .frame(width: 72)
        .frame(maxHeight: .infinity)
        .background(railBackground)
    }

    /// 풀 글래스 모드(4c)에서는 레일도 유리 위에 뜬다 — 포인트 모드는 평면 캔버스.
    @ViewBuilder
    private var railBackground: some View {
        let s = app.settings.applied
        if s.glassModeRaw == "full", !s.disableLiquidGlass {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                SonnetPalette.canvas.opacity(0.15 + 0.55 * s.glassIntensity)
            }
        } else {
            SonnetPalette.canvas
        }
    }

    private func isSelected(_ content: TabContent) -> Bool {
        app.selectedTab?.content == content
    }

    /// 프로필 아바타 — 사진이 있으면 크롭 이미지, 없으면 이름 이니셜 (파인 원판).
    private var profileButton: some View {
        Button {
            app.openProfileTab()
        } label: {
            avatar
                .frame(width: 44, height: 44)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(RailHoverButtonStyle())
        .help(Localizer.shared.t(.profile))
    }

    @ViewBuilder
    private var avatar: some View {
        let s = app.settings.applied
        if !s.authorPhotoPath.isEmpty,
           let image = ImageThumbnailCache.thumbnail(for: URL(fileURLWithPath: s.authorPhotoPath), maxPointSize: 34) {
            CroppedCircleImage(
                image: image,
                zoom: s.authorCropZoom,
                offsetX: s.authorCropOffsetX,
                offsetY: s.authorCropOffsetY,
                size: 34
            )
        } else {
            ZStack {
                Circle().fill(SonnetPalette.pine)
                Text(authorInitial)
                    .font(DSFonts.font(size: 13, weight: .semibold, family: .pretendard))
                    .foregroundStyle(Color(hex: "#F6F4EF"))
            }
            .frame(width: 34, height: 34)
        }
    }

    private var authorInitial: String {
        let name = app.settings.applied.authorName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "✎" : String(name.prefix(1))
    }
}

/// 레일 아이콘 버튼 — 44×44 · 활성 시 인장 틴트 배경 + 버밀리온.
struct RailButton: View {
    let symbol: String
    let help: String
    var isActive: Bool
    var badgeCount: Int = 0
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.resolvedAccent) private var accent

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(isActive ? accent : (hovering ? SonnetPalette.ink : SonnetPalette.inkMuted))
                    .frame(width: 44, height: 44)
                if badgeCount > 0 {
                    Text("\(min(badgeCount, 99))")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(accent))
                        .offset(x: 2, y: 4)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isActive ? SonnetPalette.accentTint : (hovering ? SonnetPalette.ink.opacity(0.06) : .clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressBounceButtonStyle())
        .onHover { hovering = $0 }
        .animation(DesignTokens.Motion.glassPop, value: hovering)
        .animation(DesignTokens.Motion.glassPop, value: isActive)
        .help(help)
    }
}

/// SettingsLink처럼 label을 직접 받는 자리의 호버 배경 스타일.
private struct RailHoverButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hovering ? SonnetPalette.ink.opacity(0.06) : .clear)
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .onHover { hovering = $0 }
            .animation(DesignTokens.Motion.glassPop, value: hovering)
            .animation(DesignTokens.Motion.press, value: configuration.isPressed)
    }
}

/// 수신함 popover — 가져오기/백업/복원 등 시스템 이벤트 목록.
struct InboxPopover: View {
    @Environment(AppState.self) private var app
    @Environment(\.resolvedAccent) private var accent

    var body: some View {
        let l10n = Localizer.shared
        VStack(alignment: .leading, spacing: 0) {
            Text(l10n.t(.inbox))
                .font(DSType.subtitle())
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
            Divider().opacity(0.4)
            if app.inbox.isEmpty {
                VStack(spacing: DesignTokens.Spacing.s) {
                    Image(systemName: "tray")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text(l10n.t(.noRecents))
                        .font(DSType.caption())
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(app.inbox) { event in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: event.symbol)
                                    .font(.caption)
                                    .foregroundStyle(accent)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(event.message)
                                        .font(DSType.caption())
                                        .lineLimit(2)
                                    Text(event.date, format: .dateTime.month().day().hour().minute())
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 280)
        .background(SonnetPalette.surface)
    }
}

/// 사이드바 공용 이름 변경 팝오버 (프로젝트 파일 인스펙터와 공유).
struct SidebarRenamePopover: View {
    @Binding var draft: String
    let onCommit: () -> Void

    var body: some View {
        let l10n = Localizer.shared
        HStack(spacing: 6) {
            TextField(l10n.t(.rename), text: $draft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 190)
                .onSubmit(onCommit)
            Button(l10n.t(.done), action: onCommit)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(10)
    }
}

/// 문서 행 (프로젝트 파일 인스펙터가 사용).
struct SidebarDocumentRow: View {
    @Environment(AppState.self) private var app
    @Environment(\.resolvedAccent) private var accent
    let item: DocumentListItem

    @State private var hovering = false
    @State private var renaming = false
    @State private var draftTitle = ""

    /// 현재 선택된 탭이 이 문서인지 (열려 있음 강조)
    private var isActive: Bool {
        if case .document(let docID) = app.selectedTab?.content {
            return docID == item.id
        }
        return false
    }

    private var fileType: DSFileType {
        if item.envelope.isCharacterPage { return .character }
        switch item.envelope.kind {
        case .scenario: return .scenario
        case .mindmap: return .mindmap
        case .page: return .page
        }
    }

    var body: some View {
        Button {
            app.openDocument(item)
        } label: {
            HStack(spacing: 7) {
                FileTypeIcon(fileType, size: 13)
                Text(item.envelope.title.isEmpty ? Localizer.shared.t(.untitled) : item.envelope.title)
                    .font(DSFonts.font(size: 13, weight: isActive ? .semibold : .regular, family: .pretendard))
                    .lineLimit(1)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isActive
                            ? SonnetPalette.accentTint
                            : (hovering ? SonnetPalette.ink.opacity(0.06) : .clear)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(DesignTokens.Motion.glassPop, value: hovering)
        .contextMenu {
            let l10n = Localizer.shared
            Button(l10n.t(.open)) { app.openDocument(item) }
            Button(l10n.t(.rename)) {
                draftTitle = item.envelope.title
                DispatchQueue.main.async { renaming = true }
            }
            Button(l10n.t(.duplicate)) { _ = app.workspace.duplicateDocument(item) }
            Divider()
            Button(l10n.t(.hide)) { app.workspace.setHidden(item, hidden: true) }
            Button(l10n.t(.moveToTrash), role: .destructive) { app.requestTrash(item) }
        }
        .popover(isPresented: $renaming, arrowEdge: .trailing) {
            SidebarRenamePopover(draft: $draftTitle) {
                app.renameDocument(item, to: draftTitle)
                renaming = false
            }
        }
    }
}
