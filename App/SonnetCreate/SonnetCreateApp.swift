import AppCore
import AppKit
import DesignSystem
import SettingsKit
import SwiftUI

@main
struct SonnetCreateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    init() {
        DSFonts.registerBundledFonts()
    }

    /// 전체 크기 배율 → 시스템 다이나믹 타입 크기 (UI 크롬의 시스템 폰트 스케일링)
    private static func typeSize(for scale: Double) -> DynamicTypeSize {
        switch scale {
        case ..<0.97: .medium
        case ..<1.05: .large
        case ..<1.15: .xLarge
        case ..<1.25: .xxLarge
        default: .xxxLarge
        }
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(appState)
                .environment(\.renderQuality, appState.governor.effective)
                // 전체 크기(uiScale)는 폰트 배율과 시스템 타입 크기에 합성된다
                .environment(\.contentFontScale, appState.settings.applied.fontScale * appState.settings.applied.uiScale)
                .environment(\.contentLineSpacing, appState.settings.applied.lineSpacingScale)
                .dynamicTypeSize(Self.typeSize(for: appState.settings.applied.uiScale))
                .environment(\.contentFontFamily, appState.settings.applied.fontFamily)
                .environment(\.contentBlockSpacing, appState.settings.applied.blockSpacing)
                .environment(\.dialogueDisplayStyle, appState.settings.applied.dialogueDisplayRaw)
                .environment(\.dialogueAvatarSize, appState.settings.applied.dialogueAvatarSize)
                .environment(\.interfaceTheme, appState.settings.applied.interfaceTheme)
                .environment(\.resolvedAccent, appState.resolvedAccent)
                .environment(\.liquidGlassDisabled, appState.settings.applied.disableLiquidGlass)
                .font(DSFonts.font(size: 13, family: appState.settings.applied.fontFamily))
                .tint(appState.resolvedAccent)
                .preferredColorScheme(appState.settings.applied.themeMode.colorScheme)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    appDelegate.appState = appState
                    appState.touchBar.setEnabled(appState.settings.applied.touchBarEnabled)
                    Self.updateDockIcon(for: appState.settings.applied.interfaceTheme)
                }
                .onChange(of: appState.settings.applied.interfaceTheme) { _, newTheme in
                    Self.updateDockIcon(for: newTheme)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button(Localizer.shared.t(.home)) { appState.selectOrOpenHome() }
                    .keyboardShortcut("t", modifiers: .command)
                Button(Localizer.shared.t(.archive)) { appState.openArchiveTab() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                Divider()
                Button(Localizer.shared.t(.close)) { appState.closeSelectedTab() }
                    .keyboardShortcut("w", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button(Localizer.shared.t(.save)) { appState.saveSelectedDocument() }
                    .keyboardShortcut("s", modifiers: .command)
            }
            CommandMenu(Localizer.shared.t(.documents)) {
                ForEach(1...9, id: \.self) { number in
                    let index = number - 1
                    Button(
                        appState.tabs.indices.contains(index)
                            ? appState.tabTitle(for: appState.tabs[index])
                            : "—"
                    ) {
                        appState.selectTab(at: index)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                    .disabled(!appState.tabs.indices.contains(index))
                }
            }
        }

        Settings {
            SettingsRootView(
                store: appState.settings,
                backupTimelineView: AnyView(
                    BackupTimelineView()
                        .environment(appState)
                )
            )
            .environment(\.interfaceTheme, appState.settings.applied.interfaceTheme)
            .environment(\.resolvedAccent, appState.resolvedAccent)
            .environment(\.liquidGlassDisabled, appState.settings.applied.disableLiquidGlass)
            .tint(appState.resolvedAccent)
            .preferredColorScheme(appState.settings.applied.themeMode.colorScheme)
        }
    }

    /// 실행 중인 앱의 Dock 아이콘을 현재 테마에 맞춰 갱신한다.
    /// Sonnet은 번들 기본 아이콘이므로 nil을 대입해 시스템이 되돌리게 한다.
    private static func updateDockIcon(for theme: InterfaceTheme) {
        let imageName: String? = switch theme {
        case .sonnet: nil
        case .pilgrimage: "BrandMark-Pilgrimage"
        case .system: "BrandMark-System"
        }
        NSApp.applicationIconImage = imageName.flatMap { NSImage(named: $0) }
    }
}

/// 종료 시 미저장 플러시 + 프로젝트 자동 백업.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            appState?.handleTermination()
        }
    }
}
