import AppCore
import AppKit
import DesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// 탭형 설정창 — 일반 · 모양 · 에디터 · 베타. 변경은 draft에 쌓이고 저장 버튼으로 반영된다.
public struct SettingsRootView: View {
    @Bindable var store: SettingsStore
    /// 백업 타임라인 등 앱 수준 액션 (일반 탭에 노출)
    let backupTimelineView: AnyView?
    @Environment(\.resolvedAccent) private var accent
    @State private var showCropEditor = false

    public init(store: SettingsStore, backupTimelineView: AnyView? = nil) {
        self.store = store
        self.backupTimelineView = backupTimelineView
    }

    public var body: some View {
        let l10n = Localizer.shared
        VStack(spacing: 0) {
            TabView {
                Tab(l10n.t(.settingsGeneral), systemImage: "gearshape") {
                    generalTab(l10n)
                }
                Tab(l10n.t(.settingsAppearance), systemImage: "paintpalette") {
                    appearanceTab(l10n)
                }
                Tab(l10n.t(.settingsEditor), systemImage: "square.and.pencil") {
                    editorTab(l10n)
                }
                Tab(l10n.t(.settingsBeta), systemImage: "flask") {
                    betaTab(l10n)
                }
            }

            Divider()
            HStack {
                if store.hasChanges {
                    Text("•")
                        .foregroundStyle(Color(hex: "#FF5B5B"))
                }
                Spacer()
                Button(l10n.t(.cancel)) { store.revert() }
                    .disabled(!store.hasChanges)
                Button(l10n.t(.save)) { store.save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.hasChanges)
                    .keyboardShortcut("s", modifiers: .command)
            }
            .padding(DesignTokens.Spacing.m)
        }
        .frame(width: 540, height: 520)
        .onAppear { store.refreshAPIKeyDraft() }
    }

    // MARK: 일반 — 언어/프로필/경로/파일 동작/백업

    private func generalTab(_ l10n: Localizer) -> some View {
        Form {
            Picker(l10n.t(.language), selection: $store.draft.language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }

            Section(l10n.t(.profile)) {
                HStack(spacing: DesignTokens.Spacing.m) {
                    Button {
                        pickPhoto()
                    } label: {
                        profileAvatar
                    }
                    .buttonStyle(.plain)
                    .help(l10n.t(.choosePhoto))

                    VStack(alignment: .leading, spacing: 6) {
                        TextField(l10n.t(.profile), text: $store.draft.authorName)
                        TextField(l10n.t(.aboutMe), text: $store.draft.authorBio, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }
                if !store.draft.authorPhotoPath.isEmpty {
                    HStack(spacing: DesignTokens.Spacing.s) {
                        Button(l10n.t(.adjustCrop)) {
                            showCropEditor = true
                        }
                        .controlSize(.small)
                        Button(l10n.t(.removePhoto), role: .destructive) {
                            store.draft.authorPhotoPath = ""
                            resetCrop()
                        }
                        .controlSize(.small)
                    }
                }
            }

            LabeledContent(l10n.t(.workspacePath)) {
                HStack(spacing: 6) {
                    Text(store.draft.workspacePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(l10n.t(.choose)) { chooseWorkspace() }
                        .controlSize(.small)
                }
            }

            Picker(l10n.t(.openBehavior), selection: $store.draft.openOnSingleClick) {
                Text(l10n.t(.singleClick)).tag(true)
                Text(l10n.t(.doubleClick)).tag(false)
            }
            .pickerStyle(.segmented)

            Toggle(l10n.t(.autosave), isOn: $store.draft.autosave)
            Toggle(l10n.t(.backups) + " — " + l10n.t(.backupNow), isOn: $store.draft.backupOnQuit)

            if let backupTimelineView {
                Section(l10n.t(.backupTimeline)) {
                    backupTimelineView
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showCropEditor) {
            VStack(spacing: DesignTokens.Spacing.m) {
                Text(l10n.t(.adjustCrop))
                    .font(.headline)
                if let image = ImageThumbnailCache.thumbnail(
                    for: URL(fileURLWithPath: store.draft.authorPhotoPath), maxPointSize: 600
                ) {
                    CircularCropEditor(
                        image: image,
                        zoom: $store.draft.authorCropZoom,
                        offsetX: $store.draft.authorCropOffsetX,
                        offsetY: $store.draft.authorCropOffsetY
                    )
                }
                HStack {
                    Spacer()
                    Button(l10n.t(.done)) { showCropEditor = false }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
            .padding(DesignTokens.Spacing.l)
            .frame(width: 300)
        }
    }

    private func resetCrop() {
        store.draft.authorCropZoom = 1
        store.draft.authorCropOffsetX = 0
        store.draft.authorCropOffsetY = 0
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if !store.draft.authorPhotoPath.isEmpty,
           let image = ImageThumbnailCache.thumbnail(for: URL(fileURLWithPath: store.draft.authorPhotoPath), maxPointSize: 56) {
            CroppedCircleImage(
                image: image,
                zoom: store.draft.authorCropZoom,
                offsetX: store.draft.authorCropOffsetX,
                offsetY: store.draft.authorCropOffsetY,
                size: 56
            )
        } else {
            ZStack {
                Circle().fill(accent.opacity(0.16))
                Image(systemName: "person.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 56, height: 56)
        }
    }

    /// 프로필 사진은 문서 번들과 무관한 앱 전역 파일이라 Application Support에 고정 저장한다.
    private func pickPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let supportDir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return }
        let target = supportDir
            .appendingPathComponent("SonnetCreate", isDirectory: true)
            .appendingPathComponent("profile-photo.\(url.pathExtension)")
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        do {
            try FileManager.default.copyItem(at: url, to: target)
            store.draft.authorPhotoPath = target.path
            resetCrop()
        } catch {}
    }

    private func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            store.draft.workspacePath = url.path
        }
    }

    // MARK: 모양 — 테마/크기/탭/품질

    private func appearanceTab(_ l10n: Localizer) -> some View {
        Form {
            LabeledContent(l10n.t(.interfaceStyle)) {
                HStack(spacing: 10) {
                    themeSwatch(.sonnet, label: l10n.t(.themeSonnet))
                    themeSwatch(.pilgrimage, label: l10n.t(.themePilgrimage))
                    themeSwatch(.system, label: l10n.t(.themeSystem))
                }
            }

            Picker(l10n.t(.themeMode), selection: $store.draft.themeMode) {
                Text(l10n.t(.themeSystem)).tag(ThemeMode.system)
                Text(l10n.t(.themeLight)).tag(ThemeMode.light)
                Text(l10n.t(.themeDark)).tag(ThemeMode.dark)
            }
            .pickerStyle(.segmented)

            LabeledContent(l10n.t(.accentColor)) {
                HStack(spacing: 8) {
                    accentSwatch(.system, symbol: "circle.lefthalf.filled")
                    ForEach(Array(AccentChoice.brandCases.enumerated()), id: \.offset) { _, choice in
                        accentSwatch(choice)
                    }
                    ColorPicker("", selection: customAccentBinding, supportsOpacity: false)
                        .labelsHidden()
                        .help(l10n.t(.accentCustom))
                }
            }

            LabeledContent(l10n.t(.uiScale)) {
                Slider(value: $store.draft.uiScale, in: 0.9...1.3, step: 0.05)
            }

            Picker(l10n.t(.tabStyle), selection: $store.draft.tabStyleRaw) {
                Text(l10n.t(.tabStyleChrome)).tag("chrome")
                Text(l10n.t(.tabStyleCapsule)).tag("capsule")
            }
            .pickerStyle(.segmented)

            Picker(l10n.t(.qualityTier), selection: $store.draft.quality) {
                Text(l10n.t(.qualityLow)).tag(RenderQuality.low)
                Text(l10n.t(.qualityStandard)).tag(RenderQuality.standard)
                Text(l10n.t(.qualityHigh)).tag(RenderQuality.high)
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
    }

    private func accentSwatch(_ choice: AccentChoice, symbol: String? = nil) -> some View {
        Button {
            store.draft.accent = choice
        } label: {
            ZStack {
                Circle().fill(choice.color)
                if let symbol {
                    Image(systemName: symbol)
                        .font(.caption2)
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 20, height: 20)
            .overlay(
                Circle().strokeBorder(
                    store.draft.accent == choice ? Color.primary : .clear,
                    lineWidth: 2
                )
            )
        }
        .buttonStyle(.plain)
    }

    private var customAccentBinding: Binding<Color> {
        Binding(
            get: {
                if case .custom(let hex) = store.draft.accent { return Color(hex: hex) }
                return store.draft.accent.color
            },
            set: { store.draft.accent = .custom(hex: $0.hexString) }
        )
    }

    // MARK: 테마 스와치 (메인/강조색 대각선 프리뷰)

    private func themeSwatch(_ theme: InterfaceTheme, label: String) -> some View {
        let isSelected = store.draft.interfaceTheme == theme
        return Button {
            store.draft.interfaceTheme = theme
        } label: {
            VStack(spacing: 4) {
                ThemeColorTile(style: swatchStyle(for: theme))
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.primary : Color.primary.opacity(0.15),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 테마별 미리보기 색 조합. 브랜드 테마는 메인 캔버스+강조색, 시스템 테마는
    /// 화면 모드(라이트/다크/시스템)에 따라 실제 시스템 색 또는 밝음/어두움 조합을 보여준다.
    private func swatchStyle(for theme: InterfaceTheme) -> ThemeSwatchStyle {
        switch theme {
        case .sonnet:
            return .split(main: SonnetPalette.canvas, accent: swatchAccent(for: theme))
        case .pilgrimage:
            return .split(main: PilgrimagePalette.canvas, accent: swatchAccent(for: theme))
        case .system:
            switch store.draft.themeMode {
            case .light:
                return .split(main: resolvedSystemColor(dark: false), accent: swatchAccent(for: theme))
            case .dark:
                return .split(main: resolvedSystemColor(dark: true), accent: swatchAccent(for: theme))
            case .system:
                // 실제 OS 모드를 알 수 없으니 "적응형"임을 밝음/어두움 조합으로 보여준다.
                return .lightDark
            }
        }
    }

    /// AppState.resolvedAccent와 동일한 규칙 — 강조색을 '시스템'으로 둔 경우에만
    /// 브랜드 테마 고유 액센트를 쓰고, 그 외엔 사용자가 고른 강조색을 그대로 보여준다.
    private func swatchAccent(for theme: InterfaceTheme) -> Color {
        if store.draft.accent == .system, theme.isBranded {
            return theme.accentColor
        }
        return store.draft.accent.color
    }

    /// 화면 모드가 라이트/다크로 고정된 경우, 실제 그 모드에서 보일 시스템 창 배경색을
    /// 강제 해석해 즉시 미리보기에 반영한다 (draft가 아직 저장 전이라 창 자체의 렌더링
    /// appearance는 못 따라오므로).
    private func resolvedSystemColor(dark: Bool) -> Color {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        var resolved = NSColor.windowBackgroundColor
        appearance?.performAsCurrentDrawingAppearance {
            resolved = NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB) ?? resolved
        }
        return Color(nsColor: resolved)
    }

    // MARK: 에디터 — 글꼴/간격/인스펙터

    private func editorTab(_ l10n: Localizer) -> some View {
        Form {
            Picker(l10n.t(.fontLabel), selection: $store.draft.fontFamily) {
                Text(l10n.t(.fontPretendard)).tag(FontFamily.pretendard)
                Text(l10n.t(.fontSystem)).tag(FontFamily.system)
                Text(l10n.t(.fontSerif)).tag(FontFamily.serif)
                Text(l10n.t(.fontMono)).tag(FontFamily.mono)
            }

            LabeledContent(l10n.t(.fontSize)) {
                Slider(value: $store.draft.fontScale, in: 0.8...1.4, step: 0.05)
            }
            LabeledContent(l10n.t(.lineSpacing)) {
                Slider(value: $store.draft.lineSpacingScale, in: 0.8...1.6, step: 0.1)
            }
            Picker(l10n.t(.blockSpacing), selection: $store.draft.blockSpacing) {
                Text(l10n.t(.spacingCompact)).tag(6.0)
                Text(l10n.t(.spacingMedium)).tag(12.0)
                Text(l10n.t(.spacingWide)).tag(20.0)
            }
            .pickerStyle(.segmented)

            Picker(l10n.t(.inspectorPosition), selection: $store.draft.scenarioInspectorOnRight) {
                Text(l10n.t(.positionLeft)).tag(false)
                Text(l10n.t(.positionRight)).tag(true)
            }
            .pickerStyle(.segmented)

            Section(l10n.t(.dialogueDisplayHeader)) {
                Picker(l10n.t(.dialogueDisplayMethod), selection: $store.draft.dialogueDisplayRaw) {
                    Text(l10n.t(.dialogueDisplayBoth)).tag("avatarAndName")
                    Text(l10n.t(.dialogueDisplayAvatarOnly)).tag("avatarOnly")
                    Text(l10n.t(.dialogueDisplayNameOnly)).tag("nameOnly")
                    Text(l10n.t(.dialogueDisplayHidden)).tag("hidden")
                }
                .pickerStyle(.segmented)

                LabeledContent(l10n.t(.dialogueAvatarSize)) {
                    Slider(value: $store.draft.dialogueAvatarSize, in: 20...52, step: 2)
                }
                .disabled(store.draft.dialogueDisplayRaw == "nameOnly" || store.draft.dialogueDisplayRaw == "hidden")
            }

            Section {
                Text("본문 미리보기 — The quick brown fox / 다람쥐 헌 쳇바퀴에 타고파")
                    .font(DSFonts.font(size: 13 * store.draft.fontScale, family: store.draft.fontFamily))
                    .lineSpacing(4 * store.draft.lineSpacingScale)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: 베타

    private func betaTab(_ l10n: Localizer) -> some View {
        Form {
            Toggle(l10n.t(.disableGlass), isOn: $store.draft.disableLiquidGlass)

            Section("Touch Bar") {
                Toggle(l10n.t(.touchBarSupport), isOn: $store.draft.touchBarEnabled)
                if store.draft.touchBarEnabled {
                    TouchBarPreviewView()
                    Text(l10n.t(.touchBarFunctions))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(TouchBarPreviewView.functions, id: \.symbol) { item in
                        Label(l10n.t(item.key), systemImage: item.symbol)
                            .font(.callout)
                    }
                }
            }

            Picker(l10n.t(.aiProvider), selection: $store.draft.aiProviderRaw) {
                Text(l10n.t(.aiProviderMock)).tag("offline")
                Text(l10n.t(.aiProviderApple)).tag("appleOnDevice")
                Text(l10n.t(.aiProviderAnthropic)).tag("anthropic")
            }

            if store.draft.aiProviderRaw == "anthropic" {
                SecureField(l10n.t(.apiKey), text: $store.draftAPIKey)
            }

            Picker(l10n.t(.contextScope), selection: $store.draft.aiContextScope) {
                Text(l10n.t(.ctxDocument)).tag(AIContextScope.document)
                Text(l10n.t(.ctxProject)).tag(AIContextScope.project)
                Text(l10n.t(.ctxWorkspace)).tag(AIContextScope.workspace)
            }

            Section {
                Text("AI 제안은 항상 검토·수정·취소 가능한 형태로 표시됩니다. 컨텍스트는 선택한 범위를 벗어나 전송되지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// 테마 스와치 색 구성 — 메인/강조색 대각선 분할, 또는 (시스템 모드가 불명확할 때) 밝음/어두움 조합.
private enum ThemeSwatchStyle {
    case split(main: Color, accent: Color)
    case lightDark
}

/// 둥근 사각형을 대각선으로 나눠 두 색을 보여주는 테마 미리보기 타일.
private struct ThemeColorTile: View {
    let style: ThemeSwatchStyle

    var body: some View {
        ZStack {
            switch style {
            case .split(let main, let accent):
                DiagonalHalf(upperRight: false).fill(main)
                DiagonalHalf(upperRight: true).fill(accent)
            case .lightDark:
                DiagonalHalf(upperRight: false).fill(Color(white: 0.97))
                DiagonalHalf(upperRight: true).fill(Color(white: 0.15))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// 사각형을 좌상단→우하단 대각선으로 나눈 삼각형 절반.
private struct DiagonalHalf: Shape {
    /// true = 우상단 삼각형, false = 좌하단 삼각형
    let upperRight: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        if upperRight {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}

/// 사이드바 퀵 액션 라이브 프리뷰 — 사이드바 상단에 표시될 실제 모습.
/// Touch Bar 프리뷰 — 활성화 시 실제로 배치될 항목의 시각 모형.
public struct TouchBarPreviewView: View {
    public struct Item {
        public let key: L10nKey
        public let symbol: String
    }

    public static let functions: [Item] = [
        Item(key: .home, symbol: "house"),
        Item(key: .save, symbol: "square.and.arrow.down"),
        Item(key: .newPage, symbol: "doc.badge.plus"),
        Item(key: .aiAgent, symbol: "sparkles"),
        Item(key: .archive, symbol: "archivebox"),
    ]

    public init() {}

    public var body: some View {
        let l10n = Localizer.shared
        HStack(spacing: 8) {
            Text("esc")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.12)))

            Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 18)

            ForEach(Self.functions, id: \.symbol) { item in
                HStack(spacing: 4) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 11))
                    Text(l10n.t(item.key))
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.14)))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black))
        .environment(\.colorScheme, .dark)
    }
}
