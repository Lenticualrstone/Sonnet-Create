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

    func send(using provider: any AIProvider) async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        input = ""
        messages.append(AIChatMessage(role: .user, text: text))
        isBusy = true
        defer { isBusy = false }
        do {
            let reply = try await provider.chat(history: messages)
            messages.append(AIChatMessage(role: .assistant, text: reply))
        } catch {
            messages.append(AIChatMessage(role: .assistant, text: "⚠️ \(error.localizedDescription)"))
        }
    }

    func clear() {
        messages = []
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
        self.id = UUID()
        self.date = Date()
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
    /// 윈도우가 전체화면 상태인지 — 헤더 레이아웃과 사이드바 픽셀 필드 배치가 이 값에 따라 갈린다
    var isFullscreen = false

    /// 휴지통 이동 확인 대기 항목 (확인 팝업)
    var pendingTrashItem: DocumentListItem?
    /// 프로젝트 삭제 확인 대기 (확인 팝업 → Finder 휴지통)
    var pendingDeleteProject: ProjectFolder?
    /// 아카이브 탭을 특정 카테고리로 열기 위한 요청 (소비형)
    var archiveCategoryRequest: ArchiveView.Category?

    /// 일별 저장 활동 (yyyy-MM-dd → 횟수) — 프로필 기여도 그래프용
    private(set) var activity: [String: Int] = [:]

    /// 수신함 이벤트 (가져오기/백업/복원 등)
    private(set) var inbox: [InboxEvent] = []

    // 열린 문서 세션
    private(set) var sessions: [UUID: DocumentSession] = [:]

    /// AI 에이전트 채팅 (탭·사이드패널 공유)
    let aiChat = AIChatStore()

    /// Touch Bar 지원 (베타)
    let touchBar = TouchBarController()

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
        loadActivity()
        loadInbox()
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
            loadActivity()
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
    }

    func openAIChatTab() {
        openSingletonTab(.aiChat)
    }

    func openProfileTab() {
        openSingletonTab(.profile)
    }

    /// 아카이브 탭 열기 — 카테고리 지정 시 해당 카테고리로 (가림/휴지통 바로가기).
    func openArchiveTab(category: ArchiveView.Category? = nil) {
        if let category {
            archiveCategoryRequest = category
        }
        openSingletonTab(.archive)
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

    /// 지금 백업 — 설정의 백업 타임라인에서도 호출된다.
    func backupNow() {
        flushAllSessions()
        if (try? backupManager.snapshot()) != nil {
            notify(symbol: "clock.arrow.circlepath", message: Localizer.shared.t(.eventBackedUp))
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
        selectedTabID = tabs[index].id
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

    func closeTab(_ tab: OpenTab) {
        if case .document(let docID) = tab.content {
            sessions[docID]?.flush()
            sessions.removeValue(forKey: docID)
        }
        tabs.removeAll { $0.id == tab.id }
        if tabs.isEmpty {
            tabs = [OpenTab(content: .home)]
        }
        if selectedTabID == tab.id {
            selectedTabID = tabs.last?.id
        }
    }

    // MARK: 문서 열기/생성

    func openDocument(_ item: DocumentListItem) {
        openDocument(id: item.envelope.id, at: item.url)
    }

    func openDocument(id: UUID, at url: URL? = nil) {
        // 이미 열린 탭이면 선택만
        if let existing = tabs.first(where: { $0.content == .document(id) }) {
            selectedTabID = existing.id
            return
        }
        let resolvedURL = url ?? workspace.item(id: id)?.url
        guard let resolvedURL, let loaded = try? DocumentPackageIO.read(from: resolvedURL) else { return }

        let session = DocumentSession(document: loaded, isPersisted: true)
        presentSession(session, id: id)
        workspace.touchRecent(id)
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
            return id
        }
        let session = DocumentSession(document: document, isPersisted: false)
        presentSession(session, id: id)
        return id
    }

    /// 세션을 등록하고 탭으로 연다 (열기/생성 공통 경로).
    private func presentSession(_ session: DocumentSession, id: UUID) {
        session.autosaveEnabled = settings.applied.autosave
        session.onSaved = { [weak self] in
            self?.workspace.scan()
            self?.workspace.touchRecent(id)
            self?.recordActivity()
        }
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
        flushAllSessions()
        if settings.applied.backupOnQuit {
            try? backupManager.snapshot()
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
        return openUnsavedDocument(document)
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

    /// 프로젝트를 .scproj로 내보내기 (저장 위치 선택).
    func exportProject(_ project: ProjectFolder) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = project.manifest.name + ".scproj"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if (try? backupManager.exportProject(project, to: url)) != nil {
            notify(symbol: "square.and.arrow.up", message: "\(Localizer.shared.t(.eventExported)): \(project.manifest.name).scproj")
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

    // MARK: 활동 로그 (기여도 그래프)

    private var activityURL: URL {
        workspace.rootURL.appendingPathComponent(".sonnetcreate/activity.json")
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    func loadActivity() {
        guard let data = try? Data(contentsOf: activityURL),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        else {
            activity = [:]
            return
        }
        activity = decoded
    }

    /// 문서 저장 1회 = 활동 1 (프로필의 GitHub식 기여도 그래프 데이터).
    private func recordActivity() {
        let key = Self.dayFormatter.string(from: Date())
        activity[key, default: 0] += 1
        if let data = try? JSONEncoder().encode(activity) {
            try? data.write(to: activityURL, options: .atomic)
        }
    }

    /// 특정 날짜의 활동 횟수.
    func activityCount(on date: Date) -> Int {
        activity[Self.dayFormatter.string(from: date)] ?? 0
    }

    // MARK: 외부 가져오기

    /// 프로젝트(.scproj/폴더)나 문서 번들을 워크스페이스로 가져온다.
    func importFromDisk() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = Localizer.shared.t(.importAny)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if importItem(at: url) {
                notify(symbol: "square.and.arrow.down", message: "\(Localizer.shared.t(.eventImported)): \(url.lastPathComponent)")
            }
        }
        workspace.scan()
    }

    @discardableResult
    private func importItem(at url: URL) -> Bool {
        let fm = FileManager.default
        // 1) .scproj 백업 패키지
        if url.pathExtension.lowercased() == "scproj" {
            return (try? backupManager.importProject(from: url)) != nil
        }
        // 2) 프로젝트 폴더 (project.json 보유) 또는 문서 번들 (.scen/.scno/.scpa)
        let isProject = fm.fileExists(atPath: url.appendingPathComponent("project.json").path)
        let isDocument = DocumentKind.from(fileExtension: url.pathExtension) != nil
        guard isProject || isDocument else { return false }
        guard url.deletingLastPathComponent() != workspace.rootURL else { return false } // 이미 워크스페이스 안

        var target = workspace.rootURL.appendingPathComponent(url.lastPathComponent)
        var counter = 2
        while fm.fileExists(atPath: target.path) {
            target = workspace.rootURL.appendingPathComponent("\(counter)-\(url.lastPathComponent)")
            counter += 1
        }
        return (try? fm.copyItem(at: url, to: target)) != nil
    }

    /// 실효 강조색 — Sonnet 테마에서 '시스템' 선택 시 적갈색이 기본.
    var resolvedAccent: Color {
        if settings.applied.accent == .system, settings.applied.interfaceTheme == .sonnet {
            return SonnetPalette.accent
        }
        return settings.applied.accent.color
    }

    // MARK: 표시 헬퍼

    func breadcrumb(for session: DocumentSession) -> [String] {
        var parts: [String] = []
        if let projectName = workspace.item(id: session.id)?.projectName {
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
