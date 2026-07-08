import AppCore
import Foundation
import SQLite3

/// 색인에 저장되는 문서 요약 한 건.
public struct DocumentIndexEntry: Sendable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var kind: String
    public var pageRole: String?
    public var path: String
    public var projectName: String?
    public var modifiedAt: Date
    public var isHidden: Bool
    public var isTrashed: Bool
    /// 본문 평문 (본문 검색용)
    public var body: String

    public init(
        id: UUID,
        title: String,
        kind: String,
        pageRole: String? = nil,
        path: String,
        projectName: String? = nil,
        modifiedAt: Date,
        isHidden: Bool = false,
        isTrashed: Bool = false,
        body: String = ""
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.pageRole = pageRole
        self.path = path
        self.projectName = projectName
        self.modifiedAt = modifiedAt
        self.isHidden = isHidden
        self.isTrashed = isTrashed
        self.body = body
    }
}

private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite 기반 UUID→위치 색인. 경로가 아닌 UUID로 참조를 해석해 이동/이름변경에도 링크가 유지된다.
public actor SearchIndex {
    // actor 메서드로만 접근이 직렬화되며, deinit의 close만 예외라 unsafe 표기가 실제로 안전하다.
    nonisolated(unsafe) private var db: OpaquePointer?

    public init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var handle: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &handle) == SQLITE_OK, let handle else {
            throw NSError(domain: "PersistenceKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "SQLite open 실패"])
        }
        db = handle
        let create = """
        CREATE TABLE IF NOT EXISTS documents (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            kind TEXT NOT NULL,
            page_role TEXT,
            path TEXT NOT NULL,
            project TEXT,
            modified REAL NOT NULL,
            hidden INTEGER NOT NULL DEFAULT 0,
            trashed INTEGER NOT NULL DEFAULT 0,
            body TEXT NOT NULL DEFAULT ''
        );
        """
        sqlite3_exec(handle, create, nil, nil, nil)
        // 구버전 테이블 마이그레이션 (body 컬럼 없으면 추가)
        sqlite3_exec(handle, "ALTER TABLE documents ADD COLUMN body TEXT NOT NULL DEFAULT '';", nil, nil, nil)
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    public func upsert(_ entry: DocumentIndexEntry) {
        let sql = """
        INSERT INTO documents (id, title, kind, page_role, path, project, modified, hidden, trashed, body)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title=excluded.title, kind=excluded.kind, page_role=excluded.page_role,
            path=excluded.path, project=excluded.project, modified=excluded.modified,
            hidden=excluded.hidden, trashed=excluded.trashed, body=excluded.body;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, entry.id.uuidString, -1, transientDestructor)
        sqlite3_bind_text(stmt, 2, entry.title, -1, transientDestructor)
        sqlite3_bind_text(stmt, 3, entry.kind, -1, transientDestructor)
        if let role = entry.pageRole {
            sqlite3_bind_text(stmt, 4, role, -1, transientDestructor)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_text(stmt, 5, entry.path, -1, transientDestructor)
        if let project = entry.projectName {
            sqlite3_bind_text(stmt, 6, project, -1, transientDestructor)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        sqlite3_bind_double(stmt, 7, entry.modifiedAt.timeIntervalSince1970)
        sqlite3_bind_int(stmt, 8, entry.isHidden ? 1 : 0)
        sqlite3_bind_int(stmt, 9, entry.isTrashed ? 1 : 0)
        sqlite3_bind_text(stmt, 10, entry.body, -1, transientDestructor)
        sqlite3_step(stmt)
    }

    public func remove(id: UUID) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM documents WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, transientDestructor)
        sqlite3_step(stmt)
    }

    public func removeAll() {
        sqlite3_exec(db, "DELETE FROM documents;", nil, nil, nil)
    }

    /// UUID → 현재 경로 해석.
    public func locate(id: UUID) -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT path FROM documents WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, transientDestructor)
        guard sqlite3_step(stmt) == SQLITE_ROW, let cString = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cString)
    }

    /// 제목/프로젝트명/본문 부분 일치 검색.
    public func search(_ query: String) -> [DocumentIndexEntry] {
        let sql = """
        SELECT id, title, kind, page_role, path, project, modified, hidden, trashed
        FROM documents
        WHERE (title LIKE ? OR project LIKE ? OR body LIKE ?) AND trashed = 0 AND hidden = 0
        ORDER BY modified DESC LIMIT 100;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        let pattern = "%\(query)%"
        sqlite3_bind_text(stmt, 1, pattern, -1, transientDestructor)
        sqlite3_bind_text(stmt, 2, pattern, -1, transientDestructor)
        sqlite3_bind_text(stmt, 3, pattern, -1, transientDestructor)
        return collectRows(stmt)
    }

    public func all() -> [DocumentIndexEntry] {
        let sql = """
        SELECT id, title, kind, page_role, path, project, modified, hidden, trashed
        FROM documents ORDER BY modified DESC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        return collectRows(stmt)
    }

    private func collectRows(_ stmt: OpaquePointer?) -> [DocumentIndexEntry] {
        var results: [DocumentIndexEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let idText = sqlite3_column_text(stmt, 0),
                let id = UUID(uuidString: String(cString: idText)),
                let titleText = sqlite3_column_text(stmt, 1),
                let kindText = sqlite3_column_text(stmt, 2),
                let pathText = sqlite3_column_text(stmt, 4)
            else { continue }
            let pageRole = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
            let project = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
            results.append(DocumentIndexEntry(
                id: id,
                title: String(cString: titleText),
                kind: String(cString: kindText),
                pageRole: pageRole,
                path: String(cString: pathText),
                projectName: project,
                modifiedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6)),
                isHidden: sqlite3_column_int(stmt, 7) == 1,
                isTrashed: sqlite3_column_int(stmt, 8) == 1
            ))
        }
        return results
    }
}

/// 디렉토리 변경 감시 (DispatchSource 기반).
public final class FolderWatcher: @unchecked Sendable {
    private var source: (any DispatchSourceFileSystemObject)?
    private var descriptor: CInt = -1

    public init() {}

    public func watch(_ url: URL, onChange: @escaping @Sendable () -> Void) {
        stop()
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .global(qos: .utility)
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { [descriptor] in close(descriptor) }
        source.resume()
        self.source = source
    }

    public func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
    }

    deinit { stop() }
}
