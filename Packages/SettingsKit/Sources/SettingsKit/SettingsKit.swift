import AppCore
import DesignSystem
import Foundation
import Observation

/// 앱 전역 설정 (UserDefaults에 JSON으로 저장).
public struct AppSettings: Codable, Sendable, Equatable {
    // 기본
    public var language: AppLanguage = .korean
    public var workspacePath: String = NSString("~/Documents/SonnetCreate").expandingTildeInPath
    public var autosave: Bool = true
    public var backupOnQuit: Bool = true
    public var authorName: String = ""
    /// 프로필 사진 — 워크스페이스 밖 고정 위치에 저장된 파일의 절대 경로 (문서 번들과 무관)
    public var authorPhotoPath: String = ""
    /// 짧은 자기소개
    public var authorBio: String = ""
    /// 프로필 사진 원형 크롭 — 줌(1~3)과 지름 대비 비율 오프셋 (캐릭터 크롭과 동일 체계)
    public var authorCropZoom: Double = 1
    public var authorCropOffsetX: Double = 0
    public var authorCropOffsetY: Double = 0
    /// 아카이브에서 항목을 여는 클릭 방식 (true = 싱글 클릭)
    public var openOnSingleClick: Bool = true

    // 테마
    /// 인터페이스 스타일 — 기본은 Sonnet (본톤 + 적갈 액센트)
    public var interfaceTheme: InterfaceTheme = .sonnet
    public var themeMode: ThemeMode = .system
    public var accent: AccentChoice = .system
    /// Liquid Glass를 끄고 평면 표면 사용 — v1.3부터 Liquid Glass가 기본
    public var disableLiquidGlass: Bool = false
    /// Liquid Glass 적용 모드 — "point"(팔레트·패널·툴바만) | "full"(사이드바·인스펙터까지)
    public var glassModeRaw: String = "point"
    /// 유리 강도 (0~1) — 표면 불투명도/블러에 반영
    public var glassIntensity: Double = 0.62
    /// 페이퍼 그레인 — 캔버스에 미세 그레인 텍스처 오버레이
    public var paperGrainEnabled: Bool = false
    /// Wavy Dot Field 배경 효과 (기본 꺼짐)
    public var backgroundEffectEnabled: Bool = false
    /// 전체 UI 크기 배율
    public var uiScale: Double = 1.0
    /// 탭 스타일 — "chrome"(기본) | "capsule"
    public var tabStyleRaw: String = "chrome"
    /// 베타: Touch Bar 지원
    public var touchBarEnabled: Bool = false
    /// 시나리오 캐릭터 인스펙터를 오른쪽에 배치
    public var scenarioInspectorOnRight: Bool = false
    /// AI 스피어 스타일 — "particle"(기본) | "glass" | "holographic" | "ink" | "plasma"
    public var aiSphereStyleRaw: String = "particle"
    /// 파티클 스피어 입자 밀도 — "sparse" | "normal"(기본) | "dense"
    public var aiSphereDensityRaw: String = "normal"
    public var quality: RenderQuality = .standard
    public var backgroundSpeed: Double = 0.6
    public var backgroundDensity: Double = 34
    public var backgroundBlurOthers: Double = 14
    public var backgroundDotSize: Double = 1.0
    /// 시점 각도 — 1.0 정면, 낮을수록 기울어짐
    public var backgroundPitch: Double = 1.0
    /// 도트 색: false = 테마 추종, true = 강조색
    public var backgroundUseAccent: Bool = false

    // 텍스트
    /// 기본 글꼴 팩 — 기본은 Pretendard
    public var fontFamily: FontFamily = .pretendard
    public var fontScale: Double = 1.0
    public var lineSpacingScale: Double = 1.0
    /// 블록 간 간격 (pt) — 페이지·시나리오 에디터 (프리셋: 좁게 6 / 중간 12 / 넓게 20)
    public var blockSpacing: Double = 12
    /// 시나리오 대사 블록의 캐릭터 표시 방식 — "avatarAndName"(기본) | "avatarOnly" | "nameOnly" | "hidden"
    public var dialogueDisplayRaw: String = "avatarAndName"
    /// 시나리오 대사 블록의 캐릭터 프로필(아바타) 크기 (pt)
    public var dialogueAvatarSize: Double = 34

    /// 수동 저장(⌘S) 시 자동 스냅샷 — 자동분은 문서당 최근 10개만 보관
    public var snapshotOnManualSave: Bool = true
    /// 일일 집필 목표 (글자 수) — 프로필의 목표 카드 기준
    public var dailyWritingGoal: Double = 1000

    // 에디터별
    /// 페이지: 포커스 모드 — 편집 중 블록 외 디밍
    public var pageFocusModeEnabled: Bool = false
    /// 페이지: 타자기 모드 — 편집 중 블록을 화면 중앙에 유지
    public var pageTypewriterEnabled: Bool = false
    /// 마인드맵: 노드 선택 시 인스펙터 자동 표시
    public var mindmapAutoOpenInspector: Bool = true

    // 업데이트 (GitHub 릴리스 연동)
    /// 실행 시 자동으로 새 릴리스를 확인
    public var autoCheckUpdates: Bool = true
    /// '이 버전 건너뛰기'로 무시한 버전 (자동 확인에서만 제외, 수동 확인은 다시 보여줌)
    public var skippedUpdateVersion: String = ""

    // AI 에이전트
    public var aiProviderRaw: String = "offline"
    /// 에이전트 도구(탐색/읽기)의 가시 범위 — v1.3부터 실제로 강제된다
    public var aiContextScope: AIContextScope = .workspace
    /// 에이전트 이름 (비우면 기본 이름)
    public var agentName: String = ""
    /// 에이전트 행동지침 — 마크다운 페이지 전문
    public var agentInstructions: String = ""
    /// 제공자별 모델 ID (비우면 제공자 기본 모델)
    public var anthropicModel: String = ""
    public var openaiModel: String = ""
    public var geminiModel: String = ""
    public var grokModel: String = ""

    public init() {}

    /// 설정 필드가 추가돼도 기존 저장분을 잃지 않도록 전 필드 decodeIfPresent.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? d.language
        workspacePath = try c.decodeIfPresent(String.self, forKey: .workspacePath) ?? d.workspacePath
        autosave = try c.decodeIfPresent(Bool.self, forKey: .autosave) ?? d.autosave
        backupOnQuit = try c.decodeIfPresent(Bool.self, forKey: .backupOnQuit) ?? d.backupOnQuit
        authorName = try c.decodeIfPresent(String.self, forKey: .authorName) ?? d.authorName
        authorPhotoPath = try c.decodeIfPresent(String.self, forKey: .authorPhotoPath) ?? d.authorPhotoPath
        authorBio = try c.decodeIfPresent(String.self, forKey: .authorBio) ?? d.authorBio
        authorCropZoom = try c.decodeIfPresent(Double.self, forKey: .authorCropZoom) ?? d.authorCropZoom
        authorCropOffsetX = try c.decodeIfPresent(Double.self, forKey: .authorCropOffsetX) ?? d.authorCropOffsetX
        authorCropOffsetY = try c.decodeIfPresent(Double.self, forKey: .authorCropOffsetY) ?? d.authorCropOffsetY
        openOnSingleClick = try c.decodeIfPresent(Bool.self, forKey: .openOnSingleClick) ?? d.openOnSingleClick
        interfaceTheme = try c.decodeIfPresent(InterfaceTheme.self, forKey: .interfaceTheme) ?? d.interfaceTheme
        themeMode = try c.decodeIfPresent(ThemeMode.self, forKey: .themeMode) ?? d.themeMode
        accent = try c.decodeIfPresent(AccentChoice.self, forKey: .accent) ?? d.accent
        disableLiquidGlass = try c.decodeIfPresent(Bool.self, forKey: .disableLiquidGlass) ?? d.disableLiquidGlass
        glassModeRaw = try c.decodeIfPresent(String.self, forKey: .glassModeRaw) ?? d.glassModeRaw
        glassIntensity = try c.decodeIfPresent(Double.self, forKey: .glassIntensity) ?? d.glassIntensity
        paperGrainEnabled = try c.decodeIfPresent(Bool.self, forKey: .paperGrainEnabled) ?? d.paperGrainEnabled
        backgroundEffectEnabled = try c.decodeIfPresent(Bool.self, forKey: .backgroundEffectEnabled) ?? d.backgroundEffectEnabled
        uiScale = try c.decodeIfPresent(Double.self, forKey: .uiScale) ?? d.uiScale
        tabStyleRaw = try c.decodeIfPresent(String.self, forKey: .tabStyleRaw) ?? d.tabStyleRaw
        touchBarEnabled = try c.decodeIfPresent(Bool.self, forKey: .touchBarEnabled) ?? d.touchBarEnabled
        scenarioInspectorOnRight = try c.decodeIfPresent(Bool.self, forKey: .scenarioInspectorOnRight) ?? d.scenarioInspectorOnRight
        aiSphereStyleRaw = try c.decodeIfPresent(String.self, forKey: .aiSphereStyleRaw) ?? d.aiSphereStyleRaw
        aiSphereDensityRaw = try c.decodeIfPresent(String.self, forKey: .aiSphereDensityRaw) ?? d.aiSphereDensityRaw
        quality = try c.decodeIfPresent(RenderQuality.self, forKey: .quality) ?? d.quality
        backgroundSpeed = try c.decodeIfPresent(Double.self, forKey: .backgroundSpeed) ?? d.backgroundSpeed
        backgroundDensity = try c.decodeIfPresent(Double.self, forKey: .backgroundDensity) ?? d.backgroundDensity
        backgroundBlurOthers = try c.decodeIfPresent(Double.self, forKey: .backgroundBlurOthers) ?? d.backgroundBlurOthers
        backgroundDotSize = try c.decodeIfPresent(Double.self, forKey: .backgroundDotSize) ?? d.backgroundDotSize
        backgroundPitch = try c.decodeIfPresent(Double.self, forKey: .backgroundPitch) ?? d.backgroundPitch
        backgroundUseAccent = try c.decodeIfPresent(Bool.self, forKey: .backgroundUseAccent) ?? d.backgroundUseAccent
        fontFamily = try c.decodeIfPresent(FontFamily.self, forKey: .fontFamily) ?? d.fontFamily
        fontScale = try c.decodeIfPresent(Double.self, forKey: .fontScale) ?? d.fontScale
        lineSpacingScale = try c.decodeIfPresent(Double.self, forKey: .lineSpacingScale) ?? d.lineSpacingScale
        blockSpacing = try c.decodeIfPresent(Double.self, forKey: .blockSpacing) ?? d.blockSpacing
        dialogueDisplayRaw = try c.decodeIfPresent(String.self, forKey: .dialogueDisplayRaw) ?? d.dialogueDisplayRaw
        dialogueAvatarSize = try c.decodeIfPresent(Double.self, forKey: .dialogueAvatarSize) ?? d.dialogueAvatarSize
        snapshotOnManualSave = try c.decodeIfPresent(Bool.self, forKey: .snapshotOnManualSave) ?? d.snapshotOnManualSave
        dailyWritingGoal = try c.decodeIfPresent(Double.self, forKey: .dailyWritingGoal) ?? d.dailyWritingGoal
        pageFocusModeEnabled = try c.decodeIfPresent(Bool.self, forKey: .pageFocusModeEnabled) ?? d.pageFocusModeEnabled
        pageTypewriterEnabled = try c.decodeIfPresent(Bool.self, forKey: .pageTypewriterEnabled) ?? d.pageTypewriterEnabled
        mindmapAutoOpenInspector = try c.decodeIfPresent(Bool.self, forKey: .mindmapAutoOpenInspector) ?? d.mindmapAutoOpenInspector
        autoCheckUpdates = try c.decodeIfPresent(Bool.self, forKey: .autoCheckUpdates) ?? d.autoCheckUpdates
        skippedUpdateVersion = try c.decodeIfPresent(String.self, forKey: .skippedUpdateVersion) ?? d.skippedUpdateVersion
        aiProviderRaw = try c.decodeIfPresent(String.self, forKey: .aiProviderRaw) ?? d.aiProviderRaw
        aiContextScope = try c.decodeIfPresent(AIContextScope.self, forKey: .aiContextScope) ?? d.aiContextScope
        agentName = try c.decodeIfPresent(String.self, forKey: .agentName) ?? d.agentName
        agentInstructions = try c.decodeIfPresent(String.self, forKey: .agentInstructions) ?? d.agentInstructions
        anthropicModel = try c.decodeIfPresent(String.self, forKey: .anthropicModel) ?? d.anthropicModel
        openaiModel = try c.decodeIfPresent(String.self, forKey: .openaiModel) ?? d.openaiModel
        geminiModel = try c.decodeIfPresent(String.self, forKey: .geminiModel) ?? d.geminiModel
        grokModel = try c.decodeIfPresent(String.self, forKey: .grokModel) ?? d.grokModel
    }
}

/// 설정 상태·저장. 편집은 draft에 쌓이고 '저장' 버튼으로 반영된다.
@MainActor
@Observable
public final class SettingsStore {
    public private(set) var applied: AppSettings
    public var draft: AppSettings

    /// API 키는 UserDefaults가 아닌 Keychain으로 — 앱이 주입.
    /// 키는 keychain 계정 이름(제공자별), 값은 편집 중인 키 문자열.
    public var draftAPIKeys: [String: String] = [:]
    public var persistAPIKey: ((_ value: String, _ account: String) -> Void)?
    public var loadAPIKey: ((_ account: String) -> String)?

    /// 이 앱이 관리하는 keychain 계정 목록 — 앱이 시작 시 주입.
    public var apiKeyAccounts: [String] = []

    /// 저장 직후 앱이 반영 작업(테마/워크스페이스 전환 등)을 하도록 호출
    public var onApply: ((AppSettings) -> Void)?

    private static let defaultsKey = "app-settings-v1"

    public init() {
        var loaded = Self.load()
        // 1회성 마이그레이션: chrome-tabs 재설계에 맞춰 기존 capsule 기본값을 chrome으로
        let migrationKey = "migrated-chrome-tabs-v1"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            if loaded.tabStyleRaw == "capsule" { loaded.tabStyleRaw = "chrome" }
            UserDefaults.standard.set(true, forKey: migrationKey)
            Self.persist(loaded)
        }
        // 1회성 마이그레이션 (v1.3): 테마/강조색 일원화 — 기존 선택을 통합 테마로 정리
        let unifiedThemeKey = "migrated-unified-theme-v13"
        if !UserDefaults.standard.bool(forKey: unifiedThemeKey) {
            loaded.interfaceTheme = .sonnet
            loaded.accent = .system
            loaded.disableLiquidGlass = false // v1.3부터 Liquid Glass 기본 켬
            UserDefaults.standard.set(true, forKey: unifiedThemeKey)
            Self.persist(loaded)
        }
        // 1회성 마이그레이션 (v1.3): 컨텍스트 범위가 이제 에이전트 도구를 실제로 제한한다 —
        // 옛 기본값(.document)을 그대로 두면 채팅 에이전트가 아무것도 못 찾는 상태로 시작한다.
        let agentScopeKey = "migrated-agent-scope-v13"
        if !UserDefaults.standard.bool(forKey: agentScopeKey) {
            loaded.aiContextScope = .workspace
            UserDefaults.standard.set(true, forKey: agentScopeKey)
            Self.persist(loaded)
        }
        applied = loaded
        draft = loaded
    }

    public var hasChanges: Bool {
        if draft != applied { return true }
        return apiKeyAccounts.contains { account in
            (draftAPIKeys[account] ?? "") != (loadAPIKey?(account) ?? "")
        }
    }

    public func refreshAPIKeyDraft() {
        for account in apiKeyAccounts {
            draftAPIKeys[account] = loadAPIKey?(account) ?? ""
        }
    }

    /// '저장' 버튼 — draft를 적용/영속화.
    public func save() {
        applied = draft
        Self.persist(applied)
        for account in apiKeyAccounts {
            persistAPIKey?(draftAPIKeys[account] ?? "", account)
        }
        onApply?(applied)
    }

    public func revert() {
        draft = applied
        refreshAPIKeyDraft()
    }

    /// 설정 창의 draft 편집 세션과 무관하게 단일 필드를 즉시 적용/영속한다
    /// (업데이트 '이 버전 건너뛰기'처럼 UI 밖에서 조용히 바뀌는 값용 —
    /// save()를 쓰면 사용자가 편집 중이던 draft 전체가 원치 않게 적용될 수 있다).
    public func applyField(_ mutate: (inout AppSettings) -> Void) {
        mutate(&applied)
        mutate(&draft)
        Self.persist(applied)
    }

    private static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    private static func persist(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
