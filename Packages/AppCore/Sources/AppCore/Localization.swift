// 로컬라이제이션 사전은 언어별 한 줄 표기가 가독성에 유리하다 — 줄 길이 규칙 제외.
// swiftlint:disable line_length
import Foundation
import Observation

/// 지원 언어 (한/일/영).
public enum AppLanguage: String, Codable, CaseIterable, Sendable, Identifiable {
    case korean = "ko"
    case japanese = "ja"
    case english = "en"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .korean: "한국어"
        case .japanese: "日本語"
        case .english: "English"
        }
    }
}

/// 앱 전역 UI 문자열 키.
public enum L10nKey: String, Sendable {
    case appName, home, searchPlaceholder, newDocument, recentDocuments, noRecents
    case scenario, mindmap, page, characterPage, project
    case newScenario, newMindMap, newPage, newCharacter, newProject
    case cancel, save, done, delete, rename, duplicate, close, open, choose, apply
    case hide, unhide, moveToTrash, restore, hiddenItems, trashItems
    case settings, settingsGeneral, settingsTheme, settingsText, settingsBeta
    case language, themeMode, themeSystem, themeLight, themeDark
    case accentColor, accentCustom, qualityTier, qualityLow, qualityStandard, qualityHigh
    case backgroundEffect, effectSpeed, effectDensity, effectBlur
    case fontSize, lineSpacing, workspacePath, autosave
    case backups, backupNow, backupTimeline, restoreBackup, exportProject, importProject
    case aiProvider, aiProviderApple, aiProviderAnthropic, aiProviderMock
    case apiKey, contextScope, ctxDocument, ctxProject, ctxWorkspace
    case dialogue, instruction, send, composerPlaceholderLine, composerPlaceholderNote
    case characters, addCharacter, characterName, characterRole, characterSummary, andOthers
    case undo, redo, searchInDocument, inspector, aiCompose, aiSuggesting, acceptAll, dismissAll, accept
    case archive, allDocuments, sortBy, sortName, sortModified, sortKind, viewList, viewGrid
    case openBehavior, singleClick, doubleClick
    case branch, mainRoute, newBranch, branchFromHere, branchPoint, backToMain
    case blockImage, blockTable
    case chooseImage, embedURL, aspectOriginal, enlarge, addRow, addColumn, showAsIcon
    case importFromProject
    case references, backlinks, addReference, properties, noReferences, createdAt, modifiedAt
    case exportHTML, exportPDF
    case effectDotSize, effectPitch, effectColor, followTheme
    case emptyWorkspaceTitle, emptyWorkspaceBody, createFirstProject, emptyCategory
    case adjustCrop
    case interfaceStyle, themeSonnet, themePilgrimage, fontLabel, fontPretendard, fontSystem, fontSerif, fontMono, disableGlass
    case blockSpacing
    case uiScale, tabStyle, tabStyleCapsule, tabStyleChrome, inspectorPosition, positionLeft, positionRight
    case importAny, aiAgent, sonnetAI, askAnything, openAsTab, clearChat
    case touchBarSupport, touchBarFunctions
    case profileTab, notesTab, relationsTab, galleryTab, voiceTab
    case addField, fieldName, fieldValue, addRelation, relationLabel
    case addImage, phaseTag, captionLabel
    case voiceTone, voiceTaboo, voiceSamples, addVoiceCard, addSample
    case appearances, linesCountFormat, editProfileImage
    case readOnlyMode, readOnlyOn, readOnlyOff
    case rehearsal, rehearsalPause, rehearsalResume, rehearsalStop, rehearsalSpeed
    case quickOpen, quickOpenPlaceholder, noMatches, actionsSection, documentsSection
    case focusMode, focusModeHint, typewriterMode, typewriterModeHint, mindmapAutoInspector
    case snapshots, takeSnapshot, snapshotNamePlaceholder, compare, beforeRestoreSnapshot
    case diffAdded, diffRemoved, diffChanged, noSnapshots, restoreSnapshotConfirm, noDifferences
    case snapshotOnSave, snapshotOnSaveHint
    case writingGoal, charsUnit, goalReached, streakDays
    case rehearsalVoice
    case settingsAppearance, settingsEditor
    case deleteProject, trashConfirmMessage, projectDeleteMessage
    case profilePage, contributions, activityEmpty
    case spacingCompact, spacingMedium, spacingWide
    case inbox, eventImported, eventExported, eventBackedUp, eventRestored, eventProjectDeleted
    case sideBySideToggle, imageWidth, imageAlign, alignLeft, alignCenter, alignRight, pasteImage
    case aboutMe, recentlyDeleted, choosePhoto, removePhoto, viewProfile
    case authRequiredHidden, authRequiredTrash, authReason, unlocked
    case profile, workspace, documents, untitled, editContent
    case addNode, nodeText, nodePage, nodeImage, nodeFile, edgeCaption, zoomReset
    case blockParagraph, blockHeading1, blockHeading2, blockHeading3
    case blockBulleted, blockNumbered, blockTask, blockToggle, blockQuote, blockCode, blockDivider, blockCallout
    case slashHint, exportMarkdown, importMarkdown
    case saveStateSaved, saveStateSaving, saveStateUnsaved, saveStateError
    case emptyEditorHint, doubleClickToCreate, dropHere, today, greeting
    case dialogueDisplayHeader, dialogueDisplayMethod
    case dialogueDisplayBoth, dialogueDisplayAvatarOnly, dialogueDisplayNameOnly, dialogueDisplayHidden
    case dialogueAvatarSize
    // 아카이브 확장: 영구삭제 확인 · 휴지통 비우기 · 삭제일 · 기타 카테고리 · 프로젝트 필터 · 다중선택
    case permanentDelete, permanentDeleteConfirmMessage, permanentDeleteConfirmMessagePlural
    case emptyTrashAction, emptyTrashConfirmMessage
    case sortTrashedDate, trashedOn, originalLocation, restoredToWorkspaceRoot
    case emptyHiddenItems, emptyTrashItems, emptyOtherFiles
    case hideFinderHint
    case otherFiles, viewOnlyHint, revealInFinder
    case allProjects, openProjectArchive
    case selectedCountFormat, deselectAll, selectAll
    case showAllFormat
    case navigateBack, navigateForward
    // v1.2 안정성: 열기/저장 실패 표면화 · 백업 복원 안내
    case errorOpenTitle, errorCorruptedContent, errorDocumentMissing, errorOpenGeneric
    case saveFailedCloseTitle, saveFailedCloseMessage, retrySave, closeWithoutSaving
    case saveFailedQuitTitle, saveFailedQuitMessage, quitAnyway
    case restoreClosesTabsMessage, eventBackupFailed, eventImportFailed, eventExportFailed
    case backupRunning, restoreRunning
    // v1.2 인터페이스: 프로젝트 파일 인스펙터 · 손상 복구
    case projectFiles
    case recoverFromSnapshot, eventRecovered
    // v1.2 신기능: 대본 내보내기 · 씬 목차 · 주간 리포트
    case exportText, exportScript, sceneList, sceneFormat
    case weeklyReport, weeklyTotal, weeklyBestDay, vsLastWeek
    // v1.3 업데이트 시스템 (GitHub 릴리스 연동)
    case updates, updateAvailableFormat, updateCheckNow, updateAutoCheck, updateUpToDate
    case updateDownload, updateViewRelease, updateSkipVersion, updateCurrentFormat, updateDownloadFailed
    // AI 스피어 스타일
    case aiSphereStyle, sphereStyleGlass, sphereStyleHolographic, sphereStyleInk, sphereStylePlasma, sphereStyleParticle
    // 시간대 인사말 (홈 히어로) — %@ 자리에 작가 이름(있으면)
    case greetingMorning, greetingAfternoon, greetingEvening, greetingNight
    case greetingMorningNamed, greetingAfternoonNamed, greetingEveningNamed, greetingNightNamed
    // 파티클 스피어 밀도
    case sphereDensity, sphereDensitySparse, sphereDensityNormal, sphereDensityDense
}

/// 딕셔너리 기반 경량 로컬라이저. 시스템 .strings 대신 패키지 간 공유가 쉬운 단일 테이블을 쓴다.
@MainActor
@Observable
public final class Localizer {
    public static let shared = Localizer()

    public var language: AppLanguage = .korean

    public init() {}

    public func t(_ key: L10nKey) -> String {
        Self.table[key]?[language] ?? Self.table[key]?[.english] ?? key.rawValue
    }

    private static let table: [L10nKey: [AppLanguage: String]] = [
        .appName: [.korean: "Sonnet Create", .japanese: "Sonnet Create", .english: "Sonnet Create"],
        .home: [.korean: "홈", .japanese: "ホーム", .english: "Home"],
        .searchPlaceholder: [.korean: "프로젝트, 문서, 캐릭터 검색…", .japanese: "プロジェクト・ドキュメント・キャラクターを検索…", .english: "Search projects, documents, characters…"],
        .newDocument: [.korean: "새 문서", .japanese: "新規ドキュメント", .english: "New Document"],
        .recentDocuments: [.korean: "최근 항목", .japanese: "最近の項目", .english: "Recents"],
        .noRecents: [.korean: "최근에 연 문서가 없습니다", .japanese: "最近開いた項目はありません", .english: "No recent documents"],
        .scenario: [.korean: "시나리오", .japanese: "シナリオ", .english: "Scenario"],
        .mindmap: [.korean: "마인드맵", .japanese: "マインドマップ", .english: "Mind Map"],
        .page: [.korean: "페이지", .japanese: "ページ", .english: "Page"],
        .characterPage: [.korean: "캐릭터 페이지", .japanese: "キャラクターページ", .english: "Character Page"],
        .project: [.korean: "프로젝트", .japanese: "プロジェクト", .english: "Project"],
        .newScenario: [.korean: "새 시나리오", .japanese: "新規シナリオ", .english: "New Scenario"],
        .newMindMap: [.korean: "새 마인드맵", .japanese: "新規マインドマップ", .english: "New Mind Map"],
        .newPage: [.korean: "새 페이지", .japanese: "新規ページ", .english: "New Page"],
        .newCharacter: [.korean: "새 캐릭터", .japanese: "新規キャラクター", .english: "New Character"],
        .newProject: [.korean: "새 프로젝트", .japanese: "新規プロジェクト", .english: "New Project"],
        .cancel: [.korean: "취소", .japanese: "キャンセル", .english: "Cancel"],
        .save: [.korean: "저장", .japanese: "保存", .english: "Save"],
        .done: [.korean: "완료", .japanese: "完了", .english: "Done"],
        .delete: [.korean: "삭제", .japanese: "削除", .english: "Delete"],
        .rename: [.korean: "이름 변경", .japanese: "名称変更", .english: "Rename"],
        .duplicate: [.korean: "복제", .japanese: "複製", .english: "Duplicate"],
        .close: [.korean: "닫기", .japanese: "閉じる", .english: "Close"],
        .open: [.korean: "열기", .japanese: "開く", .english: "Open"],
        .choose: [.korean: "선택…", .japanese: "選択…", .english: "Choose…"],
        .apply: [.korean: "적용", .japanese: "適用", .english: "Apply"],
        .hide: [.korean: "가리기", .japanese: "非表示", .english: "Hide"],
        .unhide: [.korean: "가리기 해제", .japanese: "再表示", .english: "Unhide"],
        .moveToTrash: [.korean: "휴지통으로 이동", .japanese: "ゴミ箱に入れる", .english: "Move to Trash"],
        .restore: [.korean: "복원", .japanese: "復元", .english: "Restore"],
        .hiddenItems: [.korean: "가려진 항목", .japanese: "非表示の項目", .english: "Hidden"],
        .trashItems: [.korean: "휴지통", .japanese: "ゴミ箱", .english: "Trash"],
        .settings: [.korean: "설정", .japanese: "設定", .english: "Settings"],
        .settingsGeneral: [.korean: "기본", .japanese: "一般", .english: "General"],
        .settingsTheme: [.korean: "테마", .japanese: "テーマ", .english: "Theme"],
        .settingsText: [.korean: "텍스트", .japanese: "テキスト", .english: "Text"],
        .settingsBeta: [.korean: "베타", .japanese: "ベータ", .english: "Beta"],
        .language: [.korean: "언어", .japanese: "言語", .english: "Language"],
        .themeMode: [.korean: "화면 모드", .japanese: "外観モード", .english: "Appearance"],
        .themeSystem: [.korean: "시스템", .japanese: "システム", .english: "System"],
        .themeLight: [.korean: "라이트", .japanese: "ライト", .english: "Light"],
        .themeDark: [.korean: "다크", .japanese: "ダーク", .english: "Dark"],
        .accentColor: [.korean: "강조 색상", .japanese: "アクセントカラー", .english: "Accent Color"],
        .accentCustom: [.korean: "사용자 지정", .japanese: "カスタム", .english: "Custom"],
        .qualityTier: [.korean: "품질 단계", .japanese: "品質レベル", .english: "Quality Tier"],
        .qualityLow: [.korean: "낮음", .japanese: "低", .english: "Low"],
        .qualityStandard: [.korean: "표준", .japanese: "標準", .english: "Standard"],
        .qualityHigh: [.korean: "높음", .japanese: "高", .english: "High"],
        .backgroundEffect: [.korean: "배경 효과", .japanese: "背景エフェクト", .english: "Background Effect"],
        .effectSpeed: [.korean: "속도", .japanese: "速度", .english: "Speed"],
        .effectDensity: [.korean: "밀도", .japanese: "密度", .english: "Density"],
        .effectBlur: [.korean: "블러", .japanese: "ぼかし", .english: "Blur"],
        .fontSize: [.korean: "글자 크기", .japanese: "文字サイズ", .english: "Font Size"],
        .lineSpacing: [.korean: "줄 간격", .japanese: "行間", .english: "Line Spacing"],
        .workspacePath: [.korean: "저장 경로", .japanese: "保存先", .english: "Workspace Path"],
        .autosave: [.korean: "자동 저장", .japanese: "自動保存", .english: "Autosave"],
        .backups: [.korean: "백업", .japanese: "バックアップ", .english: "Backups"],
        .backupNow: [.korean: "지금 백업", .japanese: "今すぐバックアップ", .english: "Back Up Now"],
        .backupTimeline: [.korean: "타임라인 백업", .japanese: "タイムラインバックアップ", .english: "Backup Timeline"],
        .restoreBackup: [.korean: "이 시점으로 복원", .japanese: "この時点に復元", .english: "Restore This Point"],
        .exportProject: [.korean: "프로젝트 내보내기(.scproj)", .japanese: "プロジェクトを書き出す(.scproj)", .english: "Export Project (.scproj)"],
        .importProject: [.korean: "프로젝트 가져오기", .japanese: "プロジェクトを読み込む", .english: "Import Project"],
        .aiProvider: [.korean: "AI 제공자", .japanese: "AIプロバイダ", .english: "AI Provider"],
        .aiProviderApple: [.korean: "온디바이스 (Apple)", .japanese: "オンデバイス (Apple)", .english: "On-Device (Apple)"],
        .aiProviderAnthropic: [.korean: "Anthropic API", .japanese: "Anthropic API", .english: "Anthropic API"],
        .aiProviderMock: [.korean: "오프라인 초안 (내장)", .japanese: "オフラインドラフト (内蔵)", .english: "Offline Draft (Built-in)"],
        .apiKey: [.korean: "API 키", .japanese: "APIキー", .english: "API Key"],
        .contextScope: [.korean: "컨텍스트 범위", .japanese: "コンテキスト範囲", .english: "Context Scope"],
        .ctxDocument: [.korean: "현재 문서", .japanese: "現在のドキュメント", .english: "Current Document"],
        .ctxProject: [.korean: "프로젝트", .japanese: "プロジェクト", .english: "Project"],
        .ctxWorkspace: [.korean: "워크스페이스", .japanese: "ワークスペース", .english: "Workspace"],
        .dialogue: [.korean: "대사", .japanese: "セリフ", .english: "Dialogue"],
        .instruction: [.korean: "지침", .japanese: "指示", .english: "Direction"],
        .send: [.korean: "입력", .japanese: "送信", .english: "Send"],
        .composerPlaceholderLine: [.korean: "대사를 입력하세요…", .japanese: "セリフを入力…", .english: "Write a line…"],
        .composerPlaceholderNote: [.korean: "지침을 입력하세요…", .japanese: "指示を入力…", .english: "Write a direction…"],
        .characters: [.korean: "캐릭터", .japanese: "キャラクター", .english: "Characters"],
        .addCharacter: [.korean: "캐릭터 추가", .japanese: "キャラクターを追加", .english: "Add Character"],
        .characterName: [.korean: "이름", .japanese: "名前", .english: "Name"],
        .characterRole: [.korean: "역할", .japanese: "役割", .english: "Role"],
        .characterSummary: [.korean: "설명", .japanese: "説明", .english: "Summary"],
        .andOthers: [.korean: "외 %d인", .japanese: "他%d人", .english: "+%d more"],
        .undo: [.korean: "실행 취소", .japanese: "取り消す", .english: "Undo"],
        .redo: [.korean: "다시 실행", .japanese: "やり直す", .english: "Redo"],
        .searchInDocument: [.korean: "문서 내 검색", .japanese: "ドキュメント内検索", .english: "Search in Document"],
        .inspector: [.korean: "인스펙터", .japanese: "インスペクタ", .english: "Inspector"],
        .aiCompose: [.korean: "AI 자동 작성", .japanese: "AI自動作成", .english: "AI Compose"],
        .readOnlyMode: [.korean: "읽기 전용", .japanese: "読み取り専用", .english: "Read-only"],
        .readOnlyOn: [.korean: "읽기 전용 켜기", .japanese: "読み取り専用をオン", .english: "Lock Editing"],
        .readOnlyOff: [.korean: "읽기 전용 끄기", .japanese: "読み取り専用をオフ", .english: "Unlock Editing"],
        .rehearsal: [.korean: "리허설", .japanese: "リハーサル", .english: "Rehearsal"],
        .rehearsalPause: [.korean: "일시 정지", .japanese: "一時停止", .english: "Pause"],
        .rehearsalResume: [.korean: "재개", .japanese: "再開", .english: "Resume"],
        .rehearsalStop: [.korean: "정지", .japanese: "停止", .english: "Stop"],
        .rehearsalSpeed: [.korean: "재생 속도", .japanese: "再生速度", .english: "Playback Speed"],
        .quickOpen: [.korean: "빠른 이동", .japanese: "クイック移動", .english: "Quick Open"],
        .quickOpenPlaceholder: [.korean: "문서 이름·본문·명령 검색…", .japanese: "ドキュメント・本文・コマンドを検索…", .english: "Search documents, content, commands…"],
        .noMatches: [.korean: "일치하는 항목이 없습니다", .japanese: "一致する項目がありません", .english: "No matches"],
        .actionsSection: [.korean: "명령", .japanese: "コマンド", .english: "Commands"],
        .documentsSection: [.korean: "문서", .japanese: "ドキュメント", .english: "Documents"],
        .rehearsalVoice: [.korean: "낭독", .japanese: "朗読", .english: "Read Aloud"],
        .focusMode: [.korean: "포커스 모드", .japanese: "フォーカスモード", .english: "Focus Mode"],
        .focusModeHint: [.korean: "편집 중인 블록만 밝게, 나머지는 흐리게 표시합니다", .japanese: "編集中のブロックだけを明るく表示します", .english: "Dims everything except the block you are editing"],
        .typewriterMode: [.korean: "타자기 모드", .japanese: "タイプライターモード", .english: "Typewriter Mode"],
        .typewriterModeHint: [.korean: "편집 중인 블록을 화면 중앙에 유지합니다", .japanese: "編集中のブロックを画面中央に保ちます", .english: "Keeps the editing block vertically centered"],
        .mindmapAutoInspector: [.korean: "노드 선택 시 인스펙터 자동 열기", .japanese: "ノード選択時にインスペクタを自動表示", .english: "Open inspector when a node is selected"],
        .snapshots: [.korean: "스냅샷", .japanese: "スナップショット", .english: "Snapshots"],
        .takeSnapshot: [.korean: "스냅샷 찍기", .japanese: "スナップショットを撮る", .english: "Take Snapshot"],
        .snapshotNamePlaceholder: [.korean: "스냅샷 이름 (예: 초고)", .japanese: "スナップショット名（例：初稿）", .english: "Snapshot name (e.g. First draft)"],
        .compare: [.korean: "비교", .japanese: "比較", .english: "Compare"],
        .beforeRestoreSnapshot: [.korean: "복원 전 상태", .japanese: "復元前の状態", .english: "Before restore"],
        .diffAdded: [.korean: "추가됨", .japanese: "追加", .english: "Added"],
        .diffRemoved: [.korean: "삭제됨", .japanese: "削除", .english: "Removed"],
        .diffChanged: [.korean: "변경됨", .japanese: "変更", .english: "Changed"],
        .noSnapshots: [.korean: "아직 스냅샷이 없습니다 — 큰 수정 전에 찍어두세요", .japanese: "まだスナップショットがありません", .english: "No snapshots yet — take one before big edits"],
        .restoreSnapshotConfirm: [.korean: "이 스냅샷으로 복원할까요? 현재 상태는 \'복원 전 상태\' 스냅샷으로 자동 보관됩니다.", .japanese: "このスナップショットに復元しますか？現在の状態は自動保管されます。", .english: "Restore this snapshot? The current state is kept automatically."],
        .noDifferences: [.korean: "차이가 없습니다", .japanese: "差分はありません", .english: "No differences"],
        .snapshotOnSave: [.korean: "수동 저장 시 자동 스냅샷", .japanese: "手動保存時に自動スナップショット", .english: "Snapshot on manual save"],
        .snapshotOnSaveHint: [.korean: "⌘S로 저장할 때마다 스냅샷을 남깁니다. 자동 스냅샷은 문서당 최근 10개만 보관됩니다.", .japanese: "⌘Sで保存するたびにスナップショットを残します。自動分は最新10件のみ保管。", .english: "Takes a snapshot every time you save with ⌘S. Only the 10 most recent automatic snapshots are kept per document."],
        .writingGoal: [.korean: "일일 집필 목표", .japanese: "1日の執筆目標", .english: "Daily Writing Goal"],
        .charsUnit: [.korean: "자", .japanese: "文字", .english: " chars"],
        .goalReached: [.korean: "오늘 목표 달성!", .japanese: "今日の目標達成！", .english: "Goal reached today!"],
        .streakDays: [.korean: "연속 %d일", .japanese: "連続%d日", .english: "%d-day streak"],
        .aiSuggesting: [.korean: "AI가 이어쓰는 중…", .japanese: "AIが続きを作成中…", .english: "AI is drafting…"],
        .acceptAll: [.korean: "모두 반영", .japanese: "すべて反映", .english: "Accept All"],
        .dismissAll: [.korean: "모두 무시", .japanese: "すべて破棄", .english: "Dismiss All"],
        .accept: [.korean: "반영", .japanese: "反映", .english: "Accept"],
        .archive: [.korean: "파일 아카이브", .japanese: "ファイルアーカイブ", .english: "File Archive"],
        .allDocuments: [.korean: "전체", .japanese: "すべて", .english: "All"],
        .sortBy: [.korean: "정렬", .japanese: "並べ替え", .english: "Sort By"],
        .sortName: [.korean: "이름", .japanese: "名前", .english: "Name"],
        .sortModified: [.korean: "수정일", .japanese: "変更日", .english: "Date Modified"],
        .sortKind: [.korean: "종류", .japanese: "種類", .english: "Kind"],
        .viewList: [.korean: "리스트", .japanese: "リスト", .english: "List"],
        .viewGrid: [.korean: "그리드", .japanese: "グリッド", .english: "Grid"],
        .openBehavior: [.korean: "파일 열기 방식", .japanese: "ファイルを開く操作", .english: "Open Items With"],
        .singleClick: [.korean: "싱글 클릭", .japanese: "シングルクリック", .english: "Single Click"],
        .doubleClick: [.korean: "더블 클릭", .japanese: "ダブルクリック", .english: "Double Click"],
        .branch: [.korean: "분기", .japanese: "分岐", .english: "Branch"],
        .mainRoute: [.korean: "본편", .japanese: "本編", .english: "Main Route"],
        .newBranch: [.korean: "새 분기", .japanese: "新規分岐", .english: "New Branch"],
        .branchFromHere: [.korean: "여기서 분기 만들기", .japanese: "ここから分岐を作成", .english: "Branch From Here"],
        .branchPoint: [.korean: "분기점", .japanese: "分岐点", .english: "Branch Point"],
        .backToMain: [.korean: "본편으로", .japanese: "本編へ戻る", .english: "Back to Main"],
        .blockImage: [.korean: "이미지", .japanese: "画像", .english: "Image"],
        .blockTable: [.korean: "표", .japanese: "テーブル", .english: "Table"],
        .chooseImage: [.korean: "이미지 선택…", .japanese: "画像を選択…", .english: "Choose Image…"],
        .embedURL: [.korean: "URL 임베드", .japanese: "URLを埋め込む", .english: "Embed URL"],
        .aspectOriginal: [.korean: "원본 비율", .japanese: "元の比率", .english: "Original Ratio"],
        .enlarge: [.korean: "확대 보기", .japanese: "拡大表示", .english: "Enlarge"],
        .addRow: [.korean: "행 추가", .japanese: "行を追加", .english: "Add Row"],
        .addColumn: [.korean: "열 추가", .japanese: "列を追加", .english: "Add Column"],
        .showAsIcon: [.korean: "아이콘으로 표시", .japanese: "アイコンで表示", .english: "Show as Icon"],
        .importFromProject: [.korean: "프로젝트에서 가져오기", .japanese: "プロジェクトから読み込む", .english: "Import from Project"],
        .references: [.korean: "참조", .japanese: "参照", .english: "References"],
        .backlinks: [.korean: "백링크", .japanese: "バックリンク", .english: "Backlinks"],
        .addReference: [.korean: "참조 추가", .japanese: "参照を追加", .english: "Add Reference"],
        .properties: [.korean: "속성", .japanese: "プロパティ", .english: "Properties"],
        .noReferences: [.korean: "연결된 항목이 없습니다", .japanese: "リンクされた項目はありません", .english: "No linked items"],
        .createdAt: [.korean: "생성일", .japanese: "作成日", .english: "Created"],
        .modifiedAt: [.korean: "수정일", .japanese: "変更日", .english: "Modified"],
        .exportHTML: [.korean: "HTML 내보내기", .japanese: "HTMLを書き出す", .english: "Export HTML"],
        .exportPDF: [.korean: "PDF 내보내기", .japanese: "PDFを書き出す", .english: "Export PDF"],
        .effectDotSize: [.korean: "도트 크기", .japanese: "ドットサイズ", .english: "Dot Size"],
        .effectPitch: [.korean: "시점 각도", .japanese: "視点角度", .english: "View Angle"],
        .effectColor: [.korean: "도트 색", .japanese: "ドットの色", .english: "Dot Color"],
        .followTheme: [.korean: "테마", .japanese: "テーマ", .english: "Theme"],
        .emptyWorkspaceTitle: [.korean: "창작을 시작해보세요", .japanese: "創作を始めましょう", .english: "Start creating"],
        .emptyWorkspaceBody: [.korean: "프로젝트는 세계관과 캐릭터를 함께 담는 폴더예요. 시나리오·마인드맵·페이지가 그 안에서 서로 연결됩니다.", .japanese: "プロジェクトは世界観とキャラクターをまとめるフォルダです。シナリオ・マインドマップ・ページが互いにつながります。", .english: "A project is a folder that holds your world and characters. Scenarios, mind maps, and pages connect inside it."],
        .createFirstProject: [.korean: "첫 프로젝트 만들기", .japanese: "最初のプロジェクトを作成", .english: "Create First Project"],
        .emptyCategory: [.korean: "이 카테고리에 문서가 없습니다", .japanese: "このカテゴリにドキュメントはありません", .english: "No documents in this category"],
        .adjustCrop: [.korean: "크롭 조정…", .japanese: "切り抜きを調整…", .english: "Adjust Crop…"],
        .interfaceStyle: [.korean: "스타일", .japanese: "スタイル", .english: "Style"],
        .themeSonnet: [.korean: "Sonnet", .japanese: "Sonnet", .english: "Sonnet"],
        .themePilgrimage: [.korean: "Pilgrimage", .japanese: "Pilgrimage", .english: "Pilgrimage"],
        .fontLabel: [.korean: "글꼴", .japanese: "フォント", .english: "Font"],
        .fontPretendard: [.korean: "Pretendard", .japanese: "Pretendard", .english: "Pretendard"],
        .fontSystem: [.korean: "시스템", .japanese: "システム", .english: "System"],
        .fontSerif: [.korean: "세리프", .japanese: "セリフ", .english: "Serif"],
        .fontMono: [.korean: "모노", .japanese: "モノ", .english: "Mono"],
        .disableGlass: [.korean: "Liquid Glass 비활성화 (평면 표면)", .japanese: "Liquid Glassを無効化（フラット表面）", .english: "Disable Liquid Glass (flat surfaces)"],
        .blockSpacing: [.korean: "블록 간격", .japanese: "ブロック間隔", .english: "Block Spacing"],
        .uiScale: [.korean: "전체 크기", .japanese: "全体サイズ", .english: "UI Scale"],
        .tabStyle: [.korean: "탭 스타일", .japanese: "タブスタイル", .english: "Tab Style"],
        .tabStyleCapsule: [.korean: "캡슐", .japanese: "カプセル", .english: "Capsule"],
        .tabStyleChrome: [.korean: "사각 (Chrome)", .japanese: "四角 (Chrome)", .english: "Square (Chrome)"],
        .inspectorPosition: [.korean: "캐릭터 인스펙터 위치", .japanese: "キャラクターインスペクタの位置", .english: "Character Inspector Position"],
        .positionLeft: [.korean: "왼쪽", .japanese: "左", .english: "Left"],
        .positionRight: [.korean: "오른쪽", .japanese: "右", .english: "Right"],
        .importAny: [.korean: "프로젝트/파일 불러오기", .japanese: "プロジェクト/ファイルを読み込む", .english: "Import Project/File"],
        .aiAgent: [.korean: "AI 에이전트", .japanese: "AIエージェント", .english: "AI Agent"],
        // 브랜드명이라 언어별로 옮기지 않고 그대로 사용
        .sonnetAI: [.korean: "Sonnet AI", .japanese: "Sonnet AI", .english: "Sonnet AI"],
        .askAnything: [.korean: "무엇이든 물어보세요…", .japanese: "何でも聞いてください…", .english: "Ask anything…"],
        .openAsTab: [.korean: "탭으로 열기", .japanese: "タブで開く", .english: "Open as Tab"],
        .clearChat: [.korean: "대화 지우기", .japanese: "会話をクリア", .english: "Clear Chat"],
        .touchBarSupport: [.korean: "Touch Bar 지원", .japanese: "Touch Barサポート", .english: "Touch Bar Support"],
        .touchBarFunctions: [.korean: "제공 기능", .japanese: "提供される機能", .english: "Available Functions"],
        .profileTab: [.korean: "프로필", .japanese: "プロフィール", .english: "Profile"],
        .notesTab: [.korean: "노트", .japanese: "ノート", .english: "Notes"],
        .relationsTab: [.korean: "관계", .japanese: "関係", .english: "Relations"],
        .galleryTab: [.korean: "갤러리", .japanese: "ギャラリー", .english: "Gallery"],
        .voiceTab: [.korean: "보이스", .japanese: "ボイス", .english: "Voice"],
        .addField: [.korean: "속성 추가", .japanese: "属性を追加", .english: "Add Field"],
        .fieldName: [.korean: "속성", .japanese: "属性", .english: "Field"],
        .fieldValue: [.korean: "값", .japanese: "値", .english: "Value"],
        .addRelation: [.korean: "관계 추가", .japanese: "関係を追加", .english: "Add Relation"],
        .relationLabel: [.korean: "관계 (예: 연인, 숙적)", .japanese: "関係（例：恋人、宿敵）", .english: "Relation (e.g. lover, rival)"],
        .addImage: [.korean: "이미지 추가", .japanese: "画像を追加", .english: "Add Image"],
        .phaseTag: [.korean: "시점/상태", .japanese: "時点/状態", .english: "Phase/State"],
        .captionLabel: [.korean: "설명", .japanese: "説明", .english: "Caption"],
        .voiceTone: [.korean: "말투", .japanese: "話し方", .english: "Tone"],
        .voiceTaboo: [.korean: "금기 (쓰지 않는 말)", .japanese: "禁句", .english: "Taboo"],
        .voiceSamples: [.korean: "예시 대사", .japanese: "セリフ例", .english: "Sample Lines"],
        .addVoiceCard: [.korean: "보이스 카드 추가", .japanese: "ボイスカードを追加", .english: "Add Voice Card"],
        .addSample: [.korean: "예시 추가", .japanese: "例を追加", .english: "Add Sample"],
        .appearances: [.korean: "등장 기록", .japanese: "登場記録", .english: "Appearances"],
        .linesCountFormat: [.korean: "대사 %d개", .japanese: "セリフ%d件", .english: "%d lines"],
        .editProfileImage: [.korean: "프로필 이미지 편집", .japanese: "プロフィール画像を編集", .english: "Edit Profile Image"],
        .settingsAppearance: [.korean: "모양", .japanese: "外観", .english: "Appearance"],
        .settingsEditor: [.korean: "에디터", .japanese: "エディタ", .english: "Editor"],
        .deleteProject: [.korean: "프로젝트 삭제", .japanese: "プロジェクトを削除", .english: "Delete Project"],
        .trashConfirmMessage: [.korean: "이 문서를 휴지통으로 이동할까요?", .japanese: "このドキュメントをゴミ箱に移動しますか？", .english: "Move this document to Trash?"],
        .projectDeleteMessage: [.korean: "프로젝트 폴더 전체(포함된 문서 포함)가 Finder 휴지통으로 이동합니다.", .japanese: "プロジェクトフォルダ全体（含まれるドキュメントを含む）がFinderのゴミ箱に移動します。", .english: "The entire project folder (including its documents) will move to the Finder Trash."],
        .profilePage: [.korean: "프로필", .japanese: "プロフィール", .english: "Profile"],
        .contributions: [.korean: "기여도", .japanese: "アクティビティ", .english: "Contributions"],
        .activityEmpty: [.korean: "아직 기록된 활동이 없습니다 — 문서를 저장하면 채워집니다", .japanese: "まだ活動記録がありません — 保存すると記録されます", .english: "No activity yet — it fills in as you save"],
        .spacingCompact: [.korean: "좁게", .japanese: "狭い", .english: "Compact"],
        .spacingMedium: [.korean: "중간", .japanese: "中", .english: "Medium"],
        .spacingWide: [.korean: "넓게", .japanese: "広い", .english: "Wide"],
        .dialogueDisplayHeader: [.korean: "대사 블록 캐릭터 표시", .japanese: "セリフブロックのキャラクター表示", .english: "Dialogue Character Display"],
        .dialogueDisplayMethod: [.korean: "표시 방법", .japanese: "表示方法", .english: "Display Method"],
        .dialogueDisplayBoth: [.korean: "프로필+이름", .japanese: "プロフィール+名前", .english: "Avatar + Name"],
        .dialogueDisplayAvatarOnly: [.korean: "프로필만", .japanese: "プロフィールのみ", .english: "Avatar Only"],
        .dialogueDisplayNameOnly: [.korean: "이름만", .japanese: "名前のみ", .english: "Name Only"],
        .dialogueDisplayHidden: [.korean: "숨김", .japanese: "非表示", .english: "Hidden"],
        .dialogueAvatarSize: [.korean: "캐릭터 프로필 크기", .japanese: "キャラクタープロフィールのサイズ", .english: "Character Avatar Size"],
        .inbox: [.korean: "수신함", .japanese: "受信トレイ", .english: "Inbox"],
        .eventImported: [.korean: "가져옴", .japanese: "読み込み", .english: "Imported"],
        .eventExported: [.korean: "내보냄", .japanese: "書き出し", .english: "Exported"],
        .eventBackedUp: [.korean: "백업 생성", .japanese: "バックアップ作成", .english: "Backed Up"],
        .eventRestored: [.korean: "백업 복원", .japanese: "バックアップ復元", .english: "Restored"],
        .eventProjectDeleted: [.korean: "프로젝트 삭제", .japanese: "プロジェクト削除", .english: "Project Deleted"],
        .sideBySideToggle: [.korean: "다음 블록과 나란히", .japanese: "次のブロックと横並び", .english: "Side by Side with Next"],
        .imageWidth: [.korean: "너비", .japanese: "幅", .english: "Width"],
        .imageAlign: [.korean: "정렬", .japanese: "配置", .english: "Align"],
        .alignLeft: [.korean: "왼쪽", .japanese: "左", .english: "Left"],
        .alignCenter: [.korean: "가운데", .japanese: "中央", .english: "Center"],
        .alignRight: [.korean: "오른쪽", .japanese: "右", .english: "Right"],
        .pasteImage: [.korean: "클립보드 붙여넣기", .japanese: "クリップボードから貼り付け", .english: "Paste from Clipboard"],
        .aboutMe: [.korean: "소개", .japanese: "自己紹介", .english: "About"],
        .recentlyDeleted: [.korean: "최근 지워진 항목", .japanese: "最近削除した項目", .english: "Recently Deleted"],
        .choosePhoto: [.korean: "사진 선택…", .japanese: "写真を選択…", .english: "Choose Photo…"],
        .removePhoto: [.korean: "사진 제거", .japanese: "写真を削除", .english: "Remove Photo"],
        .viewProfile: [.korean: "프로필 보기", .japanese: "プロフィールを見る", .english: "View Profile"],
        .authRequiredHidden: [.korean: "가려진 항목을 보려면 인증이 필요합니다", .japanese: "非表示項目の閲覧には認証が必要です", .english: "Authentication required to view hidden items"],
        .authRequiredTrash: [.korean: "휴지통에 접근하려면 인증이 필요합니다", .japanese: "ゴミ箱へのアクセスには認証が必要です", .english: "Authentication required to access Trash"],
        .authReason: [.korean: "보호된 항목에 접근", .japanese: "保護された項目へのアクセス", .english: "Access protected items"],
        .unlocked: [.korean: "잠금 해제됨", .japanese: "ロック解除済み", .english: "Unlocked"],
        .profile: [.korean: "작업자", .japanese: "作成者", .english: "Author"],
        .workspace: [.korean: "워크스페이스", .japanese: "ワークスペース", .english: "Workspace"],
        .documents: [.korean: "문서", .japanese: "ドキュメント", .english: "Documents"],
        .untitled: [.korean: "제목 없음", .japanese: "無題", .english: "Untitled"],
        .editContent: [.korean: "내용 수정", .japanese: "内容を編集", .english: "Edit Content"],
        .addNode: [.korean: "노드 추가", .japanese: "ノードを追加", .english: "Add Node"],
        .nodeText: [.korean: "텍스트", .japanese: "テキスト", .english: "Text"],
        .nodePage: [.korean: "페이지", .japanese: "ページ", .english: "Page"],
        .nodeImage: [.korean: "이미지", .japanese: "画像", .english: "Image"],
        .nodeFile: [.korean: "파일", .japanese: "ファイル", .english: "File"],
        .edgeCaption: [.korean: "연결선 캡션", .japanese: "接続キャプション", .english: "Edge Caption"],
        .zoomReset: [.korean: "확대 초기화", .japanese: "ズームをリセット", .english: "Reset Zoom"],
        .blockParagraph: [.korean: "본문", .japanese: "本文", .english: "Text"],
        .blockHeading1: [.korean: "제목 1", .japanese: "見出し1", .english: "Heading 1"],
        .blockHeading2: [.korean: "제목 2", .japanese: "見出し2", .english: "Heading 2"],
        .blockHeading3: [.korean: "제목 3", .japanese: "見出し3", .english: "Heading 3"],
        .blockBulleted: [.korean: "글머리 기호 목록", .japanese: "箇条書きリスト", .english: "Bulleted List"],
        .blockNumbered: [.korean: "번호 매기기 목록", .japanese: "番号付きリスト", .english: "Numbered List"],
        .blockTask: [.korean: "할 일", .japanese: "ToDo", .english: "To-do"],
        .blockToggle: [.korean: "토글", .japanese: "トグル", .english: "Toggle"],
        .blockQuote: [.korean: "인용", .japanese: "引用", .english: "Quote"],
        .blockCode: [.korean: "코드", .japanese: "コード", .english: "Code"],
        .blockDivider: [.korean: "구분선", .japanese: "区切り線", .english: "Divider"],
        .blockCallout: [.korean: "콜아웃", .japanese: "コールアウト", .english: "Callout"],
        .slashHint: [.korean: "'/'를 입력해 블록 전환", .japanese: "「/」でブロックを変換", .english: "Type '/' for commands"],
        .exportMarkdown: [.korean: "Markdown 내보내기", .japanese: "Markdownを書き出す", .english: "Export Markdown"],
        .importMarkdown: [.korean: "Markdown 가져오기", .japanese: "Markdownを読み込む", .english: "Import Markdown"],
        .saveStateSaved: [.korean: "저장됨", .japanese: "保存済み", .english: "Saved"],
        .saveStateSaving: [.korean: "저장 중", .japanese: "保存中", .english: "Saving"],
        .saveStateUnsaved: [.korean: "저장 안 됨", .japanese: "未保存", .english: "Unsaved"],
        .saveStateError: [.korean: "저장 오류", .japanese: "保存エラー", .english: "Save Error"],
        .emptyEditorHint: [.korean: "아래 입력기에서 첫 블록을 작성해보세요", .japanese: "下の入力欄から最初のブロックを作成しましょう", .english: "Write your first block from the composer below"],
        .doubleClickToCreate: [.korean: "빈 공간을 더블 클릭해 노드 생성", .japanese: "空白をダブルクリックでノード作成", .english: "Double-click empty space to create a node"],
        .dropHere: [.korean: "여기에 놓기", .japanese: "ここにドロップ", .english: "Drop here"],
        .today: [.korean: "오늘", .japanese: "今日", .english: "Today"],
        .greeting: [.korean: "무엇을 창작해볼까요?", .japanese: "今日は何を創りますか？", .english: "What shall we create?"],
        .permanentDelete: [.korean: "영구 삭제", .japanese: "完全に削除", .english: "Delete Permanently"],
        .permanentDeleteConfirmMessage: [.korean: "이 문서를 영구 삭제할까요? 이 작업은 되돌릴 수 없습니다.", .japanese: "このドキュメントを完全に削除しますか？この操作は元に戻せません。", .english: "Permanently delete this document? This cannot be undone."],
        .permanentDeleteConfirmMessagePlural: [.korean: "선택한 항목을 영구 삭제할까요? 이 작업은 되돌릴 수 없습니다.", .japanese: "選択した項目を完全に削除しますか？この操作は元に戻せません。", .english: "Permanently delete the selected items? This cannot be undone."],
        .emptyTrashAction: [.korean: "휴지통 비우기", .japanese: "ゴミ箱を空にする", .english: "Empty Trash"],
        .emptyTrashConfirmMessage: [.korean: "휴지통의 모든 항목을 영구 삭제할까요? 이 작업은 되돌릴 수 없습니다.", .japanese: "ゴミ箱の全項目を完全に削除しますか？この操作は元に戻せません。", .english: "Permanently delete everything in Trash? This cannot be undone."],
        .sortTrashedDate: [.korean: "삭제된 순", .japanese: "削除日順", .english: "Date Deleted"],
        .trashedOn: [.korean: "삭제됨", .japanese: "削除済み", .english: "Deleted"],
        .originalLocation: [.korean: "원래 위치", .japanese: "元の場所", .english: "Original Location"],
        .restoredToWorkspaceRoot: [.korean: "원래 위치가 사라져 최상위 폴더로 복원했습니다", .japanese: "元の場所が見つからず最上位フォルダに復元しました", .english: "Original location was gone — restored to the workspace root instead"],
        .emptyHiddenItems: [.korean: "가려진 항목이 없습니다", .japanese: "非表示の項目はありません", .english: "No hidden items"],
        .emptyTrashItems: [.korean: "휴지통이 비어 있습니다", .japanese: "ゴミ箱は空です", .english: "Trash is empty"],
        .emptyOtherFiles: [.korean: "기타 파일이 없습니다", .japanese: "その他のファイルはありません", .english: "No other files"],
        .hideFinderHint: [.korean: "가려진 항목은 Finder에서도 함께 숨겨집니다", .japanese: "非表示にした項目はFinderでも隠れます", .english: "Hidden items are also hidden in Finder"],
        .otherFiles: [.korean: "기타", .japanese: "その他", .english: "Other"],
        .viewOnlyHint: [.korean: "보기 전용 — 더블 클릭하면 Finder에서 엽니다", .japanese: "閲覧専用 — ダブルクリックでFinderで開きます", .english: "View only — double-click to open in Finder"],
        .revealInFinder: [.korean: "Finder에서 보기", .japanese: "Finderで表示", .english: "Reveal in Finder"],
        .allProjects: [.korean: "전체 프로젝트", .japanese: "すべてのプロジェクト", .english: "All Projects"],
        .openProjectArchive: [.korean: "프로젝트 아카이브 열기", .japanese: "プロジェクトアーカイブを開く", .english: "Open Project Archive"],
        .selectedCountFormat: [.korean: "%d개 선택됨", .japanese: "%d件選択中", .english: "%d selected"],
        .deselectAll: [.korean: "선택 해제", .japanese: "選択解除", .english: "Deselect All"],
        .selectAll: [.korean: "전체 선택", .japanese: "すべて選択", .english: "Select All"],
        .showAllFormat: [.korean: "모두 보기 (%d)", .japanese: "すべて表示 (%d)", .english: "Show All (%d)"],
        .navigateBack: [.korean: "뒤로 이동", .japanese: "戻る", .english: "Back"],
        .navigateForward: [.korean: "앞으로 이동", .japanese: "進む", .english: "Forward"],
        .errorOpenTitle: [.korean: "문서를 열 수 없습니다", .japanese: "ドキュメントを開けません", .english: "Can't Open Document"],
        .errorCorruptedContent: [.korean: "문서 내용이 손상되어 열 수 없습니다. 원본은 그대로 보존됩니다 — 문서 번들 안의 snapshots/ 또는 백업 타임라인에서 복구할 수 있습니다.", .japanese: "ドキュメントの内容が破損しているため開けません。原本はそのまま保持されます — バンドル内のsnapshots/またはバックアップから復元できます。", .english: "The document's content is corrupted and can't be opened. The original file is left untouched — you can recover from the bundle's snapshots/ folder or a backup."],
        .errorDocumentMissing: [.korean: "문서 파일을 찾을 수 없습니다. 이동되었거나 아직 저장되지 않은 문서일 수 있습니다.", .japanese: "ドキュメントファイルが見つかりません。移動されたか、まだ保存されていない可能性があります。", .english: "The document file could not be found. It may have been moved or never saved."],
        .errorOpenGeneric: [.korean: "문서를 여는 중 오류가 발생했습니다.", .japanese: "ドキュメントを開く際にエラーが発生しました。", .english: "An error occurred while opening the document."],
        .saveFailedCloseTitle: [.korean: "저장하지 못했습니다", .japanese: "保存できませんでした", .english: "Couldn't Save"],
        .saveFailedCloseMessage: [.korean: "이 문서를 저장하지 못했습니다. 저장하지 않고 닫으면 최근 변경 내용이 사라집니다.", .japanese: "このドキュメントを保存できませんでした。保存せずに閉じると最近の変更が失われます。", .english: "This document could not be saved. Closing without saving will discard your recent changes."],
        .retrySave: [.korean: "다시 시도", .japanese: "再試行", .english: "Try Again"],
        .closeWithoutSaving: [.korean: "저장하지 않고 닫기", .japanese: "保存せずに閉じる", .english: "Close Without Saving"],
        .saveFailedQuitTitle: [.korean: "저장하지 못한 문서가 있습니다", .japanese: "保存できなかったドキュメントがあります", .english: "Some Documents Couldn't Be Saved"],
        .saveFailedQuitMessage: [.korean: "일부 문서를 저장하지 못했습니다. 지금 종료하면 최근 변경 내용이 사라집니다.", .japanese: "一部のドキュメントを保存できませんでした。今終了すると最近の変更が失われます。", .english: "Some documents could not be saved. Quitting now will discard those recent changes."],
        .quitAnyway: [.korean: "그래도 종료", .japanese: "終了する", .english: "Quit Anyway"],
        .restoreClosesTabsMessage: [.korean: "복원하면 열려 있는 문서 탭이 모두 닫히고 워크스페이스가 선택한 시점으로 교체됩니다.", .japanese: "復元すると開いているドキュメントタブがすべて閉じられ、ワークスペースが選択した時点に置き換えられます。", .english: "Restoring closes all open document tabs and replaces the workspace with the selected snapshot."],
        .eventBackupFailed: [.korean: "백업 실패", .japanese: "バックアップ失敗", .english: "Backup failed"],
        .eventImportFailed: [.korean: "가져오기 실패", .japanese: "読み込み失敗", .english: "Import failed"],
        .eventExportFailed: [.korean: "내보내기 실패", .japanese: "書き出し失敗", .english: "Export failed"],
        .backupRunning: [.korean: "백업 중…", .japanese: "バックアップ中…", .english: "Backing up…"],
        .restoreRunning: [.korean: "복원 중…", .japanese: "復元中…", .english: "Restoring…"],
        .projectFiles: [.korean: "프로젝트 파일", .japanese: "プロジェクトファイル", .english: "Project Files"],
        .recoverFromSnapshot: [.korean: "최근 스냅샷에서 복구", .japanese: "最新スナップショットから復元", .english: "Recover from Latest Snapshot"],
        .eventRecovered: [.korean: "스냅샷에서 복구됨", .japanese: "スナップショットから復元しました", .english: "Recovered from snapshot"],
        .exportText: [.korean: "텍스트 내보내기", .japanese: "テキストを書き出す", .english: "Export Text"],
        .exportScript: [.korean: "대본 내보내기", .japanese: "台本を書き出す", .english: "Export Script"],
        .sceneList: [.korean: "씬 목차", .japanese: "シーン一覧", .english: "Scenes"],
        .sceneFormat: [.korean: "장면 %d", .japanese: "シーン%d", .english: "Scene %d"],
        .weeklyReport: [.korean: "주간 집필", .japanese: "週間執筆", .english: "This Week"],
        .weeklyTotal: [.korean: "7일 합계", .japanese: "7日間合計", .english: "7-day total"],
        .weeklyBestDay: [.korean: "최고 기록", .japanese: "ベスト", .english: "Best day"],
        .vsLastWeek: [.korean: "지난주 대비", .japanese: "先週比", .english: "vs last week"],
        .updates: [.korean: "업데이트", .japanese: "アップデート", .english: "Updates"],
        .updateAvailableFormat: [.korean: "새 버전 v%@ 사용 가능 — 설치할 수 있습니다", .japanese: "新バージョン v%@ が利用可能です", .english: "Version %@ is available"],
        .updateCheckNow: [.korean: "지금 확인", .japanese: "今すぐ確認", .english: "Check Now"],
        .updateAutoCheck: [.korean: "자동으로 업데이트 확인", .japanese: "自動でアップデートを確認", .english: "Check for updates automatically"],
        .updateUpToDate: [.korean: "최신 버전입니다", .japanese: "最新バージョンです", .english: "You're up to date"],
        .updateDownload: [.korean: "다운로드 및 열기", .japanese: "ダウンロードして開く", .english: "Download & Open"],
        .updateViewRelease: [.korean: "릴리스 페이지 열기", .japanese: "リリースページを開く", .english: "View Release Page"],
        .updateSkipVersion: [.korean: "이 버전 건너뛰기", .japanese: "このバージョンをスキップ", .english: "Skip This Version"],
        .updateCurrentFormat: [.korean: "현재 v%@", .japanese: "現在 v%@", .english: "Current v%@"],
        .updateDownloadFailed: [.korean: "업데이트 다운로드 실패", .japanese: "アップデートのダウンロードに失敗", .english: "Update download failed"],
        .aiSphereStyle: [.korean: "AI 스피어 스타일", .japanese: "AIスフィアのスタイル", .english: "AI Sphere Style"],
        .sphereStyleGlass: [.korean: "글래스", .japanese: "ガラス", .english: "Glass"],
        .sphereStyleHolographic: [.korean: "홀로그램", .japanese: "ホログラム", .english: "Holographic"],
        .sphereStyleInk: [.korean: "잉크", .japanese: "インク", .english: "Ink"],
        .sphereStylePlasma: [.korean: "플라즈마", .japanese: "プラズマ", .english: "Plasma"],
        .sphereStyleParticle: [.korean: "파티클", .japanese: "パーティクル", .english: "Particle"],
        .greetingMorning: [.korean: "좋은 아침이에요. 무엇을 써볼까요?", .japanese: "おはようございます。何を書きましょう？", .english: "Good morning. What shall we write?"],
        .greetingAfternoon: [.korean: "무엇을 창작해볼까요?", .japanese: "今日は何を創りますか？", .english: "What shall we create?"],
        .greetingEvening: [.korean: "저녁이네요. 오늘의 이야기를 이어가볼까요?", .japanese: "夜ですね。今日の物語を続けましょうか？", .english: "Good evening. Shall we continue the story?"],
        .greetingNight: [.korean: "깊은 밤, 영감이 찾아오는 시간이에요.", .japanese: "深い夜、インスピレーションが訪れる時間です。", .english: "Late night — when inspiration comes."],
        .greetingMorningNamed: [.korean: "좋은 아침이에요, %@ 님. 무엇을 써볼까요?", .japanese: "おはようございます、%@さん。何を書きましょう？", .english: "Good morning, %@. What shall we write?"],
        .greetingAfternoonNamed: [.korean: "%@ 님, 무엇을 창작해볼까요?", .japanese: "%@さん、今日は何を創りますか？", .english: "%@, what shall we create?"],
        .greetingEveningNamed: [.korean: "저녁이네요, %@ 님. 오늘의 이야기를 이어가볼까요?", .japanese: "夜ですね、%@さん。今日の物語を続けましょうか？", .english: "Good evening, %@. Shall we continue the story?"],
        .greetingNightNamed: [.korean: "깊은 밤이에요, %@ 님. 영감이 찾아오는 시간이죠.", .japanese: "深い夜ですね、%@さん。インスピレーションが訪れる時間です。", .english: "Late night, %@ — when inspiration comes."],
        .sphereDensity: [.korean: "입자 밀도", .japanese: "パーティクル密度", .english: "Particle Density"],
        .sphereDensitySparse: [.korean: "성기게", .japanese: "疎", .english: "Sparse"],
        .sphereDensityNormal: [.korean: "보통", .japanese: "標準", .english: "Normal"],
        .sphereDensityDense: [.korean: "촘촘하게", .japanese: "密", .english: "Dense"],
    ]
}
