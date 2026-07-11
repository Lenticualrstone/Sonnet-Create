import Foundation

// MARK: - 문서 스냅샷

/// 이름 붙인 시점 기록 — 콘텐츠 전체를 문서 번들 내부 snapshots/에 보관한다.
/// (리소스 파일은 경로 참조라 복사하지 않는다 — 텍스트 중심 비교/복원 용도)
public struct DocumentSnapshot: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var content: DocumentContent
    /// 시스템이 찍은 스냅샷 (⌘S 자동/복원 전 상태) — 오래된 것부터 정리 대상.
    public var isAutomatic: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        content: DocumentContent,
        isAutomatic: Bool = false
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.content = content
        self.isAutomatic = isAutomatic
    }

    /// isAutomatic 도입 이전에 저장된 스냅샷도 읽히도록 decodeIfPresent.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        content = try c.decode(DocumentContent.self, forKey: .content)
        isAutomatic = try c.decodeIfPresent(Bool.self, forKey: .isAutomatic) ?? false
    }
}

/// snapshots/<uuid>.json 파일 단위 입출력.
public enum SnapshotIO {
    private static func directory(in bundle: URL) -> URL {
        bundle.appendingPathComponent("snapshots", isDirectory: true)
    }

    public static func list(in bundle: URL) -> [DocumentSnapshot] {
        let dir = directory(in: bundle)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }
        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(DocumentSnapshot.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public static func save(_ snapshot: DocumentSnapshot, in bundle: URL) throws {
        let dir = directory(in: bundle)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(
            to: dir.appendingPathComponent("\(snapshot.id.uuidString).json"),
            options: .atomic
        )
    }

    public static func delete(_ id: UUID, in bundle: URL) {
        try? FileManager.default.removeItem(
            at: directory(in: bundle).appendingPathComponent("\(id.uuidString).json")
        )
    }
}
