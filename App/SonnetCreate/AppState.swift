import AIAgentKit
import AppCore
import AppKit
import BackupKit
import DesignSystem
import DocumentKit
import FileManagerKit
import Foundation
import Observation
import RenderingKit
import ScenarioEditor
import SecurityKit
import SettingsKit
import SwiftUI

/// 탭 하나의 내용.
enum TabContent: Hashable {
    case home
    case archive
    case aiChat
    case profile
    case document(UUID)
}

/// AI 에이전트 채팅 세션 (앱 전역 1개, 탭과 사이드패널이 공유).
@MainActor
@Observable
final class AIChatStore {
    var messages: [AIChatMessage] = []
    var input = ""
    var isBusy = false
    /// 현재 타이핑 연출로 노출 중인 어시스턴트 메시지 ID (스크롤 추종·상태 표시용)
    private(set) var streamingMessageID: UUID?

    func send(using provider: any AIProvider) async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        input = ""
        messages.append(AIChatMessage(role: .user, text: text))
        isBusy = true
        do {
            let reply = try await provider.chat(history: messages)
            isBusy = false
            await reveal(reply)
        } catch {
            isBusy = false
            messages.append(AIChatMessage(role: .assistant, text: "⚠️ \(error.localizedDescription)"))
        }
    }

    /// 완성된 응답을 글자 단위로 점진 노출 — 타이핑되는 듯한 연출. 취소(clear) 안전.
    private func reveal(_ full: String) async {
        let message = AIChatMessage(role: .assistant, text: "")
        messages.append(message)
        streamingMessageID = message.id
        defer { streamingMessageID = nil }

        let characters = Array(full)
        // 길이에 따라 스텝 크기를 키워 긴 답변도 과하게 오래 걸리지 않게 (최대 ~2.5초)
        let step = max(1, characters.count / 120)
        var shown = 0
        while shown < characters.count {
            shown = min(characters.count, shown + step)
            guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return } // clear됨
            messages[index].text = String(characters[0..<shown])
            try? await Task.sleep(for: .milliseconds(16))
            if Task.isCancelled { return }
        }
    }

    func clear() {
        messages = []
        streamingMessageID = nil
    }
}

struct OpenTab: Identifiable, Hashable {
    let id = UUID()
    var content: TabContent
}

/// 수신함 이벤트 한 건 (가져오기/백업/복원 등 시스템 알림).
struct InboxEvent: Identifiable, Codable {
    let id: UUID
    let date: Date
    let symbol: String
    let message: String

    init(symbol: String, message: String) {
        id = UUID()
        date = Date()
        self.symbol = symbol
        self.message = message
    }
}

/// 앱 전역 컴포지션 루트 — 모든 모듈을 조립한다.
@MainActor
@Observable
final class AppState {
    // 모듈
    let settings = SettingsStore()
    let governor = QualityGovernor()
    let privacyGate = PrivacyGate()
    let keychain = KeychainStore()
    private(set) var workspace: WorkspaceStore
    private(set) var backupManager: BackupManager

    // 탭
    var tabs: [OpenTab] = [OpenTab(content: .home)]
    var selectedTabID: UUID?
    /// 참조 패널 표시 여부 (문서 탭에서만 의미 있음)
    var showReferencePanel = false
    var showSnapshotPanel = false
    /// 프로젝트 파일 인스펙터 (프로젝트 소속 문서 탭에서만 의미 있음) — 표시 여부는 재시작 후에도 유지
    var showProjectNavigator = UserDefaults.standard.object(forKey: "show-project-navigator") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showProjectNavigator, forKey: "show-project-navigator") }
    }
    /// 탭바에서 드래그 재정렬 중인 탭
    var draggingTabID: UUID?
    /// 윈도우가 전체화면 상태인지 — 헤더 레이아웃과 사이드바 픽셀 필드 배치가 이 값에 따라 갈린다
    var isFullscreen = false

    /// 휴지통 이동 확인 대기 항목 (확인 팝업)
    var pendingTrashItem: DocumentListItem?
    /// 영구 삭제 확인 대기 항목 (단건/다건 공용, 확인 팝업)
    var pendingPermanentDeleteItems: [DocumentListItem] = []
    /// 프로젝트 삭제 확인 대기 (확인 팝업 → Finder 휴지통)
    var pendingDeleteProject: ProjectFolder?
    /// 아카이브 탭을 특정 카테고리+프로젝트로 열기 위한 요청 (소비형)
    var archiveNavigationRequest: ArchiveView.ArchiveNavigationTarget?
    /// 아카이브 탭이 마지막으로 보고한 카테고리/프로젝트 상태 — 필터 변경 없이 탭만 다시 열 때도
    /// 뒤로가기 스택에 이어붙일 수 있도록 기억해둔다.
    private var lastKnownArchiveState: (category: ArchiveView.Category, projectID: UUID?) = (.all, nil)

    // MARK: 뒤로/앞으로 탐색 (편집 되돌리기와 무관 — 탐색 중인 화면의 히스토리)

    /// 하나의 탐색 지점 — 현재 선택된 탭이 무엇을 보여주고 있었는지를 나타낸다.
    enum NavigationStep: Equatable {
        case home
        case archive(category: ArchiveView.Category, projectID: UUID?)
        case aiChat
        case profile
        case document(UUID)
    }

    private(set) var navBackStack: [NavigationStep] = []
    private(set) var navForwardStack: [NavigationStep] = []
    private var currentNavStep: NavigationStep = .home
    /// 되돌아가기/앞으로가기 적용 중에는 재귀적으로 다시 push되지 않도록 막는다.
    private var isRestoringHistory = false

    var canGoBack: Bool { !navBackStack.isEmpty }
    var canGoForward: Bool { !navForwardStack.isEmpty }

    private func pushNavigation(_ step: NavigationStep) {
        guard !isRestoringHistory, step != currentNavStep else { return }
        navBackStack.append(currentNavStep)
        navForwardStack.removeAll()
        currentNavStep = step
    }

    func goBack() {
        guard let previous = navBackStack.popLast() else { return }
        navForwardStack.append(currentNavStep)
        isRestoringHistory = true
        apply(previous)
        currentNavStep = previous
        DispatchQueue.main.async { [weak self] in self?.isRestoringHistory = false }
    }

    func goForward() {
        guard let next = navForwardStack.popLast() else { return }
        navBackStack.append(currentNavStep)
        isRestoringHistory = true
        apply(next)
        currentNavStep = next
        DispatchQueue.main.async { [weak self] in self?.isRestoringHistory = false }
    }

    private func apply(_ step: NavigationStep) {
        switch step {
        case .home: selectOrOpenHome()
        case .aiChat: openAIChatTab()
        case .profile: openProfileTab()
        case .archive(let category, let projectID): openArchiveTab(category: category, project: projectID)
        case .document(let id): openDocument(id: id)
        }
    }

    /// 아카이브 뷰가 카테고리/프로젝트 필터를 바꿀 때마다 호출 — 히스토리에 기록.
    func recordArchiveNav(_ category: ArchiveView.Category, _ projectID: UUID?) {
        lastKnownArchiveState = (category, projectID)
        pushNavigation(.archive(category: category, projectID: projectID))
    }

    /// 헤더 + 메뉴/⌘K의 '새 문서'가 들어갈 프로젝트 — 지금 보고 있는 맥락을 따른다.
    /// 프로젝트로 필터된 아카이브 탭이나 프로젝트 소속 문서 탭에서는 그 프로젝트 안에,
    /// 그 외(홈 등)에서는 워크스페이스 최상위에 만든다.
    var creationTargetProject: ProjectFolder? {
        switch selectedTab?.content {
        case .archive:
            return workspace.project(id: lastKnownArchiveState.projectID)
        case .document(let docID):
            return workspace.project(id: sessions[docID]?.document.envelope.projectID)
        default:
            return nil
        }
    }

    /// 일별 저장 활동 (yyyy-MM-dd → 횟수) — 프로필 기여도 그래프용
    /// 활동·집필 통계 원장 (기여도 그래프 / 집필 목표 카드)
    let stats = StatsLedger()

    /// 수신함 이벤트 (가져오기/백업/복원 등)
    private(set) var inbox: [InboxEvent] = []

    // 열린 문서 세션
    private(set) var sessions: [UUID: DocumentSession] = [:]

    /// AI 에이전트 채팅 (탭·사이드패널 공유)
    let aiChat = AIChatStore()

    /// Touch Bar 지원 (베타)
    let touchBar = TouchBarController()

    // MARK: 업데이트 (GitHub 릴리스 연동 — 로직은 UpdateSystem.swift)

    /// 현재보다 새로운 릴리스 — 탭바 인디케이터/퀵메뉴의 데이터 (nil = 없음)
    var availableUpdate: UpdateInfo?
    var isCheckingUpdate = false
    var isDownloadingUpdate = false

    init() {
        let root = URL(fileURLWithPath: settings.applied.workspacePath, isDirectory: true)
        workspace = WorkspaceStore(rootURL: root)
        backupManager = BackupManager(workspaceRoot: root)
        selectedTabID = tabs.first?.id

        Localizer.shared.language = settings.applied.language
        governor.userPreference = settings.applied.quality

        settings.persistAPIKey = { [keychain] key in
            keychain.save(key, for: "anthropic-api-key")
        }
        settings.loadAPIKey = { [keychain] in
            keychain.read("anthropic-api-key") ?? ""
        }
        settings.onApply = { [weak self] applied in
            self?.applySettings(applied)
        }
        touchBar.appState = self
        stats.load(rootURL: workspace.rootURL)
        loadInbox()

        if settings.applied.autoCheckUpdates {
            checkForUpdates()
        }
    }

    private func applySettings(_ applied: AppSettings) {
        Localizer.shared.language = applied.language
        governor.userPreference = applied.quality
        let newRoot = URL(fileURLWithPath: applied.workspacePath, isDirectory: true)
        if newRoot != workspace.rootURL {
            flushAllSessions()
            sessions.removeAll()
            tabs = [OpenTab(content: .home)]
            selectedTabID = tabs.first?.id
            workspace.setRoot(newRoot)
            backupManager = BackupManager(workspaceRoot: newRoot)
            stats.load(rootURL: workspace.rootURL)
            loadInbox()
        }
        for session in sessions.values {
            session.autosaveEnabled = applied.autosave
        }
        touchBar.setEnabled(applied.touchBarEnabled)
    }

    // MARK: 탭

    var selectedTab: OpenTab? {
        tabs.first { $0.id == selectedTabID }
    }

    var isHomeSelected: Bool {
        if case .home = selectedTab?.content { return true }
        return false
    }

    func selectOrOpenHome() {
        if let existing = tabs.first(where: { $0.content == .home }) {
            selectedTabID = existing.id
        } else {
            let tab = OpenTab(content: .home)
            tabs.insert(tab, at: 0)
            selectedTabID = tab.id
        }
        pushNavigation(.home)
    }

    func openAIChatTab() {
        openSingletonTab(.aiChat)
        pushNavigation(.aiChat)
    }

    func openProfileTab() {
        openSingletonTab(.profile)
        pushNavigation(.profile)
    }

    /// 아카이브 탭 열기 — 카테고리 지정 시 해당 카테고리로 (가림/휴지통 바로가기), 프로젝트 지정 시 해당 프로젝트로 필터링.
    /// 둘 다 생략하면 마지막으로 보고 있던 카테고리/프로젝트 상태 그대로 연다.
    func openArchiveTab(category: ArchiveView.Category? = nil, project: UUID? = nil) {
        let targetCategory = category ?? lastKnownArchiveState.category
        let targetProject = category != nil ? project : lastKnownArchiveState.projectID
        archiveNavigationRequest = ArchiveView.ArchiveNavigationTarget(category: targetCategory, projectID: targetProject)
        openSingletonTab(.archive)
        pushNavigation(.archive(category: targetCategory, projectID: targetProject))
    }

    private func openSingletonTab(_ content: TabContent) {
        if let existing = tabs.first(where: { $0.content == content }) {
            selectedTabID = existing.id
        } else {
            let tab = OpenTab(content: content)
            tabs.append(tab)
            selectedTabID = tab.id
        }
    }

    // MARK: 확인 팝업

    /// 백업/복원 진행 상태 — 타임라인 UI가 버튼을 잠그고 스피너를 보여주는 데 쓴다.
    private(set) var isBackingUp = false
    private(set) var isRestoringBackup = false

    /// 모든 문서 탭/세션을 정리한다 (미저장분 플러시 포함) — 워크스페이스 교체·백업 복원 공용.
    func closeAllDocumentTabs() {
        flushAllSessions()
        sessions.removeAll()
        tabs.removeAll {
            if case .document = $0.content { return true }
            return false
        }
        if tabs.isEmpty {
            tabs = [OpenTab(content: .home)]
        }
        if !tabs.contains(where: { $0.id == selectedTabID }) {
            selectedTabID = tabs.first?.id
        }
    }

    /// 휴지통 이동 요청 — 확인 팝업을 거친다.
    func requestTrash(_ item: DocumentListItem) {
        pendingTrashItem = item
    }

    func confirmPendingTrash() {
        guard let item = pendingTrashItem else { return }
        pendingTrashItem = nil
        // 열려 있으면 탭부터 닫는다
        if let tab = tabs.first(where: { $0.content == .document(item.id) }) {
            closeTab(tab)
        }
        workspace.moveToTrash(item)
    }

    /// 영구 삭제 요청 — 확인 팝업을 거친다 (단건/다건 공용).
    func requestPermanentDelete(_ items: [DocumentListItem]) {
        guard !items.isEmpty else { return }
        pendingPermanentDeleteItems = items
    }

    func confirmPendingPermanentDelete() {
        guard !pendingPermanentDeleteItems.isEmpty else { return }
        let items = pendingPermanentDeleteItems
        pendingPermanentDeleteItems = []
        workspace.deletePermanently(items)
    }

    func requestDeleteProject(_ project: ProjectFolder) {
        pendingDeleteProject = project
    }

    func confirmPendingDeleteProject() {
        guard let project = pendingDeleteProject else { return }
        pendingDeleteProject = nil
        // 프로젝트 소속 문서 탭/세션 정리
        let memberIDs = Set(workspace.visibleDocuments.filter { $0.envelope.projectID == project.id }.map(\.id))
        for tab in tabs {
            if case .document(let docID) = tab.content, memberIDs.contains(docID) {
                closeTab(tab)
            }
        }
        workspace.deleteProject(project)
        notify(symbol: "trash", message: "\(Localizer.shared.t(.eventProjectDeleted)): \(project.manifest.name)")
    }

    /// ⌘1~9 — n번째 탭 선택.
    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectExistingTab(tabs[index])
    }

    /// 탭 스트립에서 이미 열려 있는 탭을 직접 클릭해 전환할 때 — 뒤로/앞으로 히스토리에도 반영한다.
    /// 기존 open* 경로를 그대로 재사용해 아카이브 탭이면 마지막 카테고리/프로젝트 필터도 다시 적용한다.
    func selectExistingTab(_ tab: OpenTab) {
        switch tab.content {
        case .home: selectOrOpenHome()
        case .archive: openArchiveTab(category: lastKnownArchiveState.category, project: lastKnownArchiveState.projectID)
        case .aiChat: openAIChatTab()
        case .profile: openProfileTab()
        case .document(let id): openDocument(id: id)
        }
    }

    /// ⌘W — 현재 탭 닫기.
    func closeSelectedTab() {
        if let tab = selectedTab {
            closeTab(tab)
        }
    }

    /// ⌘S — 현재 문서 수동 저장.
    func saveSelectedDocument() {
        if let tab = selectedTab, let session = session(for: tab) {
            session.save(manual: true)
        }
    }

    /// 닫기 시도 중 저장에 실패한 탭 — 확인 다이얼로그(다시 시도/저장 없이 닫기/취소) 대기.
    var pendingSaveFailureTab: OpenTab?

    func closeTab(_ tab: OpenTab) {
        if case .document(let docID) = tab.content, let session = sessions[docID] {
            session.flush()
            // 저장이 실패한 채로 세션을 버리면 변경분이 조용히 사라진다 — 닫기를 보류하고 묻는다.
            if session.saveState == .error {
                pendingSaveFailureTab = tab
                return
            }
            sessions.removeValue(forKey: docID)
        }
        removeTabFromStrip(tab)
    }

    /// 저장 실패 확인 후 '저장하지 않고 닫기' — 플러시 없이 세션을 버린다.
    func forceCloseTab(_ tab: OpenTab) {
        if case .document(let docID) = tab.content {
            sessions.removeValue(forKey: docID)
        }
        removeTabFromStrip(tab)
    }

    private func removeTabFromStrip(_ tab: OpenTab) {
        tabs.removeAll { $0.id == tab.id }
        if tabs.isEmpty {
            tabs = [OpenTab(content: .home)]
        }
        if selectedTabID == tab.id {
            selectedTabID = tabs.last?.id
        }
    }

    /// 저장 실패 상태로 남아 있는 세션들의 제목 (종료 경고용).
    var failedSaveTitles: [String] {
        sessions.values
            .filter { $0.saveState == .error }
            .map { $0.title.isEmpty ? Localizer.shared.t(.untitled) : $0.title }
    }

    // MARK: 문서 열기/생성

    func openDocument(_ item: DocumentListItem) {
        openDocument(id: item.envelope.id, at: item.url)
    }

    func openDocument(id: UUID, at url: URL? = nil) {
        // 이미 열린 탭이면 선택만
        if let existing = tabs.first(where: { $0.content == .document(id) }) {
            selectedTabID = existing.id
            pushNavigation(.document(id))
            return
        }
        let l10n = Localizer.shared
        guard let resolvedURL = url ?? workspace.item(id: id)?.url else {
            presentOpenError(message: l10n.t(.errorDocumentMissing))
            return
        }
        let loaded: LoadedDocument
        do {
            loaded = try DocumentPackageIO.read(from: resolvedURL)
        } catch DocumentIOError.corruptedContent {
            handleCorruptedDocument(at: resolvedURL, id: id)
            return
        } catch DocumentIOError.notADocumentBundle, DocumentIOError.corruptedMetadata {
            presentOpenError(message: l10n.t(.errorOpenGeneric), detail: resolvedURL.lastPathComponent)
            return
        } catch {
            presentOpenError(message: l10n.t(.errorOpenGeneric), detail: error.localizedDescription)
            return
        }

        let session = DocumentSession(document: loaded, isPersisted: true)
        session.shouldSnapshotOnManualSave = { [weak self] in
            self?.settings.applied.snapshotOnManualSave ?? false
        }
        session.onWritingDelta = { [weak self] delta in
            self?.stats.recordWriting(delta: delta)
        }
        presentSession(session, id: id)
        workspace.touchRecent(id)
    }

    /// 손상된 문서 — 번들 안에 스냅샷이 남아 있으면 최신 스냅샷으로 복구를 제안한다.
    /// 복구를 수락하면 스냅샷 내용으로 세션을 열고 즉시 저장해 번들을 치유한다.
    private func handleCorruptedDocument(at url: URL, id: UUID) {
        let l10n = Localizer.shared
        let snapshots = SnapshotIO.list(in: url)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = l10n.t(.errorOpenTitle)
        alert.informativeText = "\(l10n.t(.errorCorruptedContent))\n\n\(url.lastPathComponent)"
        notify(symbol: "exclamationmark.triangle", message: "\(l10n.t(.errorOpenTitle)): \(url.lastPathComponent)")

        guard let latest = snapshots.first else {
            alert.runModal()
            return
        }
        alert.addButton(withTitle: l10n.t(.recoverFromSnapshot))
        alert.addButton(withTitle: l10n.t(.cancel))
        guard alert.runModal() == .alertFirstButtonReturn,
              let envelope = DocumentPackageIO.readEnvelope(from: url)
        else { return }

        let refs = DocumentPackageIO.readRefs(from: url) ?? ReferenceGraph()
        let document = LoadedDocument(envelope: envelope, content: latest.content, refs: refs, url: url)
        let session = DocumentSession(document: document, isPersisted: true)
        session.shouldSnapshotOnManualSave = { [weak self] in
            self?.settings.applied.snapshotOnManualSave ?? false
        }
        session.onWritingDelta = { [weak self] delta in
            self?.stats.recordWriting(delta: delta)
        }
        presentSession(session, id: id)
        session.healAfterRecovery()
        workspace.touchRecent(id)
        notify(symbol: "bandage", message: "\(l10n.t(.eventRecovered)): \(envelope.title)")
    }

    /// 문서 열기 실패를 사용자에게 알린다 — 예전처럼 조용히 무시하면 클릭이 "고장난 것처럼" 보인다.
    private func presentOpenError(message: String, detail: String? = nil) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = Localizer.shared.t(.errorOpenTitle)
        alert.informativeText = detail.map { "\(message)\n\n\($0)" } ?? message
        alert.runModal()
        notify(symbol: "exclamationmark.triangle", message: "\(Localizer.shared.t(.errorOpenTitle)): \(detail ?? message)")
    }

    /// 새 문서를 만들어 연다. 디스크에는 아직 쓰지 않고, 실제 편집이 발생해야 저장된다
    /// (버튼만 누르고 아무 변경 없이 닫으면 파일이 남지 않는다).
    func createAndOpen(kind: DocumentKind, pageRole: PageRole? = nil, in project: ProjectFolder? = nil) {
        let l10n = Localizer.shared
        let title: String = switch (kind, pageRole) {
        case (.scenario, _): l10n.t(.newScenario)
        case (.mindmap, _): l10n.t(.newMindMap)
        case (.page, .character): l10n.t(.newCharacter)
        case (.page, _): l10n.t(.newPage)
        }
        let document = workspace.createDocument(title: title, kind: kind, pageRole: pageRole, in: project)
        openUnsavedDocument(document)
    }

    /// 아직 디스크에 없는 새 문서를 세션으로 열고 탭을 만든다.
    @discardableResult
    private func openUnsavedDocument(_ document: LoadedDocument) -> UUID {
        let id = document.envelope.id
        if let existing = tabs.first(where: { $0.content == .document(id) }) {
            selectedTabID = existing.id
            pushNavigation(.document(id))
            return id
        }
        let session = DocumentSession(document: document, isPersisted: false)
        session.shouldSnapshotOnManualSave = { [weak self] in
            self?.settings.applied.snapshotOnManualSave ?? false
        }
        session.onWritingDelta = { [weak self] delta in
            self?.stats.recordWriting(delta: delta)
        }
        presentSession(session, id: id)
        return id
    }

    /// 세션을 등록하고 탭으로 연다 (열기/생성 공통 경로).
    private func presentSession(_ session: DocumentSession, id: UUID) {
        session.autosaveEnabled = settings.applied.autosave
        session.onSaved = { [weak self] in
            // 자동저장마다 즉시 풀스캔하면 watcher 발화와 겹쳐 이중 스캔이 된다 — 디바운스 경유
            self?.workspace.scanSoon()
            self?.workspace.touchRecent(id)
            self?.stats.recordActivity()
        }
        pushNavigation(.document(id))
        configureAI(for: session)
        configureEditorHooks(for: session)
        sessions[id] = session

        let tab = OpenTab(content: .document(id))
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func session(for tab: OpenTab) -> DocumentSession? {
        if case .document(let docID) = tab.content {
            return sessions[docID]
        }
        return nil
    }

    func flushAllSessions() {
        for session in sessions.values {
            session.flush()
        }
    }

    // MARK: 종료 처리

    func handleTermination() {
        stats.flush()
        flushAllSessions()
        if settings.applied.backupOnQuit {
            _ = try? backupManager.snapshot()
        }
    }

    // MARK: AI 조립

    /// 현재 설정된 AI 제공자 (채팅·자동작성 공용).
    func currentProvider() -> any AIProvider {
        makeProvider()
    }

    private func makeProvider() -> any AIProvider {
        switch settings.applied.aiProviderRaw {
        case "appleOnDevice":
            AppleOnDeviceProvider()
        case "anthropic":
            AnthropicProvider(apiKey: keychain.read("anthropic-api-key") ?? "")
        default:
            OfflineDraftProvider()
        }
    }

    private func configureAI(for session: DocumentSession) {
        guard case .scenario(let store) = session.editor else { return }
        let projectID = session.document.envelope.projectID
        store.autoWriter = { [weak self] content in
            guard let self else { return [] }
            let scope = settings.applied.aiContextScope
            let projectName: String? = scope == .document
                ? nil
                : workspace.project(id: projectID)?.manifest.name
            let context = AIScenarioContext(
                projectName: projectName,
                castNames: content.cast.map(\.name),
                castNotes: voiceNotes(for: content.cast),
                recentBlocks: content.blocks.suffix(40).map { block in
                    (
                        speaker: block.speakerIDs.first.flatMap { id in
                            content.cast.first { $0.id == id }?.name
                        },
                        text: block.text,
                        isInstruction: block.kind == .instruction
                    )
                }
            )
            let writer = ScenarioAutoWriter(provider: makeProvider(), maxBlocks: 10)
            return try await writer.draft(context: context)
        }
    }

    /// 에디터별 워크스페이스 연동 훅 주입.
    private func configureEditorHooks(for session: DocumentSession) {
        switch session.editor {
        case .mindmap(let store):
            store.documentCatalog = { [weak self] in
                guard let self else { return [] }
                return workspace.visibleDocuments
                    .filter { $0.envelope.kind == .page }
                    .map { (id: $0.envelope.id, title: $0.envelope.title) }
            }
        case .scenario(let store):
            // 같은 프로젝트의 캐릭터 페이지(단독 문서면 단독 캐릭터 페이지)를 캐스트로 가져올 수 있게
            let projectID = session.document.envelope.projectID
            store.characterCatalog = { [weak self] in
                guard let self else { return [] }
                return workspace.visibleDocuments
                    .filter {
                        $0.envelope.isCharacterPage && $0.envelope.projectID == projectID
                    }
                    .compactMap { item in
                        guard let loaded = try? DocumentPackageIO.read(from: item.url),
                              case .page(let content) = loaded.content
                        else { return nil }
                        let profile = content.profile ?? CharacterProfile()
                        return ImportableCharacter(
                            id: item.envelope.id,
                            name: item.envelope.title,
                            role: profile.role,
                            symbolName: profile.symbolName,
                            accentHex: profile.accentHex
                        )
                    }
            }
        case .page(let store):
            guard session.document.envelope.isCharacterPage else { break }
            let selfID = session.id
            let projectID = session.document.envelope.projectID
            store.onOpenDocument = { [weak self] id in self?.openDocument(id: id) }
            store.characterCatalog = { [weak self] in
                guard let self else { return [] }
                return workspace.visibleDocuments
                    .filter { $0.envelope.isCharacterPage && $0.id != selfID && $0.envelope.projectID == projectID }
                    .map { (id: $0.id, name: $0.envelope.title) }
            }
            store.appearanceStats = { [weak self] in
                self?.appearanceStats(forCharacterPage: selfID) ?? []
            }
        }
    }

    /// 캐릭터의 등장 기록 — 워크스페이스 시나리오를 스캔해 대사 수 집계 (보조 정보).
    private func appearanceStats(forCharacterPage pageID: UUID) -> [(title: String, lineCount: Int)] {
        var results: [(title: String, lineCount: Int)] = []
        let scenarios = workspace.visibleDocuments.filter { $0.envelope.kind == .scenario }
        for item in scenarios {
            guard let loaded = try? DocumentPackageIO.read(from: item.url),
                  case .scenario(let content) = loaded.content else { continue }
            let castIDs = Set(content.cast.filter { $0.characterPageID == pageID }.map(\.id))
            guard !castIDs.isEmpty else { continue }
            let allBlocks = content.blocks + content.branches.flatMap(\.blocks)
            let count = allBlocks.filter { block in
                block.kind == .line && !castIDs.isDisjoint(with: block.speakerIDs)
            }.count
            results.append((title: item.envelope.title, lineCount: count))
        }
        return results.sorted { $0.lineCount > $1.lineCount }
    }

    /// 캐스트의 보이스 카드를 AI 컨텍스트용 요약으로 변환.
    private func voiceNotes(for cast: [CastMember]) -> [String] {
        cast.compactMap { member -> String? in
            guard let pageID = member.characterPageID,
                  let item = workspace.item(id: pageID),
                  let loaded = try? DocumentPackageIO.read(from: item.url),
                  case .page(let content) = loaded.content,
                  let voice = content.profile?.voice
            else { return nil }
            var parts: [String] = []
            if !voice.tone.isEmpty { parts.append("말투: \(voice.tone)") }
            if !voice.taboo.isEmpty { parts.append("금기: \(voice.taboo)") }
            let samples = voice.samples.filter { !$0.isEmpty }
            if !samples.isEmpty { parts.append("예시: " + samples.prefix(3).joined(separator: " / ")) }
            guard !parts.isEmpty else { return nil }
            return "\(member.name) — " + parts.joined(separator: "; ")
        }
    }

    /// 시나리오 캐스트로부터 캐릭터 페이지(.scpa) 생성 — 같은 프로젝트의 world/에 만든다.
    /// 호출 직후 열어서 편집을 유도하며, 역시 실제 편집 전에는 디스크에 쓰지 않는다.
    func createCharacterPage(for member: CastMember, linkedTo session: DocumentSession) -> UUID? {
        let project = workspace.project(id: session.document.envelope.projectID)
        let document = workspace.createDocument(
            title: member.name.isEmpty ? Localizer.shared.t(.newCharacter) : member.name,
            kind: .page,
            pageRole: .character,
            in: project
        )
        let id = openUnsavedDocument(document)
        // 캐스트가 이 UUID를 characterPageID로 즉시 참조하므로, 편집 전에 닫혀도
        // 참조가 허공을 가리키지 않도록 지금 바로 디스크에 1회 저장해 둔다.
        sessions[id]?.persistInitial()
        return id
    }

    /// 문서 이름 변경 — 열려 있으면 세션 경유(자동저장), 아니면 디스크에서 직접.
    func renameDocument(_ item: DocumentListItem, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let session = sessions[item.id] {
            session.title = trimmed
        } else {
            workspace.renameDocument(item, to: trimmed)
        }
    }

    /// 실효 강조색 — 브랜드 테마(Sonnet/Pilgrimage)에서 '시스템' 선택 시 테마 고유 액센트가 기본.
    var resolvedAccent: Color {
        if settings.applied.accent == .system, settings.applied.interfaceTheme.isBranded {
            return settings.applied.interfaceTheme.accentColor
        }
        return settings.applied.accent.color
    }

    // MARK: 표시 헬퍼

    func breadcrumb(for session: DocumentSession) -> [String] {
        var parts: [String] = []
        // envelope의 projectID가 소속의 원본 — 디스크 스캔(item) 기반이면 아직 저장되지
        // 않은 새 문서가 프로젝트 안에 만들어졌어도 상위 프로젝트가 표시되지 않는다.
        if let projectName = workspace.project(id: session.document.envelope.projectID)?.manifest.name {
            parts.append(projectName)
        } else if let projectName = workspace.item(id: session.id)?.projectName {
            parts.append(projectName)
        }
        parts.append(session.title.isEmpty ? Localizer.shared.t(.untitled) : session.title)
        return parts
    }

    func tabTitle(for tab: OpenTab) -> String {
        let l10n = Localizer.shared
        switch tab.content {
        case .home: return l10n.t(.home)
        case .archive: return l10n.t(.archive)
        case .aiChat: return l10n.t(.aiAgent)
        case .profile: return l10n.t(.profilePage)
        case .document(let docID):
            let title = sessions[docID]?.title ?? workspace.item(id: docID)?.envelope.title ?? ""
            return title.isEmpty ? l10n.t(.untitled) : title
        }
    }

    func tabSymbol(for tab: OpenTab) -> String {
        switch tab.content {
        case .home: "house"
        case .archive: "archivebox"
        case .aiChat: "sparkles"
        case .profile: "person.crop.circle"
        case .document(let docID):
            sessions[docID]?.document.envelope.isCharacterPage == true
                ? "person.crop.circle"
                : (sessions[docID]?.document.envelope.kind.symbolName ?? "doc")
        }
    }
}

// MARK: - 백업 · 수신함 · 가져오기/내보내기
// 본체(AppState)가 SwiftLint type_body_length를 넘지 않도록 전송 계열 기능을 분리해 둔다.

extension AppState {
    /// 지금 백업 — 설정의 백업 타임라인에서도 호출된다. 워크스페이스 전체 복사라
    /// 메인 스레드에서 돌리면 대형 워크스페이스에서 UI가 얼어붙는다 — 백그라운드로 옮긴다.
    func backupNow(completion: (() -> Void)? = nil) {
        guard !isBackingUp, !isRestoringBackup else { return }
        flushAllSessions()
        isBackingUp = true
        let manager = backupManager
        Task { [weak self] in
            let success = await Task.detached(priority: .userInitiated) {
                (try? manager.snapshot()) != nil
            }.value
            guard let self else { return }
            isBackingUp = false
            notify(
                symbol: success ? "clock.arrow.circlepath" : "exclamationmark.triangle",
                message: Localizer.shared.t(success ? .eventBackedUp : .eventBackupFailed)
            )
            completion?()
        }
    }

    /// 타임라인 복원 — 열린 문서 세션이 복원 전 내용을 들고 있다가 자동저장으로
    /// 복원본을 도로 덮어쓰는 사고를 막기 위해, 반드시 문서 탭을 전부 닫고 시작한다.
    func restoreBackup(_ record: BackupRecord, completion: (() -> Void)? = nil) {
        guard !isBackingUp, !isRestoringBackup else { return }
        closeAllDocumentTabs()
        isRestoringBackup = true
        let manager = backupManager
        Task { [weak self] in
            let success = await Task.detached(priority: .userInitiated) {
                (try? manager.restore(record)) != nil
            }.value
            guard let self else { return }
            isRestoringBackup = false
            workspace.scan()
            notify(
                symbol: success ? "clock.arrow.circlepath" : "exclamationmark.triangle",
                message: Localizer.shared.t(success ? .eventRestored : .eventBackupFailed)
            )
            completion?()
        }
    }

    /// 프로젝트를 .scproj로 내보내기 (저장 위치 선택). 압축은 백그라운드에서.
    func exportProject(_ project: ProjectFolder) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = project.manifest.name + ".scproj"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let manager = backupManager
        Task { [weak self] in
            let success = await Task.detached(priority: .userInitiated) {
                (try? manager.exportProject(project, to: url)) != nil
            }.value
            let l10n = Localizer.shared
            self?.notify(
                symbol: success ? "square.and.arrow.up" : "exclamationmark.triangle",
                message: success
                    ? "\(l10n.t(.eventExported)): \(project.manifest.name).scproj"
                    : "\(l10n.t(.eventExportFailed)): \(project.manifest.name)"
            )
        }
    }

    // MARK: 수신함

    private var inboxURL: URL {
        workspace.rootURL.appendingPathComponent(".sonnetcreate/inbox.json")
    }

    func loadInbox() {
        guard let data = try? Data(contentsOf: inboxURL),
              let decoded = try? JSONDecoder().decode([InboxEvent].self, from: data)
        else {
            inbox = []
            return
        }
        inbox = decoded
    }

    /// 수신함에 이벤트 기록 (최근 50개 유지).
    func notify(symbol: String, message: String) {
        inbox.insert(InboxEvent(symbol: symbol, message: message), at: 0)
        if inbox.count > 50 { inbox = Array(inbox.prefix(50)) }
        if let data = try? JSONEncoder().encode(inbox) {
            try? data.write(to: inboxURL, options: .atomic)
        }
    }

    // MARK: 외부 가져오기

    /// 프로젝트(.scproj/폴더)나 문서 번들을 워크스페이스로 가져온다. 압축 해제/복사는 백그라운드에서.
    func importFromDisk() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = Localizer.shared.t(.importAny)
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        let root = workspace.rootURL
        let manager = backupManager
        Task { [weak self] in
            let results = await Task.detached(priority: .userInitiated) {
                urls.map { (name: $0.lastPathComponent, ok: Self.importItem(at: $0, workspaceRoot: root, backupManager: manager)) }
            }.value
            guard let self else { return }
            let l10n = Localizer.shared
            for result in results {
                notify(
                    symbol: result.ok ? "square.and.arrow.down" : "exclamationmark.triangle",
                    message: "\(l10n.t(result.ok ? .eventImported : .eventImportFailed)): \(result.name)"
                )
            }
            workspace.scan()
        }
    }

    private nonisolated static func importItem(at url: URL, workspaceRoot: URL, backupManager: BackupManager) -> Bool {
        let fm = FileManager.default
        // 1) .scproj 백업 패키지
        if url.pathExtension.lowercased() == "scproj" {
            return (try? backupManager.importProject(from: url)) != nil
        }
        // 2) 프로젝트 폴더 (project.json 보유) 또는 문서 번들 (.scen/.scno/.scpa)
        let isProject = fm.fileExists(atPath: url.appendingPathComponent("project.json").path)
        let isDocument = DocumentKind.from(fileExtension: url.pathExtension) != nil
        guard isProject || isDocument else { return false }
        // 이미 워크스페이스 안 (경로 별칭 /private/var vs /var 대비 표준화 후 비교)
        guard url.deletingLastPathComponent().standardizedFileURL.path != workspaceRoot.standardizedFileURL.path else { return false }

        var target = workspaceRoot.appendingPathComponent(url.lastPathComponent)
        var counter = 2
        while fm.fileExists(atPath: target.path) {
            target = workspaceRoot.appendingPathComponent("\(counter)-\(url.lastPathComponent)")
            counter += 1
        }
        return (try? fm.copyItem(at: url, to: target)) != nil
    }
}
