import AppCore
import AppKit
import DesignSystem
import SwiftUI

/// 탭형 설정창 (기본·테마·텍스트·베타). 변경은 draft에 쌓이고 저장 버튼으로 반영된다.
public struct SettingsRootView: View {
    @Bindable var store: SettingsStore
    /// 백업 타임라인 등 앱 수준 액션 (기본 탭에 노출)
    let backupTimelineView: AnyView?

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
                Tab(l10n.t(.settingsTheme), systemImage: "paintpalette") {
                    themeTab(l10n)
                }
                Tab(l10n.t(.settingsText), systemImage: "textformat") {
                    textTab(l10n)
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
        .frame(width: 520, height: 480)
        .onAppear { store.refreshAPIKeyDraft() }
    }

    // MARK: 기본

    private func generalTab(_ l10n: Localizer) -> some View {
        Form {
            Picker(l10n.t(.language), selection: $store.draft.language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }

            TextField(l10n.t(.profile), text: $store.draft.authorName)

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

            Picker(l10n.t(.inspectorPosition), selection: $store.draft.scenarioInspectorOnRight) {
                Text(l10n.t(.positionLeft)).tag(false)
                Text(l10n.t(.positionRight)).tag(true)
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

    // MARK: 테마

    private func themeTab(_ l10n: Localizer) -> some View {
        Form {
            Picker(l10n.t(.interfaceStyle), selection: $store.draft.interfaceTheme) {
                Text(l10n.t(.themeSonnet)).tag(InterfaceTheme.sonnet)
                Text(l10n.t(.themeSystem)).tag(InterfaceTheme.system)
            }
            .pickerStyle(.segmented)

            LabeledContent(l10n.t(.uiScale)) {
                Slider(value: $store.draft.uiScale, in: 0.9...1.3, step: 0.05)
            }

            Picker(l10n.t(.tabStyle), selection: $store.draft.tabStyleRaw) {
                Text(l10n.t(.tabStyleCapsule)).tag("capsule")
                Text(l10n.t(.tabStyleChrome)).tag("chrome")
            }
            .pickerStyle(.segmented)

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

    // MARK: - Touch Bar 프리뷰

    private var customAccentBinding: Binding<Color> {
        Binding(
            get: {
                if case .custom(let hex) = store.draft.accent { return Color(hex: hex) }
                return store.draft.accent.color
            },
            set: { store.draft.accent = .custom(hex: $0.hexString) }
        )
    }

    // MARK: 텍스트

    private func textTab(_ l10n: Localizer) -> some View {
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
            LabeledContent(l10n.t(.blockSpacing)) {
                Slider(value: $store.draft.blockSpacing, in: 2...16, step: 1)
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
            // esc 영역
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
