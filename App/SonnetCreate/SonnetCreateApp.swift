import AppCore
import AppKit
import DesignSystem
import DocumentKit
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
                .environment(\.pageFocusMode, appState.settings.applied.pageFocusModeEnabled)
                .environment(\.pageTypewriterMode, appState.settings.applied.pageTypewriterEnabled)
                .environment(\.mindmapAutoOpenInspector, appState.settings.applied.mindmapAutoOpenInspector)
                .environment(\.aiSphereStyle, AISphereStyle(rawValue: appState.settings.applied.aiSphereStyleRaw) ?? .particle)
                .environment(\.aiSphereDensity, AISphereDensity(rawValue: appState.settings.applied.aiSphereDensityRaw) ?? .normal)
                .environment(\.interfaceTheme, appState.settings.applied.interfaceTheme)
                .modifier(AdaptiveAccent(base: appState.resolvedAccent))
                .environment(\.liquidGlassDisabled, appState.settings.applied.disableLiquidGlass)
                .font(DSFonts.font(size: 13, family: appState.settings.applied.fontFamily))
                .preferredColorScheme(appState.settings.applied.themeMode.colorScheme)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    appDelegate.appState = appState
                    appState.touchBar.setEnabled(appState.settings.applied.touchBarEnabled)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                // 새 문서 — 현재 컨텍스트(프로젝트 아카이브/프로젝트 문서 탭)의 프로젝트를 따른다
                Button(Localizer.shared.t(.newScenario)) {
                    appState.createAndOpen(kind: .scenario, in: appState.creationTargetProject)
                }
                .keyboardShortcut("n", modifiers: .command)
                Button(Localizer.shared.t(.newPage)) {
                    appState.createAndOpen(kind: .page, in: appState.creationTargetProject)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
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
                ),
                updateSectionView: AnyView(
                    UpdateSettingsSection()
                        .environment(appState)
                ),
                guideProjectSectionView: AnyView(
                    GuideProjectSettingsSection()
                        .environment(appState)
                )
            )
            .environment(\.interfaceTheme, appState.settings.applied.interfaceTheme)
            .modifier(AdaptiveAccent(base: appState.resolvedAccent))
            .environment(\.liquidGlassDisabled, appState.settings.applied.disableLiquidGlass)
            .preferredColorScheme(appState.settings.applied.themeMode.colorScheme)
        }
    }

}

/// 실효 강조색을 화면 모드에 맞춰 주입 — 다크 모드에서는 어두운 강조색(커스텀 네이비 등)이
/// 배경에 묻히므로 자동으로 밝혀서 environment와 tint 양쪽에 공급한다.
private struct AdaptiveAccent: ViewModifier {
    let base: Color
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let adapted = colorScheme == .dark ? base.adaptedForDarkMode() : base
        content
            .environment(\.resolvedAccent, adapted)
            .tint(adapted)
    }
}

/// 종료 시 미저장 플러시 + 프로젝트 자동 백업 + Finder 더블클릭 열기.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    /// 종료 전에 미저장분을 플러시하고, 저장에 실패한 문서가 있으면 종료를 보류하고 묻는다 —
    /// applicationWillTerminate 시점에는 이미 취소가 불가능하기 때문에 여기서 가드한다.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            guard let appState else { return .terminateNow }
            appState.flushAllSessions()
            let failed = appState.failedSaveTitles
            guard !failed.isEmpty else { return .terminateNow }

            let l10n = Localizer.shared
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = l10n.t(.saveFailedQuitTitle)
            alert.informativeText = l10n.t(.saveFailedQuitMessage) + "\n\n" + failed.joined(separator: "\n")
            alert.addButton(withTitle: l10n.t(.cancel)) // 기본 버튼 = 안전한 선택
            alert.addButton(withTitle: l10n.t(.quitAnyway))
            return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            appState?.handleTermination()
        }
    }

    /// Finder에서 .scen/.scno/.scpa 번들을 더블클릭하면 해당 탭으로 연다.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            guard let appState else { return }
            for url in urls {
                if let envelope = DocumentPackageIO.readEnvelope(from: url) {
                    appState.openDocument(id: envelope.id, at: url)
                }
            }
        }
    }
}
