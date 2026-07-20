import AppCore
import AppKit
import DesignSystem
import SwiftUI

// MARK: - 첫 실행 온보딩 (5단계)
// 강제 가입/긴 튜토리얼 대신 3걸음짜리 짧은 흐름: 저장 위치 확인 → 네 가지 문서 소개 →
// 시작 방법 선택(가이드 프로젝트 / 빈 프로젝트 / 독립 문서). 언제든 건너뛸 수 있고,
// 문서가 하나도 없는 새 워크스페이스에서 처음 1회만 나타나며, 설정에서 다시 열 수 있다.

extension AppState {
    private static let onboardingShownKey = "onboarding-shown-v2"

    /// 스플래시 종료 시 호출 — 새 워크스페이스의 첫 실행에만 온보딩을 띄운다.
    /// 기존 사용자는(문서/프로젝트 보유) 조용히 지나가고 플래그만 기록한다.
    func evaluateOnboarding() {
        // UI 테스트: 환경 변수로만 제어 — 영속 플래그를 읽지도 쓰지도 않는다
        if Self.isUITest {
            showOnboarding = ProcessInfo.processInfo.environment["UITEST_ONBOARDING"] == "1"
            return
        }
        guard !UserDefaults.standard.bool(forKey: Self.onboardingShownKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.onboardingShownKey)
        guard workspace.visibleDocuments.isEmpty, workspace.projects.isEmpty else { return }
        showOnboarding = true
    }

    /// 설정 > 가이드 프로젝트의 "첫 실행 안내 다시 보기".
    func replayOnboarding() {
        showOnboarding = true
    }
}

struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @Environment(\.renderQuality) private var quality
    @Environment(\.resolvedAccent) private var accent

    @State private var step = 0

    private let stepCount = 3

    var body: some View {
        let l10n = Localizer.shared
        ZStack {
            // 뒷배경 디밍 — 클릭해도 닫히지 않는다 (건너뛰기 버튼이 명시적 출구)
            SonnetPalette.ink.opacity(0.25)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    switch step {
                    case 0: welcomeStep(l10n)
                    case 1: typesStep(l10n)
                    default: startStep(l10n)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)

                Divider().opacity(0.4)
                footer(l10n)
            }
            .frame(width: 560)
            .glassSurface(cornerRadius: DesignTokens.Radius.large, quality: quality)
            .shadow(color: .black.opacity(0.3), radius: 30, y: 16)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    // MARK: 1걸음 — 환영 + 저장 위치 확인

    private func welcomeStep(_ l10n: Localizer) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
            HStack(spacing: DesignTokens.Spacing.m) {
                InkStrokeMark(size: 30, color: accent)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(SonnetPalette.accentTint)
                    )
                Text(l10n.t(.onboardingWelcomeTitle))
                    .font(DSFonts.display(size: 21, weight: .bold))
                    .foregroundStyle(SonnetPalette.ink)
            }
            Text(l10n.t(.onboardingWelcomeBody))
                .font(.callout)
                .foregroundStyle(SonnetPalette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            // 저장 위치 — 지금 확인시키고, 바꾸려면 폴더 선택
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.t(.workspacePath))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SonnetPalette.inkMuted)
                HStack(spacing: DesignTokens.Spacing.s) {
                    Image(systemName: "folder")
                        .foregroundStyle(SonnetPalette.inkMuted)
                    Text(app.settings.applied.workspacePath)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(l10n.t(.choose)) { chooseWorkspace() }
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                        .fill(SonnetPalette.ink.opacity(0.05))
                )
                Text(l10n.t(.onboardingStorageCaption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        app.settings.applyField { $0.workspacePath = url.path }
        app.workspace.setRoot(url)
    }

    // MARK: 2걸음 — 네 가지 문서 소개

    private func typesStep(_ l10n: Localizer) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
            Text(l10n.t(.onboardingTypesTitle))
                .font(DSFonts.display(size: 21, weight: .bold))
                .foregroundStyle(SonnetPalette.ink)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                typeCard(.scenario, name: l10n.t(.scenario), body: l10n.t(.typeDescScenario))
                typeCard(.mindmap, name: l10n.t(.mindmap), body: l10n.t(.typeDescMindmap))
                typeCard(.page, name: l10n.t(.page), body: l10n.t(.typeDescPage))
                typeCard(.character, name: l10n.t(.characterPage), body: l10n.t(.typeDescCharacter))
            }
        }
    }

    private func typeCard(_ type: DSFileType, name: String, body text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                FileTypeIcon(type, size: 16)
                Text(name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(SonnetPalette.ink)
            }
            Text(text)
                .font(.caption)
                .foregroundStyle(SonnetPalette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
                .fill(SonnetPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
                .strokeBorder(SonnetPalette.ink.opacity(0.09), lineWidth: 1)
        )
    }

    // MARK: 3걸음 — 시작 방법 선택

    private func startStep(_ l10n: Localizer) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
            Text(l10n.t(.onboardingStartTitle))
                .font(DSFonts.display(size: 21, weight: .bold))
                .foregroundStyle(SonnetPalette.ink)
            VStack(spacing: DesignTokens.Spacing.s) {
                startOption(
                    symbol: "shippingbox",
                    title: l10n.t(.onboardingGuideOption),
                    caption: l10n.t(.onboardingGuideCaption),
                    isPrimary: true
                ) {
                    app.createGuideProject()
                    finish()
                }
                startOption(
                    symbol: "folder.badge.plus",
                    title: l10n.t(.onboardingFirstProjectOption),
                    caption: l10n.t(.onboardingFirstProjectCaption)
                ) {
                    _ = try? app.workspace.createProject(name: l10n.t(.newProject))
                    finish()
                }
                startOption(
                    symbol: "doc",
                    title: l10n.t(.onboardingSoloOption),
                    caption: l10n.t(.onboardingSoloCaption)
                ) {
                    finish()
                }
            }
        }
    }

    private func startOption(
        symbol: String,
        title: String,
        caption: String,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.m) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isPrimary ? Color.white : accent)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isPrimary ? AnyShapeStyle(accent) : AnyShapeStyle(SonnetPalette.accentTint))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(SonnetPalette.ink)
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(SonnetPalette.inkMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
                    .fill(SonnetPalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
                    .strokeBorder(
                        isPrimary ? accent.opacity(0.5) : SonnetPalette.ink.opacity(0.09),
                        lineWidth: isPrimary ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous))
        }
        .buttonStyle(LiftButtonStyle(hoverScale: 1.01, pressScale: 0.99))
    }

    // MARK: 푸터 — 건너뛰기 · 진행 점 · 이전/다음

    private func footer(_ l10n: Localizer) -> some View {
        HStack(spacing: DesignTokens.Spacing.m) {
            Button(l10n.t(.onboardingSkip)) { finish() }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(SonnetPalette.inkMuted)

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Circle()
                        .fill(index == step ? accent : SonnetPalette.ink.opacity(0.15))
                        .frame(width: 7, height: 7)
                }
            }

            Spacer()

            if step > 0 {
                Button(l10n.t(.onboardingBack)) {
                    withAnimation(DesignTokens.Motion.gentle) { step -= 1 }
                }
                .controlSize(.large)
            }
            if step < stepCount - 1 {
                Button(l10n.t(.onboardingNext)) {
                    withAnimation(DesignTokens.Motion.gentle) { step += 1 }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func finish() {
        withAnimation(DesignTokens.Motion.glassPopOut) { app.showOnboarding = false }
    }
}
