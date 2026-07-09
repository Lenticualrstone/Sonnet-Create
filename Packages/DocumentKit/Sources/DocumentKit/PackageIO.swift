import AppCore
import Foundation

/// 디스크에서 읽어들인 문서 한 건 (공통 껍데기 + 본문 + 참조 그래프).
public struct LoadedDocument: Sendable, Identifiable {
    public var envelope: DocumentEnvelope
    public var content: DocumentContent
    public var refs: ReferenceGraph
    public var url: URL

    public var id: UUID { envelope.id }

    public init(envelope: DocumentEnvelope, content: DocumentContent, refs: ReferenceGraph = ReferenceGraph(), url: URL) {
        self.envelope = envelope
        self.content = content
        self.refs = refs
        self.url = url
    }
}

public enum DocumentIOError: Error, LocalizedError {
    case notADocumentBundle(URL)
    case corruptedMetadata(URL)

    public var errorDescription: String? {
        switch self {
        case .notADocumentBundle(let url): "문서 번들이 아닙니다: \(url.lastPathComponent)"
        case .corruptedMetadata(let url): "메타데이터가 손상되었습니다: \(url.lastPathComponent)"
        }
    }
}

/// 문서 패키지(번들) 입출력.
/// 번들 구조: Document.<ext>/ ├─ metadata.json ├─ content.json ├─ refs.json └─ resources/
public enum DocumentPackageIO {
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

    /// 파일명에 쓸 수 없는 문자를 정리한다.
    public static func sanitizedFilename(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = title.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    /// 디렉토리 안에서 문서가 저장될 URL을 정한다 (제목 충돌 시 숫자 접미사).
    public static func proposedURL(for envelope: DocumentEnvelope, in directory: URL) -> URL {
        let base = sanitizedFilename(envelope.title)
        let ext = envelope.kind.fileExtension
        var candidate = directory.appendingPathComponent("\(base).\(ext)", isDirectory: true)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(counter).\(ext)", isDirectory: true)
            counter += 1
        }
        return candidate
    }

    /// 문서를 번들로 저장한다. resources/는 보존된다.
    @discardableResult
    public static func write(_ document: LoadedDocument, to url: URL? = nil) throws -> URL {
        let target = url ?? document.url
        let fm = FileManager.default
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try encoder.encode(document.envelope).write(to: target.appendingPathComponent("metadata.json"), options: .atomic)
        try encoder.encode(document.content).write(to: target.appendingPathComponent("content.json"), options: .atomic)
        try encoder.encode(document.refs).write(to: target.appendingPathComponent("refs.json"), options: .atomic)
        let resources = target.appendingPathComponent("resources", isDirectory: true)
        if !fm.fileExists(atPath: resources.path) {
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        }
        return target
    }

    /// 번들에서 문서를 읽는다.
    public static func read(from url: URL) throws -> LoadedDocument {
        let metaURL = url.appendingPathComponent("metadata.json")
        guard FileManager.default.fileExists(atPath: metaURL.path) else {
            throw DocumentIOError.notADocumentBundle(url)
        }
        var envelope: DocumentEnvelope
        do {
            envelope = try decoder.decode(DocumentEnvelope.self, from: Data(contentsOf: metaURL))
        } catch {
            throw DocumentIOError.corruptedMetadata(url)
        }
        let contentURL = url.appendingPathComponent("content.json")
        let content: DocumentContent
        if let rawData = try? Data(contentsOf: contentURL) {
            let data = DocumentContentMigrations.apply(to: rawData, from: envelope.formatVersion, kind: envelope.kind)
            content = (try? decoder.decode(DocumentContent.self, from: data))
                ?? .empty(for: envelope.kind, pageRole: envelope.pageRole)
        } else {
            content = .empty(for: envelope.kind, pageRole: envelope.pageRole)
        }
        if envelope.formatVersion < DocumentFormatVersion.current {
            envelope.formatVersion = DocumentFormatVersion.current
        }
        let refsURL = url.appendingPathComponent("refs.json")
        let refs = (try? decoder.decode(ReferenceGraph.self, from: Data(contentsOf: refsURL))) ?? ReferenceGraph()
        return LoadedDocument(envelope: envelope, content: content, refs: refs, url: url)
    }

    /// 메타데이터만 빠르게 읽는다 (스캔용).
    public static func readEnvelope(from url: URL) -> DocumentEnvelope? {
        let metaURL = url.appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metaURL) else { return nil }
        return try? decoder.decode(DocumentEnvelope.self, from: data)
    }

    /// 참조 그래프만 빠르게 읽는다 (백링크 스캔용).
    public static func readRefs(from url: URL) -> ReferenceGraph? {
        let refsURL = url.appendingPathComponent("refs.json")
        guard let data = try? Data(contentsOf: refsURL) else { return nil }
        return try? decoder.decode(ReferenceGraph.self, from: data)
    }

    /// 새 문서를 만들어 즉시 저장한다.
    public static func create(
        title: String,
        kind: DocumentKind,
        pageRole: PageRole? = nil,
        projectID: UUID? = nil,
        in directory: URL
    ) throws -> LoadedDocument {
        let document = buildUnsaved(title: title, kind: kind, pageRole: pageRole, projectID: projectID, in: directory)
        return try read(from: write(document))
    }

    /// 디스크에 쓰지 않고 새 문서를 메모리에만 구성한다.
    /// 실제 편집이 최소 1회 발생한 뒤에만 `write(_:)`로 저장해, 빈 더미 파일이 남지 않도록 한다.
    public static func buildUnsaved(
        title: String,
        kind: DocumentKind,
        pageRole: PageRole? = nil,
        projectID: UUID? = nil,
        in directory: URL
    ) -> LoadedDocument {
        let envelope = DocumentEnvelope(title: title, kind: kind, pageRole: pageRole, projectID: projectID)
        let content = DocumentContent.empty(for: kind, pageRole: pageRole)
        let url = proposedURL(for: envelope, in: directory)
        return LoadedDocument(envelope: envelope, content: content, url: url)
    }
}
