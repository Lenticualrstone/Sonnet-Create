import AppCore
import AppKit
import DesignSystem
import Foundation
import SwiftUI

/// 언어별 가이드(튜토리얼) 프로젝트를 GitHub 릴리스 자산에서 찾는다.
enum GuideProjectChecker {
    /// 설치된 버전에 맞는 릴리스를 우선 조회하고, 없으면 최신 정식판으로 폴백한다
    /// (베타 실행 중이거나 해당 버전 태그가 아직 릴리스되지 않은 경우 대비 — 그래야
    /// 아직 없는 기능을 언급하는 가이드를 받는 일이 없다).
    static func assetURL(forLanguage language: AppLanguage) async -> (url: URL, name: String)? {
        let assetFileName = "SonnetCreate-Guide-\(language.rawValue).scproj"
        var release = await UpdateChecker.fetchRelease(path: "releases/tags/v\(UpdateChecker.currentVersion)")
        if release == nil {
            release = await UpdateChecker.fetchRelease(path: "releases/latest")
        }
        guard let release,
              let asset = release.assets.first(where: { $0.name.caseInsensitiveCompare(assetFileName) == .orderedSame }),
              let url = URL(string: asset.downloadURL)
        else { return nil }
        return (url, asset.name)
    }
}

// MARK: - AppState 연동

extension AppState {
    /// 설정 > 가이드 프로젝트의 "가이드 프로젝트 생성" 버튼 — GitHub에서 현재 UI 언어에 맞는
    /// .scproj를 받아 워크스페이스로 가져온다.
    func createGuideProject() {
        guard !isCreatingGuideProject else { return }
        isCreatingGuideProject = true
        let manager = backupManager
        Task { [weak self] in
            guard let self else { return }
            guard let asset = await GuideProjectChecker.assetURL(forLanguage: Localizer.shared.language) else {
                isCreatingGuideProject = false
                notify(symbol: "exclamationmark.triangle", message: Localizer.shared.t(.guideProjectUnavailable))
                return
            }
            do {
                let (temp, _) = try await URLSession.shared.download(from: asset.url)
                let success = await Task.detached(priority: .userInitiated) {
                    (try? manager.importProject(from: temp)) != nil
                }.value
                try? FileManager.default.removeItem(at: temp)
                isCreatingGuideProject = false
                if success {
                    workspace.scan()
                    notify(symbol: "shippingbox", message: Localizer.shared.t(.guideProjectCreated))
                } else {
                    notify(symbol: "exclamationmark.triangle", message: Localizer.shared.t(.guideProjectFailed))
                }
            } catch {
                isCreatingGuideProject = false
                notify(symbol: "exclamationmark.triangle", message: Localizer.shared.t(.guideProjectFailed))
            }
        }
    }
}

// MARK: - 설정 > 기본의 가이드 프로젝트 섹션 (SettingsKit에 AnyView로 주입)

struct GuideProjectSettingsSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let l10n = Localizer.shared
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            Text(l10n.t(.guideProjectHint))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                // 첫 실행 안내(온보딩)를 언제든 다시 열 수 있게 (5단계)
                Button(l10n.t(.onboardingReplay)) {
                    app.replayOnboarding()
                }
                .controlSize(.small)
                Spacer()
                if app.isCreatingGuideProject {
                    ProgressView().controlSize(.small)
                }
                Button(l10n.t(.createGuideProject)) {
                    app.createGuideProject()
                }
                .controlSize(.small)
                .disabled(app.isCreatingGuideProject)
            }
        }
    }
}
