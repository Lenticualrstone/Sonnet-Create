import AppCore
import AppKit
import DesignSystem
import Foundation
import SwiftUI

// MARK: - 모델/체커

/// GitHub 릴리스 한 건의 요약 — 업데이트 인디케이터/퀵메뉴의 데이터.
struct UpdateInfo: Equatable {
    let version: String // 태그에서 v 접두사를 뗀 "1.3"
    let title: String
    let notes: String
    let pageURL: URL
    /// .dmg 자산이 릴리스에 첨부돼 있으면 직접 다운로드 경로
    let assetURL: URL?
    let assetName: String?
}

/// GitHub Releases API로 최신 버전을 확인한다 (공개 리포, 인증 불필요).
enum UpdateChecker {
    static let repo = "Lenticualrstone/Sonnet-Create"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func fetchLatest() async -> UpdateInfo? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data),
              let pageURL = URL(string: release.htmlURL)
        else { return nil }
        let dmg = release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        return UpdateInfo(
            version: normalized(release.tagName),
            title: release.name ?? release.tagName,
            notes: release.body ?? "",
            pageURL: pageURL,
            assetURL: dmg.flatMap { URL(string: $0.downloadURL) },
            assetName: dmg?.name
        )
    }

    static func normalized(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// 숫자 세그먼트 비교 — "1.10" > "1.2".
    static func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").map { Int($0) ?? 0 }
        let localParts = local.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(remoteParts.count, localParts.count) {
            let r = index < remoteParts.count ? remoteParts[index] : 0
            let l = index < localParts.count ? localParts[index] : 0
            if r != l { return r > l }
        }
        return false
    }

    private struct Release: Decodable {
        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name, body, assets
            case htmlURL = "html_url"
        }
    }

    private struct Asset: Decodable {
        let name: String
        let downloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
        }
    }
}

// MARK: - AppState 연동

extension AppState {
    /// 최신 릴리스 확인 — 자동(실행 시)은 건너뛴 버전을 무시하고, 수동은 다시 보여준다.
    func checkForUpdates(manual: Bool = false) {
        guard !isCheckingUpdate else { return }
        isCheckingUpdate = true
        Task { [weak self] in
            let latest = await UpdateChecker.fetchLatest()
            guard let self else { return }
            isCheckingUpdate = false
            let l10n = Localizer.shared
            guard let latest, UpdateChecker.isNewer(latest.version, than: UpdateChecker.currentVersion) else {
                availableUpdate = nil
                if manual {
                    notify(symbol: "checkmark.seal", message: l10n.t(.updateUpToDate))
                }
                return
            }
            if !manual, settings.applied.skippedUpdateVersion == latest.version { return }
            let isNewDiscovery = availableUpdate != latest
            availableUpdate = latest
            if isNewDiscovery {
                notify(
                    symbol: "arrow.down.circle",
                    message: String(format: l10n.t(.updateAvailableFormat), latest.version)
                )
            }
        }
    }

    /// '이 버전 건너뛰기' — 자동 확인에서 이 버전을 다시 알리지 않는다.
    func skipAvailableUpdate() {
        guard let update = availableUpdate else { return }
        settings.applyField { $0.skippedUpdateVersion = update.version }
        availableUpdate = nil
    }

    /// DMG 자산이 있으면 내려받아 열고(반자동 설치), 없으면 릴리스 페이지로 보낸다.
    func downloadAndOpenUpdate() {
        guard let update = availableUpdate else { return }
        guard let assetURL = update.assetURL else {
            NSWorkspace.shared.open(update.pageURL)
            return
        }
        guard !isDownloadingUpdate else { return }
        isDownloadingUpdate = true
        Task { [weak self] in
            do {
                let (temp, _) = try await URLSession.shared.download(from: assetURL)
                let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                var target = downloads.appendingPathComponent(update.assetName ?? "SonnetCreate.dmg")
                var counter = 2
                while FileManager.default.fileExists(atPath: target.path) {
                    target = downloads.appendingPathComponent("\(counter)-\(update.assetName ?? "SonnetCreate.dmg")")
                    counter += 1
                }
                try FileManager.default.moveItem(at: temp, to: target)
                await MainActor.run { [weak self] in
                    self?.isDownloadingUpdate = false
                    NSWorkspace.shared.open(target)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isDownloadingUpdate = false
                    self?.notify(symbol: "exclamationmark.triangle", message: Localizer.shared.t(.updateDownloadFailed))
                }
            }
        }
    }
}

// MARK: - 업데이트 퀵메뉴 (탭바 인디케이터의 팝오버)

struct UpdateQuickMenu: View {
    @Environment(AppState.self) private var app
    @Environment(\.resolvedAccent) private var accent
    let update: UpdateInfo
    let dismiss: () -> Void

    var body: some View {
        let l10n = Localizer.shared
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(update.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(String(format: l10n.t(.updateCurrentFormat), UpdateChecker.currentVersion) + "  →  v\(update.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !update.notes.isEmpty {
                ScrollView {
                    Text(update.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 170)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }

            HStack(spacing: 8) {
                Button {
                    app.downloadAndOpenUpdate()
                } label: {
                    if app.isDownloadingUpdate {
                        ProgressView().controlSize(.small)
                    } else {
                        // 자산(dmg)이 없으면 다운로드 대신 릴리스 페이지로 이동한다
                        Label(
                            l10n.t(update.assetURL != nil ? .updateDownload : .updateViewRelease),
                            systemImage: update.assetURL != nil ? "arrow.down.circle" : "arrow.up.right.square"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(app.isDownloadingUpdate)

                if update.assetURL != nil {
                    Button(l10n.t(.updateViewRelease)) {
                        NSWorkspace.shared.open(update.pageURL)
                    }
                    .controlSize(.small)
                }

                Spacer()

                Button(l10n.t(.updateSkipVersion)) {
                    app.skipAvailableUpdate()
                    dismiss()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
            }
        }
        .padding(DesignTokens.Spacing.m)
        .frame(width: 360)
    }
}

// MARK: - 설정 > 기본의 업데이트 섹션 (SettingsKit에 AnyView로 주입)

struct UpdateSettingsSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let l10n = Localizer.shared
        @Bindable var settings = app.settings
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            Toggle(l10n.t(.updateAutoCheck), isOn: $settings.draft.autoCheckUpdates)
            HStack(spacing: 8) {
                Text(String(format: l10n.t(.updateCurrentFormat), UpdateChecker.currentVersion))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let update = app.availableUpdate {
                    Text("→ v\(update.version)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Spacer()
                if app.isCheckingUpdate {
                    ProgressView().controlSize(.small)
                }
                Button(l10n.t(.updateCheckNow)) {
                    app.checkForUpdates(manual: true)
                }
                .controlSize(.small)
                .disabled(app.isCheckingUpdate)
            }
        }
    }
}
