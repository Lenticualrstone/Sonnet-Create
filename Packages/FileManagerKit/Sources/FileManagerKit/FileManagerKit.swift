import AppCore
import DocumentKit
import Foundation
import Observation
import PersistenceKit

/// 아카이브/탐색기에 표시되는 문서 항목.
public struct DocumentListItem: Identifiable, Sendable, Equatable {
    public var envelope: DocumentEnvelope
    public var url: URL
    public var projectName: String?

    public var id: UUID { envelope.id }

    public init(envelope: DocumentEnvelope, url: URL, projectName: String? = nil) {
        self.envelope = envelope
        self.url = url
        self.projectName = projectName
    }
}

/// 앱이 문서로 인식하지 못하는 첨부 파일 (프로젝트 resources/ 폴더 · 워크스페이스 루트에 놓인 이미지·PDF·텍스트 등).
/// 보기 전용 — Finder/기본 앱으로 열람만 가능하고 가리기·휴지통 대상이 아니다.
public struct OtherFileItem: Identifiable, Sendable, Equatable {
    public var url: URL
    public var projectID: UUID?
    public var projectName: String?
    public var modifiedAt: Date
    public var fileSize: Int64

    public var id: String { url.path }
    public var filename: String { url.lastPathComponent }

    public init(url: URL, projectID: UUID?, projectName: String?, modifiedAt: Date, fileSize: Int64) {
        self.url = url
        self.projectID = projectID
        self.projectName = projectName
        self.modifiedAt = modifiedAt
        self.fileSize = fileSize
    }
}

/// 워크스페이스 전체(프로젝트/문서)의 스캔·생성·가리기·휴지통을 담당하는 스토어.
@MainActor
@Observable
public final class WorkspaceStore {
    public private(set) var rootURL: URL
    public private(set) var projects: [ProjectFolder] = []
    public private(set) var documents: [DocumentListItem] = []
    public private(set) var recentIDs: [UUID] = []
    /// 문서로 인식되지 않는 첨부 파일 (기타 카테고리, 보기 전용)
    public private(set) var otherFiles: [OtherFileItem] = []

    private var index: SearchIndex?
    private let watcher = FolderWatcher()
    private let logger = AppLogger(subsystem: "com.seolhwarim.sonnetcreate.workspace")

    private var trashDir: URL { rootURL.appendingPathComponent(".sonnetcreate/Trash", isDirectory: true) }
    private var trashMapURL: URL { rootURL.appendingPathComponent(".sonnetcreate/trash-origins.json") }

    /// '기타' 카테고리에 노출할 뷰어블 확장자 (이미지·PDF·마크다운·텍스트).
    private static let otherFileExtensions: Set<String> = [
        "pdf", "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "svg", "tiff", "bmp",
        "md", "markdown", "txt", "rtf",
    ]

    public init(rootURL: URL) {
        self.rootURL = rootURL
        bootstrap()
    }

    /// 저장 경로 변경 (설정에서 지정).
    public func setRoot(_ url: URL) {
        guard url != rootURL else { return }
        rootURL = url
        bootstrap()
    }

    private func bootstrap() {
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        index = try? SearchIndex(databaseURL: rootURL.appendingPathComponent(".sonnetcreate/index.db"))
        recentIDs = Self.loadRecents(for: rootURL)
        scan()
        watcher.watch(rootURL) { [weak self] in
            Task { @MainActor [weak self] in
                self?.scan()
            }
        }
    }

    // MARK: 스캔 + 색인

    public func scan() {
        let fm = FileManager.default
        var foundProjects: [ProjectFolder] = []
        var foundDocs: [DocumentListItem] = []
        var foundOther: [OtherFileItem] = []
        var bodies: [UUID: String] = [:]

        func collectDocument(at url: URL, projectName: String?) {
            guard DocumentKind.from(fileExtension: url.pathExtension) != nil,
                  let envelope = DocumentPackageIO.readEnvelope(from: url)
            else { return }
            foundDocs.append(DocumentListItem(envelope: envelope, url: url, projectName: projectName))
            // 본문 검색 색인용 평문 (실패해도 목록에는 지장 없음)
            if let loaded = try? DocumentPackageIO.read(from: url) {
                bodies[envelope.id] = loaded.content.plainText
            }
        }

        // 문서로 인식되지 않는 뷰어블 파일 (이미지·PDF·텍스트 등)을 '기타'로 수집한다.
        // 얕은 스캔만 수행 — 문서 번들 내부의 resources/(임베드 미디어)는 대상이 아니다.
        func collectOtherFiles(in directory: URL, projectID: UUID?, projectName: String?) {
            guard let items = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
            ) else { return }
            for item in items {
                let name = item.lastPathComponent
                if name.hasPrefix(".") { continue }
                guard Self.otherFileExtensions.contains(item.pathExtension.lowercased()) else { continue }
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey])
                guard values?.isDirectory != true else { continue }
                foundOther.append(OtherFileItem(
                    url: item,
                    projectID: projectID,
                    projectName: projectName,
                    modifiedAt: values?.contentModificationDate ?? Date(),
                    fileSize: Int64(values?.fileSize ?? 0)
                ))
            }
        }

        if let items = try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey]) {
            for item in items {
                let name = item.lastPathComponent
                if name.hasPrefix(".") { continue }
                if let project = ProjectIO.load(from: item) {
                    foundProjects.append(project)
                    for docURL in ProjectIO.documentURLs(in: project) {
                        collectDocument(at: docURL, projectName: project.manifest.name)
                    }
                    collectOtherFiles(in: project.resourcesURL, projectID: project.id, projectName: project.manifest.name)
                } else {
                    collectDocument(at: item, projectName: nil)
                }
            }
            collectOtherFiles(in: rootURL, projectID: nil, projectName: nil)
        }
        // 휴지통 항목도 목록에 포함 (isTrashed 상태로 구분)
        if let trashed = try? fm.contentsOfDirectory(at: trashDir, includingPropertiesForKeys: nil) {
            for item in trashed {
                collectDocument(at: item, projectName: nil)
            }
        }

        projects = foundProjects.sorted { $0.manifest.name < $1.manifest.name }
        documents = foundDocs.sorted { $0.envelope.modifiedAt > $1.envelope.modifiedAt }
        otherFiles = foundOther.sorted { $0.modifiedAt > $1.modifiedAt }

        // SQLite 색인 갱신 (UUID→경로 해석용)
        if let index {
            let entries = documents.map { item in
                DocumentIndexEntry(
                    id: item.envelope.id,
                    title: item.envelope.title,
                    kind: item.envelope.kind.rawValue,
                    pageRole: item.envelope.pageRole?.rawValue,
                    path: item.url.path,
                    projectName: item.projectName,
                    modifiedAt: item.envelope.modifiedAt,
                    isHidden: item.envelope.isHidden,
                    isTrashed: item.envelope.isTrashed,
                    body: bodies[item.envelope.id] ?? ""
                )
            }
            Task.detached(priority: .utility) {
                await index.removeAll()
                for entry in entries {
                    await index.upsert(entry)
                }
            }
        }
    }

    // MARK: 조회

    public var visibleDocuments: [DocumentListItem] {
        documents.filter { !$0.envelope.isHidden && !$0.envelope.isTrashed }
    }

    public var hiddenDocuments: [DocumentListItem] {
        documents.filter { $0.envelope.isHidden && !$0.envelope.isTrashed }
    }

    public var trashedDocuments: [DocumentListItem] {
        documents.filter { $0.envelope.isTrashed }
    }

    public var recentDocuments: [DocumentListItem] {
        recentIDs.compactMap { id in visibleDocuments.first { $0.id == id } }
    }

    public func item(id: UUID) -> DocumentListItem? {
        documents.first { $0.id == id }
    }

    public func project(id: UUID?) -> ProjectFolder? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    public func search(_ query: String) -> [DocumentListItem] {
        guard !query.isEmpty else { return [] }
        return visibleDocuments.filter {
            $0.envelope.title.localizedCaseInsensitiveContains(query)
                || ($0.projectName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    /// 제목 + 본문 딥서치 (SQLite 색인 활용). 제목 일치가 먼저 온다.
    public func deepSearch(_ query: String) async -> [DocumentListItem] {
        guard !query.isEmpty else { return [] }
        let titleHits = search(query)
        guard let index else { return titleHits }
        let entries = await index.search(query)
        var result = titleHits
        var seen = Set(titleHits.map(\.id))
        for entry in entries {
            guard !seen.contains(entry.id),
                  let item = visibleDocuments.first(where: { $0.id == entry.id })
            else { continue }
            result.append(item)
            seen.insert(entry.id)
        }
        return result
    }

    /// 이 문서를 참조하는 문서들 (백링크).
    public func backlinks(to targetID: UUID) -> [DocumentListItem] {
        visibleDocuments.filter { item in
            guard item.id != targetID,
                  let refs = DocumentPackageIO.readRefs(from: item.url)
            else { return false }
            return refs.outgoing.contains { $0.target == targetID }
        }
    }

    // MARK: 생성

    /// 새 문서를 메모리에만 구성한다 (디스크에 쓰지 않음).
    /// 실제 편집이 발생해야 `DocumentSession`이 저장하며, 그 전까지는 워크스페이스에도 나타나지 않는다.
    /// 빈 채로 버려진 새 문서가 더미 파일로 남는 것을 방지한다.
    public func createDocument(
        title: String,
        kind: DocumentKind,
        pageRole: PageRole? = nil,
        in project: ProjectFolder? = nil
    ) -> LoadedDocument {
        let directory: URL
        if let project {
            directory = pageRole == .character ? project.worldURL : project.documentsURL
        } else {
            directory = rootURL
        }
        return DocumentPackageIO.buildUnsaved(
            title: title, kind: kind, pageRole: pageRole,
            projectID: project?.id, in: directory
        )
    }

    @discardableResult
    public func createProject(name: String) throws -> ProjectFolder {
        let project = try ProjectIO.create(name: name, in: rootURL)
        scan()
        return project
    }

    // MARK: 이름 변경 / 복제

    public func renameDocument(_ item: DocumentListItem, to title: String) {
        guard var document = try? DocumentPackageIO.read(from: item.url) else { return }
        document.envelope.title = title
        document.envelope.modifiedAt = Date()
        try? DocumentPackageIO.write(document)
        scan()
    }

    @discardableResult
    public func duplicateDocument(_ item: DocumentListItem) -> LoadedDocument? {
        guard let source = try? DocumentPackageIO.read(from: item.url) else { return nil }
        let envelope = DocumentEnvelope(
            title: source.envelope.title + " 2",
            kind: source.envelope.kind,
            pageRole: source.envelope.pageRole,
            tags: source.envelope.tags,
            projectID: source.envelope.projectID
        )
        let directory = item.url.deletingLastPathComponent()
        let url = DocumentPackageIO.proposedURL(for: envelope, in: directory)
        let duplicate = LoadedDocument(envelope: envelope, content: source.content, refs: source.refs, url: url)
        guard (try? DocumentPackageIO.write(duplicate, to: url)) != nil else { return nil }
        // 첨부 리소스도 함께 복사
        let fm = FileManager.default
        let sourceResources = item.url.appendingPathComponent("resources")
        if let items = try? fm.contentsOfDirectory(at: sourceResources, includingPropertiesForKeys: nil) {
            let targetResources = url.appendingPathComponent("resources")
            for resource in items {
                try? fm.copyItem(at: resource, to: targetResources.appendingPathComponent(resource.lastPathComponent))
            }
        }
        scan()
        return duplicate
    }

    /// 프로젝트 폴더 전체(포함 문서 포함)를 Finder 휴지통으로 이동한다.
    /// 앱 내부 휴지통이 아닌 시스템 휴지통을 쓰는 이유: 폴더 단위 복원이 Finder에서 가장 안전하다.
    public func deleteProject(_ project: ProjectFolder) {
        try? FileManager.default.trashItem(at: project.url, resultingItemURL: nil)
        scan()
    }

    public func renameProject(_ project: ProjectFolder, to name: String) {
        var manifest = project.manifest
        manifest.name = name
        manifest.modifiedAt = Date()
        try? ProjectIO.save(manifest, at: project.url)
        scan()
    }

    // MARK: 최근 항목

    public func touchRecent(_ id: UUID) {
        recentIDs.removeAll { $0 == id }
        recentIDs.insert(id, at: 0)
        if recentIDs.count > 12 { recentIDs = Array(recentIDs.prefix(12)) }
        Self.saveRecents(recentIDs, for: rootURL)
    }

    private static func recentsKey(for root: URL) -> String {
        "recents-\(root.path.hashValue)"
    }

    private static func loadRecents(for root: URL) -> [UUID] {
        (UserDefaults.standard.stringArray(forKey: recentsKey(for: root)) ?? [])
            .compactMap(UUID.init(uuidString:))
    }

    private static func saveRecents(_ ids: [UUID], for root: URL) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: recentsKey(for: root))
    }

    // MARK: 가리기 (Finder 반영: isHidden 리소스 플래그)

    public func setHidden(_ item: DocumentListItem, hidden: Bool) {
        guard var document = try? DocumentPackageIO.read(from: item.url) else { return }
        document.envelope.isHidden = hidden
        try? DocumentPackageIO.write(document)

        var url = item.url
        var values = URLResourceValues()
        values.isHidden = hidden
        try? url.setResourceValues(values)

        scan()
    }

    // MARK: 휴지통 (Finder의 휴지통 개념처럼 별도 보관 + 원위치 기록)

    public func moveToTrash(_ item: DocumentListItem) {
        let fm = FileManager.default
        guard var document = try? DocumentPackageIO.read(from: item.url) else { return }
        document.envelope.isTrashed = true
        document.envelope.trashedAt = Date()
        try? DocumentPackageIO.write(document)

        var origins = loadTrashOrigins()
        var target = trashDir.appendingPathComponent(item.url.lastPathComponent)
        var counter = 2
        while fm.fileExists(atPath: target.path) {
            target = trashDir.appendingPathComponent("\(counter)-\(item.url.lastPathComponent)")
            counter += 1
        }
        origins[target.lastPathComponent] = item.url.deletingLastPathComponent().path
        try? fm.moveItem(at: item.url, to: target)
        saveTrashOrigins(origins)
        recentIDs.removeAll { $0 == item.id }
        Self.saveRecents(recentIDs, for: rootURL)
        scan()
    }

    /// 휴지통에서 원래 위치로 복원한다. 원래 폴더가 더 이상 존재하지 않으면(예: 프로젝트 삭제됨)
    /// 워크스페이스 최상위로 대신 복원하고 `true`를 반환한다 — 호출부에서 사용자에게 알릴 수 있도록.
    @discardableResult
    public func restoreFromTrash(_ item: DocumentListItem) -> Bool {
        let fm = FileManager.default
        var origins = loadTrashOrigins()
        let recordedPath = origins[item.url.lastPathComponent]
        let fellBackToRoot = !(recordedPath.map { fm.fileExists(atPath: $0) } ?? false)
        let originPath = (fellBackToRoot ? nil : recordedPath) ?? rootURL.path
        origins.removeValue(forKey: item.url.lastPathComponent)

        guard var document = try? DocumentPackageIO.read(from: item.url) else { return fellBackToRoot }
        document.envelope.isTrashed = false
        document.envelope.trashedAt = nil
        try? DocumentPackageIO.write(document)

        let originDir = URL(fileURLWithPath: originPath, isDirectory: true)
        try? fm.createDirectory(at: originDir, withIntermediateDirectories: true)
        var target = originDir.appendingPathComponent(item.url.lastPathComponent)
        var counter = 2
        while fm.fileExists(atPath: target.path) {
            target = originDir.appendingPathComponent("\(counter)-\(item.url.lastPathComponent)")
            counter += 1
        }
        try? fm.moveItem(at: item.url, to: target)
        saveTrashOrigins(origins)
        scan()
        return fellBackToRoot
    }

    public func deletePermanently(_ item: DocumentListItem) {
        deletePermanently([item])
    }

    /// 여러 항목을 한 번에 영구 삭제한다 (스캔은 1회만 수행).
    public func deletePermanently(_ items: [DocumentListItem]) {
        var origins = loadTrashOrigins()
        for item in items {
            try? FileManager.default.removeItem(at: item.url)
            origins.removeValue(forKey: item.url.lastPathComponent)
        }
        saveTrashOrigins(origins)
        scan()
    }

    /// 휴지통에 있는 모든 항목을 영구 삭제한다.
    public func emptyTrash() {
        deletePermanently(trashedDocuments)
    }

    /// 휴지통 항목의 원래 위치(표시용). 원래 폴더가 속한 프로젝트 이름을 우선 보여주고,
    /// 프로젝트에 속하지 않았으면 폴더 이름을, 최상위였거나 기록이 없으면 nil을 반환한다.
    public func trashOriginLabel(for item: DocumentListItem) -> String? {
        guard item.envelope.isTrashed else { return nil }
        guard let path = loadTrashOrigins()[item.url.lastPathComponent] else { return nil }
        let originURL = URL(fileURLWithPath: path)
        guard originURL != rootURL else { return nil }
        if let project = projects.first(where: { originURL.path.hasPrefix($0.url.path) }) {
            return project.manifest.name
        }
        return originURL.lastPathComponent
    }

    private func loadTrashOrigins() -> [String: String] {
        guard let data = try? Data(contentsOf: trashMapURL) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func saveTrashOrigins(_ map: [String: String]) {
        try? JSONEncoder().encode(map).write(to: trashMapURL, options: .atomic)
    }
}
