import Foundation

/// 프로젝트 매니페스트 (project.json).
/// 프로젝트 폴더 구조: <이름>/ ├─ project.json ├─ world/ (캐릭터 페이지) ├─ documents/ └─ resources/
public struct ProjectManifest: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var note: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var formatVersion: Int

    public init(
        id: UUID = UUID(),
        name: String,
        note: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        formatVersion: Int = 1
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.formatVersion = formatVersion
    }
}

/// 디스크의 프로젝트 폴더 참조.
public struct ProjectFolder: Identifiable, Sendable, Equatable {
    public var manifest: ProjectManifest
    public var url: URL

    public var id: UUID { manifest.id }

    public var worldURL: URL { url.appendingPathComponent("world", isDirectory: true) }
    public var documentsURL: URL { url.appendingPathComponent("documents", isDirectory: true) }
    public var resourcesURL: URL { url.appendingPathComponent("resources", isDirectory: true) }

    public init(manifest: ProjectManifest, url: URL) {
        self.manifest = manifest
        self.url = url
    }
}

public enum ProjectIO {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// 새 프로젝트 폴더 생성.
    public static func create(name: String, in directory: URL) throws -> ProjectFolder {
        let cleaned = DocumentPackageIO.sanitizedFilename(name)
        var url = directory.appendingPathComponent(cleaned, isDirectory: true)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(cleaned) \(counter)", isDirectory: true)
            counter += 1
        }
        let manifest = ProjectManifest(name: name)
        let folder = ProjectFolder(manifest: manifest, url: url)
        let fm = FileManager.default
        try fm.createDirectory(at: folder.worldURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: folder.documentsURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: folder.resourcesURL, withIntermediateDirectories: true)
        try save(manifest, at: url)
        return folder
    }

    public static func save(_ manifest: ProjectManifest, at url: URL) throws {
        try encoder.encode(manifest).write(to: url.appendingPathComponent("project.json"), options: .atomic)
    }

    /// 폴더가 프로젝트면 로드한다.
    public static func load(from url: URL) -> ProjectFolder? {
        let manifestURL = url.appendingPathComponent("project.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? decoder.decode(ProjectManifest.self, from: data)
        else { return nil }
        return ProjectFolder(manifest: manifest, url: url)
    }

    /// 프로젝트 안의 모든 문서 번들 URL (world/ + documents/).
    public static func documentURLs(in folder: ProjectFolder) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for dir in [folder.worldURL, folder.documentsURL] {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            result.append(contentsOf: items.filter { DocumentKind.from(fileExtension: $0.pathExtension) != nil })
        }
        return result
    }
}
